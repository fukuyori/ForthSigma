#!/usr/bin/env python3
"""Check owned native window placement against independent Win32 rectangles.

Does not change monitor configuration. Physical unplug/replug remains a manual test.
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
import json
from pathlib import Path
import time

from windows_display_test_support import SigmaSession, binary_identity
from windows_monitor_probe import snapshot

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma.exe')
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--trace', type=Path, help='Write native state before and after every external window operation')
args = parser.parse_args()
user = c.WinDLL('user32', use_last_error=True)
# Match Sigma's per-monitor-aware coordinate space, without changing the desktop.
user.SetThreadDpiAwarenessContext.argtypes = [c.c_void_p]
user.SetThreadDpiAwarenessContext.restype = c.c_void_p
assert user.SetThreadDpiAwarenessContext(c.c_void_p(-4))
callback = c.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
user.EnumWindows.argtypes = [callback, w.LPARAM]
user.GetWindowThreadProcessId.argtypes = [w.HWND, c.POINTER(w.DWORD)]
user.GetClassNameW.argtypes = [w.HWND, w.LPWSTR, c.c_int]
user.GetWindowRect.argtypes = [w.HWND, c.POINTER(w.RECT)]
user.GetClientRect.argtypes = [w.HWND, c.POINTER(w.RECT)]
user.GetDpiForWindow.argtypes = [w.HWND]
user.GetDpiForWindow.restype = w.UINT
user.MonitorFromWindow.argtypes = [w.HWND, w.DWORD]
user.MonitorFromWindow.restype = w.HANDLE
user.SetWindowPos.argtypes = [w.HWND, w.HWND, c.c_int, c.c_int, c.c_int, c.c_int, w.UINT]
user.PostMessageW.argtypes = [w.HWND, w.UINT, w.WPARAM, w.LPARAM]
user.ShowWindow.argtypes = [w.HWND, c.c_int]
user.IsIconic.argtypes = [w.HWND]
user.IsZoomed.argtypes = [w.HWND]
user.SendMessageTimeoutW.argtypes = [w.HWND, w.UINT, w.WPARAM, w.LPARAM, w.UINT, w.UINT, c.POINTER(c.c_size_t)]
user.SendMessageTimeoutW.restype = c.c_size_t


class Placement(c.Structure):
    _fields_ = [('size', w.UINT), ('flags', w.UINT), ('show', w.UINT),
                ('minimum', w.POINT), ('maximum', w.POINT), ('normal', w.RECT)]


user.GetWindowPlacement.argtypes = [w.HWND, c.POINTER(Placement)]


def trace(phase, hwnd):
    if args.trace is None:
        return
    p, client = Placement(), w.RECT()
    p.size = c.sizeof(p)
    assert user.GetWindowPlacement(hwnd, c.byref(p)) and user.GetClientRect(hwnd, c.byref(client))
    state = dict(phase=phase, outer=rect(hwnd), client=[client.right, client.bottom],
                 iconic=bool(user.IsIconic(hwnd)), zoomed=bool(user.IsZoomed(hwnd)),
                 show=p.show, normal=[p.normal.left, p.normal.top, p.normal.right, p.normal.bottom],
                 dpi=user.GetDpiForWindow(hwnd))
    with args.trace.open('a', encoding='utf-8') as output:
        output.write(json.dumps(state) + '\n')


def windows(pid):
    found = []
    @callback
    def visit(hwnd, unused):
        owner = w.DWORD()
        user.GetWindowThreadProcessId(hwnd, c.byref(owner))
        name = c.create_unicode_buffer(128)
        user.GetClassNameW(hwnd, name, len(name))
        if owner.value == pid and name.value == 'SigmaGraphicsWindow':
            found.append(hwnd)
        return True
    assert user.EnumWindows(visit, 0)
    return found


def rect(hwnd):
    r = w.RECT()
    assert user.GetWindowRect(hwnd, c.byref(r))
    return [r.left, r.top, r.right - r.left, r.bottom - r.top]


source = '''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-WINDOW
: FOUR 2SWAP SWAP . . SWAP . . ;
: MONITORS DISPLAYS DUP . DISPLAY-PRIMARY . CR
0 DO I . I DISPLAY-RECT FOUR I DISPLAY-WORK FOUR I DISPLAY-SCALE SWAP . . I DISPLAY-HZ SWAP . . CR LOOP ; MONITORS
'''
# A preliminary process tells us the enumeration count; the tested process records
# its own enumeration too, so a configuration change cannot silently pass.
from windows_display_test_support import run
probe = run(args.sigma, source + 'BYE').splitlines()
count = int(probe[0].split()[0])
assert count > 0
actions = []
for i in range(count):
    actions += [(f'preselect-{i}', f'WINDOW-CLOSE {i} WINDOW-ON', i, 'closed'),
                (f'open-{i}', '4 2 GFX-INIT 160 100 WINDOW-SIZE SHOW', i, 'normal')]
for i in reversed(range(count)):
    actions += [(f'move-{i}', f'{i} WINDOW-ON', i, 'normal'),
                (f'fullscreen-{i}', 'TRUE FULLSCREEN', i, 'full')]
    j = (i + 1) % count
    actions += [(f'fullscreen-move-{i}-{j}', f'{j} WINDOW-ON', j, 'full'),
                (f'restore-{j}', 'FALSE FULLSCREEN', j, 'normal'),
                (f'unchanged-{j}', '-1 WINDOW-ON', j, 'normal')]
for i in range(count):
    actions += [(f'reopen-setup-{i}', f'WINDOW-CLOSE FALSE FULLSCREEN {i} WINDOW-ON SHOW', i, 'normal'),
                (f'reopen-full-{i}', 'TRUE FULLSCREEN', i, 'full'),
                (f'closed-full-{i}', 'WINDOW-CLOSE', i, 'closed'),
                (f'reopen-as-normal-{i}', f'FALSE FULLSCREEN {i} WINDOW-ON SHOW', i, 'normal'),
                (f'reopen-full-again-{i}', 'TRUE FULLSCREEN', i, 'full'),
                (f'closed-still-full-{i}', 'WINDOW-CLOSE', i, 'closed'),
                (f'reopen-still-full-{i}', 'SHOW', i, 'full'),
                (f'minimize-full-move-{i}', f'{(i + 1) % count} WINDOW-ON', (i + 1) % count, 'minimized-full'),
                (f'restore-minimized-full-{i}', '', (i + 1) % count, 'full'),
                (f'full-return-{i}', f'{i} WINDOW-ON', i, 'full'),
                (f'minimize-full-cancel-move-{i}', f'{(i + 1) % count} WINDOW-ON', (i + 1) % count, 'minimized-full'),
                (f'cancel-full-while-minimized-{i}', 'FALSE FULLSCREEN', (i + 1) % count, 'cancel-minimized'),
                (f'restore-minimized-cancel-{i}', '', (i + 1) % count, 'normal'),
                (f'full-return-after-cancel-{i}', f'{i} WINDOW-ON TRUE FULLSCREEN', i, 'full'),
                (f'synthetic-display-change-{i}', '', i, 'full'),
                (f'restore-after-reopen-{i}', 'FALSE FULLSCREEN', i, 'normal'),
                (f'synthetic-workarea-change-{i}', '', i, 'normal'),
                (f'minimize-move-{i}', f'{(i + 1) % count} WINDOW-ON', (i + 1) % count, 'minimized'),
                (f'restore-minimized-{i}', '', (i + 1) % count, 'normal'),
                (f'maximize-move-{i}', f'{i} WINDOW-ON', i, 'maximized'),
                (f'minimize-maximized-move-{i}', f'{(i + 1) % count} WINDOW-ON', (i + 1) % count, 'minimized'),
                (f'restore-minimized-maximized-{i}', '', (i + 1) % count, 'maximized'),
                (f'maximized-return-{i}', f'{i} WINDOW-ON', i, 'maximized'),
                (f'restore-maximized-{i}', '', i, 'normal')]
for name, action, _, _ in actions:
    source += f'KEY DROP {action} 500 MS ." STATE {name} " WINDOW-OPEN? . WINDOW-DISPLAY . FULLSCREEN? . WINDOW-PIXELS SWAP . . WINDOW-CHANGES . CR\n'
source += 'KEY DROP BYE'
rows = []
independent_before = snapshot()
with SigmaSession(args.sigma, source) as session:
    header = list(map(int, session.line().split()))
    assert header[0] == count
    monitors = []
    for i in range(count):
        values = list(map(int, session.line().split()))
        assert len(values) == 13 and values[0] == i, values
        monitors.append(dict(index=i, rect=values[1:5], work=values[5:9],
                             scale=values[9:11], hz=values[11:13]))
    assert len(independent_before) == count, (independent_before, monitors)
    assert monitors[header[1]]['rect'] == next(m['rect'] for m in independent_before if m['primary'])
    assert [list(map(int, line.split())) for line in probe[1:]] == [
        [m['index'], *m['rect'], *m['work'], *m['scale'], *m['hz']] for m in monitors]
    for monitor in monitors:
        matches = [m for m in independent_before if m['rect'] == monitor['rect']]
        assert len(matches) == 1, (monitor, independent_before)
        independent = matches[0]
        assert monitor['work'] == independent['work'], (monitor, independent)
        numerator, denominator = monitor['scale']
        assert denominator > 0 and numerator * 96 == independent['dpi'][0] * denominator
        monitor['independent'] = independent
    for name, action, target, mode in actions:
        if name.startswith(('synthetic-', 'minimize-', 'restore-minimized-', 'maximize-move-', 'restore-maximized-')):
            hwnd = windows(session.process.pid)[0]
            trace(name + '-before', hwnd)
            if name.startswith('synthetic-display-change-'):
                x, y, _, _ = monitors[target]['rect']
                assert user.SetWindowPos(hwnd, None, x + 10, y + 10, 100, 100, 0x14)
                assert user.PostMessageW(hwnd, 0x7E, 32, 0)
            elif name.startswith('synthetic-workarea-change-'):
                result = c.c_size_t()
                assert user.SendMessageTimeoutW(hwnd, 0x1A, 0x2F, 0, 2, 2000, c.byref(result))
            elif name.startswith('minimize-'):
                user.ShowWindow(hwnd, 6)
            elif name.startswith('maximize-move-'):
                user.ShowWindow(hwnd, 3)
            else:
                user.ShowWindow(hwnd, 9)
            trace(name + '-after-operation', hwnd)
        session.send()
        fields = session.line().split()
        assert fields[:2] == [b'STATE', name.encode()], fields
        opened, display, full, pixel_width, pixel_height, changes = map(int, fields[2:])
        handles = windows(session.process.pid)
        if handles:
            trace(name + '-settled', handles[0])
        row = dict(phase=name, target=target, mode=mode, open=opened, display=display, fullscreen=full,
                   pixels=[pixel_width, pixel_height], changes=changes)
        if mode == 'cancel-minimized':
            assert opened == -1 and full == 0 and len(handles) == 1, row
        elif mode in ('minimized', 'minimized-full'):
            assert opened == -1 and len(handles) == 1 and user.IsIconic(handles[0]), row
        elif mode == 'maximized':
            assert opened == -1 and display == target and len(handles) == 1 and user.IsZoomed(handles[0]), row
            assert user.MonitorFromWindow(handles[0], 2) == monitors[target]['independent']['id'], row
        elif mode == 'closed':
            assert opened == 0 and not handles, row
        else:
            assert opened == -1 and display == target and len(handles) == 1, row
            assert full == (-1 if mode == 'full' else 0), row
            # The Forth report and the independent rectangle must both settle.
            deadline = time.monotonic() + 3
            while True:
                actual = rect(handles[0])
                if mode == 'full':
                    valid = actual == monitors[target]['independent']['rect']
                else:
                    x, y, width, height = actual
                    wx, wy, ww, wh = monitors[target]['independent']['work']
                    valid = (width <= ww and height <= wh and
                             x == wx + (ww - width) // 2 and y == wy + (wh - height) // 2)
                if valid or time.monotonic() >= deadline:
                    break
                time.sleep(.02)
            row['outer_rect'] = actual
            assert valid, (row, monitors[target])
            client = w.RECT()
            assert user.GetClientRect(handles[0], c.byref(client))
            assert [client.right, client.bottom] == row['pixels'], row
            assert user.MonitorFromWindow(handles[0], 2) == monitors[target]['independent']['id'], row
            row['dpi'] = user.GetDpiForWindow(handles[0])
            assert row['dpi'] == monitors[target]['independent']['dpi'][0], row
            if mode == 'normal':
                n, d = monitors[target]['scale']
                assert row['pixels'] == [160 * n // d, 100 * n // d], row
        if name.startswith('synthetic-workarea-change-'):
            assert changes > rows[-1]['changes'], (row, rows[-1])
        rows.append(row)
    session.send()
    session.finish()
assert snapshot() == independent_before, 'Display configuration changed during the test'
report = dict(status='pass', binary=binary_identity(args.sigma), monitors=monitors, phases=rows,
              limitations=['No physical disconnect/reconnect',
                           'Only the enumerated monitor scales and refresh rates were exercised'])
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(f'PASS: {count} monitors, {len(rows)} phases; {args.output}')
