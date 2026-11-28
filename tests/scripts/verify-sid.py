#!/usr/bin/env python3
"""PAL SID register/proxy model: independent per-clock Python, not a hardware oracle."""
import argparse,hashlib,json,math,platform,statistics,struct,subprocess,tempfile,time
from pathlib import Path
R=Path(__file__).resolve().parents[2]
CLOCK=985248;RATE=48000;MASK=(1<<24)-1
RATES=[9,32,63,95,149,220,267,313,392,977,1954,3126,3907,11720,19532,31251]
TAPS=[22,20,16,13,11,7,4,2]
COEFF=[math.floor(2*math.sin(math.pi*(30+5.8*i)/96000)*65536) for i in range(2048)]
VARS=['CYCLE','FRACTION','LOW','BAND','EVENT-COUNT','EVENT-INDEX','CLIPS','FILTER-LIMITS']
DUMP=': SNAP 25 0 DO SI-REGS I CELLS + @ . LOOP 30 0 DO SI-STATE I CELLS + @ . LOOP '+' '.join('SI-'+v+' @ .' for v in VARS)+' ; '
DEMO=[(0,68,54272),(0,29,54273),(0,0,54274),(0,8,54275),(0,34,54277),(0,168,54278),(0,65,54276),(0,230,54279),(0,14,54280),(0,67,54284),(0,136,54285),(0,21,54283),(0,113,54286),(0,9,54287),(0,50,54291),(0,104,54292),(0,33,54290),(0,7,54293),(0,100,54294),(0,167,54295),(0,31,54296)]

