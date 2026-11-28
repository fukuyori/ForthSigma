#!/usr/bin/env python3
"""Short, diagnostic-only worker stage capture; never acceptance samples.
Use a ReleaseFast/debug=false/task-trace=true/task-acceptance=false binary.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import runpy
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sigma', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--only', nargs='+', choices=['G1', 'T1'], default=['G1', 'T1'])
    parser.add_argument('--widths', nargs='+', type=int, choices=[64, 128, 256], default=[64, 128, 256])
    parser.add_argument('--parent-fill', action='store_true', help='diagnostic G1 candidate for the worker at b7073ab and earlier only; does not modify example')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    generate = runpy.run_path('tests/scripts/acceptance-fixtures.py')['generate']
    records = runpy.run_path('tests/scripts/trace-task-path.py')['records']
    paths = generate(Path('.'), args.out / 'fixtures')
    if args.parent_fill:
        worker = Path('tests/task/task-path-worker.fs').read_text()
        before = '  0 BEGIN DUP TP-N @ < WHILE\n    -1 OVER CELLS TP-PARENT + ! 1+\n  REPEAT DROP'
        after = '  0 BEGIN DUP TP-N @ CELLS < WHILE\n    TP-PARENT OVER + TP-N @ CELLS 2 PICK - 65536 MIN\n    DUP >R 255 FILL R> +\n  REPEAT DROP'
        if before not in worker:
            parser.error('--parent-fill applies only to the G1 worker at b7073ab and earlier (TP-PARENT initialisation loop); the current worker has no parent array')
        candidate = args.out / 'parent-fill-worker.fs'
        candidate.write_text(worker.replace(before, after))
    rows = []
    cases = []
    if 'G1' in args.only:
        for width in args.widths:
            for shape in ['open', 'wall', 'snake']:
                source = paths['G1-'+shape].read_text()
                if args.parent_fill:
                    source = source.replace('tests/task/task-path-worker.fs', candidate.as_posix())
                if width != 256:
                    replacements = {65568: width*width+32, 65280: width*(width-1),
                                    65535: width*width-1, 32896: width*width//2+width//2,
                                    511: 2*width-1, 256: width, 128: width//2, 255: width-1}
                    source = re.sub(r"\b(?:65568|65280|65535|32896|511|256|128|255)\b",
                                    lambda m: str(replacements[int(m[0])]), source)
                fixture = args.out / f'G1-{width}-{shape}.fs'
                fixture.write_text(source)
                cases.append((f'G1-{width}-{shape}', fixture))
    if 'T1' in args.only:
        cases.append(('T1', paths['T1']))
    env = dict(os.environ)
    for name in list(env):
        if name.startswith('SIGMA_ACCEPTANCE_') or name == 'SIGMA_TASK_TRACE_CANCEL_AT':
            env.pop(name)
    for name, fixture in cases:
        result = subprocess.run([str(args.sigma.resolve()), str(fixture)], capture_output=True, env=env, timeout=30)
        raw = result.stdout+result.stderr
        (args.out / (name+'.raw.log')).write_bytes(raw)
        assert result.returncode == 0, raw.decode(errors='replace')
        observed = [r for r in records(raw.decode(errors='replace')) if r['event']=='observed' and r['forth_return']]
        assert len(observed)==1, observed
        row = observed[0]
        pairs = list(zip(['vm_start']+runpy.run_path('tests/scripts/trace-task-path.py')['SETUP_STAGES'], runpy.run_path('tests/scripts/trace-task-path.py')['SETUP_STAGES']))
        pairs += [('acquired','vm_start'), ('vm_start','initialized'), ('initialized','restored'),
                  ('restored','permissions_checked'), ('permissions_checked','input_ready'),
                  ('input_ready','executing'), ('executing','forth_return'),
                  ('forth_return','runner_return'), ('runner_return','published')]
        rows.append(dict(case=name, times=row, ms={a+'->'+b: (row[b]-row[a])/1e6 for a,b in pairs if row.get(a) and row.get(b)}))
    summary = dict(purpose='diagnostic only; one execution per case, no acceptance verdict', parent_fill=args.parent_fill, binary_sha256=hashlib.sha256(args.sigma.read_bytes()).hexdigest(), rows=rows,
                   limitations='submit/copy/enqueue times absent; result copy includes execution-reference cleanup; Linux OS allocation/page-fault/scheduler costs not individually separated')
    (args.out/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(f'{len(rows)} diagnostic cases recorded in {args.out}')


if __name__ == '__main__':
    main()

