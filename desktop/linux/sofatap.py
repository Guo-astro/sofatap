#!/usr/bin/env python3
"""Native GTK3 pairing preview. Linux input injection is not implemented."""

import argparse
import base64
import binascii
from dataclasses import dataclass
import json
import os
from pathlib import Path
import select
import struct
import subprocess
import sys
import threading
import time

MAXIMUM_LINE = 4 * 1024 * 1024


@dataclass(frozen=True)
class Pairing:
    host: str
    png: bytes


@dataclass(frozen=True)
class State:
    name: str
    connected: bool
    pairings: tuple[Pairing, ...]


def parse_state(line):
    if len(line) > MAXIMUM_LINE:
        raise ValueError("Receiver state is too large")
    value = json.loads(line)
    if not isinstance(value, dict) or value.get("type") != "state":
        raise ValueError("Unexpected receiver message")
    if value.get("dryRun") is not True:
        raise ValueError("Linux preview only accepts dry-run state")
    name, items = value.get("name"), value.get("pairings")
    if not isinstance(name, str) or not 1 <= len(name) <= 255 or not isinstance(items, list) or len(items) > 32:
        raise ValueError("Invalid receiver state")
    if not isinstance(value.get("connected"), bool):
        raise ValueError("Invalid connection state")
    pairings = []
    for item in items:
        if not isinstance(item, dict):
            raise ValueError("Invalid pairing")
        host, encoded = item.get("host"), item.get("qrPng")
        if not isinstance(host, str) or not 1 <= len(host) <= 255 or not isinstance(encoded, str) or len(encoded) > 1024 * 1024:
            raise ValueError("Invalid pairing fields")
        try:
            png = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError) as error:
            raise ValueError("Invalid QR encoding") from error
        if len(png) < 24 or png[:8] != b"\x89PNG\r\n\x1a\n" or png[12:16] != b"IHDR":
            raise ValueError("Invalid QR image")
        width, height = struct.unpack(">II", png[16:24])
        if not 1 <= width <= 2048 or not 1 <= height <= 2048:
            raise ValueError("Invalid QR dimensions")
        pairings.append(Pairing(host, png))
    # The pairing URI is never retained, displayed as text, or written to disk.
    return State(name, value["connected"], tuple(pairings))


