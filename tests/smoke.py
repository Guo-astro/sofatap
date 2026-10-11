#!/usr/bin/env python3
"""Real TLS/WebSocket integration checks; always starts a dry-run receiver.

Requires Python websockets. Does not print or retain tokens, pairing links or text.
"""
import asyncio
import hashlib
import json
import os
from pathlib import Path
import queue
import threading
import base64
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

import websockets
from websockets.exceptions import ConnectionClosed, InvalidStatus

ROOT = Path(__file__).resolve().parents[1]
RESULTS = []


def check(name, condition):
    if not condition:
        raise AssertionError(name)
    RESULTS.append(name)


def unused_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def http_status(url, headers=None, data=None, method=None):
    request = urllib.request.Request(url, headers=headers or {}, data=data, method=method)
    try:
        with urllib.request.urlopen(request, timeout=2) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def check_renewal_stdout(dotnet, assembly, temporary):
    """A migrated/renewed profile must not put human diagnostics before native state JSON."""
    fixture = Path(temporary) / "renewal-fixture"
    fixture.mkdir()
    (fixture / "Fixture.csproj").write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings></PropertyGroup></Project>')
    # Use the same .NET runtime as the receiver to create a deliberately old-style,
    # overlong certificate. This has no Python crypto dependency and is never served:
    # the receiver must replace it before listening. Windows storage remains DPAPI.
    (fixture / "Program.cs").write_text(r'''
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using var rsa = RSA.Create(2048);
var request = new CertificateRequest("CN=Sofatap Renewal Test", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
using var certificate = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddDays(730));
var secret = new { Token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_'),
    Pfx = Convert.ToBase64String(certificate.Export(X509ContentType.Pfx, "")) };
var clear = JsonSerializer.SerializeToUtf8Bytes(secret);
Directory.CreateDirectory(args[0]);
var path = Path.Combine(args[0], "pairing.dat");
File.WriteAllBytes(path, OperatingSystem.IsWindows() ? Protect.Bytes(clear) : clear);
if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
CryptographicOperations.ZeroMemory(clear);
static class Protect {
    [StructLayout(LayoutKind.Sequential)] struct Blob { public int Length; public IntPtr Data; }
    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)] static extern bool CryptProtectData(ref Blob input, string description, IntPtr entropy, IntPtr reserved, IntPtr prompt, int flags, out Blob output);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
    public static byte[] Bytes(byte[] clear) {
        var input = new Blob { Length = clear.Length, Data = Marshal.AllocHGlobal(clear.Length) };
        var output = new Blob();
        try {
            Marshal.Copy(clear, 0, input.Data, clear.Length);
            if (!CryptProtectData(ref input, null, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 1, out output)) throw new CryptographicException();
            var result = new byte[output.Length]; Marshal.Copy(output.Data, result, 0, result.Length); return result;
        } finally { Marshal.FreeHGlobal(input.Data); if (output.Data != IntPtr.Zero) LocalFree(output.Data); }
    }
}
''')
    build = subprocess.run([dotnet, "build", str(fixture / "Fixture.csproj"), "-c", "Release", "--nologo", "-v:q"],
                           capture_output=True, timeout=60)
    check("renewal fixture builds without third-party crypto", build.returncode == 0)
    profile = Path(temporary) / "renewal-profile"
    generated = subprocess.run([dotnet, str(fixture / "bin/Release/net10.0/Fixture.dll"), str(profile)], capture_output=True, timeout=15)
    check("renewal fixture creates a legacy certificate profile", generated.returncode == 0)
    previous = (profile / "pairing.dat").read_bytes()
    with tempfile.TemporaryFile(mode="w+") as diagnostics:
        process = subprocess.Popen([dotnet, str(assembly), "--native-ui", "--dry-run", "--data-dir", str(profile),
                                    "--control-port", str(unused_port())], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=diagnostics, text=True)
        frames = queue.Queue()
        def read_first():
            frames.put(process.stdout.readline())
        reader = threading.Thread(target=read_first, daemon=True)
        reader.start()
        try:
            first = frames.get(timeout=12)
            try: state = json.loads(first)
            except json.JSONDecodeError: state = {}
            check("renewal first stdout line is native state JSON", state.get("type") == "state")
            check("renewal produces fresh pairing identity", (profile / "pairing.dat").read_bytes() != previous)
            process.stdin.write('{"type":"quit"}\n'); process.stdin.flush()
            check("renewed native receiver quits normally", process.wait(timeout=5) == 0)
        finally:
            process.stdin.close()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
            reader.join(timeout=2)
            process.stdout.close()
        diagnostics.seek(0)
        text = diagnostics.read()
        check("renewal diagnostic stays on stderr", "certificate renewed" in text)
        check("renewal diagnostic contains no pairing secret", "sofatap://pair?" not in text and "fingerprint=" not in text)


