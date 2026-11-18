#!/usr/bin/env python3
"""XIM wire fixture on a private Xvfb; never run on the user desktop.
Set SIGMA_TEST_PRIVATE_XSERVER=1 after starting a private Xvfb.
"""
from pathlib import Path
import os,sys,subprocess,struct,time,select,json
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'experiments'))
SIGMA = os.environ.get('SIGMA_TEST_BINARY', str(ROOT / 'zig-out/bin/sigma'))
from linux_x11_probe import Connection,pad
if os.environ.get('SIGMA_TEST_PRIVATE_XSERVER') != '1':
    raise SystemExit('This test requires a private Xvfb and SIGMA_TEST_PRIVATE_XSERVER=1')
c=Connection(os.environ['DISPLAY']);owner=c.resource();ids=struct.pack('<HH',1,1)
c.request(1,c.depth,struct.pack('<IIhhHHHHII',owner,c.root,0,0,1,1,0,1,c.visual,0))
selection=c.atom(b'@server=sigma-test');servers=c.atom(b'XIM_SERVERS');protocol=c.atom(b'_XIM_PROTOCOL');connect=c.atom(b'_XIM_XCONNECT');prop=c.atom(b'_sigma_test_reply')
c.request(22,body=struct.pack('<III',owner,selection,0))
c.request(18,body=struct.pack('<IIIB3xI',c.root,servers,4,32,1)+struct.pack('<I',selection));c.sync()
send_index=0
silent_started=None;probe_delay=None
client=None;received=[];lines=[];preedit_sent=False;return_sent=False;committed=False

def cm(target,atom,fmt,data):
 event=struct.pack('<BBHII',33,fmt,0,target,atom)+data.ljust(20,b'\0')
 c.request(25,body=struct.pack('<II',target,0)+event)
