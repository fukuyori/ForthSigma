\ A short tour of FORTH/Sigma's sound: one tune with the standard sound, with the steps
\ of each chip that the libraries in include/ have, with several chips in one PLAY, and
\ a sound effect made with SAMPLE.
\
\   sigma.exe examples/music.fs      (Windows)
\   sigma examples/music.fs          (Linux: pacat, pw-play, or aplay plays it;
\                                     macOS: AudioToolbox)

REQUIRE-AUDIO
REQUIRE chips.fs                        \ MSX-SOUND and the like, STYLE, SCC-WAVE
ALSO AUDIO
DECIMAL

: WAIT-MUSIC ( -- )   BEGIN 0 PLAY? WHILE 10 MS REPEAT ;
: TITLE ( c-addr u -- )   CR TYPE ;

\ ---- The tune: a melody, a bass, and a counter-melody ----------------------------

: MELODY ( -- c-addr u )   S" T140 L8 O4 EGA>C<AGE4 DEGEDC4. R8" ;
: BASS ( -- c-addr u )     S" T140 L4 O2 CGCG FCG>C<" ;
: SECOND ( -- c-addr u )   S" T140 L4 O3 EEEE FFGE" ;
\ Drums for a noise, which shifts 16 times in a cycle of its note: O1 C is a low
\ rumble, O8 B a hiss.
: DRUMS ( -- c-addr u )    S" T140 L8 O1 C O8 B O8 B O8 B O1 C O8 B O8 B O8 B O1 C O8 B O8 B O8 B O1 C O8 B O1 C O1 C" ;

\ A voice keeps its instrument and its volume from one PLAY to the next, so a PLAY of
\ commands alone sets them for the tune that follows. An instrument keeps what it was
\ given too, so each part of the tour has instruments of its own; instrument 0 stays a
\ square.
: PLAIN3 ( -- )   S" @0 V8" 2DUP 2DUP PLAY3 ;

\ ---- The standard sound -----------------------------------------------------------

\ Sixteen voices with no chip's steps: a pulse with a vibrato on the left, a sawtooth
\ through a low-pass in the middle, and a triangle on the right, with some reverb.
: ON-STANDARD ( -- )
   S" The standard sound: a pulse with vibrato, a filtered sawtooth, and a triangle, with reverb" TITLE
   STANDARD-SOUND
   10 INSTRUMENT PULSE 16384 DUTY  5 120 40000 200 ADSR  12 6 150 VIBRATO
                 65535 16384 VOICE-PAN  24000 REVERB-SEND
   11 INSTRUMENT SAW  1 1500 24000 FILTER
   12 INSTRUMENT TRIANGLE  16384 65535 VOICE-PAN  24000 REVERB-SEND
   150 24000 40000 REVERB
   S" @10 V12" S" @11 V11" S" @12 V12" PLAY3
   MELODY BASS SECOND PLAY3  WAIT-MUSIC  600 MS
   0 0 0 REVERB ;

\ ---- The chips ----------------------------------------------------------------

: ON-MSX ( -- )
   S" MSX: the AY-3-8910 of MSX BASIC" TITLE
   MSX-SOUND  PLAIN3  MELODY BASS SECOND PLAY3  WAIT-MUSIC ;

: ON-ST ( -- )
   S" Atari ST: the YM2149, with an envelope on the melody" TITLE
   ST-SOUND  PLAIN3
   S" T140 L8 O4 S8 M600 EGA>C<AGE4 DEGEDC4. R8" BASS SECOND PLAY3  WAIT-MUSIC ;

: ON-NES ( -- )
   S" NES: two pulses, a triangle, and the noise as drums" TITLE
   NES-SOUND
   20 INSTRUMENT NES-PULSE 16384 DUTY  2 72 43690 108 ADSR
   21 INSTRUMENT NES-PULSE 8192 DUTY  2 48 34952 72 ADSR
   22 INSTRUMENT NES-TRIANGLE
   23 INSTRUMENT NES-NOISE  2 108 0 72 ADSR
   S" @20 V8" S" @21 V8" S" @22" S" @23 V8" 4 PLAYS
   MELODY SECOND BASS DRUMS 4 PLAYS  WAIT-MUSIC ;

\ RING takes the voice that modulates: here voice 2, the pulse.
: ON-C64 ( -- )
   S" C64: a sawtooth through a low-pass filter, a pulse, and a ring-modulated triangle" TITLE
   C64-SOUND
   30 INSTRUMENT SAW  2 204 43690 171 ADSR  1 4090 45874 FILTER
   31 INSTRUMENT PULSE 19661 DUTY  2 114 34952 171 ADSR
   32 INSTRUMENT TRIANGLE  2 RING  2 48 52428 171 ADSR
   S" @30 V8" S" @31 V8" S" @32 V8" PLAY3
   MELODY BASS SECOND PLAY3  WAIT-MUSIC ;

