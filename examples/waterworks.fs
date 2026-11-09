\ Waterworks: lay pipe on a blueprint before the water arrives, in a window.
\ The stages, the pictures, the sounds, and the rules are this file's own, made at
\ レモン's request.
\
\   sigma.exe examples/waterworks.fs      (in a window; Tk on Linux/macOS)
\
\ Mouse: the left button lays the next pipe on the square under it; on a pipe with no
\ water yet, it replaces that pipe (-50). The right button is the same as Space.
\ Keys: the arrows move the cursor, Z or Enter lays a pipe, Space lets the water go now
\ (+10 for each second left) and, once it runs, makes it run fast; P pauses, R starts
\ the stage again, Q or Esc ends the game.
\
\ Each stage asks for a number of pipes filled. When the water spills, the stage is
\ cleared if the count was reached, and costs a life if not. Each pipe filled is +50,
\ twice that past the count; water crossing a crossing twice +500; a pipe left dry when
\ the stage ends -25. On the blueprint: rocks are in the way; a tank is slow to fill;
\ a pump makes the next 5 squares run twice as fast (+200); a tunnel sends the water
\ out of the other tunnel, going the same way; a drain ends the stage (+1000), but it
\ must not come before the count.

REQUIRE-GRAPHICS  ALSO GRAPHICS

\ ---- Sound ------------------------------------------------------------------------

