#!/usr/bin/env python3
"""P05a modes/history/source termination; Gforth is a behavior reference only."""
import argparse
import json
import os
import pathlib
import stat
import subprocess

p = argparse.ArgumentParser()
p.add_argument('sigma', nargs='?', default='zig-out/bin/sigma')
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
p.add_argument('--report', type=pathlib.Path)
a = p.parse_args()
b = a.gforth_build.resolve()
folder = pathlib.Path('.work/p05a-misc-check').resolve()
folder.mkdir(parents=True, exist_ok=True)
commands = {'sigma': [str(pathlib.Path(a.sigma).resolve()), '--max-steps', '100000', '-e'], 'gforth': [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e']}
skip = chr(92) * 3


def run(runtime, code, mask=None):
    extra = {} if mask is None else {'preexec_fn': lambda: os.umask(mask)}
    r = subprocess.run(commands[runtime] + [code + ' BYE'], capture_output=True, text=True, input='', timeout=15, **extra)
    assert r.returncode == 0, (runtime, code, r.returncode, r.stdout, r.stderr)
    return r.stdout


mode_values = 0
for fam in range(6):
    code = f': MODES 512 0 DO {fam} I +FMODE . LOOP ; MODES DEPTH .'
    outputs = [run(runtime, code).split() for runtime in commands]
    assert outputs[0] == outputs[1] and len(outputs[0]) == 513 and outputs[0][-1] == '0', outputs
    mode_values += 512
permission_cases = 0
if os.name == 'posix':
    for mask in [0, 0o022, 0o027]:
        for mode in [0, 0o400, 0o600, 0o640, 0o644, 0o666, 0o700, 0o755, 0o777]:
            for runtime in commands:
                path = folder / (runtime + '-権限.bin')
                path.unlink(missing_ok=True)
                run(runtime, f'S" {path}" W/O {mode} +FMODE CREATE-FILE THROW CLOSE-FILE THROW DEPTH .', mask)
                assert stat.S_IMODE(path.stat().st_mode) == mode & ~mask, (runtime, mode, mask, path.stat())
            permission_cases += 1
    for runtime in commands:
        path = folder / (runtime + '-existing.bin')
        path.write_bytes(b'keep')
        path.chmod(0o600)
        run(runtime, f'S" {path}" W/O 0 +FMODE CREATE-FILE THROW CLOSE-FILE THROW')
        assert path.stat().st_size == 0 and stat.S_IMODE(path.stat().st_mode) == 0o600, runtime
        run(runtime, f'S" {path}" R/O 511 +FMODE OPEN-FILE THROW CLOSE-FILE THROW')
        assert stat.S_IMODE(path.stat().st_mode) == 0o600, runtime
    permission_cases += 2

first = folder / 'history-a.fs'
second = folder / 'history-b.fs'
first.write_text(': FIRST-MISC 1 ;\n')
second.write_text(': SECOND-MISC 2 ;\n')
code = f'INCLUDE {first} MARKER BACK INCLUDE {second} ." @BEFORE@" .INCLUDED ." @END@" BACK ." @AFTER@" .INCLUDED ." @END@"'
for runtime in commands:
    text = run(runtime, code)
    for marker, expected in [('@BEFORE@', [str(first), str(second)]), ('@AFTER@', [str(first)])]:
        body = text.split(marker)[1].split('@END@')[0]
        own = [line.strip() for line in body.splitlines() if str(folder) in line]
        assert own == expected, (runtime, marker, own, expected)

# Sigma's confirmed history policy is distinct registered names; Gforth keeps
# repeated INCLUDE occurrences. Exercise and report the difference explicitly.
code = f'INCLUDE {first} INCLUDE {first} ." @LIST@" .INCLUDED ." @END@"'
for runtime in commands:
    body = run(runtime, code).split('@LIST@')[1].split('@END@')[0]
    own = [line.strip() for line in body.splitlines() if str(folder) in line]
    expected = [str(first)] * (1 if runtime == 'sigma' else 2)
    assert own == expected, (runtime, own, expected)

source_cases = 0
for case in ['direct', 'nested', 'postponed']:
    child = folder / 'child.fs'
    parent = folder / 'parent.fs'
    child.write_text('4 ' + (skip if case != 'postponed' else 'SKIP-MISC') + ' 999\nNOT-A-WORD\n')
    if case == 'direct':
        code = f'INCLUDE {child} .S'
        expected = ['<1>', '4']
    else:
        parent.write_text(f'1 INCLUDE {child} 2\n3\n')
        prefix = f': SKIP-MISC POSTPONE {skip} ; ' if case == 'postponed' else ''
        code = prefix + f'INCLUDE {parent} 5 .S'
        expected = ['<5>', '1', '4', '2', '3', '5']
    for runtime in commands:
        assert run(runtime, code).split() == expected, (case, runtime)
    source_cases += 1

# The user explicitly selected a no-op instead of Gforth's invalid source-id
# access / extra-stack-value behavior outside source files. Do not crash Gforth.
assert run('sigma', f'11 {skip} 22 S" 33 {skip} 44" EVALUATE 55 .S').split() == ['<5>', '11', '22', '33', '44', '55']
report = {'words': 3, 'gforth_mode_values': mode_values, 'posix_permission_cases': permission_cases, 'gforth_history_cases': 2, 'gforth_source_cases': source_cases, 'sigma_nonfile_policy_cases': 1, 'intentional_duplicate_history_difference': 1, 'pass': True}
if a.report:
    a.report.parent.mkdir(parents=True, exist_ok=True)
    a.report.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
