#!/usr/bin/env python3
"""Minimize/restore a Sigma window on a real Linux X11/XWayland desktop.
ICCCM/EWMH requests target only the child window found by its _NET_WM_PID.
The desktop must support iconification and _NET_ACTIVE_WINDOW restoration.
"""
import json
import os
from pathlib import Path
import struct
import sys
import time

from linux_x11_test_support import SigmaSession, binary_identity, require_linux

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'experiments'))
from linux_x11_probe import Connection

require_linux()
binary = os.environ.get('SIGMA_TEST_BINARY', str(ROOT / 'zig-out/bin/sigma'))
connection = Connection(os.environ['DISPLAY'])


def property_bytes(window, atom):
    _, body = connection.reply(connection.request(20, body=struct.pack('<IIIII', window, atom, 0, 0, 256)))
    return body


def find_window(pid):
    connection.deadline = time.monotonic() + 5
    atom = connection.atom(b'_NET_WM_PID')
    pending = [connection.root]
    while pending:
        window = pending.pop()
        try:
            if property_bytes(window, atom)[:4] == struct.pack('<I', pid):
                return window
            _, body = connection.reply(connection.request(15, body=struct.pack('<I', window)))
            pending.extend(struct.unpack('<' + 'I' * (len(body) // 4), body))
        except RuntimeError as error:
            if 'X11 error code=3 ' not in str(error):
                raise
            # Another application's window can disappear during the traversal.
    raise AssertionError('child window not found')


def request(window, atom, value):
    connection.deadline = time.monotonic() + 5
    event = struct.pack('<BBHII5I', 33, 32, 0, window, connection.atom(atom), value, 0, 0, 0, 0)
    connection.request(25, body=struct.pack('<II', connection.root, (1 << 19) | (1 << 20)) + event)
    connection.sync()


def state(session):
    fields = session.line().split()
    assert fields[0] == b'STATE', fields
    return list(map(int, fields[1:]))


results = []
try:
    for wait_initial in (False, True):
        source = '''REQUIRE-GRAPHICS ALSO GRAPHICS 160 100 GFX-INIT
640 400 WINDOW-SIZE DISPLAY-WINDOW SHOW
: ACCEPT-STATE ." STATE " WINDOW-OPEN? . WINDOW-MINIMIZED? . WINDOW-FRAMES SWAP . . CR ;
'''
        if wait_initial:
            source += '2000 WINDOW-PAINT-WAIT DROP\n'
        source += '''ACCEPT-STATE KEY DROP 500 MS ACCEPT-STATE
SHOW 100 WINDOW-PAINT-WAIT ." MIN-WAIT " . CR
500 MS ACCEPT-STATE KEY DROP 500 MS ACCEPT-STATE
2000 WINDOW-PAINT-WAIT ." RESTORE-WAIT " . CR
ACCEPT-STATE WINDOW-CLOSE BYE'''
        with SigmaSession(binary, source, os.environ.copy()) as session:
            before = state(session)
            window = find_window(session.process.pid)
            request(window, b'WM_CHANGE_STATE', 3)
            time.sleep(.5)
            session.send()
            minimized = state(session)
            min_wait = session.line().split()
            pending = state(session)
            assert pending[0:2] == [-1, -1] and pending[2] == 2 and pending[3] < 2, pending
            assert minimized[0:2] == [-1, -1], minimized
            assert min_wait == [b'MIN-WAIT', b'0'], min_wait
            request(window, b'_NET_ACTIVE_WINDOW', 2)
            time.sleep(.5)
            session.send()
            restored = state(session)
            restored_wait = session.line().split()
            painted = state(session)
            session.finish()
            assert before[:2] == [-1, 0], before
            assert restored[:2] == [-1, 0], restored
            assert restored_wait == [b'RESTORE-WAIT', b'-1'], (restored_wait, restored, painted, session.errors())
            assert painted[2] == painted[3] == 2, painted
            results.append(dict(wait_initial=wait_initial, before=before, minimized=minimized,
                                restored=restored, painted=painted, pending=pending))
    # A pending image must not turn a close into a successful paint wait.
    source = '''REQUIRE-GRAPHICS ALSO GRAPHICS 160 100 GFX-INIT
640 400 WINDOW-SIZE DISPLAY-WINDOW SHOW ." READY" CR KEY DROP
500 MS SHOW ." WAITING" CR KEY DROP
5000 WINDOW-PAINT-WAIT ." CLOSE-WAIT " . WINDOW-OPEN? . CR BYE'''
    with SigmaSession(binary, source, os.environ.copy()) as session:
        assert session.line() == b'READY'
        window = find_window(session.process.pid)
        request(window, b'WM_CHANGE_STATE', 3)
        time.sleep(.5)
        session.send()
        assert session.line() == b'WAITING'
        session.send()
        connection.deadline = time.monotonic() + 5
        event = struct.pack('<BBHII5I', 33, 32, 0, window,
                            connection.atom(b'WM_PROTOCOLS'),
                            connection.atom(b'WM_DELETE_WINDOW'), 0, 0, 0, 0)
        connection.request(25, body=struct.pack('<II', window, 0) + event)
        connection.sync()
        closed = session.line().split()
        assert closed == [b'CLOSE-WAIT', b'0', b'0'], closed
        session.finish()
    print(json.dumps(dict(status='pass', binary=binary_identity(binary), cases=results,
                          close_while_waiting='pass'), indent=2))
finally:
    connection.sock.close()
