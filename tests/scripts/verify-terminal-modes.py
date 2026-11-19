#!/usr/bin/env python3
"""POSIX PTY acceptance for terminal presentation, cooked input and cleanup."""
import argparse
import errno
import json
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import termios
import time


def main():
    if not __debug__:
        raise SystemExit("Run acceptance tests without Python -O: assertions are required")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sigma', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('.work/terminal-modes/posix.json'))
    args = parser.parse_args()
    sigma = str(args.sigma.resolve(strict=True))
    records = []

    def termios_restored(before, after):
        # Darwin sets PENDIN (retype pending input) when switching back to
        # canonical mode. It is a transient state bit, not a saved terminal mode;
        # Python's tty.setraw()/tcsetattr(saved) produces the same difference.
        if sys.platform == 'darwin' and hasattr(termios, 'PENDIN'):
            before = list(before)
            after = list(after)
            before[3] &= ~termios.PENDIN
            after[3] &= ~termios.PENDIN
        return before == after

    def run(name, source, expected, send=None, status=0, options=()):
        master, slave = pty.openpty()
        before = termios.tcgetattr(slave)
        proc = subprocess.Popen([sigma, *options, '-e', 'REQUIRE-EXTENSION ALSO EXTENSION ' + source],
                                stdin=slave, stdout=slave, stderr=slave,
                                env=dict(os.environ, TERM='xterm-256color'))
        data = bytearray()
        sent = False
        deadline = time.monotonic() + 12
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], .05)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not chunk:
                        break
                    data.extend(chunk)
                if send is not None and not sent and b'READY' in data:
                    # Ensure the input callback has installed its interrupt scope.
                    time.sleep(.1)
                    if isinstance(send, tuple):
                        os.write(master, send[0])
                        time.sleep(.1)
                        proc.send_signal(signal.SIGINT)
                    elif send == 'signal':
                        proc.send_signal(signal.SIGINT)
                    else:
                        os.write(master, send)
                    sent = True
                if proc.poll() is not None and not ready:
                    break
            assert proc.poll() is not None, (name, 'timeout', bytes(data))
            assert proc.returncode == status, (name, proc.returncode, bytes(data))
            assert expected in data, (name, expected, bytes(data))
            after = termios.tcgetattr(slave)
            assert termios_restored(before, after), (name, 'termios not restored', before, after)
            assert data.count(b'\x1b[?1049h') == data.count(b'\x1b[?1049l'), (name, 'screen not restored', bytes(data))
            records.append({'case': name, 'exit': proc.returncode, 'stdout_hex': data.hex(), 'termios_restored': True,
                            'transient_flags_ignored': ['PENDIN'] if sys.platform == 'darwin' and hasattr(termios, 'PENDIN') else []})
            return bytes(data)
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.wait()
            os.close(master)
            os.close(slave)

    data = run('before-raw-and-bye', '5 TERM-MODE! . TERM-MODE@ . BYE', b'0 5 ')
    assert b'\x1b[?25l' in data and b'\x1b[?25h' in data
    data = run('raw-mouse-and-paste', '15 TERM-MODE! . EKEY? DROP TERM-MODE@ . 0 TERM-MODE! . BYE', b'15 ')
    assert all(sequence in data for sequence in (b'\x1b[?2004h', b'\x1b[?2004l', b'\x1b[?1003h', b'\x1b[?1003l'))
    data = run('system-handoff', '5 TERM-MODE! DROP .( APP) S" printf SYS" SYSTEM .( BACK) BYE', b'BACK')
    assert data.index(b'\x1b[?1049l') < data.index(b'SYS') < data.rindex(b'\x1b[?1049h')
    data = run('key-keeps-alternate', '5 TERM-MODE! DROP .( READY) KEY . BYE', b'81 ', b'Q\n')
    assert data.count(b'\x1b[?1049h') == 1
    assert data.index(b'81 ') < data.index(b'\x1b[?1049l')
    data = run('accept-keeps-alternate', '5 TERM-MODE! DROP .( READY) PAD 20 ACCEPT . BYE', b'5 ', b'hello\n')
    assert data.count(b'\x1b[?1049h') == 1
    data = run('caught-throw-keeps-request', '5 TERM-MODE! DROP : FAIL-W -123 THROW ; \' FAIL-W CATCH . TERM-MODE@ . BYE', b'-123 5 ')
    assert data.count(b'\x1b[?1049h') == 1
    data = run('uncaught-error-restores-before-report', '5 TERM-MODE! DROP 1 0 /', b'DIVISION BY ZERO', status=1)
    assert data.index(b'\x1b[?1049l') < data.index(b'DIVISION BY ZERO')
    data = run('cooked-key-interrupt', '5 TERM-MODE! DROP .( READY) KEY DROP BYE', b'INTERRUPT', 'signal', 1)
    assert data.index(b'\x1b[?1049l') < data.index(b'INTERRUPT')
    data = run('cooked-accept-interrupt', '5 TERM-MODE! DROP .( READY) PAD 20 ACCEPT DROP BYE', b'INTERRUPT', 'signal', 1)
    data = run('repl-partial-line-interrupt', '5 TERM-MODE! DROP .( READY)', b'INTERRUPT', (b'BYE', 'signal'), 1)
    data = run('raw-ekey-interrupt', '5 TERM-MODE! DROP .( READY) EKEY DROP BYE', b'INTERRUPT', b'\x03', 1)
    data = run('profile-after-restore', '5 TERM-MODE! DROP BYE', b'\x1b[?1049l', options=('--profile',))
    # A pipe is not a terminal; controls must not leak into redirected output.
    result = subprocess.run([sigma, '-e', 'REQUIRE-EXTENSION ALSO EXTENSION 5 TERM-MODE! . TERM-MODE@ . BYE'], capture_output=True)
    assert result.returncode == 0 and result.stdout == b'-21 0 ', result
    records.append({'case': 'redirected-output', 'exit': result.returncode, 'stdout_hex': result.stdout.hex()})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({'complete': True, 'cases': records}, indent=2) + '\n')
    print(f'{len(records)} terminal presentation cases passed')


if __name__ == '__main__':
    main()
