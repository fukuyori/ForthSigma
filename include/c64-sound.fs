\ The C64's sound (tque 1190): the SID on a PAL machine, three voices, its 16-bit
\ frequency register (985248 Hz x n / 2^24), 12-bit pulse widths, and its 23-bit noise.
\
\   REQUIRE c64-sound.fs  C64-SOUND  SAW 10 300 40000 400 ADSR  S" O4 L8 CEGB>C" PLAY
\
\ Notes above the 16-bit register's 3849 Hz still sound, the noise is one bit (not the
\ SID's eight), and the filter is not made.
S" ./chip-sound.fs" REQUIRED
REQUIRE-AUDIO
GET-CURRENT ALSO AUDIO DEFINITIONS
DECIMAL

985248000 CONSTANT C64-CLOCK
: C64-STEPS ( -- )
  C64-CLOCK 24 PITCH-STEP  0 0 VOLUME-STEPS  4096 DUTY-STEPS  0 INTERPOLATION
  0 NOISE-RATE  23 5 NOISE-LFSR ;
: C64-SOUND ( -- )   (STANDARD-GLOBALS)  3 VOICE-LIMIT  ['] C64-STEPS (EACH-INSTRUMENT) ;
PREVIOUS SET-CURRENT
