#!/usr/bin/env python3
"""Validate P07a observations and the approved strict Sigma restriction policy."""
import argparse
import json
import pathlib
import subprocess
p = argparse.ArgumentParser()
p.add_argument('--sigma', type=pathlib.Path, default=pathlib.Path('zig-out/bin/sigma'))
p.add_argument('--reference', type=pathlib.Path, default=pathlib.Path('.work/p07a-check/spec-probes.json'))
a = p.parse_args()
results=[]
for case in json.loads(a.reference.read_text())['cases']:
    name=case['case']; expected=case['stdout']; code=case['exit']; difference=False
    if name in ('bracket-comp-tick-interpret','postpone-comma-no-definition','execute-exit-interpret') or any(name == word+suffix for word in ('COMPILE-ONLY','RESTRICT') for suffix in (':interpret',':synonym',':STATE-false')):
        expected='COMPILE MODE ERROR !\n'; code=1; difference=True
    elif any(name == word+suffix for word in ('COMPILE-ONLY','RESTRICT') for suffix in (':anonymous',':no-user-definition')):
        expected='DEFINITION ERROR !\n'; code=1; difference=True
    r=subprocess.run([str(a.sigma.resolve()),'--max-steps','100000','-e',case['source']+' DEPTH . BYE'],input=b'',capture_output=True,timeout=10)
    actual=r.stdout.decode(errors='replace')
    assert r.returncode==code and actual==expected, (name,r.returncode,actual,code,expected,r.stderr)
    results.append({'case':name,'approved_difference':difference})
report={'pass':True,'comparisons':sum(not x['approved_difference'] for x in results),'approved_difference_checks':sum(x['approved_difference'] for x in results),'cases':results}
a.reference.with_name('comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='cases'}))
folder=a.reference.parent.resolve()
image=folder/'tokens.sigma'; executable=folder/'tokens-program'
source = ": X 77 ; COMPILE-ONLY SYNONYM Y X : M [ COMP' DUP POSTPONE, ] ; IMMEDIATE : T 4 M ; : A 8 ; : EXIT-M ['] A EXECUTE-EXIT 99 ; : BAD S\" Y\" EVALUATE ; : RUN T . . EXIT-M . ['] X EXECUTE . ['] BAD CATCH . ; "
r=subprocess.run([str(a.sigma.resolve()),'-e',source+f'SAVE {image} SAVESYS {executable} BYE'],input=b'',capture_output=True,timeout=20)
assert r.returncode==0,(r.returncode,r.stdout,r.stderr)
for command in ([str(a.sigma.resolve()),'-e',f': BEFORE 9 ; LOAD-DICTIONARY {image} RUN DEPTH . BYE'],[str(executable),'-e','RUN DEPTH . BYE']):
    r=subprocess.run(command,input=b'',capture_output=True,timeout=20)
    assert r.returncode==0 and r.stdout==b'4 4 8 77 -14 0 ',(command,r.returncode,r.stdout,r.stderr)
report['native_image_checks']=2
a.reference.with_name('comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'pass':True,'native_image_checks':2}))
