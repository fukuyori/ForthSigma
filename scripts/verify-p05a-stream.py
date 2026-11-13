#!/usr/bin/env python3
"""Compare EMIT-FILE and regular-file SLURP-FID with the designated Gforth."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('sigma', nargs='?', default='zig-out/bin/sigma')
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
p.add_argument('--report', type=pathlib.Path)
a = p.parse_args()
b = a.gforth_build.resolve()
folder = pathlib.Path('.work/p05a-stream-check').resolve()
folder.mkdir(parents=True, exist_ok=True)
commands = {
    'sigma': [str(pathlib.Path(a.sigma).resolve()), '--max-steps', '100000', '-e'],
    'gforth': [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e'],
}
cases = []
for value in [-1, 0, 10, 65, 255, 256, 511, 65535]:
    path = folder / 'emit.bin'
    source = f'S" {path}" W/O CREATE-FILE THROW >R {value} R@ EMIT-FILE . R> CLOSE-FILE THROW S" {path}" R/O OPEN-FILE THROW >R R@ SLURP-FID DUP . DROP DUP C@ . FREE THROW R> CLOSE-FILE THROW'
    cases.append(('emit-' + str(value), source, ['0', '1', str(value & 255)]))
for size in [0, 1, 1023, 1024, 1025, 4097]:
    path = folder / ('日本語-' + str(size) + '.bin')
    data = bytes(i % 256 for i in range(size))
    path.write_bytes(data)
    for offset in sorted({0, size // 2, size, size + 3}):
        source = f': SUM-BYTES 0 -ROT BOUNDS ?DO I C@ + LOOP ; S" {path}" R/O OPEN-FILE THROW >R {offset} 0 R@ REPOSITION-FILE THROW R@ SLURP-FID DUP . OVER >R SUM-BYTES . R> FREE THROW R@ FILE-POSITION THROW D>S . R> CLOSE-FILE THROW'
        cases.append((f'slurp-{size}-{offset}', source, [str(max(0, size - offset)), str(sum(data[offset:])), str(max(offset, size))]))
for name, source, expected in cases:
    for runtime, command in commands.items():
        r = subprocess.run(command + [source + ' DEPTH . BYE'], capture_output=True, text=True, input='', timeout=15)
        assert r.returncode == 0 and r.stdout.split() == expected + ['0'], (name, runtime, r.returncode, r.stdout, r.stderr)
report = {'words': 2, 'cases': len(cases), 'checked': list(commands), 'pass': True}
if a.report:
    a.report.parent.mkdir(parents=True, exist_ok=True)
    a.report.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
