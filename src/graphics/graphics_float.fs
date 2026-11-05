\ The part of the graphics library that uses floating-point numbers: mathematical
\ coordinates and graphs of functions. REQUIRE-GRAPHICS interprets it right after
\ graphics.fs, as part of the same library, and only in a build with the floating-point
\ words (a build with -Dfloat=false leaves this file out).
\
\ X-RANGE and Y-RANGE say which part of the plane the image shows: x grows to the
\ right from the left edge to the right one, and y grows upward from the bottom edge
\ to the top one. Both start as -1 to 1. A coordinate that is not a number (NaN) draws
\ nothing; infinities and values far outside the image are limited like the integer
\ coordinates.

\ ---- Mathematical coordinates ------------------------------------------------------

FVARIABLE (X-MIN)  -1e0 (X-MIN) F!
FVARIABLE (X-MAX)   1e0 (X-MAX) F!
FVARIABLE (Y-MIN)  -1e0 (Y-MIN) F!
FVARIABLE (Y-MAX)   1e0 (Y-MAX) F!

\ NUMBER ERROR unless lo < hi and hi - lo is a finite number.
: (CHECK-RANGE) { F: lo F: hi -- }
   hi lo F-  FDUP 0e0 F> 0= IF FDROP -24 THROW THEN
   FDUP F-  0e0 F= 0= IF -24 THROW THEN ;

: X-RANGE { F: lo F: hi -- }   lo hi (CHECK-RANGE)  lo (X-MIN) F!  hi (X-MAX) F! ;
: Y-RANGE { F: lo F: hi -- }   lo hi (CHECK-RANGE)  lo (Y-MIN) F!  hi (Y-MAX) F! ;

\ Whether a float is a number (not NaN).
: (NUMBER?) ( F: r -- ) ( -- flag )   FDUP F= ;

2305843009213693952 S>F FCONSTANT (F-LIMIT)

\ A pixel coordinate, rounded to the nearest pixel and limited to -2^61 .. 2^61 (0 for
\ NaN).
: (F>PIXEL) ( F: r -- ) ( -- n )
   FDUP (NUMBER?) 0= IF FDROP 0 EXIT THEN
   FROUND  (F-LIMIT) FMIN  (F-LIMIT) FNEGATE FMAX  F>S ;

\ The column of x and the row of y: X-RANGE goes from column 0 to the last column, and
\ Y-RANGE from the last row up to row 0.
: (M>PX) ( F: x -- ) ( -- px )
   (X-MIN) F@ F-  (X-MAX) F@ (X-MIN) F@ F- F/  GFX-WIDTH 1- S>F F*  (F>PIXEL) ;
: (M>PY) ( F: y -- ) ( -- py )
   (Y-MAX) F@ FSWAP F-  (Y-MAX) F@ (Y-MIN) F@ F- F/  GFX-HEIGHT 1- S>F F*  (F>PIXEL) ;

\ The x of a column (the x of column 0 in an image one pixel wide).
\ The share of the width comes first, so that px times the range cannot overflow.
: (PX>M) ( px -- ) ( F: -- x )
   S>F  GFX-WIDTH 1- 1 MAX S>F F/  (X-MAX) F@ (X-MIN) F@ F- F*  (X-MIN) F@ F+ ;

\ ---- Drawing in mathematical coordinates ------------------------------------------

: MPSET { F: x F: y -- }
   (NEED-IMAGE)
   x (NUMBER?) y (NUMBER?) AND 0= IF EXIT THEN
   x (M>PX) y (M>PY) PSET ;

: MLINE { F: x1 F: y1 F: x2 F: y2 -- }
   (NEED-IMAGE)
   x1 (NUMBER?) y1 (NUMBER?) AND x2 (NUMBER?) AND y2 (NUMBER?) AND 0= IF EXIT THEN
   x1 (M>PX) y1 (M>PY) x2 (M>PX) y2 (M>PY) LINE ;

\ The axes x = 0 and y = 0, across the whole image; an axis outside the range is not
\ drawn.
: AXES ( -- )
   (NEED-IMAGE)
   (Y-MIN) F@ 0e0 F<=  0e0 (Y-MAX) F@ F<= AND IF
      0e0 (M>PY) >R  0 R@ GFX-WIDTH 1- R> LINE
   THEN
   (X-MIN) F@ 0e0 F<=  0e0 (X-MAX) F@ F<= AND IF
      0e0 (M>PX) >R  R@ 0 R> GFX-HEIGHT 1- LINE
   THEN ;

\ The graph of the function xt ( F: x -- y ): its y at the x of every column, with
\ lines between neighboring columns. Where y is not a number (NaN) the graph has a gap.
: PLOT { xt | py valid ny -- }
   (NEED-IMAGE)
   FALSE TO valid
   GFX-WIDTH 0 DO
      I (PX>M) xt EXECUTE
      FDUP (NUMBER?) IF
         (M>PY) TO ny
         valid IF I 1- py I ny LINE ELSE I ny PSET THEN
         ny TO py  TRUE TO valid
      ELSE
         FDROP FALSE TO valid
      THEN
   LOOP ;
