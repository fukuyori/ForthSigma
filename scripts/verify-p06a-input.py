#!/usr/bin/env python3
"""Compare input selection; assert approved Sigma line/Unicode differences separately."""
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
commands = {
    'sigma': [str(pathlib.Path('zig-out/bin/sigma').resolve()), '--max-steps', '100000', '-e'],
    'gforth': [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e'],
}
cases = [
    ('key', b'AC', b'B', ': R KEY . KEY . ;', "' R A INFILE-EXECUTE"),
    ('ids', b'AC', b'B', ': R INFILE-ID A = . ;', "INFILE-ID STDIN = . ' R A INFILE-EXECUTE INFILE-ID STDIN = ."),
    ('nested', b'AC', b'B', ': INNER KEY . ; : R KEY . [\'] INNER B INFILE-EXECUTE KEY . ;', "' R A INFILE-EXECUTE"),
    ('same-stream', b'AC', b'B', ': INNER KEY . ; : R KEY . [\'] INNER A INFILE-EXECUTE ;', "' R A INFILE-EXECUTE"),
    ('throw', b'AC', b'B', ': R KEY DROP -123 THROW ; : RUN [\'] R A INFILE-EXECUTE ;', "' RUN CATCH . A KEY-FILE . INFILE-ID STDIN = ."),
    ('ready', b'A', b'', ': R KEY? . EKEY? . KEY . KEY? . ;', "' R A INFILE-EXECUTE"),
    ('escape', b'\x1b[A', b'', ': R EKEY . EKEY . EKEY . ;', "' R A INFILE-EXECUTE"),
    ('evaluate-refill', b'A', b'', ': R S" REFILL ." EVALUATE ;', "' R A INFILE-EXECUTE A KEY-FILE ."),
]
reports = []
def run(runtime, first, second, definitions, action):
    fa, fb = root / (runtime + '-a'), root / (runtime + '-b')
    fa.write_bytes(first)
    fb.write_bytes(second)
    source = f'S" {fa}" R/O OPEN-FILE THROW CONSTANT A S" {fb}" R/O OPEN-FILE THROW CONSTANT B '
    source += definitions + ' ' + action + ' A CLOSE-FILE THROW B CLOSE-FILE THROW DEPTH . BYE'
    result = subprocess.run(commands[runtime] + [source], input=b'', capture_output=True, timeout=15)
    assert result.returncode == 0, (runtime, result.stdout, result.stderr)
    return result.stdout.decode()
for title, first, second, definitions, action in cases:
    outputs = {r: run(r, first, second, definitions, action) for r in commands}
    assert outputs['sigma'] == outputs['gforth'], (title, outputs)
    reports.append({'case': title, 'output': outputs['sigma']})
# These expectations were approved separately; they are not Gforth equivalence claims.
differences = []
for title, data, definitions, action, expected in [
    ('line-no-echo-clips', b'AB\nCD\n', ': R PAD 1 ACCEPT . PAD 1 TYPE KEY . ;', "' R A INFILE-EXECUTE", '1 A67 0 '),
    ('unicode-codepoint', '日'.encode(), ': R EKEY . ;', "' R A INFILE-EXECUTE", '26085 0 '),
    ('key-eof', b'', ': R KEY DROP ; : RUN [\'] R A INFILE-EXECUTE ;', "' RUN CATCH .", '-262 0 '),
]:
    outputs = {r: run(r, data, b'', definitions, action) for r in commands}
    assert outputs['sigma'] == expected, (title, outputs)
    differences.append({'case': title, 'outputs': outputs})
unread_checks = []
for title, data, definitions, action, expected in [
    ('xkey-unread-across-scope', b'\xc3Z', ': R XKEY . ;', "' R A INFILE-EXECUTE A KEY-FILE .", '65533 90 0 '),
    ('ekey-unread-across-scope', b'\xc3Z', ': R EKEY . ;', "' R A INFILE-EXECUTE A KEY-FILE .", '65533 90 0 '),
    ('cr-unread', b'AB\rZ\n', ': R PAD 1 ACCEPT . PAD 1 TYPE ;', "' R A INFILE-EXECUTE A KEY-FILE .", '1 A90 0 '),
]:
    output = run('sigma', data, b'', definitions, action)
    assert output == expected, (title, output)
    unread_checks.append({'case': title, 'output': output})
report = {'pass': True, 'gforth_comparisons': len(reports), 'approved_difference_checks': len(differences), 'cases': reports, 'differences': differences, 'sigma_unread_checks': unread_checks}
(root / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False))
