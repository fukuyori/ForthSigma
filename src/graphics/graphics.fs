\ The graphics library of FORTH/Sigma, written in Forth.
\
\ REQUIRE-GRAPHICS interprets this file, which is built into the program, after it
\ has put the GFX- words in the GRAPHICS vocabulary. While the file loads, new words go
\ into GRAPHICS, GRAPHICS is searched first, and BASE is decimal; afterwards the search
\ order, the current word list, and BASE are what they were before REQUIRE-GRAPHICS.
\
\ To try a changed copy of this file without rebuilding, load the built-in one first
\ and then include the copy into GRAPHICS (its words then replace the built-in ones):
\   REQUIRE-GRAPHICS  ALSO GRAPHICS DEFINITIONS  DECIMAL  INCLUDE src/graphics/graphics.fs
\
\ The GFX- words underneath (colors are $RRGGBB):
\   GFX-INIT ( w h -- )  GFX-WIDTH ( -- w )  GFX-HEIGHT ( -- h )
\   GFX-PSET ( x y rgb -- )  GFX-PGET ( x y -- rgb )  GFX-HLINE ( x1 x2 y rgb -- )
\   GFX-CLS ( rgb -- )  GFX-SAVE-PPM ( c-addr u -- ior )  GFX-SAVE-BMP ( c-addr u -- ior )
\
\ The words here draw with the current color and cut everything at the edges of the
\ image. Drawing far outside the image costs no more than drawing inside it. So that
\ the arithmetic cannot overflow, coordinates and sizes are first limited to
\ -2^61 .. 2^61 for lines and rectangles, and to -2^30 .. 2^30 for circles (a circle
\ with a value beyond that is drawn with the value moved to the limit). Words whose
\ names are in parentheses are helpers.

\ ---- Color -----------------------------------------------------------------------

VARIABLE (COLOR)   $FFFFFF (COLOR) !

: RGB ( r g b -- rgb )   255 AND  SWAP 255 AND 8 LSHIFT OR  SWAP 255 AND 16 LSHIFT OR ;
: COLOR! ( rgb -- )   $FFFFFF AND (COLOR) ! ;
: COLOR@ ( -- rgb )   (COLOR) @ ;
: COLOR ( r g b -- )   RGB COLOR! ;

\ ---- Helpers ---------------------------------------------------------------------

\ NO GRAPHICS IMAGE, as the GFX- words give it, also when nothing would be drawn.
: (NEED-IMAGE) ( -- )   GFX-WIDTH 0= IF -271 THROW THEN ;

