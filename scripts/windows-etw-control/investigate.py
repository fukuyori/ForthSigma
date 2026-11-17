"""Task874: inspect existing scheduler exports; never capture or change OS settings."""
import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path
import statistics
import struct


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def correlation(xs, ys):
    xmean, ymean = statistics.mean(xs), statistics.mean(ys)
    xv, yv = [x - xmean for x in xs], [y - ymean for y in ys]
    denominator = (sum(x*x for x in xv) * sum(y*y for y in yv)) ** 0.5
    return sum(x*y for x, y in zip(xv, yv)) / denominator if denominator else None


def extract(folder, group, samples, previous):
    tids = {s['observer']['primary_tid'] for s in samples}
    require(len(tids) == len(samples), 'Ambiguous reused TID')
    slices, dpc = collections.defaultdict(list), collections.defaultdict(list)
    raw_path, events_path = folder / 'raw.csv', folder / 'events.csv'
    count, last = 0, {}
    with raw_path.open() as raw_stream, events_path.open(errors='replace') as events_stream:
        raw = csv.reader(raw_stream)
        frequency = int(next(raw)[1])
        require(int(next(raw)[1]) == 1, 'Non-QPC trace')
        next(raw)
        for row in csv.reader(events_stream, skipinitialspace=True):
            if len(row) < 2:
                continue
            try:
                timestamp = int(row[1])
            except ValueError:
                continue
            if row[0] == 'DPC_ISR_CSWITCH_PCT' and int(row[7]) in tids:
                dpc[int(row[7])].append((timestamp, int(row[8]), int(row[5])))
            if row[0] != 'CSwitch':
                continue
            record = next(raw)
            tick, cpu = int(record[0]), int(record[1])
            new, old = struct.unpack_from('<II', bytes.fromhex(record[5]))
            require((cpu, new, old) == (int(row[16]), int(row[3]), int(row[9])), 'Raw/xperf mismatch')
            if cpu in last:
                before, prior, new_priority = last[cpu]
                require(prior == old, 'Broken scheduler chain')
                if old in tids:
                    slices[old].append((before, tick, cpu, timestamp, new_priority, int(row[10])))
            else:
                require(old not in tids, 'Missing preceding target switch')
            last[cpu] = tick, new, int(row[4])
            count += 1
        require(next(raw, None) is None, 'Extra raw records')
    require(count == previous['cswitch_count'], 'Changed CSwitch count')
    old_rows = {r['tid']: r for r in previous['rows']}
    results = []
    for sample in samples:
        tid = sample['observer']['primary_tid']
        q0, q1 = sample['observer']['queries'][:2]
        begin, end = q0['process']['after_qpc'], q1['process']['after_qpc']
        require(end > begin, 'Invalid API interval')
        runs, interruptions = slices[tid], dpc[tid]
        require(len(runs) == len(interruptions), 'DPC correspondence count')
        gross = excluded = 0.0
        priorities_in, priorities_out = collections.Counter(), collections.Counter()
        switches, prior_change = 0, 0
        for (a, b, cpu, stamp, inp, outp), (ds, dcpu, interrupt) in zip(runs, interruptions):
            require((stamp, cpu) == (ds, dcpu), 'DPC correspondence key')
            overlap = max(0, min(b, end) - max(a, begin))
            if not overlap:
                continue
            require(cpu == sample['cpu'], 'CPU drift')
            require(overlap == b-a or interrupt == 0, 'Partial DPC boundary needs raw interruption events')
            duration = overlap * 1e6 / frequency
            gross += duration
            excluded += interrupt
            priorities_in[inp] += duration
            priorities_out[outp] += duration
            switches += 1
            prior_change += inp != outp
        net = gross - excluded
        residual = sample['cpu_us'] - net
        prior = old_rows[tid]
        require(prior['scheduler_gross_range_us'][0] - 0.01 <= gross <= prior['scheduler_gross_range_us'][1] + 0.01, 'Gross interval disagreement')
        require(prior['residual_range_us'][0] <= residual <= prior['residual_range_us'][1], 'Residual interval disagreement')
        result = {k: sample[k] for k in ('group', 'cpu', 'mode', 'kind', 'cycle', 'warmup', 'cpu_us', 'wall_us')}
        result.update(tid=tid, capture_index=sample['capture_index'], begin_qpc=begin, end_qpc=end,
                      gross_us=gross, dpc_isr_us=excluded, net_us=net, residual_us=residual,
                      interval_qpc_us=(end-begin)*1e6/frequency,
                      off_cpu_us=(end-begin)*1e6/frequency-gross,
                      slices=switches, priority_changed_within_slice_count=prior_change,
                      switch_in_priority_weight_us=dict(priorities_in), switch_out_priority_weight_us=dict(priorities_out),
                      boundary_priority_before=sample['observer']['before']['thread_priority'],
                      boundary_priority_after=sample['observer']['after']['thread_priority'])
        results.append(result)
    return results


