\ Check by hand of Sigma's own window: the mouse, and whether the window can be moved,
\ resized, and closed while the program waits for input and while it computes
\ (tque #922). Run from the repository root, after `zig build`, with an input that
\ stays silent until part B has waited 20 seconds and then ends (part B makes the file
\ .work/check-window.go when it starts to wait):
\   mkdir -p .work; rm -f .work/check-window.go
\   (until [ -e .work/check-window.go ]; do sleep 0.2; done; sleep 20) |
\      zig-out/bin/sigma tests/scripts/check-window.fs -e "WINDOW-CHECK"
\ Part A: move the mouse over the image (a cross follows it), press and release the
\ left and the right button, turn the wheel, and press a button in the image and let it
\ go outside of the window. Each press, release, and notch is printed in the terminal.
\ Space or Enter in the window goes on.
\ Part B: the program reads its input and does nothing else until the input ends. Move
\ the window, resize it, then close it with its close button.
\ Part C: the program computes for 20 seconds without reading or showing anything.
\ Move, resize, and close the window again.
\ After B and after C the terminal tells the place of the mouse (-1 -1 once the window
\ was closed), and the next SHOW opens the window again. A key in the window ends.

REQUIRE-GRAPHICS  ALSO GRAPHICS
DECIMAL

: MESSAGE ( c-addr u -- )   CLS $FFFFFF COLOR!  10 10 TEXT ;
: CROSS ( -- )
   MOUSE DROP  OVER 0< IF 2DROP EXIT THEN
   $FFFF00 COLOR!
   2DUP SWAP 6 - SWAP 13 1 FILL-RECT
   6 - 1 13 FILL-RECT ;
: .EVENTS ( -- )
   BEGIN MOUSE-EVENT WHILE
      CR ." event: kind " . ." button " . ." at " SWAP . .
   REPEAT ;
: .MOUSE ( -- )   MOUSE ." mouse: buttons " . ." at " SWAP . . CR ;

: PART-A ( -- )
   CR ." A: mouse" CR
   BEGIN
      S" A: mouse. Space or Enter goes on." MESSAGE  CROSS  16 FRAME
      .EVENTS
      INKEY DUP 32 = OVER 13 = OR SWAP 10 = OR
   UNTIL CR ;

: PART-B ( -- )
   CR ." B: waiting for input" CR
   S" B: input wait 20 s. Move, resize, close." MESSAGE SHOW
   S" touch .work/check-window.go" SYSTEM
   BEGIN ['] KEY CATCH IF TRUE ELSE DROP FALSE THEN UNTIL
   ." B: the input ended. " .MOUSE ;

: PART-C ( -- )
   CR ." C: computing" CR
   S" C: computing 20 s. Move, resize, close." MESSAGE SHOW
   UTIME 20000000. D+
   BEGIN 2DUP UTIME D< UNTIL 2DROP
   ." C: the computation ended. " .MOUSE ;

: PART-D ( -- )
   BEGIN INKEY 0< UNTIL
   BEGIN
      S" Done. A key in this window ends." MESSAGE  CROSS  16 FRAME
      INKEY 0< 0=
   UNTIL
   CR ." the window answered after B and C" CR ;

: WINDOW-CHECK ( -- )
   DISPLAY-WINDOW  240 100 GFX-INIT  720 300 WINDOW-SIZE  MOUSE-ON
   PART-A PART-B PART-C PART-D BYE ;

\ Part C alone, for a check of the window closed while the program computes.
: WINDOW-CHECK-C ( -- )
   DISPLAY-WINDOW  240 100 GFX-INIT  720 300 WINDOW-SIZE  MOUSE-ON
   PART-C PART-D BYE ;

\ The wheel alone, with the time of each notch in milliseconds: for a check of how a
\ scroll that goes on after the fingers left the trackpad arrives. Space or Enter in
\ the window goes on.
VARIABLE WHEEL-START
: .WHEEL ( -- )
   BEGIN MOUSE-EVENT WHILE
      3 = IF CR ." wheel " . UTIME DROP 1000 / WHEEL-START @ - . ELSE DROP THEN 2DROP
   REPEAT ;
: PART-W ( -- )
   CR ." W: wheel" CR  UTIME DROP 1000 / WHEEL-START !
   BEGIN
      S" W: scroll, lift fingers. Space goes on." MESSAGE  CROSS  16 FRAME
      .WHEEL
      INKEY DUP 32 = OVER 13 = OR SWAP 10 = OR
   UNTIL CR ;

\ The wheel, then part C.
: WINDOW-CHECK-W ( -- )
   DISPLAY-WINDOW  240 100 GFX-INIT  720 300 WINDOW-SIZE  MOUSE-ON
   PART-W PART-C PART-D BYE ;
