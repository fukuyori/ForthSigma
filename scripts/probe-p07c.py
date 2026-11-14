#!/usr/bin/env python3
"""Observe all P07c words with bounded iteration, including invalid stride probes."""
import argparse
import json
import pathlib
import subprocess
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True)
a=p.parse_args();b=a.gforth_build.resolve()
cmd=[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']
cases=[]
def add(name,source):cases.append((name,source))
words=['+DO','-DO','-LOOP','-[DO','?DUP-0=-IF','?DUP-IF','ARRAY>MEM','CS-DROP','DELTA-I','DONE','FOR',"I'",'MEM+DO','MEM-DO','NEXT','U+DO','U-DO','U-[DO']
for w in words:
    add('lookup:'+w,f'S" {w}" FIND-NAME DUP 0<> . NAME>INTERPRET 0<> .')
    add('immediate:'+w,f'BL WORD {w} FIND NIP .')
# Every potentially wrapping loop has an explicit LEAVE after eight bodies.
prefix='VARIABLE P07C-STEPS : P07C-HIT 1 P07C-STEPS +! P07C-STEPS @ 8 >= ; '
for opener in ('+DO','U+DO','-DO','U-DO','-[DO','U-[DO'):
    end='LOOP' if opener in ('+DO','U+DO') else '-1 +LOOP'
    for limit,start in [(3,0),(0,3),(0,0),(1,-1),(-1,1),(-2,-4),(-4,-2),(9223372036854775807,9223372036854775806),(-9223372036854775808,9223372036854775807)]:
        add(f'loop:{opener}:{limit}:{start}',prefix+f': T {limit} {start} {opener} I . P07C-HIT IF LEAVE THEN {end} ; T')
for step in (1,2,3,0,-1):
    add('minus-loop:'+str(step),prefix+f': T 0 5 DO I . P07C-HIT IF LEAVE THEN {step} -LOOP ; T')
for n in (0,1,3,-1):
    add('for:'+str(n),prefix+f': T {n} FOR I . P07C-HIT IF LEAVE THEN NEXT ; T')
add('for-nested',': T 2 FOR 1 FOR J . I . NEXT NEXT ; T')
add('for-unloop-exit',': T 3 FOR I . UNLOOP EXIT NEXT ; T')
add('for-throw',": T 3 FOR -123 THROW NEXT ; ' T CATCH .")
add('loop-throw',": T 3 0 +DO -123 THROW LOOP ; ' T CATCH .")
for opener,ending in [('+DO','LOOP'),('-[DO','-1 +LOOP'),('U+DO','LOOP')]:
    limit,start=(3,0) if opener!='-[DO' else (0,3)
    add('limit:'+opener,f': T {limit} {start} {opener} I . I\' . DELTA-I . {ending} ; T')
add('limit-helper',": H I . I' . DELTA-I . ; : T 3 0 DO H LOOP ; T")
add('for-limit-observation',": T 0 FOR I . I' . DELTA-I . NEXT ; T")
for opener in ('MEM+DO','MEM-DO'):
    for length,stride in [(0,1),(1,1),(6,2),(5,2),(1,3),(8,4),(4,0),(4,-1)]:
        add(f'memory:{opener}:{length}:{stride}',prefix+f': T 100 {length} {stride} {opener} I 100 - . P07C-HIT IF LEAVE THEN LOOP ; T')
    add('memory-limit:'+opener,f': T 100 6 2 {opener} I 100 - . I\' 100 - . DELTA-I . LOOP ; T')
add('memory-values','CREATE A 1 , 3 , 7 , : T A 3 CELL ARRAY>MEM MEM+DO I @ . LOOP A 3 CELL ARRAY>MEM MEM-DO I @ . LOOP ; T')
for count,size in [(0,8),(3,8),(7,3),(-1,2),(9223372036854775807,8)]:
    add(f'array:{count}:{size}',f'{count} {size} ARRAY>MEM . .')
for word in ('?DUP-IF','?DUP-0=-IF'):
    for n in (0,1,-1,3):add('conditional:'+word+':'+str(n),f': T {word} 11 ELSE 22 THEN ; {n} T .S')
add('cs-drop-orig',': T IF [ 0 CS-PICK CS-DROP ] 7 THEN ; -1 T . 0 T')
add('cs-drop-dest',': T BEGIN [ 0 CS-PICK CS-DROP ] 1 UNTIL 7 ; T .')
add('done-leave',': T 3 0 DO I . LEAVE DONE UNLOOP ; T')
add('done-unloop',': T 3 0 DO I . UNLOOP DONE ; T')
add('loop-locals',': T { n -- } n 0 +DO { x -- } x I + . LOOP ; 10 20 2 T')
for source in (': T CS-DROP ;', ': T DONE ;', ': T NEXT ;', ': T -LOOP ;'):
    add('malformed:'+source,source)
add('for-limit', ": T 3 FOR I . I' . DELTA-I . NEXT ; T")
add('done-after', ': T 3 0 DO I . LEAVE DONE UNLOOP 99 . ; T')
add('minus-do-minus-loop', ': T 0 3 -DO I . 1 -LOOP ; T')
for opener in ('MEM+DO','MEM-DO'):
    for base,length,stride in [(9223372036854775806,4,1),(-2,4,1),(100,-1,1),(100,4,9223372036854775807)]:
        add(f'memory-boundary:{opener}:{base}:{length}:{stride}',prefix+f': T {base} {length} {stride} {opener} I {base} - . P07C-HIT IF LEAVE THEN LOOP ; T')
results=[]
for name,source in cases:
    row={'case':name,'source':source}
    try:
        r=subprocess.run(cmd+[source+' DEPTH . BYE'],input=b'',capture_output=True,timeout=3)
        row.update(exit=r.returncode,stdout=r.stdout.decode(errors='replace'),stderr=r.stderr.decode(errors='replace'))
    except subprocess.TimeoutExpired:row['timeout']=True
    results.append(row)
folder=pathlib.Path('.work/p07c-check');folder.mkdir(parents=True,exist_ok=True)
(folder/'spec-probes.json').write_text(json.dumps({'cases':results},ensure_ascii=False,indent=2)+'\n')
for r in results:print(json.dumps(r,ensure_ascii=False))