def send(op,body=b''):
 global send_index
 packet=struct.pack('<BBH',op,0,len(pad(body))//4)+pad(body)
 if len(packet)<=20:cm(client,protocol,8,packet)
 else:
  send_index+=1;reply_prop=c.atom(('_sigma_test_reply_'+str(send_index)).encode())
  c.request(18,body=struct.pack('<IIIB3xI',client,reply_prop,31,8,len(packet))+packet)
  cm(client,protocol,32,struct.pack('<II',len(packet),reply_prop))
def attributes():
 names=[('inputStyle',3),('clientWindow',5),('focusWindow',5),('preeditAttributes',0x7fff),('spotLocation',12)]
 return b''.join(struct.pack('<HH',i+1,kind)+pad(struct.pack('<H',len(n))+n.encode()) for i,(n,kind) in enumerate(names))
def draw(first,deleted,text,no_string=False):
 encoded=text.encode()
 body=struct.pack('<HHiiiIH',1,1,len(text),first,deleted,1 if no_string else 2,len(encoded))+encoded
 send(75,pad(body)+bytes(4))
def keyevent(window,keycode):
 for kind in (2,3):
  event=struct.pack('<BBHIIIIhhhhHBB',kind,keycode,0,0,c.root,window,0,0,0,0,0,0,1,0)
  c.request(25,body=struct.pack('<II',window,1 if kind==2 else 2)+event)
def children(window):
 _,b=c.reply(c.request(15,body=struct.pack('<I',window)))
 return struct.unpack('<'+'I'*(len(b)//4),b)
def find():
 for window in children(c.root):
  h,b=c.reply(c.request(20,body=struct.pack('<IIIII',window,67,31,0,256)))
  if b.startswith(b'sigma\0Sigma\0'):return window
 return None
source='''REQUIRE-GRAPHICS ALSO GRAPHICS 64 64 GFX-INIT DISPLAY-WINDOW TRUE 10 10 16 GFX-IME-CARET SHOW ." READY" CR
VARIABLE REPORTED 0 REPORTED !
: T 4500 0 DO PAD 256 GFX-IME-PREEDIT DUP IF REPORTED @ 0= IF ." PREEDIT " PAD SWAP TYPE CR 1 REPORTED ! ELSE DROP THEN ELSE DROP THEN INKEY DUP -1 <> IF ." KEY " . CR ELSE DROP THEN 1 MS LOOP ; T BYE'''
p=subprocess.Popen((['gdb','-batch','-ex','run','-ex','thread apply all bt','--args'] if os.environ.get('SIGMA_XIM_GDB') else [])+[SIGMA,'-e',source],env=dict(os.environ,XMODIFIERS='@im=sigma-test'),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,bufsize=0)
window=None;started=False
try:
 deadline=time.monotonic()+12
 while time.monotonic()<deadline:
  c.deadline=time.monotonic()+2
  readable=select.select([c.sock,p.stdout],[],[],.01)[0]
  if c.sock in readable or c.events:
   e=c.wait_event(33,owner)
   atom=struct.unpack_from('<I',e,8)[0]
   if atom==connect:
    client=struct.unpack_from('<I',e,12)[0];cm(client,connect,32,struct.pack('<5I',owner,0,0,20,0));continue
   if e[1]==8:packet=e[12:32]
   else:
    length,atom=struct.unpack_from('<II',e,12)
    h,b=c.reply(c.request(20,1,struct.pack('<IIIII',owner,atom,31,0,(length+3)//4)));packet=b[:length]
   op,_,units=struct.unpack_from('<BBH',packet);body=packet[4:4+units*4];received.append(op)
   if op==1:send(2,struct.pack('<HH',1,0))
   elif op==30:
    attrs=attributes();send(31,struct.pack('<HHHH',1,0,len(attrs),0)+attrs)
   elif op==38:send(39,struct.pack('<HHhH',1,0,0,0))
   elif op==50:
    send(51,ids)
    event=bytes([34,0,0,0,0,8,248])+bytes(25)
    c.request(25,body=struct.pack('<II',client,0)+event)
   elif op==54:send(55,ids)
   elif op==64:send(65,ids+bytes(4))
   elif op==61:
    probe_delay=time.monotonic()-silent_started;assert probe_delay>=.9,probe_delay
    send(62,ids);keyevent(window,38)
   elif op==60:
    event=body[8:40]
    if event[1]==68:
     if silent_started is None:silent_started=time.monotonic()
     continue
    if event[0]&127==2 and not preedit_sent:
     preedit_sent=True;send(73,ids)
    elif event[0]&127==2 and preedit_sent:
     text='日本語😀'.encode();send(63,ids+struct.pack('<HH',3,len(text))+text);send(78,ids);committed=True
    else:send(62,ids)
   elif op==74:
    draw(0,0,'日本');draw(0,1,'',True);draw(1,0,'語');send(62,ids)
   elif op==52:send(53,ids)
   elif op==32:send(33,struct.pack('<HH',1,0))
   elif op==3:send(4)
  if p.stdout in readable:
   line=p.stdout.readline().decode().strip();lines.append(line)
   if line=='READY':
    window=find();assert window
    c.request(42,1,struct.pack('<II',window,0))
    c.sync()
    # Give FocusIn and the GUI caret transition time to reach the IC.
    started=time.monotonic()
   if line=='PREEDIT 本語' and not return_sent:
    keyevent(window,36);return_sent=True
  if started and time.monotonic()-started>1.2:
   keyevent(window,68);started=False
  if p.poll() is not None:break
 p.wait(timeout=2)
 lines.extend(p.stdout.read().decode().splitlines())
 values=[int(line[4:]) for line in lines if line.startswith('KEY ')]
 assert 61 in received,('No XIM liveness probe',received)
 assert 'PREEDIT 本語' in lines,(p.returncode,lines,received)
 assert bytes(values)=='日本語😀'.encode(),(p.returncode,lines,received)
 assert p.returncode==0
 print(json.dumps({'preedit_delta_delete_insert':'pass','utf8_commit':'pass','bytes':values,'shutdown':'pass','protocol_opcodes':received,'silent_forward_probe_seconds':round(probe_delay,3)}))
except Exception:
 print((p.poll(),lines,received),file=sys.stderr);raise
finally:
 if p.poll() is None:p.kill();p.wait()
 c.sock.close()
