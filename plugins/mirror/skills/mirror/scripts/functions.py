#!/usr/bin/env python3
"""Local function-call adapter. Standard library only; no model or network calls."""
import argparse
import json
import math
import re
import subprocess
import sys
import tempfile
import unicodedata
import uuid
from pathlib import Path

LIMIT = 65536
HELPER = Path(__file__).resolve().with_name("mirror.sh")
READS = {"status", "list"}
WINDOW_ACTIONS = {"duplicate", "close", "hide", "show", "refresh", "cancel", "copy", "bind", "unbind"}


class InvalidArguments(ValueError):
    pass


def field(kind, description, nullable=False, **constraints):
    return {"type": [kind, "null"] if nullable else kind, "description": description, **constraints}


def object_schema(properties):
    return {"type": "object", "properties": properties, "required": list(properties), "additionalProperties": False}


def tools():
    """Responses-style strict functions; hosts can adapt the outer envelope."""
    descriptions = {
        "status": "Read Mirror's live revision and window metadata. Initial launch true may install the pinned GitHub preview if missing; macOS first-open remains manual. Follow-up checks use false to respect a human quit.",
        "list": "List local Mirror references and current revision. Returns metadata, not conversation text; follow-up checks must not relaunch.",
        "open": "Open or reuse a read-only reference to a confirmed local Codex conversation. Loading and binding are separate states; do not guess conversation IDs.",
        "duplicate": "Create one independent reference window only when a separate copy is requested; does not fork an AI task.",
        "close": "Close the specified Mirror reference, leaving Codex history untouched.",
        "hide": "Hide the specified reference window.",
        "show": "Restore the specified reference window without creating another one.",
        "refresh": "Refresh this reference in the background while keeping its existing content. Check contentStatus for completion.",
        "cancel": "Cancel reading for this window without cancelling another window's shared read.",
        "copy": "Copy the current message to the local clipboard ONLY when the user requests copying. Does not return its text.",
        "find": "Find literal text in this reference; empty query clears find and restores its prior reading position.",
        "font": "Set this reference's font size while preserving reading position and search.",
        "frame": "Arrange the reference using observed macOS screen coordinates (bottom-left origin). Does not bind a host.",
        "bind": "Bind this reference's group to an unambiguous Codex host window. Never grants system permissions.",
        "unbind": "Stop this reference's group following its Codex host window.",
    }
    result = []
    for action, description in descriptions.items():
        properties = {}
        if action in READS:
            properties["launch"] = field("boolean", "Initial status may launch Mirror; follow-up checks use false.")
        else:
            properties["revision"] = field("integer", "Latest observed native revision. Stop on revision_conflict or agent_paused; never refresh revision to force an old action.", minimum=0, maximum=9007199254740991)
            properties["window"] = field("string", "Confirmed window UUID; null only for open without a specific target.", nullable=action == "open")
        if action == "open":
            properties.update({
                "conversation": field("string", "Confirmed local Codex conversation ID; not a title or search string.", maxLength=256),
                "message": field("string", "Actual TURN_ID/ITEM_ID, or null for no message target.", nullable=True, maxLength=512),
                "new": field("boolean", "False reuses a unique reference; true explicitly requests an additional window."),
            })
        if action == "find":
            properties["query"] = field("string", "Literal search text, no control characters; at most 4096 UTF-8 bytes.", maxLength=4096)
        if action == "font":
            properties["font_size"] = field("number", "Font size in points.", minimum=11, maximum=26)
        if action == "frame":
            properties["frame"] = object_schema({
                "x": field("number", "Screen x.", minimum=-100000, maximum=100000),
                "y": field("number", "Screen y.", minimum=-100000, maximum=100000),
                "width": field("number", "Window width.", minimum=280, maximum=100000),
                "height": field("number", "Window height.", minimum=260, maximum=100000),
            })
        properties["request_id"] = field("string", "UUID or null to generate one. Retain it and the original arguments after an uncertain result; never blindly retry a mutation.", nullable=True)
        if action not in READS:
            description += " Requires a fresh revision; human changes or paused control take priority. Sent once, never automatically retried."
        result.append({"type": "function", "name": "mirror_" + action, "description": description, "strict": True, "parameters": object_schema(properties)})
    return result


def validate(value, schema):
    kinds = schema["type"]
    kinds = kinds if isinstance(kinds, list) else [kinds]
    if value is None and "null" in kinds:
        return
    kind = next((k for k in kinds if k != "null"), None)
    matches = {
        "object": lambda: type(value) is dict,
        "string": lambda: type(value) is str,
        "boolean": lambda: type(value) is bool,
        "integer": lambda: type(value) is int,
        "number": lambda: type(value) is int or (type(value) is float and math.isfinite(value)),
    }
    if kind not in matches or not matches[kind]():
        raise InvalidArguments("Argument type does not match the tool schema.")
    if kind == "object":
        if set(value) != set(schema["properties"]):
            raise InvalidArguments("Provide exactly the declared fields; use null for nullable fields.")
        for key, child in schema["properties"].items():
            validate(value[key], child)
    if kind in ("integer", "number"):
        if value < schema.get("minimum", -math.inf) or value > schema.get("maximum", math.inf):
            raise InvalidArguments("Numeric argument is out of range.")
    if kind == "string":
        try:
            value.encode("utf-8")
        except UnicodeEncodeError:
            raise InvalidArguments("Argument is not valid UTF-8.") from None
        if len(value) > schema.get("maxLength", math.inf):
            raise InvalidArguments("Text argument is too long.")


