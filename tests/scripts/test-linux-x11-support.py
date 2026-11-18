#!/usr/bin/env python3
"""Linux X11 test-helper regressions: framing, cleanup, auth and skip status.
Build -Dx11=true; SIGMA_TEST_BINARY and SIGMA_TEST_XVFB select executables.
"""
from pathlib import Path
import sys,os,tempfile,subprocess,json,time,socket,struct,ctypes,signal
from linux_x11_test_support import OwnedXvfb,SigmaSession,require_linux
require_linux()
ROOT=Path(__file__).resolve().parents[2]
SIGMA=os.environ.get('SIGMA_TEST_BINARY',str(ROOT/'zig-out/bin/sigma'))
# Keep the failure fixture's killed grandchild ours to reap.
libc=ctypes.CDLL(None)
libc.prctl.argtypes=[ctypes.c_int,ctypes.c_ulong,ctypes.c_ulong,ctypes.c_ulong,ctypes.c_ulong]
assert libc.prctl(36,1,0,0,0)==0
with tempfile.TemporaryDirectory(prefix='sigma-reader-check-') as folder:
 executable=Path(folder)/'fixture'
 childpid=Path(folder)/'child.pid'
 executable.write_text('#!'+sys.executable+'\n'+r'''import os,sys,time,signal,subprocess
signal.signal(signal.SIGTERM,signal.SIG_IGN)
p=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)'])
with open(sys.argv[2],'w') as out: out.write(str(p.pid))
os.write(2,b'x'*131072)
os.write(1,b'READY\npartial')
time.sleep(30)
''')
 executable.chmod(0o700)
 with SigmaSession(str(executable),str(childpid),dict(os.environ)) as session:
  assert session.line(5)==b'READY'
  assert childpid.read_text().strip().isdigit()
  assert os.fstat(session.stderr.fileno()).st_size==131072
  start=time.monotonic()
  try:session.line(.2)
  except TimeoutError:pass
  else:raise AssertionError('partial line did not time out')
  assert session.buffer==b'partial',session.buffer
  parent=session.process.pid
 assert session.process.returncode==-signal.SIGKILL
 assert time.monotonic()-start<5
 pid=int(childpid.read_text())
 assert os.waitpid(pid,0)[0]==pid
 assert not Path(f'/proc/{parent}').exists() and not Path(f'/proc/{pid}').exists()
 partial=True
with OwnedXvfb() as server:
 sock=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);sock.settimeout(2)
 try:
  sock.connect(f'/tmp/.X11-unix/X{server.number}')
  sock.sendall(struct.pack('<BBHHHHH',ord('l'),0,11,0,0,0,0))
  assert sock.recv(1)==b'\0','unauthenticated client accepted'
 finally:sock.close()
 with SigmaSession(SIGMA,'REQUIRE-GRAPHICS ALSO GRAPHICS 2 2 GFX-INIT DISPLAY-WINDOW SHOW ." AUTH-OK" CR BYE',server.environment()) as session:
  assert session.line()==b'AUTH-OK';session.finish()
 env=dict(os.environ,PATH='/missing/sigma-tools');env.pop('SIGMA_TEST_XVFB',None)
 p=subprocess.run([sys.executable,str(ROOT/'tests/scripts/test-linux-auto-display.py')],env=env,capture_output=True,text=True,timeout=5)
 assert p.returncode==77,(p.returncode,p.stdout,p.stderr)
 print(json.dumps({'partial_line_timeout':partial,'stderr_128k_no_pipe_deadlock':True,'sigterm_ignored_kill_fallback':True,'owned_parent_and_descendant_reaped':True,'unauthenticated_x11_rejected':True,'authenticated_native_show':True,'missing_tools_exit':p.returncode},indent=2))
