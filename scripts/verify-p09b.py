#!/usr/bin/env python3
"""P09b stack and source-navigation chunks: reference comparisons, safe bounds and native setting lifetime.

Source navigation retains Sigma LOCATE formatting and one-based line numbers.
Sigma retains its existing F.S field format; Gforth's smart rendering differs.
"""
import argparse,json,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--sigma',type=pathlib.Path,default=pathlib.Path('zig-out/bin/sigma'));p.add_argument('--reference',type=pathlib.Path,default=pathlib.Path('.work/p09b-check/spec-probes.json'));a=p.parse_args();sigma=str(a.sigma.resolve());rows=[]
def run(source):return subprocess.run([sigma,'--max-steps','100000','-e',source],capture_output=True,input=b'',timeout=20)
for c in json.loads(a.reference.read_text())['cases']:
 name=c['case']
 if not (name.startswith('dot-s:') and name!='dot-s:-1' or name in ['clear-data','clear-float','clear-both','clear-return','before-set','slash-g']):continue
 r=run(c['source']+' DEPTH . BYE');assert (r.returncode,r.stdout.decode())==(c['exit'],c['stdout']),(name,r.returncode,r.stdout,r.stderr,c)
 rows.append(name)
policies=[('limits-default','MAXDEPTH-.S @ . F.S-PRECISION . DEPTH . BYE',0,b'9 14 0 '),('negative-limit','-1 MAXDEPTH-.S ! 10 .S',1,b'NUMBER ERROR !\n'),('float-width','8 TO F.S-PRECISION 1E 2E 1 MAXDEPTH-.S ! F.S DEPTH . BYE',0,b'<2> 2.0000E0 0 '),('float-invalid','0 TO F.S-PRECISION 1E F.S',1,b'NUMBER ERROR !\n'),('float-overflow','4097 TO F.S-PRECISION 1E F.S',1,b'STRING TOO LONG !\n')]
for n,s,status,expected in policies:
 r=run(s);assert (r.returncode,r.stdout)==(status,expected),(n,r.returncode,r.stdout,r.stderr)
folder=a.reference.parent.resolve();image=folder/'stack.sigma';exe=folder/'stack-program'
source='2 MAXDEPTH-.S ! 8 TO F.S-PRECISION : SETTINGS MAXDEPTH-.S @ . F.S-PRECISION . ; '
r=run(source+f'SAVE {image} SAVESYS {exe} BYE');assert r.returncode==0,(r.stdout,r.stderr)
for cmd,expected in [([sigma,'-e',f'LOAD-DICTIONARY {image} SETTINGS BYE'],b'9 14 '),([str(exe),'-e','SETTINGS BYE'],b'2 8 ')]:
 r=subprocess.run(cmd,capture_output=True,input=b'',timeout=20);assert r.returncode==0 and r.stdout==expected,(cmd,r.returncode,r.stdout,r.stderr)
nav_source=folder/'navigation-native.fs'
nav_source.write_text('\\ one\n\\ two\n: NAV-NATIVE 11 ;\n\\ four\n\\ five\n\\ six\n')
path=str(nav_source);header=lambda n:(path+':'+str(n)+'\n').encode()
expected=header(3)+b': NAV-NATIVE 11 ;\n'+header(2)+b'\\ two\n: NAV-NATIVE 11 ;\n\\ four\n'+header(5)+b'\\ five\n\\ six\n'+header(2)+b'\\ two\n: NAV-NATIVE 11 ;\n\\ four\n'
r=run(f'INCLUDE {path} 1 TO BEFORE-LOCATE 1 TO AFTER-LOCATE \' NAV-NATIVE XT-LOCATE L N B BYE')
assert r.returncode==0 and r.stdout==expected,('navigation',r.returncode,r.stdout,r.stderr,expected)
r=run('0 WARNINGS ! L N B 3 TO BEFORE-LOCATE 12 TO AFTER-LOCATE BEFORE-LOCATE . AFTER-LOCATE . BYE')
assert r.returncode==0 and r.stdout==b'3 12 ',('no-location',r.returncode,r.stdout,r.stderr)
r=run('1 \\G ignore 2\n3 . . BYE');assert r.returncode==0 and r.stdout==b'3 1 ',('documentation-comment',r.returncode,r.stdout,r.stderr)
report={'pass':True,'stage':'stack and source navigation (12/30 words)','navigation_checks':3,'comparisons':len(rows),'sigma_policy_checks':len(policies),'native_image_checks':2};a.reference.with_name('stack-comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
