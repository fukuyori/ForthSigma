#!/usr/bin/env python3
"""Declared 2MHz YM2149/ST model: independent master-clock oracle, no physical I/O."""
import argparse,hashlib,json,math,platform,re,statistics,struct,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CLOCK=2000000;RATE=48000;SELECT=0xff8800;DATA=0xff8802
LEVELS=[0]+[math.floor(32767*10**(-1.5*(31-i)/20)) for i in range(1,32)]
VARS=['NOISE-COUNT','NOISE-HALF','LFSR','ENV-COUNT','ENV-STEP','ENV-ATTACK','ENV-HOLD','ENV-ALTERNATE','ENV-HOLDING','CYCLE','DIV','FRACTION','SELECT','EVENT-COUNT','EVENT-INDEX']
DUMP=': SNAP 16 0 DO YM-REGS I CELLS + @ . LOOP 3 0 DO YM-TONE-COUNT I CELLS + @ . LOOP 3 0 DO YM-TONE-HIGH I CELLS + @ . LOOP 2 0 DO YM-PINS I CELLS + @ . LOOP '+' '.join('YM-'+v+' @ .' for v in VARS)+' ; '
DEMO=[(0,v,r) for r,v in enumerate([28,1,227,1,82,2,9,48,12,10,16,100,0,14])]
class Model:
 def __init__(self,events=()):
  self.r=[0]*16;self.tc=[0]*3;self.th=[False]*3;self.pins=[255,255]
  self.nc=self.nh=0;self.lfsr=1;self.ec=0;self.es=31;self.ea=0;self.ehold=True;self.ealt=False;self.eholding=True
  self.cycle=self.div=self.fraction=self.select=0;self.events=list(events);self.index=0
 def tp(self,i):return max(1,self.r[2*i]|((self.r[2*i+1]&15)<<8))
 def ep(self):return max(1,self.r[11]|self.r[12]<<8)
 def envelope(self):
  if self.es:self.es-=1
  else:
   if self.ealt:self.ea^=31
   if self.ehold:self.eholding=True
   else:self.es=31
 def step(self):
  for i in range(3):
   self.tc[i]+=1
   if self.tc[i]>=self.tp(i):self.tc[i]=0;self.th[i]=not self.th[i]
  self.nh^=1
  if self.nh:
   self.nc+=1
   if self.nc>=max(1,self.r[6]&31):self.nc=0;self.lfsr=(self.lfsr>>1)|(((self.lfsr^(self.lfsr>>3))&1)<<16)
  if not self.eholding:
   self.ec+=1
   if self.ec>=self.ep():self.ec=0;self.envelope()
 def tick(self):
  self.div+=1
  if self.div==8:self.div=0;self.step()
  self.cycle+=1
 def write(self,v,target):
  if target<16:
   self.r[target]=v
   if target==13:
    shape=v&15;self.ea=31 if shape&4 else 0;self.ehold=bool(shape&1) if shape&8 else True;self.ealt=bool(shape&2) if shape&8 else bool(self.ea)
    self.es=31;self.ec=0;self.eholding=False
  elif target<18:self.pins[target-16]=v
  elif target==18:self.select=v
  elif self.select<16:self.write(v,self.select)
 def to(self,target):
  while self.index<len(self.events) and self.events[self.index][0]<=target:
   at,v,r=self.events[self.index]
   while self.cycle<at:self.tick()
   self.write(v,r);self.index+=1
  while self.cycle<target:self.tick()
 def pin(self,port):return self.pins[port]&self.r[14+port] if self.r[7]&(64<<port) else self.pins[port]
 def channel(self,i):
  if not((self.th[i] or self.r[7]&(1<<i)) and (self.lfsr&1 or self.r[7]&(8<<i))):return 0
  amp=self.r[8+i];level=self.es^self.ea if amp&16 else 0 if not amp&15 else (amp&15)*2+1
  return LEVELS[level]
 def render(self,count):
  result=bytearray()
  for _ in range(count):
   ticks,self.fraction=divmod(self.fraction+CLOCK,RATE);self.to(self.cycle+ticks);result+=struct.pack('<h',sum(self.channel(i) for i in range(3))//3)
  return bytes(result)
 def snapshot(self):return self.r+self.tc+[-int(v) for v in self.th]+self.pins+[self.nc,self.nh,self.lfsr,self.ec,self.es,self.ea,-int(self.ehold),-int(self.ealt),-int(self.eholding),self.cycle,self.div,self.fraction,self.select,len(self.events),self.index]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);p.add_argument('--benchmark',action='store_true');args=p.parse_args();binary=args.sigma.resolve();work=ROOT/'.work/1138';work.mkdir(parents=True,exist_ok=True)
 files=['include/ym2149.fs','include/ym2149-levels.fs','examples/ym2149-play.fs','scripts/ym2149-levels.py','tests/scripts/verify-ym2149.py','examples/pcm-synth-play.fs','examples/pcm-synth.fs']
 report={'platform':platform.platform(),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'source_sha256_lf':{f:hashlib.sha256((ROOT/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in files},'tests':[]}
 def run(code,source='examples/ym2149-demo.fs'):
  with tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.fs',dir=work,delete=False) as f:
   path=Path(f.name)
   for word in ['YM-EVENT!','YM-INPUT-EVENT!','YM-BUS-EVENT!','YM-WRITE','YM-INPUT!','YM-BUS!']:code=re.sub(' '+re.escape(word)+r'(?=\s|$)',lambda m:m[0]+'\n',code)
   f.write(code)
  try:q=subprocess.run([str(binary),source,str(path)],cwd=ROOT,input=b'',capture_output=True,timeout=45)
  finally:path.unlink()
  assert q.returncode==0 and not q.stderr,(q.returncode,q.stdout[:1500],q.stderr)
  return q.stdout.decode().split()
 def queue(events):
  result=[]
  for t,v,r in events:
   if r<16:result.append(f'{v} {r} {t} YM-EVENT!')
   elif r<18:result.append(f'{v} {r-16} {t} YM-INPUT-EVENT!')
   else:result.append(f'{v} {SELECT if r==18 else DATA} {t} YM-BUS-EVENT!')
  return ' '.join(result)+' '
 def snapshot(events,target,slow=False):
  m=Model(events);m.to(target);q=list(map(int,run(DUMP+queue(events)+('TRUE YM-SLOW ! ' if slow else '')+f'{target} YM-TO SNAP DEPTH . BYE')))
  assert q==m.snapshot()+[0],(target,slow,[(i,a,b) for i,(a,b) in enumerate(zip(q,m.snapshot()+[0])) if a!=b][:10])
 assert list(map(int,run(': LEVELS 32 0 DO YM-LEVELS I CELLS + @ . LOOP ; LEVELS BYE')))==LEVELS
 report['tests'].append({'case':'all32-decimal-table-independent-double-math','levels':LEVELS})
 for at in [0,1,7,8,9,15,16,31,32,125,800,801,1000,65535,65536]:snapshot(DEMO,at)
 report['tests'].append({'case':'master-divider-tone-noise-envelope-boundaries','checkpoints':15})
 down=list(range(31,-1,-1));up=list(range(32));zero=[0]*32;top=[31]*32
 shape_parts={**{i:[down,zero,zero] for i in [0,1,2,3,9]},**{i:[up,zero,zero] for i in [4,5,6,7,15]},8:[down]*3,10:[down,up,down],11:[down,top,top],12:[up]*3,13:[up,top,top],14:[up,down,up]}
 for shape in range(16):
  code=f'{shape} 13 0 YM-WRITE : ENVS 96 0 DO YM-ENV-LEVEL . 8 YM-RUN LOOP ; ENVS DEPTH . BYE'
  assert list(map(int,run(code)))==sum(shape_parts[shape],[])+[0],shape
  e=DEMO+[(13,shape,13),(99,0,11),(100,0,12),(102,1,0),(103,0,1),(1000,0,6),(1001,shape|240,13)]
  snapshot(e,7000);snapshot(e,7000,True)
 report['tests'].append({'case':'all16-shapes-hand-levels-retrigger-periodzero-shortening','levels_per_shape':96})
 expected=[];code=': SET-HIGH 3 0 DO DUP YM-TONE-HIGH I CELLS + ! LOOP DROP ; 15 8 0 YM-WRITE 15 9 0 YM-WRITE 15 10 0 YM-WRITE '
 for mixer in range(64):
  for th in [0,1]:
   for noise in [0,1]:
    code+=f'{mixer} 7 0 YM-WRITE { -th} SET-HIGH {1 if noise else 2} YM-LFSR ! 0 YM-CHANNEL . 1 YM-CHANNEL . 2 YM-CHANNEL . '
    expected.extend(32767 if ((th or mixer&(1<<i)) and (noise or mixer&(8<<i))) else 0 for i in range(3))
 assert list(map(int,run(code+'DEPTH . BYE')))==expected+[0]
 assert run('255 7 0 YM-WRITE YM-SAMPLE . 15 8 0 YM-WRITE 15 9 0 YM-WRITE 15 10 0 YM-WRITE YM-SAMPLE . 0 8 0 YM-WRITE 0 9 0 YM-WRITE 0 10 0 YM-WRITE YM-SAMPLE . DEPTH . BYE')==['0','32767','0','0']
 report['tests'].append({'case':'all64-mixer-truth-tables-and-fixed-zero-mute','gate_cases':256})
 code='';expected=[]
 for port in range(2):
  for direction in range(2):
   for latch in [0,90,255]:
    code+=f'{(64<<port)*direction} 7 0 YM-WRITE {latch} {14+port} 0 YM-WRITE '
    for pins in range(256):
     code+=f'{pins} {port} 0 YM-INPUT! {14+port} 0 YM-READ . {port} YM-PORT@ . .\n';expected.extend([latch&pins if direction else pins,255 if direction else 0,latch])
 assert list(map(int,run(code+'DEPTH . BYE')))==expected+[0]
 report['tests'].append({'case':'both-ports-input-output-latch-readback-external-low-all256-pin-values','combinations':3072})
 assert run(f'8 {SELECT} 0 YM-BUS! 15 {DATA} 0 YM-BUS! {SELECT} 0 YM-BUS@ . 128 {SELECT} 0 YM-BUS! 99 {DATA} 0 YM-BUS! {SELECT} 0 YM-BUS@ . 8 0 YM-READ . 8 {SELECT} 0 YM-BUS! {SELECT} 0 YM-BUS@ . DEPTH . BYE')==['15','255','15','15','0']
 bus=DEMO+[(1,13,18),(1,14,19),(7,90,16),(8,64,7),(8,165,14),(100,255,18),(100,99,19),(200,8,18),(200,15,19)]
 snapshot(bus,1000);snapshot(bus,1000,True)
 assert run('14 13 7 YM-WRITE YM-ENV-LEVEL . 8 YM-TO YM-ENV-LEVEL . 8 13 8 YM-WRITE YM-ENV-LEVEL . 16 YM-TO YM-ENV-LEVEL . DEPTH . BYE')==['0','1','31','30','0']
 assert run('8 YM-TO YM-LFSR @ . 24 YM-TO YM-LFSR @ . DEPTH . BYE')==['65536','32768','0']
 report['tests'].append({'case':'st-bus-selection-deselection-queued-data-and-hand-r13-noise-phase'})
 events=sorted(bus+[(300,0,0),(301,0,1),(302,1,6),(501,0,11),(502,0,12),(503,10,13),(1001,255,17),(1002,192,7),(1003,165,15),(2000,13,18),(2001,9,19),(7000,15,8),(7001,0,9),(7002,0,10)],key=lambda x:x[0])
 with tempfile.TemporaryDirectory(prefix='pcm-',dir=work) as d:
  out=Path(d)/'pcm.bin';m=Model(events);expected=m.render(2048)
  for slow,split in [(False,False),(True,False),(False,True)]:
   code=DUMP+queue(events)+('TRUE YM-SLOW ! ' if slow else '')+'CREATE OUT 4096 ALLOT '+('OUT 2048 YM-RENDER' if not split else 'OUT 1 YM-RENDER OUT 2 + 511 YM-RENDER OUT 1024 + 1536 YM-RENDER')+f' S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 4096 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP DEPTH . BYE'
   assert list(map(int,run(code)))==m.snapshot()+[0];assert out.read_bytes()==expected,(slow,split,'PCM mismatch')
 digest=hashlib.sha256(expected).hexdigest();assert digest=='bf14ef0a51dfe0fc8e749ad7115f27c25abb077a475c8506f6e3df71948796b0'
 report['tests'].append({'case':'three-voice-noise-envelope-ports-bus-full-pcm-fast-reference-split','frames':2048,'sha256':digest})
 bad=[('YM-WRITE',-1,8,100,-24),('YM-WRITE',256,8,100,-24),('YM-WRITE',1,16,100,-24),('YM-EVENT!',1,-1,100,-24),('YM-EVENT!',1,8,0,-24),('YM-INPUT!',0,2,100,-24),('YM-INPUT-EVENT!',256,0,100,-24),('YM-BUS!',256,SELECT,100,-24),('YM-BUS-EVENT!',0,SELECT+1,100,-24)]
 for word,v,r,t,error in bad:
  q=run(DUMP+queue(DEMO)+f'1 YM-TO : BAD {v} {r} {t} {word} ; SNAP [\'] BAD CATCH . SNAP DEPTH . BYE')
  assert len(q)==80 and q[:39]==q[40:79] and q[39]==str(error) and q[-1]=='0',(word,q)
 for body,error in [('YM-WRITE',-4),('YM-INPUT!',-4),('YM-BUS!',-4),('16 100 YM-READ DROP',-24),('0 0 YM-READ DROP',-24),(f'{DATA} 100 YM-BUS@ DROP',-21),('-1 YM-RUN',-24),('9223372036854775807 YM-RUN',-24),('0 -1 YM-RENDER',-24),('-1 YM-PORT@ 2DROP',-24)]:
  q=run(DUMP+'1 YM-TO : BAD '+body+" ; SNAP ['] BAD CATCH . SNAP DEPTH . BYE")
  assert len(q)==80 and q[:39]==q[40:79] and q[39]==str(error) and q[-1]=='0',(body,q)
 report['tests'].append({'case':'atomic-register-port-bus-value-read-time-stack-errors','cases':19})
 assert run(': FILL-Q 1024 0 DO 3 8 I YM-EVENT! LOOP ; FILL-Q 511 YM-TO 15 8 1024 YM-EVENT! YM-EVENT-COUNT @ . YM-EVENT-INDEX @ . 1024 YM-TO 8 YM-R@ . DEPTH . BYE')==['513','0','15','0']
 assert run("3 8 5 YM-EVENT! 15 8 5 YM-WRITE 8 YM-R@ . : BAD 1 8 4 YM-EVENT! ; ['] BAD CATCH . DEPTH . BYE")==['15','-24','0']
 assert run(": FILL-Q 1024 0 DO 3 8 I YM-EVENT! LOOP ; : BAD 1 8 1024 YM-EVENT! ; FILL-Q ['] BAD CATCH . YM-EVENT-COUNT @ . YM-CYCLE @ . DEPTH . BYE")==['-528','1024','0','0']
 report['tests'].append({'case':'queue-order-capacity-compaction-immediate-tie'})
 stream='VARIABLE YM-WRITE-INDEX VARIABLE YM-END : YM-QUEUE-WRITES YM-CYCLE @ YM-FRACTION @ 512 YM-CPU * + YM-RATE / + YM-END ! BEGIN YM-WRITE-INDEX @ YM-CPU * 8000 / YM-END @ <= WHILE YM-WRITE-INDEX @ 15 AND 8 YM-WRITE-INDEX @ YM-CPU * 8000 / YM-EVENT! 1 YM-WRITE-INDEX +! REPEAT ; '
 with tempfile.TemporaryDirectory(prefix='stream-',dir=work) as d:
  out=Path(d)/'pcm.bin';end=8192*CLOCK//RATE;active=DEMO+[(i*CLOCK//8000,i&15,8) for i in range(1,end*8000//CLOCK+1)];m=Model(active);expected=m.render(8192)
  code=stream+queue(DEMO)+'0 YM-RUN 1 YM-WRITE-INDEX ! CREATE OUT 16384 ALLOT : STREAM 16 0 DO YM-QUEUE-WRITES OUT I 1024 * + 512 YM-RENDER LOOP ; STREAM '+f'S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 16384 FD WRITE-FILE THROW FD CLOSE-FILE THROW YM-CYCLE @ . YM-WRITE-INDEX @ . DEPTH . BYE'
  assert list(map(int,run(code)))==[end,len(active)-len(DEMO)+1,0];assert out.read_bytes()==expected
 report['tests'].append({'case':'8khz-write-stream-full-pcm-exceeds1024-enqueues','frames':8192,'writes':len(active)-len(DEMO),'sha256':hashlib.sha256(expected).hexdigest()})
 start=time.perf_counter_ns();q=list(map(int,run('YM-DEMO-SETUP 16 FALSE YM-STREAM PS-FRAMES @ . PS-HANDLE @ . AUDIO? . DEPTH . BYE','examples/ym2149-play.fs')))
 assert q[:2]==[8192,0] and q[2] in [0,-1] and q[3]==0,q
 report['silent_pcm']={'frames':q[0],'audio_available':q[2],'whole_process_monotonic_ns':time.perf_counter_ns()-start,'scope':'Model rendering then zeroed frames into owned mono PCM stream, no generated-wave audition.'}
 assert run("YM-DEMO-SETUP 9223372036854775797 YM-CYCLE ! : BAD 1 FALSE YM-STREAM ; ['] BAD CATCH . PS-HANDLE @ . DEPTH . BYE",'examples/ym2149-play.fs')==['-24','0','0']
 report['tests'].append({'case':'silent-pcm-and-render-error-cleanup'})
 if args.benchmark:
  nominal=list(DEMO)
  for i in range(128):
   r=[0,2,4,6,8,9,10,11,12,13,7][i%11]
   v=(i*7)&255 if r in [0,2,4] else i%31+1 if r in [6,11] else 0 if r==12 else i&15 if r in [8,9,10,13] else (i*13)&63
   nominal.append((101+i*9503,v,r))
  minimum=[(0,v,r) for r,v in enumerate([1,0,1,0,1,0,1,0,16,16,16,1,0,10])]
  staggered=[(0,v,r) for r,v in enumerate([2,0,3,0,5,0,7,0,16,16,16,11,0,10])]
  bus_stream='VARIABLE YM-WRITE-INDEX VARIABLE YM-END : YM-QUEUE-WRITES YM-CYCLE @ YM-FRACTION @ 512 YM-CPU * + YM-RATE / + YM-END ! BEGIN YM-WRITE-INDEX @ YM-CPU * 8000 / YM-END @ <= WHILE YM-WRITE-INDEX @ 4 MOD CASE 0 OF 8 ENDOF 1 OF 13 ENDOF 2 OF 14 ENDOF 3 OF 15 ENDOF ENDCASE YM-SELECT-ADDRESS YM-WRITE-INDEX @ YM-CPU * 8000 / YM-BUS-EVENT! YM-WRITE-INDEX @ 7 * 255 AND YM-DATA-ADDRESS YM-WRITE-INDEX @ YM-CPU * 8000 / YM-BUS-EVENT! YM-WRITE-INDEX @ 7 * INVERT 255 AND YM-WRITE-INDEX @ 1 AND YM-WRITE-INDEX @ YM-CPU * 8000 / YM-INPUT-EVENT! 1 YM-WRITE-INDEX +! REPEAT ; '
  intro='CREATE OUT 1024 ALLOT 2VARIABLE T0 2VARIABLE U0 2VARIABLE T1 2VARIABLE U1 : CPU-ALL CPUTIME D+ ; : YM-BENCH 64 0 DO OUT 512 YM-RENDER LOOP ; : SUM-OUT 0 1024 0 DO OUT I + C@ + LOOP ; '
  frames=32768;end=frames*CLOCK//RATE;results={}
  for name in ['fast','reference','fast_period1','fast_staggered','fast_8khz_volume','fast_8khz_bus_io']:
   base=nominal if name in ['fast','reference'] else minimum if name=='fast_period1' else staggered if name=='fast_staggered' else DEMO
   if name=='fast_8khz_bus_io':base=DEMO+[(0,192,7)]
   active=list(base)
   if name=='fast_8khz_volume':active += [(i*CLOCK//8000,i&15,8) for i in range(1,end*8000//CLOCK+1)]
   if name=='fast_8khz_bus_io':
    for i in range(1,end*8000//CLOCK+1):active += [(i*CLOCK//8000,[8,13,14,15][i%4],18),(i*CLOCK//8000,(i*7)&255,19),(i*CLOCK//8000,~(i*7)&255,16+(i&1))]
   m=Model(active);expected=m.render(frames);checksum=sum(expected[-1024:])
   setup='YM-RESET '+queue(base)+('TRUE YM-SLOW ! ' if name=='reference' else '')+'0 YM-RUN '
   body=intro
   if name.startswith('fast_8khz'):
    body=(bus_stream if name=='fast_8khz_bus_io' else stream)+intro.replace('OUT 512 YM-RENDER','YM-QUEUE-WRITES OUT 512 YM-RENDER');setup+='1 YM-WRITE-INDEX ! '
   with tempfile.TemporaryDirectory(prefix='bench-oracle-',dir=work) as d:
    out=Path(d)/'pcm.bin';verify=DUMP+body+'CREATE VERIFY-OUT 65536 ALLOT : YM-VERIFY 64 0 DO '+('YM-QUEUE-WRITES ' if name.startswith('fast_8khz') else '')+'VERIFY-OUT I 1024 * + 512 YM-RENDER LOOP ; '+setup+'YM-VERIFY '+f'S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD VERIFY-OUT 65536 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP DEPTH . BYE'
    q=list(map(int,run(verify)));assert len(q)==40 and q[:37]==m.snapshot()[:37] and q[37]==q[38] and q[39]==0,(name,q,m.snapshot());assert out.read_bytes()==expected,(name,'full PCM')
   code=DUMP+body+setup+'YM-BENCH '+setup+'CPU-ALL U0 2! NTIME T0 2! YM-BENCH NTIME T0 2@ D- T1 2! CPU-ALL U0 2@ D- U1 2! T1 2@ D. U1 2@ D. SUM-OUT . YM-CYCLE @ . YM-LFSR @ . YM-ENV-LEVEL . YM-SELECT @ . SNAP DEPTH . BYE'
   wall=[];cpu=[];states=[]
   for _ in range(7):
    q=list(map(int,run(code)));assert len(q)==47 and q[0]>0 and q[1]>=0 and q[2:7]==[checksum,end,m.lfsr,m.es^m.ea,m.select] and q[7:44]==m.snapshot()[:37] and q[44]==q[45] and q[46]==0,(name,q);wall.append(q[0]);cpu.append(q[1]);states.append(q[7:44])
   median=statistics.median(wall)
   results[name]={'source':code,'full_pcm_verification_source':verify,'full_forth_pcm_and_semantic_state_match_python':True,'all_timed_final_states_match_python':True,'timed_final_semantic_states':states,'frames':frames,'chip_clocks':end,'wall_nanoseconds':wall,'process_cpu_microseconds':cpu,'median_ns_per_frame':median/frames,'median_realtime_ratio':frames*1e9/(median*RATE),'last_buffer_byte_sum':checksum,'oracle_pcm_sha256':hashlib.sha256(expected).hexdigest(),'final_semantic_state':m.snapshot()[:37],'nonzero_samples':sum(struct.unpack_from('<h',expected,i)[0]!=0 for i in range(0,len(expected),2)),'queued_events':len(active)}
  report['benchmark']={'scope':'Six declared point-sampled YM2149/ST workloads, seven fresh processes each. Full warmup/reset/initial queue outside timing; streamed8kHz enqueue/compaction inside timing. NTIME wall ns and CPUTIME user+system us. Separate untimed Forth process compares all32768frames and complete semantic state with independent master-clock Python. No native PSG mean-renderer, physical peripherals, emulatedCPU/TOS or device playback in timings.','nominal_events':nominal,'minimum_events':minimum,'staggered_events':staggered,'results':results}
 print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
