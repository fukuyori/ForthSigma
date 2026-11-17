"""Parse raw-QPC/xperf scheduler exports and summarize fixed control captures."""
import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path
import re
import statistics
import struct
import subprocess


def require(condition, message):
    if not condition:
        raise ValueError(message)


def trace_rows(raw_path, events_path, timespan_path, samples):
    text = timespan_path.read_text(errors='replace')
    for name in ('Buffers', 'Events'):
        found = re.findall(r'Total # Lost ' + name + r'\s*:\s*(\d+)', text)
        require(found == ['0'], 'Missing/nonzero trace loss counters: ' + name)
    tids = {s['observer']['primary_tid'] for s in samples}
    require(len(tids) == len(samples), 'Reused TID requires lifetime-specific parser; no ambiguous join')
    intervals, excluded, thread_events = (collections.defaultdict(list) for _ in range(3))
    last, offsets, count = {}, [], 0
    with raw_path.open() as raw_file, events_path.open(errors='replace') as events_file:
        raw = csv.reader(raw_file)
        frequency = int(next(raw)[1])
        require(int(next(raw)[1]) == 1 and frequency > 0, 'Trace clock must be QPC')
        next(raw)
        for row in csv.reader(events_file, skipinitialspace=True):
            if len(row) < 2:
                continue
            try:
                timestamp = int(row[1])
            except ValueError:
                continue
            name = row[0].strip()
            require(not name.startswith('InvalidEvent'), 'Invalid event row')
            if name in ('T-Start', 'T-End') and int(row[3]) in tids:
                pid = int(re.search(r'\(\s*(\d+)\)', row[2])[1])
                thread_events[int(row[3])].append((name, pid, timestamp))
            if name == 'DPC_ISR_CSWITCH_PCT' and int(row[7]) in tids:
                excluded[int(row[7])].append((timestamp, int(row[2]), int(row[8]), int(row[5])))
            if name != 'CSwitch':
                continue
            item = next(raw)
            tick, cpu = int(item[0]), int(item[1])
            payload = bytes.fromhex(item[5])
            require(len(payload) >= 8 and len(payload) == int(item[4]), 'Short/raw payload mismatch')
            new, old = struct.unpack_from('<II', payload)
            require((cpu, new, old) == (int(row[16]), int(row[3]), int(row[9])), 'Raw/xperf CSwitch mismatch')
            offsets.append(tick * 1e6 / frequency - timestamp)
            count += 1
            if cpu in last:
                before, previous = last[cpu]
                require(previous == old and tick >= before, 'CSwitch chain/time mismatch')
                if old in tids:
                    intervals[old].append((before, tick, cpu, timestamp, int(row[15])))
            else:
                require(old not in tids, 'Target slice has no preceding switch')
            last[cpu] = tick, new
        require(next(raw, None) is None, 'Raw events remaining')
    require(count > 0 and max(offsets) - min(offsets) <= 1.01, 'Raw/xperf timestamp scale mismatch')
    results = []
    for sample in samples:
        session = sample['observer']
        tid, pid = session['primary_tid'], session['pid']
        events = thread_events[tid]
        require(len(events) == 2 and [e[0] for e in events] == ['T-Start', 'T-End'] and all(e[1] == pid for e in events), 'PID/TID lifetime mismatch')
        slices, dpc = intervals[tid], excluded[tid]
        require(len(slices) == len(dpc) and len(slices) > 0, 'Missing DPC/scheduler slices')
        require(slices[0][3] - slices[0][4] >= events[0][2] - 1, 'Slice before thread start')
        cpu = sample['cpu']
        require(all(x[2] == cpu for x in slices), 'ETW target CPU drift')
        for a, b in zip(slices, dpc):
            require(a[3] == b[0] and a[2] == b[2] and abs(a[3] - a[4] - b[1]) <= 1, 'DPC slice correspondence mismatch')
        q0, q1 = session['queries'][:2]
        require(sample['frequency'] == frequency, 'Capture/ETL QPF mismatch')
        gross_values, net_values, partial_dpc = [], [], 0
        for begin in (q0['process']['before_qpc'], q0['process']['after_qpc']):
            for end in (q1['process']['before_qpc'], q1['process']['after_qpc']):
                gross = net = 0.0
                for (a, b, _, _, _), (_, _, _, excluded_us) in zip(slices, dpc):
                    overlap = max(0, min(b, end) - max(a, begin))
                    if not overlap:
                        continue
                    length = overlap * 1e6 / frequency
                    gross += length
                    if overlap != b - a and excluded_us:
                        # Aggregate DPC duration cannot locate a partial interruption.
                        partial_dpc += 1
                    net += length - excluded_us
                gross_values.append(gross)
                net_values.append(net)
        # One us per slice for the xperf aggregate's integer-us rounding.
        allowance = len(slices)
        net_range = None if partial_dpc else [min(net_values) - allowance, max(net_values) + allowance]
        result = {key: sample[key] for key in ('group', 'cpu', 'mode', 'kind', 'warmup', 'cycle', 'cpu_us')}
        result.update(pid=pid, tid=tid, scheduler_gross_range_us=[min(gross_values), max(gross_values)],
                      scheduler_net_range_us=net_range, partial_boundary_dpc_cases=partial_dpc,
                      residual_range_us=None if net_range is None else [sample['cpu_us'] - net_range[1], sample['cpu_us'] - net_range[0]])
        result['residual_percent_of_api'] = None if net_range is None else [x / sample['cpu_us'] * 100 for x in result['residual_range_us']]
        results.append(result)
    return {'cswitch_count': count, 'chain_mismatches': 0, 'frequency': frequency,
            'offset_range_us': [min(offsets), max(offsets)], 'rows': results,
            'net_boundary_unresolved': any(r['residual_range_us'] is None for r in results)}


