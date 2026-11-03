#!/usr/bin/env python3
"""Test the shipped archive in an empty, isolated user/skill directory."""
import hashlib
import json
import os
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "dist/Mirror-Agent-Toolkit-1.0.0.zip"


class DownloadedToolkitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not ARCHIVE.is_file():
            raise RuntimeError("Package the toolkit before onboarding tests")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="新用户 downloads ' ", dir=ROOT / ".build")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "empty home"
        self.home.mkdir()
        with zipfile.ZipFile(ARCHIVE) as archive:
            self.assertIsNone(archive.testzip())
            archive.extractall(self.root)
        self.package = self.root / "Mirror-Agent-Toolkit"
        self.source = self.package / "skills"
        self.script = self.source / "mirror/scripts/register.sh"
        self.target = self.home / "Agent skills 中文"
        self.env = {"HOME": str(self.home), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"}

    def register(self, target=None):
        process = subprocess.run(["/bin/bash", str(self.script), "--target", str(target or self.target)],
                                 env=self.env, cwd=self.home, capture_output=True, text=True)
        self.assertEqual(process.stderr, "")
        return process.returncode, json.loads(process.stdout)

    def test_fresh_registration_from_path_with_spaces_chinese_and_quote(self):
        code, result = self.register()
        self.assertEqual(code, 0, result)
        self.assertEqual(result["status"], "registered")
        for name in ["mirror", "mirror-setup"]:
            self.assertTrue((self.target / name / "SKILL.md").is_file())
        self.assertFalse((self.home / "Applications").exists())
        self.assertFalse(list(self.target.glob(".mirror-*")))
        # Installed files no longer rely on the original extracted directory.
        shutil.rmtree(self.package)
        process = subprocess.run(["/bin/bash", str(self.target / "mirror/scripts/mirror.sh"), "--help"], env=self.env, capture_output=True, text=True)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(json.loads(process.stdout)["status"], "help")

    def test_repeat_registration_reuses_without_changing_files(self):
        self.register()
        before = {p.relative_to(self.target): (p.stat().st_mtime_ns, p.read_bytes()) for p in self.target.rglob("*") if p.is_file()}
        code, result = self.register()
        self.assertEqual(code, 0, result)
        self.assertEqual(result["status"], "reused")
        after = {p.relative_to(self.target): (p.stat().st_mtime_ns, p.read_bytes()) for p in self.target.rglob("*") if p.is_file()}
        self.assertEqual(before, after)

    def test_existing_modified_skill_is_preserved_without_partial_install(self):
        existing = self.target / "mirror-setup"
        existing.mkdir(parents=True)
        (existing / "SKILL.md").write_text("user customized skill")
        code, result = self.register()
        self.assertNotEqual(code, 0)
        self.assertEqual(result["status"], "skill_conflict")
        self.assertEqual((existing / "SKILL.md").read_text(), "user customized skill")
        self.assertFalse((self.target / "mirror").exists())
        self.assertFalse(list(self.target.glob(".mirror-*")))

    def test_symlink_target_and_existing_skill_refused(self):
        destination = self.home / "destination"
        destination.mkdir()
        link = self.home / "linked"
        link.symlink_to(destination, target_is_directory=True)
        code, result = self.register(link / "nested")
        self.assertNotEqual(code, 0)
        self.assertEqual(result["status"], "unsafe_target")
        self.assertFalse(list(destination.iterdir()))
        self.target.mkdir()
        (self.target / "mirror").symlink_to(destination, target_is_directory=True)
        code, result = self.register()
        self.assertEqual(result["status"], "skill_conflict")
        self.assertTrue((self.target / "mirror").is_symlink())

    def test_existing_registration_lock_is_not_deleted(self):
        lock = self.target / ".mirror-skill-install.lock"
        lock.mkdir(parents=True)
        code, result = self.register()
        self.assertNotEqual(code, 0)
        self.assertEqual(result["status"], "registration_in_progress")
        self.assertTrue(lock.exists())
        self.assertFalse((self.target / "mirror").exists())

    def test_missing_companion_fails_before_install(self):
        shutil.rmtree(self.source / "mirror-setup")
        code, result = self.register()
        self.assertNotEqual(code, 0)
        self.assertEqual(result["status"], "incomplete_package")
        self.assertFalse(self.target.exists())

    def test_missing_desktop_is_reported_without_download_or_install(self):
        # Real shipped installer + real platform check; no mocked release pins.
        process = subprocess.run(["/bin/bash", str(self.source / "mirror/scripts/install.sh")], env=self.env,
                                 cwd=self.home, capture_output=True, text=True)
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual(json.loads(process.stdout)["status"], "release_unavailable")
        self.assertFalse((self.home / "Applications").exists())

    def test_manifest_integrity_and_no_machine_specific_configuration(self):
        manifest = json.loads((self.package / "manifest.json").read_text())
        for name, digest in manifest["file_sha256"].items():
            data = (self.package / name).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), digest)
            self.assertNotIn(b"/Users/", data)
        self.assertEqual(len(json.loads((self.source / "mirror/references/function-tools.json").read_text())), 15)

    def test_installed_adapter_uses_only_standard_library(self):
        self.register()
        process = subprocess.run([sys.executable, "-I", "-S", str(self.target / "mirror/scripts/functions.py"), "--tools"],
                                 env=self.env, cwd=self.home, capture_output=True, text=True)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertEqual(len(json.loads(process.stdout)), 15)

    def test_installed_helper_can_read_an_existing_native_app(self):
        app = os.environ.get("MIRROR_TEST_APP")
        if not app:
            self.skipTest("Set MIRROR_TEST_APP to a confirmed running app for a read-only native check")
        self.register()
        shutil.rmtree(self.package)
        process = subprocess.run(["/bin/bash", str(self.target / "mirror/scripts/mirror.sh"), "status", "--launch", "false", "--app", app],
                                 env=self.env, cwd=self.home, capture_output=True, text=True)
        self.assertEqual(process.returncode, 0, "Native app must already be running for this optional check")
        result = json.loads(process.stdout)
        self.assertTrue(result["ok"])
        self.assertEqual(result["status"], "ready")
        self.assertIs(type(result["revision"]), int)

    def test_codex_really_discovers_installed_skills_without_a_model_call(self):
        cli = shutil.which("codex")
        if not cli:
            self.skipTest("Local Codex CLI is unavailable; host discovery is not certified")
        project = self.home / "new project"
        project.mkdir()
        subprocess.run(["/usr/bin/git", "init", "--quiet", str(project)], env=self.env, check=True, capture_output=True)
        target = project / ".agents/skills"
        code, result = self.register(target)
        self.assertEqual(code, 0, result)
        codex_home = self.home / ".codex"
        codex_home.mkdir()
        server = subprocess.Popen([cli, "app-server", "--stdio", "-c", "analytics.enabled=false"],
                                  cwd=project, env={**self.env, "CODEX_HOME": str(codex_home)},
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        pending = b""

        def request(number, method, params):
            nonlocal pending
            server.stdin.write((json.dumps({"id": number, "method": method, "params": params}) + "\n").encode())
            server.stdin.flush()
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    message = json.loads(line)
                    if message.get("id") == number:
                        self.assertNotIn("error", message)
                        return message["result"]
                ready, _, _ = select.select([server.stdout], [], [], .25)
                if ready:
                    chunk = os.read(server.stdout.fileno(), 65536)
                    self.assertTrue(chunk, "App Server stopped before its response")
                    pending += chunk
            self.fail("App Server did not finish local skill discovery")

        try:
            request(1, "initialize", {"clientInfo": {"name": "mirror-onboarding-test", "version": "1.0.0"}})
            server.stdin.write(b'{"method":"initialized"}\n')
            server.stdin.flush()
            listing = request(2, "skills/list", {"cwds": [str(project)], "forceReload": True})
            rows = [item for item in listing["data"] if Path(item["cwd"]) == project]
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0].get("errors", []), [])
            found = {skill["name"]: skill for skill in rows[0]["skills"] if skill["name"] in ("mirror", "mirror-setup")}
            self.assertEqual(set(found), {"mirror", "mirror-setup"})
            for skill in found.values():
                self.assertTrue(Path(skill["path"]).resolve().is_relative_to(target))
            self.assertFalse(list(codex_home.glob("sessions/**/*")), "No conversation should be created")
        finally:
            server.stdin.close()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.terminate()
                try:
                    server.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait(timeout=3)
            server.stdout.close()


if __name__ == "__main__":
    unittest.main()
