#!/usr/bin/env python3
"""Deliver a synthetic RandR resource event to an owned Sigma window.
Checks WINDOW-CHANGES invalidation without changing monitors or window geometry.
This is an event-routing regression, not physical hotplug acceptance.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import select
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
if not __debug__:
    raise SystemExit('verification requires assertions enabled')
source = '''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-WINDOW
4 2 GFX-INIT 320 200 WINDOW-SIZE SHOW 2000 WINDOW-PAINT-WAIT DROP
: REPORT ." STATE " DISPLAYS . WINDOW-CHANGES . WINDOW-DISPLAY . WINDOW-PIXELS SWAP . . WINDOW-OPEN? . CR ;
300 MS REPORT KEY DROP 300 MS REPORT KEY DROP WINDOW-CLOSE BYE'''
connection = Connection(os.environ['DISPLAY'])


def values(window, name, count=4096):
    connection.deadline = time.monotonic() + 5
    _, body = connection.reply(connection.request(20, body=struct.pack(
        '<IIIII', window, connection.atom(name), 0, 0, count)))
    return list(struct.unpack('<' + 'I' * (len(body) // 4), body))


def state(session):
    row = session.line().split()
    assert len(row) == 7 and row[0] == b'STATE', row
    return dict(zip(('displays', 'changes', 'display', 'width', 'height', 'open'), map(int, row[1:])))


try:
    with SigmaSession(str(args.sigma.resolve()), source, os.environ.copy()) as session:
        before = state(session)
        clients = values(connection.root, b'_NET_CLIENT_LIST')
        owned = [window for window in clients if values(window, b'_NET_WM_PID', 1) == [session.process.pid]]
        assert len(owned) == 1, owned
        connection.deadline = time.monotonic() + 5
        extension, _ = connection.reply(connection.request(98, body=struct.pack('<H2x', 5) + b'RANDR' + b'\0' * 3))
        assert extension[8] and extension[10]
        event = bytearray(32)
        event[0] = extension[10] + 1  # RRNotify
        event[1] = 5  # RRNotify_ResourceChange
        struct.pack_into('<I', event, 8, connection.root)
        connection.request(25, body=struct.pack('<II', owned[0], 0) + event)
        connection.sync()
        session.send()
        after = state(session)
        assert after['changes'] > before['changes'], (before, after)
        assert {k: v for k, v in before.items() if k != 'changes'} == {k: v for k, v in after.items() if k != 'changes'}
        assert before['open'] == -1 and before['width'] == 320 and before['height'] == 200
        session.send()
        session.finish()
        assert not session.errors(), session.errors()
        assert not session.buffer.strip()
        assert select.select([session.process.stdout], [], [], 2)[0], 'stdout EOF deadline'
        assert os.read(session.process.stdout.fileno(), 4096) == b''
    report = dict(status='pass', physical_hotplug_tested=False, synthetic_event=True,
                  binary=binary_identity(args.sigma), source=source, before=before, after=after,
                  source_sha256={name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                                 for name in ('src/host_display_linux.zig', 'src/host_window_linux.zig', 'tests/scripts/verify-linux-display-change-events.py')})
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print('pass: synthetic RandR event increments changes without changing geometry')
finally:
    connection.sock.close()
