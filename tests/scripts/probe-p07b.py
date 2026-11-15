#!/usr/bin/env python3
"""Investigate the whole quotation/macro unit before implementation."""
import argparse
import json
import pathlib
import subprocess
p=argparse.ArgumentParser()
p.add_argument('--gforth-build',type=pathlib.Path,required=True)
a=p.parse_args();b=a.gforth_build.resolve()
cmd=[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']
cases=[]
def add(name,source):cases.append((name,source))
for word in (';]','IN-COLON-DEF?','NONAME','[:','[[',']]'):
    add('lookup:'+word,f': CHECK S" {word}" FIND-NAME DUP 0<> . DUP IF NAME>INTERPRET 0<> . ELSE DROP 0 . THEN ; CHECK')
    add('immediate:'+word,f'BL WORD {word} FIND NIP .')
add('in-colon-interpret','IN-COLON-DEF? .')
add('in-colon-compile',': T [ IN-COLON-DEF? . ] ;')
add('in-colon-runtime',': T IN-COLON-DEF? ; T .')
add('in-colon-immediate',': M IN-COLON-DEF? . ; IMMEDIATE : T M ;')
add('noname-colon','NONAME : 7 ; LATEST . LATESTXT EXECUTE .')
add('noname-variable','NONAME VARIABLE LATEST . LATESTXT EXECUTE 7 OVER ! @ .')
add('noname-constant','7 NONAME CONSTANT LATEST . LATESTXT EXECUTE .')
add('noname-value','7 NONAME VALUE LATEST . LATESTXT EXECUTE .')
add('noname-defer',"NONAME DEFER LATESTXT DUP ' DUP SWAP DEFER! 7 SWAP EXECUTE . .")
add('noname-create','NONAME CREATE 7 , LATESTXT EXECUTE @ .')
add('noname-twice','NONAME NONAME : 7 ; LATESTXT EXECUTE .')
add('noname-intervening','NONAME 3 4 + CONSTANT LATESTXT EXECUTE .')
add('noname-executed',': MAKE NONAME : ; MAKE 7 ; LATESTXT EXECUTE .')
add('quote-interpret','[: 7 ;] EXECUTE .')
add('quote-compile',': T [: 7 ;] ; T EXECUTE .')
add('quote-nested',': T [: [: 7 ;] ;] ; T EXECUTE EXECUTE .')
add('quote-surrounding',': T 1 [: 2 ;] EXECUTE 3 ; T . . .')
add('quote-conditional',': T IF [: 1 ;] ELSE [: 2 ;] THEN EXECUTE ; -1 T . 0 T .')
add('quote-control-isolation',': T IF [: IF 1 ELSE 2 THEN ;] EXECUTE THEN ; -1 -1 T .')
add('quote-local',': T [: { x -- } x 2 * ;] ; 3 T EXECUTE .')
add('quote-outer-local',': T { x -- } [: x ;] ; 3 T EXECUTE .')
add('quote-recursion',': T [: DUP 0> IF 1- RECURSE ELSE DROP 7 THEN ;] ; 3 T EXECUTE .')
add('quote-in-colon',': T [: [ IN-COLON-DEF? . ] IN-COLON-DEF? ;] ; T EXECUTE .')
add('quote-name',': T [: 7 ;] ; LATESTXT \' T = . T >NAME 0= .')
add('quote-catch','[: -123 THROW ;] CATCH .')
add('quote-callback',': T 4 [: DUP * ;] EXECUTE ; T .')
add('quote-unbalanced-control',': T [: IF 7 ;] ;')
add('quote-unclosed',': T [: 7 ;')
add('quote-close-alone',';]')
add('postpone-arithmetic',': M ]] DUP + [[ ; IMMEDIATE : T 3 M ; T .')
add('postpone-integer',': M ]] 7 [[ ; IMMEDIATE : T M ; T .')
add('postpone-double',': M ]] 7. [[ ; IMMEDIATE : T M ; T D.')
add('postpone-float',': M ]] 2.5e [[ ; IMMEDIATE : T M ; T F.')
add('postpone-string',': M ]] S" [[ ; IMMEDIATE : T M text" ; T TYPE')
add('postpone-print',': M ]] ." [[ ; IMMEDIATE : T M text" ; T')
add('postpone-control',': M ]] IF 1 ELSE 2 THEN [[ ; IMMEDIATE : T M ; -1 T . 0 T .')
add('postpone-assignment','1 VALUE V : M ]] TO [[ ; IMMEDIATE : T 7 M V ; V . T V .')
add('postpone-local',': M { x -- } ]] x + [[ ; IMMEDIATE : T 3 [ 4 ] M ; T .')
add('postpone-state',': M ]] STATE @ . [[ ; IMMEDIATE : T M ; T')
add('postpone-state-immediate',': M ]] [ STATE @ . ] [[ ; IMMEDIATE')
add('postpone-quote',': M ]] [: 7 ;] [[ ; IMMEDIATE : T M ; T EXECUTE .')
add('postpone-repeated',': M ]] DUP [[ ]] + [[ ; IMMEDIATE : T 3 M ; T .')
add('postpone-from-interpret',': M [ ]] DUP [[ ; IMMEDIATE : T 3 M ; T . .')
add('postpone-no-definition',']] 7 [[')
add('postpone-close-alone','[[')
for name,source in {
    'two-variable':'NONAME 2VARIABLE LATESTXT EXECUTE 2 CELLS ERASE',
    'two-constant':'7. NONAME 2CONSTANT LATESTXT EXECUTE D.',
    'two-value':'7. NONAME 2VALUE LATESTXT EXECUTE D.',
    'float-variable':'NONAME FVARIABLE LATESTXT EXECUTE DUP 2.5e F! F@ F.',
    'float-constant':'2.5e NONAME FCONSTANT LATESTXT EXECUTE F.',
    'float-value':'2.5e NONAME FVALUE LATESTXT EXECUTE F.',
    'string-value':'S" text" NONAME $VALUE LATESTXT EXECUTE TYPE',
    'buffer':'16 NONAME BUFFER: LATESTXT EXECUTE 16 ERASE',
}.items(): add('noname-'+name,source)
add('quote-stable-token', ': T [: 7 ;] ; T T = .')
add('quote-outer-local-restored', ': T { x -- } [: 7 ;] EXECUTE x ; 3 T . .')
add('quote-callback-throw', ': T 4 [: -123 THROW ;] CATCH ; T . .')
add('postpone-local-float', ': M { F: x -- } ]] x [[ ; IMMEDIATE : T [ 2.5e ] M ; T F.')
add('postpone-local-double', ': M { D: x -- } ]] x [[ ; IMMEDIATE : T [ 7. ] M ; T D.')
add('postpone-local-xt', ": M { XT: f -- } ]] f [[ ; IMMEDIATE : T [ ' DUP ] M ; 3 T . .")
add('postpone-escaped-string', r': M ]] S\" [[ ; IMMEDIATE : T M a\nb" ; T TYPE')
add('postpone-escaped-print', r': M ]] .\" [[ ; IMMEDIATE : T M a\nb" ; T')
add('postpone-counted-string', ': M ]] C" [[ ; IMMEDIATE : T M text" ; T COUNT TYPE')
add('postpone-abort-string', ": M ]] ABORT\" [[ ; IMMEDIATE : T -1 M fail\" ; ' T CATCH .")
add('postpone-print-paren', ': M ]] .( [[ ; IMMEDIATE : T M text) ; T')
results=[]
for name,source in cases:
    row={'case':name,'source':source}
    try:
        r=subprocess.run(cmd+[source+' DEPTH . BYE'],input=b'',capture_output=True,timeout=10)
        row.update(exit=r.returncode,stdout=r.stdout.decode(errors='replace'),stderr=r.stderr.decode(errors='replace'))
    except subprocess.TimeoutExpired:row['timeout']=True
    results.append(row)
folder=pathlib.Path('.work/p07b-check');folder.mkdir(parents=True,exist_ok=True)
(folder/'spec-probes.json').write_text(json.dumps({'cases':results},ensure_ascii=False,indent=2)+'\n')
for row in results:print(json.dumps(row,ensure_ascii=False))