\ A wave of 32 signed bytes for the SCC: one round of a sine, roughly.
CREATE SINE-WAVE
   0 C, 25 C, 49 C, 71 C, 90 C, 106 C, 117 C, 125 C, 127 C, 125 C, 117 C, 106 C,
   90 C, 71 C, 49 C, 25 C, 0 C, 231 C, 207 C, 185 C, 166 C, 150 C, 139 C, 131 C,
   129 C, 131 C, 139 C, 150 C, 166 C, 185 C, 207 C, 231 C,

\ SCC-WAVE leaves its instrument chosen.
: ON-SCC ( -- )
   S" SCC: five voices, one with a wave of 32 samples" TITLE
   SCC-SOUND
   SINE-WAVE 40 SCC-WAVE  2 114 52428 171 ADSR
   41 INSTRUMENT SAW
   S" @40 V8" S" @41 V8" S" @0 V8" 2DUP 2DUP 5 PLAYS
   MELODY SECOND BASS S" T140 L2 O4 C E F G" S" T140 L1 O2 C C"  5 PLAYS  WAIT-MUSIC ;

\ Paula puts its voices left, right, right, left; here the instruments do, one for
\ each voice.
: ON-AMIGA ( -- )
   S" Amiga: Paula's four voices, left, right, right, left" TITLE
   AMIGA-SOUND
   50 INSTRUMENT TRIANGLE  2 114 52428 306 ADSR  65535 0 VOICE-PAN
   51 INSTRUMENT SAW  0 65535 VOICE-PAN
   52 INSTRUMENT 0 65535 VOICE-PAN
   53 INSTRUMENT 65535 0 VOICE-PAN
   S" @50 V8" S" @51 V8" S" @52 V8" S" @53 V8" 4 PLAYS
   MELODY BASS SECOND  S" T140 L1 O3 G G"  4 PLAYS  WAIT-MUSIC ;

\ STYLE gives one instrument a chip's steps, so the voices of one PLAY can sound like
\ different chips. STANDARD-SOUND takes the chips' steps from every instrument and
\ gives all eight voices back.
: ON-MSX-AND-SCC ( -- )
   S" The MSX's PSG and the SCC together, as on Konami's cartridges" TITLE
   STANDARD-SOUND
   42 INSTRUMENT MSX STYLE
   40 INSTRUMENT SCC STYLE                 \ the sine of before
   43 INSTRUMENT SCC STYLE
   S" @42 V8" 2DUP 2DUP S" @40 V8" S" @43 V8" 5 PLAYS
   MELODY BASS SECOND  MELODY SECOND  5 PLAYS  WAIT-MUSIC ;

\ The NES's triangle and noise have words of their own, which also set their steps.
: ON-EVERY-CHIP ( -- )
   S" Any voice, any chip: the NES, the SCC, and the C64 in one PLAY" TITLE
   STANDARD-SOUND
   1 INSTRUMENT PULSE NES STYLE  16384 DUTY  2 72 43690 108 ADSR
   2 INSTRUMENT SAW SCC STYLE  2 114 52428 171 ADSR
   3 INSTRUMENT SAW C64 STYLE  2 204 43690 171 ADSR  1 4090 45874 FILTER
   4 INSTRUMENT NES-TRIANGLE
   5 INSTRUMENT NES-NOISE  2 108 0 72 ADSR
   S" @1 V8" S" @2 V8" S" @4" S" @5 V8" S" @3 V8" 5 PLAYS
   MELODY SECOND BASS DRUMS  S" T140 L2 O3 C E F G"  5 PLAYS  WAIT-MUSIC ;

\ ---- A sound effect ------------------------------------------------------------

\ A falling "zap": a square wave whose period grows, fading out, 0.5 s at 8000 Hz.
4000 CONSTANT ZAP-LENGTH
CREATE ZAP ZAP-LENGTH ALLOT
: MAKE-ZAP ( -- )
   ZAP-LENGTH 0 DO
      I  I 200 / 4 +  /  1 AND IF 100 ELSE -100 THEN   \ the square
      ZAP-LENGTH I - *  ZAP-LENGTH /                    \ fading out
      ZAP I + C!
   LOOP ;

\ SFX has voices of its own (9 to 12), beside PLAY's.
: ZAPS ( -- )
   S" A sound effect made with SAMPLE, three times over the music" TITLE
   MAKE-ZAP  ZAP ZAP-LENGTH 8000 0 SAMPLE
   MSX-SOUND  PLAIN3  MELODY BASS SECOND PLAY3
   3 0 DO  0 SFX 600 MS  LOOP
   WAIT-MUSIC ;

: TOUR ( -- )
   ON-STANDARD ON-MSX ON-ST ON-NES ON-C64 ON-SCC ON-AMIGA ON-MSX-AND-SCC ON-EVERY-CHIP ZAPS
   STANDARD-SOUND CR ;

TOUR
