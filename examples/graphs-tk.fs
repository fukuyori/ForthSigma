\ The eight graphs of examples/graphs.fs drawn on a Tk canvas: Forth works out
\ where everything goes, and Tcl/Tk draws it as lines, rectangles, arcs, ovals,
\ and text of its own, so the graphs have smooth lines and the system's letters.
\ It needs a build with graphics and floating-point numbers, and Tcl/Tk (wish);
\ see "Tcl/Tk" in the user manual.
\
\   sigma.exe examples/graphs-tk.fs
\
\ Each graph grows into place and stays for four seconds. Space, Enter, or the
\ Next button goes on to the next at once; Q, Esc, the Quit button, or closing
\ the window ends the demonstration. The numbers in the charts are made up.

REQUIRE-GRAPHICS  ALSO GRAPHICS
DECIMAL

800 CONSTANT W
500 CONSTANT H

\ ---- How far the graph has grown --------------------------------------------------

\ Every graph is drawn whole for each frame, as far as P says: 0 is nothing, 1000
\ is all of it.
VARIABLE P
: PART ( n -- n' )   P @ 1000 */ ;                     \ n by the share P
: DONE? ( -- flag )   P @ 1000 = ;
: LERP ( a b f -- n )   >R OVER - R> 1000 */ + ;       \ from a to b by f / 1000

\ ---- The Tcl script of a frame, built in a buffer ---------------------------------

\ A frame is one script: it deletes the last frame's items and makes the new ones.
\ A place on the canvas is a whole number of tenths of a pixel, written as 123.4.
65536 CONSTANT SCRIPT-SIZE
CREATE SCRIPT   SCRIPT-SIZE ALLOT
VARIABLE SCRIPT#
: SCRIPT{ ( -- )   0 SCRIPT# ! ;
: +S ( c-addr u -- )
   DUP SCRIPT# @ + SCRIPT-SIZE > ABORT" The script is too long"
   TUCK  SCRIPT SCRIPT# @ +  SWAP MOVE  SCRIPT# +! ;
: +N ( n -- )   DUP ABS 0 <# BL HOLD #S ROT SIGN #> +S ;              \ and a space
: +C ( tenths -- )   DUP ABS 0 <# BL HOLD # [CHAR] . HOLD #S ROT SIGN #> +S ;
: +XY ( x y -- )   SWAP +C +C ;
: }TCL ( -- )   SCRIPT SCRIPT# @ TCL ;

\ ---- The window -------------------------------------------------------------------

\ The canvas's items are made by short Tcl commands, so that a frame's script is
\ short. Each takes a color as a number of the list `pal`; the items have the tag
\ g, by which the next frame deletes them.
\   R color x1 y1 x2 y2                a filled rectangle
\   L color width x y x y ...          a line through the points
\   D color x y x y ...                the same, thin and dashed
\   O color x y r                      a filled circle
\   A color x y r start extent         a slice of a pie (degrees, as Tk counts them)
\   T color size anchor x y text       text; anchor 0 its top middle at x y,
\                                      1 its right end, 2 its left end, 3 its middle
: WINDOW ( -- )
   \ The window stays hidden until it has all its widgets: on macOS, a window shown
   \ while it grows can be left partly undrawn.
   S" catch {destroy .g}; toplevel .g; wm withdraw .g; wm title .g {FORTH/Sigma Graphs}; wm resizable .g 0 0" TCL
   S" canvas .g.c -width 800 -height 500 -bg #10121c -highlightthickness 0; pack .g.c" TCL
   S" frame .g.f; button .g.f.n -text Next -command {sigma_event next}; button .g.f.q -text Quit -command {sigma_event quit}" TCL
   S" pack .g.f.n .g.f.q -side left -padx 6 -pady 6; pack .g.f" TCL
   S" set pal {#4e79a7 #f28e2b #e15759 #76b7b2 #59a14f #edc948 #2c3040 #9696a0 #aaaab4 #ebebeb}" TCL
   S" proc R {i x1 y1 x2 y2} {.g.c create rectangle $x1 $y1 $x2 $y2 -fill [lindex $::pal $i] -outline {} -tags g}" TCL
   S" proc L {i w args} {if {[llength $args] >= 4} {.g.c create line {*}$args -fill [lindex $::pal $i] -width $w -capstyle round -joinstyle round -tags g}}" TCL
   S" proc D {i args} {if {[llength $args] >= 4} {.g.c create line {*}$args -fill [lindex $::pal $i] -dash {4 4} -tags g}}" TCL
   S" proc O {i x y r} {.g.c create oval [expr {$x-$r}] [expr {$y-$r}] [expr {$x+$r}] [expr {$y+$r}] -fill [lindex $::pal $i] -outline {} -tags g}" TCL
   S" proc A {i x y r s e} {if {$e != 0} {.g.c create arc [expr {$x-$r}] [expr {$y-$r}] [expr {$x+$r}] [expr {$y+$r}] -start $s -extent $e -fill [lindex $::pal $i] -outline #10121c -tags g}}" TCL
   S" proc T {i size a x y text} {.g.c create text $x $y -text $text -fill [lindex $::pal $i] -font [list Helvetica $size] -anchor [lindex {n e w center} $a] -tags g}" TCL
   S" foreach k {space Return Right} {bind .g <KeyPress-$k> {sigma_event next}}; foreach k {q Q Escape} {bind .g <KeyPress-$k> {sigma_event quit}}" TCL
   S" wm protocol .g WM_DELETE_WINDOW {sigma_event quit}; update idletasks; wm deiconify .g; focus -force .g" TCL ;

\ ---- Colors, shapes, and text -----------------------------------------------------

VARIABLE INK#                                           \ the color the next items have
: INK ( n -- )   INK# ! ;
: GRID-INK ( -- )   6 INK ;
: AXIS-INK ( -- )   7 INK ;
: LABEL-INK ( -- )  8 INK ;
: BRIGHT-INK ( -- ) 9 INK ;
: +INK ( -- )   INK# @ +N ;
: +END ( -- )   S" ; " +S ;                            \ the end of a Tcl command

VARIABLE WIDTH                                          \ of lines, in pixels
VARIABLE SIZE                                           \ of letters, in points
: SMALL ( -- )   11 SIZE ! ;
: LARGE ( -- )   20 SIZE ! ;

: PATCH ( x1 y1 x2 y2 -- )     S" R " +S +INK  2SWAP +XY +XY  +END ;
: SEGMENT ( x1 y1 x2 y2 -- )   S" L " +S +INK  WIDTH @ +N  2SWAP +XY +XY  +END ;
: DOT ( x y r -- )             S" O " +S +INK  >R +XY R> +N  +END ;
\ A slice round x y: `start` and `extent` are tenths of a degree, counted as Tk
\ does, from 3 o'clock and against the clock.
: WEDGE ( x y r start extent -- )
   S" A " +S +INK  2>R >R +XY R> +N  2R> SWAP +C +C  +END ;

\ A line through many points: PATH{ or DASHES{ , then +XY for each point, then }PATH .
: PATH{ ( -- )     S" L " +S +INK  WIDTH @ +N ;
: DASHES{ ( -- )   S" D " +S +INK ;
: }PATH ( -- )     +END ;

\ The text is kept aside first: it may be a number that N>S made, and the numbers
\ of the command are made in the same place.
CREATE KEPT   128 ALLOT
VARIABLE KEPT#
: KEEP ( c-addr u -- )   127 MIN  DUP KEPT# !  KEPT SWAP MOVE ;
: (TEXT) ( c-addr u x y anchor -- )
   >R 2>R  KEEP  2R> R>
   S" T " +S +INK  SIZE @ +N  +N  +XY  S" {" +S  KEPT KEPT# @ +S  S" }" +S  +END ;
: CTEXT ( c-addr u x y -- )   0 (TEXT) ;               \ its top middle at x y
: RTEXT ( c-addr u x y -- )   1 (TEXT) ;               \ its right end
: LTEXT ( c-addr u x y -- )   2 (TEXT) ;               \ its left end
: MTEXT ( c-addr u x y -- )   3 (TEXT) ;               \ its middle
: N>S ( n -- c-addr u )   DUP ABS 0 <# #S ROT SIGN #> ;

: TITLE ( c-addr u -- )   BRIGHT-INK  LARGE  W 5 * 180 CTEXT  SMALL ;

\ ---- The box of a graph, and the numbers it shows ---------------------------------

\ A graph is drawn in a box of the canvas, in pixels. RANGE says which x and y its
\ edges are; >PX and >PY give places in tenths of a pixel.
0 VALUE BX   0 VALUE BY   0 VALUE BW   0 VALUE BH
: BOX ( x y w h -- )   TO BH  TO BW  TO BY  TO BX ;
: WIDE-BOX ( -- )     90 70 670 350 BOX ;
: SQUARE-BOX ( -- )   225 70 350 350 BOX ;
: LEFT ( -- x )     BX 10 * ;
: RIGHT ( -- x )    BX BW + 10 * ;
: TOP ( -- y )      BY 10 * ;
: BOTTOM ( -- y )   BY BH + 10 * ;

FVARIABLE X0   FVARIABLE X1   FVARIABLE Y0   FVARIABLE Y1
: RANGE ( F: x0 x1 y0 y1 -- )   Y1 F!  Y0 F!  X1 F!  X0 F! ;
: >PX ( F: x -- ) ( -- px )
   X0 F@ F-  X1 F@ X0 F@ F- F/  BW 10 * S>F F*  FROUND F>S  LEFT + ;
: >PY ( F: y -- ) ( -- py )
   Y1 F@ FSWAP F-  Y1 F@ Y0 F@ F- F/  BH 10 * S>F F*  FROUND F>S  TOP + ;

: BOX-AXES ( -- )   \ the left and the bottom edges
   AXIS-INK  1 WIDTH !  LEFT TOP LEFT BOTTOM SEGMENT  LEFT BOTTOM RIGHT BOTTOM SEGMENT ;

\ A line across the box at y = n, with the number to its left.
: Y-TICK ( n -- )
   DUP S>F >PY                                          ( n py )
   GRID-INK  1 WIDTH !  LEFT OVER RIGHT OVER SEGMENT
   LABEL-INK  SWAP N>S ROT  LEFT 80 - SWAP  RTEXT ;
: Y-TICKS { lo hi step -- }   hi 1+ lo DO  I Y-TICK  step +LOOP ;

\ The number n below the box at x = n.
: X-TICK ( n -- )   LABEL-INK  DUP S>F >PX  SWAP N>S ROT  BOTTOM 60 + CTEXT ;
: X-TICKS { lo hi step -- }   hi 1+ lo DO  I X-TICK  step +LOOP ;

\ A small square of color n and a name, for a legend, at the pixel x y.
: KEY-ENTRY { c-addr u n x y -- }
   n INK  x 10 *  y 10 *  x 10 + 10 *  y 10 + 10 *  PATCH
   LABEL-INK  c-addr u  x 17 + 10 *  y 5 + 10 *  LTEXT ;

\ ---- 1. A bar chart ---------------------------------------------------------------

CREATE RAIN   52 , 56 , 118 , 125 , 138 , 168 , 154 , 168 , 210 , 198 , 93 , 51 ,
: MONTH ( i -- c-addr 3 )   3 * S" JanFebMarAprMayJunJulAugSepOctNovDec" DROP + 3 ;

: BAR { value i color -- }   \ from the bottom up to `value`, in column i
   color INK  i S>F 0.15e0 F+ >PX  value S>F >PY  i S>F 0.85e0 F+ >PX  BOTTOM  PATCH ;

: BARS ( -- )
   S" Monthly rainfall (mm)" TITLE
   WIDE-BOX  0e0 12e0 0e0 250e0 RANGE  0 250 50 Y-TICKS
   12 0 DO
      I CELLS RAIN + @  DUP PART I 0 BAR                ( value )
      DONE? IF  BRIGHT-INK  DUP N>S  I S>F 0.5e0 F+ >PX  3 PICK S>F >PY 170 -  CTEXT  THEN
      DROP
      LABEL-INK  I MONTH  I S>F 0.5e0 F+ >PX  BOTTOM 60 +  CTEXT
   LOOP
   BOX-AXES ;

\ ---- 2. A line chart --------------------------------------------------------------

CREATE NORTH   5 , 6 , 9 , 14 , 19 , 22 , 26 , 27 , 23 , 18 , 12 , 7 ,
CREATE SOUTH   23 , 23 , 21 , 19 , 16 , 13 , 12 , 14 , 16 , 18 , 20 , 22 ,

: POINT ( a i -- px py )   TUCK CELLS + @ S>F >PY  SWAP S>F >PX SWAP ;
: PART-END { x1 y1 x2 y2 f -- x y }   x1 x2 f LERP  y1 y2 f LERP ;

\ The line through the 12 values at `a`, as far as P says, with a dot at each value
\ it has reached.
: SERIES { a color -- }
   color INK  2 WIDTH !
   PATH{  a 0 POINT +XY
   11 0 DO
      P @ 11 *  I 1000 * -  0 MAX 1000 MIN              ( how much of this piece )
      DUP IF  a I POINT  a I 1+ POINT  4 ROLL PART-END +XY  ELSE DROP THEN
   LOOP  }PATH
   12 0 DO  P @ 11 *  I 1000 *  >= IF  a I POINT 4 DOT  THEN  LOOP ;

: LINES ( -- )
   S" Average temperature (C)" TITLE
   WIDE-BOX  -0.5e0 11.5e0 0e0 30e0 RANGE  0 30 5 Y-TICKS
   12 0 DO  LABEL-INK  I MONTH  I S>F >PX  BOTTOM 60 +  CTEXT  LOOP
   BOX-AXES
   NORTH 1 SERIES  SOUTH 3 SERIES
   S" North town" 1  BX 16 +  BY 8 +   KEY-ENTRY
   S" South town" 3  BX 16 +  BY 28 +  KEY-ENTRY ;

\ ---- 3. A pie chart ---------------------------------------------------------------

5 CONSTANT SLICES
CREATE SHARES   35 , 25 , 20 , 12 , 8 ,                 \ percent; their sum is 100
: SHARE ( i -- n )   CELLS SHARES + @ ;
: SLICE-NAME ( i -- c-addr u )   6 * S" Apple BananaCherryDate  Other " DROP + 6 -TRAILING ;

300 CONSTANT PIE-X   255 CONSTANT PIE-Y   165 CONSTANT PIE-R

\ Angles are in tenths of a degree, round from the top, clockwise: 3600 to a turn.
\ EDGES has where each slice starts, and where the last one ends.
CREATE EDGES   SLICES 1+ CELLS ALLOT
: EDGE ( i -- n )   CELLS EDGES + @ ;
: SET-EDGES ( -- )   0  SLICES 0 DO  DUP I CELLS EDGES + !  I SHARE 36 * +  LOOP  SLICES CELLS EDGES + ! ;
SET-EDGES

\ The point at `radius` pixels from the pie's middle, at an angle.
: SPOKE-END ( angle radius -- x y )
   10 * S>F  S>F 1800e0 F/ PI F*                        ( F: radius radians )
   FOVER FOVER FSIN F* FROUND F>S  PIE-X 10 * +
   FCOS F* FROUND F>S  PIE-Y 10 * SWAP - ;

: PERCENT ( n -- c-addr u )   0 <# [CHAR] % HOLD #S #> ;

: PIE ( -- )
   S" Fruit sold" TITLE
   SLICES 0 DO
      I EDGE  I 1+ EDGE 3600 PART MIN                   ( from to )
      2DUP < IF                                         \ Tk's angles go the other way
         I INK  PIE-X 10 *  PIE-Y 10 *  PIE-R  900 5 PICK -  5 PICK 5 PICK -  WEDGE
      THEN  2DROP
      I 1+ EDGE  3600 PART <= IF                        \ the whole slice is there
         BRIGHT-INK  I SHARE PERCENT  I EDGE I 1+ EDGE + 2/  PIE-R 62 100 */  SPOKE-END  MTEXT
      THEN
   LOOP
   SLICES 0 DO  I SLICE-NAME  I  560  I 26 * 190 +  KEY-ENTRY  LOOP ;

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
         3 INK  S>F >PY  SWAP S>F >PX  SWAP  3 DOT
      ELSE 2DROP THEN
   LOOP
   DONE? IF
      1 INK  2 WIDTH !  148e0 >PX  148e0 FITTED >PY  197e0 >PX  197e0 FITTED >PY  SEGMENT
      S" Least-squares line" 1  BX 16 +  BY 8 +  KEY-ENTRY
   THEN ;

\ ---- 5. A histogram ---------------------------------------------------------------

3000 CONSTANT THROWS
CREATE COUNTS   19 CELLS ALLOT                          \ how often each sum came

: DICE ( -- )
   S" The sum of three dice" TITLE
   WIDE-BOX  2.5e0 18.5e0 0e0 400e0 RANGE  0 400 100 Y-TICKS  3 18 1 X-TICKS
   COUNTS 19 CELLS ERASE  7 SEED !
   THROWS PART 0 ?DO  6 CHANCE 6 CHANCE 6 CHANCE + + 3 +  CELLS COUNTS +  1 SWAP +!  LOOP
   4 INK
   19 3 DO
      I S>F 0.4e0 F- >PX  I CELLS COUNTS + @ S>F >PY  I S>F 0.4e0 F+ >PX  BOTTOM  PATCH
   LOOP
   BOX-AXES
   LABEL-INK  THROWS PART N>S  RIGHT 80 -  TOP 100 +  RTEXT
   S" throws:"  RIGHT 480 -  TOP 100 +  RTEXT ;

\ ---- Curves -----------------------------------------------------------------------

\ The points of the curve of xt ( F: t -- x y ) for t from 0 to 1, in 600 pieces, the
\ first n of them.
: POINTS { xt n -- }
   0e0 xt EXECUTE  >PY >PX SWAP +XY
   n 0 ?DO  I 1+ S>F 600e0 F/ xt EXECUTE  >PY >PX SWAP +XY  LOOP ;
: CURVE ( xt -- )   2 WIDTH !  PATH{  600 PART POINTS  }PATH ;      \ as far as P says
: DASHED-CURVE ( xt -- )   DASHES{  600 POINTS  }PATH ;             \ the whole of it

: TURN ( F: t -- angle )   2e0 PI F* F* ;

\ ---- 6. The graph of a function ---------------------------------------------------

: ABOVE ( F: t -- x y )   12e0 F*  FDUP -0.25e0 F* FEXP ;
: BELOW ( F: t -- x y )   ABOVE FNEGATE ;
: SWING ( F: t -- x y )   ABOVE  FOVER 3e0 F* FCOS  F* ;

: WAVE ( -- )
   S" y = exp(-x/4) cos 3x" TITLE
   WIDE-BOX  0e0 12e0 -1.1e0 1.1e0 RANGE  -1 1 1 Y-TICKS  0 12 2 X-TICKS
   BOX-AXES
   AXIS-INK  ['] ABOVE DASHED-CURVE  ['] BELOW DASHED-CURVE
   5 INK  ['] SWING CURVE ;

\ ---- 7. A Lissajous figure --------------------------------------------------------

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
: RING ( F: t -- x y )   TURN  FDUP FCOS  FSWAP FSIN ;
: HALF-RING ( F: t -- x y )   RING  0.5e0 F*  FSWAP 0.5e0 F*  FSWAP ;

: ROSE-GRAPH ( -- )
   S" r = cos 4a" TITLE
   SQUARE-BOX  -1.15e0 1.15e0 -1.15e0 1.15e0 RANGE
   AXIS-INK  ['] HALF-RING DASHED-CURVE  ['] RING DASHED-CURVE
   GRID-INK  1 WIDTH !
   LEFT 0e0 >PY RIGHT OVER SEGMENT  0e0 >PX TOP OVER BOTTOM SEGMENT
   2 INK  ['] ROSE CURVE ;

\ ---- The demonstration ------------------------------------------------------------

8 CONSTANT #GRAPHS
CREATE GRAPHS
   ' BARS ,  ' LINES ,  ' PIE ,  ' SCATTER ,  ' DICE ,  ' WAVE ,  ' FIGURE ,  ' ROSE-GRAPH ,

: FOOTER ( n -- )   \ n is the graph, from 0
   LABEL-INK  SMALL
   1+ N>S  120 H 14 - 10 *  LTEXT
   S" / 8"  240 H 14 - 10 *  LTEXT
   S" Space: next   Q: quit"  W 12 - 10 *  H 14 - 10 *  RTEXT ;

\ One frame: the last frame's items go, and graph n is made as far as P says.
: DRAW ( n -- )
   SCRIPT{  S" .g.c delete g; " +S  SMALL
   DUP CELLS GRAPHS + @ EXECUTE  FOOTER
   S" update idletasks" +S  }TCL ;

\ What the window asks for: 0 nothing, 1 the next graph, 2 the end.
: ASKED ( -- n )
   TCL-EVENT IF  S" quit" COMPARE 0= IF 2 ELSE 1 THEN  ELSE 0 THEN ;

\ Graph n grows for about a second and a half and stays for four seconds.
: PRESENT ( n -- end? )
   1001 0 DO
      I P !  DUP DRAW  33 MS
      ASKED ?DUP IF  NIP 2 =  UNLOOP EXIT  THEN
   25 +LOOP
   120 0 DO
      33 MS  ASKED ?DUP IF  NIP 2 =  UNLOOP EXIT  THEN
   LOOP
   DROP FALSE ;

: GRAPH-DEMO ( -- )
   WINDOW
   0 BEGIN  DUP PRESENT 0=  WHILE  1+ #GRAPHS MOD  REPEAT  DROP
   S" destroy .g" TCL ;

GRAPH-DEMO
