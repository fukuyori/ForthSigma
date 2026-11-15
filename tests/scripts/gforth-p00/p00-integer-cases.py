from p00_runner import BUILD, SOURCE
import csv,subprocess
from pathlib import Path
cases={}
for w in ['*/F','*/S','*/MODF','*/MODS']:
 q=(-14//3 if w.endswith('F') else -4);r=-14-q*3
 cases[w]=('-7 2 3 '+w+(' SWAP . .' if 'MOD' in w else ' .'), f'{r} {q}' if 'MOD' in w else str(q))
for w in ['/F','/S','/MODF','/MODS','MODF','MODS']:
 q=(-7//3 if w.endswith('F') else -2);r=-7-q*3
 cases[w]=('-7 3 '+w+(' SWAP . .' if w.startswith('/MOD') else ' .'), f'{r} {q}' if w.startswith('/MOD') else str(r if w.startswith('MOD') else q))
cases.update({'>POW2':('3 >POW2 .','4'),'ARSHIFT':('-8 1 ARSHIFT .','-4'),'CTZ':('8 CTZ .','3'),'DARSHIFT':('-8. 1 DARSHIFT D>S .','-4'),'DLSHIFT':('3. 1 DLSHIFT D>S .','6'),'DROL':('3. 1 DROL D>S .','6'),'DROR':('6. 1 DROR D>S .','3'),'DRSHIFT':('6. 1 DRSHIFT D>S .','3'),'DU/MOD':('10. 3 DU/MOD SWAP . .','1 3'),'LOG2':('8 LOG2 .','3'),'LROL':('$80000000 1 LROL .','1'),'LROR':('2 1 LROR .','1'),'MUX':('1 2 1 MUX .','3'),'POW2?':('8 POW2? .','-1'),'U*/':('10 2 3 U*/ .','6'),'U*/MOD':('10 2 3 U*/MOD SWAP . .','2 6'),'U/':('10 3 U/ .','3'),'U/MOD':('10 3 U/MOD SWAP . .','1 3'),'UD/MOD':('10. 3 UD/MOD D>S . .','3 1'),'UMOD':('10 3 UMOD .','1'),'WROL':('$8000 1 WROL .','1'),'WROR':('2 1 WROR .','1')})
rows=[]
for word,(src,exp) in cases.items():
 r=subprocess.run([str(BUILD/'gforth-ditc'), '-i', str(BUILD/'gforth.fi'),'-e',src+' BYE'],capture_output=True,text=True,timeout=10)
 actual=' '.join(r.stdout.split());ok=r.returncode==0 and actual==exp
 rows.append({'case_id':'P02a:'+word,'word':word,'input':src,'expected':exp,'gforth_actual':actual,'exit_code':r.returncode,'pass':ok})
 if not ok:print('MISMATCH',word,repr(exp),repr(actual),r.stderr[:100])
p=Path('docs/gforth-p00-runtime-cases.tsv');old=list(csv.DictReader(p.open(),delimiter='\t'));old=[r for r in old if not r['case_id'].startswith('P02a:')]
with p.open('w') as f:
 w=csv.DictWriter(f,fieldnames=list(dict.fromkeys(k for row in old+rows for k in row)),delimiter='\t',lineterminator='\n',quoting=csv.QUOTE_ALL);w.writeheader();w.writerows(old+rows)
print('Integer cases',len(rows),'passed',sum(r['pass'] for r in rows))
