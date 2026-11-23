#!/usr/bin/env python3
"""Verify display restoration after the measurement parent deliberately exits."""
import argparse
import ctypes as c
from datetime import datetime, timezone
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time
from windows_monitor_probe import snapshot, user

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
assert not args.output.exists()
initial = snapshot()
with tempfile.TemporaryDirectory(prefix='sigma-refresh-watchdog-') as folder:
    parent_report = Path(folder) / 'parent.json'
    child = subprocess.Popen([sys.executable, str(ROOT / 'tests/scripts/measure-windows-mixed-refresh.py'),
                              '--test-parent-exit', '--output', str(parent_report)])
    assert child.wait(timeout=15) == 0
    parent = json.loads(parent_report.read_text(encoding='utf-8'))
    assert parent['status'] == 'parent-exiting-for-watchdog-test'
    restored_path = Path(parent['watchdog_directory']) / 'restored.json'
    deadline = time.monotonic() + 25
    while not restored_path.exists() and time.monotonic() < deadline:
        time.sleep(.1)
    restoration = json.loads(restored_path.read_text(encoding='utf-8'))
    assert restoration['status'] == 'restored', restoration
    final = snapshot()
    assert final == initial
    raw = c.create_string_buffer(220)
    struct.pack_into('<H', raw, 68, 220)
    assert user.EnumDisplaySettingsW(parent['device'], 0xFFFFFFFF, raw)
    assert struct.unpack_from('<I', raw, 184)[0] == parent['original']['hz']
    report = dict(status='pass', finished_at=datetime.now(timezone.utc).isoformat(),
                  parent=parent, restoration=restoration, initial_monitors=initial, final_monitors=final,
                  method='Parent os._exit after apply bypasses finally; separate five-second watchdog restores saved DEVMODE')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x', encoding='utf-8') as output:
        json.dump(report, output, indent=2)
        output.write('\n')
print(f'pass: independent watchdog restored after parent exit; {args.output}')
