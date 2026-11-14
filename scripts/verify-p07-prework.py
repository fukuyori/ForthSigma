#!/usr/bin/env python3
"""Compare assignment semantics, allowing only approved existing Sigma differences."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--sigma', type=pathlib.Path, default=pathlib.Path('zig-out/bin/sigma'))
p.add_argument('--reference', type=pathlib.Path, default=pathlib.Path('.work/p07-prework-check/spec-probes.json'))
a = p.parse_args()
rows = json.loads(a.reference.read_text())['cases']
results = []
for row in rows:
    name = row['case']
    reference = row['runs']['gforth']
    expected = reference['stdout']
    expected_exit = reference['exit']
    policy = False
    if name.endswith((':invalid-target', ':missing-name')):
        expected, expected_exit, policy = '-259 0 ', 0, True
    elif name == 'ACTION-OF:value':
        expected, expected_exit, policy = 'DEFINITION ERROR !\n', 1, True
    elif name in ('IS:double', 'IS:float', 'IS:string'):
        expected = {'IS:double': '3 4 0 ', 'IS:float': '3. 4. 0 ', 'IS:string': 'b0 '}[name]
        expected_exit, policy = 0, True
    r = subprocess.run([str(a.sigma.resolve()), '--max-steps', '100000', '-e', row['source']+' DEPTH . BYE'], input=b'', capture_output=True, timeout=10)
    output = r.stdout.decode(errors='replace')
    # Existing Sigma diagnostic for dictionary redefinition (Gforth writes its warning to stderr).
    if name.endswith(':shadow') or name == 'search-order-shadow':
        assert output.startswith('WARNING: SAME NAME WORD EXISTS\n'), (name,output)
        output = output.removeprefix('WARNING: SAME NAME WORD EXISTS\n')
    assert r.returncode == expected_exit and output == expected, (name, r.returncode, output, expected_exit, expected, r.stderr)
    results.append({'case': name, 'approved_difference': policy})
report = {'pass': True, 'comparisons': sum(not r['approved_difference'] for r in results), 'approved_difference_checks': sum(r['approved_difference'] for r in results), 'cases': results}
a.reference.with_name('comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='cases'}))
# Native SAVE/LOAD and SAVESYS execute the same token-bearing definitions.
folder = a.reference.parent
image = folder.resolve() / 'assignments.sigma'
executable = folder.resolve() / 'assignments-program'
source = '1 VALUE V \' TO CONSTANT SET : M POSTPONE TO ; IMMEDIATE : T 8 M V ; : RUN S" 3 SET EXECUTE V" EVALUATE T V . ; '
r = subprocess.run([str(a.sigma.resolve()), '-e', source + f'SAVE {image} SAVESYS {executable} BYE'], input=b'', capture_output=True, timeout=20)
assert r.returncode == 0, (r.stdout, r.stderr)
for command in ([str(a.sigma.resolve()), '-e', f': BEFORE 99 ; LOAD-DICTIONARY {image} RUN DEPTH . BYE'], [str(executable), '-e', 'RUN DEPTH . BYE']):
    r = subprocess.run(command, input=b'', capture_output=True, timeout=20)
    assert r.returncode == 0 and r.stdout == b'8 0 ', (command, r.returncode, r.stdout, r.stderr)
report['native_image_checks'] = 2
a.reference.with_name('comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'native_image_checks': 2, 'pass': True}))
