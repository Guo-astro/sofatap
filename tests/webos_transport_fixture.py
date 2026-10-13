#!/usr/bin/env python3
"""Loopback-only TLS/WebSocket fixture; credentials and certificates are disposable."""
import asyncio
import hashlib
import json
import logging
from pathlib import Path
import signal
import ssl
import sys

from websockets.asyncio.server import serve


async def main(directory: Path) -> None:
    logging.getLogger("websockets.server").setLevel(logging.CRITICAL)
    stats = {"requests": {}, "frames": {}}

    def save(name, value):
        temporary = directory / (name + ".tmp")
        temporary.write_text(json.dumps(value))
        temporary.replace(directory / name)

    def record(group, path, value=None):
        if group == "requests":
            stats[group][path] = stats[group].get(path, 0) + 1
        else:
            stats[group].setdefault(path, []).append(value)
        save("stats.json", stats)

    def context(name):
        result = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        result.minimum_version = ssl.TLSVersion.TLSv1_2
        result.load_cert_chain(directory / f"{name}.pem", directory / f"{name}.key")
        return result

    def fingerprint(name):
        der = ssl.PEM_cert_to_DER_cert((directory / f"{name}.pem").read_text())
        return hashlib.sha256(der).hexdigest()

    redirect_port = 0

    async def process_request(connection, request):
        record("requests", request.path)
        if request.path == "/redirect":
            response = connection.respond(302, "redirect refused by client test")
            response.headers["Location"] = f"https://127.0.0.1:{redirect_port}/redirect-target"
            return response
        return None

    async def handler(connection):
        path = connection.request.path
        try:
            if path == "/binary":
                await connection.send(b"unexpected binary response")
                return
            if path == "/oversized":
                await connection.send("x" * 65_537)
                return
            if path == "/server-close":
                await connection.close()
                return
            async for message in connection:
                record("frames", path, message)
                if path == "/late":
                    await asyncio.sleep(0.2)
                await connection.send(message)
        except Exception:
            # Deliberate client cancellation/failed trust is normal in this fixture.
            return

    save("stats.json", stats)
    options = dict(host="127.0.0.1", port=0, process_request=process_request,
                   ping_interval=None, close_timeout=0.2, max_size=65_536)
    async with serve(handler, ssl=context("control"), **options) as control, \
               serve(handler, ssl=context("pointer"), **options) as pointer, \
               serve(handler, ssl=context("control"), **options) as redirect_target:
        redirect_port = redirect_target.sockets[0].getsockname()[1]
        save("fixture.json", {
            "controlPort": control.sockets[0].getsockname()[1],
            "pointerPort": pointer.sockets[0].getsockname()[1],
            "redirectPort": redirect_port,
            "controlPin": fingerprint("control"),
            "pointerPin": fingerprint("pointer"),
        })
        stopped = asyncio.Event()
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, stopped.set)
        await stopped.wait()


if __name__ == "__main__":
    asyncio.run(main(Path(sys.argv[1])))