: AUDIO-LOADED? ( -- flag )   S" REQUIRE-AUDIO" ['] EVALUATE CATCH  DUP IF NIP NIP THEN  0= ;
[UNDEFINED] NO-SOUND [IF] AUDIO-LOADED? [ELSE] FALSE [THEN] CONSTANT HAS-SOUND

0 CONSTANT S-LAY   1 CONSTANT S-SWAP   2 CONSTANT S-GURGLE   3 CONSTANT S-SPILL
4 CONSTANT S-START  5 CONSTANT S-BONUS  6 CONSTANT S-NO   7 CONSTANT S-TICK

HAS-SOUND [IF]
ALSO AUDIO
11025 CONSTANT S-RATE
CREATE S-WAVE S-RATE ALLOT
VARIABLE HISS-SEED
: HISS-BYTE ( -- n )   HISS-SEED @ 1103515245 * 12345 + DUP HISS-SEED !  16 RSHIFT 255 AND 128 - ;
: SWISH { at n k amp | v -- }
   n 0 DO
      HISS-BYTE v - k * 256 / v + TO v
      v amp * n I - * n / 256 /  S-WAVE at + I + C!
   LOOP ;
: CHIME { at n half amp -- }
   n 0 DO
      I half / 1 AND IF amp ELSE amp NEGATE THEN  n I - * n /
      S-WAVE at + I + DUP C@ DUP 127 > IF 256 - THEN ROT +  -127 MAX 127 MIN  SWAP C!
   LOOP ;
\ A square wave whose half period grows by one every 16 samples: a falling blip.
: BLOOP { at n half amp -- }
   n 0 DO
      I half I 16 / + / 1 AND IF amp ELSE amp NEGATE THEN  n I - * n /
      S-WAVE at + I + C!
   LOOP ;
: BLANK-WAVE ( -- )   S-WAVE S-RATE ERASE ;
: KEEP-WAVE ( n k -- )   >R S-WAVE SWAP S-RATE R> SAMPLE ;
: EFFECT ( k -- )   SFX ;
: JINGLE ( c-addr u -- )   PLAY ;
: MAKE-SOUNDS ( -- )
   BLANK-WAVE  0 700 60 300 SWISH   0 500 40 50 CHIME        700 S-LAY KEEP-WAVE
   BLANK-WAVE  5 0 DO  I 500 * 460 160 280 SWISH  LOOP       2600 S-SWAP KEEP-WAVE
   BLANK-WAVE  0 900 9 70 BLOOP                               900 S-GURGLE KEEP-WAVE
   BLANK-WAVE  0 9000 150 260 SWISH                          9000 S-SPILL KEEP-WAVE
   BLANK-WAVE  0 5000 30 200 SWISH                           5000 S-START KEEP-WAVE
   BLANK-WAVE  0 1500 6 40 CHIME  300 1200 4 36 CHIME        1500 S-BONUS KEEP-WAVE
   BLANK-WAVE  0 1200 30 70 CHIME                            1200 S-NO KEEP-WAVE
   BLANK-WAVE  0 400 8 50 CHIME                               400 S-TICK KEEP-WAVE ;
PREVIOUS
[ELSE]
: EFFECT ( k -- )   DROP ;
: JINGLE ( c-addr u -- )   2DROP ;
: MAKE-SOUNDS ( -- ) ;
[THEN]

\ ---- Numbers and sizes -------------------------------------------------------------

800 CONSTANT W          \ the image
640 CONSTANT H
10 CONSTANT BW          \ the board, in squares
8 CONSTANT BH
64 CONSTANT CS          \ a square
144 CONSTANT BX0        \ the board's top left
56 CONSTANT BY0
12 CONSTANT STEPS       \ the pictures of water going through one square

VARIABLE SEED
: RND ( n -- 0..n-1 )   SEED @ 6364136223846793005 * 1442695040888963407 +  DUP SEED !  33 RSHIFT  SWAP MOD ;
: NOW ( -- us )   UTIME DROP ;

: MIX1 { a b t -- c }   a 255 t - *  b t *  +  127 +  255 / ;
: MIX-RGB { c1 c2 t -- c }
   c1 16 RSHIFT 255 AND  c2 16 RSHIFT 255 AND  t MIX1  16 LSHIFT
   c1 8 RSHIFT 255 AND   c2 8 RSHIFT 255 AND   t MIX1   8 LSHIFT OR
   c1 255 AND            c2 255 AND            t MIX1  OR ;

: ISQRT { n | v -- r }
   n 2 < IF n EXIT THEN
   n TO v  BEGIN  v n v / + 2/  DUP v < WHILE  TO v  REPEAT DROP  v ;

\ ---- Sprites made of spans ---------------------------------------------------------
\ A sprite: its number of spans, width, height, then a cell for each span with x1, x2,
\ and y (12 bits each) and the color.

: SPAN, { x1 x2 y c -- }   x1  x2 12 LSHIFT OR  y 24 LSHIFT OR  c 36 LSHIFT OR  , ;

: BAKE { bw bh xt | a x c x2 -- a }    \ xt ( x y -- rgb | -1 )
   ALIGN HERE TO a   0 ,  bw ,  bh ,
   bh 0 DO
      0 TO x
      BEGIN x bw < WHILE
         x I xt EXECUTE TO c
         x TO x2
         BEGIN  x2 1+ bw < IF  x2 1+ I xt EXECUTE c =  ELSE FALSE THEN  WHILE  x2 1+ TO x2  REPEAT
         c -1 <> IF  x x2 I c SPAN,  THEN
         x2 1+ TO x
      REPEAT
   LOOP
   HERE a - 1 CELLS / 3 -  a !   a ;

: SPR { x y a | e v -- }
   a 3 CELLS + DUP  a @ CELLS +  TO e
   BEGIN DUP e < WHILE
      DUP @ TO v
      v $FFF AND x +   v 12 RSHIFT $FFF AND x +   v 24 RSHIFT $FFF AND y +   v 36 RSHIFT  GFX-HLINE
      CELL+
   REPEAT DROP ;
: SPR-W ( a -- w )   CELL+ @ ;
: SPR-H ( a -- h )   2 CELLS + @ ;

\ ---- Painting tools ----------------------------------------------------------------

$FF00FE CONSTANT KEY-COLOR
$14304E CONSTANT C-BOARD   $1C3E60 CONSTANT C-GRID   $0C1E32 CONSTANT C-BAR
$FFF4D6 CONSTANT C-TEXT    $8FB4D0 CONSTANT C-LABEL

: CANVAS-PX ( x y -- rgb | -1 )   GFX-PGET  DUP KEY-COLOR = IF DROP -1 THEN ;

3 CONSTANT ZOOM
VARIABLE TURNS    \ quarter turns about the middle of a square, for the points below
: TURNED ( x y -- x' y' )
   TURNS @ 0 ?DO  SWAP 64 SWAP -  LOOP ;
: >CANVAS ( x y -- cx cy )   TURNED  ZOOM * SWAP ZOOM * SWAP ;
: INK ( rgb -- )   COLOR! ;

CREATE PTS 32 2* CELLS ALLOT   VARIABLE #PTS
: [P ( -- )   0 #PTS ! ;
: DV ( x y -- )   >CANVAS  PTS #PTS @ 2* CELLS + 2!  1 #PTS +! ;
: PT@ ( n -- x y )   2* CELLS PTS + 2@ ;
VARIABLE ROW-LO   VARIABLE ROW-HI
: ROW-HIT ( x -- )   DUP ROW-LO @ MIN ROW-LO !  ROW-HI @ MAX ROW-HI ! ;
: EDGE { y x0 y0 x1 y1 -- }
   y y0 y1 MIN < IF EXIT THEN   y y0 y1 MAX > IF EXIT THEN
   y0 y1 = IF  x0 ROW-HIT  x1 ROW-HIT  EXIT THEN
   y y0 - x1 x0 - *  y1 y0 - /  x0 +  ROW-HIT ;
: P] { | top bot -- }
   99999 TO top  -99999 TO bot
   #PTS @ 0 DO  I PT@ NIP DUP top MIN TO top  bot MAX TO bot  LOOP
   bot 1+ top DO
      99999 ROW-LO !  -99999 ROW-HI !
      #PTS @ 0 DO  J  I PT@  I 1+ #PTS @ MOD PT@  EDGE  LOOP
      ROW-HI @ ROW-LO @ >= IF  ROW-LO @ ROW-HI @ I COLOR@ GFX-HLINE  THEN
   LOOP ;
: BOX ( x1 y1 x2 y2 -- )   { x1 y1 x2 y2 }  [P x1 y1 DV x2 y1 DV x2 y2 DV x1 y2 DV P] ;
: DISC ( x y r -- )   >R >CANVAS R> ZOOM * FILL-CIRCLE ;

\ Three by three samples to a pixel; a pixel whose middle is key is a hole.
: ART-PX { x y | r g b n v -- rgb | -1 }
   x ZOOM * 1+  y ZOOM * 1+  GFX-PGET KEY-COLOR = IF -1 EXIT THEN
   ZOOM 0 DO ZOOM 0 DO
      x ZOOM * I +  y ZOOM * J +  GFX-PGET TO v
      v KEY-COLOR <> IF
         v 16 RSHIFT 255 AND r + TO r
         v 8 RSHIFT 255 AND g + TO g
         v 255 AND b + TO b
         n 1+ TO n
      THEN
   LOOP LOOP
   r n / 16 LSHIFT  g n / 8 LSHIFT OR  b n / OR ;
: ART-BEGIN ( -- )   KEY-COLOR GFX-CLS  0 TURNS ! ;
: ART-DONE ( -- spr )   0 TURNS !  CS CS ['] ART-PX BAKE ;

\ ---- Pipes -------------------------------------------------------------------------
\ Kinds of square: 0 empty; 1 east-west, 2 north-south; corners 3 NE, 4 ES, 5 SW, 6 WN;
\ 7 a crossing; 8, 9 a tank east-west and north-south; 10, 11 a pump likewise; 12 rock;
\ 13 the source; 14 a drain; 15 a tunnel. Directions: 0 N, 1 E, 2 S, 3 W.

CREATE OPENINGS  0 C, 10 C, 5 C, 3 C, 6 C, 12 C, 9 C, 15 C, 10 C, 5 C, 10 C, 5 C, 0 C, 0 C, 15 C, 15 C,
ALIGN
: MASK-OF ( t -- mask )   OPENINGS + C@ ;
: BASE-PIPE ( t -- t' )   DUP 7 > IF  1 AND 0= IF 1 ELSE 2 THEN  THEN ;

VARIABLE PK   VARIABLE C2X   VARIABLE C2Y     \ straight 0 or 1, corner 2; the corner's center, doubled
: SET-PATH ( t -- )
   CASE
      1 OF 0 PK ! ENDOF
      2 OF 1 PK ! ENDOF
      3 OF 2 PK ! 128 C2X !   0 C2Y ! ENDOF
      4 OF 2 PK ! 128 C2X ! 128 C2Y ! ENDOF
      5 OF 2 PK !   0 C2X ! 128 C2Y ! ENDOF
      6 OF 2 PK !   0 C2X !   0 C2Y ! ENDOF
   ENDCASE ;
: X2OF ( x -- n )   2* 1+ C2X @ - ABS ;
: Y2OF ( y -- n )   2* 1+ C2Y @ - ABS ;
: ACROSS2 { x y -- a2 }     \ twice the distance from the middle line of the pipe
   PK @ 0= IF  y 2* 1+ 64 - ABS EXIT THEN
   PK @ 1 = IF  x 2* 1+ 64 - ABS EXIT THEN
   x X2OF DUP *  y Y2OF DUP * +  ISQRT 64 - ABS ;
: NEAR-OPENING? { x y -- flag }
   PK @ 0= IF  x 4 <  x 59 > OR  EXIT THEN
   PK @ 1 = IF  y 4 <  y 59 > OR  EXIT THEN
   x X2OF 8 <  y Y2OF 8 < OR ;
: STEP-OF { x y e | a b -- s }     \ how far along the pipe, for water entering by side e
   PK @ 2 < IF
      PK @ IF y ELSE x THEN  e 1 = e 2 = OR IF 63 SWAP - THEN  STEPS * 64 /  EXIT
   THEN
   x X2OF TO a   y Y2OF TO b
   e 1 AND IF a ELSE b THEN  STEPS *  a b + 1 MAX /  STEPS 1- MIN ;

$16222F CONSTANT C-CHANNEL
: RIM-COLOR ( a2 -- rgb )     \ a2 from 21 to 32, a round copper edge
   DUP 26 <= IF  21 - 255 * 5 /  $7E4A24 SWAP $E8A468 SWAP MIX-RGB
   ELSE  26 - 255 * 6 /  $E8A468 SWAP $703A18 SWAP MIX-RGB  THEN ;

: PIPE-PX { x y | a -- rgb | -1 }
   x y ACROSS2 TO a
   a 38 > IF -1 EXIT THEN
   x y NEAR-OPENING? IF
      a 20 <= IF C-CHANNEL EXIT THEN
      a 36 <= IF  $D8B060 $9C7830  a 20 - 255 * 16 /  MIX-RGB  EXIT THEN
      -1 EXIT
   THEN
   a 20 <= IF C-CHANNEL EXIT THEN
   a 32 <= IF a RIM-COLOR EXIT THEN
   a 34 <= IF  $703A18 C-BOARD 140 MIX-RGB  EXIT THEN
   -1 ;

CREATE WMAP CS CS * ALLOT
VARIABLE WSTEP
CREATE WATER-INK  $1A6AB0 , $2A93D8 , $4FC3F0 , $9FE8FF ,

: WATER-BAND ( a2 -- band )     \ 3 at the middle of the channel
   DUP 5 < IF DROP 3 EXIT THEN   DUP 11 < IF DROP 2 EXIT THEN   16 < IF 1 ELSE 0 THEN ;
: FILL-WMAP { e -- }
   CS 0 DO CS 0 DO
      I J ACROSS2 { a }
      a 20 > IF 255 ELSE  a WATER-BAND 16 *  I J e STEP-OF +  THEN
      WMAP J CS * I + + C!
   LOOP LOOP ;
: WATER-PX ( x y -- rgb | -1 )
   CS * + WMAP + C@  DUP 255 = IF DROP -1 EXIT THEN
   DUP 15 AND WSTEP @ > IF DROP -1 EXIT THEN
   4 RSHIFT CELLS WATER-INK + @ ;

CREATE PIPE-ART 7 CELLS ALLOT
CREATE WATER-ART 12 STEPS * CELLS ALLOT    \ for each of 12 ways through a pipe
CREATE HEADS 12 STEPS * 2* ALLOT
: LOW-OPENING ( t -- e )   MASK-OF  0 BEGIN  OVER OVER RSHIFT 1 AND 0= WHILE 1+ REPEAT NIP ;
: HIGH-OPENING ( t -- e )  MASK-OF  3 BEGIN  OVER OVER RSHIFT 1 AND 0= WHILE 1- REPEAT NIP ;

: HEAD-XY { s e | hx hy a b len -- x y }
   PK @ 2 < IF
      s 2* 1+ CS * STEPS 2* /  TO a
      e 1 = e 2 = OR IF CS a - TO a THEN
      PK @ IF  32 a  ELSE  a 32  THEN  EXIT
   THEN
   s 2* 1+ TO a   STEPS 2* a - TO b
   a a * b b * + ISQRT TO len
   32 a * len / TO hx   32 b * len / TO hy
   e 1 AND 0= IF  hx hy TO hx TO hy  THEN
   C2X @ IF  64 hx -  ELSE  hx  THEN
   C2Y @ IF  64 hy -  ELSE  hy  THEN ;

: MAKE-PATH { t e idx -- }
   e FILL-WMAP
   STEPS 0 DO
      I WSTEP !
      CS CS ['] WATER-PX BAKE   idx STEPS * I + CELLS WATER-ART + !
      I e HEAD-XY   HEADS idx STEPS * I + 2* + 1+ C!   HEADS idx STEPS * I + 2* + C!
   LOOP ;
: MAKE-PIPES ( -- )
   7 1 DO
      I SET-PATH
      CS CS ['] PIPE-PX BAKE  I CELLS PIPE-ART + !
      I  I LOW-OPENING   I 1- 2*     MAKE-PATH
      I  I HIGH-OPENING  I 1- 2* 1+  MAKE-PATH
   LOOP ;

: PATH-OF ( t e -- idx )   OVER LOW-OPENING = IF 1- 2* ELSE 1- 2* 1+ THEN ;
: WATER-SPR ( path step -- a )   SWAP STEPS * + CELLS WATER-ART + @ ;
: FULL-WATER ( t -- a )   1- 2*  STEPS 1- WATER-SPR ;

\ ---- The fixed things --------------------------------------------------------------

CREATE SOURCE-ART 8 CELLS ALLOT     \ four ways, dry and flowing
VARIABLE ROCK-ART   VARIABLE DRAIN-ART   VARIABLE TUNNEL-ART
CREATE TANK-ART 2 CELLS ALLOT   CREATE PUMP-ART 2 CELLS ALLOT

: PAINT-ROCK ( -- )
   $4A5260 INK  [P 8 26 DV 22 8 DV 44 7 DV 58 24 DV 56 46 DV 40 58 DV 18 56 DV 6 42 DV P]
   $6A7484 INK  [P 16 26 DV 26 13 DV 42 12 DV 50 26 DV 34 34 DV 18 34 DV P]
   $8A94A4 INK  [P 24 22 DV 30 16 DV 40 16 DV 42 23 DV 32 27 DV P]
   $343A46 INK  [P 18 38 DV 34 38 DV 42 50 DV 26 52 DV P] ;

: PAINT-SOURCE { flowing -- }      \ a stub going east, turned by TURNS, and a valve wheel
   $703A18 INK  32 14 64 50 BOX
   $E8A468 INK  32 18 64 46 BOX
   flowing IF $2A93D8 ELSE C-CHANNEL THEN INK  32 22 64 42 BOX
   $D8B060 INK  58 14 62 22 BOX  58 42 62 50 BOX
   $8892A4 INK  32 32 24 DISC
   $C03030 INK  32 32 20 DISC
   $E85050 INK  32 32 17 DISC
   $C03030 INK  32 32 12 DISC
   $D0D8E0 INK  29 14 35 50 BOX  14 29 50 35 BOX
   $FFFFFF INK  [P 24 25 DV 42 32 DV 24 39 DV P]
   $303840 INK  32 32 3 DISC ;

: PAINT-DRAIN ( -- )
   $8892A4 INK  32 32 28 DISC
   $2A3440 INK  32 32 24 DISC
   $101820 INK  32 32 20 DISC
   $8892A4 INK  10 26 54 30 BOX  10 34 54 38 BOX  26 10 30 54 BOX  34 10 38 54 BOX ;

: PAINT-TUNNEL ( -- )
   $6A3AA0 INK  32 32 28 DISC
   $B070E0 INK  32 32 24 DISC
   $3A1A60 INK  32 32 20 DISC
   $100820 INK  32 32 12 DISC
   $D0A8FF INK  [P 32 12 DV 40 18 DV 34 20 DV P]  [P 52 32 DV 46 40 DV 44 34 DV P]
                [P 32 52 DV 24 46 DV 30 44 DV P]  [P 12 32 DV 18 24 DV 20 30 DV P] ;

: PAINT-TANK ( -- )
   $8892A4 INK  11 11 53 53 BOX
   $C8D0D8 INK  13 13 51 51 BOX
   $101C2C INK  17 17 47 47 BOX ;

: PAINT-PUMP ( -- )
   $802020 INK  12 12 52 52 BOX
   $D04040 INK  14 14 50 50 BOX
   $601818 INK  32 32 16 DISC
   $F0C030 INK  [P 32 18 DV 38 30 DV 26 30 DV P]  [P 46 32 DV 34 38 DV 34 26 DV P]
                [P 32 46 DV 26 34 DV 38 34 DV P]  [P 18 32 DV 30 26 DV 30 38 DV P]
   $303840 INK  32 32 3 DISC ;

: MAKE-FIXED ( -- )
   4 0 DO
      ART-BEGIN  5 I - 4 MOD TURNS !  FALSE PAINT-SOURCE  ART-DONE  SOURCE-ART I CELLS + !
      ART-BEGIN  5 I - 4 MOD TURNS !  TRUE PAINT-SOURCE   ART-DONE  SOURCE-ART I 4 + CELLS + !
   LOOP
   ART-BEGIN PAINT-ROCK    ART-DONE ROCK-ART !
   ART-BEGIN PAINT-DRAIN   ART-DONE DRAIN-ART !
   ART-BEGIN PAINT-TUNNEL  ART-DONE TUNNEL-ART !
   ART-BEGIN PAINT-TANK    ART-DONE TANK-ART !
   ART-BEGIN PAINT-PUMP    ART-DONE PUMP-ART ! ;

\ ---- Text and the table ------------------------------------------------------------

: USE-FONT ( height -- )
   >R S" Segoe UI Semibold" R@ ['] SYSTEM-FONT CATCH
   IF  2DROP DROP  BUILTIN-FONT  R> 8 / 1 MAX TEXT-SCALE
   ELSE  R> DROP  1 TEXT-SCALE  THEN ;
: TEXT-SPRITE { a u fg bg | bw bh -- spr }
   a u TEXT-WIDTH TO bw   TEXT-HEIGHT TO bh
   bg GFX-CLS  fg INK  a u 0 0 TEXT
   bw bh ['] CANVAS-PX BAKE ;
: LABEL ( a u -- spr )   C-LABEL C-BAR TEXT-SPRITE ;
: BRIGHT ( a u -- spr )  C-TEXT C-BAR TEXT-SPRITE ;
: DIGIT$ ( n -- c-addr 1 )   S" 0123456789" DROP + 1 ;

VARIABLE TABLE-ART
CREATE DIGITS 10 CELLS ALLOT    VARIABLE DIGIT-W
VARIABLE SLASH-SPR  VARIABLE L-STAGE  VARIABLE L-SCORE  VARIABLE L-NEXT  VARIABLE L-PIPES
VARIABLE L-LIVES    VARIABLE L-WATER  VARIABLE L-FLOW   VARIABLE L-PAUSE
VARIABLE L-TITLE    VARIABLE L-START  VARIABLE L-HELP1  VARIABLE L-HELP2  VARIABLE L-BEST
VARIABLE L-HELP-PLAY
VARIABLE R-CLEAR    VARIABLE R-LEAK   VARIABLE R-OVER   VARIABLE R-DONE   VARIABLE R-GO
VARIABLE R-AGAIN    VARIABLE R-MENU
CREATE STAGE-NAMES 8 CELLS ALLOT

: TABLE-PX { x y | u v -- rgb }
   x BX0 -  TO u   y BY0 - TO v
   u 0 CS BW * WITHIN  v 0 CS BH * WITHIN AND 0= IF C-BAR EXIT THEN
   u CS MOD 0=  v CS MOD 0= OR IF C-GRID ELSE C-BOARD THEN ;

: STAGE-NAME$ ( n -- a u )
   CASE
      0 OF S" First Flow" ENDOF
      1 OF S" Stony Ground" ENDOF
      2 OF S" Reservoir" ENDOF
      3 OF S" Down the Drain" ENDOF
      4 OF S" Under Pressure" ENDOF
      5 OF S" The Underpass" ENDOF
      6 OF S" The Maze" ENDOF
      7 OF S" Full Bore" ENDOF
      S" " ROT
   ENDCASE ;

: MAKE-TEXT ( -- )
   W H ['] TABLE-PX BAKE TABLE-ART !
   15 USE-FONT
   S" STAGE" LABEL L-STAGE !     S" SCORE" LABEL L-SCORE !     S" LIVES" LABEL L-LIVES !
   S" NEXT" LABEL L-NEXT !       S" PIPES" LABEL L-PIPES !
   S" WATER IN" LABEL L-WATER !  S" WATER RUNNING" LABEL L-FLOW !
   S" 0" TEXT-WIDTH DIGIT-W !
   10 0 DO  I DIGIT$ BRIGHT  DIGITS I CELLS + !  LOOP
   S" /" BRIGHT SLASH-SPR !
   8 0 DO  I STAGE-NAME$ BRIGHT  STAGE-NAMES I CELLS + !  LOOP
   S" Paused" BRIGHT L-PAUSE !
   13 USE-FONT
   S" Left button: lay a pipe    Space: let the water go    P pause    R restart    Q quit" LABEL L-HELP-PLAY !
   15 USE-FONT
   S" Lay the pipes ahead of the water, and do not let it spill too soon." BRIGHT L-HELP1 !
   S" Mouse or arrows and Z to lay, Space to let the water go, Q to quit" LABEL L-HELP2 !
   S" Click to start" BRIGHT L-START !
   S" BEST" LABEL L-BEST !
   S" Click to go on" LABEL R-GO !
   S" Click to try again" LABEL R-AGAIN !
   S" Click for the title" LABEL R-MENU !
   64 USE-FONT
   S" Waterworks" $6FD0FF C-BAR TEXT-SPRITE L-TITLE !
   40 USE-FONT
   S" Stage clear" C-TEXT C-BAR TEXT-SPRITE R-CLEAR !
   S" It spilled" $FF9070 C-BAR TEXT-SPRITE R-LEAK !
   S" Game over" $FF9070 C-BAR TEXT-SPRITE R-OVER !
   S" All stages clear!" $F0C030 C-BAR TEXT-SPRITE R-DONE ! ;

: BAKE-ALL ( -- )
   512 256 GFX-INIT
   MAKE-PIPES  MAKE-FIXED  MAKE-TEXT ;

\ ---- The stages --------------------------------------------------------------------
\ > < ^ v the source and the way it runs, # rock, D drain, = and H a tank, p and P a
\ pump, @ a tunnel (two to a stage).

8 CONSTANT #STAGES
CREATE MAPS BW BH * #STAGES * ALLOT
VARIABLE MAP-AT   MAPS MAP-AT !
: ROW ( a u -- )   DROP MAP-AT @ BW MOVE  BW MAP-AT +! ;
CREATE STAGE-INFO  \ pipes asked for, frames before the water, frames for each square
   8 , 1260 , 146 ,     \ RATE takes 1024 / frames as a whole number: 7, 8, .. 14 here
  10 , 1200 , 128 ,
  12 , 1140 , 113 ,
  12 , 1140 , 102 ,
  14 , 1080 ,  93 ,
  14 , 1080 ,  85 ,
  16 , 1080 ,  78 ,
  20 , 1020 ,  73 ,

S" .........." ROW
S" .........." ROW
S" .........." ROW
S" ..>......." ROW
S" .........." ROW
S" .........." ROW
S" .........." ROW
S" .........." ROW

S" .........." ROW
S" ..#....#.." ROW
S" .........." ROW
S" ....##...." ROW
S" .>........" ROW
S" .......#.." ROW
S" ..#......." ROW
S" .........." ROW

S" .........." ROW
S" .#......#." ROW
S" ...=......" ROW
S" .....#...." ROW
S" ..^......." ROW
S" ......H..." ROW
S" .#......#." ROW
S" .........." ROW

S" .........." ROW
S" ..#...#..." ROW
S" ......#.D." ROW
S" .>....#..." ROW
S" ......#..." ROW
S" ..#......." ROW
S" ....#....." ROW
S" .........." ROW

S" .........." ROW
S" .#..p...#." ROW
S" .........." ROW
S" ...#..#..." ROW
S" .v.....P.." ROW
S" ...#..#..." ROW
S" .#......#." ROW
S" .........." ROW

S" .....#...." ROW
S" .....#...." ROW
S" ..@..#.@.." ROW
S" .....#...." ROW
S" .>...#...." ROW
S" .....#...." ROW
S" .....#...." ROW
S" .....#...." ROW

S" ...#......" ROW
S" .#.#.####." ROW
S" .#.#....#." ROW
S" .#.####.#." ROW
S" .#......#." ROW
S" .######.#." ROW
S" ^.......#." ROW
S" ........#D" ROW

S" #........#" ROW
S" ..p..=...." ROW
S" .#...#..@." ROW
S" .......#.." ROW
S" ...<...#.." ROW
S" .@.#......" ROW
S" ....H..#.D" ROW
S" #........#" ROW

\ ---- The game ----------------------------------------------------------------------

CREATE BOARD BW BH * ALLOT     CREATE WETS BW BH * ALLOT
: >CELL ( x y -- n )   BW * + ;
: IN-BOARD? ( x y -- flag )   0 BH WITHIN  SWAP 0 BW WITHIN AND ;
: KIND@ ( x y -- t )   >CELL BOARD + C@ ;
: KIND! ( t x y -- )   >CELL BOARD + C! ;
: WET@ ( x y -- bits )   >CELL WETS + C@ ;
: WET! ( bits x y -- )   >CELL WETS + DUP C@ ROT OR SWAP C! ;

CREATE DX-T  0 , 1 , 0 , -1 ,
CREATE DY-T  -1 , 0 , 1 , 0 ,
: DIR-X ( d -- n )   CELLS DX-T + @ ;
: DIR-Y ( d -- n )   CELLS DY-T + @ ;
: OPPOSITE ( d -- d' )   2 + 3 AND ;

0 CONSTANT M-TITLE  1 CONSTANT M-PLAY  2 CONSTANT M-END  3 CONSTANT M-RESULT
VARIABLE GMODE   VARIABLE DONE   VARIABLE PAUSED   VARIABLE CLOCK
VARIABLE STG     VARIABLE SCORE  VARIABLE LIVES    VARIABLE BEST
VARIABLE START-SCORE
VARIABLE QUOTA   VARIABLE FLOW   VARIABLE COUNTDOWN  VARIABLE FILLED
VARIABLE SRC-X   VARIABLE SRC-Y  VARIABLE SRC-D
VARIABLE TUN1    VARIABLE TUN2
VARIABLE FLOWING VARIABLE W-X    VARIABLE W-Y    VARIABLE W-E   VARIABLE W-EX   VARIABLE W-P
VARIABLE FAST    VARIABLE PUMPED VARIABLE END-T  VARIABLE END-DRAIN
VARIABLE RESULT  \ 0 cleared, 1 spilled, 2 game over, 3 all clear

5 CONSTANT #QUEUE
CREATE QUEUE #QUEUE CELLS ALLOT
CREATE BAG  1 C, 1 C, 1 C, 2 C, 2 C, 2 C, 3 C, 3 C, 4 C, 4 C, 5 C, 5 C, 6 C, 6 C, 7 C,
ALIGN
: DRAW-PIECE-KIND ( -- t )   15 RND BAG + C@ ;
: FILL-QUEUE ( -- )   #QUEUE 0 DO  DRAW-PIECE-KIND QUEUE I CELLS + !  LOOP ;
: NEXT-KIND ( -- t )   QUEUE @ ;
: SHIFT-QUEUE ( -- )
   QUEUE CELL+ QUEUE #QUEUE 1- CELLS MOVE
   DRAW-PIECE-KIND  QUEUE #QUEUE 1- CELLS + ! ;

\ The water's way, for the bubbles.
100 CONSTANT MAX-TRAIL
CREATE TRAIL MAX-TRAIL 3 * CELLS ALLOT    VARIABLE #TRAIL
: TRAIL! { x y path -- }
   #TRAIL @ MAX-TRAIL >= IF EXIT THEN
   x  #TRAIL @ 3 * CELLS TRAIL + !   y #TRAIL @ 3 * 1+ CELLS TRAIL + !
   path #TRAIL @ 3 * 2 + CELLS TRAIL + !   1 #TRAIL +! ;

\ Drops and dust.
60 CONSTANT #SPARKS
CREATE SPARKS #SPARKS 6 * CELLS ALLOT     \ x y dx dy life color; positions times 16
: SPARK[] ( n -- a )   6 * CELLS SPARKS + ;
VARIABLE NEXT-SPARK
: SPARK { x y dx dy life c | a -- }
   NEXT-SPARK @ SPARK[] TO a
   x 16 * a !  y 16 * a CELL+ !  dx a 2 CELLS + !  dy a 3 CELLS + !  life a 4 CELLS + !  c a 5 CELLS + !
   NEXT-SPARK @ 1+ #SPARKS MOD NEXT-SPARK ! ;
: BURST { x y n spread c -- }
   n 0 DO
      x y  spread 2* 1+ RND spread -  spread 2* 1+ RND spread -  20 30 RND +  c SPARK
   LOOP ;
: STEP-SPARKS ( -- )
   #SPARKS 0 DO
      I SPARK[] { a }
      a 4 CELLS + @ 0> IF
         a 2 CELLS + @ a +!   a 3 CELLS + @ a CELL+ +!
         1 a 3 CELLS + +!   -1 a 4 CELLS + +!
      THEN
   LOOP ;
: DRAW-SPARKS ( -- )
   #SPARKS 0 DO
      I SPARK[] { a }
      a 4 CELLS + @ 0> IF
         a @ 16 /  DUP 2 +  a CELL+ @ 16 /  a 5 CELLS + @ GFX-HLINE
         a @ 16 /  DUP 2 +  a CELL+ @ 16 / 1+  a 5 CELLS + @ GFX-HLINE
      THEN
   LOOP ;

: LOAD-STAGE { n | m c t -- }
   BOARD BW BH * ERASE   WETS BW BH * ERASE
   n BW BH * * MAPS + TO m
   -1 TUN1 !  -1 TUN2 !
   BH 0 DO BW 0 DO
      m J BW * I + + C@ TO c
      0 TO t
      c [CHAR] # = IF 12 TO t THEN
      c [CHAR] D = IF 14 TO t THEN
      c [CHAR] = = IF 8 TO t THEN
      c [CHAR] H = IF 9 TO t THEN
      c [CHAR] p = IF 10 TO t THEN
      c [CHAR] P = IF 11 TO t THEN
      c [CHAR] @ = IF  15 TO t  TUN1 @ 0< IF  I J >CELL TUN1 !  ELSE  I J >CELL TUN2 !  THEN  THEN
      c [CHAR] ^ = IF  13 TO t  0 SRC-D !  THEN
      c [CHAR] > = IF  13 TO t  1 SRC-D !  THEN
      c [CHAR] v = IF  13 TO t  2 SRC-D !  THEN
      c [CHAR] < = IF  13 TO t  3 SRC-D !  THEN
      t 13 = IF  I SRC-X !  J SRC-Y !  THEN
      t I J KIND!
   LOOP LOOP
   n 3 * CELLS STAGE-INFO +  DUP @ QUOTA !  CELL+ DUP @ COUNTDOWN !  CELL+ @ FLOW !
   n STG !   0 FILLED !   0 #TRAIL !
   FALSE FLOWING !  FALSE FAST !  0 PUMPED !  FALSE END-DRAIN !  FALSE PAUSED !
   FILL-QUEUE
   SCORE @ START-SCORE !
   M-PLAY GMODE ! ;

: +SCORE ( n -- )   SCORE @ + 0 MAX SCORE ! ;

\ ---- The water ---------------------------------------------------------------------

: EXIT-OF ( t entry -- d )
   OVER 3 7 WITHIN IF  1 SWAP LSHIFT  SWAP MASK-OF XOR  0 BEGIN OVER OVER RSHIFT 1 AND 0= WHILE 1+ REPEAT NIP  EXIT THEN
   NIP OPPOSITE ;
: AXIS ( entry -- bit )   1 AND IF 1 ELSE 2 THEN ;

: CELL-CENTER ( x y -- px py )   CS * BY0 + 32 + SWAP  CS * BX0 + 32 + SWAP ;

: SPILL ( -- )
   M-END GMODE !  80 END-T !  FALSE FLOWING !
   W-X @ W-Y @ CELL-CENTER
   W-EX @ DIR-Y 32 * + SWAP  W-EX @ DIR-X 32 * + SWAP
   50 30 $6FD0FF BURST
   S-SPILL EFFECT ;
: REACH-DRAIN ( -- )
   M-END GMODE !  50 END-T !  FALSE FLOWING !  TRUE END-DRAIN !
   S-BONUS EFFECT ;

: COUNT-PIPE ( -- )
   1 FILLED +!
   FILLED @ QUOTA @ > IF 100 ELSE 50 THEN +SCORE
   S-GURGLE EFFECT ;

: PARTNER ( cell -- cell' )   DUP TUN1 @ = IF DROP TUN2 @ ELSE DROP TUN1 @ THEN ;

\ The water leaves its square by side W-EX and goes into the next one.
: NEXT-SQUARE { | nx ny t e -- }
   W-X @ W-EX @ DIR-X + TO nx   W-Y @ W-EX @ DIR-Y + TO ny
   nx ny IN-BOARD? 0= IF SPILL EXIT THEN
   nx ny KIND@ TO t
   W-EX @ OPPOSITE TO e
   t MASK-OF 1 e LSHIFT AND 0= IF SPILL EXIT THEN
   t 7 = IF
      nx ny WET@ e AXIS AND IF SPILL EXIT THEN
      nx ny WET@ IF  500 +SCORE S-BONUS EFFECT  THEN
   ELSE
      nx ny WET@ IF SPILL EXIT THEN
   THEN
   t 14 = IF
      nx W-X !  ny W-Y !
      REACH-DRAIN EXIT
   THEN
   t 7 = IF e AXIS ELSE 1 THEN nx ny WET!
   nx W-X !  ny W-Y !  e W-E !
   t e EXIT-OF W-EX !
   0 W-P !
   COUNT-PIPE
   t 15 = IF
      nx ny >CELL PARTNER  DUP BW MOD W-X !  BW / W-Y !
      1 W-X @ W-Y @ WET!
      512 W-P !
      EXIT
   THEN
   t 10 = t 11 = OR IF  6 PUMPED !  200 +SCORE  S-BONUS EFFECT  THEN
   PUMPED @ IF -1 PUMPED +! THEN
   nx ny  t 7 = t 7 > OR IF  t 8 < IF  e 1 AND IF 1 ELSE 2 THEN  ELSE t BASE-PIPE THEN  ELSE t THEN  e PATH-OF  TRAIL! ;

: LET-WATER-GO ( -- )
   TRUE FLOWING !  0 COUNTDOWN !
   SRC-X @ W-X !  SRC-Y @ W-Y !  SRC-D @ W-EX !  SRC-D @ OPPOSITE W-E !
   512 W-P !
   S-START EFFECT ;

: RATE ( -- n )
   1024 FLOW @ /
   PUMPED @ IF 2* THEN
   FAST @ IF 5 * THEN
   W-X @ W-Y @ KIND@ DUP 8 = SWAP 9 = OR IF 3 / 1 MAX THEN ;

: STEP-WATER ( -- )
   RATE W-P +!
   W-P @ 1024 >= IF NEXT-SQUARE THEN ;

\ ---- The end of a stage -------------------------------------------------------------

: DRY-PIPES ( -- n )
   0  BW BH * 0 DO
      BOARD I + C@ 1 8 WITHIN  WETS I + C@ 0= AND IF 1+ THEN
   LOOP ;

: GAME-LOST ( -- )
   SCORE @ BEST @ MAX BEST !
   2 RESULT !  M-RESULT GMODE !
   S" T120 L8 O4 EDC<B2" JINGLE ;

: STAGE-FAILED ( -- )
   -1 LIVES +!
   LIVES @ 0> IF  1 RESULT !  M-RESULT GMODE !  S" T140 L8 O4 ED<B4" JINGLE
   ELSE GAME-LOST THEN ;

: STAGE-CLEARED ( -- )
   DRY-PIPES -25 * +SCORE
   END-DRAIN @ IF 1000 +SCORE THEN
   STG @ 1+ #STAGES = IF
      SCORE @ BEST @ MAX BEST !
      3 RESULT !  M-RESULT GMODE !
      S" T170 L16 O5 CEG>CEG>C4<G8>C2" JINGLE
   ELSE
      0 RESULT !  M-RESULT GMODE !
      S" T170 L16 O5 CEG>C4" JINGLE
   THEN ;

: END-OF-WATER ( -- )
   FILLED @ QUOTA @ >= IF STAGE-CLEARED ELSE STAGE-FAILED THEN ;

: TO-TITLE ( -- )   M-TITLE GMODE ! ;
: NEW-RUN ( -- )   0 SCORE !  3 LIVES !  0 LOAD-STAGE ;

: ACCEPT-RESULT ( -- )
   RESULT @ CASE
      0 OF STG @ 1+ LOAD-STAGE ENDOF
      1 OF START-SCORE @ SCORE !  STG @ LOAD-STAGE ENDOF
      2 OF TO-TITLE ENDOF
      3 OF TO-TITLE ENDOF
   ENDCASE ;

\ ---- Laying pipe -------------------------------------------------------------------

VARIABLE CUR-X   VARIABLE CUR-Y   VARIABLE CUR-ON

: CAN-LAY? { x y -- flag }
   x y IN-BOARD? 0= IF FALSE EXIT THEN
   x y KIND@ 8 < IF  x y WET@ 0=  ELSE FALSE THEN ;

: LAY-AT { x y | old px py -- }
   GMODE @ M-PLAY <> PAUSED @ OR IF EXIT THEN
   x y CAN-LAY? 0= IF  S-NO EFFECT EXIT  THEN
   x y KIND@ TO old
   x y CELL-CENTER TO py TO px
   old IF
      -50 +SCORE
      px py 14 14 $C88850 BURST
      S-SWAP EFFECT
   ELSE
      S-LAY EFFECT
   THEN
   NEXT-KIND x y KIND!
   SHIFT-QUEUE ;

: FLOW-KEY ( -- )
   GMODE @ M-PLAY <> PAUSED @ OR IF EXIT THEN
   FLOWING @ IF  TRUE FAST !  EXIT  THEN
   COUNTDOWN @ 60 / 10 * +SCORE
   LET-WATER-GO ;

: RESTART ( -- )
   GMODE @ M-PLAY = GMODE @ M-END = OR IF
      START-SCORE @ SCORE !  STG @ LOAD-STAGE
   THEN ;

: CLICK-MODE ( -- )    \ a click or Enter away from the board
   GMODE @ CASE
      M-TITLE OF NEW-RUN ENDOF
      M-RESULT OF ACCEPT-RESULT ENDOF
   ENDCASE ;

\ ---- Input -------------------------------------------------------------------------

VARIABLE OLD-B   VARIABLE OLD-MX   VARIABLE OLD-MY

: >SQUARE ( mx my -- x y )   BY0 - DUP 0< IF DROP -1 ELSE CS / THEN  SWAP
                             BX0 - DUP 0< IF DROP -1 ELSE CS / THEN  SWAP ;

: READ-MOUSE { | mx my b sx sy -- }
   MOUSE TO b TO my TO mx
   mx OLD-MX @ <>  my OLD-MY @ <> OR  mx 0>= AND IF
      mx OLD-MX !  my OLD-MY !
      mx my >SQUARE TO sy TO sx
      sx sy IN-BOARD? DUP CUR-ON !  IF  sx CUR-X !  sy CUR-Y !  THEN
   THEN
   b 1 AND  OLD-B @ 1 AND 0= AND IF
      GMODE @ M-PLAY = IF
         CUR-ON @ IF  CUR-X @ CUR-Y @ LAY-AT  THEN
      ELSE  CLICK-MODE  THEN
   THEN
   b 2 AND  OLD-B @ 2 AND 0= AND IF  FLOW-KEY  THEN
   b OLD-B ! ;

: MOVE-CURSOR { dx dy -- }
   TRUE CUR-ON !
   CUR-X @ dx + 0 MAX BW 1- MIN CUR-X !
   CUR-Y @ dy + 0 MAX BH 1- MIN CUR-Y ! ;

: KEY! ( key -- )
   DUP [CHAR] A [CHAR] Z 1+ WITHIN IF 32 + THEN
   CASE
      [CHAR] q OF  TRUE DONE !  ENDOF
      27       OF  TRUE DONE !  ENDOF
      K-LEFT   OF  -1 0 MOVE-CURSOR  ENDOF
      K-RIGHT  OF   1 0 MOVE-CURSOR  ENDOF
      K-UP     OF  0 -1 MOVE-CURSOR  ENDOF
      K-DOWN   OF  0  1 MOVE-CURSOR  ENDOF
      [CHAR] z OF  GMODE @ M-PLAY = IF CUR-X @ CUR-Y @ LAY-AT ELSE CLICK-MODE THEN  ENDOF
      13       OF  GMODE @ M-PLAY = IF CUR-X @ CUR-Y @ LAY-AT ELSE CLICK-MODE THEN  ENDOF
      BL       OF  GMODE @ M-PLAY = IF FLOW-KEY ELSE CLICK-MODE THEN  ENDOF
      [CHAR] p OF  GMODE @ M-PLAY = IF PAUSED @ 0= PAUSED ! THEN  ENDOF
      [CHAR] r OF  RESTART  ENDOF
   ENDCASE ;

: READ-KEYS ( -- )   BEGIN INKEY DUP -1 <> WHILE KEY! REPEAT DROP ;

\ ---- The picture -------------------------------------------------------------------

: PIPE-SPR ( t -- a )   CELLS PIPE-ART + @ ;

: DRAW-PIECE { sx sy t -- }    \ a pipe with no water
   t 7 = IF  sx sy 1 PIPE-SPR SPR  sx sy 2 PIPE-SPR SPR  EXIT  THEN
   sx sy t PIPE-SPR SPR ;

: FRAME-OF ( -- step )   W-P @ STEPS * 1024 /  STEPS 1- MIN ;
: CURRENT? ( x y -- flag )   W-Y @ =  SWAP W-X @ = AND  FLOWING @ AND ;

: DRAW-WATER { x y t sx sy | -- }     \ t a simple pipe, 1 to 6
   x y CURRENT? IF
      sx sy  t W-E @ PATH-OF FRAME-OF WATER-SPR SPR
   ELSE
      x y WET@ IF  sx sy t FULL-WATER SPR  THEN
   THEN ;

: DRAW-CROSS { x y sx sy | wets -- }
   x y WET@ TO wets
   sx sy 1 PIPE-SPR SPR
   x y CURRENT? W-E @ 1 AND 0<> AND IF
      sx sy 1 W-E @ PATH-OF FRAME-OF WATER-SPR SPR
   ELSE  wets 1 AND IF  sx sy 1 FULL-WATER SPR  THEN  THEN
   sx sy 2 PIPE-SPR SPR
   x y CURRENT? W-E @ 1 AND 0= AND IF
      sx sy 2 W-E @ PATH-OF FRAME-OF WATER-SPR SPR
   ELSE  wets 2 AND IF  sx sy 2 FULL-WATER SPR  THEN  THEN ;

: TANK-LEVEL { x y sx sy | v -- }
   x y CURRENT? IF  W-P @ 30 * 1024 / TO v
   ELSE  x y WET@ IF 30 TO v THEN  THEN
   v 0> IF
      $2A93D8 COLOR!  sx 17 + sy 47 + v - 30 v FILL-RECT
      $9FE8FF COLOR!  sx 17 + sy 47 + v - 30 2 FILL-RECT
   THEN ;

: DRAW-SQUARE { x y | t sx sy -- }
   x y KIND@ TO t
   t 0= IF EXIT THEN
   x CS * BX0 + TO sx   y CS * BY0 + TO sy
   t 7 < IF  sx sy t PIPE-SPR SPR  x y t sx sy DRAW-WATER  EXIT  THEN
   t 7 = IF  x y sx sy DRAW-CROSS  EXIT  THEN
   t 12 < IF
      sx sy t BASE-PIPE PIPE-SPR SPR
      x y t BASE-PIPE sx sy DRAW-WATER
      t 10 < IF
         sx sy TANK-ART @ SPR  x y sx sy TANK-LEVEL
      ELSE  sx sy PUMP-ART @ SPR  THEN
      EXIT
   THEN
   t 12 = IF  sx sy ROCK-ART @ SPR  EXIT  THEN
   t 13 = IF
      sx sy  SRC-D @ FLOWING @ GMODE @ M-END = OR  #TRAIL @ 0> OR IF 4 + THEN  CELLS SOURCE-ART + @  SPR
      EXIT
   THEN
   t 14 = IF  sx sy DRAIN-ART @ SPR  EXIT  THEN
   sx sy TUNNEL-ART @ SPR ;

: DOT { x y c -- }
   x x 2 + y c GFX-HLINE   x x 2 + y 1+ c GFX-HLINE   x 1+ x 1+ y 1- c GFX-HLINE ;

: HEAD@ ( path step -- hx hy )
   SWAP STEPS * + 2* HEADS +  DUP C@ SWAP 1+ C@ ;

: DRAW-BUBBLES ( -- )
   #TRAIL @ 0 ?DO
      I 3 * CELLS TRAIL + @  I 3 * 1+ CELLS TRAIL + @  I 3 * 2 + CELLS TRAIL + @  { x y path }
      path  CLOCK @ 4 /  I 5 * + STEPS MOD  HEAD@
      y CS * BY0 + +  SWAP x CS * BX0 + + SWAP  $D8F4FF DOT
   LOOP ;

: NUMBER-AT { n x y -- }
   n S>D <# #S #>  0 DO
      DUP I + C@ [CHAR] 0 - CELLS DIGITS + @  { s }
      x I DIGIT-W @ * +  y  s SPR
   LOOP DROP ;
: DIGITS-OF ( n -- count )   S>D <# #S #> NIP ;
: NUM-W ( n -- px )   DIGITS-OF DIGIT-W @ * ;

: DROP-ICON { x y c -- }
   c COLOR!
   x 7 + y 9 + 6 FILL-CIRCLE
   6 0 DO  x 7 + I -  x 7 + I +  y I 2* + c GFX-HLINE  LOOP ;

: DRAW-TOP { | x -- }
   12 TO x
   x 11 L-STAGE @ SPR     L-STAGE @ SPR-W x + 8 + TO x
   STG @ 1+ x 11 NUMBER-AT   DIGIT-W @ x + 14 + TO x
   x 11  STG @ CELLS STAGE-NAMES + @ SPR
   400 11 L-SCORE @ SPR   L-SCORE @ SPR-W 408 + TO x
   SCORE @ x 11 NUMBER-AT
   640 11 L-LIVES @ SPR   L-LIVES @ SPR-W 650 + TO x
   LIVES @ 0 ?DO  x I 22 * + 9  $6FD0FF DROP-ICON  LOOP ;

: DRAW-QUEUE { | y -- }
   16 56 L-NEXT @ SPR
   #QUEUE 0 DO
      I 76 * 84 + TO y
      I IF  ELSE  $F0C030 COLOR!  14 y 4 - 72 4 FILL-RECT  14 y CS + 2 + 72 4 FILL-RECT
                  14 y 4 - 4 CS 10 + FILL-RECT  82 y 4 - 4 CS 10 + FILL-RECT  THEN
      18 y QUEUE I CELLS + @ DRAW-PIECE
   LOOP ;

: DRAW-COUNT { | x -- }
   16 480 L-PIPES @ SPR
   16 TO x
   FILLED @ x 504 NUMBER-AT   FILLED @ NUM-W x + TO x
   x 504 SLASH-SPR @ SPR      SLASH-SPR @ SPR-W x + TO x
   QUOTA @ x 504 NUMBER-AT
   FILLED @ QUOTA @ >= IF  $70F0B0 COLOR!  16 530 100 4 FILL-RECT  ELSE
      $2A4A68 COLOR!  16 530 100 4 FILL-RECT
      $6FD0FF COLOR!  16 530 100 FILLED @ * QUOTA @ / 4 FILL-RECT
   THEN ;

: DRAW-BOTTOM { | v -- }
   GMODE @ M-RESULT = IF EXIT THEN
   FLOWING @ GMODE @ M-END = OR IF
      144 582 L-FLOW @ SPR
   ELSE
      144 582 L-WATER @ SPR
      144 L-WATER @ SPR-W + 10 + TO v
      COUNTDOWN @ 60 / 1+ v 582 NUMBER-AT
      $2A4A68 COLOR!  v 40 + 588 400 8 FILL-RECT
      COUNTDOWN @ 240 < IF $FF7050 ELSE $6FD0FF THEN COLOR!
      v 40 +  588  400 COUNTDOWN @ *  STG @ 3 * 1+ CELLS STAGE-INFO + @ /  8 FILL-RECT
   THEN
   144 610 L-HELP-PLAY @ SPR
   PUMPED @ IF  $F0C030 COLOR!  660 582 120 8 FILL-RECT  THEN ;

: BOX-AROUND { x y c -- }
   c COLOR!
   x y CS 3 FILL-RECT   x y CS + 3 - CS 3 FILL-RECT
   x y 3 CS FILL-RECT   x CS + 3 - y 3 CS FILL-RECT ;

: DRAW-CURSOR { | sx sy c -- }
   CUR-ON @ 0= GMODE @ M-PLAY <> OR IF EXIT THEN
   CUR-X @ CS * BX0 + TO sx   CUR-Y @ CS * BY0 + TO sy
   CUR-X @ CUR-Y @ CAN-LAY? IF
      CUR-X @ CUR-Y @ KIND@ IF $F0C030 ELSE $70F0B0 THEN TO c
      sx sy NEXT-KIND DRAW-PIECE
   ELSE  $FF7050 TO c  THEN
   sx sy c BOX-AROUND ;

: DRAW-BOARD ( -- )
   BH 0 DO BW 0 DO  I J DRAW-SQUARE  LOOP LOOP ;

: CENTER-X ( spr -- x )   SPR-W W SWAP - 2/ ;

: RESULT-PANEL ( -- )
   $0C1E32 COLOR!  BX0 150 + 200 340 200 FILL-RECT
   $6FD0FF COLOR!  BX0 150 + 200 340 3 FILL-RECT  BX0 150 + 397 340 3 FILL-RECT ;
: AT-MIDDLE ( y spr -- )   { y s }  BX0 320 + s SPR-W 2/ -  y  s SPR ;
: NUMBER-MIDDLE { n y -- }   n  BX0 320 + n NUM-W 2/ -  y NUMBER-AT ;

: DRAW-RESULT ( -- )
   RESULT-PANEL
   RESULT @ CASE
      0 OF  220 R-CLEAR @ AT-MIDDLE  ENDOF
      1 OF  220 R-LEAK @ AT-MIDDLE   ENDOF
      2 OF  220 R-OVER @ AT-MIDDLE   ENDOF
      3 OF  220 R-DONE @ AT-MIDDLE   ENDOF
   ENDCASE
   296 L-SCORE @ AT-MIDDLE
   SCORE @ 318 NUMBER-MIDDLE
   358 RESULT @ DUP 0= IF DROP R-GO ELSE 1 = IF R-AGAIN ELSE R-MENU THEN THEN @ AT-MIDDLE ;

: DEMO-LINE ( -- )     \ water running along a pipe on the title screen
   CLOCK @ STEPS BW * 2* MOD  { t }
   t STEPS BW * MOD { p }
   BW 0 DO
      I CS * 80 +  300 1 PIPE-SPR SPR
      t STEPS BW * < IF
         p STEPS / I > IF  I CS * 80 + 300 1 FULL-WATER SPR  THEN
         p STEPS / I = IF  I CS * 80 + 300  1 3 PATH-OF  p STEPS MOD WATER-SPR SPR  THEN
      ELSE
         p STEPS / I <= IF  I CS * 80 + 300 1 FULL-WATER SPR  THEN
      THEN
   LOOP ;

: DRAW-TITLE ( -- )
   C-BAR GFX-CLS
   L-TITLE @ CENTER-X  120 L-TITLE @ SPR
   DEMO-LINE
   L-HELP1 @ CENTER-X 240 L-HELP1 @ SPR
   L-HELP2 @ CENTER-X 400 L-HELP2 @ SPR
   L-START @ CENTER-X 450 CLOCK @ 32 AND IF L-START @ SPR ELSE 2DROP THEN
   BEST @ IF
      L-BEST @ CENTER-X 30 -  520 L-BEST @ SPR
      BEST @ W 2/ 16 +  520  NUMBER-AT
   THEN ;

: RENDER ( -- )
   GMODE @ M-TITLE = IF DRAW-TITLE EXIT THEN
   0 0 TABLE-ART @ SPR
   DRAW-TOP  DRAW-QUEUE  DRAW-COUNT  DRAW-BOTTOM
   DRAW-BOARD
   DRAW-BUBBLES
   DRAW-CURSOR
   DRAW-SPARKS
   PAUSED @ IF  L-PAUSE @ CENTER-X 320 L-PAUSE @ SPR  THEN
   GMODE @ M-RESULT = IF DRAW-RESULT THEN ;

\ ---- The steps ---------------------------------------------------------------------

: TICK-PLAY ( -- )
   FLOWING @ IF  STEP-WATER  EXIT  THEN
   -1 COUNTDOWN +!
   COUNTDOWN @ 0> IF
      COUNTDOWN @ 240 < COUNTDOWN @ 60 MOD 0= AND IF S-TICK EFFECT THEN
   ELSE  LET-WATER-GO  THEN ;

: TICK-GAME ( -- )
   1 CLOCK +!
   PAUSED @ IF EXIT THEN
   STEP-SPARKS
   GMODE @ CASE
      M-PLAY OF  TICK-PLAY  ENDOF
      M-END  OF  -1 END-T +!  END-T @ 0= IF END-OF-WATER THEN  ENDOF
   ENDCASE ;

: GAME-STEP ( -- )   READ-KEYS  READ-MOUSE  TICK-GAME  RENDER ;

: INIT-GAME ( -- )
   NOW SEED !  FALSE DONE !  TO-TITLE  0 BEST !  0 OLD-B ! ;

: WATERWORKS ( -- )
   BAKE-ALL  MAKE-SOUNDS
   W H GFX-INIT  MOUSE-ON
   INIT-GAME
   BEGIN  GAME-STEP  16 FRAME  DONE @ UNTIL
   MOUSE-OFF
   CR ." Best: " BEST @ . CR ;

[UNDEFINED] NO-AUTORUN [IF] WATERWORKS BYE [THEN]
