#!/usr/bin/env python3
"""Behavioral comparison of caller-owned output capture; no reference code copied."""
import argparse
import json
import pathlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--gforth-build', type=pathlib.Path, required=True)
a = parser.parse_args()
b = a.gforth_build.resolve()
commands = {
    'sigma': [str(pathlib.Path('zig-out/bin/sigma').resolve()), '--max-steps', '100000', '-e'],
    'gforth': [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e'],
}
cases = [
    ': OUT S" ABC" TYPE ;',
    ': OUT ;',
    ': OUT 65 EMIT 66 EMIT CR ;',
    ': OUT S" 日本語" TYPE ;',
    ': INNER S" X" TYPE ; : OUT S" a" TYPE [\'] INNER >STRING-EXECUTE OVER >R TYPE R> FREE THROW S" b" TYPE ;',
    ': OUT 42 . ;',
]
results = []
for definitions in cases:
    outputs = {}
    for runtime, command in commands.items():
        source = definitions + " ' OUT >STRING-EXECUTE OVER >R TYPE R> FREE THROW DEPTH . BYE"
        result = subprocess.run(command + [source], text=True, input='', capture_output=True, timeout=15)
        assert result.returncode == 0, (runtime, result.stdout, result.stderr)
        outputs[runtime] = result.stdout
    assert outputs['sigma'] == outputs['gforth'], outputs
    results.append(outputs['sigma'])
folder = pathlib.Path('.work/p06a-capture-check')
folder.mkdir(exist_ok=True)
report = {'pass': True, 'comparisons': len(results), 'outputs': results}
(folder / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False))
