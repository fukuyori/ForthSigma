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

\ Where SHOW puts the image: 0 automatic (see SHOW), 1 the terminal, 2 the window,
\ 3 the Tk window (DISPLAY-TK). And how the terminal shows it: 0 with half block
\ characters, 1 as Sixel graphics.
VARIABLE (DISPLAY)  0 (DISPLAY) !
VARIABLE (TERMINAL-MODE)  0 (TERMINAL-MODE) !

: DISPLAY-TERMINAL ( -- )   1 (DISPLAY) ! ;
\ HOST FUNCTION UNAVAILABLE when the host has no window.
: DISPLAY-WINDOW ( -- )   GFX-WINDOW? 0= IF -21 THROW THEN  2 (DISPLAY) ! ;
: DISPLAY-AUTO ( -- )   0 (DISPLAY) !  0 GFX-AUTO-DISPLAY! ;
\ FULLSCREEN: Sigma's own window covers its screen (true) or is a window again (false).
\ The user leaves fullscreen with Alt+Enter (Control+Command+F on macOS); FULLSCREEN?
\ then gives false. Asked before SHOW has chosen where to show, the window opens so;
\ the terminal takes no notice. HOST FUNCTION UNAVAILABLE with DISPLAY-TERMINAL.
\ Whether SHOW shows in the Tk window, chosen or found by the automatic choice.
: (TK-SHOWN?) ( -- flag )   (DISPLAY) @ DUP 0= IF DROP GFX-AUTO-DISPLAY THEN 3 = ;
: FULLSCREEN ( flag -- )
   (DISPLAY) @ 1 = IF -21 THROW THEN
   0<> DUP GFX-FULLSCREEN
   (TK-SHOWN?) IF
      IF S" sigma_fullscreen 1" ELSE S" sigma_fullscreen 0" THEN GFX-TCL DROP 2DROP EXIT
   THEN DROP ;
\ In the Tk window, as the window is, and the wish follows it; before the window is
\ opened (an empty answer), the wish as it is.
: FULLSCREEN? ( -- flag )
   (TK-SHOWN?) IF
      S" sigma_fullscreen_state" GFX-TCL IF 2DROP GFX-FULLSCREEN? EXIT THEN
      1 <> IF DROP GFX-FULLSCREEN? EXIT THEN
      C@ [CHAR] 1 =  DUP GFX-FULLSCREEN EXIT
   THEN GFX-FULLSCREEN? ;
\ Whether the mouse cursor shows over Sigma's own window (at first it does).
: MOUSE-CURSOR ( flag -- )
   0<> DUP GFX-MOUSE-CURSOR
   (TK-SHOWN?) IF
      IF S" sigma_cursor 1" ELSE S" sigma_cursor 0" THEN GFX-TCL DROP 2DROP EXIT
   THEN DROP ;
\ The displays of the machine. DISPLAYS takes them as they are now and gives how many
\ there are (0 where they cannot be told); the DISPLAY- words then tell of display i (0 to
\ that number less 1) as DISPLAYS took it, until the next DISPLAYS. Places and sizes are
\ in physical pixels of the desktop, whose origin is the primary display's top left
\ corner: a display left of it or above it has negative coordinates. DISPLAY-WORK is the
\ part an ordinary window may cover. DISPLAY-SCALE (3 2 for 150%) and DISPLAY-HZ
\ (60000 1001 for 59.94 Hz) are fractions; a denominator of 0 says the value is not
\ known. INVALID NUMERIC ARGUMENT for a display that is not there.
: DISPLAYS ( -- n )   TRUE GFX-DISPLAYS ;
: DISPLAY-RECT ( i -- x y w h )   4 0 DO  DUP I GFX-DISPLAY-INFO SWAP  LOOP DROP ;
: DISPLAY-WORK ( i -- x y w h )   8 4 DO  DUP I GFX-DISPLAY-INFO SWAP  LOOP DROP ;
: DISPLAY-SCALE ( i -- num den )   DUP 8 GFX-DISPLAY-INFO SWAP 9 GFX-DISPLAY-INFO ;
: DISPLAY-HZ ( i -- num den )   DUP 10 GFX-DISPLAY-INFO SWAP 11 GFX-DISPLAY-INFO ;
\ The primary display, or -1 when DISPLAYS gave none.
: DISPLAY-PRIMARY ( -- i )   0 -1 GFX-DISPLAY-INFO ;
\ The window system's identifier of the Tk window while it is shown, or 0: no answer, a
\ window that is not shown, or an answer that is not a number. winfo id gives "0x80e90";
\ Tcl's expr makes it the decimal number this reads.
: (TK-WINDOW-ID) ( -- id )
   S" expr {[winfo ismapped .] ? [winfo id .] : 0}" GFX-TCL IF 2DROP 0 EXIT THEN
   DUP 0= IF 2DROP 0 EXIT THEN
   BASE @ >R DECIMAL  0 0 2SWAP >NUMBER  R> BASE !
   NIP OR IF DROP 0 THEN ;
