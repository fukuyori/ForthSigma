#!/usr/bin/env python3
"""DMC register/output model tests; own memory pattern, no ROM or hardware DMA claims."""
import argparse,hashlib,importlib.util,json,platform,statistics,struct,subprocess,tempfile,time
from pathlib import Path
R=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('apu_reference',R/'tests/scripts/verify-nes-apu.py');apu=importlib.util.module_from_spec(spec);spec.loader.exec_module(apu)
MEMORY=bytes((i*37+11)&255 for i in range(32768))
DATA=': DM-DATA 32768 0 DO I 37 * 11 + 255 AND NA-DMC-MEMORY I + C! LOOP ; DM-DATA '
RATES=[428,380,340,320,286,254,226,214,190,160,142,128,106,84,72,54]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);p.add_argument('--benchmark',action='store_true');args=p.parse_args();binary=args.sigma.resolve()
 W=R/'.work/1135';W.mkdir(parents=True,exist_ok=True)
 report={'platform':platform.platform(),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'source_sha256_lf':{f:hashlib.sha256((R/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in ['include/nes-apu.fs','tests/audio/nes-apu-play.fs','tests/audio/pcm-synth.fs','tests/audio/pcm-synth-play.fs','tests/scripts/verify-nes-apu.py','tests/scripts/verify-nes-dmc.py']},'memory_fixture':{'description':'Original byte[i]=(37*i+11)&255; emulated addresses8000..FFFF. No ROM.','sha256':hashlib.sha256(MEMORY).hexdigest()},'tests':[]}
 def run(code,source='tests/audio/nes-apu-demo.fs'):
  with tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.fs',dir=W,delete=False) as f:
   path=Path(f.name);f.write(code.replace(' NA-EVENT!',' NA-EVENT!\n'))
  try:q=subprocess.run([str(binary),source,str(path)],cwd=R,input=b'',capture_output=True,timeout=45)
  finally:path.unlink()
  assert q.returncode==0 and not q.stderr,(q.returncode,q.stdout[:1000],q.stderr)
  return q.stdout.decode().split()
 def queue(events):return ' '.join(f'{v} {a} {at} NA-EVENT!' for at,v,a in events)+' '
 def dmc(rate=15,start=0,length=0,flags=128):return [(0,flags|rate,0x4010),(0,64,0x4011),(0,start,0x4012),(0,length,0x4013),(0,31,0x4015)]
 def snapshot(events,target,slow=False):
  m=apu.Model(events,MEMORY);m.to(target)
  actual=list(map(int,run(apu.DUMP+DATA+queue(events)+('TRUE NA-SLOW ! ' if slow else '')+f'{target} NA-TO SNAP DEPTH . BYE')))
  expected=m.snapshot()+[0];assert actual==expected,(target,[(i,a,b) for i,(a,b) in enumerate(zip(actual,expected)) if a!=b][:8])
 for rate,period in enumerate(RATES):
  for target in [1,2,2+7*period,2+8*period,2+16*period]:snapshot(apu.DEMO+dmc(rate),target)
 report['tests'].append({'case':'all16-rates-reader-buffer-output-boundaries','checkpoints':80})
 scenarios=[dmc(flags=192),dmc(length=2)+[(3,15,0x4015)],dmc()+[(3,31,0x4015)],dmc()+[(3,0,0x4010)],dmc()+[(3,127,0x4011)],dmc(start=255,length=4),dmc()+[(1,15,0x4015),(500,31,0x4015)],dmc()+[(3,0,0x4017)],dmc()+[(4,0,0x4011),(5,0,0x4010)]]
 for events in scenarios:
  for target in [3,380,434,29999]:snapshot(apu.DEMO+events,target)
 report['tests'].append({'case':'loop-stop-restart-irq-disable-dac-wrap-and-rate-change','checkpoints':36})
 snapshot(apu.DEMO+dmc(start=255,length=4),30000,True)
 # Hand vector: initial8 silent bit clocks, then 55 LSB-first at fastest rate54.
 code='85 49152 NA-MEM! 15 16400 0 NA-WRITE 64 16401 0 NA-WRITE 16 16405 0 NA-WRITE 1 NA-STATUS . 2 NA-TO 1 ND@ . 380 NA-TO 1 ND@ . 434 NA-TO 1 ND@ . 488 NA-TO 1 ND@ . 812 NA-TO 1 ND@ . DEPTH . BYE'
 assert run(code)==['0','64','64','66','64','64','0']
 # IRQ is on fetch, status read only acknowledges frameIRQ,4015write acknowledgesDMC.
 code='143 16400 0 NA-WRITE 16 16405 0 NA-WRITE 1 NA-STATUS . NA-IRQ? . 1 NA-STATUS . 0 16405 1 NA-WRITE 1 NA-STATUS . DEPTH . BYE'
 assert run(code)==['128','-1','128','0','0']
 assert run('143 16400 0 NA-WRITE 16 16405 0 NA-WRITE 0 NA-STATUS . 1 NA-STATUS . DEPTH . BYE')==['16','128','0']
 # +/-2 steps preserve parity at boundaries rather than clipping126->127 or1->0.
 code='0 12 ND! 1 10 ND! 126 1 ND! NA-DMC-OUTPUT 1 ND@ . 1 10 ND! 125 1 ND! NA-DMC-OUTPUT 1 ND@ . 0 10 ND! 1 1 ND! NA-DMC-OUTPUT 1 ND@ . 0 10 ND! 2 1 ND! NA-DMC-OUTPUT 1 ND@ . DEPTH . BYE'
 assert run(code)==['126','127','1','0','0']
 assert run('15 16400 0 NA-WRITE 0 16400 3 NA-WRITE 5 ND@ . 4 ND@ . 55 NA-TO 5 ND@ . 56 NA-TO 5 ND@ . DEPTH . BYE')==['26','213','0','213','0']
 assert run('15 16400 0 NA-WRITE 255 16402 0 NA-WRITE 4 16403 0 NA-WRITE 16 16405 0 NA-WRITE 27596 NA-TO 6 ND@ . 7 ND@ . 27597 NA-TO 6 ND@ . 7 ND@ . DEPTH . BYE')==['32768','1','32769','0','0']
 assert run('2 16403 0 NA-WRITE 16 16405 0 NA-WRITE 3 NA-TO 7 ND@ . 6 ND@ . 16 16405 3 NA-WRITE 7 ND@ . 6 ND@ . DEPTH . BYE')==['32','49153','32','49153','0']
 report['tests'].append({'case':'hand-delta-parity-eight-silent-clocks-irq-ack'})
 assert run('85 49152 NA-MEM! NA-RESET NA-DMC-MEMORY 16384 + C@ . 255 16401 0 NA-WRITE 1 ND@ . 0 16405 0 NA-WRITE 1 ND@ . DEPTH . BYE')==['85','127','127','0']
 report['tests'].append({'case':'reset-keeps-sample-memory-direct-dac-persists-disabled'})
 # All LUT entries, including wide intermediate products, against Python arbitrary integers.
 code=': TABLES 31 0 DO NA-PULSE-MIX I CELLS + @ . LOOP 32768 0 DO NA-TND-MIX I CELLS + @ . LOOP ; TABLES BYE'
 got=list(map(int,run(code)));expected=[9588*i*32767//(100*(8128+100*i)) for i in range(31)]
 for index in range(32768):
  t,n,d=index//2048,(index//128)&15,index&127;s=t*12241*22638+n*8227*22638+d*8227*12241
  expected.append(15979*s*32767//(100*(8227*12241*22638+100*s)))
 assert got==expected
 report['tests'].append({'case':'all32799-wide-rational-mixer-entries','sha256':hashlib.sha256(b''.join(struct.pack('<q',x) for x in got)).hexdigest(),'pulse_max':max(got[:31]),'tnd_max':max(got[31:]),'maximum_sum':max(got[:31])+max(got[31:])})
 # Invalid memory writes preserve every mapped byte and model state.
 with tempfile.TemporaryDirectory(prefix='memory-',dir=W) as d:
  out=Path(d)/'memory.bin';body=DATA+apu.DUMP+'SNAP '
  bad=[(-1,0x8000),(256,0x8000),(1,0x7fff),(1,0x10000)]
  for i,(v,a) in enumerate(bad):body+=f": BAD{i} {v} {a} NA-MEM! ; ['] BAD{i} CATCH . "
  body+=f' SNAP S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD NA-DMC-MEMORY 32768 FD WRITE-FILE THROW FD CLOSE-FILE THROW DEPTH . BYE'
  q=run(body);assert q[:74]==q[78:152] and q[74:78]==['-24']*4 and q[152:]==['0'];assert out.read_bytes()==MEMORY
 report['tests'].append({'case':'mapped-memory-validation-atomic-full-byte-comparison'})
 # Multiple voices, DMC loop/wrap and queued register writes spanning rendering boundaries.
 events=apu.DEMO+dmc(start=255,length=4,flags=192)+[(37,1,0x4010),(511,31,0x4015),(512,64,0x4011),(513,15,0x4010),(7001,15,0x4015),(7002,31,0x4015),(20000,128,0x4017),(25000,0,0x4010)]
 with tempfile.TemporaryDirectory(prefix='vectors-',dir=W) as d:
  out=Path(d)/'pcm.bin';m=apu.Model(events,MEMORY);expected=m.render(2048)
  for slow,split in [(False,False),(True,False),(False,True)]:
   render='OUT 2048 NA-RENDER' if not split else 'OUT 1 NA-RENDER OUT 2 + 511 NA-RENDER OUT 1024 + 1536 NA-RENDER'
   code=DATA+apu.DUMP+queue(events)+('TRUE NA-SLOW ! ' if slow else '')+'CREATE OUT 4096 ALLOT '+render+f' S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 4096 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP DEPTH . BYE'
   assert list(map(int,run(code)))==m.snapshot()+[0];assert out.read_bytes()==expected,(slow,split)
 report['tests'].append({'case':'five-voice-pcm-fast-reference-split-python','frames':2048,'sha256':hashlib.sha256(expected).hexdigest()})
 # Streaming8kHz direct DAC: refill bounded queue between512sample render blocks.
 dac_intro='VARIABLE DM-DAC-INDEX VARIABLE DM-END : DM-QUEUE-DAC NA-CYCLE @ NA-FRACTION @ 512 NA-CPU * + NA-RATE / + DM-END ! BEGIN DM-DAC-INDEX @ NA-CPU * 8000 / DM-END @ <= WHILE DM-DAC-INDEX @ 7 * 127 AND 16401 DM-DAC-INDEX @ NA-CPU * 8000 / NA-EVENT! 1 DM-DAC-INDEX +! REPEAT ; '
 base=apu.DEMO+dmc(flags=192,length=4)
 with tempfile.TemporaryDirectory(prefix='dac-stream-',dir=W) as d:
  out=Path(d)/'dac.bin';count=8192;end=count*apu.CPU//apu.RATE
  active=base+[(i*apu.CPU//8000,(i*7)&127,0x4011) for i in range(1,end*8000//apu.CPU+1)]
  m=apu.Model(active,MEMORY);expected=m.render(count)
  code=DATA+dac_intro+queue(base)+'0 NA-RUN 1 DM-DAC-INDEX ! CREATE OUT 16384 ALLOT : RENDER-DAC 16 0 DO DM-QUEUE-DAC OUT I 1024 * + 512 NA-RENDER LOOP ; RENDER-DAC '+f' S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 16384 FD WRITE-FILE THROW FD CLOSE-FILE THROW 1 ND@ . NA-CYCLE @ . DM-DAC-INDEX @ . DEPTH . BYE'
  q=list(map(int,run(code)));assert q==[m.nd[1],end,len(active)-len(base)+1,0],q;assert out.read_bytes()==expected
 report['tests'].append({'case':'streaming8khz-dac-reclaims-queue-and-matches-python','frames':count,'dac_writes':len(active)-len(base),'sha256':hashlib.sha256(expected).hexdigest()})
 start=time.perf_counter_ns();code=DATA+'NA-DEMO-SETUP 207 16400 0 NA-WRITE 64 16401 0 NA-WRITE 4 16403 0 NA-WRITE 31 16405 0 NA-WRITE 16 FALSE NA-STREAM PS-FRAMES @ . PS-HANDLE @ . AUDIO? . DEPTH . BYE'
 q=list(map(int,run(code,'tests/audio/nes-apu-play.fs')));assert q[0:2]==[8192,0] and q[2] in [0,-1] and q[3]==0,q
 report['silent_pcm']={'source':code,'whole_process_monotonic_ns':time.perf_counter_ns()-start,'frames':q[0],'audio_available':q[2],'scope':'One ownedprocess; fivevoice synth then zero data to PCM; no audible generated waveform submitted.'}
 if args.benchmark:
  setup_events=apu.DEMO+dmc(flags=192,start=255,length=4)
  for i in range(128):
   at=101+i*9001;a=[0x4002,0x4006,0x400a,0x400e,0x4011,0x4010][i%6]
   v=(128+i%80) if a in [0x4002,0x4006,0x400a] else ((i%12+3)|(i&1)<<7) if a==0x400e else (i*7)&127 if a==0x4011 else 192|i%16
   setup_events.append((at,v,a))
  stress_events=[(at,(v&128) if a==0x400e else 207 if a==0x4010 else v,a) for at,v,a in setup_events]+[(0,0,0x400e)]
  stress_events.sort(key=lambda e:e[0])
  intro='CREATE OUT 1024 ALLOT 2VARIABLE T0 2VARIABLE T1 2VARIABLE U0 2VARIABLE U1 : CPU-ALL CPUTIME D+ ; : DM-BENCH 64 0 DO OUT 512 NA-RENDER LOOP ; : SUM-OUT 0 1024 0 DO OUT I + C@ + LOOP ; '
  results={}
  for mode in ['fast','reference','fast_max_noise_dmc','fast_dac_8khz']:
   active=stress_events if mode=='fast_max_noise_dmc' else setup_events
   if mode=='fast_dac_8khz':
    end=32768*apu.CPU//apu.RATE
    active=base+[(i*apu.CPU//8000,(i*7)&127,0x4011) for i in range(1,end*8000//apu.CPU+1)]
   m=apu.Model(active,MEMORY);expected=m.render(32768);checksum=sum(expected[-1024:]);final_cycle=m.cycle
   setup='NA-RESET '+queue(active)+('TRUE NA-SLOW ! ' if mode=='reference' else '')+'0 NA-RUN '
   code=DATA+intro+setup+' DM-BENCH '+setup+' CPU-ALL U0 2! NTIME T0 2! DM-BENCH NTIME T0 2@ D- T1 2! CPU-ALL U0 2@ D- U1 2! T1 2@ D. U1 2@ D. SUM-OUT . NA-CYCLE @ . DEPTH . BYE'
   if mode=='fast_dac_8khz':
    intro_dac=intro.replace('OUT 512 NA-RENDER','DM-QUEUE-DAC OUT 512 NA-RENDER')
    setup='NA-RESET '+queue(base)+'0 NA-RUN 1 DM-DAC-INDEX ! '
    code=DATA+dac_intro+intro_dac+setup+' DM-BENCH '+setup+' CPU-ALL U0 2! NTIME T0 2! DM-BENCH NTIME T0 2@ D- T1 2! CPU-ALL U0 2@ D- U1 2! T1 2@ D. U1 2@ D. SUM-OUT . NA-CYCLE @ . DEPTH . BYE'
   wall=[];cpu=[]
   for _ in range(7):
    q=list(map(int,run(code)));assert q[0]>0 and q[1]>=0 and q[2:]==[checksum,final_cycle,0],q;wall.append(q[0]);cpu.append(q[1])
   median=statistics.median(wall);results[mode]={'source':code,'frames':32768,'cpu_cycles':final_cycle,'wall_nanoseconds':wall,'process_cpu_microseconds':cpu,'last_buffer_byte_sum':checksum,'median_ns_per_frame':median/32768,'median_realtime_ratio':32768*1e9/(median*48000),'median_ns_per_cpu_cycle':median/final_cycle,'scheduled_writes_after_setup':len(active)-len(base) if mode=='fast_dac_8khz' else 128}
  report['benchmark']={'scope':'APU modelonly;5voices includingDMCmemory/IRQ/loop,DAC and128timedwrites. NoDMAstalls,emulatedCPU/PPU/device/filter.7newprocesses withwarmup/reset/memoryload/queuedcycle0setup outside timedregion;fast_dac_8khz includesstreaming enqueue/compaction inside timedregion. NTIMEwallcanjump; CPUrawretained.','events':setup_events,'stress_events':stress_events,'results':results}
 print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
