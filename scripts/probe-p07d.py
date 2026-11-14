#!/usr/bin/env python3
"""Observe temporary parsing and forward binding before implementing P07d."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True);a=p.parse_args();b=a.gforth_build.resolve();cmd=[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e'];cases=[]
def add(name,src):cases.append((name,src))
for w in ('.UNRESOLVED','EXECUTE-PARSING','EXECUTE-PARSING-FILE','FORWARD','NAME','PARSE-WORD','RECURSIVE','STRING-PARSE'):
 add('lookup:'+w,f'S" {w}" FIND-NAME 0<> .');add('immediate:'+w,f'BL WORD {w} FIND NIP .')
for w in ('NAME','PARSE-WORD'):
 add('parse:'+w,f': T {w} TYPE ; T abc T xyz')
 add('parse-empty:'+w,f': T S" " [\'] {w} EXECUTE-PARSING NIP . ; T')
for delimiter,source in [('::','abc::rest'),('END','abcENDtail'),('xx','xxxx'),('x','nothing'),('','abc'),('::',''),('END','ENDx')]:
 add('string:'+repr((delimiter,source)),f': P S" {delimiter}" STRING-PARSE TYPE [CHAR] | EMIT >IN @ . SOURCE NIP . ; S" {source}" \' P EXECUTE-PARSING')
add('temporary-source',': P SOURCE TYPE SOURCE-ID . >IN @ . REFILL . ; S" abc" \' P EXECUTE-PARSING')
add('temporary-create','5 S" FOO" \' CONSTANT EXECUTE-PARSING FOO .')
add('temporary-restore',': P PARSE-NAME TYPE ; : T S" abc" [\'] P EXECUTE-PARSING PARSE-NAME TYPE ; T xyz')
add('temporary-throw',': P PARSE-NAME 2DROP -123 THROW ; : R S" abc" [\'] P EXECUTE-PARSING ; : T [\'] R CATCH . PARSE-NAME TYPE ; T xyz')
add('temporary-nested',': P PARSE-NAME TYPE ; : Q S" inner" [\'] P EXECUTE-PARSING PARSE-NAME TYPE ; S" outer" \' Q EXECUTE-PARSING')
add('temporary-not-evaluate',': P 9 ; S" UNKNOWN" \' P EXECUTE-PARSING .')
add('temporary-cursor',': P 2 >IN ! PARSE-NAME TYPE ; S" abc def" \' P EXECUTE-PARSING')
for label,src in zip(['forward-unresolved','forward-bind','forward-tick','forward-multiple','forward-duplicate','forward-noncolon','forward-redefine'], ['FORWARD F .UNRESOLVED','FORWARD F : T F ; .UNRESOLVED : F 7 ; T . .UNRESOLVED',"FORWARD F ' F 0<> .",'FORWARD F FORWARD G .UNRESOLVED','FORWARD F FORWARD F .UNRESOLVED','FORWARD F 7 CONSTANT F .UNRESOLVED',': F 1 ; FORWARD F : T F ; : F 2 ; T .']):
 add(label,src)
add('forward-tick-after',"FORWARD F ' F CONSTANT OLD : F 7 ; OLD ' F = . OLD EXECUTE .")
add('forward-xt-literal',"FORWARD F : T ['] F ; : F 7 ; T ' F = . T EXECUTE .")
add('forward-mutual','FORWARD ODD-X : EVEN-X DUP IF 1- ODD-X ELSE DROP -1 THEN ; : ODD-X DUP IF 1- EVEN-X ELSE DROP 0 THEN ; 4 EVEN-X . 5 EVEN-X . .UNRESOLVED')
add('forward-synonym', 'FORWARD F SYNONYM S F : T S ; : F 7 ; T .')
add('forward-failure', ': BAD S" FORWARD F : F IF ;" EVALUATE ; \' BAD CATCH . .UNRESOLVED')
add('forward-wid', 'WORDLIST CONSTANT W FORWARD F : T F ; W SET-CURRENT : F 7 ; FORTH-WORDLIST SET-CURRENT .UNRESOLVED : F 8 ; T .')
add('recursive',': FACT RECURSIVE DUP IF DUP 1- FACT * ELSE DROP 1 THEN ; 5 FACT .')
add('recursive-outside',': T S" RECURSIVE" EVALUATE ; \' T CATCH .')
add('recursive-visibility',': F RECURSIVE [ S" F" FIND-NAME 0<> . ] 7 ; F .')
folder=pathlib.Path('.work/p07d-check').resolve();folder.mkdir(parents=True,exist_ok=True);path=folder/'input.txt';path.write_text('abc def\nsecond line\n')
for name,body in [('initial','SOURCE NIP . >IN @ .'),('refill','REFILL . PARSE-NAME TYPE REFILL . PARSE-NAME TYPE REFILL .'),('parse','PARSE-NAME TYPE'),('throw','REFILL DROP -123 THROW')]:
 src=f'S" {path}" R/O OPEN-FILE THROW CONSTANT F : P {body} ; : R F [\'] P EXECUTE-PARSING-FILE ; \' R CATCH . '
 add('file:'+name,src)
results=[]
for name,source in cases:
 row={'case':name,'source':source}
 try:
  r=subprocess.run(cmd+[source+' DEPTH . BYE'],input=b'',capture_output=True,timeout=3);row.update(exit=r.returncode,stdout=r.stdout.decode(errors='replace'),stderr=r.stderr.decode(errors='replace'))
 except subprocess.TimeoutExpired:row['timeout']=True
 results.append(row)
(folder/'spec-probes.json').write_text(json.dumps({'cases':results},ensure_ascii=False,indent=2)+'\n')
for r in results:print(json.dumps(r,ensure_ascii=False))
