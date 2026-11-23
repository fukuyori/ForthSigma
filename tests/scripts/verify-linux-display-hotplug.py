#!/usr/bin/env python3
"""Record a physical secondary-monitor unplug/replug on Linux (1336/1345).
Never changes display configuration. The user disconnects and reconnects the named
monitor. DRM status and EDID corroborate disconnection, but power-off or a
privileged forced disconnection still require an operator declaration to exclude.
--preflight exercises the owned window and recorder without claiming hotplug.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
import select
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
parser.add_argument('--connector', default='DP-3')
parser.add_argument('--output-dir', type=Path)
parser.add_argument('--timeout', type=float, default=240)
parser.add_argument('--preflight', action='store_true')
parser.add_argument('--coordinate-quantum', type=int, choices=(1, 2), default=1)
parser.add_argument('--confirm-report', type=Path)
parser.add_argument('--operator-statement')
parser.add_argument('--confirmation-output', type=Path)
args = parser.parse_args()
if not __debug__:
    raise SystemExit('verification requires assertions enabled; remove -O/PYTHONOPTIMIZE')
if args.confirm_report is not None:
    assert args.operator_statement and args.operator_statement.strip(), 'an explicit post-run operator statement is required'
    original_bytes = args.confirm_report.read_bytes()
    original = json.loads(original_bytes)
    assert original['status'] == 'observed-awaiting-operator-confirmation', 'not an observed completed sequence'
    assert original.get('electrical_disconnection_observed') and original.get('electrical_disconnect_reconnect_observed')
    assert not original['physical_hotplug_tested'] and original.get('finished_at') and not original.get('sigma_stderr')
    required = {'baseline-secondary', 'drm-disconnection-observed', 'disconnected-live',
                'missing-preference-opens-on-remaining-monitor', 'drm-reconnection-observed',
                'reconnected-on-remaining-monitor', 'no-automatic-return-for-10-seconds',
                'explicit-selection-after-reconnect'}
    assert required <= {phase['phase'] for phase in original['phases']}
    assert any(row['drm']['status'] == 'disconnected' and row['drm']['edid_sha256'] is None for row in original['samples'])
    assert original['samples'][-1]['drm'] == original['initial_drm']
    destination = args.confirmation_output or args.confirm_report.with_name('operator-confirmation.json')
    confirmation = dict(status='pass', physical_hotplug_tested=True,
                        source_report=str(args.confirm_report.resolve()),
                        source_report_sha256=hashlib.sha256(original_bytes).hexdigest(),
                        operator_statement=args.operator_statement.strip(),
                        confirmed_at=datetime.now(timezone.utc).isoformat())
    with open(destination, 'x') as output:
        output.write(json.dumps(confirmation, indent=2) + '\n')
    print('pass: operator confirmation recorded separately; source report preserved')
    raise SystemExit(0)
if args.output_dir is None:
    parser.error('--output-dir is required for recording')
assert 10 <= args.timeout <= 600
paths = list(Path('/sys/class/drm').glob(f'card*-{args.connector}/status'))
assert len(paths) == 1, ('one DRM connector required', [str(p) for p in paths])
status_path = paths[0]


class AwaitingHardware(Exception):
    """No stable user hardware transition was observed before the deadline."""


@contextmanager
def recorded_session(binary, source, report):
    with SigmaSession(str(binary.resolve()), source, os.environ.copy()) as session:
        try:
            yield session
        finally:
            report['sigma_stderr'] = session.errors()


def require_eof(session):
    assert not session.buffer.strip(), session.buffer
    deadline = time.monotonic() + 2
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([session.process.stdout], [], [], remaining)[0]:
            raise TimeoutError('stdout EOF deadline')
        data = os.read(session.process.stdout.fileno(), 4096)
        if not data:
            return
        assert not data.strip(), data


def drm():
    status = status_path.read_text().strip()
    try:
        edid = status_path.with_name('edid').read_bytes()
    except OSError:
        edid = b''
    return dict(status=status, edid_sha256=hashlib.sha256(edid).hexdigest() if edid else None)


def monitors(connection):
    connection.deadline = time.monotonic() + 5
    header, _ = connection.reply(connection.request(98, body=struct.pack('<H2x', 5) + b'RANDR' + b'\0' * 3))
    assert header[8], 'RandR required'
    opcode = header[9]
    connection.reply(connection.request(opcode, 0, struct.pack('<II', 1, 5)))
    header, body = connection.reply(connection.request(opcode, 42, struct.pack('<IB3x', connection.root, 1)))
    rows, offset = [], 0
    for _ in range(struct.unpack_from('<I', header, 12)[0]):
        atom, primary, _, outputs, x, y, width, height, _, _ = struct.unpack_from('<IBBHhhHHII', body, offset)
        name_header, name_body = connection.reply(connection.request(17, body=struct.pack('<I', atom)))
        name = name_body[:struct.unpack_from('<H', name_header, 8)[0]].decode('utf-8', 'replace')
        rows.append(dict(name=name, primary=bool(primary), rect=[x, y, width, height]))
        offset += 24 + outputs * 4
    return rows


def work_areas(connection, raw):
    connection.deadline = time.monotonic() + 5
    def values(name, offset=0, count=4):
        header, body = connection.reply(connection.request(20, body=struct.pack(
            '<IIIII', connection.root, connection.atom(name), 6, offset, count)))
        if header[1] != 32:
            return []
        return list(struct.unpack('<' + 'I' * (len(body) // 4), body))
    desktop = values(b'_NET_CURRENT_DESKTOP', count=1)
    work = values(b'_NET_WORKAREA', offset=4 * min(desktop[0] if desktop else 0, 1 << 20))
    areas = []
    for monitor in raw:
        x, y, width, height = monitor['rect']
        if len(work) != 4 or not work[2] or not work[3]:
            areas.append([x, y, width, height])
            continue
        wx, wy, ww, wh = work
        wx, wy = (v if v < 2**31 else v - 2**32 for v in (wx, wy))
        left, top = max(x, wx), max(y, wy)
        right, bottom = min(x + width, wx + ww), min(y + height, wy + wh)
        areas.append([left, top, right - left, bottom - top] if right > left and bottom > top else [x, y, 0, 0])
    return areas


def find_window(connection, pid):
    connection.deadline = time.monotonic() + 5
    pending = [connection.root]
    atom = connection.atom(b'_NET_WM_PID')
    while pending:
        window = pending.pop()
        try:
            _, value = connection.reply(connection.request(20, body=struct.pack('<IIIII', window, atom, 0, 0, 1)))
            if value[:4] == struct.pack('<I', pid):
                return window
            _, body = connection.reply(connection.request(15, body=struct.pack('<I', window)))
            pending.extend(struct.unpack('<' + 'I' * (len(body) // 4), body))
        except RuntimeError as error:
            if 'X11 error code=3 ' not in str(error):
                raise
    raise AssertionError('owned Sigma window not found')


def snapshot(session):
    fields = session.line().split()
    assert len(fields) == 9 and fields[0] == b'SNAP', fields
    count, opened, display, changes, width, height, fullscreen, depth = map(int, fields[1:])
    rows = []
    for _ in range(count):
        row = session.line().split()
        assert len(row) == 14 and row[0] == b'DISPLAY', row
        values = list(map(int, row[1:]))
        rows.append(dict(index=values[0], rect=values[1:5], work=values[5:9],
                         scale=values[9:11], hz=values[11:13]))
    assert depth == 1, ('only the display count is kept for the reporting loop', depth)
    return dict(count=count, open=opened, display=display, changes=changes,
                pixels=[width, height], fullscreen=bool(fullscreen), displays=rows)


connection = Connection(os.environ['DISPLAY'])
report = dict(task=[1336, 1345], status='incomplete', physical_hotplug_tested=False,
              binary=binary_identity(args.sigma), connector=args.connector,
              drm_status_path=str(status_path), phases=[], samples=[],
              source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              electrical_disconnection_observed=False,
              electrical_disconnect_reconnect_observed=False,
              coordinate_quantum=args.coordinate_quantum,
              physical_evidence_limits=['DRM disconnection and EDID disappearance cannot by themselves distinguish cable unplug from monitor power-off or privileged forced disconnection'])
args.output_dir.mkdir(parents=True, exist_ok=False)
try:
    initial_drm = drm()
    initial_monitors = monitors(connection)
    assert initial_drm['status'] == 'connected' and initial_drm['edid_sha256'], initial_drm
    assert len(initial_monitors) == 2, 'exactly two active monitors required'
    target = next(i for i, m in enumerate(initial_monitors) if m['name'] == args.connector)
    assert not initial_monitors[target]['primary'], 'disconnect only the secondary monitor'
    report.update(initial_drm=initial_drm, initial_monitors=initial_monitors)
    source = f'''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-WINDOW
DISPLAYS DROP {target} WINDOW-ON 4 2 GFX-INIT 320 200 WINDOW-SIZE SHOW 2000 WINDOW-PAINT-WAIT DROP
: FOUR 2SWAP SWAP . . SWAP . . ;
: SNAP DISPLAYS DUP ." SNAP " . WINDOW-OPEN? . WINDOW-DISPLAY . WINDOW-CHANGES .
WINDOW-PIXELS SWAP . . FULLSCREEN? . DEPTH . CR
0 ?DO ." DISPLAY " I . I DISPLAY-RECT FOUR I DISPLAY-WORK FOUR
I DISPLAY-SCALE SWAP . . I DISPLAY-HZ SWAP . . CR LOOP ;
: CONTROL BEGIN KEY DUP [CHAR] q <> WHILE CASE
[CHAR] p OF ENDOF
[CHAR] c OF WINDOW-CLOSE ENDOF
[CHAR] s OF SHOW 2000 WINDOW-PAINT-WAIT DROP ENDOF
[CHAR] t OF KEY [CHAR] 0 - WINDOW-ON 300 MS ENDOF
ENDCASE SNAP REPEAT DROP ;
SNAP CONTROL WINDOW-CLOSE BYE'''
    report['source'] = source
    with open(args.output_dir / 'samples.jsonl', 'w') as journal, recorded_session(args.sigma, source, report) as session:
        started = time.monotonic()

        def sample(command=None):
            if command is not None:
                session.send(command)
            state = snapshot(session)
            raw = monitors(connection)
            hardware = drm()
            areas = work_areas(connection, raw)
            consistent = len(raw) == state['count']
            if consistent and raw:
                primary = next((m for m in raw if m['primary']), raw[0])['rect']
                consistent = all(info['rect'] == [m['rect'][0] - primary[0], m['rect'][1] - primary[1], *m['rect'][2:]]
                                 for info, m in zip(state['displays'], raw))
                consistent = consistent and all(info['work'] == [area[0] - primary[0], area[1] - primary[1], *area[2:]]
                                                for info, area in zip(state['displays'], areas))
            if raw and state['open']:
                window = find_window(connection, session.process.pid)
                connection.deadline = time.monotonic() + 5
                position, _ = connection.reply(connection.request(40, body=struct.pack('<IIhh', window, connection.root, 0, 0)))
                origin = list(struct.unpack_from('<hh', position, 12))
                geometry, _ = connection.reply(connection.request(14, body=struct.pack('<I', window)))
                size = list(struct.unpack_from('<HH', geometry, 16))
                intersections = [max(0, min(origin[0] + size[0], m['rect'][0] + m['rect'][2]) - max(origin[0], m['rect'][0])) *
                         max(0, min(origin[1] + size[1], m['rect'][1] + m['rect'][3]) - max(origin[1], m['rect'][1])) for m in raw]
                expected_display = intersections.index(max(intersections)) if max(intersections, default=0) else -1
                consistent = consistent and size == state['pixels'] and state['display'] == expected_display
                state['x11_display_name'] = raw[expected_display]['name'] if expected_display >= 0 else None
                state['x11_origin'], state['x11_pixels'] = origin, size
            row = dict(seconds=round(time.monotonic() - started, 3), drm=hardware,
                       raw_monitors=raw, raw_work_areas=areas, consistent=consistent, sigma=state)
            journal.write(json.dumps(row) + '\n')
            journal.flush()
            report['samples'].append(row)
            return row

        def wait_for(label, condition, timeout, hardware_only=False, hardware=None):
            deadline = time.monotonic() + timeout
            consecutive = 0
            hardware_changed = False
            while time.monotonic() < deadline:
                row = sample(b'p')
                if hardware is not None and not hardware(row):
                    hardware_changed = True
                consecutive = consecutive + 1 if (hardware_only or row['consistent']) and condition(row) else 0
                if consecutive >= 3:
                    report['phases'].append(dict(phase=label, sample=len(report['samples']) - 1))
                    return row
                time.sleep(.4)
            if hardware_only or hardware_changed:
                raise AwaitingHardware(('operator-sequence-or-hardware-not-stable', label))
            raise AssertionError(('state verification deadline', label, row))

        def on_monitor(row, name):
            index = row['sigma']['display']
            return (row['sigma']['open'] == -1 and 0 <= index < len(row['raw_monitors']) and
                    row['raw_monitors'][index]['name'] == name and row['sigma']['pixels'] == [320, 200])

        def centered(row):
            index = row['sigma']['display']
            window = find_window(connection, session.process.pid)
            connection.deadline = time.monotonic() + 5
            header, body = connection.reply(connection.request(20, body=struct.pack(
                '<IIIII', window, connection.atom(b'_NET_FRAME_EXTENTS'), 6, 0, 4)))
            extents = list(struct.unpack('<IIII', body)) if header[1] == 32 and len(body) == 16 else [0] * 4
            x, y, width, height = row['raw_work_areas'][index]
            left, right, top, bottom = extents
            expected = [x + (width - 320 - left - right) // 2 + left,
                        y + (height - 200 - top - bottom) // 2 + top]
            assert all(abs(a - b) < args.coordinate_quantum for a, b in zip(row['sigma']['x11_origin'], expected)), (row, expected)

        sample()
        primary_name = next(m['name'] for m in initial_monitors if m['primary'])
        baseline = wait_for('baseline-secondary', lambda r: on_monitor(r, args.connector), 8)
        centered(baseline)
        print('READY: owned window is on', args.connector, flush=True)
        if args.preflight:
            primary_index = next(i for i, m in enumerate(initial_monitors) if m['primary'])
            sample(b't' + str(primary_index).encode())
            centered(wait_for('preflight-primary', lambda r: on_monitor(r, primary_name), 8))
            sample(b't' + str(target).encode())
            centered(wait_for('preflight-secondary', lambda r: on_monitor(r, args.connector), 8))
            assert sample(b'c')['sigma']['open'] == 0
            sample(b's')
            wait_for('preflight-reopened', lambda r: on_monitor(r, args.connector), 8)
            report['status'] = 'preflight-pass'
            report['limitations'] = ['physical unplug/replug was not performed']
        else:
            disconnected = lambda r: r['drm']['status'] == 'disconnected' and r['drm']['edid_sha256'] is None
            reconnected = lambda r: r['drm'] == initial_drm
            print('ACTION: unplug the secondary monitor cable; keep the primary monitor connected.', flush=True)
            wait_for('drm-disconnection-observed', disconnected, args.timeout, hardware_only=True)
            report['electrical_disconnection_observed'] = True
            unplugged = wait_for('disconnected-live', lambda r: disconnected(r) and r['sigma']['count'] == 1 and
                                 not any(m['name'] == args.connector for m in r['raw_monitors']) and
                                 on_monitor(r, primary_name) and r['sigma']['changes'] > baseline['sigma']['changes'], 10, hardware=disconnected)
            assert sample(b'c')['sigma']['open'] == 0
            sample(b's')
            wait_for('missing-preference-opens-on-remaining-monitor', lambda r: disconnected(r) and
                     r['sigma']['count'] == 1 and on_monitor(r, primary_name), 10, hardware=disconnected)
            print('ACTION: reconnect the same secondary monitor cable.', flush=True)
            wait_for('drm-reconnection-observed', reconnected, args.timeout, hardware_only=True)
            report['electrical_disconnect_reconnect_observed'] = True
            def returned_on_primary(row):
                return (reconnected(row) and len(row['raw_monitors']) == 2 and row['sigma']['count'] == 2 and
                        next((m['name'] for m in row['raw_monitors'] if m['primary']), None) == primary_name and
                        any(m['name'] == args.connector for m in row['raw_monitors']) and on_monitor(row, primary_name))
            returned = wait_for('reconnected-on-remaining-monitor', returned_on_primary, 10, hardware=reconnected)
            deadline = time.monotonic() + 10
            observations, valid_run, bad_run = 0, 0, 0
            while time.monotonic() < deadline or valid_run < 3:
                if time.monotonic() > deadline + 3:
                    raise AssertionError('reconnection hold did not settle')
                row = sample(b'p')
                if not reconnected(row):
                    raise AwaitingHardware('hardware changed during reconnection hold')
                valid = row['consistent'] and returned_on_primary(row) and row['sigma'].get('x11_display_name') == primary_name
                valid_run = valid_run + 1 if valid else 0
                bad_run = 0 if valid else bad_run + 1
                assert bad_run < 3, ('sustained mismatch or window moved during reconnection hold', row)
                observations += 1
                time.sleep(.4)
            assert observations >= 3
            report['phases'].append(dict(phase='no-automatic-return-for-10-seconds', sample=len(report['samples']) - 1))
            target_now = next(i for i, m in enumerate(returned['raw_monitors']) if m['name'] == args.connector)
            sample(b't' + str(target_now).encode())
            centered(wait_for('explicit-selection-after-reconnect', lambda r: reconnected(r) and on_monitor(r, args.connector), 8, hardware=reconnected))
            report['status'] = 'observed-awaiting-operator-confirmation'
        session.send(b'q')
        session.finish()
        assert not session.errors(), session.errors()
        require_eof(session)
    print(report['status'], flush=True)
except BaseException as error:
    report['status'] = 'incomplete' if isinstance(error, (AwaitingHardware, SystemExit, KeyboardInterrupt)) else 'fail'
    report['error'] = repr(error)
    raise
finally:
    connection.sock.close()
    report['finished_at'] = datetime.now(timezone.utc).isoformat()
    (args.output_dir / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
