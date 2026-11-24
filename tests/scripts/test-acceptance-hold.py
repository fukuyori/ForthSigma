#!/usr/bin/env python3
"""Untimed acceptance hold regression: no host request, BYE and expired holds.

Run against a -Dtask-acceptance=true binary. Wall time is a hang guard only.
"""
import argparse
import json
import os
from pathlib import Path
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sigma', type=Path, default=ROOT / ('zig-out/bin/sigma.exe' if os.name == 'nt' else 'zig-out/bin/sigma'))
    args = parser.parse_args()
    work = ROOT / '.work/phase-hold/guards'
    fixtures = runpy.run_path(str(ROOT / 'tests/scripts/acceptance-fixtures.py'))['generate'](ROOT, work)
    original = fixtures['cancel'].read_text()
    prefix = original.rsplit('BEGIN AP DUP 3 < WHILE', 1)[0]
    results = []
    for case, ending in [
        ('bye', '100 MS ; RUN BYE\n'),
        ('timeout', '5500 MS AJ @ TASK-CANCEL THROW AW AJ @ TASK-RELEASE THROW ; RUN AF\n'),
        ('deferred-output', 'BEGIN AP DUP 3 < WHILE DROP REPEAT DROP '
         '." CANCELLED-PENDING" CR 100 MS AP DROP ." RELEASING" CR 1 MS '
         'AJ @ TASK-RELEASE THROW ; RUN AF\n'),
    ]:
        source = work / (case + '.fs')
        source.write_text(prefix + ending)
        env = dict(os.environ, SIGMA_ACCEPTANCE_SMOKE='1', SIGMA_ACCEPTANCE_CANCEL_AT='vm_start')
        for key in ['SIGMA_ACCEPTANCE_NATIVE', 'SIGMA_ACCEPTANCE_MEMORY_HOLD']:
            env.pop(key, None)
        child = subprocess.run([str(args.sigma.resolve()), str(source)], env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
        (work / (case + '.raw.log')).write_bytes(child.stdout)
        rows = [json.loads(line.split('ACCEPTANCE ', 1)[1]) for line in child.stdout.decode(errors='replace').splitlines()
                if line.startswith('ACCEPTANCE ')]
        tasks = [r for r in rows if 'task' in r]
        assert child.returncode == 0, (case, child.returncode, child.stdout)
        assert len(tasks) == 1 and tasks[0]['hold_stage'] == 5, (case, tasks)
        assert tasks[0]['hold_timeout'] == (case == 'timeout'), (case, tasks)
        if case == 'bye':
            assert tasks[0]['request_stage'] == 0, tasks  # no TASK-CANCEL API call
        if case == 'deferred-output':
            pending = child.stdout.split(b'CANCELLED-PENDING', 1)[1].split(b'RELEASING', 1)[0]
            assert b'ACCEPTANCE ' not in pending, pending
            assert not any('lost_events' in r for r in rows), rows
        results.append(dict(case=case, task=tasks[0], exit_code=child.returncode))
    (work / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print('hold guards: BYE, 5s timeout and output deferred until reclaim passed (no timing samples)')

if __name__ == '__main__':
    main()
