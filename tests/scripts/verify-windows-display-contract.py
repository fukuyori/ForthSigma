#!/usr/bin/env python3
"""Exercise display-support contracts on Windows across native, Tk and terminal.
Creates only owned child windows and a temporary SAVESYS executable. No benchmarks.
"""
import argparse
import sys
import json
from pathlib import Path
import subprocess
import tempfile

from windows_display_test_support import binary_identity, invoke, run

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma.exe')
parser.add_argument('--no-graphics', type=Path, required=True)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
FIELDS = ('tcl open focused minimized closes width height x y view_width view_height '
          'changes shown painted paint_wait vsync display cached_displays native_width native_height native_open native_shown native_painted scale_n scale_d').split()
PRELUDE = '''REQUIRE-GRAPHICS ALSO GRAPHICS
: ACCEPT-FOUR 2SWAP SWAP . . SWAP . . ;
: ACCEPT-STATE ." STATE " GFX-TCL? . WINDOW-OPEN? . WINDOW-FOCUSED? .
WINDOW-MINIMIZED? . WINDOW-CLOSES . WINDOW-PIXELS SWAP . .
WINDOW-IMAGE-RECT ACCEPT-FOUR WINDOW-CHANGES . WINDOW-FRAMES SWAP . .
0 WINDOW-PAINT-WAIT . VSYNC-WAIT . WINDOW-DISPLAY . FALSE GFX-DISPLAYS . GFX-WINDOW-STATE DROP SWAP . . GFX-WINDOW-FLAGS 2DROP DROP . GFX-WINDOW-FRAMES SWAP . . WINDOW-DISPLAY DUP 0< IF DROP 0 0 ELSE DISPLAY-SCALE THEN SWAP . . CR ;
'''
results = []


def states(stdout):
    rows = []
    for tail in stdout.split('STATE ')[1:]:
        values = list(map(int, tail.splitlines()[0].split()))
        assert len(values) == len(FIELDS), values
        rows.append(dict(zip(FIELDS, values)))
    return rows


def absent(row, tcl=0):
    assert row['tcl'] == tcl, row
    assert row['display'] == -1 and row['vsync'] in (0, -1), row
    for key in FIELDS:
        if key not in ('tcl', 'display', 'vsync', 'scale_n', 'scale_d'):
            assert row[key] == 0, (key, row)


for binary, variant in [(args.sigma, 'full')]:
    rows = states(run(binary, PRELUDE + 'DISPLAY-TERMINAL ACCEPT-STATE 4 2 GFX-INIT SHOW ACCEPT-STATE BYE'))
    assert len(rows) == 2
    for row in rows:
        absent(row)
    results.append(dict(case=variant + '-terminal-does-not-start-window-or-tk', states=rows))

    rows = states(run(binary, PRELUDE + 'DISPLAY-TK ACCEPT-STATE 4 2 GFX-INIT 160 100 WINDOW-SIZE SHOW 300 MS DISPLAYS DROP ACCEPT-STATE BYE'))
    assert len(rows) == 2
    absent(rows[0])
    row = rows[1]
    assert row['tcl'] == row['open'] == -1 and row['focused'] in (0, -1), row
    assert row['minimized'] == row['closes'] == row['native_open'] == row['shown'] == row['painted'] == row['changes'] == row['native_width'] == row['native_height'] == 0, row
    assert row['paint_wait'] == 0 and row['vsync'] in (0, -1) and row['display'] >= 0, row
    assert row['scale_n'] == row['scale_d'] and row['scale_n'] > 0, ('This fixture requires scale 1', row)
    assert row['width'] == 160 and row['height'] == 100, row
    assert row['view_width'] == 160 and row['view_height'] == 80, row
    assert row['view_height'] * 2 == row['view_width'], row
    assert row['x'] == (row['width'] - row['view_width']) // 2 and row['y'] == (row['height'] - row['view_height']) // 2, row
    results.append(dict(case=variant + '-tk-table', states=rows))

    source = PRELUDE + '''VARIABLE ACCEPT-N DISPLAYS ACCEPT-N !
: BAD-DISPLAY ACCEPT-N @ DISPLAY-RECT ; : BAD-FIT 3 WINDOW-FIT ;
: BAD-ALPHA 0 0 128 GFX-ALPHA-PSET ;
: BAD-RGB -1 1 1 0 0 0 -1 GFX-RGB ;
4 2 GFX-INIT ." ERRORS " ' BAD-DISPLAY CATCH . ' BAD-FIT CATCH .
' BAD-ALPHA CATCH . ' BAD-RGB CATCH . DEPTH . CR BYE'''
    output = run(binary, source)
    errors = list(map(int, output.split('ERRORS ')[1].splitlines()[0].split()))
    assert errors == [-24, -24, -278, -9, 0], errors
    results.append(dict(case=variant + '-error-contract', errors=errors))

