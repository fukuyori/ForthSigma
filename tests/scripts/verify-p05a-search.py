#!/usr/bin/env python3
"""Behavioral comparisons only; no Gforth implementation code is incorporated."""
import argparse, json, pathlib, subprocess, os, pwd
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path('.work/p05a-search-check').resolve();root.mkdir(parents=True,exist_ok=True)
for directory in ['first','second','日本語 dir','source','home']:(root/directory).mkdir(exist_ok=True)
for filename,text in [('first/name','A'),('second/name','B'),('second/only','C'),('日本語 dir/名前','D'),('source/local','E'),('home/item','F')]: (root/filename).write_text(text)
b=a.gforth_build.resolve(); commands={'sigma':[str(pathlib.Path('zig-out/bin/sigma').resolve()),'--max-steps','100000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
base='VARIABLE P : SHOW OPEN-PATH-FILE DUP IF . ELSE DROP TYPE SPACE DUP KEY-FILE . CLOSE-FILE THROW THEN ; '
cases=[]
for dirs in ['first|second','second|first','missing|second','|first','first||second','first|','missing']:
 for name in ['name','only','absent']:
  cases.append((dirs+':'+name,base+'P PATH= '+dirs+' S" '+name+'" P SHOW'))
for name in ['~+/first/name','./first/name',str(root/'first/name'),'./first//../second/name','./first/./name','./first/../second/only','./../p05a-search-check/first/name','~/'+str((root/'home/item').relative_to(pathlib.Path.home()))]:
 cases.append((name,base+'P CLEAR-PATH S" '+name+'" P SHOW'))
cases.append(('named-home',base+'P CLEAR-PATH S" ~'+pwd.getpwuid(os.getuid()).pw_name+'/'+str((root/'home/item').relative_to(pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir)))+'" P SHOW'))
for prefix in ['first/../second/', 'first/./../second/', 'first//../second/', './second/', '../p05a-search-check/second/', 'second//', 'second/./']:
 cases.append(('compact:'+prefix,base+'P PATH= '+prefix+' S" only" P SHOW'))
cases.append(('spaces',base+'S" 日本語 dir" P ALSO-PATH S" 名前" P SHOW'))
cases.append(('file>path','VARIABLE P P PATH= first|second S" only" P FILE>PATH TYPE'))
cases.append(('empty',base+'P CLEAR-PATH S" name" P SHOW'))
# A file makes ./ refer to its source directory, including path entries of ./.
(root/'source/run.fs').write_text('VARIABLE P P PATH= ./ S" local" P FILE>PATH TYPE CR S" ./local" P FILE>PATH TYPE CR\n')
cases.append(('source','INCLUDE source/run.fs'))
(root/'source/eval.fs').write_text('VARIABLE P : GET S" ./local" P FILE>PATH TYPE ; : EV S" GET" EVALUATE ; \' EV CATCH .\n')
cases.append(('evaluate-source','INCLUDE source/eval.fs'))
results=[]
for title,source in cases:
 outputs={}
 for runtime,cmd in commands.items():
  r=subprocess.run(cmd+[source+' DEPTH . BYE'],cwd=root,env=os.environ,input='',text=True,capture_output=True,timeout=15)
  assert r.returncode==0,(title,runtime,r.returncode,r.stdout,r.stderr)
  outputs[runtime]=r.stdout
 assert outputs['sigma']==outputs['gforth'],(title,outputs)
 results.append(title)
# The designated Gforth leaks an extra stack cell for bare ~+; keep Sigma balanced.
quirk={}
for runtime,cmd in commands.items():
 r=subprocess.run(cmd+[base+'P CLEAR-PATH S" ~+" P SHOW DEPTH . BYE'],cwd=root,env=os.environ,input='',capture_output=True,text=True,timeout=15)
 assert r.returncode==0,(runtime,r.stderr)
 quirk[runtime]=r.stdout
assert quirk=={'sigma':'-514 0 ','gforth':'-514 1 '},quirk
report={'words':2,'bare_tilde_plus_stack_difference':quirk,'gforth_comparisons':len(results),'pass':True,'cases':results}
(root/'comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps(report,ensure_ascii=False))
