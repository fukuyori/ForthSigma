\ Sonar Sweep: find the mines on the sea bed by what the sonar tells you, in a window.
\ The pictures, the sounds, and the three sea areas are this file's own, made at
\ レモン's request.
\
\   sigma.exe examples/sweeper.fs      (in a window; Tk on Linux/macOS)
\
\ Mouse: the left button opens a square; the right button sets or lifts a buoy; the left
\ or the middle button on a number opens the squares around it, when as many buoys as
\ the number stand around it.
\ Keys: the arrows move the cursor, Z or Enter opens, X or Space sets a buoy, R starts
\ again, T goes to the title, P pauses, Q or Esc ends the game.
\
\ A number tells how many mines lie on the 8 squares around it. Open every square that
\ has no mine to clear the sea. The first square opened and those around it never hold
\ a mine.

REQUIRE-GRAPHICS  ALSO GRAPHICS

\ ---- Sound ------------------------------------------------------------------------

: AUDIO-LOADED? ( -- flag )   S" REQUIRE-AUDIO" ['] EVALUATE CATCH  DUP IF NIP NIP THEN  0= ;
[UNDEFINED] NO-SOUND [IF] AUDIO-LOADED? [ELSE] FALSE [THEN] CONSTANT HAS-SOUND

0 CONSTANT S-OPEN   1 CONSTANT S-PING   2 CONSTANT S-BUOY   3 CONSTANT S-LIFT
4 CONSTANT S-BOOM   5 CONSTANT S-THUD   6 CONSTANT S-NO

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
   BLANK-WAVE  0 450 7 60 CHIME                              450 S-OPEN KEEP-WAVE
   BLANK-WAVE  0 3600 5 62 CHIME  0 3600 10 30 CHIME        3600 S-PING KEEP-WAVE
   BLANK-WAVE  0 500 9 70 BLOOP                              500 S-BUOY KEEP-WAVE
   BLANK-WAVE  0 300 5 36 CHIME                              300 S-LIFT KEEP-WAVE
   BLANK-WAVE  0 9000 70 300 SWISH                          9000 S-BOOM KEEP-WAVE
   BLANK-WAVE  0 2500 110 240 SWISH                         2500 S-THUD KEEP-WAVE
   BLANK-WAVE  0 1000 30 60 CHIME                           1000 S-NO KEEP-WAVE ;
PREVIOUS
[ELSE]
: EFFECT ( k -- )   DROP ;
: JINGLE ( c-addr u -- )   2DROP ;
: MAKE-SOUNDS ( -- ) ;
[THEN]

\ ---- Numbers and sizes -------------------------------------------------------------

800 CONSTANT W          \ the image
640 CONSTANT H
448 CONSTANT MAX-SQUARES

3 CONSTANT #LEVELS
CREATE LEVELS           \ columns, rows, mines, pixels to a square
   10 , 10 , 12 , 52 ,
   16 , 14 , 36 , 38 ,
   28 , 16 , 90 , 27 ,

VARIABLE LEVEL
0 VALUE BW   0 VALUE BH   0 VALUE #MINES   0 VALUE CS
0 VALUE BX0  0 VALUE BY0  0 VALUE #SQUARES

: LOAD-LEVEL ( n -- )
   DUP LEVEL !
   4 * CELLS LEVELS +  DUP @ TO BW  CELL+ DUP @ TO BH  CELL+ DUP @ TO #MINES  CELL+ @ TO CS
   W BW CS * - 2/ TO BX0
   552 BH CS * - 2/ 56 + TO BY0
   BW BH * TO #SQUARES ;

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

\ A sine of 64 steps to the circle, times 1024.
CREATE QUARTER  0 , 100 , 200 , 297 , 392 , 483 , 569 , 650 , 724 , 792 , 851 , 903 , 946 , 980 , 1004 , 1019 , 1024 ,
: SIN64 { k | s -- v }
   k 63 AND TO k   1 TO s
   k 31 > IF  k 32 - TO k  -1 TO s  THEN
   k 16 > IF  32 k - TO k  THEN
   k CELLS QUARTER + @  s * ;
: COS64 ( k -- v )   16 + SIN64 ;

\ ---- Sprites made of spans ---------------------------------------------------------
\ A sprite: its number of spans, width, height, then a cell for each span with x1, x2,
\ and y (12 bits each) and the color.

: SPAN, { x1 x2 y c -- }   x1  x2 12 LSHIFT OR  y 24 LSHIFT OR  c 36 LSHIFT OR  , ;

: BAKE { pw ph xt | a x c x2 -- a }    \ xt ( x y -- rgb | -1 )
   ALIGN HERE TO a   0 ,  pw ,  ph ,
   ph 0 DO
      0 TO x
      BEGIN x pw < WHILE
         x I xt EXECUTE TO c
         x TO x2
         BEGIN  x2 1+ pw < IF  x2 1+ I xt EXECUTE c =  ELSE FALSE THEN  WHILE  x2 1+ TO x2  REPEAT
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
: CENTER-X ( a -- x )   SPR-W W SWAP - 2/ ;

\ ---- Painting tools ----------------------------------------------------------------
\ A square is painted at 3 canvas pixels to a pixel, in units of 64 to the square.

$FF00FE CONSTANT KEY-COLOR
$081A2C CONSTANT C-BAR     $0A1826 CONSTANT C-OPEN    $16304A CONSTANT C-EDGE
$FFF4D6 CONSTANT C-TEXT    $8FB4D0 CONSTANT C-LABEL   $2A5A7C CONSTANT C-LINE
$8FE0FF CONSTANT C-LIT     $70F0B0 CONSTANT C-SONAR

: CANVAS-PX ( x y -- rgb | -1 )   GFX-PGET  DUP KEY-COLOR = IF DROP -1 THEN ;

3 CONSTANT ZOOM
: SCALED ( n -- n' )   CS ZOOM * *  64 / ;
: >CANVAS ( x y -- cx cy )   SCALED SWAP SCALED SWAP ;
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
: BOX { x1 y1 x2 y2 -- }   [P x1 y1 DV x2 y1 DV x2 y2 DV x1 y2 DV P] ;
: DISC ( x y r -- )   >R >CANVAS R> SCALED FILL-CIRCLE ;

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
: ART-BEGIN ( -- )   KEY-COLOR GFX-CLS ;
: ART-DONE ( -- spr )   CS CS ['] ART-PX BAKE ;

\ ---- The pictures of the squares ---------------------------------------------------

9  CONSTANT K-COVER    \ 0 to 8 are the open squares with that number
10 CONSTANT K-BUOY
11 CONSTANT K-MINE
12 CONSTANT K-HIT
13 CONSTANT K-WRONG
14 CONSTANT #KINDS
CREATE ART #LEVELS #KINDS * CELLS ALLOT
: >ART ( k -- a )   LEVEL @ #KINDS * + CELLS ART + ;
: SPRITE ( k -- spr )   >ART @ ;

: USE-FONT ( height -- )
   >R S" Segoe UI Semibold" R@ ['] SYSTEM-FONT CATCH
   IF  2DROP DROP  BUILTIN-FONT  R> 8 / 1 MAX TEXT-SCALE
   ELSE  R> DROP  1 TEXT-SCALE  THEN ;
: DIGIT$ ( n -- c-addr 1 )   S" 0123456789" DROP + 1 ;

CREATE NUMBER-COLORS  0 , $6FD0FF , $70E090 , $F8D050 , $C89CFF , $FF8C60 , $50E0D0 , $FFFFFF , $FF90C0 ,

: PAINT-OPEN ( bg -- )   C-EDGE INK  0 0 64 64 BOX  INK  2 2 62 62 BOX ;

: PAINT-NUMBER { n | a u -- }
   C-OPEN PAINT-OPEN
   n 0= IF EXIT THEN
   n CELLS NUMBER-COLORS + @ INK
   n DIGIT$ TO u TO a
   a u  CS ZOOM * a u TEXT-WIDTH - 2/  CS ZOOM * TEXT-HEIGHT - 2/  TEXT ;

: PAINT-COVER ( -- )
   $0E2A44 INK  0 0 64 64 BOX
   $58A4CC INK  2 2 62 62 BOX
   $174060 INK  [P 62 2 DV 62 62 DV 2 62 DV P]
   $2E7098 INK  8 8 56 56 BOX ;

: PAINT-BUOY ( -- )
   $E8EEF4 INK  29 12 34 46 BOX
   $E8402C INK  [P 34 12 DV 52 21 DV 34 30 DV P]
   $F0B428 INK  [P 16 44 DV 48 44 DV 43 55 DV 21 55 DV P]
   $FFF0C8 INK  18 44 46 47 BOX ;

: PAINT-MINE ( -- )
   $8A98A8 INK  30 6 34 58 BOX   6 30 58 34 BOX
   [P 14 17 DV 17 14 DV 50 47 DV 47 50 DV P]
   [P 47 14 DV 50 17 DV 17 50 DV 14 47 DV P]
   $4A5564 INK  32 32 18 DISC
   $6C7888 INK  31 31 15 DISC
   $D8E2EC INK  26 26 5 DISC ;

: PAINT-CROSS ( -- )
   $FF3030 INK
   [P 8 13 DV 13 8 DV 56 51 DV 51 56 DV P]
   [P 51 8 DV 56 13 DV 13 56 DV 8 51 DV P] ;

: MAKE-LEVEL-ART ( -- )
   CS ZOOM * 3 * 4 / USE-FONT
   9 0 DO  ART-BEGIN I PAINT-NUMBER  ART-DONE  I >ART !  LOOP
   ART-BEGIN PAINT-COVER                       ART-DONE  K-COVER >ART !
   ART-BEGIN PAINT-COVER PAINT-BUOY            ART-DONE  K-BUOY >ART !
   ART-BEGIN C-OPEN PAINT-OPEN PAINT-MINE      ART-DONE  K-MINE >ART !
   ART-BEGIN $A82818 PAINT-OPEN PAINT-MINE     ART-DONE  K-HIT >ART !
   ART-BEGIN PAINT-COVER PAINT-BUOY PAINT-CROSS ART-DONE K-WRONG >ART ! ;

\ ---- Text --------------------------------------------------------------------------

: TEXT-SPRITE { a u fg bg | pw ph -- spr }
   a u TEXT-WIDTH TO pw   TEXT-HEIGHT TO ph
   bg GFX-CLS  fg INK  a u 0 0 TEXT
   pw ph ['] CANVAS-PX BAKE ;
: LABEL ( a u -- spr )   C-LABEL C-BAR TEXT-SPRITE ;
: BRIGHT ( a u -- spr )  C-TEXT C-BAR TEXT-SPRITE ;

CREATE DIGITS 10 CELLS ALLOT    VARIABLE DIGIT-W
VARIABLE COLON-SPR   VARIABLE MINUS-SPR
VARIABLE L-MINES  VARIABLE L-TIME  VARIABLE L-BEST  VARIABLE L-NEW  VARIABLE L-TITLE-B
VARIABLE L-AGAIN  VARIABLE L-PAUSE VARIABLE L-HELP  VARIABLE L-NONE
VARIABLE T-TITLE  VARIABLE T-HELP1 VARIABLE T-HELP2 VARIABLE T-HELP3
VARIABLE R-CLEAR  VARIABLE R-HIT   VARIABLE R-RECORD
CREATE LEVEL-NAMES #LEVELS CELLS ALLOT
CREATE LEVEL-NOTES #LEVELS CELLS ALLOT

: LEVEL-NAME$ ( n -- a u )
   CASE
      0 OF S" Harbor" ENDOF
      1 OF S" Channel" ENDOF
      2 OF S" Open Sea" ENDOF
      S" " ROT
   ENDCASE ;
: LEVEL-NOTE$ ( n -- a u )
   CASE
      0 OF S" 10 by 10, 12 mines" ENDOF
      1 OF S" 16 by 14, 36 mines" ENDOF
      2 OF S" 28 by 16, 90 mines" ENDOF
      S" " ROT
   ENDCASE ;

: MAKE-TEXT ( -- )
   13 USE-FONT
   S" Left: open    Right: buoy    Left on a number: open around it    R again    T title    P pause    Q quit" LABEL L-HELP !
   15 USE-FONT
   S" MINES LEFT" LABEL L-MINES !   S" TIME" LABEL L-TIME !   S" BEST" LABEL L-BEST !
   S" New" BRIGHT L-NEW !           S" Title" BRIGHT L-TITLE-B !
   S" Again" BRIGHT L-AGAIN !       S" Paused" BRIGHT L-PAUSE !
   S" none yet" LABEL L-NONE !
   #LEVELS 0 DO  I LEVEL-NOTE$ LABEL  LEVEL-NOTES I CELLS + !  LOOP
   S" A number tells how many mines lie on the 8 squares around it." BRIGHT T-HELP1 !
   S" Left button opens a square, right button sets a buoy on a mine." LABEL T-HELP2 !
   S" Click or press 1, 2, 3 to choose a sea.   Q quits." LABEL T-HELP3 !
   S" New best time!" $F0C030 C-BAR TEXT-SPRITE R-RECORD !
   20 USE-FONT
   S" 0" TEXT-WIDTH DIGIT-W !
   10 0 DO  I DIGIT$ BRIGHT  DIGITS I CELLS + !  LOOP
   S" :" BRIGHT COLON-SPR !   S" -" BRIGHT MINUS-SPR !
   24 USE-FONT
   #LEVELS 0 DO  I LEVEL-NAME$ BRIGHT  LEVEL-NAMES I CELLS + !  LOOP
   64 USE-FONT
   S" Sonar Sweep" C-LIT C-BAR TEXT-SPRITE T-TITLE !
   40 USE-FONT
   S" Sea cleared" C-TEXT C-BAR TEXT-SPRITE R-CLEAR !
   S" Mine hit" $FF9070 C-BAR TEXT-SPRITE R-HIT ! ;

\ The radar on the title.
70 CONSTANT RADAR-R
VARIABLE RADAR-ART
: RADAR-PX { x y | dx dy d -- rgb | -1 }
   x RADAR-R - TO dx   y RADAR-R - TO dy
   dx dx * dy dy * + ISQRT TO d
   d RADAR-R > IF -1 EXIT THEN
   d RADAR-R 1- >= IF C-LINE EXIT THEN
   d 23 = d 46 = OR  dx 0= OR  dy 0= OR IF $123C50 EXIT THEN
   $0A2436 ;

: BAKE-ALL ( -- )
   800 256 GFX-INIT
   #LEVELS 0 DO  I LOAD-LEVEL  MAKE-LEVEL-ART  LOOP
   MAKE-TEXT
   RADAR-R 2* 1+ DUP ['] RADAR-PX BAKE RADAR-ART ! ;

\ ---- The sea -----------------------------------------------------------------------
\ A byte for each square: the number around it in the low 4 bits, and these.

$10 CONSTANT MINE-B   $20 CONSTANT OPEN-B   $40 CONSTANT BUOY-B   $80 CONSTANT BOOM-B

CREATE BOARD MAX-SQUARES ALLOT
: >I ( x y -- i )   BW * + ;
: I>X ( i -- x )   BW MOD ;
: I>Y ( i -- y )   BW / ;
: SQ ( x y -- a )   >I BOARD + ;
: IN-BOARD? { x y -- flag }   x 0 BW WITHIN  y 0 BH WITHIN AND ;

CREATE DXS  -1 ,  0 ,  1 , -1 , 1 , -1 , 0 , 1 ,
CREATE DYS  -1 , -1 , -1 ,  0 , 0 ,  1 , 1 , 1 ,
: EACH-AROUND { x y xt | nx ny -- }     \ xt ( x y -- )
   8 0 DO
      x DXS I CELLS + @ + TO nx
      y DYS I CELLS + @ + TO ny
      nx ny IN-BOARD? IF  nx ny xt EXECUTE  THEN
   LOOP ;

VARIABLE TALLY
: +MINE ( x y -- )    SQ C@ MINE-B AND IF 1 TALLY +! THEN ;
: +BUOY ( x y -- )    SQ C@ BUOY-B AND IF 1 TALLY +! THEN ;
: +HIDDEN ( x y -- )  SQ C@ OPEN-B BUOY-B OR AND 0= IF 1 TALLY +! THEN ;
: COUNT-AROUND ( x y xt -- n )   0 TALLY !  EACH-AROUND  TALLY @ ;

0 CONSTANT M-TITLE  1 CONSTANT M-PLAY  2 CONSTANT M-END  3 CONSTANT M-RESULT
VARIABLE GMODE    VARIABLE DONE     VARIABLE PAUSED   VARIABLE CLOCK
VARIABLE STARTED  VARIABLE LOST     VARIABLE #OPENED  VARIABLE #BUOYS
VARIABLE HIT-X    VARIABLE HIT-Y    VARIABLE END-T    VARIABLE BOOM-N   VARIABLE LAST-BOOM
VARIABLE RECORD?  VARIABLE CUR-X    VARIABLE CUR-Y    VARIABLE CUR-ON   VARIABLE SEL
VARIABLE RUNNING  VARIABLE T0       VARIABLE FINAL
CREATE BESTS #LEVELS CELLS ALLOT

\ The time.
: TIME-US ( -- us )   RUNNING @ IF NOW T0 @ - ELSE FINAL @ THEN ;
: TIME-S ( -- s )   TIME-US 1000000 / ;
: START-CLOCK ( -- )   NOW T0 !  TRUE RUNNING ! ;
: STOP-CLOCK ( -- )   TIME-US FINAL !  FALSE RUNNING ! ;
: >PAUSE ( -- )   STARTED @ IF STOP-CLOCK THEN  TRUE PAUSED ! ;
: >UNPAUSE ( -- )   STARTED @ IF  NOW FINAL @ - T0 !  TRUE RUNNING !  THEN  FALSE PAUSED ! ;

\ Rings and sparks.
: CENTER-OF ( x y -- px py )   CS * BY0 + CS 2/ +  SWAP  CS * BX0 + CS 2/ +  SWAP ;

8 CONSTANT #RINGS
CREATE RINGS #RINGS 5 * CELLS ALLOT     \ x y radius life color
VARIABLE NEXT-RING
36 CONSTANT RING-LIFE
: RING[] ( n -- a )   5 * CELLS RINGS + ;
: ADD-RING { x y c | a -- }
   NEXT-RING @ RING[] TO a
   x a !  y a CELL+ !  6 a 2 CELLS + !  RING-LIFE a 3 CELLS + !  c a 4 CELLS + !
   NEXT-RING @ 1+ #RINGS MOD NEXT-RING ! ;
: STEP-RINGS ( -- )
   #RINGS 0 DO
      I RING[] { a }
      a 3 CELLS + @ 0> IF  6 a 2 CELLS + +!  -1 a 3 CELLS + +!  THEN
   LOOP ;
: CLEAR-RINGS ( -- )   RINGS #RINGS 5 * CELLS ERASE ;

: DRAW-RING { cx cy r c | dy a b y0 -- }
   r 1+ r NEGATE DO
      I TO dy
      r r * dy dy * - ISQRT TO a
      dy ABS 1+ r > IF 0 ELSE  r r *  dy ABS 1+ DUP * -  ISQRT  THEN TO b
      cy dy + TO y0
      y0 0 H WITHIN IF
         cx a - 0 MAX  cx b - W 1- MIN  y0 c GFX-HLINE
         cx b + 0 MAX  cx a + W 1- MIN  y0 c GFX-HLINE
      THEN
   LOOP ;
: DRAW-RINGS ( -- )
   #RINGS 0 DO
      I RING[] { a }
      a 3 CELLS + @ 0> IF
         a @  a CELL+ @  a 2 CELLS + @
         C-OPEN  a 4 CELLS + @  a 3 CELLS + @ 255 * RING-LIFE /  MIX-RGB  DRAW-RING
      THEN
   LOOP ;

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
      x y  spread 2* 1+ RND spread -  spread 2* 1+ RND spread -  16 24 RND +  c SPARK
   LOOP ;
: STEP-SPARKS ( -- )
   #SPARKS 0 DO
      I SPARK[] { a }
      a 4 CELLS + @ 0> IF
         a 2 CELLS + @ a +!   a 3 CELLS + @ a CELL+ +!
         -1 a 4 CELLS + +!
      THEN
   LOOP ;
: DRAW-SPARKS { | sx sy -- }
   #SPARKS 0 DO
      I SPARK[] { a }
      a 4 CELLS + @ 0> IF
         a @ 16 / TO sx   a CELL+ @ 16 / TO sy
         sx 0 W 3 - WITHIN  sy 0 H 2 - WITHIN AND IF
            sx DUP 2 +  sy     a 5 CELLS + @ GFX-HLINE
            sx DUP 2 +  sy 1+  a 5 CELLS + @ GFX-HLINE
         THEN
      THEN
   LOOP ;
: CLEAR-SPARKS ( -- )   SPARKS #SPARKS 6 * CELLS ERASE ;

\ ---- Mines and opening -------------------------------------------------------------

CREATE POOL MAX-SQUARES CELLS ALLOT   VARIABLE #POOL
: POOL+ ( n -- )   POOL #POOL @ CELLS + !  1 #POOL +! ;

: SAFE? { x y fx fy -- flag }   x fx - ABS 2 <  y fy - ABS 2 < AND ;

: SET-NUMBERS ( -- )
   #SQUARES 0 DO
      I I>X I I>Y ['] +MINE COUNT-AROUND
      I BOARD + DUP C@ $F0 AND ROT OR SWAP C!
   LOOP ;

: PLACE-MINES { fx fy | k t -- }
   0 #POOL !
   #SQUARES 0 DO
      I I>X I I>Y fx fy SAFE? 0= IF  I POOL+  THEN
   LOOP
   #MINES 0 DO
      #POOL @ I - RND I + TO k
      POOL k CELLS + @ TO t
      POOL I CELLS + @  POOL k CELLS + !
      t POOL I CELLS + !
      t BOARD + DUP C@ MINE-B OR SWAP C!
   LOOP
   SET-NUMBERS
   TRUE STARTED !
   START-CLOCK ;

CREATE WAITING MAX-SQUARES CELLS ALLOT   VARIABLE #WAITING
: WAIT+ ( i -- )   WAITING #WAITING @ CELLS + !  1 #WAITING +! ;
: WAIT- ( -- i )   -1 #WAITING +!  WAITING #WAITING @ CELLS + @ ;

: UNCOVER { x y | a c -- }        \ never called for a mine
   x y SQ TO a   a C@ TO c
   c OPEN-B BUOY-B OR AND IF EXIT THEN
   c OPEN-B OR a C!
   1 #OPENED +!
   c $0F AND 0= IF  x y >I WAIT+  THEN ;
: FLOOD ( -- )
   BEGIN #WAITING @ WHILE
      WAIT- DUP I>X SWAP I>Y ['] UNCOVER EACH-AROUND
   REPEAT ;

: TO-RESULT ( -- )
   M-RESULT GMODE !
   LOST @ IF  S" T110 L8 O3 GFED2" JINGLE  THEN ;

: DIST2 ( i -- d )   DUP I>X HIT-X @ - DUP *  SWAP I>Y HIT-Y @ - DUP *  + ;
: SORT-POOL ( -- )        \ the nearest to the hit first
   #POOL @ 1 MAX 1 ?DO
      POOL I CELLS + @ { v }
      I BEGIN
         DUP 0> IF  DUP 1- CELLS POOL + @ DIST2  v DIST2 >  ELSE FALSE THEN
      WHILE
         DUP 1- CELLS POOL + @  OVER CELLS POOL + !
         1-
      REPEAT
      v SWAP CELLS POOL + !
   LOOP ;
: LIST-MINES ( -- )
   0 #POOL !
   #SQUARES 0 DO
      I BOARD + C@  DUP MINE-B AND 0<>  SWAP BUOY-B BOOM-B OR AND 0= AND IF  I POOL+  THEN
   LOOP
   SORT-POOL ;

: BLOW-UP { x y | px py -- }
   x HIT-X !  y HIT-Y !  TRUE LOST !  STOP-CLOCK
   x y SQ DUP C@ BOOM-B OR SWAP C!
   LIST-MINES
   0 BOOM-N !  0 END-T !  0 LAST-BOOM !
   M-END GMODE !
   x y CENTER-OF TO py TO px
   px py 40 40 $FFB040 BURST
   px py $FF7040 ADD-RING
   S-BOOM EFFECT ;

: DETONATE { n | px py -- }
   n BOARD + DUP C@ BOOM-B OR SWAP C!
   n I>X n I>Y CENTER-OF TO py TO px
   px py 6 26 $FF9040 BURST
   END-T @ LAST-BOOM @ - 5 >= IF  S-THUD EFFECT  END-T @ LAST-BOOM !  THEN ;

: WIN ( -- )
   STOP-CLOCK
   #SQUARES 0 DO
      I BOARD + C@ MINE-B AND IF  I BOARD + DUP C@ BUOY-B OR SWAP C!  THEN
   LOOP
   #MINES #BUOYS !
   LEVEL @ CELLS BESTS + { b }
   b @ 0<  TIME-S b @ < OR IF  TIME-S b !  TRUE RECORD? !  THEN
   0 #POOL !  0 END-T !
   M-END GMODE !
   4 0 DO  W 2/  H 2/  C-SONAR  ADD-RING  LOOP
   S" T170 L16 O5 EG>C<G>EG>C4<G8>C2" JINGLE ;

: CHECK-WIN ( -- )   #OPENED @  #SQUARES #MINES -  = IF WIN THEN ;

: AFTER-OPEN { x y before | px py -- }
   #OPENED @ before - 8 > IF
      x y CENTER-OF TO py TO px
      px py C-SONAR ADD-RING
      S-PING EFFECT
   ELSE
      S-OPEN EFFECT
   THEN
   CHECK-WIN ;

VARIABLE CHORD-HIT
: OPEN-AROUND { x y | c -- }
   x y SQ C@ TO c
   c OPEN-B BUOY-B OR AND IF EXIT THEN
   c MINE-B AND IF
      CHORD-HIT @ 0< IF  x y >I CHORD-HIT !  THEN  EXIT
   THEN
   x y UNCOVER ;

: CHORD { x y | before -- }
   x y SQ C@ $0F AND  0= IF EXIT THEN
   x y ['] +HIDDEN COUNT-AROUND 0= IF EXIT THEN
   x y ['] +BUOY COUNT-AROUND  x y SQ C@ $0F AND  <> IF  S-NO EFFECT EXIT  THEN
   #OPENED @ TO before
   -1 CHORD-HIT !
   x y ['] OPEN-AROUND EACH-AROUND
   FLOOD
   CHORD-HIT @ 0>= IF  CHORD-HIT @ DUP I>X SWAP I>Y BLOW-UP  EXIT  THEN
   x y before AFTER-OPEN ;

: PLAYING? ( -- flag )   GMODE @ M-PLAY =  PAUSED @ 0= AND ;

: LEFT-AT { x y | c before -- }
   PLAYING? 0= IF EXIT THEN
   x y IN-BOARD? 0= IF EXIT THEN
   x y SQ C@ TO c
   c OPEN-B AND IF  x y CHORD  EXIT  THEN
   c BUOY-B AND IF  S-NO EFFECT  EXIT  THEN
   STARTED @ 0= IF  x y PLACE-MINES  THEN
   x y SQ C@ MINE-B AND IF  x y BLOW-UP  EXIT  THEN
   #OPENED @ TO before
   x y UNCOVER  FLOOD
   x y before AFTER-OPEN ;

: RIGHT-AT { x y | a c -- }
   PLAYING? 0= IF EXIT THEN
   x y IN-BOARD? 0= IF EXIT THEN
   x y SQ TO a   a C@ TO c
   c OPEN-B AND IF EXIT THEN
   c BUOY-B XOR a C!
   c BUOY-B AND IF  -1 #BUOYS +!  S-LIFT EFFECT  ELSE  1 #BUOYS +!  S-BUOY EFFECT  THEN ;

: MIDDLE-AT { x y -- }
   PLAYING? 0= IF EXIT THEN
   x y IN-BOARD? 0= IF EXIT THEN
   x y SQ C@ OPEN-B AND IF  x y CHORD  THEN ;

: NEW-GAME ( -- )
   BOARD MAX-SQUARES ERASE
   0 #OPENED !  0 #BUOYS !  0 #WAITING !
   FALSE STARTED !  FALSE LOST !  FALSE RUNNING !  FALSE PAUSED !  FALSE RECORD? !
   0 FINAL !  0 END-T !  0 BOOM-N !
   BW 2/ CUR-X !  BH 2/ CUR-Y !  FALSE CUR-ON !
   CLEAR-RINGS  CLEAR-SPARKS
   M-PLAY GMODE ! ;

: START-LEVEL ( n -- )   LOAD-LEVEL  NEW-GAME  S-PING EFFECT ;
: TO-TITLE ( -- )   M-TITLE GMODE !  FALSE PAUSED !  CLEAR-RINGS  CLEAR-SPARKS ;

: STEP-END { | target -- }
   1 END-T +!
   LOST @ IF
      END-T @ #POOL @ * 50 /  #POOL @ MIN  TO target
      BEGIN BOOM-N @ target < WHILE
         POOL BOOM-N @ CELLS + @ DETONATE
         1 BOOM-N +!
      REPEAT
   THEN
   END-T @ 90 >= IF TO-RESULT THEN ;

\ ---- Input -------------------------------------------------------------------------

VARIABLE OLD-B   VARIABLE MX   VARIABLE MY

: IN-RECT? { rx ry rw rh -- flag }
   MX @ rx rx rw + WITHIN   MY @ ry ry rh + WITHIN  AND ;

: >SQUARE ( mx my -- x y )   BY0 - DUP 0< IF DROP -1 ELSE CS / THEN  SWAP
                             BX0 - DUP 0< IF DROP -1 ELSE CS / THEN  SWAP ;

\ Places of the things one can click.
: BTN-NEW ( -- x y w h )     612 10 80 32 ;
: BTN-TITLE ( -- x y w h )   702 10 84 32 ;
: BTN-AGAIN ( -- x y w h )   246 372 140 40 ;
: BTN-BACK ( -- x y w h )    414 372 140 40 ;
: ROW-Y ( n -- y )   80 * 300 + ;
: ROW-RECT ( n -- x y w h )   ROW-Y 190 SWAP 420 68 ;
: ROW-UNDER ( -- n | -1 )
   #LEVELS 0 DO  I ROW-RECT IN-RECT? IF I UNLOOP EXIT THEN  LOOP  -1 ;

: UNDER-MOUSE ( -- x y )   MX @ MY @ >SQUARE ;

: LEFT-PRESS { | n -- }
   GMODE @ CASE
      M-TITLE OF  ROW-UNDER TO n  n 0>= IF n START-LEVEL THEN  ENDOF
      M-PLAY OF
         BTN-NEW IN-RECT? IF  NEW-GAME  ELSE
         BTN-TITLE IN-RECT? IF  TO-TITLE  ELSE
         UNDER-MOUSE LEFT-AT  THEN THEN
      ENDOF
      M-RESULT OF
         BTN-AGAIN IN-RECT? IF  NEW-GAME  ELSE
         BTN-BACK IN-RECT? IF  TO-TITLE  THEN THEN
      ENDOF
   ENDCASE ;

: READ-MOUSE { | px py b -- }
   MOUSE TO b TO py TO px
   px 0>= IF
      px MX @ <>  py MY @ <> OR IF
         px MX !  py MY !
         GMODE @ M-TITLE = IF
            ROW-UNDER DUP 0>= IF SEL ! ELSE DROP THEN
         ELSE
            UNDER-MOUSE 2DUP IN-BOARD? DUP CUR-ON ! IF  CUR-Y ! CUR-X !  ELSE 2DROP THEN
         THEN
      THEN
   THEN
   b 1 AND  OLD-B @ 1 AND 0= AND IF  LEFT-PRESS  THEN
   b 2 AND  OLD-B @ 2 AND 0= AND IF  UNDER-MOUSE RIGHT-AT  THEN
   b 4 AND  OLD-B @ 4 AND 0= AND IF  UNDER-MOUSE MIDDLE-AT  THEN
   b OLD-B ! ;

: MOVE-CURSOR { dx dy -- }
   GMODE @ M-TITLE = IF
      SEL @ dy + 0 MAX #LEVELS 1- MIN SEL !  EXIT
   THEN
   TRUE CUR-ON !
   CUR-X @ dx + 0 MAX BW 1- MIN CUR-X !
   CUR-Y @ dy + 0 MAX BH 1- MIN CUR-Y ! ;

: GO-KEY ( -- )          \ Z or Enter
   GMODE @ CASE
      M-TITLE OF  SEL @ START-LEVEL  ENDOF
      M-PLAY OF  CUR-X @ CUR-Y @ LEFT-AT  ENDOF
      M-RESULT OF  NEW-GAME  ENDOF
   ENDCASE ;
: BUOY-KEY ( -- )        \ X or Space
   GMODE @ CASE
      M-TITLE OF  SEL @ START-LEVEL  ENDOF
      M-PLAY OF  CUR-X @ CUR-Y @ RIGHT-AT  ENDOF
      M-RESULT OF  NEW-GAME  ENDOF
   ENDCASE ;
: PAUSE-KEY ( -- )
   GMODE @ M-PLAY <> IF EXIT THEN
   PAUSED @ IF >UNPAUSE ELSE >PAUSE THEN ;
: LEVEL-KEY ( n -- )   GMODE @ M-TITLE = IF START-LEVEL ELSE DROP THEN ;
: AGAIN-KEY ( -- )   GMODE @ M-TITLE <> GMODE @ M-END <> AND IF NEW-GAME THEN ;

: KEY! ( key -- )
   DUP [CHAR] A [CHAR] Z 1+ WITHIN IF 32 + THEN
   CASE
      [CHAR] q OF  TRUE DONE !  ENDOF
      27       OF  TRUE DONE !  ENDOF
      K-LEFT   OF  -1 0 MOVE-CURSOR  ENDOF
      K-RIGHT  OF   1 0 MOVE-CURSOR  ENDOF
      K-UP     OF  0 -1 MOVE-CURSOR  ENDOF
      K-DOWN   OF  0  1 MOVE-CURSOR  ENDOF
      [CHAR] z OF  GO-KEY  ENDOF
      13       OF  GO-KEY  ENDOF
      [CHAR] x OF  BUOY-KEY  ENDOF
      BL       OF  BUOY-KEY  ENDOF
      [CHAR] p OF  PAUSE-KEY  ENDOF
      [CHAR] r OF  AGAIN-KEY  ENDOF
      [CHAR] t OF  TO-TITLE  ENDOF
      [CHAR] 1 OF  0 LEVEL-KEY  ENDOF
      [CHAR] 2 OF  1 LEVEL-KEY  ENDOF
      [CHAR] 3 OF  2 LEVEL-KEY  ENDOF
   ENDCASE ;

: READ-KEYS ( -- )   BEGIN INKEY DUP -1 <> WHILE KEY! REPEAT DROP ;

\ ---- The picture -------------------------------------------------------------------

: OUTLINE { x y rw rh c -- }
   c COLOR!
   x y rw 2 FILL-RECT   x y rh + 2 - rw 2 FILL-RECT
   x y 2 rh FILL-RECT   x rw + 2 - y 2 rh FILL-RECT ;

: NUMBER-AT { n x y -- }
   n S>D <# #S #>  0 DO
      DUP I + C@ [CHAR] 0 - CELLS DIGITS + @  { s }
      x I DIGIT-W @ * +  y  s SPR
   LOOP DROP ;

: SIGNED-AT { n x y -- }
   n 0< IF  x y MINUS-SPR @ SPR  n NEGATE  x 10 +  y NUMBER-AT  ELSE  n x y NUMBER-AT  THEN ;

: TIME-AT { s x y -- }      \ m:ss
   s 60 / x y NUMBER-AT
   s 60 / 9 > IF DIGIT-W @ 2* ELSE DIGIT-W @ THEN x + TO x
   x y COLON-SPR @ SPR
   COLON-SPR @ SPR-W x + TO x
   s 60 MOD 10 / x y NUMBER-AT
   s 60 MOD 10 MOD  x DIGIT-W @ +  y NUMBER-AT ;

: SQUARE-SPR { x y | c -- spr }
   PAUSED @ IF  K-COVER SPRITE EXIT  THEN
   x y SQ C@ TO c
   c BOOM-B AND IF
      x HIT-X @ =  y HIT-Y @ = AND IF K-HIT ELSE K-MINE THEN SPRITE EXIT
   THEN
   c OPEN-B AND IF  c $0F AND SPRITE EXIT  THEN
   c BUOY-B AND IF
      LOST @  c MINE-B AND 0= AND IF K-WRONG ELSE K-BUOY THEN SPRITE EXIT
   THEN
   K-COVER SPRITE ;

: DRAW-BOARD ( -- )
   C-LINE COLOR!  BX0 3 -  BY0 3 -  BW CS * 6 +  BH CS * 6 +  FILL-RECT
   BH 0 DO BW 0 DO
      I CS * BX0 +  J CS * BY0 +  I J SQUARE-SPR  SPR
   LOOP LOOP ;

: DRAW-CURSOR ( -- )
   PLAYING? CUR-ON @ AND 0= IF EXIT THEN
   CUR-X @ CS * BX0 +  CUR-Y @ CS * BY0 +  CS CS C-LIT OUTLINE ;

: DRAW-BUTTON { x y rw rh art -- }
   x y rw rh  x y rw rh IN-RECT? IF C-LIT ELSE C-LINE THEN  OUTLINE
   x rw art SPR-W - 2/ +   y rh art SPR-H - 2/ +  art SPR ;

: DRAW-BAR ( -- )
   16 12 LEVEL @ CELLS LEVEL-NAMES + @ SPR
   210 17 L-MINES @ SPR
   #MINES #BUOYS @ -  310 13 SIGNED-AT
   400 17 L-TIME @ SPR
   TIME-S 450 13 TIME-AT
   BTN-NEW L-NEW @ DRAW-BUTTON
   BTN-TITLE L-TITLE-B @ DRAW-BUTTON
   L-HELP @ CENTER-X 616 L-HELP @ SPR ;

: DRAW-RESULT ( -- )
   C-BAR COLOR!  220 220 360 210 FILL-RECT
   220 220 360 210 C-LINE OUTLINE
   LOST @ IF R-HIT @ ELSE R-CLEAR @ THEN  DUP CENTER-X 236 ROT SPR
   340 310 L-TIME @ SPR
   FINAL @ 1000000 / 400 306 TIME-AT
   RECORD? @ IF  R-RECORD @ CENTER-X 340 R-RECORD @ SPR  THEN
   BTN-AGAIN L-AGAIN @ DRAW-BUTTON
   BTN-BACK L-TITLE-B @ DRAW-BUTTON ;

: DRAW-SWEEP { | a x y c -- }
   400 RADAR-R -  135 RADAR-ART @ SPR
   10 0 DO
      CLOCK @ 2/ I - TO a
      C-SONAR $0A2436  I 25 *  MIX-RGB TO c
      RADAR-R 2 - 2 DO
         a COS64 I * 1024 / 400 + TO x
         a SIN64 I * 1024 / 205 + TO y
         x DUP 1+ y c GFX-HLINE
      LOOP
   LOOP ;

\ Where the sonar finds something on the title: angle, distance.
CREATE BLIPS  5 , 40 ,  14 , 58 ,  23 , 28 ,  36 , 52 ,  46 , 34 ,  57 , 60 ,
: DRAW-BLIPS { | a r d c -- }
   6 0 DO
      I 2* CELLS BLIPS + @ TO a
      I 2* 1+ CELLS BLIPS + @ TO r
      CLOCK @ 2/ a - 63 AND TO d
      d 32 < IF
         $0A2436 C-SONAR  255 d 8 * -  MIX-RGB COLOR!
         a COS64 r * 1024 / 400 +   a SIN64 r * 1024 / 205 +   3 FILL-CIRCLE
      THEN
   LOOP ;

: DRAW-ROW { n | y0 -- }
   n ROW-Y TO y0
   n ROW-RECT  n SEL @ = IF C-LIT ELSE C-LINE THEN  OUTLINE
   210 y0 6 + n CELLS LEVEL-NAMES + @ SPR
   210 y0 42 + n CELLS LEVEL-NOTES + @ SPR
   470 y0 12 + L-BEST @ SPR
   n CELLS BESTS + @ DUP 0< IF
      DROP  470 y0 38 + L-NONE @ SPR
   ELSE
      470 y0 34 + TIME-AT
   THEN ;

: DRAW-TITLE ( -- )
   T-TITLE @ CENTER-X 28 T-TITLE @ SPR
   DRAW-SWEEP  DRAW-BLIPS
   #LEVELS 0 DO  I DRAW-ROW  LOOP
   T-HELP1 @ CENTER-X 546 T-HELP1 @ SPR
   T-HELP2 @ CENTER-X 572 T-HELP2 @ SPR
   T-HELP3 @ CENTER-X 598 T-HELP3 @ SPR ;

: RENDER ( -- )
   C-BAR GFX-CLS
   GMODE @ M-TITLE = IF  DRAW-TITLE  EXIT  THEN
   DRAW-BOARD  DRAW-CURSOR  DRAW-BAR  DRAW-RINGS  DRAW-SPARKS
   PAUSED @ IF  L-PAUSE @ CENTER-X 320 L-PAUSE @ SPR  THEN
   GMODE @ M-RESULT = IF DRAW-RESULT THEN ;

\ ---- The steps ---------------------------------------------------------------------

: TICK-GAME ( -- )
   1 CLOCK +!
   PAUSED @ IF EXIT THEN
   STEP-SPARKS  STEP-RINGS
   GMODE @ M-END = IF STEP-END THEN ;

: GAME-STEP ( -- )   READ-KEYS  READ-MOUSE  TICK-GAME  RENDER ;

: INIT-GAME ( -- )
   NOW SEED !  FALSE DONE !  0 OLD-B !  0 SEL !
   -1 MX !  -1 MY !
   #LEVELS 0 DO  -1 BESTS I CELLS + !  LOOP
   0 LOAD-LEVEL
   TO-TITLE ;

: SONAR-SWEEP ( -- )
   BAKE-ALL  MAKE-SOUNDS
   W H GFX-INIT  MOUSE-ON
   INIT-GAME
   BEGIN  GAME-STEP  16 FRAME  DONE @ UNTIL
   MOUSE-OFF ;

[UNDEFINED] NO-AUTORUN [IF] SONAR-SWEEP BYE [THEN]
