#!/usr/bin/env python3
"""Independent integer S-DSP sample-boundary oracle; all generated audio stays in RAM."""
import argparse,hashlib,heapq,json,platform,re,struct,subprocess,tempfile
from pathlib import Path
if not __debug__:raise SystemExit("Verification requires assertions; do not use -O.")
ROOT=Path(__file__).resolve().parents[2]
DATA=json.loads((ROOT/'scripts/snes-gauss-data.json').read_text(encoding='utf-8'))
GAUSS=DATA['values']
RATES=[0,2048,1536,1280,1024,768,640,512,384,320,256,192,160,128,96,80,64,48,40,32,24,20,16,12,10,8,6,5,4,3,2,1]
FIELDS=['on','pos','nib','header','p1','p2','phase','env','mode','delay']
GLOBALS=['CYCLE','DIV','FRAME','PENDING','NOISE','EOFF','ELEN','EHI','LEFT','RIGHT']
DUMP=': SNAP 128 0 DO I SD-R@ . LOOP 112 0 DO SD-VOICES I CELLS + @ . LOOP '+' '.join('SD-'+v+' @ .' for v in GLOBALS)+' 16 0 DO SD-EHIST I CELLS + @ . LOOP SD-EVENT-COUNT @ . SD-EVENT-INDEX @ . ;\n'
def signed(n,bits):return (n+(1<<(bits-1)))%(1<<bits)-(1<<(bits-1))
def clamp(n):return min(32767,max(-32768,n))
def brr(nibble,header,old,older):
    n=signed(nibble,4);shift=header>>4
    val=n*2**shift//2 if shift<=12 else -2048 if n<0 else 0
    # Mathematically equivalent rational predictors, distinct from Forth shift decomposition.
    p,q=[(0,0),(old*15//16,0),(old*61//32,older*-15//16),(old*115//64,older*-13//16)][header//4%4]
    return signed(clamp(val+p+q),15)

class Model:
    def __init__(self):
        self.r=bytearray(128);self.r[108]=224;self.ram=bytearray(65536)
        self.v=[dict(zip(FIELDS,[0,0,0,0,0,0,0,0,3,0]),hist=[0]*4) for _ in range(8)]
        self.t=self.div=self.frame=self.pending=self.eoff=self.ehi=self.left=self.right=0
        self.noise=16384;self.elen=4;self.ehist=[[0,0] for _ in range(8)];self.events=[];self.serial=0;self.coverage=set()
    def word(self,addr):return self.ram[addr%65536]+256*self.ram[(addr+1)%65536]
    def putword(self,addr,n):
        self.ram[addr%65536]=n%256;self.ram[(addr+1)%65536]=n//256%256
    def directory(self,i):return (self.r[93]*256+self.r[i*16+4]*4)%65536
    def start(self,i):
        self.v[i]=dict(zip(FIELDS,[-1,self.word(self.directory(i)),0,0,0,0,0,0,0,5]),hist=[0]*4)
        self.r[124]&=255-(1<<i)
    def consume(self,i):
        v=self.v[i];n=v['nib'];pos=v['pos']
        if not n:v['header']=self.ram[pos]
        byte=self.ram[(pos+1+n//2)%65536];value=brr(byte%16 if n%2 else byte//16,v['header'],v['p1'],v['p2'])
        v['p2'],v['p1']=v['p1'],value;v['hist']=v['hist'][1:]+[value];v['nib']+=1
        if v['nib']==16:
            v['nib']=0
            if v['header']%2:
                self.r[124]|=1<<i;v['pos']=self.word(self.directory(i)+2)
                if not(v['header']&2):v['env']=0;v['mode']=3;self.coverage.add('nonloop-end')
            else:v['pos']=(pos+9)%65536
    def due(self,rate):return rate!=0 and self.frame%RATES[rate]==0
    def envelope(self,i):
        v=self.v[i];env=v['env'];mode=v['mode'];a,b,g=self.r[i*16+5:i*16+8]
        if mode==3:v['env']=max(0,env-8);return
        if a&128:
            rate=[2*(a%16)+1,16+2*(a//16%8),b%32][mode]
            delta=(1024 if a%16==15 else 32) if mode==0 else -((env+255)//256)
            if self.due(rate):env+=delta
        elif g<128:env=g*16
        elif self.due(g%32):
            modeg=g//32%4;env+=[-32,-((env+255)//256),32,32 if env<1536 else 8][modeg]
        v['env']=min(2047,max(0,env))
        if v['mode']==0 and v['env']>=2016:v['mode']=1
        if v['mode']==1 and v['env']<=(b//32+1)*256:v['mode']=2
    def gaussian(self,i):
        v=self.v[i];f=v['phase']//16;h=v['hist'];c=[GAUSS[255-f],GAUSS[511-f],GAUSS[256+f],GAUSS[f]]
        parts=[x*y//1024 for x,y in zip(h,c)]
        return clamp(signed(sum(parts[:3]),16)+parts[3])//2
    def voice(self,i,previous):
        v=self.v[i];value=0;published_env=v['env']
        if v['on']:
            if v['delay']:
                v['delay']-=1
                if v['delay']==0:self.consume(i)
            else:
                sample=signed(self.noise,15) if self.r[61]&(1<<i) else self.gaussian(i)
                value=sample*v['env']//2048
                self.envelope(i)
                pitch=self.r[i*16+2]+256*(self.r[i*16+3]%64)
                if self.r[i*16+3]>=64:self.coverage.add('pitch-high-mask')
                if i and self.r[45]&(1<<i):
                    pitch=pitch*(1024+previous//16)//1024
                    if pitch>16383:self.coverage.add('pmon-clamp')
                    pitch=min(16383,max(0,pitch))
                v['phase']+=pitch
                if v['phase']>=8192:self.coverage.add('multiple-consume')
                while v['phase']>=4096:self.consume(i);v['phase']-=4096
        self.r[i*16+8]=published_env//16;self.r[i*16+9]=value//128%256
        return value
    def step(self):
        self.frame+=1
        if self.due(self.r[108]%32):self.noise=self.noise//2+(((self.noise^(self.noise//2))%2)<<14)
        for i,v in enumerate(self.v):
            if self.r[108]&128:v['env']=0;v['mode']=3
            if self.frame%2:
                if self.r[92]&(1<<i):v['mode']=3
                if self.pending&(1<<i):self.start(i)
        if self.frame%2:self.pending=0
        mix=[0,0];emix=[0,0];previous=0
        for i in range(8):
            value=self.voice(i,previous);previous=value
            for ch in range(2):
                term=value*signed(self.r[i*16+ch],8)//64
                mix[ch]=clamp(mix[ch]+term)
                if self.r[77]&(1<<i):emix[ch]=clamp(emix[ch]+term)
        if not self.eoff:self.elen=max(4,(self.r[125]%16)*2048)
        address=(self.r[109]*256+self.eoff)%65536
        if self.r[109]*256+self.eoff>=65536:self.coverage.add('echo-16bit-wrap')
        if address in [256,260]:self.coverage.add('echo-dir-overlap')
        if address in [512,516,520]:self.coverage.add('echo-brr-overlap')
        self.ehist[self.ehi]=[signed(self.word(address+ch*2),16)//2 for ch in range(2)]
        outs=[]
        for ch in range(2):
            terms=[self.ehist[(self.ehi+k+1)%8][ch]*signed(self.r[k*16+15],8)//64 for k in range(8)]
            if not -32768<=sum(terms[:7])<=32767:self.coverage.add('fir-prefix-wrap')
            fir=clamp(signed(sum(terms[:7]),16)+terms[7])
            val=clamp(signed(mix[ch]*signed(self.r[ch*16+12],8)//128,16)+signed(fir*signed(self.r[ch*16+44],8)//128,16))
            outs.append(0 if self.r[108]&64 else val)
            if not(self.r[108]&32):self.putword(address+ch*2,clamp(emix[ch]+signed(fir*signed(self.r[13],8)//128,16))&~1)
        self.left,self.right=outs;self.eoff=(self.eoff+4)%self.elen;self.ehi=(self.ehi+1)%8
    def advance(self,tick):
        assert tick>=self.t
        while self.t+32-self.div<=tick:
            self.t+=32-self.div;self.div=0;self.step()
        self.div+=tick-self.t;self.t=tick
    def store(self,value,target):
        if target<128:
            self.r[target]=0 if target==124 else value
            if target==76:self.pending=value
        else:self.ram[target-128]=value
    def enqueue(self,value,target,tick):
        heapq.heappush(self.events,(tick,self.serial,value,target));self.serial+=1
    def to(self,tick):
        while self.events and self.events[0][0]<=tick:
            t,_,v,r=heapq.heappop(self.events);self.advance(t);self.store(v,r)
        self.advance(tick)
    def render(self,frames):
        out=bytearray()
        for _ in range(frames):self.to(self.t+32);out.extend(struct.pack('<hh',self.left,self.right))
        return bytes(out)
    def state(self):
        voices=[value for v in self.v for value in [*[v[f] for f in FIELDS],*v['hist']]]
        return list(self.r)+voices+[self.t,self.div,self.frame,self.pending,self.noise,self.eoff,self.elen,self.ehi,self.left,self.right]+[x for h in self.ehist for x in h]

def demo():
    m=Model();m.putword(256,512);m.putword(258,512);m.ram[512:521]=bytes([195,2,70,118,66,14,172,154,206])
    for reg,val in [(93,1),(12,64),(28,64),(44,32),(60,32),(13,48),(127,64),(109,64),(125,1),(77,255)]:m.store(val,reg)
    for i in range(8):
        p=901+i*73
        for reg,val in [(2,p%256),(3,p//256),(0,8 if i%2 else 20),(1,20 if i%2 else 8),(7,48)]:m.store(val,i*16+reg)
    m.store(0,108);m.store(255,76);return m

def queue(events):
    return '\n'.join(f'{v} {r} {t} SD-REG-EVENT!' if r<128 else f'{v} {r-128} {t} SD-RAM-EVENT!' for t,v,r in events)+'\n'

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);p.add_argument('--reference-doc',type=Path);p.add_argument('--native',action='store_true');args=p.parse_args();binary=args.sigma.resolve();work=ROOT/'.work/1174';work.mkdir(parents=True,exist_ok=True);tests=[]
    if args.reference_doc:
        text=args.reference_doc.read_text(encoding='utf-8')
        if args.reference_doc.suffix.lower() in ['.html','.htm']:assert hashlib.sha256(args.reference_doc.read_bytes()).hexdigest()==DATA['source_html_sha256']
        region=text.split('The Gauss table contains the following values (in hex):',1)[1].split('The gauss table is slightly bugged:',1)[0]
        region=re.sub(r';[^\n]*','',re.sub(r'<[^>]*>','',region))
        independent=[int(x,16) for x in re.findall(r'\b[0-9A-Fa-f]{3}\b',region)]
        assert independent==GAUSS and len(independent)==512
        tests.append({'case':'independent-extraction-from-reference-document','reference_sha256':hashlib.sha256(args.reference_doc.read_bytes()).hexdigest()})
    def run(code):
        with tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.fs',dir=work,delete=False) as f:file=Path(f.name);f.write(DUMP+code+'\nDEPTH . BYE\n')
        try:r=subprocess.run([str(binary),'examples/snes-dsp-audio-native.fs' if args.native else 'examples/snes-dsp-audio.fs',str(file)],cwd=ROOT,input=b'',capture_output=True,timeout=60)
        finally:file.unlink()
        assert r.returncode==0 and not r.stderr,(r.returncode,r.stdout[:1500],r.stderr)
        v=list(map(int,r.stdout.split()));assert v.pop()==0,'stack leak';return v
    assert run('SNAP')==Model().state()+[0,0]
    if args.native:assert run("SD-FRAMES-XT @ ' SD-NATIVE-FRAMES = .")==[-1]
    shift_values=[-9223372036854775808,-2147483649,-65537,-32769,-16384,-2049,-1025,-257,-129,-33,-17,-9,-3,-1,0,1,3,32767,65537,2147483648,9223372036854775807]
    code='\n'.join(f'{n} {bits} SD-ASR .' for n in shift_values for bits in range(64))
    assert run(code)==[n//(1<<bits) for n in shift_values for bits in range(64)]
    tests.append({'case':'arithmetic-shift-full64bits-extremes','vectors':len(shift_values)*64})

    # All headers/nibbles with diverse signed histories exercise rational predictor rounding.
    for old,older in [(0,0),(12345,-8765),(-16384,16383)]:
        code=f': BRRS 256 0 DO 16 0 DO I J {old} {older} SD-BRR . LOOP LOOP ; BRRS'
        wanted=[brr(n,h,old,older) for h in range(256) for n in range(16)]
        assert run(code)==wanted
    tests.append({'case':'all256headers16nibbles3histories-rational-brr'})
    assert hashlib.sha256(struct.pack('<512H',*GAUSS)).hexdigest()=='0acd5077942f6cc6676829bc1954a05aeaad51be716f62d9ef4e8e7c94685af2'
    assert all(a<=b for a,b in zip(GAUSS,GAUSS[1:]))
    assert all(2047<=sum(GAUSS[x] for x in [i,255-i,256+i,511-i])<=2049 for i in range(256))
    for hist in [[0,1000,-500,16383],[-16384]*4,[16383]*4,[-16384,16383,-16384,16383]]:
        m=Model();m.v[0]['hist']=hist;wanted=[]
        for f in range(256):m.v[0]['phase']=f*16;wanted.append(m.gaussian(0))
        init=' '.join(f'{value} 0 {10+i} SD-V!' for i,value in enumerate(hist))
        got=run('SD-RESET '+init+' : GS 256 0 DO I 16 * 0 SD-PHASE SD-V! 0 SD-GAUSS-SAMPLE . LOOP ; GS')
        assert got==wanted
        if hist==[-16384]*4:assert 16376 in got
    tests.append({'case':'all256-gauss-phases4-history-extremes-and-overflow'})
    assert run(': RATES 32 0 DO I CELLS SD-RATES + @ . LOOP ; RATES')==RATES
    wanted=[]
    for rate in range(32):
        frames=RATES[rate]*2 if rate else 8
        wanted.extend([-int(bool(rate and f%RATES[rate]==0)) for f in range(1,frames+1)])
    assert run(': RATECHECK 32 0 DO I CELLS SD-RATES + @ DUP IF 2 * ELSE DROP 8 THEN 0 DO I 1+ SD-FRAME ! J SD-RATE? . LOOP LOOP ; RATECHECK')==wanted
    tests.append({'case':'all32-global-rate-boundaries-two-periods'})
    envcases=[]
    for mode in range(4):
        for rate in range(32):envcases.append((0,96,128+32*mode+rate,[2047,2047,0,1520][mode],0,RATES[rate]*2 if rate else 8))
    envcases.extend((0,96,gain,0,0,1) for gain in range(128))
    envcases.extend((128+a,96,0,0,0,2*RATES[2*a+1]) for a in range(16))
    envcases.extend((128+16*d,96,0,2047,1,2*RATES[16+2*d]) for d in range(8))
    envcases.extend((128,rate,0,1024,2,2*RATES[rate] if rate else 8) for rate in range(32))
    envcases.extend((0,0,0,env,3,2) for env in [0,1,7,8,2047])
    wanted=[]
    for a,b,gain,env,mode,frames in envcases:
        m=Model();m.r[5:8]=bytes([a,b,gain]);m.v[0]['env']=env;m.v[0]['mode']=mode
        for frame in range(1,frames+1):m.frame=frame;m.envelope(0)
        wanted.extend([m.v[0]['env'],m.v[0]['mode']])
    proc=': ET { a b gain env mode frames -- } SD-RESET a 5 SD-STORE b 6 SD-STORE gain 7 SD-STORE env 0 SD-ENV SD-V! mode 0 SD-MODE SD-V! frames 0 DO I 1+ SD-FRAME ! 0 SD-ENV-STEP LOOP 0 SD-ENV SD-V@ . 0 SD-MODE SD-V@ . ; '
    assert run(proc+'\n'+'\n'.join(' '.join(map(str,case))+' ET' for case in envcases))==wanted
    tests.append({'case':'gain4modes-all32rates-direct128-attack16-decay8-sustain32-release','cases':len(envcases)})
    if args.native:
        # These go through the native frame entry, not the retained private Forth helpers.
        for old,older in [(0,0),(12345,-8765),(-16384,16383)]:
            code=f': NB 256 0 DO 16 0 DO SD-RESET 32 108 SD-STORE TRUE 0 SD-ON SD-V! 512 0 SD-POS SD-V! 16 3 SD-STORE J 512 SD-B! I 16 * 513 SD-B! {old} 0 SD-P1 SD-V! {older} 0 SD-P2 SD-V! 32 SD-RUN 0 SD-P1 SD-V@ . LOOP LOOP ; NB'
            assert run(code)==[brr(n,h,old,older) for h in range(256) for n in range(16)]
        tests.append({'case':'native-frame-all256headers16nibbles3histories'})
        proc=': ETN { a b gain env mode frames -- } SD-RESET 32 108 SD-STORE TRUE 0 SD-ON SD-V! a 5 SD-STORE b 6 SD-STORE gain 7 SD-STORE env 0 SD-ENV SD-V! mode 0 SD-MODE SD-V! frames 0 DO 32 SD-RUN LOOP 0 SD-ENV SD-V@ . 0 SD-MODE SD-V@ . ; '
        assert run(proc+'\n'+'\n'.join(' '.join(map(str,case))+' ETN' for case in envcases))==wanted
        tests.append({'case':'native-frame-all317-envelope-cases','cases':len(envcases)})
        for hist in [[0,1000,-500,16383],[-16384]*4,[16383]*4,[-16384,16383,-16384,16383]]:
            expected=[]
            for f in range(256):
                m=Model();m.r[108]=32;m.r[0]=64;m.r[12]=128;m.v[0].update(on=-1,env=2032,phase=f*16,hist=hist.copy());m.advance(32)
                expected.extend([m.left,m.right,m.r[8],m.r[9]])
            init=' '.join(f'{value} 0 {10+i} SD-V!' for i,value in enumerate(hist))
            code=': NG 256 0 DO SD-RESET 32 108 SD-STORE 64 0 SD-STORE 128 12 SD-STORE TRUE 0 SD-ON SD-V! 2032 0 SD-ENV SD-V! I 16 * 0 SD-PHASE SD-V! '+init+' 32 SD-RUN SD-LEFT @ . SD-RIGHT @ . 8 SD-R@ . 9 SD-R@ . LOOP ; NG'
            assert run(code)==expected
        tests.append({'case':'native-frame-gaussian256phases4-extreme-histories-oldENV-publish-and-PCM'})
        for tap in range(8):
            code=f'SD-RESET 32 108 SD-STORE 64 44 SD-STORE 64 {tap*16+15} SD-STORE -1234 0 SD-W! : NI 9 0 DO 32 SD-RUN SD-LEFT @ . 0 0 SD-W! LOOP ; NI'
            assert run(code)==[-309 if i==7-tap else 0 for i in range(9)]
        # Saturated FIR -> -128 feedback wraps +32768 to -32768. Initial word differs.
        for flag in [0,32,64]:
            m=Model();m.r[108]=flag;m.r[15]=127;m.r[127]=64;m.r[44]=128;m.r[13]=128;m.ehist[1][0]=-16384;m.putword(0,-1234);initial_word=m.word(0);m.advance(32)
            assert m.word(0)==(initial_word if flag&32 else 32768)
            assert (m.word(0)!=initial_word)==(not bool(flag&32))
            code=f'SD-RESET {flag} 108 SD-STORE 127 15 SD-STORE 64 127 SD-STORE 128 44 SD-STORE 128 13 SD-STORE -16384 SD-EHIST 2 CELLS + ! -1234 0 SD-W! 32 SD-RUN SNAP 0 SD-W@ . 2 SD-W@ .'
            assert run(code)==m.state()+[0,0,m.word(0),m.word(2)]
        m=Model();m.r[108]=32;m.r[12]=128
        init='SD-RESET 32 108 SD-STORE 128 12 SD-STORE '
        for i in range(2):
            m.r[i*16]=127;m.v[i].update(on=-1,env=2032,hist=[-10000]*4)
            init+=f'127 {i*16} SD-STORE TRUE {i} SD-ON SD-V! 2032 {i} SD-ENV SD-V! '+''.join(f'-10000 {i} {10+k} SD-V! ' for k in range(4))
        m.advance(32);assert m.left==-32768
        assert run(init+'32 SD-RUN SNAP')==m.state()+[0,0]
        tests.append({'case':'native-frame-FIR8impulses-feedback-signed-volume-wrap-mute-and-write-disable'})
    assert run('SD-RESET 1 12 32 SD-REG-EVENT! 2 12 32 SD-REG! 12 SD-R@ . 3 12 32 SD-REG-EVENT! 12 SD-R@ . 0 SD-RUN 12 SD-R@ .')==[2,2,3]
    assert run('SD-DEMO-SETUP : DELAYTEST 6 0 DO 32 SD-RUN 0 SD-DELAY SD-V@ . 0 SD-ENV SD-V@ . 0 SD-PHASE SD-V@ . LOOP ; DELAYTEST')==[4,0,0,3,0,0,2,0,0,1,0,0,0,0,0,0,768,901]
    assert run('SD-DEMO-SETUP 0 76 0 SD-REG! 1 76 32 SD-REG-EVENT! 32 SD-TO 0 SD-ON SD-V@ . 64 SD-TO 0 SD-ON SD-V@ . 96 SD-TO 0 SD-ON SD-V@ .')==[0,0,-1]
    assert run('SD-DEMO-SETUP 0 SD-START 0 SD-CONSUME 0 512 SD-B! 768 258 SD-W! : MORE 14 0 DO 0 SD-CONSUME LOOP ; MORE 124 SD-R@ . 0 SD-NIB SD-V@ . 0 SD-CONSUME 124 SD-R@ . 0 SD-NIB SD-V@ . 0 SD-POS SD-V@ . 0 SD-HEADER SD-V@ .')==[0,15,1,0,768,195]
    assert run('SD-RESET 52 65535 SD-B! 18 0 SD-B! 65535 SD-W@ .')==[4660]
    tests.append({'case':'hand-kon5delay-event-boundary-latched-header-end-loop-and-word-wrap'})
    assert run(': ALLREG 128 0 DO SD-RESET 256 0 DO I J 0 SD-REG! J 0 SD-REG@ . LOOP LOOP ; ALLREG')==[0 if reg==124 else value for reg in range(128) for value in range(256)]
    ram_values=[(i*17)^85 for i in range(65536)];ram_values=[i%256 for i in ram_values]
    assert run('SD-RESET : ALLRAM 65536 0 DO I 17 * 85 XOR 255 AND I 0 SD-RAM! LOOP 65536 0 DO I 0 SD-RAM@ . LOOP ; ALLRAM')==ram_values
    tests.append({'case':'all128registers256bytes-and-all65536aram-addresses'})
    assert run('7 200 16383 -16384 SD-BRR . 8 200 -16384 16383 SD-BRR .')==[-1,0]
    assert run('SD-RESET 32 108 SD-STORE -32768 SD-MIX ! 128 12 SD-STORE SD-ECHO SD-LEFT @ .')==[-32768]
    echoedge='SD-RESET 64 15 SD-STORE 64 127 SD-STORE -16384 SD-EHIST 2 CELLS + ! -32768 0 SD-W! '
    assert run(echoedge+'32 108 SD-STORE 128 44 SD-STORE SD-ECHO SD-LEFT @ .')==[-32768]
    assert run(echoedge+'0 108 SD-STORE 128 13 SD-STORE SD-ECHO 0 SD-W@ SD-S16 .')==[-32768]
    for tap in range(8):
        code=f'SD-RESET 32 108 SD-STORE 64 44 SD-STORE 64 {tap*16+15} SD-STORE -1234 0 SD-W! : IMPULSE 9 0 DO SD-ECHO SD-LEFT @ . 0 0 SD-W! LOOP ; IMPULSE'
        assert run(code)==[-309 if i==7-tap else 0 for i in range(9)]
    assert run('SD-RESET 0 108 SD-STORE 1 125 SD-STORE 32 SD-RUN 0 125 32 SD-REG! 16320 SD-RUN SD-EOFF @ . SD-ELEN @ . 32 SD-RUN SD-EOFF @ . SD-ELEN @ . 32 SD-RUN SD-EOFF @ . SD-ELEN @ .')==[2044,2048,0,2048,0,4]
    assert run('SD-RESET 31 108 SD-STORE : NOISE20 20 0 DO 32 SD-RUN SD-NOISE @ . LOOP ; NOISE20')==[8192,4096,2048,1024,512,256,128,64,32,16,8,4,2,16385,24576,12288,6144,3072,1536,768]
    tests.append({'case':'hand-signed-volume-feedback-wrap-fir8impulses-edl-latch-noise20'})
    # First five poll+delay outputs are zero, then compare full stereo/ARAM/state.
    events=[(31,31,108),(211,128,45),(1023,128,61),(2049,128,92),(3071,1,76),(4096,0,92),(6001,192,108),(6303,0,108),(6400,255,124),(7000,2,125),(7200,65,109),(8192,255,44),(8224,128,13),(9501,7,127)]
    cases=[('demo',demo(),[]),('changes',demo(),events)]
    m=demo()
    for reg,value in [(12,128),(28,128),(44,128),(60,127),(13,128),(109,255),(125,1),(61,170),(45,255),(108,31)]:m.store(value,reg)
    for i in range(8):
        for reg,value in [(i*16,128 if i%2 else 127),(i*16+1,127 if i%2 else 128),(i*16+2,255),(i*16+3,255),(i*16+7,127),(i*16+15,128 if i%2 else 127)]:m.store(value,reg)
    cases.append(('signed8voice-noise-pmon-fir-and-aram-alias',m,[(4096,0,125),(5120,255,109),(7000,255,124)]))
    m=demo()
    for i in range(8):m.store(100,i*16+7)
    cases.append(('all-envelope-modes',m,[(601,159,39),(601,191,55),(601,223,71),(601,255,87),(601,143,101),(601,255,117),(601,255,118),(602,31,108),(1024,255,92),(2048,0,92),(2048,255,76)]))
    m=Model();m.putword(256,65532);m.putword(258,65532)
    for i,b in enumerate([195,2,70,118,66,14,172,154,206]):m.ram[(65532+i)%65536]=b
    for reg,val in [(93,1),(2,255),(3,63),(7,127),(0,127),(1,128),(12,127),(28,127),(108,32),(76,1)]:m.store(val,reg)
    cases.append(('brr16bit-wrap-maxpitch',m,[(1024,0,2),(1536,255,2),(1700,0,124)]))
    for tick in [65,97]:
        m=demo();m.store(1,92);m.store(1,76)
        cases.append((f'koff-kon-clear-at{tick}',m,[(tick,0,92)]))
    m=demo();m.ram[512]=193;m.store(255,61);m.store(31,108)
    cases.append(('nonloop-end-even-under-noise',m,[(1000,255,124),(1500,1,76)]))
    m=demo()
    for i in range(8):m.store(127,i*16+15)
    for reg,val in [(12,0),(28,0),(44,127),(60,127),(125,0),(108,32)]:m.store(val,reg)
    m.putword(16384,32766);m.putword(16386,-32768)
    cases.append(('fir-prefix-overflow',m,[]))
    cases.append(('offset17-render',demo(),[(17,64,12),(31,128,13),(32,31,108),(33,255,61),(1000,0,124)]))
    all_coverage=set()
    for label,m,events_for_case in cases:
        initial_regs=bytes(m.r);initial_ram=bytes(m.ram);start_tick=17 if label=='offset17-render' else 0
        m.advance(start_tick)
        for tick,val,reg in events_for_case:m.enqueue(val,reg,tick)
        expected=m.render(2048)
        with tempfile.TemporaryDirectory(dir=work) as tmp:
            pcm=Path(tmp)/'out.bin';ram=Path(tmp)/'ram.bin'
            prefix='SD-RESET\n'+''.join(f'{v} {i} 0 SD-REG!\n' for i,v in enumerate(initial_regs))+''.join(f'{v} {i} 0 SD-RAM!\n' for i,v in enumerate(initial_ram) if v)+(f'{start_tick} SD-TO\n' if start_tick else '')+queue(events_for_case)+'CREATE OUT 8192 ALLOT\n'
            if label=='demo':prefix='SD-DEMO-SETUP\nCREATE OUT 8192 ALLOT\n'
            for body in ['OUT 2048 SD-RENDER','OUT 13 SD-RENDER OUT 52 + 2035 SD-RENDER']:
                code=prefix+body+f' SNAP S" {pcm.as_posix()}" W/O CREATE-FILE THROW CONSTANT FD OUT 8192 FD WRITE-FILE THROW FD CLOSE-FILE THROW S" {ram.as_posix()}" W/O CREATE-FILE THROW CONSTANT RF SD-ARAM 65536 RF WRITE-FILE THROW RF CLOSE-FILE THROW'
                got=run(code);assert got[:266]==m.state(),(label,[(i,a,b) for i,(a,b) in enumerate(zip(got[:266],m.state())) if a!=b][:12]);assert got[266:]==[len(events_for_case)]*2
                assert pcm.read_bytes()==expected,(label,'PCM');assert ram.read_bytes()==m.ram,(label,'ARAM')
        all_coverage.update(m.coverage)
        tests.append({'case':label+'-full2048frames-state-aram-split','pcm_sha256':hashlib.sha256(expected).hexdigest(),'oracle_branches':sorted(m.coverage)})
    assert all_coverage>={'nonloop-end','pitch-high-mask','pmon-clamp','multiple-consume','echo-16bit-wrap','echo-dir-overlap','echo-brr-overlap','fir-prefix-wrap'},all_coverage
    error_cases=[('256 0 0 SD-REG!',-24),('256 12 999 SD-REG!',-24),('256 65535 999 SD-RAM!',-24),('1 128 0 SD-REG!',-24),('128 999 SD-REG@',-24),('1 65536 0 SD-RAM!',-24),('65536 999 SD-RAM@',-24),('-1 SD-TO',-24),('-1 SD-RUN',-24),('1 12 50 SD-REG-EVENT!',-24),('0 12 -1 SD-REG-EVENT!',-24),('OUT -1 SD-RENDER',-24)]
    for body,error in error_cases:
        code='SD-DEMO-SETUP 0 12 100 SD-REG-EVENT! CREATE QB 24576 ALLOT CREATE RB 65536 ALLOT CREATE OUT 4 ALLOT SD-EVENTS QB 24576 MOVE SD-ARAM RB 65536 MOVE SNAP : BAD '+body+" ; ' BAD CATCH . SNAP SD-EVENTS 24576 QB 24576 COMPARE . SD-ARAM 65536 RB 65536 COMPARE ."
        got=run(code);assert got[268]==error and got[:268]==got[269:537] and got[537:]==[0,0],(body,got[268],got[-2:])
    assert run('SD-RESET 7 12 0 SD-REG-EVENT! -1 0 SD-RENDER 12 SD-R@ . SD-SAMPLE . . 0 SD-RUN 12 SD-R@ .')==[0,0,0,7]
    fill='SD-RESET : FILLQ 1024 0 DO I 255 AND 12 I SD-REG-EVENT! LOOP ; FILLQ '
    assert run(fill+": BAD 2 12 0 SD-REG-EVENT! ; ' BAD CATCH . 512 SD-TO 7 12 1024 SD-REG-EVENT! SD-EVENT-COUNT @ . SD-EVENT-INDEX @ . 1024 SD-TO 12 SD-R@ .")==[-528,512,0,7]
    got=run("SD-DEMO-SETUP 9223372036854775775 SD-CYCLE ! CREATE OUT 8 ALLOT OUT 8 42 FILL SNAP : BAD OUT 2 SD-RENDER ; ' BAD CATCH . SNAP OUT C@ . OUT 7 + C@ . OUT 1 SD-RENDER SD-CYCLE @ .")
    assert got[268]==-24 and got[:268]==got[269:537] and got[537:]==[42,42,9223372036854775807]
    assert run("SD-RESET 9223372036854775791 SD-CYCLE ! : BAD 17 SD-RUN ; ' BAD CATCH . SD-CYCLE @ .")==[-24,9223372036854775791]
    assert run("SD-RESET : BAD -1 1 SD-RENDER ; ' BAD CATCH . SD-CYCLE @ . SD-FRAME @ .")==[-9,32,1]
    tests.append({'case':'error-atomicity-entire-aram-queue-capacity-reclaim-time-and-memory','atomic_cases':len(error_cases)})
    files=['examples/snes-dsp-audio.fs','examples/snes-gauss.fs','examples/snes-dsp-audio-play.fs','scripts/snes-tables.py','scripts/snes-gauss-data.json','tests/scripts/verify-snes-dsp-audio.py']
    if args.native:files+=['src/core/sound_snes_dsp.zig','src/core/words_snes_dsp.zig','src/core/snes_gauss.zig','examples/snes-dsp-native-backend.fs','examples/snes-dsp-audio-native.fs']
    print(json.dumps({'scope':__doc__,'platform':platform.platform(),'backend':'native' if args.native else 'forth','binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'tests':tests,'source_sha256_lf':{f:hashlib.sha256((ROOT/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in files}},indent=2))
if __name__=='__main__':main()
