\ Klondike: the patience card game for one player, drawn and played in a window.
\ The cards are painted when the program starts: every pip, letter, picture card, and
\ card back is this file's own, made at レモン's request.
\
\   sigma.exe examples/klondike.fs      (in a window; Tk on Linux/macOS)
\
\ Mouse: drag a card or a run of cards; click a card to send it where it can go; click
\ the stock to draw; the right button sends everything it can to the foundations.
\ Keys: Space draw, U undo (also Ctrl+Z), H hint, A auto, N new deal, R this deal again,
\ D draw 1 or 3 (deals again), Q or Esc ends the game. Undo also brings back the game
\ a new deal replaced.
\
\ The piles are built down in alternating colors on the seven columns, up in suit from
\ the ace on the four foundations; only a king goes on an empty column.
\ Score: waste to column 5, to a foundation 10, turning a card over 5, foundation back
\ to a column -15; going through the stock again costs 100 when drawing one, and 20
\ from the third time when drawing three.

REQUIRE-GRAPHICS  ALSO GRAPHICS

\ ---- Sound effects ----------------------------------------------------------------
\ Made with SAMPLE and played with SFX when the build has the audio words; a build
\ without them (-Daudio=false) plays silently.

: AUDIO-LOADED? ( -- flag )   S" REQUIRE-AUDIO" ['] EVALUATE CATCH  DUP IF NIP NIP THEN  0= ;
[UNDEFINED] NO-SOUND [IF] AUDIO-LOADED? [ELSE] FALSE [THEN] CONSTANT HAS-SOUND

0 CONSTANT S-PLACE  1 CONSTANT S-FLIP  2 CONSTANT S-FOUND  3 CONSTANT S-SHUFFLE  4 CONSTANT S-BAD

HAS-SOUND [IF]
ALSO AUDIO
11025 CONSTANT S-RATE
CREATE S-WAVE S-RATE ALLOT
VARIABLE HISS-SEED
: HISS-BYTE ( -- n )   HISS-SEED @ 1103515245 * 12345 + DUP HISS-SEED !  16 RSHIFT 255 AND 128 - ;
\ n samples of noise from sample at on, low-passed by k/256, fading out.
: SWISH { at n k amp | v -- }
   n 0 DO
      HISS-BYTE v - k * 256 / v + TO v
      v amp * n I - * n / 256 /  S-WAVE at + I + C!
   LOOP ;
\ n samples of a square wave of half period half, fading out, added to what is there.
: CHIME { at n half amp -- }
   n 0 DO
      I half / 1 AND IF amp ELSE amp NEGATE THEN  n I - * n /
      S-WAVE at + I + DUP C@ DUP 127 > IF 256 - THEN ROT +  -127 MAX 127 MIN  SWAP C!
   LOOP ;
: BLANK-WAVE ( -- )   S-WAVE S-RATE ERASE  ;
: KEEP-WAVE ( n k -- )   >R S-WAVE SWAP S-RATE R> SAMPLE ;
: EFFECT ( k -- )   SFX ;
: JINGLE ( c-addr u -- )   PLAY ;
: MAKE-SOUNDS ( -- )
   BLANK-WAVE  0 500 120 300 SWISH                     500 S-PLACE KEEP-WAVE
   BLANK-WAVE  0 260 220 260 SWISH                     260 S-FLIP KEEP-WAVE
   BLANK-WAVE  0 400 120 260 SWISH  0 1100 7 34 CHIME  60 700 5 26 CHIME   1100 S-FOUND KEEP-WAVE
   BLANK-WAVE  10 0 DO  I 560 *  520  90 I 8 * +  300 SWISH  LOOP          6000 S-SHUFFLE KEEP-WAVE
   BLANK-WAVE  0 1200 34 70 CHIME                      1200 S-BAD KEEP-WAVE ;
PREVIOUS
[ELSE]
: EFFECT ( k -- )   DROP ;
: JINGLE ( c-addr u -- )   2DROP ;
: MAKE-SOUNDS ( -- ) ;
[THEN]

\ ---- Numbers and sizes -------------------------------------------------------------

800 CONSTANT W          \ the image
640 CONSTANT H
88 CONSTANT CW          \ a card
124 CONSTANT CH

VARIABLE SEED
: RND ( n -- 0..n-1 )   SEED @ 6364136223846793005 * 1442695040888963407 +  DUP SEED !  33 RSHIFT  SWAP MOD ;
: NOW ( -- us )   UTIME DROP ;

: MIX1 { a b t -- c }   a 255 t - *  b t *  +  127 +  255 / ;
: MIX-RGB { c1 c2 t -- c }     \ t from 0 (all c1) to 255 (all c2)
   c1 16 RSHIFT 255 AND  c2 16 RSHIFT 255 AND  t MIX1  16 LSHIFT
   c1 8 RSHIFT 255 AND   c2 8 RSHIFT 255 AND   t MIX1   8 LSHIFT OR
   c1 255 AND            c2 255 AND            t MIX1  OR ;

: ISQRT { n | v -- r }
   n 2 < IF n EXIT THEN
   n TO v  BEGIN  v n v / + 2/  DUP v < WHILE  TO v  REPEAT DROP  v ;

\ A sine table, 256 steps to the circle, scaled by 1024 (Bhaskara's formula).
CREATE SINE 256 CELLS ALLOT
: MAKE-SINE ( -- )
   256 0 DO
      I 128 MOD 180 * 128 / { d }
      d 180 d - * 4096 *   40500 d 180 d - * - /
      I 128 >= IF NEGATE THEN  I CELLS SINE + !
   LOOP ;
: ISIN ( a -- v )   255 AND CELLS SINE + @ ;
: ICOS ( a -- v )   64 + ISIN ;

\ ---- Sprites made of spans ---------------------------------------------------------
\ A sprite is: its number of spans, its width, its height, then one cell for each span
\ with x1, x2, and y (12 bits each) and the color, ordered by row. Pictures are built
\ once and drawn as spans; a card covered by the next is cut after its first rows.

: SPAN, { x1 x2 y c -- }   x1  x2 12 LSHIFT OR  y 24 LSHIFT OR  c 36 LSHIFT OR  , ;

\ xt ( x y -- rgb | -1 ) gives the pixels; -1 is a hole in the sprite.
: BAKE { bw bh xt | a x c x2 -- a }
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

: BLIT { x y lim a | e v -- }    \ only the rows above lim
   a 3 CELLS + DUP  a @ CELLS +  TO e
   BEGIN DUP e < WHILE
      DUP @ TO v
      v 24 RSHIFT $FFF AND lim >= IF DROP EXIT THEN
      v $FFF AND x +   v 12 RSHIFT $FFF AND x +   v 24 RSHIFT $FFF AND y +   v 36 RSHIFT  GFX-HLINE
      CELL+
   REPEAT DROP ;
: SPR ( x y a -- )   999 SWAP BLIT ;
: SPR-W ( a -- w )   CELL+ @ ;

\ The sprite narrowed around its middle to k/256 of its width, for a card turning over.
: BLIT-THIN { x y a k | e v cx -- }
   x CW 2/ + TO cx
   a 3 CELLS + DUP  a @ CELLS +  TO e
   BEGIN DUP e < WHILE
      DUP @ TO v
      v $FFF AND CW 2/ - k * 256 / cx +
      v 12 RSHIFT $FFF AND CW 2/ - k * 256 / cx +
      v 24 RSHIFT $FFF AND y +   v 36 RSHIFT  GFX-HLINE
      CELL+
   REPEAT DROP ;

\ ---- Painting tools ----------------------------------------------------------------
\ Everything is painted large on a scratch image and then shrunk, for smooth edges.

$FF00FE CONSTANT KEY-COLOR
: CANVAS-PX ( x y -- rgb | -1 )   GFX-PGET  DUP KEY-COLOR = IF DROP -1 THEN ;

VARIABLE ZOOM   VARIABLE AX   VARIABLE AY
: >CANVAS ( x y -- cx cy )   ZOOM @ * AY @ +  SWAP ZOOM @ * AX @ +  SWAP ;
: INK ( rgb -- )   COLOR! ;

CREATE PTS 48 2* CELLS ALLOT   VARIABLE #PTS
: [P ( -- )   0 #PTS ! ;
: VX ( x y -- )   PTS #PTS @ 2* CELLS + 2!  1 #PTS +! ;
: DV ( x y -- )   >CANVAS VX ;
: PT@ ( n -- x y )   2* CELLS PTS + 2@ ;

VARIABLE ROW-LO   VARIABLE ROW-HI
: ROW-HIT ( x -- )   DUP ROW-LO @ MIN ROW-LO !  ROW-HI @ MAX ROW-HI ! ;
: EDGE { y x0 y0 x1 y1 -- }
   y y0 y1 MIN < IF EXIT THEN   y y0 y1 MAX > IF EXIT THEN
   y0 y1 = IF  x0 ROW-HIT  x1 ROW-HIT  EXIT THEN
   y y0 - x1 x0 - *  y1 y0 - /  x0 +  ROW-HIT ;
\ Fill the convex polygon of the points given since [P.
: P] { | top bot -- }
   99999 TO top  -99999 TO bot
   #PTS @ 0 DO  I PT@ NIP DUP top MIN TO top  bot MAX TO bot  LOOP
   bot 1+ top DO
      99999 ROW-LO !  -99999 ROW-HI !
      #PTS @ 0 DO  J  I PT@  I 1+ #PTS @ MOD PT@  EDGE  LOOP
      ROW-HI @ ROW-LO @ >= IF  ROW-LO @ ROW-HI @ I COLOR@ GFX-HLINE  THEN
   LOOP ;

VARIABLE PEN-X   VARIABLE PEN-Y   VARIABLE PEN-R
: STAMP ( x y -- )   PEN-R @ FILL-CIRCLE ;
: PEN-AT ( x y -- )   >CANVAS  2DUP PEN-Y ! PEN-X !  STAMP ;
: PEN-TO { x y | tx ty n -- }     \ a thick line from the pen
   x y >CANVAS TO ty TO tx
   tx PEN-X @ - ABS  ty PEN-Y @ - ABS MAX  2/ 1+ TO n
   n 1+ 1 DO
      tx PEN-X @ - I * n /  PEN-X @ +
      ty PEN-Y @ - I * n /  PEN-Y @ +  STAMP
   LOOP
   tx PEN-X !  ty PEN-Y ! ;

: DRECT { x1 y1 x2 y2 -- }
   y2 ZOOM @ * y1 ZOOM @ * DO  x1 ZOOM @ *  x2 ZOOM @ * 1-  I  COLOR@ GFX-HLINE  LOOP ;
: DCIRC ( x y r -- )   >R >CANVAS R> ZOOM @ * FILL-CIRCLE ;
: DELL { cx cy rx ry | x0 y0 rr -- }
   cx cy >CANVAS TO y0 TO x0   ry ZOOM @ * TO rr
   rr 1+ rr NEGATE DO
      rx ZOOM @ *  rr rr * I I * - ISQRT *  rr /  { half }
      x0 half -  x0 half +  y0 I +  COLOR@ GFX-HLINE
   LOOP ;

\ Masks: a width, a height, and how much of each pixel the white shape covers.
4 CONSTANT SS
: SUB-ALPHA { x y | s -- a }
   SS 0 DO SS 0 DO  x SS * I +  y SS * J +  GFX-PGET 255 AND  s + TO s  LOOP LOOP
   s SS SS * / ;
: GRAB-MASK { bw bh | a -- a }
   ALIGN HERE TO a  bw , bh ,
   bh 0 DO bw 0 DO  I J SUB-ALPHA C,  LOOP LOOP  ALIGN  a ;

\ ---- The suits ---------------------------------------------------------------------
\ Spades 0, hearts 1, clubs 2, diamonds 3; the odd ones are red. cx cy is the middle of
\ the shape and s half its height, in canvas pixels.

: HEART-AT { cx cy s dir | r top -- }      \ dir 1: point down, -1: point up
   s 50 * 100 / TO r
   cy s dir * - r dir * +  TO top
   cx r 92 * 100 / -  top  r FILL-CIRCLE
   cx r 92 * 100 / +  top  r FILL-CIRCLE
   [P  cx  cy s dir * + VX
       cx r 186 * 100 / -   top r dir * 30 * 100 / + VX
       cx   top r dir * 40 * 100 / - VX
       cx r 186 * 100 / +   top r dir * 30 * 100 / + VX  P] ;
: STEM-AT { cx cy s -- }
   [P  cx  cy s 10 * 100 / + VX   cx s 40 * 100 / -  cy s + VX   cx s 40 * 100 / +  cy s + VX  P] ;
: SPADE-AT { cx cy s -- }
   cx  cy s 20 * 100 / -  s 80 * 100 /  -1 HEART-AT
   cx cy s STEM-AT ;
: CLUB-AT { cx cy s | r -- }
   s 46 * 100 / TO r
   cx  cy s - r +  r FILL-CIRCLE
   cx r 112 * 100 / -  cy s 16 * 100 / +  r FILL-CIRCLE
   cx r 112 * 100 / +  cy s 16 * 100 / +  r FILL-CIRCLE
   [P  cx cy s - r + VX   cx r -  cy VX   cx  cy s 40 * 100 / + VX   cx r +  cy VX  P]
   cx cy s STEM-AT ;
: DIAMOND-AT { cx cy s | hw -- }
   s 76 * 100 / TO hw
   [P  cx cy s - VX   cx hw + cy VX   cx cy s + VX   cx hw - cy VX  P] ;
: SUIT-AT ( cx cy s suit -- )
   CASE
      0 OF SPADE-AT ENDOF
      1 OF 1 HEART-AT ENDOF
      2 OF CLUB-AT ENDOF
      3 OF DIAMOND-AT ENDOF
   ENDCASE ;

\ Four sizes of each suit: half heights 5, 8, 9, and 24 pixels.
0 CONSTANT K-MINI  1 CONSTANT K-MID  2 CONSTANT K-PIP  3 CONSTANT K-ACE
CREATE SUIT-MASKS 16 CELLS ALLOT
: SUIT-MASK ( suit kind -- m )   SWAP 4 * + CELLS SUIT-MASKS + @ ;
: MAKE-SUIT-MASK { suit half | side -- m }
   half 1+ 2* TO side
   0 GFX-CLS  $FFFFFF INK
   side 2*  side 2*  half SS *  suit SUIT-AT
   side side GRAB-MASK ;
: MAKE-SUIT-MASKS ( -- )
   4 0 DO
      I 5 MAKE-SUIT-MASK   K-MINI I 4 * + CELLS SUIT-MASKS + !
      I 8 MAKE-SUIT-MASK   K-MID I 4 * + CELLS SUIT-MASKS + !
      I 9 MAKE-SUIT-MASK   K-PIP I 4 * + CELLS SUIT-MASKS + !
      I 24 MAKE-SUIT-MASK  K-ACE I 4 * + CELLS SUIT-MASKS + !
   LOOP ;

\ ---- The letters on the cards ------------------------------------------------------
\ Drawn with a round pen on a grid 40 wide and 64 high.

: G-A    0 64 PEN-AT 20 0 PEN-TO 40 64 PEN-TO   7 42 PEN-AT 33 42 PEN-TO ;
: G-2    2 16 PEN-AT 4 8 PEN-TO 10 2 PEN-TO 20 0 PEN-TO 30 2 PEN-TO 37 9 PEN-TO 38 18 PEN-TO
         34 28 PEN-TO 24 38 PEN-TO 10 50 PEN-TO 0 64 PEN-TO 40 64 PEN-TO ;
: G-3    3 10 PEN-AT 10 2 PEN-TO 20 0 PEN-TO 31 3 PEN-TO 36 10 PEN-TO 36 18 PEN-TO 31 26 PEN-TO
         18 29 PEN-TO 31 32 PEN-TO 38 39 PEN-TO 39 48 PEN-TO 35 58 PEN-TO 26 63 PEN-TO
         16 64 PEN-TO 6 61 PEN-TO 0 53 PEN-TO ;
: G-4    30 64 PEN-AT 30 0 PEN-TO 0 44 PEN-TO 40 44 PEN-TO ;
: G-5    36 0 PEN-AT 8 0 PEN-TO 5 28 PEN-TO 14 23 PEN-TO 24 23 PEN-TO 33 27 PEN-TO 39 36 PEN-TO
         39 47 PEN-TO 34 58 PEN-TO 24 64 PEN-TO 13 64 PEN-TO 4 60 PEN-TO 0 52 PEN-TO ;
: G-6    36 8 PEN-AT 29 1 PEN-TO 20 0 PEN-TO 10 3 PEN-TO 3 13 PEN-TO 0 28 PEN-TO 0 42 PEN-TO
         3 54 PEN-TO 10 62 PEN-TO 20 64 PEN-TO 30 62 PEN-TO 37 54 PEN-TO 39 44 PEN-TO 37 33 PEN-TO
         30 26 PEN-TO 20 23 PEN-TO 10 26 PEN-TO 3 33 PEN-TO 0 42 PEN-TO ;
: G-7    0 0 PEN-AT 40 0 PEN-TO 14 64 PEN-TO ;
: G-8    20 29 PEN-AT 11 26 PEN-TO 5 19 PEN-TO 5 10 PEN-TO 10 3 PEN-TO 20 0 PEN-TO 30 3 PEN-TO
         35 10 PEN-TO 35 19 PEN-TO 29 26 PEN-TO 20 29 PEN-TO 9 33 PEN-TO 1 41 PEN-TO 1 52 PEN-TO
         8 61 PEN-TO 20 64 PEN-TO 32 61 PEN-TO 39 52 PEN-TO 39 41 PEN-TO 31 33 PEN-TO 20 29 PEN-TO ;
: G-9    4 56 PEN-AT 11 63 PEN-TO 20 64 PEN-TO 30 61 PEN-TO 37 51 PEN-TO 40 36 PEN-TO 40 22 PEN-TO
         37 10 PEN-TO 30 2 PEN-TO 20 0 PEN-TO 10 2 PEN-TO 3 10 PEN-TO 1 20 PEN-TO 3 31 PEN-TO
         10 38 PEN-TO 20 41 PEN-TO 30 38 PEN-TO 37 31 PEN-TO 40 22 PEN-TO ;
: G-10   0 11 PEN-AT 9 0 PEN-TO 9 64 PEN-TO
         34 0 PEN-AT 44 4 PEN-TO 49 16 PEN-TO 50 32 PEN-TO 49 48 PEN-TO 44 60 PEN-TO 34 64 PEN-TO
         24 60 PEN-TO 19 48 PEN-TO 18 32 PEN-TO 19 16 PEN-TO 24 4 PEN-TO 34 0 PEN-TO ;
: G-J    18 0 PEN-AT 40 0 PEN-TO   32 0 PEN-AT 32 46 PEN-TO 29 57 PEN-TO 21 63 PEN-TO 12 64 PEN-TO
         4 59 PEN-TO 0 50 PEN-TO ;
: G-Q    20 0 PEN-AT 31 3 PEN-TO 38 12 PEN-TO 40 24 PEN-TO 40 40 PEN-TO 38 52 PEN-TO 31 61 PEN-TO
         20 64 PEN-TO 9 61 PEN-TO 2 52 PEN-TO 0 40 PEN-TO 0 24 PEN-TO 2 12 PEN-TO 9 3 PEN-TO 20 0 PEN-TO
         24 46 PEN-AT 42 68 PEN-TO ;
: G-K    2 0 PEN-AT 2 64 PEN-TO   38 0 PEN-AT 2 38 PEN-TO   16 24 PEN-AT 40 64 PEN-TO ;
: G-SIGMA  40 6 PEN-AT 40 0 PEN-TO 0 0 PEN-TO 22 32 PEN-TO 0 64 PEN-TO 40 64 PEN-TO 40 58 PEN-TO ;

CREATE GLYPHS  ' G-A , ' G-2 , ' G-3 , ' G-4 , ' G-5 , ' G-6 , ' G-7 , ' G-8 , ' G-9 , ' G-10 , ' G-J , ' G-Q , ' G-K ,
CREATE RANK-MASKS 13 CELLS ALLOT
VARIABLE SIGMA-MASK

: GLYPH-CANVAS ( x y radius zoom -- )
   ZOOM !  PEN-R !  AY !  AX !  0 GFX-CLS  $FFFFFF INK ;
: MAKE-GLYPHS ( -- )
   13 0 DO
      I 9 = IF 7 ELSE 12 THEN  8  5  1  GLYPH-CANVAS
      GLYPHS I CELLS + @ EXECUTE
      16 20 GRAB-MASK  RANK-MASKS I CELLS + !
   LOOP
   24 24 9 2 GLYPH-CANVAS  G-SIGMA  32 44 GRAB-MASK SIGMA-MASK !
   0 AX !  0 AY !  1 ZOOM ! ;

\ ---- Making the cards --------------------------------------------------------------

\ Two work areas on the heap: the dictionary is kept for the finished sprites.
CW CH * CELLS ALLOCATE THROW CONSTANT CARD-BUF
CW CH * CELLS ALLOCATE THROW CONSTANT BASE-BUF
: BUF-XY ( x y -- a )   CW * + CELLS CARD-BUF + ;
: BUF-PX ( x y -- rgb | -1 )   BUF-XY @ ;

: BLEND { x y a c | p -- }
   x 0 CW WITHIN  y 0 CH WITHIN AND 0= IF EXIT THEN
   x y BUF-XY TO p
   p @ -1 = IF EXIT THEN
   p @ c a MIX-RGB  p ! ;
: STAMP-MASK { x y m c flip | bw bh -- }
   m @ TO bw   m CELL+ @ TO bh
   bh 0 DO bw 0 DO
      m 2 CELLS + J bw * + I + C@ DUP IF
         { a }
         flip IF  CW 1- x - I -  CH 1- y - J -  ELSE  x I +  y J +  THEN  a c BLEND
      ELSE DROP THEN
   LOOP LOOP ;

\ Coverage of a corner pixel by a rounded card of radius 8; the outermost pixel is the
\ border, drawn the color border over rim.
8 CONSTANT CORNER
: CORNER-PX { fx fy fill border rim | in edge sx sy dd -- c }
   SS 0 DO SS 0 DO
      fx SS * I + 2* 1+  CORNER SS * 2* -
      DUP * TO sx
      fy SS * J + 2* 1+  CORNER SS * 2* -
      DUP * TO sy
      sx sy + TO dd
      dd CORNER SS * 2* DUP * <= IF
         in 1+ TO in
         dd CORNER 1- SS * 2* DUP * > IF edge 1+ TO edge THEN
      THEN
   LOOP LOOP
   in 0= IF -1 EXIT THEN
   fill border edge 255 * in / MIX-RGB
   rim SWAP  in 255 * SS SS * /  MIX-RGB ;

: PAPER-PX { fill y -- c }     \ a little darker to the foot of the card
   fill $E8E2D2 y 120 * CH / MIX-RGB ;

: SHAPE-PX { x y fill border rim | fx fy -- c }
   x CW 1- x - MIN TO fx   y CH 1- y - MIN TO fy
   fx CORNER < fy CORNER < AND IF  fx fy fill border rim CORNER-PX EXIT  THEN
   fx 0= fy 0= OR IF border EXIT THEN
   fill ;

: MAKE-SHAPE { fill border rim -- }
   CH 0 DO CW 0 DO  I J fill border rim SHAPE-PX  I J BUF-XY !  LOOP LOOP ;
: PAPER-SHAPE ( -- )     \ the shape of every card face, in BASE-BUF
   $FDFAF0 $9098A0 $2A4A3A MAKE-SHAPE
   CH 1- 1 DO CW 1- 1 DO
      I J BUF-XY @ $FDFAF0 = IF  $FDFAF0 J PAPER-PX  I J BUF-XY !  THEN
   LOOP LOOP
   CARD-BUF BASE-BUF CW CH * CELLS MOVE ;

VARIABLE CUR-SUIT   VARIABLE CUR-INK
: RED-SUIT? ( suit -- flag )   1 AND 0<> ;
: SUIT-INK ( suit -- rgb )   RED-SUIT? IF $C81E2E ELSE $1A2230 THEN ;

31 CONSTANT COL-L   44 CONSTANT COL-C   57 CONSTANT COL-R
: PIP { cx cy | m -- }
   CUR-SUIT @ K-PIP SUIT-MASK TO m
   cy 62 > IF
      CW cx - m @ 2/ -  CH cy - m CELL+ @ 2/ -  m CUR-INK @ TRUE STAMP-MASK
   ELSE
      cx m @ 2/ -  cy m CELL+ @ 2/ -  m CUR-INK @ FALSE STAMP-MASK
   THEN ;
: PAIR-AT ( y -- )   COL-L OVER PIP  COL-R SWAP PIP ;
: ROWS-2 ( -- )   24 PAIR-AT  100 PAIR-AT ;
: ROWS-3 ( -- )   ROWS-2  62 PAIR-AT ;
: ROWS-4 ( -- )   24 PAIR-AT  49 PAIR-AT  75 PAIR-AT  100 PAIR-AT ;
: PIPS ( rank -- )
   CASE
      1 OF  COL-C 24 PIP  COL-C 100 PIP  ENDOF
      2 OF  COL-C 24 PIP  COL-C 62 PIP  COL-C 100 PIP  ENDOF
      3 OF  ROWS-2  ENDOF
      4 OF  ROWS-2  COL-C 62 PIP  ENDOF
      5 OF  ROWS-3  ENDOF
      6 OF  ROWS-3  COL-C 43 PIP  ENDOF
      7 OF  ROWS-3  COL-C 43 PIP  COL-C 81 PIP  ENDOF
      8 OF  ROWS-4  COL-C 62 PIP  ENDOF
      9 OF  ROWS-4  COL-C 37 PIP  COL-C 87 PIP  ENDOF
   ENDCASE ;

: ACE-PIP ( -- )
   CUR-SUIT @ K-ACE SUIT-MASK { m }
   CW m @ - 2/  CH m CELL+ @ - 2/  m CUR-INK @ FALSE STAMP-MASK ;

: INDEX ( rank -- )
   CELLS RANK-MASKS + @ { m }
   2 5 m CUR-INK @ FALSE STAMP-MASK    2 5 m CUR-INK @ TRUE STAMP-MASK
   CUR-SUIT @ K-MINI SUIT-MASK TO m
   4 26 m CUR-INK @ FALSE STAMP-MASK   4 26 m CUR-INK @ TRUE STAMP-MASK ;

\ ---- The picture cards -------------------------------------------------------------
\ Half a figure, 50 by 51 design pixels, painted three times as large, shrunk, and
\ placed twice: the second copy turned around, as on a printed card.

50 CONSTANT ART-W   51 CONSTANT ART-H
19 CONSTANT ART-X   11 CONSTANT ART-Y
3 CONSTANT ART-ZOOM

$FFF4D6 CONSTANT C-CREAM   $F4C9A4 CONSTANT C-SKIN   $E0AC80 CONSTANT C-SHADE
$E8B820 CONSTANT C-GOLD    $A87C10 CONSTANT C-DARK-GOLD   $2A2430 CONSTANT C-LINE
$FFFFFF CONSTANT C-WHITE   $C81E2E CONSTANT C-RUBY
VARIABLE ROBE   VARIABLE TRIM

: ROBE-FOR ( suit -- rgb )
   CASE  0 OF $27408B ENDOF   1 OF $C8202C ENDOF   2 OF $1E7A4C ENDOF   3 OF $DA7A16 ENDOF   0 SWAP ENDCASE ;
: TRIM-FOR ( suit -- rgb )
   CASE  0 OF $16264F ENDOF   1 OF $7E1220 ENDOF   2 OF $10492C ENDOF   3 OF $9A5208 ENDOF   0 SWAP ENDCASE ;

: EYES ( -- )
   C-WHITE INK  21 19 2 DCIRC  29 19 2 DCIRC
   C-LINE INK   21 19 1 DCIRC  29 19 1 DCIRC
   [P 17 15 DV 24 15 DV 24 16 DV 17 16 DV P]
   [P 26 15 DV 33 15 DV 33 16 DV 26 16 DV P]
   C-SHADE INK  [P 25 19 DV 27 25 DV 24 25 DV P] ;
: MOUTH ( -- )   C-RUBY INK  [P 22 28 DV 28 28 DV 27 30 DV 23 30 DV P] ;

: FACE-OVAL ( -- )   C-SKIN INK  25 21 9 11 DELL  21 29 29 36 DRECT ;

: BOARD ( -- )   C-CREAM INK  0 0 ART-W ART-H DRECT ;

: CHEVRONS ( y -- )     \ gold bands down the middle of the robe
   { y }
   C-GOLD INK   21 y 29 51 DRECT
   TRIM @ INK   23 y 27 51 DRECT
   C-GOLD INK
   4 0 DO  [P 21 y I 4 * + DV 29 y I 4 * + DV 25 y I 4 * + 3 + DV P]  LOOP ;

: ROBE-BODY ( -- )
   ROBE @ INK   [P 3 51 DV 47 51 DV 44 39 DV 34 34 DV 16 34 DV 6 39 DV P]
   TRIM @ INK   [P 3 51 DV 12 51 DV 13 40 DV 6 39 DV P]  [P 47 51 DV 38 51 DV 37 40 DV 44 39 DV P] ;

: ERMINE ( -- )
   C-WHITE INK  [P 13 42 DV 37 42 DV 34 33 DV 16 33 DV P]
   C-LINE INK   17 38 1 DCIRC  25 39 1 DCIRC  33 38 1 DCIRC  21 36 1 DCIRC  29 36 1 DCIRC ;

: JEWEL ( x y -- )   C-RUBY INK 2 DCIRC ;

: CROWN ( -- )
   C-GOLD INK
   [P 14 13 DV 36 13 DV 36 9 DV 14 9 DV P]
   [P 14 10 DV 19 10 DV 14 1 DV P]
   [P 20 10 DV 30 10 DV 25 -1 DV P]
   [P 31 10 DV 36 10 DV 36 1 DV P]
   C-DARK-GOLD INK  14 12 36 13 DRECT
   14 2 JEWEL  25 2 JEWEL  35 2 JEWEL  20 11 JEWEL  30 11 JEWEL ;

: SWORD ( -- )
   $C8D0D8 INK  [P 41 7 DV 45 7 DV 45 51 DV 41 51 DV P]  [P 41 7 DV 45 7 DV 43 0 DV P]
   $8890A0 INK  43 7 44 51 DRECT
   C-GOLD INK   37 32 49 35 DRECT ;

: KING ( -- )
   BOARD SWORD ROBE-BODY 42 CHEVRONS ERMINE
   $6A6470 INK  25 20 13 12 DELL
   FACE-OVAL EYES
   $8A8290 INK  [P 15 23 DV 35 23 DV 33 34 DV 25 38 DV 17 34 DV P]
   $6A6470 INK  [P 20 26 DV 25 25 DV 25 27 DV 18 28 DV P]  [P 30 26 DV 25 25 DV 25 27 DV 32 28 DV P]
   C-RUBY INK   [P 23 29 DV 27 29 DV 26 31 DV 24 31 DV P]
   CROWN ;

: TIARA ( -- )
   C-GOLD INK   [P 16 11 DV 34 11 DV 33 8 DV 17 8 DV P]
   [P 17 9 DV 22 9 DV 19 4 DV P]  [P 21 9 DV 29 9 DV 25 1 DV P]  [P 28 9 DV 33 9 DV 31 4 DV P]
   25 4 JEWEL ;

: FLOWER ( x y -- )
   { x y }
   $3C8A4A INK   x 1+ y x 2 + 51 DRECT
   ROBE @ INK   x 4 + y 3 DCIRC   x 3 - y 3 DCIRC   x y 4 - 3 DCIRC  x y 4 + 3 DCIRC
   C-GOLD INK   x y 2 DCIRC ;

: QUEEN ( -- )
   BOARD
   $4A2C1C INK   25 25 15 19 DELL   10 25 40 44 DRECT
   ROBE @ INK   [P 5 51 DV 45 51 DV 42 40 DV 33 35 DV 17 35 DV 8 40 DV P]
   TRIM @ INK   [P 5 51 DV 13 51 DV 15 40 DV 8 40 DV P]  [P 45 51 DV 37 51 DV 35 40 DV 42 40 DV P]
   C-SKIN INK   [P 18 34 DV 32 34 DV 25 46 DV P]
   C-GOLD INK   4 0 DO  [P 18 I 3 * + 36 I 2* + DV 21 I 3 * + 36 I 2* + DV 20 I 3 * + 38 I 2* + DV P]  LOOP
   5 0 DO  28 I 3 * + 42 I 2* - 1 DCIRC  LOOP
   FACE-OVAL EYES MOUTH
   $4A2C1C INK   [P 16 11 DV 34 11 DV 34 16 DV 26 13 DV 16 16 DV P]
   TIARA  43 27 FLOWER ;

: SPEAR ( -- )
   $8A5A2C INK  42 8 45 51 DRECT
   $C8D0D8 INK  [P 43 0 DV 47 8 DV 43 14 DV 40 8 DV P]
   C-GOLD INK   40 14 48 16 DRECT ;

: TUNIC ( -- )
   ROBE @ INK  [P 6 51 DV 44 51 DV 41 40 DV 33 36 DV 17 36 DV 9 40 DV P]
   C-GOLD INK  4 0 DO  10 I 8 * + 42 13 I 8 * + 51 DRECT  LOOP
   C-WHITE INK  [P 18 38 DV 32 38 DV 28 33 DV 22 33 DV P] ;

: JACK ( -- )
   BOARD SPEAR TUNIC
   $C87A2C INK   15 23 4 9 DELL   35 23 4 9 DELL
   FACE-OVAL EYES MOUTH
   ROBE @ INK   [P 13 13 DV 37 13 DV 35 4 DV 15 4 DV P]
   C-GOLD INK   12 12 38 15 DRECT
   C-WHITE INK  [P 33 8 DV 36 5 DV 46 0 DV 44 5 DV P]
   TRIM @ INK   [P 34 8 DV 44 3 DV 44 4 DV 35 8 DV P] ;

: PAINT-FACE ( rank suit -- )
   DUP ROBE-FOR ROBE !  TRIM-FOR TRIM !
   0 AX !  0 AY !  ART-ZOOM ZOOM !
   CASE  10 OF JACK ENDOF  11 OF QUEEN ENDOF  12 OF KING ENDOF  ENDCASE ;

: ART-PX { x y | r g b v -- rgb }
   ART-ZOOM 0 DO ART-ZOOM 0 DO
      x ART-ZOOM * I +  y ART-ZOOM * J +  GFX-PGET TO v
      v 16 RSHIFT 255 AND r + TO r
      v 8 RSHIFT 255 AND g + TO g
      v 255 AND b + TO b
   LOOP LOOP
   r 9 / 16 LSHIFT  g 9 / 8 LSHIFT OR  b 9 / OR ;

: PLACE-ART ( -- )
   ART-H 0 DO ART-W 0 DO
      I J ART-PX
      DUP I ART-X +  J ART-Y + BUF-XY !
      ART-W 1- I - ART-X +  ART-H 2* 1- J - ART-Y + BUF-XY !
   LOOP LOOP ;
: FRAME-ART ( -- )
   TRIM @ { c }
   ART-X 1-  ART-Y 1-  ART-W 2 +  ART-H 2* 2 +  { x y bw bh }
   bw 0 DO  c x I + y BUF-XY !   c x I + y bh 1- + BUF-XY !  LOOP
   bh 0 DO  c x y I + BUF-XY !   c x bw 1- + y I + BUF-XY !  LOOP
   ART-W 0 DO  c  ART-X I +  ART-Y ART-H + BUF-XY !  LOOP ;
: FACE-PIP ( -- )
   CUR-SUIT @ K-MID SUIT-MASK { m }
   ART-X 2 +  ART-Y 2 +  m CUR-INK @ FALSE STAMP-MASK
   ART-X 2 +  ART-Y 2 +  m CUR-INK @ TRUE STAMP-MASK ;

CREATE FACES 52 CELLS ALLOT
VARIABLE BACK-SPR
: MAKE-CARD { rank suit -- a }
   CARD-BUF BASE-BUF SWAP CW CH * CELLS MOVE
   suit CUR-SUIT !  suit SUIT-INK CUR-INK !
   rank INDEX
   rank 0= IF  ACE-PIP  ELSE
   rank 10 < IF  rank PIPS  ELSE
      KEY-COLOR GFX-CLS  rank suit PAINT-FACE  PLACE-ART FRAME-ART FACE-PIP
   THEN THEN
   CW CH ['] BUF-PX BAKE ;

: BACK-PX { x y | u v c -- c }     \ a blue lattice inside a white margin
   x 6 - TO u  y 6 - TO v
   u 0 CW 12 - WITHIN  v 0 CH 12 - WITHIN AND 0= IF -2 EXIT THEN
   $1F3A78
   u v + 10 MOD 0= u v - 1000 + 10 MOD 0= OR IF DROP $5578C8 THEN ;
: MAKE-BACK ( -- )
   CARD-BUF BASE-BUF SWAP CW CH * CELLS MOVE
   CH 0 DO CW 0 DO
      I J BACK-PX  DUP -2 <> IF  I J BUF-XY !  ELSE DROP THEN
   LOOP LOOP
   \ the ring and the sign of the sum in the middle
   CH 0 DO CW 0 DO
      I CW 2/ - DUP *  J CH 2/ - DUP * + { dd }
      dd 22 22 * < IF  $1F3A78 I J BUF-XY !  THEN
      dd 22 22 * >= dd 25 25 * < AND IF  C-GOLD I J BUF-XY !  THEN
   LOOP LOOP
   CW 32 - 2/  CH 44 - 2/  SIGMA-MASK @  C-GOLD  FALSE STAMP-MASK
   CW CH ['] BUF-PX BAKE BACK-SPR ! ;

: MAKE-CARDS ( -- )
   PAPER-SHAPE
   52 0 DO  I 13 MOD I 13 / MAKE-CARD  I CELLS FACES + !  LOOP
   MAKE-BACK ;

\ The empty places: a darker shape, with a faint letter or ring.
$17593F CONSTANT C-SLOT   $2F8560 CONSTANT C-SLOT-LINE   $1E6A4C CONSTANT C-SLOT-RIM
VARIABLE SLOT-A   VARIABLE SLOT-K   VARIABLE SLOT-O   VARIABLE SLOT-P
: SLOT-SHAPE ( -- )   C-SLOT C-SLOT-LINE C-SLOT-RIM MAKE-SHAPE ;
: GHOST ( rank -- )
   CELLS RANK-MASKS + @ { m }
   CW m @ - 2/  CH m CELL+ @ - 2/  m C-SLOT-LINE FALSE STAMP-MASK ;
: MAKE-SLOTS ( -- )
   SLOT-SHAPE            CW CH ['] BUF-PX BAKE SLOT-P !
   SLOT-SHAPE  0 GHOST   CW CH ['] BUF-PX BAKE SLOT-A !
   SLOT-SHAPE  12 GHOST  CW CH ['] BUF-PX BAKE SLOT-K !
   SLOT-SHAPE
   CH 0 DO CW 0 DO
      I CW 2/ - DUP *  J CH 2/ - DUP * + { dd }
      dd 20 20 * >= dd 24 24 * < AND IF  C-SLOT-LINE I J BUF-XY !  THEN
   LOOP LOOP
   CW CH ['] BUF-PX BAKE SLOT-O ! ;

\ ---- The table and the text --------------------------------------------------------

\ The cloth: lighter at the top, one row in two a little darker, like a woven thread.
VARIABLE FELT
: FELT-PX ( x y -- rgb )
   NIP { y }
   $287A58 $125038 y 255 * H / MIX-RGB
   y 1 AND IF $000000 10 MIX-RGB THEN ;

$0E3A2A CONSTANT C-BAR   $FFF4D6 CONSTANT C-TEXT   $9CC8B4 CONSTANT C-LABEL
40 CONSTANT BAR-H

: USE-FONT ( height -- )     \ a smooth font where the system has one
   >R S" Segoe UI Semibold" R@ ['] SYSTEM-FONT CATCH
   IF  2DROP DROP  BUILTIN-FONT  R> 8 / 1 MAX TEXT-SCALE
   ELSE  R> DROP  1 TEXT-SCALE  THEN ;

: TEXT-SPRITE { a u fg bg | bw bh -- spr }
   a u TEXT-WIDTH TO bw   TEXT-HEIGHT TO bh
   bg GFX-CLS  fg INK  a u 0 0 TEXT
   bw bh ['] CANVAS-PX BAKE ;

CREATE DIGITS 10 CELLS ALLOT
VARIABLE COLON-SPR   VARIABLE DIGIT-W
CREATE BIG-DIGITS 10 CELLS ALLOT
VARIABLE L-SCORE   VARIABLE L-MOVES   VARIABLE L-TIME
VARIABLE WIN-TITLE   VARIABLE WIN-HINT   VARIABLE BIG-W   VARIABLE L-WIN-SCORE

8 CONSTANT #BTN-ART
7 CONSTANT #BTN
60 CONSTANT BTN-W   26 CONSTANT BTN-H   7 CONSTANT BTN-Y
CREATE BTN-SPR #BTN-ART 3 * CELLS ALLOT
: BTN-X ( n -- x )   64 * 344 + ;

: ROUNDED { x y bw bh c -- }
   c INK
   bh 0 DO  x 4 + x bw + 5 -  y I + c GFX-HLINE  LOOP
   x y 4 + bw bh 8 - FILL-RECT
   x 4 + y 4 + 4 FILL-CIRCLE   x bw + 5 - y 4 + 4 FILL-CIRCLE
   x 4 + y bh + 5 - 4 FILL-CIRCLE   x bw + 5 - y bh + 5 - 4 FILL-CIRCLE ;

: BUTTON-SPRITE { a u fg bg -- spr }
   C-BAR GFX-CLS
   0 0 BTN-W BTN-H bg ROUNDED
   fg INK
   a u  BTN-W a u TEXT-WIDTH - 2/  BTN-H TEXT-HEIGHT - 2/  TEXT
   BTN-W BTN-H ['] CANVAS-PX BAKE ;

: BUTTON-3 { a u n -- }
   a u C-TEXT $1E6B4F BUTTON-SPRITE  BTN-SPR n 3 * CELLS + !
   a u $FFFFFF $2F936E BUTTON-SPRITE  BTN-SPR n 3 * 1+ CELLS + !
   a u $20180A $F0C030 BUTTON-SPRITE  BTN-SPR n 3 * 2 + CELLS + ! ;

: DIGIT$ ( n -- c-addr 1 )   S" 0123456789" DROP + 1 ;

: MAKE-TEXT ( -- )
   \ the table
   W H ['] FELT-PX BAKE FELT !
   \ the bar
   15 USE-FONT
   S" SCORE" C-LABEL C-BAR TEXT-SPRITE L-SCORE !
   S" MOVES" C-LABEL C-BAR TEXT-SPRITE L-MOVES !
   S" TIME"  C-LABEL C-BAR TEXT-SPRITE L-TIME !
   S" 0" TEXT-WIDTH DIGIT-W !
   10 0 DO  I DIGIT$ C-TEXT C-BAR TEXT-SPRITE  DIGITS I CELLS + !  LOOP
   S" :" C-TEXT C-BAR TEXT-SPRITE COLON-SPR !
   13 USE-FONT
   S" New"     0 BUTTON-3
   S" Restart" 1 BUTTON-3
   S" Undo"    2 BUTTON-3
   S" Hint"    3 BUTTON-3
   S" Auto"    4 BUTTON-3
   S" Draw 1"  5 BUTTON-3
   S" Quit"    6 BUTTON-3
   S" Draw 3"  7 BUTTON-3
   \ the end of the game
   52 USE-FONT
   S" You won!" C-GOLD $0B2C20 TEXT-SPRITE WIN-TITLE !
   30 USE-FONT
   S" 0" TEXT-WIDTH BIG-W !
   10 0 DO  I DIGIT$ C-TEXT $0B2C20 TEXT-SPRITE  BIG-DIGITS I CELLS + !  LOOP
   S" Score" C-LABEL $0B2C20 TEXT-SPRITE L-WIN-SCORE !
   17 USE-FONT
   S" Click for a new deal" C-LABEL $0B2C20 TEXT-SPRITE WIN-HINT ! ;

: BAKE-ALL ( -- )
   MAKE-SINE
   512 256 GFX-INIT
   MAKE-SUIT-MASKS  MAKE-GLYPHS  MAKE-CARDS  MAKE-SLOTS
   MAKE-TEXT ;

\ ---- The game ----------------------------------------------------------------------
\ Piles: 0 the stock, 1 the waste, 2-5 the foundations, 6-12 the columns.
\ A pile is its count and its cards, bottom first. A card is 0..51 (13 ranks of each
\ suit, the ace first), with $40 added when it lies face up.

0 CONSTANT P-STOCK   1 CONSTANT P-WASTE   2 CONSTANT P-F0   6 CONSTANT P-T0   13 CONSTANT #PILES
56 CONSTANT PILE-SIZE
$40 CONSTANT UP-BIT

#PILES PILE-SIZE * CONSTANT PILES-SIZE
PILES-SIZE 6 CELLS + CONSTANT GS-SIZE
CREATE GS GS-SIZE ALLOT              \ all that undo brings back
GS CONSTANT PILES
GS PILES-SIZE + CONSTANT SCORE
SCORE CELL+ CONSTANT MOVES
MOVES CELL+ CONSTANT PASSES
PASSES CELL+ CONSTANT FAN            \ how many waste cards lie spread out
FAN CELL+ CONSTANT DRAW3
DRAW3 CELL+ CONSTANT DEAL-NO

\ An undo slot is packed: each pile as its count and its cards, then the numbers.
#PILES 52 + 6 CELLS + CONSTANT SLOT-SIZE
500 CONSTANT UNDO-MAX
CREATE UNDO-RING UNDO-MAX SLOT-SIZE * ALLOT
VARIABLE U-TOP   VARIABLE U-DEPTH

VARIABLE WON         VARIABLE WIN-T     VARIABLE WINS
VARIABLE DONE        VARIABLE DIRTY     VARIABLE AUTO-ON   VARIABLE AUTO-T
VARIABLE ELAPSED     VARIABLE LAST-NOW  VARIABLE LAST-SECS

: CID ( c -- id )   $3F AND ;
: UP? ( c -- flag )   UP-BIT AND 0<> ;
: RANK ( c -- r )   CID 13 MOD ;
: SUIT ( c -- s )   CID 13 / ;
: RED? ( c -- flag )   SUIT 1 AND 0<> ;

: PILE ( p -- a )   PILE-SIZE * PILES + ;
: #CARDS ( p -- n )   PILE C@ ;
: SET-COUNT ( n p -- )   PILE C! ;
: CARD@ ( p n -- c )   SWAP PILE + 1+ C@ ;
: CARD! ( c p n -- )   SWAP PILE + 1+ C! ;
: TOP-CARD ( p -- c )   DUP #CARDS 1- CARD@ ;
: PUSH-CARD { c p -- }   c p p #CARDS CARD!  p #CARDS 1+ p SET-COUNT ;
: POP-CARD ( p -- c )   DUP TOP-CARD SWAP  DUP #CARDS 1- SWAP SET-COUNT ;
: FOUND? ( p -- flag )   P-F0 P-T0 WITHIN ;
: COLUMN? ( p -- flag )   P-T0 #PILES WITHIN ;

: +SCORE ( n -- )   SCORE @ + 0 MAX SCORE ! ;

: COL-X ( col -- x )   108 * 32 + ;
48 CONSTANT TOP-Y    192 CONSTANT TAB-Y
9 CONSTANT DOWN-GAP  26 CONSTANT UP-GAP-MAX

: BASE-X ( p -- x )
   DUP 2 < IF ELSE DUP P-T0 < IF 1+ ELSE P-T0 - THEN THEN  COL-X ;
: BASE-Y ( p -- y )   COLUMN? IF TAB-Y ELSE TOP-Y THEN ;

: #DOWN { p | n -- d }
   BEGIN  n p #CARDS <  IF p n CARD@ UP? 0= ELSE FALSE THEN  WHILE  n 1+ TO n  REPEAT  n ;

: UP-GAP { p | d u -- g }
   p #DOWN TO d   p #CARDS d - TO u
   u 2 < IF UP-GAP-MAX EXIT THEN
   H 10 - TAB-Y - CH - d DOWN-GAP * -  u 1- /  UP-GAP-MAX MIN  10 MAX ;

: FIRST-FAN ( -- n )   P-WASTE #CARDS DUP FAN @ MIN - ;

: CARD-XY { p n | d -- x y }
   p P-WASTE = IF
      p BASE-X  n FIRST-FAN - 0 MAX 24 * +  TOP-Y EXIT
   THEN
   p COLUMN? IF
      p #DOWN TO d
      p BASE-X   TAB-Y  n d MIN DOWN-GAP * +  n d - 0 MAX p UP-GAP * +  EXIT
   THEN
   p BASE-X TOP-Y ;

\ ---- The cards in flight ------------------------------------------------------------

64 CONSTANT MAX-F
9 CONSTANT F-CELLS
CREATE FLIGHTS MAX-F F-CELLS * CELLS ALLOT
VARIABLE #F
CREATE HIDDEN 64 ALLOT
: F[] ( n -- a )   F-CELLS * CELLS FLIGHTS + ;
: FIELD@ ( a n -- v )   CELLS + @ ;

: CLEAR-FLIGHTS ( -- )   0 #F !  HIDDEN 64 ERASE ;
: FLY { c x0 y0 x1 y1 delay dur flip snd | a -- }
   #F @ MAX-F >= IF EXIT THEN
   #F @ F[] TO a
   c a !  x0 a CELL+ !  y0 a 2 CELLS + !  x1 a 3 CELLS + !  y1 a 4 CELLS + !
   delay NEGATE a 5 CELLS + !  dur a 6 CELLS + !  flip a 7 CELLS + !  snd a 8 CELLS + !
   HIDDEN c CID + DUP C@ 1+ SWAP C!  1 #F +! ;
: C-HIDDEN? ( c -- flag )   CID HIDDEN + C@ 0<> ;

: LAND { n | a -- }
   n F[] TO a
   a @ CID HIDDEN + DUP C@ 1- SWAP C!
   a 8 CELLS + @ DUP 0>= IF EFFECT ELSE DROP THEN
   n 1+ F[]  n F[]  #F @ n - 1- F-CELLS * CELLS  MOVE
   -1 #F +! ;

: STEP-FLIGHTS { | n a -- }
   BEGIN n #F @ < WHILE
      n F[] TO a
      1 a 5 CELLS + +!
      a 5 CELLS + @  a 6 CELLS + @  >= IF  n LAND  ELSE  n 1+ TO n  THEN
   REPEAT ;

\ ---- The moves ----------------------------------------------------------------------

: U-SLOT ( n -- a )   UNDO-MAX MOD SLOT-SIZE * UNDO-RING + ;
: PACK { a -- }
   #PILES 0 DO
      I PILE  a  I PILE C@ 1+  DUP a + TO a  MOVE
   LOOP
   SCORE a 6 CELLS MOVE ;
: UNPACK { a -- }
   #PILES 0 DO
      a  I PILE  a C@ 1+  DUP a + TO a  MOVE
   LOOP
   a SCORE 6 CELLS MOVE ;
: SAVE-UNDO ( -- )
   U-TOP @ U-SLOT PACK
   1 U-TOP +!   U-DEPTH @ 1+ UNDO-MAX MIN U-DEPTH ! ;
: UNDO ( -- )
   U-DEPTH @ 0= IF  S-BAD EFFECT EXIT  THEN
   -1 U-TOP +!  -1 U-DEPTH +!
   U-TOP @ U-SLOT UNPACK
   CLEAR-FLIGHTS  FALSE WON !  FALSE AUTO-ON !  TRUE DIRTY !
   S-FLIP EFFECT ;

: CAN-COLUMN? { c p -- flag }
   p #CARDS 0= IF  c RANK 12 =  EXIT THEN
   p TOP-CARD { t }
   t UP?  c RED? t RED? <> AND  c RANK 1+ t RANK = AND ;
: CAN-FOUND? { c p -- flag }
   p #CARDS 0= IF  c RANK 0=  EXIT THEN
   p TOP-CARD { t }
   c SUIT t SUIT =  c RANK t RANK 1+ = AND ;

: CAN-DROP? { src n dst | cnt c -- flag }
   src dst = IF FALSE EXIT THEN
   src #CARDS n - TO cnt
   src n CARD@ TO c
   dst FOUND? IF  cnt 1 =  c dst CAN-FOUND? AND  EXIT THEN
   dst COLUMN? IF  c dst CAN-COLUMN?  EXIT THEN
   FALSE ;

\ Where a click sends a card: to a foundation, or to a column, empty columns last.
: AUTO-DEST { src n | c -- dst | -1 }
   src FOUND? 0= IF
      P-T0 P-F0 DO  src n I CAN-DROP? IF I UNLOOP EXIT THEN  LOOP
   THEN
   #PILES P-T0 DO
      I #CARDS IF  src n I CAN-DROP? IF I UNLOOP EXIT THEN  THEN
   LOOP
   \ a king already at the foot of a column has no reason to go to another
   src COLUMN? n 0= AND IF -1 EXIT THEN
   #PILES P-T0 DO
      I #CARDS 0= IF  src n I CAN-DROP? IF I UNLOOP EXIT THEN  THEN
   LOOP
   -1 ;

CREATE START-XY 13 2* CELLS ALLOT
VARIABLE DRAG-FROM?   VARIABLE DRAG-AT-X   VARIABLE DRAG-AT-Y

: REMEMBER-STARTS { src n cnt -- }
   cnt 0 DO
      DRAG-FROM? @ IF  DRAG-AT-X @  DRAG-AT-Y @ I UP-GAP-MAX * +
      ELSE  src n I + CARD-XY  THEN
      START-XY I 2* CELLS + 2!
   LOOP ;

: REVEAL { p | c x y -- }
   p COLUMN? 0= IF EXIT THEN
   p #CARDS 0= IF EXIT THEN
   p TOP-CARD UP? IF EXIT THEN
   p TOP-CARD UP-BIT OR TO c
   c p  p #CARDS 1- CARD!
   5 +SCORE
   p p #CARDS 1- CARD-XY TO y TO x
   c x y x y 0 12 TRUE S-FLIP FLY ;

: MOVE-SCORE { src dst -- }
   src P-WASTE =  dst COLUMN? AND IF 5 +SCORE THEN
   src P-WASTE =  dst FOUND? AND IF 10 +SCORE THEN
   src COLUMN?  dst FOUND? AND IF 10 +SCORE THEN
   src FOUND?  dst COLUMN? AND IF -15 +SCORE THEN ;

: DO-MOVE { src n dst | cnt base snd -- }
   SAVE-UNDO
   src #CARDS n - TO cnt
   dst #CARDS TO base
   src n cnt REMEMBER-STARTS
   cnt 0 DO  src n I + CARD@ dst PUSH-CARD  LOOP
   n src SET-COUNT
   src P-WASTE = IF  FAN @ 1- 1 MAX FAN !  THEN
   src dst MOVE-SCORE
   dst FOUND? IF S-FOUND ELSE S-PLACE THEN TO snd
   cnt 0 DO
      dst base I + CARD@
      START-XY I 2* CELLS + 2@
      dst base I + CARD-XY
      0 11 FALSE   I 0= IF snd ELSE -1 THEN   FLY
   LOOP
   src REVEAL
   1 MOVES +!  TRUE DIRTY ! ;

: RECYCLE ( -- )
   P-WASTE #CARDS 0= IF  S-BAD EFFECT EXIT  THEN
   SAVE-UNDO
   BEGIN P-WASTE #CARDS WHILE  P-WASTE POP-CARD CID P-STOCK PUSH-CARD  REPEAT
   1 FAN !
   1 PASSES +!
   DRAW3 @ IF  PASSES @ 3 >= IF -20 +SCORE THEN  ELSE  -100 +SCORE  THEN
   S-SHUFFLE EFFECT  TRUE DIRTY ! ;

: DRAW-CARDS { | cnt base c -- }
   P-STOCK #CARDS 0= IF  RECYCLE EXIT  THEN
   SAVE-UNDO
   DRAW3 @ IF 3 ELSE 1 THEN  P-STOCK #CARDS MIN TO cnt
   P-WASTE #CARDS TO base
   cnt 0 DO  P-STOCK POP-CARD UP-BIT OR  P-WASTE PUSH-CARD  LOOP
   cnt FAN !
   cnt 0 DO
      P-WASTE base I + CARD@
      P-STOCK BASE-X  TOP-Y
      P-WASTE base I + CARD-XY
      I 3 *  10  TRUE  I 0= IF S-FLIP ELSE -1 THEN  FLY
   LOOP
   1 MOVES +!  TRUE DIRTY ! ;

\ ---- Dealing ------------------------------------------------------------------------

CREATE DECK 52 ALLOT

: SHUFFLE-DECK ( -- )
   52 0 DO  I DECK I + C!  LOOP
   52 1 DO
      I 1+ RND  { k }
      DECK k + C@   DECK I + C@  DECK k + C!  DECK I + C!
   LOOP ;

: START-DEAL { no | c n -- }
   CLEAR-FLIGHTS
   PILES PILES-SIZE ERASE
   0 SCORE !  0 MOVES !  0 PASSES !  1 FAN !  no DEAL-NO !
   FALSE WON !  0 WIN-T !  FALSE AUTO-ON !  0 ELAPSED !
   no SEED !  20 0 DO  1 RND DROP  LOOP
   SHUFFLE-DECK
   52 0 DO  DECK I + C@ P-STOCK PUSH-CARD  LOOP
   7 0 DO
      7 I DO
         P-STOCK POP-CARD  I J = IF UP-BIT OR THEN  P-T0 I + PUSH-CARD
      LOOP
   LOOP
   7 0 DO
      7 I DO
         P-T0 I + J CARD@
         P-STOCK BASE-X  TOP-Y
         P-T0 I + J CARD-XY
         n 2*  12  P-T0 I + J CARD@ UP?  -1  FLY
         n 1+ TO n
      LOOP
   LOOP
   S-SHUFFLE EFFECT
   TRUE DIRTY ! ;

: KEEP-GAME ( -- )   MOVES @ 0> IF SAVE-UNDO THEN ;
: NEW-DEAL ( -- )   KEEP-GAME  NOW 0 MAX 99999 MOD 1+ START-DEAL ;
: SAME-DEAL ( -- )   KEEP-GAME  DEAL-NO @ START-DEAL ;
: TOGGLE-DRAW ( -- )   KEEP-GAME  DRAW3 @ 0= DRAW3 !  DEAL-NO @ START-DEAL ;

\ ---- Help and the end of the game ---------------------------------------------------

VARIABLE HINT-T   VARIABLE HINT-SRC   VARIABLE HINT-N   VARIABLE HINT-DST

: SET-HINT ( src n dst -- )   HINT-DST ! HINT-N ! HINT-SRC !  90 HINT-T !  TRUE DIRTY ! ;

: HINT-FOUND ( -- flag )   \ a card that can go to a foundation
   #PILES P-WASTE DO
      I FOUND? 0=  I #CARDS 0<> AND IF
         P-T0 P-F0 DO
            J  J #CARDS 1-  I  CAN-DROP? IF  J J #CARDS 1- I SET-HINT  TRUE UNLOOP UNLOOP EXIT THEN
         LOOP
      THEN
   LOOP FALSE ;
: HINT-RUN ( -- flag )     \ a run that uncovers a card or frees a column
   #PILES P-T0 DO
      I #DOWN 0>  I #DOWN I #CARDS < AND  IF
         I  I #DOWN  AUTO-DEST  DUP P-T0 >= IF
            I I #DOWN ROT SET-HINT  TRUE UNLOOP EXIT
         THEN DROP
      THEN
   LOOP FALSE ;
: HINT-WASTE ( -- flag )
   P-WASTE #CARDS 0= IF FALSE EXIT THEN
   P-WASTE  P-WASTE #CARDS 1-  AUTO-DEST  DUP 0>= IF
      P-WASTE P-WASTE #CARDS 1- ROT SET-HINT  TRUE EXIT
   THEN DROP FALSE ;
: HINT-STOCK ( -- flag )
   P-STOCK #CARDS P-WASTE #CARDS OR 0= IF FALSE EXIT THEN
   P-STOCK -1 -1 SET-HINT  TRUE ;

: HINT ( -- )
   HINT-FOUND IF EXIT THEN   HINT-RUN IF EXIT THEN
   HINT-WASTE IF EXIT THEN   HINT-STOCK IF EXIT THEN
   S-BAD EFFECT ;

: AUTO-STEP ( -- flag )    \ one card to a foundation, if any can go
   #PILES P-WASTE DO
      I FOUND? 0=  I #CARDS 0<> AND IF
         P-T0 P-F0 DO
            J  J #CARDS 1-  I  CAN-DROP? IF  J J #CARDS 1- I DO-MOVE  TRUE UNLOOP UNLOOP EXIT THEN
         LOOP
      THEN
   LOOP FALSE ;

: FINISHED? ( -- flag )
   TRUE  P-T0 P-F0 DO  I #CARDS 13 = AND  LOOP ;
\ Nothing is left to find: every column is face up and the stock and the waste are out.
: READY? ( -- flag )
   P-STOCK #CARDS P-WASTE #CARDS OR IF FALSE EXIT THEN
   TRUE  #PILES P-T0 DO  I #DOWN 0= AND  LOOP ;

\ ---- The mouse ----------------------------------------------------------------------

VARIABLE MX   VARIABLE MY   VARIABLE MB   VARIABLE OLD-B
VARIABLE D-SRC   VARIABLE D-IDX   VARIABLE D-OX   VARIABLE D-OY
VARIABLE D-PX    VARIABLE D-PY    VARIABLE D-MOVED

: IN-CARD? { x y rx ry -- flag }   x rx - 0 CW WITHIN  y ry - 0 CH WITHIN AND ;

: HIT-COLUMN { x y p -- p n | -1 -1 }
   p #CARDS 0= IF -1 -1 EXIT THEN
   0 p #CARDS 1- DO
      x y p I CARD-XY IN-CARD? IF
         p I CARD@ UP? IF p I ELSE -1 -1 THEN  UNLOOP EXIT
      THEN
   -1 +LOOP
   -1 -1 ;

: HIT-TOP { x y p -- p n | -1 -1 }
   p #CARDS 0= IF -1 -1 EXIT THEN
   x y p p #CARDS 1- CARD-XY IN-CARD? IF p p #CARDS 1- ELSE -1 -1 THEN ;

: HIT-PILE { x y -- p n | -1 -1 }
   x y P-STOCK BASE-X TOP-Y IN-CARD? IF P-STOCK 0 EXIT THEN
   x y P-WASTE HIT-TOP OVER 0>= IF EXIT THEN 2DROP
   P-T0 P-F0 DO  x y I HIT-TOP OVER 0>= IF UNLOOP EXIT THEN 2DROP  LOOP
   #PILES P-T0 DO  x y I HIT-COLUMN OVER 0>= IF UNLOOP EXIT THEN 2DROP  LOOP
   -1 -1 ;

: BTN-AT { x y -- n | -1 }
   y BTN-Y BTN-Y BTN-H + WITHIN 0= IF -1 EXIT THEN
   #BTN 0 DO  x  I BTN-X  DUP BTN-W + WITHIN IF I UNLOOP EXIT THEN  LOOP
   -1 ;

: DRAW-LABEL-ART ( n -- art )   DUP 5 = DRAW3 @ AND IF DROP 7 THEN ;

: QUIT-GAME ( -- )   TRUE DONE ! ;
: START-AUTO ( -- )   TRUE AUTO-ON !  0 AUTO-T ! ;

: BTN-PRESS ( n -- )
   CASE
      0 OF NEW-DEAL ENDOF
      1 OF SAME-DEAL ENDOF
      2 OF UNDO ENDOF
      3 OF HINT ENDOF
      4 OF START-AUTO ENDOF
      5 OF TOGGLE-DRAW ENDOF
      6 OF QUIT-GAME ENDOF
   ENDCASE ;

: DRAG-X ( -- x )   MX @ D-OX @ - ;
: DRAG-Y ( -- y )   MY @ D-OY @ - ;

: ON-PRESS { x y | p n -- }
   CLEAR-FLIGHTS  FALSE AUTO-ON !  0 HINT-T !  TRUE DIRTY !
   WON @ IF  NEW-DEAL EXIT  THEN
   x y BTN-AT DUP 0>= IF  BTN-PRESS EXIT  THEN DROP
   x y HIT-PILE TO n TO p
   p 0< IF EXIT THEN
   p P-STOCK = IF  DRAW-CARDS EXIT  THEN
   p D-SRC !  n D-IDX !  FALSE D-MOVED !
   x D-PX !  y D-PY !
   p n CARD-XY  y SWAP - D-OY !  x SWAP - D-OX ! ;

: BEST-DROP { | best area rx ry ox oy d -- dst | -1 }
   -1 TO d
   #PILES P-F0 DO
      D-SRC @ D-IDX @ I CAN-DROP? IF
         I #CARDS IF  I I #CARDS 1- CARD-XY  ELSE  I BASE-X I BASE-Y  THEN  TO ry TO rx
         CW DRAG-X rx - ABS -  TO ox
         CH DRAG-Y ry - ABS -  TO oy
         ox 0>  oy 0> AND IF
            ox oy * TO area
            area best > IF  area TO best  I TO d  THEN
         THEN
      THEN
   LOOP
   d ;

: SPRING-BACK { | cnt c -- }
   D-SRC @ #CARDS D-IDX @ - TO cnt
   cnt 0 DO
      D-SRC @ D-IDX @ I + CARD@
      DRAG-X  DRAG-Y I UP-GAP-MAX * +
      D-SRC @ D-IDX @ I + CARD-XY
      0 10 FALSE -1 FLY
   LOOP ;

: ON-RELEASE { | d -- }
   D-SRC @ 0< IF EXIT THEN
   D-MOVED @ IF
      BEST-DROP TO d
      d 0>= IF
         TRUE DRAG-FROM? !  DRAG-X DRAG-AT-X !  DRAG-Y DRAG-AT-Y !
         D-SRC @ D-IDX @ d DO-MOVE
         FALSE DRAG-FROM? !
      ELSE  SPRING-BACK  THEN
   ELSE
      D-SRC @ D-IDX @ AUTO-DEST TO d
      d 0>= IF  D-SRC @ D-IDX @ d DO-MOVE  ELSE  S-BAD EFFECT  THEN
   THEN
   -1 D-SRC !  FALSE D-MOVED !  TRUE DIRTY ! ;

VARIABLE HOVER
: READ-MOUSE { | x y b h -- }
   MOUSE TO b TO y TO x
   x y BTN-AT TO h
   h HOVER @ <> IF  h HOVER !  TRUE DIRTY !  THEN
   x MX !  y MY !  b MB !
   b 1 AND  OLD-B @ 1 AND 0= AND  x 0>= AND IF  x y ON-PRESS  THEN
   b 2 AND  OLD-B @ 2 AND 0= AND  WON @ 0= AND IF  CLEAR-FLIGHTS 0 HINT-T ! START-AUTO  THEN
   D-SRC @ 0>= IF
      D-MOVED @ 0= IF
         x D-PX @ - ABS  y D-PY @ - ABS +  4 > IF  TRUE D-MOVED !  THEN
      THEN
      D-MOVED @ IF TRUE DIRTY ! THEN
   THEN
   b 1 AND 0=  OLD-B @ 1 AND 0<> AND IF  ON-RELEASE  THEN
   b OLD-B ! ;

\ ---- The picture --------------------------------------------------------------------

: ART ( c -- a )   DUP UP? IF CID CELLS FACES + @ ELSE DROP BACK-SPR @ THEN ;

: DRAW-CARD ( x y lim c -- )   ART BLIT ;

: VISIBLE { p | n -- n' }
   p #CARDS TO n
   D-SRC @ p =  D-MOVED @ AND IF  D-IDX @ TO n  THEN
   BEGIN  n 0> IF  p n 1- CARD@ C-HIDDEN?  ELSE FALSE THEN  WHILE  n 1- TO n  REPEAT
   n ;

: DRAW-STOCK ( -- )
   P-STOCK BASE-X TOP-Y
   P-STOCK #CARDS IF  BACK-SPR @ SPR  ELSE  SLOT-O @ SPR  THEN ;

: DRAW-WASTE { | v first -- }
   P-WASTE VISIBLE TO v
   v 0= IF  P-WASTE BASE-X TOP-Y SLOT-P @ SPR  EXIT  THEN
   FIRST-FAN 1- 0 MAX  v 1- MIN TO first      \ the card below shows while the top one flies
   v first DO  P-WASTE I CARD-XY 999  P-WASTE I CARD@  DRAW-CARD  LOOP ;

: DRAW-FOUNDATION { p | v -- }
   p VISIBLE TO v
   v IF  p BASE-X TOP-Y 999  p v 1- CARD@  DRAW-CARD
   ELSE  p BASE-X TOP-Y SLOT-A @ SPR  THEN ;

: DRAW-COLUMN { p | v y0 -- }
   p VISIBLE TO v
   v 0= IF  p BASE-X TAB-Y SLOT-K @ SPR  EXIT  THEN
   v 0 DO
      p I CARD-XY DUP TO y0
      I v 1- < IF  p I 1+ CARD-XY NIP y0 - CORNER 1+ +  ELSE 999 THEN
      p I CARD@  DRAW-CARD
   LOOP ;

: DRAW-FLIGHT { a | t dur q x y c -- }
   a 5 FIELD@ TO t   t 0< IF EXIT THEN
   a 6 FIELD@ TO dur   dur t - TO q
   a 3 FIELD@  a 1 FIELD@ OVER -  q * q * dur / dur / +  TO x
   a 4 FIELD@  a 2 FIELD@ OVER -  q * q * dur / dur / +  TO y
   a @ TO c
   a 7 FIELD@ IF
      t 2* dur < IF  x y BACK-SPR @  dur t 2* - 256 * dur /  BLIT-THIN
      ELSE           x y c ART       t 2* dur - 256 * dur /  BLIT-THIN  THEN
   ELSE  x y 999 c DRAW-CARD  THEN ;

\ A soft shadow: the picture under it made darker, pixel by pixel.
: SHADE { x y bw bh -- }
   bh 0 DO bw 0 DO
      x I + y J + GFX-PGET DUP 0>= IF
         0 80 MIX-RGB  x I + y J + ROT GFX-PSET
      ELSE DROP THEN
   LOOP LOOP ;

: BOX-AROUND { x y bw bh c -- }
   c COLOR!
   x 3 - y 3 - bw 6 + 3 FILL-RECT    x 3 - y bh + bw 6 + 3 FILL-RECT
   x 3 - y 3 - 3 bh 6 + FILL-RECT    x bw + y 3 - 3 bh 6 + FILL-RECT ;

: PILE-TARGET-XY ( p -- x y )
   DUP #CARDS IF  DUP #CARDS 1- CARD-XY  ELSE  DUP BASE-X SWAP BASE-Y  THEN ;

: DRAW-DRAG { | cnt x y total d -- }
   D-MOVED @ 0= IF EXIT THEN
   D-SRC @ #CARDS D-IDX @ - TO cnt
   DRAG-X TO x   DRAG-Y TO y
   CH cnt 1- UP-GAP-MAX * + TO total
   BEST-DROP TO d
   d 0>= IF  d PILE-TARGET-XY CW CH $70F0B0 BOX-AROUND  THEN
   x CW + y 6 + 5 total SHADE
   x 6 + y total + CW 1- 5 SHADE
   cnt 0 DO
      x  y I UP-GAP-MAX * +
      I cnt 1- < IF UP-GAP-MAX CORNER 1+ + ELSE 999 THEN
      D-SRC @ D-IDX @ I + CARD@  DRAW-CARD
   LOOP ;

: DRAW-HINT { | c -- }
   HINT-T @ 0= IF EXIT THEN
   $F0C030 $FFFFFF  HINT-T @ 8 * ISIN 1024 + 256 * 2048 / 255 MIN  MIX-RGB TO c
   HINT-SRC @ P-STOCK = IF  P-STOCK BASE-X TOP-Y CW CH c BOX-AROUND  EXIT  THEN
   HINT-SRC @ HINT-N @ CARD-XY  CW
   HINT-SRC @ DUP #CARDS 1- CARD-XY NIP  HINT-SRC @ HINT-N @ CARD-XY NIP -  CH +  c BOX-AROUND
   HINT-DST @ PILE-TARGET-XY CW CH c BOX-AROUND ;

: NUMBER-AT { n x y -- }
   n S>D <# #S #>  0 DO
      DUP I + C@ [CHAR] 0 - CELLS DIGITS + @  { s }
      x I DIGIT-W @ * +  y  s SPR
   LOOP DROP ;
: DIGITS-OF ( n -- count )   S>D <# #S #> NIP ;
: TWO-AT { n x y -- }
   n 10 / CELLS DIGITS + @ x y ROT SPR
   n 10 MOD CELLS DIGITS + @ x DIGIT-W @ + y ROT SPR ;

: DRAW-BAR { | x secs -- }
   C-BAR COLOR!  0 0 W BAR-H FILL-RECT
   12 TO x
   x 11 L-SCORE @ SPR   L-SCORE @ SPR-W x + 7 + TO x
   SCORE @ x 11 NUMBER-AT   x 4 DIGIT-W @ * + 12 + TO x
   x 11 L-MOVES @ SPR   L-MOVES @ SPR-W x + 7 + TO x
   MOVES @ x 11 NUMBER-AT   x 3 DIGIT-W @ * + 12 + TO x
   x 11 L-TIME @ SPR    L-TIME @ SPR-W x + 7 + TO x
   ELAPSED @ 1000000 / TO secs
   secs 60 / x 11 NUMBER-AT
   secs 60 / DIGITS-OF DIGIT-W @ * x + TO x
   x 11 COLON-SPR @ SPR   COLON-SPR @ SPR-W x + TO x
   secs 60 MOD x 11 TWO-AT
   #BTN 0 DO
      I BTN-X  BTN-Y
      I DRAW-LABEL-ART 3 *
      I 4 =  WON @ 0= AND  READY? AND IF 2 ELSE HOVER @ I = IF 1 ELSE 0 THEN THEN +
      CELLS BTN-SPR + @  SPR
   LOOP ;

: BIG-NUMBER { n cx y | cnt x -- }
   n S>D <# #S #>  DUP TO cnt
   cx cnt BIG-W @ * 2/ - TO x
   0 DO
      DUP I + C@ [CHAR] 0 - CELLS BIG-DIGITS + @  { s }
      x I BIG-W @ * +  y  s SPR
   LOOP DROP ;

: CENTERED ( y spr -- )   { y s }  W s SPR-W - 2/  y  s SPR ;

\ At the end the cards turn around the middle of the table, opening out.
: DRAW-WIN { | ang r -- }
   52 0 DO
      WIN-T @ 2*  I 5 * + TO ang
      I 5 * 70 +  WIN-T @ 90 MIN * 90 / TO r
      W CW - 2/  ang ICOS r * 1024 / +
      H BAR-H + CH - 2/  ang ISIN r * 1024 / +
      999   I UP-BIT OR  DRAW-CARD
   LOOP
   W 440 - 2/  190 440 230 $0B2C20 ROUNDED
   212 WIN-TITLE @ CENTERED
   296 L-WIN-SCORE @ CENTERED
   SCORE @ W 2/ 326 BIG-NUMBER
   376 WIN-HINT @ CENTERED ;

: RENDER ( -- )
   0 0 FELT @ SPR
   WON @ IF  DRAW-WIN DRAW-BAR  EXIT  THEN
   DRAW-BAR
   DRAW-STOCK DRAW-WASTE
   P-T0 P-F0 DO  I DRAW-FOUNDATION  LOOP
   #PILES P-T0 DO  I DRAW-COLUMN  LOOP
   DRAW-HINT
   #F @ 0 ?DO  I F[] DRAW-FLIGHT  LOOP
   DRAW-DRAG ;

\ ---- The keys and the steps ---------------------------------------------------------

: BEFORE-ACTION ( -- )   CLEAR-FLIGHTS  FALSE AUTO-ON !  0 HINT-T !  TRUE DIRTY ! ;

: DRAW-KEY ( -- )   WON @ IF NEW-DEAL ELSE DRAW-CARDS THEN ;

: KEY! ( key -- )
   DUP [CHAR] A [CHAR] Z 1+ WITHIN IF 32 + THEN
   DUP [CHAR] q =  OVER 27 = OR IF  DROP QUIT-GAME EXIT  THEN
   D-SRC @ 0>= IF  DROP EXIT  THEN          \ not while a card is held
   CASE
      BL        OF  BEFORE-ACTION DRAW-KEY     ENDOF
      [CHAR] u  OF  BEFORE-ACTION UNDO         ENDOF
      26        OF  BEFORE-ACTION UNDO         ENDOF
      [CHAR] h  OF  BEFORE-ACTION WON @ 0= IF HINT THEN  ENDOF
      [CHAR] a  OF  BEFORE-ACTION START-AUTO   ENDOF
      [CHAR] n  OF  BEFORE-ACTION NEW-DEAL     ENDOF
      [CHAR] r  OF  BEFORE-ACTION SAME-DEAL    ENDOF
      [CHAR] d  OF  BEFORE-ACTION TOGGLE-DRAW  ENDOF
   ENDCASE ;

: READ-KEYS ( -- )   BEGIN INKEY DUP -1 <> WHILE KEY! REPEAT DROP ;

: WIN-JINGLE ( -- )   S" T160 L16 O5 CEG>CEG>C4" JINGLE ;

: TICK-CLOCK { | t -- }
   NOW TO t
   MOVES @ 0>  WON @ 0= AND IF
      t LAST-NOW @ - ELAPSED +!
      ELAPSED @ 1000000 / DUP LAST-SECS @ <> IF  LAST-SECS !  TRUE DIRTY !  ELSE DROP THEN
   THEN
   t LAST-NOW ! ;

: TICK-GAME ( -- )
   TICK-CLOCK
   #F @ IF  STEP-FLIGHTS  TRUE DIRTY !  THEN
   AUTO-ON @ IF
      1 AUTO-T +!
      AUTO-T @ 6 MOD 0= IF  AUTO-STEP 0= IF FALSE AUTO-ON ! THEN  THEN
   THEN
   HINT-T @ IF  -1 HINT-T +!  TRUE DIRTY !  THEN
   WON @ 0=  #F @ 0= AND  IF
      FINISHED? IF  TRUE WON !  0 WIN-T !  FALSE AUTO-ON !  1 WINS +!  WIN-JINGLE  THEN
   THEN
   WON @ IF  1 WIN-T +!  TRUE DIRTY !  THEN ;

: GAME-STEP ( -- )
   READ-KEYS  READ-MOUSE  TICK-GAME
   DIRTY @ IF  RENDER  FALSE DIRTY !  THEN ;

: INIT-GAME ( -- )
   -1 D-SRC !  -1 HOVER !  FALSE DONE !  FALSE DRAW3 !
   0 U-TOP !  0 U-DEPTH !  0 OLD-B !
   NOW LAST-NOW !
   NOW 99999 MOD 1+ START-DEAL ;

: KLONDIKE ( -- )
   BAKE-ALL  MAKE-SOUNDS
   W H GFX-INIT  MOUSE-ON
   INIT-GAME
   BEGIN  GAME-STEP  16 FRAME  DONE @ UNTIL
   MOUSE-OFF
   CR ." Games won: " WINS @ . CR ;

[UNDEFINED] NO-AUTORUN [IF] KLONDIKE BYE [THEN]
