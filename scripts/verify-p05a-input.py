#!/usr/bin/env python3
"""File-key comparison plus Sigma-only buffered-readiness, pipe and PTY checks."""
import argparse
import json
import os
import pathlib
import select
import subprocess
import sys
import time

p = argparse.ArgumentParser()
p.add_argument('sigma', nargs='?', default='zig-out/bin/sigma')
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
p.add_argument('--report', type=pathlib.Path)
a = p.parse_args()
sigma = str(pathlib.Path(a.sigma).resolve())
b = a.gforth_build.resolve()
folder = pathlib.Path('.work/p05a-input-check').resolve()
folder.mkdir(parents=True, exist_ok=True)
commands = {'sigma': [sigma, '--max-steps', '100000', '-e'], 'gforth': [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e']}
path = folder / 'byte.bin'
for value in range(-1, 256):
    path.write_bytes(b'' if value < 0 else bytes([value]))
    code = f'S" {path}" R/O OPEN-FILE THROW CONSTANT F F FILE-EOF? . F KEY?-FILE . F FILE-EOF? . F KEY-FILE . F FILE-EOF? . F KEY-FILE . F FILE-EOF? . F FILE-SIZE THROW 2DROP F FILE-EOF? . 0 0 F REPOSITION-FILE THROW F FILE-EOF? . F CLOSE-FILE THROW DEPTH . BYE'
    expected = ['0', '-1' if value >= 0 else '0', '0', str(value), '0' if value >= 0 else '-1', '-1', '-1', '-1', '0', '0']
    for runtime, cmd in commands.items():
        r = subprocess.run(cmd + [code], capture_output=True, timeout=10)
        assert r.returncode == 0 and r.stdout.decode().split() == expected, (runtime, value, r.stdout, r.stderr)
code = 'STDIN FILE-EOF? . STDIN KEY-FILE . STDIN KEY-FILE . STDIN KEY-FILE . STDIN KEY-FILE . STDIN KEY-FILE . STDIN FILE-EOF? . DEPTH . BYE'
for runtime, cmd in commands.items():
    r = subprocess.run(cmd + [code], input=bytes([0, 3, 255, 65]), capture_output=True, timeout=10)
    assert r.returncode == 0 and r.stdout.split() == [b'0', b'0', b'3', b'255', b'65', b'-1', b'-1', b'0'], (runtime, r.stdout, r.stderr)
path.write_bytes(b'AB')
code = f'S" {path}" R/O OPEN-FILE THROW CONSTANT F F KEY?-FILE . F KEY-FILE . F KEY?-FILE . F KEY-FILE . F CLOSE-FILE THROW BYE'
for runtime, cmd in commands.items():
    r = subprocess.run(cmd + [code], capture_output=True, timeout=10)
    expected = [b'-1', b'65', b'-1' if runtime == 'sigma' else b'0', b'66']
    assert r.returncode == 0 and r.stdout.split() == expected, (runtime, r.stdout, r.stderr)


def until(fd, token, captured, timeout=10):
    deadline = time.monotonic() + timeout
    while token not in captured:
        assert time.monotonic() < deadline, ('timeout', token, captured)
        if select.select([fd], [], [], 0.05)[0]:
            part = os.read(fd, 4096)
            assert part, ('unexpected EOF', token, captured)
            captured += part
    return captured


pty_cases = 0
if sys.platform != 'win32':
    import pty
    import termios
    variants = [
        ('byte', 'STDIN KEY-FILE .', b'A', b'65 '),
        ('escape', 'STDIN KEY-FILE .', b'\x1b', b'27 '),
        ('utf8', 'STDIN KEY-FILE . STDIN KEY-FILE . STDIN KEY-FILE .', '日'.encode(), b'230 151 165 '),
        ('shared-key', 'STDIN KEY-FILE . STDIN KEY?-FILE . KEY .', b'AB', b'65 -1 66 '),
        ('interrupt', 'STDIN KEY-FILE .', b'\x03', None),
        ('ready-interrupt', ': READY-WAIT BEGIN STDIN KEY?-FILE DROP 1 MS AGAIN ; READY-WAIT', b'\x03', None),
    ]
    for name, body, data, expected in variants:
        master, slave = pty.openpty()
        before = termios.tcgetattr(slave)
        proc = subprocess.Popen(commands['sigma'] + ['STDIN KEY?-FILE . ." WAIT" ' + body + ' BYE'], stdin=slave, stdout=slave, stderr=slave)
        captured = b''
        try:
            captured = until(master, b'WAIT', captured)
            assert b'0 WAIT' in captured, (name, captured)
            os.write(master, data)
            deadline = time.monotonic() + 10
            while proc.poll() is None:
                assert time.monotonic() < deadline, (name, captured)
                if select.select([master], [], [], 0.05)[0]:
                    captured += os.read(master, 4096)
            while select.select([master], [], [], 0)[0]:
                captured += os.read(master, 4096)
            if expected is None:
                assert proc.returncode != 0 and b'INTERRUPT' in captured.upper(), (name, proc.returncode, captured)
            else:
                assert proc.returncode == 0 and expected in captured, (name, proc.returncode, captured)
            after = termios.tcgetattr(slave)
            # Darwin's terminal driver sets transient PENDIN when canonical input
            # is restored. The existing EKEY path produces the identical bit change.
            stable_before = before.copy()
            stable_after = after.copy()
            stable_before[3] &= ~getattr(termios, 'PENDIN', 0)
            stable_after[3] &= ~getattr(termios, 'PENDIN', 0)
            assert stable_before == stable_after, (name, 'terminal not restored', before, after, captured)
            pty_cases += 1
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)
            os.close(slave)

    # Opening the FIFO synchronizes the writer/reader; keep the writer open while
    # checking readiness so an empty stream is not mistaken for EOF.
    import threading
    fifo = folder / 'ready.fifo'
    if fifo.exists():
        fifo.unlink()
    os.mkfifo(fifo)
    send = threading.Event()
    end = threading.Event()
    writer_errors = []

    def writer():
        try:
            fd = os.open(fifo, os.O_WRONLY)
            try:
                if send.wait(10):
                    os.write(fd, b'AB')
                end.wait(10)
            finally:
                os.close(fd)
        except Exception as exc:
            writer_errors.append(str(exc))

    code = f'S" {fifo}" R/O OPEN-FILE THROW CONSTANT F F KEY?-FILE . ." WAIT" F KEY-FILE . F KEY?-FILE . F KEY-FILE . F KEY?-FILE . F FILE-EOF? . ." END" F KEY-FILE . F FILE-EOF? . F CLOSE-FILE THROW BYE'
    proc = subprocess.Popen(commands['sigma'] + [code], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    thread = threading.Thread(target=writer, daemon=True)
    thread.start()
    captured = b''
    try:
        captured = until(proc.stdout.fileno(), b'WAIT', captured)
        send.set()
        captured = until(proc.stdout.fileno(), b'END', captured)
        end.set()
        tail, stderr = proc.communicate(timeout=10)
        captured += tail
        thread.join(timeout=2)
        assert proc.returncode == 0 and captured == b'0 WAIT65 -1 66 0 0 END-1 -1 ', (proc.returncode, captured, stderr)
        assert not writer_errors and not thread.is_alive(), writer_errors
    finally:
        send.set()
        end.set()
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        proc.stdout.close()
        proc.stderr.close()
        fifo.unlink(missing_ok=True)

report = {'words': 3, 'gforth_comparisons': 258, 'intentional_buffered_readiness_difference': 1, 'sigma_pty_cases': pty_cases, 'sigma_fifo_cases': int(sys.platform != 'win32'), 'pass': True}
if a.report:
    a.report.parent.mkdir(parents=True, exist_ok=True)
    a.report.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
