#!/usr/bin/env python3
"""Move only an owned Sigma window across the current X/RandR monitors.
Does not change monitor configuration, display scale or refresh rate.
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
source = '''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-WINDOW
4 2 GFX-INIT 64 40 WINDOW-SIZE SHOW 2000 WINDOW-PAINT-WAIT DROP
DISPLAYS CONSTANT ACCEPT-DISPLAYS
: ACCEPT-FOUR 2SWAP SWAP . . SWAP . . ;
: ACCEPT-MONITORS ACCEPT-DISPLAYS 0 DO ." MONITOR " I . I DISPLAY-RECT ACCEPT-FOUR CR LOOP ;
ACCEPT-MONITORS ." READY " ACCEPT-DISPLAYS . CR
: ACCEPT-MOVES ACCEPT-DISPLAYS 1+ 0 DO KEY DROP 400 MS
." MOVE " WINDOW-DISPLAY . WINDOW-CHANGES . WINDOW-PIXELS SWAP . . CR LOOP ;
ACCEPT-MOVES KEY DROP WINDOW-CLOSE BYE'''
connection = Connection(os.environ['DISPLAY'])


def find_window(pid):
    connection.deadline = time.monotonic() + 5
    atom = connection.atom(b'_NET_WM_PID')
    pending = [connection.root]
    while pending:
        window = pending.pop()
        try:
            _, value = connection.reply(connection.request(20, body=struct.pack('<IIIII', window, atom, 0, 0, 1)))
            if value[:4] == struct.pack('<I', pid):
                return window
            _, children = connection.reply(connection.request(15, body=struct.pack('<I', window)))
        except RuntimeError as error:
            if 'X11 error code=3 ' in str(error):
                continue
            raise
        pending.extend(struct.unpack('<' + 'I' * (len(children) // 4), children))
    raise AssertionError('owned Sigma window not found')


def raw_monitors():
    connection.deadline = time.monotonic() + 5
    extension, _ = connection.reply(connection.request(98, body=struct.pack('<H2x', 5) + b'RANDR' + b'\0' * 3))
    assert extension[8] != 0, 'RandR required'
    opcode = extension[9]
    connection.reply(connection.request(opcode, 0, struct.pack('<II', 1, 5)))
    header, body = connection.reply(connection.request(opcode, 42, struct.pack('<IB3x', connection.root, 1)))
    count = struct.unpack_from('<I', header, 12)[0]
    rows = []
    offset = 0
    for _ in range(count):
        _, primary, _, outputs, x, y, width, height, _, _ = struct.unpack_from('<IBBHhhHHII', body, offset)
        rows.append(dict(primary=bool(primary), rect=[x, y, width, height]))
        offset += 24 + outputs * 4
    return rows


try:
    with SigmaSession(binary, source, os.environ.copy()) as session:
        monitors = []
        while True:
            line = session.line().split()
            if line[0] == b'READY':
                assert int(line[1]) == len(monitors) > 0, line
                break
            assert line[0] == b'MONITOR', line
            monitors.append(list(map(int, line[1:])))
        raw = raw_monitors()
        assert len(raw) == len(monitors), (raw, monitors)
        primary = next((row for row in raw if row['primary']), raw[0])['rect'][:2]
        for monitor, row in zip(monitors, raw):
            x, y, width, height = row['rect']
            assert monitor[1:] == [x - primary[0], y - primary[1], width, height], (monitor, row)
        window = find_window(session.process.pid)
        moves = []
        for monitor in monitors + monitors[:1]:
            index, x, y, width, height = monitor
            target = [primary[0] + x + (width - 64) // 2, primary[1] + y + (height - 40) // 2]
            connection.deadline = time.monotonic() + 5
            atom = connection.atom(b'_NET_MOVERESIZE_WINDOW')
            event = struct.pack('<BBHII5I', 33, 32, 0, window, atom,
                                1 | (3 << 8) | (2 << 12), target[0] & 0xffffffff,
                                target[1] & 0xffffffff, 0, 0)
            connection.request(25, body=struct.pack('<II', connection.root, (1 << 19) | (1 << 20)) + event)
            connection.sync()
            time.sleep(.3)
            session.send()
            actual = session.line().split()
            assert actual[0] == b'MOVE', actual
            actual = list(map(int, actual[1:]))
            location, _ = connection.reply(connection.request(40, body=struct.pack('<IIhh', window, connection.root, 0, 0)))
            origin = list(struct.unpack_from('<hh', location, 12))
            assert actual[0] == index and actual[2:] == [64, 40], (monitor, actual, target, origin)
            raw_x, raw_y, _, _ = raw[index]['rect']
            assert raw_x <= origin[0] and origin[0] + 64 <= raw_x + width, (raw[index], origin)
            assert raw_y <= origin[1] and origin[1] + 40 <= raw_y + height, (raw[index], origin)
            if moves and moves[-1]['monitor'] != index:
                assert actual[1] > moves[-1]['changes'], (moves, actual)
            moves.append(dict(monitor=index, changes=actual[1], pixels=actual[2:], requested_origin=target, actual_origin=origin))
        session.send()
        session.finish()
        trailer = session.buffer + session.process.stdout.read()
        assert not trailer.strip(), trailer
        assert not session.errors(), session.errors()
    print(json.dumps(dict(status='pass', binary=binary_identity(binary), monitors=monitors, raw_monitors=raw, moves=moves,
                          multi_monitor=len(monitors) > 1), indent=2))
finally:
    connection.sock.close()
