#!/usr/bin/env python3
"""Compare process cwd words in disposable child processes, never changing parent cwd."""
import argparse, json, pathlib, subprocess, os, pwd
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path('.work/p05b-cwd-check').resolve();root.mkdir(parents=True,exist_ok=True)
for path in ['child','日本語 dir','source']:(root/path).mkdir(exist_ok=True)
(root/'not-dir').write_text('x')
(root/'link').unlink(missing_ok=True);(root/'link').symlink_to(root/'child',target_is_directory=True)
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path('zig-out/bin/sigma').resolve()),'--max-steps','100000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
setup='CREATE CWD-BUFFER 4097 ALLOT : PRINT-CWD CWD-BUFFER 4096 GET-DIR TYPE ; '
cases=[]
for size in [0,1,2,len(str(root))-1,len(str(root)),len(str(root))+1,1024,4096]:
 cases.append(('size:'+str(size),setup+'CWD-BUFFER 4097 88 FILL CWD-BUFFER '+str(size)+' GET-DIR DUP . OVER 0= . 2DUP TYPE 2DROP CWD-BUFFER '+str(min(size+1,4096))+' + C@ .'))
for name in ['child','日本語 dir','./child','./child/..','child/../日本語 dir','link','missing','not-dir','',str(root/'child'),'~+/child','~/'+str((root/'child').relative_to(pathlib.Path.home())),'~'+pwd.getpwuid(os.getuid()).pw_name+'/'+str((root/'child').relative_to(pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir)))]:
 cases.append(('set:'+name,setup+'S" '+name+'" SET-DIR . PRINT-CWD'))
jp_length=len(str(root/'日本語 dir').encode())
for size in [jp_length,jp_length+1]:
 cases.append(('unicode-size:'+str(size),setup+'S" 日本語 dir" SET-DIR . CWD-BUFFER '+str(size)+' GET-DIR DUP . OVER 0= . TYPE'))
cases.append(('restore',setup+'S" child" SET-DIR . S" .." SET-DIR . PRINT-CWD'))
(root/'source/test.fs').write_text('S" ./child" SET-DIR . PRINT-CWD\n')
cases.append(('source-relative',setup+'INCLUDE source/test.fs'))
for name,source in cases:
 outputs={}
 for runtime,cmd in commands.items():
  r=subprocess.run(cmd+[source+' DEPTH . BYE'],cwd=root,env=os.environ,input='',capture_output=True,text=True,timeout=15)
  assert r.returncode==0,(name,runtime,r.returncode,r.stdout,r.stderr)
  outputs[runtime]=r.stdout
 assert outputs['sigma']==outputs['gforth'],(name,outputs)
report={'words':2,'gforth_comparisons':len(cases),'pass':True}
(root/'comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
