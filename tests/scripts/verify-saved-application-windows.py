#!/usr/bin/env python3
"""Private Windows console: saved-app wait interruption and OS termination."""
import argparse,ctypes,json,os,subprocess,sys,tempfile,time
from ctypes import wintypes as w
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def run(sigma):
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.CreateFileW.argtypes=[w.LPCWSTR,w.DWORD,w.DWORD,ctypes.c_void_p,w.DWORD,w.DWORD,w.HANDLE];kernel.CreateFileW.restype=w.HANDLE
    kernel.GetConsoleMode.argtypes=[w.HANDLE,ctypes.POINTER(w.DWORD)];kernel.CloseHandle.argtypes=[w.HANDLE]
    handler=ctypes.WINFUNCTYPE(w.BOOL,w.DWORD)(lambda event:1)
    kernel.SetConsoleCtrlHandler.argtypes=[ctypes.c_void_p,w.BOOL];assert kernel.SetConsoleCtrlHandler(handler,1)
    reports=[]
    with tempfile.TemporaryDirectory(prefix='console-app-',dir=ROOT/'.work/1069') as temp:
        folder=Path(temp);handle=kernel.CreateFileW('CONIN$',0xC0000000,3,None,3,0,None)
        assert handle not in (None,ctypes.c_void_p(-1).value)
        try:
            for name,body,cooperative in [('waiting','5000000000. NS',True),('computing','BEGIN AGAIN',False)]:
                saved=folder/(name+'.exe')
                code=': MAIN ." READY" CR STDOUT FLUSH-FILE THROW '+body+' ; \' MAIN APP-ENTRY! SAVESYS '+saved.name+' BYE'
                made=subprocess.run([str(sigma),'-e',code],cwd=folder,capture_output=True,input=b'',timeout=15)
                assert made.returncode==0 and not made.stderr,(made.stdout,made.stderr)
                before=w.DWORD();assert kernel.GetConsoleMode(handle,ctypes.byref(before))
                with open('CONIN$','rb',buffering=0) as stream:
                    child=subprocess.Popen([str(saved)],cwd=folder,stdin=stream,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                    try:
                        assert child.stdout.readline().strip()==b'READY'
                        time.sleep(.05)
                        assert kernel.GenerateConsoleCtrlEvent(0,0)
                        out,err=child.communicate(timeout=8)
                        if cooperative:
                            assert child.returncode==1 and b'USER INTERRUPT' in out and not err,(child.returncode,out,err)
                            after=w.DWORD();assert kernel.GetConsoleMode(handle,ctypes.byref(after)) and after.value==before.value
                        else:assert child.returncode!=0 and b'USER INTERRUPT' not in out,(child.returncode,out,err)
                        reports.append({'case':name,'exit_code':child.returncode,'stdout':out.decode(errors='replace'),'stderr':err.decode(errors='replace')})
                    finally:
                        if child.poll() is None:child.kill();child.wait()
        finally:kernel.CloseHandle(handle)
    return reports
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('sigma',type=Path);p.add_argument('--child',action='store_true');a=p.parse_args()
    if os.name!='nt':raise SystemExit('Windows only')
    if not a.child:
        startup=subprocess.STARTUPINFO();startup.dwFlags=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
        r=subprocess.run([sys.executable,__file__,str(a.sigma.resolve()),'--child'],creationflags=subprocess.CREATE_NEW_CONSOLE,startupinfo=startup,capture_output=True,timeout=45)
        sys.stdout.buffer.write(r.stdout);sys.stderr.buffer.write(r.stderr);raise SystemExit(r.returncode)
    print(json.dumps(run(a.sigma),indent=2))
