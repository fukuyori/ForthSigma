#!/usr/bin/env python3
"""Reproducible clipping/rotation CPU samples; no SHOW or display timing claim.
Compare the current clip/no-clip paths doing equal work, not an older implementation.
"""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import statistics
import subprocess

if not __debug__:
    raise SystemExit('Run without Python -O')
ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma.exe')
parser.add_argument('--samples', type=int, default=7)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
assert args.samples >= 3
PRELUDE = '''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-TERMINAL
512 512 GFX-INIT
: CPU-US CPUTIME D+ D>S ;
: CHECKSUM 0 GFX-HEIGHT 0 DO GFX-WIDTH 0 DO I J GFX-PGET + LOOP LOOP ;
VARIABLE START-US
'''
cases = []
for clipping, setup in [('none', 'NO-CLIP'), ('inside', '64 64 384 384 CLIP!')]:
    cases.append(dict(name='hline-' + clipping, kind='clip', iterations=8000000,
                      setup=setup, work='96 415 128 $4080C0 GFX-HLINE'))
    cases.append(dict(name='pset-' + clipping, kind='clip', iterations=8000000,
                      setup=setup, work='128 128 $4080C0 GFX-PSET'))
pattern = '''128 128 NEW-IMAGE CONSTANT SRC SRC DRAW-TO
: PATTERN 128 0 DO 128 0 DO I 8 / J 8 / + 1 AND IF $F08020 ELSE $2060D0 THEN I J ROT GFX-PSET LOOP LOOP ;
PATTERN SCREEN DRAW-TO MODE-COPY IMAGE-MODE
'''
for smooth in (False, True):
    for scale in (500, 1000, 2000):
        cases.append(dict(name=f'rotate-{scale}-' + ('smooth' if smooth else 'nearest'),
                          kind='rotate', iterations={500: 8000, 1000: 2000, 2000: 1000}[scale],
                          setup=pattern + ('TRUE' if smooth else 'FALSE') + ' IMAGE-SMOOTH',
                          work=f'SRC 256 256 3700 {scale} PUT-ROTATED'))
rows = {case['name']: [] for case in cases}
# Warm-up is one independent process per case, then rotate the case order each round.
for sample in range(-1, args.samples):
    shift = max(sample, 0) % len(cases)
    for case in cases[shift:] + cases[:shift]:
        source = PRELUDE + case['setup'] + '\n: WORK 0 DO ' + case['work'] + ' LOOP ;\n'
        source += f"10 WORK 0 GFX-CLS CPU-US START-US ! {case['iterations']} WORK CPU-US START-US @ - "
        source += '." RESULT " . CHECKSUM . DEPTH . CR BYE'
        result = subprocess.run([str(args.sigma.resolve()), '-e', source], capture_output=True, timeout=60)
        output = result.stdout.decode('utf-8', 'replace')
        assert result.returncode == 0 and not result.stderr and 'BACKTRACE:' not in output, (case['name'], result.returncode, output, result.stderr)
        assert output.count('RESULT ') == 1, output
        cpu, checksum, depth = map(int, output.split('RESULT ')[1].split())
        assert cpu > 0 and depth == 0, (case['name'], output)
        rows[case['name']].append(dict(round=sample, cpu_us=cpu, checksum=checksum, warmup=sample < 0))
        print(case['name'], sample, cpu, flush=True)
for case in cases:
    samples = rows[case['name']]
    assert len({row['checksum'] for row in samples}) == 1, (case, samples)
    case['samples'] = samples
    case['median_cpu_us'] = statistics.median(row['cpu_us'] for row in samples if not row['warmup'])
    case['median_us_per_operation'] = case['median_cpu_us'] / case['iterations']
for operation in ('hline', 'pset'):
    assert rows[operation + '-none'][0]['checksum'] == rows[operation + '-inside'][0]['checksum']
    expected = 0x4080C0 * (320 if operation == 'hline' else 1)
    assert rows[operation + '-none'][0]['checksum'] == expected, (operation, rows[operation + '-none'])
report = dict(platform=platform.platform(), machine=platform.machine(), processor=platform.processor(),
              binary=dict(path=str(args.sigma.resolve()), bytes=args.sigma.stat().st_size,
                          sha256=hashlib.sha256(args.sigma.read_bytes()).hexdigest()),
              working_tree=subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).splitlines(),
              revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              method='Process CPU user+system microseconds inside WORK; independent processes, one warm-up and rotated case order; no affinity or other-process isolation',
              limitations=['Current clipped/unclipped paths with equal work; not pre-implementation overhead',
                           'No window rendering, frame presentation or whole-game performance claim'],
              cases=cases)
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
