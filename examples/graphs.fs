\ A demonstration that draws eight graphs one after another, each growing into
\ place: a bar chart, a line chart, a pie chart, a scatter plot with its
\ least-squares line, a histogram of dice, the graph of a function, a Lissajous
\ figure, and a rose in polar coordinates. It needs a build with graphics and
\ floating-point numbers.
\
\   sigma.exe examples/graphs.fs      (in a window; Tk on Linux/macOS)
\
\ The window shows the 480 by 300 image twice as large. Each graph stays for four
\ seconds; Space or Enter goes on to the next at once, and Q or Esc ends the
\ demonstration. The numbers in the charts are made up.

REQUIRE-GRAPHICS  ALSO GRAPHICS
DECIMAL

480 CONSTANT W
300 CONSTANT H

\ ---- How far the graph has grown --------------------------------------------------

\ Every graph is drawn whole for each frame, as far as P says: 0 is nothing, 1000
\ is all of it.
VARIABLE P
: PART ( n -- n' )   P @ 1000 */ ;                     \ n by the share P
: DONE? ( -- flag )   P @ 1000 = ;
: LERP ( a b f -- n )   >R OVER - R> 1000 */ + ;       \ from a to b by f / 1000

\ ---- Colors and text --------------------------------------------------------------

CREATE PALETTE
   78 121 167 RGB ,  242 142 43 RGB ,  225 87 89 RGB ,
   118 183 178 RGB ,  89 161 79 RGB ,  237 201 72 RGB ,
: INK ( n -- )   CELLS PALETTE + @ COLOR! ;

: PAPER ( -- )   16 18 28 RGB GFX-CLS ;
: GRID-INK ( -- )    44 48 64 COLOR ;
: AXIS-INK ( -- )    150 150 160 COLOR ;
: LABEL-INK ( -- )   170 170 180 COLOR ;
: BRIGHT-INK ( -- )  235 235 235 COLOR ;

: CTEXT ( c-addr u x y -- )   \ its middle at x
   >R >R  2DUP TEXT-WIDTH 2/  R> SWAP -  R> TEXT ;
: RTEXT ( c-addr u x y -- )   \ its right end at x
   >R >R  2DUP TEXT-WIDTH  R> SWAP -  R> TEXT ;
: N>S ( n -- c-addr u )   DUP ABS 0 <# #S ROT SIGN #> ;

: TITLE ( c-addr u -- )
   BRIGHT-INK  2 TEXT-SCALE  W 2/ 10 CTEXT  1 TEXT-SCALE ;

\ ---- The box of a graph, and the numbers it shows ---------------------------------

\ A graph is drawn in a box of the image. RANGE says which x and y its edges are.
0 VALUE BX   0 VALUE BY   0 VALUE BW   0 VALUE BH
: BOX ( x y w h -- )   TO BH  TO BW  TO BY  TO BX ;
: WIDE-BOX ( -- )     56 44 400 208 BOX ;
: SQUARE-BOX ( -- )   136 44 208 208 BOX ;
: BOTTOM ( -- y )   BY BH + 1- ;

FVARIABLE X0   FVARIABLE X1   FVARIABLE Y0   FVARIABLE Y1
: RANGE ( F: x0 x1 y0 y1 -- )   Y1 F!  Y0 F!  X1 F!  X0 F! ;
: >PX ( F: x -- ) ( -- px )
   X0 F@ F-  X1 F@ X0 F@ F- F/  BW 1- S>F F*  FROUND F>S  BX + ;
: >PY ( F: y -- ) ( -- py )
   Y1 F@ FSWAP F-  Y1 F@ Y0 F@ F- F/  BH 1- S>F F*  FROUND F>S  BY + ;

: BOX-AXES ( -- )   \ the left and the bottom edges
   AXIS-INK  BX BY BX BOTTOM LINE  BX BOTTOM BX BW + 1- BOTTOM LINE ;

\ A line across the box at y = n, with the number to its left.
: Y-TICK ( n -- )
   DUP S>F >PY                                          ( n py )
   GRID-INK  BX OVER  BX BW + 1-  OVER  LINE
   LABEL-INK  SWAP N>S ROT  BX 5 - SWAP 4 -  RTEXT ;
: Y-TICKS { lo hi step -- }   hi 1+ lo DO  I Y-TICK  step +LOOP ;

\ The number n below the box at x = n.
: X-TICK ( n -- )   LABEL-INK  DUP S>F >PX  SWAP N>S ROT  BOTTOM 5 + CTEXT ;
: X-TICKS { lo hi step -- }   hi 1+ lo DO  I X-TICK  step +LOOP ;

\ A small square of color n and a name, for a legend.
: KEY-ENTRY { c-addr u n x y -- }
   n INK  x y 7 7 FILL-RECT  LABEL-INK  c-addr u  x 11 +  y  TEXT ;

\ ---- 1. A bar chart ---------------------------------------------------------------

CREATE RAIN   52 , 56 , 118 , 125 , 138 , 168 , 154 , 168 , 210 , 198 , 93 , 51 ,
: MONTH ( i -- c-addr 1 )   S" JFMAMJJASOND" DROP + 1 ;

: BAR { value i color | x y -- }   \ from the bottom up to `value`, in column i
   i S>F 0.15e0 F+ >PX TO x   value S>F >PY TO y
   color INK  x y  i S>F 0.85e0 F+ >PX x -  BOTTOM y - 1+  FILL-RECT ;

: BARS ( -- )
   S" Monthly rainfall (mm)" TITLE
   WIDE-BOX  0e0 12e0 0e0 250e0 RANGE  0 250 50 Y-TICKS
   12 0 DO
      I CELLS RAIN + @  DUP PART I 0 BAR                ( value )
      DONE? IF  BRIGHT-INK  DUP N>S  I S>F 0.5e0 F+ >PX  3 PICK S>F >PY 10 -  CTEXT  THEN
      DROP
      LABEL-INK  I MONTH  I S>F 0.5e0 F+ >PX  BOTTOM 5 +  CTEXT
   LOOP
   BOX-AXES ;

\ ---- 2. A line chart --------------------------------------------------------------

CREATE NORTH   5 , 6 , 9 , 14 , 19 , 22 , 26 , 27 , 23 , 18 , 12 , 7 ,
CREATE SOUTH   23 , 23 , 21 , 19 , 16 , 13 , 12 , 14 , 16 , 18 , 20 , 22 ,

: POINT ( a i -- px py )   TUCK CELLS + @ S>F >PY  SWAP S>F >PX SWAP ;
: PART-LINE { x1 y1 x2 y2 f -- }   x1 y1  x1 x2 f LERP  y1 y2 f LERP  LINE ;

\ The line through the 12 values at `a`, as far as P says, with a dot at each.
: SERIES { a color -- }
   color INK
   11 0 DO
      P @ 11 *  I 1000 * -  0 MAX 1000 MIN              ( how much of this piece )
      DUP IF
         a I POINT  2DUP 2 FILL-CIRCLE  a I 1+ POINT  4 ROLL PART-LINE
      ELSE DROP THEN
   LOOP
   DONE? IF  a 11 POINT 2 FILL-CIRCLE  THEN ;

: LINES ( -- )
   S" Average temperature (C)" TITLE
   WIDE-BOX  -0.5e0 11.5e0 0e0 30e0 RANGE  0 30 5 Y-TICKS
   12 0 DO  LABEL-INK  I MONTH  I S>F >PX  BOTTOM 5 +  CTEXT  LOOP
   BOX-AXES
   NORTH 1 SERIES  SOUTH 3 SERIES
   S" North town" 1  BX 12 +  BY 4 +   KEY-ENTRY
   S" South town" 3  BX 12 +  BY 16 +  KEY-ENTRY ;

\ ---- 3. A pie chart ---------------------------------------------------------------

5 CONSTANT SLICES
CREATE SHARES   35 , 25 , 20 , 12 , 8 ,                 \ percent; their sum is 100
: SHARE ( i -- n )   CELLS SHARES + @ ;
: SLICE-NAME ( i -- c-addr u )   6 * S" Apple BananaCherryDate  Other " DROP + 6 -TRAILING ;

170 CONSTANT PIE-X   152 CONSTANT PIE-Y   98 CONSTANT PIE-R

\ Angles are in fifths of a degree, round from the top, clockwise: 1800 to a turn.
\ EDGES has where each slice starts, and where the last one ends.
CREATE EDGES   SLICES 1+ CELLS ALLOT
: EDGE ( i -- n )   CELLS EDGES + @ ;
: SET-EDGES ( -- )   0  SLICES 0 DO  DUP I CELLS EDGES + !  I SHARE 18 * +  LOOP  SLICES CELLS EDGES + ! ;
SET-EDGES

: SLICE-OF ( angle -- i )
   SLICES 0 DO  DUP I 1+ EDGE < IF  DROP I UNLOOP EXIT  THEN  LOOP  DROP SLICES 1- ;

\ The angle of the point dx to the right of the pie's middle and dy below it.
: ANGLE ( dx dy -- n )
   SWAP S>F  NEGATE S>F  FATAN2  FDUP F0< IF  2e0 PI F* F+  THEN  900e0 F* PI F/  F>S ;

\ The point at `radius` from the pie's middle, at an angle.
: SPOKE-END ( angle radius -- x y )
   S>F  S>F 900e0 F/ PI F*  PI 2e0 F/ F-                ( F: radius radians )
   FOVER FOVER FCOS F* FROUND F>S PIE-X +
   FSIN F* FROUND F>S PIE-Y + ;

\ Every pixel of the disc whose angle is below `sweep` gets the color of its slice.
: DISC { sweep -- }
   PIE-R 1+  PIE-R NEGATE  DO
      PIE-R 1+  PIE-R NEGATE  DO
         I DUP *  J DUP * +  PIE-R DUP *  <= IF
            I J ANGLE  DUP sweep < IF
               SLICE-OF CELLS PALETTE + @  PIE-X I +  PIE-Y J +  ROT GFX-PSET
            ELSE DROP THEN
         THEN
      LOOP
   LOOP ;

: PIE ( -- )
   S" Fruit sold (%)" TITLE
   1800 PART DISC
   SLICES 0 DO
      I 1+ EDGE  1800 PART <= IF                        \ the whole slice is there
         BRIGHT-INK  I SHARE N>S  I EDGE I 1+ EDGE + 2/  PIE-R 62 100 */  SPOKE-END  4 - CTEXT
      THEN
   LOOP
   SLICES 0 DO  I SLICE-NAME  I  330  I 16 * 110 +  KEY-ENTRY  LOOP ;

\ ---- Numbers by chance, the same every time ---------------------------------------

VARIABLE SEED
: CHANCE ( n -- 0..n-1 )
   SEED @ 1103515245 * 12345 +  2147483647 AND  DUP SEED !  16 RSHIFT  SWAP MOD ;

\ ---- 4. A scatter plot ------------------------------------------------------------

150 CONSTANT PEOPLE
\ A height in cm, and a weight in kg that grows with it, give or take 9.
: PERSON ( -- height weight )   45 CHANCE 150 +  DUP 100 - 9 10 */ 2 +  19 CHANCE 9 - + ;

\ The line y = a x + b that is nearest to the points: the sums it is made from.
VARIABLE SUM-X   VARIABLE SUM-Y   VARIABLE SUM-XY   VARIABLE SUM-XX
: FITTED ( F: x -- y )   { F: x -- }
   PEOPLE SUM-XY @ * SUM-X @ SUM-Y @ * - S>F
   PEOPLE SUM-XX @ * SUM-X @ DUP * - S>F  F/            ( F: a )
   FDUP x F*  SUM-Y @ S>F  FROT SUM-X @ S>F F*  F-  PEOPLE S>F F/  F+ ;

: SCATTER ( -- )
   S" Height (cm) and weight (kg)" TITLE
   WIDE-BOX  145e0 200e0 30e0 100e0 RANGE  30 100 10 Y-TICKS  150 200 10 X-TICKS
   BOX-AXES
   1 SEED !  0 SUM-X !  0 SUM-Y !  0 SUM-XY !  0 SUM-XX !
   PEOPLE 0 DO
      PERSON                                            ( height weight )
      OVER SUM-X +!  DUP SUM-Y +!  2DUP * SUM-XY +!  OVER DUP * SUM-XX +!
      I PEOPLE PART < IF
         3 INK  S>F >PY  SWAP S>F >PX  SWAP  2 FILL-CIRCLE
      ELSE 2DROP THEN
   LOOP
   DONE? IF
      1 INK  148e0 >PX  148e0 FITTED >PY  197e0 >PX  197e0 FITTED >PY  LINE
      S" Least-squares line" 1  BX 12 +  BY 4 +  KEY-ENTRY
   THEN ;

\ ---- 5. A histogram ---------------------------------------------------------------

3000 CONSTANT THROWS
CREATE COUNTS   19 CELLS ALLOT                          \ how often each sum came

: DICE ( -- )
   S" The sum of three dice" TITLE
   WIDE-BOX  2.5e0 18.5e0 0e0 400e0 RANGE  0 400 100 Y-TICKS  3 18 1 X-TICKS
   COUNTS 19 CELLS ERASE  7 SEED !
   THROWS PART 0 ?DO  6 CHANCE 6 CHANCE 6 CHANCE + + 3 +  CELLS COUNTS +  1 SWAP +!  LOOP
   19 3 DO
      4 INK  I S>F 0.4e0 F- >PX                         ( x )
      I CELLS COUNTS + @ S>F >PY                        ( x y )
      2DUP  I S>F 0.4e0 F+ >PX 2 PICK -  BOTTOM 2 PICK - 1+  FILL-RECT  2DROP
   LOOP
   BOX-AXES
   LABEL-INK  THROWS PART N>S  BX BW + 8 -  BY 4 +  RTEXT
   S" throws:"  BX BW + 40 -  BY 4 +  RTEXT ;

\ ---- Curves -----------------------------------------------------------------------

\ The curve of xt ( F: t -- x y ) for t from 0 to 1, in 600 pieces, the first n of
\ them.
: (CURVE) { xt n | px py -- }
   0e0 xt EXECUTE  >PY TO py  >PX TO px
   n 0 ?DO
      I 1+ S>F 600e0 F/ xt EXECUTE  >PY >PX SWAP        ( px2 py2 )
      2DUP  px py 2SWAP LINE  TO py TO px
   LOOP ;
: CURVE ( xt -- )   600 PART (CURVE) ;                  \ as far as P says
: WHOLE-CURVE ( xt -- )   600 (CURVE) ;

\ ---- 6. The graph of a function ---------------------------------------------------

: ABOVE ( F: t -- x y )   12e0 F*  FDUP -0.25e0 F* FEXP ;
: BELOW ( F: t -- x y )   ABOVE FNEGATE ;
: SWING ( F: t -- x y )   ABOVE  FOVER 3e0 F* FCOS  F* ;

: WAVE ( -- )
   S" y = exp(-x/4) cos 3x" TITLE
   WIDE-BOX  0e0 12e0 -1.1e0 1.1e0 RANGE  -1 1 1 Y-TICKS  0 12 2 X-TICKS
   BOX-AXES
   GRID-INK  ['] ABOVE WHOLE-CURVE  ['] BELOW WHOLE-CURVE
   5 INK  ['] SWING CURVE ;

\ ---- 7. A Lissajous figure --------------------------------------------------------

: TURN ( F: t -- angle )   2e0 PI F* F* ;
: LISSAJOUS ( F: t -- x y )   TURN  FDUP 3e0 F* FSIN  FSWAP 4e0 F* FSIN ;

: FIGURE ( -- )
   S" x = sin 3t, y = sin 4t" TITLE
   SQUARE-BOX  -1.15e0 1.15e0 -1.15e0 1.15e0 RANGE  -1 1 1 Y-TICKS  -1 1 1 X-TICKS
   BOX-AXES
   3 INK  ['] LISSAJOUS CURVE ;

\ ---- 8. A rose in polar coordinates -----------------------------------------------

: ROSE ( F: t -- x y )
   TURN  FDUP 4e0 F* FCOS                               ( F: angle r )
   FOVER FCOS FOVER F*  FROT FSIN FROT F* ;

: RING ( F: r -- )   >PX 0e0 >PX -  0e0 >PX 0e0 >PY ROT  CIRCLE ;

: ROSE-GRAPH ( -- )
   S" r = cos 4a" TITLE
   SQUARE-BOX  -1.15e0 1.15e0 -1.15e0 1.15e0 RANGE
   GRID-INK  0.5e0 RING  1e0 RING
   -1.15e0 >PX 0e0 >PY  1.15e0 >PX 0e0 >PY  LINE
   0e0 >PX -1.15e0 >PY  0e0 >PX 1.15e0 >PY  LINE
   2 INK  ['] ROSE CURVE ;

\ ---- The demonstration ------------------------------------------------------------

8 CONSTANT #GRAPHS
CREATE GRAPHS
   ' BARS ,  ' LINES ,  ' PIE ,  ' SCATTER ,  ' DICE ,  ' WAVE ,  ' FIGURE ,  ' ROSE-GRAPH ,

: FOOTER ( n -- )   \ n is the graph, from 0
   LABEL-INK
   1+ N>S  8 H 12 -  TEXT   S" / 8"  20 H 12 -  TEXT
   S" Space: next   Q: quit"  W 8 -  H 12 -  RTEXT ;

: DRAW ( n -- )   PAPER  DUP CELLS GRAPHS + @ EXECUTE  FOOTER ;

\ What the key that was pressed asks for: 0 nothing, 1 the next graph, 2 the end.
: ASKED ( -- n )
   INKEY  DUP -1 = IF DROP 0 EXIT THEN
   DUP [CHAR] q =  OVER [CHAR] Q = OR  OVER 27 = OR IF DROP 2 EXIT THEN
   DUP BL =  SWAP 13 = OR  1 AND ;

\ Graph n grows for about a second and a half and stays for four seconds.
: PRESENT ( n -- end? )
   1001 0 DO
      I P !  DUP DRAW  33 FRAME
      ASKED ?DUP IF  NIP 2 =  UNLOOP EXIT  THEN
   25 +LOOP
   120 0 DO
      33 MS  ASKED ?DUP IF  NIP 2 =  UNLOOP EXIT  THEN
   LOOP
   DROP FALSE ;

: GRAPH-DEMO ( -- )
   W H GFX-INIT  W 2* H 2* WINDOW-SIZE
   0 BEGIN  DUP PRESENT 0=  WHILE  1+ #GRAPHS MOD  REPEAT  DROP ;

GRAPH-DEMO
