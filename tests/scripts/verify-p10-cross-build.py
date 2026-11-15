#!/usr/bin/env python3
"""Load a full-build dictionary in feature-excluded builds without exposing excluded words."""
import argparse
import json
import os
from pathlib import Path
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--default', type=Path, required=True)
p.add_argument('--matrix', type=Path, required=True)
a = p.parse_args()
folder = a.matrix.resolve()
image = folder / 'full-build.sigma'
default = str(a.default.resolve(strict=True))

def run(exe, source):
    r = subprocess.run([str(exe), '-e', source + ' BYE'], input=b'', capture_output=True, timeout=30)
    assert r.returncode == 0, (str(exe), r.returncode, r.stdout, r.stderr)
    return r.stdout

assert run(default, f': SAFE-W 42 ; : FLOAT-W 1E 2E F+ FDROP ; SAVE {image}') == b''
rows = []
for group in ['float', 'files', 'help', 'tools', 'graphics', 'audio', 'debug']:
    exe = folder / ('no-' + group) / 'bin' / ('sigma.exe' if os.name == 'nt' else 'sigma')
    actual = run(exe, f'LOAD-DICTIONARY {image} SAFE-W . [DEFINED] F+ . \' FLOAT-W CATCH . DEPTH .')
    expected = b'42 0 -261 0 ' if group == 'float' else b'42 -1 0 0 '
    assert actual == expected, (group, actual, expected)
    rows.append({'disabled': group, 'stdout_hex': actual.hex()})
(folder / 'cross-build.json').write_text(json.dumps({'complete': True, 'cases': rows}, indent=2) + '\n')
print(f'{len(rows)} cross-build image cases passed')
