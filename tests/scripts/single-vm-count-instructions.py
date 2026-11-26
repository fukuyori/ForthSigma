#!/usr/bin/env python3
"""Count user-mode instructions per iteration for the single-VM A/A'/B fixtures (Linux perf).

usage: single-vm-count-instructions.py BUILDS_JSON OUT_JSON

Runs each fixture of single-vm-ab.py with N=1000 and N=10,000,000, three times each, under
`perf stat -e instructions:u`, and reports (min count at 10M - min count at 1000) / (10M - 1000).
Startup and definition costs cancel out. Requires kernel.perf_event_paranoid <= 2.
"""
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('svab', ROOT / 'tests/scripts/single-vm-ab.py')
svab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(svab)

SMALL, LARGE, REPEAT = 1000, 10_000_000, 3


def count(binary, source):
    r = subprocess.run(['perf', 'stat', '-x', ',', '-e', 'instructions:u', binary, '-e', source],
                       input=b'xx', capture_output=True, check=True)
    line = next(l for l in r.stderr.decode().splitlines() if 'instructions' in l)
    return int(line.split(',')[0])


def main():
    builds = json.loads(Path(sys.argv[1]).read_text())
    rows = []
    for name, (body, _) in svab.CASES.items():
        body = re.sub(r'\b(N|RUN|INC|TOKEN|ACTION|DATA)\b', lambda m: 'SVAB-' + m[0], body)
        for label in ('A', 'Aprime', 'B'):
            counts = {}
            for n in (SMALL, LARGE):
                source = f'{n} CONSTANT SVAB-N {body} ." READY" CR KEY DROP SVAB-RUN ." DONE " . CR KEY DROP BYE'
                counts[n] = [count(builds[label]['binary'], source) for _ in range(REPEAT)]
            per = (min(counts[LARGE]) - min(counts[SMALL])) / (LARGE - SMALL)
            rows.append({'case': name, 'label': label, 'counts': counts, 'per_iteration': per})
            print(name, label, round(per, 4), flush=True)
    Path(sys.argv[2]).write_text(json.dumps(rows, indent=1) + '\n')


if __name__ == '__main__':
    main()
