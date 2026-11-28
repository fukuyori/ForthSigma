\ Turtle graphics for Sigma (task 1476); load from the repository root.
\ Public API: SPECIFICATION.md chapter 4. TT@ is the reserved private prefix.
\ Loading and headless commands never SHOW or FRAME.
BASE @ GET-CURRENT GET-ORDER
FORTH DEFINITIONS DECIMAL
VARIABLE TT@LOAD-CURRENT ( -- addr )
\ Saved below after the search order has been consumed.
VARIABLE TT@LOAD-BASE ( -- addr )
\ Saved below after the search order has been consumed.
CREATE TT@LOAD-ORDER 256 CELLS ALLOT ( -- addr )
VARIABLE TT@LOAD-N ( -- addr )
DUP TT@LOAD-N !
: TT@STORE-ORDER ( wid... n -- )
   0 ?DO TT@LOAD-ORDER I CELLS + ! LOOP
;
TT@STORE-ORDER
TT@LOAD-CURRENT ! TT@LOAD-BASE !
VARIABLE TT@LOAD-DONE ( -- addr )
: TT@RESTORE ( -- )
   TT@LOAD-N @ 0 ?DO TT@LOAD-ORDER TT@LOAD-N @ 1- I - CELLS + @ LOOP
   TT@LOAD-N @ SET-ORDER TT@LOAD-CURRENT @ SET-CURRENT TT@LOAD-BASE @ BASE !
;
: TT@READ ( -- )
   BEGIN REFILL WHILE SOURCE EVALUATE TT@LOAD-DONE @ IF EXIT THEN REPEAT
