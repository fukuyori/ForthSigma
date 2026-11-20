#!/usr/bin/env python3
"""Independent PCM synth vectors and synthesis-only timing; integration submits silence."""
import argparse,hashlib,json,platform,statistics,struct,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
TURN=1<<24

def oracle(settings,count,events=None):
    phase=[0]*4;noise=[1]*4;result=bytearray();settings=[list(x) for x in settings]
    for sample in range(count):
        for voice,reg,value in (events or {}).get(sample,[]):settings[voice][reg]=value
        total=0
        for voice,(kind,hz,gain,duty) in enumerate(settings):
            value=phase[voice]+hz*TURN//48000
            if value>=TURN:noise[voice]=(noise[voice]>>1)|(((noise[voice]^(noise[voice]>>1))&1)<<15)
            phase[voice]=value&(TURN-1)
            if kind==1:total+=gain if phase[voice]<duty*65536 else -gain
            elif kind==2:
                x=phase[voice]>>14
                total+=((x*128-32768) if x<512 else (98304-x*128))*gain//32768
            elif kind==3:total+=gain if noise[voice]&1 else -gain
        result+=struct.pack('<h',total)
    return bytes(result)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);p.add_argument('--benchmark',action='store_true');args=p.parse_args();binary=args.sigma.resolve()
    report={'platform':platform.platform(),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'source_sha256_lf':{f:hashlib.sha256((ROOT/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in ['examples/pcm-synth.fs','examples/pcm-synth-play.fs',str(Path(__file__).resolve().relative_to(ROOT)).replace('\\','/')]},'tests':[]}
    def run(code,source='examples/pcm-synth.fs'):
        r=subprocess.run([str(binary),source,'-e',code],cwd=ROOT,input=b'',capture_output=True,timeout=30)
        assert r.returncode==0 and not r.stderr,(r.returncode,r.stdout,r.stderr)
        return r.stdout.decode()
    def setup(settings):return 'PS-RESET '+' '.join(f'{value} {voice} {reg} PS-REG!' for voice,fields in enumerate(settings) for reg,value in enumerate(fields))
    assert run('CREATE X 4 ALLOT -32768 X PS-LE! 32767 X 2 + PS-LE! X C@ . X 1+ C@ . X 2 + C@ . X 3 + C@ . BYE').split()==['0','128','255','127']
    assert run(": BAD 0 -1 PS-RENDER ; ['] BAD CATCH . 0 0 PS-RENDER DEPTH . BYE").split()==['-24','0']
    report['tests'].append({'case':'signed16-little-endian-extremes-and-render-count-validation'})
    # Hand-calculated quarter-turn samples: advance before output, independent of oracle.
    assert run('1 0 0 PS-REG! 12000 0 1 PS-REG! 100 0 2 PS-REG! PS-SAMPLE . PS-SAMPLE . PS-SAMPLE . PS-SAMPLE . BYE').split()==['100','-100','-100','100']
    assert run('2 0 0 PS-REG! 12000 0 1 PS-REG! 8191 0 2 PS-REG! PS-SAMPLE . PS-SAMPLE . PS-SAMPLE . PS-SAMPLE . BYE').split()==['0','8191','0','-8191']
    assert run('3 0 0 PS-REG! 12000 0 1 PS-REG! 100 0 2 PS-REG! PS-SAMPLE . PS-SAMPLE . PS-SAMPLE . PS-SAMPLE . BYE').split()==['100','100','100','-100']
    report['tests'].append({'case':'hand-calculated-quarter-turn-pulse-triangle-noise'})
    configs=[[[0,0,0,128]]*4,[[1,440,8191,1],[1,23999,8191,255],[2,110,8191,128],[3,3000,8191,128]],[[1,0,8191,128],[2,0,8191,128],[3,23999,8191,128],[0,200,0,128]]]
    work=ROOT/'.work/999';work.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='vectors-',dir=work) as d:
        path=Path(d)/'samples.bin';quoted=path.as_posix()
        for index,settings in enumerate(configs):
            count=8193
            for split in [False,True]:
                render='OUT 8193 PS-RENDER' if not split else 'OUT 1 PS-RENDER OUT 2 + 511 PS-RENDER OUT 1024 + 7681 PS-RENDER'
                code=setup(settings)+f' CREATE OUT {count*2} ALLOT '+render+f' S" {quoted}" W/O CREATE-FILE THROW CONSTANT FD OUT {count*2} FD WRITE-FILE THROW FD CLOSE-FILE THROW DEPTH . BYE'
                assert run(code).strip()=='0'
                actual=path.read_bytes();expected=oracle(settings,count);assert actual==expected,(index,split,next((i for i,(a,b) in enumerate(zip(actual,expected)) if a!=b),None))
                report['tests'].append({'case':f'vector-{index}-split-{split}','bytes':len(actual),'sha256':hashlib.sha256(actual).hexdigest()})
        # Mid-block register changes preserve phase/noise state; Hz and gain updates are not resets.
        settings=configs[1];events={4096:[(0,1,777),(2,2,17),(3,0,0)]};count=8193
        code=setup(settings)+f' CREATE OUT {count*2} ALLOT OUT 4096 PS-RENDER 777 0 1 PS-REG! 17 2 2 PS-REG! 0 3 0 PS-REG! OUT 8192 + 4097 PS-RENDER S" {quoted}" W/O CREATE-FILE THROW CONSTANT FD OUT {count*2} FD WRITE-FILE THROW FD CLOSE-FILE THROW DEPTH . BYE'
        assert run(code).strip()=='0';actual=path.read_bytes();assert actual==oracle(settings,count,events)
        report['tests'].append({'case':'register-change-continuity','bytes':len(actual),'sha256':hashlib.sha256(actual).hexdigest()})
    # Snapshot every register/state cell and both neighboring cells of each array.
    # This detects rejected out-of-range writes even when the next sample sounds identical.
    bad=[(-1,0,0),(4,0,0),(-1,0,1),(24000,0,1),(-1,0,2),(8192,0,2),(0,0,3),(256,0,3),(1,-1,0),(1,4,0),(1,0,-1),(1,0,4)]
    snapshot=': SNAP-ARRAY 6 0 DO DUP I 1- CELLS + @ . LOOP DROP ; : SNAP '+ ' '.join(name+' SNAP-ARRAY' for name in ['PS-KIND','PS-STEP','PS-GAIN','PS-DUTY','PS-PHASE','PS-NOISE'])+' ; '
    for value,voice,reg in bad:
        code=snapshot+f": BAD {value} {voice} {reg} PS-REG! ; PS-DEMO-SETUP 0 PS-VOICE DROP SNAP ['] BAD CATCH . SNAP DEPTH . BYE"
        result=run(code).split();assert len(result)==74 and result[36]=='-24' and result[-1]=='0',result
        assert result[:36]==result[37:73],(value,voice,reg,result)
    report['tests'].append({'case':'invalid-registers-preserve-all-24-state-cells-and-12-neighbor-cells','count':len(bad)})
    assert run('PS-DEMO-SETUP 32 FALSE PS-STREAM DEPTH . BYE','examples/pcm-synth-play.fs').strip()=='0'
    assert run('0 FALSE PS-STREAM 0 FALSE PS-STREAM DEPTH . BYE','examples/pcm-synth-play.fs').strip()=='0'
    report['tests'].append({'case':'silent-public-stream-32-blocks-and-reopen','frames':16384})
    # Isolated mock callbacks: force partial acceptance, full ring, timeout and cleanup errors.
    # Definitions shadow AUDIO words only inside these disposable processes.
    mock_prefix = """REQUIRE-AUDIO ALSO AUDIO DEFINITIONS
VARIABLE MC-WRITES VARIABLE MC-WAITS VARIABLE MC-CLOSES VARIABLE MC-LEFT
VARIABLE MC-WAIT-FAIL VARIABLE MC-CLOSE-FAIL VARIABLE MC-OPEN-FAIL VARIABLE MC-CLOSE-THROW
CREATE MC-ADDR 64 ALLOT
: PCM-OPEN 2DROP DROP MC-OPEN-FAIL @ IF 0 -528 ELSE 7 0 THEN ;
: PCM-WRITE DROP OVER MC-WRITES @ CELLS MC-ADDR + ! NIP MC-WRITES @ 0= IF 5 MIN ELSE
  MC-WRITES @ 1 = IF DROP 0 THEN THEN
  DUP NEGATE MC-LEFT +! 1 MC-WRITES +! 0 ;
: PCM-WAIT DROP 2DROP 1 MC-WAITS +! MC-WAIT-FAIL @ IF FALSE ELSE TRUE THEN 0 ;
: PCM-STOP DROP 2DROP TRUE 0 ;
: PCM-UNDERRUNS DROP 0 0 ;
: PCM-CLOSE DROP 1 MC-CLOSES +! MC-CLOSE-THROW @ IF -265 THROW THEN MC-CLOSE-FAIL @ ;
"""
    mock_cases=[
      ('partial-full-retry','512 MC-LEFT ! 1 FALSE PS-STREAM MC-LEFT @ . MC-WRITES @ . MC-WAITS @ . MC-CLOSES @ . PS-HANDLE @ . MC-ADDR @ PS-BUFFER - . MC-ADDR CELL+ @ PS-BUFFER - . MC-ADDR 2 CELLS + @ PS-BUFFER - . PS-PARTIAL @ . PS-FULL @ . PS-WRITES @ . PS-WAITS @ . PS-FRAMES @ .','0 3 2 1 0 0 10 10 1 1 3 2 512'),
      ('timeout-cleanup','TRUE MC-WAIT-FAIL ! : GO 1 FALSE PS-STREAM ; [\'] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .','-528 1 0'),
      ('close-retry','-516 MC-CLOSE-FAIL ! : GO 1 FALSE PS-STREAM ; [\'] GO CATCH . PS-HANDLE @ . 0 MC-CLOSE-FAIL ! PS-CLEANUP . PS-HANDLE @ .','-516 7 0 0'),
      ('primary-error-retained','TRUE MC-WAIT-FAIL ! -516 MC-CLOSE-FAIL ! : GO 1 FALSE PS-STREAM ; [\'] GO CATCH . PS-HANDLE @ .','-528 7'),
      ('cleanup-throw-retains-primary',"TRUE MC-WAIT-FAIL ! TRUE MC-CLOSE-THROW ! : GO 1 FALSE PS-STREAM ; ['] GO CATCH . PS-HANDLE @ .",'-528 7'),
      ('cleanup-throw-propagates',"TRUE MC-CLOSE-THROW ! : GO 1 FALSE PS-STREAM ; ['] GO CATCH . PS-HANDLE @ .",'-265 7'),
      ('open-busy-no-close' ,'TRUE MC-OPEN-FAIL ! : GO 1 FALSE PS-STREAM ; [\'] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .','-528 0 0'),
    ]
    with tempfile.TemporaryDirectory(prefix='mock-',dir=work) as d:
        source=Path(d)/'mock.fs'
        source.write_text(mock_prefix+' S" examples/pcm-synth-play.fs" INCLUDED\n',encoding='utf-8')
        for name,code,expected in mock_cases:
            output=run(code+' DEPTH . BYE',source.as_posix())
            clean=' '.join(line for line in output.splitlines() if not line.startswith('WARNING:')).strip()
            assert clean==expected+' 0',(name,output)
            report['tests'].append({'case':name,'output':clean})
    # One paced silent integration run; external monotonic clock covers the whole process.
    import time
    start=time.perf_counter_ns()
    code='PS-DEMO-SETUP 96 FALSE PS-STREAM PS-FRAMES @ . PS-WRITES @ . PS-PARTIAL @ . PS-FULL @ . PS-WAITS @ . PS-UNDERRUN-COUNT @ . AUDIO? . DEPTH . BYE'
    values=list(map(int,run(code,'examples/pcm-synth-play.fs').split()));elapsed=time.perf_counter_ns()-start
    assert len(values)==8 and values[0]==49152 and values[-1]==0,values
    report['paced_silent_integration']={'source':code,'whole_process_monotonic_nanoseconds':elapsed,'frames':values[0],'write_calls':values[1],'partial_writes':values[2],'full_writes':values[3],'wait_calls':values[4],'underrun_episodes':values[5],'audio_available':values[6],'scope':'One process: startup, synthesis, silencing, host open/write/wait/engine drain/close/exit. Not device latency. Backend name and audible output unverified.'}
    if args.benchmark:
        # Fixed-size buffer; no allocation, host, PCM calls or stdout within timed region.
        code="CREATE OUT 1024 ALLOT 2VARIABLE T0 2VARIABLE T1 2VARIABLE U0 2VARIABLE U1 : CPU-ALL CPUTIME D+ ; : MEASURE 1000 0 DO OUT 512 PS-RENDER LOOP ; : SUM-OUT 0 1024 0 DO OUT I + C@ + LOOP ; PS-DEMO-SETUP MEASURE CPU-ALL U0 2! NTIME T0 2! MEASURE NTIME T0 2@ D- T1 2! CPU-ALL U0 2@ D- U1 2! T1 2@ D. U1 2@ D. SUM-OUT . DEPTH . BYE"
        expected_sum=sum(oracle([[1,440,2000,64],[1,660,2000,128],[2,110,2000,128],[3,3000,500,128]],1024000)[-1024:])
        samples=[];cpu=[];discarded=[]
        for attempt in range(10):
            if len(samples)==7:break
            parts=run(code).split();assert len(parts)==4 and parts[2:]==[str(expected_sum),'0'],parts
            wall_ns,cpu_us=map(int,parts[:2])
            if wall_ns<=0 or cpu_us<0:
                discarded.append({'attempt':attempt,'wall_ns':wall_ns,'cpu_us':cpu_us});continue
            samples.append(wall_ns);cpu.append(cpu_us)
        assert len(samples)==7,(samples,discarded)
        frames=512000;median=statistics.median(samples)
        report['benchmark']={'scope':'Synthesis only: Forth dispatch/loop + rendering + s16LE stores; excludes audio thread/device/write/wait/startup. Independent new process each repeat; one warm-up loop; NTIME wall nanoseconds and CPUTIME process CPU microseconds. Wall time can jump; nonpositive wall/negative CPU differences rejected. Synthetic workload, not a chip benchmark.','source':code,'frames_per_repeat':frames,'wall_nanoseconds':samples,'process_cpu_microseconds':cpu,'discarded_samples':discarded,'last_buffer_byte_sum':expected_sum,'median_ns_per_frame':median/frames,'median_realtime_ratio_at_48000':frames*1000000000/(median*48000),'median_realtime_spare_fraction':1-median*48000/(frames*1000000000)}
    print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
