#!/usr/bin/env python3
"""Private Windows console fixture; no user keyboard or desktop interaction."""
import argparse,ctypes,json,os,subprocess,sys,tempfile
from ctypes import wintypes as w
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def run(sigma):
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    class Key(ctypes.Structure):
        _fields_=[('down',w.BOOL),('repeat',w.WORD),('vk',w.WORD),('scan',w.WORD),('char',w.WCHAR),('control',w.DWORD)]
    class Record(ctypes.Structure):
        _fields_=[('type',w.WORD),('pad',w.WORD),('key',Key)]
    kernel.CreateFileW.argtypes=[w.LPCWSTR,w.DWORD,w.DWORD,ctypes.c_void_p,w.DWORD,w.DWORD,w.HANDLE];kernel.CreateFileW.restype=w.HANDLE
    kernel.WriteConsoleInputW.argtypes=[w.HANDLE,ctypes.POINTER(Record),w.DWORD,ctypes.POINTER(w.DWORD)]
    kernel.CloseHandle.argtypes=[w.HANDLE]
    with tempfile.TemporaryDirectory(prefix='async-console-',dir=ROOT/'.work') as directory:
        source=Path(directory)/'console.fs'
        source.write_text('''REQUIRE-EXTENSION ALSO EXTENSION DECIMAL
CREATE IDS STDIN ,
." READY" CR STDOUT FLUSH-FILE THROW
IDS 1 3000 WAIT-FILES THROW DROP
PAD 3 STDIN READ-AVAILABLE THROW DROP ." COUNT " . CR
PAD C@ . PAD 1+ C@ . PAD 2 + C@ . CR
: CHECK 8 0 DO 0 EKEY-WAIT THROW IF 2147483659 = IF ." F1-KEPT" CR UNLOOP EXIT THEN ELSE DROP THEN LOOP -1 THROW ; CHECK
BYE
''')
        handle=kernel.CreateFileW('CONIN$',0xC0000000,3,None,3,0,None)
        assert handle not in (None,ctypes.c_void_p(-1).value),ctypes.get_last_error()
        try:
            with open('CONIN$','rb',buffering=0) as input_stream:
                process=subprocess.Popen([str(sigma.resolve()),str(source)],cwd=ROOT,stdin=input_stream,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                assert process.stdout.readline().strip()==b'READY'
                records=(Record*2)(Record(1,0,Key(1,1,0x70,0x3b,'\0',0)),Record(1,0,Key(1,1,0x41,0x1e,'日',0)))
                count=w.DWORD();assert kernel.WriteConsoleInputW(handle,records,2,ctypes.byref(count)) and count.value==2
                out,err=process.communicate(timeout=8)
                text=out.decode();assert process.returncode==0 and not err and 'COUNT 3' in text and '230 151 165' in text and 'F1-KEPT' in text,(process.returncode,out,err)
                return {'kind':'private-injected-console','stdout':text}
        finally:kernel.CloseHandle(handle)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--sigma',required=True,type=Path);p.add_argument('--output',type=Path);p.add_argument('--child',action='store_true');a=p.parse_args()
    if os.name!='nt':raise SystemExit('Windows only')
    if not a.child:
        startup=subprocess.STARTUPINFO();startup.dwFlags=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
        cmd=[sys.executable,__file__,'--sigma',str(a.sigma.resolve()),'--child']
        if a.output:cmd+=['--output',str(a.output.resolve())]
        r=subprocess.run(cmd,creationflags=subprocess.CREATE_NEW_CONSOLE,startupinfo=startup,capture_output=True,timeout=15);sys.stdout.buffer.write(r.stdout);sys.stderr.buffer.write(r.stderr);raise SystemExit(r.returncode)
    result=run(a.sigma)
    if a.output:a.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
