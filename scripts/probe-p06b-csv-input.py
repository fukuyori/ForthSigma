#!/usr/bin/env python3
"""Record CSV-reader edge behavior before specifying the independent implementation."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
a = p.parse_args()
b = a.gforth_build.resolve()
root = pathlib.Path('.work/p06b-csv-input-check').resolve()
root.mkdir(parents=True, exist_ok=True)
command = [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e']
cases = {
    'empty': b'', 'blank': b'\n', 'plain': b'a,b\nc,d\n',
    'trailing': b'a,\n,,\n', 'quoted': b'"a,b","c""d"\n',
    'multiline': b'"a\nb",c\nd,e\n', 'unclosed': b'"a\nb',
    'mid-quote': b'a"b,c\n', 'after-quote': b'"a"x,b\n',
    'crlf': b'"a\r\nb",c\r\n', 'no-final-newline': b'a,b',
}
results = []
for title, data in cases.items():
    path = root / (title + '.csv')
    path.write_bytes(data)
    source = 'REQUIRE csv.fs : FIELD . . DUP . BOUNDS ?DO I C@ . LOOP 124 EMIT ; '
    source += f'S" {path}" \' FIELD READ-CSV DEPTH . BYE'
    try:
        run = subprocess.run(command + [source], input=b'', capture_output=True, timeout=10)
        results.append({'case': title, 'input_hex': data.hex(), 'exit': run.returncode,
                        'stdout': run.stdout.decode(errors='replace'), 'stderr': run.stderr.decode(errors='replace')})
    except subprocess.TimeoutExpired:
        results.append({'case': title, 'timeout': True})
report = {'kind': 'reference observations, not Sigma conformance', 'cases': results}
(root / 'initial-probes.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'observations': len(results), 'report': str(root / 'initial-probes.json')}, ensure_ascii=False))
