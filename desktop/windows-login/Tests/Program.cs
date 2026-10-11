using Sofatap.Login;
using System.Text;

var checks = 0;
void Check(bool value) { if (!value) throw new Exception($"check {checks + 1} failed"); checks++; }
void Denied(Action action, string code) { try { action(); throw new Exception("not rejected"); } catch (LoginDeniedException e) { Check(e.Message == code); } }
long now = 0;
var generation = Guid.NewGuid();
using var broker = new AttemptBroker("S-1-test", "device", () => now, 1);
Denied(() => broker.Create(2), "provider_unavailable");
broker.ProviderSeen(2, generation);
var c = broker.Create(2); var id = Guid.Parse(c.AttemptId);
Check(c.Nonce.Length == 43 && c.Nonce.All(ch => char.IsAsciiLetterOrDigit(ch) || ch is '-' or '_'));
Denied(() => broker.Create(2), "attempt_in_progress");
using var secret = new SecretBytes(Encoding.Unicode.GetBytes("test password"));
broker.Submit(id, c.Nonce, secret, 2);
Denied(() => broker.Submit(id, c.Nonce, secret, 2), "stale_challenge");
Check(broker.Take(3, generation) is null);
using (var delivery = broker.Take(2, generation)) Check(delivery is not null && delivery.Password.Bytes.SequenceEqual(secret.Bytes));
Check(broker.Take(2, generation) is null);
broker.ObserveUnlocked(2); Check(broker.Status(id).Status == "waiting_for_windows");
broker.Report(id, 2, Guid.NewGuid(), true); broker.ObserveUnlocked(2); Check(broker.Status(id).Status == "waiting_for_windows");
broker.Report(id, 2, generation, true); broker.ObserveUnlocked(2); Check(broker.Status(id).Status == "unlocked");
now = 70; broker.ProviderSeen(2, generation); c = broker.Create(2); id = Guid.Parse(c.AttemptId);
now += 30; Check(broker.Status(id).Status == "expired");
broker.ProviderSeen(2, generation); c = broker.Create(2); id = Guid.Parse(c.AttemptId);
Denied(() => broker.Submit(id, "wrong", secret, 2), "invalid_submission"); Check(broker.Status(id).Status == "rejected");
broker.ProviderSeen(2, generation); c = broker.Create(2); id = Guid.Parse(c.AttemptId); broker.Submit(id, c.Nonce, secret, 2);
broker.ProviderSeen(2, Guid.NewGuid()); Check(broker.Status(id).Status == "unavailable");
now = 400; broker.ProviderSeen(2, generation); c = broker.Create(2); id = Guid.Parse(c.AttemptId); broker.Submit(id, c.Nonce, secret, 2);
using (var delivery = broker.Take(2, generation)) Check(delivery is not null);
Check(broker.Cancel(id).Status == "unknown");
now = 500; broker.ProviderSeen(2, generation); c = broker.Create(2); id = Guid.Parse(c.AttemptId); Check(broker.Cancel(id).Status == "cancelled");
for (var i = 0; i < 5; i++) { c = broker.Create(2); broker.Cancel(Guid.Parse(c.AttemptId)); }
Denied(() => broker.Create(2), "rate_limited");
// Session/provider boundaries, one-use concurrency and credential rate limits use isolated brokers.
now = 0;
using (var b = new AttemptBroker("sid", "device", () => now, 1))
{
    b.ProviderSeen(4, generation); var challenge = b.Create(4); var attempt = Guid.Parse(challenge.AttemptId);
    Denied(() => b.Submit(attempt, challenge.Nonce, secret, 5), "stale_challenge");
    Check(b.Status(attempt).AccountSid == "sid" && b.Status(attempt).DeviceId == "device" && b.Status(attempt).AttemptId == challenge.AttemptId);
    var successes = 0; var failures = 0;
    Parallel.For(0, 16, _ => { try { b.Submit(attempt, challenge.Nonce, secret, 4); Interlocked.Increment(ref successes); } catch (LoginDeniedException) { Interlocked.Increment(ref failures); } });
    Check(successes == 1 && failures == 15);
    using var delivery = b.Take(4, generation); Check(delivery is not null && delivery.RemainingMilliseconds is > 0 and <= 30000);
    var bytes = delivery!.Password.Bytes; delivery.Dispose(); Check(bytes.All(value => value == 0));
    b.Report(attempt, 5, generation, true); b.ObserveUnlocked(4); Check(b.Status(attempt).Status == "waiting_for_windows");
    b.Report(attempt, 4, generation, false); Check(b.Status(attempt).Status == "rejected");
}
using (var b = new AttemptBroker("sid", "device", () => now, 1))
{
    b.ProviderSeen(4, generation); var challenge = b.Create(4); var attempt = Guid.Parse(challenge.AttemptId);
    now = 3; Denied(() => b.Submit(attempt, challenge.Nonce, secret, 4), "stale_challenge");
    b.ProviderSeen(4, generation); b.Submit(attempt, challenge.Nonce, secret, 4); b.Invalidate();
    Check(b.Take(4, generation) is null && b.Status(attempt).Status == "unavailable");
    b.ProviderSeen(5, generation); Check(!b.ProviderReady(4) && b.ProviderReady(5));
}
now = 0;
using (var b = new AttemptBroker("sid", "device", () => now, 1))
{
    for (var index = 0; index < 3; index++) {
        now = index * 65; b.ProviderSeen(1, generation); var challenge = b.Create(1); var attempt = Guid.Parse(challenge.AttemptId);
        b.Submit(attempt, challenge.Nonce, secret, 1); b.Cancel(attempt);
    }
    now = 195; b.ProviderSeen(1, generation); var fourth = b.Create(1); var id4 = Guid.Parse(fourth.AttemptId);
    Denied(() => b.Submit(id4, fourth.Nonce, secret, 1), "rate_limited"); Check(b.Status(id4).Status == "rejected");
    now = 301; b.ProviderSeen(1, generation); var next = b.Create(1); b.Submit(Guid.Parse(next.AttemptId), next.Nonce, secret, 1);
    Check(b.Cancel(Guid.Parse(next.AttemptId)).Status == "cancelled");
}
now = 0;
using (var b = new AttemptBroker("sid", "device", () => now, 1))
{
    b.ProviderSeen(1, generation); var challenge = b.Create(1); var attempt = Guid.Parse(challenge.AttemptId); b.Submit(attempt, challenge.Nonce, secret, 1);
    using var delivered = b.Take(1, generation); now = 30; Check(b.Status(attempt).Status == "unknown");
    b.Report(attempt, 1, generation, true); b.ObserveUnlocked(1); Check(b.Status(attempt).Status == "unknown");
    using var restarted = new AttemptBroker("sid", "device", () => now, 1); restarted.ProviderSeen(1, generation);
    Denied(() => restarted.Submit(attempt, challenge.Nonce, secret, 1), "stale_challenge");
}
Console.WriteLine($"{checks} login broker checks passed; no desktop or real credentials used.");
