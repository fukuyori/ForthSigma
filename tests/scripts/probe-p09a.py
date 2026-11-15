#!/usr/bin/env python3
"""Observe P09a diagnostic APIs through the designated Gforth executable."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True);a=p.parse_args();b=a.gforth_build.resolve();cmd=[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e'];cases=[]
def add(n,s):cases.append((n,s))
words=[')','?ERRNO-THROW','?IOR','ASSERT-LEVEL','ASSERT0(','ASSERT1(','ASSERT2(','ASSERT3(','CATCH-NOBT','EXCEPTION','EXCEPTIONS','FAST-THROW','NOTHROW','WARNING"','WARNINGS']
for w in words:
 if '"' not in w:add('lookup:'+w,f'S" {w}" FIND-NAME 0<> .');add('compile-only:'+w,f'S" {w}" FIND-NAME COMPILE-ONLY? .')
 add('immediate:'+w,f'BL WORD {w} FIND NIP .')
add('defaults','ASSERT-LEVEL @ . WARNINGS @ .')
for level in [-1,0,1,2,3,9]:
 for which in range(4):add(f'assert:{level}:{which}',f'{level} ASSERT-LEVEL ! : T 10 ASSERT{which}( 1+ TRUE ) ; T .')
add('assert-ordinary-level','-1 ASSERT-LEVEL ! : T ASSERT( UNKNOWN ) 7 ; T .')
add('assert-compile-fixed','0 ASSERT-LEVEL ! : T ASSERT1( UNKNOWN ) 7 ; 3 ASSERT-LEVEL ! T .')
add('assert-interpret','ASSERT0( TRUE ) 7 .')
add('assert-false',': T ASSERT0( FALSE ) ; \' T CATCH .')
add('assert-missing',': T ASSERT0( TRUE')
add('assert-disabled-no-parse','-1 ASSERT-LEVEL ! : T ASSERT0( IF UNKNOWN BAD 1 ) 7 ; T .')
add('assert-nested',': T ASSERT0( ASSERT1( TRUE ) TRUE ) ; T')
add('close-alone',': T S" )" EVALUATE ; \' T CATCH .')
add('nobt',': BAD -10 THROW ; 7 \' BAD CATCH-NOBT . . NOTHROW 8 .')
add('nobt-nested',': BAD -123 THROW ; : INNER [\'] BAD CATCH-NOBT ; \' INNER CATCH . .')
add('nobt-alias', 'SYNONYM CN CATCH-NOBT : BAD -123 THROW ; : T [\'] BAD CN ; T .')
add('fast',': BAD -123 FAST-THROW ; 7 \' BAD CATCH . .')
add('fast-nobt',': BAD -123 FAST-THROW ; \' BAD CATCH-NOBT .')
add('nothrow','1 NOTHROW 2 . .')
add('exception-code','S" alpha" EXCEPTION DUP 0< . S" beta" EXCEPTION - .')
add('exception-catch','S" alpha" EXCEPTION CONSTANT E : BAD E THROW ; \' BAD CATCH E = .')
add('exception-latest',': P 7 ; LATEST S" alpha" EXCEPTION DROP LATEST = .')
add('exception-copy','S" alpha" 2DUP EXCEPTION >R 0 FILL R> 0< .')
add('exceptions-range',': MSG DROP S" group" ; \' MSG 3 EXCEPTIONS S" next" EXCEPTION - .')
add('exceptions-zero',': MSG DROP S" group" ; \' MSG 0 EXCEPTIONS S" next" EXCEPTION = .')
add('exceptions-negative',': MSG DROP S" group" ; : BAD [\'] MSG -1 EXCEPTIONS DROP ; \' BAD CATCH .')
for x in [0,1,2,-2]:add('ior:'+str(x),f'{x} ?IOR')
add('errno-false','0 ?ERRNO-THROW')
folder=pathlib.Path('.work/p09a-check');folder.mkdir(parents=True,exist_ok=True);missing=(folder/'must-not-exist-p09a-file').resolve();assert not missing.exists()
for word in ['?IOR','?ERRNO-THROW']:
 add('errno-missing:'+word,f': BAD S" {missing}" R/O OPEN-FILE 2DROP -1 {word} ; \' BAD CATCH .')
for level in [0,-1,-2,-3,-4,1]:
 add('warning:'+str(level),f'{level} WARNINGS ! : T TRUE WARNING" sample" 7 ; \' T CATCH .')
 add('redefine:'+str(level),f'{level} WARNINGS ! : SAMPLE-X 1 ; : SAMPLE-X 2 ; SAMPLE-X .')
add('warning-false',': T FALSE WARNING" sample" 7 ; T .')
add('warning-interpret','TRUE WARNING" sample" 7 .')
add('warning-escape',': T TRUE WARNING" a\\nb" ; T')
add('message-simple','S" alpha-custom" EXCEPTION THROW')
add('message-group',': MSG CASE 0 OF S" first-custom" ENDOF 1 OF S" second-custom" ENDOF S" other" ROT ENDCASE ; \' MSG 3 EXCEPTIONS 1- THROW')
rows=[]
for name,source in cases:
 row={'case':name,'source':source}
 try:
  r=subprocess.run(cmd+[source+' DEPTH . BYE'],capture_output=True,input=b'',timeout=3);row.update(exit=r.returncode,stdout=r.stdout.decode(errors='replace'),stderr=r.stderr.decode(errors='replace'))
 except subprocess.TimeoutExpired:row['timeout']=True
 rows.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
(folder/'spec-probes.json').write_text(json.dumps({'cases':rows},ensure_ascii=False,indent=2)+'\n')
