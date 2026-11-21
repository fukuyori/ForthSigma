\ Konami's SCC (tque 1190): five voices of 32-sample waves (SCC-WAVE) at
\ 3579545 / (32 x (period + 1)) Hz, 16 volume steps, the samples played as steps.
\
\   REQUIRE scc-sound.fs  SCC-SOUND
\   CREATE W 32 ALLOT  ( fill W with 32 signed bytes )  W 1 SCC-WAVE
\   S" @1 O4 L8 CEGB>C" PLAY
S" ./chip-sound.fs" REQUIRED
REQUIRE-AUDIO
GET-CURRENT ALSO AUDIO DEFINITIONS
DECIMAL

3579545000 CONSTANT SCC-CLOCK
CREATE SCC-LEVELS
  0 , 4369 , 8738 , 13107 , 17476 , 21845 , 26214 , 30583 ,
  34952 , 39321 , 43690 , 48059 , 52428 , 56797 , 61166 , 65535 ,
CREATE (SCC-CELLS) 32 CELLS ALLOT
: SCC-STEPS ( -- )
  SCC-CLOCK 32 1 0 4095 PITCH-PERIOD  SCC-LEVELS 16 VOLUME-STEPS  0 DUTY-STEPS
  0 INTERPOLATION  0 NOISE-RATE  15 1 NOISE-LFSR ;
: SCC-SOUND ( -- )   (STANDARD-GLOBALS)  5 VOICE-LIMIT  ['] SCC-STEPS (EACH-INSTRUMENT) ;
\ Instrument n plays the 32 signed bytes at c-addr as its wave, with the SCC's steps;
\ it is chosen afterwards. Each call takes 32 places of the pool.
: SCC-WAVE ( c-addr n -- )
  INSTRUMENT
  32 0 DO  DUP I + C@  DUP 127 > IF 256 - THEN  256 *  (SCC-CELLS) I CELLS + !  LOOP  DROP
  (SCC-CELLS) 32 WAVETABLE  SCC-STEPS ;
PREVIOUS SET-CURRENT
