#!/usr/bin/env python3
"""Check the hotplug recorder's preflight, missing-action and unresponsive-VM paths.
Uses only owned Sigma windows; does not disconnect or reconfigure monitors.
"""
import argparse
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time

from linux_x11_test_support import require_linux

require_linux()
ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma')
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args()
if not __debug__:
    raise SystemExit('recorder checks require assertions enabled')
args.output_dir.mkdir(parents=True, exist_ok=False)
recorder = ROOT / 'tests/scripts/verify-linux-display-hotplug.py'
results = []


def interrupted(signum, frame):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    raise SystemExit(f'interrupted by signal {signum}')


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGHUP, interrupted)
for case in ('preflight', 'no-operation', 'frozen-sigma'):
    folder = args.output_dir / case
    command = [sys.executable, str(recorder), '--sigma', str(args.sigma.resolve()),
               '--output-dir', str(folder.resolve()), '--timeout', '10']
    if case == 'preflight':
        command.append('--preflight')
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    stopped_pid = None
    prefix = b''
    try:
        if case == 'frozen-sigma':
            deadline = time.monotonic() + 10
            while b'READY:' not in prefix:
                remaining = deadline - time.monotonic()
                assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], 'recorder readiness deadline'
                data = os.read(process.stdout.fileno(), 4096)
                assert data, 'recorder exited before readiness'
                prefix += data
            children = Path(f'/proc/{process.pid}/task/{process.pid}/children').read_text().split()
            assert len(children) == 1, children
            stopped_pid = int(children[0])
            executable = Path(f'/proc/{stopped_pid}/cmdline').read_bytes().split(b'\0')[0]
            assert executable.decode() == str(args.sigma.resolve()), executable
            os.kill(stopped_pid, signal.SIGSTOP)
        stdout, stderr = process.communicate(timeout=30)
    finally:
        if stopped_pid is not None:
            try:
                os.kill(stopped_pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
        if process.poll() is None:
            process.terminate()
            try:
                process.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=5)
        if process.stdout is not None:
            process.stdout.close()
        if process.stderr is not None:
            process.stderr.close()
    report = json.loads((folder / 'report.json').read_text())
    expected = {'preflight': 'preflight-pass', 'no-operation': 'incomplete', 'frozen-sigma': 'fail'}[case]
    assert report['status'] == expected and not report['physical_hotplug_tested'], (case, report)
    assert (process.returncode == 0) == (case == 'preflight'), (case, process.returncode)
    if case == 'no-operation':
        assert 'AwaitingHardware' in report['error'], report['error']
    if case == 'frozen-sigma':
        assert 'TimeoutError' in report['error'], report['error']
        try:
            os.kill(stopped_pid, 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError('owned frozen Sigma survived recorder cleanup')
    results.append(dict(case=case, status='pass', recorder_status=report['status'],
                        child_returncode=process.returncode,
                        stdout=(prefix + stdout).decode('utf-8', 'replace'),
                        stderr=stderr.decode('utf-8', 'replace')))
    print('pass', case, flush=True)
for case in ('preflight', 'no-operation'):
    invalid_confirmation = args.output_dir / f'invalid-{case}-confirmation.json'
    result = subprocess.run([sys.executable, str(recorder), '--confirm-report', str(args.output_dir / case / 'report.json'),
                             '--operator-statement', 'synthetic negative test; no physical action occurred',
                             '--confirmation-output', str(invalid_confirmation)], capture_output=True, text=True, timeout=5)
    assert result.returncode != 0 and not invalid_confirmation.exists()
    assert 'not an observed completed sequence' in result.stderr, result.stderr
    results.append(dict(case=f'reject-{case}-confirmation', status='pass', child_returncode=result.returncode))
    print(f'pass reject-{case}-confirmation', flush=True)
optimized_confirmation = args.output_dir / 'invalid-optimized-confirmation.json'
result = subprocess.run([sys.executable, '-O', str(recorder), '--confirm-report', str(args.output_dir / 'no-operation/report.json'),
                         '--operator-statement', 'synthetic negative test; no physical action occurred',
                         '--confirmation-output', str(optimized_confirmation)], capture_output=True, text=True, timeout=5)
assert result.returncode != 0 and not optimized_confirmation.exists()
assert 'requires assertions enabled' in result.stderr, result.stderr
results.append(dict(case='reject-optimized-confirmation', status='pass', child_returncode=result.returncode))
print('pass reject-optimized-confirmation', flush=True)
(args.output_dir / 'checks.json').write_text(json.dumps(dict(status='pass', cases=results), indent=2) + '\n')
