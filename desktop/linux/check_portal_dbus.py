#!/usr/bin/env python3
"""Exercise Gio against a fake portal on a NEW private D-Bus, never a desktop.

Requires Linux python3-gi and dbus-run-session. No GTK window, compositor,
screen capture or input device is used. The launcher strips desktop variables;
the service refuses to replace any existing org.freedesktop.portal.Desktop.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import unittest


def launch_private_bus():
    if not shutil.which("dbus-run-session"):
        raise SystemExit("dbus-run-session is required for isolated portal tests")
    env = dict(os.environ)
    for name in ("DISPLAY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "SESSION_MANAGER"):
        env.pop(name, None)
    result = subprocess.run(["dbus-run-session", "--", sys.executable, str(Path(__file__).resolve()),
                             "--private-bus"], env=env, timeout=45)
    raise SystemExit(result.returncode)


if __name__ == "__main__" and len(sys.argv) == 1:
    launch_private_bus()

from gi.repository import Gio, GLib
from input_common import InputError
from wayland_input import (DESKTOP_PATH, INTERFACE, PORTAL, REQUEST_INTERFACE, SESSION_INTERFACE,
                           GioPortalTransport, PortalInput)


CONTROL = "dev.chekusu.SofaTap.PortalTest"
XML = """<node>
 <interface name="org.freedesktop.portal.RemoteDesktop">
  <property name="version" type="u" access="read"/>
  <property name="AvailableDeviceTypes" type="u" access="read"/>
  <method name="CreateSession"><arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method>
  <method name="SelectDevices"><arg type="o" direction="in"/><arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method>
  <method name="Start"><arg type="o" direction="in"/><arg type="s" direction="in"/><arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method>
  <method name="NotifyPointerMotion"><arg type="o" direction="in"/><arg type="a{sv}" direction="in"/><arg type="d" direction="in"/><arg type="d" direction="in"/></method>
  <method name="NotifyPointerAxis"><arg type="o" direction="in"/><arg type="a{sv}" direction="in"/><arg type="d" direction="in"/><arg type="d" direction="in"/></method>
  <method name="NotifyPointerButton"><arg type="o" direction="in"/><arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="in"/></method>
  <method name="NotifyKeyboardKeysym"><arg type="o" direction="in"/><arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="in"/></method>
 </interface>
 <interface name="dev.chekusu.SofaTap.PortalTest">
  <method name="Configure"><arg type="s" direction="in"/></method>
  <method name="Snapshot"><arg type="s" direction="out"/></method>
  <method name="Revoke"/>
  <method name="DropName"/>
 </interface>
 <interface name="org.freedesktop.portal.Session">
  <method name="Close"/>
  <signal name="Closed"><arg type="a{sv}"/></signal>
 </interface>
 <interface name="org.freedesktop.portal.Request">
  <method name="Close"/>
  <signal name="Response"><arg type="u"/><arg type="a{sv}"/></signal>
 </interface>
