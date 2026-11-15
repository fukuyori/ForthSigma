#!/usr/bin/env python3
"""Compare public CSV value and quoting behavior; no reference code copied."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
a = p.parse_args()
b = a.gforth_build.resolve()
root = pathlib.Path('.work/p06b-csv-output-check').resolve()
root.mkdir(parents=True, exist_ok=True)
commands = {
    'sigma': [str(pathlib.Path('zig-out/bin/sigma').resolve()), '--max-steps', '100000', '-e'],
    'gforth': [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e'],
}
results = []
for quote in [34, 39, 0, 256, -1]:
    for index, data in enumerate([b'', b'ab', b'a"b\',\r\n', '日本語'.encode(), b'\x00\xff']):
        path = root / 'field.bin'
        path.write_bytes(data)
        outputs = {}
        for runtime, command in commands.items():
            source = ('REQUIRE csv.fs ' if runtime == 'gforth' else '')
            source += f'{quote} TO CSV-QUOTE S" {path}" SLURP-FILE OVER >R .QUOTED-CSV R> FREE THROW DEPTH . BYE'
            run = subprocess.run(command + [source], input=b'', capture_output=True, timeout=15)
            assert run.returncode == 0, (runtime, quote, index, run.stdout, run.stderr)
            outputs[runtime] = run.stdout.hex()
        assert outputs['sigma'] == outputs['gforth'], (quote, index, outputs)
        results.append({'quote': quote, 'input': data.hex(), 'output': outputs['sigma']})
for source in ['CSV-QUOTE . CSV-SEPARATOR .', ': CONFIG 39 TO CSV-QUOTE 59 TO CSV-SEPARATOR ; CONFIG CSV-QUOTE . CSV-SEPARATOR .', '1 +TO CSV-QUOTE 2 +TO CSV-SEPARATOR CSV-QUOTE . CSV-SEPARATOR .']:
    outputs = {}
    for runtime, command in commands.items():
        run = subprocess.run(command + [('REQUIRE csv.fs ' if runtime == 'gforth' else '') + source + ' DEPTH . BYE'], input=b'', capture_output=True, timeout=15)
        assert run.returncode == 0, (runtime, run.stdout, run.stderr)
        outputs[runtime] = run.stdout.hex()
    assert outputs['sigma'] == outputs['gforth'], outputs
    results.append({'source': source, 'output': outputs['sigma']})
report = {'pass': True, 'comparisons': len(results), 'cases': results}
(root / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'pass': True, 'comparisons': len(results)}))
