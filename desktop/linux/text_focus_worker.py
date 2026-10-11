#!/usr/bin/env python3
"""Optional focus metadata over the AT-SPI accessibility D-Bus.

Only focused-object state and numeric role are queried. No text/name/value reads,
desktop tree traversal, libatspi object cache, P2P connections or input injection.
No accessibility settings are changed. Missing services fall back to unknown.
Wire contract: GNOME at-spi2-core 2.52 xml/{Registry,Accessible,Event}.xml.
"""
import json
import sys
import time
import uuid


def classify_focus(*, focused, enabled, editable, read_only, password, defunct):
    if defunct or not focused:
        return "unknown"
    if password:
        return "protected"
    return "editable" if enabled and editable and not read_only else "other"


def classify_state_words(words, role):
    if (not isinstance(words, (list, tuple)) or len(words) != 2
            or any(type(word) is not int or not 0 <= word <= 0xffffffff for word in words)
            or type(role) is not int or not 0 <= role <= 0xffffffff):
        return "unknown"
    def has(bit):
        return bool(words[bit // 32] & (1 << (bit % 32)))
    return classify_focus(focused=has(12), enabled=has(8), editable=has(7),
                          read_only=has(43), defunct=has(6), password=role == 40)


class FocusProbe:
    def __init__(self, bus, Gio, GLib, clock=time.monotonic, stop=lambda: None):
        self.Gio, self.GLib, self.clock = Gio, GLib, clock
        self.stop = stop
        self.bus = bus
        self.target = None
        self.identity = None
        self.kind = "unknown"
        self.generation = 0
        self.request = None
        self.values = {}
        self.updated = 0

    def reset(self, target=None):
        self.generation += 1
        if self.request is not None:
            self.request.cancel()
        self.request = None
        self.target = target
        self.identity = uuid.uuid4().hex if target else None
        self.kind = "unknown"
        self.updated = 0
        self.values = {}

    def focused(self, bus, sender, path, interface, member, parameters, *_):
        # Inspect only the focus flag. Never unpack event payload/properties.
        try:
            if (not isinstance(sender, str) or not sender.startswith(":") or len(sender) > 255
                    or not isinstance(path, str) or not path.startswith("/") or len(path) > 1024):
                return
            if interface == "org.a11y.atspi.Event.Object" and member == "StateChanged":
                if (parameters.n_children() < 2 or parameters.get_child_value(0).get_type_string() != "s"
                        or parameters.get_child_value(1).get_type_string() != "i"):
                    return
                if parameters.get_child_value(0).get_string() != "focused":
                    return
                gained = parameters.get_child_value(1).get_int32() != 0
            elif interface == "org.a11y.atspi.Event.Focus" and member == "Focus":
                gained = True  # Deprecated Focus event means focus gain.
            else:
                return
            target = (sender, path)
            if gained and target != self.target:
                self.reset(target)
                self.refresh()
            elif not gained and target == self.target:
                self.reset()
        except (self.GLib.Error, TypeError, ValueError):
            self.reset()

    def refresh(self):
        if self.target is None or self.request is not None:
            return
        self.request = self.Gio.Cancellable()
        request = self.request
        self.values = {}
        generation = self.generation

        def finished(connection, result, field):
            try:
                reply = connection.call_finish(result)
                value = reply.unpack()[0]
            except (self.GLib.Error, IndexError, TypeError):
                if generation == self.generation and self.request is request:
                    self.request.cancel()
                    self.request = None
                    self.kind = "unknown"
                return
            if generation != self.generation or self.request is not request:
                return
            self.values[field] = value
            if len(self.values) == 2:
                self.kind = classify_state_words(self.values["state"], self.values["role"])
                self.updated = self.clock()
                self.request = None

        # Two bounded asynchronous calls through the accessibility bus. Never
        # ask for GetApplicationBusAddress, Cache.GetItems, names or values.
        try:
            for field, method, signature in (("state", "GetState", "(au)"), ("role", "GetRole", "(u)")):
                self.bus.call(self.target[0], self.target[1], "org.a11y.atspi.Accessible", method,
                              None, self.GLib.VariantType.new(signature), self.Gio.DBusCallFlags.NO_AUTO_START,
                              200, request, finished, field)
        except self.GLib.Error:
            request.cancel()
            self.request = None
            self.kind = "unknown"

    def tick(self):
        if self.bus.is_closed():
            self.reset()
        else:
            self.refresh()
        kind = self.kind if self.clock() - self.updated < 1 else "unknown"
        try:
            print(json.dumps({"kind": kind, "identity": self.identity if kind != "unknown" else None},
                             separators=(",", ":")), flush=True)
        except BrokenPipeError:
            # GLib catches callback exceptions, so the outer __main__ handler
            # alone cannot terminate a helper whose receiver has disappeared.
            self.reset()
            self.stop()
            return False
        return True


def main():
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
    except (ImportError, ValueError):
        print('{"kind":"unknown","identity":null}', flush=True)
        return
    try:
        session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        address = session.call_sync("org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress",
                                    None, GLib.VariantType.new("(s)"), Gio.DBusCallFlags.NONE,
                                    1000, None).unpack()[0]
        if not isinstance(address, str) or not address.startswith("unix:") or ";" in address:
            return
        bus = Gio.DBusConnection.new_for_address_sync(address,
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None, None)
        bus.set_exit_on_close(False)
        loop = GLib.MainLoop()
        probe = FocusProbe(bus, Gio, GLib, stop=loop.quit)
        bus.signal_subscribe(None, "org.a11y.atspi.Event.Object", "StateChanged", None, "focused",
                             Gio.DBusSignalFlags.NONE, probe.focused, None)
        bus.signal_subscribe(None, "org.a11y.atspi.Event.Focus", "Focus", None, None,
                             Gio.DBusSignalFlags.NONE, probe.focused, None)
        for event in ("object:state-changed:focused", "focus"):
            bus.call_sync("org.a11y.atspi.Registry", "/org/a11y/atspi/registry", "org.a11y.atspi.Registry",
                          "RegisterEvent", GLib.Variant("(sass)", (event, [], "")),
                          GLib.VariantType.new("()"), Gio.DBusCallFlags.NONE, 1000, None)
        probe.tick()
        GLib.timeout_add(250, probe.tick)
        loop.run()
    except Exception:
        return


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
