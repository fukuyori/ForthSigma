#!/usr/bin/env python3
"""Behavioral CSV-reader comparisons only; no reference implementation incorporated."""
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
commands = {
    'sigma': [str(pathlib.Path('zig-out/bin/sigma').resolve()), '--max-steps', '100000', '-e'],
    'gforth': [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e'],
}
cases = {
    'empty': b'', 'blank': b'\n', 'plain': b'a,b\nc,d\n', 'trailing': b'a,\n,,\n',
    'quoted': b'"a,b","c""d"\n', 'multiline': b'"a\nb",c\nd,e\n',
    'unclosed': b'"a\nb', 'mid-quote': b'a"b,c\n', 'after-quote': b'"a"x,b\n',
    'crlf': b'"a\r\nb",c\r\n', 'no-final-newline': b'a,b',
    'unicode': '"日本,語",名前\n'.encode(), 'binary': b'"a\x00b",\xff\n',
    'doubled-unquoted': b'a""b,c"\n', 'empty-quotes': b'"",""\n',
    'quoted-blank-line': b'"a\n\nb",c\n',
}
results = []
for title, data in cases.items():
    path = root / (title + '.csv')
    path.write_bytes(data)
    outputs = {}
    for runtime, command in commands.items():
        source = ('REQUIRE csv.fs ' if runtime == 'gforth' else '')
        source += ': CSV-FIELD . . DUP . BOUNDS ?DO I C@ . LOOP 124 EMIT ; '
        source += f'S" {path}" \' CSV-FIELD READ-CSV DEPTH . BYE'
        run = subprocess.run(command + [source], input=b'', capture_output=True, timeout=15)
        assert run.returncode == 0, (title, runtime, run.stdout, run.stderr)
        outputs[runtime] = run.stdout.decode()
    assert outputs['sigma'] == outputs['gforth'], (title, outputs)
    results.append({'case': title, 'output': outputs['sigma']})
path = root / 'plain.csv'
for title, definitions, action in [
    ('throw', ': CSV-FIELD 2DROP 2DROP -123 THROW ; : RUN S" ' + str(path) + '" [\'] CSV-FIELD READ-CSV ;', "' RUN CATCH ."),
    ('history', ': CSV-FIELD 2DROP 2DROP ;', f'S" {path}" INCLUDED? . S" {path}" \' CSV-FIELD READ-CSV S" {path}" INCLUDED? .'),
    ('source', ': CSV-FIELD 2DROP 2DROP SOURCE-ID 0> . SOURCELINE# . ;', f'S" {path}" \' CSV-FIELD READ-CSV'),
]:
    outputs = {}
    for runtime, command in commands.items():
        source = ('REQUIRE csv.fs ' if runtime == 'gforth' else '') + definitions + ' ' + action + ' DEPTH . BYE'
        run = subprocess.run(command + [source], input=b'', capture_output=True, timeout=15)
        assert run.returncode == 0, (title, runtime, run.stdout, run.stderr)
        outputs[runtime] = run.stdout.decode()
    assert outputs['sigma'] == outputs['gforth'], (title, outputs)
    results.append({'case': title, 'output': outputs['sigma']})
report = {'pass': True, 'comparisons': len(results), 'cases': results}
(root / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'pass': True, 'comparisons': len(results)}))
