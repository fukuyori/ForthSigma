#!/usr/bin/env python3
"""Exercise display-support contracts on Linux across native, Tk and terminal.
Creates only owned child windows and a temporary SAVESYS executable. No benchmarks.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

from linux_x11_test_support import binary_identity, require_linux, stop_process_group

ROOT = Path(__file__).resolve().parents[2]
require_linux()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma')
parser.add_argument('--no-graphics', type=Path, required=True)
parser.add_argument('--no-x11', type=Path, required=True)
args = parser.parse_args()
FIELDS = ('tcl open focused minimized closes width height x y view_width view_height '
          'changes shown painted paint_wait vsync display cached_displays native_width native_height native_open').split()
PRELUDE = '''REQUIRE-GRAPHICS ALSO GRAPHICS
: ACCEPT-FOUR 2SWAP SWAP . . SWAP . . ;
: ACCEPT-STATE ." STATE " GFX-TCL? . WINDOW-OPEN? . WINDOW-FOCUSED? .
WINDOW-MINIMIZED? . WINDOW-CLOSES . WINDOW-PIXELS SWAP . .
WINDOW-IMAGE-RECT ACCEPT-FOUR WINDOW-CHANGES . WINDOW-FRAMES SWAP . .
0 WINDOW-PAINT-WAIT . VSYNC-WAIT . WINDOW-DISPLAY . FALSE GFX-DISPLAYS . GFX-WINDOW-STATE DROP SWAP . . GFX-WINDOW-FLAGS 2DROP DROP . CR ;
'''
results = []


def invoke(binary, arguments, cwd=None):
    process = subprocess.Popen([str(binary.resolve())] + arguments, cwd=cwd,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    try:
        stdout, stderr = process.communicate(input=b'', timeout=25)
        output = stdout.decode('utf-8', 'replace')
        assert process.returncode == 0 and not stderr, (process.returncode, output, stderr)
        # Runtime errors can print to stdout while the process still returns zero.
        assert 'BACKTRACE:' not in output and 'STACK UNDER FLOW' not in output, output
        return output
    finally:
        stop_process_group(process)


def run(binary, source, cwd=None):
    return invoke(binary, ['-e', source], cwd)


def states(stdout):
    rows = []
    for tail in stdout.split('STATE ')[1:]:
        values = list(map(int, tail.splitlines()[0].split()))
        assert len(values) == len(FIELDS), values
        rows.append(dict(zip(FIELDS, values)))
    return rows


def absent(row, tcl=0):
    assert row['tcl'] == tcl, row
    assert row['display'] == -1, row
    for key in FIELDS:
        if key not in ('tcl', 'display'):
            assert row[key] == 0, (key, row)


for binary, variant in [(args.sigma, 'full'), (args.no_x11, 'no-x11')]:
    rows = states(run(binary, PRELUDE + 'DISPLAY-TERMINAL ACCEPT-STATE 4 2 GFX-INIT SHOW ACCEPT-STATE BYE'))
    assert len(rows) == 2
    for row in rows:
        absent(row)
    results.append(dict(case=variant + '-terminal-does-not-start-window-or-tk', states=rows))

    rows = states(run(binary, PRELUDE + 'DISPLAY-TK ACCEPT-STATE 4 2 GFX-INIT 64 40 WINDOW-SIZE SHOW 300 MS ACCEPT-STATE BYE'))
    assert len(rows) == 2
    absent(rows[0])
    row = rows[1]
    assert row['tcl'] == row['open'] == -1 and row['focused'] in (0, -1), row
    assert row['minimized'] == row['closes'] == row['native_open'] == row['shown'] == row['painted'] == row['changes'] == row['native_width'] == row['native_height'] == 0, row
    assert row['paint_wait'] == row['vsync'] == 0 and row['display'] == -1, row
    expected = [64, 40, 0, 4, 64, 32] if variant == 'full' else [0] * 6
    assert [row[k] for k in ('width', 'height', 'x', 'y', 'view_width', 'view_height')] == expected, row
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

rows = states(run(args.sigma, PRELUDE + '''DISPLAY-WINDOW 4 2 GFX-INIT 64 40 WINDOW-SIZE
SHOW 2000 WINDOW-PAINT-WAIT DROP ACCEPT-STATE
DISPLAY-TERMINAL SHOW ACCEPT-STATE
DISPLAY-TK SHOW 300 MS ACCEPT-STATE
GFX-WINDOW-CLOSE ACCEPT-STATE BYE'''))
assert len(rows) == 4
for row in rows[:2]:
    assert row['open'] == row['native_open'] == -1 and row['shown'] == row['painted'] == 1 and row['paint_wait'] == -1, row
    assert row['native_width'] == 64 and row['native_height'] == 40 and row['closes'] == 0, row
assert rows[1]['tcl'] == 0 and rows[2]['tcl'] == -1
assert rows[3]['native_open'] == rows[3]['paint_wait'] == rows[3]['closes'] == 0, rows[3]
assert rows[2]['open'] == rows[2]['native_open'] == -1 and rows[2]['shown'] == rows[2]['painted'] == rows[2]['paint_wait'] == 0, rows[2]
assert rows[3]['shown'] == rows[3]['painted'] == 0 and rows[3]['tcl'] == rows[3]['open'] == -1, rows[3]
results.append(dict(case='switching-backends-keeps-native-window-and-counts', states=rows))

with tempfile.TemporaryDirectory(prefix='sigma-display-contract-') as temporary:
    folder = Path(temporary)
    source = PRELUDE + '''DISPLAY-WINDOW 4 2 GFX-INIT 64 40 WINDOW-SIZE SHOW
2000 WINDOW-PAINT-WAIT DROP DISPLAYS DROP 2 WINDOW-FIT TRUE WINDOW-SMOOTH
TRUE WINDOW-KEEP-OPEN 1 0 1 1 CLIP! 4 IMAGE-MODE 127 IMAGE-ALPHA TRUE IMAGE-SMOOTH
: ACCEPT-MAIN ACCEPT-STATE ." LIBRARY " (MODE) @ . (ALPHA) @ . (SMOOTH) @ . CR ;
' ACCEPT-MAIN APP-ENTRY! SAVESYS display-app ACCEPT-STATE BYE'''
    before = states(run(args.sigma, source, folder))[0]
    assert before['open'] == -1 and before['cached_displays'] > 0, before
    app = folder / 'display-app'
    output = invoke(app, [])
    fresh = states(output)[0]
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
: BAD-WINDOW DISPLAY-WINDOW ; : BAD-SHOW 2 (DISPLAY) ! SHOW ;
: BAD-FULLSCREEN DISPLAY-TERMINAL TRUE FULLSCREEN ;
." ERRORS " ' BAD-WINDOW CATCH . ' BAD-SHOW CATCH . ' BAD-FULLSCREEN CATCH . DEPTH . CR BYE'''
output = run(args.no_x11, source)
errors = list(map(int, output.split('ERRORS ')[1].splitlines()[0].split()))
assert errors == [-21, -265, -21, 0], errors
results.append(dict(case='no-x11-backend-error-contract', errors=errors))
print(json.dumps(dict(status='pass', binaries={name: binary_identity(binary) for name, binary in
                     [('full', args.sigma), ('no-x11', args.no_x11), ('no-graphics', args.no_graphics)]},
                     cases=results), indent=2))
