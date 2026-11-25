#!/usr/bin/env python3
"""Short paired G1-open diagnosis. Use acceptance+trace binaries, never for D07 verdicts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import statistics
import subprocess
import threading
import time


HERE = Path(__file__).resolve().parent


def capture(exe, fixture, log):
    memory = runpy.run_path(str(HERE / 'acceptance-probes.py'))['memory']
    records = runpy.run_path(str(HERE / 'trace-task-path.py'))['records']
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('SIGMA_ACCEPTANCE_') and k != 'SIGMA_TASK_TRACE_CANCEL_AT'}
    env['SIGMA_ACCEPTANCE_SMOKE'] = '0'
    done = threading.Event()
    errors = []

    def sample(pid):
        while not done.is_set():
            try:
                memory(pid)
            except (OSError, ValueError) as exc:
                if child.poll() is None:
                    errors.append(str(exc))
            done.wait(.01)

    with log.open('wb') as stream:
        wall = time.perf_counter()
        cpu = time.process_time()
        with subprocess.Popen([str(exe), str(fixture)], stdin=subprocess.PIPE, stdout=stream,
                              stderr=subprocess.STDOUT, env=env) as child:
            sampler = threading.Thread(target=sample, args=(child.pid,))
            sampler.start()
            try:
                if child.wait(timeout=30):
                    raise RuntimeError(f'child failed: {log}')
            finally:
                if child.poll() is None:
                    child.kill()
                done.set()
                sampler.join()
        cpu = time.process_time() - cpu
        wall = time.perf_counter() - wall
    raw = log.read_bytes()
    lines = [line for line in raw.splitlines(keepends=True) if line.startswith(b'ACCEPTANCE ')]
    rows = [json.loads(line[11:]) for line in lines]
    tasks = [row for row in rows if 'task' in row]
    traces = [row for row in records(raw.decode(errors='replace')) if row['event'] == 'observed']
    if errors or len(tasks) != 10 or len(traces) != 10:
        raise ValueError(f'incomplete diagnostic run: {log}, {len(tasks)} tasks, {len(traces)} traces, {errors[:1]}')
    intervals = []
    for task, trace in zip(tasks, traces):
        points = [task['submitted'], trace['acquired'], trace['executing'], trace['forth_return'],
                  task['published']]
        if points != sorted(points) or not points[0]:
            raise ValueError(f'invalid or unmatched trace: {log}')
        intervals.append([(end-start)/1e6 for start, end in zip(points, points[1:])])
    return dict(fixture=fixture.name, binary_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(),
                acceptance_lines_per_s=len(lines)/wall, acceptance_bytes_per_s=sum(map(len, lines))/wall,
                parent_cpu_pct=100*cpu/wall, tasks=len(tasks),
                median_ms=dict(zip(['submit_acquire', 'acquire_execute', 'execute_return', 'return_publish'],
                                   map(statistics.median, zip(*intervals)))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sigma', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    fixtures = runpy.run_path(str(HERE / 'acceptance-fixtures.py'))['generate'](
        HERE.parents[1], args.out / 'fixtures', turns=10)
    current = fixtures['G1-open'].read_text()
    if current.count('100 APACE LOOP') != 1:
        raise ValueError('unexpected pacing fixture')
    results = []
    for index, word in enumerate(['MS', 'APACE', 'APACE', 'MS']):
        path = args.out / f'{index}-{word}.fs'
        path.write_text(current.replace('100 APACE LOOP', f'100 {word} LOOP'))
        result = capture(args.sigma.resolve(strict=True), path, path.with_suffix('.raw.log'))
        results.append(result)
        print(json.dumps(result), flush=True)
    (args.out / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    main()
