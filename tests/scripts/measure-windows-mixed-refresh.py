#!/usr/bin/env python3
"""Temporarily change only one monitor's refresh rate, measure, then restore.

Never writes display settings to the registry. A separate watchdog owns restoration
even when the parent exits. Requires an already enumerated same-resolution mode.
"""
import argparse
import base64
import ctypes as c
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import time
import uuid
from windows_monitor_probe import snapshot, available_modes, topology

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma.exe')
parser.add_argument('--hz', type=int, default=75)
parser.add_argument('--device')
parser.add_argument('--output', type=Path)
parser.add_argument('--watchdog', type=Path, help=argparse.SUPPRESS)
parser.add_argument('--test-parent-exit', action='store_true', help='Exit after applying; watchdog restores after five seconds (test only)')
args = parser.parse_args()
user = c.WinDLL('user32', use_last_error=True)
user.EnumDisplaySettingsW.argtypes = [w.LPCWSTR, w.DWORD, c.c_void_p]
user.ChangeDisplaySettingsExW.argtypes = [w.LPCWSTR, c.c_void_p, w.HWND, w.DWORD, c.c_void_p]
user.ChangeDisplaySettingsExW.restype = c.c_long


def mode(device):
    raw = c.create_string_buffer(220)
    struct.pack_into('<H', raw, 68, 220)
    if not user.EnumDisplaySettingsW(device, 0xFFFFFFFF, raw):
        raise c.WinError(c.get_last_error())
    return bytes(raw)


def summary(raw):
    return dict(position=list(struct.unpack_from('<ii', raw, 76)),
                orientation=struct.unpack_from('<I', raw, 84)[0],
                bpp=struct.unpack_from('<I', raw, 168)[0],
                width=struct.unpack_from('<I', raw, 172)[0],
                height=struct.unpack_from('<I', raw, 176)[0],
                flags=struct.unpack_from('<I', raw, 180)[0],
                hz=struct.unpack_from('<I', raw, 184)[0])


def change(device, raw, flags=0):
    return user.ChangeDisplaySettingsExW(device, c.create_string_buffer(raw), None, flags, None)


