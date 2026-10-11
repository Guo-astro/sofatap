using System.Diagnostics;
using System.Security.Cryptography;

namespace Sofatap.Login;

public sealed record Challenge(string AttemptId, string Nonce, DateTimeOffset ExpiresAt, string AccountSid, string DeviceId, int SessionId);
public sealed record AttemptStatus(string Status, string AccountSid, string DeviceId, string AttemptId);
public sealed class LoginDeniedException(string code) : Exception(code);
public sealed class SecretBytes(byte[] bytes) : IDisposable
{
    public byte[] Bytes { get; } = bytes;
    public void Dispose() => CryptographicOperations.ZeroMemory(Bytes);
}
public sealed record Delivery(Guid AttemptId, SecretBytes Password, int RemainingMilliseconds) : IDisposable { public void Dispose() => Password.Dispose(); }

// All transitions are serialized. Secrets never survive a session/provider change, expiry or consumption.
// Clocks are injectable so expiry tests do not sleep or operate a desktop.
public sealed class AttemptBroker(string accountSid, string deviceId, Func<long>? clock = null, long? frequency = null) : IDisposable
{
    private readonly object _gate = new();
    private readonly Func<long> _clock = clock ?? Stopwatch.GetTimestamp;
    private readonly long _frequency = frequency ?? Stopwatch.Frequency;
    private readonly Queue<long> _requests = new();
    private readonly Queue<long> _submissions = new();
    private readonly Dictionary<Guid, string> _results = [];
    private readonly Queue<Guid> _resultOrder = new();
    private Guid _generation;
    private int _session = -1;
    private long _providerSeen;
    private Pending? _pending;
    private sealed class Pending(Guid id, string nonce, int session, Guid generation, long deadline)
    {
        public Guid Id = id;
        public string Nonce = nonce;
        public int Session = session;
        public Guid Generation = generation;
        public long Deadline = deadline;
        public bool Consumed, Delivered, Authenticated;
        public SecretBytes? Password;
    }
    public bool ProviderReady(int session)
    {
        lock (_gate) return session == _session && _generation != Guid.Empty && Age(_providerSeen) < 3;
    }
    private double Age(long stamp) => (_clock() - stamp) / (double)_frequency;
    public void ProviderSeen(int session, Guid generation)
    {
        lock (_gate)
        {
            if (generation == Guid.Empty) throw new LoginDeniedException("invalid_provider");
            if (session != _session || generation != _generation) Finish("unavailable");
            _session = session; _generation = generation; _providerSeen = _clock();
        }
    }
    public void Invalidate()
    {
        lock (_gate) { Finish("unavailable"); _session = -1; _generation = Guid.Empty; }
    }
    public Challenge Create(int session)
    {
        lock (_gate)
        {
            Expire(); RateLimit(_requests, 6, 60);
            if (!ProviderReady(session)) throw new LoginDeniedException("provider_unavailable");
            if (_pending is not null) throw new LoginDeniedException("attempt_in_progress");
            var id = Guid.NewGuid(); var nonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
            _pending = new(id, nonce, session, _generation, _clock() + 30 * _frequency);
            return new(id.ToString("D"), nonce, DateTimeOffset.UtcNow.AddSeconds(30), accountSid, deviceId, session);
        }
    }
    public void Submit(Guid id, string nonce, SecretBytes password, int session)
    {
        lock (_gate)
        {
            Expire();
            var p = _pending;
            if (p is null || p.Id != id || p.Consumed || p.Session != session || p.Generation != _generation || !ProviderReady(session))
                throw new LoginDeniedException("stale_challenge");
            // Consume even a bad nonce or invalid password; no credential submission may be replayed.
            p.Consumed = true;
            try { RateLimit(_submissions, 3, 300); } catch { Finish("rejected"); throw; }
            var received = System.Text.Encoding.ASCII.GetBytes(nonce);
            var expected = System.Text.Encoding.ASCII.GetBytes(p.Nonce);
            if (!CryptographicOperations.FixedTimeEquals(received, expected) || password.Bytes.Length is < 2 or > 2048 || password.Bytes.Length % 2 != 0)
            { Finish("rejected"); throw new LoginDeniedException("invalid_submission"); }
            p.Nonce = "";
            p.Password = new(password.Bytes.ToArray());
        }
    }
    public Delivery? Take(int session, Guid generation)
    {
        lock (_gate)
        {
            Expire(); var p = _pending;
            if (p is null || p.Session != session || p.Generation != generation || p.Delivered || p.Password is null) return null;
            p.Delivered = true; var secret = p.Password; p.Password = null;
            return new(p.Id, secret, (int)Math.Clamp((p.Deadline - _clock()) * 1000 / _frequency, 1, 30_000));
        }
    }
    public void Report(Guid id, int session, Guid generation, bool success)
    {
        lock (_gate)
        {
            Expire(); var p = _pending;
            if (p is null || p.Id != id || p.Session != session || p.Generation != generation || !p.Delivered) return;
            if (!success) Finish("rejected"); else p.Authenticated = true;
        }
    }
    public void ObserveUnlocked(int session)
    {
        lock (_gate)
        {
            Expire();
            if (_pending is { Authenticated: true } p && p.Session == session) Finish("unlocked");
        }
    }
    public AttemptStatus Status(Guid id)
    {
        lock (_gate)
        {
            Expire();
            return new(_pending?.Id == id ? "waiting_for_windows" : _results.GetValueOrDefault(id, "unavailable"), accountSid, deviceId, id.ToString("D"));
        }
    }
    public AttemptStatus Cancel(Guid id)
    {
        lock (_gate)
        {
            if (_pending?.Id == id) Finish(_pending.Delivered ? "unknown" : "cancelled");
            return Status(id);
        }
    }
    private void RateLimit(Queue<long> timestamps, int count, int seconds)
    {
        while (timestamps.TryPeek(out var oldest) && Age(oldest) >= seconds) timestamps.Dequeue();
        if (timestamps.Count >= count) throw new LoginDeniedException("rate_limited");
        timestamps.Enqueue(_clock());
    }
    private void Expire() { if (_pending is { } p && _clock() >= p.Deadline) Finish(p.Delivered ? "unknown" : "expired"); }
    private void Finish(string status)
    {
        if (_pending is not { } p) return;
        p.Password?.Dispose(); p.Password = null; p.Nonce = "";
        _results[p.Id] = status; _resultOrder.Enqueue(p.Id);
        while (_resultOrder.Count > 64) _results.Remove(_resultOrder.Dequeue());
        _pending = null;
    }
    public void Dispose() { lock (_gate) Finish("unavailable"); }
}
