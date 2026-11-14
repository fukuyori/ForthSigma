#!/usr/bin/env python3
"""Compare P08a with explicit Sigma identity, error and display policies."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--sigma',type=pathlib.Path,default=pathlib.Path('zig-out/bin/sigma'));p.add_argument('--reference',type=pathlib.Path,default=pathlib.Path('.work/p08a-check/spec-probes.json'));a=p.parse_args();sigma=str(a.sigma.resolve());rows=[]
policies={'compile-only:]]':(0,'0 0 '),'nextname-empty':(0,'0 0 7 0 '),'empty-name-link':(0,'0 0 0 '),'in-constant':(1,'DEFINITION ERROR !\n'),'wordlist-words':(0,'Alpha Beta 0'),'vlist':(0,'Alpha Beta 0'),'vocs':(0,'Named EKEYS Root Forth Macros 0')}
for c in json.loads(a.reference.read_text())['cases']:
 name=c['case'];code,expected=policies.get(name,(c['exit'],c['stdout']))
 r=subprocess.run([sigma,'--max-steps','100000','-e',c['source']+' DEPTH . BYE'],capture_output=True,input=b'',timeout=10)
 actual=r.stdout.decode(errors='replace')
 if name=='redefine:CS-WORDLIST':
  assert actual.startswith('WARNING: SAME NAME WORD EXISTS\n'),(name,actual)
  actual=actual.removeprefix('WARNING: SAME NAME WORD EXISTS\n')
 assert r.returncode==code and actual.split()==expected.split(),(name,r.returncode,actual,code,expected,r.stderr)
 rows.append({'case':name,'sigma_policy':name in policies})
folder=a.reference.parent.resolve();image=folder/'names.sigma';exe=folder/'names-program'
source='CS-VOCABULARY V ALSO V DEFINITIONS : Foo 7 ; : foo 8 ; FORTH DEFINITIONS PREVIOUS : MAKE S" Made" NEXTNAME CONSTANT ; : RUN ALSO V S" Foo" FIND-NAME NAME>INTERPRET EXECUTE . S" foo" FIND-NAME NAME>INTERPRET EXECUTE . FORTH PREVIOUS 9 MAKE S" Made" FIND-NAME NAME>INTERPRET EXECUTE . ; '
r=subprocess.run([sigma,'-e',source+f'SAVE {image} SAVESYS {exe} BYE'],capture_output=True,input=b'',timeout=20);assert r.returncode==0,(r.stdout,r.stderr)
for command in ([sigma,'-e',f'WORDLIST DROP LOAD-DICTIONARY {image} RUN DEPTH . BYE'],[str(exe),'-e','RUN DEPTH . BYE']):
 r=subprocess.run(command,capture_output=True,input=b'',timeout=20);assert r.returncode==0 and r.stdout==b'7 8 9 0 ',(command,r.returncode,r.stdout,r.stderr)
report={'pass':True,'comparisons':sum(not r['sigma_policy'] for r in rows),'sigma_policy_checks':sum(r['sigma_policy'] for r in rows),'native_image_checks':2,'cases':rows}
a.reference.with_name('comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='cases'}))
