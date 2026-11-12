from p00_runner import BUILD, SOURCE
import csv,subprocess,tempfile
from pathlib import Path
base=Path('.work/gforth-audit').resolve()
exe=str(BUILD/'gforth-ditc')
image=str(BUILD/'gforth.fi')
tests=[
('BLK','BLK @ .','0'),('BLOCK','1 BLOCK C@ .','55'),
('BUFFER','1 BUFFER C@ .','55'),
('UPDATE','1 BLOCK 65 OVER C! UPDATE SAVE-BUFFERS EMPTY-BUFFERS 1 BLOCK C@ .','65'),
('SAVE-BUFFERS','1 BLOCK 66 OVER C! UPDATE SAVE-BUFFERS EMPTY-BUFFERS 1 BLOCK C@ .','66'),
('FLUSH','1 BLOCK 67 OVER C! UPDATE FLUSH 1 BLOCK C@ .','67'),
('EMPTY-BUFFERS','1 BLOCK 68 OVER C! UPDATE EMPTY-BUFFERS 1 BLOCK C@ .','55'),
('SCR','SCR @ .','0'),('LIST','1 LIST SCR @ .',None),
('THRU','1 2 THRU','7 8'),('LOAD','1 LOAD','7'),
('LOAD-zero','0 \' LOAD CATCH .','-35'),
('BLOCK-limit',': BAD $200000 BLOCK DROP ; \' BAD CATCH .','-35'),
('K-SHIFT-MASK','HEX K-SHIFT-MASK .','10000000'),
('K-ALT-MASK','HEX K-ALT-MASK .','20000000'),
('K-CTRL-MASK','HEX K-CTRL-MASK .','40000000'),
('EKEY>FKEY','K-UP EKEY>FKEY . K-UP = . 65 EKEY>FKEY . .','-1 -1 0 65'),
('LOAD-input','3 LOAD BLK @ .','3 2 1024 0'),
('LOAD-throw',': BAD 4 LOAD ; \' BAD CATCH . BLK @ .','-99 0'),
]
rows=[]
for word,src,exp in tests:
 with tempfile.TemporaryDirectory(dir=base) as td:
  file=Path(td)/'blocks.fb'
  blocks=['','7 .','8 .','BLK @ . SOURCE-ID . SOURCE NIP .','-99 THROW']
  file.write_bytes(b''.join(b.encode().ljust(1024,b' ') for b in blocks))
  source='USE '+str(file)+' '+src+' BYE'
  r=subprocess.run([exe,'-i',image,'-e',source],capture_output=True,text=True,timeout=10)
  actual=' '.join(r.stdout.split())
  if exp is None:ok=r.returncode==0 and actual.startswith('Screen 1 not modified') and actual.endswith('1');expected='Screen 1 not modified の見出し、0〜15行、末尾SCR=1'
  else:expected=exp;ok=r.returncode==0 and actual==exp
  rows.append({'case_id':'S01:'+word,'word':word,'input':src,'expected':expected,'gforth_actual':actual,'exit_code':r.returncode,'pass':ok})
  if not ok:print('MISMATCH',word,repr(actual),repr(expected),r.stderr[:120])
f=Path('docs/gforth-p00-runtime-cases.tsv')
old=list(csv.DictReader(f.open(),delimiter='\t'));old=[r for r in old if not r['case_id'].startswith('S01:')]
with f.open('w') as out:
 w=csv.DictWriter(out,fieldnames=list(dict.fromkeys(k for row in old+rows for k in row)),delimiter='\t',lineterminator='\n',quoting=csv.QUOTE_ALL);w.writeheader();w.writerows(old+rows)
print('Standard cases:',len(rows),'passed:',sum(r['pass'] for r in rows))
