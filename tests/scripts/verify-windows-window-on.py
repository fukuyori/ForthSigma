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

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma.exe')
parser.add_argument('--output', type=Path, required=True)
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
: MONITORS DISPLAYS DUP . CR
0 DO I . I DISPLAY-RECT FOUR I DISPLAY-WORK FOUR I DISPLAY-SCALE SWAP . . I DISPLAY-HZ SWAP . . CR LOOP ; MONITORS
'''
# A preliminary process tells us the enumeration count; the tested process records
# its own enumeration too, so a configuration change cannot silently pass.
from windows_display_test_support import run
probe = run(args.sigma, source + 'BYE').splitlines()
count = int(probe[0])
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
for name, action, _, _ in actions:
    source += f'KEY DROP {action} 500 MS ." STATE {name} " WINDOW-OPEN? . WINDOW-DISPLAY . FULLSCREEN? . CR\n'
source += 'KEY DROP BYE'
rows = []
with SigmaSession(args.sigma, source) as session:
    assert int(session.line()) == count
    monitors = []
    for i in range(count):
        values = list(map(int, session.line().split()))
        assert len(values) == 13 and values[0] == i, values
        monitors.append(dict(index=i, rect=values[1:5], work=values[5:9],
                             scale=values[9:11], hz=values[11:13]))
    for name, action, target, mode in actions:
        session.send()
        fields = session.line().split()
        assert fields[:2] == [b'STATE', name.encode()], fields
        opened, display, full = map(int, fields[2:])
        handles = windows(session.process.pid)
        row = dict(phase=name, target=target, mode=mode, open=opened, display=display, fullscreen=full)
        if mode == 'closed':
            assert opened == 0 and not handles, row
        else:
            assert opened == -1 and display == target and len(handles) == 1, row
            assert full == (-1 if mode == 'full' else 0), row
            # The Forth report and the independent rectangle must both settle.
            deadline = time.monotonic() + 3
            while True:
                actual = rect(handles[0])
                if mode == 'full':
                    valid = actual == monitors[target]['rect']
                else:
                    x, y, width, height = actual
                    wx, wy, ww, wh = monitors[target]['work']
                    valid = (width <= ww and height <= wh and
                             x == wx + (ww - width) // 2 and y == wy + (wh - height) // 2)
                if valid or time.monotonic() >= deadline:
                    break
                time.sleep(.02)
            row['outer_rect'] = actual
            assert valid, (row, monitors[target])
        rows.append(row)
    session.send()
    session.finish()
report = dict(status='pass', binary=binary_identity(args.sigma), monitors=monitors, phases=rows,
              limitations=['No physical disconnect/reconnect',
                           'Only the enumerated monitor scales and refresh rates were exercised'])
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(f'PASS: {count} monitors, {len(rows)} phases; {args.output}')
