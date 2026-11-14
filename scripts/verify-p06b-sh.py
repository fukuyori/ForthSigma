#!/usr/bin/env python3
"""Behavioral comparisons of SH using the existing platform SYSTEM service."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
a = p.parse_args()
b = a.gforth_build.resolve()
commands = {
    'sigma': [str(pathlib.Path('zig-out/bin/sigma').resolve()), '--max-steps', '100000', '-e'],
    'gforth': [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e'],
}
cases = [
    'S" SH true" EVALUATE $? .',
    'S" SH exit 3" EVALUATE $? .',
    '17 S" SH exit 7" EVALUATE . $? .',
    'S" SH" EVALUATE $? .',
    'S" SH printf A" EVALUATE $? .',
    'S" SH printf 日本語" EVALUATE $? .',
    ': RUN-SH SH ; S" RUN-SH exit 2" EVALUATE $? .',
    ': CAP-SH S" SH exit 0" EVALUATE ; \' CAP-SH >STRING-EXECUTE OVER >R TYPE R> FREE THROW $? .',
]
results = []
for source in cases:
    outputs = {}
    for runtime, command in commands.items():
        run = subprocess.run(command + [source + ' DEPTH . BYE'], input=b'', capture_output=True, timeout=15)
        assert run.returncode == 0, (runtime, source, run.stdout, run.stderr)
        outputs[runtime] = run.stdout.decode()
    assert outputs['sigma'] == outputs['gforth'], (source, outputs)
    results.append({'source': source, 'output': outputs['sigma']})
folder = pathlib.Path('.work/p06b-sh-check')
folder.mkdir(parents=True, exist_ok=True)
report = {'pass': True, 'comparisons': len(results), 'cases': results}
(folder / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'pass': True, 'comparisons': len(results)}))
