#!/usr/bin/env python3
"""macOS: Tk close retention (tque 1338) with actual wish and Tcl-driven protocol callbacks."""
import argparse
import json
from pathlib import Path
from macos_display_test_support import binary_identity, run

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()

def tcl(script):
    assert '"' not in script
    return 'S" ' + script + '" TCL '

steps = [
    ('before', 'TRUE WINDOW-KEEP-OPEN WINDOW-CLOSE', 0, 0),
    ('shown', '4 2 GFX-INIT 160 100 WINDOW-SIZE SHOW', -1, 0),
    ('first-request-held', tcl('sigma_window_close_request'), -1, 1),
    ('acknowledged', 'WINDOW-CLOSES DROP', -1, 1),
    ('request-after-ack-held', tcl('sigma_window_close_request'), -1, 2),
    ('other-queries-do-not-ack', 'WINDOW-OPEN? DROP WINDOW-FOCUSED? DROP WINDOW-MINIMIZED? DROP ' + tcl('sigma_window_close_request'), 0, 3),
    ('reopened', 'SHOW', -1, 3),
    ('explicit-close-not-counted', 'WINDOW-CLOSE', 0, 3),
    ('two-requests-escape', 'SHOW ' + tcl('sigma_window_close_request; sigma_window_close_request'), 0, 5),
    ('disable-pending', 'SHOW ' + tcl('sigma_window_close_request') + 'FALSE WINDOW-KEEP-OPEN', -1, 6),
    ('default-close', tcl('sigma_window_close_request'), 0, 7),
    ('reenable', 'TRUE WINDOW-KEEP-OPEN SHOW ' + tcl('sigma_window_close_request'), -1, 8),
    ('stop', 'TCL-STOP', 0, 8),
    ('restart-inherits-setting', 'SHOW ' + tcl('sigma_window_close_request'), -1, 9),
    ('restart-escape', tcl('sigma_window_close_request'), 0, 10),
    ('native-and-tk', 'DISPLAY-WINDOW SHOW 2000 WINDOW-PAINT-WAIT DROP DISPLAY-TK SHOW WINDOW-CLOSE', 0, 10),
    ('destroy-label', 'SHOW ' + tcl('destroy .sigma; update') + 'WINDOW-CLOSE', 0, 10),
]
source = '''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-TK
: REPORT GFX-TK-WINDOW-FLAGS . . . . GFX-WINDOW-FLAGS 2DROP DROP . GFX-TCL? . DEPTH . CR ;
'''
for name, action, _, _ in steps:
    source += action + ' 100 MS ." STEP ' + name + ' " REPORT\n'
source += 'S" set sentinel original" TCL-EVAL WINDOW-CLOSES DROP WINDOW-CLOSE ." PRESERVED " TYPE CR TCL-STOP GFX-WINDOW-CLOSE BYE'
output = run(args.sigma, source)
rows = []
for tail in output.split('STEP ')[1:]:
    fields = tail.splitlines()[0].split()
    name = fields.pop(0)
    values = list(map(int, fields))
    assert len(values) == 7, values
    row = dict(zip(('closes', 'minimized', 'focused', 'open', 'native_open', 'tcl', 'depth'), values))
    rows.append(dict(phase=name, state=row))
assert len(rows) == len(steps), output
for row, (name, _, opened, closes) in zip(rows, steps):
    state = row['state']
    assert row['phase'] == name and state['open'] == opened and state['closes'] == closes and state['depth'] == 0, row
    assert state['tcl'] == (0 if name in ('before', 'stop') else -1), row
    assert state['native_open'] == (-1 if name in ('native-and-tk', 'destroy-label') else 0), row
assert 'PRESERVED original' in output, output
report = dict(status='pass', binary=binary_identity(args.sigma), phases=rows,
              limitations=['Tcl invokes the installed WM close handler; no physical close button test'])
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print('pass', len(rows), 'phases')
