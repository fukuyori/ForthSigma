\ Sigma Storm: a vertical scrolling shooter for FORTH/Sigma. The stages, the pictures,
\ the tunes, and the rules are this file's own.
\
\   sigma.exe examples/shmup.fs     (in a window; Tk on Linux/macOS)
\
\ Three stages, each with its waves, a carrier half way, and a boss in parts.
\   Arrows or WASD   move
\   Z, Space, or J   fire (held)         F   fire by itself, on or off
\   C or L           slow, tight fire, and the ship's hit point shown (held)
\   X or K           bomb: clears the shots and hurts everything on the screen
\   P pause, F1 the frame times, Q or Esc back to the title and then out.
\ A mapped gamepad works too: the d-pad or the left stick moves, south fires, west or a
\ shoulder is slow, east bombs, start pauses.
\
\ Only the small core of the ship can be hit. Shots that pass close graze it for points.
\ P capsules raise the weapon to level 5, B capsules give a bomb, and gems are points.
\ Kills in quick succession raise the chain, which multiplies the score.
\
\ How it is drawn: the pictures are painted when the file loads and kept on a sheet,
\ each a sprite of the game words (REQUIRE-GAME) that DRAW-SPRITE copies; a shot hits
\ an enemy where their pictures' pixels meet (PIXEL-HIT?). Each stage's background is a
\ picture of color numbers with a palette (DRAW-INDEXED), whose water colors turn on the
\ ocean (ROTATE-PALETTE). Clouds are half seen, explosions, lasers, and shots glow by
\ adding their light, and a bomb or a boss blowing up ripples the rows of the screen
\ (RASTER-SCROLL). The game advances in fixed steps of 16 ms however fast the display
\ is, up to four steps a frame, so a slow display costs frames and not speed.

REQUIRE-GAME  ALSO GRAPHICS ALSO GAME

240 CONSTANT W   320 CONSTANT H
W H GFX-INIT

\ ---- Sound effects ----------------------------------------------------------------
\ Made with SAMPLE and played with SFX when the build has the audio words; a build
\ without them (-Daudio=false) plays silently.

