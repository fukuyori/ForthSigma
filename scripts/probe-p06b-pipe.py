#!/usr/bin/env python3
"""Read-only reference behavior probes for the pending pipe portability decision."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
a = p.parse_args()
b = a.gforth_build.resolve()
command = [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e']
cases = [
    ('broken-pipe-code', 'BROKEN-PIPE-ERROR .'),
    ('exit-status', 'S" exit 3" R/O OPEN-PIPE THROW CLOSE-PIPE . .'),
    ('read-write-mode', 'S" true" R/W OPEN-PIPE DUP . 0= IF CLOSE-PIPE . . ELSE DROP THEN'),
    ('retains-system-status', '123 TO $? S" true" R/O OPEN-PIPE THROW CLOSE-PIPE 2DROP $? .'),
]
results = []
for title, source in cases:
    run = subprocess.run(command + [source + ' DEPTH . BYE'], input=b'', capture_output=True, timeout=10)
    results.append({'case': title, 'source': source, 'exit': run.returncode,
                    'stdout': run.stdout.decode(errors='replace'), 'stderr': run.stderr.decode(errors='replace')})
folder = pathlib.Path('.work/p06b-pipe-check')
folder.mkdir(parents=True, exist_ok=True)
report = {'kind': 'reference observations, not Sigma conformance checks', 'cases': results}
(folder / 'initial-probes.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'observations': len(results), 'cases': [{'case': r['case'], 'stdout': r['stdout']} for r in results]}))
