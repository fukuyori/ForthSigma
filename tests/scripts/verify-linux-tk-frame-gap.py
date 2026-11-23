#!/usr/bin/env python3
"""Record the unimplemented Tk frame contract (#1303), not Tk acceptance.

Creates owned Tk/native windows. Confirms explicit unsupported Tk frame results;
remove/replace these expectations when implementing Tk frame completion.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
from linux_x11_test_support import binary_identity, require_linux, stop_process_group

ROOT = Path(__file__).resolve().parents[2]
require_linux()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma')
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
process = subprocess.Popen([str(args.sigma.resolve()), '-e', source],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, start_new_session=True)
try:
    stdout, stderr = process.communicate(b'', timeout=25)
    output = stdout.decode('utf-8', 'replace')
    assert process.returncode == 0 and not stderr, (process.returncode, output, stderr)
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
        assert [row[k] for k in ('shown', 'painted', 'wait', 'vsync')] == [1, 1, -1, 0], rows
    for row in rows[4:]:
        assert [row[k] for k in ('shown', 'painted', 'wait', 'vsync')] == [0, 0, 0, 0], rows
    print(json.dumps(dict(task=1303, acceptance=False,
                         conclusion='Tk frame completion is unsupported and does not borrow native results.',
                         binary=binary_identity(args.sigma),
                         environment={k: os.environ.get(k) for k in ('XDG_SESSION_TYPE', 'DISPLAY')},
                         source=source, states=rows), indent=2))
finally:
    stop_process_group(process)