\ Differences of two limited values fit a cell, and */ multiplies them in a double cell.
2305843009213693952 CONSTANT (LIMIT)
: (CLAMP) ( n -- n' )   (LIMIT) NEGATE MAX  (LIMIT) MIN ;
\ The square of a limited radius fits a cell.
1073741824 CONSTANT (CIRCLE-LIMIT)
: (CLAMP-CIRCLE) ( n -- n' )   (CIRCLE-LIMIT) NEGATE MAX  (CIRCLE-LIMIT) MIN ;

\ The largest r with r*r <= n, for 0 <= n (Newton's method on integers).
: (ISQRT) { n | x y -- r }
   n 2 < IF n EXIT THEN
   n TO x  x 1+ 2/ TO y
   BEGIN y x < WHILE  y TO x  x n x / + 2/ TO y  REPEAT
   x ;

\ A vertical line from y1 to y2, both included, cut at the edges.
: (VLINE) { x y1 y2 | top bottom -- }
   x 0< x GFX-WIDTH >= OR IF EXIT THEN
   y1 y2 MIN 0 MAX TO top   y1 y2 MAX GFX-HEIGHT 1- MIN TO bottom
   top bottom > IF EXIT THEN
   bottom 1+ top DO  x I COLOR@ GFX-PSET  LOOP ;

\ ---- Points, clearing, and saving ---------------------------------------------------

: PSET ( x y -- )   COLOR@ GFX-PSET ;
: CLS ( -- )   0 GFX-CLS ;
: SAVE-PPM ( c-addr u -- )   GFX-SAVE-PPM THROW ;
: SAVE-BMP ( c-addr u -- )   GFX-SAVE-BMP THROW ;

\ ---- Lines -------------------------------------------------------------------------

\ Bresenham's line between two points inside the image.
: (BRESENHAM) { x1 y1 x2 y2 | dx dy sx sy err e2 -- }
   x2 x1 - ABS TO dx   y2 y1 - ABS NEGATE TO dy
   x1 x2 < IF 1 ELSE -1 THEN TO sx   y1 y2 < IF 1 ELSE -1 THEN TO sy
   dx dy + TO err
   BEGIN
      x1 y1 COLOR@ GFX-PSET
      x1 x2 = y1 y2 = AND IF EXIT THEN
      err 2* TO e2
      e2 dy >= IF  err dy + TO err  x1 sx + TO x1  THEN
      e2 dx <= IF  err dx + TO err  y1 sy + TO y1  THEN
   AGAIN ;

\ Where a point lies against the image: 1 left, 2 right, 4 above, 8 below.
: (OUTCODE) { x y -- code }
   0  x 0< IF 1 OR THEN  x GFX-WIDTH 1- > IF 2 OR THEN
   y 0< IF 4 OR THEN  y GFX-HEIGHT 1- > IF 8 OR THEN ;

\ A line from x1 y1 to x2 y2, both ends included. An end outside the image is first
\ moved to the edge (Cohen-Sutherland), so a long line outside costs nothing.
: LINE { x1 y1 x2 y2 | c1 c2 c x y moves -- }
   (NEED-IMAGE)
   x1 (CLAMP) TO x1  y1 (CLAMP) TO y1  x2 (CLAMP) TO x2  y2 (CLAMP) TO y2
   0 TO moves
   BEGIN
      x1 y1 (OUTCODE) TO c1   x2 y2 (OUTCODE) TO c2
      \ Rounding can leave an end a pixel outside; after a few moves the ends are at
      \ the edge, and GFX-PSET cuts what is left.
      c1 c2 OR 0=  moves 8 >=  OR IF  x1 y1 x2 y2 (BRESENHAM) EXIT  THEN
      moves 1+ TO moves
      c1 c2 AND IF EXIT THEN
      c1 IF c1 ELSE c2 THEN TO c
      c 8 AND IF
         GFX-HEIGHT 1- TO y   x1  x2 x1 -  y y1 -  y2 y1 - */ +  TO x
      ELSE c 4 AND IF
         0 TO y   x1  x2 x1 -  y y1 -  y2 y1 - */ +  TO x
      ELSE c 2 AND IF
         GFX-WIDTH 1- TO x   y1  y2 y1 -  x x1 -  x2 x1 - */ +  TO y
      ELSE
         0 TO x   y1  y2 y1 -  x x1 -  x2 x1 - */ +  TO y
      THEN THEN THEN
      c c1 = IF  x TO x1  y TO y1  ELSE  x TO x2  y TO y2  THEN
   AGAIN ;

\ ---- Rectangles --------------------------------------------------------------------

\ The outline of the w by h rectangle whose top left corner is x y; nothing when w or
\ h is 0 or less.
: RECT { x y w h -- }
   (NEED-IMAGE)
   x (CLAMP) TO x  y (CLAMP) TO y  w (CLAMP) TO w  h (CLAMP) TO h
   w 1 < h 1 < OR IF EXIT THEN
   x  x w + 1-  y          COLOR@ GFX-HLINE
   x  x w + 1-  y h + 1-   COLOR@ GFX-HLINE
   x          y  y h + 1-  (VLINE)
   x w + 1-   y  y h + 1-  (VLINE) ;

: FILL-RECT { x y w h | top bottom -- }
   (NEED-IMAGE)
   x (CLAMP) TO x  y (CLAMP) TO y  w (CLAMP) TO w  h (CLAMP) TO h
   w 1 < h 1 < OR IF EXIT THEN
   y 0 MAX TO top   y h + 1- GFX-HEIGHT 1- MIN TO bottom
   top bottom > IF EXIT THEN
   bottom 1+ top DO  x  x w + 1-  I  COLOR@ GFX-HLINE  LOOP ;

\ ---- Circles -----------------------------------------------------------------------

\ The circles have the pixels of the midpoint circle algorithm, computed a row at a
\ time instead of by walking around the circle. In the first octant (0 <= x <= y) the
\ algorithm puts at column x the largest y with x*x + y*y - y < r*r, which is
\ (isqrt(4(r*r - x*x)) + 1) / 2. The other octants are its mirror images, so a row
\ at distance yy from the center has the pixels
\   x = a for every a <= yy whose octant y is yy (a run from the octant), and
\   x = the octant y at column yy, when yy is in the octant (yy <= that y),
\ on both sides of the center.

\ The octant y at column x of a circle of radius r (0 <= x <= r).
: (OCTANT-Y) ( r x -- y )   DUP *  SWAP DUP *  SWAP -  4 *  (ISQRT) 1+ 2/ ;

\ The last column whose octant y is yy or more, or -1 when there is none.
: (LAST-COLUMN) ( r yy -- a | -1 )
   DUP DUP * -  SWAP DUP * +  1-
   DUP 0< IF DROP -1 ELSE (ISQRT) THEN ;

\ The pixels of the outline on the row yy rows from the center (0 <= yy <= r): the run
\ from x1 to x2 (none when x1 > x2), and the single column x3 (none when x3 < 0).
: (CIRCLE-ROW) { r yy | x3 -- x1 x2 x3 }
   r yy 1+ (LAST-COLUMN) 1+   r yy (LAST-COLUMN) yy MIN
   r yy (OCTANT-Y) TO x3
   yy x3 > IF -1 TO x3 THEN
   x3 ;

\ How far the circle reaches on that row: its outermost outline pixel.
: (EXTENT) ( r yy -- e )   (CIRCLE-ROW)  DUP 0< IF DROP NIP ELSE NIP NIP THEN ;

\ The rows of the circle around cx cy with radius r that lie in the image, for the
\ words below; nothing when r is less than 0. Each row costs the same however large
\ r is.
: (CIRCLE-ROWS) ( cy r -- bottom+1 top | 0 0 )
   DUP 0< IF 2DROP 0 0 EXIT THEN
   2DUP + GFX-HEIGHT 1- MIN 1+  -ROT  - 0 MAX
   2DUP <= IF 2DROP 0 0 THEN ;

: FILL-CIRCLE { cx cy r | w -- }
   (NEED-IMAGE)
   cx (CLAMP-CIRCLE) TO cx  cy (CLAMP-CIRCLE) TO cy  r (CLAMP-CIRCLE) TO r
   cy r (CIRCLE-ROWS) ?DO
      r  I cy - ABS  (EXTENT) TO w
      cx w -  cx w +  I  COLOR@ GFX-HLINE
   LOOP ;

\ The outline. Every pixel of it is in FILL-CIRCLE of the same circle, which fills each
\ row out to the outermost pixel.
: CIRCLE { cx cy r | x1 x2 x3 -- }
   (NEED-IMAGE)
   cx (CLAMP-CIRCLE) TO cx  cy (CLAMP-CIRCLE) TO cy  r (CLAMP-CIRCLE) TO r
   cy r (CIRCLE-ROWS) ?DO
      r  I cy - ABS  (CIRCLE-ROW) TO x3 TO x2 TO x1
      x1 x2 <= IF
         cx x1 +  cx x2 +  I  COLOR@ GFX-HLINE
         cx x2 -  cx x1 -  I  COLOR@ GFX-HLINE
      THEN
      x3 0>= IF
         cx x3 +  I  COLOR@ GFX-PSET
         cx x3 -  I  COLOR@ GFX-PSET
      THEN
   LOOP ;

\ ---- Filling an area ----------------------------------------------------------------

\ PAINT fills the area of one color around a point, a row at a time. The rows still to
\ do wait on a stack in the heap (two cells for each), which grows as needed.
VARIABLE (P-STACK)  VARIABLE (P-SIZE)  VARIABLE (P-USED)  VARIABLE (P-TARGET)

: (P-PUSH) ( x y -- )
   (P-USED) @ (P-SIZE) @ = IF
      (P-STACK) @  (P-SIZE) @ 4 * CELLS  RESIZE THROW  (P-STACK) !
      (P-SIZE) @ 2* (P-SIZE) !
   THEN
   (P-STACK) @  (P-USED) @ 2* CELLS +  2!   1 (P-USED) +! ;

: (P-POP) ( -- x y )   -1 (P-USED) +!  (P-STACK) @  (P-USED) @ 2* CELLS +  2@ ;

: (P-TARGET?) ( x y -- flag )   GFX-PGET (P-TARGET) @ = ;

\ Pushes the start of each run of the target color on row y between lx and rx.
: (P-SEEDS) { lx rx y -- }
   y 0< y GFX-HEIGHT >= OR IF EXIT THEN
   rx 1+ lx DO
      I y (P-TARGET?) IF
         I lx = IF TRUE ELSE I 1- y (P-TARGET?) 0= THEN
         IF I y (P-PUSH) THEN
      THEN
   LOOP ;

: (P-SPAN) { x y | lx rx -- }
   x y (P-TARGET?) 0= IF EXIT THEN
   x TO lx  BEGIN lx 1- y (P-TARGET?) WHILE lx 1- TO lx REPEAT
   x TO rx  BEGIN rx 1+ y (P-TARGET?) WHILE rx 1+ TO rx REPEAT
   lx rx y COLOR@ GFX-HLINE
   lx rx y 1- (P-SEEDS)
   lx rx y 1+ (P-SEEDS) ;

: (P-FILL) ( x y -- )   (P-PUSH)  BEGIN (P-USED) @ WHILE (P-POP) (P-SPAN) REPEAT ;

\ Fills the area around x y that has the color of x y, with the current color;
\ nothing outside the image or when the area has the current color already.
: PAINT ( x y -- )
   (NEED-IMAGE)
   2DUP GFX-PGET  DUP -1 =  OVER COLOR@ =  OR IF DROP 2DROP EXIT THEN
   (P-TARGET) !
   64 DUP (P-SIZE) !  2* CELLS ALLOCATE THROW (P-STACK) !  0 (P-USED) !
   ['] (P-FILL) CATCH
   (P-STACK) @ FREE DROP
   THROW ;

\ ---- Showing the image -------------------------------------------------------------

\ Where SHOW puts the image: 0 the window when the host has one and the terminal
\ otherwise, 1 the terminal, 2 the window. And how the terminal shows it: 0 with half
\ block characters, 1 as Sixel graphics.
VARIABLE (DISPLAY)  0 (DISPLAY) !
VARIABLE (TERMINAL-MODE)  0 (TERMINAL-MODE) !

: DISPLAY-TERMINAL ( -- )   1 (DISPLAY) ! ;
\ HOST FUNCTION UNAVAILABLE when the host has no window.
: DISPLAY-WINDOW ( -- )   GFX-WINDOW? 0= IF -21 THROW THEN  2 (DISPLAY) ! ;
: TERMINAL-BLOCKS ( -- )   0 (TERMINAL-MODE) ! ;
: TERMINAL-SIXEL ( -- )   1 (TERMINAL-MODE) ! ;

: (WINDOW?) ( -- flag )
   (DISPLAY) @ DUP 2 =  SWAP 0=  GFX-WINDOW? AND  OR ;

\ Shows the image where DISPLAY-TERMINAL or DISPLAY-WINDOW said.
: SHOW ( -- )
   (NEED-IMAGE)
   (WINDOW?) IF GFX-SHOW-WINDOW EXIT THEN
   (TERMINAL-MODE) @ IF GFX-SHOW-SIXEL ELSE GFX-SHOW-BLOCKS THEN ;
