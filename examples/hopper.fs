\ Sky Hopper: a side-scrolling platform game for FORTH/Sigma. The courses, the
\ pictures, and the rules are this file's own.
\
\   sigma.exe examples/hopper.fs     (in a window; Tk on Linux/macOS)
\
\ Run to the right to the balloon at the end of each course before the time runs out.
\ Stamp on the mosslings; a snail stamped on leaves its shell, which a touch kicks
\ away. Star blocks hold coins or a berry, which makes the hopper big: a big hopper
\ breaks bricks from below and takes one hit before it is small again. 100 coins give
\ a life.
\ Keys: the arrows move, Z, Space, or Up jumps (higher while held), X held runs,
\ P pauses, R gives up the try (a life), Q or Esc ends. A mapped gamepad works too:
\ the d-pad or the left stick moves, south jumps, west or east runs, start pauses.
\ On Windows the keys go to the console Sigma runs in and to the window.
\ With the audio words, jumps, coins, stamps, kicks, blocks, and hits make sounds, a
\ tune of its own plays in each course (one for the day, one for the cave), and short
\ tunes mark the berry, a new life, a miss, and the balloon.

REQUIRE-GRAPHICS  ALSO GRAPHICS

\ ---- Sound effects ----------------------------------------------------------------
\ Made with SAMPLE and played with SFX when the build has the audio words; a build
\ without them (-Daudio=false) plays the game silently.

