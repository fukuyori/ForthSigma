from p00_runner import BUILD, SOURCE
import csv,subprocess
from pathlib import Path
c={}
def add(n,s,e='-1'):c[n]=(s,e)
for n,value in [('/W',2),('/L',4),('/X',8),('FLOAT',8)]:add(n,n+' .',str(value))
for n in ['CELL/','FLOAT/','DFLOAT/']:add(n,'24 '+n+' .','3')
add('SFLOAT/','24 SFLOAT/ .','6');add('CHAR-','4 CHAR- .','3')
for n,width in [('W',2),('L',4),('X',8)]:
 add(n+'@','CREATE B 16 ALLOT 123 B '+n+'! B '+n+'@ .','123')
 add(n+'!','CREATE B 16 ALLOT 123 B '+n+'! B '+n+'@ .','123')
 add(n+',','HERE 123 '+n+', '+n+'@ .','123')
 add(n+'ALIGN','1 ALLOT '+n+'ALIGN HERE '+str(width)+' MOD .','0')
 add(n+'ALIGNED','3 '+n+'ALIGNED '+str(width)+' MOD .','0')
 add(n+'LE','1 '+n+'LE .','1')
 add(n+'BE','1 '+n+'BE .',str(1 << ((width-1)*8)))
 add(n+'FIELD:','0 '+n+'FIELD: F .',str(width))
 add(n+'>S',str((1<<(width*8))-1)+' '+n+'>S .','-1')
add('C>S','255 C>S .','-1')
add('*ALIGNED','3 8 *ALIGNED .','8');add('*ALIGN','1 ALLOT 8 *ALIGN HERE 8 MOD .','0')
add('MAXALIGN','1 ALLOT MAXALIGN HERE MAXALIGNED HERE = .')
add('MAXALIGNED','HERE MAXALIGNED DUP MAXALIGNED = .')
add('!@','VARIABLE V 4 V ! 7 V !@ . V @ .','4 7')
add('+!@','VARIABLE V 4 V ! 7 V +!@ . V @ .','4 11')
add('2FIELD:','0 2FIELD: F .','16')
add('A,','HERE DUP A, @ HERE CELL- = .')
add('ACONSTANT','HERE DUP ACONSTANT A A = .')
add('AVARIABLE','AVARIABLE A A @ .','0')
add('MEM,','S" abc" HERE >R MEM, R> 3 S" abc" COMPARE .','0')
add('SAVE-MEM-DICT','S" abc" SAVE-MEM-DICT S" abc" COMPARE .','0')
add('SAVE-MEM','S" abc" SAVE-MEM OVER >R S" abc" COMPARE . R> FREE THROW','0')
add('TH','CREATE B 3 CELLS ALLOT B 2 TH B 2 CELLS + = .')
for n in ['TH!','TH@']:add(n,'CREATE B 3 CELLS ALLOT 7 B 2 TH! B 2 TH@ .','7')
add('XD!','CREATE B 16 ALLOT 11. B XD! B XD@ D>S .','11')
add('XD@','CREATE B 16 ALLOT 11. B XD! B XD@ D>S .','11')
add('XD,','HERE 11. XD, XD@ D>S .','11')
add('XD>S','11 XD>S D>S .','11')
add('XDLE','11. XDLE D>S .','11')
add('XDBE','1. XDBE D>S .','72057594037927936')
add('BUFFER%','BUFFER% . .','24 8')
add('INIT-BUFFER','CREATE B BUFFER% %SIZE ALLOT B INIT-BUFFER B @ .','0')
add('FREE-MEM-VAR','2VARIABLE V 8 ALLOCATE THROW 8 V 2! V FREE-MEM-VAR V 2@ OR .','0')
rows=[]
for word,(src,exp) in c.items():
 r=subprocess.run([str(BUILD/'gforth-ditc'), '-i', str(BUILD/'gforth.fi'),'-e',src+' DEPTH 0= . BYE'],capture_output=True,text=True,timeout=10)
 actual=' '.join(r.stdout.split());ok=r.returncode==0 and actual==exp+' -1'
 rows.append({'case_id':'P03:'+word,'word':word,'input':src,'expected':exp+' -1','gforth_actual':actual,'exit_code':r.returncode,'pass':ok})
 if not ok:print('MISMATCH',word,repr(exp),repr(actual),r.stderr[:130])
p=Path('docs/gforth-p00-runtime-cases.tsv');old=list(csv.DictReader(p.open(),delimiter='\t'));old=[r for r in old if not r['case_id'].startswith('P03:')]
with p.open('w') as f:
 w=csv.DictWriter(f,fieldnames=list(dict.fromkeys(k for row in old+rows for k in row)),delimiter='\t',lineterminator='\n',quoting=csv.QUOTE_ALL);w.writeheader();w.writerows(old+rows)
print('Memory cases',len(rows),'passed',sum(r['pass'] for r in rows))
