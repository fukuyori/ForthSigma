\ The NES's sound (tque 1190): the 2A03's APU (NTSC), four voices mixed with its
\ formulas (MIXER 1: voices 1 and 2 the pulses, 3 the triangle, 4 the noise), 11-bit
\ timers, 16 volume steps, and duties in eighths.
\
\   REQUIRE nes-sound.fs  NES-SOUND
\   1 INSTRUMENT NES-TRIANGLE  2 INSTRUMENT NES-NOISE
\   S" O5 L8 CEGE" S" O5 L8 EGBG" S" @1 O3 L4 CG" S" @2 O2 L8 CCCC" 4 PLAYS
\
\ The noise's period is any of 4 to 4068, not only the chip's 16.
S" ./chip-sound.fs" REQUIRED
REQUIRE-AUDIO
GET-CURRENT ALSO AUDIO DEFINITIONS
DECIMAL

1789773000 CONSTANT NES-CLOCK
CREATE NES-LEVELS
  0 , 4369 , 8738 , 13107 , 17476 , 21845 , 26214 , 30583 ,
  34952 , 39321 , 43690 , 48059 , 52428 , 56797 , 61166 , 65535 ,
CREATE (NES-TRI-LEVELS) 65535 ,
\ The triangle's 32 steps, 15 down to 0 and up again.
CREATE (NES-TRI-WAVE)
  32767 , 28398 , 24029 , 19660 , 15291 , 10922 , 6553 , 2184 ,
  -2184 , -6553 , -10922 , -15291 , -19660 , -24029 , -28398 , -32767 ,
  -32767 , -28398 , -24029 , -19660 , -15291 , -10922 , -6553 , -2184 ,
  2184 , 6553 , 10922 , 15291 , 19660 , 24029 , 28398 , 32767 ,

\ A pulse's steps: periods 8 to 2047 of clock / 16 (timer + 1), 16 levels, duties in
\ eighths.
: NES-STEPS ( -- )
  NES-CLOCK 16 1 8 2047 PITCH-PERIOD  NES-LEVELS 16 VOLUME-STEPS  8 DUTY-STEPS
  0 INTERPOLATION  0 NOISE-RATE  15 1 NOISE-LFSR ;
: NES-PULSE ( -- )   PULSE NES-STEPS ;
\ The triangle: its 32 steps at clock / 32, at full volume whatever V says (it has no
\ volume of its own).
: NES-TRIANGLE ( -- )
  (NES-TRI-WAVE) 32 WAVETABLE  NES-STEPS
  NES-CLOCK 32 1 2 2047 PITCH-PERIOD  (NES-TRI-LEVELS) 1 VOLUME-STEPS  0 DUTY-STEPS ;
: NES-NOISE ( -- )
  NOISE NES-STEPS  NES-CLOCK 16 0 4 4068 PITCH-PERIOD  0 DUTY-STEPS ;
: NES-SOUND ( -- )
  (STANDARD-GLOBALS)  4 VOICE-LIMIT  1 MIXER  ['] NES-STEPS (EACH-INSTRUMENT) ;
PREVIOUS SET-CURRENT
