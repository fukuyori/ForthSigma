#!/usr/bin/env python3
"""POSIX PTY acceptance for deadline-aware standard events."""
import errno
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import termios
import time


def main():
    if not __debug__:
        raise SystemExit('Run acceptance tests without Python -O')
    sigma = str(Path(sys.argv[1]).resolve(strict=True))
    records = []
    def run(name, body, expected, sends=(), status=0):
        master, slave = pty.openpty()
        before = termios.tcgetattr(slave)
        source = ('REQUIRE-EXTENSION ALSO EXTENSION : R EKEY-WAIT . . . ; '
                  '.( READY) ' + body)
        process = subprocess.Popen([sigma, '-e', source], stdin=slave, stdout=slave, stderr=slave,
                                   env=dict(os.environ, TERM='xterm-256color'))
        data = bytearray()
        ready_at = None
        index = 0
        until = time.monotonic() + 8
        try:
            while time.monotonic() < until:
                readable, _, _ = select.select([master], [], [], .002)
                if readable:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO: break
                        raise
                    data.extend(chunk)
                if b'READY' in data and ready_at is None:
                    ready_at = time.monotonic()
                if ready_at is not None:
                    while index < len(sends) and time.monotonic() - ready_at >= sends[index][0]:
                        os.write(master, sends[index][1]); index += 1
                if process.poll() is not None and not readable: break
            assert process.poll() is not None, (name, 'timeout', bytes(data))
            assert process.returncode == status, (name, process.returncode, bytes(data))
            assert expected in data, (name, expected, bytes(data))
            after = termios.tcgetattr(slave)
            # Darwin may set PENDIN after a successful restoration (637 acceptance).
            if sys.platform == 'darwin':
                pendin = getattr(termios, 'PENDIN', 0)
                before[3] &= ~pendin; after[3] &= ~pendin
            assert before == after, (name, 'termios not restored')
            records.append({'case': name, 'exit': process.returncode, 'stdout_hex': data.hex()})
            return bytes(data)
        finally:
            if process.poll() is None: process.kill()
            process.wait(); os.close(master); os.close(slave)
    run('timeout', '20 R BYE', b'0 0 0 ')
    run('split-utf8', '10 R 1000 R BYE', b'0 0 0 0 -1 26085 ', ((.003, b'\xe6'), (.04, b'\x97\xa5')))
    run('split-arrow', '10 R 1000 R BYE', b'0 0 0 0 -1 2147483650 ', ((.003, b'\x1b'), (.03, b'[A')))
    run('paste-controls', '2 TERM-MODE! DROP 1000 R 1000 R 1000 R 1000 R 1000 R 1000 R BYE',
        b'0 -1 2147483683 0 -1 3 0 -1 27 0 -1 91 0 -1 65 0 -1 2147483684 ',
        ((.02, b'\x1b[200~\x03\x1b[A\x1b[201~'),))
    run('mouse-peek', '8 TERM-MODE! DROP 30 MS EKEY? . EKEY-MOUSE . . . . 1000 R EKEY-MOUSE . . . . BYE',
        b'-1 0 0 0 0 0 -1 2147483682 0 1 3 2 ', ((.01, b'\x1b[<0;3;4M'),))
    run('peek-key', '30 MS EKEY? . KEY . BYE', b'-1 65 ', ((.01, b'A'),))
    accept_data = run('peek-accept', '30 MS EKEY? . PAD 20 ACCEPT PAD SWAP TYPE BYE', b'-1 ', ((.01, b'abc\n'),))
    assert accept_data.rstrip().endswith(b'abc'), accept_data
    run('peek-inkey', '30 MS EKEY? . REQUIRE-GRAPHICS ALSO GRAPHICS INKEY . BYE', b'-1 65 ', ((.01, b'A'),))
    run('peek-32-byte-key-flush', '30 MS EKEY? . : BYTES-W 32 0 DO KEY . LOOP ; BYTES-W BYE', b'-1 27 91 ' + b'49 ' * 30, ((.01, b'\x1b[' + b'1' * 30),))
    run('peek-stdin-key-file', '30 MS EKEY? . STDIN KEY?-FILE . STDIN KEY-FILE . BYE', b'-1 -1 65 ', ((.01, b'A'),))
    run('peek-stdin-read-file', '30 MS EKEY? . PAD 1 STDIN READ-FILE THROW . PAD C@ . BYE', b'-1 1 65 ', ((.01, b'A'),))
    run('outside-paste-interrupt', '1000 R BYE', b'INTERRUPT', ((.02, b'\x03'),), 1)
    for name, incoming, expected in [('pipe-esc-eof-byte-order', b'\x1b[', b'27 91 2147483681 '), ('pipe-utf8-eof-byte-order', b'\xe3\x81', b'227 65533 2147483681 ')]:
        result = subprocess.run([sigma, '-e', 'EKEY? DROP KEY . EKEY . EKEY . BYE'], input=incoming, capture_output=True)
        assert result.returncode == 0 and result.stdout == expected, (name, result)
        records.append({'case': name, 'exit': result.returncode, 'stdout_hex': result.stdout.hex()})
    result = subprocess.run([sigma, '-e', 'REQUIRE-EXTENSION ALSO EXTENSION 0 EKEY-WAIT . . . BYE'], input=b'', capture_output=True)
    assert result.returncode == 0 and result.stdout == b'0 -1 2147483681 ', result
    records.append({'case': 'pipe-eof', 'exit': result.returncode, 'stdout_hex': result.stdout.hex()})
    folder = Path('.work/event-queue'); folder.mkdir(parents=True, exist_ok=True)
    (folder / 'posix.json').write_text(json.dumps({'complete': True, 'cases': records}, indent=2) + '\n')
    print(f'{len(records)} standard-event PTY/pipe cases passed')


if __name__ == '__main__':
    main()
