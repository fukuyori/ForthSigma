#!/usr/bin/env python3
"""NTSC APU regression: independent Python per-cycle model and shared-helper Forth equivalence."""
import argparse,hashlib,json,platform,struct,subprocess,tempfile,statistics
from pathlib import Path
R=Path(__file__).resolve().parents[2]
CPU=1789773;RATE=48000
LENGTH=[10,254,20,2,40,4,80,6,160,8,60,10,14,12,26,14,12,16,24,18,48,20,96,22,192,24,72,26,16,28,32,30]
NOISE=[4,8,16,32,64,96,128,160,202,254,380,508,762,1016,2034,4068]
DUTY=[[0,1,0,0,0,0,0,0],[0,1,1,0,0,0,0,0],[0,1,1,1,1,0,0,0],[1,0,0,1,1,1,1,1]]
VARS=['CYCLE','FRAME','MODE','INHIBIT','IRQ','ENABLE','LINEAR','RELOAD','LFSR','NOISE-MODE','RESET-AT','PENDING-MODE','FRACTION','EVENT-COUNT','EVENT-INDEX']
DUMP=': SNAP 44 0 DO NA-STATE I CELLS + @ . LOOP '+ ' '.join('NA-'+v+' @ .' for v in VARS)+' 15 0 DO NA-DMC I CELLS + @ . LOOP ; '
DEMO=[(0,15,0x4015),(0,191,0x4000),(0,8,0x4001),(0,253,0x4002),(0,8,0x4003),(0,115,0x4004),(0,8,0x4005),(0,167,0x4006),(0,8,0x4007),(0,255,0x4008),(0,253,0x400a),(0,8,0x400b),(0,56,0x400c),(0,132,0x400e),(0,8,0x400f)]

