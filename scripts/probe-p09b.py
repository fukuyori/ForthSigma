#!/usr/bin/env python3
"""Measure P09b through the designated Gforth, without copying its implementation."""
import argparse,json,pathlib,subprocess,os
p=argparse.ArgumentParser();p.add_argument('--gforth-build',required=True,type=pathlib.Path);a=p.parse_args();b=a.gforth_build.resolve();folder=pathlib.Path('.work/p09b-check');folder.mkdir(parents=True,exist_ok=True)
source=folder.resolve()/'navigation.fs';source.write_text('\\ P09b navigation fixture\n: NAV-ALPHA 11 ;\n: NAV-BETA NAV-ALPHA 2 + ;\n: NAV-GAMMA NAV-BETA ;\n'+'\\ padding\n'*30)
editor=folder.resolve()/'editor';editor.write_text('#!/bin/sh\nprintf "EDITOR %s\\n" "$*"\n');editor.chmod(0o755)
env=dict(os.environ,EDITOR=str(editor),VISUAL=str(editor));cmd=[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e'];cases=[]
def add(n,s):cases.append((n,s))
words=['...','AFTER-LOCATE','B','BEFORE-LOCATE','BROWSE','BT','BW','CLEARSTACK','CLEARSTACKS','EDIT','EXPAND-WHERE','F.S-PRECISION','FANCY-AFTER-L','FCLEARSTACK','G','GG','L','LL','MAXDEPTH-.S','N','NT','NW','PREPEND-WHERE','SHORT-WHERE','TT','UNUSED-WORDS','WHEREG','WW','XT-LOCATE','\\G']
for w in words:
 add('lookup:'+w,f'S" {w}" FIND-NAME 0<> .');add('immediate:'+w,f'BL WORD {w} FIND NIP .')
add('defaults','BEFORE-LOCATE . AFTER-LOCATE . F.S-PRECISION . MAXDEPTH-.S @ .')
for n in [0,1,3,9,20,-1]:add('dot-s:'+str(n),f'{n} MAXDEPTH-.S ! 10 20 30 40 .S')
for n in [0,3,8,14,20,-1]:add('f-dot-s:'+str(n),f'{n} TO F.S-PRECISION 1.25e -12.5e F.S')
add('clear-data','1 2 1.25e CLEARSTACK DEPTH . FDEPTH . FCLEARSTACK')
add('clear-float','1 2 1.25e FCLEARSTACK DEPTH . FDEPTH . CLEARSTACK')
add('clear-both','1 2 1.25e CLEARSTACKS DEPTH . FDEPTH .')
add('clear-return',': T 123 >R 1 2 CLEARSTACKS R> ; T .')
add('ellipsis-empty','...')
add('ellipsis-values','10 20 30 ...')
add('slash-g','1 \\G comment ignored 2\n3')
for n,s in [('before-set','1 TO BEFORE-LOCATE 2 TO AFTER-LOCATE BEFORE-LOCATE . AFTER-LOCATE .'),('fancy','FANCY-AFTER-L'),('bt-empty','BT'),('tt-empty','0 TT'),('nt-empty','NT'),('locate-invalid','-1 XT-LOCATE'),('l-empty','L'),('ww-empty','0 WW'),('bw-empty','BW'),('nw-empty','NW')]:add(n,s)
for n,s in [('locate','LOCATE NAV-BETA'),('xt-locate',"' NAV-BETA XT-LOCATE"),('locate-next','LOCATE NAV-BETA N B L'),('browse','BROWSE NAV-'),('browse-select','BROWSE NAV- 0 WW'),('browse-next','BROWSE NAV- NW'),('browse-back','BROWSE NAV- BW'),('where','WHERE NAV-ALPHA'),('where-select','WHERE NAV-ALPHA 0 WW NW BW'),('where-prepend','PREPEND-WHERE WHERE NAV-ALPHA'),('where-expand','EXPAND-WHERE WHERE NAV-ALPHA'),('where-short','SHORT-WHERE WHERE NAV-ALPHA'),('edit','EDIT NAV-BETA'),('g','LOCATE NAV-BETA G'),('gg','WHERE NAV-ALPHA GG 0 WW'),('ll','WHERE NAV-ALPHA LL 0 WW'),('whereg','WHEREG NAV-ALPHA'),('unused','UNUSED-WORDS')]:add(n,f'INCLUDE {source} '+s)
rows=[]
# Previously observed invalid settings caused memory reads/abort traps. Keep their
# sources for Sigma policy checks, but do not repeat the unsafe reference runs.
unsafe={'dot-s:-1','f-dot-s:0','f-dot-s:-1','locate-invalid'}
for name,s in cases:
 row={'case':name,'source':s}
 if name in unsafe:
  row['skipped_unsafe']=True;rows.append(row);print(json.dumps(row),flush=True);continue
 try:
  r=subprocess.run(cmd+[s+' DEPTH . BYE'],env=env,capture_output=True,input=b'',timeout=5);row.update(exit=r.returncode,stdout=r.stdout.decode(errors='replace'),stderr=r.stderr.decode(errors='replace'))
 except subprocess.TimeoutExpired:row['timeout']=True
 rows.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
(folder/'spec-probes.json').write_text(json.dumps({'cases':rows},ensure_ascii=False,indent=2)+'\n')
