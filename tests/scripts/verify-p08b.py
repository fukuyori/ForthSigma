#!/usr/bin/env python3
"""Check P08b with Sigma's explicit address, definition and exception policies."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--sigma',type=pathlib.Path,default=pathlib.Path('zig-out/bin/sigma'));p.add_argument('--reference',type=pathlib.Path,default=pathlib.Path('.work/p08b-check/spec-probes.json'));a=p.parse_args();sigma=str(a.sigma.resolve());rows=[]
policies={n:(1,'DEFINITION ERROR !\n') for n in ['addr-constant','addr-variable','addr-local-variable','preserve-value','colon-is-value']}
policies.update({'addressable-two':(1,'STACK UNDER FLOW !\n'),'addr-no-name':(0,'-259 0 '),'preserve-interpret':(1,'COMPILE MODE ERROR !\n'),'colon-is-failure':(0,'-22 1 0 '),'wrap-nondefer':(0,'-261 1 0 ')})
cases=json.loads(a.reference.read_text())['cases']
assert set(policies) <= {c['case'] for c in cases}, 'unmatched policy override'
for c in cases:
 name=c['case'];code,expected=policies.get(name,(c['exit'],c['stdout']))
 r=subprocess.run([sigma,'--max-steps','100000','-e',c['source']+' DEPTH . BYE'],capture_output=True,input=b'',timeout=10);actual=r.stdout.decode(errors='replace')
 if name in ('preserve-uninitialized','wrap-uninitialized'):
  warning='WARNING: DEFERRED WORD D IS UNINITIALIZED\n';assert warning in actual,(name,actual);actual=actual.replace(warning,'',1)
 assert r.returncode==code and actual==expected,(name,r.returncode,actual,code,expected,r.stderr)
 rows.append({'case':name,'sigma_policy':name in policies})
folder=a.reference.parent.resolve();image=folder/'values.sigma';exe=folder/'values-program'
source='16 ALLOCATE THROW AVALUE P 65 P C! 7 VALUE V : GET ADDR V ; : A 1 ; DEFER D \' A IS D : RESET PRESERVE D ; :IS D 3 ; DEFER E : RESET-E PRESERVE E ; : RUN P C@ . GET @ . D . RESET D . RESET-E ACTION-OF E -1 = . ; '
r=subprocess.run([sigma,'-e',source+f'SAVE {image} SAVESYS {exe} BYE'],capture_output=True,input=b'',timeout=20);assert r.returncode==0,(r.stdout,r.stderr)
for command in ([sigma,'-e',f'CREATE BEFORE 24 ALLOT 32 ALLOCATE THROW DROP LOAD-DICTIONARY {image} RUN DEPTH . BYE'],[str(exe),'-e','RUN DEPTH . BYE']):
 r=subprocess.run(command,capture_output=True,input=b'',timeout=20);assert r.returncode==0 and r.stdout==b'65 7 3 1 -1 0 ',(command,r.returncode,r.stdout,r.stderr)
report={'pass':True,'comparisons':sum(not r['sigma_policy'] for r in rows),'sigma_policy_checks':sum(r['sigma_policy'] for r in rows),'native_image_checks':2,'cases':rows}
a.reference.with_name('comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='cases'}))
