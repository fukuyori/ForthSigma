#!/usr/bin/env python3
"""Compare the six P05a path descriptor words, without filesystem lookup."""
import argparse, json, pathlib, subprocess
p=argparse.ArgumentParser();p.add_argument('sigma',nargs='?',default='zig-out/bin/sigma');p.add_argument('--gforth-build',type=pathlib.Path,required=True);p.add_argument('--report',type=pathlib.Path);a=p.parse_args()
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path(a.sigma).resolve()),'--max-steps','100000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
cases=[]
for name in ['a','a/b','/','/a','~','~/a','~+/a','./','./a','../a','C:','C:a','C:/a','a:','a:b','\\a','日本語/名']:
 cases.append(('absolute:'+name,'S" '+name+'" ABSOLUTE-FILE? .'))
for path in ['a','a|b','|a','a||b','a|','|','a|||b','./|../|~+','日本語|foo']:
 cases.append(('set:'+path,'VARIABLE P : BYTES P $@ DUP . BOUNDS ?DO I C@ . LOOP ; P PATH= '+path+' P .PATH BYTES'))
for first in ['', 'foo', '日本語']:
 for second in ['', 'bar','a dir']:
  cases.append(('append:'+first+second,'VARIABLE P P CLEAR-PATH S" '+first+'" P ALSO-PATH S" '+second+'" P ALSO-PATH P .PATH P $@LEN .'))
cases.append(('self','VARIABLE P P PATH= one P $@ P ALSO-PATH P .PATH'))
cases.append(('compiled','VARIABLE P : SET-P PATH= ; : ADD-P PATH+ ; P SET-P one|two P ADD-P three P .PATH'))
for name,source in cases:
 outputs={}
 for runtime,cmd in commands.items():
  r=subprocess.run(cmd+[source+' DEPTH . BYE'],capture_output=True,text=True,input='',timeout=15)
  assert r.returncode==0,(name,runtime,r.returncode,r.stdout,r.stderr)
  outputs[runtime]=r.stdout
 assert outputs['sigma']==outputs['gforth'],(name,outputs)
report={'words':6,'gforth_comparisons':len(cases),'pass':True}
if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
