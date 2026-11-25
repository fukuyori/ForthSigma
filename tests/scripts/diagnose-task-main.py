"""Diagnostic only: preserve workloads and D07 endpoints; never acceptance verdicts."""
import argparse
import hashlib
import json
from pathlib import Path
import runpy
import time

ROOT = Path(__file__).resolve().parents[2]


def analyze(directory):
    result = []
    for log in sorted(directory.glob('*.raw.log')):
        lines = log.read_text(errors='replace').splitlines()
        events = [json.loads(s[11:]) for s in lines if s.startswith('ACCEPTANCE ')]
        spans = [json.loads(s[10:]) for s in lines if s.startswith('MAIN-SPAN ')]
        complete = any('lost' in s for s in spans)
        lost = sum(s.get('lost', 0) for s in spans)
        spans = [s for s in spans if 'start' in s]
        tasks = [e for e in events if e.get('published', 0) > 0]
        slow = [s for s in spans if s['end']-s['start'] > 100_000_000]
        maxima = {}
        covered_until = 0
        gaps = []
        for span in sorted(spans, key=lambda s: s['start']):
            maxima[span['name']] = max(maxima.get(span['name'], 0), span['end']-span['start'])
            if covered_until and span['start']-covered_until > 100_000_000:
                gaps.append(dict(start=covered_until, end=span['start']))
            covered_until = max(covered_until, span['end'])
        outliers = []
        for e in tasks:
            if e['reclaimed']-e['published'] <= 100_000_000:
                continue
            outliers.append(dict(task=e, spans=[s for s in spans if s['end'] >= e['published']-20_000_000 and s['start'] <= e['reclaimed']]))
        result.append(dict(raw=log.name, complete=complete, tasks=len(tasks), lost_spans=lost,
                           long_spans=slow, max_span_ns=maxima, uncovered_gaps=gaps, outliers=outliers))
    return dict(diagnostic_only=True, runs=result)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--sigma', type=Path)
    p.add_argument('--out', required=True, type=Path)
    p.add_argument('--seconds', type=int, default=600)
    p.add_argument('--chunk', type=int, default=120)
    p.add_argument('--only', nargs='+', default=['I1', 'G1-open'], choices=['I1', 'G1-open'])
    p.add_argument('--output', choices=['direct', 'buffered'], default='buffered')
    p.add_argument('--analyze', action='store_true')
    a = p.parse_args()
    if not a.analyze:
        if not a.sigma or a.out.exists() or min(a.seconds, a.chunk) <= 0:
            p.error('supply binary, positive durations and new output directory')
        a.out.mkdir(parents=True)
        fixtures = runpy.run_path(str(ROOT/'tests/scripts/acceptance-fixtures.py'))['generate'](ROOT, a.out/'fixtures', turns=1000000)
        driver = runpy.run_path(str(ROOT/'tests/scripts/acceptance-probes.py'))['run']
        (a.out/'manifest.json').write_text(json.dumps(dict(diagnostic_only=True, binary_sha256=hashlib.sha256(a.sigma.read_bytes()).hexdigest(), seconds=a.seconds, chunk=a.chunk, cases=a.only, output=a.output, fixtures={k: hashlib.sha256(v.read_bytes()).hexdigest() for k,v in fixtures.items()}), indent=2))
        for case in a.only:
            remaining = a.seconds
            index = 0
            while remaining:
                duration = min(remaining, a.chunk)
                parent_cpu = time.process_time_ns()
                parent_wall = time.perf_counter_ns()
                result = driver(a.sigma.resolve(), fixtures[case].resolve(), a.out/f'{case}-{index:03}', False, seconds=duration, buffer_output=a.output == 'buffered')
                result['diagnostic_parent_cpu_ns'] = time.process_time_ns()-parent_cpu
                result['diagnostic_parent_wall_ns'] = time.perf_counter_ns()-parent_wall
                (a.out/f'{case}-{index:03}.json').write_text(json.dumps(result, indent=2)+'\n')
                if result['exit_code'] or result['timed_out'] or result['os_sample_errors']:
                    raise RuntimeError(result)
                print(case, index, 'completed', flush=True)
                remaining -= duration
                index += 1
    report = analyze(a.out)
    if not a.analyze and any(not r['complete'] or r['lost_spans'] for r in report['runs']):
        raise RuntimeError('incomplete main span capture; retain raw logs')
    (a.out/'summary.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps([dict(raw=r['raw'], complete=r['complete'], tasks=r['tasks'], lost=r['lost_spans'], long_spans=len(r['long_spans']), outliers=len(r['outliers'])) for r in report['runs']], indent=2))


if __name__ == '__main__':
    main()
