#!/usr/bin/env python3
"""ZX audio workloads. Default verifies only; --measure requires prior user timing approval."""
import argparse, hashlib, importlib.util, json, platform, statistics, struct, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('zx_oracle',ROOT/'tests/scripts/verify-zx-spectrum-audio.py')
oracle=importlib.util.module_from_spec(spec);spec.loader.exec_module(oracle)
FRAMES=32768
REGS=[252,0,227,1,82,2,9,48,12,10,16,100,0,14]

def workloads():
    base=[(0,v,i) for i,v in enumerate(REGS)]
    tone=[(0,252,0),(0,62,7),(0,15,8)]
    end=FRAMES*3546895//48000
    beeper=[(i*4000,16 if i%2==0 else 0,270) for i in range(FRAMES*3500000//48000//4000+1)]
    mix=base+[(i*8000,16 if i%2==0 else 0,270) for i in range(end//8000+1)]
    zero=[(0,15,i) for i in [8,9,10]]+[(0,16,10),(0,14,13)]
    changes=base+[(113+i*16000,v,r) for i in range(128) for v,r in [(i%16,13),(i%32,6),(i*19%256,0)]]
    densebase=tone+[(0,8,65549)]
    dense=densebase+[(i*6*3546895//48000+1,v,t) for i in range(FRAMES//6) for v,t in [(i%16,49165),(i&16,270)]]
    return {'48k_beeper':(0,beeper,None),'128k_tone':(1,tone,None),'128k_mix':(1,sorted(mix),None),'128k_period_zero':(1,zero,None),'128k_changes384':(1,sorted(changes),None),'128k_8khz_bus':(1,dense,densebase)}

def program(mode,events,densebase):
    initial=events if densebase is None else densebase
    setup=f': SETUP {mode} ZX-MODEL! ZX-RESET '+oracle.queue(initial)+' ;\n'
    count=len(initial);index=0
    if densebase is not None:
        work=': WORK 5461 0 DO I 15 AND 49149 I 6 * ZX-CPU @ * ZX-RATE / 1+ ZX-OUT-EVENT! I 16 AND 254 I 6 * ZX-CPU @ * ZX-RATE / 1+ ZX-OUT-EVENT! OUT I 12 * + 6 ZX-RENDER LOOP OUT 65532 + 2 ZX-RENDER ;\n'
        for _ in range(FRAMES//6):
            for _ in range(2):
                if count>=1024:count-=index;index=0
                count+=1
            index=count
    else:work=': WORK OUT 32768 ZX-RENDER ;\n'
    return 'CREATE OUT 65536 ALLOT\n'+setup+work+'2VARIABLE W0 2VARIABLE W1 2VARIABLE U0 2VARIABLE U1\n: CPU-ALL CPUTIME D+ ;\n: SUM 0 65536 0 DO OUT I + C@ + LOOP ;\n',len(initial),count

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);p.add_argument('--measure',action='store_true');a=p.parse_args();binary=a.sigma.resolve()
    folder=ROOT/'.work/1170-1171';folder.mkdir(parents=True,exist_ok=True)
    cases={}
    for name,(mode,events,dense) in workloads().items():
        m=oracle.Model(mode);pcm=m.render(FRAMES,events);source,initial,final=program(mode,events,dense)
        assert any(pcm),name
        cases[name]={'model':m,'pcm':pcm,'source':source,'initial':initial,'final':final,'events':events,'wall':[],'cpu':[],'pre_states':[],'post_states':[],'mode':mode}
    report={'platform':platform.platform(),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'timing_enabled':a.measure,'scope':'Declared audio model only, no CPU emulator or device. WSL is not physical Linux. Full PCM,39 semantic states and 2 queue counters checked. Dense bus calculations/enqueues/compaction checks included (no pending entries moved) in measured work; setup/warmup/reset/poison and validation excluded. Wall primary; CPU reference may be quantized.','workloads':{},'round_order':[]}
    with tempfile.TemporaryDirectory(prefix='zx-bench-',dir=folder) as tmp:
        names=list(cases)
        for round in range(8 if a.measure else 1):
            order=names[round%6:]+names[:round%6];report['round_order'].append(order)
            for name in order:
                c=cases[name];m=c['model'];pcm=Path(tmp)/'pcm.bin';file=Path(tmp)/'run.fs';timed=round>0
                source=oracle.DUMP+c['source']+('SETUP WORK SETUP\n' if timed else 'SETUP\n')+'OUT 65536 165 FILL OUT C@ . OUT 65535 + C@ . SNAP STDOUT FLUSH-FILE THROW\n'
                source+=('NTIME W0 2! CPU-ALL U0 2! WORK CPU-ALL U1 2! NTIME W1 2! W1 2@ W0 2@ D- D. U1 2@ U0 2@ D- D.\n' if timed else 'WORK 0 . 0 .\n')
                source+=f'SUM . SNAP S" {pcm.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 65536 FD WRITE-FILE THROW FD CLOSE-FILE THROW DEPTH . BYE\n'
                file.write_text(source,encoding='utf-8',newline='\n')
                pcm.unlink(missing_ok=True)
                r=subprocess.run([str(binary),'tests/audio/zx-spectrum-audio-demo.fs',str(file)],cwd=ROOT,input=b'',capture_output=True,timeout=60)
                assert r.returncode==0 and not r.stderr,(name,r.returncode,r.stdout[:1000],r.stderr)
                v=list(map(int,r.stdout.split()));assert len(v)==88 and v[-1]==0,(name,v)
                assert v[:2]==[165,165] and v[2:41]==oracle.Model(c['mode']).state() and v[41:43]==[c['initial'],0],(name,'pre-state')
                assert pcm.read_bytes()==c['pcm'] and v[45]==sum(c['pcm']),(name,'PCM')
                assert v[46:85]==m.state() and v[85:87]==[c['final']]*2,(name,'post-state',v[46:87],m.state(),c['final'])
                if timed:
                    assert v[43]>0 and v[44]>=0;c['wall'].append(v[43]);c['cpu'].append(v[44]);c['pre_states'].append(v[2:43]);c['post_states'].append(v[46:87])
                c['last_source']=source
    for name,c in cases.items():
        w=c['wall'];report['workloads'][name]={'frames':FRAMES,'events':len(c['events']),'all_full_pcm_and_state_checks_passed':True,'pcm_sha256':hashlib.sha256(c['pcm']).hexdigest(),'nonzero_samples':sum(x!=0 for x in struct.unpack('<32768h',c['pcm'])),'final_semantic_state':c['model'].state(),'final_queue_count_and_index':[c['final']]*2,'wall_nanoseconds':w,'process_cpu_microseconds':c['cpu'],'timed_pre_states':c['pre_states'],'timed_post_states':c['post_states'],'median_ns_per_frame':statistics.median(w)/FRAMES if w else None,'median_realtime_ratio':FRAMES/48000*1e9/statistics.median(w) if w else None,'forth_source':c['last_source']}
    files=['tests/scripts/measure-zx-spectrum-audio.py','tests/scripts/verify-zx-spectrum-audio.py','include/zx-spectrum-audio.fs','include/zx-ay-levels.fs']
    report['source_sha256_lf']={f:hashlib.sha256((ROOT/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in files}
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
