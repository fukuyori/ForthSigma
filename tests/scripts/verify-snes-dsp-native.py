#!/usr/bin/env python3
"""Native S-DSP batches, backend changes, bounded interruption and saved execution tokens. No audio/timing."""
import argparse,hashlib,importlib.util,json,platform,subprocess,tempfile
from pathlib import Path
if not __debug__:raise SystemExit('Verification requires assertions; do not use -O.')
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('sd',ROOT/'tests/scripts/verify-snes-dsp-audio.py');sd=importlib.util.module_from_spec(spec);spec.loader.exec_module(sd)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);p.add_argument('--no-debug',action='store_true');a=p.parse_args();binary=a.sigma.resolve();folder=ROOT/'.work/1183';folder.mkdir(exist_ok=True,parents=True);tests=[]
 with tempfile.TemporaryDirectory(dir=folder,prefix='native-fixture-') as tmp:
  tmp=Path(tmp);pcm=tmp/'pcm.bin';ram=tmp/'ram.bin';source=tmp/'run.fs'
  def run(code,exe=binary,entry=True):
   source.write_text((sd.DUMP if entry else '')+code+'\nDEPTH . BYE\n',encoding='utf-8')
   r=subprocess.run([str(exe),*(['examples/snes-dsp-audio-native-demo.fs'] if entry else []),str(source)],input=b'',capture_output=True,cwd=ROOT,timeout=90)
   assert r.returncode==0 and not r.stderr,(r.returncode,r.stdout[:1200],r.stderr)
   values=list(map(int,r.stdout.split()));assert values.pop()==0,values[-5:];return values
  def save_ram():return f'S" {ram.as_posix()}" W/O CREATE-FILE THROW CONSTANT RF SD-ARAM 65536 RF WRITE-FILE THROW RF CLOSE-FILE THROW '
  def check(model,values):assert values==model.state()+[0,0],[(i,x,y) for i,(x,y) in enumerate(zip(values,model.state()+[0,0])) if x!=y][:8];assert ram.read_bytes()==model.ram
  assert run("SD-FRAMES-XT @ ' SD-NATIVE-FRAMES = .")==[-1]
  for offset in [0,17,31]:
   m=sd.demo();m.advance(offset);m.advance(32768+offset)
   values=run(f'SD-DEMO-SETUP {offset} SD-TO 32768 SD-RUN SNAP '+save_ram());check(m,values)
  tests.append({'case':'1024-frame-native-batches-divider0-17-31-full-state-and-ARAM'})
  m=sd.demo();expected=m.render(400)
  code='SD-DEMO-SETUP CREATE OUT 1600 ALLOT OUT 100 SD-RENDER SD-USE-FORTH OUT 400 + 100 SD-RENDER SD-USE-NATIVE OUT 800 + 100 SD-RENDER SD-USE-FORTH OUT 1200 + 100 SD-RENDER SNAP '+save_ram()+f'S" {pcm.as_posix()}" W/O CREATE-FILE THROW CONSTANT PF OUT 1600 PF WRITE-FILE THROW PF CLOSE-FILE THROW '
  check(m,run(code));assert pcm.read_bytes()==expected
  assert run('SD-RESET SD-FRAMES-XT @ 0<> . SD-USE-FORTH SD-RESET SD-FRAMES-XT @ . SD-USE-NATIVE SD-RESET SD-FRAMES-XT @ 0<> .')==[-1,0,-1]
  tests.append({'case':'native-forth-native-forth400frames-fullPCM-state-ARAM-reset-retains-selection'})
  if not a.no_debug:
   # Limit stops inside one native batch; queue entry stays pending until target reached.
   m=sd.demo();values=run("REQUIRE-EXTENSION ALSO EXTENSION SD-DEMO-SETUP 99 12 32768 SD-REG-EVENT! : GO 32768 SD-TO ; ' GO 300 EXEC-LIMITED . SNAP "+save_ram())
   assert values[0]==-280;state=values[1:];k=state[128+112+2];assert 0<k<1024
   m.advance(k*32);assert state[:266]==m.state() and state[266:]==[1,0];assert ram.read_bytes()==m.ram
   m=sd.demo();m.enqueue(99,12,32768);m.to(32768)
   values=run("REQUIRE-EXTENSION ALSO EXTENSION SD-DEMO-SETUP 99 12 32768 SD-REG-EVENT! : GO 32768 SD-TO ; ' GO 300 EXEC-LIMITED DROP 32768 SD-TO SNAP "+save_ram())
   assert values==m.state()+[1,1];assert ram.read_bytes()==m.ram
   tests.append({'case':'EXEC-LIMITED-native-batch-completed-progress-python-queue-and-resume','completed_frames':k})
  app=tmp/('saved.exe' if platform.system()=='Windows' else 'saved')
  assert run(f"SD-DEMO-SETUP : NATIVE? SD-FRAMES-XT @ ['] SD-NATIVE-FRAMES = 0= IF -24 THROW THEN ; NATIVE? SAVESYS {app.as_posix()}")==[]
  m=sd.demo();m.advance(32768)
  values=run('NATIVE? 32768 SD-RUN SNAP '+save_ram(),app,False);check(m,values)
  tests.append({'case':'SAVESYS-selected-native-execution-token-roundtrip-full-state-and-ARAM'})
 files=['tests/scripts/verify-snes-dsp-audio.py','scripts/snes-gauss-data.json','include/snes-gauss.fs','tests/scripts/verify-snes-dsp-native.py','include/snes-dsp-audio.fs','include/snes-dsp-native-backend.fs','include/snes-dsp-audio-native.fs','src/core/sound_snes_dsp.zig','src/core/words_snes_dsp.zig','src/core/snes_gauss.zig']
 print(json.dumps({'scope':__doc__,'platform':platform.platform(),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'tests':tests,'source_sha256_lf':{f:hashlib.sha256((ROOT/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in files}},indent=2))
if __name__=='__main__':main()
