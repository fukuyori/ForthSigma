\ Explicit PCM wrapper. Run from repository root; load alone is silent.
\ sigma tests/audio/nes-apu-play.fs -e "NA-DEMO-SETUP 96 FALSE NA-STREAM BYE"
\ TRUE submits the unfiltered waveform; FALSE synthesizes then sends zeros.
S" tests/audio/nes-apu-demo.fs" REQUIRED
S" tests/audio/pcm-synth-play.fs" INCLUDED
: NA-STREAM-RUN ( -- )
  NA-RATE 1 4096 PCM-OPEN THROW PS-HANDLE !
  PS-BLOCKS @ 0 ?DO
    PS-BUFFER 512 NA-RENDER
    PS-AUDIBLE @ 0= IF PS-BUFFER 1024 0 FILL THEN
    PS-SEND
  LOOP
  1 1000 PS-HANDLE @ PCM-STOP THROW 0= IF -528 THROW THEN
  PS-HANDLE @ PCM-UNDERRUNS THROW PS-UNDERRUN-COUNT ! ;
: NA-STREAM ( blocks audible -- )
  OVER 0< IF -24 THROW THEN
  PS-HANDLE @ IF -528 THROW THEN
  PS-AUDIBLE ! PS-BLOCKS !
  0 PS-WRITES ! 0 PS-PARTIAL ! 0 PS-FULL ! 0 PS-WAITS !
  0 PS-FRAMES ! 0 PS-UNDERRUN-COUNT !
  ['] NA-STREAM-RUN CATCH >R PS-SAFE-CLEANUP
  R> ?DUP IF SWAP DROP THROW THEN THROW ;
