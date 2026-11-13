#!/usr/bin/env python3
"""Runtime comparison for the first 21 P04a words; no Gforth code is copied."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('sigma',nargs='?',default='zig-out/bin/sigma');p.add_argument('--gforth-build',type=pathlib.Path,required=True);p.add_argument('--report',type=pathlib.Path);a=p.parse_args()
cases=[]
for name,value in [('#BELL',7),('#BS',8),('#CR',13),('#DEL',127),('#EOF',4),('#ESC',27),('#FF',12),('#LF',10),('#TAB',9),('INVALID-CHAR',65533)]:cases.append((name,name+' .',[str(value)]))
for n in [-1,*range(256),233,0x10428,0x1f600]:cases.append((f'upper-{n}',f'{n} TOUPPER .',[str(n-32 if 97<=n<=122 else n)]))
cases.append(('newline','NEWLINE DUP . DROP C@ .',['1','10']))
for first,second in [('',''),('Ab','aB'),('Abc','aB'),('a','B'),('é','É'),('abc','xyz'),('abcd','cd')]:
    def quoted(x):return 'S" '+x+'"'
    af=first.encode();bs=second.encode();fold=lambda x:bytes(c-32 if 97<=c<=122 else c for c in x)
    x,y=fold(af),fold(bs)
    order=-1 if x<y else 1 if x>y else 0
    for word,expected in [('CAPSCOMPARE',order),('CAPSSTRING-PREFIX?',-int(x.startswith(y))),('STRING-SUFFIX?',-int(af.endswith(bs))),('STR<',-int(af<bs))]:cases.append((word+first+second,quoted(first)+' '+quoted(second)+' '+word+' .',[str(expected)]))
    offset=x.find(y);remaining=len(af)-offset if offset>=0 else len(af)
    cases.append(('search'+first+second,quoted(first)+' '+quoted(second)+' CAPSSEARCH . NIP .',[str(-int(offset>=0)),str(remaining)]))
for n in [-10,0,1,3,99,9223372036854775807]:cases.append((f'slice-{n}',f'S" abc" {n} SAFE/STRING NIP .',[str(3-max(0,min(n,3)))]))
for char in [-1,0,97,98,99,122,256]:cases.append((f'scan-{char}',f'S" abca" {char} SCAN-BACK NIP .',[str(b'abca'.rfind(bytes([char]))+1 if 0<=char<=255 else 0)]))
for at,length in [(103,0),(102,0),(103,1)]:cases.append((f'nosplit-{at}-{length}',f'100 3 {at} {length} NOSPLIT? . 2DROP 2DROP',[str(-int(at==103 and length==0))]))
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path(a.sigma).resolve()),'--max-steps','100000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
for name,source,expected in cases:
 for runtime,cmd in commands.items():
  r=subprocess.run(cmd+[source+' DEPTH . BYE'],capture_output=True,text=True,input='',timeout=15)
  assert r.returncode==0 and r.stdout.split()==expected+['0'],(name,runtime,r.returncode,r.stdout,r.stderr)
for runtime,cmd in commands.items():
 r=subprocess.run(cmd+['CREATE T 97 C, 9 C, 10 C, 195 C, 169 C, T 5 TYPEWHITE BYE'],capture_output=True,text=True,input='',timeout=15)
 assert r.returncode==0 and r.stdout==' \t   ',(runtime,r.stdout,r.stderr)
report={'words':21,'cases':len(cases)+1,'checked':list(commands),'pass':True}
if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
