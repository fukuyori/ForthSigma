#!/usr/bin/env python3
"""Compare mkdir errors, partial trees and POSIX modes with isolated child umasks."""
import argparse, json, pathlib, subprocess, os, stat, tempfile, pwd
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path('.work/p05b-mkdir-check').resolve();root.mkdir(parents=True,exist_ok=True)
run=pathlib.Path(tempfile.mkdtemp(prefix='run-',dir=root))
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path('zig-out/bin/sigma').resolve()),'--max-steps','100000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
cases=[]
for word,name in [('=MKDIR','leaf'),('=MKDIR','existing'),('=MKDIR','file'),('=MKDIR','missing/leaf'),('=MKDIR','existing/leaf'),('=MKDIR',''),('MKDIR-PARENTS','new/a'),('MKDIR-PARENTS','existing/a'),('MKDIR-PARENTS','existing'),('MKDIR-PARENTS','existing/'),('MKDIR-PARENTS','new/'),('MKDIR-PARENTS','new//a'),('MKDIR-PARENTS','./new/a'),('MKDIR-PARENTS','a/../leaf'),('MKDIR-PARENTS','file/x'),('MKDIR-PARENTS','fresh/../file/x'),('MKDIR-PARENTS','日本語 dir/子'),('=MKDIR','日本語 dir'),('MKDIR-PARENTS','back\\slash/leaf')]:
 cases.append((word,name,0o755,0o022))
for mode in [0,0o100,0o200,0o400,0o500,0o600,0o700,0o711,0o750,0o755,0o777]:
 for mask in [0,0o022,0o077]: cases.append(('=MKDIR','mode-dir',mode,mask))
for mode in [0,0o500,0o700,0o755,0o777]: cases.append(('MKDIR-PARENTS','limited/child',mode,0o022))
for name in ['~/home-leaf','~+/cwd-leaf','~USER/home-leaf','~/home-parent/child']:
 cases.append(('MKDIR-PARENTS',name,0o755,0o022))
def snapshot(work):
 result={}
 for current,dirs,files in os.walk(work,followlinks=False):
  for name in dirs+files:
   path=pathlib.Path(current)/name
   result[str(path.relative_to(work))]={'dir':path.is_dir(),'mode':stat.S_IMODE(path.stat().st_mode)}
 return result
for index,(word,name,mode,mask) in enumerate(cases):
 outputs={};trees={}
 for runtime,cmd in commands.items():
  work=run/str(index)/runtime;work.mkdir(parents=True)
  (work/'existing').mkdir();(work/'existing').chmod(0o711);(work/'file').write_text('x')
  if name.startswith('~/'):
   path='~/'+str(work.relative_to(pathlib.Path.home()))+'/'+name[2:]
  elif name.startswith('~USER/'):
   user=pwd.getpwuid(os.getuid());path='~'+user.pw_name+'/'+str(work.relative_to(pathlib.Path(user.pw_dir)))+'/'+name[6:]
  else:path=name
  source=('REQUIRE mkdir.fs ' if runtime=='gforth' else '')+'S" '+path+'" '+str(mode)+' '+word+' . DEPTH . BYE'
  r=subprocess.run(cmd+[source],cwd=work,input='',capture_output=True,text=True,timeout=15,preexec_fn=lambda:os.umask(mask))
  assert r.returncode==0,(word,name,mode,mask,runtime,r.returncode,r.stdout,r.stderr)
  outputs[runtime]=r.stdout;trees[runtime]=snapshot(work)
 assert outputs['sigma']==outputs['gforth'],(word,name,mode,mask,outputs)
 assert trees['sigma']==trees['gforth'],(word,name,mode,mask,trees)
report={'words':2,'gforth_comparisons':len(cases),'trees_and_modes_compared':True,'pass':True}
(root/'comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
