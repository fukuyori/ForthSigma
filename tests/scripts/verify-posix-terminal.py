#!/usr/bin/env python3
"""POSIX PTY/FIFO acceptance: terminal modes, interrupts, resize and shared input."""
import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--sigma', type=Path, required=True)
p.add_argument('--output', type=Path, default=Path('.work/wsl-terminal/report.json'))
a = p.parse_args()
sigma = str(a.sigma.resolve(strict=True))
output = a.output.resolve()
output.parent.mkdir(parents=True, exist_ok=True)
rows = []

def saved(fd):
    value = termios.tcgetattr(fd)
    value[3] &= ~getattr(termios, 'PENDIN', 0)
    return value

class Session:
    def __init__(self, source, columns=113, lines=41):
        self.master, self.slave = pty.openpty()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack('HHHH', lines, columns, 0, 0))
        self.original = saved(self.slave)
        self.data = b''
        def attach():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        self.child = subprocess.Popen([sigma, '--max-steps', '1000000', '-e', source + ' BYE'],
                                      stdin=self.slave, stdout=self.slave, stderr=self.slave, preexec_fn=attach)

    def until(self, token, timeout=5):
        deadline = time.monotonic() + timeout
        while token not in self.data:
            assert time.monotonic() < deadline, (token, self.data)
            if select.select([self.master], [], [], 0.02)[0]:
                self.data += os.read(self.master, 65536)
        return self.data

    def finish(self):
        deadline = time.monotonic() + 5
        while self.child.poll() is None:
            assert time.monotonic() < deadline, self.data
            if select.select([self.master], [], [], 0.02)[0]:
                try:
                    self.data += os.read(self.master, 65536)
                except OSError as e:
                    if e.errno != errno.EIO:
                        raise
        while select.select([self.master], [], [], 0)[0]:
            try:
                part = os.read(self.master, 65536)
                if not part:
                    break
                self.data += part
            except OSError as e:
                if e.errno != errno.EIO:
                    raise
                break
        assert self.child.returncode == 0, (self.child.returncode, self.data)
        assert saved(self.slave) == self.original, ('terminal not restored', self.original, saved(self.slave), self.data)
        return self.data

    def close(self):
        if self.child.poll() is None:
            self.child.kill()
        self.child.wait(timeout=5)
        os.close(self.master)
        os.close(self.slave)

def record(name, data):
    rows.append({'case': name, 'output_hex': data.hex()})
    output.write_text(json.dumps({'complete': False, 'cases': rows}, indent=2) + '\n')

for name, source, data, expected in [
    ('key-file-byte', 'STDIN KEY-FILE .', b'A', b'65 '),
    ('key-file-escape', 'STDIN KEY-FILE .', b'\x1b', b'27 '),
    ('key-file-unicode', 'STDIN KEY-FILE . STDIN KEY-FILE . STDIN KEY-FILE .', '日'.encode(), b'230 151 165 '),
    ('file-key-lookahead-shared', 'STDIN KEY-FILE . STDIN KEY?-FILE . KEY .', b'AB', b'65 -1 66 '),
    ('key-file-ctrl-c', ': W STDIN KEY-FILE DROP ; \' W CATCH .', b'\x03', b'-28 '),
    ('key-ior', 'KEY-IOR .', b'A', b'65 '),
    ('key-ior-ctrl-c', "' KEY-IOR CATCH .", b'\x03', b'-28 '),
    ('key-ready-ctrl-c', ": W BEGIN STDIN KEY?-FILE DROP 1 MS AGAIN ; ' W CATCH .", b'\x03', b'-28 '),
    ('shift-tab', 'EKEY K-TAB K-SHIFT-MASK OR = .', b'\x1b[Z', b'-1 '),
    ('ctrl-up', 'EKEY K-UP K-CTRL-MASK OR = .', b'\x1b[1;5A', b'-1 '),
    ('alt-left', 'EKEY K-LEFT K-ALT-MASK OR = .', b'\x1b[1;3D', b'-1 '),
    ('key-then-ekey', 'KEY . EKEY .', 'Aé\n'.encode(), b'65 233 '),
]:
    s = Session('EKEY? DROP ." READY" ' + source)
    try:
        s.until(b'READY')
        os.write(s.master, data)
        result = s.finish()
        assert expected in result, (name, result, expected)
        record(name, result)
    finally:
        s.close()

s = Session('FORM . . 2 -3 AT-DELTAXY')
try:
    result = s.finish()
    assert result == b'113 41 \x1b[2C\x1b[3A', result
    record('form-cursor', result)
finally:
    s.close()

