"""Wayland input through the user's RemoteDesktop portal, never privileged devices.

All methods run on the worker's GLib main thread. The state machine is transport
independent so its permission, revocation and partial-input paths can be checked
without opening a desktop session. No screen capture or clipboard is requested.

API references:
https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.RemoteDesktop.html
https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Request.html
https://xkbcommon.org/doc/current/group__keysyms.html
"""

import time
import uuid

from input_common import InputError, validate_action


PORTAL = "org.freedesktop.portal.Desktop"
INTERFACE = "org.freedesktop.portal.RemoteDesktop"
DESKTOP_PATH = "/org/freedesktop/portal/desktop"
SESSION_INTERFACE = "org.freedesktop.portal.Session"
REQUEST_INTERFACE = "org.freedesktop.portal.Request"
KEYSYMS = {
    "enter": 0xFF0D, "tab": 0xFF09, "escape": 0xFF1B,
    "backspace": 0xFF08, "delete": 0xFFFF, "up": 0xFF52,
    "down": 0xFF54, "left": 0xFF51, "right": 0xFF53,
    "home": 0xFF50, "end": 0xFF57, "pageup": 0xFF55,
    "pagedown": 0xFF56, "space": 0x20,
    **{key: ord(key) for key in "acvxz"},
}
MODIFIERS = {"ctrl": 0xFFE3, "alt": 0xFFE9, "shift": 0xFFE1, "win": 0xFFEB}
BUTTONS = {"left": 0x110, "right": 0x111}  # Linux evdev BTN_LEFT / BTN_RIGHT.
MAXIMUM_TEXT_SCALARS = 2048  # Bound the number of synchronous portal round trips.


def unicode_keysym(character):
    """XKB's Latin-1 values or the 0x01000000 Unicode keysym encoding.

    Newline/tab are actual keyboard keys. Other control characters are refused
    before any text is sent, since they cannot be represented as literal input.
    """
    code = ord(character)
    if character == "\n":
        return KEYSYMS["enter"]
    if character == "\t":
        return KEYSYMS["tab"]
    if code < 0x20 or 0x7F <= code < 0xA0 or 0xD800 <= code <= 0xDFFF:
        raise InputError("invalid_request")
    return code if code <= 0xFF else 0x01000000 | code


