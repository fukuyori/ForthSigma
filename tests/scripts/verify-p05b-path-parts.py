#!/usr/bin/env python3
"""Compare borrowed path slices with the designated Gforth, including addresses."""
import argparse, json, pathlib, subprocess
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True);a=p.parse_args()
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path('zig-out/bin/sigma').resolve()),'--max-steps','100000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
names=['','/','//','///','.','..','./','../','a','a/','a//','a/.','a/..','/a/b','C:','C:/file','C:\\dir\\file','日本語/名前','a dir/a file']
for prefix in ['','/','./','../','a/','a//','日本語/']:
 for tail in ['b','b/','./b','../b','a\\b']:
  names.append(prefix+tail)
cases=0
for name in names:
 for word in ['BASENAME','DIRNAME']:
  source=': CHECK S" '+name+'" OVER >R '+word+' DUP . OVER R> - . TYPE ; CHECK DEPTH . BYE'
  outputs={}
  for runtime,cmd in commands.items():
   r=subprocess.run(cmd+[source],input='',capture_output=True,text=True,timeout=15)
   assert r.returncode==0,(name,word,runtime,r.returncode,r.stdout,r.stderr)
   outputs[runtime]=r.stdout
  assert outputs['sigma']==outputs['gforth'],(name,word,outputs)
  cases+=1
report={'words':2,'gforth_comparisons':cases,'pass':True}
root=pathlib.Path('.work/p05b-path-parts-check');root.mkdir(parents=True,exist_ok=True);(root/'comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
