#!/usr/bin/env python3
"""Exercise deterministic tool dispatch without models or real user windows."""
import importlib.util
import json
import math
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "plugins/mirror/skills/mirror/scripts/functions.py"
spec = importlib.util.spec_from_file_location("mirror_functions", SCRIPT)
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)
WINDOW = "10000000-0000-0000-0000-000000000001"
REQUEST = "20000000-0000-0000-0000-000000000001"


def arguments(action):
    args = {"request_id": REQUEST}
    if action in adapter.READS:
        return {**args, "launch": False}
    args.update(revision=7, window=WINDOW)
    if action == "open":
        args.update(window=None, conversation="confirmed-chat", message=None, new=False)
    if action == "find":
        args["query"] = "中文 & text"
    if action == "font":
        args["font_size"] = 23
    if action == "frame":
        args["frame"] = {"x": 40, "y": -100, "width": 500, "height": 600}
    return args


class DispatchTests(unittest.TestCase):
    def fake(self, result=None, code=0):
        calls = []
        if result is None:
            result = {"ok": True, "status": "ready", "revision": 7, "windows": []}

        def runner(argv, **kwargs):
            calls.append((argv, kwargs))
            kwargs["stdout"].write(json.dumps(result).encode())
            return SimpleNamespace(returncode=code)

        return calls, runner

    def test_all_native_operations_available_and_sent_once(self):
        names = {"status", "list", "open", "duplicate", "close", "hide", "show", "refresh", "cancel", "copy", "find", "font", "frame", "bind", "unbind"}
        self.assertEqual({t["name"] for t in adapter.tools()}, {"mirror_" + n for n in names})
        for name in names:
            with self.subTest(action=name):
                calls, runner = self.fake()
                result = adapter.invoke("mirror_" + name, arguments(name), runner=runner)
                self.assertTrue(result["ok"])
                self.assertEqual(len(calls), 1)
                self.assertEqual(calls[0][0][2], name)
                self.assertNotIn("shell", calls[0][1])

    def test_unknown_and_extra_fields_never_execute(self):
        calls, runner = self.fake()
        self.assertEqual(adapter.invoke("run_shell", {}, runner=runner)["status"], "invalid_arguments")
        self.assertEqual(adapter.invoke("mirror_status", {**arguments("status"), "shell": "pwd"}, runner=runner)["status"], "invalid_arguments")
        self.assertEqual(calls, [])

    def test_invalid_values_never_execute(self):
        cases = [
            ("font", "font_size", True), ("font", "font_size", math.nan),
            ("font", "font_size", 27), ("font", "font_size", 10**500),
            ("close", "revision", True), ("close", "revision", -1),
            ("close", "revision", 1.5), ("close", "revision", 9007199254740992),
            ("close", "window", "not-a-uuid"), ("close", "window", None),
            ("open", "conversation", "../private"), ("open", "conversation", "$(pwd)"),
            ("open", "message", "not-a-message"),
            ("find", "query", "中文" * 1400), ("find", "query", "line\nline"),
            ("find", "query", "\ud800"), ("status", "launch", "false"),
            ("status", "request_id", "invalid"),
        ]
        for action, key, value in cases:
            with self.subTest(action=action, key=key):
                calls, runner = self.fake()
                result = adapter.invoke("mirror_" + action, {**arguments(action), key: value}, runner=runner)
                self.assertEqual(result["status"], "invalid_arguments")
                self.assertEqual(calls, [])

    def test_frame_bounds_and_exact_fields(self):
        for frame in [{"x": 0}, {"x": 0, "y": 0, "width": 279, "height": 260}, {"x": math.inf, "y": 0, "width": 400, "height": 400}, {"x": 0, "y": 0, "width": 400, "height": 400, "z": 1}]:
            calls, runner = self.fake()
            self.assertEqual(adapter.invoke("mirror_frame", {**arguments("frame"), "frame": frame}, runner=runner)["status"], "invalid_arguments")
            self.assertEqual(calls, [])

    def test_reuse_is_default_and_new_window_needs_no_target(self):
        argv, _ = adapter.build_argv("mirror_open", arguments("open"))
        self.assertEqual(argv[argv.index("--new") + 1], "false")
        args = {**arguments("open"), "new": True, "window": WINDOW}
        self.assertEqual(adapter.invoke("mirror_open", args)["status"], "invalid_arguments")

    def test_empty_query_is_forwarded(self):
        argv, _ = adapter.build_argv("mirror_find", {**arguments("find"), "query": ""})
        self.assertEqual(argv[argv.index("--query") + 1], "")

    def test_unknown_app_selection_rejected_before_execution(self):
        calls, runner = self.fake()
        self.assertEqual(adapter.invoke("mirror_status", arguments("status"), app="relative.app", runner=runner)["status"], "invalid_arguments")
        self.assertEqual(calls, [])

    def test_revision_and_pause_failures_not_retried(self):
        for status in ["revision_conflict", "agent_paused", "app_not_running", "setup_required", "timeout"]:
            calls, runner = self.fake({"ok": False, "status": status}, code=1)
            result = adapter.invoke("mirror_close", arguments("close"), runner=runner)
            self.assertEqual(result["status"], status)
            self.assertEqual(result["requestID"], REQUEST)
            self.assertEqual(len(calls), 1)

    def test_timeout_preserves_request_receipt(self):
        def runner(argv, **kwargs):
            raise subprocess.TimeoutExpired(argv, 90)
        result = adapter.invoke("mirror_refresh", arguments("refresh"), runner=runner)
        self.assertEqual(result["status"], "timeout")
        self.assertEqual(result["requestID"], REQUEST)

    def test_null_request_id_is_generated_before_dispatch(self):
        calls, runner = self.fake()
        result = adapter.invoke("mirror_status", {"launch": False, "request_id": None}, runner=runner)
        adapter.check_uuid(result["requestID"])
        argv = calls[0][0]
        self.assertEqual(argv[argv.index("--request-id") + 1], result["requestID"])
        self.assertEqual(argv[argv.index("--launch") + 1], "false")

    def test_loading_is_not_changed_into_loaded(self):
        calls, runner = self.fake({"ok": True, "status": "loading", "windows": [{"contentStatus": "loading", "bound": False}]})
        result = adapter.invoke("mirror_open", arguments("open"), runner=runner)
        self.assertEqual(result["status"], "loading")
        self.assertFalse(result["windows"][0]["bound"])
        self.assertEqual(len(calls), 1)

    def test_bounded_and_malformed_responses(self):
        for content in [b"not JSON", b"[]", b'{"ok":true}', b"x" * (adapter.LIMIT + 1)]:
            def runner(argv, **kwargs):
                kwargs["stdout"].write(content)
                return SimpleNamespace(returncode=0)
            result = adapter.invoke("mirror_status", arguments("status"), runner=runner)
            self.assertEqual(result["status"], "invalid_response")

    def test_duplicate_json_fields_nonfinite_and_oversize_rejected(self):
        for raw in [b'{"launch":true,"launch":false}', b'{"x":NaN}', b"{}" * 40000, b'{"x":']:
            with self.assertRaises(adapter.InvalidArguments):
                adapter.load_arguments(raw)

    def test_strict_schema_export_and_nested_objects(self):
        committed = json.loads((SCRIPT.parent.parent / "references/function-tools.json").read_text())
        exported = json.loads(subprocess.check_output([sys.executable, str(SCRIPT), "--tools"]))
        self.assertEqual(committed, exported)
        def check(node):
            if node.get("type") == "object":
                self.assertIs(node["additionalProperties"], False)
                self.assertEqual(set(node["required"]), set(node["properties"]))
                for value in node["properties"].values():
                    check(value)
        for tool in exported:
            self.assertTrue(tool["strict"])
            check(tool["parameters"])

    def test_real_process_preserves_query_as_data(self):
        (ROOT / ".build").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / ".build") as directory:
            folder = Path(directory)
            fixture = folder / "fixture.py"
            fixture.write_text('import json,sys\nprint(json.dumps({"ok":True,"status":"ready","received":sys.argv[1:]}))\n')
            helper = folder / "helper.sh"
            helper.write_text("#!/bin/bash\nexec " + shlex.quote(sys.executable) + " " + shlex.quote(str(fixture)) + ' "$@"\n')
            sentinel = folder / "should-not-exist"
            query = '中文 " $(touch ' + str(sentinel) + ') `pwd` ; & \\ '
            with patch.object(adapter, "HELPER", helper):
                result = adapter.invoke("mirror_find", {**arguments("find"), "query": query})
            self.assertTrue(result["ok"])
            received = result["received"]
            self.assertEqual(received[received.index("--query") + 1], query)
            self.assertFalse(sentinel.exists())

    def test_cli_errors_are_json_and_nonzero(self):
        p = subprocess.run([sys.executable, str(SCRIPT), "mirror_close"], input=b"{}", capture_output=True)
        self.assertEqual(p.returncode, 1)
        self.assertEqual(json.loads(p.stdout)["status"], "invalid_arguments")
        self.assertEqual(p.stderr, b"")

    def test_initial_missing_app_enters_pinned_setup_once(self):
        calls = []
        def runner(argv, **kwargs):
            calls.append(argv)
            response = {"ok": False, "status": "app_not_found"} if len(calls) == 1 else {"ok": True, "status": "manual_open_required", "notarized": False}
            kwargs["stdout"].write(json.dumps(response).encode())
            return SimpleNamespace(returncode=1 if len(calls) == 1 else 0)
        result = adapter.invoke("mirror_status", {"launch": True, "request_id": REQUEST}, runner=runner)
        self.assertEqual(result["status"], "manual_open_required")
        self.assertFalse(result["notarized"])
        self.assertEqual(len(calls), 2)
        self.assertTrue(calls[1][1].endswith("install-preview.sh"))

    def test_follow_up_missing_app_does_not_install(self):
        calls, runner = self.fake({"ok": False, "status": "app_not_found"}, code=1)
        result = adapter.invoke("mirror_status", arguments("status"), runner=runner)
        self.assertEqual(result["status"], "app_not_found")
        self.assertEqual(len(calls), 1)

    def test_explicit_app_selection_does_not_install_another_copy(self):
        calls, runner = self.fake({"ok": False, "status": "app_not_found"}, code=1)
        adapter.invoke("mirror_status", {"launch": True, "request_id": REQUEST}, app="/Applications/Mirror.app", runner=runner)
        self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()
