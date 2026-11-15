#!/usr/bin/env python3
"""Observe the whole P07a unit before implementation/policy selection."""
import argparse
import json
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
a = p.parse_args()
b = a.gforth_build.resolve()
cmd = [str(b/'gforth-ditc'), '-p', str(b)+':~+', '-i', str(b/'gforth.fi'), '-e']
cases = []
def add(name, source): cases.append((name, source))
for word in ("COMP'", 'COMPILE-ONLY', 'EXECUTE-EXIT', 'POSTPONE,', 'RESTRICT', 'SELECT', "[COMP']", '[NOOP]'):
    add('immediate-flag:'+word, f'BL WORD {word} FIND NIP .')
    add('lookup:'+word, f'S" {word}" FIND-NAME DUP 0<> . NAME>INTERPRET 0<> .')
for flag in (0, -1, 1, 2, -2, 255):
    add('select:'+str(flag), f'11 22 {flag} SELECT .')
add('select-compiled', ': T SELECT ; 11 22 0 T . 11 22 -1 T .')
add('noop-interpreted', '[NOOP]')
add('noop-compiled', ': T [NOOP] ; T')
add('noop-tick', "' [NOOP] EXECUTE DEPTH .")
for word in ('DUP', 'IF', 'TO'):
    add('comp-tick:'+word, f"COMP' {word} SWAP ' {word} = . ' EXECUTE = .")
    add('comp-tick-compiled:'+word, f": T COMP' ; T {word} SWAP ' {word} = . ' EXECUTE = .")
    add('bracket-comp-tick:'+word, f": T [COMP'] {word} ; T SWAP ' {word} = . ' EXECUTE = .")
add('comp-tick-execute', "1 VALUE V : M COMP' EXECUTE ; IMMEDIATE : T 2 M TO V ; V . T V .")
add('bracket-comp-tick-interpret', "[COMP'] DUP")
add('bracket-comp-tick-immediate', ": M [COMP'] DUP EXECUTE ; IMMEDIATE : T 3 M ; T . .")
add('postpone-comma-default', ": M [ COMP' DUP POSTPONE, ] ; IMMEDIATE : T 3 M ; T . .")
add('postpone-comma-immediate', ": M [ COMP' IF POSTPONE, ] ; IMMEDIATE : T M 11 ELSE 22 THEN ; 0 T . -1 T .")
add('postpone-comma-combined', "1 VALUE V : M [ COMP' TO POSTPONE, ] ; IMMEDIATE : T 9 M V ; V . T V .")
add('postpone-comma-STATE-false', "1 VALUE V : M [COMP'] TO EXECUTE ; : T 8 [ M V ] ; T V .")
add('postpone-comma-no-definition', "COMP' DUP POSTPONE,")
for restriction in ('COMPILE-ONLY','RESTRICT'):
    prefix=f': X 77 ; {restriction} '
    add(restriction+':interpret',prefix+'X .')
    add(restriction+':compile',prefix+': T X ; T .')
    add(restriction+':tick',prefix+"' X EXECUTE .")
    add(restriction+':name-interpret',prefix+'S" X" FIND-NAME NAME>INTERPRET DUP 0<> . EXECUTE .')
    add(restriction+':synonym',prefix+'SYNONYM Y X Y .')
    add(restriction+':compiled-synonym',prefix+'SYNONYM Y X : T Y ; T .')
    add(restriction+':immediate',f': X 77 ; IMMEDIATE {restriction} : T X LITERAL ; T .')
    add(restriction+':no-user-definition',restriction)
    add(restriction+':anonymous',f':NONAME 77 ; {restriction} EXECUTE .')
    add(restriction+':STATE-false',prefix+': T [ X ] LITERAL ; T .')
add('execute-exit', ": A 7 ; : T ['] A EXECUTE-EXIT 99 ; T .")
add('execute-exit-nested', ": A 7 ; : T ['] A EXECUTE-EXIT 99 ; : U T 8 ; U . .")
add('execute-exit-local', ": A 7 ; : T { x -- } x ['] A EXECUTE-EXIT 99 ; 3 T . .")
add('execute-exit-loop', ": A 7 ; : T 3 0 DO I 1 = IF UNLOOP ['] A EXECUTE-EXIT THEN LOOP 99 ; T .")
add('execute-exit-throw', ": A -123 THROW ; : T ['] A EXECUTE-EXIT 99 ; ' T CATCH .")
add('execute-exit-interpret', "' NOOP EXECUTE-EXIT")
add('execute-exit-tick', "' EXECUTE-EXIT 0<> .")
results=[]
for name,source in cases:
    row={'case':name,'source':source}
    try:
        r=subprocess.run(cmd+[source+' DEPTH . BYE'],input=b'',capture_output=True,timeout=10)
        row.update(exit=r.returncode,stdout=r.stdout.decode(errors='replace'),stderr=r.stderr.decode(errors='replace'))
    except subprocess.TimeoutExpired: row['timeout']=True
    results.append(row)
folder=pathlib.Path('.work/p07a-check');folder.mkdir(parents=True,exist_ok=True)
(folder/'spec-probes.json').write_text(json.dumps({'cases':results},ensure_ascii=False,indent=2)+'\n')
for row in results: print(json.dumps(row,ensure_ascii=False))
