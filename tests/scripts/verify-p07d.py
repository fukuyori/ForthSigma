#!/usr/bin/env python3
"""Check scoped parsing and forward bindings, retaining Sigma compiler/error policy."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--sigma',type=pathlib.Path,default=pathlib.Path('zig-out/bin/sigma'));p.add_argument('--reference',type=pathlib.Path,default=pathlib.Path('.work/p07d-check/spec-probes.json'));a=p.parse_args();sigma=str(a.sigma.resolve());results=[]
for c in json.loads(a.reference.read_text())['cases']:
 name=c['case'];expected=c['stdout'];code=c['exit'];policy=False
 if name in ('forward-duplicate','forward-noncolon'):expected='DEFINITION ERROR !\n';code=1;policy=True
 elif name=='forward-failure':expected='-22 0 ';code=0;policy=True
 elif name=='recursive-outside':expected='-14 0 ';policy=True
 r=subprocess.run([sigma,'--max-steps','100000','-e',c['source']+' DEPTH . BYE'],input=b'',capture_output=True,timeout=10);actual=r.stdout.decode(errors='replace')
 if name in ('forward-redefine','forward-wid'):
  assert actual.startswith('WARNING: SAME NAME WORD EXISTS\n'),(name,actual)
  actual=actual.removeprefix('WARNING: SAME NAME WORD EXISTS\n')
 assert r.returncode==code and actual==expected,(name,r.returncode,actual,code,expected,r.stderr)
 results.append({'case':name,'sigma_policy_check':policy})
folder=a.reference.parent.resolve();image=folder/'parsing.sigma';exe=folder/'parsing-program'
source="FORWARD F : T F ; : TOKEN ['] F ; : F 7 ; : P PARSE-NAME TYPE ; : RUN T . TOKEN EXECUTE . S\" text\" ['] P EXECUTE-PARSING ; "
r=subprocess.run([sigma,'-e',source+f'SAVE {image} SAVESYS {exe} BYE'],input=b'',capture_output=True,timeout=20);assert r.returncode==0,(r.stdout,r.stderr)
for command in ([sigma,'-e',f': BEFORE 1 ; LOAD-DICTIONARY {image} RUN DEPTH . BYE'],[str(exe),'-e','RUN DEPTH . BYE']):
 r=subprocess.run(command,input=b'',capture_output=True,timeout=20);assert r.returncode==0 and r.stdout==b'7 7 text0 ',(command,r.returncode,r.stdout,r.stderr)
report={'pass':True,'comparisons':sum(not x['sigma_policy_check'] for x in results),'sigma_policy_checks':sum(x['sigma_policy_check'] for x in results),'native_image_checks':2,'cases':results};a.reference.with_name('comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='cases'}))