def analyze(folder, metadata):
    capture = json.loads((folder / 'capture.json').read_text(encoding='utf-8'))
    require(capture['status'] == 'complete', 'Incomplete capture')
    require(digest(folder / 'capture.json') == metadata['analysis']['capture_sha256'], 'Capture changed')
    rows = []
    for group in (1, 2):
        exports = folder / f'g{group}-analysis'
        for name in ('raw.csv', 'events.csv', 'parsed.json'):
            require(digest(exports / name) == metadata['local_export_files'][f'g{group}-analysis/{name}']['sha256'], 'Export changed: ' + name)
        samples = [dict(s, capture_index=i+1) for i, s in enumerate(capture['samples']) if s['group'] == group and s['etw']]
        require(len(samples) == 32, 'Missing ETW samples')
        previous = json.loads((exports / 'parsed.json').read_text())
        rows.extend(extract(exports, group, samples, previous))
        print('group', group, 'scheduler/DPC/priority extraction complete', flush=True)
    measured = [r for r in rows if not r['warmup']]
    grouped = collections.defaultdict(list)
    for row in measured:
        grouped[(row['group'], row['cpu'], row['mode'], row['kind'])].append(row)
    summary = []
    fields = ('cpu_us', 'gross_us', 'dpc_isr_us', 'net_us', 'residual_us', 'off_cpu_us')
    for key, values in sorted(grouped.items()):
        require(len(values) == 3, 'Missing measured samples')
        item = dict(zip(('group', 'cpu', 'mode', 'kind'), key))
        item['metrics'] = {name: {'mean': statistics.mean(v[name] for v in values), 'median': statistics.median(v[name] for v in values), 'min': min(v[name] for v in values), 'max': max(v[name] for v in values)} for name in fields}
        summary.append(item)
    differences = []
    for dimension, low, high in [('cpu', 0, 2), ('mode', 'minimal', 'full')]:
        for a in summary:
            if a[dimension] != low:
                continue
            for b in summary:
                if b[dimension] != high or any(a[k] != b[k] for k in ('group', 'cpu', 'mode', 'kind') if k != dimension):
                    continue
                delta = {f: b['metrics'][f]['mean']-a['metrics'][f]['mean'] for f in fields}
                require(abs(delta['cpu_us'] - (delta['gross_us'] - delta['dpc_isr_us'] + delta['residual_us'])) < 1e-6, 'Accounting difference identity')
                differences.append({'dimension': dimension, 'before': {k:a[k] for k in ('group','cpu','mode','kind')}, 'after': {k:b[k] for k in ('group','cpu','mode','kind')}, 'mean_deltas_us':delta})
    correlations = []
    for group in (1, 2):
        for cpu in (0, 2):
            for kind in ('sigma', 'native'):
                subset = [r for r in measured if (r['group'],r['cpu'],r['kind']) == (group,cpu,kind)]
                correlations.append({'group':group,'cpu':cpu,'kind':kind,'n':len(subset),
                    'pearson_residual_dpc':correlation([r['residual_us'] for r in subset],[r['dpc_isr_us'] for r in subset]),
                    'pearson_residual_order':correlation([r['residual_us'] for r in subset],[r['capture_index'] for r in subset])})
    return {'task':874,'source_capture_sha256':digest(folder/'capture.json'),'etw_rows':rows,'etw_measured_rows':len(measured),'summary':summary,'mean_difference_accounting':differences,'descriptive_correlations':correlations,
            'limits':['Existing 128 runs only; scheduler/priority detailed data only for ETW-on64 runs, measured48',
                      'Priority values sampled at switches, not continuous changes or frequency',
                      'Switch-in/out priority weights describe slice residence including interruptions, not instruction execution by priority',
                      'Mean difference identity is bookkeeping, not causal explanation; preregistered medians retained in prior results',
                      'Correlations use n6 per group/CPU/program, mix observer modes and can be confounded',
                      'ETW off has no scheduler/DPC trace; cross-block differences cannot be decomposed in this way',
                      'DPC per-slice integer-us rounding and API quantization remain; residual is not ground-truth error'],
            'analysis_source':Path(__file__).read_text(encoding='utf-8')}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = analyze(args.capture.resolve(), json.loads(args.metadata.read_text(encoding='utf-8')))
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(args.output)
