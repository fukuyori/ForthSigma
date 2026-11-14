#!/usr/bin/env python3
"""Probe safe P09c return-stack cases in the designated Gforth."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--gforth-build',required=True,type=pathlib.Path);a=p.parse_args();b=a.gforth_build.resolve();cmd=[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e'];cases=[]
def add(n,s):cases.append((n,s))
for w in ['F>R','FR>','FR@',"R'@",'RPICK']:add('lookup:'+w,f'S" {w}" FIND-NAME 0<> .');add('immediate:'+w,f'BL WORD {w} FIND NIP .')
add('float-round',': T 1.25e F>R FR@ F. FR> F. ; T FDEPTH .')
add('float-pair',': T 1.25e -2.5e F>R F>R FR> F. FR> F. ; T')
add('float-cell',': T 1.25e F>R 77 >R R> . FR@ F. FR> F. ; T')
add('r-tick',": T 11 >R 22 >R R'@ . R@ . R> . R> . ; T")
for i in [0,1,2]:add('rpick:'+str(i),f': T 11 >R 22 >R 33 >R {i} RPICK . R> DROP R> DROP R> DROP ; T')
add('loop',': T 3 0 DO I S>F F>R FR@ F>S FR> F>S + LOOP ; T')
add('catch',": BAD 1.25e F>R 77 >R -123 THROW ; : T 42 >R ['] BAD CATCH . R> . ; T")
add('locals',': T { n -- r } n S>F F>R FR@ F>S FR> FDROP ; 7 T')
add('recursion',': T DUP 0= IF DROP EXIT THEN DUP S>F F>R 1- RECURSE FR> F>S ; 4 T')
folder=pathlib.Path('.work/p09c-check');folder.mkdir(parents=True,exist_ok=True);rows=[]
for name,s in cases:
 r=subprocess.run(cmd+[s+' DEPTH . BYE'],input=b'',capture_output=True,timeout=3);row=dict(case=name,source=s,exit=r.returncode,stdout=r.stdout.decode(errors='replace'),stderr=r.stderr.decode(errors='replace'));rows.append(row);print(json.dumps(row),flush=True)
(folder/'spec-probes.json').write_text(json.dumps({'cases':rows},indent=2)+'\n')
