#!/usr/bin/env python3
"""Optional AT-SPI focus metadata. Does not query names, values, labels or text.

No tree traversal: startup remains unknown until an accessibility focus event.
No permission prompts or desktop input. Absence of AT-SPI is a supported fallback.
The AT-SPI library may receive incidental platform event metadata; none is emitted.
"""
import json
import os
import sys
import uuid


def classify_focus(*, focused, enabled, editable, read_only, password, defunct):
    if defunct or not focused:
        return "unknown"
    if password:
        return "protected"
    return "editable" if enabled and editable and not read_only else "other"


def main():
    # Cache.NONE controls which cached properties API calls use, but does not
    # disable libatspi's automatic Cache.GetItems request. Set its no-cache switch
    # before loading GI/AT-SPI so names/descriptions are not requested in bulk.
    # This changes only this helper process, never the user's desktop settings.
    os.environ["ATSPI_NO_CACHE"] = "1"
    try:
        import gi
        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi, GLib
    except (ImportError, ValueError):
        print('{"kind":"unknown","identity":null}', flush=True)
        return

    current = None
    identity = None

    def emit():
        nonlocal current, identity
        kind = "unknown"
        try:
            if current is not None:
                states = current.get_state_set()
                kind = classify_focus(
                    focused=states.contains(Atspi.StateType.FOCUSED),
                    enabled=states.contains(Atspi.StateType.ENABLED),
                    editable=states.contains(Atspi.StateType.EDITABLE),
                    read_only=states.contains(Atspi.StateType.READ_ONLY),
                    password=current.get_role() == Atspi.Role.PASSWORD_TEXT,
                    defunct=states.contains(Atspi.StateType.DEFUNCT),
                )
        except Exception:
            kind = "unknown"
        if kind == "unknown":
            current = None
            identity = None
        print(json.dumps({"kind": kind, "identity": identity}, separators=(",", ":")), flush=True)
        return True

    def focus_changed(event, *_):
        nonlocal current, identity
        # Object events include both gain and loss; legacy focus events mean gain.
        gained = event.type.startswith("focus") or bool(event.detail1)
        if gained:
            if event.source != current:
                current = event.source
                identity = uuid.uuid4().hex
        elif event.source == current:
            current = None
            identity = None
        # The heartbeat emits a bounded rate even when an application floods events.

    try:
        if Atspi.init() != 0:
            return
        Atspi.set_timeout(150, 300)
        # Do not use cached states; subsequent explicit queries request role/state
        # metadata only. Libatspi may still receive unsolicited platform events.
        Atspi.get_desktop(0).set_cache_mask(Atspi.Cache.NONE)
        listener = Atspi.EventListener.new(focus_changed)
        listener.register("object:state-changed:focused")
        listener.register("focus")
        emit()
        GLib.timeout_add(250, emit)
        GLib.MainLoop().run()
    except Exception:
        # No arbitrary provider diagnostics or metadata are returned to the host.
        return


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
