#!/usr/bin/env python3
"""macOS (tque 1304): record the unimplemented Tk frame contract (#1300), not Tk acceptance.

Creates owned Tk/native windows. Confirms explicit unsupported Tk frame results;
remove/replace these expectations when implementing Tk frame completion.
"""
import argparse
import json
from pathlib import Path
from macos_display_test_support import binary_identity, run

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
source = '''REQUIRE-GRAPHICS ALSO GRAPHICS
: FRAME-REPORT WINDOW-OPEN? . WINDOW-FRAMES SWAP . .
200 WINDOW-PAINT-WAIT . VSYNC-WAIT . CR ;
: TK-BURST 30 0 DO SHOW LOOP ;
DISPLAY-TK
." FRAME before " FRAME-REPORT
4 2 GFX-INIT 64 40 WINDOW-SIZE SHOW 300 MS
." FRAME tk " FRAME-REPORT
TK-BURST S" update idletasks" TCL-EVAL 2DROP
." FRAME tk-idle " FRAME-REPORT
DISPLAY-WINDOW SHOW 2000 WINDOW-PAINT-WAIT DROP
." FRAME native " FRAME-REPORT
DISPLAY-TK TK-BURST
." FRAME coexist " FRAME-REPORT
GFX-WINDOW-CLOSE
." FRAME native-closed " FRAME-REPORT
BYE'''
output = run(args.sigma, source)
rows = []
for line in output.splitlines():
    fields = line.split()
    assert len(fields) == 7 and fields[0] == 'FRAME', output
    values = list(map(int, fields[2:]))
    rows.append(dict(phase=fields[1], **dict(zip(
        ('open', 'shown', 'painted', 'wait', 'vsync'), values))))
assert [r['phase'] for r in rows] == ['before', 'tk', 'tk-idle', 'native', 'coexist', 'native-closed'], rows
assert rows[0]['open'] == 0, rows
for row in rows[:3]:
    assert [row[k] for k in ('shown', 'painted', 'wait', 'vsync')] == [0, 0, 0, 0], rows
assert all(row['open'] == -1 for row in rows[1:]), rows
for row in rows[3:4]:
    assert [row[k] for k in ('shown', 'painted', 'wait')] == [1, 1, -1] and row['vsync'] in (0, -1), rows
for row in rows[4:]:
    assert [row[k] for k in ('shown', 'painted', 'wait', 'vsync')] == [0, 0, 0, 0], rows
report = dict(task=1300, status='pass', tk_frame_supported=False,
              conclusion='Tk frame completion is unsupported and does not borrow native results.',
              binary=binary_identity(args.sigma), source=source, states=rows)
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print('pass', len(rows), 'phases; Tk frames explicitly unsupported')
