#!/usr/bin/env python3
"""Behavioral comparison of the P04b macro APIs, without copying Gforth code."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('sigma', nargs='?', default='zig-out/bin/sigma')
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
p.add_argument('--report', type=pathlib.Path)
a = p.parse_args()
cases = []
for api in ['.SUBSTITUTE', '$SUBSTITUTE', 'SUBSTITUTE']:
    tail = {'.SUBSTITUTE': '. ', '$SUBSTITUTE': '. TYPE ', 'SUBSTITUTE': 'BUF 80 SUBSTITUTE . TYPE '}[api]
    if api == 'SUBSTITUTE':
        call = tail
    else:
        call = api + ' ' + tail
    for text in ['', 'plain', '%%', '%X%', '%X%%X%', 'a%X%b', '%x%/%X%', '%absent%', '%', '%X', '%%%X%%%', '%X%%absent%%%']:
        code = 'CREATE BUF 80 ALLOT VARIABLE CALLS REPLACER: X 1 CALLS +! S" value" ; S" ' + text + '" ' + call + 'CALLS @ .'
        cases.append((api + ':' + text, code))
for api in ['.SUBSTITUTE', '$SUBSTITUTE', 'SUBSTITUTE']:
    call = {'SUBSTITUTE': 'BUF 1 SUBSTITUTE . TYPE', '$SUBSTITUTE': '$SUBSTITUTE . TYPE', '.SUBSTITUTE': '.SUBSTITUTE .'}[api]
    cases.append(('side-effects-' + api, 'CREATE BUF 1 ALLOT VARIABLE CALLS REPLACER: X 1 CALLS +! CALLS @ 1 = IF S" first" ELSE S" later" THEN ; S" %X%%X%" ' + call + ' CALLS @ .'))
    call = {'SUBSTITUTE': 'BUF 30 SUBSTITUTE', '$SUBSTITUTE': '$SUBSTITUTE', '.SUBSTITUTE': '.SUBSTITUTE'}[api]
    cases.append(('throw-' + api, 'CREATE BUF 30 ALLOT REPLACER: X -123 THROW ; : RUN S" before%X%after" ' + call + ' ; \' RUN CATCH .'))
cases += [
    ('case', 'S" upper" S" X" REPLACES S" lower" S" x" REPLACES S" %X%/%x%" .SUBSTITUTE .'),
    ('replace-value', 'S" old" S" X" REPLACES S" new" S" X" REPLACES S" %X%" .SUBSTITUTE .'),
    ('current', 'GET-CURRENT REPLACER: X S" hi" ; GET-CURRENT = . S" %X%" .SUBSTITUTE .'),
    ('macro-value', 'GET-CURRENT MACROS-WORDLIST SET-CURRENT S" owned" MACRO: X SET-CURRENT MACROS-WORDLIST >ORDER S" !" +TO X PREVIOUS S" %X%" .SUBSTITUTE .'),
    ('percent-in-name', 'S" unreachable" S" X%Y" REPLACES S" %X%Y%" .SUBSTITUTE .'),
    ('long-unknown-name', 'CREATE TEXT 302 ALLOT TEXT 302 120 FILL 37 TEXT C! 37 TEXT 301 + C! TEXT 302 .SUBSTITUTE .'),
    ('callback-output', 'REPLACER: X ." emitted" S" returned" ; S" a%X%b" $SUBSTITUTE . TYPE'),
    ('nested', 'S" inner" S" I" REPLACES REPLACER: X S" <%I%>" $SUBSTITUTE DROP ; S" %X%" $SUBSTITUTE . TYPE'),
]
b = a.gforth_build.resolve()
commands = {'sigma': [str(pathlib.Path(a.sigma).resolve()), '--max-steps', '100000', '-e'], 'gforth': [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e']}
for name, source in cases:
    outputs = {}
    for runtime, command in commands.items():
        r = subprocess.run(command + [source + ' DEPTH . BYE'], capture_output=True, text=True, input='', timeout=15)
        assert r.returncode == 0, (name, runtime, r.stdout, r.stderr)
        outputs[runtime] = r.stdout
    assert outputs['sigma'] == outputs['gforth'], (name, outputs)
report = {'words': 3, 'cases': len(cases), 'checked': list(commands), 'pass': True}
if a.report:
    a.report.parent.mkdir(parents=True, exist_ok=True)
    a.report.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
