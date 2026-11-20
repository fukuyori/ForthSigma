#!/usr/bin/env python3
"""Declared PAL Paula model: independent per-clock oracle, not a real-chip oracle."""
import argparse, hashlib, json, platform, statistics, struct, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CLOCK=3546895; RATE=48000; SIZE=524288
INITIAL=bytes((37*i+11)&255 for i in range(1024))+bytes(SIZE-1024)
VARS=['DMA','ADK','INTENA','INTREQ','CYCLE','FRACTION','PER-CLAMPS','EVENT-COUNT','EVENT-INDEX']
DUMP=': SNAP 24 0 DO PA-REGS I CELLS + @ . LOOP 56 0 DO PA-STATE I CELLS + @ . LOOP '+' '.join('PA-'+v+' @ .' for v in VARS)+' ; '
DEMO=[]
for i in range(4):DEMO += [(0,i*128,0xa2+i*16),(0,32,0xa4+i*16),(0,214+i*107,0xa6+i*16),(0,32,0xa8+i*16)]
DEMO += [(0,0x820f,0x96)]

def volume(v):return 64 if v&64 else v&63
def period(v):return v or 65536
class Model:
 def __init__(self,events=(),memory=INITIAL):
  self.memory=bytearray(memory);self.reg=[[0]*6 for _ in range(4)];self.c=[[0]*14 for _ in range(4)]
  for c in self.c:c[7]=65536
  self.dma=self.adk=self.intena=self.intreq=self.cycle=self.fraction=self.clamps=0
  self.events=list(events);self.index=0
 def enabled(self,i):return bool(self.dma&512 and self.dma&(1<<i))
 def irq(self,i):self.intreq |= 128<<i
 def reload(self,i):
  c=self.c[i];r=self.reg[i];c[0]=r[0]*65536+r[1];c[1]=r[2] or 65536;c[10]=0
 def attach(self,i,word):
  av=bool(self.adk&(1<<i));ap=bool(self.adk&(16<<i));c=self.c[i]
  if i==3 or not(av or ap):return
  if av and ap:
   av,ap=not c[10],bool(c[10]);c[10]^=1
  if av:self.c[i+1][8]=volume(word)
  if ap:
   value=period(word)
   if value<123:self.clamps+=1;value=123
   self.c[i+1][7]=value
 def fetch(self,i):
  c=self.c[i];a=c[0];word=self.memory[a]*256+self.memory[(a+1)%SIZE]
  c[5]=self.reg[i][5]=word;c[0]=(a+2)%SIZE;c[11]+=1
  self.attach(i,word)
  if c[9]:self.irq(i);c[9]=0
  c[1]-=1
  if c[1]==0:self.reload(i);self.irq(i)
 def transition(self,i):
  c=self.c[i];phase=c[4];mode=c[3]
  if phase==2:
   self.irq(i)
   if c[13]:c[4]=0;self.transition(i)
   else:c[3]=c[2]=0
   return
  if phase==0:
   if mode==1:self.fetch(i)
   else:c[5]=c[12];c[13]=0;c[11]+=1;self.attach(i,c[5])
   byte=c[5]>>8;c[4]=1
  else:byte=c[5]&255;c[4]=0 if mode==1 else 2
  c[6]=byte-256 if byte>=128 else byte;c[2]=c[7]
 def tick(self):
  due=[]
  for i,c in enumerate(self.c):
   if c[3]:c[2]-=1
   if c[3] and c[2]==0:due.append(i)
  for i in due:self.transition(i)
  self.cycle+=1
 def write(self,v,a):
  if 0xa0<=a<0xdc and a%16<12:
   i=(a-0xa0)//16;f=(a%16)//2;c=self.c[i]
   if f==0:v&=7
   if f==1:v&=65534
   if f==3:c[7]=period(v)
   if f==4:c[8]=volume(v)
   self.reg[i][f]=v
   if f==5 and not self.enabled(i):
    c[12]=v;c[13]=1
    if c[3]!=2:c[3]=2;c[4]=0;c[2]=1;c[10]=0
   return
  names={0x96:'dma',0x9e:'adk',0x9a:'intena',0x9c:'intreq'};name=names[a];old=getattr(self,name)
  setattr(self,name,(old|v)&32767 if v&32768 else old&~v)
  if a==0x96:
   for i,c in enumerate(self.c):
    was=bool(old&512 and old&(1<<i));now=self.enabled(i)
    if now and not was:self.reload(i);c[2]=1;c[3]=1;c[4]=0;c[9]=1;c[13]=0
    if was and not now:c[3]=c[2]=0
 def to(self,target):
  while self.index<len(self.events) and self.events[self.index][0]<=target:
   at,v,a=self.events[self.index]
   while self.cycle<at:self.tick()
   self.write(v,a);self.index+=1
  while self.cycle<target:self.tick()
 def sample(self):
  sides=[0,0]
  for i,c in enumerate(self.c):
   if not self.adk&(17<<i):sides[0 if i in [0,3] else 1]+=c[6]*c[8]*2
  return sides
 def render(self,count):
  data=bytearray()
  for _ in range(count):
   ticks,self.fraction=divmod(self.fraction+CLOCK,RATE);self.to(self.cycle+ticks)
   data+=struct.pack('<hh',*self.sample())
  return bytes(data)
 def snapshot(self):return sum(self.reg,[])+sum(self.c,[])+[self.dma,self.adk,self.intena,self.intreq,self.cycle,self.fraction,self.clamps,len(self.events),self.index]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);p.add_argument('--benchmark',action='store_true');args=p.parse_args();binary=args.sigma.resolve()
 work=ROOT/'.work/1137';work.mkdir(parents=True,exist_ok=True)
 files=['examples/paula.fs','examples/paula-play.fs','tests/scripts/verify-paula.py','examples/pcm-synth-play.fs','examples/pcm-synth.fs']
 report={'platform':platform.platform(),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'source_sha256_lf':{f:hashlib.sha256((ROOT/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in files},'tests':[]}
 def run(code,source='examples/paula.fs'):
  with tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.fs',dir=work,delete=False) as f:
   path=Path(f.name);f.write(code.replace(' PA-EVENT!',' PA-EVENT!\n'))
  try:q=subprocess.run([str(binary),source,str(path)],cwd=ROOT,input=b'',capture_output=True,timeout=45)
  finally:path.unlink()
  assert q.returncode==0 and not q.stderr,(q.returncode,q.stdout[:1200],q.stderr)
  return q.stdout.decode().split()
 def queue(events):return ' '.join(f'{v} {a} {t} PA-EVENT!' for t,v,a in events)+' '
 def snapshot(events,target,slow=False):
  m=Model(events);m.to(target)
  q=list(map(int,run(DUMP+'PA-DEMO-MEMORY '+queue(events)+('TRUE PA-SLOW ! ' if slow else '')+f'{target} PA-TO SNAP DEPTH . BYE')))
  assert q==m.snapshot()+[0],(target,slow,[(i,x,y) for i,(x,y) in enumerate(zip(q,m.snapshot()+[0])) if x!=y][:12])
 for per in [0,123,124,255,65535]:
  e=[(0,3,164),(0,per,166),(0,64,168),(0,0x8201,150)]
  for at in [0,1,period(per),period(per)+1,2*period(per)+1,4*period(per)+1]:snapshot(e,at)
 report['tests'].append({'case':'period-high-low-fetch-first-last-irq','checkpoints':30})
 cases=[DEMO+[(1,0x780,156),(427,512,162),(428,1,164),(1000,512,150),(1001,0x8200,150)],DEMO+[(1,0x780,156),(200,1,150),(201,0x8001,150)],DEMO+[(123,0,166),(124,65535,182),(1000,0x780,156)],[(0,123,166),(0,64,168),(0,0x7f80,170),(100,0x0180,170),(150,0xff7f,170),(300,0x1234,170)]]
 for i,bit in enumerate([1,16,17,2,32,34,4,64,68,8,128,136,255]):cases.append(DEMO+[(0,32768|bit,158),(2000,bit,158),(2001,64,184),(2200,123,198)])
 for e in cases:
  e.sort(key=lambda x:x[0])
  for at in [1,124,247,1000,7000]:snapshot(e,at)
  snapshot(e,7000,True)
 report['tests'].append({'case':'master-enable-restart-manual-attach-simultaneous-boundaries','scenarios':len(cases),'checkpoints':len(cases)*6})
 assert run('127 0 PA-MEM! 128 1 PA-MEM! 1 164 0 PA-WRITE 123 166 0 PA-WRITE 64 168 0 PA-WRITE 33281 150 0 PA-WRITE 1 PA-TO PA-SAMPLE . . 30 1 PA-READ . 124 PA-TO PA-SAMPLE . . 247 PA-TO 0 11 PA@ . DEPTH . BYE')==['0','16256','128','0','-16384','2','0']
 assert run('123 166 0 PA-WRITE 64 168 0 PA-WRITE 32640 170 0 PA-WRITE 1 PA-TO 0 6 PA@ . 0 156 1 PA-WRITE 65407 170 100 PA-WRITE 124 PA-TO 0 6 PA@ . 247 PA-TO 0 6 PA@ . 30 247 PA-READ . 370 PA-TO 0 6 PA@ . 493 PA-TO 0 3 PA@ . 0 6 PA@ . DEPTH . BYE')==['127','-128','-1','128','127','0','127','0']
 assert run('49280 154 0 PA-WRITE 32896 156 0 PA-WRITE PA-IRQ? . 128 156 0 PA-WRITE PA-IRQ? . 30 0 PA-READ . DEPTH . BYE')==['-1','0','0','0']
 assert run('7 160 0 PA-WRITE 65535 162 0 PA-WRITE 2 164 0 PA-WRITE 123 166 0 PA-WRITE 1 524286 PA-MEM! 2 524287 PA-MEM! 3 0 PA-MEM! 4 1 PA-MEM! 33281 150 0 PA-WRITE 247 PA-TO 0 5 PA@ . 0 0 PA@ . 0 1 PA@ . DEPTH . BYE')==['772','524286','2','0']
 assert run('127 168 0 PA-WRITE 0 8 PA@ . 65535 160 0 PA-WRITE 0 0 PA-R@ . 65535 162 0 PA-WRITE 0 1 PA-R@ . TRUE PA-SLOW ! PA-RESET PA-SLOW @ . 0 7 PA@ . DEPTH . BYE')==['64','7','65534','0','65536','0']
 report['tests'].append({'case':'hand-byte-order-manual-latch-irq-mask-wrap-masks-reset'})
 assert run('127 0 PA-MEM! 128 1 PA-MEM! 123 166 0 PA-WRITE 1 164 0 PA-WRITE 33281 150 0 PA-WRITE 1 PA-TO 0 1 PA-MEM! 124 PA-TO 0 6 PA@ . DEPTH . BYE')==['-128','0']
 assert run('123 166 0 PA-WRITE 1 164 0 PA-WRITE 33281 150 0 PA-WRITE 255 166 50 PA-WRITE 0 2 PA@ . 124 PA-TO 0 2 PA@ . 378 PA-TO 0 11 PA@ . 379 PA-TO 0 11 PA@ . DEPTH . BYE')==['74','255','1','2','0']
 assert list(map(int,run(': VOLUMES 128 0 DO I 168 0 PA-WRITE 0 8 PA@ . LOOP ; VOLUMES DEPTH . BYE')))==[64 if i&64 else i for i in range(128)]+[0]
 assert run('123 166 0 PA-WRITE 32784 158 0 PA-WRITE 1 170 0 PA-WRITE 1 PA-TO 1 7 PA@ . PA-PER-CLAMPS @ . 0 170 1 PA-WRITE 247 PA-TO 1 7 PA@ . PA-PER-CLAMPS @ . DEPTH . BYE')==['123','1','65536','1','0']
 code=DUMP+'PA-DEMO-MEMORY ';expected=[]
 for mask in range(256):
  e=DEMO+[(0,32768|mask,158)];m=Model(e);m.to(1000);expected+=m.snapshot()
  code+='PA-RESET '+queue(e)+'1000 PA-TO SNAP\n'
 assert list(map(int,run(code+'DEPTH . BYE')))==expected+[0]
 report['tests'].append({'case':'buffer-latch-delayed-period-all128-volume-values-all256-attach-masks'})
 events=sorted(DEMO+[(13,32785,158),(1000,17,158),(1001,65535,170),(2010,64,184),(3001,128,156),(4001,123,166),(5001,0x8002,158),(7001,2,158),(10000,49280,154)],key=lambda x:x[0])
 with tempfile.TemporaryDirectory(prefix='pcm-',dir=work) as d:
  out=Path(d)/'pcm.bin';m=Model(events);expected=m.render(2048)
  for slow,split in [(False,False),(True,False),(False,True)]:
   code=DUMP+'PA-DEMO-MEMORY '+queue(events)+('TRUE PA-SLOW ! ' if slow else '')+'CREATE OUT 8192 ALLOT '+('OUT 2048 PA-RENDER' if not split else 'OUT 1 PA-RENDER OUT 4 + 511 PA-RENDER OUT 2048 + 1536 PA-RENDER')+f' S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 8192 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP DEPTH . BYE'
   assert list(map(int,run(code)))==m.snapshot()+[0];assert out.read_bytes()==expected,(slow,split,'PCM mismatch')
 digest=hashlib.sha256(expected).hexdigest();assert digest=='ab75b30b15c8d7f96ad1d05d57931f054d132483ad9779a07b7f8ce5560ad52d'
 report['tests'].append({'case':'four-channel-stereo-full-pcm-fast-reference-split-python','frames':2048,'sha256':digest})
 bad=[(-1,166,50,-24),(65536,166,50,-24),(1,165,50,-24),(1,512,50,-24),(1,2,50,-24),(1,166,-1,-24),(1,166,0,-24),(122,166,50,-21),(256,150,50,-21),(8192,154,50,-21),(1,156,50,-21),(256,158,50,-21)]
 count=0
 for word in ['PA-WRITE','PA-EVENT!']:
  for v,a,t,error in bad:
   q=run(DUMP+'PA-DEMO-MEMORY '+queue(DEMO)+f'1 PA-TO : BAD {v} {a} {t} {word} ; SNAP [\'] BAD CATCH . SNAP DEPTH . BYE')
   assert len(q)==180 and q[:89]==q[90:179] and q[89]==str(error) and q[-1]=='0',(word,v,a,t,q);count+=1
 for body,error in [('PA-WRITE',-4),('PA-EVENT!',-4),('160 2 PA-READ DROP',-21),('2 0 PA-READ DROP',-24),('-1 PA-RUN',-24),('9223372036854775807 PA-RUN',-24),('0 -1 PA-RENDER',-24)]:
  q=run(DUMP+'1 PA-TO : BAD '+body+" ; SNAP ['] BAD CATCH . SNAP DEPTH . BYE")
  assert len(q)==180 and q[:89]==q[90:179] and q[89]==str(error) and q[-1]=='0',(body,q);count+=1
 report['tests'].append({'case':'atomic-value-address-mask-period-read-time-stack-errors','cases':count})
 with tempfile.TemporaryDirectory(prefix='memory-',dir=work) as d:
  out=Path(d)/'memory.bin';code='PA-DEMO-MEMORY '
  for i,(v,a) in enumerate([(-1,0),(256,0),(1,-1),(1,SIZE)]):code+=f": BAD{i} {v} {a} PA-MEM! ; ['] BAD{i} CATCH . "
  code+='PA-RESET '+f'S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD PA-MEMORY 524288 FD WRITE-FILE THROW FD CLOSE-FILE THROW DEPTH . BYE'
  assert run(code)==['-24']*4+['0'];assert out.read_bytes()==INITIAL
 report['tests'].append({'case':'full512k-memory-atomic-errors-and-reset-preservation'})
 assert run(': FILL-Q 1024 0 DO 32 168 I PA-EVENT! LOOP ; FILL-Q 511 PA-TO 63 168 1024 PA-EVENT! PA-EVENT-COUNT @ . PA-EVENT-INDEX @ . 1024 PA-TO 0 8 PA@ . DEPTH . BYE')==['513','0','63','0']
 assert run("32 168 5 PA-EVENT! 63 168 5 PA-WRITE 0 8 PA@ . : BAD 1 168 4 PA-EVENT! ; ['] BAD CATCH . DEPTH . BYE")==['63','-24','0']
 assert run(": FILL-Q 1024 0 DO 32 168 I PA-EVENT! LOOP ; : BAD 1 168 1024 PA-EVENT! ; FILL-Q ['] BAD CATCH . PA-EVENT-COUNT @ . PA-CYCLE @ . DEPTH . BYE")==['-528','1024','0','0']
 report['tests'].append({'case':'queue-capacity-order-compaction-and-immediate-tie'})
 stream='VARIABLE PA-WRITE-INDEX VARIABLE PA-END : PA-QUEUE-WRITES PA-CYCLE @ PA-FRACTION @ 512 PA-CPU * + PA-RATE / + PA-END ! BEGIN PA-WRITE-INDEX @ PA-CPU * 8000 / PA-END @ <= WHILE PA-WRITE-INDEX @ 65 MOD 168 PA-WRITE-INDEX @ PA-CPU * 8000 / PA-EVENT! 1 PA-WRITE-INDEX +! REPEAT ; '
 with tempfile.TemporaryDirectory(prefix='stream-',dir=work) as d:
  out=Path(d)/'pcm.bin';end=8192*CLOCK//RATE;active=DEMO+[(i*CLOCK//8000,i%65,168) for i in range(1,end*8000//CLOCK+1)];m=Model(active);expected=m.render(8192)
  code=stream+'PA-DEMO-MEMORY '+queue(DEMO)+'0 PA-RUN 1 PA-WRITE-INDEX ! CREATE OUT 32768 ALLOT : PA-RENDER-STREAM 16 0 DO PA-QUEUE-WRITES OUT I 2048 * + 512 PA-RENDER LOOP ; PA-RENDER-STREAM '+f'S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 32768 FD WRITE-FILE THROW FD CLOSE-FILE THROW PA-CYCLE @ . PA-WRITE-INDEX @ . DEPTH . BYE'
  assert list(map(int,run(code)))==[end,len(active)-len(DEMO)+1,0];assert out.read_bytes()==expected
 report['tests'].append({'case':'8khz-streaming-enqueue-compaction-full-stereo-oracle','frames':8192,'writes':len(active)-len(DEMO),'sha256':hashlib.sha256(expected).hexdigest()})
 start=time.perf_counter_ns();q=list(map(int,run('PA-DEMO-MEMORY PA-DEMO-SETUP 16 FALSE PA-STREAM PS-FRAMES @ . PS-HANDLE @ . AUDIO? . DEPTH . BYE','examples/paula-play.fs')))
 assert q[:2]==[8192,0] and q[2] in [0,-1] and q[3]==0,q
 report['silent_pcm']={'frames':q[0],'audio_available':q[2],'whole_process_monotonic_ns':time.perf_counter_ns()-start,'scope':'Owned process; synthesis then zeros to two-channel PCM; no generated waveform audition.'}
 assert run("PA-DEMO-MEMORY PA-DEMO-SETUP 9223372036854775797 PA-CYCLE ! : BAD 1 FALSE PA-STREAM ; ['] BAD CATCH . PS-HANDLE @ . DEPTH . BYE",'examples/paula-play.fs')==['-24','0','0']
 report['tests'].append({'case':'silent-stereo-pcm-and-error-cleanup'})
 if args.benchmark:
  nominal=DEMO+[(101+i*17011,i%65,168+(i%4)*16) for i in range(128)]
  stress=[(t,123 if a>=160 and a%16==6 else 1 if a>=160 and a%16==4 else 64 if a>=160 and a%16==8 else v,a) for t,v,a in DEMO]
  attach=[(t,123 if a>=160 and a%16==6 else 4 if a>=160 and a%16==4 else 64 if a>=160 and a%16==8 else v,a) for t,v,a in DEMO]+[(0,0x8051,158)]
  attach_memory=bytearray(INITIAL);attach_memory[:8]=bytes.fromhex('0040007b0020007c');attach_memory[256:264]=bytes.fromhex('007b007c007d007e')
  extra=' '.join(f'{b} {a} PA-MEM!' for a,b in list(enumerate(attach_memory[:8]))+[(256+i,b) for i,b in enumerate(attach_memory[256:264])])+' '
  frames=32768;end=frames*CLOCK//RATE;results={}
  intro='CREATE OUT 2048 ALLOT 2VARIABLE T0 2VARIABLE U0 2VARIABLE T1 2VARIABLE U1 : CPU-ALL CPUTIME D+ ; : PA-BENCH 64 0 DO OUT 512 PA-RENDER LOOP ; : SUM-OUT 0 2048 0 DO OUT I + C@ + LOOP ; '
  for name in ['fast','reference','fast_min_period','fast_attach','fast_8khz_volume','fast_8khz_manual']:
   active=nominal if name in ['fast','reference'] else stress if name=='fast_min_period' else attach if name=='fast_attach' else DEMO
   stream_source=stream
   if name=='fast_8khz_manual':
    active=[(t,0x820e if a==150 else v,a) for t,v,a in DEMO]
    stream_source=stream.replace('65 MOD 168','37 * 65535 AND 170')
   base=list(active)
   if name.startswith('fast_8khz'):
    active=base+[(i*CLOCK//8000,(i*37)&65535 if name=='fast_8khz_manual' else i%65,170 if name=='fast_8khz_manual' else 168) for i in range(1,end*8000//CLOCK+1)]
   m=Model(active,attach_memory if name=='fast_attach' else INITIAL);expected=m.render(frames);checksum=sum(expected[-2048:])
   setup='PA-RESET '+queue(base)+('TRUE PA-SLOW ! ' if name=='reference' else '')+'0 PA-RUN '
   body=intro
   if name.startswith('fast_8khz'):body=stream_source+intro.replace('OUT 512 PA-RENDER','PA-QUEUE-WRITES OUT 512 PA-RENDER');setup+='1 PA-WRITE-INDEX ! '
   memory='PA-DEMO-MEMORY '+(extra if name=='fast_attach' else '')
   with tempfile.TemporaryDirectory(prefix='bench-oracle-',dir=work) as d:
    out=Path(d)/'pcm.bin'
    verify=memory+body+'CREATE VERIFY-OUT 131072 ALLOT : PA-VERIFY 64 0 DO '+('PA-QUEUE-WRITES ' if name.startswith('fast_8khz') else '')+'VERIFY-OUT I 2048 * + 512 PA-RENDER LOOP ; '+setup+'PA-VERIFY '+f'S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD VERIFY-OUT 131072 FD WRITE-FILE THROW FD CLOSE-FILE THROW PA-CYCLE @ . PA-INTREQ @ . PA-PER-CLAMPS @ . 0 11 PA@ . 1 11 PA@ . 2 11 PA@ . 3 11 PA@ . DEPTH . BYE'
    assert list(map(int,run(verify)))==[end,m.intreq,m.clamps,*[c[11] for c in m.c],0];assert out.read_bytes()==expected,(name,'full workload PCM')
   code=memory+body+setup+'PA-BENCH '+setup+'CPU-ALL U0 2! NTIME T0 2! PA-BENCH NTIME T0 2@ D- T1 2! CPU-ALL U0 2@ D- U1 2! T1 2@ D. U1 2@ D. SUM-OUT . PA-CYCLE @ . PA-INTREQ @ . PA-PER-CLAMPS @ . DEPTH . BYE'
   wall=[];cpu=[]
   for _ in range(7):
    q=list(map(int,run(code)));assert q[0]>0 and q[1]>=0 and q[2:]==[checksum,end,m.intreq,m.clamps,0],(name,q);wall.append(q[0]);cpu.append(q[1])
   median=statistics.median(wall)
   results[name]={'source':code,'full_pcm_verification_source':verify,'full_forth_pcm_matches_python':True,'frames':frames,'chip_ticks':end,'wall_nanoseconds':wall,'process_cpu_microseconds':cpu,'median_ns_per_frame':median/frames,'median_realtime_ratio':frames*1e9/(median*RATE),'last_buffer_byte_sum':checksum,'oracle_pcm_sha256':hashlib.sha256(expected).hexdigest(),'final_pending_irq':m.intreq,'period_clamps':m.clamps,'word_fetches':[c[11] for c in m.c],'writes':len(active),'stereo_nonzero_samples':[sum(struct.unpack_from('<h',expected,i)[0]!=0 for i in range(side*2,len(expected),4)) for side in [0,1]]}
  report['benchmark']={'scope':'Six declared stereo Paula workloads, seven fresh processes each; warmup/reset/memory initialization/initial queue outside timing. NTIME wall ns and user+system CPUTIME us. 8kHz includes enqueue/compaction in timed region. Separate untimed process compares every byte of32768frames and final IRQ/clamp/fetch counters with Python. No emulatedCPU/Agnus bus or real device playback.','nominal_events':nominal,'stress_events':stress,'attach_events':attach,'results':results}
 print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
