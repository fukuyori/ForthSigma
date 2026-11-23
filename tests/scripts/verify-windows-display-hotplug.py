#!/usr/bin/env python3
"""Record Windows secondary-monitor removal/reconnection without changing settings.

--preflight exercises the recorder only. Monitor disappearance does not distinguish
physical unplugging from software disablement; retain that limitation in the report.
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import time
from windows_display_test_support import SigmaSession, binary_identity
from windows_monitor_probe import snapshot, topology

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma.exe')
parser.add_argument('--device', help=r'Secondary GDI device, for example \\.\DISPLAY3')
parser.add_argument('--preflight', action='store_true')
parser.add_argument('--fullscreen', action='store_true', help='Start fullscreen and verify coverage after removal, then restore normally')
parser.add_argument('--timeout', type=float, default=240)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
assert 10 <= args.timeout <= 600
assert not args.output.exists(), 'Do not overwrite a hardware run'
initial = snapshot()
secondary = [m for m in initial if not m['primary'] and (args.device is None or m['device'] == args.device)]
assert secondary, 'A connected secondary monitor is required'
target = secondary[-1]
source = '''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-WINDOW
: FOUR 2SWAP SWAP . . SWAP . . ;
: SNAP DISPLAYS DUP ." SNAP " . WINDOW-OPEN? . WINDOW-DISPLAY . WINDOW-CHANGES .
WINDOW-PIXELS SWAP . . CR
0 ?DO ." MONITOR " I . I DISPLAY-RECT FOUR I DISPLAY-WORK FOUR CR LOOP ;
: CONTROL BEGIN KEY CASE
[CHAR] p OF SNAP ENDOF
[CHAR] c OF WINDOW-CLOSE 300 MS SNAP ENDOF
[CHAR] s OF SHOW 2000 WINDOW-PAINT-WAIT DROP SNAP ENDOF
[CHAR] f OF FALSE FULLSCREEN 300 MS SNAP ENDOF
[CHAR] t OF KEY [CHAR] 0 - WINDOW-ON 300 MS SNAP ENDOF
[CHAR] q OF EXIT ENDOF
ENDCASE AGAIN ;
4 2 GFX-INIT 320 200 WINDOW-SIZE @MODE@ SNAP CONTROL WINDOW-CLOSE BYE'''
source = source.replace('@MODE@', 'TRUE FULLSCREEN' if args.fullscreen else '')
user = c.WinDLL('user32', use_last_error=True)
cb = c.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
user.EnumWindows.argtypes = [cb, w.LPARAM]
user.GetWindowThreadProcessId.argtypes = [w.HWND, c.POINTER(w.DWORD)]
user.GetClassNameW.argtypes = [w.HWND, w.LPWSTR, c.c_int]
user.MonitorFromWindow.argtypes = [w.HWND, w.DWORD]
user.MonitorFromWindow.restype = w.HANDLE
user.GetWindowRect.argtypes = [w.HWND, c.POINTER(w.RECT)]
user.SetThreadDpiAwarenessContext.argtypes = [c.c_void_p]
user.SetThreadDpiAwarenessContext.restype = c.c_void_p
assert user.SetThreadDpiAwarenessContext(c.c_void_p(-4))


def current_monitor(pid):
    found = []
    @cb
    def visit(hwnd, unused):
        owner, name = w.DWORD(), c.create_unicode_buffer(128)
        user.GetWindowThreadProcessId(hwnd, c.byref(owner))
        user.GetClassNameW(hwnd, name, len(name))
        if owner.value == pid and name.value == 'SigmaGraphicsWindow':
            outer = w.RECT()
            assert user.GetWindowRect(hwnd, c.byref(outer))
            found.append((int(user.MonitorFromWindow(hwnd, 2) or 0),
                          [outer.left, outer.top, outer.right - outer.left, outer.bottom - outer.top]))
        return True
    assert user.EnumWindows(visit, 0)
    assert len(found) <= 1, found
    return found[0] if found else (None, None)


report = dict(status='incomplete', preflight=args.preflight, physical_hotplug_tested=False,
              starts_fullscreen=args.fullscreen,
              started_at=datetime.now(timezone.utc).isoformat(), binary=binary_identity(args.sigma),
              source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              initial_monitors=initial, target=target, phases=[], samples=[],
              limitations=['GDI monitor removal cannot prove physical unplugging; operator confirmation is required',
                           'No display configuration change is performed by this script'])
args.output.parent.mkdir(parents=True, exist_ok=True)
started = time.monotonic()


def centered(row):
    if not row['open'] or row['outer_rect'] is None:
        return False
    monitor = next(m for m in row['independent'] if m['device'] == row['actual_device'])
    x, y, width, height = row['outer_rect']
    wx, wy, ww, wh = monitor['work']
    return width <= ww and height <= wh and x == wx + (ww - width) // 2 and y == wy + (wh - height) // 2


try:
    with SigmaSession(args.sigma, source) as session:
        def read_state():
            fields = session.line().split()
            assert fields[0] == b'SNAP' and len(fields) == 7, fields
            count, opened, display, changes, width, height = map(int, fields[1:])
            monitors = []
            for index in range(count):
                parts = session.line().split()
                assert parts[:2] == [b'MONITOR', str(index).encode()] and len(parts) == 10, parts
                values = list(map(int, parts[2:]))
                monitors.append(dict(index=index, rect=values[:4], work=values[4:]))
            raw = snapshot()
            consistent = len(raw) == count
            for monitor in monitors:
                matches = [m for m in raw if m['rect'] == monitor['rect'] and m['work'] == monitor['work']]
                consistent = consistent and len(matches) == 1
                monitor['device'] = matches[0]['device'] if len(matches) == 1 else None
            actual_id, outer_rect = current_monitor(session.process.pid)
            actual_info = next((m for m in raw if m['id'] == actual_id), None)
            actual = actual_info['device'] if actual_info else None
            if opened:
                consistent = consistent and 0 <= display < count and actual is not None
                if 0 <= display < count:
                    consistent = consistent and monitors[display]['device'] == actual
            else:
                consistent = consistent and actual_id is None and display == -1
            row = dict(seconds=time.monotonic() - started, count=count, open=opened,
                       display=display, changes=changes, pixels=[width, height],
                       monitors=monitors, independent=raw, actual_device=actual, consistent=consistent)
            row['actual_rect'] = actual_info['rect'] if actual_info else None
            row['outer_rect'] = outer_rect
            report['samples'].append(row)
            return row

        def command(data=b'p'):
            session.process.stdin.write(data)
            session.process.stdin.flush()
            return read_state()

        def wait_for(label, condition, timeout=5):
            deadline = time.monotonic() + timeout
            consecutive = 0
            while time.monotonic() < deadline:
                row = command()
                consecutive = consecutive + 1 if row['consistent'] and condition(row) else 0
                if consecutive >= 3:
                    report['phases'].append(dict(phase=label, sample=len(report['samples']) - 1))
                    return row
                time.sleep(.2)
            raise TimeoutError(f'{label}: no stable expected state')

        before = read_state()
        assert before['consistent']
        target_index = next(m['index'] for m in before['monitors'] if m['device'] == target['device'])
        assert target_index < 10, 'single-digit control protocol'
        command(b't' + str(target_index).encode())
        command(b's')
        baseline = wait_for('baseline-secondary', lambda r: r['actual_device'] == target['device'])
        if args.fullscreen:
            assert baseline['outer_rect'] == target['rect'], baseline
        if args.preflight:
            command(b'c')
            wait_for('closed', lambda r: not r['open'])
            command(b's')
            wait_for('reopened-secondary', lambda r: r['actual_device'] == target['device'])
            assert topology(snapshot()) == topology(initial)
            if args.fullscreen:
                command(b'f')
                wait_for('fullscreen-reopen-normal-restored', lambda r: r['actual_device'] == target['device'] and centered(r))
            report['status'] = 'preflight-pass'
        else:
            print(f"Disconnect the cable of secondary {target['device']} (rect {target['rect']}).", flush=True)
            removed = wait_for('disconnected-live', lambda r: r['open'] == -1 and
                               len(r['independent']) == len(initial) - 1 and
                               all(m['rect'] != target['rect'] for m in r['independent']) and
                               r['changes'] > baseline['changes'], args.timeout)
            if args.fullscreen:
                wait_for('fullscreen-covers-remaining-monitor', lambda r: r['outer_rect'] == r['actual_rect'])
                command(b'f')
                wait_for('fullscreen-exit-centred-on-remaining-monitor', centered)
            command(b'c')
            wait_for('closed-while-missing', lambda r: not r['open'])
            command(b's')
            fallback = wait_for('missing-preference-reopened', lambda r: r['open'] == -1 and
                                r['actual_rect'] != target['rect'])
            print('Reconnect the same monitor cable.', flush=True)
            reconnected = wait_for('reconnected', lambda r: topology(r['independent']) == topology(initial), args.timeout)
            report['reconnection_handle_changes'] = [dict(rect=old['rect'], before=old['id'], after=new['id'],
                                                        before_device=old['device'], after_device=new['device'])
                                                     for old in initial for new in reconnected['independent'] if old['rect'] == new['rect']]
            hold_until = time.monotonic() + 10
            while time.monotonic() < hold_until:
                row = command()
                assert row['consistent'] and row['actual_rect'] == fallback['actual_rect'], row
                time.sleep(.2)
            report['phases'].append(dict(phase='no-automatic-return-for-10-seconds', sample=len(report['samples']) - 1))
            state = command()
            target_index = next(m['index'] for m in state['monitors'] if m['rect'] == target['rect'])
            assert target_index < 10, 'single-digit control protocol'
            reconnected_device = state['monitors'][target_index]['device']
            command(b't' + str(target_index).encode())
            wait_for('explicit-selection-after-reconnect', lambda r: r['actual_device'] == reconnected_device)
            report['status'] = 'observed-awaiting-operator-confirmation'
        session.process.stdin.write(b'q')
        session.process.stdin.flush()
        session.finish()
except BaseException as error:
    report['status'] = 'failed'
    report['error'] = f'{type(error).__name__}: {error}'
    raise
finally:
    report['finished_at'] = datetime.now(timezone.utc).isoformat()
    with args.output.open('x', encoding='utf-8') as output:
        json.dump(report, output, indent=2)
        output.write('\n')
    print(f"{report['status']}: {args.output}", flush=True)