for name, source, data, expected in [
    ('resize-and-key', '200 MS EKEY? . EKEY K-WINCH = . FORM . . KEY .', b'A\n', b'-1 -1 114 42 65 '),
    ('resize-during-accept', 'PAD 16 ACCEPT PAD SWAP TYPE EKEY K-WINCH = .', b'abc\n', b'abc-1 '),
]:
    s = Session('EKEY? DROP ." READY" ' + source)
    try:
        s.until(b'READY')
        fcntl.ioctl(s.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 42, 114, 0, 0))
        os.kill(s.child.pid, signal.SIGWINCH)
        os.write(s.master, data)
        result = s.finish()
        assert expected in result, (name, result)
        record(name, result)
    finally:
        s.close()

for duration in [2000000000, 18446744073709551739]:
    for raw in [False, True]:
        source = ('EKEY? DROP ' if raw else '') + f'." BEFORE" CR 100 MS : W {duration}. NS ; ." READY" \' W CATCH . 1000000. NS ." AFTER" CR 200 MS EKEY . EKEY .'
        s = Session(source)
        try:
            s.until(b'BEFORE')
            before = saved(s.slave)
            s.until(b'READY')
            time.sleep(0.03)
            # NS enables ISIG+NOFLSH: the driver sends SIGINT and retains A/B.
            os.write(s.master, b'A\x03B')
            s.until(b'AFTER')
            assert saved(s.slave) == before, ('NS scope terminal state', before, saved(s.slave), s.data)
            result = s.finish()
            assert b'-28 AFTER' in result and b'65 66 ' in result, result
            record(f'ns-interrupt-{duration}-raw-{raw}', result)
        finally:
            s.close()

for name, raw, data, tail, expected in [
    ('ns-retains-special', True, b'\x1b[AZ', 'EKEY K-UP = . EKEY .', b'-1 90 '),
    ('ns-retains-control', True, b'\x1a\x1c', 'EKEY . EKEY .', b'26 28 '),
    ('ns-retains-canonical', False, b'AB', 'EKEY . EKEY .', b'65 66 '),
]:
    s = Session(('EKEY? DROP ' if raw else '') + '." BEFORE" CR 100 MS ." READY" 150000000. NS ." AFTER" CR 200 MS ' + tail)
    try:
        s.until(b'BEFORE')
        before = saved(s.slave)
        s.until(b'READY')
        time.sleep(0.03)
        os.write(s.master, data)
        s.until(b'AFTER')
        assert saved(s.slave) == before, (name, s.data)
        result = s.finish()
        assert expected in result, (name, result)
        record(name, result)
    finally:
        s.close()

s = Session('K-DOWN CONSTANT STD-DOWN REQUIRE-GRAPHICS ALSO GRAPHICS : WAIT-W BEGIN INKEY DUP -1 = WHILE DROP 1 MS REPEAT ; ." READY" WAIT-W K-UP = . ." NEXT!" EKEY STD-DOWN = .')
try:
    s.until(b'READY')
    time.sleep(0.02)
    os.write(s.master, b'\x1b[A')
    s.until(b'NEXT!')
    os.write(s.master, b'\x1b[B')
    result = s.finish()
    assert b'-1 NEXT!-1 ' in result, result
    record('graphics-inkey-standard-ekey', result)
finally:
    s.close()

# A named FIFO retains an open writer while readiness is queried on an empty
# pipe; then test stdio prefetch and actual EOF after the writer closes.
with tempfile.TemporaryDirectory(prefix='sigma-fifo-', dir='/tmp') as folder:
    fifo = Path(folder) / 'input.fifo'
    os.mkfifo(fifo)
    source = f'S" {fifo}" R/O OPEN-FILE THROW CONSTANT F ." OPEN" F KEY?-FILE . ." EMPTY" F KEY-FILE . F KEY?-FILE . F KEY-FILE . F KEY-FILE . F FILE-EOF? . F CLOSE-FILE THROW BYE'
    child = subprocess.Popen([sigma, '-e', source], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        writer = os.open(fifo, os.O_WRONLY)
        assert child.stdout.read(4) == b'OPEN'
        assert child.stdout.read(7) == b'0 EMPTY'
        os.write(writer, b'AB')
        os.close(writer)
        out, err = child.communicate(timeout=5)
        assert child.returncode == 0 and out == b'65 -1 66 -1 -1 ', (child.returncode, out, err)
        record('fifo-empty-ready-prefetch-eof', out)
    finally:
        if child.poll() is None:
            child.kill()
        child.wait(timeout=5)

output.write_text(json.dumps({'complete': True, 'cases': rows}, indent=2) + '\n')
print(f'{len(rows)} POSIX terminal cases passed')
