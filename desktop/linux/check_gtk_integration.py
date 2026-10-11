#!/usr/bin/env python3
"""Native GTK/host lifecycle checks on an authenticated private Xvfb display.

No phone, physical display, clipboard, mouse or keyboard input is used.
SOFATAP_TEST_BACKEND must name the packaged lib/SofaTapHost apphost.
"""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import signal
import select
import shutil
import socket
import subprocess
import sys
import tempfile
import time


def live_process(pid):
    try:
        # A reaped-parent zombie cannot inject input or keep a listener alive.
        return Path(f"/proc/{pid}/stat").read_text().split(") ", 1)[1].split()[0] != "Z"
    except FileNotFoundError:
        return False


def children(pid):
    try:
        values = Path(f"/proc/{pid}/task/{pid}/children").read_text().split()
        return [int(value) for value in values]
    except FileNotFoundError:
        return []


def port_open(port):
    with socket.socket() as connection:
        connection.settimeout(0.25)
        return connection.connect_ex(("127.0.0.1", port)) == 0


def child_check(backend, dry_run, profile, port):
    if sys.platform != "linux" or os.environ.get("SOFATAP_GTK_PRIVATE_DISPLAY") != os.environ.get("DISPLAY"):
        raise RuntimeError("GTK checks require the parent-created private Linux display")
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import GLib, Gtk
    frontend = backend.parent / "linux" / "sofatap.py"
    spec = importlib.util.spec_from_file_location("sofatap_packaged_frontend", frontend)
    if spec is None or spec.loader is None:
        raise RuntimeError("Packaged frontend could not be loaded")
    sofatap = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = sofatap
    spec.loader.exec_module(sofatap)
    if Path(sofatap.__file__).resolve() != frontend.resolve():
        raise RuntimeError("The test did not load the packaged frontend")

    wrapper = profile / "receiver-wrapper"
    wrapper.write_text("#!/usr/bin/python3\nimport os,sys\nos.execv(" + repr(str(backend)) + ", [" +
                       repr(str(backend)) + ", '--data-dir', " + repr(str(profile / "credentials")) +
                       ", '--port', " + repr(str(port)) + "] + sys.argv[1:])\n")
    wrapper.chmod(0o700)
    result = {"mode": "dry-run" if dry_run else "x11", "nativeGTK": False, "qrRendered": False,
              "nativeButtons": False, "statusVerified": False, "backendStopped": False,
              "workerStopped": False, "portClosed": False}
    errors = []
    tracked = set()
    started = time.monotonic()
    closing_at = None
    original_main = Gtk.main

    def poll():
        nonlocal closing_at
        windows = [window for window in Gtk.Window.list_toplevels() if window.get_title() == "Sofa Tap"]
        window = next((window for window in windows if hasattr(window, "backend")), None)
        if window is None:
            if time.monotonic() - started > 15:
                errors.append("Native receiver window did not appear")
                Gtk.main_quit()
                return False
            return True
        process = window.backend.process
        if process is not None:
            tracked.add(process.pid)
            tracked.update(children(process.pid))
        if closing_at is not None:
            if time.monotonic() - closing_at > 14:
                errors.append("Native window did not finish bounded shutdown")
                Gtk.main_quit()
                return False
            return True
        expected = "演练模式" if dry_run else "桌面已就绪"
        status = window.status.get_text()
        if expected in status and window.image.get_pixbuf() is not None:
            result["nativeGTK"] = isinstance(window, Gtk.Window) and isinstance(window.image, Gtk.Image)
            result["qrRendered"] = window.image.get_pixbuf().get_width() > 0
            result["nativeButtons"] = all(isinstance(button, Gtk.Button) and button.get_sensitive()
                                           for button in (window.refresh, window.quit_button))
            result["statusVerified"] = not window.access_button.get_visible() and not window.failed
            if not port_open(port):
                errors.append("Receiver control listener was not active")
            if not dry_run and (process is None or not children(process.pid)):
                errors.append("Real X11 mode did not start its owned input worker")
            closing_at = time.monotonic()
            if dry_run:
                window.quit_button.emit("clicked")
            else:
                window.close()  # Exercise the native window-manager close path too.
        elif window.failed or time.monotonic() - started > 15:
            errors.append("Native QR and expected desktop status did not become available")
            closing_at = time.monotonic()
            window.quit_button.emit("clicked")
        return True

    def checked_main():
        GLib.timeout_add(50, poll)
        original_main()

    Gtk.main = checked_main
    try:
        arguments = ["--backend", str(wrapper)] + (["--dry-run"] if dry_run else [])
        code = sofatap.main(arguments)
        if code != 0:
            errors.append("Native frontend returned an error")
    finally:
        Gtk.main = original_main
    deadline = time.monotonic() + 4
    while any(live_process(pid) for pid in tracked) and time.monotonic() < deadline:
        time.sleep(0.05)
    result["backendStopped"] = bool(tracked) and not any(live_process(pid) for pid in tracked)
    result["workerStopped"] = result["backendStopped"]
    result["portClosed"] = not port_open(port)
    if not all(value for key, value in result.items() if key != "mode"):
        errors.append("Native UI or owned-process lifecycle assertion failed")
    # No pairing snapshot, token, QR pixels or private profile content is printed.
    print(json.dumps(result, sort_keys=True), flush=True)
    if errors:
        print("; ".join(errors), file=sys.stderr)
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", type=Path, default=os.environ.get("SOFATAP_TEST_BACKEND"))
    parser.add_argument("--child", choices=("dry-run", "x11"), help=argparse.SUPPRESS)
    parser.add_argument("--profile", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--port", type=int, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if sys.platform != "linux":
        parser.error("Run this test on Linux; it never uses the Mac or a physical desktop")
    if not args.backend or not args.backend.is_file():
        parser.error("Set SOFATAP_TEST_BACKEND to the built Linux receiver executable")
    backend = args.backend.resolve()
    frontend = backend.parent / "linux" / "sofatap.py"
    launcher = backend.parent.parent / "sofatap"
    manifest_path = backend.parent.parent / "BUILD-MANIFEST.json"
    if not frontend.is_file() or not launcher.is_file() or not manifest_path.is_file():
        parser.error("SOFATAP_TEST_BACKEND must be lib/SofaTapHost inside a complete Linux package")
    manifest = json.loads(manifest_path.read_text())
    if hashlib.sha256(frontend.read_bytes()).hexdigest() != manifest.get("frontendSHA256"):
        parser.error("The packaged frontend does not match its build manifest")
    if args.child:
        return child_check(backend, args.child == "dry-run", args.profile, args.port)
    for executable in ("Xvfb", "xauth"):
        if not shutil.which(executable):
            parser.error(f"The private-display test requires {executable}")
    with tempfile.TemporaryDirectory(prefix="sofatap-gtk-integration-") as temporary:
        root = Path(temporary)
        authority = root / "Xauthority"
        authority.touch(mode=0o600)
        cookie = secrets.token_hex(16)
        # Xvfb loads this generated cookie; after -displayfd chooses its number,
        # the same authority is added at that address for the client lookup.
        subprocess.run(["xauth", "-f", str(authority), "add", ":0", ".", cookie], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        read_fd, write_fd = os.pipe()
        xvfb = subprocess.Popen(["Xvfb", "-displayfd", str(write_fd), "-screen", "0", "1280x900x24",
                                 "-nolisten", "tcp", "-noreset", "-auth", str(authority)],
                                pass_fds=(write_fd,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.close(write_fd)
        try:
            if not select.select([read_fd], [], [], 8)[0]:
                raise RuntimeError("Private Xvfb did not start")
            display_number = os.read(read_fd, 64).decode("ascii").strip()
            if not display_number.isdecimal() or xvfb.poll() is not None:
                raise RuntimeError("Private Xvfb returned no display")
            display = ":" + display_number
            subprocess.run(["xauth", "-f", str(authority), "add", display, ".", cookie], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            environment = dict(os.environ)
            environment.pop("WAYLAND_DISPLAY", None)
            environment.pop("DBUS_SESSION_BUS_ADDRESS", None)
            environment.update(DISPLAY=display, XAUTHORITY=str(authority), XDG_SESSION_TYPE="x11",
                               SOFATAP_GTK_PRIVATE_DISPLAY=display, LC_ALL="C.UTF-8", NO_AT_BRIDGE="1", GDK_BACKEND="x11")
            # Exercise the shipped shell launcher and its symlink/path handling.
            # --help exits before creating a GUI/backend, so no global profile or
            # default control port can be touched by this entrypoint smoke test.
            linked_launcher = root / "launcher link with spaces"
            linked_launcher.symlink_to(launcher)
            help_output = None
            for entrypoint in (launcher, linked_launcher):
                command = subprocess.run([str(entrypoint), "--help"], env=environment,
                                         text=True, capture_output=True, timeout=8)
                if command.returncode or "--dry-run" not in command.stdout or "--backend" not in command.stdout:
                    raise RuntimeError("The packaged launcher did not reach its frontend argument parser")
                if help_output is not None and command.stdout != help_output:
                    raise RuntimeError("The packaged launcher changed behavior through a symlink")
                help_output = command.stdout
            print("PASS: packaged launcher and symlink entrypoint (--help; no input or default profile)", flush=True)
            failed = False
            for mode in ("dry-run", "x11"):
                profile = root / mode
                profile.mkdir(mode=0o700)
                with socket.socket() as reservation:
                    reservation.bind(("127.0.0.1", 0))
                    port = reservation.getsockname()[1]
                child = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--child", mode,
                                          "--backend", str(backend), "--profile", str(profile), "--port", str(port)],
                                         env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                         start_new_session=True)
                try:
                    output, diagnostics = child.communicate(timeout=45)
                except subprocess.TimeoutExpired:
                    print(f"{mode}: native GTK lifecycle check exceeded its deadline", file=sys.stderr)
                    failed = True
                    continue
                finally:
                    # This fresh process group contains only our test frontend and
                    # its owned host/worker. Never leave a listener behind on failure.
                    for sig in (signal.SIGTERM, signal.SIGKILL):
                        try:
                            os.killpg(child.pid, sig)
                        except ProcessLookupError:
                            break
                    child.wait(timeout=3)
                # Child stdout contains only the booleans above; do not echo native diagnostics.
                for line in output.splitlines():
                    state = json.loads(line)
                    if not isinstance(state, dict) or set(state) != {"mode", "nativeGTK", "qrRendered", "nativeButtons",
                                                                   "statusVerified", "backendStopped", "workerStopped", "portClosed"}:
                        raise RuntimeError("Unexpected integration-test output")
                    print(json.dumps(state, sort_keys=True), flush=True)
                if child.returncode != 0 or not output.strip():
                    print(f"{mode}: native GTK lifecycle check failed (exit {child.returncode})", file=sys.stderr)
                    failed = True
            return int(failed)
        finally:
            os.close(read_fd)
            xvfb.terminate()
            try:
                xvfb.wait(timeout=5)
            except subprocess.TimeoutExpired:
                xvfb.kill()
                xvfb.wait(timeout=2)


if __name__ == "__main__":
    raise SystemExit(main())
