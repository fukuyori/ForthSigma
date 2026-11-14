#!/usr/bin/env python3
"""Check NS steady-clock contracts, signal interruption and terminal input retention."""
import argparse, pathlib, subprocess, json, os, time, signal, select, sys
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True);a=p.parse_args()
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path('zig-out/bin/sigma').resolve()),'--max-steps','1000000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
results=[]
for duration in [-1000000,-1,0,1,1000,1000000,20000000,100000000]:
 for runtime,cmd in commands.items():
  code=f'2VARIABLE START NTIME START 2! {duration}. NS NTIME START 2@ D- D. DEPTH . BYE'
  r=subprocess.run(cmd+[code],input='',capture_output=True,text=True,timeout=10)
  assert r.returncode==0,(duration,runtime,r.stdout,r.stderr)
  elapsed,depth=map(int,r.stdout.split());assert depth==0 and elapsed>=max(0,duration),(duration,runtime,elapsed,depth)
  results.append({'duration_ns':duration,'runtime':runtime,'elapsed_ns':elapsed})
for runtime,cmd in commands.items():
 r=subprocess.run(cmd+[': W 170141183460469231731687303715884105727. NS ; \' W CATCH . DEPTH . BYE'],input='',capture_output=True,text=True,timeout=10)
 assert r.returncode==0 and r.stdout.split()==['-11','0'],(runtime,r.stdout,r.stderr)
 r=subprocess.run(cmd+['1000000. NS STDIN KEY-FILE . STDIN KEY-FILE . DEPTH . BYE'],input=b'\x03A',capture_output=True,timeout=10)
 assert r.returncode==0 and r.stdout.split()==[b'3',b'65',b'0'],(runtime,r.stdout,r.stderr)
 r=subprocess.run(cmd+['STDIN KEY?-FILE DROP 1000000. NS STDIN KEY-FILE . STDIN KEY-FILE . DEPTH . BYE'],input=b'A\x03',capture_output=True,timeout=10)
 assert r.returncode==0 and r.stdout.split()==[b'65',b'3',b'0'],(runtime,r.stdout,r.stderr)

def read_until(fd,token,captured,timeout=5):
 end=time.monotonic()+timeout
 while token not in captured:
  assert time.monotonic()<end,('timeout',token,captured)
  if select.select([fd],[],[],.02)[0]:
   part=os.read(fd,8192);assert part,('EOF',token,captured);captured+=part
 return captured
# Recovered waits can be followed by another NS; no sticky cancellation state.
for duration in [2000000000,18446744073709551739]:
 for runtime,cmd in commands.items():
  child=subprocess.Popen(cmd+[f': W {duration}. NS ; ." READY" STDOUT FLUSH-FILE THROW \' W CATCH . 1000000. NS DEPTH . BYE'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  try:
   got=read_until(child.stdout.fileno(),b'READY',b'');time.sleep(.03);child.send_signal(signal.SIGINT)
   tail,errors=child.communicate(timeout=3);got+=tail
   assert child.returncode==0 and b'-28 0 ' in got,(runtime,child.returncode,got,errors)
  finally:
   if child.poll() is None:child.kill();child.wait()
pty_results=[]
if sys.platform!='win32':
 import pty,termios,fcntl,errno
 def attach():
  os.setsid();fcntl.ioctl(0,termios.TIOCSCTTY,0)
 def stable(settings):
  result=settings.copy();result[3]&=~getattr(termios,'PENDIN',0);return result
 cases=[
  ('canonical-interrupt',False,True,b'A\x03B',b'65 66 '),
  ('raw-interrupt',True,True,b'A\x03B',b'65 66 '),
  ('raw-special',True,False,b'\x1b[AZ',b'-1 2147483650 90 '),
  ('raw-control',True,False,b'\x1a\x1c',b'26 28 '),
  ('canonical-normal',False,False,b'AB',b'65 66 '),
 ]
 for name,raw,interrupting,data,expected in cases:
  code=('EKEY? DROP ' if raw else '')+'." BEFORE" CR 100 MS '
  if interrupting:code+=': W 2000000000. NS ; ." READY" \' W CATCH . '
  else:code+='." READY" 150000000. NS '
  code+='." AFTER" CR 100 MS '+('EKEY EKEY>FKEY . . EKEY . ' if name=='raw-special' else 'EKEY . EKEY . ')+'BYE'
  master,slave=pty.openpty()
  child=subprocess.Popen(commands['sigma']+[code],stdin=slave,stdout=slave,stderr=slave,preexec_fn=attach)
  captured=b''
  try:
   captured=read_until(master,b'BEFORE',captured);before=termios.tcgetattr(slave)
   captured=read_until(master,b'READY',captured);time.sleep(.03);os.write(master,data)
   captured=read_until(master,b'AFTER',captured);after=termios.tcgetattr(slave)
   assert stable(before)==stable(after),(name,'termios',before,after,captured)
   if interrupting:assert b'-28 AFTER' in captured,(name,captured)
   end=time.monotonic()+5
   while child.poll() is None:
    assert time.monotonic()<end,(name,captured)
    if select.select([master],[],[],.02)[0]:
     try:captured+=os.read(master,8192)
     except OSError as error:
      if error.errno!=errno.EIO:raise
   while select.select([master],[],[],0)[0]:
    try:
     part=os.read(master,8192)
     if not part:break
     captured+=part
    except OSError as error:
     if error.errno!=errno.EIO:raise
     break
   assert child.returncode==0 and expected in captured,(name,child.returncode,captured)
   pty_results.append(name)
  finally:
   if child.poll() is None:child.kill();child.wait()
   os.close(master);os.close(slave)
report={'word':'NS','duration_contract_cases':8,'duration_runtime_checks':len(results),'range_cases':2,'redirected_cases':4,'signal_recovery_cases':4,'sigma_pty_cases':pty_results,'timing_results':results,'pass':True}
root=pathlib.Path('.work/p05b-ns-check');root.mkdir(parents=True,exist_ok=True);(root/'comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='timing_results'}))
