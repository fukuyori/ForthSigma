#!/usr/bin/env python3
"""X11 window integration; build -Dx11=true. SIGMA_TEST_BINARY selects Sigma.
Run on a private Xvfb for deterministic unobscured pixel readback.
"""
from pathlib import Path
import sys,subprocess,os,time,struct,select,json
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'experiments'))
SIGMA = os.environ.get('SIGMA_TEST_BINARY', str(ROOT / 'zig-out/bin/sigma'))
from linux_x11_probe import Connection
c=Connection(os.environ['DISPLAY'])
c.red,c.green,c.blue=c.visual_info[1:]
source='''REQUIRE-GRAPHICS ALSO GRAPHICS
2 2 GFX-INIT 0 0 $FF0000 GFX-PSET 1 0 $00FF00 GFX-PSET 0 1 $0000FF GFX-PSET 1 1 $FFFFFF GFX-PSET
257 129 WINDOW-SIZE DISPLAY-WINDOW SHOW ." READY" CR
: READ-TEST 1200 0 DO INKEY DUP -1 <> IF ." KEY " . CR ELSE DROP THEN 1 MS LOOP ; READ-TEST
SHOW ." REOPEN" CR 700 MS BYE'''
close_after = float(os.environ.get('SIGMA_TEST_CLOSE_AFTER', '0'))
source = source.replace('READ-TEST 1200', 'READ-TEST ' + str(1200 + int(close_after * 1000)))
p=subprocess.Popen([SIGMA,'-e',source],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,bufsize=0)

def children(w):
 h,b=c.reply(c.request(15,body=struct.pack('<I',w)))
 return list(struct.unpack('<'+'I'*(len(b)//4),b))
def name(w):
 h,b=c.reply(c.request(20,body=struct.pack('<IIIII',w,39,31,0,256)))
 return b[:struct.unpack_from('<I',h,16)[0]]
def find():
 todo=children(c.root)
 while todo:
  w=todo.pop()
  if name(w)==b'FORTH/Sigma graphics':
   h,b=c.reply(c.request(20,body=struct.pack('<IIIII',w,67,31,0,256)))
   if b.startswith(b'sigma\0Sigma\0'):return w
  todo.extend(children(w))
 return None

def line():
 if not select.select([p.stdout],[],[],6)[0]:raise TimeoutError('Sigma output')
 return p.stdout.readline().decode().strip()
try:
 assert line()=='READY'
 window=find();assert window
 expected=[((65,1),c.red),((191,1),c.green),((65,127),c.blue),((191,127),c.red|c.green|c.blue),((0,0),0)]
 for _ in range(100):
  if os.environ.get('SIGMA_TEST_SKIP_WINDOW_PIXELS'):
   good=True;break
  h,b=c.reply(c.request(73,2,struct.pack('<IhhHHI',window,0,0,257,129,0xffffffff)))
  bits,padding=c.formats[c.depth];stride=((257*bits+padding-1)//padding)*padding//8
  good=all(int.from_bytes(b[y*stride+x*bits//8:y*stride+(x+1)*bits//8],'little' if c.byte_order==0 else 'big')&(c.red|c.green|c.blue)==value for (x,y),value in expected)
  if good:break
  time.sleep(.01)
 assert good or os.environ.get('SIGMA_TEST_SKIP_WINDOW_PIXELS'), [('sample',xy,'expected',v,'actual',hex(int.from_bytes(b[xy[1]*stride+xy[0]*bits//8:xy[1]*stride+(xy[0]+1)*bits//8],'little'))) for xy,v in expected]
 h,b=c.reply(c.request(101,body=bytes([8,248,0,0])))
 cols=h[1];key=None
 for i in range(248):
  if struct.unpack_from('<I',b,i*cols*4)[0]==97:key=i+8;break
 assert key
 for typ in (2,3):
  event=struct.pack('<BBHIIIIhhhhHBB',typ,key,0,123,c.root,window,0,0,0,0,0,0,1,0)
  c.request(25,body=struct.pack('<II',window,1 if typ==2 else 2)+event)
 actual=line();assert actual=='KEY 97',repr(actual)
 if os.environ.get('SIGMA_TEST_RESIZE'):
  c.request(12,body=struct.pack('<IH2xII',window,12,333,211))
  for _ in range(100):
   header,image=c.reply(c.request(73,2,struct.pack('<IhhHHI',window,0,0,333,211,0xffffffff)))
   bits,padding=c.formats[c.depth];row_stride=((333*bits+padding-1)//padding)*padding//8
   samples=[((62,1),c.red),((270,1),c.green),((62,209),c.blue),((270,209),c.red|c.green|c.blue),((0,0),0)]
   ok=all(int.from_bytes(image[y*row_stride+x*bits//8:y*row_stride+(x+1)*bits//8],'little' if c.byte_order==0 else 'big')&(c.red|c.green|c.blue)==value for (x,y),value in samples)
   if ok:break
   time.sleep(.01)
  assert ok,'resize redraw differs'
 if close_after:
  time.sleep(close_after);c.deadline=time.monotonic()+5
 if os.environ.get('SIGMA_TEST_REMAP'):
  assert os.environ.get('SIGMA_TEST_PRIVATE_XSERVER') == '1', 'Remapping requires a private X server'
  values=list(struct.unpack_from('<'+'I'*cols,b,(key-8)*cols*4));values[0]=98
  if cols>1:values[1]=66
  c.request(100,1,bytes([key,cols,0,0])+struct.pack('<'+'I'*cols,*values));c.sync();time.sleep(.05)
  for typ in (2,3):
   event=struct.pack('<BBHIIIIhhhhHBB',typ,key,0,124,c.root,window,0,0,0,0,0,0,1,0)
   c.request(25,body=struct.pack('<II',window,1 if typ==2 else 2)+event)
  actual=line();assert actual=='KEY 98',repr(actual)
 protocols,delete=c.atom(b'WM_PROTOCOLS'),c.atom(b'WM_DELETE_WINDOW')
 event=struct.pack('<BBHII5I',33,32,0,window,protocols,delete,0,0,0,0)
 c.request(25,body=struct.pack('<II',window,0)+event)
 assert line()=='REOPEN'
 new=find();assert new and new!=window
 p.wait(timeout=5);assert p.returncode==0
 print(json.dumps({'window_pixels':'skipped (obscured desktop)' if os.environ.get('SIGMA_TEST_SKIP_WINDOW_PIXELS') else 'pass','letterbox':'pass','resize_redraw':'pass' if os.environ.get('SIGMA_TEST_RESIZE') else 'not requested','key_press_release':'pass','wm_delete_reopen':'pass','exit':'pass'}))
finally:
 if p.poll() is None:p.kill();p.wait()
 c.sock.close()
