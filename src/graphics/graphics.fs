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
\   GFX-SAVE-PNG ( c-addr u -- ior )
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
: SAVE-PNG ( c-addr u -- )   GFX-SAVE-PNG THROW ;

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

\ Where SHOW puts the image: 0 not chosen yet (see SHOW), 1 the terminal, 2 the window,
\ 3 the Tk window (DISPLAY-TK). And how the terminal shows it: 0 with half block
\ characters, 1 as Sixel graphics.
VARIABLE (DISPLAY)  0 (DISPLAY) !
VARIABLE (TERMINAL-MODE)  0 (TERMINAL-MODE) !

: DISPLAY-TERMINAL ( -- )   1 (DISPLAY) ! ;
\ HOST FUNCTION UNAVAILABLE when the host has no window.
: DISPLAY-WINDOW ( -- )   GFX-WINDOW? 0= IF -21 THROW THEN  2 (DISPLAY) ! ;
: TERMINAL-BLOCKS ( -- )   0 (TERMINAL-MODE) ! ;
: TERMINAL-SIXEL ( -- )   1 (TERMINAL-MODE) ! ;

: (WINDOW?) ( -- flag )
   (DISPLAY) @ DUP 2 =  SWAP 0=  GFX-WINDOW? AND  OR ;

\ The colors SHOW uses: 0 full color, or 2, 16, or 256, and whether it dithers (with a
\ 4 by 4 Bayer matrix). The image keeps its colors; GFX-COLOR-MODE ( n flag -- ) sets
\ them for the GFX-SHOW- words, which SHOW does each time.
VARIABLE (COLORS)  0 (COLORS) !
VARIABLE (DITHER)  0 (DITHER) !

\ NUMBER ERROR unless n is 0, 2, 16, or 256.
: DISPLAY-COLORS ( n -- )   DUP (DITHER) @ GFX-COLOR-MODE  (COLORS) ! ;
: DITHER ( flag -- )   0<> (DITHER) ! ;

\ Whether Sigma runs on a desktop: DISPLAY or WAYLAND_DISPLAY is set (X11, Wayland),
\ or __CFBundleIdentifier (a terminal app of macOS; not set over SSH).
: (DESKTOP?) ( -- flag )
   S" DISPLAY" GETENV NIP  S" WAYLAND_DISPLAY" GETENV NIP OR
   S" __CFBundleIdentifier" GETENV NIP OR  0<> ;

