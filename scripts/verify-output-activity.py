#!/usr/bin/env python3
"""Task698: check SHOW frame reuse on a POSIX pseudo-terminal, without a GUI."""
import argparse
import errno
import json
import os
import pathlib
import select
import signal
import struct
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--sigma', type=pathlib.Path, default=pathlib.Path('zig-out/bin/sigma'))
p.add_argument('--output', type=pathlib.Path, default=pathlib.Path('.work/698-native-after.json'))
a = p.parse_args()
if os.name != 'posix':
    p.error('this verifier uses POSIX PTYs; Windows native checks are separate')
import fcntl
import pty
import termios


def run(code):
    master, slave = pty.openpty()
    child = None
    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        child = subprocess.Popen([str(a.sigma.resolve()), '--max-steps', '100000', '-e', code],
                                 stdin=subprocess.DEVNULL, stdout=slave,
                                 stderr=subprocess.PIPE, start_new_session=True)
        os.close(slave)
        slave = None
        output = bytearray()
        deadline = time.monotonic() + 20
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([master], [], [], remaining)[0]:
                raise TimeoutError('SHOW PTY verifier timed out')
            try:
                data = os.read(master, 65536)
            except OSError as e:
                if e.errno == errno.EIO:
                    break
                raise
            if not data:
                break
            output.extend(data)
        _, errors = child.communicate(timeout=max(0.1, deadline - time.monotonic()))
        assert child.returncode == 0 and not errors, (child.returncode, errors)
        return bytes(output)
    finally:
        if child is not None:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGKILL)
            child.communicate()
        if slave is not None:
            os.close(slave)
        os.close(master)


cases = [
    ('consecutive', '', True, False),
    ('write-file', 'S" note" STDOUT WRITE-FILE THROW', False, True),
    ('write-line', 'S" note" STDOUT WRITE-LINE THROW', False, True),
    ('empty-line', 'S" " STDOUT WRITE-LINE THROW', False, False),
    ('empty-file', 'S" " STDOUT WRITE-FILE THROW', True, False),
    ('system', 'S" printf note" SYSTEM', False, True),
    ('system-nonzero', 'S" exit 3" SYSTEM', False, False),
    ('captured-system', ': CMD S" printf note" SYSTEM ; \' CMD >STRING-EXECUTE DROP FREE THROW', False, True),
    ('captured-sh', ': CMD S" SH printf note" EVALUATE ; \' CMD >STRING-EXECUTE DROP FREE THROW', False, True),
    ('private-capture', ': TXT S" private" TYPE ; \' TXT >STRING-EXECUTE DROP FREE THROW', True, False),
]
rows = []
for renderer, rows_up in [('GFX-SHOW-BLOCKS', 2), ('GFX-SHOW-SIXEL', 1)]:
    for name, between, reuse, note in cases:
        code = 'REQUIRE-GRAPHICS ALSO GRAPHICS 8 4 GFX-INIT ' + renderer + ' ' + between + ' ' + renderer + ' BYE'
        output = run(code)
        rewind = output.count(f'\r\x1b[{rows_up}A'.encode())
        assert rewind == int(reuse), (renderer, name, rewind, reuse)
        assert (b'note' in output) == note, (renderer, name, output)
        rows.append({'renderer': renderer, 'case': name, 'rewinds': rewind})
report = {'pass': True, 'checks': len(rows), 'cases': rows}
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'pass': True, 'checks': len(rows)}))
