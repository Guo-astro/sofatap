#!/usr/bin/env python3
"""Real TLS/WebSocket integration checks; always starts a dry-run receiver.

Requires Python websockets. Does not print or retain tokens, pairing links or text.
"""
import asyncio
import hashlib
import html
import json
import os
from pathlib import Path
import re
import signal
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


async def exercise(dashboard_port, control_port):
    dashboard = f"http://127.0.0.1:{dashboard_port}/"
    status, body = http_status(dashboard)
    check("local dashboard reachable", status == 200)
    page = body.decode()
    links = re.findall(r'data-pairing-uri=[\"\x27]([^\"\x27]+)', page)
    check("pairing advertised locally", bool(links))
    fields = urllib.parse.parse_qs(urllib.parse.urlsplit(html.unescape(links[0])).query)
    token, fingerprint = fields["token"][0], fields["fingerprint"][0]
    advertised_host = fields["host"][0]
    qr_status, qr_body = http_status(dashboard + "qr.svg?host=" + urllib.parse.quote(advertised_host))
    check("local pairing QR rendered", qr_status == 200 and b"<svg" in qr_body)
    check("dashboard marked dry run", "演练模式 · 不会操作电脑" in html.unescape(page))
    fallback = re.findall(r'<textarea\b[^>]*\breadonly\b[^>]*>(.*?)</textarea>', page, re.S)
    check("manual pairing fallback matches QR", bool(fallback) and html.unescape(fallback[0]) == html.unescape(links[0]))
    check("dashboard DNS rebinding denied", http_status(dashboard, {"Host": f"evil.example:{dashboard_port}"})[0] == 403)
    check("dashboard foreign origin denied", http_status(dashboard, {"Origin": "https://evil.example"})[0] == 403)
    check("foreign QR host denied", http_status(dashboard + "qr.svg?host=evil.example")[0] == 400)

    nonce_match = re.search(r'name="nonce" value="([0-9a-f]{64})"', page)
    check("local action nonce present", nonce_match is not None)
    nonce_body = urllib.parse.urlencode({"nonce": nonce_match[1]}).encode()
    form_headers = {"Origin": dashboard.rstrip("/"), "Content-Type": "application/x-www-form-urlencoded"}
    check("GET cannot quit receiver", http_status(dashboard + "quit")[0] == 404)
    check("local action requires Origin", http_status(dashboard + "quit", {"Content-Type": form_headers["Content-Type"]}, nonce_body)[0] == 403)
    check("foreign page cannot quit receiver", http_status(dashboard + "quit", {**form_headers, "Origin": "https://evil.example"}, nonce_body)[0] == 403)
    check("local action requires correct nonce", http_status(dashboard + "quit", form_headers, b"nonce=wrong")[0] == 403)
    check("dry-run cannot request macOS permission", http_status(dashboard + "request-access", form_headers, nonce_body)[0] == 409)
    check("oversized local form rejected", http_status(dashboard + "quit", form_headers, nonce_body + b"&extra=" + b"x" * 4096)[0] in (400, 413))

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    url = f"wss://127.0.0.1:{control_port}/control"
    headers = {"Authorization": "Bearer " + token}

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
        check("valid local quit accepted", http_status(dashboard + "quit", form_headers, nonce_body)[0] == 200)
        try:
            await asyncio.wait_for(ws.recv(), timeout=3)
            raise AssertionError("quit must disconnect the controller")
        except ConnectionClosed:
            check("local quit promptly disconnects active controller", True)


def main():
    dashboard_port, control_port = unused_port(), unused_port()
    dotnet = os.environ.get("SOFATAP_DOTNET", str(ROOT / ".tools/dotnet/dotnet"))
    assembly = ROOT / "host/bin/Release/net10.0/SofaTap.dll"
    with tempfile.TemporaryDirectory(prefix="sofatap-smoke-") as temporary:
        log_path = Path(temporary) / "host.log"
        with log_path.open("wb") as log:
            process = subprocess.Popen([dotnet, str(assembly), "--dry-run", "--no-browser", "--data-dir", str(Path(temporary) / "profile"),
                                        "--dashboard-port", str(dashboard_port), "--control-port", str(control_port)], stdout=log, stderr=log)
            try:
                for _ in range(80):
                    if process.poll() is not None:
                        raise RuntimeError("Dry-run host failed to start; inspect locally without publishing credentials.")
                    try:
                        if http_status(f"http://127.0.0.1:{dashboard_port}/")[0] == 200:
                            break
                    except OSError:
                        pass
                    time.sleep(0.1)
                else:
                    raise RuntimeError("Dry-run host startup timeout")
                asyncio.run(exercise(dashboard_port, control_port))
                check("local quit actually stops receiver", process.wait(timeout=5) == 0)
            finally:
                if process.poll() is None:
                    process.send_signal(signal.SIGINT)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        check("host logs contain no pairing URL", "sofatap://pair?" not in log_path.read_text())
    report = {"suite": "TLS and WebSocket integration", "mode": "dry-run, no OS input", "passed": RESULTS}
    (ROOT / "artifacts").mkdir(exist_ok=True)
    (ROOT / "artifacts/transport-tests.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"PASS {len(RESULTS)} TLS/WebSocket integration checks (dry-run; OS input unverified)")


if __name__ == "__main__":
    main()
