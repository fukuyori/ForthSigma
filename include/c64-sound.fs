\ The C64's sound (tque 1190): the SID on a PAL machine, three voices, its 16-bit
\ frequency register (985248 Hz x n / 2^24), 12-bit pulse widths, and its 23-bit noise.
\
\   REQUIRE c64-sound.fs  C64-SOUND  SAW 10 300 40000 400 ADSR  S" O4 L8 CEGB>C" PLAY
\
\ C64-FILTER gives the chosen instrument the SID's filter from its registers' values:
\   1 INSTRUMENT SAW  1 600 8 C64-FILTER      \ low-pass, cutoff 600 of 2047, resonance 8
\ To move it while a note sounds, set it again and name the instrument with VOICE-HOLD.
\
\ Notes above the 16-bit register's 3849 Hz still sound, the noise is one bit (not the
\ SID's eight), and each voice has its own filter (the SID has one for the voices sent
\ to it), without the 6581's distortion.
S" ./chip-sound.fs" REQUIRED
REQUIRE-AUDIO
GET-CURRENT ALSO AUDIO DEFINITIONS
DECIMAL

985248000 CONSTANT C64-CLOCK
\ MML's V as V / 15.
CREATE (C64-V)
  0 , 4369 , 8738 , 13107 , 17476 , 21845 , 26214 , 30583 ,
  34952 , 39321 , 43690 , 48059 , 52428 , 56797 , 61166 , 65535 ,
: C64-STEPS ( -- )
  C64-CLOCK 24 PITCH-STEP  0 0 VOLUME-STEPS  4096 DUTY-STEPS  0 INTERPOLATION
  0 NOISE-RATE  23 5 NOISE-LFSR  (C64-V) 16 V-STEPS ;
\ The SID's mode bits (1 low-pass, 2 band-pass, 4 high-pass, added) as FILTER's modes.
CREATE (C64-MODES) 0 C, 1 C, 2 C, 5 C, 3 C, 4 C, 6 C, 7 C,
\ The filter of the chosen instrument: mode is the SID's bits (0 to 7), cutoff its 11
\ bits (0 to 2047, here 30 Hz and 5.8 Hz a step), resonance its 4 bits (0 to 15).
: C64-FILTER ( mode cutoff resonance -- )
  DUP 0 16 WITHIN 0= IF -24 THROW THEN
  OVER 0 2048 WITHIN 0= IF -24 THROW THEN
  2 PICK 0 8 WITHIN 0= IF -24 THROW THEN
  80 * 586 + 65535 * 1980 /  >R
  58 * 10 / 30 +  >R
  (C64-MODES) + C@  R> R> FILTER ;
: C64-SOUND ( -- )   (STANDARD-GLOBALS)  3 VOICE-LIMIT  ['] C64-STEPS (EACH-INSTRUMENT) ;
PREVIOUS SET-CURRENT