async def exercise(state, control_port, send_native, states):
    check("native window state received", state.get("type") == "state" and state.get("dryRun") is True)
    check("native state clearly disables input", state.get("inputStatus") == "dry_run")
    check("pairing advertised only through private pipe", bool(state.get("pairings")))
    pairing = state["pairings"][0]
    fields = urllib.parse.parse_qs(urllib.parse.urlsplit(pairing["uri"]).query)
    token, fingerprint = fields["token"][0], fields["fingerprint"][0]
    advertised_host = fields["host"][0]
    check("native QR is a PNG", base64.b64decode(pairing["qrPng"]).startswith(b"\x89PNG\r\n\x1a\n"))
    check("native host and pairing endpoint agree", advertised_host == pairing["host"] and int(fields["port"][0]) == control_port)
    send_native("requestAccess") # dry-run must never request permission.
    refreshed = states.get(timeout=4)
    check("dry-run permission command remains dry-run", refreshed.get("inputStatus") == "dry_run")
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    url = f"wss://127.0.0.1:{control_port}/control"
    headers = {"Authorization": "Bearer " + token}
    for path in ("/", "/qr.svg", "/quit", "/request-access"):
        try:
            urllib.request.urlopen(f"https://127.0.0.1:{control_port}" + path, context=context, timeout=2)
            raise AssertionError("legacy web UI path must be absent")
        except urllib.error.HTTPError as error:
            check("no HTTP pairing or action endpoint " + path, error.code == 404)

    async def denied(name, additional_headers, code, origin=None):
        try:
            async with websockets.connect(url, ssl=context, additional_headers=additional_headers,
                                          origin=origin, proxy=None):
                raise AssertionError(name)
        except InvalidStatus as error:
            check(name, error.response.status_code == code)

    await denied("missing authentication denied", {}, 401)
    await denied("wrong authentication denied", {"Authorization": "Bearer " + "z" * 43}, 401)
    await denied("browser origin denied", headers, 403, origin="https://evil.example")
    await denied("null browser origin denied", headers, 403, origin="null")

    async with websockets.connect(url, ssl=context, additional_headers=headers, proxy=None) as ws:
        peer_der = ws.transport.get_extra_info("ssl_object").getpeercert(binary_form=True)
        check("advertised TLS leaf fingerprint matches", hashlib.sha256(peer_der).hexdigest() == fingerprint)
        trusted = ssl.create_default_context(cadata=ssl.DER_cert_to_PEM_cert(peer_der))
        with socket.create_connection((advertised_host, control_port), timeout=3) as connection:
            with trusted.wrap_socket(connection, server_hostname=advertised_host):
                check("advertised LAN IP passes TLS hostname validation", True)
        if sys.platform == "darwin":
            # OpenSSL alone does not enforce Apple's private-anchor lifetime policy.
            # Scope this check to the paired leaf; never install it as a system CA.
            with tempfile.TemporaryDirectory(prefix="sofatap-native-trust-") as temporary:
                leaf = Path(temporary) / "leaf.pem"
                leaf.write_text(ssl.DER_cert_to_PEM_cert(peer_der))
                native = subprocess.run(["security", "verify-cert", "-c", str(leaf), "-r", str(leaf),
                                         "-p", "ssl", "-n", advertised_host, "-N", "-L"],
                                        capture_output=True, timeout=5)
                check("Apple native SSL policy accepts paired certificate", native.returncode == 0)
        hello = json.loads(await ws.recv())
        check("dry run explicitly disables input", hello["type"] == "hello" and hello["version"] == 1 and hello["inputAvailable"] is False)
        expected_platform = "macos" if sys.platform == "darwin" else "windows" if sys.platform == "win32" else "linux"
        check("hello identifies platform and dry-run status", hello.get("platform") == expected_platform and hello.get("dryRun") is True and hello.get("inputStatus") == "dry_run")
        await denied("second controller denied", headers, 409)

        async def command(name, payload, expected=True):
            payload.setdefault("id", str(uuid.uuid4()))
            await ws.send(json.dumps(payload, ensure_ascii=True))
            response = json.loads(await ws.recv())
            check(name, response.get("type") == "ack" and response.get("id") == payload["id"] and response.get("ok") is expected)
            return payload, response

        await command("fractional pointer accepted", {"type": "move", "dx": 0.5, "dy": -0.5})
        await command("scroll accepted", {"type": "scroll", "dx": 120, "dy": -120})
        await command("click accepted", {"type": "click", "button": "right"})
        await command("drag down accepted", {"type": "button", "button": "left", "down": True})
        await command("drag release accepted", {"type": "button", "button": "left", "down": False})
        await command("shortcut accepted", {"type": "key", "key": "a", "modifiers": ["ctrl"]})
        message, first_ack = await command("Unicode text accepted by protocol", {"type": "text", "text": "你好 Windows 👋 café\n第二行"})
        await ws.send(json.dumps(message))
        check("duplicate action returns same ACK", json.loads(await ws.recv()) == first_ack)
        changed = {**message, "text": "different"}
        await command("conflicting reused action rejected", changed, False)
        await command("out of range movement rejected", {"type": "move", "dx": 501, "dy": 0}, False)
        await command("unknown field rejected", {"type": "click", "button": "left", "extra": True}, False)
        await command("unknown command rejected", {"type": "execute", "command": "no"}, False)
        await command("unknown key rejected", {"type": "key", "key": "f13", "modifiers": []}, False)
        await command("duplicate modifier rejected", {"type": "key", "key": "a", "modifiers": ["ctrl", "ctrl"]}, False)
        await command("oversized text rejected", {"type": "text", "text": "a" * 16001}, False)
        await command("NUL text rejected", {"type": "text", "text": "a\0b"}, False)
        await command("unpaired surrogate rejected", {"type": "text", "text": "\ud800"}, False)
        await ws.send('{"id":')
        response = json.loads(await ws.recv())
        check("malformed JSON rejected without losing session", response.get("ok") is False)
        _, heartbeat = await command("session recovers after invalid frame", {"type": "ping"})
        check("heartbeat reports current availability", heartbeat.get("inputAvailable") is False and heartbeat.get("dryRun") is True and heartbeat.get("inputStatus") == "dry_run")

    async with websockets.connect(url, ssl=context, additional_headers=headers, proxy=None) as ws:
        await ws.recv()
        await ws.send(b"not JSON text")
        try:
            await ws.recv()
            raise AssertionError("binary frame denied")
        except ConnectionClosed as error:
            check("binary frame denied", error.rcvd is not None and error.rcvd.code == 1003)

    async with websockets.connect(url, ssl=context, additional_headers=headers, proxy=None) as ws:
        await ws.recv()
        await ws.send("x" * 65537)
        try:
            await ws.recv()
            raise AssertionError("oversized frame denied")
        except ConnectionClosed as error:
            check("oversized frame denied", error.rcvd is not None and error.rcvd.code == 1009)

    async with websockets.connect(url, ssl=context, additional_headers=headers, proxy=None) as ws:
        await ws.recv()
        started = time.monotonic()
        try:
            await asyncio.wait_for(ws.recv(), timeout=24)
            raise AssertionError("idle controller expires")
        except ConnectionClosed as error:
            # .NET cancels an outstanding ReceiveAsync at the idle deadline,
            # which can abort the socket before a close frame can be emitted.
            # Both policy-close and EOF satisfy the bounded idle contract.
            elapsed = time.monotonic() - started
            check("idle controller expires", 19 <= elapsed <= 24 and
                  (error.rcvd is None or error.rcvd.code == 1008))

    async with websockets.connect(url, ssl=context, additional_headers=headers, proxy=None) as ws:
        await ws.recv()
        send_native("quit")
        try:
            await asyncio.wait_for(ws.recv(), timeout=3)
            raise AssertionError("quit must disconnect the controller")
        except ConnectionClosed:
            check("native window quit promptly disconnects active controller", True)