def summary(samples):
    groups = collections.defaultdict(list)
    for s in samples:
        if not s['warmup']:
            groups[(s['group'], s['etw'], s['cpu'], s['mode'], s['kind'])].append(s)
    results = []
    for key, values in sorted(groups.items()):
        row = dict(zip(('group', 'etw', 'cpu', 'mode', 'kind'), key))
        row['count'] = len(values)
        for field in ('cpu_us', 'wall_us', 'observer_us'):
            data = [v[field] for v in values]
            median = statistics.median(data)
            row[field] = {'values': data, 'median': median, 'min': min(data), 'max': max(data),
                          'range_percent': (max(data) - min(data)) / median * 100 if median else None}
        results.append(row)
    return results


def contrasts(rows):
    output = []
    dimensions = ('group', 'etw', 'cpu', 'mode', 'kind')
    for dimension, low, high in [('cpu', 0, 2), ('mode', 'minimal', 'full'), ('etw', False, True)]:
        for a in rows:
            if a[dimension] != low:
                continue
            for b in rows:
                if b[dimension] != high or any(a[k] != b[k] for k in dimensions if k != dimension):
                    continue
                pair = {k: a[k] for k in dimensions if k != dimension}
                pair.update(dimension=dimension, before=low, after=high)
                for metric in ('cpu_us', 'wall_us', 'observer_us'):
                    left, right = a[metric], b[metric]
                    pair[metric] = {'median_difference': right['median'] - left['median'],
                                    'range_overlap': max(left['min'], right['min']) <= min(left['max'], right['max'])}
                output.append(pair)
    return output


def export_trace(etl, folder, decoder):
    folder.mkdir()
    commands = [([str(decoder), str(etl), str(folder / 'raw.csv')], 'decoder'),
                (['xperf', '-i', str(etl), '-o', str(folder / 'events.csv'), '-a', 'dumper', '-exc_dpcisr'], 'dumper'),
                (['xperf', '-i', str(etl), '-o', str(folder / 'timespan.txt'), '-a', 'tracestats', '-timespan', 'actual'], 'timespan')]
    for command, label in commands:
        p = subprocess.run(command, capture_output=True, timeout=300)
        (folder / (label + '.log')).write_bytes(p.stdout + p.stderr)
        require(p.returncode == 0, 'Export failed: ' + label)
        # Decoder warnings require explicit inspection before accepting a new capture.
        require(b'warning' not in (p.stdout + p.stderr).lower(), 'Export warning requires inspection: ' + label)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--decoder', type=Path)
    args = parser.parse_args()
    folder = args.capture.resolve()
    report = json.loads((folder / 'capture.json').read_text(encoding='utf-8'))
    require(report['status'] == 'complete', 'Incomplete capture')
    samples = report['samples']
    require(len(samples) == (8 if report['smoke'] else 128), 'Total sample count mismatch')
    if not report['smoke']:
        counted = collections.Counter((s['group'], s['etw'], s['cpu'], s['mode'], s['kind']) for s in samples if not s['warmup'])
        expected = {(g, e, c, m, k) for g in (1, 2) for e in (False, True) for c in (0, 2) for m in ('minimal', 'full') for k in ('sigma', 'native')}
        require(set(counted) == expected and set(counted.values()) == {3}, 'Missing/extra measured condition')
        require(len(report['blocks']) == 4 and sum(b['etw'] for b in report['blocks']) == 2, 'Block schedule mismatch')
    for s in samples:
        frequency = report['environment']['clock']['frequency']
        s['frequency'] = frequency
        q = s['observer']['queries']
        require(len(q) == 3 and s['checksum'] == 7 * s['n'], 'Protocol/checksum mismatch')
        s['observer_us'] = sum(x['end_qpc'] - x['start_qpc'] for x in q[:2]) * 1e6 / frequency
        a, b = s['observer']['after_identity_bracket']
        s['observer_us'] += (b - a) * 1e6 / frequency
        cpu = lambda x, field: sum(x[field]['value'].values())
        require((cpu(q[1], 'process') - cpu(q[0], 'process')) / 1000 == s['cpu_us'], 'API delta mismatch')
        s['process_minus_primary_us'] = ((cpu(q[1], 'process') - cpu(q[0], 'process')) - (cpu(q[1], 'primary_thread') - cpu(q[0], 'primary_thread'))) / 1000
    traces = []
    for block in report['blocks']:
        if not block['etw']:
            continue
        require(block['stop_exit'] == 0 and block['cleanup_confirmed'], 'Unconfirmed stop')
        etl = folder / block['etl']
        require(hashlib.sha256(etl.read_bytes()).hexdigest() == block['etl_sha256'], 'ETL changed')
        exported = folder / ('g' + str(block['group']) + '-analysis')
        require(args.decoder is not None, 'Provide compiled --decoder')
        export_trace(etl, exported, args.decoder.resolve())
        selected = [s for s in samples if s['group'] == block['group'] and s['etw']]
        traces.append(trace_rows(exported / 'raw.csv', exported / 'events.csv', exported / 'timespan.txt', selected))
    summarized = summary(samples)
    result = {'smoke': report['smoke'], 'summary': summarized, 'contrasts': contrasts(summarized), 'traces': traces,
              'process_minus_primary_us': [s['process_minus_primary_us'] for s in samples],
              'limits': report['limitations'], 'diagnostic_success': not report['smoke'] and not any(t['net_boundary_unresolved'] for t in traces)}
    output = folder / 'analysis.json'
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(output)


if __name__ == '__main__':
    main()
