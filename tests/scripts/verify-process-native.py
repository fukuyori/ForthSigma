#!/usr/bin/env python3
"""Exercise the native C backend with owned children, before Forth integration."""
import argparse,ctypes,errno,json,os,signal,subprocess,sys,tempfile,threading,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def run(library):
 api=ctypes.CDLL(str(library.resolve()));P=ctypes.c_void_p;U=ctypes.c_uint32;I=ctypes.c_int
 api.sigma_proc_new.restype=P
 api.sigma_proc_test_pid.argtypes=[P];api.sigma_proc_test_pid.restype=ctypes.c_uint64
 api.sigma_proc_stream.argtypes=[P,ctypes.c_uint];api.sigma_proc_stream.restype=P
 api.sigma_proc_status.argtypes=[P,ctypes.POINTER(U),ctypes.POINTER(U)]
 api.sigma_proc_test_fault.argtypes=[ctypes.c_uint]
 api.sigma_proc_signal.argtypes=[P,I];api.sigma_proc_destroy.argtypes=[P];api.sigma_proc_abort.argtypes=[P,ctypes.c_uint]
 api.sigma_proc_test_read.argtypes=[P,ctypes.c_uint,P,ctypes.c_size_t];api.sigma_proc_test_read.restype=ctypes.c_ssize_t
 api.sigma_proc_test_write.argtypes=[P,P,ctypes.c_size_t];api.sigma_proc_test_write.restype=ctypes.c_ssize_t
 api.sigma_proc_test_close.argtypes=[P,ctypes.c_uint]
 if os.name=='nt':api.sigma_proc_start_windows.argtypes=[P,ctypes.c_wchar_p,ctypes.c_wchar_p,ctypes.c_wchar_p,ctypes.c_wchar_p,ctypes.POINTER(I)]
 else:api.sigma_proc_start_posix.argtypes=[P,ctypes.c_char_p,ctypes.POINTER(ctypes.c_char_p),ctypes.POINTER(ctypes.c_char_p),ctypes.c_char_p,ctypes.POINTER(I)]
 class Process:
  def __init__(self):self.p=api.sigma_proc_new();assert self.p
  def start(self,args,cwd=None,env=None,modes=(0,0,0),exe=None):
   env=dict(os.environ) if env is None else env;cwd=str(cwd or ROOT);exe=exe or args[0];mode=(I*3)(*modes)
   if os.name=='nt':
    command=ctypes.create_unicode_buffer(subprocess.list2cmdline(args));block=ctypes.create_unicode_buffer('\0'.join(k+'='+v for k,v in sorted(env.items(),key=lambda pair:pair[0].upper()))+'\0\0')
    return api.sigma_proc_start_windows(self.p,exe,command,block,cwd,mode)
   argv=(ctypes.c_char_p*(len(args)+1))(*(a.encode() for a in args),None)
   entries=[(k+'='+v).encode() for k,v in env.items()];block=(ctypes.c_char_p*(len(entries)+1))(*entries,None)
   return api.sigma_proc_start_posix(self.p,os.fsencode(exe),argv,block,os.fsencode(cwd),mode)
  def status(self):
   state=U();code=U();error=api.sigma_proc_status(self.p,ctypes.byref(state),ctypes.byref(code));assert error==0,error;return state.value,code.value
  def wait(self,timeout=8):
   until=time.monotonic()+timeout
   while True:
    state=self.status()
    if state[0]!=1:return state
    assert time.monotonic()<until,'process wait timed out';time.sleep(.005)
  def communicate(self,data=b''):
   results=[b'',b''];errors=[]
   def reader(index):
    try:
     parts=[];buffer=ctypes.create_string_buffer(65536)
     while True:
      n=api.sigma_proc_test_read(self.p,index+1,buffer,len(buffer));assert n>=0,(index,n)
      if not n:break
      parts.append(buffer.raw[:n])
     results[index]=b''.join(parts)
    except BaseException as e:errors.append(repr(e))
   readers=[threading.Thread(target=reader,args=(i,),daemon=True) for i in range(2)]
   for thread in readers:thread.start()
   timer=threading.Timer(10,lambda:api.sigma_proc_signal(self.p,1));timer.start()
   try:
    if data:
     buffer=ctypes.create_string_buffer(data);assert api.sigma_proc_test_write(self.p,buffer,len(data))==len(data)
    assert api.sigma_proc_test_close(self.p,0)==0
    for thread in readers:thread.join(8);assert not thread.is_alive(),'stream did not end'
    assert not errors,errors
    return results
   finally:timer.cancel();timer.join()
  def close(self):
   if self.p:
    result=api.sigma_proc_abort(self.p,3000);assert result==0,('native cleanup retained resources',result);self.p=None
  def __enter__(self):return self
  def __exit__(self,*args):self.close()
 reports=[]
 with tempfile.TemporaryDirectory(prefix='proc-native-',dir=ROOT/'.work') as directory:
  work=Path(directory);cwd=work/'作業 folder';cwd.mkdir()
  args=['','a b','a"b','tail\\','日 本','&|<>^%PATH%']
  code='import sys,os,json;print(json.dumps({"args":sys.argv[1:],"cwd":os.getcwd(),"value":os.getenv("SIGMA_NATIVE_VALUE"),"empty":os.getenv("SIGMA_NATIVE_EMPTY"),"absent":os.getenv("SIGMA_NATIVE_ABSENT")}))'
  env=dict(os.environ);env.update(SIGMA_NATIVE_VALUE='日本語',SIGMA_NATIVE_EMPTY='');env.pop('SIGMA_NATIVE_ABSENT',None)
  with Process() as p:
   assert p.start([sys.executable,'-c',code,*args],cwd,env)==0
   out,err=p.communicate();assert not err,err;value=json.loads(out)
   assert value=={'args':args,'cwd':str(cwd.resolve()),'value':'日本語','empty':'','absent':None},value
   assert p.wait()==(2,0);assert p.status()==(2,0)
  reports.append({'case':'argv-env-cwd','passed':True})
  code='import sys;sys.stdout.buffer.write(b"O"*200000);sys.stdout.buffer.flush();sys.stderr.buffer.write(b"E"*200000);sys.stderr.buffer.flush();d=sys.stdin.buffer.read();sys.stdout.buffer.write(d)'
  with Process() as p:
   assert p.start([sys.executable,'-c',code])==0;data=b'I'*131072;out,err=p.communicate(data)
   assert out==b'O'*200000+data and err==b'E'*200000,(len(out),len(err));assert p.wait()==(2,0)
  reports.append({'case':'concurrent-three-streams','passed':True})
  for exit_code in (127,259):
   with Process() as p:
    assert p.start([sys.executable,'-c',f'import os;os._exit({exit_code})'])==0;p.communicate()
    expected=exit_code if os.name=='nt' else exit_code&255
    actual=p.wait();assert actual==(2,expected),(exit_code,actual,expected)
   reports.append({'case':f'exit-{exit_code}','passed':True})
  for name,exe,bad_cwd in [('missing-executable',str(work/'does-not-exist.exe'),None),('missing-cwd',sys.executable,str(work/'absent-cwd'))]:
   with Process() as p:
    result=p.start([exe],cwd=bad_cwd);expected=errno.ENOTDIR if os.name=='nt' and bad_cwd else errno.ENOENT;assert result==expected,(name,result)
   reports.append({'case':name,'errno':result})
  for force in (0,1):
   with Process() as p:
    assert p.start([sys.executable,'-c','import time;time.sleep(30)'])==0
    assert api.sigma_proc_destroy(p.p)==errno.EBUSY
    assert api.sigma_proc_signal(p.p,force)==0
    expected=(2,137 if force else 143) if os.name=='nt' else (3,9 if force else 15)
    assert p.wait()==expected,(p.status(),expected)
   reports.append({'case':'kill' if force else 'term','passed':True})
  children=[Process() for _ in range(3)]
  try:
   for i,p in enumerate(children):assert p.start([sys.executable,'-c',f'print({i})'])==0
   for i,p in enumerate(children):out,err=p.communicate();assert out.strip()==str(i).encode() and not err;assert p.wait()==(2,0)
  finally:
   for p in children:p.close()
  reports.append({'case':'independent-processes','passed':True})
  # stdout is read directly here; merged stderr has no separate parent pipe.
  with Process() as p:
   assert p.start([sys.executable,'-c','import os;os.write(1,b"OUT");os.write(2,b"ERR")'],modes=(2,0,3))==0
   assert api.sigma_proc_test_close(p.p,0)==0
   buffer=ctypes.create_string_buffer(32);n=api.sigma_proc_test_read(p.p,1,buffer,32)
   assert buffer.raw[:n]==b'OUTERR';assert p.wait()==(2,0)
  reports.append({'case':'merge-and-null','passed':True})
  # A deliberately inheritable parent resource must not reach the child.
  if os.name=='nt':
   kernel=ctypes.WinDLL('kernel32',use_last_error=True)
   class Security(ctypes.Structure):_fields_=[('length',U),('descriptor',P),('inherit',I)]
   kernel.CreateEventW.argtypes=[ctypes.POINTER(Security),I,I,ctypes.c_wchar_p];kernel.CreateEventW.restype=P
   kernel.WaitForSingleObject.argtypes=[P,U];kernel.CloseHandle.argtypes=[P]
   attributes=Security(ctypes.sizeof(Security),None,1);marker=kernel.CreateEventW(ctypes.byref(attributes),1,0,None);assert marker
   try:
    code=f'import ctypes;k=ctypes.WinDLL("kernel32");k.SetEvent.argtypes=[ctypes.c_void_p];k.SetEvent({marker})'
    with Process() as p:
     assert p.start([sys.executable,'-c',code])==0;p.communicate();assert p.wait()==(2,0)
    assert kernel.WaitForSingleObject(marker,0)==258,'inheritable event leaked'
   finally:assert kernel.CloseHandle(marker)
  else:
   import fcntl
   reading,writing=os.pipe();marker=fcntl.fcntl(reading,fcntl.F_DUPFD,150);os.set_inheritable(marker,True)
   try:
    code=f'import os,errno;\ntry:os.fstat({marker})\nexcept OSError as e:assert e.errno==errno.EBADF\nelse:raise AssertionError("fd leaked")'
    with Process() as p:
     assert p.start([sys.executable,'-c',code])==0;out,err=p.communicate();assert p.wait()==(2,0),(out,err)
   finally:os.close(marker);os.close(reading);os.close(writing)
  reports.append({'case':'inheritable-parent-resource-excluded','passed':True})
  # Root termination is observed without relinquishing its group/job descendants.
  saved_subreaper=I()
  if sys.platform=='linux':
   libc=ctypes.CDLL(None,use_errno=True);assert libc.prctl(37,ctypes.byref(saved_subreaper),0,0,0)==0
   assert libc.prctl(36,1,0,0,0)==0
  try:
   with Process() as p:
    code='import subprocess,sys;child=subprocess.Popen([sys.executable,"-c","import time;time.sleep(30)"],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);print(child.pid,flush=True)'
    assert p.start([sys.executable,'-c',code])==0;out,err=p.communicate();assert p.wait()==(2,0),err
    descendant=int(out.strip())
    if os.name=='nt':
     kernel.OpenProcess.argtypes=[U,I,U];kernel.OpenProcess.restype=P
     handle=kernel.OpenProcess(0x100000,0,descendant);assert handle
     try:
      assert kernel.WaitForSingleObject(handle,0)==258
      assert api.sigma_proc_signal(p.p,1)==0
      assert kernel.WaitForSingleObject(handle,5000)==0
     finally:assert kernel.CloseHandle(handle)
    elif sys.platform=='linux':
     assert api.sigma_proc_signal(p.p,1)==0
     until=time.monotonic()+5
     while True:
      pid,status=os.waitpid(descendant,os.WNOHANG)
      if pid:assert os.WIFSIGNALED(status) and os.WTERMSIG(status)==9;break
      assert time.monotonic()<until;time.sleep(.005)
    else:
     assert api.sigma_proc_signal(p.p,1)==0
     until=time.monotonic()+5
     while True:
      try:os.kill(descendant,0)
      except ProcessLookupError:break
      assert time.monotonic()<until,('descendant still exists',descendant);time.sleep(.01)
  finally:
   if sys.platform=='linux':assert libc.prctl(36,saved_subreaper.value,0,0,0)==0
  reports.append({'case':'kill-descendants-after-root-exit','passed':True})
  # Every retained partial-start state must be abortable without draining pipes.
  fault_steps=8 if os.name=='nt' else 5 if sys.platform=='linux' else 4
  for step in range(1,fault_steps+1):
   api.sigma_proc_test_fault(step)
   with Process() as p:
    result=p.start([sys.executable,'-c','import time;time.sleep(30)'])
    assert result==errno.EIO,(step,result)
   api.sigma_proc_test_fault(0)
  reports.append({'case':'startup-fault-rollback','steps':fault_steps})
  # Kernel resource counts stay bounded across both success and partial failure.
  def resource_count():
   import gc;gc.collect()
   if os.name=='nt':
    kernel=ctypes.WinDLL('kernel32',use_last_error=True);kernel.GetCurrentProcess.restype=P
    kernel.GetProcessHandleCount.argtypes=[P,ctypes.POINTER(U)];count=U()
    assert kernel.GetProcessHandleCount(kernel.GetCurrentProcess(),ctypes.byref(count));return count.value
   return len(os.listdir('/proc/self/fd' if sys.platform=='linux' else '/dev/fd'))
  before=resource_count()
  for _ in range(24):
   with Process() as p:assert p.start([str(work/'missing-executable')])==errno.ENOENT
  after=resource_count();assert after<=before+1,(before,after)
  reports.append({'case':'repeated-failure-resource-count','before':before,'after':after})
  if os.name!='nt':
   previous=signal.signal(signal.SIGCHLD,signal.SIG_IGN)
   try:
    with Process() as p:assert p.start([sys.executable,'-c','pass'])==errno.ECHILD
   finally:signal.signal(signal.SIGCHLD,previous)
   reports.append({'case':'reject-auto-reap-disposition','passed':True})
   p=Process()
   try:
    assert p.start([sys.executable,'-c','pass'])==0;p.communicate();assert p.wait()==(2,0)
    pid=api.sigma_proc_test_pid(p.p);assert os.waitpid(pid,0)[0]==pid
    state=U();code=U();assert api.sigma_proc_status(p.p,ctypes.byref(state),ctypes.byref(code))==errno.ECHILD
    assert api.sigma_proc_signal(p.p,1)==errno.ECHILD
    assert api.sigma_proc_destroy(p.p)==errno.ECHILD
    assert all(not api.sigma_proc_stream(p.p,i) for i in range(3))
    assert api.sigma_proc_destroy(p.p)==0;p.p=None
   finally:p.close()
   reports.append({'case':'foreign-reap-never-signals-cached-pgid-and-closes-streams','passed':True})


 return {'platform':sys.platform,'kind':'native-backend-before-forth-integration','cases':reports}
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--library',required=True,type=Path);parser.add_argument('--output',type=Path);options=parser.parse_args();result=run(options.library)
 if options.output:options.output.write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result))
