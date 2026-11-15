#!/usr/bin/env python3
"""Compare the six implemented P04a owned/editing string words."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('sigma',nargs='?',default='zig-out/bin/sigma');p.add_argument('--gforth-build',type=pathlib.Path,required=True);p.add_argument('--report',type=pathlib.Path);a=p.parse_args();cases=[]
quote=lambda x:'S" '+x+'"'
for first in ['', 'a', 'abcd', 'abcdefgh']:
 for second in ['', 'x', '123456789']:
  for word in ['S+','APPEND']:
   owned=' SAVE-MEM' if word=='APPEND' else ''
   code=quote(first)+owned+' '+quote(second)+' '+word+' OVER >R '+quote(first+second)+' COMPARE . R> FREE THROW'
   cases.append((word+first+second,code,['0']))
for n in [0,1,3,4,8,-1]:
 remaining='abcd'[min(n if n>=0 else 4,4):]+' '*min(n if n>=0 else 4,4)
 code=f'CREATE BUF 16 ALLOT S" abcd" BUF SWAP MOVE BUF 4 {n} DELETE BUF 4 '+quote(remaining)+' COMPARE .'
 cases.append((f'delete-{n}',code,['0']))
for text in ['', 'X', 'yz', '123456']:
 expect=(text+'abcd')[:4]
 cases.append(('insert'+text,'CREATE BUF 16 ALLOT S" abcd" BUF SWAP MOVE '+quote(text)+' BUF 4 INSERT BUF 4 '+quote(expect)+' COMPARE .',['0']))
cases.append(('insert-alias','CREATE BUF 8 ALLOT S" abcdef" BUF SWAP MOVE BUF 1+ 2 BUF 6 INSERT BUF 6 S" baabcd" COMPARE .',['0']))
for text in ['', 'a','abc']:
 bytes_code=' '.join(str(n)+' C,' for n in text.encode())
 cases.append(('cstring'+text,'CREATE Z '+bytes_code+' 0 C, Z CSTRING>SSTRING '+quote(text)+' COMPARE .',['0']))
 cases.append(('comma'+text,'HERE '+quote(text)+' STRING, COUNT '+quote(text)+' COMPARE .',['0']))
for n in [0,1,7,255,256,300]:
 cases.append((f'comma-length-{n}',f'CREATE SRC {max(1,n)} ALLOT SRC {n} 65 FILL HERE SRC {n} STRING, C@ .',[str(n%256)]))
cases.append(('append-null','0 0 S" x" APPEND OVER >R S" x" COMPARE . R> FREE THROW',['0']))
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path(a.sigma).resolve()),'--max-steps','100000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
for name,source,expected in cases:
 for runtime,cmd in commands.items():
  r=subprocess.run(cmd+[source+' DEPTH . BYE'],capture_output=True,text=True,input='',timeout=15)
  assert r.returncode==0 and r.stdout.split()==expected+['0'],(name,runtime,r.returncode,r.stdout,r.stderr)
report={'words':6,'cases':len(cases),'checked':list(commands),'pass':True}
if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
