\ Classic Runner: a test of whether FORTH/Sigma is able, and fast enough, to run a
\ tile game of the "dig and run" kind. The levels, the pictures, and the guards' rules
\ are this file's own.
\
\   sigma.exe examples/runner.fs     (in a window; Tk on Linux/macOS)
\
\ Collect all the gold; a hidden ladder then appears, and the top row ends the level.
\ Keys: arrows move, Z and X dig to the left and the right below, P pauses, R gives up
\ the level (a life), Q or Esc ends. On Windows the keys go to the console Sigma runs
\ in. The line at the bottom shows the time the game's work takes each frame (MS) and
\ the frames shown each second (FPS). With the audio words, gold, digging, and the
\ guards make sounds, and a short tune marks the ladders, a cleared level, and the end.

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

0 CONSTANT S-GOLD  1 CONSTANT S-DIG  2 CONSTANT S-CRUSH  3 CONSTANT S-CAUGHT
HAS-SOUND [IF]
: MAKE-SOUNDS ( -- )
   400 8 -1 SQUARE-SWEEP  400 S-GOLD KEEP         \ a quick rising chirp
   1200 NOISE-BURST  1200 S-DIG KEEP               \ a scrape
   1600 20 2 SQUARE-SWEEP  1600 S-CRUSH KEEP       \ a low thud
   4000 5 1 SQUARE-SWEEP  4000 S-CAUGHT KEEP ;     \ falling for half a second
[ELSE]
: MAKE-SOUNDS ( -- ) ;
[THEN]

