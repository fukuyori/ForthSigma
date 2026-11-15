#!/usr/bin/env python3
"""Build/test each individually excluded group on Windows, native Linux, or WSL."""
import argparse
import json
from pathlib import Path
import platform
import re
import subprocess
import sys

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--platform', choices=['windows', 'linux'], required=True)
p.add_argument('--groups', nargs='+', default=['float', 'files', 'help', 'tools', 'image', 'graphics', 'audio', 'debug'])
a = p.parse_args()
via_wsl = a.platform == 'linux' and sys.platform == 'win32'
if not via_wsl and ((a.platform == 'linux' and sys.platform != 'linux') or
                    (a.platform == 'windows' and sys.platform != 'win32')):
    p.error('--platform must match the host, except Linux via WSL on Windows')
root = Path.cwd().resolve()
folder = root / '.work/p10' / a.platform
folder.mkdir(parents=True, exist_ok=True)
results = []

def linux(path):
    path = str(Path(path).resolve()).replace('\\', '/')
    return '/mnt/' + path[0].lower() + path[2:]

def command(args, log):
    r = subprocess.run(args, capture_output=True, timeout=600)
    log.write_bytes(r.stdout + r.stderr)
    return r

for group in a.groups:
    flags = [f'-D{group}=false'] + (['-Dtarget=x86_64-linux-musl'] if a.platform == 'linux' else [])
    label = 'no-' + group
    prefix = folder / label
    compile_log = folder / (label + '-tests.log')
    r = command(['zig', 'build', 'test', *flags, '--summary', 'all'], compile_log)
    native_logs = []
    if not via_wsl:
        assert r.returncode == 0, (label, 'tests', str(compile_log))
    else:
        log = compile_log.read_text(errors='replace')
        paths = list(dict.fromkeys(re.findall(r'failed command: "([^"\r\n]+?test)"', log)))
        assert len(paths) == 2 and 'compilation errors' not in log and 'compile test' in log, (label, 'cross-test build', str(compile_log))
        for index, path in enumerate(paths):
            program = Path(path.replace('\\\\', '\\')).resolve()
            native_log = folder / f'{label}-native-test-{index}.log'
            native = command(['wsl', '--cd', linux(root), '--exec', linux(program)], native_log)
            assert native.returncode == 0, (label, 'native tests', str(native_log))
            native_logs.append(str(native_log.relative_to(root)))
    build_log = folder / (label + '-build.log')
    r = command(['zig', 'build', *flags, '--prefix', str(prefix), '--summary', 'all'], build_log)
    assert r.returncode == 0, (label, 'build', str(build_log))
    exe = prefix / 'bin' / ('sigma.exe' if a.platform == 'windows' else 'sigma')
    report = folder / (label + '-integration.json')
    integration_log = folder / (label + '-integration.log')
    if not via_wsl:
        invocation = [sys.executable, 'scripts/verify-p10.py', '--sigma', str(exe), '--disabled', group, '--output', str(report)]
    else:
        invocation = ['wsl', '--cd', linux(root), '--exec', 'python3', 'scripts/verify-p10.py', '--sigma', linux(exe), '--disabled', group, '--output', linux(report)]
    r = command(invocation, integration_log)
    assert r.returncode == 0, (label, 'integration', str(integration_log))
    record = json.loads(report.read_text())
    assert record['complete']
    results.append({'disabled': group, 'unit_tests': True, 'build': True,
                    'integration_cases': len(record['cases']), 'native_test_logs': native_logs})
    (folder / 'matrix.json').write_text(json.dumps({'complete': False, 'platform': a.platform, 'execution': 'wsl' if via_wsl else 'native', 'host': platform.platform(), 'configurations': results}, indent=2) + '\n')
    print(f'{a.platform}: {label} passed ({len(record["cases"])} integration cases)', flush=True)
(folder / 'matrix.json').write_text(json.dumps({'complete': True, 'platform': a.platform, 'execution': 'wsl' if via_wsl else 'native', 'host': platform.platform(), 'configurations': results}, indent=2) + '\n')
