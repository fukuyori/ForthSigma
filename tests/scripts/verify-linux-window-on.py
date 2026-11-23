#!/usr/bin/env python3
"""Verify WINDOW-ON on owned windows against the desktop's RandR geometry.
Does not change monitor configuration or simulate physical disconnection.
"""
import argparse
import hashlib
import json
import os
import signal
from pathlib import Path
import struct
import sys
import tempfile
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
parser.add_argument('--verbose', action='store_true')
parser.add_argument('--coordinate-quantum', type=int, default=1, choices=(1, 2))
args = parser.parse_args()
connection = Connection(os.environ['DISPLAY'])
source_directory = None


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


def property_values(window, name, offset=0, count=32):
    connection.deadline = time.monotonic() + 5
    _, body = connection.reply(connection.request(20, body=struct.pack(
        '<IIIII', window, connection.atom(name), 0, offset, count)))
    return list(struct.unpack('<' + 'I' * (len(body) // 4), body))


def work_area(monitor):
    x, y, w, h = monitor['rect']
    desktop = property_values(connection.root, b'_NET_CURRENT_DESKTOP', count=1)
    work = property_values(connection.root, b'_NET_WORKAREA', offset=4 * (desktop[0] if desktop else 0), count=4)
    if len(work) == 4:
        wx, wy, ww, wh = work
        # The EWMH coordinates are signed even though stored as CARDINAL.
        wx, wy = (v if v < 2**31 else v - 2**32 for v in (wx, wy))
        left, top = max(x, wx), max(y, wy)
        right, bottom = min(x + w, wx + ww), min(y + h, wy + wh)
        if right > left and bottom > top:
            return [left, top, right - left, bottom - top]
    return [x, y, w, h]


try:
    monitors = raw_monitors()
    assert len(monitors) > 1, 'at least two desktop monitors required'
    steps = []
    for index in range(len(monitors)):
        steps += [(f'before-{index}', f'WINDOW-CLOSE {index} WINDOW-ON', -1, False),
                  (f'open-{index}', 'SHOW 2000 WINDOW-PAINT-WAIT DROP', index, False)]
    for index in range(len(monitors)):
        steps.append((f'move-{index}', f'{index} WINDOW-ON', index, False))
    steps.append(('fullscreen', 'TRUE FULLSCREEN', len(monitors) - 1, True))
    for sequence, index in enumerate(list(range(len(monitors))) + [0]):
        steps.append((f'fullscreen-move-{sequence}-{index}', f'{index} WINDOW-ON', index, True))
    steps += [('normal', 'FALSE FULLSCREEN', 0, False),
              ('unspecified', '-1 WINDOW-ON', 0, False),
              ('invalid-high', "DISPLAYS ' WINDOW-ON CATCH . DROP", 0, False),
              ('invalid-low', "-2 ' WINDOW-ON CATCH . DROP", 0, False)]
    steps += [('fullscreen-roundtrip', 'TRUE FULLSCREEN', 0, True),
              ('normal-roundtrip', 'FALSE FULLSCREEN', 0, False),
              ('large-primary', '0 WINDOW-ON 300 MS 2200 1200 WINDOW-SIZE SHOW 500 MS 0 WINDOW-ON', 0, False),
              ('large-fullscreen', 'TRUE FULLSCREEN', 0, True),
              ('large-fullscreen-move', f'{len(monitors) - 1} WINDOW-ON', len(monitors) - 1, True),
              ('large-normal', 'FALSE FULLSCREEN', len(monitors) - 1, False)]
    steps += [('large-rapid-primary', '0 WINDOW-ON 300 MS 64 40 WINDOW-SIZE SHOW 150 MS 2200 1200 WINDOW-SIZE SHOW 300 MS 0 WINDOW-ON', 0, False),
              ('large-rapid-enter', 'TRUE FULLSCREEN', 0, True),
              ('large-rapid-place', f'{len(monitors) - 1} WINDOW-ON 3 MS 0 WINDOW-ON', 0, True),
              ('large-rapid-return', 'FALSE FULLSCREEN', 0, False)]
    steps += [('reset-small', '64 40 WINDOW-SIZE SHOW 300 MS 0 WINDOW-ON', 0, False),
              ('cancel-enter', 'TRUE FULLSCREEN', 0, True),
              ('cancel-and-place', f'FALSE FULLSCREEN {len(monitors) - 1} WINDOW-ON', len(monitors) - 1, False),
              ('user-move', '', len(monitors) - 1, False),
              ('user-enter', 'TRUE FULLSCREEN', len(monitors) - 1, True),
              ('user-return', 'FALSE FULLSCREEN', len(monitors) - 1, False),
              ('create-full', 'WINDOW-CLOSE 0 WINDOW-ON TRUE FULLSCREEN SHOW', 0, True),
              ('create-full-move', f'{len(monitors) - 1} WINDOW-ON', len(monitors) - 1, True),
              ('create-full-return', 'FALSE FULLSCREEN', len(monitors) - 1, False),
              ('enter-and-place', 'TRUE FULLSCREEN 0 WINDOW-ON', 0, True),
              ('rapid-place', f'{len(monitors) - 1} WINDOW-ON 3 MS 0 WINDOW-ON 3 MS {len(monitors) - 1} WINDOW-ON', len(monitors) - 1, True),
              ('rapid-return', 'FALSE FULLSCREEN', len(monitors) - 1, False),
              ('frame-during-place', 'TRUE FULLSCREEN 0 WINDOW-ON 128 80 WINDOW-SIZE SHOW', 0, True),
              ('frame-return', 'FALSE FULLSCREEN', 0, False)]
    source = 'REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-WINDOW DISPLAYS DROP 4 2 GFX-INIT 64 40 WINDOW-SIZE\n'
    for name, action, _, _ in steps:
        source += f'KEY DROP {action} 1000 MS ." STEP {name} " WINDOW-DISPLAY . WINDOW-PIXELS SWAP . . FULLSCREEN? . CR\n'
    source += 'KEY DROP WINDOW-CLOSE BYE'
    rows = []
    normal_size = [64, 40]
    source_directory = tempfile.TemporaryDirectory(prefix='sigma-window-on-')
    source_file = Path(source_directory.name) / 'accept.fs'
    source_file.write_text(source)
    with SigmaSession(str(args.sigma.resolve()), f'INCLUDE {source_file}', os.environ.copy()) as session:
        for name, _, expected, fullscreen in steps:
            if name == 'user-move':
                window = find_window(session.process.pid)
                wx, wy, _, _ = work_area(monitors[expected])
                event = struct.pack('<BBHII5I', 33, 32, 0, window,
                                    connection.atom(b'_NET_MOVERESIZE_WINDOW'),
                                    1 | (3 << 8) | (2 << 12), wx + 80, wy + 80, 0, 0)
                connection.deadline = time.monotonic() + 5
                connection.request(25, body=struct.pack('<II', connection.root, (1 << 19) | (1 << 20)) + event)
                connection.sync()
            session.send()
            fields = session.line(timeout=10).split()
            if args.verbose:
                print(fields, file=sys.stderr)
            if name.startswith('invalid-'):
                assert fields.pop(0) == b'-24', fields
            assert fields[:2] == [b'STEP', name.encode()], fields
            actual, width, height, full = map(int, fields[2:])
            assert actual == expected and full == (-1 if fullscreen else 0), (name, fields, session.errors())
            row = dict(phase=name, monitor=actual, pixels=[width, height], fullscreen=bool(full))
            if expected >= 0:
                window = find_window(session.process.pid)
                connection.deadline = time.monotonic() + 5
                location, _ = connection.reply(connection.request(40, body=struct.pack('<IIhh', window, connection.root, 0, 0)))
                origin = list(struct.unpack_from('<hh', location, 12))
                geometry, _ = connection.reply(connection.request(14, body=struct.pack('<I', window)))
                size = list(struct.unpack_from('<HH', geometry, 16))
                x, y, w, h = monitors[expected]['rect']
                assert size == [width, height], (name, size, fields)
                if fullscreen:
                    assert origin == [x, y] and size == [w, h], (name, origin, size, monitors[expected])
                else:
                    if name == 'reset-small':
                        normal_size = [64, 40]
                    if name in ('large-primary', 'large-rapid-primary'):
                        normal_size = [2200, 1200]
                    ext = property_values(window, b'_NET_FRAME_EXTENTS', count=4) or [0] * 4
                    wx, wy, ww, wh = work_area(monitors[expected])
                    normal_size = [min(normal_size[0], max(1, ww - ext[0] - ext[1])),
                                   min(normal_size[1], max(1, wh - ext[2] - ext[3]))]
                    assert size == normal_size, (name, size, normal_size, session.errors())
                    assert x <= origin[0] <= x + w - width and y <= origin[1] <= y + h - height, (name, origin, monitors[expected])
                extents = property_values(window, b'_NET_FRAME_EXTENTS', count=4) or [0] * 4
                states = property_values(window, b'_NET_WM_STATE')
                assert (connection.atom(b'_NET_WM_STATE_FULLSCREEN') in states) == fullscreen, (name, states)
                if not fullscreen:
                    if name == 'user-return':
                        user_row = next(row for row in rows if row['phase'] == 'user-move')
                        assert origin == user_row['origin'], (name, origin, user_row)
                    elif name == 'user-move':
                        wx, wy, _, _ = work_area(monitors[expected])
                        assert origin == [wx + 80 + extents[0], wy + 80 + extents[2]], (name, origin, extents)
                    elif name in ('unspecified', 'invalid-high', 'invalid-low'):
                        assert origin == rows[-1]['origin'], (name, origin, rows[-1])
                    else:
                        wx, wy, ww, wh = work_area(monitors[expected])
                        left, right, top, bottom = extents
                        expected_origin = [wx + (ww - width - left - right) // 2 + left,
                                           wy + (wh - height - top - bottom) // 2 + top]
                        assert all(abs(a - b) < args.coordinate_quantum for a, b in zip(origin, expected_origin)), (name, origin, expected_origin, extents)
                        row['expected_origin'] = expected_origin
                row.update(origin=origin, x11_pixels=size, extents=extents)
            else:
                assert [width, height] == [0, 0], (name, fields, session.errors())
            rows.append(row)
        session.send()
        session.finish()
        assert not session.errors(), session.errors()
        assert not (session.buffer + session.process.stdout.read()).strip()
    assert raw_monitors() == monitors, 'monitor configuration changed during the test'
    report = dict(status='pass', binary=binary_identity(args.sigma), monitors=monitors,
                  phases=rows, source=source, source_transport='temporary INCLUDE file', coordinate_quantum=args.coordinate_quantum,
                  work_areas=[work_area(monitor) for monitor in monitors],
                  environment={k: os.environ.get(k) for k in ('XDG_SESSION_TYPE', 'DISPLAY')},
                  source_sha256={name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                                 for name in ('src/host_window_linux.zig', 'tests/scripts/verify-linux-window-on.py')},
                  limitations=['physical disconnection not tested',
                                'this script does not configure or identify display scale; coordinate quantum is supplied by the caller'])
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print('pass', len(rows), 'phases')
finally:
    connection.sock.close()
    if source_directory is not None:
        source_directory.cleanup()
