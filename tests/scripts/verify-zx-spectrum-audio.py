#!/usr/bin/env python3
"""Independent CPU-tick/16-level AY oracle and exhaustive ZX audio port checks; no audio."""
import argparse, hashlib, json, math, platform, struct, subprocess, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
LEVELS = [0] + [math.floor(32767 * 10 ** (3 * (i - 15) / 20)) for i in range(1, 16)]
MASKS = [255,15,255,15,255,15,31,255,31,31,31,255,255,15,255]
VARS = ['MODEL','CPU','ULA','PINS','NOISE-COUNT','NOISE-HALF','LFSR','ENV-COUNT','ENV-STEP','ENV-ATTACK','ENV-HOLD','ENV-ALTERNATE','ENV-HOLDING','CYCLE','DIV','FRACTION','SELECT','EVENT-COUNT','EVENT-INDEX']
DUMP = ': SNAP 16 0 DO I ZX-R@ . LOOP 3 0 DO ZX-TONE-COUNT I CELLS + @ . LOOP 3 0 DO ZX-TONE-HIGH I CELLS + @ . LOOP '+' '.join('ZX-'+v+' @ .' for v in VARS)+' ;\n'


class Model:
    def __init__(self, mode):
        self.mode=mode; self.cpu=3546895 if mode else 3500000
        self.r=[0]*16; self.tc=[0]*3; self.th=[False]*3
        self.ula=0; self.pins=255; self.nc=self.nh=0; self.lfsr=1
        self.ec=0; self.half=0; self.level=15; self.attack=0
        self.hold=True; self.alt=False; self.held=True; self.reset_env=True
        self.t=self.div=self.frac=self.select=0

    def step(self):
        for i in range(3):
            self.tc[i]+=1
            if self.tc[i]>=max(1,self.r[i*2]+256*self.r[i*2+1]): self.tc[i]=0; self.th[i]=not self.th[i]
        self.nh=1-self.nh
        if self.nh:
            self.nc+=1
            if self.nc>=max(1,self.r[6]):
                self.nc=0; self.lfsr=(self.lfsr//2)|(((self.lfsr^(self.lfsr//8))&1)<<16)
        if not self.held:
            self.ec+=1
            if self.ec>=max(1,self.r[11]+256*self.r[12]):
                self.ec=0; self.half=1-self.half
                if self.half==0:
                    if self.level: self.level-=1
                    else:
                        if self.alt: self.attack=15-self.attack
                        if self.hold: self.held=True
                        else: self.level=15

    def advance(self, tick):
        assert tick>=self.t
        while self.t<tick and self.mode:
            self.t+=1; self.div+=1
            if self.div==16: self.div=0; self.step()
        self.t=tick

    def reg(self, reg, value):
        self.r[reg]=value&MASKS[reg]
        if reg==13:
            shape=self.r[13]; self.attack=15 if shape&4 else 0
            self.hold=bool(shape&1) if shape&8 else True
            self.alt=bool(shape&2) if shape&8 else bool(self.attack)
            self.level=15; self.half=self.ec=0; self.held=self.reset_env=False

    def store(self, value, target):
        if target<15: self.reg(target,value)
        elif target==15: self.pins=value
        else:
            port=target-16
            if port%2==0: self.ula=value
            if self.mode and port//32768 and not(port//2%2):
                if port//16384%2: self.select=value
                elif self.select<15: self.reg(self.select,value)

    def sample(self):
        result=4096 if self.ula&16 else 0
        if self.mode:
            channels=[]
            for i in range(3):
                gate=(self.th[i] or bool(self.r[7]&(1<<i))) and (bool(self.lfsr&1) or bool(self.r[7]&(8<<i)))
                level=(self.level^self.attack) if self.r[8+i]&16 else self.r[8+i]&15
                channels.append(LEVELS[level] if gate else 0)
            result+=sum(channels)//6
        return result

    def render(self, frames, events):
        pending=list(events); index=0; out=bytearray()
        for _ in range(frames):
            advance,self.frac=divmod(self.frac+self.cpu,48000); end=self.t+advance
            while index<len(pending) and pending[index][0]<=end:
                tick,value,target=pending[index]; self.advance(tick); self.store(value,target); index+=1
            self.advance(end); out.extend(struct.pack('<h',self.sample()))
        return bytes(out)

    def state(self):
        step=31 if self.reset_env else 0 if self.held else self.level*2+1-self.half
        return self.r+self.tc+[-int(v) for v in self.th]+[self.mode,self.cpu,self.ula,self.pins,self.nc,self.nh,self.lfsr,self.ec,step,31 if self.attack else 0,-int(self.hold),-int(self.alt),-int(self.held),self.t,self.div,self.frac,self.select]


def queue(events):
    return '\n'.join(f'{value} {target-16} {tick} ZX-OUT-EVENT!' if target>=16 else f'{value} {tick} ZX-INPUT-EVENT!' if target==15 else f'{value} {target} {tick} ZX-AY-EVENT!' for tick,value,target in events)+'\n'


def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('sigma',type=Path); args=p.parse_args()
    binary=args.sigma.resolve(); work=ROOT/'.work/1169'; work.mkdir(parents=True,exist_ok=True); tests=[]
    def run(code):
        with tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.fs',dir=work,delete=False) as f:
            file=Path(f.name); f.write(DUMP+code+'\nDEPTH . BYE\n')
        try: r=subprocess.run([str(binary),'tests/audio/zx-spectrum-audio-demo.fs',str(file)],cwd=ROOT,input=b'',capture_output=True,timeout=60)
        finally: file.unlink()
        assert r.returncode==0 and not r.stderr,(r.returncode,r.stdout[:2000],r.stderr)
        values=list(map(int,r.stdout.split())); assert values.pop()==0,'stack leak'; return values
    def state(values,model):
        assert values[:39]==model.state(),(values,model.state())
    assert run(': TBL 16 0 DO I CELLS ZX-LEVELS + @ . LOOP ; TBL')==LEVELS
    tests.append({'case':'all16-levels-independent-double-formula','levels':LEVELS})
    for mode in [0,1]:
        values=run(f': PORTS 65536 0 DO {mode} ZX-MODEL! ZX-RESET '+('8 65533 0 ZX-OUT ' if mode else '')+'I 13 * 255 AND I 0 ZX-OUT ZX-ULA @ . ZX-SELECT @ . 8 ZX-R@ . LOOP ; PORTS')
        wanted=[]
        for port in range(65536):
            value=port*13&255; ay=mode and port//32768 and not(port//2%2)
            wanted.extend([value if port%2==0 else 0,value if ay and port//16384%2 else 8 if mode else 0,value&31 if ay and not(port//16384%2) else 0])
        assert values==wanted
        tests.append({'case':f'all65536-out-decodes-mode{mode}','sha256':hashlib.sha256(bytes(values)).hexdigest()})
    values=run('1 ZX-MODEL! ZX-RESET 11 8 0 ZX-AY! 8 65533 0 ZX-OUT VARIABLE PORT : GET-IN PORT @ 0 ZX-IN ; : INPUTS 65536 0 DO I PORT ! [\'] GET-IN CATCH DUP IF . ELSE DROP . THEN LOOP ; INPUTS')
    assert values==[11 if port//32768 and port//16384%2 and not(port//2%2) and port%2 else -21 for port in range(65536)]
    tests.append({'case':'all65536-in-availability-128k'})
    # All register masks and values, using the direct path independently of bus.
    values=run(': MASKS 1 ZX-MODEL! ZX-RESET 15 0 DO 256 0 DO I J 0 ZX-AY! J 0 ZX-AY@ . LOOP LOOP ; MASKS')
    # R7 ends at255, so the later R14 sweep is output mode with externalFF.
    wanted=[v&MASKS[reg] for reg in range(15) for v in range(256)]
    assert values==wanted
    tests.append({'case':'all15-registers256values-masks-portA-output'})
    # AY16level sequence is hand-derived; each level lasts2EP PSG steps.
    for shape in range(16):
        down=list(range(15,-1,-1)); up=list(range(16))
        sequences={**{i:down+[0]*80 for i in range(4)}, **{i:up+[0]*80 for i in range(4,8)},
                   8:down*6, 9:down+[0]*80, 10:(down+up)*3, 11:down+[15]*80,
                   12:up*6, 13:up+[15]*80, 14:(up+down)*3, 15:up+[0]*80}
        wanted=sequences[shape]
        code=f'1 ZX-MODEL! ZX-RESET 1 11 0 ZX-AY! {shape} 13 0 ZX-AY! : ENV 96 0 DO I 32 * ZX-TO ZX-ENV-LEVEL 1 RSHIFT . LOOP ; ENV'
        assert run(code)==wanted
    tests.append({'case':'all16-envelope-shapes96levels-hand-sequences'})
    # Hand timing: shared step at16, shortened periods fire on the next step,
    # and R13 restarts envelope without resetting the shared CPU divider.
    assert run('1 ZX-MODEL! ZX-RESET 15 ZX-TO ZX-TONE-COUNT @ . ZX-TONE-HIGH @ . 16 ZX-TO ZX-TONE-COUNT @ . ZX-TONE-HIGH @ . ZX-LFSR @ .')==[0,0,0,-1,65536]
    assert run('1 ZX-MODEL! ZX-RESET 10 0 0 ZX-AY! 144 ZX-TO ZX-TONE-COUNT @ . 2 0 144 ZX-AY! 160 ZX-TO ZX-TONE-COUNT @ . ZX-TONE-HIGH @ .')==[9,0,-1]
    assert run('1 ZX-MODEL! ZX-RESET 10 11 0 ZX-AY! 8 13 0 ZX-AY! 144 ZX-TO ZX-ENV-COUNT @ . 1 11 144 ZX-AY! 160 ZX-TO ZX-ENV-COUNT @ . ZX-ENV-STEP @ . 8 13 161 ZX-AY! 175 ZX-TO ZX-ENV-STEP @ . 176 ZX-TO ZX-ENV-STEP @ .')==[9,0,30,31,30]
    assert run('1 ZX-MODEL! ZX-RESET 10 6 0 ZX-AY! 272 ZX-TO ZX-NOISE-COUNT @ . ZX-LFSR @ . 1 6 272 ZX-AY! 304 ZX-TO ZX-NOISE-COUNT @ . ZX-LFSR @ .')==[9,1,0,65536]
    assert run('1 ZX-MODEL! ZX-RESET 8 13 0 ZX-AY! 16 ZX-TO ZX-ENV-STEP @ . 32 ZX-TO ZX-ENV-STEP @ .')==[30,29]
    assert run('1 ZX-MODEL! ZX-RESET 1 12 0 ZX-AY! 8 13 0 ZX-AY! 4095 ZX-TO ZX-ENV-STEP @ . 4096 ZX-TO ZX-ENV-STEP @ .')==[31,30]
    tests.append({'case':'hand-divider-zero-periods-shortening-high-byte-and-retrigger'})
    for mode in [0,1]:
        m=Model(mode); assert run(f'{mode} ZX-MODEL! ZX-RESET SNAP')[:39]==m.state()
        events=[(0,16,270),(73,0,270),(74,16,270),(1000,0,270)]
        if mode:
            events=[(0,v,reg) for reg,v in enumerate([28,1,227,1,82,2,9,48,12,10,16,100,0,14])]+events
            events+= [(511,8,65533+16),(511,3,49149+16),(1033,14,65533+16),(1033,165,49149+16),(1034,90,15),(1903,64,7),(2301,1,11),(2313,0,12),(2500,14,13)]
        events.sort(key=lambda x:x[0]); expected=m.render(4096,events)
        with tempfile.TemporaryDirectory(prefix='pcm-',dir=work) as tmp:
            out=Path(tmp)/'pcm.bin'; base=f'{mode} ZX-MODEL! ZX-RESET\n'+queue(events)+'CREATE OUT 8192 ALLOT\n'
            for slow,body in [(False,'OUT 4096 ZX-RENDER'),(True,'OUT 4096 ZX-RENDER'),(False,'OUT 13 ZX-RENDER OUT 26 + 4083 ZX-RENDER')]:
                result=run(base+('TRUE ZX-SLOW !\n' if slow else '')+body+f' S" {out.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 8192 FD WRITE-FILE THROW FD CLOSE-FILE THROW SNAP')
                assert out.read_bytes()==expected,(mode,slow); state(result,m); assert result[39]==result[40]
        tests.append({'case':f'full4096frame-slow-fast-split-state-mode{mode}','pcm_sha256':hashlib.sha256(expected).hexdigest()})
    assert run('1 ZX-MODEL! ZX-RESET 8 65533 0 ZX-OUT 7 49149 100 ZX-OUT 5 49149 100 ZX-OUT-EVENT! 8 ZX-R@ . 0 ZX-RUN 8 ZX-R@ .')==[7,5]
    assert run('1 ZX-MODEL! ZX-RESET : INVALID 256 15 DO 1 ZX-MODEL! ZX-RESET 11 8 0 ZX-AY! I 65533 0 ZX-OUT 31 49149 0 ZX-OUT 8 ZX-R@ . 65533 0 ZX-IN . LOOP ; INVALID')==[11,255]*241
    # Virtual A directions, output latch, external-low declaration, R15 guard.
    assert run('1 ZX-MODEL! ZX-RESET 165 14 0 ZX-AY! 90 0 ZX-INPUT! 14 0 ZX-AY@ . 64 7 0 ZX-AY! 14 0 ZX-AY@ . 15 65533 0 ZX-OUT 65533 0 ZX-IN .')==[90,0,255]
    assert run('1 ZX-MODEL! ZX-RESET 8 65533 0 ZX-OUT 5 49149 100 ZX-OUT-EVENT! 9 65533 100 ZX-OUT-EVENT! 7 49149 100 ZX-OUT 8 ZX-R@ . 9 ZX-R@ .')==[5,7]
    assert run('0 ZX-MODEL! ZX-RESET 16 254 100 ZX-OUT-EVENT! ZX-SAMPLE . 100 ZX-TO ZX-SAMPLE . 0 254 100 ZX-OUT-EVENT! ZX-SAMPLE . 0 ZX-RUN ZX-SAMPLE .')==[0,4096,4096,0]
    tests.append({'case':'portA-and-same-tick-queued-immediate-causal-order'})
    # 64 mixer truth tables with all four tone/noise boolean combinations.
    vals=run(': GATES 1 ZX-MODEL! ZX-RESET 15 8 0 ZX-AY! 64 0 DO I 7 0 ZX-AY! 2 0 DO I ZX-TONE-HIGH ! 2 0 DO I ZX-LFSR ! 0 ZX-CHANNEL . LOOP LOOP LOOP ; GATES')
    wanted=[32767 if (tone or mask&1) and (noise or mask&8) else 0 for mask in range(64) for tone in range(2) for noise in range(2)]
    assert vals==wanted; tests.append({'case':'all64-mixer-truth-tables'})
    # Exact relative clock/fraction after immediate time gaps.
    m=Model(0); m.advance(1000); m.render(1,[]); first=[m.t,m.frac];m.advance(2000);m.render(1,[])
    assert run('0 ZX-MODEL! ZX-RESET 1000 ZX-TO CREATE OUT 4 ALLOT OUT 1 ZX-RENDER ZX-CYCLE @ . ZX-FRACTION @ . 2000 ZX-TO OUT 1 ZX-RENDER ZX-CYCLE @ . ZX-FRACTION @ .')==first+[m.t,m.frac]
    for mode,body,error in [(0,'65533 1000 ZX-IN',-21),(0,'1 1000 ZX-INPUT!',-21),(0,'1 0 -1 ZX-AY!',-24),(1,'256 15 -1 ZX-AY!',-21),(0,'1 0 0 ZX-AY!',-21),(1,'1 15 0 ZX-AY!',-21),(1,'1 16 0 ZX-AY!',-24),(1,'256 254 0 ZX-OUT',-24),(1,'1 -1 0 ZX-OUT',-24),(1,'49149 1000 ZX-IN',-21),(1,'65532 1000 ZX-IN',-21),(1,'-1 ZX-TO',-24),(1,'-1 ZX-RUN',-24),(1,'2 ZX-MODEL!',-24),(1,'1 254 50 ZX-OUT-EVENT!',-24)]:
        code=f'{mode} ZX-MODEL! ZX-RESET 0 254 100 ZX-OUT-EVENT! CREATE COPY 24576 ALLOT ZX-EVENTS COPY 24576 MOVE SNAP : BAD {body} ; \' BAD CATCH . SNAP ZX-EVENTS 24576 COPY 24576 COMPARE .'
        r=run(code); assert r[41]==error and r[:41]==r[42:83] and r[83]==0,(body,r)
    tests.append({'case':'atomic-input-errors-state-and-entire-queue','cases':15})
    q='0 ZX-MODEL! ZX-RESET : FILLQ 1024 0 DO I 255 AND 254 I ZX-OUT-EVENT! LOOP ; FILLQ '
    assert run(q+': BADORDER 2 254 0 ZX-OUT-EVENT! ; \' BADORDER CATCH .')==[-528]
    assert run(q+': BAD 2 254 1024 ZX-OUT-EVENT! ; \' BAD CATCH . 512 ZX-TO 7 254 1024 ZX-OUT-EVENT! ZX-EVENT-COUNT @ . ZX-EVENT-INDEX @ . 1024 ZX-TO ZX-ULA @ .')==[-528,512,0,7]
    for mode in [0,1]:
        # Preflight uses wide arithmetic; force a legal near-MAX state, not an impractically long AY loop.
        r=run(f'{mode} ZX-MODEL! ZX-RESET 9223372036854775734 ZX-CYCLE ! CREATE OUT 4 ALLOT OUT 4 42 FILL SNAP : BAD OUT 2 ZX-RENDER ; \' BAD CATCH . SNAP OUT C@ . OUT 3 + C@ .')
        assert r[41]==-24 and r[:41]==r[42:83] and r[83:]==[42,42], (mode,r)
    for mode in [0,1]:
        r=run(f'{mode} ZX-MODEL! ZX-RESET 9223372036854775734 ZX-CYCLE ! CREATE OUT 2 ALLOT OUT 1 ZX-RENDER ZX-CYCLE @ . ZX-FRACTION @ .')
        assert r==[9223372036854775734+(3546895 if mode else 3500000)//48000,(3546895 if mode else 3500000)%48000]
    assert run('0 ZX-MODEL! ZX-RESET : BAD -1 1 ZX-RENDER ; \' BAD CATCH . ZX-CYCLE @ . ZX-FRACTION @ .')==[-9,72,44000]
    tests.append({'case':'queue-capacity-reclaim-wide-time-preflight-and-partial-memory-error'})
    files=['tests/scripts/verify-zx-spectrum-audio.py','include/zx-spectrum-audio.fs','include/zx-ay-levels.fs','tests/audio/zx-spectrum-audio-play.fs','scripts/zx-ay-levels.py']
    print(json.dumps({'platform':platform.platform(),'scope':__doc__,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'source_sha256_lf':{f:hashlib.sha256((ROOT/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in files},'tests':tests},indent=2))


if __name__=='__main__':main()
