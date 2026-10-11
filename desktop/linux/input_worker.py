#!/usr/bin/env python3
"""Private, bounded NDJSON input worker. The receiver owns its lifetime."""

import json
import os
import signal
import sys

from input_common import InputError, MAXIMUM_LINE, STATUSES, parse_request


class UnavailableInput:
    def __init__(self, status="input_unavailable"):
        self.state = status

    def status(self):
        return self.state

    def request_access(self):
        return None

    def apply(self, _):
        raise InputError("input_unavailable")

    def release_all(self):
        return None

    def close(self):
        return None


def choose_backend(environment=None):
    environment = os.environ if environment is None else environment
    session = environment.get("XDG_SESSION_TYPE", "").lower()
    # Never let an XWayland DISPLAY bypass compositor authorization.
    if session == "wayland" or environment.get("WAYLAND_DISPLAY"):
        from wayland_input import PortalInput
        return PortalInput()
    if session not in {"", "x11"}:
        return UnavailableInput("unsupported_session")
    if not environment.get("DISPLAY"):
        return UnavailableInput("desktop_unavailable")
    from x11_input import X11Input
    return X11Input()


def handle_request(backend, request):
    error = None
    try:
        kind = request["type"]
        if kind == "requestAccess":
            backend.request_access()
        elif kind == "apply":
            backend.apply(request["action"])
        elif kind in {"releaseAll", "quit"}:
            backend.release_all()
    except InputError as failure:
        error = failure.code
    except Exception:
        error = "input_failed"
    try:
        status = backend.status()
        if status not in STATUSES:
            status = "input_unavailable"
            error = error or "input_failed"
    except Exception:
        status, error = "input_unavailable", error or "input_failed"
    result = {"id": request["id"], "ok": error is None, "status": status}
    if error:
        result["error"] = error
    return result


def main():
    # Native library diagnostics can include a rejected input character.
    # Keep the private data channel stdout-only and suppress raw native logs.
    with open(os.devnull, "wb") as sink:
        os.dup2(sink.fileno(), 2)
    try:
        from gi.repository import GLib
    except ImportError:
        # Report a useful state even if the shared system GI package is absent.
        backend = UnavailableInput("dependency_missing")
        try:
            while True:
                raw = sys.stdin.buffer.readline(MAXIMUM_LINE + 2)
                if not raw:
                    return 0
                if not raw.endswith(b"\n"):
                    return 2
                request = parse_request(raw[:-1])
                print(json.dumps(handle_request(backend, request), separators=(",", ":")), flush=True)
                if request["type"] == "quit":
                    return 0
        except Exception:
            return 2
    try:
        backend = choose_backend()
    except (ImportError, OSError):
        backend = UnavailableInput("dependency_missing")
    except Exception:
        backend = UnavailableInput()
    loop = GLib.MainLoop()
    buffer = bytearray()
    state = {"failed": False}
    descriptor = sys.stdin.fileno()
    os.set_blocking(descriptor, False)

    def stop(*_):
        loop.quit()
        return False

    def read_request(_descriptor, condition):
        try:
            if condition & (GLib.IO_ERR | GLib.IO_NVAL):
                raise OSError()
            chunk = os.read(descriptor, 4096)
            if not chunk:
                if buffer:
                    state["failed"] = True
                return stop()
            buffer.extend(chunk)
            while b"\n" in buffer:
                raw, _, tail = buffer.partition(b"\n")
                buffer[:] = tail
                request = parse_request(raw)
                result = handle_request(backend, request)
                sys.stdout.write(json.dumps(result, separators=(",", ":"), ensure_ascii=True) + "\n")
                sys.stdout.flush()
                if request["type"] == "quit":
                    return stop()
            if len(buffer) > MAXIMUM_LINE:
                raise InputError("invalid_request")
        except BlockingIOError:
            return True
        except Exception:
            state["failed"] = True
            return stop()
        return True

    GLib.io_add_watch(descriptor, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR | GLib.IO_NVAL, read_request)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, stop)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, stop)
    try:
        loop.run()
    finally:
        try:
            backend.close()
        except Exception:
            state["failed"] = True
    return 2 if state["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
