#!/usr/bin/env python3
"""Owned stereo callback fixtures: nonzero model output stays in memory, no native audio."""
import argparse,hashlib,json,subprocess,tempfile
from pathlib import Path
if not __debug__:raise SystemExit("Verification requires assertions; do not use -O.")
ROOT=Path(__file__).resolve().parents[2]
PREFIX='''REQUIRE-AUDIO ALSO AUDIO DEFINITIONS
VARIABLE MC-WRITES VARIABLE MC-WAITS VARIABLE MC-CLOSES VARIABLE MC-LEFT
VARIABLE MC-WAIT-FAIL VARIABLE MC-CLOSE-FAIL VARIABLE MC-OPEN-FAIL VARIABLE MC-CLOSE-THROW
VARIABLE MC-STOP-FAIL VARIABLE MC-COPIED-FRAMES VARIABLE MC-FOLLOW-FAIL
CREATE MC-ADDR 64 ALLOT CREATE MC-COPIED 24576 ALLOT
: PCM-OPEN { rate channels capacity -- handle ior }
  rate 32000 <> channels 2 <> OR capacity 4096 <> OR IF -24 THROW THEN
  MC-OPEN-FAIL @ IF 0 -528 ELSE 7 0 THEN ;
: PCM-WRITE { address frames id | accepted -- written ior }
  address MC-WRITES @ CELLS MC-ADDR + !
  MC-FOLLOW-FAIL @ MC-WRITES @ 3 = AND IF TRUE MC-WAIT-FAIL ! 1 MC-WRITES +! 0 0 EXIT THEN
  MC-WRITES @ CASE 0 OF frames 5 MIN ENDOF 1 OF 0 ENDOF frames SWAP ENDCASE TO accepted
  address MC-COPIED MC-COPIED-FRAMES @ 4 * + accepted 4 * MOVE
  accepted MC-COPIED-FRAMES +! accepted NEGATE MC-LEFT +! 1 MC-WRITES +! accepted 0 ;
: PCM-WAIT DROP 2DROP 1 MC-WAITS +! MC-WAIT-FAIL @ IF FALSE ELSE TRUE THEN 0 ;
: PCM-STOP DROP 2DROP MC-STOP-FAIL @ IF FALSE ELSE TRUE THEN 0 ;
: PCM-UNDERRUNS DROP 0 0 ;
: PCM-CLOSE DROP 1 MC-CLOSES +! MC-CLOSE-THROW @ IF -265 THROW THEN MC-CLOSE-FAIL @ ;
: MC-SUM 0 2048 0 DO MC-COPIED I + C@ + LOOP ;
S" examples/snes-dsp-audio-play.fs" INCLUDED
SD-DEMO-SETUP
'''
CASES=[('stereo-partial-full-byte-copy',
  '512 MC-LEFT ! 1 TRUE SD-STREAM MC-LEFT @ . MC-WRITES @ . MC-WAITS @ . MC-CLOSES @ . PS-HANDLE @ . MC-ADDR '
  '@ SD-PRIME - . MC-ADDR CELL+ @ SD-PRIME - . MC-ADDR 2 CELLS + @ SD-PRIME - . MC-COPIED 2048 SD-PRIME '
  '2048 COMPARE . MC-SUM 0> . PS-FRAMES @ .',
  '0 3 2 1 0 0 20 20 0 -1 512'),
 ('noise-stereo-partial-full-byte-copy',
  'SD-DEMO-SETUP 255 61 0 SD-REG! 31 108 0 SD-REG! 512 MC-LEFT ! 1 TRUE SD-STREAM MC-LEFT @ . MC-WRITES @ . MC-WAITS @ . MC-CLOSES @ . '
  'PS-HANDLE @ . MC-ADDR @ SD-PRIME - . MC-ADDR CELL+ @ SD-PRIME - . MC-ADDR 2 CELLS + @ SD-PRIME - . '
  'MC-COPIED 2048 SD-PRIME 2048 COMPARE . MC-SUM 0> . PS-FRAMES @ .',
  '0 3 2 1 0 0 20 20 0 -1 512'),
 ('full-ring-prime-partial-copy',
  '4096 MC-LEFT ! 8 TRUE SD-STREAM MC-LEFT @ . MC-WRITES @ . MC-WAITS @ . MC-CLOSES @ . PS-HANDLE @ . '
  'MC-ADDR @ SD-PRIME - . MC-ADDR CELL+ @ SD-PRIME - . MC-ADDR 2 CELLS + @ SD-PRIME - . '
  'MC-COPIED 16384 SD-PRIME 16384 COMPARE . PS-FRAMES @ .',
  '0 3 2 1 0 0 20 20 0 4096'),
 ('prime-and-following-block-copy',
  '4608 MC-LEFT ! 9 TRUE SD-STREAM MC-LEFT @ . MC-WRITES @ . MC-WAITS @ . '
  'MC-COPIED 16384 SD-PRIME 16384 COMPARE . MC-COPIED 16384 + 2048 SD-BUFFER 2048 COMPARE . '
  'MC-ADDR 3 CELLS + @ SD-BUFFER - . PS-FRAMES @ . PS-HANDLE @ .',
  '0 4 2 0 0 0 4608 0'),
 ('silent-prime-and-following-block',
  '9 FALSE SD-STREAM : SUMALL 0 18432 0 DO MC-COPIED I + C@ + LOOP ; SUMALL . PS-FRAMES @ . PS-HANDLE @ .',
  '0 4608 0'),
 ('zero-block-no-render-or-write',
  'SD-CYCLE @ 0 TRUE SD-STREAM SD-CYCLE @ = . MC-WRITES @ . MC-CLOSES @ . PS-FRAMES @ . PS-HANDLE @ .',
  '-1 0 1 0 0'),
 ('prime-exact-clock-limit-success',
  'SD-RESET 9223372036854644735 SD-CYCLE ! 8 FALSE SD-STREAM '
  '9223372036854775807 SD-CYCLE @ - . PS-FRAMES @ . PS-HANDLE @ .',
  '0 4096 0'),
 ('8voice-prime-boundary-matches-monolithic-render',
  'CREATE EXPECT 18432 ALLOT VARIABLE END-T VARIABLE END-F '
  'SD-DEMO-SETUP EXPECT 4608 SD-RENDER SD-CYCLE @ END-T ! SD-DIV @ END-F ! '
  'SD-DEMO-SETUP 9 TRUE SD-STREAM EXPECT 18432 MC-COPIED 18432 COMPARE . '
  'END-T @ SD-CYCLE @ = . END-F @ SD-DIV @ = . PS-FRAMES @ . PS-HANDLE @ .',
  '0 -1 -1 4608 0'),
 ('noise-prime-boundary-matches-monolithic-render',
  'CREATE EXPECT 18432 ALLOT VARIABLE END-T VARIABLE END-F '
  'SD-DEMO-SETUP 255 61 0 SD-REG! 31 108 0 SD-REG! EXPECT 4608 SD-RENDER SD-CYCLE @ END-T ! SD-DIV @ END-F ! '
  'SD-DEMO-SETUP 255 61 0 SD-REG! 31 108 0 SD-REG! 9 TRUE SD-STREAM EXPECT 18432 MC-COPIED 18432 COMPARE . '
  'END-T @ SD-CYCLE @ = . END-F @ SD-DIV @ = . PS-FRAMES @ . PS-HANDLE @ .',
  '0 -1 -1 4608 0'),
 ('following-block-wait-timeout-closes',
  "TRUE MC-FOLLOW-FAIL ! : GO 9 FALSE SD-STREAM ; ['] GO CATCH . PS-FRAMES @ . MC-WRITES @ . MC-WAITS @ . MC-CLOSES @ . PS-HANDLE @ .",
  '-528 4096 4 3 1 0'),
 ('timeout-closes',
  "TRUE MC-WAIT-FAIL ! : GO 1 FALSE SD-STREAM ; ['] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .",
  '-528 1 0'),
 ('close-retry',
  "-516 MC-CLOSE-FAIL ! : GO 1 FALSE SD-STREAM ; ['] GO CATCH . PS-HANDLE @ . 0 MC-CLOSE-FAIL ! PS-CLEANUP . "
  'PS-HANDLE @ .',
  '-516 7 0 0'),
 ('primary-error-retained',
  "TRUE MC-WAIT-FAIL ! -516 MC-CLOSE-FAIL ! : GO 1 FALSE SD-STREAM ; ['] GO CATCH . PS-HANDLE @ .",
  '-528 7'),
 ('cleanup-throw-retains-primary',
  "TRUE MC-WAIT-FAIL ! TRUE MC-CLOSE-THROW ! : GO 1 FALSE SD-STREAM ; ['] GO CATCH . PS-HANDLE @ .",
  '-528 7'),
 ('cleanup-throw-propagates',
  "TRUE MC-CLOSE-THROW ! : GO 1 FALSE SD-STREAM ; ['] GO CATCH . PS-HANDLE @ .",
  '-265 7'),
 ('open-busy-no-close',
  "TRUE MC-OPEN-FAIL ! : GO 1 FALSE SD-STREAM ; ['] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .",
  '-528 0 0'),
 ('drain-timeout-closes',
  "TRUE MC-STOP-FAIL ! : GO 1 FALSE SD-STREAM ; ['] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .",
  '-528 1 0'),
 ('stream-overflow-before-open',
  "9223372036854775307 SD-CYCLE ! : GO 1 FALSE SD-STREAM ; ['] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .",
  '-24 0 0'),
 ('active-handle-not-stolen',
  "7 PS-HANDLE ! : GO 1 FALSE SD-STREAM ; ['] GO CATCH . MC-CLOSES @ . PS-HANDLE @ .",
  '-528 0 7')]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('sigma',type=Path);p.add_argument('--native',action='store_true');args=p.parse_args();binary=args.sigma.resolve();work=ROOT/'.work/1174';work.mkdir(parents=True,exist_ok=True);results=[]
 for name,code,expected in CASES:
  with tempfile.NamedTemporaryFile('w',encoding='utf-8',suffix='.fs',dir=work,delete=False) as f:path=Path(f.name);f.write((PREFIX.replace('examples/snes-dsp-audio-play.fs','examples/snes-dsp-audio-native-play.fs') if args.native else PREFIX)+code+' DEPTH . BYE\n')
  try:q=subprocess.run([str(binary),str(path)],cwd=ROOT,input=b'',capture_output=True,timeout=20)
  finally:path.unlink()
  clean=' '.join(line for line in q.stdout.decode().splitlines() if not line.startswith('WARNING:')).strip()
  assert q.returncode==0 and not q.stderr and clean==expected+' 0',(name,q.returncode,clean,q.stderr)
  results.append({'case':name,'result':clean})
 files=['tests/scripts/verify-snes-dsp-audio-stream.py','include/snes-dsp-audio.fs','include/snes-gauss.fs','examples/snes-dsp-audio-play.fs','examples/pcm-synth-play.fs','examples/pcm-synth.fs']
 if args.native:files+=['src/core/sound_snes_dsp.zig','src/core/words_snes_dsp.zig','src/core/snes_gauss.zig','include/snes-dsp-native-backend.fs','include/snes-dsp-audio-native.fs','examples/snes-dsp-audio-native-play.fs']
 print(json.dumps({'scope':__doc__,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'tests':results,'source_sha256_lf':{f:hashlib.sha256((ROOT/f).read_bytes().replace(b'\r\n',b'\n')).hexdigest() for f in files}},indent=2))
if __name__=='__main__':main()
