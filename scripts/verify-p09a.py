#!/usr/bin/env python3
"""Compare P09a with observed Gforth behavior and explicit Sigma policies."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--sigma',type=pathlib.Path,default=pathlib.Path('zig-out/bin/sigma'));p.add_argument('--reference',type=pathlib.Path,default=pathlib.Path('.work/p09a-check/spec-probes.json'));a=p.parse_args();sigma=str(a.sigma.resolve())
policies={'defaults':(0,'1 -1 0 '),'assert-interpret':(0,'7 0 '),'assert-false':(0,'*the terminal*:0:20: failed assertion-2 0 '),'assert-missing':(1,'DEFINITION ERROR !\n'),'close-alone':(0,'-22 0 '),'exceptions-negative':(0,'-24 0 '),'warning:-4':(0,'-281 0 '),'redefine:-4':(1,'WARNING: SAME NAME WORD EXISTS\nWARNING TREATED AS ERROR !\n'),'warning-interpret':(1,'COMPILE MODE ERROR !\n'),'message-simple':(1,'alpha-custom\n'),'message-group':(1,'second-custom\n')}
for level in [-1,-2,-3,1]:policies['redefine:'+str(level)]=(0,'WARNING: SAME NAME WORD EXISTS\n2 0 ')
cs=json.loads(a.reference.read_text())['cases'];assert set(policies)<={c['case'] for c in cs}
rows=[]
for c in cs:
 name=c['case']
 if name.startswith(('lookup:','compile-only:','immediate:')):continue
 expected=policies.get(name,(c['exit'],c['stdout']))
 r=subprocess.run([sigma,'--max-steps','100000','-e',c['source']+' DEPTH . BYE'],capture_output=True,input=b'',timeout=10)
 assert (r.returncode,r.stdout.decode())==expected,(name,r.returncode,r.stdout,r.stderr,expected)
 if name.startswith('warning:') and name!='warning:0':assert b'WARNING: sample\n' in r.stderr,(name,r.stderr)
 if name=='warning-false':assert not r.stderr
 rows.append({'case':name,'sigma_policy':name in policies})
folder=a.reference.parent.resolve();image=folder/'diagnostics.sigma';exe=folder/'diagnostics-program'
source='S" native-custom" EXCEPTION CONSTANT E : MSG DROP S" native-group" ; \' MSG 2 EXCEPTIONS CONSTANT G : BAD E THROW ; : RUN [\'] BAD CATCH E = . G THROW ; '
r=subprocess.run([sigma,'-e',source+f'SAVE {image} SAVESYS {exe} BYE'],capture_output=True,input=b'',timeout=20);assert r.returncode==0,(r.stdout,r.stderr)
for cmd in ([sigma,'-e',f'CREATE BEFORE 24 ALLOT LOAD-DICTIONARY {image} RUN'],[str(exe),'-e','RUN']):
 r=subprocess.run(cmd,capture_output=True,input=b'',timeout=20);assert r.returncode==1 and r.stdout.startswith(b'-1 native-group\n'),(cmd,r.returncode,r.stdout,r.stderr)
report={'pass':True,'comparisons':sum(not x['sigma_policy'] for x in rows),'sigma_policy_checks':sum(x['sigma_policy'] for x in rows),'native_image_checks':2,'cases':rows}
a.reference.with_name('comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='cases'}))
