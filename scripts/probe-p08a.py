#!/usr/bin/env python3
"""Observe P08a public words without relying on Gforth implementation internals."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True);a=p.parse_args();b=a.gforth_build.resolve();cmd=[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e'];cases=[]
def add(n,s):cases.append((n,s))
words='.ID .VOC COMPILE-ONLY? CONTEXT CS-VOCABULARY CS-WORDLIST CURRENT FIND-NAME-IN IN IN-WORDLIST LATESTNT MAP-VOCS MWORDS NAME>LINK NEXTNAME OBSOLETE? ROOT SEAL TABLE VLIST VOCS WORDLIST-WORDS XT>NAME'.split()
for w in words:
 add('lookup:'+w,f'S" {w}" FIND-NAME 0<> .');add('immediate:'+w,f'BL WORD {w} FIND NIP .')
add('id',': Foo 7 ; S" Foo" FIND-NAME .ID')
add('voc','WORDLIST CONSTANT W W .VOC')
add('compile-only',': F 7 ; S" F" FIND-NAME COMPILE-ONLY? . COMPILE-ONLY S" F" FIND-NAME COMPILE-ONLY? .')
add('obsolete',': F 7 ; S" F" FIND-NAME OBSOLETE? . S" DUP" FIND-NAME OBSOLETE? .')
add('current','CURRENT @ GET-CURRENT = . WORDLIST DUP CURRENT ! GET-CURRENT = .')
add('context',': P GET-ORDER >R CONTEXT @ = . R> 1- 0 ?DO DROP LOOP ; P')
add('context-store',': P GET-ORDER >R CONTEXT @ = . R> 1- 0 ?DO DROP LOOP ; WORDLIST >ORDER FORTH-WORDLIST CONTEXT ! P')
add('find-in','WORDLIST CONSTANT W W SET-CURRENT : Foo 7 ; FORTH-WORDLIST SET-CURRENT S" foo" W FIND-NAME-IN NAME>INTERPRET EXECUTE . S" missing" W FIND-NAME-IN .')
for kind in ['CS-WORDLIST','TABLE']:
 add('case:'+kind,f'{kind} CONSTANT W W SET-CURRENT : Foo 7 ; : foo 8 ; FORTH-WORDLIST SET-CURRENT S" Foo" W FIND-NAME-IN NAME>INTERPRET EXECUTE . S" foo" W FIND-NAME-IN NAME>INTERPRET EXECUTE . S" FOO" W FIND-NAME-IN .')
 add('redefine:'+kind,f'{kind} CONSTANT W W SET-CURRENT : Foo 7 ; : Foo 8 ; FORTH-WORDLIST SET-CURRENT S" Foo" W FIND-NAME-IN NAME>INTERPRET EXECUTE .')
add('cs-voc','CS-VOCABULARY W ALSO W DEFINITIONS : Foo 7 ; : foo 8 ; Foo . foo . FORTH DEFINITIONS PREVIOUS')
add('link','WORDLIST CONSTANT W W SET-CURRENT : A 1 ; : B 2 ; : C 3 ; FORTH-WORDLIST SET-CURRENT S" C" W FIND-NAME-IN DUP NAME>LINK NAME>STRING TYPE NAME>LINK NAME>LINK NAME>LINK .')
add('latest',': F 7 ; LATESTNT LATEST = . :NONAME 8 ; LATEST . LATESTNT NAME>STRING NIP . LATESTNT SWAP XT>NAME = .')
add('xt',': F 7 ; \' F XT>NAME S" F" FIND-NAME = . SYNONYM G F \' G XT>NAME NAME>STRING TYPE')
add('xt-anon',':NONAME 7 ; DUP XT>NAME NAME>INTERPRET = .')
add('nextname','S" Foo" NEXTNAME : 7 ; Foo . S" Bar" NEXTNAME 8 CONSTANT Bar .')
add('nextname-empty','S" " NEXTNAME : 7 ; LATEST 0<> . LATESTNT NAME>STRING NIP . LATESTXT EXECUTE .')
add('nextname-replace','S" Foo" NEXTNAME S" Bar" NEXTNAME : 8 ; Bar . S" Foo" FIND-NAME .')
add('nextname-noname','S" Foo" NEXTNAME NONAME : 7 ; LATEST . S" Foo" FIND-NAME 0<> .')
add('noname-nextname','NONAME S" Foo" NEXTNAME : 7 ; Foo .')
add('nextname-colon-anon','S" Foo" NEXTNAME :NONAME 7 ; DROP : 8 ; Foo .')
add('nextname-runtime',': MAKE S" Foo" NEXTNAME : ; MAKE 7 ; Foo .')
add('in-wordlist','WORDLIST CONSTANT W GET-CURRENT CONSTANT OLD W IN-WORDLIST : F [ GET-CURRENT OLD = . ] 7 ; GET-CURRENT OLD = . S" F" W FIND-NAME-IN NAME>INTERPRET EXECUTE .')
add('in','VOCABULARY W GET-CURRENT CONSTANT OLD IN W : F 7 ; GET-CURRENT OLD = . ALSO W F . PREVIOUS')
add('in-constant','WORDLIST CONSTANT W IN W : F 7 ; S" F" W FIND-NAME-IN NAME>INTERPRET EXECUTE .')
add('in-nondefining','WORDLIST CONSTANT W W IN-WORDLIST GET-CURRENT W = .')
add('in-throw',': BAD -123 THROW ; WORDLIST CONSTANT W : CALL W IN-WORDLIST ; : R S" BAD" [\'] CALL EXECUTE-PARSING ; GET-CURRENT \' R CATCH . GET-CURRENT = .')
add('seal',': CHECK SEAL GET-ORDER 1 = . FORTH-WORDLIST = . FORTH-WORDLIST 1 SET-ORDER ; ALSO CHECK')
add('root',': CHECK ROOT GET-ORDER >R CONTEXT @ = . R> 1- 0 ?DO DROP LOOP ; CHECK FORTH')
add('map', 'VARIABLE N : COUNT-W DROP 1 N +! ; \' COUNT-W MAP-VOCS N @ 0> .')
add('map-new', 'VARIABLE A VARIABLE B : HIT DUP A @ = SWAP B @ = OR IF 1 ELSE 0 THEN ; WORDLIST A ! CS-WORDLIST B ! : P08SCAN HIT + ; 0 \' P08SCAN MAP-VOCS .')
add('wordlist-words','WORDLIST CONSTANT W W SET-CURRENT : Alpha 1 ; : Beta 2 ; FORTH-WORDLIST SET-CURRENT W WORDLIST-WORDS')
add('vlist','WORDLIST CONSTANT W W SET-CURRENT : Alpha 1 ; : Beta 2 ; FORTH-WORDLIST SET-CURRENT W >ORDER VLIST PREVIOUS')
add('mwords','WORDLIST CONSTANT W W SET-CURRENT : Alpha 1 ; : Beta 2 ; : AlphaBeta 3 ; FORTH-WORDLIST SET-CURRENT W >ORDER MWORDS Alpha')
add('mwords-empty','WORDLIST CONSTANT W W SET-CURRENT : Alpha 1 ; : Beta 2 ; FORTH-WORDLIST SET-CURRENT : P08LIST W >ORDER S" MWORDS" EVALUATE PREVIOUS ; P08LIST')
add('vocs','VOCABULARY Named VOCS')
for w in words:add('obsolete:'+w,f'S" {w}" FIND-NAME OBSOLETE? .')
add('context-nth',': P GET-ORDER >R CONTEXT @ = . R> 1- 0 ?DO DROP LOOP ; P')
add('in-throw-fixed',": BAD -123 THROW ; WORDLIST CONSTANT W : CALL W IN-WORDLIST ; : R S\" BAD\" ['] CALL EXECUTE-PARSING ; GET-CURRENT ' R CATCH . GET-CURRENT = .")
add('empty-name-link','S" " NEXTNAME : 7 ; LATEST 0<> . LATESTNT NAME>STRING NIP .')
for w in ['IF','THEN','DO','LOOP','LITERAL','[COMPILE]','COMPILE,','RECURSIVE','[:',';]',']]','CS-PICK','CS-ROLL','CS-DROP','DONE','TO','ACTION-OF','EXIT','RECURSE','POSTPONE,']:
 add('compile-only:'+w,f'S" {w}" FIND-NAME COMPILE-ONLY? .')
for w in [';', 'ELSE', 'AHEAD', 'BEGIN', 'UNTIL', 'AGAIN', 'WHILE', 'REPEAT', '?DO', '+LOOP', 'LEAVE', 'UNLOOP', '?LEAVE', '?EXIT', 'FLITERAL', '2LITERAL', 'SLITERAL', 'DOES>', 'CASE', 'OF', 'ENDOF', 'ENDCASE', '?OF', 'CONTOF', 'NEXT-CASE', 'DEFERS', '+DO', 'U+DO', '-DO', 'U-DO', '-[DO', 'U-[DO', '-LOOP', 'FOR', 'NEXT', 'MEM+DO', 'MEM-DO', '?DUP-IF', '?DUP-0=-IF']:
 add('compile-only:'+w,f'S" {w}" FIND-NAME COMPILE-ONLY? .')
folder=pathlib.Path('.work/p08a-check');folder.mkdir(parents=True,exist_ok=True);results=[]
line_file=(folder/'mwords-lines.fs').resolve();line_file.write_text('MWORDS\nPREVIOUS\n42\n')
add('mwords-file',f'WORDLIST CONSTANT W W SET-CURRENT : Alpha 1 ; FORTH-WORDLIST SET-CURRENT W >ORDER INCLUDE {line_file} .')
for name,source in cases:
 row={'case':name,'source':source}
 try:
  r=subprocess.run(cmd+[source+' DEPTH . BYE'],input=b'',capture_output=True,timeout=3);row.update(exit=r.returncode,stdout=r.stdout.decode(errors='replace'),stderr=r.stderr.decode(errors='replace'))
 except subprocess.TimeoutExpired:row['timeout']=True
 results.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
(folder/'spec-probes.json').write_text(json.dumps({'cases':results},ensure_ascii=False,indent=2)+'\n')