def main():
    control_port = unused_port()
    dotnet = os.environ.get("SOFATAP_DOTNET", str(ROOT / ".tools/dotnet/dotnet"))
    assembly = ROOT / "host/bin/Release/net10.0/SofaTap.dll"
    with tempfile.TemporaryDirectory(prefix="sofatap-smoke-") as temporary:
        log_path = Path(temporary) / "host.log"
        with log_path.open("w") as log:
            process = subprocess.Popen([dotnet, str(assembly), "--native-ui", "--dry-run", "--data-dir", str(Path(temporary) / "profile"),
                                        "--control-port", str(control_port)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True)
            states = queue.Queue()
            def pump():
                for line in process.stdout:
                    try: states.put(json.loads(line))
                    except json.JSONDecodeError: states.put({"type": "invalid_stdout"})
            reader = threading.Thread(target=pump, daemon=True)
            reader.start()
            def send_native(command):
                process.stdin.write(json.dumps({"type": command}) + "\n")
                process.stdin.flush()
            try:
                state = states.get(timeout=10)
                asyncio.run(exercise(state, control_port, send_native, states))
                check("native quit actually stops receiver", process.wait(timeout=5) == 0)
            finally:
                process.stdin.close()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait()
                reader.join(timeout=2)
                process.stdout.close()
        check("host logs contain no pairing URL", "sofatap://pair?" not in log_path.read_text())
        # Lost UI means lost control. Inherited pipe EOF must stop the backend without a quit frame.
        with subprocess.Popen([dotnet, str(assembly), "--native-ui", "--dry-run", "--data-dir", str(Path(temporary) / "eof-profile"),
                               "--control-port", str(unused_port())], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, text=True) as detached:
            check("EOF test starts native bridge", json.loads(detached.stdout.readline())["type"] == "state")
            detached.stdin.close()
            check("window pipe EOF stops backend", detached.wait(timeout=5) == 0)
        check_renewal_stdout(dotnet, assembly, temporary)
    report = {"suite": "TLS and WebSocket integration", "mode": "dry-run, no OS input", "passed": RESULTS}
    (ROOT / "artifacts").mkdir(exist_ok=True)
    (ROOT / "artifacts/transport-tests.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"PASS {len(RESULTS)} TLS/WebSocket integration checks (dry-run; OS input unverified)")


if __name__ == "__main__":
    main()
