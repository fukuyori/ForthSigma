#!/usr/bin/env python3
"""One-way pipe comparisons and Sigma-specific portability/error checks."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
a = p.parse_args()
b = a.gforth_build.resolve()
root = pathlib.Path('.work/p06b-pipe-check').resolve()
root.mkdir(parents=True, exist_ok=True)
commands = {
    'sigma': [str(pathlib.Path('zig-out/bin/sigma').resolve()), '--max-steps', '100000', '-e'],
    'gforth': [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e'],
}
cases = [
    ('read', 'printf ABC', 'R/O BIN', 'P SLURP-FID OVER >R TYPE R> FREE THROW P CLOSE-PIPE . .'),
    ('status', 'printf A; exit 3', 'R/O', 'P KEY-FILE . P CLOSE-PIPE . .'),
    ('empty', 'true', 'R/O', 'P SLURP-FID OVER >R TYPE R> FREE THROW P CLOSE-PIPE . .'),
    ('input-selection', 'printf AB', 'R/O', ': INPUT-P KEY . KEY . ; \' INPUT-P P INFILE-EXECUTE P CLOSE-PIPE . .'),
    ('write', 'cat > {target}', 'W/O BIN', 'S" 日本語" P WRITE-FILE THROW P FLUSH-FILE THROW P CLOSE-PIPE . .'),
    ('output-selection', 'cat > {target}', 'W/O', ': OUTPUT-P S" text" TYPE ; \' OUTPUT-P P OUTFILE-EXECUTE P CLOSE-PIPE . .'),
    ('system-status', 'true', 'R/O', 'P CLOSE-PIPE 2DROP $? .'),
]
results = []
for title, shell, mode, action in cases:
    outputs = {}
    for runtime, command in commands.items():
        target = root / (runtime + '-output.txt')
        target.unlink(missing_ok=True)
        code = 'S" exit 7" SYSTEM '
        code += f'S" {shell.format(target=target)}" {mode} OPEN-PIPE THROW CONSTANT P ' + action + ' DEPTH . BYE'
        run = subprocess.run(command + [code], input=b'', capture_output=True, timeout=15)
        assert run.returncode == 0, (title, runtime, run.returncode, run.stdout, run.stderr)
        outputs[runtime] = [run.stdout.decode(), target.read_bytes().hex() if target.exists() else '']
    assert outputs['sigma'] == outputs['gforth'], (title, outputs)
    results.append({'case': title, 'output': outputs['sigma']})
checks = []
for title, source, expected in [
    ('rw-rejected', 'S" true" R/W OPEN-PIPE . .', '-534 0 0 '),
    ('broken-pipe-code', 'BROKEN-PIPE-ERROR .', '-544 0 '),
    ('broken-write-survives', 'S" exit 0" W/O OPEN-PIPE THROW CONSTANT P : TRY-WRITE 100 0 DO S" x" P WRITE-FILE DUP IF UNLOOP EXIT THEN DROP 10 MS LOOP 0 ; TRY-WRITE BROKEN-PIPE-ERROR = . P CLOSE-PIPE . .', '-1 0 0 0 '),
]:
    run = subprocess.run(commands['sigma'] + [source + ' DEPTH . BYE'], input=b'', capture_output=True, timeout=15)
    assert run.returncode == 0 and run.stdout.decode() == expected, (title, run.returncode, run.stdout, run.stderr)
    checks.append(title)
report = {'pass': True, 'gforth_comparisons': len(results), 'sigma_checks': checks, 'cases': results}
(root / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'pass': True, 'gforth_comparisons': len(results), 'sigma_checks': len(checks)}))
