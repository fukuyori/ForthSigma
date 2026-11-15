#!/usr/bin/env python3
"""Record reference observations for the pending input-redirection design."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
a = p.parse_args()
b = a.gforth_build.resolve()
root = pathlib.Path('.work/p06a-input-check').resolve()
root.mkdir(parents=True, exist_ok=True)
command = [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e']
cases = [
    ('escape', b'\x1b[A', 'EKEY . EKEY . EKEY .'),
    ('utf8', '日'.encode(), 'EKEY .'),
    ('accept', b'AB\nCD\n', 'PAD 1 ACCEPT . PAD 1 TYPE KEY .'),
    ('eof', b'', "['] GET CATCH ."),
    ('readiness-eof', b'', 'KEY? . EKEY .'),
]
results = []
for name, data, body in cases:
    path = root / name
    path.write_bytes(data)
    source = f': GET KEY ; : READIT {body} ; S" {path}" R/O OPEN-FILE THROW DUP >R \' READIT SWAP INFILE-EXECUTE R> CLOSE-FILE THROW BYE'
    run = subprocess.run(command + [source], input=b'', capture_output=True, timeout=10)
    results.append({'case': name, 'source': source, 'input_hex': data.hex(),
                    'stdout_hex': run.stdout.hex(), 'stderr': run.stderr.decode(errors='replace'),
                    'exit': run.returncode})
report = {'kind': 'observations, not Sigma conformance checks', 'cases': results}
(root / 'initial-probes.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False))
