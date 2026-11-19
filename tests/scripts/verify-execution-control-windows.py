#!/usr/bin/env python3
"""EXEC-LIMITED in a private Windows console, with injected records only."""
import argparse,ctypes,json,os,subprocess,sys,tempfile,time
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
    kernel.GetConsoleMode.argtypes=[w.HANDLE,ctypes.POINTER(w.DWORD)]
    # The fixture ignores broadcast control events; Sigma installs its own handler.
    handler=ctypes.WINFUNCTYPE(w.BOOL,w.DWORD)(lambda event: 1)
    kernel.SetConsoleCtrlHandler.argtypes=[ctypes.c_void_p,w.BOOL]
    assert kernel.SetConsoleCtrlHandler(handler,1)
    reports=[]
    with tempfile.TemporaryDirectory(prefix='exec-console-',dir=ROOT/'.work/652') as directory:
        source=Path(directory)/'console.fs'
        handle=kernel.CreateFileW('CONIN$',0xC0000000,3,None,3,0,None)
        assert handle not in (None,ctypes.c_void_p(-1).value),ctypes.get_last_error()
        def case(name,raw,units,expected,signal_only=False,full=False,operation="BEGIN AGAIN",reader="EKEY"):

            assert kernel.FlushConsoleInputBuffer(handle)
            before=w.DWORD();assert kernel.GetConsoleMode(handle,ctypes.byref(before))
            code='REQUIRE-EXTENSION ALSO EXTENSION DECIMAL\n'
            if raw:code+='EKEY? DROP\n'
            code+=': FOREVER ." READY" CR STDOUT FLUSH-FILE THROW '+operation+' ;\n: RUN [\'] FOREVER 0 EXEC-LIMITED DROP ;\n\' RUN CATCH . CR\n'
            code+=(reader+' . CR\n')*len(expected)+'BYE\n'
            source.write_text(code,encoding='utf-8')
            with open('CONIN$','rb',buffering=0) as input_stream:
                process=subprocess.Popen([str(sigma.resolve()),str(source)],cwd=ROOT,stdin=input_stream,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                try:
                    assert process.stdout.readline().strip()==b'READY',name
                    if units:
                        records=(Record*len(units))(*[Record(1,0,Key(1,1,vk,0,char,0)) for vk,char in units])
                        count=w.DWORD();assert kernel.WriteConsoleInputW(handle,records,len(units),ctypes.byref(count)) and count.value==len(units)
                    if full:
                        time.sleep(.15)
                        assert process.poll() is None,'full queue should retain characters before later Ctrl+C'
                    start=time.monotonic()
                    if signal_only or full:assert kernel.GenerateConsoleCtrlEvent(0,0)
                    out,err=process.communicate(timeout=8)
                    values=[int(x) for x in out.split()]
                    assert process.returncode==0 and not err and values==[-28]+expected,(name,process.returncode,out,err)
                    after=w.DWORD();assert kernel.GetConsoleMode(handle,ctypes.byref(after))
                    assert before.value==after.value,(name,before.value,after.value)
                    reports.append({'case':name,'seconds':time.monotonic()-start,'values':values})
                finally:
                    if process.poll() is None:process.kill();process.wait()
        try:
            case('raw-key-utf8',True,[(0x70,'\0'),(0x41,'日'),(0x43,'\x03')],[2147483659,26085])
            case('escape-prefix',True,[(0,'\x1b'),(0,'\x03')],[27])
            case('incomplete-csi',True,[(0,'\x1b'),(0,'['),(0,'\x03')],[27,91])
            case('raw-to-key-backspace',True,[(0,char) for char in 'a\x08b\x03'],[97,8,98],reader='KEY')
            case('raw-to-file-utf8',True,[(0,'日'),(0,'\x03')],[230,151,165],reader='PAD 1 STDIN READ-FILE THROW DROP PAD C@')
            paste='\x1b[200~\x03\x1b[201~\x03'
            case('paste',True,[(0,char) for char in paste],[2147483683,3,2147483684])
            case('cooked-signal',False,[],[],signal_only=True)
            case('raw-ns',True,[(0x41,'a'),(0x43,'\x03')],[97],operation='5000000000. NS')
            case('cooked-key',False,[],[],signal_only=True,operation='KEY DROP')
            case('full-queue-native-signal',True,[(0x41,'a')]*70+[(0x43,'\x03')],[97]*70,full=True)
        finally:kernel.CloseHandle(handle)
    return reports
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('sigma',type=Path);p.add_argument('--child',action='store_true');a=p.parse_args()
    if os.name!='nt':raise SystemExit('Windows only')
    if not a.child:
        startup=subprocess.STARTUPINFO();startup.dwFlags=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
        r=subprocess.run([sys.executable,__file__,str(a.sigma.resolve()),'--child'],creationflags=subprocess.CREATE_NEW_CONSOLE,startupinfo=startup,capture_output=True,timeout=40)
        sys.stdout.buffer.write(r.stdout);sys.stderr.buffer.write(r.stderr);raise SystemExit(r.returncode)
    print(json.dumps(run(a.sigma),indent=2))