class PortalInput:
    """Permission is requested only by request_access(), never by status/apply."""

    def __init__(self, transport=None, clock=time.monotonic):
        self.transport = transport if transport is not None else GioPortalTransport()
        self.clock = clock
        self._state = self.transport.probe()
        self._generation = 0
        self._session = None
        self._request_cancel = None
        self._session_cancel = None
        self._closed = False
        self._buttons = set()
        self._keys = set()
        self.transport.set_lost_handler(self._lost)

    def status(self):
        return self._state

    def request_access(self):
        if self._closed or self._state in ("ready", "permission_pending"):
            return
        self._reset("permission_pending")
        self._state = self.transport.probe()
        if self._state != "permission_required":
            return
        self._state = "permission_pending"
        generation = self._generation
        token = "sofatap_" + uuid.uuid4().hex
        try:
            self._session = self.transport.session_path(token)
            self._session_cancel = self.transport.watch_session(
                self._session, lambda: self._revoked(generation))
        except Exception:
            self._reset("input_unavailable")
            return

        def created(response, results):
            if not self._continue(generation, response):
                return
            if results.get("session_handle") != self._session:
                self._reset("input_unavailable")
                return
            # Default persistence is zero on portal v1; no restore token is used.
            self._request("SelectDevices", (self._session,), {"types": 3}, selected)

        def selected(response, results):
            if self._continue(generation, response):
                self._request("Start", (self._session, ""), {}, started)

        def started(response, results):
            if not self._continue(generation, response):
                return
            devices = results.get("devices")
            if type(devices) is not int or devices & 3 != 3:
                self._reset("permission_denied")
                return
            self._state = "ready"
            self._request_cancel = None

        self._request("CreateSession", (), {"session_handle_token": token}, created)

    def _request(self, method, arguments, options, callback):
        try:
            self._request_cancel = self.transport.request(method, arguments, options, callback)
        except Exception:
            self._reset("input_unavailable")

    def _continue(self, generation, response):
        if generation != self._generation or self._closed or self._state != "permission_pending":
            return False
        self._request_cancel = None
        if response != 0:
            self._reset("permission_denied" if response == 1 else "input_unavailable")
            return False
        return True

    def _revoked(self, generation):
        if generation == self._generation:
            self._reset("permission_required")

    def _lost(self):
        self._reset("desktop_unavailable")

    def _reset(self, state):
        self._generation += 1
        self._state = state
        if self._request_cancel is not None:
            cancel, self._request_cancel = self._request_cancel, None
            cancel()
        if self._session_cancel is not None:
            cancel, self._session_cancel = self._session_cancel, None
            cancel()
        if self._session is not None:
            session, self._session = self._session, None
            self.transport.close_session(session)
        # Closing a portal session tears down its virtual input devices. Do not
        # send releases into an already revoked/replaced session.
        self._buttons.clear()
        self._keys.clear()

    def apply(self, action):
        validate_action(action)
        if self._state != "ready" or self._session is None:
            raise InputError("input_unavailable")
        kind = action["type"]
        # Validate the whole text before sending its first character.
        text_symbols = None
        if kind == "text":
            text = action["text"].replace("\r\n", "\n").replace("\r", "\n")
            if len(text) > MAXIMUM_TEXT_SCALARS:
                raise InputError("text_too_long")
            text_symbols = [unicode_keysym(character) for character in text]
        if kind in ("text", "key") and self._buttons:
            raise InputError("input_busy")
        if kind == "click" and self._buttons:
            raise InputError("input_busy")
        deadline = self.clock() + 3.0
        attempted = False

        def send(method, *values, options=None):
            nonlocal attempted
            remaining = deadline - self.clock()
            if remaining <= 0:
                raise TimeoutError()
            attempted = True  # A timed-out D-Bus call might already have applied.
            self.transport.notify(method, self._session, options or {}, values,
                                  max(1, min(500, int(remaining * 1000))))

        def key(symbol, down):
            if down:
                self._keys.add(symbol)
            send("NotifyKeyboardKeysym", symbol, int(down))
            if not down:
                self._keys.discard(symbol)

        def button(code, down):
            if down:
                self._buttons.add(code)
            send("NotifyPointerButton", code, int(down))
            if not down:
                self._buttons.discard(code)

        try:
            if kind == "move":
                send("NotifyPointerMotion", action["dx"], action["dy"])
            elif kind == "scroll":
                # Sofa Tap uses positive y for scrolling up, whereas Wayland
                # pointer axes use positive y for scrolling down.
                send("NotifyPointerAxis", action["dx"], -action["dy"], options={"finish": True})
            elif kind == "click":
                code = BUTTONS[action["button"]]
                button(code, True)
                button(code, False)
            elif kind == "button":
                code, down = BUTTONS[action["button"]], action["down"]
                if down != (code in self._buttons):
                    button(code, down)
            elif kind == "key":
                modifiers = [MODIFIERS[name] for name in action["modifiers"]]
                for symbol in modifiers:
                    key(symbol, True)
                key(KEYSYMS[action["key"]], True)
                key(KEYSYMS[action["key"]], False)
                for symbol in reversed(modifiers):
                    key(symbol, False)
            elif kind == "text":
                for symbol in text_symbols:
                    key(symbol, True)
                    key(symbol, False)
        except Exception:
            # Closing the session is preferable to retrying an uncertain press
            # or retaining a stuck virtual modifier. Retry requires local consent.
            self._reset("input_unavailable")
            raise InputError("input_partial" if attempted else "input_unavailable") from None

    def release_all(self):
        if self._state != "ready" or self._session is None:
            self._buttons.clear()
            self._keys.clear()
            return
        deadline = self.clock() + 1.0
        try:
            for method, values in (("NotifyKeyboardKeysym", self._keys),
                                   ("NotifyPointerButton", self._buttons)):
                for value in list(values):
                    remaining = deadline - self.clock()
                    if remaining <= 0:
                        raise TimeoutError()
                    self.transport.notify(method, self._session, {}, (value, 0),
                                          max(1, min(250, int(remaining * 1000))))
                    values.discard(value)
        except Exception:
            self._reset("input_unavailable")

    def close(self):
        if not self._closed:
            self._closed = True
            self._reset("desktop_unavailable")
            self.transport.close()