: AUDIO-LOADED? ( -- flag )   S" REQUIRE-AUDIO" ['] EVALUATE CATCH  DUP IF NIP NIP THEN  0= ;
[DEFINED] NO-SOUND [IF] FALSE [ELSE] AUDIO-LOADED? [THEN] CONSTANT HAS-SOUND

0 CONSTANT S-SHOT   1 CONSTANT S-HIT    2 CONSTANT S-POP    3 CONSTANT S-BOOM
4 CONSTANT S-ITEM   5 CONSTANT S-POWER  6 CONSTANT S-BOMB   7 CONSTANT S-DIE
8 CONSTANT S-WARN   9 CONSTANT S-EXTEND 10 CONSTANT S-LASER 11 CONSTANT S-GRAZE
12 CONSTANT #SOUNDS

VARIABLE CLOCK                          \ counts every step of the game
CREATE SFX-LAST  #SOUNDS CELLS ALLOT    \ the step each sound last played

HAS-SOUND [IF]
ALSO AUDIO
8000 CONSTANT WAVE-RATE
CREATE WAVE  WAVE-RATE 2* ALLOT         \ room for two seconds of sound
VARIABLE WAVE-COUNT  VARIABLE WAVE-SIGN  VARIABLE WAVE-SEED
\ A square wave of n samples, amplitude amp; its half period starts at p samples and
\ changes by dp every 64 samples. It fades out.
: SWEEP { n p dp amp -- }
   0 WAVE-COUNT !  1 WAVE-SIGN !
   n 0 DO
      1 WAVE-COUNT +!
      WAVE-COUNT @  p I 64 / dp * +  2 MAX  >= IF  0 WAVE-COUNT !  WAVE-SIGN @ NEGATE WAVE-SIGN !  THEN
      WAVE-SIGN @ amp *  n I - *  n /  WAVE I + C!
   LOOP ;
\ Noise of n samples held for hold samples, the hold growing by dh every 256 samples:
\ a rumble that falls as it fades.
: RUMBLE { n hold dh amp | v -- }
   0 TO v  0 WAVE-COUNT !
   n 0 DO
      1 WAVE-COUNT +!
      WAVE-COUNT @  hold I 256 / dh * +  >= IF
         0 WAVE-COUNT !
         WAVE-SEED @ 1103515245 * 12345 + DUP WAVE-SEED !  16 RSHIFT 256 MOD 128 -  TO v
      THEN
      v amp *  100 /  n I - *  n /  WAVE I + C!
   LOOP ;
\ Two notes one after the other, for a two-tone siren.
: TWO-TONE { n p1 p2 amp -- }
   n 0 DO
      I n 2/ < IF p1 ELSE p2 THEN  I SWAP /  1 AND IF amp ELSE amp NEGATE THEN  WAVE I + C!
   LOOP ;
: KEEP ( n k -- )   >R WAVE SWAP WAVE-RATE R> SAMPLE ;
: MAKE-SOUNDS ( -- )
   500 5 1 26 SWEEP         500 S-SHOT KEEP
   200 14 0 34 SWEEP        200 S-HIT KEEP
   2400 3 1 100 RUMBLE      2400 S-POP KEEP
   7000 2 1 125 RUMBLE      7000 S-BOOM KEEP
   900 9 -1 70 SWEEP        900 S-ITEM KEEP
   2400 14 -2 80 SWEEP      2400 S-POWER KEEP
   12000 1 1 127 RUMBLE     12000 S-BOMB KEEP
   8000 10 3 110 SWEEP      8000 S-DIE KEEP
   8000 12 8 90 TWO-TONE    8000 S-WARN KEEP
   4000 6 -1 90 SWEEP       4000 S-EXTEND KEEP
   5000 30 -3 70 SWEEP      5000 S-LASER KEEP
   160 3 0 28 SWEEP         160 S-GRAZE KEEP ;
: PLAY-SFX ( k -- )   SFX ;
PREVIOUS
[ELSE]
: MAKE-SOUNDS ( -- ) ;
: PLAY-SFX ( k -- )   DROP ;
[THEN]

\ A sound, unless the same one played within the last few steps.
: EFFECT ( k -- )
   DUP CELLS SFX-LAST + @  CLOCK @ SWAP -  4 < IF DROP EXIT THEN
   CLOCK @ OVER CELLS SFX-LAST + !  PLAY-SFX ;

\ ---- Music ------------------------------------------------------------------------
\ Four tunes of this file's own on the NES's chip: a melody and an arpeggio on the two
\ pulses, a bass on the triangle, and drums on the noise. A tune goes a bar at a time
\ (80 fiftieths of a second; each bar has at most 8 notes a voice), and a new bar is
\ queued when less than one is left, so that PLAY never has to wait.

HAS-SOUND [IF]
ALSO AUDIO
: MUSIC-CHIP ( -- )   NES-SOUND ;
: SET-INSTRUMENTS ( -- )
   1 INSTRUMENT PULSE 25 DUTY 0 3 12 3 ADSR
   2 INSTRUMENT PULSE 12 DUTY 0 4 8 3 ADSR
   3 INSTRUMENT 0 2 0 1 ADSR ;
: BAR ( melody harmony bass drums -- )   4 PLAYS ;
PREVIOUS
[ELSE]
: MUSIC-CHIP ( -- ) ;
: SET-INSTRUMENTS ( -- ) ;
: BAR ( melody harmony bass drums -- )   2DROP 2DROP 2DROP 2DROP ;
[THEN]

: DR-A  S" T150 L8 O3 @3 V12 C O4 D# O3 G O4 D# O3 C C G O4 D#" ;
: DR-B  S" T150 L8 O3 @3 V13 C C G C C C G G" ;
: BS-A  S" T150 L8 O2 AA>A<A AA>A<A" ;
: BS-F  S" T150 L8 O2 FF>F<F FF>F<F" ;
: BS-G  S" T150 L8 O2 GG>G<G GG>G<G" ;
: BS-E  S" T150 L8 O2 EE>E<E EE>E<E" ;
: BS-D  S" T150 L8 O2 DD>D<D DD>D<D" ;
: BS-C  S" T150 L8 O3 CC>C<C CC>C<C" ;
: BS-AS S" T150 L8 O2 A#A#>A#<A# A#A#>A#<A#" ;
: BS-B  S" T150 L8 O2 BB>B<B BB>B<B" ;
: AR-AM S" T150 L8 O4 @2 V7 EA>CE<A>CE<A" ;
: AR-F  S" T150 L8 O4 @2 V7 CFA>C<FA>C<F" ;
: AR-G  S" T150 L8 O4 @2 V7 DGB>D<GB>D<G" ;
: AR-EM S" T150 L8 O4 @2 V7 EGB>E<GB>E<G" ;
: AR-DM S" T150 L8 O4 @2 V7 DFA>D<FA>D<F" ;
: AR-E  S" T150 L8 O4 @2 V7 EG#B>E<G#B>E<G#" ;
: AR-C  S" T150 L8 O4 @2 V7 EG>CE<G>CE<G" ;
: AR-BB S" T150 L8 O4 @2 V7 DFA#>D<FA#>D<F" ;
: AR-D  S" T150 L8 O4 @2 V7 DF#A>D<F#A>D<F#" ;
: AR-B  S" T150 L8 O4 @2 V7 D#F#B>D#<F#B>D#<F#" ;

\ The first stage: Am F G Em Am F Dm E.
: T1-1  S" T150 L8 O5 @1 V11 E4AB>C4<BA"     AR-AM BS-A DR-A BAR ;
: T1-2  S" T150 L8 O5 @1 V11 A4FGA4GF"       AR-F  BS-F DR-A BAR ;
: T1-3  S" T150 L8 O5 @1 V11 G4DEF4ED"       AR-G  BS-G DR-A BAR ;
: T1-4  S" T150 L8 O5 @1 V11 E2R4EF"         AR-EM BS-E DR-A BAR ;
: T1-5  S" T150 L8 O5 @1 V11 E4AB>CDE<B"     AR-AM BS-A DR-A BAR ;
: T1-6  S" T150 L8 O6 @1 V11 F4.EDC<A4"      AR-F  BS-F DR-A BAR ;
: T1-7  S" T150 L8 O5 @1 V11 F4A>D4C<B4"     AR-DM BS-D DR-A BAR ;
: T1-8  S" T150 L8 O5 @1 V11 G#2B2"          AR-E  BS-E DR-B BAR ;
CREATE TUNE-1  ' T1-1 , ' T1-2 , ' T1-3 , ' T1-4 , ' T1-5 , ' T1-6 , ' T1-7 , ' T1-8 ,

\ The second stage and the title: C G Am F C G F G.
: T2-1  S" T150 L8 O5 @1 V11 G4E>C4<GE>C<"   AR-C  BS-C DR-A BAR ;
: T2-2  S" T150 L8 O5 @1 V11 D4<B>G4DG4"     AR-G  BS-G DR-A BAR ;
: T2-3  S" T150 L8 O5 @1 V11 E4C>C4<AEA"     AR-AM BS-A DR-A BAR ;
: T2-4  S" T150 L8 O5 @1 V11 F2A4G4"         AR-F  BS-F DR-A BAR ;
: T2-5  S" T150 L8 O5 @1 V11 G4E>C4DE4"      AR-C  BS-C DR-A BAR ;
: T2-6  S" T150 L8 O5 @1 V11 D4<B>D4GA4"     AR-G  BS-G DR-A BAR ;
: T2-7  S" T150 L8 O5 @1 V11 A4FAG4FE"       AR-F  BS-F DR-A BAR ;
: T2-8  S" T150 L8 O5 @1 V11 D2G2"           AR-G  BS-G DR-B BAR ;
CREATE TUNE-2  ' T2-1 , ' T2-2 , ' T2-3 , ' T2-4 , ' T2-5 , ' T2-6 , ' T2-7 , ' T2-8 ,

\ The third stage: Dm Bb C Am Dm Bb E A.
: T3-1  S" T150 L8 O5 @1 V11 D4FAD4FA"       AR-DM BS-D DR-A BAR ;
: T3-2  S" T150 L8 O5 @1 V11 A#4FA#A4FA"     AR-BB BS-AS DR-A BAR ;
: T3-3  S" T150 L8 O5 @1 V11 G4EGC4EG"       AR-C  BS-C DR-A BAR ;
: T3-4  S" T150 L8 O5 @1 V11 A2E4R4"         AR-AM BS-A DR-A BAR ;
: T3-5  S" T150 L8 O5 @1 V11 D4FA>D4C<A"     AR-DM BS-D DR-A BAR ;
: T3-6  S" T150 L8 O5 @1 V11 A#4>D<A#G4FG"   AR-BB BS-AS DR-A BAR ;
: T3-7  S" T150 L8 O5 @1 V11 G#4BG#E4G#B"    AR-E  BS-E DR-A BAR ;
: T3-8  S" T150 L8 O5 @1 V11 A2R2"           AR-AM BS-A DR-B BAR ;
CREATE TUNE-3  ' T3-1 , ' T3-2 , ' T3-3 , ' T3-4 , ' T3-5 , ' T3-6 , ' T3-7 , ' T3-8 ,

\ The bosses: Em C D B.
: TB-1  S" T150 L8 O5 @1 V12 EGB>E<BGEB"     AR-EM BS-E DR-B BAR ;
: TB-2  S" T150 L8 O5 @1 V12 EG>C<GECEG"     AR-C  BS-C DR-B BAR ;
: TB-3  S" T150 L8 O5 @1 V12 DF#A>D<AF#DA"   AR-D  BS-D DR-B BAR ;
: TB-4  S" T150 L8 O5 @1 V12 D#F#B>D#<BF#D#B" AR-B BS-B DR-B BAR ;
: TB-5  S" T150 L8 O5 @1 V12 E>E<BGE>E<BG"   AR-EM BS-E DR-B BAR ;
: TB-6  S" T150 L8 O5 @1 V12 E>E<CGE>E<CG"   AR-C  BS-C DR-B BAR ;
: TB-7  S" T150 L8 O5 @1 V12 D>D<AF#D>D<AF#" AR-D  BS-D DR-B BAR ;
: TB-8  S" T150 L8 O5 @1 V12 F#2B2"          AR-B  BS-B DR-B BAR ;
CREATE TUNE-B  ' TB-1 , ' TB-2 , ' TB-3 , ' TB-4 , ' TB-5 , ' TB-6 , ' TB-7 , ' TB-8 ,

8 CONSTANT TUNE-BARS
1600000 CONSTANT BAR-US
VARIABLE TUNE  VARIABLE TUNE-BAR  VARIABLE QUEUED-UNTIL
: NOW ( -- us )   UTIME DROP ;
: NEXT-BAR ( -- )
   QUEUED-UNTIL @ NOW MAX QUEUED-UNTIL !
   TUNE @ TUNE-BAR @ CELLS + @ EXECUTE
   TUNE-BAR @ 1+ TUNE-BARS MOD TUNE-BAR !  BAR-US QUEUED-UNTIL +! ;
: STOP-MUSIC ( -- )   0 TUNE !  MUSIC-CHIP SET-INSTRUMENTS ;
: START-MUSIC ( tune -- )   STOP-MUSIC  TUNE !  0 TUNE-BAR !  0 QUEUED-UNTIL !  NEXT-BAR NEXT-BAR ;
: MUSIC-TICK ( -- )
   TUNE @ 0= IF EXIT THEN
   QUEUED-UNTIL @ NOW - BAR-US < IF NEXT-BAR THEN ;

\ ---- Numbers ----------------------------------------------------------------------

16 CONSTANT FRAME-MS
16000 CONSTANT STEP-US
4 CONSTANT MAX-STEPS
256 CONSTANT FX                         \ positions and speeds are in 1/256 pixels
: >PX ( fx -- px )   256 / ;
: PX> ( px -- fx )   256 * ;
: SEC ( s -- steps )   125 * 2 / ;

VARIABLE SEED
: RND ( n -- 0..n-1 )
   SEED @ 6364136223846793005 * 1442695040888963407 + DUP SEED !  33 RSHIFT SWAP MOD ;
: RND-IN ( lo hi -- n )   OVER - 1+ RND + ;

\ Angles are 0..255 for a whole turn: 0 points right, 64 down.
CREATE SIN-Q
0 , 25 , 50 , 75 , 100 , 125 , 150 , 175 , 200 , 224 , 249 , 273 , 297 ,
321 , 345 , 369 , 392 , 415 , 438 , 460 , 483 , 505 , 526 , 548 , 569 , 590 ,
610 , 630 , 650 , 669 , 688 , 706 , 724 , 742 , 759 , 775 , 792 , 807 , 822 ,
837 , 851 , 865 , 878 , 891 , 903 , 915 , 926 , 936 , 946 , 955 , 964 , 972 ,
980 , 987 , 993 , 999 , 1004 , 1009 , 1013 , 1016 , 1019 , 1021 , 1023 , 1024 , 1024 ,
: SIN ( a -- s )
   255 AND DUP 128 < IF
      DUP 64 > IF 128 SWAP - THEN  CELLS SIN-Q + @
   ELSE
      128 -  DUP 64 > IF 128 SWAP - THEN  CELLS SIN-Q + @ NEGATE
   THEN ;
: COS ( a -- c )   64 + SIN ;
: POLAR ( speed a -- vx vy )   2DUP COS * 1024 /  -ROT SIN * 1024 / ;

VARIABLE AIM-X  VARIABLE AIM-Y
: DOT ( a -- d )   DUP COS AIM-X @ *  SWAP SIN AIM-Y @ *  + ;
: BETTER ( best cand -- best' )   255 AND  OVER DOT OVER DOT < IF NIP ELSE DROP THEN ;
\ The angle of a vector, by climbing to the direction whose dot product is largest.
: ATAN { dx dy | best step -- a }
   dx AIM-X !  dy AIM-Y !
   0 64 BETTER 128 BETTER 192 BETTER TO best
   32 TO step
   BEGIN step WHILE
      best  best step + BETTER  best step - BETTER  TO best
      step 2/ TO step
   REPEAT best ;

: CLAMP ( n lo hi -- n' )   ROT MIN MAX ;
: N>S ( n -- c-addr u )   S>D <# #S #> ;
: N>S0 ( n digits -- c-addr u )   >R S>D <# R> 0 ?DO # LOOP #> ;
\ A color n/256 of the way from c1 to c2.
: MIX-RGB { c1 c2 n | c -- rgb }
   0 TO c
   3 0 DO
      c1 I 8 * RSHIFT 255 AND  c2 I 8 * RSHIFT 255 AND  OVER - n * 256 / +
      I 8 * LSHIFT c OR TO c
   LOOP  c ;

\ ---- Pictures ----------------------------------------------------------------------
\ A picture is a sprite of the game words on a sheet of pictures, and where its top left
\ corner is from its center. It is painted on the screen and captured from there, before
\ the game starts. A second sheet has every picture in white, for a hit enemy's flash.

$FF00FE CONSTANT CLEAR                  \ the color that means "nothing here"
: CANVAS ( -- )   CLEAR GFX-CLS ;

1024 CONSTANT SHEET-W   256 CONSTANT SHEET-H
SHEET-W SHEET-H NEW-IMAGE CONSTANT SHEET
SHEET-W SHEET-H NEW-IMAGE CONSTANT SHADOW
SHEET DRAW-TO CANVAS  SHADOW DRAW-TO CANVAS  SCREEN DRAW-TO
VARIABLE SHELF-X  VARIABLE SHELF-Y  VARIABLE SHELF-H   \ where the next picture goes

BEGIN-STRUCTURE /PIC
   /SPRITE +FIELD PIC-SPRITE            \ first, so that a picture is a sprite
   FIELD: PIC-DX  FIELD: PIC-DY
END-STRUCTURE

: PAINTED? ( rgb -- flag )   DUP CLEAR <> SWAP 0>= AND ;
\ The smallest rectangle of the ww by hh one at x0 y0 of the screen that holds all its
\ painted pixels; 0 by 0 when there are none.
: PAINTED-AREA { x0 y0 ww hh | l r t b -- x y w h }
   ww TO l  -1 TO r  hh TO t  -1 TO b
   hh 0 ?DO  ww 0 ?DO
      x0 I + y0 J + GFX-PGET PAINTED? IF
         I l MIN TO l  I r MAX TO r  J t MIN TO t  J b MAX TO b
      THEN
   LOOP  LOOP
   r 0< IF  x0 y0 0 0 EXIT  THEN
   x0 l +  y0 t +  r l - 1+  b t - 1+ ;
\ A place for a w by h picture on the sheets, in rows from the top left.
: SHELF ( w h -- x y )
   OVER SHELF-X @ + SHEET-W > IF  0 SHELF-X !  SHELF-H @ SHELF-Y +!  0 SHELF-H !  THEN
   SHELF-Y @ OVER + SHEET-H > ABORT" the sheet of pictures is full"
   SHELF-H @ MAX SHELF-H !
   SHELF-X @ SHELF-Y @  ROT SHELF-X +! ;

\ The painted pixels of the ww by hh rectangle at x0 y0 of the screen as a picture whose
\ center is at cx cy.
: CAPTURE { x0 y0 ww hh cx cy | x y w h sx sy pic -- pic }
   x0 y0 ww hh PAINTED-AREA TO h TO w TO y TO x
   w h SHELF TO sy TO sx
   SHEET DRAW-TO  SCREEN x y w h sx sy -1 0 0 128 1 GFX-COPY
   SHADOW DRAW-TO
   h 0 ?DO  w 0 ?DO
      SCREEN x I + y J + GFX-PIXEL PAINTED? IF  sx I + sy J + $FFFFFF GFX-PSET  THEN
   LOOP  LOOP
   SCREEN DRAW-TO
   ALIGN HERE TO pic  /PIC ALLOT
   SHEET sx sy w h pic INIT-SPRITE  CLEAR pic SPRITE-KEY !
   x cx - pic PIC-DX !  y cy - pic PIC-DY !
   pic ;

VARIABLE SHX  VARIABLE SHY              \ the screen shake

\ A picture with its center at x y of the screen, moved by the shake.
: PUT-PIC { x y pic -- }   x pic PIC-DX @ + SHX @ +  y pic PIC-DY @ + SHY @ +  pic PUT-SPRITE ;
: BLIT ( x y pic -- )   DUP >R PUT-PIC R> DRAW-SPRITE ;
\ The same in white, from the second sheet.
: BLIT-WHITE { x y pic -- }
   x y pic PUT-PIC  SHADOW pic SPRITE-IMAGE !  pic DRAW-SPRITE  SHEET pic SPRITE-IMAGE ! ;
\ The same put on the screen in a mode of IMAGE-MODE: 2 adds its light, 3 mixes it in by
\ alpha (0 to 255).
: BLIT-AS { x y pic mode alpha -- }
   x y pic PUT-PIC
   pic SPRITE-IMAGE @  pic SPRITE-SX @  pic SPRITE-SY @  pic SPRITE-W @  pic SPRITE-H @
   pic SPRITE-X @  pic SPRITE-Y @  CLEAR 0 mode alpha 1 GFX-COPY ;
\ Whether picture a with its center at x1 y1 and picture b with its center at x2 y2 show
\ a pixel at the same place.
: PICS-HIT? { x1 y1 a x2 y2 b -- flag }
   x1 a PIC-DX @ +  y1 a PIC-DY @ +  a PUT-SPRITE
   x2 b PIC-DX @ +  y2 b PIC-DY @ +  b PUT-SPRITE
   a b PIXEL-HIT? ;

\ A filled rectangle by runs, and a disc from a table of half widths.
: BAR-RECT { x y ww hh c -- }
   hh 0 ?DO  x  x ww + 1-  y I +  c  GFX-HLINE  LOOP ;

48 CONSTANT MAX-R
CREATE DISC-T  MAX-R 1+ DUP * ALLOT
: ISQRT ( n -- r )   0 BEGIN 1+ 2DUP DUP * < UNTIL 1- NIP ;
: DISC-HW ( r dy -- hw )   SWAP 49 * + DISC-T + C@ ;
: INIT-DISCS ( -- )
   49 0 DO  I 1+ 0 DO  J J * I I * -  ISQRT  J 49 * I + DISC-T + C!  LOOP  LOOP ;
INIT-DISCS

: DISC { x y r c -- }
   r 0< IF EXIT THEN  r MAX-R MIN TO r
   x SHX @ + TO x  y SHY @ + TO y
   r 1+ 0 DO
      r I DISC-HW  DUP x SWAP -  SWAP x +
      2DUP y I + c GFX-HLINE  y I - c GFX-HLINE
   LOOP ;

\ A circle of any size, in 32 straight pieces.
: HOOP { x y r c -- }
   c COLOR!  x SHX @ + TO x  y SHY @ + TO y
   32 0 DO
      x I 8 * COS r * 1024 / +      y I 8 * SIN r * 1024 / +
      x I 1+ 8 * COS r * 1024 / +   y I 1+ 8 * SIN r * 1024 / +   LINE
   LOOP ;

\ Text with a shadow, and the same centered.
: STXT { a u x y c -- }
   $101028 COLOR!  a u x 1+ y 1+ TEXT
   c COLOR!  a u x y TEXT ;
: CTXT { a u y c -- }
   a u TEXT-WIDTH  W SWAP - 2/  { x }  a u x y c STXT ;

\ ---- Drawing the sprites -----------------------------------------------------------

CREATE PALETTE  128 CELLS ALLOT
: PAL-RESET ( -- )   128 0 DO  CLEAR I CELLS PALETTE + !  LOOP ;
PAL-RESET
: PAL! ( rgb "c" -- )   PARSE-NAME DROP C@ 127 AND CELLS PALETTE + ! ;
: PIX ( c -- rgb )   127 AND CELLS PALETTE + @ ;
$12122A PAL! K   $F4F8FF PAL! W   $A0F0FF PAL! A   $40C8F0 PAL! C
$2878D8 PAL! B   $183C80 PAL! N   $C0C8D8 PAL! S   $8088A0 PAL! T
$485068 PAL! U   $E83838 PAL! R   $881828 PAL! D   $F09020 PAL! O
$FFE050 PAL! Y   $50D060 PAL! G   $1E7838 PAL! E   $9050E0 PAL! P
$482878 PAL! Q   $F050B0 PAL! M   $FFC0D8 PAL! I   $B06828 PAL! H

120 CONSTANT CX0                        \ the center column on the canvas
VARIABLE RY
: S[ ( -- )   CANVAS  0 RY ! ;
\ A row given as its left half; the right half is its mirror image.
: R| ( "half-row" -- )
   PARSE-NAME { a u }
   u 0 ?DO
      a I + C@ PIX  DUP CLEAR = IF DROP ELSE
         CX0 I + u -     RY @  2 PICK GFX-PSET
         CX0 u + I - 1-  RY @  ROT GFX-PSET
      THEN
   LOOP
   1 RY +! ;
: ]S ( -- spr )   0 0 W RY @  CX0 RY @ 2/  CAPTURE ;

\ The player's ship, straight and banking.
S[
R| .........K
R| ........KW
R| ........KW
R| .......KAC
R| .......KAC
R| ......KACB
R| ......KACB
R| ......KWCB
R| ..K...KCBN
R| .KAK.KCBBN
R| .KAKKBCBNN
R| KACKBBNNNB
R| KACKBBNNCA
R| KCBBBNNCAW
R| KBBBNNKCAW
R| KNBNNKTKCA
R| .KNKKTUUKB
R| ..K.KUUUKK
R| .....KKK..
]S CONSTANT SPR-SHIP

S[
R| .......K
R| ......KW
R| ......KW
R| .....KAC
R| .....KAC
R| ....KACB
R| ....KACB
R| ....KWCB
R| .K..KCBN
R| KAKKCBBN
R| KABKBCNN
R| KCBBBNNB
R| KCBBNNCA
R| KBBNNCAW
R| KNBNKCAW
R| .KNKTKCA
R| ..KKUUKB
R| ...KUUKK
R| ....KK..
]S CONSTANT SPR-BANK

S[
R| ...K
R| ..KA
R| .KCB
R| .KBN
R| KCCB
R| KBNK
R| .KK.
]S CONSTANT SPR-POD

S[
R| ...KK
R| .KKBW
R| KCBNC
R| .KNKB
R| ..K.K
]S CONSTANT SPR-ICON

S[
R| .K
R| KW
R| AW
R| AW
R| CW
R| CW
R| CA
R| BC
R| .B
]S CONSTANT SPR-BOLT

S[
R| .M
R| MW
R| MI
R| MI
R| MI
R| QM
R| .Q
]S CONSTANT SPR-SPREAD

S[
R| .KY
R| KYW
R| KYW
R| KOY
R| KOO
R| KRO
R| .KR
]S CONSTANT SPR-FOCUS

\ The enemies, facing down.
S[
R| ..K....
R| .KRK..K
R| .KRDKKD
R| KRRDRDR
R| KDRDRRW
R| .KRRRYY
R| ..KDRYW
R| ...KDRY
R| ....KDR
R| .....KD
R| ......K
]S CONSTANT SPR-DART

S[
R| ....KKKK
R| ..KKPPPA
R| .KPPPAWW
R| KPQPAAWW
R| KQQQPPPP
R| KQKQKQKQ
R| .KKOKOKK
R| ...K.KK.
]S CONSTANT SPR-WEAVER

S[
R| ...KKKK
R| .KKUTSW
R| KUTYOTS
R| KUOROUT
R| KUTYOTS
R| .KKUTSW
R| ...KKKK
]S CONSTANT SPR-TURRET

S[
R| ......K
R| ..K..KR
R| .KRKKDR
R| ..KDURT
R| ..KUTTS
R| KKUTYWW
R| KRDTOYW
R| ..KUTTS
R| ..KDURT
R| .KRKKDR
R| ..K..KR
R| ......K
]S CONSTANT SPR-MINE

\ Capsules and gems.
S[
R| ..KKKK
R| .KRRRR
R| KRIRRR
R| KRRRRR
R| KDRRRR
R| KDRRRR
R| KDDRRR
R| .KDDDD
R| ..KKKK
]S CONSTANT SPR-P

S[
R| ..KKKK
R| .KGGGG
R| KGWGGG
R| KGGGGG
R| KEGGGG
R| KEGGGG
R| KEEGGG
R| .KEEEE
R| ..KKKK
]S CONSTANT SPR-B

S[
R| ..Y
R| .YW
R| YWW
R| OYY
R| .OY
R| ..O
]S CONSTANT SPR-GEM

S[
R| .Y
R| YW
R| OY
R| .O
]S CONSTANT SPR-GEM2

\ Pictures turned to 16 directions, or to any number of steps, by sampling a square.
40 CONSTANT RS
CREATE ROT-BUF  RS RS * CELLS ALLOT
: GRAB ( -- )
   RS 0 DO  RS 0 DO  I CX0 20 - +  J GFX-PGET  I J RS * + CELLS ROT-BUF + !  LOOP  LOOP ;
: ROT-SRC ( sx sy -- rgb )
   2DUP 0 RS WITHIN SWAP 0 RS WITHIN AND 0= IF 2DROP CLEAR EXIT THEN
   RS * + CELLS ROT-BUF + @ ;
\ The picture on the canvas in n equal turns, as a table of n sprites.
: ROT-BAKE { n | tab cy a dx dy c s rgb -- tab }
   RY @ 2/ TO cy   GRAB
   HERE TO tab  n CELLS ALLOT
   n 0 DO
      I 256 * n / TO a   a COS TO c  a SIN TO s
      CANVAS
      49 -24 DO
         I TO dy
         49 -24 DO
            I TO dx
            dx c * dy s * +  512 + 1024 /  20 +
            dy c * dx s * -  512 + 1024 /  cy +
            ROT-SRC TO rgb
            rgb CLEAR <> IF  30 dx +  30 dy +  rgb GFX-PSET  THEN
         LOOP
      LOOP
      6 6 49 49 30 30 CAPTURE  tab I CELLS + !
   LOOP
   tab ;
: ROT-INDEX ( angle -- f )   64 - 8 + 16 / 15 AND ;
: ROT-SPR ( tab angle -- spr )   ROT-INDEX CELLS + @ ;

S[
R| ......K
R| .....KE
R| ..K.KEE
R| .KGKEEG
R| KGGEEGG
R| KGEEGGG
R| .KKEEGG
R| ...KGGA
R| ....KGW
R| ....KGG
R| .....KG
R| ......K
]S DROP  16 ROT-BAKE CONSTANT ROT-HUNTER

S[
R| .K
R| KS
R| KT
R| KT
R| KT
R| KY
R| KW
R| .K
]S DROP  16 ROT-BAKE CONSTANT ROT-MISSILE

S[
R| .......K
R| ..KK..KN
R| .KCBKKNB
R| KCBNNBCA
R| KBNNBCAW
R| .KKNBCAW
R| ...KNBCA
R| ....KNBC
R| .....KNB
R| ......KN
R| .......K
]S DROP  16 ROT-BAKE CONSTANT ROT-SWOOP

\ Needle shots, turned.
S[
R| .R
R| RI
R| RW
R| RW
R| RW
R| RW
R| RI
R| .R
]S DROP  16 ROT-BAKE CONSTANT ROT-NEEDLE-R

S[
R| .B
R| BA
R| BW
R| BW
R| BW
R| BW
R| BA
R| .B
]S DROP  16 ROT-BAKE CONSTANT ROT-NEEDLE-B

\ Round shots: three sizes in six colors. A kind is two cells: the sprite and the
\ radius that can hit.
CREATE ORB-LIGHT  $FF8080 , $80B8FF , $FFA0E0 , $A0FFA8 , $FFF090 , $FFC070 ,
CREATE ORB-DARK   $D01818 , $1850E0 , $E020A0 , $10B030 , $D8A010 , $E06010 ,
0 CONSTANT C-RED  1 CONSTANT C-BLU  2 CONSTANT C-PNK
3 CONSTANT C-GRN  4 CONSTANT C-YEL  5 CONSTANT C-ORG
0 CONSTANT O-S  1 CONSTANT O-M  2 CONSTANT O-L

: ORB-RGB { d r col -- rgb }
   d r 2 - DUP * <= IF $FFFFFF EXIT THEN
   d r 1- DUP * <= IF col CELLS ORB-LIGHT + @ EXIT THEN
   col CELLS ORB-DARK + @ ;
: BAKE-ORB { r col -- spr }
   CANVAS
   r 1+ r NEGATE DO
      r 1+ r NEGATE DO
         I I * J J * +  DUP r r * > IF  DROP  ELSE
            r col ORB-RGB  30 I + SWAP  30 J + SWAP GFX-PSET
         THEN
      LOOP
   LOOP
   20 20 21 21 30 30 CAPTURE ;

CREATE ORBS  18 2* CELLS ALLOT
: ORBK ( size col -- kind )   SWAP 6 * + 2* CELLS ORBS + ;
CREATE ORB-RADII  3 , 4 , 6 ,
CREATE ORB-HITS   1 , 2 , 4 ,
: BAKE-ORBS ( -- )
   3 0 DO
      6 0 DO
         J CELLS ORB-RADII + @  I BAKE-ORB   J I ORBK !
         J CELLS ORB-HITS + @                J I ORBK CELL+ !
      LOOP
   LOOP ;
BAKE-ORBS

\ Needle kinds are made the same way: the table is chosen by direction when fired.
CREATE NEEDLE-R  ROT-NEEDLE-R , 2 ,
CREATE NEEDLE-B  ROT-NEEDLE-B , 2 ,

\ Glows: images of a round light that fades to black at its edge, added to what is on
\ the screen (mode 2), so that they brighten it and show nothing where they are dark.
: BAKE-GLOW { r c | side img d s -- img }
   r 2* 1+ TO side
   side side NEW-IMAGE TO img  img DRAW-TO  0 GFX-CLS
   side 0 DO  side 0 DO
      I r - DUP *  J r - DUP * +  ISQRT  256 * r 1+ /  TO d
      d 256 < IF
         256 d - DUP * 256 / TO s
         I J  0 c s MIX-RGB  GFX-PSET
      THEN
   LOOP  LOOP
   SCREEN DRAW-TO  img ;
: GLOW { x y img | side -- }
   img IMAGE-SIZE DROP TO side
   img 0 0 side side  x side 2/ - SHX @ +  y side 2/ - SHY @ +  -1 0 2 255 1 GFX-COPY ;

\ A glow for each kind of round shot, of its light color, and for fire of five sizes.
CREATE ORB-GLOWS  18 CELLS ALLOT
: BAKE-ORB-GLOWS ( -- )
   3 0 DO  6 0 DO
      J CELLS ORB-RADII + @ 2* 1+  I CELLS ORB-LIGHT + @ $FEFEFE AND 1 RSHIFT  BAKE-GLOW
      J 6 * I + CELLS ORB-GLOWS + !
   LOOP  LOOP ;
BAKE-ORB-GLOWS
\ The glow of a kind of shot, 0 for none (needles).
: KIND-GLOW ( kind -- img|0 )
   ORBS -  DUP 0 18 2* CELLS WITHIN IF  2/ ORB-GLOWS + @  ELSE DROP 0 THEN ;
CREATE FIRE-GLOWS  5 CELLS ALLOT
CREATE FIRE-SIZES  8 , 14 , 22 , 32 , 46 ,
: BAKE-FIRE-GLOWS ( -- )
   5 0 DO  I CELLS FIRE-SIZES + @ $C05818 BAKE-GLOW  I CELLS FIRE-GLOWS + !  LOOP ;
BAKE-FIRE-GLOWS
\ The glow of fire that reaches about r pixels.
: FIRE-GLOW ( r -- img )
   4  4 0 DO  OVER I CELLS FIRE-SIZES + @ <= IF DROP I LEAVE THEN  LOOP
   NIP CELLS FIRE-GLOWS + @ ;
20 $D04010 BAKE-GLOW CONSTANT LASER-GLOW

\ ---- Spinners, hulls, and clouds ----------------------------------------------------

8 CONSTANT SPIN-FRAMES
CREATE SPIN-TAB  SPIN-FRAMES CELLS ALLOT
: BAKE-SPINNER { f | a -- spr }
   CANVAS
   4 0 DO
      f 8 * I 64 * + TO a
      12 0 DO
         30  a I 3 * + COS I 2 + * 1024 / +
         30  a I 3 * + SIN I 2 + * 1024 / +
         I 2 < IF 4 ELSE I 7 < IF 3 ELSE 2 THEN THEN
         I 7 < IF $F09020 ELSE $B83818 THEN
         DISC
      LOOP
   LOOP
   30 30 7 $12122A DISC  30 30 6 $C8D0E0 DISC  30 30 3 $FFE050 DISC  30 30 1 $FFFFFF DISC
   8 8 45 45 30 30 CAPTURE ;
: BAKE-SPINNERS ( -- )   SPIN-FRAMES 0 DO  I BAKE-SPINNER  SPIN-TAB I CELLS + !  LOOP ;
BAKE-SPINNERS

\ Hulls are drawn row by row from a table of half widths, darker toward the edges and
\ with panel lines, and then get a dark outline.
$12122A CONSTANT OUTLINE-C
: BODY-PX? ( x y -- flag )
   GFX-PGET  DUP 0< IF DROP FALSE EXIT THEN  DUP CLEAR <> SWAP OUTLINE-C <> AND ;
: OUTLINE { rows -- }
   rows 1+ 0 DO
      W 1- 1 DO
         I J GFX-PGET CLEAR = IF
            I 1+ J BODY-PX?  I 1- J BODY-PX? OR  I J 1+ BODY-PX? OR  I J 1- BODY-PX? OR
            IF  I J OUTLINE-C GFX-PSET  THEN
         THEN
      LOOP
   LOOP ;

CREATE RAMP-STEEL $1C2438 , $2C3850 , $3E5070 , $566C90 , $7088AC , $90A8C8 , $B4C8E0 , $DCE8F4 ,
CREATE RAMP-RED   $380C18 , $581424 , $802030 , $A83038 , $C84840 , $E06850 , $F09070 , $FCC0A0 ,
CREATE RAMP-GOLD  $3C2808 , $5C400C , $806010 , $A88018 , $C8A028 , $E0C048 , $F0DC80 , $FCF4C0 ,
CREATE RAMP-MOSS  $182818 , $284028 , $3C5C38 , $54784C , $709468 , $90B084 , $B4CCA8 , $DCE8CC ,
CREATE RAMP-PURP  $20143C , $342060 , $4C3088 , $6844B0 , $8860CC , $A880E0 , $C8A8F0 , $E8D4FC ,

: RAMP-PX ( ramp idx -- rgb )   0 MAX 7 MIN CELLS + @ ;
: HULL { prof n rows ramp | pos s f hw row -- }
   rows 0 DO
      I TO row
      row n 1- * 256 * rows 1- / TO pos
      pos 256 / TO s   pos 255 AND TO f
      s n 1- >= IF  n 2 - TO s  256 TO f  THEN
      s CELLS prof + @  s 1+ CELLS prof + @  OVER - f * 256 / +  TO hw
      hw 0 ?DO
         hw I - 7 * hw /
         row 3 + 12 MOD 0= IF 2 - THEN
         I 4 + 14 MOD 0= IF 1- THEN
         DUP    ramp SWAP RAMP-PX   CX0 I - 1-  row 1+  ROT GFX-PSET
         1-     ramp SWAP RAMP-PX   CX0 I +     row 1+  ROT GFX-PSET
      LOOP
   LOOP ;
: ]HULL ( rows -- spr )   2 + DUP OUTLINE  >R 0 0 W R@  CX0 R> 2/  CAPTURE ;
: LIGHTS { x y n gap c -- }   \ a row of windows, mirrored
   n 0 ?DO
      CX0 x + I gap * +  y  2 2 c BAR-RECT
      CX0 x - I gap * -  2 -  y  2 2 c BAR-RECT
   LOOP ;

CREATE PF-GUN   4 , 10 , 16 , 17 , 14 , 9 , 3 ,
CANVAS  PF-GUN 7 26 RAMP-RED HULL
4 12 3 4 $FFE050 LIGHTS   CX0 13 7 $12122A DISC  CX0 13 5 $F09020 DISC  CX0 13 2 $FFF0A0 DISC
26 ]HULL CONSTANT SPR-GUN

CREATE PF-CARRIER   10 , 26 , 34 , 36 , 36 , 36 , 34 , 26 , 14 ,
CANVAS  PF-CARRIER 9 46 RAMP-MOSS HULL
6 8 4 7 $FFE050 LIGHTS   6 36 4 7 $FFE050 LIGHTS
CX0 20 - 18 40 8 $202820 BAR-RECT   CX0 8 - 19 16 6 $F09020 BAR-RECT
46 ]HULL CONSTANT SPR-CARRIER

