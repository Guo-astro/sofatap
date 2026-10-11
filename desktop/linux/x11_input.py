"""X11/XTest input. Unicode uses libxdo, never a shell or the clipboard.

Only a real X11 session may select this backend. XWayland is deliberately not
a fallback for a Wayland compositor's RemoteDesktop permission prompt.

Native API references:
https://www.x.org/releases/X11R7.5/doc/man/man3/XTestFakeKeyEvent.3.html
https://github.com/jordansissel/xdotool/blob/master/xdo.c
"""

import ctypes as C
import ctypes.util
import locale
import os
import time

from input_common import InputError, validate_action


KEYSYMS = {"enter": "Return", "tab": "Tab", "escape": "Escape", "backspace": "BackSpace",
           "delete": "Delete", "up": "Up", "down": "Down", "left": "Left", "right": "Right",
           "home": "Home", "end": "End", "pageup": "Prior", "pagedown": "Next", "space": "space",
           "a": "a", "c": "c", "v": "v", "x": "x", "z": "z", "ctrl": "Control_L",
           "alt": "Alt_L", "shift": "Shift_L", "win": "Super_L"}


def normalize_text(value):
    result = value.replace("\r\n", "\n").replace("\r", "\n")
    if len(result) > 2048:
        raise InputError("text_too_long")
    if any((ord(char) < 32 and char not in "\n\t") or 0x7F <= ord(char) < 0xA0 for char in result):
        raise InputError("unsupported_action")
    return result