class GioPortalTransport:
    """Small Gio transport with bounded calls, authenticated signals and cleanup."""

    def __init__(self):
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
        self.Gio, self.GLib = Gio, GLib
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.bus.set_exit_on_close(False)
        self.sender = self.bus.get_unique_name()[1:].replace(".", "_")
        self.owner = None
        self._lost = lambda: None
        self._closed = False
        self._requests = set()
        self._session_owners = {}
        self._owner_signal = self.bus.signal_subscribe(
            "org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
            "/org/freedesktop/DBus", PORTAL, Gio.DBusSignalFlags.NONE, self._owner_changed)
        self._bus_closed = self.bus.connect("closed", lambda *args: self._lost())

    def set_lost_handler(self, callback):
        self._lost = callback

    def _owner_changed(self, connection, sender, path, interface, signal, parameters, *args):
        name, old_owner, new_owner = parameters.unpack()
        if self.owner and old_owner == self.owner and new_owner != self.owner:
            self.owner = None
            self._lost()

    def _call_sync(self, destination, path, interface, method, signature, values, timeout=500):
        return self.bus.call_sync(destination, path, interface, method,
                                  self.GLib.Variant(signature, values), None,
                                  self.Gio.DBusCallFlags.NONE, timeout, None)

    def probe(self):
        if self._closed or self.bus.is_closed():
            return "desktop_unavailable"
        try:
            # Reading capabilities may activate the service, but never requests
            # a remote desktop session or displays a permission prompt.
            properties = self._call_sync(PORTAL, DESKTOP_PATH, "org.freedesktop.DBus.Properties",
                                         "GetAll", "(s)", (INTERFACE,)).unpack()[0]
            self.owner = self._call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                        "org.freedesktop.DBus", "GetNameOwner", "(s)", (PORTAL,)).unpack()[0]
            version, devices = properties.get("version"), properties.get("AvailableDeviceTypes")
            if type(version) is not int or version < 1 or type(devices) is not int or devices & 3 != 3:
                return "unsupported_session"
            return "permission_required"
        except Exception:
            self.owner = None
            return "unsupported_session"

    def session_path(self, token):
        return DESKTOP_PATH + "/session/" + self.sender + "/" + token

    def request(self, method, arguments, options, callback):
        if not self.owner or self.bus.is_closed():
            raise RuntimeError("portal_unavailable")
        owner = self.owner
        token = "sofatap_" + uuid.uuid4().hex
        expected = DESKTOP_PATH + "/request/" + self.sender + "/" + token
        options = dict(options, handle_token=token)
        signatures = {"CreateSession": "(a{sv})", "SelectDevices": "(oa{sv})", "Start": "(osa{sv})"}
        parameters = self.GLib.Variant(signatures[method], (*arguments, self._options(options)))
        state = {"done": False, "validated": False, "response": None, "signal": 0, "timer": 0}
        cancellable = self.Gio.Cancellable()

        def finish(response=None, results=None, abort=False):
            if state["done"]:
                return False
            state["done"] = True
            self._requests.discard(cancel)
            if state["signal"]:
                self.bus.signal_unsubscribe(state["signal"])
            if state["timer"]:
                self.GLib.source_remove(state["timer"])
            cancellable.cancel()
            if abort:
                self._close_object(owner, expected, REQUEST_INTERFACE)
            if response is not None:
                callback(response, results or {})
            return False

        def cancel():
            finish(abort=True)

        def response_received(connection, sender, path, interface, signal, parameters, *unused):
            if state["done"]:
                return
            try:
                response, results = parameters.unpack()
                if type(response) is not int or type(results) is not dict:
                    raise ValueError()
                state["response"] = (response, results)
                if state["validated"]:
                    finish(response, results)
            except Exception:
                finish(2, abort=True)

        def method_finished(connection, result, *unused):
            try:
                actual = connection.call_finish(result).unpack()[0]
                if state["done"]:
                    if actual == expected:
                        self._close_object(owner, actual, REQUEST_INTERFACE)
                    return
                if actual != expected:
                    # Current supported portals honor handle_token. Refuse a
                    # mismatched object instead of accepting an unrelated signal.
                    finish(2, abort=True)
                    return
                state["validated"] = True
                if state["response"] is not None:
                    finish(*state["response"])
            except Exception:
                finish(2, abort=True)

        state["signal"] = self.bus.signal_subscribe(
            owner, REQUEST_INTERFACE, "Response", expected, None,
            self.Gio.DBusSignalFlags.NONE, response_received)
        # A Start dialog may remain open for one minute. Other protocol stages
        # have no human interaction and therefore have a short response deadline.
        state["timer"] = self.GLib.timeout_add(60_000 if method == "Start" else 5_000,
                                              lambda: finish(2, abort=True))
        self._requests.add(cancel)
        try:
            self.bus.call(owner, DESKTOP_PATH, INTERFACE, method, parameters, None,
                          self.Gio.DBusCallFlags.NONE, 3_000, cancellable, method_finished)
        except Exception:
            finish(abort=True)
            raise
        return cancel

    def watch_session(self, session, callback):
        self._session_owners[session] = self.owner
        subscription = self.bus.signal_subscribe(
            self.owner, SESSION_INTERFACE, "Closed", session, None,
            self.Gio.DBusSignalFlags.NONE, lambda *args: callback())
        return lambda: self.bus.signal_unsubscribe(subscription)

    def _options(self, options):
        types = {"handle_token": "s", "session_handle_token": "s", "types": "u", "finish": "b"}
        return {name: self.GLib.Variant(types[name], value) for name, value in options.items()}

    def notify(self, method, session, options, values, timeout):
        if self._closed or not self.owner or self.bus.is_closed():
            raise RuntimeError("portal_unavailable")
        signatures = {"NotifyPointerMotion": "(oa{sv}dd)", "NotifyPointerAxis": "(oa{sv}dd)",
                      "NotifyPointerButton": "(oa{sv}iu)", "NotifyKeyboardKeysym": "(oa{sv}iu)"}
        self._call_sync(self.owner, DESKTOP_PATH, INTERFACE, method, signatures[method],
                        (session, self._options(options), *values), timeout)

    def _close_object(self, owner, path, interface):
        if not owner or self.bus.is_closed():
            return

        def finished(connection, result, *args):
            try:
                connection.call_finish(result)
            except Exception:
                pass

        try:
            self.bus.call(owner, path, interface, "Close", None, None,
                          self.Gio.DBusCallFlags.NONE, 500, None, finished)
        except Exception:
            pass

    def close_session(self, session):
        # A service may relinquish its well-known name while its unique bus
        # owner still exists. Close the session on its original owner only.
        self._close_object(self._session_owners.pop(session, self.owner), session, SESSION_INTERFACE)

    def close(self):
        if not self._closed:
            self._closed = True
            for cancel in tuple(self._requests):
                cancel()
            self.bus.signal_unsubscribe(self._owner_signal)
            self.bus.disconnect(self._bus_closed)
            self._lost = lambda: None
