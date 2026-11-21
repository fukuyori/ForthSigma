\ The MSX's sound (tque 1190): the AY-3-8910 at 1789773 Hz, three voices, 16 volume
\ steps, and SOUND, which writes the PSG's registers as MSX BASIC's SOUND does.
\
\   REQUIRE msx-sound.fs  MSX-SOUND  S" T150 O4 CDEFGAB>C" PLAY
\   7 56 SOUND  8 15 SOUND  0 254 SOUND      \ voice 1 at about 440 Hz
\
\ SOUND plays on voices 1 to 3 (PLAY's first three) with instruments 61 to 63, which it
\ chooses with INSTRUMENT on the way; a PLAY, BEEP, or stop takes those voices back, and
\ the next SOUND sounds them again. The envelope's shortest ramp is 1 ms, and the
\ channels' envelopes and noises go on their own, not as one that the PSG shares.
S" ./chip-sound.fs" REQUIRED
REQUIRE-AUDIO
GET-CURRENT ALSO AUDIO DEFINITIONS
DECIMAL

1789773000 CONSTANT MSX-CLOCK

\ The AY's 16 levels, from Matthew Westcott's measurement of an AY-3-8910 (2001, placed
\ in the public domain): 1.147 V to 2.58 V, less level 0's voltage, scaled to 65535.
CREATE AY-LEVELS
  0 , 686 , 1006 , 1418 , 2058 , 3018 , 4162 , 6951 ,
  8643 , 14177 , 19482 , 25610 , 33614 , 41754 , 53644 , 65535 ,

\ The PSG's steps on the chosen instrument, at clock: periods 1 to 4095 of clock / 16,
\ the AY's levels, and its 17-bit noise.
: AY-STEPS ( clock -- )
  16 0 1 4095 PITCH-PERIOD  AY-LEVELS 16 VOLUME-STEPS  0 DUTY-STEPS  0 INTERPOLATION
  0 NOISE-RATE  17 3 NOISE-LFSR ;
: MSX-STEPS ( -- )   MSX-CLOCK AY-STEPS ;

\ PLAY sounds like the MSX: three voices with the PSG's steps on every instrument.
: MSX-SOUND ( -- )   (STANDARD-GLOBALS)  3 VOICE-LIMIT  ['] MSX-STEPS (EACH-INSTRUMENT) ;

\ ---- SOUND: the PSG's registers -----------------------------------------------
\
\ Registers 0 to 13 as MSX BASIC starts them: tones on and noise off (R7 = 184).

CREATE PSG-REGS 16 ALLOT  PSG-REGS 16 ERASE  184 PSG-REGS 7 + C!
CREATE (PSG-CONFIG) 3 CELLS ALLOT  (PSG-CONFIG) 3 CELLS ERASE
VARIABLE (PSG-R13)
CREATE (PSG-ENV) 9 CELLS ALLOT

: (R@) ( reg -- byte )   PSG-REGS + C@ ;

\ Segment i of the envelope being made.
: (SEG) ( level ms curve i -- )
  3 * CELLS (PSG-ENV) + >R  R@ 2 CELLS + !  R@ CELL+ !  R> ! ;

\ The PSG's envelope of shape (R13) and period (R11, R12) as ENVELOPE's segments, as
\ MML's S and M make it: one ramp is 256 x period / 1789773 seconds.
: (PSG-ENVELOPE) { shape period | ms n loop -- }
  period 1 MAX 256000 * 894886 + 1789773 / 1 MAX TO ms
  -1 TO loop
  shape 15 AND CASE
    8 OF  65535 0 0 0 (SEG)  0 ms 1 1 (SEG)  2 TO n  0 TO loop  ENDOF
    10 OF  65535 0 0 0 (SEG)  0 ms 1 1 (SEG)  65535 ms 1 2 (SEG)  3 TO n  1 TO loop  ENDOF
    11 OF  65535 0 0 0 (SEG)  0 ms 1 1 (SEG)  65535 0 0 2 (SEG)  3 TO n  ENDOF
    12 OF  65535 ms 1 0 (SEG)  0 0 0 1 (SEG)  2 TO n  0 TO loop  ENDOF
    13 OF  65535 ms 1 0 (SEG)  1 TO n  ENDOF
    14 OF  65535 ms 1 0 (SEG)  0 ms 1 1 (SEG)  2 TO n  0 TO loop  ENDOF
    \ 4 to 7 and 15 go up once, then 0; the others (0 to 3, 9) down once.
    DUP 4 8 WITHIN OVER 15 = OR IF
      65535 ms 1 0 (SEG)  0 0 0 1 (SEG)
    ELSE
      65535 0 0 0 (SEG)  0 ms 1 1 (SEG)
    THEN  2 TO n
  ENDCASE
  (PSG-ENV) n loop -1 ENVELOPE ;

\ Channel c (0 to 2) on voice c+1 as the registers say. The instrument is set again,
\ and the note started anew, only when its settings change or R13 was written with the
\ envelope on; otherwise only the pitch and volume change.
: (PSG-CHANNEL) { c | period mode env level rate config -- }
  c 2* (R@)  c 2* 1+ (R@) 15 AND 256 * +  1 MAX TO period
  7 (R@) c RSHIFT 1 AND 0= 1 AND  7 (R@) c 3 + RSHIFT 1 AND 0= 2 AND  OR TO mode
  8 c + (R@) DUP 16 AND 0<> TO env  15 AND TO level
  MSX-CLOCK  6 (R@) 31 AND 1 MAX 16 *  / TO rate
  mode  env 4 AND OR
  env IF  13 (R@) 15 AND 4 LSHIFT OR  11 (R@) 12 (R@) 256 * + 8 LSHIFT OR  THEN
  mode 2 AND IF  rate 32 LSHIFT OR  THEN  TO config
  env 0= level 0= AND IF
    61 c +  0 0  c 1+ VOICE-HOLD  -1 (PSG-CONFIG) c CELLS + !  EXIT
  THEN
  \ Set again also when the voice is not sounding: instruments 61 to 63 may have been
  \ changed meanwhile.
  config (PSG-CONFIG) c CELLS + @ <>  env (PSG-R13) @ AND  OR  c 1+ VOICE-ON? 0=  OR IF
    61 c + INSTRUMENT  MSX-STEPS  rate NOISE-RATE
    mode CASE
      0 OF  SQUARE 0 NOISE-MIX  ENDOF
      1 OF  SQUARE 0 NOISE-MIX  ENDOF
      2 OF  NOISE  ENDOF
      3 OF  SQUARE 2 NOISE-MIX  ENDOF
    ENDCASE
    env IF  13 (R@)  11 (R@) 12 (R@) 256 * +  (PSG-ENVELOPE)  ELSE  0 0 -1 -1 ENVELOPE  THEN
    61 c +  0 0  c 1+ VOICE-HOLD
    config (PSG-CONFIG) c CELLS + !
  THEN
  \ With the tone and the noise both off the channel gives its volume as it is (the
  \ square at 0 Hz stays high); the envelope changes it.
  61 c +  mode 0= IF 0 ELSE MSX-CLOCK 16 period * / THEN
  env IF 65535 ELSE level CELLS AY-LEVELS + @ THEN
  c 1+ VOICE-HOLD ;

\ Writes value (0 to 255) to the PSG's register reg (0 to 13), as MSX BASIC's SOUND.
: SOUND ( reg value -- )
  OVER 0 14 WITHIN 0= IF -24 THROW THEN
  DUP 0 256 WITHIN 0= IF -24 THROW THEN
  OVER 13 = (PSG-R13) !
  SWAP PSG-REGS + C!
  3 0 DO  I (PSG-CHANNEL)  LOOP
  0 (PSG-R13) ! ;
PREVIOUS SET-CURRENT