</node>"""


def bus_call(bus, interface, method, signature="()", values=()):
    return bus.call_sync(PORTAL, DESKTOP_PATH, interface, method, GLib.Variant(signature, values),
                         None, Gio.DBusCallFlags.NONE, 1000, None)


class FakeService:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        reply = self.bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                   "RequestName", GLib.Variant("(su)", (PORTAL, 4)), None,
                                   Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
        if reply != 1:
            raise RuntimeError("refusing to replace an existing portal")
        self.interfaces = {value.name: value for value in Gio.DBusNodeInfo.new_for_xml(XML).interfaces}
        self.objects = []
        self.mode = "normal"
        self.events = []
        self.session = None
        self.session_closed = 0
        self.requests_closed = 0
        self.register(DESKTOP_PATH, INTERFACE)
        self.register(DESKTOP_PATH, CONTROL)

    def register(self, path, interface):
        self.objects.append(self.bus.register_object(path, self.interfaces[interface], self.method,
                                                     self.property, None))

    def property(self, connection, sender, path, interface, name):
        return GLib.Variant("u", 1 if name == "version" else 3)

    def method(self, connection, sender, path, interface, method, parameters, invocation):
        values = parameters.unpack()
        if interface == CONTROL:
            if method == "Configure":
                self.mode = values[0]
                self.events = []
                self.session_closed = self.requests_closed = 0
            elif method == "Snapshot":
                invocation.return_value(GLib.Variant("(s)", (json.dumps({"events": self.events,
                    "sessionClosed": self.session_closed, "requestsClosed": self.requests_closed}),)))
                return
            elif method == "Revoke" and self.session:
                self.bus.emit_signal(None, self.session, SESSION_INTERFACE, "Closed", GLib.Variant("(a{sv})", ({},)))
            elif method == "DropName":
                self.bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                   "ReleaseName", GLib.Variant("(s)", (PORTAL,)), None,
                                   Gio.DBusCallFlags.NONE, 1000, None)
            invocation.return_value(GLib.Variant("()", ()))
        elif interface == SESSION_INTERFACE:
            self.session_closed += 1
            invocation.return_value(GLib.Variant("()", ()))
        elif interface == REQUEST_INTERFACE:
            self.requests_closed += 1
            invocation.return_value(GLib.Variant("()", ()))
        elif method.startswith("Notify"):
            self.events.append([method, list(values[2:]), values[1]])
            if self.mode == "fail_notify":
                invocation.return_dbus_error("org.freedesktop.portal.Error.Failed", "synthetic failure")
            else:
                invocation.return_value(GLib.Variant("()", ()))
        else:
            options = values[-1]
            prefix = DESKTOP_PATH + "/request/" + sender[1:].replace(".", "_") + "/"
            request = prefix + options["handle_token"]
            self.register(request, REQUEST_INTERFACE)
            results = {}
            response = 0
            if method == "CreateSession":
                self.session = DESKTOP_PATH + "/session/" + sender[1:].replace(".", "_") + "/" + options["session_handle_token"]
                self.register(self.session, SESSION_INTERFACE)
                results["session_handle"] = GLib.Variant("s", self.session)
            elif method == "Start":
                if self.mode == "deny":
                    response = 1
                results["devices"] = GLib.Variant("u", 1 if self.mode == "missing_pointer" else 3)
            if self.mode != "hold":
                # Deliberately emit before returning the method handle; clients
                # must subscribe first and wait for handle validation.
                self.bus.emit_signal(sender, request, REQUEST_INTERFACE, "Response",
                                     GLib.Variant("(ua{sv})", (response, results)))
            invocation.return_value(GLib.Variant("(o)", (request,)))


def wait_for(predicate, seconds=3):
    deadline = time.monotonic() + seconds
    context = GLib.MainContext.default()
    while not predicate():
        if time.monotonic() > deadline:
            raise AssertionError("private D-Bus test timed out")
        while context.pending():
            context.iteration(False)
        time.sleep(0.005)


class PortalDbusChecks(unittest.TestCase):
    def setUp(self):
        # Each test gets a fresh fake service. Its well-known name cannot refer
        # to a desktop service because this entire process has a private bus.
        self.service = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--fake-service"],
                                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if self.service.stdout.readline().strip() != "READY":
            raise AssertionError("private fake portal failed to start")
        self.transport = GioPortalTransport()
        self.backend = PortalInput(self.transport)
        self.bus = self.transport.bus

    def tearDown(self):
        self.backend.close()
        self.service.terminate()
        try:
            self.service.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            self.service.kill()
            self.service.communicate(timeout=2)

    def configure(self, mode):
        bus_call(self.bus, CONTROL, "Configure", "(s)", (mode,))

    def snapshot(self):
        return json.loads(bus_call(self.bus, CONTROL, "Snapshot").unpack()[0])

    def grant(self):
        self.backend.request_access()
        wait_for(lambda: self.backend.status() != "permission_pending")
        self.assertEqual("ready", self.backend.status())

    def test_early_response_signals_and_real_variant_signatures(self):
        self.assertEqual("permission_required", self.backend.status())
        self.grant()
        base = {"id": "f7f791d0-38f5-4534-bc79-a8a0d9a3e936"}
        for value in ({"type": "move", "dx": 0.5, "dy": -0.5},
                      {"type": "click", "button": "right"},
                      {"type": "scroll", "dx": 1, "dy": 2},
                      {"type": "text", "text": "中👋"},
                      {"type": "key", "key": "a", "modifiers": ["ctrl"]}):
            self.backend.apply(dict(base, **value))
        events = self.snapshot()["events"]
        self.assertEqual(12, len(events))
        self.assertEqual([0.5, -0.5], events[0][1])
        self.assertEqual([273, 1], events[1][1])
        self.assertEqual([1.0, -2.0], events[3][1])
        self.assertEqual({"finish": True}, events[3][2])
        self.assertEqual([0x01004E2D, 1], events[4][1])

    def test_denial_closes_session_and_does_not_reprompt(self):
        self.configure("deny")
        self.backend.request_access()
        wait_for(lambda: self.backend.status() == "permission_denied")
        wait_for(lambda: self.snapshot()["sessionClosed"] == 1)
        self.assertEqual([], self.snapshot()["events"])

    def test_partial_device_permission_is_not_ready(self):
        self.configure("missing_pointer")
        self.backend.request_access()
        wait_for(lambda: self.backend.status() != "permission_pending")
        self.assertEqual("permission_denied", self.backend.status())

    def test_revocation_and_unique_owner_loss_are_observed(self):
        self.grant()
        bus_call(self.bus, CONTROL, "Revoke")
        wait_for(lambda: self.backend.status() == "permission_required")
        self.grant()
        bus_call(self.bus, CONTROL, "DropName")
        wait_for(lambda: self.backend.status() == "desktop_unavailable")

    def test_notify_error_is_partial_and_closes_owned_session(self):
        self.grant()
        self.configure("fail_notify")
        with self.assertRaises(InputError) as caught:
            self.backend.apply({"id": "f7f791d0-38f5-4534-bc79-a8a0d9a3e936", "type": "click", "button": "left"})
        self.assertEqual("input_partial", caught.exception.code)
        wait_for(lambda: self.snapshot()["sessionClosed"] == 1)
        self.assertEqual(1, len(self.snapshot()["events"]))

    def test_permission_response_timeout_closes_pending_objects(self):
        self.configure("hold")
        self.backend.request_access()
        wait_for(lambda: self.backend.status() == "input_unavailable", seconds=6)
        wait_for(lambda: self.snapshot()["requestsClosed"] == 1)
        wait_for(lambda: self.snapshot()["sessionClosed"] == 1)

    def test_session_closed_signal_from_another_sender_is_ignored(self):
        self.grant()
        self.bus.emit_signal(None, self.backend._session, SESSION_INTERFACE, "Closed",
                             GLib.Variant("(a{sv})", ({},)))
        context = GLib.MainContext.default()
        until = time.monotonic() + 0.05
        while time.monotonic() < until:
            while context.pending():
                context.iteration(False)
            time.sleep(0.005)
        self.assertEqual("ready", self.backend.status())

    def test_closing_pending_request_closes_request_and_session(self):
        self.configure("hold")
        self.backend.request_access()
        context = GLib.MainContext.default()
        until = time.monotonic() + 0.1
        while time.monotonic() < until:
            while context.pending():
                context.iteration(False)
            time.sleep(0.005)
        self.backend.close()
        wait_for(lambda: self.snapshot()["requestsClosed"] == 1)
        wait_for(lambda: self.snapshot()["sessionClosed"] == 1)


if __name__ == "__main__":
    if sys.argv[1:] == ["--fake-service"]:
        service = FakeService()
        print("READY", flush=True)
        GLib.MainLoop().run()
    elif sys.argv[1:] == ["--private-bus"]:
        unittest.main(argv=[sys.argv[0]])
    else:
        raise SystemExit("Use this test without arguments to create its private bus")
