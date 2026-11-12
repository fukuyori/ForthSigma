#!/usr/bin/env python3
"""Exercise the macOS packaging flow with local stand-ins for signing/build tools."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
MOCK = r'''import json, os
from pathlib import Path
import shutil, sys
import xml.etree.ElementTree as ET
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['MOCK_LOG'], 'a') as log:
    log.write(json.dumps([name, *args]) + '\n')
def option(key):
    return args[args.index(key) + 1]
if name == 'zig':
    binary = Path(option('--prefix')) / 'bin/sigma'
    binary.parent.mkdir(parents=True, exist_ok=True)
    binary.write_text('#!/bin/bash\n'
                      '[[ "$#" == 2 && "$1" == -e && "$2" == "1 2 + . BYE" ]] || exit 9\n'
                      'printf "3 "\nexit "${MOCK_SMOKE_EXIT:-0}"\n')
    binary.chmod(0o755)
elif name == 'lipo':
    if args[0] == '-archs':
        print('arm64 x86_64')
    else:
        shutil.copy2(args[1], option('-output'))
elif name == 'uname':
    print('arm64')
elif name == 'security':
    print('1) ABC "Developer ID Application: Test"')
    print('2) DEF "Developer ID Installer: Test"')
elif name == 'pkgbuild':
    if os.environ.get('MOCK_PKG_FAIL'):
        sys.exit(1)
    root = Path(option('--root'))
    files = sorted(str(p.relative_to(root)) for p in root.rglob('*') if p.is_file())
    assert (root / 'usr/local/bin/sigma').stat().st_mode & 0o777 == 0o755
    Path(args[-1]).write_text(json.dumps({'files': files, 'version': option('--version')}))
elif name == 'productbuild':
    distribution = ET.parse(option('--distribution')).getroot()
    ref = distribution.find('pkg-ref')
    component = Path(option('--package-path')) / ref.text
    manifest = json.loads(component.read_text())
    manifest['architectures'] = distribution.find('options').attrib['hostArchitectures']
    assert manifest['version'] == ref.attrib['version']
    Path(args[-1]).write_text(json.dumps(manifest))
elif name == 'xcrun':
    if args[:2] == ['notarytool', 'history']:
        if os.environ.get('MOCK_HISTORY_FAIL') or option('--keychain-profile') != 'sigma':
            print('Network or authentication error', file=sys.stderr)
            sys.exit(1)
    elif args[:2] == ['notarytool', 'submit']:
        print(json.dumps({'id': 'test-submission', 'status': os.environ.get('MOCK_NOTARY_STATUS', 'Accepted')}))
    elif args[:2] == ['notarytool', 'log']:
        print('Test rejection log')
    elif args[:2] != ['stapler', 'staple']:
        sys.exit('Unexpected xcrun call')
'''


class PackageTests(unittest.TestCase):
    def setUp(self):
        workspace = ROOT / '.work'
        workspace.mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(prefix='pkg-test-', dir=workspace)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / 'repository with spaces'
        (self.root / 'scripts').mkdir(parents=True)
        (self.root / 'docs').mkdir()
        for filename in ['scripts/sign-and-notarize-macos.sh', 'VERSION', 'LICENSE',
                         'THIRD_PARTY_NOTICES.md', 'README.md', 'docs/USER_MANUAL.md']:
            shutil.copy2(ROOT / filename, self.root / filename)
        self.script = self.root / 'scripts/sign-and-notarize-macos.sh'
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        mock = self.tools / 'mock'
        mock.write_text(f'#!{sys.executable}\n' + MOCK)
        mock.chmod(0o755)
        for name in ['zig', 'lipo', 'uname', 'security', 'pkgbuild', 'productbuild',
                     'codesign', 'pkgutil', 'xattr', 'xcrun', 'spctl']:
            (self.tools / name).symlink_to(mock.name)
        self.log = self.root / 'calls.jsonl'
        self.tmp = self.root / 'tmp'
        self.tmp.mkdir()
        self.env = {key: value for key, value in os.environ.items() if not key.startswith('SIGMA_')}
        self.env.update(PATH=str(self.tools) + os.pathsep + os.environ['PATH'],
                        MOCK_LOG=str(self.log), TMPDIR=str(self.tmp))

    def run_script(self, *args, cwd=None, **env):
        return subprocess.run(['bash', str(self.script), *args], cwd=cwd or self.root,
                              env={**self.env, **env}, text=True, capture_output=True, timeout=30)

    def calls(self, name=None):
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return [call for call in calls if name is None or call[0] == name]

    def test_signed_packages_for_both_variants(self):
        result = self.run_script('--variant', 'both', '--skip-notarize')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        packages = sorted((self.root / 'dist/pkg').glob('*.pkg'))
        self.assertEqual(len(packages), 2)
        for package in packages:
            manifest = json.loads(package.read_text())
            self.assertEqual(manifest['architectures'], 'arm64,x86_64')
            self.assertEqual(manifest['files'], [
                'usr/local/bin/sigma', 'usr/local/share/doc/sigma/LICENSE',
                'usr/local/share/doc/sigma/README.md',
                'usr/local/share/doc/sigma/THIRD_PARTY_NOTICES.md',
                'usr/local/share/doc/sigma/USER_MANUAL.md'])
        self.assertEqual(len(self.calls('zig')), 4)
        self.assertEqual(len(self.calls('codesign')), 4)
        self.assertTrue(all('--timestamp' in call for call in self.calls('productbuild')))
        self.assertEqual(self.calls('xcrun'), [])
        self.assertEqual(list(self.tmp.iterdir()), [])

    def test_notarization_and_gatekeeper(self):
        result = self.run_script('--arch', 'arm64')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        calls = self.calls('xcrun')
        self.assertEqual([call[1:3] for call in calls], [
            ['notarytool', 'history'], ['notarytool', 'history'],
            ['notarytool', 'submit'], ['stapler', 'staple']])
        self.assertIn('sigma', calls[2])
        self.assertEqual(len(self.calls('spctl')), 1)

    def test_profile_probe_failures_stop_before_build(self):
        result = self.run_script(MOCK_HISTORY_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no notarization credentials', result.stderr)
        self.assertEqual(self.calls('zig'), [])
        self.assertEqual(len(self.calls('xcrun')), 3)

    def test_rejected_submission_fetches_log_without_stapling(self):
        result = self.run_script('--profile', 'test-profile', MOCK_NOTARY_STATUS='Invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([call[1:3] for call in self.calls('xcrun')], [
            ['notarytool', 'submit'], ['notarytool', 'log']])
        self.assertEqual(self.calls('spctl'), [])

    def test_missing_option_values_fail_clearly(self):
        for option in ['--version', '--arch', '--variant', '--identity', '--installer-identity',
                       '--profile', '--apple-id', '--team-id', '--password']:
            for tail in [[], [''], ['--skip-notarize']]:
                with self.subTest(option=option, tail=tail):
                    result = self.run_script(option, *tail)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(f'{option} needs a value', result.stderr)
        self.assertEqual(self.calls(), [])

    def test_nonzero_smoke_exit_prevents_packaging_even_with_matching_output(self):
        result = self.run_script('--skip-notarize', MOCK_SMOKE_EXIT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('signed binary does not run', result.stderr)
        self.assertEqual(self.calls('pkgbuild'), [])

    def test_package_failure_removes_staging_root(self):
        result = self.run_script('--skip-notarize', MOCK_PKG_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls('pkgbuild')), 1)
        self.assertEqual(self.calls('productbuild'), [])
        self.assertEqual(list(self.tmp.iterdir()), [])

    def test_other_architecture_skips_execution_check(self):
        result = self.run_script('--arch', 'x86_64', '--skip-notarize', MOCK_SMOKE_EXIT='1')
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn('Skipping execution check', result.stdout)
        self.assertEqual(len(self.calls('zig')), 1)

    def test_help_from_scripts_directory(self):
        result = subprocess.run(['bash', './sign-and-notarize-macos.sh', '--help'],
                                cwd=self.script.parent, env=self.env,
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--skip-notarize', result.stdout)
        self.assertIn('dist/pkg/sigma-', result.stdout)


if __name__ == '__main__':
    unittest.main()
