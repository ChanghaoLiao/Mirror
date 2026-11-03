"""Preview installer checks. Network, launch and mock security checks are isolated."""
import json
import os
import shutil
import shlex
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "plugins/mirror/skills/mirror/scripts"
MOCK = r'''#!/bin/bash
case "$(basename "$0")" in
uname) [[ "$1" == -s ]] && echo Darwin || echo arm64;;
sw_vers) echo 14.0;;
PlistBuddy)
case "$2" in
*CFBundleIdentifier*) echo local.mirror.companion;;
*CFBundleShortVersionString*) cat "${@: -1}";;
*CFBundleVersion*) echo 10;;
esac;;
codesign) [[ "$SCENARIO" != signature ]] || exit 1; echo CDHash=1b9e78566932ad8aedc850d476f6b78c9e033a10 >&2;;
curl) [[ "$SCENARIO" != download ]] || exit 22; echo archive > "${@: -1}";;
shasum) [[ "$SCENARIO" != checksum ]] && echo "$PIN  archive" || echo bad;;
unzip) [[ "$SCENARIO" != traversal ]] && echo Mirror.app/Contents/Info.plist || echo ../escape;;
ditto) if [[ "$1" == -x ]]; then mkdir -p "$4/Mirror.app/Contents"; echo 1.0.0 > "$4/Mirror.app/Contents/Info.plist"; else /bin/cp -R "$1" "$2"; fi;;
pgrep) [[ "$SCENARIO" == running ]];;
xattr) if [[ "$1" == -p ]]; then exit 1; fi; echo added >> "$HOME/quarantine-added";;
open) echo requested >> "$HOME/open-requested"; [[ "$SCENARIO" != blocked ]];;
esac
'''


class PreviewTests(unittest.TestCase):
    def execute(self, scenario="success", existing=None, replace=False, published=True, bundle=False):
        with tempfile.TemporaryDirectory(dir=ROOT / ".build", prefix="preview test 中文 ") as directory:
            root = Path(directory)
            helper = root / "scripts"
            shutil.copytree(SCRIPTS, helper)
            mock = root / "mock"
            mock.mkdir()
            source = (helper / "install-preview.sh").read_text()
            for command in ["uname", "sw_vers", "PlistBuddy", "codesign", "curl", "shasum", "unzip", "ditto", "pgrep", "xattr", "open"]:
                file = mock / command
                file.write_text(MOCK)
                file.chmod(0o755)
                for prefix in ["/usr/bin/", "/usr/sbin/", "/usr/libexec/"]:
                    source = source.replace(prefix + command, shlex.quote(str(file)))
            (helper / "install-preview.sh").write_text(source)
            pin = "a" * 64
            config = (helper / "preview.conf").read_text()
            import re
            config = re.sub(r"MIRROR_PREVIEW_SHA256='[^']*'", f"MIRROR_PREVIEW_SHA256='{pin}'", config)
            config = re.sub(r"MIRROR_PREVIEW_AVAILABLE='[^']*'", f"MIRROR_PREVIEW_AVAILABLE='{str(published).lower()}'", config)
            (helper / "preview.conf").write_text(config)
            app = root / "Applications/Mirror.app"
            if existing:
                (app / "Contents").mkdir(parents=True)
                (app / "Contents/Info.plist").write_text(existing)
            args = []
            if bundle:
                local = root / "Full bundle/Mirror.app"
                (local / "Contents").mkdir(parents=True)
                (local / "Contents/Info.plist").write_text("1.0.0")
                args += ["--bundle", str(local)]
            if replace:
                args += ["--replace"]
            process = subprocess.run(["/bin/bash", str(helper / "install-preview.sh"), *args],
                                     env={**os.environ, "HOME": str(root), "SCENARIO": scenario, "PIN": pin}, capture_output=True, text=True)
            result = json.loads(process.stdout)
            version = (app / "Contents/Info.plist").read_text().strip() if app.exists() else None
            return process.returncode, result, version, (root / "quarantine-added").exists(), (root / "open-requested").exists()

    def test_download_install_stops_at_human_first_open(self):
        code, result, version, quarantine, opened = self.execute()
        self.assertEqual(code, 0)
        self.assertEqual(result["status"], "manual_open_required")
        self.assertFalse(result["notarized"])
        self.assertEqual(version, "1.0.0")
        self.assertTrue(quarantine and opened)

    def test_gatekeeper_rejection_is_not_reported_as_ready(self):
        code, result, version, quarantine, opened = self.execute("blocked")
        self.assertEqual(code, 0)
        self.assertEqual(result["status"], "manual_open_required")
        self.assertTrue(quarantine and opened)

    def test_full_bundle_works_without_published_download(self):
        code, result, version, quarantine, _ = self.execute(published=False, bundle=True)
        self.assertEqual(code, 0)
        self.assertEqual(version, "1.0.0")
        self.assertTrue(quarantine)

    def test_identical_app_reused(self):
        code, result, version, _, _ = self.execute(existing="1.0.0")
        self.assertEqual(code, 0)
        self.assertEqual(version, "1.0.0")

    def test_other_version_requires_confirmation(self):
        code, result, version, _, opened = self.execute(existing="0.3.1")
        self.assertNotEqual(code, 0)
        self.assertEqual(result["status"], "replacement_confirmation_required")
        self.assertEqual(version, "0.3.1")
        self.assertFalse(opened)

    def test_confirmed_upgrade_keeps_workflow(self):
        code, result, version, quarantine, _ = self.execute(existing="0.3.1", replace=True)
        self.assertEqual(code, 0)
        self.assertEqual(version, "1.0.0")
        self.assertTrue(quarantine)

    def test_failures_leave_existing_version_untouched(self):
        for scenario, status in [("download", "download_failed"), ("checksum", "checksum_failed"), ("signature", "signature_failed"), ("traversal", "invalid_archive"), ("running", "quit_mirror_required")]:
            with self.subTest(scenario=scenario):
                code, result, version, _, opened = self.execute(scenario, existing="0.3.1", replace=True)
                self.assertNotEqual(code, 0)
                self.assertEqual(result["status"], status)
                self.assertEqual(version, "0.3.1")
                self.assertFalse(opened)

    def test_unpublished_channel_does_not_download(self):
        code, result, version, _, opened = self.execute(published=False)
        self.assertNotEqual(code, 0)
        self.assertEqual(result["status"], "release_unavailable")
        self.assertIsNone(version)
        self.assertFalse(opened)


if __name__ == "__main__":
    unittest.main()
