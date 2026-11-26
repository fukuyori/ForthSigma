#!/usr/bin/env python3
"""Summarize Linux PAINTTRACE intervals (ns timestamps, ms output).

For repeated redraws, use the last draw-begin before complete and only endpoints
from that attempt. Missing endpoints are counted, never inferred across attempts.
Smoke records are excluded. Input files must each describe one process/run.
"""
import argparse
import bisect
import json
import math
from pathlib import Path
import statistics

ENDPOINTS = ('request', 'take', 'draw-begin', 'draw-end', 'roundtrip', 'complete')


def summarize(path):
    frames = {}
    lost = smoke = 0
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        if 'PAINTTRACE ' not in line:
            continue
        row = json.loads(line.split('PAINTTRACE ', 1)[1])
        lost += row.get('lost_events', 0)
        kind = row.get('event')
        if kind not in ENDPOINTS:
            continue
        if row.get('smoke') is True:
            smoke += 1
            continue
        if row.get('smoke') is not False or any(type(row.get(k)) is not int or row[k] <= 0 for k in ('frame', 'at')):
            raise ValueError('expected positive frame/timestamp and smoke=false')
        frames.setdefault(row['frame'], {}).setdefault(kind, []).append(row['at'])
    values = [[] for _ in range(5)]
    for events in frames.values():
        for times in events.values():
            times.sort()
        # request/take/complete are unique per serial. Redraw endpoints may repeat.
        for kind in ('request', 'take', 'complete'):
            if len(events.get(kind, [])) > 1:
                raise ValueError('duplicate ' + kind + '; supply one process/run per file')
        points = {kind: events[kind][0] for kind in ('request', 'take', 'complete') if kind in events}
        complete = points.get('complete')
        if complete is not None:
            begins = events.get('draw-begin', [])
            index = bisect.bisect_right(begins, complete)
            if index:
                begin = points['draw-begin'] = begins[index - 1]
                for kind in ('draw-end', 'roundtrip'):
                    candidates = [at for at in events.get(kind, []) if begin <= at <= complete]
                    if len(candidates) == 1:
                        points[kind] = candidates[0]
        for index, (start, end) in enumerate(zip(ENDPOINTS, ENDPOINTS[1:])):
            if start in points and end in points:
                elapsed = points[end] - points[start]
                if elapsed < 0:
                    raise ValueError('backwards endpoints: ' + start + ' -> ' + end)
                values[index].append(elapsed / 1_000_000)
    print(f'{path}: frames={len(frames)} lost_events={lost} smoke_records_ignored={smoke}')
    print('interval                         n  missing   median_ms      p95_ms      max_ms')
    for start, end, samples in zip(ENDPOINTS, ENDPOINTS[1:], values):
        samples.sort()
        label = start + ' -> ' + end
        prefix = f'{label:31} {len(samples):3} {len(frames) - len(samples):8}'
        if samples:
            print(prefix + f' {statistics.median(samples):11.6f} {samples[math.ceil(.95 * len(samples)) - 1]:11.6f} {samples[-1]:11.6f}')
        else:
            print(prefix + '         n/a         n/a         n/a')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('logs', type=Path, nargs='+', help='one process/run per file; p95 uses nearest rank')
    args = parser.parse_args()
    try:
        for path in args.logs:
            summarize(path)
    except (OSError, ValueError) as exc:
        parser.exit(1, f'{exc}\n')


if __name__ == '__main__':
    main()
