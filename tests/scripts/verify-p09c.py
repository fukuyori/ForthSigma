#!/usr/bin/env python3
"""Compare safe P09c behavior and exercise explicit Sigma stack boundaries/images."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--sigma',type=pathlib.Path,default=pathlib.Path('zig-out/bin/sigma'));p.add_argument('--reference',type=pathlib.Path,default=pathlib.Path('.work/p09c-check/spec-probes.json'));a=p.parse_args();sigma=str(a.sigma.resolve());rows=[]
for c in json.loads(a.reference.read_text())['cases']:
 r=subprocess.run([sigma,'--max-steps','100000','-e',c['source']+' DEPTH . BYE'],capture_output=True,input=b'',timeout=20)
 assert (r.returncode,r.stdout.decode())==(c['exit'],c['stdout']),(c['case'],r.returncode,r.stdout,r.stderr,c)
 rows.append(c['case'])
policies=[('empty-float','F>R',b'FLOATING-POINT STACK UNDER FLOW !\n'),('empty-return','FR>',b'RETURN STACK UNDER FLOW !\n'),('second-empty',"R'@",b'RETURN STACK UNDER FLOW !\n'),('index-empty','0 RPICK',b'RETURN STACK UNDER FLOW !\n'),('index-negative','11 >R -1 RPICK',b'RETURN STACK UNDER FLOW !\n')]
for n,s,expected in policies:
 r=subprocess.run([sigma,'-e',s],capture_output=True,input=b'',timeout=20);assert r.returncode==1 and r.stdout==expected,(n,r.returncode,r.stdout,r.stderr)
folder=a.reference.parent.resolve();image=folder/'return.sigma';exe=folder/'return-program'
source=": RETURNS 11 >R 22 >R R'@ . 0 RPICK . R> DROP R> DROP 1.25e F>R FR@ F. FR> F. ; "
r=subprocess.run([sigma,'-e',source+f'SAVE {image} SAVESYS {exe} BYE'],capture_output=True,input=b'',timeout=20);assert r.returncode==0,(r.stdout,r.stderr)
for cmd in ([sigma,'-e',f'CREATE PREFIX 24 ALLOT LOAD-DICTIONARY {image} RETURNS DEPTH . BYE'],[str(exe),'-e','RETURNS DEPTH . BYE']):
 r=subprocess.run(cmd,capture_output=True,input=b'',timeout=20);assert r.returncode==0 and r.stdout==b'11 22 1.25 1.25 0 ',(cmd,r.returncode,r.stdout,r.stderr)
report={'pass':True,'comparisons':len(rows),'sigma_policy_checks':len(policies),'native_image_checks':2};a.reference.with_name('comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
