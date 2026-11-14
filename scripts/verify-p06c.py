#!/usr/bin/env python3
"""Verify P06c against the recorded whole-subphase reference and native PTY contracts."""
import argparse
import fcntl
import json
import os
import pathlib
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time

p = argparse.ArgumentParser()
p.add_argument('--sigma', type=pathlib.Path, default=pathlib.Path('zig-out/bin/sigma'))
p.add_argument('--gforth-build', type=pathlib.Path)
p.add_argument('--reference', type=pathlib.Path, default=pathlib.Path('.work/p06c-check/spec-probes.json'))
a = p.parse_args()
sigma = str(a.sigma.resolve())
if not a.reference.exists():
    if a.gforth_build is None:
        p.error('reference report missing; provide --gforth-build to run the subphase probe first')
    subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('probe-p06c.py')), '--gforth-build', str(a.gforth_build)], check=True)
reference = json.loads(a.reference.read_text())
results = []
for case in reference['cases']:
    if 'timeout' in case or case['exit'] != 0:
        continue
    env = dict(os.environ)
    if case['case'].startswith('form-pipe:'):
        env.pop('COLUMNS', None)
        env.pop('LINES', None)
        if "120" in case['case']:
            env.update(COLUMNS='120', LINES='50')
        elif "'0'" in case['case']:
            env.update(COLUMNS='0', LINES='0')
        elif 'bad' in case['case']:
            env.update(COLUMNS='bad', LINES='-2')
    run = subprocess.run([sigma, '--max-steps', '100000', '-e', case['source'] + ' DEPTH . BYE'], input=bytes.fromhex(case.get('input_hex', '')), capture_output=True, timeout=10, env=env)
    assert run.returncode == 0 and run.stdout.hex() == case['stdout_hex'], (case['case'], run.returncode, run.stdout, run.stderr, bytes.fromhex(case['stdout_hex']))
    results.append(case['case'])

def native_pty(name, body, action=None, raw_wait=False):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 41, 113, 0, 0))
    before = termios.tcgetattr(slave)
    process = subprocess.Popen([sigma, '--max-steps', '100000', '-e', '." READY" ' + body + ' BYE'], stdin=slave, stdout=slave, stderr=slave, env=dict(os.environ, TERM='xterm-256color'))
    output = b''
    sent = False
    deadline = time.monotonic() + 10
    try:
        while process.poll() is None:
            assert time.monotonic() < deadline, (name, 'timeout', output)
            if select.select([master], [], [], 0.02)[0]:
                try:
                    output += os.read(master, 65536)
                except OSError:
                    break
            if b'READY' in output and not sent:
                flags = termios.tcgetattr(slave)[3]
                if not raw_wait or flags & termios.ICANON == 0:
                    if action:
                        action(master, slave, process)
                    sent = True
        process.wait(timeout=2)
        while select.select([master], [], [], 0)[0]:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            output += chunk
        assert process.returncode == 0, (name, process.returncode, output)
        after = termios.tcgetattr(slave)
        # Darwin may set transient PENDIN during restoration.
        before[3] &= ~getattr(termios, 'PENDIN', 0)
        after[3] &= ~getattr(termios, 'PENDIN', 0)
        assert before == after, (name, 'terminal state not restored', before, after)
        return output.replace(b'\r\n', b'\n')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)

pty_results = []
output = native_pty('geometry', 'FORM . . 2 -3 AT-DELTAXY')
assert output == b'READY113 41 \x1b[2C\x1b[3A', output
pty_results.append('geometry/movement')
for name, body, data, expected in [
    ('key-ior-byte', 'KEY-IOR .', b'A', b'READY65 '),
    ('key-ior-interrupt', ': Q KEY-IOR DROP ; \' Q CATCH .', b'\x03', b'READY-28 '),
    ('shift-tab', 'EKEY .', b'\x1b[Z', b'READY2415919133 '),
]:
    output = native_pty(name, body, lambda master, slave, proc: os.write(master, data), raw_wait=True)
    assert output == expected, (name, output)
    pty_results.append(name)

def resize(master, slave, process):
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 42, 114, 0, 0))
    os.kill(process.pid, signal.SIGWINCH)
    os.write(master, b'A\n')
output = native_pty('resize-input', '200 MS EKEY? . EKEY . FORM . . KEY .', resize)
assert b'-1 2147483671 114 42 65 ' in output, output
pty_results.append('resize/readiness/byte-preservation')

def resize_accept(master, slave, process):
    os.kill(process.pid, signal.SIGWINCH)
    os.write(master, b'abc\n')
output = native_pty('resize-accept', 'PAD 16 ACCEPT PAD SWAP TYPE EKEY .', resize_accept, raw_wait=True)
assert b'abc2147483671 ' in output, output
pty_results.append('resize/ACCEPT coexistence')
folder = pathlib.Path('.work/p06c-check')
report = {'pass': True, 'reference_comparisons': len(results), 'cases': results, 'sigma_pty_cases': pty_results}
(folder / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'pass': True, 'reference_comparisons': len(results), 'sigma_pty_checks': len(pty_results)}))
