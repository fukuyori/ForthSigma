#!/usr/bin/env python3
"""Compare iterator records without relying on directory iteration order."""
import argparse, pathlib, subprocess, json, os, pwd, errno
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path('.work/p05b-dir-iterator-check').resolve();root.mkdir(parents=True,exist_ok=True)
entries=root/'entries';entries.mkdir(exist_ok=True);(root/'empty').mkdir(exist_ok=True)
for name in ['a','abc','.hidden','日本語-file','a space','é-name','x'*120]:(entries/name).write_text('x')
try:
 fd=os.open(os.fsencode(entries)+b'/bad-\xff',os.O_CREAT|os.O_WRONLY,0o600);os.close(fd);invalid_name='created'
except OSError as error:
 if error.errno!=errno.EILSEQ:raise
 invalid_name='filesystem-rejected(EILSEQ)'
(entries/'child').mkdir(exist_ok=True);(root/'not-dir').write_text('x')
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path('zig-out/bin/sigma').resolve()),'--max-steps','1000000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
def source(name,size):
 return ('CREATE ITER-BUF 2048 ALLOT VARIABLE ITER-ID VARIABLE ITER-N VARIABLE ITER-FLAG VARIABLE ITER-ERR '
 ': ITER-CASE S" '+name+'" OPEN-DIR DUP ." O " . CR DUP IF 2DROP ELSE DROP ITER-ID ! '
 'BEGIN ITER-BUF 2048 88 FILL ITER-BUF '+str(size)+' ITER-ID @ READ-DIR ITER-ERR ! ITER-FLAG ! ITER-N ! '
 '." R " ITER-ERR @ . ITER-FLAG @ . ITER-N @ . ITER-BUF ITER-N @ BOUNDS ?DO I C@ . LOOP '
 'ITER-BUF ITER-N @ + C@ . ITER-BUF '+str(size)+' + C@ . CR ITER-FLAG @ 0= UNTIL '
 'ITER-BUF 2048 88 FILL ." E " ITER-BUF '+str(size)+' ITER-ID @ READ-DIR . . . ITER-BUF C@ . CR '
 '." C " ITER-ID @ CLOSE-DIR . CR THEN ." D " DEPTH . CR ; ITER-CASE BYE')
cases=[('entries',size) for size in [0,1,2,3,4,8,9,16,32,119,120,121,1024]]
cases += [(name,1024) for name in ['empty','missing','not-dir','./entries','entries/',str(entries),'~/'+str(entries.relative_to(pathlib.Path.home())),'~'+pwd.getpwuid(os.getuid()).pw_name+'/'+str(entries.relative_to(pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir)))]]
records=[]
for name,size in cases:
 outputs={}
 for runtime,cmd in commands.items():
  r=subprocess.run(cmd+[source(name,size)],cwd=root,env=os.environ,input='',capture_output=True,text=True,timeout=15)
  assert r.returncode==0,(runtime,name,size,r.returncode,r.stdout,r.stderr)
  lines=r.stdout.splitlines();rows=[line for line in lines if line.startswith('R ')];footer=[line for line in lines if not line.startswith('R ')]
  assert footer[-1].strip()=='D 0',(runtime,name,size,footer)
  outputs[runtime]={'rows':sorted(rows),'footer':footer}
 assert outputs['sigma']==outputs['gforth'],(name,size,outputs)
 records.append({'name':name,'capacity':size,'entries':sum(int(row.split()[2])!=0 for row in outputs['sigma']['rows'])})
report={'words':3,'gforth_comparisons':len(cases),'invalid_filename_test':invalid_name,'records':records,'pass':True}
(root/'comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'words':3,'gforth_comparisons':len(cases),'pass':True}))
