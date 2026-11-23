#!/usr/bin/env python3
"""Check and record Tk's integer nearest-neighbor path; no smoothing claim."""
import argparse
import hashlib
import json
from pathlib import Path
from windows_display_test_support import binary_identity, run
ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma.exe')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
source = '''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-TK 2 2 GFX-INIT
0 0 $FF0000 GFX-PSET 1 0 $0000FF GFX-PSET
0 1 $00FF00 GFX-PSET 1 1 $FFFFFF GFX-PSET
200 100 WINDOW-SIZE FALSE WINDOW-SMOOTH SHOW 100 MS
." SAMPLE false " S" binary encode hex [sigma_view data -format ppm]" TCL-EVAL TYPE CR
TRUE WINDOW-SMOOTH SHOW 100 MS
." SAMPLE true " S" binary encode hex [sigma_view data -format ppm]" TCL-EVAL TYPE CR BYE
'''
output = run(args.sigma, source)
rows = []
for tail in output.split('SAMPLE ')[1:]:
    mode, encoded = tail.splitlines()[0].split()
    image = bytes.fromhex(encoded)
    assert image.startswith(b'P6\n100 100\n255\n'), image[:30]
    data = image.split(b'\n', 3)[3]
    expected = ((b'\xff\0\0' * 50 + b'\0\0\xff' * 50) * 50 +
                (b'\0\xff\0' * 50 + b'\xff\xff\xff' * 50) * 50)
    assert data == expected
    rows.append(dict(smooth=mode, sha256=hashlib.sha256(image).hexdigest(), width=100, height=100))
assert len(rows) == 2 and rows[0]['sha256'] == rows[1]['sha256'], rows
report = dict(status='pass', binary=binary_identity(args.sigma), samples=rows,
              conclusion='WINDOW-SMOOTH is unsupported for Tk; both values use integer nearest-neighbor photo copies',
              scope='Current bundled Tcl script and this wish installation; no assertion about other Tk APIs or libraries')
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print('pass: Tk smooth unsupported; identical expected pixels')
