#!/usr/bin/env python3
"""Compare portable glob syntax with Gforth in UTF-8; record policy differences."""
import argparse, json, pathlib, subprocess, os, itertools
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True);a=p.parse_args()
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path('zig-out/bin/sigma').resolve()),'--max-steps','1000000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
names=['','a','b','c','d','z','0','5','9','A','Z','_','-','!','[',']','*','?','\\','.','a/b','.hidden','abc','abbc','aaabaaaac','aaabaaaad','a.txt','dir/name.txt','a b',' ','[]','[a','[abc','[!', '[a[b]]']
patterns=['','*','?','??','???','a*','*a','a?c','*b*','*a*b*a*c','a**?c','*.txt','*/*.txt','[a-c]','[!a-c]','[^a-c]','[c-a]','[-a]','[a-]','[]]','[!]]','[\\]]','\\*','\\?','\\[','\\\\','[','[a','a\\','[a\\-c]','[a-c[:digit:]]','[a-[:digit:]]','[]','[!','[!]','[a*','[?','[a[b]]','[a-b-c]','[a--c]','[!c-a]','[[]','[]a]','[[:unknown:]]','[![:unknown:]]']
for cls in ['alnum','alpha','blank','cntrl','digit','graph','lower','print','punct','space','upper','xdigit']:
 patterns.extend(['[[:'+cls+':]]','[![:'+cls+':]]'])
cases=list(itertools.product(names,patterns))
# Exhaust small star/literal patterns to exercise retry checkpoint interactions.
for length in range(4):
 for chars in itertools.product('ab*?',repeat=length):
  for name in ['','a','b','aa','ab','ba','bb','aba','aab','bba']:
   cases.append((name,''.join(chars)))
for name in ['日本語','名','語','é','😀','e\u0301']:
 for pattern in ['*','?','??','???','?????????','[名-語]','[!名-語]','*語','é','e\u0301']:
  cases.append((name,pattern))
def source(batch):
 return ''.join('S" '+name+'" S" '+pattern+'" FILENAME-MATCH . ' for name,pattern in batch)+'DEPTH . BYE'
def run(runtime,batch,locale='en_US.UTF-8',collate='C'):
 env={**os.environ,'LC_CTYPE':locale,'LC_COLLATE':collate};env.pop('LC_ALL',None)
 r=subprocess.run(commands[runtime]+[source(batch)],env=env,input='',capture_output=True,text=True,timeout=15)
 assert r.returncode==0,(runtime,r.returncode,r.stdout,r.stderr,batch)
 values=list(map(int,r.stdout.split()));assert values[-1]==0,(runtime,batch,values)
 return values[:-1]
for at in range(0,len(cases),25):
 batch=cases[at:at+25];sig=run('sigma',batch);gf=run('gforth',batch)
 assert len(sig)==len(gf)==len(batch)
 for case,x,y in zip(batch,sig,gf):assert x==y,(case,x,y)
differences=[]
for name,pattern,locale,sigma,gforth in [('日本語','???','C',-1,0),('é','?','C',-1,0),('é','[[:alpha:]]','en_US.UTF-8',0,-1),('é','[[:print:]]','en_US.UTF-8',0,-1)]:
 got={r:run(r,[(name,pattern)],locale)[0] for r in commands}
 assert got=={'sigma':sigma,'gforth':gforth},(name,pattern,locale,got)
 differences.append({'name':name,'pattern':pattern,'locale':locale,**got})
native_range={r:run(r,[('A','[a-c]')],'en_US.UTF-8','en_US.UTF-8')[0] for r in commands}
assert native_range=={'sigma':0,'gforth':-1},native_range
differences.append({'name':'A','pattern':'[a-c]','locale':'en_US.UTF-8 (native collation)',**native_range})
report={'word':'FILENAME-MATCH','reference_ctype':'en_US.UTF-8','reference_collation':'C','gforth_comparisons':len(cases),'intentional_differences':differences,'pass':True}
root=pathlib.Path('.work/p05b-filename-match-check');root.mkdir(parents=True,exist_ok=True);(root/'comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