rows = states(run(args.sigma, PRELUDE + '''DISPLAY-WINDOW 4 2 GFX-INIT 160 100 WINDOW-SIZE
SHOW 2000 WINDOW-PAINT-WAIT DROP ACCEPT-STATE
DISPLAY-TERMINAL SHOW ACCEPT-STATE
DISPLAY-TK 200 120 WINDOW-SIZE SHOW 300 MS DISPLAYS DROP ACCEPT-STATE
GFX-WINDOW-CLOSE ACCEPT-STATE BYE'''))
assert len(rows) == 4
for index, row in enumerate(rows[:3]):
    assert row['open'] == row['native_open'] == -1, row
    assert row['native_shown'] == row['native_painted'] == 1, row
    assert row['shown'] == row['painted'] == (0 if index == 2 else 1), row
    assert row['paint_wait'] == (0 if index == 2 else -1), row
    assert row['native_width'] == 160 and row['native_height'] == 100 and row['closes'] == 0, row
assert [rows[0][k] for k in ('width', 'height', 'x', 'y', 'view_width', 'view_height')] == [160, 100, 0, 10, 160, 80], rows[0]
assert [rows[2][k] for k in ('width', 'height', 'view_width', 'view_height', 'x', 'y')] == [200, 120, 200, 100, 0, 10], rows[2]
assert rows[2]['width'] != rows[2]['native_width'], rows[2]
assert rows[1]['tcl'] == 0 and rows[2]['tcl'] == -1
assert rows[3]['native_open'] == rows[3]['paint_wait'] == rows[3]['closes'] == 0, rows[3]
assert rows[3]['shown'] == rows[3]['painted'] == rows[3]['vsync'] == 0 and rows[3]['tcl'] == rows[3]['open'] == -1, rows[3]
results.append(dict(case='switching-backends-keeps-native-window-and-counts', states=rows))

with tempfile.TemporaryDirectory(prefix='sigma-display-contract-') as temporary:
    folder = Path(temporary)
    source = PRELUDE + '''DISPLAY-WINDOW 4 2 GFX-INIT 160 100 WINDOW-SIZE SHOW
2000 WINDOW-PAINT-WAIT DROP DISPLAYS DROP 2 WINDOW-FIT TRUE WINDOW-SMOOTH
TRUE WINDOW-KEEP-OPEN 1 0 1 1 CLIP! 4 IMAGE-MODE 127 IMAGE-ALPHA TRUE IMAGE-SMOOTH
: ACCEPT-MAIN KEY DROP ACCEPT-STATE ." LIBRARY " (MODE) @ . (ALPHA) @ . (SMOOTH) @ . CR ;
' ACCEPT-MAIN APP-ENTRY! SAVESYS display-app.exe ACCEPT-STATE BYE'''
    saved_rows = states(run(args.sigma, source, folder))
    assert len(saved_rows) == 1, saved_rows
    before = saved_rows[0]
    assert before['open'] == -1 and before['cached_displays'] > 0, before
    app = folder / 'display-app.exe'
    output = invoke(app)
    fresh_rows = states(output)
    assert len(fresh_rows) == 1, fresh_rows
    fresh = fresh_rows[0]
    absent(fresh)
    library = list(map(int, output.split('LIBRARY ')[1].splitlines()[0].split()))
    assert library == [4, 127, -1], library
    results.append(dict(case='saved-app-starts-without-runtime-resources', app=binary_identity(app), before=before, fresh=fresh, library=library))

