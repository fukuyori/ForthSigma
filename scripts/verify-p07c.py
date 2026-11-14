#!/usr/bin/env python3
"""Compare valid loop observations and selected Sigma boundary/error policies."""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--sigma',type=pathlib.Path,default=pathlib.Path('zig-out/bin/sigma'));p.add_argument('--reference',type=pathlib.Path,default=pathlib.Path('.work/p07c-check/spec-probes.json'));a=p.parse_args();sigma=str(a.sigma.resolve());results=[]
for case in json.loads(a.reference.read_text())['cases']:
 name=case['case'];src=case['source'];expected=case['stdout'];code=case['exit'];policy=False
 if name=='limit-helper':expected='0 3 3 1 3 2 2 3 1 0 ';policy=True
 invalid_mem = name.startswith('memory:') and name.endswith((':0',':-1'))
 overflow = name.startswith('memory-boundary:') and (':-2:4:1' in name or ':100:-1:1' in name)
 if invalid_mem or overflow:
  src=src.rsplit(' T',1)[0]+" ' T CATCH .";expected='-24 0 ';code=0;policy=True
 elif name=='memory-boundary:MEM-DO:100:4:9223372036854775807':expected='0 ';policy=True
 elif name in ('malformed:: T DONE ;','malformed:: T NEXT ;','malformed:: T -LOOP ;'):
  expected='CONTROL STRUCTURE ERROR !\n';code=1;policy=True
 r=subprocess.run([sigma,'--max-steps','100000','-e',src+' DEPTH . BYE'],input=b'',capture_output=True,timeout=10)
 assert r.returncode==code and r.stdout.decode(errors='replace')==expected,(name,r.returncode,r.stdout,code,expected,r.stderr)
 results.append({'case':name,'sigma_policy_check':policy})
folder=a.reference.parent.resolve();image=folder/'loops.sigma';exe=folder/'loops-program'
source=": Q [: 3 FOR I . NEXT ;] ; : UP 3 0 +DO I . LOOP ; : DOWN 0 3 -DO I . 1 -LOOP ; : MEM 100 6 2 MEM-DO I 100 - . LOOP ; : EARLY 3 0 DO I . LEAVE DONE UNLOOP ; : RUN UP DOWN MEM EARLY Q EXECUTE ; "
r=subprocess.run([sigma,'-e',source+f'SAVE {image} SAVESYS {exe} BYE'],input=b'',capture_output=True,timeout=20);assert r.returncode==0,(r.stdout,r.stderr)
for cmd in ([sigma,'-e',f': BEFORE 1 ; LOAD-DICTIONARY {image} RUN DEPTH . BYE'],[str(exe),'-e','RUN DEPTH . BYE']):
 r=subprocess.run(cmd,input=b'',capture_output=True,timeout=20);assert r.returncode==0 and r.stdout==b'0 1 2 3 2 1 4 2 0 0 3 2 1 0 0 ',(cmd,r.returncode,r.stdout,r.stderr)
report={'pass':True,'comparisons':sum(not x['sigma_policy_check'] for x in results),'sigma_policy_checks':sum(x['sigma_policy_check'] for x in results),'native_image_checks':2,'cases':results};a.reference.with_name('comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='cases'}))

for source in (': INCOMPLETE 3 FOR I', ': INCOMPLETE 3 0 +DO I'):
 r=subprocess.run([sigma,'-e',source],input=b'',capture_output=True,timeout=10)
 assert r.returncode==1 and b'DEFINITION ERROR !' in r.stdout,(source,r.returncode,r.stdout,r.stderr)
report['native_eof_checks']=2
a.reference.with_name('comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'pass':True,'native_eof_checks':2}))
