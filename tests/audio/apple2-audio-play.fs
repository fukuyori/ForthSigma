\ Explicit stereo wrapper; load alone is silent, FALSE submits zeros.
S" tests/audio/apple2-audio-demo.fs" REQUIRED
S" tests/audio/pcm-synth-play.fs" INCLUDED
\ Publish a full ring initially: the host may render eight 480-frame buffers
\ back-to-back. Keep subsequent production in 512-frame blocks.
CREATE A2-PRIME 16384 ALLOT
CREATE A2-BUFFER 2048 ALLOT
: A2-SEND { address frames -- }
  0 PS-SENT !
  BEGIN frames PS-SENT @ - DUP 0> WHILE
    DUP PS-REQUEST ! address PS-SENT @ 4 * + SWAP PS-HANDLE @ PCM-WRITE THROW
    1 PS-WRITES +!
    DUP 0= IF 1 PS-FULL +! THEN
    DUP 0> IF DUP PS-REQUEST @ < IF 1 PS-PARTIAL +! THEN THEN
    DUP PS-FRAMES +! PS-SENT +!
    PS-SENT @ frames < IF
      1 PS-WAITS +! 1 1000 PS-HANDLE @ PCM-WAIT THROW 0= IF -528 THROW THEN
    THEN
  REPEAT DROP ;
: A2-STREAM-RUN { | initial -- }
  A2-RATE 2 4096 PCM-OPEN THROW PS-HANDLE !
  PS-BLOCKS @ 8 MIN TO initial
  initial IF
    A2-PRIME initial 512 * A2-RENDER
    PS-AUDIBLE @ 0= IF A2-PRIME initial 2048 * 0 FILL THEN
    A2-PRIME initial 512 * A2-SEND
  THEN
  PS-BLOCKS @ initial - 0 ?DO
    A2-BUFFER 512 A2-RENDER
    PS-AUDIBLE @ 0= IF A2-BUFFER 2048 0 FILL THEN A2-BUFFER 512 A2-SEND
  LOOP
  1 1000 PS-HANDLE @ PCM-STOP THROW 0= IF -528 THROW THEN
  PS-HANDLE @ PCM-UNDERRUNS THROW PS-UNDERRUN-COUNT ! ;
: A2-STREAM ( blocks audible -- )
  OVER 0< IF -24 THROW THEN PS-HANDLE @ IF -528 THROW THEN
  OVER A2-MAX-FRAMES 512 / > IF -24 THROW THEN
  PS-AUDIBLE ! PS-BLOCKS !
  0 PS-WRITES ! 0 PS-PARTIAL ! 0 PS-FULL ! 0 PS-WAITS !
  0 PS-FRAMES ! 0 PS-UNDERRUN-COUNT !
  ['] A2-STREAM-RUN CATCH >R PS-SAFE-CLEANUP
  R> ?DUP IF SWAP DROP THROW THEN THROW ;
