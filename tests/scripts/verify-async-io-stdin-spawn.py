#!/usr/bin/env python3
"""A child inherits stdin after the parent's migrated reader is paused."""
import argparse,json,queue,subprocess,sys,tempfile,threading
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def run(sigma):
 with tempfile.TemporaryDirectory(prefix='async-spawn-',dir=ROOT/'.work') as directory:
  work=Path(directory);child=work/'child.py';source=work/'spawn.fs'
  child.write_text('import sys\nprint("CHILD-READY",flush=True)\nb=sys.stdin.buffer.read(1)\nprint("CHILD",b[0] if b else -1,flush=True)\n')
  source.write_text(f'''REQUIRE-EXTENSION ALSO EXTENSION DECIMAL
CREATE IDS STDIN , IDS 1 3000 WAIT-FILES THROW DROP
PAD 1 STDIN READ-AVAILABLE THROW DROP DROP
." PARENT " PAD C@ . CR STDOUT FLUSH-FILE THROW
S" {sys.executable} {child}" SYSTEM
STDIN KEY-FILE ." AFTER " . CR BYE
''')
  process=subprocess.Popen([str(sigma.resolve()),str(source)],cwd=ROOT,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  lines=queue.Queue()
  def receive():
   while True:
    line=process.stdout.readline();lines.put(line)
    if not line:return
  threading.Thread(target=receive,daemon=True).start()
  try:
   process.stdin.write(b'A');process.stdin.flush();seen=[]
   while True:
    line=lines.get(timeout=8);assert line,(seen,process.poll());seen.append(line)
    if b'CHILD-READY' in line:break
   process.stdin.write(b'B');process.stdin.close()
   process.wait(timeout=8)
   while True:
    line=lines.get(timeout=2)
    if not line:break
    seen.append(line)
   out=b''.join(seen).decode();err=process.stderr.read()
   assert process.returncode==0 and not err and 'PARENT 65' in out and 'CHILD 66' in out and 'AFTER -1' in out,(process.returncode,out,err)
   return {'platform':sys.platform,'case':'stdin-reader-paused-before-system','stdout':out}
  finally:
   if process.poll() is None:process.kill();process.wait()
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--sigma',required=True,type=Path);p.add_argument('--output',type=Path);a=p.parse_args();r=run(a.sigma)
 if a.output:a.output.write_text(json.dumps(r,indent=2)+'\n')
 print(json.dumps(r))
