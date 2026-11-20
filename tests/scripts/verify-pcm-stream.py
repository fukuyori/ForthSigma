#!/usr/bin/env python3
"""Exercise public PCM in owned processes and SAVESYS apps; all submitted frames are silence."""
import argparse,json,os,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('sigma',type=Path);p.add_argument('--no-image',action='store_true');args=p.parse_args();binary=args.sigma.resolve();reports=[]
work=ROOT/'.work/1128';work.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='public-',dir=work) as d:
 folder=Path(d)
 def run(code,expected=0,exe=binary):
  command=[str(exe),'-e',code] if exe==binary else [str(exe)]
  r=subprocess.run(command,cwd=folder,input=b'',capture_output=True,timeout=10)
  assert r.returncode==expected and not r.stderr,(command,r.returncode,r.stdout,r.stderr)
  return r.stdout.decode('utf-8')
 prefix='REQUIRE-AUDIO ALSO AUDIO '
 stream=prefix+'48000 2 4096 PCM-OPEN THROW CONSTANT P '
 code=stream+'CREATE BUF 16384 ALLOT BUF 16384 ERASE BUF 4096 P PCM-WRITE THROW . 4096 1000 P PCM-WAIT THROW . 1 1000 P PCM-STOP THROW . P PCM-QUEUED THROW . P PCM-CLOSE . P PCM-QUEUED SWAP DROP . BYE'
 assert run(code).split()==['4096','-1','-1','0','0','-521']
 reports.append('copied-silent-stereo-write-wait-drain-stop-close-stale-id')
 code=stream+': BAD -1 1 P PCM-WRITE 2DROP ; \' BAD CATCH . P PCM-CLOSE . BYE'
 assert run(code).split()==['-9','0']
 reports.append('invalid-memory-catch-and-close-recovery')
 code=stream+'48000 1 4096 PCM-OPEN SWAP DROP . 0 0 P PCM-STOP 2DROP P PCM-CLOSE . BYE'
 assert run(code).split()==['-528','0']
 reports.append('one-stream-busy-and-close-pending-stop')
 if not args.no_image:
  filename='saved-audio'+('.exe' if os.name=='nt' else '')
  code=stream+': MAIN 48000 1 4096 PCM-OPEN THROW DUP PCM-CLOSE THROW DROP ." APP-OK" ; \' MAIN APP-ENTRY! SAVESYS '+filename+' BYE'
  assert not run(code).strip()
  saved=folder/filename;assert saved.exists();assert run('',exe=saved).strip()=='APP-OK'
  reports.append('active-stream-savesys-does-not-persist-live-ownership')
  # A full restore is internal; LOAD is append and must preserve target ownership.
  code=stream+'SAVE owned.img P PCM-CLOSE THROW LOAD-DICTIONARY owned.img 48000 2 4096 PCM-OPEN THROW PCM-CLOSE . BYE'
  assert run(code).split()==['0']
  reports.append('save-load-reopen-without-reviving-old-handle')
  code=stream+'SAVE active.img LOAD-DICTIONARY active.img P PCM-QUEUED THROW DROP P PCM-CLOSE . BYE'
  assert run(code).split()==['0']
  reports.append('load-while-active-preserves-target-pcm')
print(json.dumps(reports,indent=2))
