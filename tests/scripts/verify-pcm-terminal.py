#!/usr/bin/env python3
"""Owned PTY/private hidden console: PCM interruption and raw-key preservation."""
import argparse,ctypes,json,os,re,select,subprocess,sys,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def source(operation,reads):
    tail='EKEY . '*reads
    if operation=='wait':work='4096 -1 P @ PCM-WAIT 2DROP';after=''
    elif operation=='stop':work='1 -1 P @ PCM-STOP THROW DROP';after='P @ PCM-CLOSE THROW OPEN-PCM'
    else:work='P @ PCM-CLOSE THROW';after='OPEN-PCM'
    return ('REQUIRE-AUDIO ALSO AUDIO CREATE BUF 16384 ALLOT BUF 16384 ERASE VARIABLE P '
      ': OPEN-PCM 48000 2 4096 PCM-OPEN THROW P ! ; OPEN-PCM EKEY? DROP '
      ': RUN BEGIN BUF 4096 P @ PCM-WRITE 2DROP ." READY" CR STDOUT FLUSH-FILE THROW '+work+' '+after+' AGAIN ; '
      "' RUN CATCH . CR P @ PCM-CLOSE . CR "+tail+'BYE')
cases=[('wait','ab', [97,98]),('stop','ab',[97,98]),('close','ab',[97,98]),('wait','\x1b[',[27,91]),('wait','日',[26085])]
def check(name,data,expected,values,status):
    pattern=str(expected).encode()+rb'\s+0'+b''.join(rb'\s+'+str(v).encode() for v in values)
    assert status==0 and re.search(pattern,data),(name,status,data)
def unix(sigma,folder):
    import termios
    rows=[]
    for operation,keys,values in cases:
      script=folder/'test.fs';script.write_text(source(operation,len(values)),encoding='utf-8')
      master,slave=os.openpty();before=termios.tcgetattr(slave);data=b''
      proc=subprocess.Popen([str(sigma),str(script)],stdin=slave,stdout=slave,stderr=slave,env=dict(os.environ,TERM='xterm'))
      def collect(until,seconds=5):
        nonlocal data
        end=time.monotonic()+seconds
        while not until():
          assert time.monotonic()<end,(operation,data,proc.poll())
          ready,_,_=select.select([master],[],[],.02)
          if ready:
            try:data+=os.read(master,8192)
            except OSError:pass
          if proc.poll() is not None:break
      try:
        collect(lambda:b'READY' in data);assert b'READY' in data,data
        os.write(master,keys.encode()+b'\x03');start=time.monotonic()
        collect(lambda:proc.poll() is not None);proc.wait(timeout=2)
        # Drain bytes already queued when the process exited.
        while select.select([master],[],[],0)[0]:
          try:
            part=os.read(master,8192)
            if not part:break
            data+=part
          except OSError:break
        check(operation,data,-516 if operation=='close' else -28,values,proc.returncode)
        after=termios.tcgetattr(slave);pendin=getattr(termios,'PENDIN',0);before[3]&=~pendin;after[3]&=~pendin
        assert before==after,(operation,'terminal mode not restored')
        rows.append({'operation':operation,'payload':keys,'exit':proc.returncode,'elapsed_seconds':time.monotonic()-start,'output':data.decode(errors='replace')})
      finally:
        if proc.poll() is None:proc.kill();proc.wait()
        os.close(master);os.close(slave)
    return rows
def windows(sigma,folder):
    from ctypes import wintypes as w
    c=ctypes;k=c.WinDLL('kernel32',use_last_error=True)
    class Key(c.Structure):_fields_=[('down',w.BOOL),('repeat',w.WORD),('vk',w.WORD),('scan',w.WORD),('char',w.WCHAR),('control',w.DWORD)]
    class Event(c.Union):_fields_=[('key',Key),('padding',c.c_byte*16)]
    class Record(c.Structure):_fields_=[('kind',w.WORD),('event',Event)]
    k.CreateFileW.argtypes=[w.LPCWSTR,w.DWORD,w.DWORD,c.c_void_p,w.DWORD,w.DWORD,w.HANDLE];k.CreateFileW.restype=w.HANDLE
    k.GetConsoleMode.argtypes=[w.HANDLE,c.POINTER(w.DWORD)];k.CloseHandle.argtypes=[w.HANDLE]
    k.WriteConsoleInputW.argtypes=[w.HANDLE,c.POINTER(Record),w.DWORD,c.POINTER(w.DWORD)];k.FlushConsoleInputBuffer.argtypes=[w.HANDLE]
    handle=k.CreateFileW('CONIN$',0xC0000000,3,None,3,0,None);assert handle not in (None,c.c_void_p(-1).value)
    rows=[]
    try:
      for operation,keys,values in cases:
        assert k.FlushConsoleInputBuffer(handle)
        before=w.DWORD();assert k.GetConsoleMode(handle,c.byref(before))
        with open('CONIN$','rb',buffering=0) as stream:
          proc=subprocess.Popen([str(sigma),'-e',source(operation,len(values))],stdin=stream,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
          try:
            assert proc.stdout.readline().strip()==b'READY'
            for char in keys+'\x03':
              record=Record(1,Event(key=Key(1,1,67 if char=='\x03' else 0,0,char,8 if char=='\x03' else 0)));written=w.DWORD()
              assert k.WriteConsoleInputW(handle,c.byref(record),1,c.byref(written)) and written.value==1
            start=time.monotonic();out,err=proc.communicate(timeout=8)
            assert not err,(operation,err);check(operation,out,-516 if operation=='close' else -28,values,proc.returncode)
            after=w.DWORD();assert k.GetConsoleMode(handle,c.byref(after)) and after.value==before.value,(before.value,after.value)
            rows.append({'operation':operation,'payload':keys,'exit':proc.returncode,'elapsed_seconds':time.monotonic()-start,'output':out.decode(errors='replace')})
          finally:
            if proc.poll() is None:proc.kill();proc.wait()
    finally:k.CloseHandle(handle)
    return rows
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('sigma',type=Path);p.add_argument('--child',action='store_true');args=p.parse_args();sigma=args.sigma.resolve()
 if os.name=='nt' and not args.child:
    startup=subprocess.STARTUPINFO();startup.dwFlags=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    r=subprocess.run([sys.executable,__file__,str(sigma),'--child'],creationflags=subprocess.CREATE_NEW_CONSOLE,startupinfo=startup,capture_output=True,timeout=60)
    sys.stdout.buffer.write(r.stdout);sys.stderr.buffer.write(r.stderr);raise SystemExit(r.returncode)
 work=ROOT/'.work/1128';work.mkdir(exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='terminal-',dir=work) as d:print(json.dumps(windows(sigma,Path(d)) if os.name=='nt' else unix(sigma,Path(d)),ensure_ascii=False,indent=2))