class Model:
 def __init__(self,events=()):
  self.reg=[0]*25;self.c=[[0]*10 for _ in range(3)]
  for c in self.c:c[1]=0x7ffff8;c[3]=2;c[6]=1;c[9]=1
  self.cycle=self.fraction=self.low=self.band=self.clips=self.limits=0;self.events=list(events);self.index=0
 def ctrl(self,i):return self.reg[i*7+4]
 def rate(self,i):
  stage=self.c[i][3];v=self.reg[i*7+(5 if stage<2 else 6)]
  return RATES[(v>>4) if stage==0 else v&15]
 def update_exp(self,i):
  d={255:1,93:2,54:4,26:8,14:16,6:30,0:1}
  if self.c[i][2] in d:self.c[i][9]=d[self.c[i][2]]
 def envelope(self,i):
  c=self.c[i]
  if c[3]==0:
   c[5]=0;c[2]=min(255,c[2]+1);self.update_exp(i)
   if c[2]==255:c[3]=1
   return
  c[5]+=1
  if c[5]<c[9]:return
  c[5]=0
  if c[6]:return
  sustain=(self.reg[i*7+6]>>4)*17
  if (c[3]==2 or c[2]>sustain) and c[2]:
   c[2]-=1;self.update_exp(i)
   if not c[2]:c[6]=1
 def tick(self):
  old=[c[0] for c in self.c];new=[0 if self.ctrl(i)&8 else (old[i]+c[7])&MASK for i,c in enumerate(self.c)]
  rising=[not old[i]&(1<<23) and bool(new[i]&(1<<23)) for i in range(3)]
  for i,c in enumerate(self.c):
   if not old[i]&(1<<19) and new[i]&(1<<19):c[1]=((c[1]<<1)|(((c[1]>>22)^(c[1]>>17))&1))&0x7fffff
   c[0]=0 if self.ctrl(i)&2 and rising[(i-1)%3] else new[i]
  for i,c in enumerate(self.c):
   c[4]=(c[4]+1)&32767
   if c[4]==self.rate(i):c[4]=0;self.envelope(i)
  self.cycle+=1
 def write(self,value,address):
  o=address-0xd400
  if o>=25:return
  if o<21:
   i,f=divmod(o,7);c=self.c[i]
   if f==3:value&=15
   if f==4:
    old=self.ctrl(i)
    if (old^value)&1:
     if value&1:c[3]=0;c[6]=0
     else:c[3]=2
    if value&8:c[0]=0;c[1]=0x7ffff8
    elif old&8:c[1]=0x7ffff8
   self.reg[o]=value
   if f<2:c[7]=self.reg[i*7]|self.reg[i*7+1]<<8
   if f in [2,3]:c[8]=self.reg[i*7+2]|self.reg[i*7+3]<<8
  else:self.reg[o]=value&7 if o==21 else value
 def to(self,target):
  while self.index<len(self.events) and self.events[self.index][0]<=target:
   at,v,a=self.events[self.index]
   while self.cycle<at:self.tick()
   self.write(v,a);self.index+=1
  while self.cycle<target:self.tick()
 def wave(self,i):
  ctl=self.ctrl(i);w=ctl&240;c=self.c[i];p=c[0]
  if not w:return 0
  if ctl&8:return 4095 if w==64 else 0
  if w==16:
   invert=bool(p&(1<<23)) ^ bool(ctl&4 and self.c[(i-1)%3][0]&(1<<23));x=(p>>12)&2047
   return (x^2047 if invert else x)*2
  if w==32:return p>>12
  if w==64:return 4095 if c[8]==0 or (c[8]!=4095 and (p>>12)>=c[8]) else 0
  x=0
  for bit in TAPS:x=x*2+((c[1]>>bit)&1)
  return x<<4
 def clamp_state(self,x):
  if abs(x)>8589934592:self.limits+=1
  return max(-8589934592,min(8589934592,x))
 def filter(self,inp):
  a=COEFF[self.reg[21]|self.reg[22]<<3];d=(1414-80*(self.reg[23]>>4))*65536//1000
  for _ in range(2):
   high=inp*65536-self.low-d*self.band//65536
   self.band=self.clamp_state(self.band+a*high//65536);self.low=self.clamp_state(self.low+a*self.band//65536)
  return ((self.low if self.reg[24]&16 else 0)+(self.band if self.reg[24]&32 else 0)+(high if self.reg[24]&64 else 0))//65536
 def sample(self):
  routed=direct=0
  for i,c in enumerate(self.c):
   value=(self.wave(i)-2048)*c[2]//255 if self.ctrl(i)&240 else 0
   if self.reg[23]&(1<<i):routed+=value
   elif not (i==2 and self.reg[24]&128):direct+=value
  filtered=self.filter(routed) if routed or self.low or self.band else 0
  value=(direct+filtered)*(self.reg[24]&15)//3
  if not -32768<=value<=32767:self.clips+=1
  return max(-32768,min(32767,value))
 def render(self,count,coverage=False):
  result=bytearray()
  self.coverage={'pulse_low':0,'pulse_high':0,'ring_source_high':0}
  for _ in range(count):
   clocks,self.fraction=divmod(self.fraction+CLOCK,RATE);self.to(self.cycle+clocks)
   if coverage:
    if self.ctrl(2)&240==64:self.coverage['pulse_low']+=self.wave(2)==0;self.coverage['pulse_high']+=self.wave(2)==4095
    self.coverage['ring_source_high']+=bool(self.ctrl(1)&4 and self.ctrl(1)&240==16 and self.c[0][0]&(1<<23))
   result+=struct.pack('<h',self.sample())
  return bytes(result)
 def snapshot(self):return self.reg+sum(self.c,[])+[self.cycle,self.fraction,self.low,self.band,len(self.events),self.index,self.clips,self.limits]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);p.add_argument('--benchmark',action='store_true');args=p.parse_args();binary=args.sigma.resolve();W=R/'.work/1136';W.mkdir(parents=True,exist_ok=True)
 report={'platform':platform.platform(),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'source_sha256_lf':{f:hashlib.sha256((R/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in ['include/sid.fs','tests/audio/sid-play.fs','include/sid-filter-coeffs.fs','scripts/sid-filter-coeffs.py','tests/scripts/verify-sid.py','tests/audio/pcm-synth-play.fs','tests/audio/pcm-synth.fs']},'tests':[]}
 def run(code,source='tests/audio/sid-demo.fs'):
  with tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.fs',dir=W,delete=False) as f:
   path=Path(f.name);f.write(code.replace(' SI-EVENT!',' SI-EVENT!\n'))
  try:q=subprocess.run([str(binary),source,str(path)],cwd=R,input=b'',capture_output=True,timeout=45)
  finally:path.unlink()
  assert q.returncode==0 and not q.stderr,(q.returncode,q.stdout[:1000],q.stderr)
  return q.stdout.decode().split()
 def schedule(events):return ' '.join(f'{v} {a} {at} SI-EVENT!' for at,v,a in events)+' '
 def snap(events,target,slow=False):
  m=Model(events);m.to(target);q=list(map(int,run(DUMP+schedule(events)+('TRUE SI-SLOW ! ' if slow else '')+f'{target} SI-TO SNAP DEPTH . BYE')))
  expected=m.snapshot()+[0];assert q==expected,(target,slow,[(i,a,b) for i,(a,b) in enumerate(zip(q,expected)) if a!=b][:8])
 # Verify the reproducible Decimal-generated proxy table against independently computed double math.
 assert list(map(int,run(': COEFFS 2048 0 DO SI-FILTER-COEFFS I CELLS + @ . LOOP ; COEFFS BYE')))==COEFF
 report['tests'].append({'case':'all2048-proxy-coefficients-independent-math','sha256':hashlib.sha256(b''.join(struct.pack('<q',x) for x in COEFF)).hexdigest()})
 for target in [0,1,8,9,16,48,63,64,1000,2295,5000,32767,32768,50000]:snap(DEMO,target)
 report['tests'].append({'case':'rate-phase-envelope-and-wrap-boundaries','checkpoints':14})
 for rate,period in enumerate(RATES):
  e=[(0,rate<<4,0xd405),(0,17,0xd404)]
  snap(e,period-1);snap(e,period);snap(e,2*period+1)
 report['tests'].append({'case':'all16-attack-periods-independent-state','checkpoints':48})
 # Noise LFSR clock continues for all voices, independent of selected waveform.
 events=DEMO+[(1,128,0xd40f),(1,129,0xd412),(16,23,0xd40b),(17,67,0xd404),(256,25,0xd40b),(257,23,0xd40b),(1000,0,0xd404),(1001,65,0xd404),(2000,0,0xd405),(2001,0,0xd406),(2300,64,0xd404),(2500,65,0xd404),(4000,0,0xd417),(4100,15,0xd418),(5000,255,0xd417),(5001,127,0xd418)]
 for i in range(64):events.append((6000+i*337,(i*13)&255,[0xd400,0xd407,0xd40e,0xd415,0xd416,0xd417,0xd418][i%7]))
 events.sort(key=lambda x:x[0])
 with tempfile.TemporaryDirectory(prefix='vector-',dir=W) as d:
  out=Path(d)/'pcm.bin';m=Model(events);expected=m.render(2048)
  for slow,split in [(False,False),(True,False),(False,True)]:
   render='OUT 2048 SI-RENDER' if not split else 'OUT 1 SI-RENDER OUT 2 + 511 SI-RENDER OUT 1024 + 1536 SI-RENDER'
   code=DUMP+schedule(events)+('TRUE SI-SLOW ! ' if slow else '')+'CREATE OUT 4096 ALLOT '+render+f' S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 4096 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP DEPTH . BYE'
   actual=list(map(int,run(code)));assert out.read_bytes()==expected,(slow,split,'PCM mismatch');assert actual==m.snapshot()+[0],(slow,split,'state mismatch',[(i,a,b) for i,(a,b) in enumerate(zip(actual,m.snapshot()+[0])) if a!=b][:8])
 digest=hashlib.sha256(expected).hexdigest()
 assert digest=='ad597ded6f6f2c5e26d3e167ed23be3881aa25b55fef9148a3c0e842553990c7',digest
 report['tests'].append({'case':'scheduled-three-voice-filter-fast-reference-split-oracle','frames':2048,'sha256':digest,'clipped_frames':m.clips,'filter_limits':m.limits})
 # Hand-derived accumulator/noise/envelope/reads, not generated by the model.
 assert run('0 54286 0 SI-WRITE 128 54287 0 SI-WRITE 129 54290 0 SI-WRITE 54299 0 SI-READ . 54299 16 SI-READ . 54299 48 SI-READ . DEPTH . BYE')==['254','254','252','0']
 assert run('17 54276 0 SI-WRITE 8 SI-TO 0 2 SI@ . 9 SI-TO 0 2 SI@ . 2295 SI-TO 0 2 SI@ . 0 3 SI@ . DEPTH . BYE')==['0','1','255','1','0']
 assert run('0 54286 0 SI-WRITE 128 54287 0 SI-WRITE 33 54290 0 SI-WRITE 54299 1 SI-READ . 54299 256 SI-READ . 54299 512 SI-READ . DEPTH . BYE')==['0','128','0','0']
 assert run('100 0 4 SI! 17 54276 0 SI-WRITE 32676 SI-TO 0 2 SI@ . 32677 SI-TO 0 2 SI@ . DEPTH . BYE')==['0','1','0']
 assert run('17 54276 0 SI-WRITE 1350 SI-TO 0 2 SI@ . 0 9 SI@ . 16 54276 1350 SI-WRITE 1368 SI-TO 0 2 SI@ . DEPTH . BYE')==['150','2','149','0']
 report['tests'].append({'case':'hand-noise-read-phase-adsr-delay-stateful-exp'})
 # Simultaneous hard-sync uses all pre-sync MSB rises, independent of voice update order.
 sync=[(0,0,0xd400),(0,128,0xd401),(0,19,0xd404),(0,0,0xd407),(0,128,0xd408),(0,19,0xd40b),(0,0,0xd40e),(0,128,0xd40f),(0,19,0xd412)]
 assert run(schedule(sync)+'256 SI-TO 0 0 SI@ . 1 0 SI@ . 2 0 SI@ . DEPTH . BYE')==['0','0','0','0'];snap(sync,10000,True);snap(sync,10000)
 report['tests'].append({'case':'simultaneous-sync-ring-test-and-reference'})
 # Endpoint and routing values are direct derivations, independent of Model.
 assert run('64 54276 0 SI-WRITE 0 SI-WAVE . 255 54274 0 SI-WRITE 15 54275 0 SI-WRITE 0 SI-WAVE . 72 54276 0 SI-WRITE 0 SI-WAVE . 24 54276 0 SI-WRITE 0 SI-WAVE . DEPTH . BYE')==['4095','0','4095','0','0']
 assert run('16 54276 0 SI-WRITE 0 SI-WAVE . 8388608 2 0 SI! 20 54276 0 SI-WRITE 0 SI-WAVE . DEPTH . BYE')==['0','4094','0']
 assert run('64 54290 0 SI-WRITE 255 2 2 SI! 15 54296 0 SI-WRITE SI-SAMPLE . 143 54296 0 SI-WRITE SI-SAMPLE . 4 54295 0 SI-WRITE SI-SAMPLE . DEPTH . BYE')==['10235','0','0','0']
 # Impulse response covers every mode and resonance endpoint, plus all cutoff extremes.
 for cutoff in [0,1,1023,2047]:
  for res in [0,15]:
   for mode in range(8):
    m=Model();m.reg[21]=cutoff&7;m.reg[22]=cutoff>>3;m.reg[23]=res<<4;m.reg[24]=mode<<4
    inputs=[2047,0,-2048]+[0]*29;expected=[m.filter(x) for x in inputs]
    code=f'{cutoff&7} 54293 0 SI-WRITE {cutoff>>3} 54294 0 SI-WRITE {res<<4} 54295 0 SI-WRITE {mode<<4} 54296 0 SI-WRITE '+' '.join(f'{x} SI-FILTER .' for x in inputs)+' SI-LOW @ . SI-BAND @ . SI-FILTER-LIMITS @ . DEPTH . BYE'
    assert list(map(int,run(code)))==expected+[m.low,m.band,m.limits,0],(cutoff,res,mode)
 report['tests'].append({'case':'pulse-test-ring-routing-hand-values-and-filter-impulses','impulse_cases':64})
 # FC0 alpha128, damping92667: two substeps give bp255/lp0 for +1,
 # and bp-256/lp-2 for -1. These values are derived without Model.
 assert run('127 54296 0 SI-WRITE 1 SI-FILTER . SI-LOW @ . SI-BAND @ . SI-RESET 127 54296 0 SI-WRITE -1 SI-FILTER . SI-LOW @ . SI-BAND @ . TRUE SI-SLOW ! SI-RESET SI-SLOW @ . DEPTH . BYE')==['1','0','255','-2','-2','-256','0','0']
 assert run('8589934593 SI-CLAMP . -8589934593 SI-CLAMP . SI-FILTER-LIMITS @ . DEPTH . BYE')==['8589934592','-8589934592','2','0']
 for low in [-8589934592,8589934592]:
  m=Model();m.low=low;m.band=-low;m.reg[21]=7;m.reg[22]=255;m.reg[23]=240;m.reg[24]=127
  expected=[m.sample() for _ in range(16)]
  code=f'{low} SI-LOW ! { -low} SI-BAND ! 7 54293 0 SI-WRITE 255 54294 0 SI-WRITE 240 54295 0 SI-WRITE 127 54296 0 SI-WRITE : EDGE-SAMPLES 16 0 DO SI-SAMPLE . LOOP ; EDGE-SAMPLES SI-CLIPS @ . SI-FILTER-LIMITS @ . DEPTH . BYE'
  assert list(map(int,run(code)))==expected+[m.clips,m.limits,0]
 report['tests'].append({'case':'filter-state-limiter-and-output-clipping-independent-extremes'})
 # Validate immediate/queued errors before time or state changes.
 bad=[(-1,0xd400,5,-24),(256,0xd400,5,-24),(1,0xd3ff,5,-24),(1,0xd419,5,-24),(1,0xd41f,5,-24),(0x51,0xd404,100000,-21),(0xc1,0xd40b,100000,-21),(1,0xd400,-1,-24),(1,0xd400,0,-24)]
 for word in ['SI-WRITE','SI-EVENT!']:
  for v,a,t,err in bad:
   q=run(DUMP+f'SI-DEMO-SETUP 1 SI-TO : BAD {v} {a} {t} {word} ; SNAP [\'] BAD CATCH . SNAP DEPTH . BYE')
   assert len(q)==128 and q[:63]==q[64:127] and q[63]==str(err) and q[-1]=='0',(word,v,a,t,q)
 for body,error in [('54272 100 SI-READ DROP',-21),('54297 100 SI-READ DROP',-21),('54298 100 SI-READ DROP',-21),('54299 0 SI-READ DROP',-24),('-1 SI-RUN',-24),('9223372036854775807 SI-RUN',-24),('SI-WRITE',-4),('SI-EVENT!',-4),('0 -1 SI-RENDER',-24)]:
  q=run(DUMP+'1 SI-TO : BAD '+body+" ; SNAP ['] BAD CATCH . SNAP DEPTH . BYE")
  assert len(q)==128 and q[:63]==q[64:127] and q[63]==str(error) and q[-1]=='0',(body,q)
 report['tests'].append({'case':'invalid-value-address-waveform-read-time-stack-atomic','cases':27})
 # Queue capacity, order, reclaim and queued-before-immediate tie handling.
 assert run(": FILL-Q 1024 0 DO 1 54272 I SI-EVENT! LOOP ; FILL-Q 511 SI-TO 2 54272 1024 SI-EVENT! SI-EVENT-COUNT @ . SI-EVENT-INDEX @ . 1024 SI-TO 0 SI-R@ . DEPTH . BYE")==['513','0','2','0']
 assert run('1 54272 10 SI-EVENT! 2 54272 10 SI-WRITE 0 SI-R@ . DEPTH . BYE')==['2','0']
 assert run(": FILL-Q 1024 0 DO 1 54272 I SI-EVENT! LOOP ; : BAD 1 54272 1024 SI-EVENT! ; FILL-Q ['] BAD CATCH . SI-EVENT-COUNT @ . SI-CYCLE @ . DEPTH . BYE")==['-528','1024','0','0']
 assert run(": BAD 1 54272 1 SI-EVENT! ; 1 54272 2 SI-EVENT! ['] BAD CATCH . SI-EVENT-COUNT @ . SI-CYCLE @ . DEPTH . BYE")==['-24','1','0','0']
 report['tests'].append({'case':'queue-order-capacity-compaction'})
 stream='VARIABLE SI-WRITE-INDEX VARIABLE SI-END : SI-QUEUE-WRITES SI-CYCLE @ SI-FRACTION @ 512 SI-CPU * + SI-RATE / + SI-END ! BEGIN SI-WRITE-INDEX @ SI-CPU * 8000 / SI-END @ <= WHILE SI-WRITE-INDEX @ 7 * 255 AND 54272 SI-WRITE-INDEX @ SI-CPU * 8000 / SI-EVENT! 1 SI-WRITE-INDEX +! REPEAT ; '
 with tempfile.TemporaryDirectory(prefix='stream-',dir=W) as d:
  out=Path(d)/'pcm.bin';end=8192*CLOCK//RATE;events=DEMO+[(i*CLOCK//8000,(i*7)&255,0xd400) for i in range(1,end*8000//CLOCK+1)];m=Model(events);expected=m.render(8192)
  code=stream+schedule(DEMO)+'0 SI-RUN 1 SI-WRITE-INDEX ! CREATE OUT 16384 ALLOT : RENDER-STREAM 16 0 DO SI-QUEUE-WRITES OUT I 1024 * + 512 SI-RENDER LOOP ; RENDER-STREAM '+f'S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 16384 FD WRITE-FILE THROW FD CLOSE-FILE THROW SI-CYCLE @ . SI-WRITE-INDEX @ . DEPTH . BYE'
  assert list(map(int,run(code)))==[end,len(events)-len(DEMO)+1,0];assert out.read_bytes()==expected
 report['tests'].append({'case':'streaming8khz-full-pcm-independent-oracle','frames':8192,'writes':len(events)-len(DEMO),'sha256':hashlib.sha256(expected).hexdigest()})
 start=time.perf_counter_ns();q=list(map(int,run('SI-DEMO-SETUP 16 FALSE SI-STREAM PS-FRAMES @ . PS-HANDLE @ . AUDIO? . SI-CLIPS @ . SI-FILTER-LIMITS @ . DEPTH . BYE','tests/audio/sid-play.fs')))
 assert len(q)==6 and q[0:2]==[8192,0] and q[2] in [0,-1] and q[-1]==0,q
 report['silent_pcm']={'frames':q[0],'audio_available':q[2],'clipped_frames':q[3],'filter_limits':q[4],'whole_process_monotonic_ns':time.perf_counter_ns()-start,'scope':'New process; proxy init/synth/zeroing/PCM open-write-wait-drain-close-exit. No generated waveform audition.'}
 assert run("SI-DEMO-SETUP 9223372036854775797 SI-CYCLE ! : BAD 1 FALSE SI-STREAM ; ['] BAD CATCH . PS-HANDLE @ . DEPTH . BYE",'tests/audio/sid-play.fs')==['-24','0','0']
 report['tests'].append({'case':'silent-pcm-and-render-error-cleanup'})
 if args.benchmark:
  frames=32768;end=frames*CLOCK//RATE
  nominal=DEMO+[(101+i*5003,(i*17)&255,[0xd400,0xd407,0xd40e,0xd415,0xd416,0xd417,0xd418][i%7]) for i in range(128)]
  heavy=[]
  for voice,control in enumerate([129,23,67]):
   base=0xd400+voice*7
   frequency=[65535,32767,21845][voice]
   heavy += [(0,frequency&255,base),(0,frequency>>8,base+1),(0,0,base+2),(0,8,base+3),(0,0,base+5),(0,240,base+6),(0,control,base+4)]
  heavy += [(0,7,0xd415),(0,255,0xd416),(0,247,0xd417),(0,127,0xd418)]
  heavy += [(101+i*5003,[129,23,67][i%3] & (255 if (i//3)&1 else 254),0xd404+(i%3)*7) for i in range(128)]
  intro='CREATE OUT 1024 ALLOT 2VARIABLE T0 2VARIABLE U0 2VARIABLE T1 2VARIABLE U1 : CPU-ALL CPUTIME D+ ; : SI-BENCH 64 0 DO OUT 512 SI-RENDER LOOP ; : SUM-OUT 0 1024 0 DO OUT I + C@ + LOOP ; '
  results={}
  for name in ['fast','reference','fast_max_filter_sync_noise','fast_max_three_noise','fast_8khz_writes']:
   active=nominal if name in ['fast','reference'] else heavy
   if name=='fast_max_three_noise':active=[(at,130|(v&1) if a in [0xd404,0xd40b,0xd412] else 255 if a<0xd415 and (a-0xd400)%7 in [0,1] else v,a) for at,v,a in heavy]
   # Future gate events cannot be prequeued ahead of streamed writes: preload only cycle0.
   if name=='fast_8khz_writes':active=[e for e in heavy if e[0]==0]+[(i*CLOCK//8000,(i*7)&255,0xd400) for i in range(1,end*8000//CLOCK+1)]
   m=Model(active);expected=m.render(frames,coverage=True);checksum=sum(expected[-1024:])
   if name in ['fast_max_filter_sync_noise','fast_8khz_writes']:assert all(m.coverage.values()),(name,m.coverage)
   setup='SI-RESET '+schedule([e for e in heavy if e[0]==0] if name=='fast_8khz_writes' else active)+('TRUE SI-SLOW ! ' if name=='reference' else '')+'0 SI-RUN '
   body=intro
   if name=='fast_8khz_writes':body=stream+intro.replace('OUT 512 SI-RENDER','SI-QUEUE-WRITES OUT 512 SI-RENDER');setup+='1 SI-WRITE-INDEX ! '
   # Validate the complete actual Forth output separately, outside the timed samples.
   with tempfile.TemporaryDirectory(prefix='bench-oracle-',dir=W) as d:
    out=Path(d)/'pcm.bin'
    verify=body+'CREATE VERIFY-OUT 65536 ALLOT : SI-VERIFY 64 0 DO '+('SI-QUEUE-WRITES ' if name=='fast_8khz_writes' else '')+'VERIFY-OUT I 1024 * + 512 SI-RENDER LOOP ; '+setup+'SI-VERIFY '+f'S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD VERIFY-OUT 65536 FD WRITE-FILE THROW FD CLOSE-FILE THROW SI-CYCLE @ . SI-CLIPS @ . SI-FILTER-LIMITS @ . SI-LOW @ . SI-BAND @ . 0 2 SI@ . 1 2 SI@ . 2 2 SI@ . DEPTH . BYE'
    assert list(map(int,run(verify)))==[end,m.clips,m.limits,m.low,m.band,*[c[2] for c in m.c],0];assert out.read_bytes()==expected,(name,'full workload PCM mismatch')
   code=body+setup+'SI-BENCH '+setup+'CPU-ALL U0 2! NTIME T0 2! SI-BENCH NTIME T0 2@ D- T1 2! CPU-ALL U0 2@ D- U1 2! T1 2@ D. U1 2@ D. SUM-OUT . SI-CYCLE @ . SI-CLIPS @ . SI-FILTER-LIMITS @ . DEPTH . BYE'
   wall=[];cpu=[]
   for _ in range(7):
    q=list(map(int,run(code)));assert q[0]>0 and q[1]>=0 and q[2:]==[checksum,end,m.clips,m.limits,0],(name,q,checksum,end,m.clips,m.limits);wall.append(q[0]);cpu.append(q[1])
   median=statistics.median(wall)
   results[name]={'source':code,'full_pcm_verification_source':verify,'full_forth_pcm_matches_python':True,'oracle_wave_coverage':m.coverage,'final_state_verified_against_forth':True,'frames':frames,'cpu_cycles':end,'wall_nanoseconds':wall,'process_cpu_microseconds':cpu,'last_buffer_byte_sum':checksum,'oracle_pcm_sha256':hashlib.sha256(expected).hexdigest(),'final_envelopes':[c[2] for c in m.c],'final_filter_state':[m.low,m.band],'clipped_frames':m.clips,'filter_limits':m.limits,'median_ns_per_frame':median/frames,'median_realtime_ratio':frames*1e9/(median*RATE),'writes':len(active)}
  report['benchmark']={'scope':'Seven fresh processes per workload; one full warmup, reset and initial queue loading outside timing. NTIME wall ns and CPUTIME user+system us. Three voices plus two-step integer proxy filter. 8kHz includes enqueue/compaction in timing. No emulated CPU, device output or actual SID analog response. Separate untimed Forth process compares every PCM byte and final filter/envelope state with Python; timed samples check last buffer checksum, cycle and clipping counters.','nominal_events':nominal,'heavy_events':heavy,'results':results}
 print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
