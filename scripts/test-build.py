#!/usr/bin/env python3
"""Exercise packaging failure boundaries without signing, launching, or replacing an app."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['BUILD_TEST_LOG'], 'a') as log:
    log.write(json.dumps([name] + args) + '\n')
if name == 'osascript':
    counter = pathlib.Path(os.environ['BUILD_TEST_COUNT'])
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    if os.environ.get('BUILD_TEST_CHECK_ERROR') == '1':
        sys.exit(1)
    if os.environ.get('BUILD_TEST_CHECK_INVALID') == '1':
        print('unknown')
    else:
        print('true' if str(count) == os.environ.get('BUILD_TEST_RUNNING_CHECK') else 'false')
elif name == 'codesign':
    if '--force' in args and os.environ.get('BUILD_TEST_SIGN_ERROR') == '1':
        sys.exit(1)
    if '--test-requirement' in args and os.environ.get('BUILD_TEST_DEVELOPER_ID') != '1':
        sys.exit(1)
    if '--verify' in args and os.environ.get('BUILD_TEST_VERIFY_ERROR') == '1':
        sys.exit(1)
elif name == 'ditto':
    if '-c' in args:
        pathlib.Path(args[-1]).write_text('mock archive')
    else:
        shutil.copytree(args[-2], args[-1], dirs_exist_ok=True)
'''


class BuildTests(unittest.TestCase):
    def setUp(self):
        (ROOT / '.build').mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='build-tests.', dir=ROOT / '.build')
        self.root = Path(self.temporary.name)
        scripts = self.root / 'scripts'
        scripts.mkdir()
        shutil.copy2(ROOT / 'scripts/build.sh', scripts / 'build.sh')
        shutil.copy2(ROOT / 'scripts/Info.plist', scripts / 'Info.plist')
        (scripts / 'swift.sh').write_text(
            'scratch=.build\nprintf "%s\\n" "$@" > swift-args\n'
            'while [ "$#" -gt 0 ]; do\n'
            '  if [ "$1" = --scratch-path ]; then scratch="$2"; shift; fi\n'
            '  shift\ndone\n'
            'mkdir -p "$scratch/release"\nprintf mock-binary > "$scratch/release/Mirror"\n'
            'printf invoked > swift-was-invoked\n')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for command in ['osascript', 'codesign', 'xattr', 'ditto']:
            tool = self.bin / command
            tool.write_text(MOCK)
            tool.chmod(0o755)
        self.output = self.root / "artifact output's"
        self.target = self.output / 'Mirror.app' / 'Contents' / 'MacOS' / 'Mirror'
        self.target.parent.mkdir(parents=True)
        self.target.write_text('existing app must survive failed build')
        self.log = self.root / 'calls.jsonl'
        self.env = os.environ.copy()
        for name in list(self.env):
            if name.startswith(('MIRROR_', 'BUILD_TEST_')):
                self.env.pop(name)
        self.env.update({
            'PATH': str(self.bin) + os.pathsep + self.env['PATH'],
            'MIRROR_DIST_DIR': str(self.output),
            'BUILD_TEST_LOG': str(self.log),
            'BUILD_TEST_COUNT': str(self.root / 'check-count'),
        })

    def tearDown(self):
        self.temporary.cleanup()

    def build(self, **environment):
        return subprocess.run(
            ['bash', str(self.root / 'scripts/build.sh')], cwd=self.root,
            env=self.env | environment, text=True, capture_output=True, timeout=20)

    def calls(self, name):
        if not self.log.exists():
            return []
        return [row for row in map(json.loads, self.log.read_text().splitlines()) if row[0] == name]

    def assert_preserved(self, result):
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.target.read_text(), 'existing app must survive failed build')
        self.assertFalse((self.output / 'Mirror.zip').exists())
        self.assertEqual(self.calls('ditto'), [])
        self.assertEqual(list((self.root / '.build').glob('package.*')), [])

    def test_running_target_stops_before_compilation(self):
        result = self.build(BUILD_TEST_RUNNING_CHECK='1')
        self.assert_preserved(result)
        self.assertFalse((self.root / 'swift-was-invoked').exists())
        self.assertIn('MIRROR_DIST_DIR', result.stderr)

    def test_app_started_during_compilation_is_not_overwritten(self):
        self.assert_preserved(self.build(BUILD_TEST_RUNNING_CHECK='2'))
        self.assertTrue((self.root / 'swift-was-invoked').exists())

    def test_process_check_failure_is_not_treated_as_stopped(self):
        self.assert_preserved(self.build(BUILD_TEST_CHECK_ERROR='1'))

    def test_unknown_process_check_is_not_treated_as_stopped(self):
        self.assert_preserved(self.build(BUILD_TEST_CHECK_INVALID='1'))

    def test_release_rejects_implicit_adhoc(self):
        self.assert_preserved(self.build(MIRROR_RELEASE='1'))
        self.assertFalse((self.root / 'swift-was-invoked').exists())

    def test_release_rejects_explicit_adhoc(self):
        self.assert_preserved(self.build(MIRROR_RELEASE='1', MIRROR_SIGNING_IDENTITY='-'))

    def test_invalid_mode_is_not_silently_preview(self):
        self.assert_preserved(self.build(MIRROR_RELEASE='true'))

    def test_signing_failure_preserves_previous_app(self):
        self.assert_preserved(self.build(BUILD_TEST_SIGN_ERROR='1'))

    def test_signature_verification_failure_preserves_previous_app(self):
        self.assert_preserved(self.build(BUILD_TEST_VERIFY_ERROR='1'))

    def test_release_requires_verified_certificate_not_its_name(self):
        self.assert_preserved(self.build(
            MIRROR_RELEASE='1', MIRROR_SIGNING_IDENTITY='Developer ID Application: Pretend'))
        self.assertTrue(any('--test-requirement' in call for call in self.calls('codesign')))

    def test_local_preview_retains_default_adhoc_interface(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.target.read_text(), 'mock-binary')
        self.assertTrue((self.output / 'Mirror.zip').exists())
        self.assertIn('ad-hoc signed', result.stdout)
        sign = next(call for call in self.calls('codesign') if '--force' in call)
        self.assertEqual(sign[sign.index('--sign') + 1], '-')
        self.assertEqual(len(self.calls('osascript')), 2)

    def test_configured_local_signer_is_passed_as_one_argument(self):
        identity = 'Local Mirror signing identity'
        result = self.build(MIRROR_SIGNING_IDENTITY=identity)
        self.assertEqual(result.returncode, 0, result.stderr)
        sign = next(call for call in self.calls('codesign') if '--force' in call)
        self.assertEqual(sign[sign.index('--sign') + 1], identity)
        self.assertNotIn('--timestamp', sign)

    def test_isolated_build_path_does_not_use_or_remove_previous_binary(self):
        previous = self.root / '.build' / 'release' / 'Mirror'
        previous.parent.mkdir(parents=True)
        previous.write_text('previous build')
        scratch = self.root / 'isolated build'
        result = self.build(MIRROR_BUILD_PATH=str(scratch))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(previous.read_text(), 'previous build')
        self.assertEqual((scratch / 'release' / 'Mirror').read_text(), 'mock-binary')
        self.assertEqual(self.target.read_text(), 'mock-binary')
        self.assertIn(str(scratch), (self.root / 'swift-args').read_text().splitlines())

    def test_developer_id_release_requires_runtime_timestamp_and_certificate(self):
        result = self.build(MIRROR_RELEASE='1', MIRROR_SIGNING_IDENTITY='test identity',
                            BUILD_TEST_DEVELOPER_ID='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        sign = next(call for call in self.calls('codesign') if '--force' in call)
        self.assertIn('--timestamp', sign)
        self.assertEqual(sign[sign.index('--options') + 1], 'runtime')
        self.assertTrue(any('--test-requirement' in call for call in self.calls('codesign')))
        self.assertIn('Notarization is a separate release step', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
