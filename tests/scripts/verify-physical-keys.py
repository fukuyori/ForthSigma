#!/usr/bin/env python3
"""Synthetic native-window physical-key acceptance; Windows and Linux/X11.
Does not prove physical keyboard, layout, IME or macOS behavior.
"""
import argparse, ctypes, importlib.util, json, os, queue, struct, subprocess, sys, tempfile, threading, time
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
PROGRAM=r'''REQUIRE-GRAPHICS GRAPHICS
16 16 GFX-INIT DISPLAY-WINDOW SHOW
CREATE BITS 32 ALLOT
: EDGE KEY-EVENT IF . . ELSE 999 . THEN ;
: SNAP BITS KEY-RESYNC BITS C@ . ;
." PH-READY" CR
KEY DROP
." PH-STATE " SCAN-INPUT? . SC-A SCAN-SUPPORTED? . SC-LSHIFT SCAN-HELD? . SC-RSHIFT SCAN-HELD? . SC-A SCAN-HELD? . CR
 ." PH-STDIN " EKEY . CR
." PH-TEXT " INKEY . CR
." PH-EDGES " EDGE EDGE EDGE EDGE KEY-EVENT . CR
." PH-SHIFT-READY" CR
KEY DROP
." PH-SHIFT " SC-LSHIFT SCAN-HELD? . SC-RSHIFT SCAN-HELD? . EDGE KEY-EVENT . CR
." PH-FOCUS-READY" CR
KEY DROP
." PH-FOCUS " SC-LSHIFT SCAN-HELD? . SC-RSHIFT SCAN-HELD? . EDGE KEY-EVENT . CR
 ." PH-SYS-READY" CR
KEY DROP
." PH-SYS " EDGE EDGE KEY-EVENT . CR
." PH-OVERFLOW-READY" CR
KEY DROP
: DRAIN-PH 256 0 DO KEY-EVENT IF 2DROP ELSE -99 THROW THEN LOOP ;
DRAIN-PH
." PH-OVERFLOW " EDGE EDGE SC-A SCAN-HELD? . SNAP KEY-EVENT . CR
." PH-CLOSE-READY" CR
KEY DROP
." PH-CLOSE " SCAN-INPUT? . SC-A SCAN-HELD? . EDGE KEY-EVENT . CR
." PH-DONE" CR BYE
'''
def run(sigma):
    logs=[]; q=queue.Queue()
    with tempfile.TemporaryDirectory(prefix='physical-',dir=ROOT/'.work') as d:
        source=Path(d)/'native.fs';source.write_text(PROGRAM)
        p=subprocess.Popen([str(sigma.resolve()),str(source)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,bufsize=0,cwd=ROOT)
        def reader():
            for raw in iter(p.stdout.readline,b''):
                text=raw.decode('utf-8','replace').strip();logs.append(text);q.put(text)
            q.put(None)
        threading.Thread(target=reader,daemon=True).start()
        def line(prefix,expected=None):
            deadline=time.monotonic()+15
            while time.monotonic()<deadline:
                text=q.get(timeout=max(.01,deadline-time.monotonic()))
                if text is None: raise RuntimeError('Sigma exited: '+repr(logs))
                if prefix in text:
                    tail=text.split(prefix,1)[1].strip()
                    if expected is not None:
                        got=[int(x) for x in tail.split()]
                        if got!=expected:raise AssertionError((prefix,got,expected,logs))
                    return
            raise TimeoutError((prefix,logs))
        def gate(data=b'g'): p.stdin.write(data);p.stdin.flush()
        backend=None
        try:
            line('PH-READY')
            backend=Windows(p.pid) if os.name=='nt' else Linux(p.pid)
            # Prime a text event separately from physical edges.
            backend.a(True);backend.a(True);backend.a(False);backend.shift(True,False);backend.shift(True,True);backend.text_a();backend.sync()
            gate(b'gx')
            line('PH-STATE',[-1,-1,-1,-1,0])
            line('PH-STDIN',[120])
            line('PH-TEXT',[65 if os.name=='nt' else 97])
            line('PH-EDGES',[1,4,2,4,1,225,1,229,0])
            line('PH-SHIFT-READY');backend.shift(False,False);backend.sync();gate()
            line('PH-SHIFT',[0,-1,2,225,0])
            line('PH-FOCUS-READY');backend.focus_lost();backend.sync();gate()
            line('PH-FOCUS',[0,0,2,229,0])
            line('PH-SYS-READY');backend.system_ctrl();backend.sync();gate()
            line('PH-SYS',[1,228,2,228,0])
            line('PH-OVERFLOW-READY')
            for _ in range(140):backend.tap_a()
            backend.a(True);backend.sync();gate()
            line('PH-OVERFLOW',[3,0,3,0,-1,16,0])
            line('PH-CLOSE-READY');backend.close_window();backend.sync();time.sleep(.05);gate()
            line('PH-CLOSE',[0,0,2,4,0]);line('PH-DONE')
            code=p.wait(timeout=10)
            if code:raise RuntimeError((code,logs))
            return {'platform':sys.platform,'pid':p.pid,'cases':7,'kind':'synthetic-native-window','lines':logs}
        finally:
            if p.poll() is None:p.terminate();p.wait(timeout=5)
            if backend:backend.finish()
class Windows:
    def __init__(self,pid):
        from ctypes import wintypes as w
        self.u=ctypes.WinDLL('user32',use_last_error=True)
        self.u.SendMessageW.argtypes=[w.HWND,w.UINT,w.WPARAM,w.LPARAM];self.u.SendMessageW.restype=ctypes.c_ssize_t
        self.u.GetWindowThreadProcessId.argtypes=[w.HWND,ctypes.POINTER(w.DWORD)]
        callback=ctypes.WINFUNCTYPE(w.BOOL,w.HWND,w.LPARAM);found=[]
        def visit(hwnd,_):
            owner=w.DWORD();self.u.GetWindowThreadProcessId(hwnd,ctypes.byref(owner))
            name=ctypes.create_unicode_buffer(128);self.u.GetClassNameW(hwnd,name,128)
            if owner.value==pid and name.value=='SigmaGraphicsWindow':found.append(hwnd)
            return True
        self.u.EnumWindows(callback(visit),0)
        if len(found)!=1:raise RuntimeError(('window count',found))
        self.window=found[0]
        self.u.GetForegroundWindow.restype=w.HWND
        self.u.SetForegroundWindow.argtypes=[w.HWND]
        self.u.GetAsyncKeyState.argtypes=[ctypes.c_int];self.u.GetAsyncKeyState.restype=ctypes.c_short
        if self.u.GetAsyncKeyState(0xa0)<0 or self.u.GetAsyncKeyState(0xa1)<0:raise RuntimeError('Release Shift before running this test')
        self.u.SetForegroundWindow(self.window)
        deadline=time.monotonic()+1
        while self.u.GetForegroundWindow()!=self.window and time.monotonic()<deadline:time.sleep(.01)
        if self.u.GetForegroundWindow()!=self.window:raise RuntimeError('Cannot focus owned test window for injected Shift input')
        class KI(ctypes.Structure):_fields_=[('vk',w.WORD),('scan',w.WORD),('flags',w.DWORD),('time',w.DWORD),('extra',ctypes.c_size_t)]
        class IU(ctypes.Union):_fields_=[('ki',KI),('padding',ctypes.c_byte*32)]
        class INPUT(ctypes.Structure):_fields_=[('type',w.DWORD),('u',IU)]
        self.KI,self.IU,self.INPUT=KI,IU,INPUT;self.shifts=set()
        self.u.SendInput.argtypes=[w.UINT,ctypes.POINTER(INPUT),ctypes.c_int];self.u.SendInput.restype=w.UINT
    def key(self,code,make,down,extended=False):
        bits=1|(make<<16)|(int(extended)<<24)
        if not down:bits|=0xc0000000
        self.u.SendMessageW(self.window,0x100 if down else 0x101,code,bits)
    def a(self,down):self.key(65,0x1e,down)
    def tap_a(self):self.a(True);self.a(False)
    def shift(self,down,right):
        event=self.INPUT(1,self.IU(ki=self.KI(0,0x36 if right else 0x2a,8|(0 if down else 2),0,0)))
        if self.u.SendInput(1,ctypes.byref(event),ctypes.sizeof(event))!=1:raise RuntimeError('SendInput failed')
        if down:self.shifts.add(right)
        else:self.shifts.discard(right)
        time.sleep(.02)
    def system_ctrl(self):
        self.u.SendMessageW(self.window,0x104,0x11,1|(0x1d<<16)|(1<<24))
        self.u.SendMessageW(self.window,0x105,0x11,1|(0x1d<<16)|(1<<24)|0xc0000000)
    def text_a(self):self.u.SendMessageW(self.window,0x102,65,1|(0x1e<<16))
    def focus_lost(self):
        for right in sorted(self.shifts):self.shift(False,right)
        self.u.SendMessageW(self.window,8,0,0)
    def close_window(self):self.u.SendMessageW(self.window,0x10,0,0)
    def sync(self):time.sleep(.03)
    def finish(self):
        for right in sorted(self.shifts):self.shift(False,right)
class Linux:
    def __init__(self,pid):
        spec=importlib.util.spec_from_file_location('xprobe',ROOT/'experiments/linux_x11_probe.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
        # WSLg local test connection: no cookie files are read by this harness.
        mod.auth=lambda _: (b'',b'')
        self.c=mod.Connection(os.environ.get('DISPLAY',':0'));self.time=1
        self.pid_atom=self.atom('_NET_WM_PID');self.name_atom=self.atom('WM_NAME')
        windows=[self.c.root];found=[]
        while windows:
            w=windows.pop()
            header,body=self.c.reply(self.c.request(20,0,struct.pack('<5I',w,self.pid_atom,0,0,1)))
            if len(body)>=4 and struct.unpack_from('<I',body)[0]==pid:found.append(w)
            h,b=self.c.reply(self.c.request(15,0,struct.pack('<I',w)))
            windows.extend(struct.unpack('<'+'I'*(len(b)//4),b))
        if len(found)!=1:raise RuntimeError(('window count',found))
        self.window=found[0]
        # Query XKB GetNames; keycode values are intentionally not assumed.
        h,_=self.c.reply(self.c.request(98,0,struct.pack('<H2x',9)+b'XKEYBOARD'));self.op=h[9]
        self.c.reply(self.c.request(self.op,0,struct.pack('<HH',1,0)))
        h,b=self.c.reply(self.c.request(self.op,17,struct.pack('<H2xI',0x100,1<<9)))
        self.codes={b[i*4:i*4+4].rstrip(b'\0'):h[18]+i for i in range(h[19])}
    def atom(self,name):
        raw=name.encode();h,_=self.c.reply(self.c.request(16,0,struct.pack('<H2x',len(raw))+raw));return struct.unpack_from('<I',h,8)[0]
    def event(self,data,mask):self.c.request(25,0,struct.pack('<II',self.window,mask)+data)
    def key(self,name,down):
        data=bytearray(32);data[0]=2 if down else 3;data[1]=self.codes[name];self.time+=1
        struct.pack_into('<IIII',data,4,self.time,self.c.root,self.window,0);data[30]=1
        self.event(data,1 if down else 2)
    def a(self,down):self.key(b'AC01',down)
    def tap_a(self):self.a(True);self.a(False)
    def shift(self,down,right):self.key(b'RTSH' if right else b'LFSH',down)
    def system_ctrl(self):self.key(b'RCTL',True);self.key(b'RCTL',False)
    def text_a(self):pass # X11 key press already creates the independent text key.
    def focus_lost(self):
        data=bytearray(32);data[0]=10;struct.pack_into('<I',data,4,self.window);data[8]=0
        self.event(data,1<<21)
    def close_window(self):
        data=bytearray(32);data[0]=33;data[1]=32
        struct.pack_into('<III',data,4,self.window,self.atom('WM_PROTOCOLS'),self.atom('WM_DELETE_WINDOW'))
        self.event(data,0)
    def sync(self):self.c.sync();time.sleep(.04)
    def finish(self):self.c.sock.close()
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--sigma',required=True,type=Path);ap.add_argument('--output',type=Path);args=ap.parse_args()
    if sys.platform not in ('win32','linux'):ap.error('This automated harness supports Windows and Linux/X11 only')
    result=run(args.sigma)
    if args.output:args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False))
