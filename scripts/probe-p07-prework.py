#!/usr/bin/env python3
"""Observe all four assignment words before P07 prework policy approval."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
p.add_argument('--sigma', type=pathlib.Path, default=pathlib.Path('zig-out/bin/sigma'))
a = p.parse_args()
b = a.gforth_build.resolve()
commands = {
    'gforth': [str(b / 'gforth-ditc'), '-p', str(b) + ':~+', '-i', str(b / 'gforth.fi'), '-e'],
    'sigma': [str(a.sigma.resolve()), '--max-steps', '100000', '-e'],
}
cases = []
def add(name, source): cases.append((name, source))
for word in ('TO', '+TO', 'IS', 'ACTION-OF'):
    for kind, source in {
        'tick': f"' {word} 0<> .",
        'bracket-tick': f": T ['] {word} ; T 0<> .",
        'lookup': f'S" {word}" FIND-NAME DUP 0<> . NAME>INTERPRET 0<> .',
        'shadow': f': {word} 77 ; {word} .',
        'synonym': f'SYNONYM OTHER {word} ' + ('DEFER D : A 8 ; \' A OTHER D D .' if word=='IS' else "DEFER D : A 8 ; ' A IS D OTHER D EXECUTE ." if word=='ACTION-OF' else '1 VALUE V 2 OTHER V V .'),
    }.items(): add(word+':'+kind, source)
    setup = "DEFER D : A 8 ; ' A IS D " if word in ('IS','ACTION-OF') else '1 VALUE V '
    target = 'D' if word in ('IS','ACTION-OF') else 'V'
    value = "['] A " if word=='IS' else '' if word=='ACTION-OF' else '2 '
    effect = 'EXECUTE .' if word=='ACTION-OF' else 'D .' if word=='IS' else 'V .'
    add(word+':postpone', setup+f': M POSTPONE {word} ; IMMEDIATE : T {value}M {target} ; T '+effect)
    value = "' A " if word=='IS' else '' if word=='ACTION-OF' else '2 '
    add(word+':interpret-xt', setup+f"' {word} CONSTANT X {value}X EXECUTE {target} "+effect)
    compiled_value = "['] A " if word=='IS' else value
    suffix = "POSTPONE LITERAL " if word == "ACTION-OF" else ""
    run = "T " if word == "ACTION-OF" else ""
    add(word+':xt-while-compiling', setup+f"' {word} CONSTANT X : M {compiled_value}X EXECUTE {suffix}; IMMEDIATE : T M {target} ; {run}"+effect)
    add(word+':name-compile', setup+f': M [ S" {word}" FIND-NAME NAME>COMPILE SWAP ] LITERAL LITERAL EXECUTE ; IMMEDIATE : T '+("['] A " if word=='IS' else '' if word=='ACTION-OF' else '2 ')+f'M {target} ; T '+effect)
for word in ('TO','IS','+TO'):
    add(word+':value', f'1 VALUE V 3 {word} V V . : T 4 {word} V ; T V .')
    add(word+':double', f'1. 2VALUE V 3. {word} V V D. : T 4. {word} V ; T V D.')
    add(word+':float', f'1e FVALUE V 3e {word} V V F. : T 4e {word} V ; T V F.')
    add(word+':local', f': T {{ x -- }} 3 {word} x x . ; 1 T')
    add(word+':invalid-target', f': T S" 3 {word} DUP" EVALUATE ; \' T CATCH .')
    add(word+':missing-name', f': T S" 3 {word}" EVALUATE ; \' T CATCH .')
add('ACTION-OF:invalid-target', ": T S\" ACTION-OF DUP\" EVALUATE ; ' T CATCH .")
add('ACTION-OF:missing-name', ': T S" ACTION-OF" EVALUATE ; \' T CATCH .')
add('ACTION-OF:runtime-action', "DEFER D : A 1 ; : B 2 ; ' A IS D : T ACTION-OF D ; ' B IS D T EXECUTE .")
add('ACTION-OF:value', '1 VALUE V ACTION-OF V . : T ACTION-OF V ; 2 TO V T .')
add('IS:string', 'S" a" $VALUE V S" b" IS V V TYPE')
add('search-order-shadow', 'WORDLIST CONSTANT W W SET-CURRENT : TO 55 ; FORTH-WORDLIST SET-CURRENT W >ORDER TO . PREVIOUS 1 VALUE V 2 TO V V .')
results = []
for name, source in cases:
    row={'case':name,'source':source,'runs':{}}
    for engine, cmd in commands.items():
        try:
            r=subprocess.run(cmd+[source+' DEPTH . BYE'],input=b'',capture_output=True,timeout=10)
            row['runs'][engine]={'exit':r.returncode,'stdout':r.stdout.decode(errors='replace'),'stderr':r.stderr.decode(errors='replace')}
        except subprocess.TimeoutExpired: row['runs'][engine]={'timeout':True}
    results.append(row)
folder=pathlib.Path('.work/p07-prework-check'); folder.mkdir(parents=True,exist_ok=True)
(folder/'spec-probes.json').write_text(json.dumps({'cases':results},ensure_ascii=False,indent=2)+'\n')
for row in results:
    print(row['case'],json.dumps(row['runs'],ensure_ascii=False))