if args.watchdog:
    directory = args.watchdog
    saved = json.loads((directory / 'original.json').read_text(encoding='utf-8'))
    device = saved['device']
    original = base64.b64decode(saved['raw_base64'])
    (directory / 'ready').write_text('ready', encoding='utf-8')
    deadline = time.monotonic() + saved.get('watchdog_seconds', 90)
    while time.monotonic() < deadline and not (directory / 'restore').exists():
        time.sleep(.1)
    result = dict(status='failed', attempts=[])
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        code = change(device, original)
        current = summary(mode(device))
        result['attempts'].append(dict(code=code, observed=current))
        if code == 0 and current == summary(original):
            result['status'] = 'restored'
            break
        time.sleep(.5)
    (directory / 'restored.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    raise SystemExit(0 if result['status'] == 'restored' else 1)

assert args.output is not None and not args.output.exists(), 'A new --output is required'
initial = snapshot()
selected = next((m for m in initial if m['device'] == args.device), None) if args.device else next(m for m in initial if m['primary'])
assert selected is not None, args.device
device = selected['device']
original = mode(device)
original_summary = summary(original)
assert [original_summary['width'], original_summary['height'], args.hz] in available_modes(device)
assert original_summary['hz'] != args.hz
candidate = bytearray(original)
# Limit the requested change to dmDisplayFrequency. CDS_TEST first, no registry flags.
struct.pack_into('<I', candidate, 72, 0x00400000)
struct.pack_into('<I', candidate, 184, args.hz)
assert change(device, bytes(candidate), 2) == 0, 'CDS_TEST rejected this rate'
directory = ROOT / '.work/1037' / ('mixed-refresh-' + uuid.uuid4().hex)
directory.mkdir(parents=True)
(directory / 'original.json').write_text(json.dumps(dict(device=device, raw_base64=base64.b64encode(original).decode(),
                                                       watchdog_seconds=5 if args.test_parent_exit else 90)), encoding='utf-8')
report = dict(status='incomplete', original=original_summary, device=device, requested_hz=args.hz,
              initial_monitors=initial, watchdog_directory=str(directory), registry_settings_written=False)
watchdog = None
measurement = None
try:
    with (directory / 'watchdog.log').open('w') as log:
        watchdog = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--watchdog', str(directory)],
                                    stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                    creationflags=subprocess.CREATE_NO_WINDOW)
    ready_deadline = time.monotonic() + 5
    while not (directory / 'ready').exists() and time.monotonic() < ready_deadline:
        assert watchdog.poll() is None, 'watchdog exited before ready'
        time.sleep(.05)
    assert (directory / 'ready').exists() and watchdog.poll() is None
    code = change(device, bytes(candidate))
    report['apply_code'] = code
    assert code == 0, code
    deadline = time.monotonic() + 5
    expected = dict(original_summary, hz=args.hz)
    while summary(mode(device)) != expected and time.monotonic() < deadline:
        time.sleep(.1)
    report['applied'] = summary(mode(device))
    assert report['applied'] == expected, report['applied']
    assert topology(snapshot()) == topology(initial), 'Resolution, layout or DPI changed'
    if args.test_parent_exit:
        report['status'] = 'parent-exiting-for-watchdog-test'
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open('x', encoding='utf-8') as output:
            json.dump(report, output, indent=2)
        os._exit(0)  # Deliberately bypass finally; only the watchdog can restore.
    measurement_path = directory / 'timing.json'
    measurement = subprocess.Popen([sys.executable, str(ROOT / 'tests/scripts/measure-windows-vsync.py'),
                                    '--sigma', str(args.sigma.resolve()), '--rounds', '2', '--samples', '120',
                                    '--output', str(measurement_path)], stdin=subprocess.DEVNULL)
    assert measurement.wait(timeout=40) == 0
    assert watchdog.poll() is None, 'watchdog restored before measurement ended'
    assert summary(mode(device)) == expected and topology(snapshot()) == topology(initial)
    report['measurement'] = json.loads(measurement_path.read_text(encoding='utf-8'))
    assert any(row['hz'][0] / row['hz'][1] > 70 for row in report['measurement']['results'])
    assert any(row['hz'][0] / row['hz'][1] < 65 for row in report['measurement']['results'])
    report['measurement_completed'] = True
except BaseException as error:
    report['error'] = f'{type(error).__name__}: {error}'
    raise
finally:
    if measurement is not None and measurement.poll() is None:
        measurement.kill()
        measurement.wait(timeout=5)
    (directory / 'restore').write_text('restore', encoding='utf-8')
    try:
        if watchdog is not None:
            try:
                report['watchdog_returncode'] = watchdog.wait(timeout=25)
            except subprocess.TimeoutExpired:
                report['watchdog_timeout'] = True
        if (directory / 'restored.json').exists():
            report['restoration'] = json.loads((directory / 'restored.json').read_text(encoding='utf-8'))
        if report.get('restoration', {}).get('status') != 'restored':
            report['parent_restore_code'] = change(device, original)
        report['final_mode'] = summary(mode(device))
        report['final_monitors'] = snapshot()
        report['restored'] = report.get('restoration', {}).get('status') == 'restored' and report['final_mode'] == original_summary and topology(report['final_monitors']) == topology(initial)
        if report.get('measurement_completed') and report['restored'] and report.get('watchdog_returncode') == 0:
            report['status'] = 'pass'
    finally:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open('x', encoding='utf-8') as output:
            json.dump(report, output, indent=2)
            output.write('\n')
        print(f"{report['status']}; restored={report.get('restored')}: {args.output}", flush=True)
assert report['status'] == 'pass', report
