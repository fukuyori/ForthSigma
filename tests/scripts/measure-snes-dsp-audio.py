#!/usr/bin/env python3
"""S-DSP six workloads. Default is untimed validation; --measure needs user start approval."""
import argparse,hashlib,importlib.util,json,platform,statistics,struct,subprocess,tempfile
from pathlib import Path
if not __debug__:raise SystemExit('Run without -O; verification assertions are required.')
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('sd_oracle',ROOT/'tests/scripts/verify-snes-dsp-audio.py');oracle=importlib.util.module_from_spec(spec);spec.loader.exec_module(oracle)
FRAMES=16384

def workloads():
    one=oracle.Model();one.putword(256,512);one.putword(258,512);one.ram[512:521]=bytes([195,2,70,118,66,14,172,154,206])
    for r,v in [(93,1),(108,32),(12,64),(28,64),(0,80),(1,80),(2,133),(3,3),(7,64),(76,1)]:one.store(v,r)
    eight=oracle.demo()
    for r,v in [(108,32),(44,0),(60,0),(77,0)]:eight.store(v,r)
    maximum=oracle.demo()
    for r,v in [(108,32),(44,0),(60,0),(77,0),(45,255)]:maximum.store(v,r)
    maximum.ram[512]=207
    for i in range(8):maximum.store(255,i*16+2);maximum.store(255,i*16+3)
    env=oracle.demo()
    for r,v in [(108,63),(61,170),(44,0),(60,0),(77,0)]:env.store(v,r)
    for i in range(8):env.store(143|(i%8<<4),i*16+5);env.store((i%8<<5)|19,i*16+6)
    echo=oracle.demo()
    for i,v in enumerate([-4,8,16,32,32,16,8,-4]):echo.store(v%256,i*16+15)
    echo.store(96,13)
    dense=oracle.demo()
    for r,v in [(108,32),(44,0),(60,0),(77,0)]:dense.store(v,r)
    return {'one_voice':(one,False),'eight_voices':(eight,False),'brr_filter3_pitchmax':(maximum,False),'adsr_shared_noise':(env,False),'echo_fir8':(echo,False),'dense_8khz_reg_ram':(dense,True)}

