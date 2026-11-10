\ Ninth Inning: a pinball table of a ballpark, on painted wood, in a window.
\ The table follows a picture of an old wooden table that レモン gave; the pictures,
\ the sounds, the names and the rules are this file's own.
\
\   sigma.exe examples/pinball.fs       (in a window; Tk on Linux/macOS)
\
\ Flippers: Z or the left arrow or the left mouse button, and / or the right arrow or
\ the right mouse button. Plunger: hold Space or the down arrow (or a mouse button while
\ the ball waits) and let go. P pauses, R starts again, Q or Esc ends the game.
\
\ The four lanes at the top spell ABCD; all four raise the bonus multiplier (2X, 3X,
\ 5X, 10X), and the flippers move the lit lanes. The four drop targets on the left spell
\ BASE: all four down is a base hit. The three targets in the middle make a double and
\ light the dugout, the hole under the bumpers: a ball in the lit dugout is a home run,
\ and in the dark one a stolen base. Every runner who reaches home scores a run, and
\ every fifth run lights the extra ball at the kickout hole on the right. The runners,
\ the targets and the lanes stay from ball to ball. The bonus is counted, times the
\ multiplier, when the ball drains.

REQUIRE-GRAPHICS  ALSO GRAPHICS

\ ---- Sound ------------------------------------------------------------------------

