from p00_runner import BUILD, SOURCE
import csv,subprocess
from pathlib import Path
cases={
'0<=':[('0 0<= .','-1'),('1 0<= .','0'),('-1 0<= .','-1')],
'D0<=':[('0. D0<= .','-1'),('1. D0<= .','0')],
'D0<>':[('0. D0<> .','0'),('1. D0<> .','-1')],
'D0>':[('1. D0> .','-1'),('0. D0> .','0')],
'D0>=':[('0. D0>= .','-1'),('-1. D0>= .','0')],
'D<=':[('1. 2. D<= .','-1'),('2. 1. D<= .','0')],
'D<>':[('1. 2. D<> .','-1'),('1. 1. D<> .','0')],
'D>':[('2. 1. D> .','-1'),('1. 2. D> .','0')],
'D>=':[('1. 1. D>= .','-1'),('1. 2. D>= .','0')],
'DU<=':[('0. -1. DU<= .','-1'),('-1. 0. DU<= .','0')],
'DU>':[('-1. 0. DU> .','-1'),('0. -1. DU> .','0')],
'DU>=':[('0. 0. DU>= .','-1'),('0. -1. DU>= .','0')],
'U<=':[('0 -1 U<= .','-1'),('-1 0 U<= .','0')],
'U>=':[('-1 0 U>= .','-1'),('0 -1 U>= .','0')],
'UMIN':[('0 -1 UMIN .','0'),('4 3 UMIN .','3')],
'UMAX':[('0 -1 UMAX .','-1'),('4 3 UMAX .','4')],
'2NIP':[('1 2 3 4 2NIP SWAP . .','3 4')],
'2TUCK':[('1 2 3 4 2TUCK . . . . . .','4 3 2 1 4 3')],
'THIRD':[('1 2 3 THIRD . . . .','1 3 2 1')],
'FOURTH':[('1 2 3 4 FOURTH . . . . .','1 4 3 2 1')],
'RDROP':[(': TEST 1 >R RDROP ; TEST DEPTH .','0')],
'2RDROP':[(': TEST 1 2 2>R 2RDROP ; TEST DEPTH .','0')],
'2,':[('HERE 11 22 2, 2@ SWAP . .','11 22')],
'ROL':[('1 1 ROL .','2'),('1 0 ROL .','1')],
'ROR':[('2 1 ROR .','1'),('2 0 ROR .','2')],
}
rows=[]
for word,tests in cases.items():
 for i,(source,expected) in enumerate(tests,1):
  r=subprocess.run([str(BUILD/'gforth-ditc'), '-i', str(BUILD/'gforth.fi'),'-e',source+' BYE'],cwd=SOURCE,capture_output=True,text=True,timeout=10)
  actual=' '.join(r.stdout.split());ok=r.returncode==0 and actual==expected
  rows.append({'case_id':word+':'+str(i),'word':word,'input':source,'expected':expected,'gforth_actual':actual,'exit_code':r.returncode,'pass':ok})
  if not ok:print('MISMATCH',word,expected,actual,r.stderr[:150])
with open('docs/gforth-p00-runtime-cases.tsv','w') as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]),delimiter='\t',lineterminator='\n',quoting=csv.QUOTE_ALL);w.writeheader();w.writerows(rows)
print(len(cases),'words,',len(rows),'cases,',sum(r['pass'] for r in rows),'passed')
