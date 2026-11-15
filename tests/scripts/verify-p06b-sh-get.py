#!/usr/bin/env python3
"""Compare complete borrowed shell output and status; check Sigma alias safety separately."""
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
show = ': SHOW-RESULT DUP . BOUNDS ?DO I C@ . LOOP ; '
cases = []
for command in ['printf ABC', 'true', 'printf 日本語', r"printf 'A\000B\n'", r"printf 'x\n\n'", 'printf ABC; exit 3']:
    cases.append(f'S" {command}" SH-GET SHOW-RESULT $? .')
cases.append('S" printf A" SH-GET SHOW-RESULT S" printf BC" SH-GET SHOW-RESULT $? .')
cases.append(': CAP-SHELL S" printf ABC" SH-GET TYPE ; \' CAP-SHELL >STRING-EXECUTE OVER >R TYPE R> FREE THROW $? .')
results = []
for source in cases:
    outputs = {}
    for runtime, cmd in commands.items():
        run = subprocess.run(cmd + [show + source + ' DEPTH . BYE'], input=b'', capture_output=True, timeout=15)
        assert run.returncode == 0, (runtime, source, run.stdout, run.stderr)
        outputs[runtime] = run.stdout.decode()
    assert outputs['sigma'] == outputs['gforth'], (source, outputs)
    results.append({'source': source, 'output': outputs['sigma']})
source = 'S" printf \'printf ABC\'" SH-GET SH-GET TYPE $? . DEPTH . BYE'
run = subprocess.run(commands['sigma'] + [source], input=b'', capture_output=True, timeout=15)
assert run.returncode == 0 and run.stdout == b'ABC0 0 ', (run.returncode, run.stdout, run.stderr)
folder = pathlib.Path('.work/p06b-sh-get-check')
folder.mkdir(parents=True, exist_ok=True)
report = {'pass': True, 'gforth_comparisons': len(results), 'sigma_alias_check': run.stdout.decode(), 'cases': results}
(folder / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'pass': True, 'gforth_comparisons': len(results), 'sigma_alias_checks': 1}))