class X11Native:
    """All Xlib access stays on the worker's single GLib thread."""

    def __init__(self):
        self.display = None
        self.xdo_context = None
        self.error_seen = False
        self.x = C.CDLL(ctypes.util.find_library("X11") or "libX11.so.6")
        self.xt = C.CDLL(ctypes.util.find_library("Xtst") or "libXtst.so.6")
        self.xdo = C.CDLL(ctypes.util.find_library("xdo") or "libxdo.so.3")
        self._bind()
        self.display = self.x.XOpenDisplay(None)
        if not self.display:
            raise InputError("input_unavailable")
        # Default Xlib aborts on protocol errors. Record an error, never report
        # success, and keep a chance to release only this receiver's inputs.
        self._error_callback = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_void_p)(self._on_error)
        self.previous_error_handler = self.x.XSetErrorHandler(self._error_callback)
        args = [C.c_int() for _ in range(4)]
        if not self.xt.XTestQueryExtension(self.display, *(C.byref(arg) for arg in args)):
            self.close()
            raise InputError("input_unavailable")
        # xdo consults the process locale on every text call. Force UTF-8 only
        # inside this dedicated worker, without changing the user's session.
        os.environ["LC_ALL"] = "C.UTF-8"
        os.environ["XDO_QUIET"] = "1"
        os.environ.pop("DEBUG", None)
        locale.setlocale(locale.LC_CTYPE, "C.UTF-8")
        self.xdo_context = self.xdo.xdo_new_with_opened_display(self.display, None, 0)
        if not self.xdo_context:
            self.close()
            raise InputError("input_unavailable")

    def _bind(self):
        def bind(lib, name, result, *arguments):
            function = getattr(lib, name)
            function.restype, function.argtypes = result, list(arguments)
        D, I, U, L = C.c_void_p, C.c_int, C.c_uint, C.c_ulong
        bind(self.x, "XOpenDisplay", D, C.c_char_p)
        bind(self.x, "XCloseDisplay", I, D)
        bind(self.x, "XSync", I, D, I)
        bind(self.x, "XFlush", I, D)
        bind(self.x, "XSetErrorHandler", D, D)
        bind(self.x, "XQueryKeymap", I, D, C.c_void_p)
        bind(self.x, "XDefaultRootWindow", L, D)
        bind(self.x, "XQueryPointer", I, D, L, C.POINTER(L), C.POINTER(L),
             C.POINTER(I), C.POINTER(I), C.POINTER(I), C.POINTER(I), C.POINTER(U))
        bind(self.x, "XStringToKeysym", L, C.c_char_p)
        bind(self.x, "XKeysymToKeycode", C.c_ubyte, D, L)
        bind(self.x, "XDisplayKeycodes", I, D, C.POINTER(I), C.POINTER(I))
        bind(self.x, "XGetKeyboardMapping", C.POINTER(L), D, C.c_ubyte, I, C.POINTER(I))
        bind(self.x, "XChangeKeyboardMapping", I, D, I, I, C.POINTER(L), I)
        bind(self.x, "XFree", I, D)
        bind(self.xt, "XTestQueryExtension", I, D, C.POINTER(I), C.POINTER(I), C.POINTER(I), C.POINTER(I))
        bind(self.xt, "XTestFakeRelativeMotionEvent", I, D, I, I, L)
        bind(self.xt, "XTestFakeButtonEvent", I, D, U, I, L)
        bind(self.xt, "XTestFakeKeyEvent", I, D, U, I, L)
        bind(self.xdo, "xdo_new_with_opened_display", D, D, C.c_char_p, I)
        bind(self.xdo, "xdo_free", None, D)
        bind(self.xdo, "xdo_enter_text_window", I, D, L, C.c_char_p, U)

    def _on_error(self, *_):
        self.error_seen = True
        return 0

    def sync(self):
        self.x.XSync(self.display, 0)
        if self.error_seen:
            self.error_seen = False
            raise InputError("input_partial")

    def any_keys_down(self):
        keys = (C.c_ubyte * 32)()
        self.x.XQueryKeymap(self.display, keys)
        self.sync()
        # Caps Lock changes literal text even when no physical key is held.
        return any(keys) or bool(self.pointer_mask() & 2)

    def pointer_mask(self):
        root, child, rx, ry, wx, wy, mask = C.c_ulong(), C.c_ulong(), C.c_int(), C.c_int(), C.c_int(), C.c_int(), C.c_uint()
        if not self.x.XQueryPointer(self.display, self.x.XDefaultRootWindow(self.display), C.byref(root), C.byref(child),
                                    C.byref(rx), C.byref(ry), C.byref(wx), C.byref(wy), C.byref(mask)):
            raise InputError("input_unavailable")
        self.sync()
        return mask.value

    def button_down(self, number):
        return bool(self.pointer_mask() & (1 << (7 + number)))

    def keycode(self, name):
        symbol = self.x.XStringToKeysym(KEYSYMS[name].encode("ascii"))
        code = self.x.XKeysymToKeycode(self.display, symbol)
        if not code:
            raise InputError("unsupported_action")
        return code

    def move(self, x, y):
        if not self.xt.XTestFakeRelativeMotionEvent(self.display, x, y, 0):
            raise InputError("input_failed")
        self.sync()

    def button(self, number, down):
        if not self.xt.XTestFakeButtonEvent(self.display, number, int(down), 0):
            raise InputError("input_failed")
        self.sync()

    def key(self, code, down):
        if not self.xt.XTestFakeKeyEvent(self.display, code, int(down), 0):
            raise InputError("input_failed")
        self.sync()

    def mapping(self):
        low, high, per_code = C.c_int(), C.c_int(), C.c_int()
        self.x.XDisplayKeycodes(self.display, C.byref(low), C.byref(high))
        count = high.value - low.value + 1
        data = self.x.XGetKeyboardMapping(self.display, low.value, count, C.byref(per_code))
        if not data or not 1 <= count <= 256 or not 1 <= per_code.value <= 64:
            if data:
                self.x.XFree(data)
            raise InputError("input_unavailable")
        try:
            return low.value, count, per_code.value, tuple(data[:count * per_code.value])
        finally:
            self.x.XFree(data)

    def text(self, value):
        value = normalize_text(value)
        if not value:
            return
        before = self.mapping()
        low, count, width, symbols = before
        unused = [low + index for index in range(count) if not any(symbols[index * width:(index + 1) * width])]
        bindings = {}
        schedule = []
        for char in value:
            if char in "\n\t":
                schedule.append((None, self.keycode("enter" if char == "\n" else "tab")))
                continue
            symbol = ord(char) if ord(char) <= 255 else 0x01000000 | ord(char)
            if self.x.XKeysymToKeycode(self.display, symbol):
                schedule.append((char, None))
            else:
                if symbol not in bindings:
                    if len(bindings) >= len(unused):
                        raise InputError("text_too_long")
                    bindings[symbol] = unused[len(bindings)]
                schedule.append((None, bindings[symbol]))
        # Reserve one second for X-server processing. Unicode uses fixed slots
        # for the whole batch, so it does not need per-character mapping delays.
        if len(schedule) * 1000 + (200_000 if bindings else 0) > 2_000_000:
            raise InputError("text_too_long")
        deadline = time.monotonic() + 3
        installed, expected, held = {}, {}, set()

        def row(mapping, code):
            offset = (code - mapping[0]) * mapping[2]
            return mapping[3][offset:offset + mapping[2]]

        try:
            # Rebinding one scratch key for every character races GTK's
            # MappingNotify cache. Assign every missing symbol its own unused
            # code, and keep all those mappings stable until the batch is over.
            for symbol, code in bindings.items():
                installed[code] = symbol
                values = (C.c_ulong * width)(*([symbol] * width))
                self.x.XChangeKeyboardMapping(self.display, code, width, values, 1)
            if installed:
                self.sync()
                applied = self.mapping()
                expected = {code: row(applied, code) for code in installed}
                time.sleep(.1)
            for char, code in schedule:
                if time.monotonic() >= deadline:
                    raise InputError("input_partial")
                if code is not None:
                    held.add(code)
                    self.key(code, True)
                    self.key(code, False)
                    held.discard(code)
                    time.sleep(.001)
                else:
                    if self.xdo.xdo_enter_text_window(self.xdo_context, 0, char.encode("utf-8"), 1000) != 0:
                        raise InputError("input_partial")
                    self.sync()
        finally:
            cleanup_failed = False
            for code in held:
                try: self.key(code, False)
                except Exception: cleanup_failed = True
            if installed:
                # Give the destination event loop time to consume the batch
                # while its mapping remains valid; success still means system
                # submission, not an acknowledgement from the destination app.
                time.sleep(.1)
                current = self.mapping()
                for code, symbol in installed.items():
                    observed = row(current, code)
                    owned = observed == expected.get(code) if code in expected else all(item in (0, symbol) for item in observed)
                    if not owned:
                        cleanup_failed = True
                        continue  # Do not erase a concurrent user's remapping.
                    original = row(before, code)
                    values = (C.c_ulong * width)(*original)
                    self.x.XChangeKeyboardMapping(self.display, code, width, values, 1)
                self.sync()
            if cleanup_failed:
                raise InputError("input_partial")

    def close(self):
        if self.xdo_context:
            self.xdo.xdo_free(self.xdo_context)
            self.xdo_context = None
        if self.display:
            self.x.XCloseDisplay(self.display)
            self.display = None
        if hasattr(self, "previous_error_handler"):
            self.x.XSetErrorHandler(self.previous_error_handler)