def source_for(model,dense):
    setup=': SETUP SD-RESET\n'+''.join(f'{v} {r} 0 SD-REG!\n' for r,v in enumerate(model.r))+''.join(f'{v} {r} 0 SD-RAM!\n' for r,v in enumerate(model.ram) if v)+' ;\n'
    if dense:
        work=': WORK 4096 0 DO I 37 * 255 AND 2 I 128 * 1+ SD-REG-EVENT! I 13 * 255 AND 513 I 7 AND + I 128 * 1+ SD-RAM-EVENT! OUT I 16 * + 4 SD-RENDER LOOP ;\n'
        count=index=0
        for _ in range(FRAMES//4):
            for _ in range(2):
                if count>=1024:count-=index;index=0
                count+=1
            index=count
    else:work=': WORK OUT 16384 SD-RENDER ;\n';count=0
    return 'CREATE OUT 65536 ALLOT\n'+setup+work+'2VARIABLE W0 2VARIABLE W1 2VARIABLE U0 2VARIABLE U1\n: CPU-ALL CPUTIME D+ ;\n: SUM 0 65536 0 DO OUT I + C@ + LOOP ;\n',count

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);p.add_argument('--measure',action='store_true');p.add_argument('--native',action='store_true');a=p.parse_args();binary=a.sigma.resolve();folder=ROOT/'.work/1175-1176';folder.mkdir(parents=True,exist_ok=True);cases={}
    for name,(m,dense) in workloads().items():
        source,count=source_for(m,dense);initial=m.state();initial_ram=bytes(m.ram)
        if dense:
            for i in range(FRAMES//4):
                m.enqueue(i*37%256,2,i*128+1);m.enqueue(i*13%256,128+513+i%8,i*128+1)
        pcm=m.render(FRAMES);assert any(pcm),name
        cases[name]={'source':source,'count':count,'initial':initial,'initial_ram':initial_ram,'model':m,'pcm':pcm,'wall':[],'cpu':[],'pre':[],'post':[],'events':FRAMES//4*2 if dense else 0}
    report={'platform':platform.platform(),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'timing_enabled':a.measure,'backend':'native' if a.native else 'forth','scope':'Declared S-DSP core only, not SPC700/ROM/device. Six16384frame stereo loads. Default no NTIME/CPUTIME calls. --measure7 fresh processes per load with rotated order; warmup/reset/fullARAM reset/A5/pre-state outside timing. Every fullPCM/266semantic state/queue2/fullARAM checked outside timing. Dense8kHz2events includes reg/ownedRAM byte enqueue and compaction checks; no pending entries moved. Wall primary may jump, CPUTIME reference may be quantized and2 calls included in wall. Linux is WSL2.','round_order':[],'round_timing_flags':[],'workloads':{}}
    with tempfile.TemporaryDirectory(dir=folder,prefix='sd-bench-') as tmp:
        names=list(cases)
        for sample in range(8 if a.measure else 1):
            order=names[sample%6:]+names[:sample%6];report['round_order'].append(order);report['round_timing_flags'].append(sample>0)
            for name in order:
                c=cases[name];m=c['model'];pcm=Path(tmp)/'out.bin';ram=Path(tmp)/'ram.bin';pre_ram=Path(tmp)/'pre-ram.bin';file=Path(tmp)/'run.fs';timed=sample>0
                text=oracle.DUMP+c['source']+('SETUP WORK SETUP\n' if timed else 'SETUP\n')+'OUT 65536 165 FILL OUT C@ . OUT 65535 + C@ . SNAP STDOUT FLUSH-FILE THROW\n'
                text+=f'S" {pre_ram.as_posix()}" W/O CREATE-FILE THROW CONSTANT PF SD-ARAM 65536 PF WRITE-FILE THROW PF CLOSE-FILE THROW\n'
                text+=('NTIME W0 2! CPU-ALL U0 2! WORK CPU-ALL U1 2! NTIME W1 2! W1 2@ W0 2@ D- D. U1 2@ U0 2@ D- D.\n' if timed else 'WORK 0 . 0 .\n')
                text+=f'SUM . SNAP S" {pcm.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 65536 FD WRITE-FILE THROW FD CLOSE-FILE THROW S" {ram.as_posix()}" W/O CREATE-FILE THROW CONSTANT RF SD-ARAM 65536 RF WRITE-FILE THROW RF CLOSE-FILE THROW DEPTH . BYE\n'
                file.write_text(text,encoding='utf-8',newline='\n');pcm.unlink(missing_ok=True);ram.unlink(missing_ok=True);pre_ram.unlink(missing_ok=True)
                r=subprocess.run([str(binary),'examples/snes-dsp-audio-native-demo.fs' if a.native else 'examples/snes-dsp-audio-demo.fs',str(file)],cwd=ROOT,input=b'',capture_output=True,timeout=120)
                assert r.returncode==0 and not r.stderr,(name,r.returncode,r.stdout[:1000],r.stderr)
                v=list(map(int,r.stdout.split()));assert len(v)==542 and v[-1]==0,(name,len(v),v[-4:])
                assert v[:2]==[165,165] and v[2:268]==c['initial'] and v[268:270]==[0,0],(name,'pre-state')
                assert pre_ram.read_bytes()==c['initial_ram'],(name,'pre-ARAM')
                assert pcm.read_bytes()==c['pcm'] and ram.read_bytes()==m.ram and v[272]==sum(c['pcm']),(name,'fullPCM/ARAM')
                assert v[273:539]==m.state() and v[539:541]==[c['count']]*2,(name,'post-state')
                if timed:
                    assert v[270]>0 and v[271]>=0;c['wall'].append(v[270]);c['cpu'].append(v[271]);c['pre'].append(v[2:270]);c['post'].append(v[273:541])
                c['last_source']=text
    for name,c in cases.items():
        w=c['wall'];report['workloads'][name]={'frames':FRAMES,'events':c['events'],'all_full_pcm_state_aram_checks_passed':True,'all_pre_aram_reset_checked':True,'initial_aram_sha256':hashlib.sha256(c['initial_ram']).hexdigest(),'pcm_sha256':hashlib.sha256(c['pcm']).hexdigest(),'aram_sha256':hashlib.sha256(c['model'].ram).hexdigest(),'nonzero_channel_samples':sum(x!=0 for x in struct.unpack('<32768h',c['pcm'])),'final_semantic_state':c['model'].state(),'final_queue_count_and_index':[c['count']]*2,'wall_nanoseconds':w,'process_cpu_microseconds':c['cpu'],'timed_pre_states':c['pre'],'timed_post_states':c['post'],'median_ns_per_frame':statistics.median(w)/FRAMES if w else None,'median_realtime_ratio':FRAMES/32000*1e9/statistics.median(w) if w else None,'forth_source':c['last_source']}
    files=['tests/scripts/measure-snes-dsp-audio.py','tests/scripts/verify-snes-dsp-audio.py','include/snes-dsp-audio.fs','include/snes-gauss.fs','scripts/snes-gauss-data.json']
    if a.native:files+=['src/core/sound_snes_dsp.zig','src/core/words_snes_dsp.zig','src/core/snes_gauss.zig','include/snes-dsp-native-backend.fs','include/snes-dsp-audio-native.fs','examples/snes-dsp-audio-native-play.fs']
    report['source_sha256_lf']={f:hashlib.sha256((ROOT/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in files}
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
