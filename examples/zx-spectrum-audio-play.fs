\ Explicit mono wrapper; load alone is silent, FALSE submits zeros.
S" examples/zx-spectrum-audio-demo.fs" REQUIRED
S" examples/pcm-synth-play.fs" INCLUDED
\ Publish a full ring initially: the host may render eight 480-frame buffers
\ back-to-back. Keep subsequent production in 512-frame blocks.
CREATE ZX-PRIME 8192 ALLOT
: ZX-PRIME-SEND { frames -- }
  0 PS-SENT !
  BEGIN frames PS-SENT @ - DUP 0> WHILE
    DUP PS-REQUEST ! ZX-PRIME PS-SENT @ 2 * + SWAP PS-HANDLE @ PCM-WRITE THROW
    1 PS-WRITES +!
    DUP 0= IF 1 PS-FULL +! THEN
    DUP 0> IF DUP PS-REQUEST @ < IF 1 PS-PARTIAL +! THEN THEN
    DUP PS-FRAMES +! PS-SENT +!
    PS-SENT @ frames < IF
      1 PS-WAITS +! 1 1000 PS-HANDLE @ PCM-WAIT THROW 0= IF -528 THROW THEN
    THEN
  REPEAT DROP ;
: ZX-STREAM-RUN { | initial -- }
  ZX-RATE 1 4096 PCM-OPEN THROW PS-HANDLE !
  PS-BLOCKS @ 8 MIN TO initial
  initial IF
    ZX-PRIME initial 512 * ZX-RENDER
    PS-AUDIBLE @ 0= IF ZX-PRIME initial 1024 * 0 FILL THEN
    initial 512 * ZX-PRIME-SEND
  THEN
  PS-BLOCKS @ initial - 0 ?DO
    PS-BUFFER 512 ZX-RENDER
    PS-AUDIBLE @ 0= IF PS-BUFFER 1024 0 FILL THEN PS-SEND
  LOOP
  1 1000 PS-HANDLE @ PCM-STOP THROW 0= IF -528 THROW THEN
  PS-HANDLE @ PCM-UNDERRUNS THROW PS-UNDERRUN-COUNT ! ;
: ZX-STREAM ( blocks audible -- )
  OVER 0< IF -24 THROW THEN PS-HANDLE @ IF -528 THROW THEN
  OVER ZX-MAX-FRAMES 512 / > IF -24 THROW THEN
  PS-AUDIBLE ! PS-BLOCKS !
  0 PS-WRITES ! 0 PS-PARTIAL ! 0 PS-FULL ! 0 PS-WAITS !
  0 PS-FRAMES ! 0 PS-UNDERRUN-COUNT !
  ['] ZX-STREAM-RUN CATCH >R PS-SAFE-CLEANUP
  R> ?DUP IF SWAP DROP THROW THEN THROW ;