names = ['DISPLAYS', 'WINDOW-OPEN?', 'WINDOW-PIXELS', 'WINDOW-FIT', 'WINDOW-CLOSE',
         'WINDOW-SMOOTH', 'WINDOW-PAINT-WAIT', 'CLIP!', 'GFX-RGB', 'PUT-ROTATED', 'IMAGE-KEEP-ALPHA']
defined = ' '.join('[DEFINED] ' + name + ' .' for name in names)
positive = run(args.sigma, 'REQUIRE-GRAPHICS ALSO GRAPHICS ' + defined + ' BYE')
assert list(map(int, positive.split())) == [-1] * len(names), positive
source = ': ACCEPT-REQUIRE S" REQUIRE-GRAPHICS" EVALUATE ; \' ACCEPT-REQUIRE CATCH . [DEFINED] GRAPHICS . ' + defined + ' BYE'
output = run(args.no_graphics, source)
assert list(map(int, output.split())) == [-270, 0] + [0] * len(names), output
results.append(dict(case='graphics-excluded-words-absent', names=names, require_error=-270, full_positive_control=True))
source = PRELUDE + '''4 2 GFX-INIT
: BAD-FULLSCREEN DISPLAY-TERMINAL TRUE FULLSCREEN ;
: BAD-WAIT -1 GFX-FRAME-WAIT ; : LONG-WAIT 60001 GFX-FRAME-WAIT ;
." ERRORS " ' BAD-FULLSCREEN CATCH . ' BAD-WAIT CATCH . ' LONG-WAIT CATCH . DEPTH . CR BYE'''
output = run(args.sigma, source)
errors = list(map(int, output.split('ERRORS ')[1].splitlines()[0].split()))
assert errors == [-21, -24, -24, 0], errors
results.append(dict(case='terminal-fullscreen-and-wait-error-contract', errors=errors))
output = run(args.sigma, PRELUDE + '." CLAMPED " -1 WINDOW-PAINT-WAIT . 60001 WINDOW-PAINT-WAIT . DEPTH . CR BYE')
clamped = list(map(int, output.split('CLAMPED ')[1].splitlines()[0].split()))
assert clamped == [0, 0, 0], clamped
results.append(dict(case='public-wait-clamps-range-without-window', values=clamped))
small = states(run(args.sigma, PRELUDE + 'DISPLAY-WINDOW 4 2 GFX-INIT 64 40 WINDOW-SIZE SHOW 2000 WINDOW-PAINT-WAIT DROP DISPLAYS DROP ACCEPT-STATE BYE'))
assert len(small) == 1 and small[0]['width'] >= 64 and small[0]['height'] >= 40, small
results.append(dict(case='small-request-versus-actual-client-size', requested=[64, 40], states=small))
report = dict(status='pass', platform=sys.platform, working_tree=subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).splitlines(), source_revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              binaries={name: binary_identity(binary) for name, binary in
                        [('full', args.sigma), ('no-graphics', args.no_graphics)]},
              limitations=['Tk frame completion is unsupported and reports zeros/false even alongside native',
                           'No physical display reconnect, DPI change, buttons, IME or presentation timing'],
              cases=results)
encoded = json.dumps(report, indent=2)
if args.output:
    args.output.write_text(encoded + '\n', encoding='utf-8')
print(encoded)
