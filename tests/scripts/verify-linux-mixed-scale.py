#!/usr/bin/env python3
"""Temporarily test two-monitor mixed scale on GNOME, with an independent rollback.
Changes only the secondary scale (default 2), never persists configuration.
Physical hotplug is not tested. Requires the current unrotated horizontal layout.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time

from linux_x11_test_support import SigmaSession, binary_identity, require_linux

require_linux()


def interrupted(signum, frame):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    raise SystemExit(f'interrupted by signal {signum}')


for termination_signal in (signal.SIGTERM, signal.SIGHUP):
    signal.signal(termination_signal, interrupted)
import gi
from gi.repository import Gio, GLib

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma')
parser.add_argument('--output-dir', type=Path, default=ROOT / '.work/1037/mixed-scale')
parser.add_argument('--scale', type=float, default=2, choices=(2,))
parser.add_argument('--restore-plan', type=Path)
parser.add_argument('--watchdog-read-fd', type=int)
parser.add_argument('--watchdog-ready-fd', type=int)
args = parser.parse_args()
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def call(method, params=None):
    return bus.call_sync('org.gnome.Mutter.DisplayConfig',
                         '/org/gnome/Mutter/DisplayConfig',
                         'org.gnome.Mutter.DisplayConfig', method, params, None,
                         Gio.DBusCallFlags.NONE, 5000, None).unpack()


def inventory():
    return call('GetCurrentState')


def configuration(state):
    _, physical, logical, properties = state
    active = {spec[0] for monitor in logical for spec in monitor[5]}
    modes = {m[0][0]: next(mode[0] for mode in m[1] if mode[6].get('is-current'))
             for m in physical if m[0][0] in active}
    output_properties = {}
    for monitor in physical:
        props = monitor[2]
        output_properties[monitor[0][0]] = {name: props[name] for name in ('color-mode', 'rgb-range') if name in props}
        if 'is-underscanning' in props:
            output_properties[monitor[0][0]]['underscanning'] = props['is-underscanning']
    return dict(monitors=[[m[0], m[1], m[2], m[3], m[4],
                           [[spec[0], modes[spec[0]], output_properties[spec[0]]] for spec in m[5]]]
                          for m in logical],
                layout_mode=properties.get('layout-mode', 1))


def apply(config, method=1):
    # Serial numbers change with every apply: always take the current one.
    state = inventory()
    properties = {}
    if state[3].get('supports-changing-layout-mode'):
        properties['layout-mode'] = GLib.Variant('u', config['layout_mode'])
    monitors = json.loads(json.dumps(config['monitors']))
    for monitor in monitors:
        for output in monitor[5]:
            output[2] = {name: GLib.Variant('b' if type(value) is bool else 'u', value)
                         for name, value in output[2].items()}
    call('ApplyMonitorsConfig', GLib.Variant('(uua(iiduba(ssa{sv}))a{sv})',
                                           (state[0], method, monitors, properties)))


def wait_configuration(config):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        actual = configuration(inventory())
        if actual == config:
            return actual
        time.sleep(.1)
    raise AssertionError(('monitor configuration did not settle', config, actual))


PROBE_SOURCE = '''REQUIRE-GRAPHICS ALSO GRAPHICS
: FOUR 2SWAP SWAP . . SWAP . . ;
: SNAP DISPLAYS DUP ." COUNT " . CR DISPLAY-PRIMARY ." PRIMARY " . CR
0 DO ." DISPLAY " I . I DISPLAY-RECT FOUR I DISPLAY-WORK FOUR
I DISPLAY-SCALE SWAP . . I DISPLAY-HZ SWAP . . CR LOOP ;
SNAP KEY DROP SNAP KEY DROP SNAP KEY DROP BYE'''


def read_snapshot(session):
    count_line = session.line().split()
    assert count_line[0] == b'COUNT', count_line
    count = int(count_line[1])
    primary_line = session.line().split()
    assert primary_line[0] == b'PRIMARY', primary_line
    rows = []
    for _ in range(count):
        fields = session.line().split()
        assert fields[0] == b'DISPLAY' and len(fields) == 14, fields
        values = list(map(int, fields[1:]))
        rows.append(dict(index=values[0], rect=values[1:5], work=values[5:9],
                         scale=values[9:11], hz=values[11:13]))
    return dict(primary=int(primary_line[1]), displays=rows)


if args.restore_plan:
    plan = json.loads(args.restore_plan.read_text())
    if args.watchdog_ready_fd is not None:
        os.write(args.watchdog_ready_fd, b'1')
        os.close(args.watchdog_ready_fd)
    if args.watchdog_read_fd is not None:
        readable, _, _ = select.select([args.watchdog_read_fd], [], [], 150)
        message = os.read(args.watchdog_read_fd, 1) if readable else b''
        os.close(args.watchdog_read_fd)
        if message == b'R':
            print('parent restored configuration')
            raise SystemExit(0)
    restore_deadline = time.monotonic() + 30
    while True:
        try:
            apply(plan['original'])
            wait_configuration(plan['original'])
            break
        except Exception:
            if time.monotonic() >= restore_deadline:
                raise
            time.sleep(1)
    print('watchdog restored original configuration')
    raise SystemExit(0)

state = inventory()
_, physical, logical, properties = state
assert os.environ.get('XDG_SESSION_TYPE') == 'wayland'
assert not properties.get('global-scale-required', False)
assert len(logical) == 2 and properties.get('layout-mode', 1) == 1
assert all(len(m[5]) == 1 and m[3] == 0 and m[1] == 0 for m in logical)
assert sum(bool(m[4]) for m in logical) == 1
assert all(m[2] == 1 for m in logical), 'start with both monitors at scale 1'
for monitor in physical:
    props = monitor[2]
    known = {'is-builtin', 'display-name', 'min-refresh-rate', 'is-for-lease',
             'color-mode', 'supported-color-modes', 'rgb-range', 'is-underscanning'}
    assert not (props.keys() - known), ('unrecognized monitor properties', props.keys() - known)
    assert not props.get('is-for-lease'), 'leased outputs require explicit handling'
features = list(Gio.Settings.new('org.gnome.mutter').get_strv('experimental-features'))
assert 'xwayland-native-scaling' in features, 'this check covers Mutter xwayland-native-scaling'
original = configuration(state)
candidate = json.loads(json.dumps(original))
widths = {}
for monitor in candidate['monitors']:
    connector = monitor[5][0][0]
    entry = next(m for m in physical if m[0][0] == connector)
    mode = next(m for m in entry[1] if m[6].get('is-current'))
    if not monitor[4]:
        assert args.scale in mode[5]
        monitor[2] = args.scale
    widths[connector] = int(round(mode[1] / monitor[2]))
x = 0
for monitor in sorted(candidate['monitors'], key=lambda m: m[0]):
    monitor[0] = x
    x += widths[monitor[5][0][0]]
assert len({m[2] for m in candidate['monitors']}) == 2, 'candidate must have different scales'
apply(original, method=0)
apply(candidate, method=0)  # Verify both configurations before applying either.
args.output_dir.mkdir(parents=True, exist_ok=False)
plan_path = args.output_dir / 'restore-plan.json'
plan_path.write_text(json.dumps(dict(original=original, candidate=candidate), indent=2) + '\n')
read_fd, write_fd = os.pipe()
ready_read, ready_write = os.pipe()
watchdog_log = open(args.output_dir / 'watchdog.log', 'wb')
watchdog = subprocess.Popen([sys.executable, str(Path(__file__).resolve()),
                             '--restore-plan', str(plan_path.resolve()),
                             '--watchdog-read-fd', str(read_fd),
                             '--watchdog-ready-fd', str(ready_write)],
                            pass_fds=(read_fd, ready_write), stdin=subprocess.DEVNULL,
                            stdout=watchdog_log, stderr=subprocess.STDOUT, start_new_session=True)
os.close(read_fd)
os.close(ready_write)
report = dict(status='incomplete', task=1336, binary=binary_identity(args.sigma), original=original,
              candidate=candidate, physical_hotplug_tested=False,
              source_sha256={name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                             for name in ('tests/scripts/verify-linux-mixed-scale.py', 'tests/scripts/verify-linux-window-on.py', 'src/host_window_linux.zig')})
probe = None
probe_stage = None
try:
    assert select.select([ready_read], [], [], 8)[0], 'watchdog did not become ready'
    assert os.read(ready_read, 1) == b'1' and watchdog.poll() is None
    def overall_timeout(signum, frame):
        raise TimeoutError('mixed-scale verification exceeded 75 seconds')
    signal.signal(signal.SIGALRM, overall_timeout)
    signal.setitimer(signal.ITIMER_REAL, 75)
    report['mutter_experimental_features'] = features
    report['physical_monitor_properties'] = {m[0][0]: m[2] for m in physical}
    probe = SigmaSession(str(args.sigma.resolve()), PROBE_SOURCE, os.environ.copy())
    report['before'] = read_snapshot(probe)
    probe_stage = 'before'
    apply(candidate)
    report['applied'] = wait_configuration(candidate)
    # Allow XWayland to receive Mutter's new logical layout.
    expected = []
    primary = next(m for m in candidate['monitors'] if m[4])
    physical_by_name = {m[0][0]: m for m in physical}
    for monitor in candidate['monitors']:
        entry = physical_by_name[monitor[5][0][0]]
        mode = next(m for m in entry[1] if m[6].get('is-current'))
        expected.append([int((monitor[0] - primary[0]) * 2), int((monitor[1] - primary[1]) * 2),
                         int(mode[1] / monitor[2] * 2), int(mode[2] / monitor[2] * 2)])
    def union(rectangles):
        left = min(r[0] for r in rectangles)
        top = min(r[1] for r in rectangles)
        right = max(r[0] + r[2] for r in rectangles)
        bottom = max(r[1] + r[3] for r in rectangles)
        return [left, top, right - left, bottom - top]
    old_bounds = union([m['rect'] for m in report['before']['displays']])
    old_work = union([m['work'] for m in report['before']['displays']])
    new_bounds = union(expected)
    margins = [old_work[0] - old_bounds[0], old_work[1] - old_bounds[1],
               old_bounds[0] + old_bounds[2] - old_work[0] - old_work[2],
               old_bounds[1] + old_bounds[3] - old_work[1] - old_work[3]]
    assert all(value >= 0 for value in margins)
    wx, wy = new_bounds[0] + margins[0] * 2, new_bounds[1] + margins[1] * 2
    wr = new_bounds[0] + new_bounds[2] - margins[2] * 2
    wb = new_bounds[1] + new_bounds[3] - margins[3] * 2
    expected_work = [[max(r[0], wx), max(r[1], wy),
                      min(r[0] + r[2], wr) - max(r[0], wx),
                      min(r[1] + r[3], wb) - max(r[1], wy)] for r in expected]
    report['expected_mixed_rects'] = expected
    report['expected_mixed_work'] = expected_work
    deadline = time.monotonic() + 8
    observed = None
    # Use short fresh probes while retaining the original Sigma for the live check.
    while time.monotonic() < deadline:
        with SigmaSession(str(args.sigma.resolve()), PROBE_SOURCE, os.environ.copy()) as transient:
            observed = read_snapshot(transient)
        if (sorted(row['rect'] for row in observed['displays']) == sorted(expected) and
                sorted(row['work'] for row in observed['displays']) == sorted(expected_work)):
            break
        time.sleep(.1)
    assert sorted(row['rect'] for row in observed['displays']) == sorted(expected), (observed, expected)
    assert sorted(row['work'] for row in observed['displays']) == sorted(expected_work), (observed, expected_work)
    probe.send()
    report['mixed'] = read_snapshot(probe)
    probe_stage = 'mixed'
    assert len(report['mixed']['displays']) == 2
    assert all(row['scale'] == [0, 0] for row in report['mixed']['displays'])
    report['inventory'] = json.loads(subprocess.check_output(
        [sys.executable, str(ROOT / 'tests/scripts/inspect-linux-monitor-config.py')], timeout=15))
    test_output = args.output_dir / 'window-on.json'
    process = subprocess.Popen([sys.executable, str(ROOT / 'tests/scripts/verify-linux-window-on.py'),
                                '--sigma', str(args.sigma.resolve()), '--output', str(test_output.resolve()),
                                '--coordinate-quantum', '2'],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=65)
    except BaseException:
        signal.setitimer(signal.ITIMER_REAL, 0)
        try:
            os.killpg(process.pid, signal.SIGTERM)  # The handler unwinds its owned SigmaSession.
        except ProcessLookupError:
            pass
        try:
            process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()
        raise
    report['window_on'] = dict(returncode=process.returncode, stdout=stdout, stderr=stderr)
    assert process.returncode == 0, report['window_on']
    window_report = json.loads(test_output.read_text())
    raw = window_report['monitors']
    primary = next(m for m in raw if m['primary'])['rect']
    assert len(raw) == len(report['mixed']['displays']) == len(window_report['work_areas'])
    for info, monitor, work in zip(report['mixed']['displays'], raw, window_report['work_areas']):
        x, y, width, height = monitor['rect']
        assert info['rect'] == [x - primary[0], y - primary[1], width, height]
        wx, wy, ww, wh = work
        assert info['work'] == [wx - primary[0], wy - primary[1], ww, wh]
    assert watchdog.poll() is None, 'watchdog restored configuration during testing'
    assert configuration(inventory()) == candidate, 'configuration changed during verification'
    report['checks_passed'] = True
finally:
    signal.setitimer(signal.ITIMER_REAL, 0)
    # This executes on test failure; the watchdog also covers parent termination.
    try:
        apply(original)
        report['restored'] = wait_configuration(original)
        if watchdog.poll() is None:
            try:
                os.write(write_fd, b'R')
            except BrokenPipeError:
                pass
        if probe_stage == 'mixed':
            time.sleep(2)
            probe.send()
            report['after'] = read_snapshot(probe)
            probe_stage = 'after'
            assert report['after'] == report['before'], 'live Sigma did not recover its display snapshot'
            probe.send()
            probe.finish()
            assert not probe.errors(), probe.errors()
            report['probe_restored'] = True
    finally:
        if probe is not None:
            probe.close()
        os.close(write_fd)
        os.close(ready_read)
        try:
            watchdog.wait(timeout=45)
        except subprocess.TimeoutExpired:
            report['watchdog_timeout'] = True
        watchdog_log.close()
        report['watchdog_returncode'] = watchdog.returncode
        report['status'] = 'pass' if report.get('checks_passed') and report.get('probe_restored') and watchdog.returncode == 0 else 'fail'
        (args.output_dir / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
assert report['restored'] == original and watchdog.returncode == 0
print('pass: mixed scale verified and original configuration restored')