: AUDIO-LOADED? ( -- flag )   S" REQUIRE-AUDIO" ['] EVALUATE CATCH  DUP IF NIP NIP THEN  0= ;
[UNDEFINED] NO-SOUND [IF] AUDIO-LOADED? [ELSE] FALSE [THEN] CONSTANT HAS-SOUND

0 CONSTANT S-FLIP   1 CONSTANT S-BUMP   2 CONSTANT S-HIT    3 CONSTANT S-DROP
4 CONSTANT S-KICK   5 CONSTANT S-HOLE   6 CONSTANT S-LANE   7 CONSTANT S-CROWD

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
   BLANK-WAVE  0 500 120 180 SWISH                           500 S-FLIP KEEP-WAVE
   BLANK-WAVE  0 900 12 70 BLOOP                             900 S-BUMP KEEP-WAVE
   BLANK-WAVE  0 1600 6 60 CHIME  500 1100 4 50 CHIME       1600 S-HIT KEEP-WAVE
   BLANK-WAVE  0 700 9 60 CHIME                              700 S-DROP KEEP-WAVE
   BLANK-WAVE  0 1400 100 240 SWISH                         1400 S-KICK KEEP-WAVE
   BLANK-WAVE  0 1800 30 90 BLOOP                           1800 S-HOLE KEEP-WAVE
   BLANK-WAVE  0 1100 5 50 CHIME  300 800 4 40 CHIME        1100 S-LANE KEEP-WAVE
   BLANK-WAVE  0 9000 18 200 SWISH  0 9000 60 12 CHIME      9000 S-CROWD KEEP-WAVE ;
PREVIOUS
[ELSE]
: EFFECT ( k -- )   DROP ;
: JINGLE ( c-addr u -- )   2DROP ;
: MAKE-SOUNDS ( -- ) ;
[THEN]

\ ---- Numbers -----------------------------------------------------------------------

800 CONSTANT W          \ the image
800 CONSTANT H
560 CONSTANT TW         \ the table; the score card is to the right of it

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

4096 CONSTANT FX

CREATE QUARTER  0 , 100 , 200 , 297 , 392 , 483 , 569 , 650 , 724 , 792 , 851 , 903 , 946 , 980 , 1004 , 1019 , 1024 ,
: SIN64 { k | s -- v }
   k 63 AND TO k   1 TO s
   k 31 > IF  k 32 - TO k  -1 TO s  THEN
   k 16 > IF  32 k - TO k  THEN
   k CELLS QUARTER + @  s * ;
\ A sine and a cosine of angles of 4096 to the circle, as multiples of FX.
: SINT { a | k fr v0 -- v }
   a 4095 AND TO a   a 64 / TO k   a 63 AND TO fr
   k SIN64 TO v0
   k 1+ SIN64 v0 - fr * 64 / v0 +  4 * ;
: COST ( a -- v )   1024 + SINT ;

\ ---- Sprites ------------------------------------------------------------------------
\ A sprite: an image, its width, and its height. BAKE makes the image from xt
\ ( x y -- rgb | -1 ), which reads the picture painted on the image drawn on; -1 is a
\ hole, kept in the image as KEY-COLOR, which SPR leaves out.

$FF00FE CONSTANT KEY-COLOR

: BAKE { pw ph xt | img old row a -- a }
   pw 1 MAX ph 1 MAX NEW-IMAGE TO img  DRAWING TO old  pw 1 MAX CELLS ALLOCATE THROW TO row
   ph 0 ?DO
      pw 0 ?DO  I J xt EXECUTE  DUP 0< IF DROP KEY-COLOR THEN  row I CELLS + !  LOOP
      img DRAW-TO  pw 0 ?DO  I J row I CELLS + @ GFX-PSET  LOOP  old DRAW-TO
   LOOP
   row FREE THROW
   ALIGN HERE TO a  img , pw , ph ,  a ;

: SPR-W ( a -- w )   CELL+ @ ;
: SPR-H ( a -- h )   2 CELLS + @ ;
: SPR { x y a -- }   a @ 0 0 a SPR-W a SPR-H x y KEY-COLOR 0 0 128 1 GFX-COPY ;
: CENTERED { cx cy a -- }   cx a SPR-W 2/ -  cy a SPR-H 2/ -  a SPR ;

\ ---- Painting tools ----------------------------------------------------------------
\ Pictures are painted larger than they are shown, in units of 64 to CS pixels.

$F2E6C8 CONSTANT C-PAPER    $3A2414 CONSTANT C-INK    $8A6A48 CONSTANT C-FADED
$2A1A10 CONSTANT C-DARK     $F0C060 CONSTANT C-GOLD

3 VALUE ZOOM
64 VALUE CS
: SCALED ( n -- n' )   CS ZOOM * *  64 / ;
: >CANVAS ( x y -- cx cy )   SCALED SWAP SCALED SWAP ;
: INK ( rgb -- )   COLOR! ;
: CANVAS-PX ( x y -- rgb | -1 )   GFX-PGET  DUP KEY-COLOR = IF DROP -1 THEN ;

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
\ A bar with round ends, in canvas units of the painting.
: BAR { x0 y0 x1 y1 r | dx dy d nx ny -- }
   x1 x0 - TO dx   y1 y0 - TO dy
   dx dx * dy dy * + ISQRT 1 MAX TO d
   dy NEGATE r * d / TO nx   dx r * d / TO ny
   [P x0 nx + y0 ny + DV  x1 nx + y1 ny + DV  x1 nx - y1 ny - DV  x0 nx - y0 ny - DV P]
   x0 y0 r DISC   x1 y1 r DISC ;

: ART-PX { x y | r g b n v -- rgb | -1 }
   x ZOOM * ZOOM 2/ +  y ZOOM * ZOOM 2/ +  GFX-PGET KEY-COLOR = IF -1 EXIT THEN
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
: ART-BEGIN ( side -- )   TO CS  KEY-COLOR GFX-CLS ;
: ART-DONE ( -- spr )   CS CS ['] ART-PX BAKE ;

: USE-FONT ( height -- )
   >R S" Georgia" R@ ['] SYSTEM-FONT CATCH
   IF  2DROP DROP  BUILTIN-FONT  R> 8 / 1 MAX TEXT-SCALE
   ELSE  R> DROP  1 TEXT-SCALE  THEN ;
: USE-PLAIN ( height -- )
   >R S" Segoe UI Semibold" R@ ['] SYSTEM-FONT CATCH
   IF  2DROP DROP  BUILTIN-FONT  R> 8 / 1 MAX TEXT-SCALE
   ELSE  R> DROP  1 TEXT-SCALE  THEN ;
: DIGIT$ ( n -- c-addr 1 )   S" 0123456789" DROP + 1 ;

\ Text centered on x y of the painting.
: LABEL { a u x y c -- }
   c INK  a u  x SCALED a u TEXT-WIDTH 2/ -  y SCALED TEXT-HEIGHT 2/ -  TEXT ;

: TEXT-SPRITE { a u fg bg | pw ph -- spr }
   a u TEXT-WIDTH TO pw   TEXT-HEIGHT TO ph
   bg GFX-CLS  fg INK  a u 0 0 TEXT
   pw ph ['] CANVAS-PX BAKE ;
: PAPER ( a u -- spr )   C-INK C-PAPER TEXT-SPRITE ;
: FADED ( a u -- spr )   C-FADED C-PAPER TEXT-SPRITE ;

\ ---- The table: its walls ----------------------------------------------------------
\ Positions and speeds are multiples of FX; speeds are per step, 8 steps to a frame.

8 CONSTANT SUBSTEPS
9 FX * CONSTANT BALL-R
2 FX * CONSTANT WALL-R
16 CONSTANT GRAVITY

0 CONSTANT K-WALL    1 CONSTANT K-SLING   2 CONSTANT K-GATE   3 CONSTANT K-STAR   4 CONSTANT K-KICKER
5 CONSTANT K-TGT     \ 5 to 7 the three targets in the middle
8 CONSTANT K-DROP    \ 8 to 11 the four drop targets

200 CONSTANT MAX-SEGS
10 CONSTANT SEG-CELLS
CREATE SEGS MAX-SEGS SEG-CELLS * CELLS ALLOT    VARIABLE #SEGS
\ x0 y0 ux uy length xlo ylo xhi yhi kind
: SEG[] ( n -- a )   SEG-CELLS * CELLS SEGS + ;

: ADD-SEG { x0 y0 x1 y1 kind | a dx dy d m -- }
   #SEGS @ SEG[] TO a
   x1 x0 - TO dx   y1 y0 - TO dy
   dx dx * dy dy * + ISQRT 1 MAX TO d
   BALL-R WALL-R + 4096 + TO m
   x0 a !   y0 a CELL+ !
   dx FX * d /  a 2 CELLS + !    dy FX * d /  a 3 CELLS + !
   d a 4 CELLS + !
   x0 x1 MIN m -  a 5 CELLS + !   y0 y1 MIN m -  a 6 CELLS + !
   x0 x1 MAX m +  a 7 CELLS + !   y0 y1 MAX m +  a 8 CELLS + !
   kind a 9 CELLS + !
   1 #SEGS +! ;
: LN { x0 y0 x1 y1 kind -- }   x0 FX * y0 FX * x1 FX * y1 FX * kind ADD-SEG ;

: ARC { cx cy r a0 a1 n kind -- }
   n 0 DO
      a1 a0 - I * n / a0 + { p }
      a1 a0 - I 1+ * n / a0 + { q }
      cx FX * r p COST * +   cy FX * r p SINT * +
      cx FX * r q COST * +   cy FX * r q SINT * +
      kind ADD-SEG
   LOOP ;

: MIRROR-X ( x -- x' )   528 SWAP - ;
: LN2 { x0 y0 x1 y1 kind -- }      \ a line and its mirror image about the middle of the field
   x0 y0 x1 y1 kind LN   x0 MIRROR-X y0 x1 MIRROR-X y1 kind LN ;

\ The corners of the pieces on the field.
372 CONSTANT TA-X   330 CONSTANT TA-Y      \ the three targets: from A to C
440 CONSTANT TB-X   316 CONSTANT TB-Y
420 CONSTANT TC-X   366 CONSTANT TC-Y
184 CONSTANT BANK-X  350 CONSTANT BANK-Y  24 CONSTANT BANK-STEP    \ the drop targets
: TGT-PT ( k -- x y )   \ the point k thirds of the way from A to C
   >R  TC-X TA-X - R@ * 3 / TA-X +   TC-Y TA-Y - R> * 3 / TA-Y + ;

: BUILD-WALLS ( -- )
   0 #SEGS !
   281 281 257 2048 4096 32 K-WALL ARC
   24 281 24 812 K-WALL LN
   538 281 538 812 K-WALL LN
   504 235 504 812 K-WALL LN
   504 776 538 776 K-WALL LN            \ the plunger's stop
   504 235 504 153 K-GATE LN
   \ the painted kicker at the top left
   72 206 140 140 K-WALL LN
   140 140 132 244 K-KICKER LN
   132 244 72 206 K-WALL LN
   \ the lanes A B C D, and the star at their right
   170 96 170 140 K-WALL LN   214 96 214 140 K-WALL LN
   258 96 258 140 K-WALL LN   302 96 302 140 K-WALL LN
   346 96 346 150 K-WALL LN
   346 96 388 132 K-STAR LN
   388 132 346 150 K-WALL LN
   \ the three targets and the wedge behind them
   3 0 DO  I TGT-PT  I 1+ TGT-PT  K-TGT I + LN  LOOP
   TA-X TA-Y TB-X TB-Y K-WALL LN
   TB-X TB-Y TC-X TC-Y K-WALL LN
   \ the bank of drop targets and its back; the way up the middle stays open
   4 0 DO  BANK-X BANK-Y I BANK-STEP * +  BANK-X BANK-Y I 1+ BANK-STEP * +  K-DROP I + LN  LOOP
   BANK-X BANK-Y 196 346 K-WALL LN
   BANK-X 446 196 446 K-WALL LN
   196 346 196 446 K-WALL LN
   \ the guides that turn a ball coming down a side wall in to the field
   24 318 70 352 K-WALL LN2
   \ the two small kickers at the sides
   88 388 88 452 K-WALL LN2
   88 452 126 452 K-WALL LN2
   88 388 126 452 K-KICKER LN2
   \ the rails beside the flippers: in line with a flipper at rest, their face in line
   \ with its face, and ending over its pivot, so that the ball rolls straight on to the
   \ flipper and does not stop between a rail and a pivot
   58 600 58 639 K-WALL LN2
   58 639 183 695 K-WALL LN2
   \ the ways from the outlanes, under the rails and the flippers, to the drain
   24 700 204 772 K-WALL LN2
   \ the slingshots
   128 552 128 617 K-WALL LN2
   128 617 188 660 K-WALL LN2
   128 552 188 660 K-SLING LN2 ;

\ ---- The ball, the flippers and the rest of what moves ------------------------------

VARIABLE BX   VARIABLE BY   VARIABLE VX   VARIABLE VY
VARIABLE NX   VARIABLE NY   VARIABLE LAST-VN   VARIABLE LAST-T
VARIABLE FLIP-W   VARIABLE FLIP-SIN   VARIABLE FLIP-COS   VARIABLE FLIP-MIR

0 CONSTANT B-LANE   1 CONSTANT B-ROLL   2 CONSTANT B-HOLD
VARIABLE BSTATE    VARIABLE LANE-OPEN

\ Flippers: 0 left, 1 right. The angle is 0 level, positive down.
70 FX * CONSTANT FLIP-LEN
273 CONSTANT ANG-REST
-319 CONSTANT ANG-UP
26 CONSTANT FLIP-SPEED
CREATE FL-ANG 2 CELLS ALLOT
CREATE FL-DELTA 2 CELLS ALLOT
CREATE FL-HELD 2 CELLS ALLOT
: PIVOT-X ( n -- fx )   IF 347 ELSE 181 THEN FX * ;
: PIVOT-Y ( n -- fx )   DROP 700 FX * ;
: MIR-OF ( n -- m )   IF -1 ELSE 1 THEN ;

\ The contact: pushes the ball out, reflects its speed against a moving surface.
: RESOLVE { px py d r e pvx pvy | vn imp -- }
   d 0= IF  0 NX !  FX NEGATE NY !
   ELSE  px FX * d / NX !   py FX * d / NY !  THEN
   r d - NX @ * FX / BX +!
   r d - NY @ * FX / BY +!
   VX @ pvx - NX @ *  VY @ pvy - NY @ * +  FX /  TO vn
   vn LAST-VN !
   vn 0< IF
      vn FX e + * FX /  TO imp
      imp NX @ * FX / NEGATE VX +!
      imp NY @ * FX / NEGATE VY +!
   THEN ;

: HIT-LINE { x0 y0 ux uy len r e | rx ry t cx cy dx dy d2 pv pvx pvy -- hit? }
   BX @ x0 - TO rx   BY @ y0 - TO ry
   rx ux *  ry uy * + FX / TO t
   t 0 MAX len MIN TO t
   x0 ux t * FX / + TO cx
   y0 uy t * FX / + TO cy
   BX @ cx - TO dx    BY @ cy - TO dy
   dx dx *  dy dy * + TO d2
   d2 r r * >= IF FALSE EXIT THEN
   t LAST-T !
   FLIP-W @ IF
      t FLIP-W @ * FX / TO pv
      FLIP-MIR @ NEGATE FLIP-SIN @ * pv * FX / TO pvx
      FLIP-COS @ pv * FX / TO pvy
   THEN
   dx dy d2 ISQRT r e pvx pvy RESOLVE
   TRUE ;

: HIT-CIRCLE { cx cy cr e | dx dy r d2 -- hit? }
   BX @ cx - TO dx   BY @ cy - TO dy
   cr BALL-R + TO r
   dx ABS r >= IF FALSE EXIT THEN
   dy ABS r >= IF FALSE EXIT THEN
   dx dx * dy dy * + TO d2
   d2 r r * >= IF FALSE EXIT THEN
   dx dy d2 ISQRT r e 0 0 RESOLVE
   TRUE ;

: KICK ( k -- )  { k }  NX @ k * FX / VX +!   NY @ k * FX / VY +! ;

\ ---- The ballpark: what the game keeps ----------------------------------------------

0 CONSTANT M-TITLE   1 CONSTANT M-PLAY   2 CONSTANT M-OVER
VARIABLE GMODE   VARIABLE DONE   VARIABLE PAUSED   VARIABLE CLOCK
VARIABLE SCORE   VARIABLE BEST   VARIABLE BALL-NO  VARIABLE EXTRA
VARIABLE BONUS   VARIABLE MULT-I VARIABLE RUNS     VARIABLE RUNNERS
VARIABLE HR-LIT  VARIABLE EB-LIT VARIABLE HOME-FLASH
VARIABLE SAFE-T  VARIABLE STILL-T
VARIABLE CHARGE  VARIABLE LOCK-INPUT
VARIABLE IN-L    VARIABLE IN-R     VARIABLE IN-P
VARIABLE SHIELD-OK

CREATE MULTS  1 , 2 , 3 , 5 , 10 ,
: MULT ( -- n )   MULT-I @ CELLS MULTS + @ ;

4 CONSTANT #BUMP
CREATE BUMP-X  165 , 258 , 405 , 364 ,
CREATE BUMP-Y  290 , 222 , 186 , 272 ,
CREATE BUMP-VAL 100 , 100 , 500 , 500 ,
CREATE BUMP-COOL  #BUMP CELLS ALLOT
CREATE BUMP-FLASH #BUMP CELLS ALLOT
25 FX * CONSTANT BUMP-R

CREATE LANE-LIT 4 CELLS ALLOT   CREATE LANE-IN 4 CELLS ALLOT
CREATE LANE-X  192 , 236 , 280 , 324 ,
120 CONSTANT LANE-Y
CREATE DROP-UP 4 CELLS ALLOT    VARIABLE BANK-RESET
CREATE TGT-LIT 3 CELLS ALLOT    VARIABLE TGT-RESET   VARIABLE TGT-COOL
VARIABLE STAR-COOL   VARIABLE STAR-FLASH   VARIABLE SLING-COOL
CREATE ROLL-IN 4 CELLS ALLOT    \ the inlanes and outlanes: left in, left out, right in, right out

\ The two holes: the dugout under the bumpers and the kickout hole on the right.
250 CONSTANT DUG-X    312 CONSTANT DUG-Y
352 CONSTANT KICK-X   470 CONSTANT KICK-Y
VARIABLE HOLE-NO   VARIABLE HOLE-COOL   VARIABLE HOLD-T

\ Sparks.
64 CONSTANT #SPARKS
CREATE SPARKS #SPARKS 6 * CELLS ALLOT
VARIABLE NEXT-SPARK
: SPARK[] ( n -- a )   6 * CELLS SPARKS + ;
: SPARK { x y dx dy life c | a -- }
   NEXT-SPARK @ SPARK[] TO a
   x 16 * a !  y 16 * a CELL+ !  dx a 2 CELLS + !  dy a 3 CELLS + !  life a 4 CELLS + !  c a 5 CELLS + !
   NEXT-SPARK @ 1+ #SPARKS MOD NEXT-SPARK ! ;
: BURST { x y n spread c -- }
   n 0 DO
      x y  spread 2* 1+ RND spread -  spread 2* 1+ RND spread -  14 20 RND +  c SPARK
   LOOP ;

\ The messages on the score card.
24 CONSTANT #MSG
CREATE MSG-ART #MSG CELLS ALLOT   VARIABLE MSG-NOW   VARIABLE MSG-T
0 CONSTANT TX-PLAY      1 CONSTANT TX-SINGLE   2 CONSTANT TX-DOUBLE   3 CONSTANT TX-HOMER
4 CONSTANT TX-STEAL     5 CONSTANT TX-RUN      6 CONSTANT TX-MULT     7 CONSTANT TX-EB-LIT
8 CONSTANT TX-EB        9 CONSTANT TX-SAVE    10 CONSTANT TX-OUT     11 CONSTANT TX-KICK
12 CONSTANT TX-STAR    13 CONSTANT TX-AGAIN   14 CONSTANT TX-BONUS   15 CONSTANT TX-LANE
16 CONSTANT TX-OUTLANE 17 CONSTANT TX-HR-LIT
: MSG$ ( n -- a u )
   CASE
      TX-PLAY OF S" Play ball!" ENDOF
      TX-SINGLE OF S" BASE: a base hit!" ENDOF
      TX-DOUBLE OF S" A double!" ENDOF
      TX-HOMER OF S" Home run!" ENDOF
      TX-STEAL OF S" A stolen base." ENDOF
      TX-RUN OF S" A run scores!" ENDOF
      TX-MULT OF S" ABCD: the bonus multiplier rises." ENDOF
      TX-EB-LIT OF S" The extra ball is lit." ENDOF
      TX-EB OF S" Extra ball!" ENDOF
      TX-SAVE OF S" The ball is saved." ENDOF
      TX-OUT OF S" Out! The next batter is up." ENDOF
      TX-KICK OF S" Into the kickout hole." ENDOF
      TX-STAR OF S" The star!" ENDOF
      TX-AGAIN OF S" Shoot again!" ENDOF
      TX-BONUS OF S" The bonus is counted." ENDOF
      TX-LANE OF S" A lane is lit." ENDOF
      TX-OUTLANE OF S" Down the outlane..." ENDOF
      TX-HR-LIT OF S" The dugout is lit: home run!" ENDOF
      S" " ROT
   ENDCASE ;
: SAY ( n -- )   MSG-NOW !  200 MSG-T ! ;

: +SCORE ( n -- )   SCORE +! ;
: +BONUS ( n -- )   BONUS @ + 99 MIN BONUS ! ;

: RUN-SCORES ( -- )
   1 RUNS +!  5000 +SCORE  2 +BONUS  40 HOME-FLASH !
   264 634 16 20 $F8F0D0 BURST
   RUNS @ 5 MOD 0= IF  TRUE EB-LIT !  TX-EB-LIT SAY  THEN ;

\ The runners: bit 0 on first base, 1 on second, 2 on third. A hit of n bases moves
\ each runner n bases and, with batter?, puts the batter on base too.
: ADVANCE { n batter? | r -- }
   RUNNERS @ 2*  batter? IF 1 OR THEN  n LSHIFT TO r
   r 4 RSHIFT  BEGIN DUP WHILE  DUP 1 AND IF RUN-SCORES THEN  1 RSHIFT  REPEAT DROP
   r 1 RSHIFT 7 AND RUNNERS ! ;

: DROP-HIT { n -- }
   DROP-UP n CELLS + @ 0= IF EXIT THEN
   FALSE DROP-UP n CELLS + !
   500 +SCORE  1 +BONUS  S-DROP EFFECT
   4 0 DO  DROP-UP I CELLS + @ IF UNLOOP EXIT THEN  LOOP
   TX-SINGLE SAY  2000 +SCORE  S-HIT EFFECT
   1 TRUE ADVANCE
   190 400 16 24 $F8E070 BURST
   60 BANK-RESET ! ;
: RESET-BANK ( -- )   4 0 DO  TRUE DROP-UP I CELLS + !  LOOP  0 BANK-RESET ! ;

: TGT-HIT { n -- }
   TGT-COOL @ 0> IF EXIT THEN
   10 TGT-COOL !
   TGT-LIT n CELLS + @ IF  100 +SCORE  S-DROP EFFECT  EXIT  THEN
   TRUE TGT-LIT n CELLS + !
   300 +SCORE  1 +BONUS  S-DROP EFFECT
   3 0 DO  TGT-LIT I CELLS + @ 0= IF UNLOOP EXIT THEN  LOOP
   TX-DOUBLE SAY  3000 +SCORE  S-HIT EFFECT
   2 TRUE ADVANCE
   HR-LIT @ 0= IF  TRUE HR-LIT !  TX-HR-LIT SAY  THEN
   396 350 16 24 $F8F8F8 BURST
   40 TGT-RESET ! ;
: RESET-TARGETS ( -- )   3 0 DO  FALSE TGT-LIT I CELLS + !  LOOP  0 TGT-RESET ! ;

: STAR-HIT ( -- )
   STAR-COOL @ 0> IF EXIT THEN
   20 STAR-COOL !  30 STAR-FLASH !
   1000 +SCORE  1 +BONUS  S-LANE EFFECT
   360 126 10 16 $FF6040 BURST ;

: LANE-HIT { n -- }
   LANE-LIT n CELLS + @ 0= IF
      TRUE LANE-LIT n CELLS + !
      500 +SCORE  1 +BONUS  S-LANE EFFECT
   ELSE  100 +SCORE  THEN
   4 0 DO  LANE-LIT I CELLS + @ 0= IF UNLOOP EXIT THEN  LOOP
   MULT-I @ 4 < IF  1 MULT-I +!  THEN
   TX-MULT SAY  3000 +SCORE  S-HIT EFFECT
   258 130 16 30 $F8E070 BURST
   4 0 DO  FALSE LANE-LIT I CELLS + !  LOOP ;

\ The flippers move the lit lanes to the left or to the right.
: LANES-LEFT ( -- )
   LANE-LIT @  3 0 DO  LANE-LIT I 1+ CELLS + @  LANE-LIT I CELLS + !  LOOP  LANE-LIT 3 CELLS + ! ;
: LANES-RIGHT ( -- )
   LANE-LIT 3 CELLS + @  0 2 DO  LANE-LIT I CELLS + @  LANE-LIT I 1+ CELLS + !  -1 +LOOP  LANE-LIT ! ;

\ ---- Collision of one step ----------------------------------------------------------

: DROP-ACTIVE? ( kind -- f )   K-DROP - CELLS DROP-UP + @ ;

: ON-SEG { kind -- }
   kind K-SLING = IF
      LAST-VN @ -1200 < SLING-COOL @ 0= AND IF
         2800 KICK  10 +SCORE  8 SLING-COOL !  S-KICK EFFECT
      THEN EXIT
   THEN
   kind K-KICKER = IF
      LAST-VN @ -1200 < SLING-COOL @ 0= AND IF
         2400 KICK  50 +SCORE  8 SLING-COOL !  S-KICK EFFECT
      THEN EXIT
   THEN
   kind K-STAR = IF  LAST-VN @ -300 < IF STAR-HIT THEN  EXIT  THEN
   kind K-DROP >= IF  LAST-VN @ -300 < IF  kind K-DROP - DROP-HIT  THEN  EXIT  THEN
   kind K-TGT >= IF  LAST-VN @ -300 < IF  kind K-TGT - TGT-HIT  THEN  EXIT  THEN ;

: TEST-SEGS ( -- )
   #SEGS @ 0 DO
      I SEG[] { a }
      BX @ a 5 CELLS + @ >  BX @ a 7 CELLS + @ < AND
      BY @ a 6 CELLS + @ > AND  BY @ a 8 CELLS + @ < AND IF
         a 9 CELLS + @ { kind }
         kind K-GATE = LANE-OPEN @ AND
         kind K-DROP >= IF  kind DROP-ACTIVE? 0= OR  THEN
         0= IF
            a @  a CELL+ @  a 2 CELLS + @  a 3 CELLS + @  a 4 CELLS + @
            BALL-R WALL-R +  1720  HIT-LINE IF  kind ON-SEG  THEN
         THEN
      THEN
   LOOP ;

: BUMP { n -- }
   n CELLS BUMP-COOL + @ 0> IF EXIT THEN
   8 n CELLS BUMP-COOL + !
   12 n CELLS BUMP-FLASH + !
   3584 KICK
   n CELLS BUMP-VAL + @ +SCORE
   S-BUMP EFFECT ;

: TEST-BUMPERS ( -- )
   #BUMP 0 DO
      I CELLS BUMP-X + @ FX *  I CELLS BUMP-Y + @ FX *  BUMP-R  1200  HIT-CIRCLE IF  I BUMP  THEN
   LOOP ;

: STEP-FLIPPER { n | a d -- }
   n CELLS FL-ANG + @ TO a
   n CELLS FL-HELD + @ IF
      a FLIP-SPEED - ANG-UP MAX
   ELSE
      a FLIP-SPEED 3 * 4 / + ANG-REST MIN
   THEN
   DUP a - n CELLS FL-DELTA + !
   n CELLS FL-ANG + ! ;

: TEST-FLIPPER { n | a s c mir -- }
   n CELLS FL-ANG + @ TO a
   a SINT TO s   a COST TO c
   n MIR-OF TO mir
   s FLIP-SIN !  c FLIP-COS !  mir FLIP-MIR !
   n CELLS FL-DELTA + @ 6283 * 1000 / FLIP-W !
   n PIVOT-X  n PIVOT-Y  mir c *  s  FLIP-LEN  BALL-R 7 FX * +  2048  HIT-LINE DROP
   0 FLIP-W ! ;

: CLAMP-SPEED { | s2 s -- }
   VX @ DUP * VY @ DUP * + TO s2
   s2 15000 15000 * > IF
      s2 ISQRT TO s
      VX @ 15000 * s / VX !
      VY @ 15000 * s / VY !
   THEN ;

: STEP-BALL ( -- )
   GRAVITY VY +!
   VX @ BX +!  VY @ BY +!
   TEST-SEGS  TEST-BUMPERS
   0 TEST-FLIPPER  1 TEST-FLIPPER
   CLAMP-SPEED ;

: STEP-PHYSICS ( -- )
   SUBSTEPS 0 DO
      0 STEP-FLIPPER  1 STEP-FLIPPER
      BSTATE @ B-HOLD <> IF  STEP-BALL  THEN
   LOOP ;

\ ---- Once a frame -------------------------------------------------------------------

: SENSOR-X ( -- x )   BX @ FX / ;
: SENSOR-Y ( -- y )   BY @ FX / ;

: CHECK-LANES ( -- )
   4 0 DO
      SENSOR-X I CELLS LANE-X + @ - ABS 12 <
      SENSOR-Y LANE-Y - ABS 14 < AND IF
         LANE-IN I CELLS + @ 0= IF  I LANE-HIT  THEN
         TRUE LANE-IN I CELLS + !
      ELSE
         FALSE LANE-IN I CELLS + !
      THEN
   LOOP ;

\ The rollovers in the inlanes and the outlanes: n is 0 1 on the left, 2 3 on the right.
: IN-ROLL? ( x0 x1 y0 y1 -- f )   SENSOR-Y -ROT WITHIN >R  SENSOR-X -ROT WITHIN R> AND ;
: ROLL-AT? { n -- f }
   n 2 MOD IF 26 56 ELSE 62 124 THEN          \ the x of the left side
   n 2 >= IF  MIRROR-X SWAP MIRROR-X  THEN
   600 616 IN-ROLL? ;
: ROLL-HIT { n -- }
   n 2 MOD IF
      1000 +SCORE  TX-OUTLANE SAY  S-DROP EFFECT
   ELSE
      500 +SCORE  1 +BONUS  S-LANE EFFECT
   THEN ;
: CHECK-ROLLS ( -- )
   BSTATE @ B-ROLL <> IF EXIT THEN
   4 0 DO
      I ROLL-AT? IF
         ROLL-IN I CELLS + @ 0= IF  I ROLL-HIT  THEN
         TRUE ROLL-IN I CELLS + !
      ELSE  FALSE ROLL-IN I CELLS + !  THEN
   LOOP ;

: HOLE-X ( n -- x )   IF KICK-X ELSE DUG-X THEN ;
: HOLE-Y ( n -- y )   IF KICK-Y ELSE DUG-Y THEN ;

: ENTER-HOLE { n -- }
   B-HOLD BSTATE !
   n HOLE-NO !
   n HOLE-X FX * BX !   n HOLE-Y FX * BY !
   0 VX !  0 VY !
   70 HOLD-T !
   S-HOLE EFFECT ;

: CHECK-HOLES { | dx dy s2 -- }
   BSTATE @ B-ROLL <> HOLE-COOL @ 0> OR IF EXIT THEN
   VX @ DUP * VY @ DUP * + TO s2
   s2 4096 2* 4096 2* * >= IF EXIT THEN
   2 0 DO
      BX @ I HOLE-X FX * - TO dx
      BY @ I HOLE-Y FX * - TO dy
      dx ABS 11 FX * <  dy ABS 11 FX * < AND IF  I ENTER-HOLE UNLOOP EXIT  THEN
   LOOP ;

: AWARD-HOLE ( -- )
   HOLE-NO @ 0= IF
      HR-LIT @ IF
         FALSE HR-LIT !
         TX-HOMER SAY  10000 +SCORE  3 +BONUS
         4 TRUE ADVANCE
         S-CROWD EFFECT  S" T200 L16 O4 GG>CEG8E16G4" JINGLE
         DUG-X DUG-Y 40 40 $F8E070 BURST
      ELSE
         TX-STEAL SAY  1000 +SCORE  1 +BONUS
         1 FALSE ADVANCE
         S-LANE EFFECT
      THEN
   ELSE
      EB-LIT @ IF
         FALSE EB-LIT !  1 EXTRA +!
         TX-EB SAY  5000 +SCORE
         S-CROWD EFFECT  S" T180 L16 O5 CEGC>" JINGLE
         KICK-X KICK-Y 30 30 $70F090 BURST
      ELSE
         TX-KICK SAY  1500 +SCORE  1 +BONUS
         S-DROP EFFECT
      THEN
   THEN ;

: LET-GO ( -- )          \ out of the hole
   B-ROLL BSTATE !
   60 HOLE-COOL !
   HOLE-NO @ 0= IF
      1200 RND 4800 - VX !   5000 NEGATE 1500 RND - VY !      \ up and to the left
   ELSE
      1600 RND 5200 - VX !   8000 NEGATE 2000 RND - VY !
   THEN
   S-KICK EFFECT ;

: STEP-HOLD ( -- )
   -1 HOLD-T +!
   HOLD-T @ 40 = IF AWARD-HOLE THEN
   HOLD-T @ 0= IF LET-GO THEN ;

: RESET-BALL ( -- )
   521 FX * BX !  760 FX * BY !  0 VX !  0 VY !
   B-LANE BSTATE !   TRUE LANE-OPEN !   0 CHARGE !  0 STILL-T ! ;

: GAME-OVER ( -- )
   SCORE @ BEST @ MAX BEST !
   M-OVER GMODE !
   S" T90 L8 O3 GFEDC2" JINGLE ;

: COUNT-BONUS ( -- )
   BONUS @ 1000 * MULT * +SCORE
   0 BONUS !  0 MULT-I ! ;

: DRAINED ( -- )
   SAFE-T @ 0> IF
      TX-SAVE SAY   0 SAFE-T !  FALSE SHIELD-OK !  S-LANE EFFECT
      RESET-BALL  EXIT
   THEN
   COUNT-BONUS
   EXTRA @ 0> IF
      -1 EXTRA +!  TX-AGAIN SAY  TRUE SHIELD-OK !
      RESET-BALL  EXIT
   THEN
   1 BALL-NO +!
   BALL-NO @ 3 > IF
      GAME-OVER
   ELSE
      TX-OUT SAY  TRUE SHIELD-OK !
      RESET-BALL
   THEN ;

: STEP-STILL ( -- )
   BSTATE @ B-ROLL <> IF  0 STILL-T !  EXIT  THEN
   VX @ ABS 400 < VY @ ABS 400 < AND IF
      1 STILL-T +!
      STILL-T @ 200 > IF         \ stuck: the table is nudged
         2400 RND 1200 - VX !
         4096 NEGATE VY !
         0 STILL-T !
      THEN
   ELSE 0 STILL-T ! THEN ;

: CHECK-LANE-BALL ( -- )
   BX @ 504 FX * < IF  FALSE LANE-OPEN !  THEN
   BSTATE @ B-ROLL = BX @ 504 FX * > AND BY @ 720 FX * > AND
   VX @ ABS 800 < AND VY @ ABS 800 < AND IF
      B-LANE BSTATE !  TRUE LANE-OPEN !  0 CHARGE !
   THEN ;

: LAUNCH ( -- )
   B-ROLL BSTATE !
   TRUE LANE-OPEN !
   7000 CHARGE @ 130 * + NEGATE VY !
   300 RND 150 - VX !
   SHIELD-OK @ IF 600 SAFE-T ! THEN
   S-KICK EFFECT ;

: STEP-PLUNGER ( -- )
   BSTATE @ B-LANE <> IF EXIT THEN
   BY @ 730 FX * < IF EXIT THEN
   IN-P @ IF
      CHARGE @ 60 < IF 1 CHARGE +! THEN
   ELSE
      CHARGE @ IF LAUNCH 0 CHARGE ! THEN
   THEN ;

: DOWN-COUNT ( a -- )   DUP @ 0> IF -1 SWAP +! ELSE DROP THEN ;

: STEP-TIMERS ( -- )
   SAFE-T DOWN-COUNT   HOLE-COOL DOWN-COUNT   SLING-COOL DOWN-COUNT
   STAR-COOL DOWN-COUNT   STAR-FLASH DOWN-COUNT   TGT-COOL DOWN-COUNT   HOME-FLASH DOWN-COUNT
   #BUMP 0 DO  I CELLS BUMP-COOL + DOWN-COUNT   I CELLS BUMP-FLASH + DOWN-COUNT  LOOP
   MSG-T DOWN-COUNT
   BANK-RESET @ 1 = IF RESET-BANK THEN  BANK-RESET DOWN-COUNT
   TGT-RESET @ 1 = IF RESET-TARGETS THEN  TGT-RESET DOWN-COUNT ;

: STEP-EFFECTS ( -- )
   #SPARKS 0 DO
      I 6 * CELLS SPARKS + { a }
      a 4 CELLS + @ 0> IF
         a 2 CELLS + @ a +!   a 3 CELLS + @ a CELL+ +!
         -1 a 4 CELLS + +!
      THEN
   LOOP ;

VARIABLE WAS-FLIP-L   VARIABLE WAS-FLIP-R

: FLIP-INPUT ( -- )
   IN-L @ FL-HELD !   IN-R @ FL-HELD CELL+ !
   IN-L @ WAS-FLIP-L @ 0= AND IF  S-FLIP EFFECT  LANES-LEFT  THEN
   IN-R @ WAS-FLIP-R @ 0= AND IF  S-FLIP EFFECT  LANES-RIGHT  THEN
   IN-L @ WAS-FLIP-L !  IN-R @ WAS-FLIP-R ! ;

: TICK-PLAY ( -- )
   FLIP-INPUT
   STEP-PLUNGER
   STEP-PHYSICS
   BSTATE @ B-HOLD = IF STEP-HOLD THEN
   CHECK-LANES  CHECK-ROLLS  CHECK-HOLES  CHECK-LANE-BALL  STEP-STILL
   STEP-TIMERS  STEP-EFFECTS
   BY @ 815 FX * > IF DRAINED THEN ;

: TICK-GAME ( -- )
   1 CLOCK +!
   PAUSED @ IF EXIT THEN
   GMODE @ M-PLAY = IF TICK-PLAY ELSE
      STEP-EFFECTS
   THEN ;

: NEW-GAME ( -- )
   0 SCORE !  1 BALL-NO !  0 EXTRA !  0 BONUS !  0 MULT-I !  0 RUNS !  0 RUNNERS !
   FALSE HR-LIT !  FALSE EB-LIT !  0 HOME-FLASH !
   RESET-BANK  RESET-TARGETS
   4 0 DO  FALSE LANE-LIT I CELLS + !  FALSE LANE-IN I CELLS + !  FALSE ROLL-IN I CELLS + !  LOOP
   ANG-REST FL-ANG !  ANG-REST FL-ANG CELL+ !
   0 FL-DELTA !  0 FL-DELTA CELL+ !
   SPARKS #SPARKS 6 * CELLS ERASE
   #BUMP 0 DO  0 I CELLS BUMP-COOL + !  0 I CELLS BUMP-FLASH + !  LOOP
   0 HOLE-COOL !  0 SLING-COOL !  0 STAR-COOL !  0 STAR-FLASH !  0 TGT-COOL !  0 SAFE-T !
   TRUE SHIELD-OK !
   RESET-BALL
   FALSE PAUSED !
   M-PLAY GMODE !
   TRUE LOCK-INPUT !
   TX-PLAY SAY ;

\ ---- The pictures -------------------------------------------------------------------

VARIABLE TABLE-ART   VARIABLE SHEET-ART   VARIABLE BALL-ART   VARIABLE DIAMOND-ART
VARIABLE RUNNER-ART  VARIABLE HOME-ART    VARIABLE BAT-ART
CREATE BUMP-ART 4 CELLS ALLOT      \ 100 and 500, each plain and flashing
16 CONSTANT #FLIP
CREATE FLIP-ART #FLIP 2* CELLS ALLOT
CREATE DROP-ART 8 CELLS ALLOT      \ up and down, for each letter
CREATE LANE-ART 8 CELLS ALLOT      \ dark and lit, for each letter
CREATE MULT-ART 8 CELLS ALLOT
CREATE HR-ART 2 CELLS ALLOT   CREATE EB-ART 2 CELLS ALLOT
CREATE TGT-ART 2 CELLS ALLOT  CREATE STAR-ART 2 CELLS ALLOT
CREATE DIGITS-S 10 CELLS ALLOT     VARIABLE DIGIT-W-S
CREATE DIGITS-B 10 CELLS ALLOT     VARIABLE DIGIT-W-B

: PAINT-BUMPER { a u skin flash? | cap -- }
   flash? IF $FFFDF0 ELSE $F2E4C0 THEN TO cap
   $2A1A12 INK  32 32 31 DISC
   flash? IF skin $FFFFFF 90 MIX-RGB ELSE skin THEN INK  32 32 29 DISC
   skin $201008 110 MIX-RGB INK  32 34 22 DISC
   cap INK  32 31 21 DISC
   flash? IF $FFFFFF ELSE $FFF8E8 THEN INK  27 25 6 DISC
   $3A2214 INK
   a u  32 SCALED a u TEXT-WIDTH 2/ -  31 SCALED TEXT-HEIGHT 2/ -  TEXT ;

: MAKE-BUMPERS ( -- )
   44 USE-PLAIN
   56 ART-BEGIN S" 100" $E08A3A FALSE PAINT-BUMPER ART-DONE BUMP-ART !
   56 ART-BEGIN S" 100" $E08A3A TRUE  PAINT-BUMPER ART-DONE BUMP-ART 1 CELLS + !
   56 ART-BEGIN S" 500" $D8442E FALSE PAINT-BUMPER ART-DONE BUMP-ART 2 CELLS + !
   56 ART-BEGIN S" 500" $D8442E TRUE  PAINT-BUMPER ART-DONE BUMP-ART 3 CELLS + ! ;

: PAINT-BALL ( -- )
   $5A6068 INK  32 32 31 DISC
   $B8C0C8 INK  30 30 27 DISC
   $F8FAFC INK  24 22 11 DISC ;

\ A flipper on a canvas: the pivot at 14, 44 of the box of 96 by 88 (1 pixel to a unit).
: PAINT-FLIPPER { a mir | c s px tx ty -- }
   a COST TO c   a SINT TO s
   mir 0> IF 14 ELSE 82 THEN TO px
   px mir c * 70 * FX / + TO tx
   44 s 70 * FX / + TO ty
   $5A1810 INK  px 44 tx ty 7 BAR
   $D83A2A INK  px 44 tx ty 6 BAR
   $F4F0E6 INK  px 44 tx ty 4 BAR
   $FFFFFF INK  px 43 tx ty 1- 1 BAR
   $C8D0D8 INK  px 44 5 DISC
   $384048 INK  px 44 2 DISC ;
: FLIP-ANGLE ( k -- a )   ANG-REST ANG-UP -  *  #FLIP 1- /  ANG-REST SWAP - ;
: FLIP-BAKE ( -- spr )   96 88 ['] ART-PX BAKE ;
: MAKE-FLIPPERS ( -- )
   #FLIP 0 DO
      64 ART-BEGIN  I FLIP-ANGLE 1 PAINT-FLIPPER  FLIP-BAKE  FLIP-ART I CELLS + !
      64 ART-BEGIN  I FLIP-ANGLE -1 PAINT-FLIPPER  FLIP-BAKE  FLIP-ART I #FLIP + CELLS + !
   LOOP ;

: BASE-LETTER$ ( n -- a u )   S" BASE" DROP + 1 ;
: PAINT-DROP { n up? -- }
   $1A1410 INK  0 0 34 64 BOX
   up? IF
      $E8C040 INK  3 2 32 62 BOX
      $FFF0B0 INK  3 2 32 8 BOX
      $3A2214 INK
      n BASE-LETTER$  17 SCALED n BASE-LETTER$ TEXT-WIDTH 2/ -  34 SCALED TEXT-HEIGHT 2/ -  TEXT
   ELSE
      $3A2E26 INK  3 2 32 62 BOX
   THEN ;

: MAKE-DROPS ( -- )
   \ a drop target is 12 wide by 23 high; painted in a box of 64 units to 23 pixels
   44 USE-FONT
   4 0 DO
      23 ART-BEGIN  I TRUE PAINT-DROP   12 23 ['] ART-PX BAKE  DROP-ART I 2* CELLS + !
      23 ART-BEGIN  I FALSE PAINT-DROP  12 23 ['] ART-PX BAKE  DROP-ART I 2* 1+ CELLS + !
   LOOP ;

\ A lamp in the field: a colored insert with its word, dark or lit.
: PAINT-LAMP { a u c lit? -- }
   $2A1A12 INK  32 32 31 DISC
   lit? IF  c $FFFFFF 60 MIX-RGB  ELSE  c $2A1A12 150 MIX-RGB  THEN INK  32 32 27 DISC
   lit? IF  c $FFFFFF 170 MIX-RGB INK  28 26 12 DISC  THEN
   lit? IF $3A2214 ELSE c $F8F0E0 120 MIX-RGB THEN INK
   u IF  a u  32 SCALED a u TEXT-WIDTH 2/ -  32 SCALED TEXT-HEIGHT 2/ -  TEXT  THEN ;
: LAMP-PAIR { a u c side dest -- }
   side ART-BEGIN  a u c FALSE PAINT-LAMP  ART-DONE dest !
   side ART-BEGIN  a u c TRUE PAINT-LAMP   ART-DONE dest CELL+ ! ;

: MULT$ ( n -- a u )
   CASE  0 OF S" 2X" ENDOF  1 OF S" 3X" ENDOF  2 OF S" 5X" ENDOF  S" 10X" ROT  ENDCASE ;

: MAKE-LAMPS ( -- )
   40 USE-PLAIN
   4 0 DO  S" ABCD" DROP I + 1  $F0C040 22  LANE-ART I 2* CELLS +  LAMP-PAIR  LOOP
   30 USE-PLAIN
   4 0 DO  I MULT$  $E86A30 24  MULT-ART I 2* CELLS +  LAMP-PAIR  LOOP
   S" HR" $E83A30 26 HR-ART LAMP-PAIR
   S" EB" $48B060 26 EB-ART LAMP-PAIR
   S" " $F0F0F0 14 TGT-ART LAMP-PAIR
   S" " $E83020 16 STAR-ART LAMP-PAIR ;

: PAINT-RUNNER ( -- )
   $2A1A12 INK  32 32 31 DISC
   $D83A2A INK  32 32 27 DISC
   $FF9080 INK  26 24 9 DISC ;
: PAINT-HOME ( -- )
   $2A1A12 INK  32 32 31 DISC
   $FFF4C0 INK  32 32 27 DISC
   $FFFFFF INK  28 26 12 DISC ;

: MAKE-SMALL ( -- )
   20 ART-BEGIN PAINT-BALL ART-DONE BALL-ART !
   16 ART-BEGIN PAINT-RUNNER ART-DONE RUNNER-ART !
   20 ART-BEGIN PAINT-HOME ART-DONE HOME-ART ! ;

\ The diamond on the score card: 120 pixels, the bases 44 from the middle.
: PAINT-DIAMOND ( -- )
   $6E9E58 INK  32 40 31 DISC
   $5A8A48 INK  32 40 27 DISC
   $D8B080 INK  [P 32 9 DV 55 32 DV 32 55 DV 9 32 DV P]
   $6E9E58 INK  [P 32 17 DV 47 32 DV 32 47 DV 17 32 DV P]
   $C8A070 INK  32 32 4 DISC
   $FFFFFF INK  52 30 58 36 BOX  29 6 35 12 BOX  6 30 12 36 BOX
   [P 29 52 DV 35 52 DV 35 56 DV 32 59 DV 29 56 DV P] ;

: MAKE-DIGITS ( -- )
   20 USE-PLAIN   S" 0" TEXT-WIDTH DIGIT-W-S !
   10 0 DO  I DIGIT$ PAPER DIGITS-S I CELLS + !  LOOP
   30 USE-PLAIN   S" 0" TEXT-WIDTH DIGIT-W-B !
   10 0 DO  I DIGIT$ PAPER DIGITS-B I CELLS + !  LOOP ;

VARIABLE L-SCORE  VARIABLE L-BALL   VARIABLE L-RUNS   VARIABLE L-BONUS  VARIABLE L-MULT
VARIABLE L-TITLE  VARIABLE L-HR     VARIABLE L-EB     VARIABLE L-SAVE   VARIABLE L-BEST
VARIABLE L-EXTRA  VARIABLE L-HELP1  VARIABLE L-HELP2  VARIABLE L-HELP3  VARIABLE L-HELP4
VARIABLE L-HELP5  VARIABLE L-X
VARIABLE T-BIG    VARIABLE T-SUB    VARIABLE T-KEYS1  VARIABLE T-KEYS2  VARIABLE T-START
VARIABLE O-OVER   VARIABLE O-AGAIN  VARIABLE O-PAUSE

: MAKE-LABELS ( -- )
   32 USE-FONT  S" Ninth Inning" C-INK C-PAPER TEXT-SPRITE L-TITLE !
   15 USE-FONT
   S" SCORE" FADED L-SCORE !  S" BALL" FADED L-BALL !  S" RUNS" FADED L-RUNS !
   S" BONUS" FADED L-BONUS !  S" x" FADED L-X !
   S" Home run is lit" PAPER L-HR !  S" Extra ball is lit" PAPER L-EB !
   S" Ball save" PAPER L-SAVE !  S" Shoot again" PAPER L-EXTRA !  S" BEST" FADED L-BEST !
   14 USE-PLAIN
   S" Z or Left: left flipper" FADED L-HELP1 !
   S" / or Right: right flipper" FADED L-HELP2 !
   S" Space or Down: plunger" FADED L-HELP3 !
   S" The mouse buttons work too" FADED L-HELP4 !
   S" P pause   R again   Q quit" FADED L-HELP5 !
   15 USE-FONT
   #MSG 0 DO  I MSG$ DUP IF  PAPER MSG-ART I CELLS + !  ELSE 2DROP  THEN  LOOP
   68 USE-FONT  S" Ninth Inning" C-GOLD C-DARK TEXT-SPRITE T-BIG !
   20 USE-FONT  S" A ballpark on a wooden pinball table" $E8DCC0 C-DARK TEXT-SPRITE T-SUB !
   15 USE-FONT
   S" Spell BASE and ABCD, fill the bases, bring them home." $C8BCA0 C-DARK TEXT-SPRITE T-KEYS1 !
   S" Light the dugout for a home run; five runs light the extra ball." $C8BCA0 C-DARK TEXT-SPRITE T-KEYS2 !
   24 USE-FONT  S" Space or click to start" $F8E8B0 C-DARK TEXT-SPRITE T-START !
   44 USE-FONT  S" Game over" $FF9070 C-DARK TEXT-SPRITE O-OVER !
   S" Paused" C-GOLD C-DARK TEXT-SPRITE O-PAUSE !
   18 USE-FONT  S" Space or click to play again" $E8DCC0 C-DARK TEXT-SPRITE O-AGAIN ! ;

\ ---- The table picture -------------------------------------------------------------
\ Painted at twice its size, 560 by 800: the wood, the painted field, and the rails.

$E8D8B0 CONSTANT C-CREAM   $3E8E9A CONSTANT C-TEAL    $C8463A CONSTANT C-RED
$E4B444 CONSTANT C-YELLOW  $6E9E58 CONSTANT C-GREEN   $2A1A12 CONSTANT C-EDGE

: PAINT-WOOD { | c -- }
   140 0 DO
      I 7 * 13 MOD  I I * 5 MOD 3 * +  I 17 MOD 6 = IF 18 + THEN  8 * { t }
      $C49260 $8E5E34 t 255 MIN MIX-RGB TO c
      c INK  I 4 *  0  I 4 * 4 +  800 BOX
   LOOP ;

: PAINT-FIELD ( -- )
   C-EDGE INK  281 281 259 DISC  22 281 540 800 BOX
   C-CREAM INK  281 281 255 DISC  26 281 536 800 BOX ;

\ Rays of color from below the lanes up to the arch, as on the old table.
: RAY { a0 a1 c -- }
   c INK
   [P 264 330 DV
      281 250 a0 COST * FX / +  281 250 a0 SINT * FX / + DV
      281 250 a1 COST * FX / +  281 250 a1 SINT * FX / + DV P] ;
: PAINT-RAYS ( -- )
   2150 2420 C-TEAL RAY
   2420 2690 C-RED RAY
   2900 3150 C-YELLOW RAY
   3150 3420 C-GREEN RAY
   3640 3920 C-TEAL RAY ;

: PAINT-SIDES ( -- )
   C-TEAL INK
   [P 26 290 DV 70 300 DV 150 470 DV 140 560 DV 60 600 DV 26 600 DV P]
   [P 502 290 DV 458 300 DV 378 470 DV 388 560 DV 468 600 DV 502 600 DV P]
   C-YELLOW INK
   26 600 58 760 BOX  470 600 502 760 BOX
   [P 64 606 DV 126 640 DV 126 700 DV 64 670 DV P]
   [P 464 606 DV 402 640 DV 402 700 DV 464 670 DV P] ;

: PAINT-OUTFIELD ( -- )
   C-GREEN INK  264 700 172 DISC
   $5A8A48 INK  264 700 166 DISC
   C-GREEN INK  264 700 160 DISC
   $D8B080 INK  [P 264 552 DV 312 598 DV 264 644 DV 216 598 DV P]
   C-GREEN INK  [P 264 568 DV 296 598 DV 264 628 DV 232 598 DV P]
   $C8A070 INK  264 598 6 DISC
   $FFFFFF INK  294 592 306 604 BOX  258 556 270 568 BOX  222 592 234 604 BOX
   [P 258 630 DV 270 630 DV 270 638 DV 264 643 DV 258 638 DV P] ;

: PAINT-BANK-STRIPE ( -- )
   C-RED INK  [P 150 330 DV 180 336 DV 180 470 DV 150 480 DV P]
   C-YELLOW INK  [P 154 338 DV 176 342 DV 176 348 DV 154 344 DV P] ;

: PAINT-BASEBALL { x y r -- }
   C-EDGE INK  x y r 1+ DISC
   $FAF6EA INK  x y r DISC
   C-RED INK  x r 2/ - y r - x r 2/ - y r + 1 BAR  x r 2/ + y r - x r 2/ + y r + 1 BAR ;

: PAINT-KICKER-ART ( -- )
   \ the painted kicker at the top left, a bat across it
   C-EDGE INK  [P 72 206 DV 140 140 DV 132 244 DV P]
   C-RED INK   [P 80 205 DV 136 150 DV 129 234 DV P]
   $C89058 INK  86 214 130 160 5 BAR
   $E8B878 INK  86 214 130 160 2 BAR
   108 196 7 PAINT-BASEBALL
   \ the small kickers at the sides
   C-EDGE INK  [P 88 388 DV 88 452 DV 126 452 DV P]  [P 440 388 DV 440 452 DV 402 452 DV P]
   C-YELLOW INK  [P 92 400 DV 92 448 DV 118 448 DV P]  [P 436 400 DV 436 448 DV 410 448 DV P]
   100 436 5 PAINT-BASEBALL  428 436 5 PAINT-BASEBALL ;

: PAINT-STAR-PIECE ( -- )
   C-EDGE INK  [P 346 96 DV 388 132 DV 346 150 DV P]
   C-TEAL INK  [P 350 106 DV 380 132 DV 350 144 DV P] ;

: PAINT-WEDGE ( -- )
   C-EDGE INK  [P TA-X TA-Y DV TB-X TB-Y DV TC-X TC-Y DV P]
   C-GREEN INK [P 380 331 DV 432 320 DV 418 358 DV P]
   \ the bank behind the drop targets
   C-EDGE INK  196 344 202 448 BOX
   $3A2E26 INK  BANK-X BANK-Y 196 446 BOX ;

: PAINT-HOLE { x y -- }
   C-EDGE INK  x y 13 DISC
   $B8B4A8 INK  x y 12 DISC
   $1A1410 INK  x y 10 DISC
   $3A3430 INK  x 2 - y 2 - 5 DISC ;

: PAINT-LANE-STRIP ( -- )
   $8A5A30 INK  504 235 538 800 BOX
   C-EDGE INK  536 235 538 800 BOX ;

: PAINT-APRON { | c -- }
   \ below the ways from the outlanes; the drain between them
   C-EDGE INK  [P 24 701 DV 205 773 DV 205 800 DV 24 800 DV P]
               [P 504 701 DV 323 773 DV 323 800 DV 504 800 DV P]
   $D8C8A0 INK [P 26 708 DV 199 777 DV 199 800 DV 26 800 DV P]
               [P 502 708 DV 329 777 DV 329 800 DV 502 800 DV P]
   $1A1410 INK  205 773 323 800 BOX
   $2E2622 INK  209 776 319 780 BOX ;

: PAINT-WORDS ( -- )
   26 USE-PLAIN
   S" DUGOUT" DUG-X 290 C-EDGE LABEL
   S" KICKOUT" KICK-X 450 C-EDGE LABEL
   S" EXTRA BALL" KICK-X 518 C-EDGE LABEL
   S" BONUS" 94 594 C-EDGE LABEL   S" BONUS" 434 594 C-EDGE LABEL
   S" OUT" 41 650 C-EDGE LABEL    S" OUT" 487 650 C-EDGE LABEL
   S" OUTLANE" 76 774 C-EDGE LABEL   S" DRAIN" 452 774 C-EDGE LABEL
   S" 1B" 318 616 $FFFFFF LABEL  S" 3B" 210 616 $FFFFFF LABEL ;

VARIABLE RAIL-PASS
: RAIL { x0 y0 x1 y1 -- }
   RAIL-PASS @ CASE
      0 OF  $1A1612 INK  x0 y0 x1 y1 5 BAR  ENDOF
      1 OF  $9AA0A4 INK  x0 y0 x1 y1 3 BAR  ENDOF
      2 OF  $F0F4F4 INK  x0 y0 x1 y1 1 BAR  ENDOF
   ENDCASE ;

: DRAW-RAILS-PASS ( -- )
   #SEGS @ 0 DO
      I SEG[] { a }
      a 9 CELLS + @ { kind }
      kind K-DROP < kind K-GATE <> AND IF
         a @ FX / { x0 }  a CELL+ @ FX / { y0 }
         a @  a 2 CELLS + @ a 4 CELLS + @ * FX / + FX / { x1 }
         a CELL+ @  a 3 CELLS + @ a 4 CELLS + @ * FX / + FX / { y1 }
         kind K-SLING = kind K-KICKER = OR IF
            RAIL-PASS @ 0 = IF  C-EDGE INK  x0 y0 x1 y1 5 BAR  THEN
            RAIL-PASS @ 1 = IF  $F8F4EC INK  x0 y0 x1 y1 4 BAR  THEN
            RAIL-PASS @ 2 = IF  C-RED INK  x0 y0 x1 y1 1 BAR  THEN
         ELSE kind K-TGT >= IF
            RAIL-PASS @ 0 = IF  C-EDGE INK  x0 y0 x1 y1 5 BAR  THEN
            RAIL-PASS @ 1 = IF  $F8F8F4 INK  x0 3 + y0 1+ x1 3 - y1 1- 4 BAR  THEN
         ELSE kind K-STAR = IF
            RAIL-PASS @ 0 = IF  C-EDGE INK  x0 y0 x1 y1 5 BAR  THEN
            RAIL-PASS @ 1 = IF  C-YELLOW INK  x0 y0 x1 y1 3 BAR  THEN
         ELSE  x0 y0 x1 y1 RAIL  THEN THEN THEN
      THEN
   LOOP ;
: DRAW-RAILS ( -- )   3 0 DO  I RAIL-PASS !  DRAW-RAILS-PASS  LOOP ;

: PAINT-SLING-BODIES ( -- )
   C-RED INK  [P 128 552 DV 128 617 DV 188 660 DV P]
              [P 400 552 DV 400 617 DV 340 660 DV P]
   $F0E2C0 INK  [P 134 574 DV 134 610 DV 168 635 DV P]
                [P 394 574 DV 394 610 DV 360 635 DV P] ;

: PAINT-POSTS ( -- )      \ the pegs at the ends of the rails
   7 0 DO
      I CASE
         0 OF 170 96 ENDOF  1 OF 214 96 ENDOF  2 OF 258 96 ENDOF  3 OF 302 96 ENDOF
         4 OF 346 96 ENDOF  5 OF 58 600 ENDOF  6 OF 470 600 ENDOF
      ENDCASE { x y }
      C-EDGE INK  x y 5 DISC
      $D8DCDC INK  x y 4 DISC
      $FFFFFF INK  x 1- y 1- 1 DISC
   LOOP ;

: TABLE-PX ( x y -- rgb )   ART-PX $F8F8F8 AND ;

: MAKE-TABLE ( -- )
   64 TO CS  2 TO ZOOM
   1120 1600 GFX-INIT
   KEY-COLOR GFX-CLS
   PAINT-WOOD
   PAINT-FIELD
   PAINT-RAYS
   PAINT-SIDES
   PAINT-OUTFIELD
   PAINT-BANK-STRIPE
   PAINT-LANE-STRIP
   PAINT-APRON
   PAINT-SLING-BODIES
   PAINT-KICKER-ART
   PAINT-STAR-PIECE
   PAINT-WEDGE
   DUG-X DUG-Y PAINT-HOLE   KICK-X KICK-Y PAINT-HOLE
   PAINT-WORDS
   DRAW-RAILS
   PAINT-POSTS
   TW H ['] TABLE-PX BAKE TABLE-ART !
   3 TO ZOOM ;

: SHEET-PX { x y -- rgb }
   x 8 < y 8 < OR  x 231 > OR  y 791 > OR IF $8E5E34 EXIT THEN
   x 12 < y 12 < OR  x 227 > OR  y 787 > OR IF C-PAPER $3E2412 40 MIX-RGB EXIT THEN
   C-PAPER ;

: BAKE-ALL ( -- )
   BUILD-WALLS
   1024 512 GFX-INIT
   MAKE-BUMPERS  MAKE-FLIPPERS  MAKE-DROPS  MAKE-LAMPS  MAKE-SMALL
   120 ART-BEGIN PAINT-DIAMOND ART-DONE DIAMOND-ART !
   MAKE-DIGITS  MAKE-LABELS
   240 800 ['] SHEET-PX BAKE SHEET-ART !
   MAKE-TABLE ;

\ ---- Drawing ------------------------------------------------------------------------

: NUMBER-AT { n x y table dw -- }
   n S>D <# #S #>  0 DO
      DUP I + C@ [CHAR] 0 - CELLS table + @  { s }
      x I dw * +  y  s SPR
   LOOP DROP ;
: SMALL-AT ( n x y -- )   DIGITS-S DIGIT-W-S @ NUMBER-AT ;
: BIG-AT ( n x y -- )     DIGITS-B DIGIT-W-B @ NUMBER-AT ;

: DRAW-BUMPERS ( -- )
   #BUMP 0 DO
      I CELLS BUMP-X + @  I CELLS BUMP-Y + @
      I 2 / 2*  I CELLS BUMP-FLASH + @ 0> IF 1+ THEN  CELLS BUMP-ART + @  CENTERED
   LOOP ;

: DRAW-DROPS ( -- )
   4 0 DO
      BANK-X 7 -  BANK-Y I BANK-STEP * + 1+
      I 2*  DROP-UP I CELLS + @ 0= IF 1+ THEN  CELLS DROP-ART + @  SPR
   LOOP ;

: FLIP-FRAME ( n -- k )
   CELLS FL-ANG + @  ANG-REST SWAP -  #FLIP 1- *  ANG-REST ANG-UP - /  0 MAX #FLIP 1- MIN ;

: DRAW-FLIPPERS ( -- )
   181 14 -   700 44 -   0 FLIP-FRAME CELLS FLIP-ART + @  SPR
   347 82 -   700 44 -   1 FLIP-FRAME #FLIP + CELLS FLIP-ART + @  SPR ;

: LAMP ( x y lit? pair -- )   SWAP IF CELL+ THEN @ CENTERED ;
: BLINK? ( -- f )   CLOCK @ 16 AND 0= ;

: DRAW-LIGHTS ( -- )
   4 0 DO
      I CELLS LANE-X + @  110  LANE-LIT I CELLS + @  LANE-ART I 2* CELLS +  LAMP
      I CELLS LANE-X + @  166  MULT-I @ I >  MULT-ART I 2* CELLS +  LAMP
   LOOP
   3 0 DO
      I TGT-PT  I 1+ TGT-PT  ROT + 2/ >R  + 2/ R>   \ the middle of the target
      SWAP 11 - SWAP 14 +  TGT-LIT I CELLS + @  TGT-ART LAMP
   LOOP
   296 304  HR-LIT @ BLINK? AND  HR-ART LAMP
   KICK-X 498  EB-LIT @ BLINK? AND  EB-ART LAMP
   360 126  STAR-FLASH @ 0> STAR-FLASH @ 4 AND 0= AND  STAR-ART LAMP
   RUNNERS @ 1 AND IF  300 598 RUNNER-ART @ CENTERED  THEN
   RUNNERS @ 2 AND IF  264 562 RUNNER-ART @ CENTERED  THEN
   RUNNERS @ 4 AND IF  228 598 RUNNER-ART @ CENTERED  THEN
   HOME-FLASH @ 4 AND IF  264 636 HOME-ART @ CENTERED  THEN ;

: DRAW-PLUNGER ( -- )
   $B0B4B8 COLOR!  516 776 CHARGE @ 2/ + 12 20 FILL-RECT
   $E8ECEC COLOR!  518 776 CHARGE @ 2/ + 8 3 FILL-RECT ;

: DRAW-BALL ( -- )
   GMODE @ M-PLAY <> IF EXIT THEN
   BX @ FX /  BY @ FX /  BALL-ART @ CENTERED ;

: DRAW-EFFECTS ( -- )
   #SPARKS 0 DO
      I 6 * CELLS SPARKS + { a }
      a 4 CELLS + @ 0> IF
         a @ 16 / { sx }  a CELL+ @ 16 / { sy }
         sx 0 TW 3 - WITHIN  sy 0 H 2 - WITHIN AND IF
            sx DUP 2 + sy    a 5 CELLS + @ GFX-HLINE
            sx DUP 2 + sy 1+ a 5 CELLS + @ GFX-HLINE
         THEN
      THEN
   LOOP ;

: DRAW-CARD-DIAMOND ( -- )
   680 330 DIAMOND-ART @ CENTERED
   RUNNERS @ 1 AND IF  720 330 RUNNER-ART @ CENTERED  THEN
   RUNNERS @ 2 AND IF  680 290 RUNNER-ART @ CENTERED  THEN
   RUNNERS @ 4 AND IF  640 330 RUNNER-ART @ CENTERED  THEN
   HOME-FLASH @ 4 AND IF  680 371 HOME-ART @ CENTERED  THEN ;

: DRAW-SHEET ( -- )
   560 0 SHEET-ART @ SPR
   680 40  L-TITLE @ CENTERED
   580 76 L-SCORE @ SPR
   SCORE @ 580 92 BIG-AT
   580 140 L-BALL @ SPR   BALL-NO @ 3 MIN 640 136 SMALL-AT
   690 140 L-RUNS @ SPR   RUNS @ 750 136 SMALL-AT
   580 176 L-BONUS @ SPR  BONUS @ 1000 * 650 172 SMALL-AT
   730 176 L-X @ SPR      MULT 745 172 SMALL-AT
   DRAW-CARD-DIAMOND
   HR-LIT @ IF   680 420 L-HR @ CENTERED  THEN
   EB-LIT @ IF   680 444 L-EB @ CENTERED  THEN
   EXTRA @ 0> IF 680 468 L-EXTRA @ CENTERED  THEN
   SAFE-T @ 0> IF  580 494 L-SAVE @ SPR  $40A0E0 COLOR!  660 500  120 SAFE-T @ * 600 / 6 FILL-RECT  THEN
   MSG-T @ 0> IF  680 560 MSG-NOW @ CELLS MSG-ART + @ CENTERED  THEN
   580 655 L-BEST @ SPR   BEST @ 640 651 SMALL-AT
   680 694 L-HELP1 @ CENTERED
   680 712 L-HELP2 @ CENTERED
   680 730 L-HELP3 @ CENTERED
   680 748 L-HELP4 @ CENTERED
   680 766 L-HELP5 @ CENTERED ;

: DRAW-TITLE ( -- )
   C-DARK COLOR!  40 250 480 300 FILL-RECT
   C-GOLD COLOR!  40 250 480 3 FILL-RECT  40 547 480 3 FILL-RECT
   280 310 T-BIG @ CENTERED
   280 368 T-SUB @ CENTERED
   280 420 T-KEYS1 @ CENTERED
   280 446 T-KEYS2 @ CENTERED
   CLOCK @ 32 AND 0= IF  280 510 T-START @ CENTERED  THEN ;

: DRAW-OVER ( -- )
   C-DARK COLOR!  60 300 440 160 FILL-RECT
   C-GOLD COLOR!  60 300 440 3 FILL-RECT  60 457 440 3 FILL-RECT
   280 358 O-OVER @ CENTERED
   280 418 O-AGAIN @ CENTERED ;

: RENDER ( -- )
   0 0 TABLE-ART @ SPR
   DRAW-LIGHTS  DRAW-DROPS  DRAW-BUMPERS
   DRAW-PLUNGER  DRAW-FLIPPERS  DRAW-BALL  DRAW-EFFECTS
   DRAW-SHEET
   GMODE @ M-TITLE = IF DRAW-TITLE THEN
   GMODE @ M-OVER = IF DRAW-OVER THEN
   PAUSED @ IF  280 400 O-PAUSE @ CENTERED  THEN ;

\ ---- Input -------------------------------------------------------------------------

: HELD2 ( c1 c2 -- flag )   KEY-HELD? SWAP KEY-HELD? OR ;

: GO-ON ( -- )   GMODE @ M-PLAY <> IF NEW-GAME THEN ;

: KEY! ( key -- )
   DUP [CHAR] A [CHAR] Z 1+ WITHIN IF 32 + THEN
   CASE
      [CHAR] q OF  TRUE DONE !  ENDOF
      27       OF  TRUE DONE !  ENDOF
      [CHAR] p OF  GMODE @ M-PLAY = IF PAUSED @ 0= PAUSED ! THEN  ENDOF
      [CHAR] r OF  NEW-GAME  ENDOF
      BL       OF  GO-ON  ENDOF
      13       OF  GO-ON  ENDOF
   ENDCASE ;
: READ-KEYS ( -- )   BEGIN INKEY DUP -1 <> WHILE KEY! REPEAT DROP ;

VARIABLE OLD-B
: READ-INPUT { | b -- }
   MOUSE TO b 2DROP
   b 1 AND 0<> OLD-B @ 1 AND 0= AND IF GO-ON THEN
   K-LEFT KEY-HELD?  [CHAR] z [CHAR] Z HELD2 OR   b 1 AND 0<> OR  IN-L !
   K-RIGHT KEY-HELD? [CHAR] / KEY-HELD? OR        b 2 AND 0<> OR  IN-R !
   BL KEY-HELD?  K-DOWN KEY-HELD? OR
   BSTATE @ B-LANE =  b 3 AND 0<> AND  OR  IN-P !
   LOCK-INPUT @ IF
      IN-P @ IF FALSE IN-P ! ELSE FALSE LOCK-INPUT ! THEN
   THEN
   b OLD-B ! ;

\ ---- The game loop -----------------------------------------------------------------

: GAME-STEP ( -- )   READ-KEYS  READ-INPUT  TICK-GAME  RENDER ;

: INIT-GAME ( -- )
   NOW SEED !  FALSE DONE !  0 BEST !  0 OLD-B !
   FALSE IN-L !  FALSE IN-R !  FALSE IN-P !
   FALSE WAS-FLIP-L !  FALSE WAS-FLIP-R !
   NEW-GAME
   M-TITLE GMODE ! ;

: NINTH-INNING ( -- )
   BAKE-ALL  MAKE-SOUNDS
   W H GFX-INIT  MOUSE-ON
   INIT-GAME
   BEGIN  GAME-STEP  16 FRAME  DONE @ UNTIL
   MOUSE-OFF ;

[UNDEFINED] NO-AUTORUN [IF] NINTH-INNING BYE [THEN]
