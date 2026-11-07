\ A short tour of FORTH/Sigma's sound: one tune on each chip, the MSX's PSG and the
\ SCC together, and a sound effect made with SAMPLE.
\
\   sigma.exe "include examples/music.fs"      (Windows)
\   sigma "include examples/music.fs"          (Linux: pacat, pw-play, or aplay plays it)

REQUIRE-AUDIO
ALSO AUDIO
DECIMAL

: WAIT-MUSIC ( -- )   BEGIN 0 PLAY? WHILE 10 MS REPEAT ;
: TITLE ( c-addr u -- )   CR TYPE ;

\ ---- The tune: a melody, a bass, and a counter-melody ----------------------------

: MELODY ( -- c-addr u )   S" T140 L8 O4 EGA>C<AGE4 DEGEDC4. R8" ;
: BASS ( -- c-addr u )     S" T140 L4 O2 CGCG FCG>C<" ;
: SECOND ( -- c-addr u )   S" T140 L4 O3 EEEE FFGE" ;
\ The NES's noise voice: O3 C is its lowest sound, O4 D# its highest.
: DRUMS ( -- c-addr u )    S" T140 L8 O3 C O4 D# O4 D# O4 D# O3 C O4 D# O4 D# O4 D# O3 C O4 D# O4 D# O4 D# O3 C O4 D# O3 C O3 C" ;

\ ---- The chips ----------------------------------------------------------------

: ON-MSX ( -- )
   S" MSX: the AY-3-8910 of MSX BASIC" TITLE
   MSX-SOUND  MELODY BASS SECOND PLAY3  WAIT-MUSIC ;

: ON-ST ( -- )
   S" Atari ST: the YM2149, with an envelope on the melody" TITLE
   ST-SOUND
   S" T140 L8 O4 S8 M600 EGA>C<AGE4 DEGEDC4. R8" BASS SECOND PLAY3  WAIT-MUSIC ;

\ A voice's instrument is the first command of its string: WITH-INSTRUMENT puts
\ "@n " (n 1 to 9) before a tune, in one of four buffers (slot 0 to 3), so that the
\ same tune can be played with other instruments.
CREATE TUNES 4 256 * ALLOT
: WITH-INSTRUMENT ( c-addr u n slot -- c-addr2 u2 )
   256 * TUNES +  >R                                   ( c-addr u n )
   [CHAR] 0 + R@ 1+ C!  [CHAR] @ R@ C!  BL R@ 2 + C!   ( c-addr u )
   TUCK  R@ 3 +  SWAP MOVE                             ( u )
   R> SWAP 3 + ;

: ON-NES ( -- )
   S" NES: two pulses, a triangle, and the noise as drums" TITLE
   NES-SOUND
   1 INSTRUMENT PULSE 25 DUTY 0 3 10 3 ADSR
   2 INSTRUMENT PULSE 12 DUTY 0 2 8 2 ADSR
   3 INSTRUMENT 0 3 0 2 ADSR
   MELODY 1 0 WITH-INSTRUMENT  SECOND 2 1 WITH-INSTRUMENT  BASS  DRUMS 3 3 WITH-INSTRUMENT
   4 PLAYS  WAIT-MUSIC ;

: ON-C64 ( -- )
   S" C64: a sawtooth through the low-pass filter, a pulse, and a ring-modulated triangle" TITLE
   C64-SOUND
   1 INSTRUMENT SAW 0 6 10 4 ADSR 1 700 10 FILTER
   2 INSTRUMENT PULSE 30 DUTY 0 4 8 4 ADSR
   3 INSTRUMENT TRIANGLE TRUE RING 0 2 12 4 ADSR
   MELODY 1 0 WITH-INSTRUMENT  BASS 2 1 WITH-INSTRUMENT  SECOND 3 2 WITH-INSTRUMENT
   PLAY3  WAIT-MUSIC ;

\ A wave of 32 signed bytes for the SCC: one round of a sine, roughly.
CREATE SINE-WAVE
   0 C, 25 C, 49 C, 71 C, 90 C, 106 C, 117 C, 125 C, 127 C, 125 C, 117 C, 106 C,
   90 C, 71 C, 49 C, 25 C, 0 C, 231 C, 207 C, 185 C, 166 C, 150 C, 139 C, 131 C,
   129 C, 131 C, 139 C, 150 C, 166 C, 185 C, 207 C, 231 C,

: ON-SCC ( -- )
   S" SCC: five voices of 32-sample waves" TITLE
   SCC-SOUND
   SINE-WAVE 1 SCC-WAVE  1 INSTRUMENT 0 4 12 4 ADSR
   2 INSTRUMENT SAW
   MELODY 1 0 WITH-INSTRUMENT  SECOND 2 1 WITH-INSTRUMENT  BASS
   S" T140 L2 O4 C E F G" S" T140 L1 O2 C C"  5 PLAYS  WAIT-MUSIC ;

: ON-AMIGA ( -- )
   S" Amiga: Paula's four voices, left, right, right, left" TITLE
   AMIGA-SOUND
   1 INSTRUMENT TRIANGLE 0 4 12 6 ADSR
   2 INSTRUMENT SAW
   MELODY 1 0 WITH-INSTRUMENT  BASS 2 1 WITH-INSTRUMENT  SECOND  S" T140 L1 O3 G G"
   4 PLAYS  WAIT-MUSIC ;

: ON-MSX-AND-SCC ( -- )
   S" The MSX's PSG and the SCC together, as on Konami's cartridges" TITLE
   MSX SCC OR CHIPS
   SINE-WAVE 1 SCC-WAVE
   MELODY BASS SECOND  MELODY 1 0 WITH-INSTRUMENT  SECOND  S" " S" " S" "
   8 PLAYS  WAIT-MUSIC ;

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

: ZAPS ( -- )
   S" A sound effect made with SAMPLE, three times over the music" TITLE
   MAKE-ZAP  ZAP ZAP-LENGTH 8000 0 SAMPLE
   MSX-SOUND  MELODY BASS SECOND PLAY3
   3 0 DO  0 SFX 600 MS  LOOP
   WAIT-MUSIC ;

: TOUR ( -- )
   ON-MSX ON-ST ON-NES ON-C64 ON-SCC ON-AMIGA ON-MSX-AND-SCC ZAPS
   MSX-SOUND CR ;

TOUR
