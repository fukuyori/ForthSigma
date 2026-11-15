#!/usr/bin/env python3
"""Investigate all P06c words before the subphase-wide policy decision."""
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
import termios
import time
import tty

parser = argparse.ArgumentParser()
parser.add_argument('--gforth-build', type=pathlib.Path, required=True)
a = parser.parse_args()
b = a.gforth_build.resolve()
root = pathlib.Path('.work/p06c-check').resolve()
root.mkdir(parents=True, exist_ok=True)
cmd = [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e']
constants = ['K-BACKSPACE', 'K-ENTER', 'K-EOF', 'K-MUTE', 'K-PAUSE', 'K-SEL', 'K-TAB', 'K-VOLDOWN', 'K-VOLUP', 'K-WINCH']
results = []
def pipe_case(name, source, data=b'', env=None):
    run = subprocess.run(cmd + [source + ' DEPTH . BYE'], input=data, capture_output=True, timeout=10, env=env)
    results.append({'case': name, 'source': source, 'input_hex': data.hex(), 'exit': run.returncode,
                    'stdout_hex': run.stdout.hex(), 'stderr': run.stderr.decode(errors='replace')})
for word in constants:
    pipe_case('constant:' + word, word + ' .')
    pipe_case('classification:' + word, f'{word} EKEY>FKEY . . {word} EKEY>CHAR . . {word} EKEY>XCHAR . .')
    pipe_case('name:' + word, word + ' SIMPLE-FKEY-STRING TYPE')
for mask in range(8):
    flags = ' '.join(f'{name} OR' for bit, name in [(1, 'K-SHIFT-MASK'), (2, 'K-CTRL-MASK'), (4, 'K-ALT-MASK')] if mask & bit)
    pipe_case('fkey-modifiers:' + str(mask), f'K-UP {flags} FKEY.')
for value in [65, -1, 0x80000022, 0x8000001f, 0x80000020, 0x90000002]:
    pipe_case('name-invalid:' + str(value), f': TRY-NAME {value} SIMPLE-FKEY-STRING 2DROP ; \' TRY-NAME CATCH .')
    pipe_case('fkey-edge:' + str(value), f': TRY-NAME {value} FKEY. ; \' TRY-NAME CATCH .')
for data in [b'A', b'\x00', b'\x03', b'\r\n', '日'.encode(), b'']:
    pipe_case('key-ior:' + data.hex(), 'KEY-IOR .', data)
path = root / 'empty-input'
path.write_bytes(b'')
pipe_case('key-ior-file-eof', f': INPUT-P KEY-IOR . ; S" {path}" R/O OPEN-FILE THROW DUP >R \' INPUT-P SWAP INFILE-EXECUTE R> CLOSE-FILE THROW')
pipe_case('key-ior-file-closed', f'S" {path}" R/O OPEN-FILE THROW DUP CLOSE-FILE THROW : INPUT-P KEY-IOR . ; \' INPUT-P SWAP INFILE-EXECUTE')
pipe_case('eof-events', 'EKEY? . EKEY . EKEY? . EKEY .')
pipe_case('key-ior-repeat-eof', 'KEY-IOR . KEY-IOR .')
pipe_case('file-plain-controls', 'EKEY . EKEY . EKEY .', b'\r\t\x7f')
for dimensions in [None, ('120', '50'), ('0', '0'), ('bad', '-2')]:
    env = dict(os.environ)
    env.pop('COLUMNS', None)
    env.pop('LINES', None)
    if dimensions:
        env['COLUMNS'], env['LINES'] = dimensions
    pipe_case('form-pipe:' + str(dimensions), 'FORM . .', env=env)
pipe_case('form-capture', ': Q FORM . . ; \' Q >STRING-EXECUTE TYPE')
for x, y in [(0, 0), (1, 2), (-3, -4)]:
    pipe_case(f'at-deltaxy-pipe:{x}:{y}', f'{x} {y} AT-DELTAXY')
    pipe_case(f'at-deltaxy-capture:{x}:{y}', f': Q {x} {y} AT-DELTAXY ; : RUN [\'] Q >STRING-EXECUTE 2DROP ; \' RUN CATCH .')

pipe_case('at-deltaxy-min', '-9223372036854775808 0 AT-DELTAXY')
pipe_case('form-outfile', ': Q FORM . . ; S\" '+str(root / 'form-output')+'\" W/O CREATE-FILE THROW DUP >R \' Q SWAP OUTFILE-EXECUTE R> CLOSE-FILE THROW')

def pty_case(name, source, data=None, resize=False, delay=0, interrupt=False):
    master, slave = pty.openpty()
    tty.setraw(slave)
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 41, 113, 0, 0))
    env = dict(os.environ, TERM='xterm-256color')
    env.pop('COLUMNS', None)
    env.pop('LINES', None)
    process = subprocess.Popen(cmd + ['." READY" ' + source + ' BYE'], stdin=slave, stdout=slave, stderr=slave, env=env)
    output = b''
    sent = False
    timed_out = False
    deadline = time.monotonic() + 5
    try:
        while process.poll() is None and time.monotonic() < deadline:
            if select.select([master], [], [], 0.05)[0]:
                try:
                    output += os.read(master, 65536)
                except OSError:
                    break
            if b'READY' in output and not sent:
                if delay:
                    time.sleep(delay)
                if interrupt:
                    os.kill(process.pid, signal.SIGINT)
                if data is not None:
                    os.write(master, data)
                if resize:
                    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 42, 114, 0, 0))
                    os.kill(process.pid, signal.SIGWINCH)
                    os.write(master, b'A')
                sent = True
        if process.poll() is None:
            timed_out = True
            process.kill()
        process.wait(timeout=2)
        while select.select([master], [], [], 0)[0]:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            output += chunk
        results.append({'case': name, 'source': source, 'stdout_hex': output.hex(), 'exit': process.returncode, 'timeout': timed_out})
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
pty_case('form-pty', 'FORM . .')
pty_case('at-deltaxy-pty', '2 -3 AT-DELTAXY')
for data in [b'A', b'\x03']:
    pty_case('key-ior-pty:' + data.hex(), ': Q KEY-IOR . ; \' Q CATCH .', data)
for data in [b'\r', b'\t', b'\x7f', b'\x1b[Z']:
    pty_case('ekey-pty:' + data.hex(), 'EKEY .', data)
pty_case('key-ior-ctrlc-after-wait', ': Q KEY-IOR . ; \' Q CATCH .', b'\x03', delay=0.15)
pty_case('key-ior-sigint', ': Q KEY-IOR . ; \' Q CATCH .', delay=0.15, interrupt=True)
pty_case('resize-pty', '100 MS EKEY . FORM . .', resize=True)
report = {'kind': 'reference observations, not Sigma conformance', 'words': constants + ['AT-DELTAXY', 'FKEY.', 'FORM', 'KEY-IOR', 'SIMPLE-FKEY-STRING'], 'cases': results}
(root / 'spec-probes.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'words': len(report['words']), 'observations': len(results), 'timeouts': [r['case'] for r in results if r.get('timeout')], 'report': str(root / 'spec-probes.json')}))