28 CONSTANT COLS
16 CONSTANT ROWS
8 CONSTANT TS                       \ a tile is TS by TS pixels
COLS TS * CONSTANT W
ROWS TS * 12 + CONSTANT H           \ the map, and a line below it
40 CONSTANT FPS
1000 FPS / CONSTANT FRAME-MS
FPS 5 * CONSTANT HOLE-TICKS         \ a hole fills again after 5 s
FPS CONSTANT TRAP-TICKS             \ a guard is held in a hole (guards' ticks)

0 CONSTANT EMPTY   1 CONSTANT BRICK   2 CONSTANT SOLID   3 CONSTANT LADDER
4 CONSTANT ROPE    5 CONSTANT GOLD    6 CONSTANT HIDDEN  7 CONSTANT HOLE

\ ---- The map -----------------------------------------------------------------------

CREATE MAP  COLS ROWS * ALLOT
CREATE TIMERS  COLS ROWS * CELLS ALLOT

: INSIDE? ( tx ty -- flag )   0 ROWS WITHIN SWAP 0 COLS WITHIN AND ;
: >INDEX ( tx ty -- n )   COLS * + ;
\ Above the map is open; beside and below it is solid.
: TILE@ ( tx ty -- t )
   2DUP INSIDE? IF  >INDEX MAP + C@ EXIT  THEN
   NIP 0< IF EMPTY ELSE SOLID THEN ;
: TILE! ( t tx ty -- )   >INDEX MAP + C! ;
: TIMER ( tx ty -- addr )   >INDEX CELLS TIMERS + ;
: BLOCKS? ( t -- flag )   DUP BRICK = SWAP SOLID = OR ;
: BLOCKED? ( tx ty -- flag )   TILE@ BLOCKS? ;
: FLOOR? ( t -- flag )   DUP BLOCKS? SWAP LADDER = OR ;

\ ---- The runner (0) and the guards (1 ..) ------------------------------------------

8 CONSTANT MAX-E
: ENTITY-FIELD ( "name" -- )   CREATE MAX-E CELLS ALLOT  DOES> ( i -- addr ) SWAP CELLS + ;
ENTITY-FIELD EX  ENTITY-FIELD EY  ENTITY-FIELD EDX  ENTITY-FIELD EDY
ENTITY-FIELD ESTATE  ENTITY-FIELD ETIME
VARIABLE #E
0 CONSTANT ROAMING  1 CONSTANT TRAPPED  2 CONSTANT CLIMBING  3 CONSTANT ESCAPING

: TX ( i -- tx )   EX @ TS 2/ + TS / ;
: TY ( i -- ty )   EY @ TS 2/ + TS / ;
: ALIGNED? ( i -- flag )   DUP EX @ TS MOD 0=  SWAP EY @ TS MOD 0=  AND ;
: GO ( dx dy i -- )   TUCK EDY ! EDX ! ;
: STEP ( i -- )   DUP EDX @ OVER EX +!  DUP EDY @ SWAP EY +! ;

VARIABLE LEVEL  VARIABLE LIVES  VARIABLE SCORE  VARIABLE GOLD-LEFT
VARIABLE DIG    VARIABLE DEAD   VARIABLE PAUSED VARIABLE DONE  VARIABLE TICKS
VARIABLE FALLING

VARIABLE SEED
: RANDOM ( n -- 0..n-1 )   SEED @ 6364136223846793005 * 1442695040888963407 +  DUP SEED !  33 RSHIFT  SWAP MOD ;
: SGN ( n -- -1|0|1 )   DUP 0< IF DROP -1 EXIT THEN  0<> 1 AND ;

\ ---- The levels --------------------------------------------------------------------
\ # brick (dug), = solid, H ladder, - rope, $ gold, S ladder that appears with the last
\ gold, P the runner, G a guard; anything else is empty.

: ADD-GUARD ( tx ty -- )
   #E @ MAX-E < 0= IF 2DROP EXIT THEN
   #E @ >R  TS * R@ EY !  TS * R@ EX !  0 0 R@ GO  ROAMING R@ ESTATE !  R> DROP  1 #E +! ;

: PUT-CHAR ( char tx ty -- )
   ROT CASE
      [CHAR] # OF  BRICK  ENDOF
      [CHAR] = OF  SOLID  ENDOF
      [CHAR] H OF  LADDER  ENDOF
      [CHAR] - OF  ROPE  ENDOF
      [CHAR] $ OF  1 GOLD-LEFT +!  GOLD  ENDOF
      [CHAR] S OF  HIDDEN  ENDOF
      [CHAR] P OF  2DUP TS * 0 EY !  TS * 0 EX !  EMPTY  ENDOF
      [CHAR] G OF  2DUP ADD-GUARD  EMPTY  ENDOF
      EMPTY SWAP
   ENDCASE  -ROT TILE! ;

: ROW ( c-addr u ty -- )   { a u ty }  u COLS MIN 0 ?DO  a I + C@ I ty PUT-CHAR  LOOP ;

: LEVEL-1 ( -- )
   S" S                           " 0 ROW
   S" S    $              $       " 1 ROW
   S" S########H###   #######H### " 2 ROW
   S" S        H          G  H    " 3 ROW
   S" S        H-------------H    " 4 ROW
   S" S        H             H    " 5 ROW
   S" S   $    H    $        H  $ " 6 ROW
   S" S####H#####   ####H#########" 7 ROW
   S"      H            H         " 8 ROW
   S"      H     G      H         " 9 ROW
   S"   ######H######H######      " 10 ROW
   S"         H      H      H     " 11 ROW
   S"    $    H  P   H   $  H     " 12 ROW
   S" ##H#########################" 13 ROW
   S"   H                     $   " 14 ROW
   S" ============================" 15 ROW ;

: LEVEL-2 ( -- )
   S"                             " 0 ROW
   S"   S                     G   " 1 ROW
   S"   S   $      $      $       " 2 ROW
   S" ##S#######H######H##########" 3 ROW
   S"           H      H          " 4 ROW
   S"    $      H  P   H     $    " 5 ROW
   S" #####H###############H######" 6 ROW
   S"      H       $       H      " 7 ROW
   S"      H    #######    H      " 8 ROW
   S"      H               H      " 9 ROW
   S"    ##########H##########    " 10 ROW
   S"              H              " 11 ROW
   S"     $        H    G         " 12 ROW
   S" #######H################H###" 13 ROW
   S"        H      $$        H   " 14 ROW
   S" ============================" 15 ROW ;

CREATE LEVELS  ' LEVEL-1 ,  ' LEVEL-2 ,
2 CONSTANT #LEVELS

: START-LEVEL ( -- )
   MAP COLS ROWS * ERASE  TIMERS COLS ROWS * CELLS ERASE
   1 #E !  0 GOLD-LEFT !  0 0 0 GO  ROAMING 0 ESTATE !
   0 DIG !  0 DEAD !  FALSE FALLING !
   LEVEL @ #LEVELS MOD CELLS LEVELS + @ EXECUTE ;

\ ---- Standing, holes, and gold -----------------------------------------------------

: TRAPPED-AT? ( tx ty -- flag )   \ a guard held in a hole there
   #E @ 1 ?DO
      I ESTATE @ TRAPPED =  I TX 3 PICK = AND  I TY 2 PICK = AND
      IF 2DROP TRUE UNLOOP EXIT THEN
   LOOP 2DROP FALSE ;

\ On a ladder or a rope, on a floor or a ladder, or on the head of a guard in a hole.
: SUPPORTED? ( i -- flag )
   DUP TX SWAP TY { tx ty }
   tx ty TILE@ DUP LADDER = SWAP ROPE = OR IF TRUE EXIT THEN
   tx ty 1+ TILE@ DUP FLOOR? IF DROP TRUE EXIT THEN
   HOLE = IF tx ty 1+ TRAPPED-AT? EXIT THEN
   FALSE ;

: REVEAL ( -- )   \ the hidden ladders
   COLS ROWS * 0 DO  MAP I + C@ HIDDEN = IF LADDER MAP I + C! THEN  LOOP ;

: PICK-GOLD ( -- )
   0 TX 0 TY TILE@ GOLD <> IF EXIT THEN
   EMPTY 0 TX 0 TY TILE!  100 SCORE +!  S-GOLD EFFECT
   -1 GOLD-LEFT +!  GOLD-LEFT @ 0= IF  REVEAL  S" T200 L32 O5 CEG>CEG>C" JINGLE  THEN ;

: RESPAWN ( i -- )   \ a guard again, from the top
   >R  BEGIN COLS RANDOM DUP 0 TILE@ EMPTY <> WHILE DROP REPEAT
   TS * R@ EX !  0 R@ EY !  0 0 R@ GO  ROAMING R@ ESTATE !  R> DROP ;

: CRUSHED ( i -- )   ?DUP IF  RESPAWN 200 SCORE +!  S-CRUSH EFFECT  ELSE TRUE DEAD ! THEN ;

: CLOSE-HOLE ( tx ty -- )   \ whoever is in it
   2DUP BRICK -ROT TILE!
   #E @ 0 ?DO  I TX 2 PICK =  I TY 2 PICK = AND  IF I CRUSHED THEN  LOOP 2DROP ;

: UPDATE-HOLES ( -- )
   ROWS 0 DO  COLS 0 DO
      I J TILE@ HOLE = IF
         -1 I J TIMER +!  I J TIMER @ 0 <= IF I J CLOSE-HOLE THEN
      THEN
   LOOP  LOOP ;

\ ---- The runner --------------------------------------------------------------------

: HELD? ( key -- flag )   KEY-HELD? ;

: TRY-DIG ( -- flag )   \ digs below to the side DIG asked, when it can
   DIG @ DUP 0= IF EXIT THEN
   0 DIG !  0 TX + 0 TY { x y }
   x y 1+ TILE@ BRICK =  x y TILE@ DUP EMPTY = SWAP HIDDEN = OR  AND
   IF  HOLE x y 1+ TILE!  HOLE-TICKS x y 1+ TIMER !  S-DIG EFFECT  TRUE  ELSE FALSE THEN ;

: WANTS ( -- dx dy )
   0 TX 0 TY { x y }
   K-UP HELD? IF
      x y TILE@ LADDER =  y 0> AND  x y 1- BLOCKED? 0= AND IF 0 -1 EXIT THEN
   THEN
   K-DOWN HELD? IF
      x y 1+ TILE@ LADDER = IF 0 1 EXIT THEN
      x y TILE@ DUP LADDER = SWAP ROPE = OR  x y 1+ BLOCKED? 0= AND IF 0 1 EXIT THEN
   THEN
   K-LEFT HELD? IF  x 1- y BLOCKED? 0= IF -1 0 EXIT THEN  THEN
   K-RIGHT HELD? IF  x 1+ y BLOCKED? 0= IF 1 0 EXIT THEN  THEN
   0 0 ;

: DECIDE-RUNNER ( -- )
   0 SUPPORTED? 0= IF  TRUE FALLING !  0 1 0 GO EXIT  THEN
   FALSE FALLING !
   TRY-DIG IF 0 0 0 GO EXIT THEN
   WANTS 0 GO ;

\ Between two tiles the runner may turn back, but not while falling.
: TURN-RUNNER ( -- )
   FALLING @ IF EXIT THEN
   0 EDX @ 0< K-RIGHT HELD? AND IF  1 0 EDX !  THEN
   0 EDX @ 0> K-LEFT HELD? AND IF  -1 0 EDX !  THEN
   0 EDY @ 0< K-DOWN HELD? AND IF  1 0 EDY !  THEN
   0 EDY @ 0> K-UP HELD? AND IF  -1 0 EDY !  THEN ;

: MOVE-RUNNER ( -- )   0 ALIGNED? IF DECIDE-RUNNER ELSE TURN-RUNNER THEN  0 STEP ;

\ ---- The guards --------------------------------------------------------------------

: CAN-UP? ( x y -- flag )   DUP 0> >R  2DUP TILE@ LADDER = >R  1- BLOCKED? 0= R> AND R> AND ;
: CAN-DOWN? ( x y -- flag )   \ a ladder below, or nothing to stand on
   1+ TILE@ DUP LADDER = IF DROP TRUE EXIT THEN  FLOOR? 0= ;

VARIABLE LEFT-OPEN  VARIABLE RIGHT-OPEN
: WAY? ( x y up? -- flag )   IF CAN-UP? ELSE CAN-DOWN? THEN ;
\ The side of the nearest column of this row where the guard can go up (or down),
\ looking along the row until a wall; 0 when there is none.
: FIND-WAY ( x y up? -- dx )
   { x y up }  TRUE LEFT-OPEN !  TRUE RIGHT-OPEN !
   COLS 1 DO
      LEFT-OPEN @ IF
         x I - y BLOCKED? IF FALSE LEFT-OPEN ! ELSE  x I - y up WAY? IF -1 UNLOOP EXIT THEN  THEN
      THEN
      RIGHT-OPEN @ IF
         x I + y BLOCKED? IF FALSE RIGHT-OPEN ! ELSE  x I + y up WAY? IF 1 UNLOOP EXIT THEN  THEN
      THEN
   LOOP 0 ;

: CHASE ( i -- dx dy )
   DUP TX SWAP TY  0 TX 0 TY  { x y px py }
   py y < IF  x y CAN-UP? IF 0 -1 EXIT THEN  THEN
   py y > IF  x y CAN-DOWN? IF 0 1 EXIT THEN  THEN
   py y = IF  px x - SGN
   ELSE  x y py y < FIND-WAY  DUP 0= IF DROP px x - SGN THEN  THEN
   DUP x + y BLOCKED? IF DROP 0 THEN  0 ;

: DECIDE-GUARD ( i -- )
   >R
   R@ TX R@ TY TILE@ HOLE = IF
      TRAPPED R@ ESTATE !  TRAP-TICKS R@ ETIME !  0 0 R> GO  EXIT
   THEN
   R@ SUPPORTED? 0= IF 0 1 R> GO EXIT THEN
   R@ CHASE R> GO ;

\ Out of the hole: to the side of the runner, or the other one.
: ESCAPE ( i -- )
   >R  ESCAPING R@ ESTATE !  TS R@ ETIME !
   0 TX R@ TX - SGN  DUP 0= IF DROP 1 THEN
   DUP R@ TX + R@ TY BLOCKED? IF NEGATE THEN
   DUP R@ TX + R@ TY BLOCKED? IF DROP 0 THEN
   0 R> GO ;

: COUNT-DOWN ( i -- flag )   -1 OVER ETIME +!  ETIME @ 0 <= ;

: UPDATE-GUARD ( i -- )
   DUP ESTATE @ CASE
      ROAMING OF  DUP ALIGNED? IF DUP DECIDE-GUARD THEN  DUP STEP  ENDOF
      TRAPPED OF
         DUP COUNT-DOWN IF  CLIMBING OVER ESTATE !  TS OVER ETIME !  0 -1 2 PICK GO  THEN
      ENDOF
      CLIMBING OF  DUP STEP  DUP COUNT-DOWN IF DUP ESCAPE THEN  ENDOF
      ESCAPING OF  DUP STEP  DUP COUNT-DOWN IF ROAMING OVER ESTATE ! THEN  ENDOF
   ENDCASE DROP ;

\ The guards move on two ticks of three, slower than the runner.
: UPDATE-GUARDS ( -- )
   TICKS @ 3 MOD 0= IF EXIT THEN
   #E @ 1 ?DO  I UPDATE-GUARD  LOOP ;

: CAUGHT? ( -- flag )
   #E @ 1 ?DO
      I EX @ 0 EX @ - ABS 6 <  I EY @ 0 EY @ - ABS 6 < AND  IF TRUE UNLOOP EXIT THEN
   LOOP FALSE ;

\ ---- The game ----------------------------------------------------------------------

2VARIABLE MESSAGE  VARIABLE MESSAGE-TICKS  VARIABLE AFTER-MESSAGE
\ Shows the text for a while, the game stopped, then runs xt.
: SAY ( c-addr u ticks xt -- )   AFTER-MESSAGE !  MESSAGE-TICKS !  MESSAGE 2! ;

: NEW-GAME ( -- )   0 LEVEL !  5 LIVES !  0 SCORE !  START-LEVEL ;
: LOSE-LIFE ( -- )
   -1 LIVES +!
   LIVES @ 0= IF  S" GAME OVER" FPS 3 * ['] NEW-GAME SAY  S" T120 L8 O4 GEC<G2" JINGLE
   ELSE  S" CAUGHT" FPS ['] START-LEVEL SAY  S-CAUGHT EFFECT  THEN ;
: CLEARED ( -- )
   1 LEVEL +!  1000 SCORE +!  S" LEVEL CLEAR" FPS 2* ['] START-LEVEL SAY
   S" T160 L16 O5 CEG>C4" JINGLE ;
: WON? ( -- flag )   GOLD-LEFT @ 0=  0 TY 0= AND  0 ALIGNED? AND ;

\ P held down repeats: only a press 0.6 s after the last P seen changes the pause.
VARIABLE LAST-P
: TOGGLE-PAUSE ( -- )
   UTIME DROP  DUP LAST-P @ - 600000 > IF  PAUSED @ 0= PAUSED !  THEN  LAST-P ! ;

: KEY! ( key -- )
   CASE
      [CHAR] z OF  -1 DIG !  ENDOF   [CHAR] Z OF  -1 DIG !  ENDOF
      [CHAR] x OF  1 DIG !  ENDOF    [CHAR] X OF  1 DIG !  ENDOF
      [CHAR] p OF  TOGGLE-PAUSE  ENDOF
      [CHAR] P OF  TOGGLE-PAUSE  ENDOF
      [CHAR] r OF  MESSAGE-TICKS @ 0= IF LOSE-LIFE THEN  ENDOF
      [CHAR] R OF  MESSAGE-TICKS @ 0= IF LOSE-LIFE THEN  ENDOF
      [CHAR] q OF  TRUE DONE !  ENDOF  [CHAR] Q OF  TRUE DONE !  ENDOF
      27       OF  TRUE DONE !  ENDOF
   ENDCASE ;
: KEYS ( -- )   BEGIN INKEY DUP -1 <> WHILE KEY! REPEAT DROP ;

: TICK ( -- )
   KEYS
   MESSAGE-TICKS @ IF
      -1 MESSAGE-TICKS +!  MESSAGE-TICKS @ 0= IF AFTER-MESSAGE @ EXECUTE THEN  EXIT
   THEN
   PAUSED @ IF EXIT THEN
   1 TICKS +!
   MOVE-RUNNER PICK-GOLD UPDATE-GUARDS UPDATE-HOLES
   DEAD @ CAUGHT? OR IF  0 DEAD !  LOSE-LIFE EXIT  THEN
   WON? IF CLEARED THEN ;

\ ---- The pictures ------------------------------------------------------------------

: DRAW-BRICK ( x y -- )
   { x y }  170 70 40 COLOR  x y TS TS FILL-RECT
   110 40 20 COLOR  x y 3 + TS 1 FILL-RECT  x y 7 + TS 1 FILL-RECT
   x 3 + y 1 3 FILL-RECT  x 6 + y 4 + 1 3 FILL-RECT ;
: DRAW-SOLID ( x y -- )
   { x y }  110 110 125 COLOR  x y TS TS FILL-RECT
   170 170 185 COLOR  x y TS 1 FILL-RECT  x y 1 TS FILL-RECT ;
: DRAW-LADDER ( x y -- )
   { x y }  210 210 210 COLOR
   x 1+ y 1 TS FILL-RECT  x 6 + y 1 TS FILL-RECT
   x 1+ y 2 + 6 1 FILL-RECT  x 1+ y 6 + 6 1 FILL-RECT ;
: DRAW-ROPE ( x y -- )   200 160 110 COLOR  1+ TS 1 FILL-RECT ;
: DRAW-GOLD ( x y -- )
   { x y }  230 190 0 COLOR  x 2 + y 4 + 4 4 FILL-RECT
   255 240 120 COLOR  x 3 + y 4 + 2 1 FILL-RECT ;
\ A hole filling again: the brick grows up from the bottom in its last 0.6 s.
: DRAW-HOLE ( x y tx ty -- )
   TIMER @ 24 - NEGATE 3 /  DUP 0> IF
      { x y h }  170 70 40 COLOR  x y TS + h - TS h FILL-RECT
   ELSE DROP 2DROP THEN ;

: DRAW-TILE ( tx ty -- )
   { tx ty }  tx TS * ty TS *  tx ty TILE@
   CASE
      BRICK OF  DRAW-BRICK  ENDOF
      SOLID OF  DRAW-SOLID  ENDOF
      LADDER OF  DRAW-LADDER  ENDOF
      ROPE OF  DRAW-ROPE  ENDOF
      GOLD OF  DRAW-GOLD  ENDOF
      HOLE OF  tx ty DRAW-HOLE  ENDOF
      >R 2DROP R>
   ENDCASE ;

: DRAW-MAP ( -- )   ROWS 0 DO  COLS 0 DO  I J DRAW-TILE  LOOP  LOOP ;

\ 8 by 8 pictures, a byte a row, the leftmost pixel the highest bit.
CREATE RUNNER-A  $18 C, $18 C, $7E C, $BD C, $3C C, $24 C, $42 C, $C3 C,
CREATE RUNNER-B  $18 C, $18 C, $7E C, $BD C, $3C C, $24 C, $24 C, $66 C,
CREATE GUARD-A   $3C C, $5A C, $3C C, $7E C, $BD C, $24 C, $42 C, $C3 C,
CREATE GUARD-B   $3C C, $5A C, $3C C, $7E C, $BD C, $24 C, $24 C, $66 C,

: SPRITE ( addr x y -- )
   { a x y }
   TS 0 DO  a I + C@  TS 0 DO  DUP 128 I RSHIFT AND IF  x I + y J + PSET  THEN  LOOP DROP  LOOP ;
\ The second picture every 4 pixels moved.
: STRIDE ( i a b -- addr )   ROT DUP EX @ SWAP EY @ + 4 / 1 AND IF NIP ELSE DROP THEN ;

: DRAW-ENTITIES ( -- )
   #E @ 1 ?DO
      I ESTATE @ TRAPPED = IF 160 40 40 ELSE 240 60 60 THEN COLOR
      I GUARD-A GUARD-B STRIDE  I EX @ I EY @ SPRITE
   LOOP
   120 230 255 COLOR  0 RUNNER-A RUNNER-B STRIDE  0 EX @ 0 EY @ SPRITE ;

\ ---- The line at the bottom: the game, and how fast it runs ------------------------

VARIABLE WORK-US  VARIABLE PERIOD-US  VARIABLE LAST-US
: NOW ( -- us )   UTIME DROP ;
: AVERAGE ( us addr -- )   DUP @ 7 * ROT + 8 / SWAP ! ;
: N>S ( n -- c-addr u )   S>D <# #S #> ;
: TENTHS ( us -- c-addr u )   100 / S>D <# # [CHAR] . HOLD #S #> ;

: STATUS ( -- )
   ROWS TS * 3 + { y }
   200 200 200 COLOR
   S" GOLD" 2 y TEXT     GOLD-LEFT @ N>S 22 y TEXT
   S" LIFE" 36 y TEXT    LIVES @ N>S 56 y TEXT
   S" LV" 70 y TEXT      LEVEL @ 1+ N>S 82 y TEXT
   S" SC" 96 y TEXT      SCORE @ N>S 108 y TEXT
   120 220 120 COLOR
   WORK-US @ TENTHS 144 y TEXT  S" MS" 168 y TEXT
   PERIOD-US @ ?DUP IF 1000000 SWAP / ELSE 0 THEN N>S 184 y TEXT  S" FPS" 200 y TEXT ;

: SHOW-MESSAGE ( -- )
   MESSAGE-TICKS @ PAUSED @ OR 0= IF EXIT THEN
   2 TEXT-SCALE
   MESSAGE-TICKS @ IF MESSAGE 2@ ELSE S" PAUSED" THEN
   2DUP TEXT-WIDTH  W OVER - 2/ { w x }
   0 0 0 COLOR  x 4 - 52 w 8 + 24 FILL-RECT
   255 230 80 COLOR  x 56 TEXT
   1 TEXT-SCALE ;

: DRAW ( -- )   CLS DRAW-MAP DRAW-ENTITIES STATUS SHOW-MESSAGE ;

: CLASSIC-RUNNER ( -- )
   W H GFX-INIT  W 4 * H 4 * WINDOW-SIZE  MAKE-SOUNDS
   NOW SEED !  NEW-GAME  FALSE DONE !  FALSE PAUSED !  0 MESSAGE-TICKS !
   NOW LAST-US !
   BEGIN
      NOW >R  TICK DRAW  NOW R> - WORK-US AVERAGE
      FRAME-MS FRAME
      NOW DUP LAST-US @ - PERIOD-US AVERAGE  LAST-US !
   DONE @ UNTIL
   CR ." Score: " SCORE @ . CR ;

CLASSIC-RUNNER
