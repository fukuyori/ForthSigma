#!/usr/bin/env python3
"""Verify quotations, anonymous definers and postponing against observed Gforth."""
import argparse
import json
import pathlib
import subprocess
p=argparse.ArgumentParser()
p.add_argument('--sigma',type=pathlib.Path,default=pathlib.Path('zig-out/bin/sigma'))
p.add_argument('--reference',type=pathlib.Path,default=pathlib.Path('.work/p07b-check/spec-probes.json'))
a=p.parse_args(); sigma=str(a.sigma.resolve());results=[]
policy={
 'quote-outer-local': 'x ?\n',
 'quote-unbalanced-control': 'CONTROL STRUCTURE ERROR !\n',
 'quote-unclosed': 'CONTROL STRUCTURE ERROR !\n',
 'quote-close-alone': 'CONTROL STRUCTURE ERROR !\n',
 'postpone-no-definition': 'COMPILE MODE ERROR !\n',
 'postpone-close-alone': '[[ ?\n',
}
for case in json.loads(a.reference.read_text())['cases']:
    name=case['case'];expected=policy.get(name,case['stdout']);code=1 if name in policy else case['exit']
    r=subprocess.run([sigma,'--max-steps','100000','-e',case['source']+' DEPTH . BYE'],input=b'',capture_output=True,timeout=10)
    assert r.returncode==code and r.stdout.decode(errors='replace')==expected,(name,r.returncode,r.stdout,code,expected,r.stderr)
    results.append({'case':name,'sigma_error_check':name in policy})
folder=a.reference.parent.resolve();image=folder/'quotations.sigma';exe=folder/'quotations-program'
source=': Q [: [: 7 ;] ;] ; : M ]] 8 + [[ ; IMMEDIATE : T 3 M ; : STR ]] S" [[ ; IMMEDIATE : S STR text" ; : RUN Q EXECUTE EXECUTE . T . S TYPE ; '
r=subprocess.run([sigma,'-e',source+f'SAVE {image} SAVESYS {exe} BYE'],input=b'',capture_output=True,timeout=20)
assert r.returncode==0,(r.stdout,r.stderr)
for command in ([sigma,'-e',f': BEFORE 1 ; LOAD-DICTIONARY {image} RUN DEPTH . BYE'],[str(exe),'-e','RUN DEPTH . BYE']):
    r=subprocess.run(command,input=b'',capture_output=True,timeout=20)
    assert r.returncode==0 and r.stdout==b'7 11 text0 ',(command,r.returncode,r.stdout,r.stderr)
report={'pass':True,'comparisons':sum(not r['sigma_error_check'] for r in results),'sigma_error_checks':sum(r['sigma_error_check'] for r in results),'native_image_checks':2,'cases':results}
a.reference.with_name('comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='cases'}))
# Native EOF must reject compiler state that could span ordinary interactive lines.
for source in (': PARTIAL [: 7', ': PARTIAL ]] 7'):
    r=subprocess.run([sigma,'-e',source],input=b'',capture_output=True,timeout=10)
    assert r.returncode==1 and b'DEFINITION ERROR !' in r.stdout,(source,r.returncode,r.stdout,r.stderr)
report['native_eof_checks']=2
a.reference.with_name('comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'pass':True,'native_eof_checks':2}))