: AUDIO-LOADED? ( -- flag )   S" REQUIRE-AUDIO" ['] EVALUATE CATCH  DUP IF NIP NIP THEN  0= ;
AUDIO-LOADED? CONSTANT HAS-SOUND

HAS-SOUND [IF]
ALSO AUDIO
8000 CONSTANT WAVE-RATE
CREATE WAVE WAVE-RATE ALLOT             \ room for a second of sound
VARIABLE WAVE-COUNT  VARIABLE WAVE-SIGN  VARIABLE WAVE-SEED
\ A square wave of n samples whose half period starts at p samples and changes by dp
\ every 64 samples (below 0: the pitch rises), fading out.
: SQUARE-SWEEP { n p dp -- }
   0 WAVE-COUNT !  1 WAVE-SIGN !
   n 0 DO
      1 WAVE-COUNT +!
      WAVE-COUNT @  p I 64 / dp * +  2 MAX  >= IF  0 WAVE-COUNT !  WAVE-SIGN @ NEGATE WAVE-SIGN !  THEN
      WAVE-SIGN @ 100 *  n I - *  n /  WAVE I + C!
   LOOP ;
\ Noise of n samples, fading out.
: NOISE-BURST { n -- }
   n 0 DO
      WAVE-SEED @ 1103515245 * 12345 + DUP WAVE-SEED !  16 RSHIFT 200 MOD 100 -
      n I - *  n /  WAVE I + C!
   LOOP ;
\ The first n samples of the wave as sample k.
: KEEP ( n k -- )   >R WAVE SWAP WAVE-RATE R> SAMPLE ;
: EFFECT ( k -- )   SFX ;
: JINGLE ( c-addr u -- )   PLAY ;
PREVIOUS
[ELSE]
: EFFECT ( k -- )   DROP ;
: JINGLE ( c-addr u -- )   2DROP ;
[THEN]

0 CONSTANT S-JUMP  1 CONSTANT S-COIN  2 CONSTANT S-STOMP  3 CONSTANT S-KICK
4 CONSTANT S-BUMP  5 CONSTANT S-BREAK  6 CONSTANT S-SHRINK
HAS-SOUND [IF]
: MAKE-SOUNDS ( -- )
   1200 16 -1 SQUARE-SWEEP  1200 S-JUMP KEEP       \ rising
   1200 4 0 SQUARE-SWEEP  1200 S-COIN KEEP         \ a high ring
   600 16 2 SQUARE-SWEEP  600 S-STOMP KEEP         \ a falling thump
   400 10 0 SQUARE-SWEEP  400 S-KICK KEEP          \ a click
   500 24 0 SQUARE-SWEEP  500 S-BUMP KEEP          \ a low knock
   2400 NOISE-BURST  2400 S-BREAK KEEP             \ pieces flying
   3000 6 1 SQUARE-SWEEP  3000 S-SHRINK KEEP ;     \ falling
[ELSE]
: MAKE-SOUNDS ( -- ) ;
[THEN]

\ ---- Music ------------------------------------------------------------------------
\ Two tunes of this file's own, on the NES's chip: a melody and a harmony on the two
\ pulses, a bass on the triangle, and drums on the noise. A tune is played a bar at a
\ time (a phrase: 80 fiftieths of a second, at T150 an eighth note is 10), so that
\ PLAY never waits: one or two bars are always in the queues, and a new one is put
\ when less than one is left. The drums: O3 C a kick, O3 G a snare, O4 D# a hat.

HAS-SOUND [IF]
ALSO AUDIO
: MUSIC-CHIP ( -- )   NES-SOUND ;      \ choosing the chip again also stops the music
: SET-INSTRUMENTS ( -- )
   1 INSTRUMENT PULSE 25 DUTY 0 3 11 3 ADSR    \ the melody
   2 INSTRUMENT PULSE 12 DUTY 0 4 9 4 ADSR     \ the harmony
   3 INSTRUMENT 0 2 0 1 ADSR ;                  \ the drums, short
: PHRASE ( melody harmony bass drums -- )   4 PLAYS ;
\ Short tunes of samples, which do not stop the music: four rising notes, each n
\ samples, of half periods p1 to p4.
: TONE-AT { at n p -- }   n 0 DO  I p / 1 AND IF -80 ELSE 80 THEN  WAVE at + I + C!  LOOP ;
: FOUR-NOTES { n p1 p2 p3 p4 -- }
   0 n p1 TONE-AT  n n p2 TONE-AT  n 2* n p3 TONE-AT  n 3 * n p4 TONE-AT ;
PREVIOUS
[ELSE]
: MUSIC-CHIP ( -- ) ;
: SET-INSTRUMENTS ( -- ) ;
: PHRASE ( melody harmony bass drums -- )   2DROP 2DROP 2DROP 2DROP ;
[THEN]

7 CONSTANT S-GROW  8 CONSTANT S-LIFE
HAS-SOUND [IF]
: MAKE-MUSIC-SOUNDS ( -- )
   SET-INSTRUMENTS
   600 8 6 5 4 FOUR-NOTES  2400 S-GROW KEEP      \ up, as the hopper grows
   500 4 5 4 3 FOUR-NOTES  2000 S-LIFE KEEP ;    \ a new life
[ELSE]
: MAKE-MUSIC-SOUNDS ( -- ) ;
[THEN]

\ Out in the day: C, Am, F, G, C, Am, F to G, C.
: DAY-1   S" T150 L8 O5 @1 V10 EGGECDER"     S" T150 L2 O4 @2 V7 EG"   S" T150 L4 O3 CGCG"       S" T150 L8 O3 @3 V12 CO4D#O3GO4D#O3CCGO4D#" PHRASE ;
: DAY-2   S" T150 L8 O5 @1 V10 CEEC<A>CE4"   S" T150 L2 O4 @2 V7 EC"   S" T150 L4 O3 <A>E<A>E"   S" T150 L8 O3 @3 V12 CO4D#O3GO4D#O3CCGO4D#" PHRASE ;
: DAY-3   S" T150 L8 O5 @1 V10 FAAFDFAG"     S" T150 L2 O4 @2 V7 FA"   S" T150 L4 O3 <F>C<F>C"   S" T150 L8 O3 @3 V12 CO4D#O3GO4D#O3CCGO4D#" PHRASE ;
: DAY-4   S" T150 L8 O5 @1 V10 G4BGD4R4"     S" T150 L2 O4 @2 V7 DG"   S" T150 L4 O3 <G>D<G>D"   S" T150 L8 O3 @3 V12 CO4D#O3GO4D#O3CCGO4D#" PHRASE ;
: DAY-5   S" T150 L8 O5 @1 V10 EG>C<GEG>C4"  S" T150 L2 O4 @2 V7 EG"   S" T150 L4 O3 CGCG"       S" T150 L8 O3 @3 V12 CO4D#O3GO4D#O3CCGO4D#" PHRASE ;
: DAY-6   S" T150 L8 O5 @1 V10 AGECE4D4"     S" T150 L2 O4 @2 V7 CE"   S" T150 L4 O3 <A>E<A>E"   S" T150 L8 O3 @3 V12 CO4D#O3GO4D#O3CCGO4D#" PHRASE ;
: DAY-7   S" T150 L8 O5 @1 V10 FAGB>D4<B4"   S" T150 L2 O4 @2 V7 FD"   S" T150 L4 O3 <F>C<G>D"   S" T150 L8 O3 @3 V12 CO4D#O3GO4D#O3CCGO4D#" PHRASE ;
: DAY-8   S" T150 L8 O5 @1 V10 C2.R4"        S" T150 L1 O4 @2 V7 E"    S" T150 L4 O3 CGC2"       S" T150 L8 O3 @3 V12 CO4D#O3GO4D#O3GGGG" PHRASE ;
CREATE DAY-TUNE  ' DAY-1 , ' DAY-2 , ' DAY-3 , ' DAY-4 , ' DAY-5 , ' DAY-6 , ' DAY-7 , ' DAY-8 ,

\ In a cave: Am, F, G, Am, Dm, Am, E, Am, lower and slower to the ear.
: CAVE-1  S" T150 L8 O4 @1 V9 A4REA>C4<B"    S" T150 L1 O4 @2 V6 E"    S" T150 L4 O3 <A>E<A>E"   S" T150 L4 O3 @3 V10 CO4D#O3CO4D#" PHRASE ;
: CAVE-2  S" T150 L8 O4 @1 V9 A4F4C4R4"      S" T150 L1 O4 @2 V6 C"    S" T150 L4 O3 <F>C<F>C"   S" T150 L4 O3 @3 V10 CO4D#O3CO4D#" PHRASE ;
: CAVE-3  S" T150 L8 O4 @1 V9 B4GDGB4R"      S" T150 L1 O4 @2 V6 D"    S" T150 L4 O3 <G>D<G>D"   S" T150 L4 O3 @3 V10 CO4D#O3CO4D#" PHRASE ;
: CAVE-4  S" T150 L8 O4 @1 V9 A2R2"          S" T150 L1 O4 @2 V6 E"    S" T150 L4 O3 <A>E<A>E"   S" T150 L4 O3 @3 V10 CO4D#O3CO4D#" PHRASE ;
: CAVE-5  S" T150 L8 O4 @1 V9 D4FA>D4<CR"    S" T150 L1 O4 @2 V6 F"    S" T150 L4 O3 DADA"       S" T150 L4 O3 @3 V10 CO4D#O3CO4D#" PHRASE ;
: CAVE-6  S" T150 L8 O4 @1 V9 C4<A4>E4R4"    S" T150 L1 O4 @2 V6 E"    S" T150 L4 O3 <A>E<A>E"   S" T150 L4 O3 @3 V10 CO4D#O3CO4D#" PHRASE ;
: CAVE-7  S" T150 L8 O4 @1 V9 G#BG#E4D#ER"   S" T150 L1 O3 @2 V6 B"    S" T150 L4 O3 EBEB"       S" T150 L4 O3 @3 V10 CO4D#O3CO4D#" PHRASE ;
: CAVE-8  S" T150 L8 O4 @1 V9 A2.R4"         S" T150 L1 O4 @2 V6 E"    S" T150 L4 O3 <A>E<A2>"   S" T150 L4 O3 @3 V10 CCL8GGGG" PHRASE ;
CREATE CAVE-TUNE  ' CAVE-1 , ' CAVE-2 , ' CAVE-3 , ' CAVE-4 , ' CAVE-5 , ' CAVE-6 , ' CAVE-7 , ' CAVE-8 ,

8 CONSTANT TUNE-BARS
1600000 CONSTANT BAR-US                 \ a bar: 80 fiftieths of a second
VARIABLE TUNE                           \ the tune playing, 0 for none
VARIABLE TUNE-BAR  VARIABLE QUEUED-UNTIL
: MUSIC-NOW ( -- us )   UTIME DROP ;
: NEXT-BAR ( -- )
   QUEUED-UNTIL @ MUSIC-NOW MAX QUEUED-UNTIL !     \ after a gap, from now
   TUNE @ TUNE-BAR @ CELLS + @ EXECUTE
   TUNE-BAR @ 1+ TUNE-BARS MOD TUNE-BAR !  BAR-US QUEUED-UNTIL +! ;
: STOP-MUSIC ( -- )   0 TUNE !  MUSIC-CHIP ;
: START-MUSIC ( tune -- )   STOP-MUSIC  TUNE !  0 TUNE-BAR !  0 QUEUED-UNTIL !  NEXT-BAR NEXT-BAR ;
\ Each frame: a new bar when less than one is left in the queues.
: MUSIC-TICK ( -- )
   TUNE @ 0= IF EXIT THEN
   QUEUED-UNTIL @ MUSIC-NOW - BAR-US < IF NEXT-BAR THEN ;

8 CONSTANT TS                       \ a tile is TS by TS pixels
32 CONSTANT VIEW-COLS               \ the columns the screen shows
22 CONSTANT ROWS
VIEW-COLS TS * CONSTANT W
ROWS TS * CONSTANT H
240 CONSTANT MAX-COLS               \ the longest course
50 CONSTANT FPS
1000 FPS / CONSTANT FRAME-MS
16 CONSTANT SUB                     \ positions and speeds are kept in 1/16 pixels

: >PX ( sub -- px )   2/ 2/ 2/ 2/ ;  \ 2/ rounds down, also below 0
: >TILE ( px -- t )   2/ 2/ 2/ ;

0 CONSTANT EMPTY    1 CONSTANT GROUND   2 CONSTANT BRICK    3 CONSTANT QCOIN
4 CONSTANT QBERRY   5 CONSTANT USED     6 CONSTANT HARD     7 CONSTANT TUBE-TL
8 CONSTANT TUBE-TR  9 CONSTANT TUBE-L   10 CONSTANT TUBE-R  11 CONSTANT COIN

: SOLID? ( t -- flag )   1 11 WITHIN ;

\ ---- The map -----------------------------------------------------------------------

CREATE MAP  MAX-COLS ROWS * ALLOT
VARIABLE LEN                        \ the columns of this course
VARIABLE THEME                      \ 0 out in the day, 1 in a cave

\ Above and below the map is open (a fall below it is a miss); beside it is solid.
: TILE@ ( tx ty -- t )
   DUP 0 ROWS WITHIN 0= IF 2DROP EMPTY EXIT THEN
   OVER 0 LEN @ WITHIN 0= IF 2DROP HARD EXIT THEN
   MAX-COLS * + MAP + C@ ;
: TILE! ( t tx ty -- )
   2DUP 0 ROWS WITHIN SWAP 0 MAX-COLS WITHIN AND
   IF  MAX-COLS * + MAP + C!  ELSE  2DROP DROP  THEN ;

\ Whether the box (in pixels) covers a solid tile.
: BOX-SOLID? { x y w h -- flag }
   y h + 1- >TILE 1+  y >TILE DO
      x w + 1- >TILE 1+  x >TILE DO
         I J TILE@ SOLID? IF  UNLOOP UNLOOP TRUE EXIT  THEN
      LOOP
   LOOP FALSE ;

: OVERLAP? { ax ay aw ah bx by bw bh -- flag }
   ax bx bw + <  bx ax aw + < AND  ay by bh + < AND  by ay ah + < AND ;

\ ---- The game's state --------------------------------------------------------------

VARIABLE COURSE  VARIABLE LIVES  VARIABLE SCORE  VARIABLE COINS  VARIABLE TIME-LEFT
VARIABLE TICKS   VARIABLE CAM    VARIABLE PAUSED VARIABLE DONE
VARIABLE BUMP-X  VARIABLE BUMP-Y VARIABLE BUMP-T  \ the block bumped from below
VARIABLE BALLOON-X                  \ the column of the balloon's basket
VARIABLE GOAL                       \ 0 playing, 1 rising in the balloon, 2 time bonus
VARIABLE LIFT                       \ how high the balloon has risen

: ADD-COIN ( -- )
   200 SCORE +!  1 COINS +!  S-COIN EFFECT
   COINS @ 100 = IF  0 COINS !  1 LIVES +!  S-LIFE EFFECT  THEN ;

\ ---- The things: enemies, the berry, coins and pieces of brick ---------------------

48 CONSTANT MAX-E
: ENTITY-FIELD ( "name" -- )   CREATE MAX-E CELLS ALLOT  DOES> ( i -- addr ) SWAP CELLS + ;
ENTITY-FIELD ETYPE  ENTITY-FIELD EX  ENTITY-FIELD EY  ENTITY-FIELD EVX  ENTITY-FIELD EVY
ENTITY-FIELD ESTATE  ENTITY-FIELD ETIME

0 CONSTANT E-NONE    1 CONSTANT E-MOSS    2 CONSTANT E-SNAIL   3 CONSTANT E-SHELL
4 CONSTANT E-BERRY   5 CONSTANT E-COIN    6 CONSTANT E-CHIP    7 CONSTANT E-FLAT
8 CONSTANT E-KNOCKED

: CLEAR-ENTITIES ( -- )   MAX-E 0 DO  E-NONE I ETYPE !  LOOP ;

\ A new thing at x y (pixels); -1 when there is no room.
: NEW-E ( x y type -- i )
   MAX-E 0 DO
      I ETYPE @ E-NONE = IF
         I ETYPE !  SUB * I EY !  SUB * I EX !
         0 I EVX !  0 I EVY !  0 I ESTATE !  0 I ETIME !  I UNLOOP EXIT
      THEN
   LOOP DROP 2DROP -1 ;

: EBOX ( i -- x y w h )   DUP EX @ >PX  SWAP EY @ >PX  8 8 ;
: ENEMY? ( i -- flag )   ETYPE @ DUP E-MOSS = OVER E-SNAIL = OR SWAP E-SHELL = OR ;
: COUNT-DOWN ( i -- flag )   -1 OVER ETIME +!  ETIME @ 0 <= ;

\ Walks, falls, and turns back at walls.
: E-MOVE ( i -- )
   >R
   R@ EVX @ R@ EX +!
   R@ EBOX BOX-SOLID? IF
      R@ EX @ >PX  R@ EVX @ 0> IF 7 + >TILE TS * 8 - ELSE >TILE 1+ TS * THEN  SUB * R@ EX !
      R@ EVX @ NEGATE R@ EVX !
   THEN
   R@ EVY @ 4 + 64 MIN R@ EVY !
   R@ EVY @ R@ EY +!
   R@ EBOX BOX-SOLID? IF
      R@ EY @ >PX  R@ EVY @ 0> IF 7 + >TILE TS * 8 - ELSE >TILE 1+ TS * THEN  SUB * R@ EY !
      0 R@ EVY !
   THEN
   R@ EY @ >PX H > IF  E-NONE R@ ETYPE !  THEN
   R> DROP ;

\ Flies without touching the map, and is gone below it.
: FLY ( i -- )
   >R  R@ EVX @ R@ EX +!
   R@ EVY @ 4 + 64 MIN R@ EVY !  R@ EVY @ R@ EY +!
   R@ EY @ >PX H 8 + > IF  E-NONE R@ ETYPE !  THEN
   R> DROP ;

\ Knocked out: up, and down off the screen.
: KNOCK ( i -- )
   DUP ETYPE @ OVER ESTATE !  E-KNOCKED OVER ETYPE !
   -40 OVER EVY !  DUP EVX @ 0< IF -8 ELSE 8 THEN SWAP EVX !  200 SCORE +! ;

: SPAWN ( tx ty type -- i )   >R TS * SWAP TS * SWAP R> NEW-E ;
: MOSS ( tx ty -- )    E-MOSS SPAWN  DUP 0< IF DROP EXIT THEN  -8 SWAP EVX ! ;
: SNAIL ( tx ty -- )   E-SNAIL SPAWN  DUP 0< IF DROP EXIT THEN  -8 SWAP EVX ! ;

: POP-COIN ( tx ty -- )   \ a coin jumps out of the block
   1- E-COIN SPAWN  DUP 0< IF DROP EXIT THEN
   -56 OVER EVY !  20 SWAP ETIME !  ADD-COIN ;
: SPAWN-BERRY ( tx ty -- )   \ it comes up out of the block
   E-BERRY SPAWN  DUP 0< IF DROP EXIT THEN
   1 OVER ESTATE !  16 SWAP ETIME ! ;
: CHIP ( x y vx vy -- )
   2SWAP E-CHIP NEW-E  DUP 0< IF DROP 2DROP EXIT THEN
   TUCK EVY !  EVX ! ;
: BREAK-BRICK ( tx ty -- )
   TS * SWAP TS * SWAP { x y }
   x y -12 -56 CHIP  x 4 + y 12 -56 CHIP  x y 4 + -12 -32 CHIP  x 4 + y 4 + 12 -32 CHIP ;

\ Enemies standing on a block bumped from below are knocked out.
: KNOCK-ABOVE ( tx ty -- )
   TS * SWAP TS * SWAP  { x y }
   MAX-E 0 DO
      I ENEMY? IF  I EBOX  x y 8 - 8 8 OVERLAP? IF I KNOCK THEN  THEN
   LOOP ;

\ A moving shell knocks out the enemies it meets; a shell left alone a while comes out.
: SHELL-TICK { s -- }
   s EVX @ 0= IF
      1 s ETIME +!
      s ETIME @ 400 > IF  E-SNAIL s ETYPE !  -8 s EVX !  THEN
   ELSE
      s ESTATE @ IF  -1 s ESTATE +!  THEN
      MAX-E 0 DO
         I s <>  I ENEMY? AND IF
            I EBOX s EBOX OVERLAP? IF I KNOCK THEN
         THEN
      LOOP
   THEN ;

: BERRY-TICK ( i -- )
   DUP ESTATE @ IF
      -8 OVER EY +!
      DUP COUNT-DOWN IF  0 OVER ESTATE !  16 OVER EVX !  THEN  DROP
   ELSE E-MOVE THEN ;

: UPDATE-E ( i -- )
   DUP ETYPE @ CASE
      E-MOSS OF  DUP E-MOVE  ENDOF
      E-SNAIL OF  DUP E-MOVE  ENDOF
      E-SHELL OF  DUP E-MOVE  DUP SHELL-TICK  ENDOF
      E-BERRY OF  DUP BERRY-TICK  ENDOF
      E-COIN OF  DUP FLY  DUP COUNT-DOWN IF  E-NONE OVER ETYPE !  THEN  ENDOF
      E-CHIP OF  DUP FLY  ENDOF
      E-FLAT OF  DUP COUNT-DOWN IF  E-NONE OVER ETYPE !  THEN  ENDOF
      E-KNOCKED OF  DUP FLY  ENDOF
   ENDCASE DROP ;

\ ---- The hopper --------------------------------------------------------------------

VARIABLE PX  VARIABLE PY  VARIABLE PVX  VARIABLE PVY   \ the top left of its box
VARIABLE BIG  VARIABLE ONGROUND  VARIABLE FACING
VARIABLE JUMP-T  VARIABLE JUMP-V  VARIABLE JUMP-WAS
VARIABLE INVULN  VARIABLE GROW-T  VARIABLE WALK-T
VARIABLE DYING  VARIABLE DIE-T

6 CONSTANT PW
: PH ( -- h )   BIG @ IF 16 ELSE 8 THEN ;
: PBOX ( -- x y w h )   PX @ >PX  PY @ >PX  PW PH ;

VARIABLE IN-LEFT  VARIABLE IN-RIGHT  VARIABLE IN-JUMP  VARIABLE IN-RUN

: START-DYING ( -- )
   DYING @ IF EXIT THEN
   STOP-MUSIC  S" T150 L16 O5 C<GEC<G4" JINGLE
   BIG @ IF  0 BIG !  8 SUB * PY +!  THEN
   TRUE DYING !  30 DIE-T !  0 PVX !  0 PVY ! ;

: HURT ( -- )
   INVULN @ DYING @ OR IF EXIT THEN
   BIG @ IF  0 BIG !  8 SUB * PY +!  100 INVULN !  S-SHRINK EFFECT  ELSE  START-DYING  THEN ;

: GROW ( -- )
   1000 SCORE +!  BIG @ IF EXIT THEN
   S-GROW EFFECT
   TRUE BIG !  -8 SUB * PY +!  30 GROW-T ! ;

: BOUNCE ( -- )   40 JUMP-V !  -40 PVY !  IN-JUMP @ IF 6 ELSE 0 THEN JUMP-T !  S-STOMP EFFECT ;

: START-BUMP ( tx ty -- )   BUMP-Y !  BUMP-X !  8 BUMP-T ! ;

: BUMP { tx ty -- }
   tx ty TILE@ CASE
      QCOIN OF  USED tx ty TILE!  tx ty POP-COIN  tx ty START-BUMP  tx ty KNOCK-ABOVE  ENDOF
      QBERRY OF  USED tx ty TILE!  tx ty SPAWN-BERRY  tx ty START-BUMP  tx ty KNOCK-ABOVE  S-BUMP EFFECT  ENDOF
      BRICK OF
         BIG @ IF  EMPTY tx ty TILE!  tx ty BREAK-BRICK  50 SCORE +!  S-BREAK EFFECT
         ELSE  tx ty START-BUMP  S-BUMP EFFECT  THEN
         tx ty KNOCK-ABOVE
      ENDOF
   ENDCASE ;

\ The block the head hit: the one over the middle of the head, or the other one.
: HEAD-BUMP ( -- )
   PY @ >PX >TILE  PX @ >PX 3 + >TILE  { ty cx }
   cx ty TILE@ SOLID? 0= IF
      PX @ >PX >TILE  DUP cx = IF DROP PX @ >PX PW + 1- >TILE THEN  TO cx
   THEN
   cx ty BUMP ;

: MOVE-PX ( -- )
   PVX @ PX +!
   PVX @ 0= IF EXIT THEN
   PBOX BOX-SOLID? IF
      PX @ >PX  PVX @ 0> IF  PW + 1- >TILE TS * PW -  ELSE  >TILE 1+ TS *  THEN
      SUB * PX !  0 PVX !
   THEN ;

: ON-SOLID? ( -- flag )   PX @ >PX  PY @ >PX 1+  PW PH BOX-SOLID? ;

: MOVE-PY ( -- )
   PVY @ PY +!
   PBOX BOX-SOLID? IF
      PVY @ 0< IF
         HEAD-BUMP  PY @ >PX >TILE 1+ TS * SUB * PY !  0 JUMP-T !
      ELSE
         PY @ >PX PH + 1- >TILE TS * PH - SUB * PY !
      THEN
      0 PVY !
   THEN
   PVY @ 0< 0= ON-SOLID? AND  DUP ONGROUND !
   IF  PY @ >PX SUB * PY !  0 PVY !  THEN ;

: IN-DIR ( -- -1|0|1 )   IN-RIGHT @ 0<> 1 AND  IN-LEFT @ 0<> 1 AND - ;
: APPROACH { v t s -- v' }   v t < IF v s + t MIN ELSE v s - t MAX THEN ;

: RUN-X ( -- )
   IN-DIR  IN-RUN @ IF 32 ELSE 20 THEN  { d top }
   d 0= IF  PVX @ 0  ONGROUND @ IF 2 ELSE 1 THEN  APPROACH PVX !  EXIT  THEN
   d FACING !
   PVX @ d * top > IF  PVX @ d top * 1 APPROACH
   ELSE  PVX @ d top *  PVX @ d * 0< IF 4 ELSE 2 THEN  APPROACH  THEN  PVX ! ;

\ A jump starts when the key is pressed on the ground, and goes higher while it is
\ held, and when running.
: JUMP-Y ( -- )
   IN-JUMP @ 0<>  JUMP-WAS @ 0= AND  ONGROUND @ AND IF
      PVX @ ABS 4 / 48 + JUMP-V !  JUMP-V @ NEGATE PVY !  6 JUMP-T !  FALSE ONGROUND !
      S-JUMP EFFECT
   ELSE
      IN-JUMP @ JUMP-T @ 0> AND IF  -1 JUMP-T +!  JUMP-V @ NEGATE PVY !
      ELSE  0 JUMP-T !  PVY @ 4 + 64 MIN PVY !  THEN
   THEN
   IN-JUMP @ JUMP-WAS ! ;

: COLLECT ( -- )   \ the coins the box covers
   PBOX { x y w h }
   y h + 1- >TILE 1+  y >TILE DO
      x w + 1- >TILE 1+  x >TILE DO
         I J TILE@ COIN = IF  EMPTY I J TILE!  ADD-COIN  THEN
      LOOP
   LOOP ;

: KEEP-IN-VIEW ( -- )   \ the screen does not go back to the left
   PX @ >PX CAM @ < IF  CAM @ SUB * PX !  PVX @ 0 MAX PVX !  THEN ;

: PLAYER-TICK ( -- )
   RUN-X JUMP-Y
   MOVE-PX KEEP-IN-VIEW MOVE-PY
   COLLECT
   INVULN @ IF -1 INVULN +! THEN
   GROW-T @ IF -1 GROW-T +! THEN
   PVX @ ABS WALK-T +!
   PY @ >PX H > IF  START-DYING  0 DIE-T !  THEN ;   \ fell: no pause, it goes on down

: CAMERA ( -- )
   PX @ >PX 120 -  CAM @ MAX  LEN @ TS * W - MIN  0 MAX  CAM ! ;

\ ---- The hopper and the things ----------------------------------------------------

: TOUCHES? ( i -- flag )   >R PBOX R> EBOX OVERLAP? ;
\ Falling, with the feet in the top of the thing.
: STOMP? ( i -- flag )
   PVY @ 0>  SWAP EY @ >PX  PY @ >PX PH + 1-  SWAP - 5 < AND ;

: SHELL-TOUCH ( i -- )
   DUP EVX @ 0= IF                   \ kicked, away from the hopper
      PX @ >PX 3 +  OVER EX @ >PX 4 + < IF 48 ELSE -48 THEN  OVER EVX !
      10 OVER ESTATE !  100 SCORE +!  S-KICK EFFECT
      DUP STOMP? IF BOUNCE THEN
   ELSE
      DUP STOMP? IF  0 OVER EVX !  0 OVER ETIME !  BOUNCE
      ELSE  DUP ESTATE @ 0= IF HURT THEN  THEN
   THEN DROP ;

: INTERACT ( i -- )
   DUP TOUCHES? 0= IF DROP EXIT THEN
   DUP ETYPE @ CASE
      E-MOSS OF
         DUP STOMP? IF  E-FLAT OVER ETYPE !  25 OVER ETIME !  100 SCORE +!  BOUNCE
         ELSE HURT THEN
      ENDOF
      E-SNAIL OF
         DUP STOMP? IF  E-SHELL OVER ETYPE !  0 OVER EVX !  0 OVER ETIME !  0 OVER ESTATE !
            100 SCORE +!  BOUNCE
         ELSE HURT THEN
      ENDOF
      E-SHELL OF  DUP SHELL-TOUCH  ENDOF
      E-BERRY OF  DUP ESTATE @ 0= IF  E-NONE OVER ETYPE !  GROW  THEN  ENDOF
   ENDCASE DROP ;

\ Things are moved only near the screen; those left behind are gone.
: ACTIVE? ( i -- flag )   EX @ >PX  CAM @ 48 -  CAM @ W + 48 +  WITHIN ;

: UPDATE-ENTITIES ( -- )
   MAX-E 0 DO
      I ETYPE @ IF
         I ACTIVE? IF
            I UPDATE-E
            I ETYPE @  GOAL @ 0= AND  DYING @ 0= AND IF I INTERACT THEN
         ELSE
            I EX @ >PX CAM @ 48 - < IF  E-NONE I ETYPE !  THEN
         THEN
      THEN
   LOOP ;

\ ---- Dying and the balloon ---------------------------------------------------------

: UPDATE-DYING ( -- )   \ a pause, then a hop up, and down off the screen
   DIE-T @ IF
      -1 DIE-T +!  DIE-T @ 0= IF -64 PVY ! THEN
   ELSE
      PVY @ 4 + 64 MIN PVY !  PVY @ PY +!
   THEN ;
: FELL? ( -- flag )   DYING @  PY @ >PX H 16 + > AND ;

: BASKET-X ( -- px )   BALLOON-X @ TS * ;
: REACHED-BALLOON? ( -- flag )   PX @ >PX PW + BASKET-X 3 + > ;

: START-GOAL ( -- )
   STOP-MUSIC  S" T180 L16 O5 CEG>CEG>C4" JINGLE
   1 GOAL !  0 LIFT !  0 PVX !  0 PVY !  1 FACING !
   BASKET-X 3 + SUB * PX !
   PY @ >PX  DUP 100 < IF DROP 2000 ELSE 136 < IF 800 ELSE 200 THEN THEN  SCORE +! ;

2VARIABLE MESSAGE  VARIABLE MESSAGE-TICKS  VARIABLE AFTER-MESSAGE
\ Shows the text for a while, the game stopped, then runs xt.
: SAY ( c-addr u ticks xt -- )   AFTER-MESSAGE !  MESSAGE-TICKS !  MESSAGE 2! ;

DEFER NEXT-COURSE
: GOAL-TICK ( -- )
   GOAL @ 1 = IF
      1 LIFT +!
      151 LIFT @ - PH - SUB * PY !   \ standing in the basket as it rises
      LIFT @ 150 > IF 2 GOAL ! THEN  EXIT
   THEN
   GOAL @ 2 = IF
      TIME-LEFT @ IF
         TIME-LEFT @ 2 MIN  DUP NEGATE TIME-LEFT +!  50 * SCORE +!
      ELSE
         3 GOAL !  S" COURSE CLEAR" FPS 2* ['] NEXT-COURSE SAY
      THEN
   THEN ;

\ ---- The courses -------------------------------------------------------------------
\ Rows 20 and 21 are the ground; a hopper on it stands in row 19.

: FILL-ROW { t a b y -- }   b 1+ a ?DO  t I y TILE!  LOOP ;
: GROUND-RUN ( tx1 tx2 -- )   2DUP GROUND -ROT 20 FILL-ROW  GROUND -ROT 21 FILL-ROW ;
: BRICKS ( tx ty n -- )   { x y n }  BRICK x x n + 1- y FILL-ROW ;
: COIN-ROW ( tx ty n -- )   { x y n }  COIN x x n + 1- y FILL-ROW ;
: CEILING ( tx1 tx2 -- )   HARD -ROT 2 FILL-ROW ;
: Q ( tx ty -- )    QCOIN -ROT TILE! ;
: QB ( tx ty -- )   QBERRY -ROT TILE! ;
: TUBE ( tx h -- )   \ two columns wide, h tall, on the ground
   { x h }
   h 0 ?DO  TUBE-L x 19 I - TILE!  TUBE-R x 1+ 19 I - TILE!  LOOP
   TUBE-TL x 20 h - TILE!  TUBE-TR x 1+ 20 h - TILE! ;
: COLUMN ( tx h -- )   { x h }  h 0 ?DO  HARD x 19 I - TILE!  LOOP ;
: STAIR-UP ( tx n -- )     { x n }  n 0 DO  x I +  I 1+  COLUMN  LOOP ;
: STAIR-DOWN ( tx n -- )   { x n }  n 0 DO  x I +  n I -  COLUMN  LOOP ;
: BALLOON ( tx -- )   DUP BALLOON-X !  12 + LEN ! ;

: COURSE-1 ( -- )   \ out in the day
   0 THEME !
   0 68 GROUND-RUN  71 85 GROUND-RUN  89 141 GROUND-RUN  144 209 GROUND-RUN
   12 16 Q
   18 16 1 BRICKS  19 16 QB  20 16 1 BRICKS  21 16 Q  22 16 1 BRICKS  20 12 Q
   27 19 MOSS
   30 2 TUBE  40 3 TUBE  46 19 MOSS  52 4 TUBE  58 19 MOSS  60 19 MOSS
   62 15 4 COIN-ROW
   74 16 3 BRICKS  75 16 Q
   77 12 8 BRICKS  80 11 MOSS  83 11 MOSS  78 9 6 COIN-ROW
   92 16 1 BRICKS  93 16 Q  94 16 1 BRICKS
   98 19 SNAIL
   101 16 Q  104 16 Q  107 16 Q  104 12 QB
   106 19 MOSS  108 19 MOSS
   113 16 2 BRICKS  117 12 3 BRICKS  118 12 Q
   121 19 MOSS  123 19 MOSS
   126 4 STAIR-UP  132 4 STAIR-DOWN
   138 4 STAIR-UP  144 4 STAIR-DOWN
   152 19 MOSS  156 19 SNAIL
   160 2 TUBE  165 16 3 COIN-ROW  171 2 TUBE  175 19 MOSS
   180 6 STAIR-UP  186 6 COLUMN
   196 BALLOON ;

: COURSE-2 ( -- )   \ in a cave, and out of it at the end
   1 THEME !
   0 44 GROUND-RUN  48 95 GROUND-RUN  99 120 GROUND-RUN  140 191 GROUND-RUN
   0 170 CEILING
   10 16 Q  11 16 QB  12 16 Q
   16 19 MOSS  18 19 MOSS
   22 3 TUBE  28 19 SNAIL
   32 13 6 BRICKS  33 10 4 COIN-ROW
   36 19 MOSS  38 19 MOSS
   54 4 TUBE
   60 15 16 BRICKS  60 18 16 COIN-ROW  66 19 MOSS  72 19 SNAIL
   80 2 TUBE  86 4 TUBE
   100 16 Q  102 16 QB  104 16 Q  106 16 Q
   110 19 SNAIL  114 19 MOSS  116 19 MOSS
   123 17 3 BRICKS  128 15 3 BRICKS  133 17 3 BRICKS  128 12 3 COIN-ROW  129 14 MOSS
   145 4 STAIR-UP  149 4 COLUMN  150 4 STAIR-DOWN
   158 19 SNAIL  160 19 MOSS  163 19 MOSS
   180 BALLOON ;

CREATE COURSES  ' COURSE-1 ,  ' COURSE-2 ,
2 CONSTANT #COURSES

CREATE MSG-BUF 32 ALLOT
: COURSE$ ( -- c-addr u )
   S" COURSE " MSG-BUF SWAP MOVE
   COURSE @ 1+ S>D <# #S #>  TUCK MSG-BUF 7 + SWAP MOVE  7 + MSG-BUF SWAP ;

: NOTHING ( -- ) ;
: START-LEVEL ( -- )
   MAP MAX-COLS ROWS * ERASE  CLEAR-ENTITIES
   COURSE @ #COURSES MOD CELLS COURSES + @ EXECUTE
   2 TS * SUB * PX !  20 TS * PH - SUB * PY !  0 PVX !  0 PVY !
   1 FACING !  0 JUMP-T !  TRUE JUMP-WAS !  0 INVULN !  0 GROW-T !  0 WALK-T !
   FALSE DYING !  0 DIE-T !  FALSE ONGROUND !
   0 CAM !  0 BUMP-T !  0 GOAL !  0 LIFT !  300 TIME-LEFT !  0 TICKS !
   COURSE$ FPS ['] NOTHING SAY
   THEME @ IF CAVE-TUNE ELSE DAY-TUNE THEN START-MUSIC ;

:NONAME ( -- )   1 COURSE +!  START-LEVEL ; IS NEXT-COURSE
: RESTART ( -- )   0 BIG !  START-LEVEL ;
: NEW-GAME ( -- )   0 COURSE !  3 LIVES !  0 SCORE !  0 COINS !  RESTART ;
: LOSE-LIFE ( -- )
   -1 LIVES +!
   LIVES @ 0= IF  S" GAME OVER" FPS 3 * ['] NEW-GAME SAY
   ELSE  S" MISS" FPS ['] RESTART SAY  THEN ;

: CLOCK ( -- )
   TICKS @ 20 MOD IF EXIT THEN
   TIME-LEFT @ 0= IF EXIT THEN
   -1 TIME-LEFT +!  TIME-LEFT @ 0= IF START-DYING THEN ;

\ ---- Input ------------------------------------------------------------------------

VARIABLE PAD-OK  VARIABLE START-WAS
: HELD2 ( c1 c2 -- flag )   KEY-HELD? SWAP KEY-HELD? OR ;
: KEYBOARD ( -- )
   K-LEFT KEY-HELD? IN-LEFT !  K-RIGHT KEY-HELD? IN-RIGHT !
   K-UP KEY-HELD?  [CHAR] z [CHAR] Z HELD2 OR  BL KEY-HELD? OR  IN-JUMP !
   [CHAR] x [CHAR] X HELD2 IN-RUN ! ;
: PAD-BUTTON ( n -- flag )   0 GAMEPAD-BUTTON? ;
: OR! ( flag addr -- )   TUCK @ OR SWAP ! ;
: GAMEPAD ( -- )   \ the first mapped gamepad, when SDL3 is there
   PAD-OK @ 0= IF EXIT THEN
   GAMEPAD-POLL DUP 0< IF  DROP FALSE PAD-OK !  EXIT  THEN
   0= IF EXIT THEN
   0 GAMEPAD-MAPPED? 0= IF EXIT THEN
   13 PAD-BUTTON  0 0 GAMEPAD-AXIS -16000 < OR  IN-LEFT OR!
   14 PAD-BUTTON  0 0 GAMEPAD-AXIS 16000 > OR  IN-RIGHT OR!
   0 PAD-BUTTON  IN-JUMP OR!
   1 PAD-BUTTON 2 PAD-BUTTON OR  IN-RUN OR!
   6 PAD-BUTTON  DUP START-WAS @ 0= AND IF  PAUSED @ 0= PAUSED !  THEN  START-WAS ! ;
: LIVE-INPUT ( -- )   KEYBOARD GAMEPAD ;
DEFER READ-INPUT  ' LIVE-INPUT IS READ-INPUT

: KEY! ( key -- )
   CASE
      [CHAR] p OF  PAUSED @ 0= PAUSED !  ENDOF
      [CHAR] P OF  PAUSED @ 0= PAUSED !  ENDOF
      [CHAR] r OF  MESSAGE-TICKS @ GOAL @ OR 0= IF START-DYING THEN  ENDOF
      [CHAR] R OF  MESSAGE-TICKS @ GOAL @ OR 0= IF START-DYING THEN  ENDOF
      [CHAR] q OF  TRUE DONE !  ENDOF  [CHAR] Q OF  TRUE DONE !  ENDOF
      27       OF  TRUE DONE !  ENDOF
   ENDCASE ;
: KEYS ( -- )   BEGIN INKEY DUP -1 <> WHILE KEY! REPEAT DROP ;

\ ---- A tick of the game ----------------------------------------------------------

: TICK ( -- )
   KEYS READ-INPUT
   MESSAGE-TICKS @ IF
      -1 MESSAGE-TICKS +!  MESSAGE-TICKS @ 0= IF AFTER-MESSAGE @ EXECUTE THEN  EXIT
   THEN
   PAUSED @ IF EXIT THEN
   1 TICKS +!
   BUMP-T @ IF -1 BUMP-T +! THEN
   DYING @ IF  UPDATE-DYING  FELL? IF LOSE-LIFE THEN  EXIT  THEN
   GOAL @ IF  GOAL-TICK UPDATE-ENTITIES  EXIT  THEN
   PLAYER-TICK
   DYING @ IF EXIT THEN
   CAMERA UPDATE-ENTITIES
   REACHED-BALLOON? IF START-GOAL EXIT THEN
   CLOCK ;

\ ---- The pictures ----------------------------------------------------------------

: DAY? ( -- flag )   THEME @ 0= ;

: DRAW-GROUND ( x y tx ty -- )
   1- TILE@ GROUND <> { x y top }
   DAY? IF
      160 100 50 COLOR  x y TS TS FILL-RECT
      120 70 35 COLOR  x 1+ y 5 + PSET  x 5 + y 3 + PSET  x 3 + y 7 + PSET
      top IF  80 190 60 COLOR  x y TS 2 FILL-RECT  50 140 40 COLOR  x y 2 + TS 1 FILL-RECT  THEN
   ELSE
      70 80 115 COLOR  x y TS TS FILL-RECT
      45 50 80 COLOR  x 1+ y 5 + PSET  x 5 + y 3 + PSET  x 3 + y 7 + PSET
      top IF  120 130 170 COLOR  x y TS 1 FILL-RECT  THEN
   THEN ;
: DRAW-BRICK ( x y -- )
   { x y }
   DAY? IF 200 95 50 ELSE 80 120 170 THEN COLOR  x y TS TS FILL-RECT
   DAY? IF 100 45 20 ELSE 30 50 85 THEN COLOR
   x y 3 + TS 1 FILL-RECT  x y 7 + TS 1 FILL-RECT
   x 2 + y 1 3 FILL-RECT  x 6 + y 4 + 1 3 FILL-RECT ;
: DRAW-STAR-BLOCK ( x y -- )   \ a coin or a berry inside
   { x y }
   240 190 50 COLOR  x y TS TS FILL-RECT
   150 90 20 COLOR  x y TS TS RECT
   TICKS @ 8 / 3 AND IF 120 60 10 ELSE 255 250 210 THEN COLOR
   x 3 + y 2 + 2 4 FILL-RECT  x 2 + y 3 + 4 2 FILL-RECT ;
: DRAW-USED ( x y -- )
   { x y }  130 100 70 COLOR  x y TS TS FILL-RECT  80 60 40 COLOR  x y TS TS RECT ;
: DRAW-HARD ( x y -- )
   { x y }
   DAY? IF 150 150 160 ELSE 95 95 120 THEN COLOR  x y TS TS FILL-RECT
   DAY? IF 205 205 215 ELSE 140 140 170 THEN COLOR  x y TS 1 FILL-RECT  x y 1 TS FILL-RECT
   DAY? IF 90 90 100 ELSE 50 50 70 THEN COLOR  x y 7 + TS 1 FILL-RECT  x 7 + y 1 TS FILL-RECT ;
: DRAW-TUBE ( x y left? top? -- )
   { x y left top }
   40 160 140 COLOR  x y TS TS FILL-RECT
   left IF  120 225 200 COLOR  x 2 + y 2 TS FILL-RECT  20 90 80 COLOR  x y 1 TS FILL-RECT
   ELSE  20 90 80 COLOR  x 7 + y 1 TS FILL-RECT  x 4 + y 1 TS FILL-RECT  THEN
   top IF  20 90 80 COLOR  x y TS 1 FILL-RECT  x y 7 + TS 1 FILL-RECT  THEN ;
: DRAW-COIN ( x y -- )
   { x y }  250 210 40 COLOR
   TICKS @ 16 / 1 AND IF  x 2 + y 1+ 4 6 FILL-RECT  ELSE  x 3 + y 1+ 2 6 FILL-RECT  THEN
   255 250 180 COLOR  x 3 + y 2 + 1 3 FILL-RECT ;

: BUMPED ( y tx ty -- y' )   \ a block bumped from below goes up and back
   BUMP-Y @ = SWAP BUMP-X @ = AND  BUMP-T @ AND IF  4 BUMP-T @ 4 - ABS - -  THEN ;

: DRAW-TILE ( x y t tx ty -- )
   { x y t tx ty }
   t CASE
      GROUND OF  x y tx ty DRAW-GROUND  ENDOF
      BRICK OF  x y tx ty BUMPED DRAW-BRICK  ENDOF
      QCOIN OF  x y tx ty BUMPED DRAW-STAR-BLOCK  ENDOF
      QBERRY OF  x y tx ty BUMPED DRAW-STAR-BLOCK  ENDOF
      USED OF  x y tx ty BUMPED DRAW-USED  ENDOF
      HARD OF  x y DRAW-HARD  ENDOF
      TUBE-TL OF  x y TRUE TRUE DRAW-TUBE  ENDOF
      TUBE-TR OF  x y FALSE TRUE DRAW-TUBE  ENDOF
      TUBE-L OF  x y TRUE FALSE DRAW-TUBE  ENDOF
      TUBE-R OF  x y FALSE FALSE DRAW-TUBE  ENDOF
      COIN OF  x y DRAW-COIN  ENDOF
   ENDCASE ;

: DRAW-MAP ( -- )
   CAM @ >TILE  CAM @ 7 AND NEGATE  { c0 ox }
   ROWS 0 DO
      VIEW-COLS 1+ 0 DO
         I c0 + J TILE@ ?DUP IF  >R I TS * ox +  J TS *  R>  I c0 + J DRAW-TILE  THEN
      LOOP
   LOOP ;

: CLOUD ( x y -- )   { x y }  x y 6 FILL-CIRCLE  x 7 + y 3 - 7 FILL-CIRCLE  x 14 + y 5 FILL-CIRCLE ;

\ Far hills and clouds by day, which move slower than the ground; dim rocks in a cave.
: BACKDROP ( -- )
   DAY? IF
      120 180 250 RGB GFX-CLS
      70 160 90 COLOR
      5 0 DO  I 176 * CAM @ 2/ 176 MOD - 40 +  168 30 FILL-CIRCLE  LOOP
      100 185 110 COLOR
      5 0 DO  I 176 * 88 + CAM @ 2/ 176 MOD - 40 +  172 20 FILL-CIRCLE  LOOP
      250 250 255 COLOR
      4 0 DO  I 112 * CAM @ 2/ 2/ 112 MOD - 30 +  I 1 AND 12 * 30 +  CLOUD  LOOP
   ELSE
      14 14 30 RGB GFX-CLS
      35 35 60 COLOR
      9 0 DO  I 40 * CAM @ 2/ 40 MOD - 12 +  I 3 AND 30 * 40 +  2 FILL-CIRCLE  LOOP
   THEN ;

\ 8 pixels a row, a byte a row, the leftmost pixel the highest bit; FLIP mirrors them.
VARIABLE FLIP
: LAYER ( addr n x y -- )
   { a n x y }
   n 0 DO
      a I + C@ ?DUP IF
         8 0 DO
            DUP 128 I RSHIFT AND IF  x FLIP @ IF 7 I - ELSE I THEN +  y J +  PSET  THEN
         LOOP DROP
      THEN
   LOOP ;

\ The hopper, small (8 rows) and big (16 rows), facing right.
CREATE S-HOOD   $3C C, $7E C, $60 C, $60 C,
CREATE S-FACE   $00 C, $00 C, $1E C, $1E C,
CREATE S-EYE    $00 C, $00 C, $04 C,
CREATE S-COAT   $3C C, $7E C,
CREATE S-STAND  $24 C, $66 C,
CREATE S-WALK1  $42 C, $C3 C,
CREATE S-WALK2  $18 C, $18 C,
CREATE S-JUMP   $42 C, $81 C,

CREATE B-HOOD   $3C C, $7E C, $FE C, $C0 C, $C0 C, $E0 C,
CREATE B-FACE   $00 C, $00 C, $00 C, $3E C, $3E C, $1C C,
CREATE B-EYE    $00 C, $00 C, $00 C, $00 C, $04 C,
CREATE B-COAT   $3C C, $7E C, $FF C, $FF C, $FF C, $7E C, $7E C,
CREATE B-HANDS  $81 C,
CREATE B-BELT   $7E C,
CREATE B-STAND  $66 C, $66 C, $E7 C,
CREATE B-WALK1  $C3 C, $C3 C, $81 C,
CREATE B-WALK2  $3C C, $18 C, $3C C,
CREATE B-JUMP   $C6 C, $C0 C, $C0 C,

: HOOD-COLOR ( -- )   240 140 40 COLOR ;
: SKIN-COLOR ( -- )   250 210 165 COLOR ;
: COAT-COLOR ( -- )   50 110 200 COLOR ;
: DARK-COLOR ( -- )   40 30 30 COLOR ;

\ 0 standing, 1 and 2 walking, 3 in the air.
: POSE ( -- n )
   DYING @ ONGROUND @ 0= OR GOAL @ 0= AND IF 3 EXIT THEN
   PVX @ 0= GOAL @ OR IF 0 EXIT THEN
   WALK-T @ 64 / 1 AND 1+ ;

: DRAW-SMALL ( x y -- )
   { x y }
   HOOD-COLOR S-HOOD 4 x y LAYER  SKIN-COLOR S-FACE 4 x y LAYER  DARK-COLOR S-EYE 3 x y LAYER
   COAT-COLOR S-COAT 2 x y 4 + LAYER
   DARK-COLOR
   POSE CASE  0 OF S-STAND ENDOF  1 OF S-WALK1 ENDOF  2 OF S-WALK2 ENDOF  S-JUMP SWAP  ENDCASE
   2 x y 6 + LAYER ;
: DRAW-BIG ( x y -- )
   { x y }
   HOOD-COLOR B-HOOD 6 x y LAYER  SKIN-COLOR B-FACE 6 x y LAYER  DARK-COLOR B-EYE 5 x y LAYER
   COAT-COLOR B-COAT 7 x y 6 + LAYER
   SKIN-COLOR B-HANDS 1 x y 9 + LAYER
   90 50 20 COLOR B-BELT 1 x y 10 + LAYER
   DARK-COLOR
   POSE CASE  0 OF B-STAND ENDOF  1 OF B-WALK1 ENDOF  2 OF B-WALK2 ENDOF  B-JUMP SWAP  ENDCASE
   3 x y 13 + LAYER ;

: DRAW-PLAYER ( -- )
   GOAL @ 2 >= IF EXIT THEN
   INVULN @ 4 / 1 AND IF EXIT THEN
   FACING @ 0< FLIP !
   PX @ >PX 1- CAM @ -  PY @ >PX
   BIG @  GROW-T @ 4 / 1 AND 0= AND IF DRAW-BIG ELSE
      BIG @ IF 8 + THEN DRAW-SMALL
   THEN
   FALSE FLIP ! ;

\ A mossling, a snail, its shell, and the berry.
CREATE M-BODY   $3C C, $7E C, $FF C, $FF C, $FF C, $7E C,
CREATE M-WHITE  $00 C, $00 C, $66 C,
CREATE M-PUPIL  $00 C, $00 C, $22 C,
CREATE M-FEET1  $66 C, $E7 C,
CREATE M-FEET2  $3C C, $66 C,
CREATE M-FLAT   $7E C, $FF C,
CREATE N-SHELL  $1C C, $3E C, $7F C, $7F C, $7F C, $3E C,
CREATE N-CURL   $00 C, $00 C, $18 C, $24 C, $1C C,
CREATE N-BODY1  $00 C, $80 C, $80 C, $80 C, $80 C, $C0 C, $FF C, $7E C,
CREATE N-BODY2  $00 C, $80 C, $80 C, $80 C, $80 C, $C0 C, $FF C, $FE C,
CREATE N-EYE    $00 C, $80 C,
CREATE R-BODY   $3C C, $7E C, $FF C, $FF C, $7E C, $3C C,
CREATE R-LEAF   $0C C, $18 C,
CREATE R-SHINE  $00 C, $20 C,

: STEP2 ( -- flag )   TICKS @ 10 / 1 AND ;

: DRAW-MOSS ( x y -- )
   { x y }
   90 165 60 COLOR M-BODY 6 x y LAYER
   255 255 255 COLOR M-WHITE 3 x y LAYER  20 20 20 COLOR M-PUPIL 3 x y LAYER
   100 60 30 COLOR  STEP2 IF M-FEET1 ELSE M-FEET2 THEN 2 x y 6 + LAYER ;
: DRAW-FLAT ( x y -- )   { x y }  90 165 60 COLOR M-FLAT 2 x y 6 + LAYER ;
: DRAW-SHELL ( x y -- )
   { x y }
   175 95 215 COLOR N-SHELL 6 x y LAYER  100 40 140 COLOR N-CURL 5 x y LAYER ;
: DRAW-SNAIL ( x y -- )
   { x y }
   240 220 140 COLOR  STEP2 IF N-BODY1 ELSE N-BODY2 THEN 8 x y LAYER
   x y DRAW-SHELL  40 30 30 COLOR N-EYE 2 x y LAYER ;
: DRAW-BERRY ( x y -- )
   { x y }
   220 40 60 COLOR R-BODY 6 x y 2 + LAYER
   60 170 60 COLOR R-LEAF 2 x y LAYER  255 200 210 COLOR R-SHINE 2 x y 2 + LAYER ;
: DRAW-CHIP ( x y -- )   DAY? IF 200 95 50 ELSE 80 120 170 THEN COLOR  3 3 FILL-RECT ;

: DRAW-E ( i -- )
   DUP EX @ >PX CAM @ -  OVER EY @ >PX  ROT  { x y i }
   i EVX @ 0> FLIP !
   i ETYPE @ CASE
      E-MOSS OF  x y DRAW-MOSS  ENDOF
      E-SNAIL OF  x y DRAW-SNAIL  ENDOF
      E-SHELL OF
         i EVX @ 0=  i ETIME @ 300 > AND IF  TICKS @ 2/ 1 AND x + TO x  THEN
         x y 2 + DRAW-SHELL
      ENDOF
      E-BERRY OF  x y DRAW-BERRY  ENDOF
      E-COIN OF  x y DRAW-COIN  ENDOF
      E-CHIP OF  x y DRAW-CHIP  ENDOF
      E-FLAT OF  x y DRAW-FLAT  ENDOF
      E-KNOCKED OF  i ESTATE @ E-MOSS = IF x y DRAW-MOSS ELSE x y 2 + DRAW-SHELL THEN  ENDOF
   ENDCASE
   FALSE FLIP ! ;

\ A berry coming up out of its block is drawn before the blocks, so that they hide it.
: EMERGING? ( i -- flag )   DUP ETYPE @ E-BERRY =  SWAP ESTATE @ 0<> AND ;
: DRAW-EMERGING ( -- )   MAX-E 0 DO  I EMERGING? IF I DRAW-E THEN  LOOP ;
: DRAW-ENTITIES ( -- )
   MAX-E 0 DO  I ETYPE @ IF  I EMERGING? 0= IF I DRAW-E THEN  THEN  LOOP ;

\ The balloon: the envelope and the ropes behind the hopper, the basket in front.
: BASKET ( -- x y )   BASKET-X CAM @ -  148 LIFT @ - ;
: DRAW-ENVELOPE ( -- )
   BASKET { x y }
   x 12 + 0< IF EXIT THEN  x W > IF EXIT THEN
   220 220 200 COLOR
   x y x 6 + y 22 - LINE  x 11 + y x 6 + y 22 - LINE
   x 2 - y 14 - x 1+ y LINE  x 13 + y 14 - x 10 + y LINE
   230 70 60 COLOR  x 6 + y 30 - 16 FILL-CIRCLE
   250 200 60 COLOR  x 6 + y 30 - 10 FILL-CIRCLE
   230 70 60 COLOR  x 6 + y 30 - 4 FILL-CIRCLE
   250 200 60 COLOR  x 4 + y 16 - 5 3 FILL-RECT ;
: DRAW-BASKET ( -- )
   BASKET { x y }
   150 95 45 COLOR  x y 12 8 FILL-RECT
   100 60 25 COLOR  x y 12 1 FILL-RECT  x y 4 + 12 1 FILL-RECT
   x 4 + y 1 8 FILL-RECT  x 8 + y 1 8 FILL-RECT ;

\ ---- The line at the top, and messages ------------------------------------------

: N>S ( n digits -- c-addr u )   >R S>D <# R> 0 ?DO # LOOP #> ;
: SHADOWED ( c-addr u x -- )   >R 2DUP  20 20 40 COLOR  R@ 1+ 3 TEXT  255 255 255 COLOR  R> 2 TEXT ;

: STATUS ( -- )
   S" SCORE" 4 SHADOWED     SCORE @ 6 N>S 28 SHADOWED
   S" COIN" 64 SHADOWED     COINS @ 2 N>S 84 SHADOWED
   S" COURSE" 104 SHADOWED  COURSE @ 1+ 1 N>S 132 SHADOWED
   S" TIME" 150 SHADOWED    TIME-LEFT @ 3 N>S 170 SHADOWED
   S" LIFE" 196 SHADOWED    LIVES @ 0 MAX 2 N>S 216 SHADOWED ;

: SHOW-MESSAGE ( -- )
   MESSAGE-TICKS @ PAUSED @ OR 0= IF EXIT THEN
   2 TEXT-SCALE
   MESSAGE-TICKS @ IF MESSAGE 2@ ELSE S" PAUSED" THEN
   2DUP TEXT-WIDTH  W OVER - 2/ { w x }
   0 0 0 COLOR  x 6 - 70 w 12 + 26 FILL-RECT
   255 230 80 COLOR  x 75 TEXT
   1 TEXT-SCALE ;

: DRAW ( -- )
   BACKDROP DRAW-EMERGING DRAW-MAP DRAW-ENVELOPE DRAW-ENTITIES DRAW-PLAYER DRAW-BASKET
   STATUS SHOW-MESSAGE ;

: SKY-HOPPER ( -- )
   W H GFX-INIT  W 4 * H 4 * WINDOW-SIZE  MAKE-SOUNDS MAKE-MUSIC-SOUNDS
   TRUE PAD-OK !  FALSE START-WAS !
   NEW-GAME  FALSE DONE !  FALSE PAUSED !
   BEGIN  TICK MUSIC-TICK DRAW  FRAME-MS FRAME  DONE @ UNTIL
   STOP-MUSIC
   CR ." Score: " SCORE @ . CR ;

[UNDEFINED] NO-AUTORUN [IF] SKY-HOPPER [THEN]
