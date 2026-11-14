#!/usr/bin/env python3
"""Check native editor handoff with a recording stand-in, never a real editor."""
import argparse,json,os,pathlib,shlex,subprocess,sys
p=argparse.ArgumentParser();p.add_argument('--sigma',type=pathlib.Path,default=pathlib.Path('zig-out/bin/sigma'));p.add_argument('--reference',type=pathlib.Path,default=pathlib.Path('.work/p09b-check/spec-probes.json'));a=p.parse_args();sigma=str(a.sigma.resolve());folder=(a.reference.parent/'editor-native').resolve();folder.mkdir(parents=True,exist_ok=True)
temporary=folder/'temporary files';temporary.mkdir(exist_ok=True);log=folder/'calls.jsonl';stub=folder/'record editor.py'
stub.write_text('''import json,os,pathlib,stat,sys
p=pathlib.Path(sys.argv[-1]);report=p.name.startswith('sigma-editor-')
r={'line':sys.argv[-2],'path':str(p),'report':report}
if report:r.update(text=p.read_text(),permissions=stat.S_IMODE(p.stat().st_mode))
with open(os.environ['SIGMA_EDITOR_LOG'],'a',encoding='utf-8') as f:f.write(json.dumps(r,ensure_ascii=False)+'\\n')
sys.exit(int(os.environ.get('SIGMA_EDITOR_EXIT','0')))
''')
name="日本語 source'$(echo BAD).fs" if os.name!='nt' else '日本語 source & argument.fs'
source=folder/name;original='\\ lead\n: EDIT-NATIVE 11 ;\n: EDIT-USE EDIT-NATIVE ;\n';source.write_text(original)
prefix=subprocess.list2cmdline([sys.executable,str(stub)]) if os.name=='nt' else shlex.join([sys.executable,str(stub)])
env=dict(os.environ,EDITOR=prefix,TMPDIR=str(temporary),SIGMA_EDITOR_LOG=str(log))
include=f'S" {source}" INCLUDED '
def run(code,environment=None,program=None):
 log.unlink(missing_ok=True)
 r=subprocess.run([program or sigma,'--max-steps','100000','-e',code],env=environment or env,capture_output=True,input=b'',timeout=20)
 calls=[json.loads(x) for x in log.read_text().splitlines()] if log.exists() else []
 return r,calls
checks=0
r,calls=run(include+'0 TO BEFORE-LOCATE 0 TO AFTER-LOCATE EDIT EDIT-NATIVE L G N G B G BYE')
assert r.returncode==0 and [x['line'] for x in calls]==['+2','+2','+3','+2'],(r.returncode,r.stdout,r.stderr,calls)
assert all(x['path']==str(source) and not x['report'] for x in calls),calls
assert b'BAD' not in r.stdout.replace(str(source).encode(),b''),(r.stdout,r.stderr)
assert source.read_text()==original;checks+=1
modes=[('gg','GG 0 WW 1 WW',1),('gg-default','GG GG 0 WW 1 WW',2),('ll-once','GG GG LL 0 WW 1 WW',1),('ll-default','GG GG LL LL 0 WW 1 WW',0)]
reference={x['case']:x for x in json.loads(a.reference.read_text())['cases']}
for name,code,count in modes:
 ref=reference[name];assert ref['exit']==0 and ref['stdout'].count('EDITOR +')==count,(name,ref)
 r,calls=run(include+'BROWSE EDIT- '+code+' BYE')
 assert r.returncode==0 and len(calls)==count,(name,r.returncode,r.stdout,r.stderr,calls)
 checks+=1
r,calls=run(include+'PREPEND-WHERE WHEREG EDIT-NATIVE BYE')
assert r.returncode==0 and r.stdout==b'' and len(calls)==1,(r.returncode,r.stdout,r.stderr,calls)
report=calls[0];assert report['report'] and report['line']=='+1' and (str(source)+':3:12:') in report['text'],report
assert not pathlib.Path(report['path']).exists(),report
if os.name!='nt':assert report['permissions'] & 0o077==0,report
checks+=1
bad=dict(env,SIGMA_EDITOR_EXIT='7');r,calls=run(include+'WHEREG EDIT-NATIVE',bad)
assert r.returncode==1 and b'HOST FUNCTION ERROR !' in r.stdout and len(calls)==1,(r.returncode,r.stdout,r.stderr,calls)
assert not pathlib.Path(calls[0]['path']).exists(),calls;checks+=1
missing=dict(env);missing.pop('EDITOR',None)
r,calls=run(include+'EDIT EDIT-NATIVE',missing)
assert r.returncode==1 and b'HOST FUNCTION UNAVAILABLE !' in r.stdout and not calls,(r.returncode,r.stdout,r.stderr,calls);checks+=1
r,calls=run(include+'WHEREG EDIT-NATIVE',dict(env,EDITOR='   '))
assert r.returncode==1 and b'HOST FUNCTION UNAVAILABLE !' in r.stdout and not calls,(r.returncode,r.stdout,r.stderr,calls);checks+=1
image=folder/'editor.sigma';executable=folder/('editor-program.exe' if os.name=='nt' else 'editor-program')
r,calls=run(include+f'SAVE {image} SAVESYS {executable} BYE');assert r.returncode==0,(r.stdout,r.stderr)
for program,code in [(sigma,f'LOAD-DICTIONARY {image} EDIT EDIT-NATIVE BYE'),(str(executable),'EDIT EDIT-NATIVE BYE')]:
 r,calls=run(code,program=program)
 assert r.returncode==0 and len(calls)==1 and calls[0]['path']==str(source) and calls[0]['line']=='+2',(r.returncode,r.stdout,r.stderr,calls)
 checks+=1
assert source.read_text()==original
if os.name!='nt':assert not list(temporary.glob('sigma-editor-*'))
report={'pass':True,'native_editor_checks':checks,'reference_mode_checks':len(modes),'native_image_checks':2}
a.reference.with_name('editor-comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))
