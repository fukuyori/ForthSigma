#!/usr/bin/env python3
"""POSIX-only shell startup reproduction; stdlib, no sigma required.
Run on Linux: python3 tests/scripts/reproduce-tty-shell-ready.py --shell /bin/dash
Run on macOS: python3 tests/scripts/reproduce-tty-shell-ready.py --shell /bin/sh
Raw bytes retain echo, prompt, CR/LF; termios flags are reported, never assumed.
"""
import argparse
import errno
import json
import os
import re
import select
import time
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--shell', default='/bin/dash')
    args = parser.parse_args()
    if os.name == 'nt':
        parser.error('POSIX pty required; dash cannot be executed by this Windows check')
    import pty
    import termios
    pid, master = pty.fork()
    if pid == 0:
        os.execv(args.shell, [args.shell, '-i'])
    raw = bytearray()
    token = 'TTY_' + uuid.uuid4().hex + '_READY'
    try:
        attrs = termios.tcgetattr(master)
        command = "printf '\\n%s\\n' " + token + '\n'
        os.write(master, command.encode())
        deadline = time.monotonic() + 10
        while not re.search(rb'(?m)^' + token.encode() + rb'\r?\n', raw):
            if time.monotonic() > deadline:
                raise AssertionError('missing ready output: %r' % raw)
            if select.select([master], [], [], 0.1)[0]:
                raw.extend(os.read(master, 4096))
        print(json.dumps(dict(shell=args.shell, command=command, raw=repr(bytes(raw)),
                             iflag=attrs[0], oflag=attrs[1], lflag=attrs[3], passed=True)))
    finally:
        os.write(master, b'exit\n')
        # Reap only our shell, bounded even if the shell did not exit.
        deadline = time.monotonic() + 5
        while os.waitpid(pid, os.WNOHANG)[0] == 0:
            if time.monotonic() > deadline:
                import signal
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
                break
            time.sleep(0.01)
        os.close(master)


if __name__ == '__main__':
    main()
