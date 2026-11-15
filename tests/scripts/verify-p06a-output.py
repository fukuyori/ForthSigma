#!/usr/bin/env python3
"""Compare borrowed output redirection without incorporating reference code."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
a = p.parse_args()
b = a.gforth_build.resolve()
root = pathlib.Path('.work/p06a-output-check').resolve()
root.mkdir(parents=True, exist_ok=True)
commands = {
    'sigma': [str(pathlib.Path('zig-out/bin/sigma').resolve()), '--max-steps', '100000', '-e'],
    'gforth': [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e'],
}
cases = [
    ('basic', ': TXT 65 EMIT S" 日本語" TYPE CR ;', "' TXT A OUTFILE-EXECUTE"),
    ('id', ': TXT OUTFILE-ID A = . ;', "OUTFILE-ID STDOUT = . ' TXT A OUTFILE-EXECUTE OUTFILE-ID STDOUT = ."),
    ('nested', ': INNER 66 EMIT ; : TXT 65 EMIT [\'] INNER B OUTFILE-EXECUTE 67 EMIT ;', "' TXT A OUTFILE-EXECUTE"),
    ('throw', ': TXT 65 EMIT -123 THROW ; : RUN [\'] TXT A OUTFILE-EXECUTE ;', "' RUN CATCH . 90 EMIT"),
    ('inner-catch', ': BAD 65 EMIT -123 THROW ; : TXT [\'] BAD CATCH . 66 EMIT ;', "' TXT A OUTFILE-EXECUTE"),
    ('capture-outer', ': TXT 88 EMIT ; : RUN [\'] TXT A OUTFILE-EXECUTE 89 EMIT ;', "' RUN >STRING-EXECUTE OVER >R TYPE R> FREE THROW"),
    ('capture-inner', ': TXT 88 EMIT ; : RUN [\'] TXT >STRING-EXECUTE OVER >R TYPE R> FREE THROW ;', "' RUN A OUTFILE-EXECUTE"),
    ('tmp-outer', ': TXT 88 EMIT ; : RUN [\'] TXT A OUTFILE-EXECUTE 89 EMIT ;', "' RUN $TMP TYPE"),
]
reports = []
for name, definitions, action in cases:
    outputs = {}
    for runtime, command in commands.items():
        first, second = root / (runtime + '-a.txt'), root / (runtime + '-b.txt')
        code = f'S" {first}" W/O CREATE-FILE THROW CONSTANT A S" {second}" W/O CREATE-FILE THROW CONSTANT B '
        code += definitions + ' ' + action + ' A CLOSE-FILE THROW B CLOSE-FILE THROW DEPTH . BYE'
        result = subprocess.run(command + [code], text=True, capture_output=True, input='', timeout=15)
        assert result.returncode == 0, (name, runtime, result.stdout, result.stderr)
        outputs[runtime] = [result.stdout, first.read_bytes().hex(), second.read_bytes().hex()]
    assert outputs['sigma'] == outputs['gforth'], (name, outputs)
    reports.append({'case': name, 'output': outputs['sigma']})
report = {'pass': True, 'comparisons': len(reports), 'cases': reports}
(root / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False))
