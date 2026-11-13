#!/usr/bin/env python3
"""Runtime checks for string values and the MACRO: alias."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('sigma',nargs='?',default='zig-out/bin/sigma');p.add_argument('--gforth-build',type=pathlib.Path,required=True);p.add_argument('--report',type=pathlib.Path);a=p.parse_args();cases=[]
q=lambda x:'S" '+x+'"'
for defining in ['$VALUE','MACRO:']:
 for initial in ['', 'a','abc','é']:
  for replacement in ['', 'xy','longer-value']:
   source=q(initial)+' '+defining+' SV-P04 SV-P04 '+q(initial)+' COMPARE . '+q(replacement)+' TO SV-P04 SV-P04 '+q(replacement)+' COMPARE . S" !" +TO SV-P04 SV-P04 '+q(replacement+'!')+' COMPARE .'
   cases.append((defining+initial+replacement,source,['0','0','0']))
for defining in ['$VALUE','MACRO:']:
 source=f': MAKE-P04 {defining} ; S" start" MAKE-P04 SV-P04 : SET-P04 S" changed" TO SV-P04 ; : ADD-P04 S" !" +TO SV-P04 ; SET-P04 ADD-P04 SV-P04 S" changed!" COMPARE .'
 cases.append(('compiled-'+defining,source,['0']))
cases.append(('self-assign','S" kept" $VALUE SV-P04 SV-P04 TO SV-P04 SV-P04 S" kept" COMPARE .',['0']))
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path(a.sigma).resolve()),'--max-steps','100000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
for name,source,expected in cases:
 for runtime,cmd in commands.items():
  r=subprocess.run(cmd+[source+' DEPTH . BYE'],capture_output=True,text=True,input='',timeout=15)
  assert r.returncode==0 and r.stdout.split()==expected+['0'],(name,runtime,r.returncode,r.stdout,r.stderr)
report={'words':2,'cases':len(cases),'checked':list(commands),'pass':True}
if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
