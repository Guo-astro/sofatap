"""Private input-worker protocol validation; contains no desktop API calls."""

import json
import math
import uuid

MAXIMUM_LINE = 131_072  # Existing 64 KiB action plus wrapper / JSON UTF-8 re-encoding.
STATUSES = {"ready", "permission_required", "permission_pending", "permission_denied",
            "desktop_unavailable", "unsupported_session", "input_unavailable", "dependency_missing"}
ERRORS = {"invalid_request", "input_failed", "input_partial", "input_busy", "input_unavailable",
          "permission_required", "permission_denied", "unsupported_action", "clipboard_unavailable", "text_too_long"}
KEYS = {"enter", "tab", "escape", "backspace", "delete", "up", "down", "left", "right",
        "home", "end", "pageup", "pagedown", "space", "a", "c", "v", "x", "z"}
MODIFIERS = {"ctrl", "alt", "shift", "win"}


class InputError(Exception):
    def __init__(self, code="input_failed"):
        self.code = code if code in ERRORS else "input_failed"
        super().__init__(self.code)


def _uuid(value):
    if not isinstance(value, str) or len(value) != 36:
        raise InputError("invalid_request")
    try:
        if str(uuid.UUID(value)) != value.lower():
            raise ValueError()
    except ValueError as error:
        raise InputError("invalid_request") from error


def _fields(value, fields):
    if not isinstance(value, dict) or set(value) != set(fields):
        raise InputError("invalid_request")


def validate_action(action):
    if not isinstance(action, dict):
        raise InputError("invalid_request")
    _uuid(action.get("id"))
    kind = action.get("type")
    if not isinstance(kind, str):
        raise InputError("invalid_request")
    if kind in {"move", "scroll"}:
        _fields(action, {"id", "type", "dx", "dy"})
        limit = 500 if kind == "move" else 1200
        for field in ("dx", "dy"):
            value = action[field]
            if type(value) not in (int, float) or abs(value) > limit or not math.isfinite(value):
                raise InputError("invalid_request")
    elif kind in {"click", "button"}:
        _fields(action, {"id", "type", "button"} | ({"down"} if kind == "button" else set()))
        if not isinstance(action["button"], str) or action["button"] not in {"left", "right"} or (kind == "button" and type(action["down"]) is not bool):
            raise InputError("invalid_request")
    elif kind == "key":
        _fields(action, {"id", "type", "key", "modifiers"})
        mods = action["modifiers"]
        if (not isinstance(action["key"], str) or action["key"] not in KEYS
                or not isinstance(mods, list) or len(mods) > 4
                or any(not isinstance(m, str) or m not in MODIFIERS for m in mods)
                or len(set(mods)) != len(mods)):
            raise InputError("invalid_request")
    elif kind == "text":
        _fields(action, {"id", "type", "text"})
        value = action["text"]
        if not isinstance(value, str) or "\0" in value:
            raise InputError("invalid_request")
        try:
            if len(value.encode("utf-16-le")) > 32_000:
                raise InputError("invalid_request")
        except UnicodeError as error:
            raise InputError("invalid_request") from error
    elif kind == "ping":
        _fields(action, {"id", "type"})
    else:
        raise InputError("invalid_request")
    return action


def parse_request(raw):
    if len(raw) > MAXIMUM_LINE:
        raise InputError("invalid_request")
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise InputError("invalid_request")
            result[key] = value
        return result
    try:
        request = json.loads(raw, object_pairs_hook=pairs, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    except (ValueError, UnicodeError, RecursionError) as error:
        raise InputError("invalid_request") from error
    if not isinstance(request, dict):
        raise InputError("invalid_request")
    _uuid(request.get("id"))
    kind = request.get("type")
    if not isinstance(kind, str):
        raise InputError("invalid_request")
    if kind == "apply":
        _fields(request, {"id", "type", "action"})
        validate_action(request["action"])
    elif kind in {"status", "requestAccess", "releaseAll", "quit"}:
        _fields(request, {"id", "type"})
    else:
        raise InputError("invalid_request")
    return request
