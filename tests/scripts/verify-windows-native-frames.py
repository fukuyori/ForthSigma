#!/usr/bin/env python3
"""Owned native window paint waits; compositor results are not physical presentation."""
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
callback = c.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
user.EnumWindows.argtypes = [callback, w.LPARAM]
user.GetWindowThreadProcessId.argtypes = [w.HWND, c.POINTER(w.DWORD)]
user.GetClassNameW.argtypes = [w.HWND, w.LPWSTR, c.c_int]
user.ShowWindow.argtypes = [w.HWND, c.c_int]
user.IsIconic.argtypes = [w.HWND]
user.PostMessageW.argtypes = [w.HWND, w.UINT, w.WPARAM, w.LPARAM]


def window(pid):
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
    assert len(found) == 1, found
    return found[0]


source = '''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-WINDOW
DISPLAYS DUP . CR
: RATES 0 DO I WINDOW-ON SHOW 2000 WINDOW-PAINT-WAIT DROP 300 MS
I . I DISPLAY-HZ SWAP . . VSYNC-WAIT . CR LOOP ;
4 2 GFX-INIT 160 100 WINDOW-SIZE RATES
." READY " 2000 WINDOW-PAINT-WAIT . CR
KEY DROP SHOW ." MINIMIZED " 150 WINDOW-PAINT-WAIT . WINDOW-MINIMIZED? . CR
KEY DROP ." WAITING" CR KEY DROP 5000 WINDOW-PAINT-WAIT . WINDOW-OPEN? . CR
KEY DROP ." CLOSED " 5000 WINDOW-PAINT-WAIT . CR
KEY DROP SHOW ." REOPENED " 2000 WINDOW-PAINT-WAIT . CR
KEY DROP BYE'''
with SigmaSession(args.sigma, source) as session:
    count = int(session.line())
    rates = [list(map(int, session.line().split())) for _ in range(count)]
    assert all(len(row) == 4 and row[0] == i and row[3] in (0, -1) for i, row in enumerate(rates)), rates
    assert session.line().split() == [b'READY', b'-1']
    hwnd = window(session.process.pid)
    user.ShowWindow(hwnd, 6)  # SW_MINIMIZE, only our window.
    deadline = time.monotonic() + 3
    while not user.IsIconic(hwnd) and time.monotonic() < deadline:
        time.sleep(.01)
    assert user.IsIconic(hwnd)
    session.send()
    minimized = session.line().split()
    assert minimized == [b'MINIMIZED', b'0', b'-1'], minimized
    session.send()
    assert session.line() == b'WAITING'
    session.send()
    time.sleep(.1)
    started = time.monotonic()
    assert user.PostMessageW(hwnd, 0x10, 0, 0)  # WM_CLOSE
    closed_during = session.line().split()
    elapsed = time.monotonic() - started
    assert closed_during == [b'0', b'0'] and elapsed < 2, (closed_during, elapsed)
    session.send()
    assert session.line().split() == [b'CLOSED', b'0']
    session.send()
    assert session.line().split() == [b'REOPENED', b'-1']
    session.send()
    session.finish()
report = dict(status='pass', binary=binary_identity(args.sigma), source=source,
              rates_index_num_den_vsync=rates, minimized_wait=False,
              close_during_wait_seconds=elapsed, closed_wait=False, reopened_wait=True,
              limitations=['DwmFlush unavailable environment not exercised',
                           'No claim of physical presentation or distinct compositor pacing per monitor'])
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(f'PASS: {count} monitor compositor calls, minimized/closing/closed/reopened waits')
