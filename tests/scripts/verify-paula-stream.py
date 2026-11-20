#!/usr/bin/env python3
"""Stereo callback fixtures and hand-derived attachment checks; no native audio."""
import argparse,hashlib,json,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PREFIX='''REQUIRE-AUDIO ALSO AUDIO DEFINITIONS
VARIABLE MC-WRITES VARIABLE MC-WAITS VARIABLE MC-CLOSES VARIABLE MC-LEFT
VARIABLE MC-WAIT-FAIL VARIABLE MC-CLOSE-FAIL VARIABLE MC-OPEN-FAIL VARIABLE MC-CLOSE-THROW
VARIABLE MC-STOP-FAIL VARIABLE MC-COPIED-FRAMES
CREATE MC-ADDR 64 ALLOT CREATE MC-COPIED 2048 ALLOT
: PCM-OPEN { rate channels capacity -- handle ior }
  rate 48000 <> channels 2 <> OR capacity 4096 <> OR IF -24 THROW THEN
  MC-OPEN-FAIL @ IF 0 -528 ELSE 7 0 THEN ;
: PCM-WRITE { address frames id | accepted -- written ior }
  address MC-WRITES @ CELLS MC-ADDR + !
  MC-WRITES @ CASE 0 OF frames 5 MIN ENDOF 1 OF 0 ENDOF frames SWAP ENDCASE TO accepted
  address MC-COPIED MC-COPIED-FRAMES @ 4 * + accepted 4 * MOVE
  accepted MC-COPIED-FRAMES +! accepted NEGATE MC-LEFT +! 1 MC-WRITES +! accepted 0 ;
: PCM-WAIT DROP 2DROP 1 MC-WAITS +! MC-WAIT-FAIL @ IF FALSE ELSE TRUE THEN 0 ;
: PCM-STOP DROP 2DROP MC-STOP-FAIL @ IF FALSE ELSE TRUE THEN 0 ;
: PCM-UNDERRUNS DROP 0 0 ;
: PCM-CLOSE DROP 1 MC-CLOSES +! MC-CLOSE-THROW @ IF -265 THROW THEN MC-CLOSE-FAIL @ ;
: MC-SUM 0 2048 0 DO MC-COPIED I + C@ + LOOP ;
S" examples/paula-play.fs" INCLUDED
PA-DEMO-MEMORY PA-DEMO-SETUP
'''
CASES=[
 ('hand-odd-length-block-restarts-with-volume','PA-RESET 0 0 PA-MEM! 64 1 PA-MEM! 0 2 PA-MEM! 123 3 PA-MEM! 0 4 PA-MEM! 32 5 PA-MEM! 3 164 0 PA-WRITE 123 166 0 PA-WRITE 32785 158 0 PA-WRITE 33281 150 0 PA-WRITE 493 PA-TO 1 8 PA@ . 1 7 PA@ . 0 10 PA@ . 739 PA-TO 1 8 PA@ . 1 7 PA@ . 0 10 PA@ . 985 PA-TO 1 8 PA@ . 1 7 PA@ . 0 10 PA@ . PA-PER-CLAMPS @ .','32 123 0 64 123 1 64 123 0 0'),
 ('hand-attachment-alternation-and-block-restart','PA-RESET 0 0 PA-MEM! 64 1 PA-MEM! 0 2 PA-MEM! 123 3 PA-MEM! 0 4 PA-MEM! 32 5 PA-MEM! 0 6 PA-MEM! 124 7 PA-MEM! 4 164 0 PA-WRITE 123 166 0 PA-WRITE 32785 158 0 PA-WRITE 33281 150 0 PA-WRITE 1 PA-TO 1 8 PA@ . 1 7 PA@ . 0 10 PA@ . 247 PA-TO 1 8 PA@ . 1 7 PA@ . 0 10 PA@ . 493 PA-TO 1 8 PA@ . 1 7 PA@ . 0 10 PA@ . 739 PA-TO 1 8 PA@ . 1 7 PA@ . 0 10 PA@ . 985 PA-TO 1 8 PA@ . 1 7 PA@ . 0 10 PA@ .','64 65536 1 64 123 0 32 123 1 32 124 0 64 124 1'),
 ('stereo-partial-full-offset-and-byte-copy','512 MC-LEFT ! 1 TRUE PA-STREAM MC-LEFT @ . MC-WRITES @ . MC-WAITS @ . MC-CLOSES @ . PS-HANDLE @ . MC-ADDR @ PA-BUFFER - . MC-ADDR CELL+ @ PA-BUFFER - . MC-ADDR 2 CELLS + @ PA-BUFFER - . MC-COPIED 2048 PA-BUFFER 2048 COMPARE . MC-SUM 0> . PS-FRAMES @ .','0 3 2 1 0 0 20 20 0 -1 512'),
 ('timeout-cleanup',"TRUE MC-WAIT-FAIL ! : GO 1 FALSE PA-STREAM ; ['] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .",'-528 1 0'),
 ('close-retry',"-516 MC-CLOSE-FAIL ! : GO 1 FALSE PA-STREAM ; ['] GO CATCH . PS-HANDLE @ . 0 MC-CLOSE-FAIL ! PS-CLEANUP . PS-HANDLE @ .",'-516 7 0 0'),
 ('primary-error-retained',"TRUE MC-WAIT-FAIL ! -516 MC-CLOSE-FAIL ! : GO 1 FALSE PA-STREAM ; ['] GO CATCH . PS-HANDLE @ .",'-528 7'),
 ('cleanup-throw-retains-primary',"TRUE MC-WAIT-FAIL ! TRUE MC-CLOSE-THROW ! : GO 1 FALSE PA-STREAM ; ['] GO CATCH . PS-HANDLE @ .",'-528 7'),
 ('cleanup-throw-propagates',"TRUE MC-CLOSE-THROW ! : GO 1 FALSE PA-STREAM ; ['] GO CATCH . PS-HANDLE @ .",'-265 7'),
 ('open-busy-no-close',"TRUE MC-OPEN-FAIL ! : GO 1 FALSE PA-STREAM ; ['] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .",'-528 0 0'),
 ('drain-timeout-closes',"TRUE MC-STOP-FAIL ! : GO 1 FALSE PA-STREAM ; ['] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .",'-528 1 0')]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);args=p.parse_args();binary=args.sigma.resolve();work=ROOT/'.work/1137';results=[]
 for name,code,expected in CASES:
  with tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.fs',dir=work,delete=False) as f:
   path=Path(f.name);f.write(PREFIX+code+' DEPTH . BYE\n')
  try:q=subprocess.run([str(binary),str(path)],cwd=ROOT,input=b'',capture_output=True,timeout=20)
  finally:path.unlink()
  clean=' '.join(line for line in q.stdout.decode().splitlines() if not line.startswith('WARNING:')).strip()
  assert q.returncode==0 and not q.stderr and clean==expected+' 0',(name,q.returncode,clean,q.stderr)
  results.append({'case':name,'result':clean})
 print(json.dumps({'scope':__doc__,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'tests':results,'source_sha256_lf':{f:hashlib.sha256((ROOT/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in ['tests/scripts/verify-paula-stream.py','examples/paula-play.fs','include/paula.fs','examples/pcm-synth-play.fs','examples/pcm-synth.fs']}},indent=2))
if __name__=='__main__':main()
