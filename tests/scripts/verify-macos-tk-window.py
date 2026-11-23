#!/usr/bin/env python3
"""macOS (tque 1288): Tk's WINDOW-FIT, WINDOW-PIXELS, and WINDOW-IMAGE-RECT.

Records the current contract on Aqua: Tk lays the image out by whole factors whatever
WINDOW-FIT asks (as on Windows and Linux), and the host cannot tell the Tk window's
size in physical pixels (Aqua's `winfo id` is not a macOS window number), so
WINDOW-PIXELS is 0 0 and WINDOW-IMAGE-RECT four zeros. Tk's own rectangle
(sigma_view_rect, in Tk pixels) is checked against the whole-factor rule.
"""
import argparse
import json
from pathlib import Path
from macos_display_test_support import binary_identity, run

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
sizes = [(640, 400), (503, 307), (91, 61)]
source = '''REQUIRE-GRAPHICS ALSO GRAPHICS 160 100 GFX-INIT DISPLAY-TK
: ACCEPT-RECT WINDOW-IMAGE-RECT 2SWAP SWAP . . SWAP . . ;
." BEFORE " WINDOW-PIXELS SWAP . . ACCEPT-RECT CR
640 400 WINDOW-SIZE SHOW 300 MS
'''
for width, height in sizes:
    source += f'S" wm geometry . {width}x{height}; update" TCL-EVAL 2DROP 300 MS SHOW 300 MS\n'
    for mode in range(3):
        source += f'''{mode} WINDOW-FIT SHOW 200 MS
." CASE {width} {height} {mode} " WINDOW-PIXELS SWAP . . ACCEPT-RECT S" winfo width .; winfo height .; sigma_view_rect" TCL-EVAL TYPE CR
'''
source += 'TCL-STOP BYE'
output = run(args.sigma, source)
lines = [line for line in output.splitlines() if line.startswith(('BEFORE', 'CASE'))]
assert lines[0].split() == ['BEFORE'] + ['0'] * 6, lines[0]
cases = []
for line in lines[1:]:
    fields = line.split()
    width, height, mode = map(int, fields[1:4])
    pixels = list(map(int, fields[4:6]))
    rect = list(map(int, fields[6:10]))
    tk = list(map(int, fields[10:]))
    assert pixels == [0, 0] and rect == [0, 0, 0, 0], line
    # sigma_view_rect: x y w h of the image and the Tk window's width and height.
    view, tk_size = tk[:4], tk[4:6]
    factor = min(tk_size[0] // 160, tk_size[1] // 100)
    if factor >= 1:
        image_size = [160 * factor, 100 * factor]
    else:
        step = max((160 + tk_size[0] - 1) // tk_size[0], (100 + tk_size[1] - 1) // tk_size[1])
        image_size = [(160 + step - 1) // step, (100 + step - 1) // step]
    assert view == [(tk_size[0] - image_size[0]) // 2, (tk_size[1] - image_size[1]) // 2] + image_size, line
    cases.append(dict(requested=[width, height], fit=mode, pixels=pixels, rect=rect, tk_view=view, tk_size=tk_size))
assert len(cases) == 9, lines
for offset in range(0, 9, 3):
    assert cases[offset]['tk_view'] == cases[offset + 1]['tk_view'] == cases[offset + 2]['tk_view'], cases
report = dict(task=1288, status='pass', binary=binary_identity(args.sigma), cases=cases,
              conclusion='Tk ignores WINDOW-FIT (whole factors); WINDOW-PIXELS and WINDOW-IMAGE-RECT are zeros for Tk on macOS.')
encoded = json.dumps(report, indent=2)
if args.output:
    args.output.write_text(encoded + '\n', encoding='utf-8')
print('pass', len(cases), 'cases')
