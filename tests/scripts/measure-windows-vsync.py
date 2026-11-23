#!/usr/bin/env python3
"""Measure VSYNC-WAIT calls on each existing monitor, without changing modes."""
import argparse
import json
from pathlib import Path
import statistics
import time
from windows_display_test_support import SigmaSession, binary_identity, run
from windows_monitor_probe import snapshot, available_modes

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma.exe')
parser.add_argument('--samples', type=int, default=120)
parser.add_argument('--rounds', type=int, default=3)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
assert 10 <= args.samples <= 1000 and 1 <= args.rounds <= 10
independent = snapshot()
count = int(run(args.sigma, 'REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAYS . BYE'))
assert count == len(independent) > 0
source = '''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-WINDOW DISPLAYS DROP
4 2 GFX-INIT 160 100 WINDOW-SIZE
CREATE TIMES 1000 CELLS ALLOT CREATE RESULTS 1000 CELLS ALLOT
VARIABLE START-US
: SAMPLE 0 DO UTIME D>S START-US ! VSYNC-WAIT RESULTS I CELLS + !
UTIME D>S START-US @ - TIMES I CELLS + ! LOOP ;
: REPORT 0 DO TIMES I CELLS + @ . RESULTS I CELLS + @ . CR LOOP ;
'''
order = [(r, (i + r) % count) for r in range(args.rounds) for i in range(count)]
for r, i in order:
    source += f'KEY DROP {i} WINDOW-ON SHOW 2000 WINDOW-PAINT-WAIT . 300 MS '
    source += f'." READY {r} {i} " WINDOW-DISPLAY . {i} DISPLAY-HZ SWAP . . CR '
    source += f'KEY DROP {args.samples} SAMPLE {args.samples} REPORT ." DONE" CR\n'
source += 'KEY DROP BYE'
rows = []
with SigmaSession(args.sigma, source) as session:
    for r, i in order:
        session.send()
        ready = session.line().split()
        assert ready[:4] == [b'-1', b'READY', str(r).encode(), str(i).encode()], ready
        actual, hz_n, hz_d = map(int, ready[4:])
        assert actual == i and hz_n > 0 and hz_d > 0, ready
        started = time.perf_counter()
        session.send()
        samples = [list(map(int, session.line(timeout=15).split())) for _ in range(args.samples)]
        assert session.line() == b'DONE'
        elapsed = time.perf_counter() - started
        assert all(len(s) == 2 and s[0] >= 0 and s[1] in (0, -1) for s in samples), samples
        assert all(s[1] == -1 for s in samples), 'Timing requires successful compositor waits'
        durations = [s[0] for s in samples]
        rows.append(dict(round=r, display=i, hz=[hz_n, hz_d], samples_us_and_success=samples,
                         successes=sum(s[1] == -1 for s in samples), batch_wall_seconds=elapsed,
                         median_us=statistics.median(durations), min_us=min(durations), max_us=max(durations),
                         p95_us=sorted(durations)[int(.95 * (len(durations) - 1))]))
        print(f'round {r}, display {i}: {rows[-1]["successes"]}/{args.samples} success, median {rows[-1]["median_us"]} us', flush=True)
    session.send()
    session.finish()
assert snapshot() == independent, 'Display configuration changed during measurement'
report = dict(binary=binary_identity(args.sigma), status='pass', monitors=independent,
              available_modes={m['device']: available_modes(m['device']) for m in independent},
              samples=args.samples, rounds=args.rounds, results=rows,
              method='Per-call UTIME microseconds in Sigma; batch perf_counter in Python; rotated monitor order; existing desktop only',
              limitations=['UTIME is wall clock, not monotonic; batch timings include protocol overhead',
                           'DwmFlush completion is compositor synchronization, not physical presentation',
                           'No mode change or unavailable-DwmFlush environment',
                           'No assumption that DwmFlush follows the refresh rate of the window monitor'])
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
