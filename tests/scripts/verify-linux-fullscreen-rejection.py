#!/usr/bin/env python3
"""Check fullscreen refusal recovery using only an owned override-redirect window.
Temporarily unmanage that window so the desktop WM ignores its fullscreen request,
then remanage it and verify that WINDOW-ON works again. No desktop configuration changes.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import struct
import sys
import time
from linux_x11_test_support import SigmaSession, binary_identity, require_linux

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'experiments'))
from linux_x11_probe import Connection
require_linux()


def interrupted(signum, frame):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    raise SystemExit(f'interrupted by signal {signum}')


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGHUP, interrupted)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
source = '''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-WINDOW DISPLAYS DROP
4 2 GFX-INIT 64 40 WINDOW-SIZE 0 WINDOW-ON SHOW 2000 WINDOW-PAINT-WAIT DROP
: REPORT FULLSCREEN? . WINDOW-OPEN? . WINDOW-DISPLAY . WINDOW-PIXELS SWAP . . CR ;
." READY " REPORT
KEY DROP TRUE FULLSCREEN 100 MS ." PENDING " FULLSCREEN? . CR 1 WINDOW-ON 1400 MS ." REJECTED " REPORT
KEY DROP FALSE FULLSCREEN 300 MS 1 WINDOW-ON 600 MS ." RECOVERED " REPORT
KEY DROP WINDOW-CLOSE BYE'''
connection = Connection(os.environ['DISPLAY'])


def find_window(pid):
    pending = [connection.root]
    connection.deadline = time.monotonic() + 5
    while pending:
        window = pending.pop()
        try:
            _, value = connection.reply(connection.request(20, body=struct.pack(
                '<IIIII', window, connection.atom(b'_NET_WM_PID'), 0, 0, 1)))
            if value[:4] == struct.pack('<I', pid):
                return window
            _, children = connection.reply(connection.request(15, body=struct.pack('<I', window)))
            pending.extend(struct.unpack('<' + 'I' * (len(children) // 4), children))
        except RuntimeError as error:
            if 'X11 error code=3 ' not in str(error):
                raise
    raise AssertionError('owned Sigma window not found')


def override_redirect(window, enabled):
    connection.deadline = time.monotonic() + 5
    connection.request(10, body=struct.pack('<I', window))  # Unmap our own window.
    connection.sync()
    time.sleep(.2)  # Let the WM withdraw/reparent before mapping it again.
    connection.deadline = time.monotonic() + 5
    connection.request(2, body=struct.pack('<III', window, 1 << 9, int(enabled)))
    connection.request(8, body=struct.pack('<I', window))
    connection.sync()
    time.sleep(.2)
    connection.deadline = time.monotonic() + 5
    header, _ = connection.reply(connection.request(3, body=struct.pack('<I', window)))
    assert bool(header[27]) == enabled, header[27]


try:
    with SigmaSession(str(args.sigma.resolve()), source, os.environ.copy()) as session:
        ready = session.line().split()
        assert ready == [b'READY', b'0', b'-1', b'0', b'64', b'40'], ready
        window = find_window(session.process.pid)
        override_redirect(window, True)
        session.send()
        pending = session.line(timeout=5).split()
        assert pending == [b'PENDING', b'-1'], pending
        rejected = session.line(timeout=5).split()
        assert rejected[:3] == [b'REJECTED', b'0', b'-1'], (rejected, session.errors())
        connection.deadline = time.monotonic() + 5
        _, state = connection.reply(connection.request(20, body=struct.pack(
            '<IIIII', window, connection.atom(b'_NET_WM_STATE'), 4, 0, 32)))
        assert connection.atom(b'_NET_WM_STATE_FULLSCREEN') not in struct.unpack('<' + 'I' * (len(state) // 4), state)
        override_redirect(window, False)
        session.send()
        recovered = session.line().split()
        assert recovered == [b'RECOVERED', b'0', b'-1', b'1', b'64', b'40'], (recovered, session.errors())
        session.send()
        session.finish()
        assert not session.errors(), session.errors()
        assert not (session.buffer + session.process.stdout.read()).strip()
    report = dict(status='pass', binary=binary_identity(args.sigma), source=source,
                  ready=[v.decode() for v in ready], pending=[v.decode() for v in pending], rejected=[v.decode() for v in rejected],
                  recovered=[v.decode() for v in recovered],
                  limitation='owned override-redirect window, not an installation of a non-EWMH WM')
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print('pass: ignored fullscreen request timed out and WINDOW-ON recovered')
finally:
    connection.sock.close()