\ The display Sigma's window is on, among those DISPLAYS took: the host's own window, or
\ the Tk window when SHOW shows there. -1 without a window, when its display was not
\ there then, or on a host that cannot tell.
: WINDOW-DISPLAY ( -- i )
   (TK-SHOWN?) IF  (TK-WINDOW-ID) ?DUP 0= IF -1 EXIT THEN  ELSE 0 THEN  GFX-WINDOW-DISPLAY ;
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

\ Automatic display is selected once per process, independently of saved Forth
\ dictionaries. Host startup failures may fall through to Tk, then terminal.
: (AUTO-SHOW-WINDOW) ( -- )
   ['] GFX-SHOW-WINDOW CATCH ?DUP IF
      DUP -265 = IF 3 GFX-AUTO-DISPLAY! THEN
      THROW
   THEN ;

: (AUTO-SHOW-TK) ( -- )
   ['] GFX-SHOW-TK CATCH ?DUP IF
      DUP -265 = IF 1 GFX-AUTO-DISPLAY! THEN
      THROW
   THEN ;

: (AUTO-SHOW) ( -- )
   GFX-AUTO-DISPLAY DUP 2 = IF DROP (AUTO-SHOW-WINDOW) EXIT THEN
   DUP 3 = IF DROP (AUTO-SHOW-TK) EXIT THEN
   DUP 1 = IF DROP (TERMINAL-MODE) @ IF GFX-SHOW-SIXEL ELSE GFX-SHOW-BLOCKS THEN EXIT THEN
   DROP
   ['] (DESKTOP?) CATCH ?DUP IF DROP FALSE THEN
   GFX-AUTO-TRY DUP GFX-AUTO-DISPLAY!
   1 <> IF EXIT THEN
   (TERMINAL-MODE) @ IF GFX-SHOW-SIXEL ELSE GFX-SHOW-BLOCKS THEN ;

\ Shows the image where DISPLAY-TERMINAL, DISPLAY-WINDOW, or DISPLAY-TK said, with the
\ colors DISPLAY-COLORS and DITHER chose. Automatic display remembers its successful
\ backend for this process and falls back only when a backend cannot start.
: SHOW ( -- )
   (NEED-IMAGE)
   (COLORS) @ (DITHER) @ GFX-COLOR-MODE
   (DISPLAY) @ 0= IF (AUTO-SHOW) EXIT THEN
   (DISPLAY) @ 3 = IF GFX-SHOW-TK EXIT THEN
   (DISPLAY) @ 2 = IF
      ['] GFX-SHOW-WINDOW CATCH ?DUP IF DUP -21 = IF DROP -265 THEN THROW THEN
      EXIT
   THEN
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
\ The oldest press, release, or notch of the wheel not yet read, without waiting: kind 1
\ pressed, 2 released (button 1 left, 2 right, 4 middle), 3 the wheel (button 1 up, -1
\ down), at the pixel x y of the image. 64 are kept; when more come, the oldest go.
: MOUSE-EVENT ( -- x y button kind true | false )   GFX-MOUSE-EVENT ;

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
\     flag the script's error message (GFX-TCL-ERROR ( -- c-addr u ) gives the message
\     again); it throws -265 when the program cannot be started or has ended
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

\ Physical keys: independent of INKEY and EKEY; USB HID page 0x07.
: SCAN-INPUT? ( -- flag ) GFX-SCAN-INPUT? ;
: SCAN-SUPPORTED? ( scan -- flag ) GFX-SCAN-SUPPORTED? ;
: SCAN-HELD? ( scan -- flag ) GFX-SCAN-HELD? ;
: KEY-EVENT ( -- scan kind true | false ) GFX-KEY-EVENT ;
: KEY-RESYNC ( addr -- ) GFX-KEY-RESYNC ;
4 CONSTANT SC-A
5 CONSTANT SC-B
6 CONSTANT SC-C
7 CONSTANT SC-D
8 CONSTANT SC-E
9 CONSTANT SC-F
10 CONSTANT SC-G
11 CONSTANT SC-H
12 CONSTANT SC-I
13 CONSTANT SC-J
14 CONSTANT SC-K
15 CONSTANT SC-L
16 CONSTANT SC-M
17 CONSTANT SC-N
18 CONSTANT SC-O
19 CONSTANT SC-P
20 CONSTANT SC-Q
21 CONSTANT SC-R
22 CONSTANT SC-S
23 CONSTANT SC-T
24 CONSTANT SC-U
25 CONSTANT SC-V
26 CONSTANT SC-W
27 CONSTANT SC-X
28 CONSTANT SC-Y
29 CONSTANT SC-Z
30 CONSTANT SC-1
31 CONSTANT SC-2
32 CONSTANT SC-3
33 CONSTANT SC-4
34 CONSTANT SC-5
35 CONSTANT SC-6
36 CONSTANT SC-7
37 CONSTANT SC-8
38 CONSTANT SC-9
39 CONSTANT SC-0
40 CONSTANT SC-RETURN
41 CONSTANT SC-ESCAPE
42 CONSTANT SC-BACKSPACE
43 CONSTANT SC-TAB
44 CONSTANT SC-SPACE
45 CONSTANT SC-MINUS
46 CONSTANT SC-EQUALS
47 CONSTANT SC-LEFTBRACKET
48 CONSTANT SC-RIGHTBRACKET
49 CONSTANT SC-BACKSLASH
50 CONSTANT SC-NONUSHASH
51 CONSTANT SC-SEMICOLON
52 CONSTANT SC-APOSTROPHE
53 CONSTANT SC-GRAVE
54 CONSTANT SC-COMMA
55 CONSTANT SC-PERIOD
56 CONSTANT SC-SLASH
57 CONSTANT SC-CAPSLOCK
58 CONSTANT SC-F1
59 CONSTANT SC-F2
60 CONSTANT SC-F3
61 CONSTANT SC-F4
62 CONSTANT SC-F5
63 CONSTANT SC-F6
64 CONSTANT SC-F7
65 CONSTANT SC-F8
66 CONSTANT SC-F9
67 CONSTANT SC-F10
68 CONSTANT SC-F11
69 CONSTANT SC-F12
70 CONSTANT SC-PRINTSCREEN
71 CONSTANT SC-SCROLLLOCK
72 CONSTANT SC-PAUSE
73 CONSTANT SC-INSERT
74 CONSTANT SC-HOME
75 CONSTANT SC-PAGEUP
76 CONSTANT SC-DELETE
77 CONSTANT SC-END
78 CONSTANT SC-PAGEDOWN
79 CONSTANT SC-RIGHT
80 CONSTANT SC-LEFT
81 CONSTANT SC-DOWN
82 CONSTANT SC-UP
83 CONSTANT SC-NUMLOCKCLEAR
84 CONSTANT SC-KP-DIVIDE
85 CONSTANT SC-KP-MULTIPLY
86 CONSTANT SC-KP-MINUS
87 CONSTANT SC-KP-PLUS
88 CONSTANT SC-KP-ENTER
89 CONSTANT SC-KP-1
90 CONSTANT SC-KP-2
91 CONSTANT SC-KP-3
92 CONSTANT SC-KP-4
93 CONSTANT SC-KP-5
94 CONSTANT SC-KP-6
95 CONSTANT SC-KP-7
96 CONSTANT SC-KP-8
97 CONSTANT SC-KP-9
98 CONSTANT SC-KP-0
99 CONSTANT SC-KP-PERIOD
100 CONSTANT SC-NONUSBACKSLASH
101 CONSTANT SC-APPLICATION
102 CONSTANT SC-POWER
103 CONSTANT SC-KP-EQUALS
104 CONSTANT SC-F13
105 CONSTANT SC-F14
106 CONSTANT SC-F15
107 CONSTANT SC-F16
108 CONSTANT SC-F17
109 CONSTANT SC-F18
110 CONSTANT SC-F19
111 CONSTANT SC-F20
112 CONSTANT SC-F21
113 CONSTANT SC-F22
114 CONSTANT SC-F23
115 CONSTANT SC-F24
116 CONSTANT SC-EXECUTE
117 CONSTANT SC-HELP
118 CONSTANT SC-MENU
119 CONSTANT SC-SELECT
120 CONSTANT SC-STOP
121 CONSTANT SC-AGAIN
122 CONSTANT SC-UNDO
123 CONSTANT SC-CUT
124 CONSTANT SC-COPY
125 CONSTANT SC-PASTE
126 CONSTANT SC-FIND
127 CONSTANT SC-MUTE
128 CONSTANT SC-VOLUMEUP
129 CONSTANT SC-VOLUMEDOWN
130 CONSTANT SC-LOCKINGCAPSLOCK
131 CONSTANT SC-LOCKINGNUMLOCK
132 CONSTANT SC-LOCKINGSCROLLLOCK
133 CONSTANT SC-KP-COMMA
134 CONSTANT SC-KP-EQUALSAS400
135 CONSTANT SC-INTERNATIONAL1
136 CONSTANT SC-INTERNATIONAL2
137 CONSTANT SC-INTERNATIONAL3
138 CONSTANT SC-INTERNATIONAL4
139 CONSTANT SC-INTERNATIONAL5
140 CONSTANT SC-INTERNATIONAL6
141 CONSTANT SC-INTERNATIONAL7
142 CONSTANT SC-INTERNATIONAL8
143 CONSTANT SC-INTERNATIONAL9
144 CONSTANT SC-LANG1
145 CONSTANT SC-LANG2
146 CONSTANT SC-LANG3
147 CONSTANT SC-LANG4
148 CONSTANT SC-LANG5
149 CONSTANT SC-LANG6
150 CONSTANT SC-LANG7
151 CONSTANT SC-LANG8
152 CONSTANT SC-LANG9
153 CONSTANT SC-ALTERASE
154 CONSTANT SC-SYSREQ
155 CONSTANT SC-CANCEL
156 CONSTANT SC-CLEAR
157 CONSTANT SC-PRIOR
158 CONSTANT SC-RETURN2
159 CONSTANT SC-SEPARATOR
160 CONSTANT SC-OUT
161 CONSTANT SC-OPER
162 CONSTANT SC-CLEARAGAIN
163 CONSTANT SC-CRSEL
164 CONSTANT SC-EXSEL
176 CONSTANT SC-KP-00
177 CONSTANT SC-KP-000
178 CONSTANT SC-THOUSANDSSEPARATOR
179 CONSTANT SC-DECIMALSEPARATOR
180 CONSTANT SC-CURRENCYUNIT
181 CONSTANT SC-CURRENCYSUBUNIT
182 CONSTANT SC-KP-LEFTPAREN
183 CONSTANT SC-KP-RIGHTPAREN
184 CONSTANT SC-KP-LEFTBRACE
185 CONSTANT SC-KP-RIGHTBRACE
186 CONSTANT SC-KP-TAB
187 CONSTANT SC-KP-BACKSPACE
188 CONSTANT SC-KP-A
189 CONSTANT SC-KP-B
190 CONSTANT SC-KP-C
191 CONSTANT SC-KP-D
192 CONSTANT SC-KP-E
193 CONSTANT SC-KP-F
194 CONSTANT SC-KP-XOR
195 CONSTANT SC-KP-POWER
196 CONSTANT SC-KP-PERCENT
197 CONSTANT SC-KP-LESS
198 CONSTANT SC-KP-GREATER
199 CONSTANT SC-KP-AMPERSAND
200 CONSTANT SC-KP-DBLAMPERSAND
201 CONSTANT SC-KP-VERTICALBAR
202 CONSTANT SC-KP-DBLVERTICALBAR
203 CONSTANT SC-KP-COLON
204 CONSTANT SC-KP-HASH
205 CONSTANT SC-KP-SPACE
206 CONSTANT SC-KP-AT
207 CONSTANT SC-KP-EXCLAM
208 CONSTANT SC-KP-MEMSTORE
209 CONSTANT SC-KP-MEMRECALL
210 CONSTANT SC-KP-MEMCLEAR
211 CONSTANT SC-KP-MEMADD
212 CONSTANT SC-KP-MEMSUBTRACT
213 CONSTANT SC-KP-MEMMULTIPLY
214 CONSTANT SC-KP-MEMDIVIDE
215 CONSTANT SC-KP-PLUSMINUS
216 CONSTANT SC-KP-CLEAR
217 CONSTANT SC-KP-CLEARENTRY
218 CONSTANT SC-KP-BINARY
219 CONSTANT SC-KP-OCTAL
220 CONSTANT SC-KP-DECIMAL
221 CONSTANT SC-KP-HEXADECIMAL
224 CONSTANT SC-LCTRL
225 CONSTANT SC-LSHIFT
226 CONSTANT SC-LALT
227 CONSTANT SC-LGUI
228 CONSTANT SC-RCTRL
229 CONSTANT SC-RSHIFT
230 CONSTANT SC-RALT
231 CONSTANT SC-RGUI
1 CONSTANT SC-PRESS
2 CONSTANT SC-RELEASE
3 CONSTANT SC-RESYNC
