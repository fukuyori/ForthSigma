#!/usr/bin/env python3
"""Owned mono callback fixtures: nonzero model output stays in memory, no native audio."""
import argparse,hashlib,json,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PREFIX='''REQUIRE-AUDIO ALSO AUDIO DEFINITIONS
VARIABLE MC-WRITES VARIABLE MC-WAITS VARIABLE MC-CLOSES VARIABLE MC-LEFT
VARIABLE MC-WAIT-FAIL VARIABLE MC-CLOSE-FAIL VARIABLE MC-OPEN-FAIL VARIABLE MC-CLOSE-THROW
VARIABLE MC-STOP-FAIL VARIABLE MC-COPIED-FRAMES
CREATE MC-ADDR 64 ALLOT CREATE MC-COPIED 1024 ALLOT
: PCM-OPEN { rate channels capacity -- handle ior }
  rate 48000 <> channels 1 <> OR capacity 4096 <> OR IF -24 THROW THEN
  MC-OPEN-FAIL @ IF 0 -528 ELSE 7 0 THEN ;
: PCM-WRITE { address frames id | accepted -- written ior }
  address MC-WRITES @ CELLS MC-ADDR + !
  MC-WRITES @ CASE 0 OF frames 5 MIN ENDOF 1 OF 0 ENDOF frames SWAP ENDCASE TO accepted
  address MC-COPIED MC-COPIED-FRAMES @ 2 * + accepted 2 * MOVE
  accepted MC-COPIED-FRAMES +! accepted NEGATE MC-LEFT +! 1 MC-WRITES +! accepted 0 ;
: PCM-WAIT DROP 2DROP 1 MC-WAITS +! MC-WAIT-FAIL @ IF FALSE ELSE TRUE THEN 0 ;
: PCM-STOP DROP 2DROP MC-STOP-FAIL @ IF FALSE ELSE TRUE THEN 0 ;
: PCM-UNDERRUNS DROP 0 0 ;
: PCM-CLOSE DROP 1 MC-CLOSES +! MC-CLOSE-THROW @ IF -265 THROW THEN MC-CLOSE-FAIL @ ;
: MC-SUM 0 1024 0 DO MC-COPIED I + C@ + LOOP ;
S" examples/ym2149-play.fs" INCLUDED
YM-DEMO-SETUP
'''
CASES=[
 ('relative-render-clock-after-immediate-write-and-to','CREATE OUT 8 ALLOT 15 8 1000 YM-WRITE OUT 1 YM-RENDER YM-CYCLE @ . YM-FRACTION @ . 2000 YM-TO OUT 1 YM-RENDER YM-CYCLE @ . YM-FRACTION @ . OUT 1 YM-RENDER YM-CYCLE @ . YM-FRACTION @ .','1041 32000 2042 16000 2084 0'),
 ('pure-queries-only-see-applied-events','YM-RESET 0 0 0 YM-INPUT-EVENT! 0 YM-PIN@ . 0 YM-RUN 0 YM-PIN@ .','255 0'),
 ('bus-read-both-ports-input-and-output','YM-RESET 165 14 0 YM-WRITE 90 0 0 YM-INPUT! 14 YM-SELECT-ADDRESS 0 YM-BUS! YM-SELECT-ADDRESS 0 YM-BUS@ . 64 7 0 YM-WRITE YM-SELECT-ADDRESS 0 YM-BUS@ . 15 YM-SELECT-ADDRESS 0 YM-BUS! 240 YM-DATA-ADDRESS 0 YM-BUS! 60 1 0 YM-INPUT! YM-SELECT-ADDRESS 0 YM-BUS@ . 192 7 0 YM-WRITE YM-SELECT-ADDRESS 0 YM-BUS@ .','90 0 60 48'),
 ('declared-reset-envelope-state-before-shape-write','YM-RESET 255 7 0 YM-WRITE 16 8 0 YM-WRITE 13 0 YM-READ . YM-ENV-LEVEL . YM-SAMPLE . 0 13 0 YM-WRITE 8 YM-TO YM-ENV-LEVEL .','0 31 10922 30'),
 ('mono-partial-full-byte-copy','512 MC-LEFT ! 1 TRUE YM-STREAM MC-LEFT @ . MC-WRITES @ . MC-WAITS @ . MC-CLOSES @ . PS-HANDLE @ . MC-ADDR @ PS-BUFFER - . MC-ADDR CELL+ @ PS-BUFFER - . MC-ADDR 2 CELLS + @ PS-BUFFER - . MC-COPIED 1024 PS-BUFFER 1024 COMPARE . MC-SUM 0> . PS-FRAMES @ .','0 3 2 1 0 0 10 10 0 -1 512'),
 ('timeout-closes',"TRUE MC-WAIT-FAIL ! : GO 1 FALSE YM-STREAM ; ['] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .",'-528 1 0'),
 ('close-retry',"-516 MC-CLOSE-FAIL ! : GO 1 FALSE YM-STREAM ; ['] GO CATCH . PS-HANDLE @ . 0 MC-CLOSE-FAIL ! PS-CLEANUP . PS-HANDLE @ .",'-516 7 0 0'),
 ('primary-error-retained',"TRUE MC-WAIT-FAIL ! -516 MC-CLOSE-FAIL ! : GO 1 FALSE YM-STREAM ; ['] GO CATCH . PS-HANDLE @ .",'-528 7'),
 ('cleanup-throw-retains-primary',"TRUE MC-WAIT-FAIL ! TRUE MC-CLOSE-THROW ! : GO 1 FALSE YM-STREAM ; ['] GO CATCH . PS-HANDLE @ .",'-528 7'),
 ('cleanup-throw-propagates',"TRUE MC-CLOSE-THROW ! : GO 1 FALSE YM-STREAM ; ['] GO CATCH . PS-HANDLE @ .",'-265 7'),
 ('open-busy-no-close',"TRUE MC-OPEN-FAIL ! : GO 1 FALSE YM-STREAM ; ['] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .",'-528 0 0'),
 ('drain-timeout-closes',"TRUE MC-STOP-FAIL ! : GO 1 FALSE YM-STREAM ; ['] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .",'-528 1 0')]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);args=p.parse_args();binary=args.sigma.resolve();work=ROOT/'.work/1138';work.mkdir(parents=True,exist_ok=True);results=[]
 for name,code,expected in CASES:
  with tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.fs',dir=work,delete=False) as f:path=Path(f.name);f.write(PREFIX+code+' DEPTH . BYE\n')
  try:q=subprocess.run([str(binary),str(path)],cwd=ROOT,input=b'',capture_output=True,timeout=20)
  finally:path.unlink()
  clean=' '.join(line for line in q.stdout.decode().splitlines() if not line.startswith('WARNING:')).strip()
  assert q.returncode==0 and not q.stderr and clean==expected+' 0',(name,q.returncode,clean,q.stderr)
  results.append({'case':name,'result':clean})
 files=['tests/scripts/verify-ym2149-stream.py','examples/ym2149.fs','examples/ym2149-levels.fs','examples/ym2149-play.fs','examples/pcm-synth-play.fs','examples/pcm-synth.fs']
 print(json.dumps({'scope':__doc__,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'tests':results,'source_sha256_lf':{f:hashlib.sha256((ROOT/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in files}},indent=2))
if __name__=='__main__':main()