\ The first SHOW with nothing chosen on a host without a window of its own (Linux,
\ macOS) tries the Tk window when Sigma runs on a desktop, and keeps to it when that
\ works; else, or when wish cannot start, it keeps to the terminal. True when it
\ showed the image in the Tk window.
: (TRY-TK) ( -- flag )
   1 (DISPLAY) !
   ['] (DESKTOP?) CATCH IF FALSE THEN  0= IF FALSE EXIT THEN
   ['] GFX-SHOW-TK CATCH IF FALSE EXIT THEN
   3 (DISPLAY) !  TRUE ;

\ Shows the image where DISPLAY-TERMINAL, DISPLAY-WINDOW, or DISPLAY-TK said, with the
\ colors DISPLAY-COLORS and DITHER chose. With nothing chosen: the window when the host
\ has one, else the Tk window on a desktop (see (TRY-TK)), else the terminal.
: SHOW ( -- )
   (NEED-IMAGE)
   (COLORS) @ (DITHER) @ GFX-COLOR-MODE
   (DISPLAY) @ 0=  GFX-WINDOW? 0= AND IF (TRY-TK) IF EXIT THEN THEN
   (DISPLAY) @ 3 = IF GFX-SHOW-TK EXIT THEN
   (WINDOW?) IF GFX-SHOW-WINDOW EXIT THEN
   (TERMINAL-MODE) @ IF GFX-SHOW-SIXEL ELSE GFX-SHOW-BLOCKS THEN ;

\ ---- Keys, the mouse, and animation --------------------------------------------------

\ The codes INKEY gives for keys that are not characters. A character gives its byte
\ (each byte of a UTF-8 character in turn), Enter 13, Backspace 8, Tab 9, and Esc 27.
256 CONSTANT K-UP     257 CONSTANT K-DOWN   258 CONSTANT K-LEFT    259 CONSTANT K-RIGHT
260 CONSTANT K-HOME   261 CONSTANT K-END    262 CONSTANT K-PRIOR   263 CONSTANT K-NEXT
264 CONSTANT K-INSERT 265 CONSTANT K-DELETE
266 CONSTANT K-F1   267 CONSTANT K-F2   268 CONSTANT K-F3   269 CONSTANT K-F4
270 CONSTANT K-F5   271 CONSTANT K-F6   272 CONSTANT K-F7   273 CONSTANT K-F8
274 CONSTANT K-F9   275 CONSTANT K-F10  276 CONSTANT K-F11  277 CONSTANT K-F12

\ The next key pressed on the terminal or in the window, without waiting; -1 when there
\ is none. Ctrl+C throws USER INTERRUPT (-28).
: INKEY ( -- key | -1 )   GFX-INKEY ;
\ Whether the key (a code as INKEY gives it) is held down now; a terminal does not tell
\ when a key is released, so its keys count as held for 0.6 s after they were pressed.
: KEY-HELD? ( key -- flag )   GFX-KEY-HELD ;

\ Snapshot once per frame. Indices 0..7 can change after reconnect: compare IDs.
\ Poll returns -1 if SDL3 is unavailable, 0 if no pads are connected.
: GAMEPAD-POLL ( -- count ) GFX-GAMEPAD-POLL ;
: GAMEPAD? ( pad -- flag ) 0 SWAP GFX-GAMEPAD-QUERY ;
: GAMEPAD-ID ( pad -- id ) 1 SWAP GFX-GAMEPAD-QUERY ;
: GAMEPAD-BUTTONS ( pad -- mask ) 2 SWAP GFX-GAMEPAD-QUERY ;
: GAMEPAD-MAPPED? ( pad -- flag ) 3 SWAP GFX-GAMEPAD-QUERY ;
: GAMEPAD-AXES ( pad -- count ) 4 SWAP GFX-GAMEPAD-QUERY ;
: GAMEPAD-BUTTON-COUNT ( pad -- count ) 5 SWAP GFX-GAMEPAD-QUERY ;
: GAMEPAD-HATS ( pad -- count ) 6 SWAP GFX-GAMEPAD-QUERY ;
: GAMEPAD-AXIS ( axis pad -- value )
   { axis pad } axis 0 16 WITHIN 0= IF -24 THROW THEN 16 axis + pad GFX-GAMEPAD-QUERY ;
: GAMEPAD-HAT ( hat pad -- mask )
   { hat pad } hat 0 4 WITHIN 0= IF -24 THROW THEN 32 hat + pad GFX-GAMEPAD-QUERY ;
: GAMEPAD-BUTTON? ( button pad -- flag )
   { button pad } button 0 32 WITHIN 0= IF -24 THROW THEN
   pad GAMEPAD-BUTTONS 1 button LSHIFT AND 0<> ;
: GAMEPAD-NAME ( addr capacity pad -- length ) GFX-GAMEPAD-NAME ;
: GAMEPAD-GUID ( addr capacity pad -- length ) GFX-GAMEPAD-GUID ;
: GAMEPAD-MAP ( addr length -- flag ) GFX-GAMEPAD-MAP ;
\ The size of the part of the window (and of the Tk window) that shows the image, from
\ the next SHOW; 0 0 for the image's own size. The image keeps its proportions.
: WINDOW-SIZE ( w h -- )   GFX-WINDOW-SIZE ;

\ The pixel of the image under the mouse and the buttons held (1 left, 2 right,
\ 4 middle); -1 -1 while the position is not known.
: MOUSE ( -- x y buttons )   GFX-MOUSE ;
: MOUSE-ON ( -- )   TRUE GFX-MOUSE-MODE ;
: MOUSE-OFF ( -- )   FALSE GFX-MOUSE-MODE ;

\ FRAME waits until ms milliseconds have passed since the last FRAME, and shows the
\ image: a loop that draws and calls FRAME runs at a steady pace. When the drawing took
\ longer, it does not wait, and the next frame counts from now.
VARIABLE (FRAME-TIME)  0 (FRAME-TIME) !

: FRAME ( ms -- )
   0 MAX 1000 *  (FRAME-TIME) @ +  UTIME DROP   ( target now )
   2DUP - DUP 0> IF 1000 / MS ELSE DROP THEN
   MAX (FRAME-TIME) !
   SHOW ;

\ ---- Text --------------------------------------------------------------------------

\ TEXT draws with the current font: at first the ASCII characters of Misaki Gothic
\ (Num Kadoma), 4 pixels wide and 8 high; a BDF font file after LOAD-FONT; a font of
\ the system after SYSTEM-FONT (Windows). A character the font does not have (each
\ UTF-8 character, or a byte that is not one) is drawn as "?", and a control character
\ is not drawn. The words underneath:
\   GFX-GLYPH-LOAD ( code -- advance | -1 )  loads a glyph (-1: the font has none)
\   GFX-GLYPH-BOX ( -- left width height )   its box, from the pen and the line's top
\   GFX-GLYPH-ALPHA ( x y -- a )             its coverage, 0 to 255, at x y of the box
\   GFX-FONT-HEIGHT ( -- h )  GFX-FONT-BUILTIN ( -- )
\   GFX-FONT-LOAD ( c-addr u -- ior )  GFX-FONT-SYSTEM ( c-addr u height -- ior )
VARIABLE (TEXT-SCALE)  1 (TEXT-SCALE) !

\ Each pixel of the font drawn as n by n pixels; NUMBER ERROR unless 1 <= n <= 256.
: TEXT-SCALE ( n -- )   DUP 1 257 WITHIN 0= IF DROP -24 THROW THEN  (TEXT-SCALE) ! ;

: BUILTIN-FONT ( -- )   GFX-FONT-BUILTIN ;
\ A BDF font file; the ior of the file, or FONT ERROR when it is not a BDF font this
\ can read. On an error the font stays as it was.
: LOAD-FONT ( c-addr u -- )   GFX-FONT-LOAD THROW ;
\ The system's font of that name, height pixels a line (1 to 256): FONT ERROR when the
\ system has none of the name, HOST FUNCTION UNAVAILABLE on a host without fonts.
: SYSTEM-FONT ( c-addr u height -- )   GFX-FONT-SYSTEM THROW ;
\ The height of a line of text, at the current scale.
: TEXT-HEIGHT ( -- h )   GFX-FONT-HEIGHT (TEXT-SCALE) @ * ;

\ The code point of the UTF-8 character at the start of a string that is not empty,
\ and the rest of the string; -1, taking one byte, when the bytes are not a character:
\ a byte that cannot start one, missing continuation bytes, a longer form than the
\ character needs (such as C1 81 for A), a surrogate, or a value above U+10FFFF.
: (UTF8-NEXT) { addr u | b n code least -- addr' u' code }
   addr C@ TO b
   b $80 < IF  addr 1+ u 1- b  EXIT THEN
   b $E0 AND $C0 = IF  1 TO n  b $1F AND TO code  $80 TO least  ELSE
   b $F0 AND $E0 = IF  2 TO n  b $0F AND TO code  $800 TO least  ELSE
   b $F8 AND $F0 = IF  3 TO n  b $07 AND TO code  $10000 TO least  ELSE
      addr 1+ u 1- -1 EXIT
   THEN THEN THEN
   u n <= IF  addr 1+ u 1- -1  EXIT THEN
   n 1+ 1 DO
      addr I + C@  DUP $C0 AND $80 <> IF  DROP UNLOOP addr 1+ u 1- -1  EXIT THEN
      $3F AND  code 6 LSHIFT OR TO code
   LOOP
   code least <  code $10FFFF >  OR  code $D800 $E000 WITHIN  OR IF  addr 1+ u 1- -1  EXIT THEN
   addr n 1+ +  u n 1+ -  code ;

\ Loads the glyph TEXT draws for a code point and gives its advance; -1 when nothing
\ is drawn (a control character, or a font without even "?").
: (LOAD-GLYPH) ( code -- advance | -1 )
   DUP 0 32 WITHIN IF DROP -1 EXIT THEN
   GFX-GLYPH-LOAD  DUP -1 = IF DROP [CHAR] ? GFX-GLYPH-LOAD THEN ;

\ One 8-bit channel of fg over bg with coverage a.
: (MIX) { fg bg a -- c }   fg a *  bg 255 a - *  +  127 +  255 / ;

\ A pixel of the current color with coverage a over what the image has there.
: (BLEND-PIXEL) { x y a | bg c -- }
   a 255 = IF  x y COLOR@ GFX-PSET  EXIT THEN
   x y GFX-PGET TO bg   bg 0< IF EXIT THEN
   COLOR@ TO c
   c 16 RSHIFT 255 AND  bg 16 RSHIFT 255 AND  a (MIX) 16 LSHIFT
   c 8 RSHIFT 255 AND   bg 8 RSHIFT 255 AND   a (MIX) 8 LSHIFT OR
   c 255 AND            bg 255 AND            a (MIX) OR
   x y ROT GFX-PSET ;

\ A pixel of the font, s by s pixels of the image from x y; nothing outside the image.
: (GLYPH-CELL) { x y a s -- }
   x GFX-WIDTH >=  y GFX-HEIGHT >= OR  x s + 1 <  OR  y s + 1 < OR IF EXIT THEN
   s 1 = IF  x y a (BLEND-PIXEL)  EXIT THEN
   a 255 = IF  x y s s FILL-RECT  EXIT THEN
   y s + 0 MAX  y 0 MAX ?DO
      x s + GFX-WIDTH MIN  x 0 MAX ?DO  I J a (BLEND-PIXEL)  LOOP
   LOOP ;

\ Draws the loaded glyph with its pen at x y (the top of the line).
: (DRAW-LOADED) { x y | left w h s -- }
   GFX-GLYPH-BOX TO h TO w TO left   (TEXT-SCALE) @ TO s
   h 0 ?DO
      w 0 ?DO
         I J GFX-GLYPH-ALPHA ?DUP IF
            >R  left I + s * x +  J s * y +  R> s (GLYPH-CELL)
         THEN
      LOOP
   LOOP ;

\ Draws the UTF-8 string with the top left of its line at x y, with the current color.
\ Where a font has shades of coverage at the edges of its strokes, the color is mixed
\ with the image; other pixels are left as they are.
: TEXT { addr u x y | advance -- }
   (NEED-IMAGE)
   x (CLAMP) TO x  y (CLAMP) TO y
   BEGIN u 0> WHILE
      addr u (UTF8-NEXT) (LOAD-GLYPH) TO advance TO u TO addr
      advance 0>= IF
         x y (DRAW-LOADED)
         x  advance (TEXT-SCALE) @ *  +  (CLAMP) TO x
      THEN
   REPEAT ;

\ How wide TEXT draws the string, in pixels.
: TEXT-WIDTH { addr u | w -- w }
   0 TO w
   BEGIN u 0> WHILE
      addr u (UTF8-NEXT) (LOAD-GLYPH)  DUP 0< IF DROP ELSE w + TO w THEN  TO u TO addr
   REPEAT
   w (TEXT-SCALE) @ * ;

\ ---- Tcl/Tk ---------------------------------------------------------------------------

\ The TCL words talk to a Tcl/Tk interpreter (wish) that runs as a program of its own,
\ started the first time it is needed: the program TCL-PROGRAM named, else SIGMA_WISH,
\ else wish on the PATH (macOS: not /usr/bin/wish), else Git for Windows's wish
\ (Windows) or Homebrew's or MacPorts's (macOS). The words underneath:
\   GFX-TCL ( c-addr u -- c-addr2 u2 flag )  runs a script: its result, or with a true
\     flag its error message (GFX-TCL-ERROR ( -- c-addr u ) gives the message again)
\   GFX-TCL-EVENT ( -- c-addr u true | false )  GFX-TCL-PROGRAM ( c-addr u -- )
\   GFX-TCL-STOP ( -- )  GFX-SHOW-TK ( -- )
\ A result stays until the next script, an event until the next TCL-EVENT.

\ The result of a Tcl script; TCL ERROR (THROW -273) when it fails, whose message
\ TCL-ERROR$ gives.
: TCL-EVAL ( c-addr u -- c-addr2 u2 )   GFX-TCL IF 2DROP -273 THROW THEN ;
: TCL ( c-addr u -- )   TCL-EVAL 2DROP ;
: TCL-ERROR$ ( -- c-addr u )   GFX-TCL-ERROR ;
\ The next text a Tk widget sent with sigma_event, without waiting.
: TCL-EVENT ( -- c-addr u true | false )   GFX-TCL-EVENT ;
: TCL-PROGRAM ( c-addr u -- )   GFX-TCL-PROGRAM ;
: TCL-STOP ( -- )   GFX-TCL-STOP ;
\ Make SHOW show the image in a Tk window, from which INKEY and MOUSE also read.
: DISPLAY-TK ( -- )   3 (DISPLAY) ! ;

\ ---- Images ----------------------------------------------------------------------

\ Images besides the screen, outside the dictionary's memory: at most 256, and 1 GiB
\ in all. A handle names one; SCREEN is the screen. The drawing words, GFX-WIDTH,
\ GFX-HEIGHT, and the SAVE- words use the image DRAW-TO chose; SHOW always shows the
\ screen. FREE-IMAGE, or a handle from before SAVE or SAVESYS, makes a handle invalid
\ (INVALID IMAGE HANDLE, THROW -278).
\   GFX-IMAGE-NEW ( w h -- img )  GFX-IMAGE-FREE ( img -- )  GFX-IMAGE-SIZE ( img -- w h )
\   GFX-TARGET ( img -- )  GFX-TARGET@ ( -- img )
\   GFX-COPY ( src sx sy w h dx dy key flip mode alpha scale -- )
0 CONSTANT SCREEN
: NEW-IMAGE ( w h -- img )   GFX-IMAGE-NEW ;
: FREE-IMAGE ( img -- )   GFX-IMAGE-FREE ;
: IMAGE-SIZE ( img -- w h )   GFX-IMAGE-SIZE ;
: DRAW-TO ( img -- )   GFX-TARGET ;
: DRAWING ( -- img )   GFX-TARGET@ ;

VARIABLE (TRANSPARENT)  -1 (TRANSPARENT) !
VARIABLE (FLIP)  0 (FLIP) !
\ The color COPY-RECT and PUT-IMAGE leave out, or -1 for none.
: TRANSPARENT ( rgb|-1 -- )   DUP 0< IF DROP -1 ELSE $FFFFFF AND THEN (TRANSPARENT) ! ;
\ How COPY-RECT and PUT-IMAGE flip: 0 not, 1 left and right, 2 top and bottom, 3 both.
: IMAGE-FLIP ( n -- )   DUP 0 4 WITHIN 0= IF DROP -24 THROW THEN (FLIP) ! ;
\ Copy the w by h rectangle at sx sy of image src to dx dy of the image drawn on.
VARIABLE (MODE)  0 (MODE) !
VARIABLE (ALPHA)  128 (ALPHA) !
VARIABLE (SCALE)  1 (SCALE) !
\ How COPY-RECT and PUT-IMAGE put the pixels: 0 over those there, 1 XOR, 2 added (each
\ color at most 255), 3 mixed with them by IMAGE-ALPHA.
: IMAGE-MODE ( n -- )   DUP 0 4 WITHIN 0= IF DROP -24 THROW THEN (MODE) ! ;
\ How much of the copy mode 3 shows, 0 (none) to 255 (all); 128 at the start.
: IMAGE-ALPHA ( n -- )   DUP 0 256 WITHIN 0= IF DROP -24 THROW THEN (ALPHA) ! ;
\ COPY-RECT and PUT-IMAGE draw each pixel n by n, 1 to 16.
: IMAGE-SCALE ( n -- )   DUP 1 17 WITHIN 0= IF DROP -24 THROW THEN (SCALE) ! ;
: COPY-RECT ( src sx sy w h dx dy -- )
   (TRANSPARENT) @ (FLIP) @ (MODE) @ (ALPHA) @ (SCALE) @ GFX-COPY ;
\ Copy the whole image src to x y of the image drawn on.
: PUT-IMAGE { src x y | w h -- }   src IMAGE-SIZE TO h TO w  src 0 0 w h x y COPY-RECT ;
\ Read a PNG, BMP, or PPM/PGM file into a new image. Pixels more than half transparent
\ get the TRANSPARENT color (black when there is none); IMAGE FORMAT ERROR (-279) for
\ a file it cannot read.
: LOAD-IMAGE ( c-addr u -- img )   (TRANSPARENT) @ GFX-IMAGE-LOAD THROW ;
