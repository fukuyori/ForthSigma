"""Short investigation only; never an acceptance verdict or a smoke run.

Build with task-acceptance=true/task-reclaim-diagnostics=true first.
Each process retains the public fixture and real endpoint definitions.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def rows(path):
    return [json.loads(s[len('ACCEPTANCE '):]) for s in path.read_text(errors='replace').splitlines()
            if s.startswith('ACCEPTANCE ')]


def analyze(directory):
    stats = runpy.run_path(str(ROOT / 'tests/scripts/run-acceptance.py'))['stats']
    metrics, outliers, tasks = {}, [], 0
    for path in sorted(directory.glob('*.raw.log')):
        events = rows(path)
        turns = [e for e in events if e.get('metric') == 'management_turn_ns']
        for e in events:
            if 'metric' in e and e.get('start', 0) > 0:
                metrics.setdefault(e['metric'], []).append(e['end'] - e['start'])
            if e.get('requested', 0) <= 0:
                continue
            tasks += 1
            for end in ('stopped', 'published', 'reclaimed'):
                metrics.setdefault('request_' + end + '_ns', []).append(e[end] - e['requested'])
            if e['reclaimed'] - e['requested'] > 100_000_000:
                # Include the preceding turn to show the gap straddling publication.
                selected = [t for t in turns if t['end'] >= e['published'] and t['start'] <= e['reclaimed']]
                preceding = [t for t in turns if t['end'] < e['published']]
                outliers.append(dict(raw=path.name, task=e,
                    turns=preceding[-1:] + selected,
                    intervals=[t for t in events if t.get('start', 0) > 0 and
                               t['end'] >= e['published'] and t['start'] <= e['reclaimed']]))
    return dict(diagnostic_only=True, requested_tasks=tasks,
                statistics={k: stats(v) for k, v in metrics.items()}, outliers=outliers)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--sigma', type=Path)
    p.add_argument('--out', required=True, type=Path)
    p.add_argument('--analyze', type=Path)
    p.add_argument('--repetitions', type=int, default=300)
    p.add_argument('--sampler', choices=['on', 'off'], default='on')
    p.add_argument('--stages', nargs='+', default=['catches_allocated', 'frames_allocated',
                   'loops_allocated', 'return_allocated', 'state_reserved', 'native_running'])
    a = p.parse_args()
    if a.analyze:
        report = analyze(a.analyze)
        a.out.parent.mkdir(parents=True, exist_ok=True)
        a.out.write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({k: v for k, v in report.items() if k != 'outliers'}, indent=2))
        return
    if not a.sigma or a.repetitions < 1 or a.out.exists():
        p.error('supply --sigma, positive repetitions and a new --out directory')
    a.out.mkdir(parents=True)
    fixtures = runpy.run_path(str(ROOT / 'tests/scripts/acceptance-fixtures.py'))['generate'](ROOT, a.out / 'fixtures')
    driver = runpy.run_path(str(ROOT / 'tests/scripts/acceptance-probes.py'))['run']
    sigma = a.sigma.resolve()
    manifest = dict(diagnostic_only=True, sampler=a.sampler, repetitions=a.repetitions,
                    stages=a.stages, binary_sha256=hashlib.sha256(sigma.read_bytes()).hexdigest(),
                    fixtures={k: hashlib.sha256(v.read_bytes()).hexdigest() for k, v in fixtures.items()})
    (a.out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    stage_names = (ROOT / 'src/core/task_trace.zig').read_text().split('pub const Stage = enum {')[1].split('};')[0]
    stage_names = [s.strip() for s in stage_names.split(',') if s.strip()]
    for stage in a.stages:
        if stage not in stage_names:
            p.error('unknown stage: ' + stage)
        native = 'search' if stage.startswith('native_') else None
        source = fixtures['native-search' if native else 'cancel']
        for i in range(a.repetitions):
            dest = a.out / f'{stage}-{i:04d}'
            if a.sampler == 'on':
                result = driver(sigma, source, dest, False, stage, native)
                events = result['events']
            else:
                env = dict(os.environ, SIGMA_ACCEPTANCE_SMOKE='0', SIGMA_ACCEPTANCE_CANCEL_AT=stage)
                if native:
                    env['SIGMA_ACCEPTANCE_NATIVE'] = native
                else:
                    env.pop('SIGMA_ACCEPTANCE_NATIVE', None)
                env.pop('SIGMA_ACCEPTANCE_MEMORY_HOLD', None)
                with dest.with_suffix('.raw.log').open('wb') as log:
                    subprocess.run([str(sigma), str(source.resolve())], cwd=ROOT, env=env,
                                   stdout=log, stderr=subprocess.STDOUT, timeout=15, check=True)
                events = rows(dest.with_suffix('.raw.log'))
            task = [e for e in events if e.get('requested', 0) > 0]
            if any(e.get('lost_events', 0) for e in events):
                raise RuntimeError(f'event overflow: {dest}')
            if len(task) != 1 or task[0]['hold_timeout'] or task[0]['hold_stage'] != stage_names.index(stage) or task[0]['request_stage'] != stage_names.index(stage):
                raise RuntimeError(f'phase failure: {dest}')
            t = task[0]
            if not 0 < t['requested'] <= t['stopped'] <= t['published'] <= t['reclaimed']:
                raise RuntimeError(f'invalid endpoints: {dest}')
        print(stage, 'completed', flush=True)
    (a.out / 'summary.json').write_text(json.dumps(analyze(a.out), indent=2) + '\n')


if __name__ == '__main__':
    main()