def check_uuid(value):
    if value is not None and not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", value):
        raise InvalidArguments("Window and request identifiers must be UUIDs.")


def build_argv(name, arguments, app=None):
    schema = next((t for t in tools() if t["name"] == name), None)
    if schema is None:
        raise InvalidArguments("Unknown Mirror function.")
    validate(arguments, schema["parameters"])
    action = name.removeprefix("mirror_")
    request_id = arguments["request_id"] or str(uuid.uuid4())
    check_uuid(request_id)
    check_uuid(arguments.get("window"))
    for key, pattern in (("conversation", r"[A-Za-z0-9_.-]+"), ("message", r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")):
        value = arguments.get(key)
        if value is not None and (not re.fullmatch(pattern, value) or ".." in value):
            raise InvalidArguments("Invalid conversation or message identifier.")
    if action == "open" and arguments["new"] and arguments["window"] is not None:
        raise InvalidArguments("A new reference cannot also select an existing window.")
    if action == "find":
        query = arguments["query"]
        if len(query.encode("utf-8")) > 4096 or any(unicodedata.category(c) in ("Cc", "Cf") for c in query):
            raise InvalidArguments("Search text exceeds 4096 UTF-8 bytes or contains controls.")
    argv = ["/bin/bash", str(HELPER), action, "--request-id", request_id]
    flags = {"launch": "--launch", "revision": "--revision", "window": "--window", "conversation": "--conversation", "message": "--message", "new": "--new", "query": "--query", "font_size": "--font-size", "frame": "--frame"}
    for key, flag in flags.items():
        value = arguments.get(key)
        if value is None:
            continue
        if type(value) is bool:
            value = "true" if value else "false"
        elif type(value) is dict:
            value = json.dumps(value, allow_nan=False, separators=(",", ":"))
        else:
            value = str(value)
        argv.extend([flag, value])
    if app is not None:
        if not Path(app).is_absolute() or not app.endswith(".app"):
            raise InvalidArguments("Host app selection must be an absolute .app path.")
        argv.extend(["--app", app])
    return argv, request_id


def run_receipt(argv, request_id, runner, timeout=90):
    with tempfile.TemporaryFile() as output:
        completed = runner(argv, stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.DEVNULL, timeout=timeout, check=False)
        output.seek(0)
        raw = output.read(LIMIT + 1)
    if len(raw) > LIMIT:
        return {"ok": False, "status": "invalid_response", "requestID": request_id, "message": "Local response exceeded 64 KiB."}
    try:
        result = json.loads(raw)
    except (ValueError, UnicodeError):
        result = None
    if type(result) is not dict or type(result.get("ok")) is not bool or type(result.get("status")) is not str:
        return {"ok": False, "status": "invalid_response", "requestID": request_id, "message": "Local helper did not return a valid receipt."}
    if completed.returncode != 0 and result["ok"]:
        return {"ok": False, "status": "invalid_response", "requestID": request_id}
    result.setdefault("requestID", request_id)
    return result


def invoke(name, arguments, app=None, runner=subprocess.run):
    """No retries, shell evaluation, credentials, model calls or hosted transport."""
    request_id = None
    try:
        argv, request_id = build_argv(name, arguments, app)
        result = run_receipt(argv, request_id, runner)
        if name == "mirror_status" and arguments["launch"] and app is None and result["status"] == "app_not_found":
            # Only explicit initial use may install. No following-up a human quit,
            # overriding an app selector, changing release pins or retrying mutations.
            result = run_receipt(["/bin/bash", str(HELPER.with_name("install-preview.sh"))], request_id, runner, timeout=600)
        return result
    except InvalidArguments as error:
        return {"ok": False, "status": "invalid_arguments", "message": str(error)}
    except subprocess.TimeoutExpired:
        return {"ok": False, "status": "timeout", "requestID": request_id, "message": "Outcome may be uncertain. Check status with launch false; do not repeat a mutation under a fresh request ID."}
    except OSError:
        return {"ok": False, "status": "helper_unavailable", "requestID": request_id, "message": "Local helper could not run. Requires local execution on a compatible Mac."}


def load_arguments(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise InvalidArguments("Duplicate JSON fields are not allowed.")
            result[key] = value
        return result
    if len(raw) > LIMIT:
        raise InvalidArguments("Arguments exceed 64 KiB.")
    try:
        return json.loads(raw, object_pairs_hook=unique, parse_constant=lambda _: (_ for _ in ()).throw(InvalidArguments("Non-finite JSON numbers are not allowed.")))
    except (ValueError, UnicodeError, RecursionError):
        raise InvalidArguments("Arguments must be a UTF-8 JSON object with unique fields.") from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("name", nargs="?", help="Function name; arguments are read as JSON from stdin.")
    parser.add_argument("--tools", action="store_true", help="Export strict function schemas without starting Mirror.")
    parser.add_argument("--app", help="Host-selected existing Mirror .app; not a model-controlled tool parameter.")
    options = parser.parse_args()
    if options.tools:
        print(json.dumps(tools(), ensure_ascii=False, indent=2))
        return 0
    try:
        if not options.name:
            raise InvalidArguments("A Mirror function name is required.")
        arguments = load_arguments(sys.stdin.buffer.read(LIMIT + 1))
        result = invoke(options.name, arguments, app=options.app)
    except InvalidArguments as error:
        result = {"ok": False, "status": "invalid_arguments", "message": str(error)}
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
