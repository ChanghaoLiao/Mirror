"""Installer integration checks with fake Apple/network tools; never touches real Applications."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'plugins/mirror/skills/mirror/scripts'
MOCK = '''#!/bin/bash
case "$(basename "$0")" in
uname) [[ "$1" == -s ]] && echo Darwin || echo arm64;;
sw_vers) echo 14.0;;
PlistBuddy) [[ "$2" == *CFBundleIdentifier* ]] && echo local.mirror.companion || cat "${@: -1}";;
codesign) [[ "$SCENARIO" != signature ]] || exit 1; echo TeamIdentifier=ABCDEFGHIJ >&2;;
spctl) [[ "$SCENARIO" != notarization ]] || exit 1; echo 'source=Notarized Developer ID' >&2;;
curl) [[ "$SCENARIO" != download ]] || exit 22; echo archive > "${@: -1}";;
shasum) [[ "$SCENARIO" != checksum ]] && echo "$PIN  archive" || echo 'bad archive';;
unzip) [[ "$SCENARIO" != traversal ]] && echo Mirror.app/Contents/Info.plist || echo ../escape;;
ditto) mkdir -p "$4/Mirror.app/Contents"; echo 1.0.0 > "$4/Mirror.app/Contents/Info.plist";;
pgrep) [[ "$SCENARIO" == running ]];;
open) echo opened >> "$HOME/launches";;
esac
'''


class InstallerTests(unittest.TestCase):
    def execute(self, scenario, existing=None, replace=False, published=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = root / 'scripts'
            shutil.copytree(SCRIPTS, helper)
            mock = root / 'mock'
            mock.mkdir()
            source = (helper / 'install.sh').read_text()
            for command in ('uname', 'sw_vers', 'PlistBuddy', 'codesign', 'spctl', 'curl', 'shasum', 'unzip', 'ditto', 'pgrep', 'open'):
                file = mock / command
                file.write_text(MOCK)
                file.chmod(0o755)
                for prefix in ('/usr/bin/', '/usr/sbin/', '/usr/libexec/'):
                    source = source.replace(prefix + command, str(file))
            (helper / 'install.sh').write_text(source)
            pin = 'a' * 64
            (helper / 'release.conf').write_text(f"MIRROR_INSTALL_VERSION=1.0.0\nMIRROR_INSTALL_PUBLISHED={str(published).lower()}\nMIRROR_INSTALL_TEAM=ABCDEFGHIJ\nMIRROR_INSTALL_SHA256={pin}\n")
            app = root / 'Applications/Mirror.app'
            if existing:
                (app / 'Contents').mkdir(parents=True)
                (app / 'Contents/Info.plist').write_text(existing)
            result = subprocess.run(['bash', str(helper / 'install.sh'), *(['--replace'] if replace else [])],
                                    env={**os.environ, 'HOME': str(root), 'SCENARIO': scenario, 'PIN': pin},
                                    capture_output=True, text=True)
            content = (app / 'Contents/Info.plist').read_text().strip() if app.exists() else None
            return result.returncode, result.stdout, content, (root / 'launches').exists()

    def test_first_install_and_reuse(self):
        for existing, status in ((None, 'installed'), ('1.0.0', 'reused'), ('1.2.0', 'reused')):
            code, output, _, launched = self.execute('success', existing)
            self.assertEqual(code, 0, output)
            self.assertIn(status, output)
            self.assertTrue(launched)

    def test_old_version_requires_confirmation(self):
        code, output, version, launched = self.execute('success', '0.3.1')
        self.assertNotEqual(code, 0)
        self.assertIn('replacement_confirmation_required', output)
        self.assertEqual(version, '0.3.1')
        self.assertFalse(launched)

    def test_confirmed_upgrade(self):
        code, output, version, launched = self.execute('success', '0.3.1', True)
        self.assertEqual(code, 0, output)
        self.assertEqual(version, '1.0.0')
        self.assertTrue(launched)

    def test_failures_preserve_old_app(self):
        for scenario, status in [('download', 'download_failed'), ('checksum', 'checksum_failed'),
                                 ('signature', 'signature_or_notarization_failed'),
                                 ('notarization', 'signature_or_notarization_failed'),
                                 ('traversal', 'invalid_archive'), ('running', 'quit_mirror_required')]:
            with self.subTest(scenario=scenario):
                code, output, version, launched = self.execute(scenario, '0.3.1', True)
                self.assertNotEqual(code, 0)
                self.assertIn(status, output)
                self.assertEqual(version, '0.3.1')
                self.assertFalse(launched)

    def test_unpublished_release(self):
        code, output, version, launched = self.execute('success', published=False)
        self.assertNotEqual(code, 0)
        self.assertIn('release_unavailable', output)
        self.assertIsNone(version)
        self.assertFalse(launched)


if __name__ == '__main__':
    unittest.main()