CREATE PF-B1   5 , 12 , 24 , 44 , 60 , 64 , 52 , 34 , 28 , 30 , 16 , 5 ,
CANVAS  PF-B1 12 66 RAMP-STEEL HULL
CX0 30 15 $12122A DISC  CX0 30 12 $2C3850 DISC
10 22 5 11 $FFE050 LIGHTS   34 34 3 9 $40C8F0 LIGHTS
CX0 6 - 50 12 12 $181C2C BAR-RECT
66 ]HULL CONSTANT SPR-BOSS1

CREATE PF-B2   38 , 20 , 30 , 50 , 56 , 56 , 44 , 30 , 34 , 38 , 22 , 8 , 3 ,
CANVAS  PF-B2 13 72 RAMP-RED HULL
CX0 34 13 $12122A DISC  CX0 34 10 $581424 DISC
14 16 5 10 $FFE050 LIGHTS   26 44 4 8 $F09020 LIGHTS
72 ]HULL CONSTANT SPR-BOSS2

CREATE PF-B3   10 , 26 , 36 , 42 , 45 , 46 , 45 , 42 , 36 , 26 , 10 ,
CANVAS  PF-B3 11 74 RAMP-GOLD HULL
CX0 37 17 $12122A DISC  CX0 37 14 $5C400C DISC
12 12 4 8 $40C8F0 LIGHTS   12 62 4 8 $40C8F0 LIGHTS
74 ]HULL CONSTANT SPR-BOSS3

S[
R| ....KKK
R| ..KKTST
R| .KUTTSS
R| .KUTYOS
R| .KUTOYS
R| .KUTTST
R| ..KUTTU
R| ...KUTK
R| ....KUK
R| ....KTK
R| ....KTK
R| ....KSK
R| .....K.
]S CONSTANT SPR-CANNON

S[
R| ...KKKK
R| ..KPPPP
R| .KPPAWW
R| KPPAWWW
R| KPAWWWW
R| KPPAWWW
R| KQPPAAA
R| .KQPPPP
R| ..KKKKK
]S CONSTANT SPR-ORBITER

: BAKE-CLOUD { n | x y r -- spr }
   CANVAS
   n 0 DO
      90 RND 75 + TO x   34 RND 16 + TO y   10 RND 7 + TO r
      x y 2 + r $9CB0C8 DISC
   LOOP
   SEED @  1 SEED !  SEED !
   n 0 DO
      90 RND 75 + TO x   34 RND 16 + TO y   10 RND 7 + TO r
      x y 1- r 2 - $F0F4FA DISC
   LOOP
   50 0 140 70 120 34 CAPTURE ;
12345 SEED !
12 BAKE-CLOUD CONSTANT SPR-CLOUD1
9 BAKE-CLOUD CONSTANT SPR-CLOUD2

\ ---- The state of the game ----------------------------------------------------------

0 CONSTANT M-TITLE  1 CONSTANT M-INTRO  2 CONSTANT M-PLAY
3 CONSTANT M-CLEAR  4 CONSTANT M-OVER   5 CONSTANT M-END

VARIABLE MODE   VARIABLE MODE-T   VARIABLE DONE   VARIABLE PAUSED   VARIABLE SHOW-PERF
VARIABLE AUTO-FIRE
VARIABLE STG    VARIABLE STAGE-T  VARIABLE PHASE  VARIABLE PHASE-T  VARIABLE WAVE-PTR
VARIABLE BOSS-I VARIABLE BOSS-MAX
VARIABLE SCORE  VARIABLE HI-SCORE VARIABLE LIVES  VARIABLE BOMBS    VARIABLE POWER
VARIABLE CHAIN  VARIABLE CHAIN-T  VARIABLE NEXT-EXT  VARIABLE GRAZE  VARIABLE KILLS
VARIABLE PL-X   VARIABLE PL-Y     VARIABLE PL-TURN   VARIABLE PL-SLOW
VARIABLE INV    VARIABLE DEAD     VARIABLE FIRE-T    VARIABLE BOMB-T
VARIABLE SHAKE  VARIABLE FLASH  VARIABLE WOBBLE     \ WOBBLE: steps of rippling rows
VARIABLE SCROLL VARIABLE SCROLL-V
VARIABLE IN-L VARIABLE IN-R VARIABLE IN-U VARIABLE IN-D VARIABLE IN-FIRE VARIABLE IN-SLOW
VARIABLE PRESS-FIRE  VARIABLE PRESS-BOMB  VARIABLE PRESS-START

