\ The common part of the chip libraries (tque 1190, 4 of docs/SOUND_CORE_DESIGN_STUDY.md).
\ The chips' character is made of the standard sound's own words (PITCH-PERIOD,
\ VOLUME-STEPS, VOICE-LIMIT and the others); the words go into the AUDIO vocabulary.
\ Clocks are in 1/1000 Hz.
REQUIRE-AUDIO
GET-CURRENT ALSO AUDIO DEFINITIONS
DECIMAL

\ The standard sound's steps on the chosen instrument: none of a chip's.
: STANDARD-STEPS ( -- )
  0 1 0 1 1 PITCH-PERIOD  0 0 VOLUME-STEPS  0 DUTY-STEPS  0 INTERPOLATION
  0 NOISE-RATE  15 1 NOISE-LFSR ;

\ Runs xt on each of the 64 instruments, chosen one after another; instrument 0 is
\ chosen after it.
: (EACH-INSTRUMENT) ( xt -- )
  64 0 DO  I INSTRUMENT  DUP EXECUTE  LOOP  DROP  0 INSTRUMENT ;

\ The settings of all the voices together as they are at start.
: (STANDARD-GLOBALS) ( -- )
  8 VOICE-LIMIT  0 MIXER  0 0 OUTPUT-BITS  0 1000 MASTER-FILTER  0 1000 MOD-FILTER ;

\ Back to the standard sound: no chip's steps on any instrument, and the settings of
\ all the voices as at start (the waves and envelopes stay).
: STANDARD-SOUND ( -- )   (STANDARD-GLOBALS)  ['] STANDARD-STEPS (EACH-INSTRUMENT) ;
PREVIOUS SET-CURRENT