class X11Input:
    def __init__(self, native=None):
        self.native = native or X11Native()
        self.held_buttons = set()
        self.held_keys = set()
        self.fraction_x = self.fraction_y = self.scroll_x = self.scroll_y = 0.0
        self.closed = False

    def status(self):
        return "input_unavailable" if self.closed else "ready"

    def request_access(self):
        return None  # X11 access is controlled by the logged-in X session.

    def _button(self, number, down):
        if down:
            self.held_buttons.add(number)  # Track before call: partial failure may have sent it.
        self.native.button(number, down)
        if not down:
            self.held_buttons.discard(number)

    def _key(self, code, down):
        if down:
            self.held_keys.add(code)
        self.native.key(code, down)
        if not down:
            self.held_keys.discard(code)

    def apply(self, action):
        validate_action(action)
        if self.closed:
            raise InputError("input_unavailable")
        kind = action["type"]
        try:
            if kind == "move":
                self.fraction_x += action["dx"]
                self.fraction_y += action["dy"]
                x, y = int(self.fraction_x), int(self.fraction_y)
                if x or y:
                    self.native.move(x, y)
                    self.fraction_x -= x
                    self.fraction_y -= y
            elif kind == "scroll":
                self.scroll_x += action["dx"]
                self.scroll_y += action["dy"]
                x, y = int(self.scroll_x / 120), int(self.scroll_y / 120)
                for number, steps in ((7 if x > 0 else 6, abs(x)), (4 if y > 0 else 5, abs(y))):
                    for _ in range(steps):
                        self._button(number, True)
                        self._button(number, False)
                self.scroll_x -= x * 120
                self.scroll_y -= y * 120
            elif kind in {"click", "button"}:
                number = 1 if action["button"] == "left" else 3
                if number not in self.held_buttons and self.native.button_down(number):
                    raise InputError("input_busy")
                if kind == "click":
                    if number in self.held_buttons:
                        raise InputError("input_busy")
                    self._button(number, True)
                    self._button(number, False)
                elif action["down"] != (number in self.held_buttons):
                    self._button(number, action["down"])
            elif kind in {"key", "text"}:
                if self.held_buttons or self.native.any_keys_down():
                    raise InputError("input_busy")
                if kind == "text":
                    self.native.text(action["text"])
                else:
                    codes = [self.native.keycode(key) for key in action["modifiers"] + [action["key"]]]
                    for code in codes:
                        self._key(code, True)
                    for code in reversed(codes):
                        self._key(code, False)
        except Exception:
            self.release_all()
            raise

    def release_all(self):
        failed = False
        for code in tuple(self.held_keys):
            try:
                self._key(code, False)
            except Exception:
                failed = True
        for number in tuple(self.held_buttons):
            try:
                self._button(number, False)
            except Exception:
                failed = True
        self.fraction_x = self.fraction_y = self.scroll_x = self.scroll_y = 0.0
        if failed:
            raise InputError("input_partial")

    def close(self):
        try:
            self.release_all()
        finally:
            self.closed = True
            self.native.close()
