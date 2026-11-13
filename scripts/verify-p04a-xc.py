#!/usr/bin/env python3
"""Check XC@+? against Gforth for nonempty inputs and the selected Sigma empty rule."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('sigma',nargs='?',default='zig-out/bin/sigma');p.add_argument('--gforth-build',type=pathlib.Path,required=True);p.add_argument('--report',type=pathlib.Path);a=p.parse_args()
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path(a.sigma).resolve()),'--max-steps','100000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
cases=[(bytes([n]),1) for n in range(256)]
for cp in [128,233,2047,2048,0xd7ff,0xd800,0xe000,0xffff,0x10000,0x10ffff]:
 data=chr(cp).encode('utf-8','surrogatepass')
 for n in range(1,len(data)+1):cases.append((data+b'!',n))
for data in [b'\xc0\x80',b'\xe6\x97A',b'\xf4\x90\x80\x80',b'\xed\xa0\x80',b'\xffABC']:
 for n in range(1,len(data)+1):cases.append((data,n))
for data,n in cases:
 outputs={}
 for runtime,cmd in commands.items():
  source='CREATE XC-P04 '+' '.join(str(x)+' C,' for x in data)+f' XC-P04 {n} XC@+? . . XC-P04 - . DEPTH . BYE'
  r=subprocess.run(cmd+[source],capture_output=True,text=True,input='',timeout=15)
  assert r.returncode==0,(runtime,list(data),n,r.stdout,r.stderr)
  outputs[runtime]=r.stdout.split()
 assert outputs['sigma']==outputs['gforth'] and outputs['sigma'][-1]=='0',(list(data),n,outputs)
for value in [0,65,255]:
 source=f'CREATE XC-P04 {value} C, XC-P04 0 XC@+? . . XC-P04 - . DEPTH . BYE'
 r=subprocess.run(commands['sigma']+[source],capture_output=True,text=True,input='',timeout=15)
 assert r.returncode==0 and r.stdout.split()==['65533','-1','1','0'],(value,r.stdout,r.stderr)
report={'words':1,'nonempty_gforth_cases':len(cases),'sigma_empty_cases':3,'pass':True}
if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
