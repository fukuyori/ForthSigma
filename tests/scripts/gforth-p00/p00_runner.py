import csv,subprocess,os
from pathlib import Path
BUILD=Path(os.environ.get('GFORTH_P00_BUILD', '.work/gforth-audit/gforth-build')).resolve()
SOURCE=Path(os.environ.get('GFORTH_P00_SOURCE', '/Users/fuk/source/forth/gforth')).resolve()
def run(prefix,cases):
 rows=[]
 for case in cases:
  word,src,expected=case[:3]
  stdin=case[3] if len(case)>3 else "\n"*1000
  cmd=[str(BUILD/'gforth-ditc'),'-p',str(BUILD)+':~+','-i',str(BUILD/'gforth.fi'),'-e',src+' DEPTH 0= . FDEPTH 0= . BYE']
  r=subprocess.run(cmd,capture_output=True,input=stdin,text=True,timeout=15,env={**os.environ,"EDITOR":"true","TZ":"UTC"})
  actual=' '.join(r.stdout.split());exp=expected+' -1 -1';ok=r.returncode==0 and (expected[9:] in actual and actual.endswith('-1 -1') if expected.startswith('CONTAINS:') else actual==exp)
  rows.append({'case_id':prefix+':'+word,'stdin':('LF*1000' if stdin=='\n'*1000 else stdin),'word':word,'input':src,'expected':exp,'gforth_actual':actual,'exit_code':r.returncode,'pass':ok})
  if not ok:print('MISMATCH',word,repr(exp),repr(actual),r.stderr[:180])
 p=Path('docs/gforth-p00-runtime-cases.tsv');old=list(csv.DictReader(p.open(),delimiter='\t'));old=[r for r in old if not r['case_id'].startswith(prefix+':')]
 with p.open('w') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]),delimiter='\t',lineterminator='\n',quoting=csv.QUOTE_ALL);w.writeheader();w.writerows(old+rows)
 print(prefix,len(rows),'cases',sum(r['pass'] for r in rows),'passed')