class Backend:
    def __init__(self, executable, on_state, on_failure):
        self.executable = executable
        self.on_state, self.on_failure = on_state, on_failure
        self.process = None
        self.stopping = False
        self.writer_lock = threading.Lock()
        self.shutdown_lock = threading.Lock()

    def start(self):
        self.process = subprocess.Popen(
            [str(self.executable), "--native-ui", "--dry-run"],
            cwd=self.executable.parent, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        # Use bounded nonblocking writes, including when quit waits for another command.
        os.set_blocking(self.process.stdin.fileno(), False)
        threading.Thread(target=self.read_states, daemon=True).start()
        threading.Thread(target=self.drain_errors, daemon=True).start()

    def read_states(self):
        try:
            while True:
                line = self.process.stdout.readline(MAXIMUM_LINE + 1)
                if not line:
                    break
                if len(line) > MAXIMUM_LINE:
                    raise ValueError("Receiver state is too large")
                if not line.endswith(b"\n"):
                    raise ValueError("Receiver disconnected mid-frame")
                line = line.decode("utf-8", errors="strict")
                state = parse_state(line)
                if not self.stopping:
                    self.on_state(state)
        except (OSError, UnicodeError, ValueError):
            pass
        finally:
            if not self.stopping:
                self.on_failure()
                try:
                    self.stop()
                except (OSError, ValueError, subprocess.TimeoutExpired):
                    pass  # The visible window retains a Quit button for a retry.

    def drain_errors(self):
        # Never copy diagnostics or private snapshots into a log or UI message.
        try:
            while self.process.stderr.read(2048):
                pass
        except (OSError, UnicodeError, ValueError):
            pass

    def send(self, command, deadline=None):
        if command not in {"refresh", "requestAccess", "quit"}:
            raise ValueError("Unknown UI command")
        if deadline is None:
            deadline = time.monotonic() + 5
        if not self.writer_lock.acquire(timeout=max(0, deadline - time.monotonic())):
            raise TimeoutError("Receiver command timed out")
        try:
            if self.process is None or self.process.poll() is not None:
                raise OSError("Receiver is not running")
            data = memoryview((json.dumps({"type": command}) + "\n").encode("utf-8"))
            descriptor = self.process.stdin.fileno()
            while data:
                if self.stopping and command != "quit":
                    raise OSError("Receiver is stopping")
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("Receiver command timed out")
                try:
                    data = data[os.write(descriptor, data):]
                except BlockingIOError:
                    select.select([], [descriptor], [], remaining)
        finally:
            self.writer_lock.release()

    def stop(self):
        self.stopping = True
        deadline = time.monotonic() + 5
        if not self.shutdown_lock.acquire(timeout=5):
            raise TimeoutError("Receiver shutdown is already in progress")
        try:
            self.stop_owned_process(deadline)
        finally:
            self.shutdown_lock.release()

    def stop_owned_process(self, deadline):
        if self.process is None:
            return
        if self.process.poll() is None:
            try:
                self.send("quit", deadline)
            except (OSError, ValueError):
                pass
            try:
                self.process.wait(timeout=max(0, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=2)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", required=True, type=Path, help="self-contained Sofa Tap receiver executable")
    parser.add_argument("--dry-run", action="store_true", help="Linux is always in dry-run preview mode")
    args = parser.parse_args(argv)
    executable = args.backend.expanduser().resolve()
    if not executable.is_file() or not os.access(executable, os.X_OK):
        parser.error("--backend must point to an executable Sofa Tap receiver")
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import GdkPixbuf, GLib, Gtk
    except (ImportError, ValueError):
        print("Sofa Tap Linux preview requires Python 3, PyGObject and GTK 3. See desktop/linux/README.md.", file=sys.stderr)
        return 2
    if not Gtk.init_check()[0]:
        print("Sofa Tap requires a logged-in graphical Linux desktop.", file=sys.stderr)
        return 2

    class Window(Gtk.Window):
        def __init__(self):
            super().__init__(title="Sofa Tap · Linux 预览")
            self.set_default_size(450, 640)
            self.set_border_width(24)
            self.set_position(Gtk.WindowPosition.CENTER)
            self.pairings = ()
            self.rendered_png = None
            self.updating = False
            self.stopping = False
            layout = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            self.add(layout)
            title = Gtk.Label()
            title.set_markup('<span size="xx-large" weight="bold">手机，坐下来控制。</span>')
            title.set_xalign(0)
            layout.pack_start(title, False, False, 0)
            self.name = Gtk.Label(label="正在启动接收端…", xalign=0)
            self.status = Gtk.Label(label="Linux 演练预览 · 不会控制电脑", xalign=0)
            self.status.set_line_wrap(True)
            layout.pack_start(self.name, False, False, 0)
            layout.pack_start(self.status, False, False, 0)
            self.addresses = Gtk.ComboBoxText()
            self.addresses.connect("changed", self.render_qr)
            layout.pack_start(self.addresses, False, False, 0)
            self.image = Gtk.Image()
            self.image.set_size_request(300, 300)
            layout.pack_start(self.image, True, True, 0)
            help_text = Gtk.Label(label="iPhone 与电脑连接同一个家庭网络后扫码。\n这是 Linux 界面和连接预览，鼠标、键盘注入尚未实现。\n二维码包含控制凭据，请勿分享。", xalign=0)
            help_text.set_line_wrap(True)
            layout.pack_start(help_text, False, False, 0)
            buttons = Gtk.ButtonBox(orientation=Gtk.Orientation.HORIZONTAL)
            buttons.set_layout(Gtk.ButtonBoxStyle.END)
            self.refresh = Gtk.Button(label="刷新")
            self.refresh.set_sensitive(False)
            self.refresh.connect("clicked", self.refresh_state)
            self.quit_button = Gtk.Button(label="退出接收器")
            self.quit_button.connect("clicked", self.close_receiver)
            buttons.add(self.refresh)
            buttons.add(self.quit_button)
            layout.pack_start(buttons, False, False, 0)
            self.connect("delete-event", self.close_receiver)
            self.backend = Backend(executable,
                lambda state: GLib.idle_add(self.apply_state, state),
                lambda: GLib.idle_add(self.show_failure))
            self.show_all()
            try:
                self.backend.start()
            except OSError:
                self.show_failure()

        def apply_state(self, state):
            if self.stopping:
                return False
            self.name.set_text(state.name)
            self.status.set_text("iPhone 已连接 · Linux 演练，不会控制电脑" if state.connected else "Linux 演练预览 · 等待 iPhone 扫码，不会控制电脑")
            selected = self.addresses.get_active_text()
            self.updating = True
            self.pairings = state.pairings
            self.addresses.remove_all()
            for pairing in self.pairings:
                self.addresses.append_text(pairing.host)
            index = next((i for i, pairing in enumerate(self.pairings) if pairing.host == selected), 0)
            self.addresses.set_active(index if self.pairings else -1)
            self.updating = False
            self.refresh.set_sensitive(True)
            self.render_qr()
            return False

        def render_qr(self, *_):
            if self.updating:
                return
            index = self.addresses.get_active()
            if index < 0 or index >= len(self.pairings):
                self.image.clear()
                self.rendered_png = None
                return
            png = self.pairings[index].png
            if png == self.rendered_png:
                return
            try:
                loader = GdkPixbuf.PixbufLoader.new_with_type("png")
                loader.write(png)
                loader.close()
                pixbuf = loader.get_pixbuf()
                scale = min(360 / pixbuf.get_width(), 360 / pixbuf.get_height())
                pixbuf = pixbuf.scale_simple(max(1, int(pixbuf.get_width() * scale)), max(1, int(pixbuf.get_height() * scale)), GdkPixbuf.InterpType.NEAREST)
                self.image.set_from_pixbuf(pixbuf)
                self.rendered_png = png
            except GLib.Error:
                self.image.clear()
                self.status.set_text("二维码暂时不可用，请刷新")

        def refresh_state(self, *_):
            def send():
                try:
                    self.backend.send("refresh")
                except (OSError, ValueError):
                    GLib.idle_add(self.show_failure)
            threading.Thread(target=send, daemon=True).start()

        def show_failure(self):
            if not self.stopping:
                self.image.clear()
                self.rendered_png = None
                self.pairings = ()
                self.refresh.set_sensitive(False)
                self.status.set_text("接收端连接已中断。请检查后端版本，退出后重试。")
            return False

        def close_receiver(self, *_):
            if self.stopping:
                return True
            self.stopping = True
            self.image.clear()
            self.status.set_text("正在退出接收器…")
            self.refresh.set_sensitive(False)
            self.quit_button.set_sensitive(False)
            def stop():
                try:
                    self.backend.stop()
                except (OSError, ValueError, subprocess.TimeoutExpired):
                    GLib.idle_add(self.show_shutdown_failure)
                else:
                    GLib.idle_add(self.finish_close)
            threading.Thread(target=stop, daemon=True).start()
            return True

        def show_shutdown_failure(self):
            self.stopping = False
            self.quit_button.set_sensitive(True)
            self.status.set_text("接收进程尚未退出。请重试退出，或在系统进程管理器中关闭接收端。")
            return False

        def finish_close(self):
            self.destroy()
            Gtk.main_quit()
            return False

    window = Window()
    try:
        Gtk.main()
    finally:
        window.backend.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