: RANKED ( v -- v' )   STG @ 16 * 100 +  100 */ ;
: QUICKER ( n -- n' )   6 STG @ - *  6 / ;
: SHAKE! ( n -- )   SHAKE @ MAX SHAKE ! ;

\ ---- Particles and explosions -------------------------------------------------------

CREATE RAMP-FIRE  $FFFFFF , $FFF0A0 , $FFD040 , $F8A020 , $E86818 , $B83010 , $702010 , $381010 ,
CREATE RAMP-ICE   $FFFFFF , $C0F0FF , $80D8FF , $40B0F0 , $2080E0 , $1858B0 , $183880 , $102040 ,
CREATE RAMP-GRN   $FFFFFF , $C0FFC8 , $80F090 , $48D060 , $28A040 , $187830 , $105020 , $082810 ,
CREATE RAMP-GLD   $FFFFFF , $FFF8C0 , $FFE880 , $FFD040 , $E8A820 , $B87818 , $805010 , $402808 ,

200 CONSTANT MAX-P
: P-FIELD ( "name" -- )   CREATE MAX-P CELLS ALLOT  DOES> SWAP CELLS + ;
P-FIELD FXX  P-FIELD FXY  P-FIELD FVX  P-FIELD FVY  P-FIELD FLF  P-FIELD FMX  P-FIELD FRP
VARIABLE P-CUR

: SPARK { x y vx vy life ramp | p -- }
   P-CUR @ TO p   p 1+ MAX-P MOD P-CUR !
   x p FXX !  y p FXY !  vx p FVX !  vy p FVY !  life p FLF !  life p FMX !  ramp p FRP ! ;

: SPARKS { x y n spd ramp -- }
   n 0 ?DO
      x y   spd RND spd 3 / +  256 RND POLAR   18 RND 10 +  ramp SPARK
   LOOP ;

: PARTICLES-TICK ( -- )
   MAX-P 0 DO
      I FLF @ IF
         I FVX @ I FXX +!   I FVY @ I FXY +!
         I FVX @ 15 * 16 / I FVX !   I FVY @ 15 * 16 / I FVY !
         -1 I FLF +!
      THEN
   LOOP ;

: DRAW-PARTICLES ( -- )
   SHX @ SHY @ { ox oy }
   MAX-P 0 DO
      I FLF @ IF
         I FXX @ >PX ox +   I FXY @ >PX oy +
         I FMX @ I FLF @ - 7 * I FMX @ /  CELLS I FRP @ + @   { px py c }
         px  px I FLF @ 8 > IF 1+ THEN  py c GFX-HLINE
      THEN
   LOOP ;

40 CONSTANT MAX-X
: X-FIELD ( "name" -- )   CREATE MAX-X CELLS ALLOT  DOES> SWAP CELLS + ;
X-FIELD XPX  X-FIELD XPY  X-FIELD XAGE  X-FIELD XLIFE  X-FIELD XSIZE
VARIABLE X-CUR

: BLAST { x y size | e -- }
   X-CUR @ TO e   e 1+ MAX-X MOD X-CUR !
   x e XPX !  y e XPY !  size e XSIZE !  0 e XAGE !
   size 3 * 2/ 12 + e XLIFE ! ;

: BLASTS-TICK ( -- )
   MAX-X 0 DO
      I XLIFE @ IF
         1 I XAGE +!   I XAGE @ I XLIFE @ >= IF 0 I XLIFE ! THEN
      THEN
   LOOP ;

: DRAW-BLAST { e | x y s p r -- }
   e XPX @ >PX TO x   e XPY @ >PX TO y   e XSIZE @ TO s
   e XAGE @ 256 * e XLIFE @ / TO p
   s 90 p + * 256 / TO r
   p 150 < IF
      x y r $E04818 DISC    x y r 3 * 4 / $FF9820 DISC
      x y r 2/ $FFE870 DISC    p 70 < IF x y r 4 / $FFFFFF DISC THEN
      x y  r 3 * 2/ FIRE-GLOW  GLOW
   ELSE
      x y r $702818 DISC   x y r 2 * 3 / $A83818 DISC
      x y r p 150 - * 200 / $180C10 DISC
   THEN ;

: DRAW-BLASTS ( -- )   MAX-X 0 DO  I XLIFE @ IF I DRAW-BLAST THEN  LOOP ;

\ ---- Enemy shots --------------------------------------------------------------------

320 CONSTANT MAX-B
: B-FIELD ( "name" -- )   CREATE MAX-B CELLS ALLOT  DOES> SWAP CELLS + ;
B-FIELD BX  B-FIELD BY  B-FIELD BVX  B-FIELD BVY  B-FIELD BAX  B-FIELD BAY
B-FIELD BSP  B-FIELD BR  B-FIELD BGZ  B-FIELD BGL     \ BGL: its glow, or 0
VARIABLE B-CUR  VARIABLE LAST-B

: NEW-B ( -- b )
   MAX-B 0 DO
      B-CUR @ 1+ MAX-B MOD DUP B-CUR !
      DUP BSP @ 0= IF UNLOOP EXIT THEN  DROP
   LOOP  B-CUR @ ;

: SHOOT { x y spd ang kind | b -- }
   NEW-B TO b   b LAST-B !
   x b BX !  y b BY !
   spd ang POLAR  b BVY !  b BVX !
   0 b BAX !  0 b BAY !  0 b BGZ !
   kind CELL+ @ b BR !
   kind @  kind NEEDLE-R =  kind NEEDLE-B = OR IF ang ROT-SPR THEN  b BSP !
   kind KIND-GLOW b BGL ! ;

: LAST-ACCEL ( ax ay -- )   LAST-B @ BAY !  LAST-B @ BAX ! ;

: FAN { x y n spread spd ang kind -- }
   n 0 ?DO
      x y spd   ang  spread I 2* n 1- - * 2/ +   kind SHOOT
   LOOP ;

: BURST { x y n spd offs kind -- }
   n 0 ?DO  x y spd  I 256 * n / offs +  kind SHOOT  LOOP ;

: BULLET-COUNT ( -- n )   0  MAX-B 0 DO  I BSP @ 0<> -  LOOP ;

\ ---- Items --------------------------------------------------------------------------

32 CONSTANT MAX-I
: I-FIELD ( "name" -- )   CREATE MAX-I CELLS ALLOT  DOES> SWAP CELLS + ;
I-FIELD IX  I-FIELD IY  I-FIELD IVX  I-FIELD IVY  I-FIELD ITY
0 CONSTANT IT-NONE  1 CONSTANT IT-P  2 CONSTANT IT-B  3 CONSTANT IT-GEM
VARIABLE I-CUR

: NEW-ITEM { x y ty | n -- }
   I-CUR @ TO n   n 1+ MAX-I MOD I-CUR !
   x n IX !  y n IY !  ty n ITY !
   300 RND 150 - n IVX !   -180 n IVY ! ;

\ Every remaining enemy shot becomes a gem or a spark.
: CANCEL-SHOTS ( gems? -- )
   { gems }
   MAX-B 0 DO
      I BSP @ IF
         gems  I 3 AND 0= AND IF  I BX @ I BY @ IT-GEM NEW-ITEM  THEN
         I BX @ I BY @ 2 240 RAMP-ICE SPARKS
         0 I BSP !
      THEN
   LOOP ;

\ ---- Score ---------------------------------------------------------------------------

: MULT ( -- m )   CHAIN @ 8 / 1+  8 MIN ;
: ADD-SCORE ( n -- )
   SCORE +!
   SCORE @ NEXT-EXT @ >= IF
      1 LIVES +!  S-EXTEND EFFECT
      NEXT-EXT @ 200000 = IF 500000 ELSE NEXT-EXT @ 500000 + THEN NEXT-EXT !
   THEN ;

\ ---- Enemies --------------------------------------------------------------------------

64 CONSTANT MAX-E
: E-FIELD ( "name" -- )   CREATE MAX-E 1+ CELLS ALLOT  DOES> SWAP CELLS + ;
E-FIELD EAI  E-FIELD ETY  E-FIELD EX  E-FIELD EY  E-FIELD EVX  E-FIELD EVY
E-FIELD EHP  E-FIELD ESP  E-FIELD ET  E-FIELD EF  E-FIELD EA  E-FIELD EB  E-FIELD EC
E-FIELD EWAIT  E-FIELD EPAR  E-FIELD EIMM

VARIABLE ME
: MX ( -- a )   ME @ EX ;     : MY ( -- a )   ME @ EY ;
: MVX ( -- a )  ME @ EVX ;    : MVY ( -- a )  ME @ EVY ;
: MHP ( -- a )  ME @ EHP ;    : MSP ( -- a )  ME @ ESP ;
: MT ( -- a )   ME @ ET ;     : MA ( -- a )   ME @ EA ;
: MB ( -- a )   ME @ EB ;     : MC ( -- a )   ME @ EC ;
: MIMM ( -- a ) ME @ EIMM ;
: FREE-ME ( -- )   0 ME @ EAI ! ;

\ An enemy type, given in reverse: extra flags drops onkill pts hh hw hp spr ai.
: ETYPE: ( extra flags drops onkill pts hh hw hp spr ai "name" -- )
   CREATE , , , , , , , , , , ;
: T.AI ( t -- a ) ;
: T.SPR ( t -- a )   1 CELLS + ;    : T.HP ( t -- a )   2 CELLS + ;
: T.HW ( t -- a )    3 CELLS + ;    : T.HH ( t -- a )   4 CELLS + ;
: T.PTS ( t -- a )   5 CELLS + ;    : T.KILL ( t -- a ) 6 CELLS + ;
: T.DROP ( t -- a )  7 CELLS + ;    : T.FLAG ( t -- a ) 8 CELLS + ;
: T.EXTRA ( t -- a ) 9 CELLS + ;
1 CONSTANT F-GROUND   2 CONSTANT F-BOSS   4 CONSTANT F-PART

: E-NEW { x y typ | e -- e }
   MAX-E TO e
   MAX-E 0 DO  I EAI @ 0= IF I TO e LEAVE THEN  LOOP
   typ T.AI @ e EAI !  typ e ETY !
   x e EX !  y e EY !  0 e EVX !  0 e EVY !
   typ T.HP @ e EHP !  typ T.SPR @ e ESP !
   0 e ET !  0 e EF !  0 e EA !  0 e EB !  0 e EC !  0 e EWAIT !  -1 e EPAR !  0 e EIMM !
   e ;

: OUT? ( -- flag )
   MY @ >PX  DUP H 44 + >  SWAP -240 < OR   MX @ >PX -120 360 WITHIN 0=  OR ;
: CHECK-OUT ( -- )   OUT? IF FREE-ME THEN ;
: VIS? ( -- flag )   MY @ >PX 6 H 40 - WITHIN  MX @ >PX 2 W 2 - WITHIN AND ;
: HERE-AT ( -- x y )   MX @ MY @ ;
: AIMED ( -- a )   PL-X @ MX @ -  PL-Y @ MY @ -  ATAN ;
: EVERY? ( n phase -- flag )   >R MT @ SWAP MOD R> = ;

: AI-WEAVE ( -- )
   MT @ 3 * SIN 44 * 4 /  MA @ +  MX !
   300 MVY !
   80 QUICKER MB @ EVERY?  VIS? AND IF
      HERE-AT 330 RANKED AIMED O-M C-PNK ORBK SHOOT
   THEN
   CHECK-OUT ;

: AI-DART ( -- )
   MT @ 40 < IF 760 MVY ! ELSE
   MT @ 75 < IF MVY @ 225 * 256 / MVY ! ELSE
      MVY @ 18 + 760 MIN MVY !  MB @ MVX !
   THEN THEN
   MT @ 60 =  VIS? AND IF  HERE-AT 460 RANKED AIMED O-M C-RED ORBK SHOOT  THEN
   CHECK-OUT ;

: AI-SWOOP ( -- )
   MB @ MA +!
   600  MA @ 16 /  POLAR  MVY ! MVX !
   ROT-SWOOP MA @ 16 / ROT-SPR MSP !
   MT @ 56 =  MT @ 96 = OR  VIS? AND IF  HERE-AT 480 RANKED AIMED NEEDLE-B SHOOT  THEN
   CHECK-OUT ;

: AI-HUNT ( -- )
   MT @ 260 < IF
      AIMED  MA @ 16 / -  128 + 255 AND 128 -  -2 2 CLAMP  16 * MA +!
   THEN
   500  MA @ 16 /  POLAR  MVY ! MVX !
   ROT-HUNTER MA @ 16 / ROT-SPR MSP !
   CHECK-OUT ;

: AI-GUN ( -- )
   MB @ 0= IF
      MY @ MA @ < IF  360 MVY !  ELSE  0 MVY !  1 MB !  0 MT !  THEN
   ELSE
      70 QUICKER 30 EVERY?  MC @ 4 < AND IF
         HERE-AT 5 10 380 RANKED AIMED NEEDLE-R FAN
         1 MC +!
      THEN
      MC @ 4 >=  MT @ 400 > OR IF 340 MVY ! THEN
   THEN
   CHECK-OUT ;

: AI-SPIN ( -- )
   170 MVY !
   SPIN-TAB MT @ 3 / SPIN-FRAMES MOD CELLS + @ MSP !
   6 0 EVERY?  VIS? AND IF
      HERE-AT 4 300 RANKED MT @ 5 * O-S C-YEL ORBK BURST
   THEN
   CHECK-OUT ;

: AI-MINE ( -- )   220 MVY !  CHECK-OUT ;
: MINE-BURST ( -- )   HERE-AT 12 320 RANKED MT @ O-M C-ORG ORBK BURST ;

: AI-TURRET ( -- )
   SCROLL-V @ MVY !
   AIMED MA !
   70 QUICKER 20 EVERY?  VIS? AND  PL-Y @ MY @ - ABS 40 PX> > AND IF
      HERE-AT 420 RANKED MA @ O-M C-GRN ORBK SHOOT
   THEN
   CHECK-OUT ;
: TURRET-BARREL { x y a -- }
   $C0C8D8 COLOR!
   x SHX @ + TO x  y SHY @ + TO y
   x y  x a COS 11 * 1024 / +  y a SIN 11 * 1024 / +  LINE ;

\ ---- Bosses ----------------------------------------------------------------------------

: BOSS-IN? ( yt -- flag )
   PX> MY @ > IF  320 MVY !  TRUE MIMM !  TRUE  ELSE  0 MVY !  FALSE MIMM !  FALSE  THEN ;
: PH ( -- n )
   MHP @ 100 *  BOSS-MAX @ /  DUP 66 > IF DROP 0 ELSE 33 > IF 1 ELSE 2 THEN THEN ;
: SWAY ( amp -- )   MT @ SIN * 4 /  W 2/ PX> +  MX ! ;
: NOSE ( dy -- x y )   >R MX @  MY @ R> PX> + ;

4 CONSTANT MAX-LZ
CREATE LZX MAX-LZ CELLS ALLOT   CREATE LZV MAX-LZ CELLS ALLOT
CREATE LZY MAX-LZ CELLS ALLOT   CREATE LZT MAX-LZ CELLS ALLOT
45 CONSTANT LZ-WARN  135 CONSTANT LZ-END  11 CONSTANT LZ-HALF
: LASER-ERASE ( -- )   MAX-LZ 0 DO  0 I CELLS LZT + !  LOOP ;
: LASER { x y vx | n -- }
   MAX-LZ TO n
   MAX-LZ 0 DO  I CELLS LZT + @ 0= IF I TO n LEAVE THEN  LOOP
   n MAX-LZ = IF EXIT THEN
   x n CELLS LZX + !  y n CELLS LZY + !  vx n CELLS LZV + !  1 n CELLS LZT + ! ;
: LASERS-TICK ( -- )
   MAX-LZ 0 DO
      I CELLS LZT + @ ?DUP IF
         1+  DUP LZ-END > IF DROP 0 THEN  I CELLS LZT + !
         I CELLS LZT + @ LZ-WARN = IF S-LASER EFFECT  6 SHAKE! THEN
         I CELLS LZV + @ I CELLS LZX + +!
      THEN
   LOOP ;

\ Boss one.
: B1-P0 ( -- )
   84 QUICKER 0 EVERY?  IF  0 NOSE 3 14 420 RANKED AIMED NEEDLE-B FAN  THEN
   24 6 EVERY?  IF
      MX @ 28 PX> -  MY @  400 RANKED AIMED O-S C-RED ORBK SHOOT
      MX @ 28 PX> +  MY @  400 RANKED AIMED O-S C-RED ORBK SHOOT
   THEN ;
: B1-P1 ( -- )
   7 0 EVERY? IF
      10 NOSE 300 RANKED MT @ 7 *  O-S C-BLU ORBK SHOOT
      10 NOSE 300 RANKED MT @ 7 * 128 + O-S C-PNK ORBK SHOOT
   THEN
   124 QUICKER 0 EVERY? IF  0 NOSE 3 20 500 RANKED AIMED NEEDLE-R FAN  THEN ;
: B1-P2 ( -- )
   90 QUICKER 0 EVERY? IF  0 NOSE 8 300 RANKED MT @ O-M C-RED ORBK BURST  THEN
   90 QUICKER 45 EVERY? IF 0 NOSE 8 300 RANKED MT @ 9 + O-M C-BLU ORBK BURST  THEN
   240 120 EVERY? IF  MX @ MY @ 16 PX> +  MX @ PL-X @ < IF 110 ELSE -110 THEN  LASER  THEN ;
: AI-B1 ( -- )
   64 BOSS-IN? IF EXIT THEN
   56 SWAY
   PH CASE  0 OF B1-P0 ENDOF  1 OF B1-P1 ENDOF  2 OF B1-P2 ENDOF  ENDCASE ;

\ Boss two.
: B2-P0 ( -- )
   11 0 EVERY? IF
      W PX> RND  -6 PX>  260 RANKED 64 NEEDLE-B SHOOT   0 6 LAST-ACCEL
   THEN
   116 QUICKER 0 EVERY? IF  0 NOSE 4 12 380 RANKED AIMED O-M C-ORG ORBK FAN  THEN ;
: B2-P1 ( -- )
   170 40 EVERY? IF
      MX @ 34 PX> -  MY @   80 LASER
      MX @ 34 PX> +  MY @  -80 LASER
   THEN
   11 0 EVERY? IF  8 NOSE 340 RANKED MT @ 11 * O-S C-PNK ORBK SHOOT  THEN ;
: WALL ( -- )
   \ a row of falling shots with a gap above the player
   PL-X @ >PX 16 / { gap }
   16 0 DO
      I gap - ABS 2 > IF
         I 16 * 8 + PX>  -6 PX>  330 RANKED 64 O-M C-RED ORBK SHOOT
      THEN
   LOOP ;
: B2-P2 ( -- )
   150 QUICKER 0 EVERY? IF WALL THEN
   84 QUICKER 13 EVERY? IF  0 NOSE 8 340 RANKED MT @ 3 * O-M C-ORG ORBK BURST  THEN
   15 0 EVERY? IF  14 NOSE 480 RANKED AIMED NEEDLE-R SHOOT  THEN ;
: AI-B2 ( -- )
   72 BOSS-IN? IF EXIT THEN
   44 SWAY
   PH CASE  0 OF B2-P0 ENDOF  1 OF B2-P1 ENDOF  2 OF B2-P2 ENDOF  ENDCASE ;

\ Boss three.
: B3-P0 ( -- )
   4 0 EVERY? IF
      MT @ SIN 40 * 1024 / MT @ 3 * +
      DUP  0 NOSE 280 RANKED ROT O-S C-GRN ORBK SHOOT
      128 + 0 NOSE 280 RANKED ROT O-S C-YEL ORBK SHOOT
   THEN
   110 QUICKER 0 EVERY? IF  0 NOSE 3 16 440 RANKED AIMED NEEDLE-R FAN  THEN ;
: B3-P1 ( -- )
   220 30 EVERY? IF
      MX @  MY @  0 LASER
      PL-X @ 56 PX> -  MY @  60 LASER
      PL-X @ 56 PX> +  MY @ -60 LASER
   THEN
   58 QUICKER 0 EVERY? IF  0 NOSE 12 300 RANKED MT @ 2* O-M C-PNK ORBK BURST  THEN ;
: B3-P2 ( -- )
   7 0 EVERY? IF
      MT @ 9 *  3 0 DO  DUP I 85 * +  0 NOSE ROT 300 RANKED SWAP O-S C-YEL ORBK SHOOT  LOOP  DROP
   THEN
   84 QUICKER 0 EVERY? IF  0 NOSE 14 360 RANKED MT @ O-M C-RED ORBK BURST  THEN
   300 150 EVERY? IF  MX @ 40 PX> -  MY @  70 LASER   MX @ 40 PX> +  MY @  -70 LASER  THEN ;
: AI-B3 ( -- )
   70 BOSS-IN? IF EXIT THEN
   40 SWAY
   PH CASE  0 OF B3-P0 ENDOF  1 OF B3-P1 ENDOF  2 OF B3-P2 ENDOF  ENDCASE ;

: BOSS-EXTRA { x y -- }   \ a core that pulses over the boss's hull
   CLOCK @ 8 * SIN 3 * 1024 / { d }
   x y 10 d + $F05018 DISC   x y 7 d + $FFB040 DISC   x y 3 d + $FFFFE0 DISC ;

\ Parts follow the boss at an offset and fire by themselves.
: PARENT-GONE? ( -- flag )   ME @ EPAR @ EAI @ 0= ;
: AI-CANNON ( -- )
   PARENT-GONE? IF FREE-ME EXIT THEN
   ME @ EPAR @ EX @ MA @ + MX !
   ME @ EPAR @ EY @ MB @ + MY !
   130 QUICKER MC @ EVERY?  ME @ EPAR @ EIMM @ 0= AND IF
      HERE-AT 3 14 400 RANKED AIMED O-M C-PNK ORBK FAN
   THEN ;

\ Orbiters circle the boss; EA is the angle in 1/16ths and EB the radius.
: AI-ORBIT ( -- )
   PARENT-GONE? IF FREE-ME EXIT THEN
   MC @ MA +!
   ME @ EPAR @ EX @  MB @ PX> MA @ 16 / COS * 1024 / +  MX !
   ME @ EPAR @ EY @  MB @ PX> MA @ 16 / SIN * 1024 / +  MY !
   110 QUICKER MB @ EVERY?  ME @ EPAR @ EIMM @ 0= AND IF
      HERE-AT 440 RANKED AIMED O-M C-GRN ORBK SHOOT
   THEN ;

VARIABLE T-DART-F                       \ the dart type, set when the types are made
: AI-CARRIER ( -- )
   MY @ MA @ < IF 300 MVY ! ELSE
      0 MVY !  MT @ SIN 28 * 4 /  MB @ + MX !
      90 0 EVERY? IF
         MX @  MC @ 1 AND IF 44 ELSE -44 THEN PX> +   MY @  T-DART-F @ E-NEW  { e }
         300 RND 150 - e EB !   1 MC +!
      THEN
      80 QUICKER 40 EVERY? IF  HERE-AT 7 16 360 RANKED AIMED O-M C-ORG ORBK FAN  THEN
      MT @ 1100 > IF 300 MVY ! THEN
   THEN
   CHECK-OUT ;

\ ---- The kinds of enemy ---------------------------------------------------------------

0 0 1 0 150  7 8   1 SPR-WEAVER ' AI-WEAVE ETYPE: T-WEAVE
0 0 1 0 200  6 7   1 SPR-DART ' AI-DART ETYPE: T-DART
T-DART T-DART-F !
0 0 1 0 250  7 7   1 0 ' AI-SWOOP ETYPE: T-SWOOP
0 0 1 0 300  6 6   1 0 ' AI-HUNT ETYPE: T-HUNT
0 0 4 0 2000 14 17 18 SPR-GUN ' AI-GUN ETYPE: T-GUN
0 0 3 0 1500 12 12 12 0 ' AI-SPIN ETYPE: T-SPIN
0 0 1 ' MINE-BURST 400 6 7 3 SPR-MINE ' AI-MINE ETYPE: T-MINE
' TURRET-BARREL F-GROUND 2 0 800 7 7 6 SPR-TURRET ' AI-TURRET ETYPE: T-TURRET
0 0 12 0 12000 22 36 150 SPR-CARRIER ' AI-CARRIER ETYPE: T-CARRIER
' BOSS-EXTRA F-BOSS 0 0 50000 30 62 750 SPR-BOSS1 ' AI-B1 ETYPE: T-BOSS1
' BOSS-EXTRA F-BOSS 0 0 80000 32 54 950 SPR-BOSS2 ' AI-B2 ETYPE: T-BOSS2
' BOSS-EXTRA F-BOSS 0 0 120000 34 44 1100 SPR-BOSS3 ' AI-B3 ETYPE: T-BOSS3
0 F-PART 4 0 6000 9 8 70 SPR-CANNON ' AI-CANNON ETYPE: T-CANNON
0 F-PART 3 0 5000 8 8 50 SPR-ORBITER ' AI-ORBIT ETYPE: T-ORBITER

\ ---- Spawning ------------------------------------------------------------------------

: DELAY! ( n e -- )   EWAIT ! ;
: W-COLUMN ( x -- )
   { x } 6 0 DO
      x PX>  -18 PX>  T-WEAVE E-NEW  { e }
      I 14 * e DELAY!  x PX> e EA !  70 RND e EB !
   LOOP ;
: W-VEE ( x -- )
   { x } 5 0 DO
      x I 2 - 22 * + PX>  -16 PX>  T-DART E-NEW  { e }
      I 2 - ABS 8 * e DELAY!   300 RND 150 - e EB !
   LOOP ;
: W-SWOOP ( side -- )
   { side } 6 0 DO
      side IF 262 ELSE -22 THEN PX>  36 I 7 * + PX>  T-SWOOP E-NEW  { e }
      I 11 * e DELAY!
      side IF 128 ELSE 0 THEN 16 * e EA !
      side IF -5 ELSE 5 THEN e EB !
      ROT-SWOOP side IF 128 ELSE 0 THEN ROT-SPR e ESP !
   LOOP ;
: W-HUNT ( n -- )
   0 ?DO
      200 RND 20 + PX>  -14 PX>  T-HUNT E-NEW  { e }
      I 20 * e DELAY!  64 16 * e EA !  ROT-HUNTER 64 ROT-SPR e ESP !
   LOOP ;
: W-GUN ( x -- )
   { x } x PX>  -20 PX>  T-GUN E-NEW  { e }
   50 RND 40 + PX> e EA ! ;
: W-GUN2 ( x -- )   DUP W-GUN  W SWAP - W-GUN ;
: W-SPIN ( x -- )
   PX> -24 PX> T-SPIN E-NEW  { e }  SPIN-TAB @ e ESP ! ;
: W-MINES ( n -- )
   0 ?DO  200 RND 20 + PX>  -14 PX>  T-MINE E-NEW  I 26 * SWAP DELAY!  LOOP ;
: W-TURRETS ( n -- )
   { n } n 0 ?DO
      W n 1+ / I 1+ * PX>  -14 PX>  T-TURRET E-NEW DROP
   LOOP ;
: W-CARRIER ( x -- )
   PX> -40 PX> T-CARRIER E-NEW  { e }
   64 PX> e EA !   e EX @ e EB ! ;

: E-CLEAR ( -- )   MAX-E 0 DO  0 I EAI !  LOOP ;

: PART! { typ dx dy phase -- }
   BOSS-I @ EX @ dx PX> +  BOSS-I @ EY @ dy PX> +  typ E-NEW  { e }
   BOSS-I @ e EPAR !   dx PX> e EA !   dy PX> e EB !   phase e EC !
   typ T-ORBITER = IF  dx 16 * e EA !   dy e EB !   phase e EC !  THEN ;

: SPAWN-BOSS ( typ -- )   { typ }
   W 2/ PX>  -70 PX>  typ E-NEW  DUP BOSS-I !  DROP
   typ T.HP @ BOSS-MAX !
   TRUE BOSS-I @ EIMM !  ;

: BOSS-1 ( -- )
   T-BOSS1 SPAWN-BOSS
   T-CANNON -44 18 0 PART!   T-CANNON 44 18 38 PART! ;
: BOSS-2 ( -- )
   T-BOSS2 SPAWN-BOSS
   T-CANNON -36 26 0 PART!  T-CANNON 36 26 25 PART!
   T-CANNON -18 8 12 PART!  T-CANNON 18 8 50 PART! ;
: BOSS-3 ( -- )
   T-BOSS3 SPAWN-BOSS
   6 0 DO  T-ORBITER  I 256 * 6 /  58  3  PART!  LOOP ;

\ ---- The stages -----------------------------------------------------------------------

: W> ( sec*2 xt arg -- )   ROT 125 * 4 / ,  SWAP , , ;

CREATE WAVES-1
   4 ' W-COLUMN 60 W>     8 ' W-COLUMN 180 W>     14 ' W-VEE 120 W>
  20 ' W-SWOOP 0 W>      24 ' W-SWOOP 1 W>        30 ' W-GUN 120 W>
  36 ' W-COLUMN 40 W>    36 ' W-COLUMN 200 W>     44 ' W-VEE 70 W>
  46 ' W-VEE 170 W>      54 ' W-HUNT 3 W>         60 ' W-SPIN 120 W>
  68 ' W-GUN2 60 W>      76 ' W-MINES 5 W>        82 ' W-SWOOP 0 W>
  84 ' W-SWOOP 1 W>      92 ' W-CARRIER 120 W>   118 ' W-HUNT 4 W>
 124 ' W-VEE 120 W>     130 ' W-COLUMN 120 W>    -1 , 0 , 0 ,

CREATE WAVES-2
   4 ' W-TURRETS 3 W>    10 ' W-COLUMN 60 W>      14 ' W-TURRETS 4 W>
  20 ' W-SWOOP 1 W>      24 ' W-VEE 120 W>        30 ' W-GUN2 70 W>
  36 ' W-TURRETS 5 W>    42 ' W-SPIN 60 W>        46 ' W-SPIN 180 W>
  52 ' W-HUNT 4 W>       58 ' W-TURRETS 4 W>      62 ' W-COLUMN 40 W>
  62 ' W-COLUMN 200 W>   70 ' W-MINES 7 W>        76 ' W-SWOOP 0 W>
  78 ' W-SWOOP 1 W>      86 ' W-GUN2 50 W>        92 ' W-CARRIER 120 W>
 118 ' W-TURRETS 5 W>   124 ' W-VEE 70 W>        124 ' W-VEE 170 W>
 130 ' W-HUNT 5 W>       -1 , 0 , 0 ,

CREATE WAVES-3
   4 ' W-VEE 120 W>       8 ' W-TURRETS 5 W>      12 ' W-SWOOP 0 W>
  14 ' W-SWOOP 1 W>      20 ' W-SPIN 120 W>       24 ' W-GUN2 60 W>
  30 ' W-TURRETS 6 W>    36 ' W-HUNT 6 W>         42 ' W-COLUMN 40 W>
  42 ' W-COLUMN 120 W>   42 ' W-COLUMN 200 W>     50 ' W-SPIN 60 W>
  50 ' W-SPIN 180 W>     58 ' W-MINES 9 W>        64 ' W-GUN2 60 W>
  68 ' W-GUN 120 W>      76 ' W-TURRETS 6 W>      80 ' W-SWOOP 0 W>
  82 ' W-SWOOP 1 W>      90 ' W-CARRIER 80 W>     92 ' W-CARRIER 160 W>
 118 ' W-HUNT 6 W>      124 ' W-VEE 70 W>        124 ' W-VEE 170 W>
 130 ' W-TURRETS 6 W>    -1 , 0 , 0 ,

CREATE STAGE-WAVES   WAVES-1 ,  WAVES-2 ,  WAVES-3 ,
CREATE STAGE-BOSSES  ' BOSS-1 , ' BOSS-2 , ' BOSS-3 ,
CREATE STAGE-TUNES   TUNE-1 , TUNE-2 , TUNE-3 ,
3 CONSTANT #STAGES

: STAGE-NAME ( -- c-addr u )
   STG @ CASE
      0 OF S" ORBITAL DEBRIS" ENDOF
      1 OF S" OCEAN WORLD" ENDOF
      2 OF S" IRON CITADEL" ENDOF
      S" " ROT
   ENDCASE ;

\ ---- Backgrounds: a picture of color numbers made for each stage ---------------------
\ The background is a strip of W by STRIP color numbers that scrolls round, drawn with
\ the colors of a palette.

512 CONSTANT STRIP
W STRIP INDEXED: BACKDROP
PALETTE: BG-PAL

\ Fills the strip with the color numbers xt ( x y -- n ) gives.
: BAKE-STRIP { xt | row -- }
   STRIP 0 DO
      BACKDROP INDEXED-DATA I W * + TO row
      W 0 DO  I J xt EXECUTE  row I + C!  LOOP
   LOOP ;

\ The strip from where the scroll has come to, twice so that it goes round, and black
\ where the shake leaves the screen uncovered.
: DRAW-STRIP ( -- )
   SCROLL @ >PX  SHX @ SHY @ { sc ox oy | y0 -- }
   oy sc + STRIP 1- AND TO y0
   ox y0 BACKDROP BG-PAL -1 DRAW-INDEXED
   ox y0 STRIP - BACKDROP BG-PAL -1 DRAW-INDEXED
   ox 0> IF  0 0 ox H 0 BAR-RECT  THEN
   ox 0< IF  W ox + 0 ox NEGATE H 0 BAR-RECT  THEN ;

\ Noise: smooth random values on a lattice, wrapped along the strip.
CREATE NT 256 ALLOT
: INIT-NOISE ( -- )   256 0 DO  256 RND NT I + C!  LOOP ;
: LAT ( ix iy -- v )   57 * +  251 MOD  NT + C@ ;
: VN { x y c | ix iy tx ty p a b -- v }
   x c / TO ix   y c / TO iy
   x c MOD 256 c */ TO tx   y c MOD 256 c */ TO ty
   STRIP c / TO p
   ix iy LAT   ix 1+ iy LAT   OVER - tx * 256 / +  TO a
   ix iy 1+ p MOD LAT   ix 1+ iy 1+ p MOD LAT   OVER - tx * 256 / +  TO b
   a  b a - ty * 256 / + ;
: FBM ( x y -- v )
   2DUP 64 VN 4 * >R  2DUP 32 VN 2* >R  16 VN  R> + R> +  7 / ;

: LEVEL ( v lo step n -- idx )   >R >R - R> / 0 MAX R> 1- MIN ;

: PX-SPACE ( x y -- idx )   FBM 92 22 8 LEVEL ;
CREATE PAL-SPACE  $06060F , $0A0A1C , $10102A , $181438 , $221846 , $301C52 , $40205C , $502864 ,

\ The water of each depth has eight color numbers, 16 + 8 * depth on, by the height of
\ the noise: lines of the same height, which shine when their colors turn.
: WATER ( v depth -- idx )   8 * 16 +  SWAP 4 / 7 AND + ;
: PX-OCEAN ( x y -- idx )
   FBM  DUP 104 < IF 0 WATER EXIT THEN  DUP 118 < IF 1 WATER EXIT THEN  DUP 128 < IF 2 WATER EXIT THEN
   DUP 134 < IF DROP 3 EXIT THEN  DUP 150 < IF DROP 4 EXIT THEN  DUP 166 < IF DROP 5 EXIT THEN
   178 < IF 6 ELSE 7 THEN ;
CREATE PAL-OCEAN  $103870 , $185090 , $2878B0 , $D8C890 , $58A048 , $387838 , $706858 , $E8ECF0 ,
\ The eight colors of each depth: its own, and two that shine.
: WATER-COLORS ( -- )
   3 0 DO
      I CELLS PAL-OCEAN + @ { base }
      8 0 DO
         base $FFFFFF  I 0= IF 56 ELSE I 1 = IF 20 ELSE 0 THEN THEN  MIX-RGB
         16 J 8 * + I + BG-PAL PALETTE!
      LOOP
   LOOP ;
\ The water's colors turn by one each few steps.
: TURN-WATER ( -- )
   STG @ 1 =  CLOCK @ 5 MOD 0= AND IF
      3 0 DO  16 I 8 * + 8 BG-PAL ROTATE-PALETTE  LOOP
   THEN ;

: HASH2 ( ix iy -- v )   16 MOD 57 * + 7 * 251 MOD NT + C@ ;
: PX-FORT { x y | tx ty u v r d -- idx }
   x 32 / TO tx   y 32 / TO ty   x 31 AND TO u   y 31 AND TO v
   tx ty HASH2 TO r
   r 4 MOD 0= IF 3 ELSE 2 THEN TO d                 \ plate shade
   r 8 MOD 3 = IF  u 8 28 WITHIN v 8 28 WITHIN AND IF
      u 4 AND IF 4 ELSE 1 THEN TO d  THEN THEN      \ a vent
   r 8 MOD 5 = IF  u 13 18 WITHIN v 13 18 WITHIN OR IF 5 TO d THEN THEN   \ a brace
   u 0=  v 0= OR IF 0 TO d THEN
   u 31 =  v 31 = OR IF 6 TO d THEN
   u 3 =  v 3 = AND  u 28 =  v 3 = AND OR  u 3 = v 28 = AND OR  u 28 = v 28 = AND OR IF 7 TO d THEN
   d ;
CREATE PAL-FORT   $10121C , $202436 , $343A50 , $3E465E , $4E5674 , $5E6884 , $707A98 , $B8C0D0 ,

CREATE STAGE-PIX   ' PX-SPACE , ' PX-OCEAN , ' PX-FORT ,
CREATE STAGE-PALS  PAL-SPACE , PAL-OCEAN , PAL-FORT ,

: BAKE-STAGE ( -- )
   777 SEED !  INIT-NOISE
   STG @ CELLS STAGE-PALS + @  BG-PAL  8 CELLS MOVE
   STG @ 1 = IF WATER-COLORS THEN
   STG @ CELLS STAGE-PIX + @ BAKE-STRIP
   CLOCK @ 12345 + SEED ! ;

\ The layers above the strip.
64 CONSTANT MAX-STAR
CREATE STAR-X MAX-STAR CELLS ALLOT   CREATE STAR-Y MAX-STAR CELLS ALLOT
: INIT-STARS ( -- )
   MAX-STAR 0 DO  W RND I CELLS STAR-X + !   H PX> RND I CELLS STAR-Y + !  LOOP ;
: DRAW-STARS ( -- )
   MAX-STAR 0 DO
      I 3 MOD { layer }
      layer 1+ 90 * I CELLS STAR-Y + +!
      I CELLS STAR-Y + @  H PX> >= IF
         0 I CELLS STAR-Y + !   W RND I CELLS STAR-X + !
      THEN
      I CELLS STAR-X + @  SHX @ +  { sx }
      I CELLS STAR-Y + @ >PX SHY @ +  { sy }
      layer 2 = IF  sx sx 1+ sy $F0F4FF  ELSE
      layer 1 = IF  sx sx sy $9098C0  ELSE  sx sx sy $505878  THEN THEN  GFX-HLINE
   LOOP ;

6 CONSTANT MAX-CLOUD
: DRAW-CLOUDS ( -- )
   MAX-CLOUD 0 DO
      I 53 * 17 + 300 MOD 30 -
      SCROLL @ >PX 2* I 97 * + 460 MOD 90 -
      I 1 AND IF SPR-CLOUD1 ELSE SPR-CLOUD2 THEN  3 176 BLIT-AS     \ two thirds seen
   LOOP ;

: DRAW-FORT-LIGHTS ( -- )
   CLOCK @ 4 * SIN 90 * 1024 / 150 +  { g }
   g 8 RSHIFT 0 MAX   g  255 AND  { a b }
   a 16 LSHIFT b 8 LSHIFT OR b OR { c }
   56 SHX @ + 0 2 H c BAR-RECT
   182 SHX @ + 0 2 H c BAR-RECT ;

CREATE STAGE-OVER  ' DRAW-STARS , ' DRAW-CLOUDS , ' DRAW-FORT-LIGHTS ,

\ ---- The player ------------------------------------------------------------------------

48 CONSTANT MAX-S
: S-FIELD ( "name" -- )   CREATE MAX-S CELLS ALLOT  DOES> SWAP CELLS + ;
S-FIELD SX  S-FIELD SY  S-FIELD SVX  S-FIELD SVY  S-FIELD SDMG  S-FIELD SSPR  S-FIELD SHM
VARIABLE S-CUR

: NEW-SHOT { x y vx vy dmg spr homing | s -- }
   S-CUR @ TO s   s 1+ MAX-S MOD S-CUR !
   x s SX !  y s SY !  vx s SVX !  vy s SVY !  dmg s SDMG !  spr s SSPR !  homing s SHM ! ;

: BOLT { x dx -- }   \ a shot from x going mostly up
   PL-X @ x +  PL-Y @ 8 PX> -  dx  -2600  1  SPR-BOLT  0 NEW-SHOT ;
: SPREAD-SHOT { x a -- }
   PL-X @ x +  PL-Y @ 6 PX> -  2500 a POLAR  1  SPR-SPREAD  0 NEW-SHOT ;
: FOCUS-SHOT { x -- }
   PL-X @ x +  PL-Y @ 10 PX> -  0 -3200  2  SPR-FOCUS  0 NEW-SHOT ;
: MISSILE { x a -- }
   PL-X @ x +  PL-Y @  900 a POLAR  4  ROT-MISSILE a ROT-SPR  1 NEW-SHOT ;

: POD-X ( -- px )   PL-SLOW @ IF 14 ELSE 26 THEN ;

: FIRE-WIDE ( -- )
   POWER @ 1 > IF
      POWER @ 3 >= IF  -5 PX> 188 SPREAD-SHOT  5 PX> 196 SPREAD-SHOT  THEN
      POWER @ 4 >= IF  -7 PX> 172 SPREAD-SHOT  7 PX> 212 SPREAD-SHOT  THEN
   THEN
   POWER @ 1 > IF  -4 PX> -40 BOLT   4 PX> 40 BOLT  THEN
   0 0 BOLT ;

: FIRE-TIGHT ( -- )
   0 FOCUS-SHOT   POWER @ 2 >= IF  -5 PX> FOCUS-SHOT  5 PX> FOCUS-SHOT  THEN ;

: FIRE-PODS ( -- )
   POWER @ 3 < IF EXIT THEN
   POD-X PX> DUP NEGATE 0 BOLT  0 BOLT ;

: FIRE-MISSILES ( -- )
   POWER @ 5 < IF EXIT THEN
   FIRE-T @ 24 MOD 0= IF  POD-X PX> DUP NEGATE 168 MISSILE  216 MISSILE  THEN ;

: PLAYER-FIRE ( -- )
   1 FIRE-T +!
   IN-FIRE @ AUTO-FIRE @ OR 0= IF EXIT THEN
   FIRE-T @ 4 MOD 0= IF
      PL-SLOW @ IF FIRE-TIGHT ELSE FIRE-WIDE THEN
      FIRE-PODS  S-SHOT EFFECT
   THEN
   FIRE-MISSILES ;

: NEAREST-TARGET { sx-fx sy-fx | best d e -- e|-1 }
   -1 TO e  $7FFFFFFFFFFF TO best
   MAX-E 0 DO
      I EAI @ IF  I EWAIT @ 0= I EIMM @ 0= AND  I ETY @ T.FLAG @ F-GROUND AND 0= AND IF
         I EX @ sx-fx - ABS  I EY @ sy-fx - ABS +  TO d
         d best < IF  d TO best  I TO e  THEN
      THEN THEN
   LOOP e ;

: SHOTS-TICK ( -- )
   MAX-S 0 DO
      I SSPR @ IF
         I SHM @ IF
            I SX @ I SY @ NEAREST-TARGET  { tgt }
            tgt 0>= IF
               tgt EX @ I SX @ -  tgt EY @ I SY @ -  ATAN  { a }
               600 a POLAR  I SVY @ 3 * + 4 /  SWAP  I SVX @ 3 * + 4 /  SWAP
               I SVY !  I SVX !
               ROT-MISSILE a ROT-SPR I SSPR !
            THEN
         THEN
         I SVX @ I SX +!   I SVY @ I SY +!
         I SY @ >PX -10 <  I SY @ >PX H 10 + > OR
         I SX @ >PX -10 W 10 + WITHIN 0= OR IF  0 I SSPR !  THEN
      THEN
   LOOP ;

: SPAWN-PLAYER ( -- )
   W 2/ PX> PL-X !   H 40 - PX> PL-Y !   120 INV !  0 DEAD ! ;

: START-GAME ( -- )
   0 STG !  0 SCORE !  3 LIVES !  3 BOMBS !  1 POWER !
   0 CHAIN !  0 CHAIN-T !  200000 NEXT-EXT !  0 GRAZE !  0 KILLS !  SPAWN-PLAYER ;

\ ---- Damage ------------------------------------------------------------------------

DEFER BOSS-FALL
: DROPS { x y n -- }   n 0 ?DO  x y IT-GEM NEW-ITEM  LOOP ;
: AWARD-DROPS { x y typ -- }
   typ T.DROP @ { n }
   x y n DROPS
   n 3 >= IF  x y  IT-P IT-B 8 RND 0= IF NIP ELSE DROP THEN  NEW-ITEM  THEN ;

\ Every 16th kill leaves a capsule, every fifth of those a bomb.
: KILL-PRIZE { x y -- }
   1 KILLS +!
   KILLS @ 16 MOD IF EXIT THEN
   x y  KILLS @ 80 MOD IF IT-P ELSE IT-B THEN  NEW-ITEM ;

: KILL-E { e | typ x y -- }
   e ETY @ TO typ   e EX @ TO x   e EY @ TO y
   e ME !
   typ T.KILL @ ?DUP IF EXECUTE THEN
   typ T.PTS @ MULT * ADD-SCORE
   1 CHAIN +!  90 CHAIN-T !
   x y typ AWARD-DROPS   x y KILL-PRIZE
   x y  typ T.HH @ 2* 8 MAX 40 MIN  BLAST
   x y  typ T.HH @ 6 MIN 4 + 900 RAMP-FIRE SPARKS
   typ T.HH @ 12 > IF  S-BOOM EFFECT  10 SHAKE!  ELSE  S-POP EFFECT  THEN
   0 e EAI ! ;

: HIT-E { dmg e -- }
   dmg NEGATE e EHP +!   3 e EF !
   S-HIT EFFECT
   e EHP @ 0> IF EXIT THEN
   e ETY @ T.FLAG @ F-BOSS AND IF  e BOSS-FALL  ELSE  e KILL-E  THEN ;

\ A shot hits an enemy where their pictures show a pixel at the same place; the
\ rectangles of the pictures are compared first, which is quicker.
: E-STRUCK? { x y spr e | p -- flag }
   e ESP @ TO p  p 0= IF FALSE EXIT THEN
   x e EX @ - ABS >PX  p SPRITE-W @ spr SPRITE-W @ + >=  IF FALSE EXIT THEN
   y e EY @ - ABS >PX  p SPRITE-H @ spr SPRITE-H @ + >=  IF FALSE EXIT THEN
   x >PX y >PX spr  e EX @ >PX e EY @ >PX p  PICS-HIT? ;

: SHOTS-HIT ( -- )
   MAX-S 0 DO
      I SSPR @ IF
         I { s } I SX @ I SY @ { x y }
         MAX-E 0 DO
            I EAI @ IF  I EWAIT @ 0=  I EIMM @ 0= AND IF
               x y s SSPR @ I E-STRUCK? IF
                  x y 2 300 RAMP-ICE SPARKS
                  s SDMG @ I HIT-E
                  0 s SSPR !
                  LEAVE
               THEN
            THEN THEN
         LOOP
      THEN
   LOOP ;

: BOMB-DAMAGE ( amount -- )
   { amount }
   MAX-E 0 DO
      I EAI @ IF  I EWAIT @ 0=  I EIMM @ 0= AND  I EY @ >PX -20 H WITHIN AND IF
         amount I HIT-E
      THEN THEN
   LOOP ;

: USE-BOMB ( -- )
   BOMBS @ 1 <  DEAD @ OR  BOMB-T @ OR IF EXIT THEN
   -1 BOMBS +!   80 BOMB-T !   100 INV @ MAX INV !
   FALSE CANCEL-SHOTS   LASER-ERASE
   S-BOMB EFFECT   24 SHAKE!   16 FLASH !
   30 BOMB-DAMAGE ;

: KILL-PLAYER ( -- )
   INV @ DEAD @ OR IF EXIT THEN
   PL-X @ PL-Y @ 30 BLAST
   PL-X @ PL-Y @ 24 800 RAMP-ICE SPARKS
   S-DIE EFFECT  20 SHAKE!
   TRUE CANCEL-SHOTS   LASER-ERASE
   -1 LIVES +!   3 BOMBS !   0 CHAIN !
   POWER @ 1- 1 MAX POWER !
   PL-X @ PL-Y @ IT-P NEW-ITEM
   90 DEAD ! ;

: B-HIT-TEST ( -- )
   \ enemy shots against the ship
   PL-X @ PL-Y @ { px py }
   MAX-B 0 DO
      I BSP @ IF
         I BX @ px - ABS  I BY @ py - ABS  { dx dy }
         dx 15 PX> <  dy 15 PX> < AND IF
            I BR @ 2 + PX> { r }
            dx r < dy r < AND IF
               KILL-PLAYER  0 I BSP !
            ELSE
               I BGZ @ 0= IF
                  TRUE I BGZ !  1 GRAZE +!  50 MULT * ADD-SCORE
                  I BX @ I BY @ 2 260 RAMP-GLD SPARKS  S-GRAZE EFFECT
               THEN
            THEN
         THEN
      THEN
   LOOP ;

: E-HIT-TEST ( -- )
   \ bodies and lasers against the ship
   INV @ IF EXIT THEN
   MAX-E 0 DO
      I EAI @ IF  I EWAIT @ 0= IF
         I ETY @ { t }
         t T.FLAG @ F-GROUND AND 0= IF
            I EX @ PL-X @ - ABS  t T.HW @ 1- PX> <
            I EY @ PL-Y @ - ABS  t T.HH @ 1- PX> < AND IF  KILL-PLAYER  THEN
         THEN
      THEN THEN
   LOOP ;

: L-HIT-TEST ( -- )
   INV @ IF EXIT THEN
   MAX-LZ 0 DO
      I CELLS LZT + @ DUP LZ-WARN >=  SWAP LZ-END <= AND IF
         I CELLS LZX + @ PL-X @ - ABS  LZ-HALF PX> < IF  KILL-PLAYER  THEN
      THEN
   LOOP ;

\ ---- Boss falling, phases ------------------------------------------------------------

: AI-FALL ( -- )
   MT @ 150 < IF
      6 0 EVERY? IF
         MX @ 110 RND 55 - PX> +   MY @ 60 RND 30 - PX> +  24 RND 14 +  BLAST
         S-BOOM EFFECT  8 SHAKE!  WOBBLE @ 16 MAX WOBBLE !
      THEN
   ELSE
      MX @ MY @ 48 BLAST   MX @ MY @ 60 1400 RAMP-FIRE SPARKS
      MX @ MY @ 60 1000 RAMP-GLD SPARKS
      30 SHAKE!  20 FLASH !  48 WOBBLE !  S-BOMB EFFECT
      MX @ MY @ 30 DROPS
      FREE-ME
      3 PHASE !  0 PHASE-T !
   THEN ;

:NONAME ( e -- )
   { e }
   ['] AI-FALL e EAI !   0 e ET !   TRUE e EIMM !  0 e EVX !  40 e EVY !
   TRUE CANCEL-SHOTS   LASER-ERASE
   e ETY @ T.PTS @ MULT * ADD-SCORE ; IS BOSS-FALL

\ ---- The items' and enemies' steps ----------------------------------------------------

: ITEM-TAKE { n -- }
   n ITY @ CASE
      IT-P OF  POWER @ 5 < IF 1 POWER +! THEN  1000 ADD-SCORE  S-POWER EFFECT  ENDOF
      IT-B OF  BOMBS @ 5 < IF 1 BOMBS +! THEN  1000 ADD-SCORE  S-POWER EFFECT  ENDOF
      IT-GEM OF  200 MULT * ADD-SCORE  S-ITEM EFFECT  ENDOF
   ENDCASE
   n IX @ n IY @ 5 500 RAMP-GLD SPARKS
   IT-NONE n ITY ! ;

: ITEMS-TICK ( -- )
   MAX-I 0 DO
      I ITY @ IF
         I IVX @ I IX +!   I IVY @ I IY +!
         I IVX @ 31 * 32 / I IVX !
         I IVY @ 12 + 260 MIN I IVY !
         PL-X @ I IX @ -  PL-Y @ I IY @ -   { dx dy }
         dx ABS 56 PX> <  dy ABS 56 PX> < AND  DEAD @ 0= AND  I ITY @ IT-GEM = AND IF
            dx 16 / I IX +!  dy 16 / I IY +!
         THEN
         dx ABS 11 PX> <  dy ABS 11 PX> < AND  DEAD @ 0= AND IF
            I ITEM-TAKE
         ELSE
            I IY @ >PX H 10 + > IF  IT-NONE I ITY !  THEN
         THEN
      THEN
   LOOP ;

: ENEMIES-TICK ( -- )
   MAX-E 0 DO
      I EAI @ IF
         I EWAIT @ IF  -1 I EWAIT +!  ELSE
            I ME !
            1 MT +!
            ME @ EAI @ EXECUTE
            I EAI @ IF
               MVX @ MX +!  MVY @ MY +!
               I EF @ IF  -1 I EF +!  THEN
            THEN
         THEN
      THEN
   LOOP ;

: BULLETS-TICK ( -- )
   MAX-B 0 DO
      I BSP @ IF
         I BAX @ I BVX +!   I BAY @ I BVY +!
         I BVX @ I BX +!    I BVY @ I BY +!
         I BX @ >PX  -8 W 8 + WITHIN  I BY @ >PX -8 H 8 + WITHIN AND 0= IF  0 I BSP !  THEN
      THEN
   LOOP ;

: PLAYER-TICK ( -- )
   DEAD @ IF
      -1 DEAD +!
      DEAD @ 0= IF
         LIVES @ 0< IF  M-OVER MODE !  0 MODE-T !  ELSE SPAWN-PLAYER THEN
      THEN
      EXIT
   THEN
   INV @ IF -1 INV +! THEN
   IN-SLOW @ PL-SLOW !
   IN-L @ IN-R @ - DUP PL-TURN !  { dx }     \ a held key's flag is -1
   IN-U @ IN-D @ - { dy }
   PL-SLOW @ IF 390 ELSE 790 THEN  { v }
   dx 0<> dy 0<> AND IF  v 181 * 256 / TO v  THEN
   dx v * PL-X +!   dy v * PL-Y +!
   PL-X @ 9 PX> W 9 - PX> CLAMP PL-X !
   PL-Y @ 12 PX> H 10 - PX> CLAMP PL-Y !
   PLAYER-FIRE
   PRESS-BOMB @ IF USE-BOMB THEN ;

: BOMB-TICK ( -- )
   BOMB-T @ IF
      -1 BOMB-T +!
      BOMB-T @ 8 MOD 0= IF  5 BOMB-DAMAGE  THEN
      FALSE CANCEL-SHOTS
   THEN ;

: CHAIN-TICK ( -- )
   CHAIN-T @ IF  -1 CHAIN-T +!  CHAIN-T @ 0= IF 0 CHAIN ! THEN  THEN ;

: FX-TICK ( -- )
   PARTICLES-TICK BLASTS-TICK LASERS-TICK
   SHAKE @ IF  -1 SHAKE +!  THEN
   FLASH @ IF  -1 FLASH +!  THEN   WOBBLE @ IF  -1 WOBBLE +!  THEN
   SCROLL-V @ SCROLL +! ;

: UPDATE-SHAKE ( -- )
   SHAKE @ IF  SHAKE @ 6 MIN { s }  s 2* 1+ RND s - SHX !  s 2* 1+ RND s - SHY !
   ELSE 0 SHX ! 0 SHY ! THEN ;

\ ---- Stage logic ------------------------------------------------------------------------

: FREE-ALL ( -- )
   E-CLEAR  MAX-B 0 DO 0 I BSP ! LOOP  MAX-S 0 DO 0 I SSPR ! LOOP
   MAX-I 0 DO IT-NONE I ITY ! LOOP  LASER-ERASE
   MAX-P 0 DO 0 I FLF ! LOOP  MAX-X 0 DO 0 I XLIFE ! LOOP ;

: GOTO ( m -- )   MODE !  0 MODE-T ! ;

: PLAY-TUNE ( tune -- )   START-MUSIC ;

: START-STAGE ( -- )
   FREE-ALL  BAKE-STAGE  INIT-STARS
   0 STAGE-T !  0 PHASE !  0 PHASE-T !  -1 BOSS-I !
   STG @ CELLS STAGE-WAVES + @ WAVE-PTR !
   0 SCROLL !   STG @ 1 = IF 180 ELSE 110 THEN SCROLL-V !
   STG @ CELLS STAGE-TUNES + @ PLAY-TUNE
   M-INTRO GOTO ;

: WAVE-TICK ( -- )
   BEGIN
      WAVE-PTR @ @  DUP -1 <>  SWAP STAGE-T @ <=  AND
   WHILE
      WAVE-PTR @ 2 CELLS + @  WAVE-PTR @ CELL+ @  EXECUTE
      WAVE-PTR @ 3 CELLS + WAVE-PTR !
   REPEAT ;

: CALM? ( -- flag )
   TRUE MAX-E 0 DO
      I EAI @ IF  I ETY @ T.FLAG @ F-GROUND AND 0= IF DROP FALSE LEAVE THEN  THEN
   LOOP ;

: PHASE-TICK ( -- )
   1 PHASE-T +!
   PHASE @ CASE
      0 OF
         WAVE-PTR @ @ -1 = IF
            CALM?  PHASE-T @ 800 >  OR IF
               S-WARN EFFECT   1 PHASE !  0 PHASE-T !
            THEN
         ELSE  0 PHASE-T !  THEN
      ENDOF
      1 OF
         PHASE-T @ 40 MOD 0= IF S-WARN EFFECT THEN
         PHASE-T @ 190 = IF
            TUNE-B PLAY-TUNE
            STG @ CELLS STAGE-BOSSES + @ EXECUTE
            2 PHASE !  0 PHASE-T !
         THEN
      ENDOF
      3 OF
         PHASE-T @ 200 = IF
            STOP-MUSIC
            LIVES @ 10000 *  BOMBS @ 3000 * +  ADD-SCORE
            M-CLEAR GOTO
         THEN
      ENDOF
   ENDCASE ;

: PLAY-TICK ( -- )
   1 STAGE-T +!
   WAVE-TICK PHASE-TICK
   PLAYER-TICK SHOTS-TICK ENEMIES-TICK BULLETS-TICK ITEMS-TICK
   BOMB-TICK CHAIN-TICK
   DEAD @ 0= IF  B-HIT-TEST E-HIT-TEST L-HIT-TEST  THEN
   SHOTS-HIT
   FX-TICK ;

: TITLE! ( -- )
   0 STG !  BAKE-STAGE  INIT-STARS  FREE-ALL
   TUNE-2 PLAY-TUNE  M-TITLE GOTO ;

: GAME-OVER-TICK ( -- )
   SCORE @ HI-SCORE @ MAX HI-SCORE !
   MODE-T @ 40 > PRESS-FIRE @ AND  MODE-T @ 400 > OR IF TITLE! THEN ;

: TITLE-TICK ( -- )
   SCROLL-V @ SCROLL +!
   PRESS-START @ PRESS-FIRE @ OR IF
      777 CLOCK @ + SEED !  START-GAME  START-STAGE
   THEN ;

: INTRO-TICK ( -- )
   SCROLL-V @ SCROLL +!
   MODE-T @ 130 > IF  M-PLAY GOTO  THEN ;

: CLEAR-TICK ( -- )
   FX-TICK
   SCORE @ HI-SCORE @ MAX HI-SCORE !
   MODE-T @ 300 > IF
      1 STG +!
      STG @ #STAGES >= IF
         1 STG !  BAKE-STAGE  TUNE-2 PLAY-TUNE
         S-EXTEND EFFECT  M-END GOTO
      ELSE START-STAGE THEN
   THEN ;

: END-TICK ( -- )
   SCORE @ HI-SCORE @ MAX HI-SCORE !
   FX-TICK
   MODE-T @ 60 > PRESS-FIRE @ AND  MODE-T @ 900 > OR IF TITLE! THEN ;

CREATE TICKERS  ' TITLE-TICK , ' INTRO-TICK , ' PLAY-TICK , ' CLEAR-TICK , ' GAME-OVER-TICK , ' END-TICK ,

: TICK ( -- )
   1 CLOCK +!  1 MODE-T +!
   UPDATE-SHAKE  TURN-WATER
   MODE @ CELLS TICKERS + @ EXECUTE
   FALSE PRESS-FIRE !  FALSE PRESS-BOMB !  FALSE PRESS-START ! ;

\ ---- Drawing ------------------------------------------------------------------------------

: DRAW-LAYER-BG ( -- )   DRAW-STRIP   STG @ CELLS STAGE-OVER + @ EXECUTE ;

: DRAW-E { e | t x y -- }
   e ETY @ TO t   e EX @ >PX TO x   e EY @ >PX TO y
   e EF @  t T.HH @ 16 < AND IF  x y e ESP @ BLIT-WHITE  ELSE  x y e ESP @ BLIT  THEN
   t T.EXTRA @ ?DUP IF
      t T-TURRET = IF  { xt } x y e EA @ xt EXECUTE
      ELSE  { xt } x y xt EXECUTE  THEN
   THEN ;

: DRAW-ENEMIES ( ground? -- )
   { ground }
   MAX-E 0 DO
      I EAI @ IF  I EWAIT @ 0= IF
         I ETY @ T.FLAG @ F-GROUND AND 0<> ground = IF  I DRAW-E  THEN
      THEN THEN
   LOOP ;

: DRAW-BULLETS ( -- )
   MAX-B 0 DO
      I BSP @ ?DUP IF  >R I BX @ >PX  I BY @ >PX  R> BLIT  THEN
   LOOP
   \ Their light, over them all.
   MAX-B 0 DO
      I BSP @ IF  I BGL @ ?DUP IF  >R I BX @ >PX  I BY @ >PX  R> GLOW  THEN  THEN
   LOOP ;

: DRAW-SHOTS ( -- )
   MAX-S 0 DO
      I SSPR @ ?DUP IF  >R I SX @ >PX  I SY @ >PX  R> BLIT  THEN
   LOOP ;

: DRAW-ITEMS ( -- )
   MAX-I 0 DO
      I ITY @ IF
         I IX @ >PX  I IY @ >PX  { x y }
         I ITY @ CASE
            IT-P OF  x y SPR-P BLIT   S" P" x 1- SHX @ + y 3 - SHY @ + $FFFFFF COLOR! TEXT  ENDOF
            IT-B OF  x y SPR-B BLIT   S" B" x 1- SHX @ + y 3 - SHY @ + $FFFFFF COLOR! TEXT  ENDOF
            IT-GEM OF  x y CLOCK @ 8 / 1 AND IF SPR-GEM ELSE SPR-GEM2 THEN BLIT  ENDOF
         ENDCASE
      THEN
   LOOP ;

: DRAW-LASERS ( -- )
   MAX-LZ 0 DO
      I CELLS LZT + @ { t }
      t IF
         I CELLS LZX + @ >PX SHX @ +   I CELLS LZY + @ >PX SHY @ + { x y }
         t LZ-WARN < IF
            CLOCK @ 2 AND IF  x y 1 H y - $F03030 BAR-RECT  THEN
         ELSE
            LZ-HALF t LZ-END 8 - > IF  LZ-END t - *  8 /  THEN  { hw }
            x hw - y hw 2* H y - $E02010 BAR-RECT
            x hw 2* 3 / -  y  hw 4 * 3 /  H y - $FF9040 BAR-RECT
            x hw 3 / -  y  hw 2* 3 /  H y - $FFFFE0 BAR-RECT
            x y 16 $FF9040 DISC  x y 9 $FFFFE0 DISC
            \ Its light along the beam (the shake is already in x and y).
            H y - 24 / 1+ 0 DO  x SHX @ -  y SHY @ - I 24 * +  LASER-GLOW GLOW  LOOP
         THEN
      THEN
   LOOP ;

: DRAW-SHIP ( -- )
   DEAD @ IF EXIT THEN
   PL-X @ >PX  PL-Y @ >PX  { x y }
   INV @ 3 AND 1 > IF EXIT THEN
   \ exhaust
   x 3 - SHX @ +  y 9 + SHY @ +  CLOCK @ 2 AND IF 7 ELSE 4 THEN  { ex ey len }
   ex ey 6 len $F06020 BAR-RECT   ex 1+ ey 4 len 2/ 1+ $FFE060 BAR-RECT
   x y PL-TURN @ IF SPR-BANK ELSE SPR-SHIP THEN BLIT
   POWER @ 3 >= IF
      x POD-X -  y 4 + SPR-POD BLIT
      x POD-X +  y 4 + SPR-POD BLIT
   THEN
   PL-SLOW @ IF
      x y 2 $FFFFFF DISC   x y 6 $40F0FF HOOP
   THEN ;

: DRAW-BOMB-WAVE ( -- )
   BOMB-T @ 0= IF EXIT THEN
   PL-X @ >PX  PL-Y @ >PX  { x y }
   80 BOMB-T @ - 6 * { r }
   x y r $FFFFFF HOOP  x y r 6 - $80D0FF HOOP  x y r 12 - $4080E0 HOOP ;

: DRAW-FLASH ( -- )
   FLASH @ 0= IF EXIT THEN
   FLASH @ 12 MIN 20 * { v }
   CLOCK @ 1 AND IF
      v 16 LSHIFT v 8 LSHIFT OR v OR  GFX-CLS
   THEN ;

\ A bomb, and a boss blowing up, ripple the rows of the screen: each row moves sideways
\ by its cell of a table, along a wave that runs down the screen.
CREATE RIPPLE-T  H CELLS ALLOT
: RIPPLE ( -- )
   BOMB-T @ 10 /  WOBBLE @ 6 /  MAX  { amp }
   amp 0= IF EXIT THEN
   H 0 DO  I 6 * CLOCK @ 8 * - SIN amp * 1024 /  RIPPLE-T I CELLS + !  LOOP
   RIPPLE-T 0 0 W H RASTER-SCROLL ;

\ The top line, the lives and bombs, and the boss's bar.
: HUD ( -- )
   1 TEXT-SCALE
   S" SCORE" 4 3 $90A8C8 STXT   SCORE @ 8 N>S0 30 3 $FFFFFF STXT
   S" HI" 92 3 $90A8C8 STXT     HI-SCORE @ SCORE @ MAX 8 N>S0 104 3 $FFE050 STXT
   MULT 1 > IF
      S" x" 170 3 $FF9040 STXT  MULT N>S 176 3 $FF9040 STXT
      CHAIN @ N>S 190 3 $C0C0C0 STXT   S" HIT" 206 3 $9098C0 STXT
   THEN
   \ lives, bombs, weapon level
   LIVES @ 0 MAX 7 MIN 0 ?DO  10 I 12 * +  H 8 -  SPR-ICON BLIT  LOOP
   BOMBS @ 0 ?DO
      W 12 - I 12 * -  H 8 -  5  $50D060 DISC
      S" B" W 13 - I 12 * - H 11 - $0A200A COLOR! TEXT
   LOOP
   S" PW" W 2/ 26 - H 11 - $90A8C8 STXT
   5 0 DO
      W 2/ 14 - I 9 * +  H 10 -  7 7
      I POWER @ < IF $F05030 ELSE $383848 THEN  BAR-RECT
   LOOP
   BOSS-I @ 0>= IF  BOSS-I @ EAI @ IF
      BOSS-I @ EHP @ 0> IF
         10 14 220 5 $383848 BAR-RECT
         BOSS-I @ EHP @ 218 *  BOSS-MAX @ /  { n }
         11 15 n 3  BOSS-I @ EHP @ 3 * BOSS-MAX @ > IF $F05030 ELSE $FF2020 THEN  BAR-RECT
      THEN
   THEN THEN ;

VARIABLE T-TICK  VARIABLE T-DRAW  VARIABLE FPS  VARIABLE FPS-N  VARIABLE FPS-AT
: DRAW-PERF ( -- )
   SHOW-PERF @ 0= IF EXIT THEN
   0 22 W 10 $101028 BAR-RECT
   S" STEP" 2 23 $90F090 STXT   T-TICK @ N>S 24 23 $FFFFFF STXT
   S" DRAW" 60 23 $90F090 STXT  T-DRAW @ N>S 82 23 $FFFFFF STXT
   S" FPS" 122 23 $90F090 STXT  FPS @ N>S 138 23 $FFFFFF STXT
   S" SHOTS" 164 23 $90F090 STXT  BULLET-COUNT N>S 188 23 $FFFFFF STXT ;

: WARNING-BAND ( -- )
   PHASE @ 1 = IF
      CLOCK @ 16 / 1 AND IF
         0 130 W 40 $701010 BAR-RECT
         3 TEXT-SCALE  S" WARNING" 136 $FFD040 CTXT  1 TEXT-SCALE
      THEN
   THEN ;

: DRAW-WORLD ( -- )
   DRAW-LAYER-BG
   TRUE DRAW-ENEMIES
   DRAW-ITEMS
   FALSE DRAW-ENEMIES
   DRAW-LASERS
   DRAW-SHOTS
   DRAW-BLASTS
   DRAW-PARTICLES
   DRAW-SHIP
   DRAW-BOMB-WAVE
   DRAW-BULLETS
   DRAW-FLASH
   RIPPLE
   HUD
   WARNING-BAND ;

: DRAW-TITLE ( -- )
   DRAW-LAYER-BG
   5 TEXT-SCALE
   S" SIGMA" 70 $183A90 CTXT
   S" SIGMA" 66 $70D0FF CTXT
   S" STORM" 122 $6A1838 CTXT
   S" STORM" 118 $FFB040 CTXT
   1 TEXT-SCALE
   CLOCK @ 32 / 1 AND IF  S" PRESS SPACE TO START" 210 $FFFFFF CTXT  THEN
   S" ARROWS/WASD MOVE   Z FIRE   C SLOW   X BOMB" 244 $90A8C8 CTXT
   S" P PAUSE   F AUTO FIRE   F1 FRAME TIMES   Q QUIT" 256 $90A8C8 CTXT
   S" HIGH SCORE" 280 $90A8C8 CTXT
   HI-SCORE @ 8 N>S0 292 $FFE050 CTXT ;

: BIG-MSG ( a u y c -- )   2 TEXT-SCALE CTXT 1 TEXT-SCALE ;

: DRAW-INTRO ( -- )
   DRAW-LAYER-BG
   S" STAGE " 2 TEXT-SCALE  2DUP TEXT-WIDTH  W 40 - SWAP - 2/ { x }
   x 110 $FFFFFF STXT
   STG @ 1+ N>S x 72 + 110 $FFE050 STXT
   STAGE-NAME 140 $70D0FF CTXT
   1 TEXT-SCALE
   HUD ;

: DRAW-CLEAR ( -- )
   DRAW-WORLD
   S" STAGE CLEAR" 100 $FFE050 BIG-MSG
   S" BONUS" 140 $FFFFFF CTXT
   LIVES @ 10000 * BOMBS @ 3000 * +  N>S 154 $FFE050 CTXT
   S" GRAZE" 178 $FFFFFF CTXT
   GRAZE @ N>S 192 $FFE050 CTXT ;

: DRAW-OVER ( -- )
   DRAW-WORLD
   S" GAME OVER" 120 $F05030 BIG-MSG
   S" FINAL SCORE" 160 $FFFFFF CTXT
   SCORE @ 8 N>S0 174 $FFE050 CTXT
   MODE-T @ 40 > IF  S" PRESS FIRE" 210 $90A8C8 CTXT  THEN ;

: DRAW-END ( -- )
   DRAW-LAYER-BG
   S" ALL CLEAR" 100 $FFE050 BIG-MSG
   S" THE STORM IS OVER" 140 $FFFFFF CTXT
   S" FINAL SCORE" 170 $FFFFFF CTXT
   SCORE @ 8 N>S0 184 $FFE050 CTXT
   MODE-T @ 60 > IF  S" PRESS FIRE" 220 $90A8C8 CTXT  THEN ;

CREATE DRAWERS  ' DRAW-TITLE , ' DRAW-INTRO , ' DRAW-WORLD , ' DRAW-CLEAR , ' DRAW-OVER , ' DRAW-END ,

: DRAW-PAUSE ( -- )
   PAUSED @ 0= IF EXIT THEN
   60 150 120 32 $101028 BAR-RECT
   S" PAUSED" 158 $FFFFFF BIG-MSG ;

: DRAW ( -- )
   MODE @ CELLS DRAWERS + @ EXECUTE
   DRAW-PAUSE DRAW-PERF ;

\ ---- Input --------------------------------------------------------------------------

VARIABLE PAD-OK  VARIABLE START-WAS  VARIABLE FIRE-WAS  VARIABLE BOMB-WAS

: HELD2 ( c1 c2 -- flag )   KEY-HELD? SWAP KEY-HELD? OR ;
: KEYBOARD ( -- )
   K-LEFT KEY-HELD?   [CHAR] a [CHAR] A HELD2 OR  IN-L !
   K-RIGHT KEY-HELD?  [CHAR] d [CHAR] D HELD2 OR  IN-R !
   K-UP KEY-HELD?     [CHAR] w [CHAR] W HELD2 OR  IN-U !
   K-DOWN KEY-HELD?   [CHAR] s [CHAR] S HELD2 OR  IN-D !
   [CHAR] z [CHAR] Z HELD2  BL KEY-HELD? OR  [CHAR] j [CHAR] J HELD2 OR  IN-FIRE !
   [CHAR] c [CHAR] C HELD2  [CHAR] l [CHAR] L HELD2 OR  IN-SLOW ! ;

: OR! ( flag addr -- )   TUCK @ OR SWAP ! ;
: PAD-BUTTON ( n -- flag )   0 GAMEPAD-BUTTON? ;
VARIABLE PAD-BOMB
: GAMEPAD-INPUT ( -- )
   FALSE PAD-BOMB !
   PAD-OK @ 0= IF EXIT THEN
   GAMEPAD-POLL DUP 0< IF  DROP FALSE PAD-OK !  EXIT  THEN
   0= IF EXIT THEN
   0 GAMEPAD-MAPPED? 0= IF EXIT THEN
   13 PAD-BUTTON  0 0 GAMEPAD-AXIS -16000 < OR  IN-L OR!
   14 PAD-BUTTON  0 0 GAMEPAD-AXIS 16000 > OR   IN-R OR!
   11 PAD-BUTTON  1 0 GAMEPAD-AXIS -16000 < OR  IN-U OR!
   12 PAD-BUTTON  1 0 GAMEPAD-AXIS 16000 > OR   IN-D OR!
   0 PAD-BUTTON  IN-FIRE OR!
   2 PAD-BUTTON  9 PAD-BUTTON OR  10 PAD-BUTTON OR  IN-SLOW OR!
   1 PAD-BUTTON  PAD-BOMB !
   6 PAD-BUTTON  DUP START-WAS @ 0= AND IF
      MODE @ M-TITLE = IF  TRUE PRESS-START !  ELSE PAUSED @ 0= PAUSED !  THEN
   THEN  START-WAS ! ;

: QUIT-OR-TITLE ( -- )
   MODE @ M-TITLE = IF  TRUE DONE !  ELSE  FALSE PAUSED !  TITLE!  THEN ;

: KEY! ( key -- )
   CASE
      [CHAR] p OF PAUSED @ 0= PAUSED ! ENDOF   [CHAR] P OF PAUSED @ 0= PAUSED ! ENDOF
      [CHAR] f OF AUTO-FIRE @ 0= AUTO-FIRE ! ENDOF   [CHAR] F OF AUTO-FIRE @ 0= AUTO-FIRE ! ENDOF
      K-F1 OF SHOW-PERF @ 0= SHOW-PERF ! ENDOF
      [CHAR] q OF QUIT-OR-TITLE ENDOF   [CHAR] Q OF QUIT-OR-TITLE ENDOF
      27 OF QUIT-OR-TITLE ENDOF
      13 OF TRUE PRESS-START ! ENDOF
   ENDCASE ;
: KEYS ( -- )   BEGIN INKEY DUP -1 <> WHILE KEY! REPEAT DROP ;

: LIVE-INPUT ( -- )   KEYBOARD GAMEPAD-INPUT ;
DEFER READ-INPUT  ' LIVE-INPUT IS READ-INPUT

: EDGES ( -- )
   IN-FIRE @ DUP FIRE-WAS @ 0= AND PRESS-FIRE OR!  FIRE-WAS !
   [CHAR] x [CHAR] X HELD2 [CHAR] k [CHAR] K HELD2 OR  PAD-BOMB @ OR
   DUP BOMB-WAS @ 0= AND PRESS-BOMB OR!  BOMB-WAS ! ;

\ ---- The main loop ------------------------------------------------------------------------

VARIABLE LAST-US  VARIABLE ACC

\ Whole steps of 16 ms due since the last frame, at least one, and at most MAX-STEPS.
: STEPS-DUE ( -- n )
   NOW DUP LAST-US @ - SWAP LAST-US !  ACC +!
   ACC @ STEP-US 2/ + STEP-US /   1 MAX MAX-STEPS MIN
   DUP STEP-US * NEGATE ACC +!
   ACC @ STEP-US NEGATE STEP-US CLAMP ACC ! ;

: FRAME-STATS ( -- )
   1 FPS-N +!
   NOW FPS-AT @ - 1000000 >= IF  FPS-N @ FPS !  0 FPS-N !  NOW FPS-AT !  THEN ;

: ONE-FRAME ( -- )
   KEYS READ-INPUT EDGES
   PAUSED @ 0= IF
      NOW
      STEPS-DUE 0 ?DO TICK LOOP
      NOW SWAP - T-TICK !
   ELSE  STEPS-DUE DROP  THEN
   MUSIC-TICK
   NOW  DRAW  NOW SWAP - T-DRAW !
   FRAME-STATS
   FRAME-MS FRAME ;

: SIGMA-STORM ( -- )
   W 3 * H 3 * WINDOW-SIZE
   MAKE-SOUNDS SET-INSTRUMENTS
   TRUE PAD-OK !  FALSE DONE !  FALSE PAUSED !  FALSE SHOW-PERF !  FALSE AUTO-FIRE !
   CANVAS  0 GFX-CLS
   12345 SEED !
   NOW LAST-US !  NOW FPS-AT !
   TITLE!
   BEGIN ONE-FRAME DONE @ UNTIL
   STOP-MUSIC ;

[UNDEFINED] NO-AUTORUN [IF] SIGMA-STORM BYE [THEN]