class Model:
 def __init__(self,events=(),memory=None):
  self.c=[[0]*11 for _ in range(4)];self.c[3][1]=1
  self.cycle=self.frame=self.mode=self.inhibit=self.irq=self.enable=self.linear=self.reload=self.noise_mode=self.reset_at=self.pending_mode=self.fraction=0
  self.lfsr=1;self.events=list(events);self.index=0
  self.nd=[0]*15;self.nd[4]=213;self.nd[11]=8;self.nd[12]=1
  self.memory=bytearray(32768) if memory is None else bytearray(memory)
  assert len(self.memory)==32768
 def target(self,i):
  c=self.c[i];p=c[1];delta=p>>(c[8]&7)
  return max(0,p-delta-(i==0)) if c[8]&8 else p+delta
 def muted(self,i):return self.c[i][1]<8 or self.target(i)>2047
 def quarter(self):
  for i in [0,1,3]:
   c=self.c[i];v=c[0]&15
   if c[5]:c[5]=0;c[7]=15;c[6]=v
   elif c[6]:c[6]-=1
   else:
    c[6]=v
    if c[7]:c[7]-=1
    elif c[0]&32:c[7]=15
  if self.reload:self.linear=self.c[2][0]&127
  elif self.linear:self.linear-=1
  if not self.c[2][0]&128:self.reload=0
 def half(self):
  for i,c in enumerate(self.c):
   if c[4] and not c[0]&(128 if i==2 else 32):c[4]-=1
  for i in [0,1]:
   c=self.c[i];s=c[8]
   if c[9]==0 and s&128 and s&7 and not self.muted(i):c[1]=self.target(i)
   if c[9]==0 or c[10]:c[9]=(s>>4)&7;c[10]=0
   else:c[9]-=1
 def write(self,value,address):
  if 0x4010<=address<=0x4013:
   field=address-0x4010
   if field==0:
    self.nd[0]=value;self.nd[4]=[428,380,340,320,286,254,226,214,190,160,142,128,106,84,72,54][value&15]//2-1
    if not value&128:self.nd[13]=0
   elif field==1:self.nd[1]=value&127
   else:self.nd[field]=value
   return
  if address==0x4015:
   self.enable=value&31;self.nd[13]=0
   if not value&16:self.nd[7]=0
   elif not self.nd[7]:self.restart()
   for i,c in enumerate(self.c):
    if not value&(1<<i):c[4]=0
   return
  if address==0x4017:
   self.inhibit=value&64
   if self.inhibit:self.irq=0
   self.pending_mode=value&128;self.reset_at=self.cycle+(4 if self.cycle&1 else 3);return
  i=(address-0x4000)//4;reg=address&3;c=self.c[i]
  if i<2:
   if reg==0:c[0]=value
   elif reg==1:c[8]=value;c[10]=1
   elif reg==2:c[1]=(c[1]&0x700)|value
   else:
    c[1]=(c[1]&255)|((value&7)<<8)
    if self.enable&(1<<i):c[4]=LENGTH[value>>3]
    c[3]=0;c[5]=1
  elif i==2:
   if reg==0:c[0]=value
   elif reg==2:c[1]=(c[1]&0x700)|value
   elif reg==3:
    c[1]=(c[1]&255)|((value&7)<<8)
    if self.enable&4:c[4]=LENGTH[value>>3]
    self.reload=1
  else:
   if reg==0:c[0]=value
   elif reg==2:self.noise_mode=value&128;c[1]=NOISE[value&15]//2-1
   elif reg==3:
    if self.enable&8:c[4]=LENGTH[value>>3]
    c[5]=1
 def restart(self):self.nd[6]=0xc000+self.nd[2]*64;self.nd[7]=self.nd[3]*16+1
 def fetch(self):
  d=self.nd
  if d[9] or not d[7]:return
  d[8]=self.memory[d[6]-0x8000];d[9]=1;d[6]=(d[6]+1) if d[6]<0xffff else 0x8000;d[7]-=1;d[14]+=1
  if not d[7]:
   if d[0]&64:self.restart()
   elif d[0]&128:d[13]=1
 def dmc_clock(self):
  d=self.nd
  if d[5]:d[5]-=1;return
  d[5]=d[4]
  if not d[12]:
   if d[10]&1:
    if d[1]<=125:d[1]+=2
   elif d[1]>=2:d[1]-=2
  d[10]>>=1;d[11]-=1
  if not d[11]:
   d[11]=8
   if d[9]:d[12]=0;d[10]=d[8];d[9]=0
   else:d[12]=1
 def tick(self):
  self.cycle+=1;self.fetch()
  for i,c in enumerate(self.c):
   if i!=2 and self.cycle&1:continue
   if c[2]:c[2]-=1;continue
   c[2]=c[1]
   if i<2:c[3]=(c[3]+1)%8
   elif i==2:
    if c[4] and self.linear:c[3]=(c[3]+1)%32
   else:self.lfsr=(self.lfsr>>1)|(((self.lfsr^(self.lfsr>>(6 if self.noise_mode else 1)))&1)<<14)
  if not self.cycle&1:self.dmc_clock()
  self.frame+=1
  if self.reset_at and self.reset_at==self.cycle:
   self.reset_at=0;self.frame=0;self.mode=self.pending_mode
   if self.mode:self.quarter();self.half()
   return
  if self.frame in [7457,14913,22371] or self.frame==(37281 if self.mode else 29829):self.quarter()
  if self.frame in [14913,37281 if self.mode else 29829]:self.half()
  if not self.mode and self.frame in [29828,29829,29830] and not self.inhibit:self.irq=1
  if self.frame==(37282 if self.mode else 29830):self.frame=0
 def to(self,target):
  while self.index<len(self.events) and self.events[self.index][0]<=target:
   at,v,a=self.events[self.index]
   while self.cycle<at:self.tick()
   self.write(v,a);self.index+=1
  while self.cycle<target:self.tick()
 def snapshot(self):
  return sum(self.c,[])+[self.cycle,self.frame,self.mode,self.inhibit,self.irq,self.enable,self.linear,self.reload,self.lfsr,self.noise_mode,self.reset_at,self.pending_mode,self.fraction,len(self.events),self.index]+self.nd
 def volume(self,i):return self.c[i][0]&15 if self.c[i][0]&16 else self.c[i][7]
 def levels(self):
  p=[self.volume(i) if self.c[i][4] and not self.muted(i) and DUTY[self.c[i][0]>>6][self.c[i][3]] else 0 for i in [0,1]]
  k=self.c[2][3];t=15-k if k<16 else k-16
  n=self.volume(3) if self.c[3][4] and not self.lfsr&1 else 0
  return *p,t,n
 def sample(self):
  p,q,t,n=self.levels();s=t*12241*22638+n*8227*22638+self.nd[1]*8227*12241
  return min(32767,9588*(p+q)*32767//(100*(8128+100*(p+q)))+15979*s*32767//(100*(8227*12241*22638+100*s)))
 def render(self,count):
  out=bytearray()
  for _ in range(count):
   self.fraction,clocks= (self.fraction+CPU)%RATE,(self.fraction+CPU)//RATE
   self.to(self.cycle+clocks);out+=struct.pack('<h',self.sample())
  return bytes(out)

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);p.add_argument('--benchmark',action='store_true');args=p.parse_args();binary=args.sigma.resolve()
 work=R/'.work/1132';work.mkdir(parents=True,exist_ok=True)
 report={'platform':platform.platform(),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'source_sha256_lf':{f:hashlib.sha256((R/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in ['include/nes-apu.fs','tests/audio/nes-apu-play.fs','tests/scripts/verify-nes-apu.py','tests/audio/pcm-synth.fs','tests/audio/pcm-synth-play.fs']},'tests':[]}
 def run(code,source='tests/audio/nes-apu-demo.fs'):
  # Use an owned input file so long event schedules do not hit the CLI -e string limit.
  with tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.fs',dir=work,delete=False) as f:
   path=Path(f.name);f.write(code.replace(' NA-EVENT!',' NA-EVENT!\n'))
  try:q=subprocess.run([str(binary),source,str(path)],cwd=R,input=b'',capture_output=True,timeout=45)
  finally:path.unlink()
  assert q.returncode==0 and not q.stderr,(q.returncode,q.stdout,q.stderr)
  return q.stdout.decode().split()
 def schedule(events):return ' '.join(f'{v} {a} {at} NA-EVENT!' for at,v,a in events)+' '
 def snap(events,target,slow=False):
  model=Model(events);model.to(target)
  code=DUMP+schedule(events)+('TRUE NA-SLOW ! ' if slow else '')+f'{target} NA-TO SNAP DEPTH . BYE'
  actual=list(map(int,run(code)));assert actual==model.snapshot()+[0],(target,[(i,a,b) for i,(a,b) in enumerate(zip(actual,model.snapshot()+[0])) if a!=b][:8])
 # Edge boundaries for frame clocks, status/IRQ, envelope and length. No output involved.
 for target in [0,1,2,3,7456,7457,14912,14913,22371,29827,29828,29829,29830,29831,60000]:snap(DEMO,target)
 report['tests'].append({'case':'four-step-frame-timer-state-boundaries','checkpoints':15})
 for events in [DEMO+[(1,128,0x4017)],DEMO+[(0,128,0x4017)],DEMO+[(7454,128,0x4017)],DEMO+[(29828,64,0x4017)],DEMO+[(500,0,0x4015),(501,15,0x4015)]]:
  for target in [7457,14913,37281,37285,37286,40000]:snap(events,target)
 report['tests'].append({'case':'delayed-reset-parity-collision-inhibit-disable','checkpoints':30})
 # Dense deterministic writes around CPU/sample/frame boundaries, same-cycle ordering included.
 events=DEMO+[(1,0x81,0x4001),(2,0x89,0x4005),(37,7,0x4002),(38,8,0x4002),(511,0,0x4008),(512,255,0x4008),(513,0,0x400e),(7456,255,0x4000),(7457,0,0x400f),(14912,2,0x400b),(14913,8,0x400b),(20001,128,0x4017),(25001,0,0x4017),(29828,0,0x4015),(29829,15,0x4015),(29829,8,0x4003),(30001,255,0x400e)]
 for i in range(70):events.append((31000+i*503,(i*29)&255,[0x4000,0x4002,0x4004,0x4006,0x4008,0x400c,0x400e][i%7]))
 events.sort(key=lambda e:e[0])
 with tempfile.TemporaryDirectory(prefix='vectors-',dir=work) as d:
  output=Path(d)/'out.bin'
  model=Model(events);expected=model.render(2048)
  # Fixed1134 output: changing both implementations must not redefine regression truth.
  assert hashlib.sha256(expected).hexdigest()=='c63131af04a7ac388810613e3425568cc4dce1b3f8334e3a1c392421c8d94755'
  for slow,split in [(False,False),(False,True),(True,False)]:
   render='OUT 2048 NA-RENDER' if not split else 'OUT 1 NA-RENDER OUT 2 + 511 NA-RENDER OUT 1024 + 1536 NA-RENDER'
   code=DUMP+schedule(events)+('TRUE NA-SLOW ! ' if slow else '')+'CREATE OUT 4096 ALLOT '+render+f' S" {output.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 4096 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP DEPTH . BYE'
   actual=list(map(int,run(code)));assert output.read_bytes()==expected,(slow,split,'pcm mismatch');assert actual==model.snapshot()+[0],(slow,split,'state mismatch')
  report['tests'].append({'case':'scheduled-render-fast-split-reference-oracle','frames':2048,'writes':len(events),'sha256':hashlib.sha256(expected).hexdigest()})
 # Hand expectations: pulse phase/period8 and a single quarter-frame envelope reload.
 code='15 16405 0 NA-WRITE 159 16384 0 NA-WRITE 8 16385 0 NA-WRITE 8 16386 0 NA-WRITE 0 16387 0 NA-WRITE 2 NA-TO 0 NA-PULSE . 0 3 NA@ . 0 2 NA@ . 7457 NA-TO 0 7 NA@ . DEPTH . BYE'
 assert run(code)==['15','1','8','15','0']
 assert run('29827 NA-STATUS . 29828 NA-STATUS . NA-IRQ? . 29829 NA-STATUS . 29830 NA-STATUS . DEPTH . BYE')==['0','64','0','64','64','0']
 report['tests'].append({'case':'hand-pulse-envelope-and-triple-frame-irq'})
 assert run('15 16405 0 NA-WRITE 0 16386 0 NA-WRITE 1 16387 0 NA-WRITE 0 16390 0 NA-WRITE 1 16391 0 NA-WRITE 9 16385 0 NA-WRITE 9 16389 0 NA-WRITE 0 NA-TARGET . 1 NA-TARGET . DEPTH . BYE')==['127','128','0']
 report['tests'].append({'case':'hand-sweep-pulse1-ones-complement'})

 # Invalid immediate and queued calls must not advance time or mutate any exposed state.
 bad=[(-1,0x4000,5,-24),(256,0x4000,5,-24),(0,0x3fff,5,-24),(0,0x4014,5,-24),(0,0x4016,5,-24),(0,0x4018,5,-24),(0,0x4000,-1,-24),(0,0x4000,0,-24)]
 for word in ['NA-WRITE','NA-EVENT!']:
  for v,a,t,err in bad:
   code=DUMP+f'NA-DEMO-SETUP 1 NA-TO : BAD {v} {a} {t} {word} ; SNAP [\'] BAD CATCH . SNAP DEPTH . BYE'
   q=run(code);assert len(q)==150 and q[:74]==q[75:149] and int(q[74])==err and q[-1]=='0',(word,v,a,t,q)
 report['tests'].append({'case':'invalid-register-and-time-atomic','cases':16})
 assert run(": BAD 0 -1 NA-RENDER ; ['] BAD CATCH . 0 0 NA-RENDER DEPTH . BYE")==['-24','0']
 # Same-cycle events keep order; queue rejects out-of-order and over-capacity before effects.
 assert run("1 16384 0 NA-EVENT! 2 16384 0 NA-EVENT! 0 NA-RUN 0 0 NA@ . NA-EVENT-INDEX @ . DEPTH . BYE")==['2','2','0']
 code=": FILL-Q 1024 0 DO 1 16384 I NA-EVENT! LOOP ; : BAD 1 16384 1024 NA-EVENT! ; FILL-Q ['] BAD CATCH . NA-EVENT-COUNT @ . NA-CYCLE @ . DEPTH . BYE"
 assert run(code)==['-528','1024','0','0']
 assert run(": BAD 1 16384 1 NA-EVENT! ; 1 16384 2 NA-EVENT! ['] BAD CATCH . NA-EVENT-COUNT @ . NA-CYCLE @ . DEPTH . BYE")==['-24','1','0','0']
 report['tests'].append({'case':'queue-order-capacity-zero-and-negative-render'})
 assert run(": BAD 9223372036854775807 NA-RUN ; 1 NA-RUN ['] BAD CATCH . NA-CYCLE @ . DEPTH . BYE")==['-24','1','0']
 assert run(": BAD 0 16407 9223372036854775807 NA-WRITE ; ['] BAD CATCH . NA-CYCLE @ . DEPTH . BYE")==['-24','0','0']
 report['tests'].append({'case':'timestamp-addition-overflow-before-advance'})
 # Reuse after complete/partial consumption; APU state must survive queue compaction.
 assert run(": FILL-Q 1024 0 DO 1 16384 I NA-EVENT! LOOP ; FILL-Q 1023 NA-TO 2 16384 1024 NA-EVENT! 1024 NA-TO 0 0 NA@ . NA-CYCLE @ . NA-EVENT-COUNT @ . NA-EVENT-INDEX @ . DEPTH . BYE")==['2','1024','1','1','0']
 assert run(": FILL-Q 1024 0 DO I 255 AND 16384 I NA-EVENT! LOOP ; FILL-Q 511 NA-TO 99 16384 1024 NA-EVENT! NA-EVENT-COUNT @ . NA-EVENT-INDEX @ . 1024 NA-TO 0 0 NA@ . DEPTH . BYE")==['513','0','99','0']
 assert run('1 16384 10 NA-EVENT! 2 16384 10 NA-WRITE 0 0 NA@ . DEPTH . BYE')==['2','0']
 report['tests'].append({'case':'queue-reclaim-complete-partial-and-immediate-order'})
 for body in ['0 NA-STATUS DROP','-1 NA-RUN','9223372036854775807 NA-RUN','0 16407 9223372036854775804 NA-WRITE']:
  q=run(DUMP+'1 NA-RUN : BAD '+body+" ; SNAP ['] BAD CATCH . SNAP DEPTH . BYE")
  assert len(q)==150 and q[:74]==q[75:149] and q[74]=='-24' and q[-1]=='0',(body,q)
 for body in ['NA-WRITE','1 NA-WRITE','1 16384 NA-WRITE','NA-EVENT!']:
  q=run(DUMP+': BAD '+body+" ; SNAP ['] BAD CATCH . SNAP DEPTH . BYE")
  assert len(q)==150 and q[:74]==q[75:149] and q[74]=='-4' and q[-1]=='0',(body,q)
 # Unused writes and unused enable bits have no register side effects.
 q=run(DUMP+'SNAP 255 16393 0 NA-WRITE 255 16397 0 NA-WRITE 224 16405 0 NA-WRITE SNAP DEPTH . BYE');assert q[:74]==q[74:148] and q[148:]==['0']
 assert run('1 NA-LFSR ! NA-NOISE-SHIFT NA-LFSR @ . NA-NOISE-SHIFT NA-LFSR @ . 65 NA-LFSR ! 128 NA-NOISE-MODE ! NA-NOISE-SHIFT NA-LFSR @ . DEPTH . BYE')==['16384','8192','32','0']
 assert run('NA-PULSE-MIX 15 CELLS + @ . NA-PULSE-MIX 30 CELLS + @ . DEPTH . BYE')==['4894','8469','0']
 report['tests'].append({'case':'error-atomic-stack-underflow-unused-bits-hand-lfsr-mixer'})
 # Enqueue during rendering; compare continuous output with a preloaded schedule.
 with tempfile.TemporaryDirectory(prefix='streaming-',dir=work) as d:
  output=Path(d)/'out.bin';events=DEMO+[(20000,130,0x4002)];m=Model(events);expected=m.render(1024)
  code=DUMP+schedule(DEMO)+'CREATE OUT 2048 ALLOT OUT 512 NA-RENDER 130 16386 20000 NA-EVENT! OUT 1024 + 512 NA-RENDER '+f' S" {output.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 2048 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP DEPTH . BYE'
  assert list(map(int,run(code)))==m.snapshot()+[0];assert output.read_bytes()==expected
 report['tests'].append({'case':'enqueue-between-render-calls-continuity'})


 # Integration is deliberately silent. PCM is separate from the pure APU timing region.
 import time
 start=time.perf_counter_ns()
 code='NA-DEMO-SETUP 16 FALSE NA-STREAM PS-FRAMES @ . PS-WRITES @ . PS-PARTIAL @ . PS-FULL @ . PS-WAITS @ . PS-UNDERRUN-COUNT @ . AUDIO? . PS-HANDLE @ . DEPTH . BYE'
 q=list(map(int,run(code,'tests/audio/nes-apu-play.fs')));assert len(q)==9 and q[0]==8192 and q[-2:]==[0,0],q
 assert q[5]>=0 and q[6] in [0,-1],q
 report['silent_pcm']={'source':code,'whole_process_monotonic_ns':time.perf_counter_ns()-start,'frames':q[0],'write_calls':q[1],'partial':q[2],'full':q[3],'waits':q[4],'underruns':q[5],'audio_available':q[6],'scope':'One new process; startup, synthesis, silencing, host write/wait/drain/close/exit. No audible generated waveform submitted.'}
 code="NA-DEMO-SETUP 9223372036854775797 NA-CYCLE ! : BAD 1 FALSE NA-STREAM ; ['] BAD CATCH . PS-HANDLE @ . DEPTH . BYE"
 assert run(code,'tests/audio/nes-apu-play.fs')==['-24','0','0']
 report['tests'].append({'case':'real-pcm-render-error-closes-owned-stream'})
 if args.benchmark:
  # 32768 samples: ~683 ms of NES audio, with all voices and 128 scheduled writes after setup.
  # One warm-up, reset and enqueue outside measured region; seven new processes.
  code_base='CREATE OUT 1024 ALLOT 2VARIABLE T0 2VARIABLE T1 2VARIABLE U0 2VARIABLE U1 : CPU-ALL CPUTIME D+ ; : NA-BENCH 64 0 DO OUT 512 NA-RENDER LOOP ; : SUM-OUT 0 1024 0 DO OUT I + C@ + LOOP ; '
  bench_events=DEMO+[(0,99,0x4004),(0,40,0x400c)]
  for i in range(128):
   a=[0x4002,0x4006,0x400a,0x400e][i%4];v=(128+i%80) if a!=0x400e else (i%12+3)|((i&1)<<7)
   bench_events.append((101+i*9001,v,a))
  stress_events=DEMO+[(0,99,0x4004),(0,40,0x400c),(0,0,0x400e),(0,0,0x400a)]
  stress_events += [(at,(v&128) if a==0x400e else v,a) for at,v,a in bench_events[len(DEMO)+2:]]
  final_cycle=32768*CPU//RATE;record={}
  for mode in ['fast','reference','fast_max_noise']:
   active_events=stress_events if mode=='fast_max_noise' else bench_events
   expected=Model(active_events).render(32768);last_sum=sum(expected[-1024:])
   setup='NA-RESET '+schedule(active_events)+('TRUE NA-SLOW ! ' if mode=='reference' else '')+'0 NA-RUN '
   code=code_base+setup+' NA-BENCH '+setup+' CPU-ALL U0 2! NTIME T0 2! NA-BENCH NTIME T0 2@ D- T1 2! CPU-ALL U0 2@ D- U1 2! T1 2@ D. U1 2@ D. SUM-OUT . NA-CYCLE @ . DEPTH . BYE'
   samples=[];cpu=[]
   for _ in range(7):
    q=list(map(int,run(code)));assert q[0]>0 and q[1]>=0 and q[2:]==[last_sum,final_cycle,0],q;samples.append(q[0]);cpu.append(q[1])
   median=statistics.median(samples);record[mode]={'frames':32768,'cpu_cycles':final_cycle,'source':code,'wall_nanoseconds':samples,'process_cpu_microseconds':cpu,'last_buffer_byte_sum':last_sum,'median_ns_per_frame':median/32768,'median_ns_per_cpu_cycle':median/final_cycle,'median_realtime_ratio':32768*1e9/(median*RATE)}
  report['benchmark']={'scope':'APU-only; four voices and scheduled register writes, output stores included; no emulated6502/PPU/DMC/DMA/device/PCM pacing/filters. Point samples, not bandlimited. New process per repeat; warm-up/reset/queue loading excluded; NTIME wall can jump. All7 positive samples and CPU counters recorded.','events':bench_events,'max_noise_events':stress_events,'results':record}
 print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
