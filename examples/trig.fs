\ A demonstration of the graphs of the graphics words: sin x, cos x, and tan x from -2π
\ to 2π, with a grid, the axes, labels, and a legend. It needs a build with graphics
\ and floating-point numbers.
\
\   sigma.exe examples/trig.fs       (in a window; Tk on Linux/macOS)
\
\ The window shows the 480 by 300 image twice as large; a key pressed in the console
\ (or the terminal) ends the demonstration.

REQUIRE-GRAPHICS  ALSO GRAPHICS

480 CONSTANT W
300 CONSTANT H
\ PI is Sigma's own. x is shown a little beyond -2π .. 2π, so that the labels fit.
2e0 PI F* 0.35e0 F+ FCONSTANT X-LIMIT
3e0 FCONSTANT Y-LIMIT

\ tan x, but NaN where it is far beyond the image: PLOT leaves a gap there, instead of
\ a line from the top to the bottom across each asymptote.
: TAN-GAPS ( F: x -- y )   FTAN  FDUP FABS 10e0 F> IF  FDROP 0e0 0e0 F/  THEN ;

\ ---- The grid, the axes, and the labels ------------------------------------------

: VERTICAL ( F: x -- )   { F: x }  x Y-LIMIT FNEGATE x Y-LIMIT MLINE ;
: HORIZONTAL ( F: y -- )   { F: y }  X-LIMIT FNEGATE y X-LIMIT y MLINE ;

: GRID ( -- )
   40 40 40 COLOR
   5 -4 DO  I S>F PI F* 2e0 F/ VERTICAL  LOOP        \ every π/2
   4 -3 DO  I S>F HORIZONTAL  LOOP ;                  \ every 1
: MAIN-LINES ( -- )
   90 90 90 COLOR
   3 -2 DO  I S>F PI F* VERTICAL  LOOP  AXES ;        \ every π, and the axes

\ Text on a black box, so that the lines behind it do not cross it.
: LABEL ( c-addr u x y -- )
   2>R  COLOR@ 0 0 0 COLOR
   2R@ SWAP 1- SWAP 1-  4 PICK 4 PICK TEXT-WIDTH 2 +  TEXT-HEIGHT 2 +  FILL-RECT
   COLOR!  2R> TEXT ;
\ Its middle at the point x of the x axis, below it.
: X-LABEL ( c-addr u -- ) ( F: x -- )
   (M>PX)  >R 2DUP TEXT-WIDTH 2/ R> SWAP -  0e0 (M>PY) 3 +  LABEL ;
\ At the left edge, its middle at the height y.
: Y-LABEL ( c-addr u -- ) ( F: y -- )
   (M>PY)  4 SWAP 4 -  LABEL ;

: LABELS ( -- )
   170 170 170 COLOR
   S" -2pi" -2e0 PI F* X-LABEL  S" -pi" PI FNEGATE X-LABEL
   S" pi" PI X-LABEL  S" 2pi" 2e0 PI F* X-LABEL
   S" 2" 2e0 Y-LABEL  S" 1" 1e0 Y-LABEL  S" -1" -1e0 Y-LABEL  S" -2" -2e0 Y-LABEL ;

\ ---- The legend -------------------------------------------------------------------

: ENTRY ( c-addr u r g b row -- )   \ a short thick line of the color, and the name
   >R COLOR
   W 64 - R@ 12 * 12 + 16 3 FILL-RECT
   W 42 - R> 12 * 9 + TEXT ;

: LEGEND ( -- )
   0 0 0 COLOR  W 72 - 4 68 44 FILL-RECT
   100 100 100 COLOR  W 72 - 4 68 44 RECT
   S" sin x" 255 220 0 0 ENTRY
   S" cos x" 0 220 255 1 ENTRY
   S" tan x" 255 90 200 2 ENTRY ;

\ ---- The demonstration ------------------------------------------------------------

: GRAPHS ( -- )
   255 90 200 COLOR  ['] TAN-GAPS PLOT
   0 220 255 COLOR   ['] FCOS PLOT
   255 220 0 COLOR   ['] FSIN PLOT ;

: DRAW ( -- )
   W H GFX-INIT
   X-LIMIT FNEGATE X-LIMIT X-RANGE  Y-LIMIT FNEGATE Y-LIMIT Y-RANGE
   GRID MAIN-LINES GRAPHS LABELS LEGEND ;

: TRIG-DEMO ( -- )
   DRAW  W 2* H 2* WINDOW-SIZE  SHOW
   CR ." Press a key to end." CR
   BEGIN 50 MS INKEY -1 <> UNTIL ;

TRIG-DEMO