;
: TT@LOAD ( -- )
   ['] TT@READ CATCH TT@RESTORE THROW
;
TT@LOAD
DECIMAL
REQUIRE-GRAPHICS
ALSO GRAPHICS
VOCABULARY TURTLE
ALSO TURTLE DEFINITIONS

\ ---- Owned state and validation ----
-4200 CONSTANT TT@ERR-BOUNDS ( -- n )
-4201 CONSTANT TT@ERR-INPUT ( -- n )
-4205 CONSTANT TT@ERR-CANCEL ( -- n )
VARIABLE TT@IMG ( -- addr )
VARIABLE TT@W ( -- addr )
VARIABLE TT@H ( -- addr )
VARIABLE TT@PEN ( -- addr )
VARIABLE TT@COLOR ( -- addr )
VARIABLE TT@BG ( -- addr )
VARIABLE TT@SIZE ( -- addr )
VARIABLE TT@VISIBLE ( -- addr )
VARIABLE TT@MODE ( -- addr )
VARIABLE TT@SPEED ( -- addr )
VARIABLE TT@RUNNING ( -- addr )
VARIABLE TT@CLOSES ( -- addr )
VARIABLE TT@XT ( -- addr )
FVARIABLE TT@X ( -- addr )
FVARIABLE TT@Y ( -- addr )
FVARIABLE TT@HEADING ( -- addr )
3.141592653589793e 180e F/ FCONSTANT TT@RAD ( F: -- r )
CREATE TT@PALETTE ( -- addr )
$000000 , $0000FF , $00FF00 , $00FFFF ,
$FF0000 , $FF00FF , $FFFF00 , $FFFFFF ,
$A52A2A , $D2B48C , $228B22 , $7FFFD4 ,
$FA8072 , $800080 , $FFA500 , $808080 ,
: TT@FINITE ( F: r -- r )
   FDUP FDUP F- 0e F= 0= IF TT@ERR-INPUT THROW THEN
;
: TT@GEOMETRY ( F: r -- r )
   TT@FINITE FDUP FABS 1000000e F> IF TT@ERR-INPUT THROW THEN
;
: TT@INTEGER { n lo hi -- n }
   n lo hi 1+ WITHIN 0= IF TT@ERR-INPUT THROW THEN n
;
: TT@NUMBER-COLOR ( n -- rgb )
   0 15 TT@INTEGER CELLS TT@PALETTE + @
;
: TT@COMPONENT ( F: p -- ) ( -- n )
   TT@FINITE FDUP 0e F< IF TT@ERR-INPUT THROW THEN
   FDUP 100e F> IF TT@ERR-INPUT THROW THEN
   255e F* 100e F/ 0.5e F+ FLOOR F>S
;
: TT@RGB ( F: r g b -- ) ( -- rgb )
   TT@COMPONENT >R TT@COMPONENT >R TT@COMPONENT
   16 LSHIFT R> 8 LSHIFT OR R> OR
;
: TT@NORMAL { F: x F: period -- } ( F: -- x' )
   x period 2e F/ F+ period F/ FLOOR period F* x FSWAP F-
;
: TT@ANGLE ( F: a -- a' )
   TT@FINITE 360e TT@NORMAL FDUP 0e F< IF 360e F+ THEN TT@FINITE
;
: TT@INSIDE { F: x F: y -- flag }
   x TT@W @ S>F -2e F/ F>= x TT@W @ S>F 2e F/ F< AND
   y TT@H @ S>F -2e F/ F>= AND y TT@H @ S>F 2e F/ F< AND
;
: TT@BOUNDS ( F: x y -- )
   TT@INSIDE 0= IF TT@ERR-BOUNDS THROW THEN
;
: TT@TARGET ( -- )
   TT@IMG @ DRAW-TO
   TT@W @ 1- S>F 2e F/ FDUP FNEGATE FSWAP X-RANGE
   TT@H @ 1- S>F 2e F/ FDUP FNEGATE FSWAP Y-RANGE
   TT@COLOR @ COLOR!
;
: TT@PX ( F: x -- ) ( -- n )
   TT@W @ 1- S>F 2e F/ F+ TT@W @ 1- S>F F/ TT@W @ 1- S>F F* FROUND F>S
;
: TT@PY ( F: y -- ) ( -- n )
   TT@H @ 1- S>F 2e F/ FSWAP F- TT@H @ 1- S>F F/ TT@H @ 1- S>F F* FROUND F>S
;
\ The pure half of input polling is available to headless tests.
: TT@INPUT { key closes -- }
   key 27 = closes TT@CLOSES @ <> OR IF TT@ERR-CANCEL THROW THEN
;
: TT@POLL ( -- )
   TT@RUNNING @ IF
      BEGIN INKEY DUP -1 <> WHILE WINDOW-CLOSES TT@INPUT REPEAT
      WINDOW-CLOSES TT@INPUT
   THEN
;

\ ---- Pixel strokes and periodic geometry ----
: TT@STROKE { F: x1 F: y1 F: x2 F: y2 | ax ay bx by lo -- }
   TT@PEN @ 0= IF EXIT THEN
   TT@TARGET
   x1 TT@PX TO ax y1 TT@PY TO ay x2 TT@PX TO bx y2 TT@PY TO by
   TT@SIZE @ 1- 2 / NEGATE TO lo
   TT@SIZE @ 0 DO
      TT@SIZE @ 0 DO
         TT@POLL
         ax I lo + + ay J lo + + bx I lo + + by J lo + + LINE
      LOOP
   LOOP
;
\ Shift boundary-outward starts first. Each remaining interval ends at the
\ earliest x/y crossing; equal fractions shift both axes, including corners.
: TT@SEGMENT { F: ax F: ay F: bx F: by | F: dx F: dy F: tx F: ty F: t F: ex F: ey -- }
   TT@POLL
   TT@MODE @ 0<> IF ax ay bx by TT@STROKE EXIT THEN
   bx ax F- TO dx by ay F- TO dy
   ax TT@W @ S>F TT@NORMAL TO ax ay TT@H @ S>F TT@NORMAL TO ay
   BEGIN
      dx 0e F< ax TT@W @ S>F -2e F/ F<= AND IF ax TT@W @ S>F F+ TO ax THEN
      dy 0e F< ay TT@H @ S>F -2e F/ F<= AND IF ay TT@H @ S>F F+ TO ay THEN
      2e TO tx 2e TO ty
      dx 0e F> IF TT@W @ S>F 2e F/ ax F- dx F/ TO tx THEN
      dx 0e F< IF TT@W @ S>F -2e F/ ax F- dx F/ TO tx THEN
      dy 0e F> IF TT@H @ S>F 2e F/ ay F- dy F/ TO ty THEN
      dy 0e F< IF TT@H @ S>F -2e F/ ay F- dy F/ TO ty THEN
      tx ty FMIN 1e FMIN TO t
      ax dx t F* F+ TO ex ay dy t F* F+ TO ey
      ax ay ex ey TT@STROKE
      t 1e F>= IF EXIT THEN
      dx 1e t F- F* TO dx dy 1e t F- F* TO dy
      ex TO ax ey TO ay
      tx t F= IF dx 0e F> IF ax TT@W @ S>F F- ELSE ax TT@W @ S>F F+ THEN TO ax THEN
      ty t F= IF dy 0e F> IF ay TT@H @ S>F F- ELSE ay TT@H @ S>F F+ THEN TO ay THEN
      TT@POLL
   AGAIN
;
: TT@MOVE { F: x F: y -- }
   x TT@GEOMETRY FDROP y TT@GEOMETRY FDROP TT@POLL
   TT@MODE @ 2 = IF x y TT@BOUNDS THEN
   TT@X F@ TT@Y F@ x y TT@SEGMENT
   TT@MODE @ 0= IF
      x TT@W @ S>F TT@NORMAL TT@X F! y TT@H @ S>F TT@NORMAL TT@Y F!
   ELSE x TT@X F! y TT@Y F! THEN
;

\ ---- Composition (the turtle never touches the canvas) ----
: TT@VERTEX { F: forward F: side -- } ( F: -- x y )
   TT@HEADING F@ TT@RAD F* FSINCOS
   { F: sn F: cs -- }
   TT@X F@ forward sn F* F+ side cs F* F+
   TT@Y F@ forward cs F* F+ side sn F* F-
;
: TT@PAINT-BODY ( -- )
   TT@TARGET SCREEN DRAW-TO NO-CLIP
   -1 TRANSPARENT 0 IMAGE-FLIP 0 IMAGE-MODE 1 IMAGE-SCALE
   TT@IMG @ 0 0 PUT-IMAGE
   TT@VISIBLE @ IF
      10e 0e TT@VERTEX -6e -5e TT@VERTEX MLINE
      -6e -5e TT@VERTEX -6e 5e TT@VERTEX MLINE
      -6e 5e TT@VERTEX 10e 0e TT@VERTEX MLINE
   THEN
;
: TT@FIRST { first second -- error }
   first IF first ELSE second THEN
;
: TT@RESTORE-TARGET ( -- ) TT@IMG @ DRAW-TO ;
: TURTLE-PAINT ( -- )
   ['] TT@PAINT-BODY CATCH ['] TT@RESTORE-TARGET CATCH TT@FIRST THROW
;
: TT@DISPLAY ( -- )
   TT@POLL TURTLE-PAINT TT@POLL TT@SPEED @ FRAME
;
: TT@DONE ( -- )
   TT@POLL TT@RUNNING @ TT@SPEED @ 0> AND IF TT@DISPLAY THEN
;

\ ---- Lifetime and resets ----
: TURTLE-DISPOSE ( -- )
   TT@IMG @ ?DUP IF 0 TT@IMG ! FREE-IMAGE THEN
;
: TT@DEFAULTS ( -- )
   0e TT@X F! 0e TT@Y F! 0e TT@HEADING F!
   TRUE TT@PEN ! $FFFFFF TT@COLOR ! 0 TT@BG ! 1 TT@SIZE !
   TRUE TT@VISIBLE ! 0 TT@MODE ! 10 TT@SPEED !
;
: TT@NEW { w h -- }
   w 2 4096 TT@INTEGER DROP h 2 4096 TT@INTEGER DROP
   TURTLE-DISPOSE w h GFX-INIT
   w h NEW-IMAGE TT@IMG ! w TT@W ! h TT@H !
   TT@DEFAULTS TT@TARGET 0 GFX-CLS 0 WINDOW-FIT
;
: TURTLE-INIT ( w h -- )
   \ A saved dictionary may contain a stale image handle; never free it here.
   \ Dispose a live canvas before calling this startup entry again.
   0 TT@IMG ! FALSE TT@RUNNING ! TT@NEW
;
: SETSCREENSIZE ( w h -- ) TT@NEW TT@DONE ;
: TURTLE-IMAGE ( -- img ) TT@IMG @ ;
: TURTLE-SAVE-PNG ( addr u -- ) TT@TARGET SAVE-PNG ;

\ ---- Public movement, settings, and aliases ----
: SETXY ( F: x y -- ) TT@MOVE TT@DONE ;
: FD { F: d -- }
   d TT@GEOMETRY FDROP
   TT@HEADING F@ TT@RAD F* FSINCOS
   d F* TT@Y F@ F+ FSWAP d F* TT@X F@ F+ FSWAP SETXY
;
: FORWARD ( F: d -- ) FD ;
: BK ( F: d -- ) FNEGATE FD ;
: BACK ( F: d -- ) BK ;
: SETH ( F: a -- ) TT@ANGLE TT@HEADING F! TT@DONE ;
: SETHEADING ( F: a -- ) SETH ;
: RT ( F: a -- ) TT@FINITE TT@HEADING F@ F+ SETH ;
: RIGHT ( F: a -- ) RT ;
: LT ( F: a -- ) FNEGATE RT ;
: LEFT ( F: a -- ) LT ;
: PU ( -- ) FALSE TT@PEN ! TT@DONE ;
: PENUP ( -- ) PU ;
: PD ( -- ) TRUE TT@PEN ! TT@DONE ;
: PENDOWN ( -- ) PD ;
: HOME ( -- ) 0e 0e TT@MOVE 0e TT@HEADING F! TT@DONE ;
: TT@CLEAR ( -- ) TT@POLL TT@TARGET TT@BG @ GFX-CLS ;
: CLEAN ( -- ) TT@CLEAR TT@DONE ;
: CS ( -- ) TT@CLEAR 0e TT@X F! 0e TT@Y F! 0e TT@HEADING F! TT@DONE ;
: CLEARSCREEN ( -- ) CS ;
: SETPC ( n -- ) TT@NUMBER-COLOR TT@COLOR ! TT@DONE ;
: SETPENCOLOR ( n -- ) SETPC ;
: SETPENCOLOR-RGB ( F: r g b -- ) TT@RGB TT@COLOR ! TT@DONE ;
: SETBG ( n -- ) TT@NUMBER-COLOR TT@BG ! CLEAN ;
: SETBACKGROUND ( n -- ) SETBG ;
: SETBACKGROUND-RGB ( F: r g b -- ) TT@RGB TT@BG ! CLEAN ;
: SETPENSIZE ( n -- ) 1 64 TT@INTEGER TT@SIZE ! TT@DONE ;
: SETSPEED ( n -- ) 0 1000 TT@INTEGER TT@SPEED ! TT@DONE ;
: ST ( -- ) TRUE TT@VISIBLE ! TT@DONE ;
: SHOWTURTLE ( -- ) ST ;
: HT ( -- ) FALSE TT@VISIBLE ! TT@DONE ;
: HIDETURTLE ( -- ) HT ;
: WINDOW ( -- ) 1 TT@MODE ! TT@DONE ;
: WRAP ( -- )
   TT@X F@ TT@W @ S>F TT@NORMAL TT@X F!
   TT@Y F@ TT@H @ S>F TT@NORMAL TT@Y F!
   0 TT@MODE ! TT@DONE
;
: FENCE ( -- ) TT@X F@ TT@Y F@ TT@BOUNDS 2 TT@MODE ! TT@DONE ;
: LABEL ( addr u -- )
   TT@POLL TT@TARGET TT@X F@ TT@PX TT@Y F@ TT@PY TEXT TT@DONE
;

\ ---- Arc: preflight all vertices before any FENCE drawing ----
: TT@ARC-POINT { F: angle F: radius -- } ( F: -- x y )
   angle TT@RAD F* FSINCOS
   radius F* TT@Y F@ F+ FSWAP radius F* TT@X F@ F+ FSWAP
   TT@GEOMETRY FSWAP TT@GEOMETRY FSWAP
;
: ARC { F: angle F: radius | n F: step F: ax F: ay F: bx F: by -- }
   angle TT@GEOMETRY FDROP radius TT@GEOMETRY FDROP
   radius 0e F< IF TT@ERR-INPUT THROW THEN
   TT@POLL
   angle 0e F= TT@PEN @ 0= OR IF TT@DONE EXIT THEN
   angle FABS TT@RAD F* radius 1e FMAX F* FNEGATE FLOOR FNEGATE F>S 1 MAX TO n
   angle n S>F F/ TO step
   TT@MODE @ 2 = IF
      n 1+ 0 DO
         TT@POLL TT@HEADING F@ I S>F step F* F+ radius TT@ARC-POINT TT@BOUNDS
      LOOP
   THEN
   TT@HEADING F@ radius TT@ARC-POINT TO ay TO ax
   n 0 DO
      TT@HEADING F@ I 1+ S>F step F* F+ radius TT@ARC-POINT TO by TO bx
      ax ay bx by TT@SEGMENT bx TO ax by TO ay
   LOOP
   TT@DONE
;

\ ---- Display runner: keep a successful drawing open until cancellation ----
: TT@RUN-BODY ( -- )
   640 480 WINDOW-SIZE 0 WINDOW-FIT
   WINDOW-CLOSES TT@CLOSES ! TRUE TT@RUNNING !
   TT@POLL TURTLE-PAINT TT@POLL SHOW
   TT@XT @ EXECUTE TT@DISPLAY
   BEGIN TT@POLL 1 MS AGAIN
;
: TT@CLEANUP ( -- )
   FALSE TT@RUNNING ! WINDOW-CLOSE
;
: TURTLE-RUN ( xt -- )
   TT@XT ! ['] TT@RUN-BODY CATCH
   ['] TT@CLEANUP CATCH TT@FIRST
   ['] TURTLE-DISPOSE CATCH TT@FIRST
   DUP TT@ERR-CANCEL = IF DROP ELSE THROW THEN
;
PREVIOUS PREVIOUS
TRUE TT@LOAD-DONE !
