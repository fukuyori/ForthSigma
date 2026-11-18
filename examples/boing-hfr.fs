\ High-resolution, high-frame-rate Boing: 1920 x 1200, targeting 120 frames/s.
\ Build for speed, then run:
\   zig build -Doptimize=ReleaseFast
\   zig-out/bin/sigma examples/boing-hfr.fs
\ Space pauses/resumes; Q or Esc quits. Graphics and floating-point are required;
\ audio is optional. Prefer the native window; Tk and terminals may be slower.
\ Actual presentation depends on the display/backend. SHOW is asynchronous, so
\ 120 loop iterations/s do not prove 120 distinct frames reached the monitor.
\ The image starts in a 1280 x 800 window; resize/maximize it for your display.
\ Change DETAIL to 4 for 1280 x 800 rendering, or TARGET-FPS to 60 for less work.
\ DETAIL must be 1..10 to fit the indexed palette; this demo uses 64-bit cells.
\ Movement follows elapsed time, with a 100 ms cap after stalls. Only the old
\ ball/shadow rectangle is restored, leaving the static background untouched.

REQUIRE-GAME  ALSO GRAPHICS ALSO GAME

\ ---- Sound effects ----------------------------------------------------------------
\ Made with SAMPLE and played with SFX when the build has the audio words; a build
\ without them (-Daudio=false) shows the ball silently.

: AUDIO-LOADED? ( -- flag )   S" REQUIRE-AUDIO" ['] EVALUATE CATCH  DUP IF NIP NIP THEN  0= ;
AUDIO-LOADED? CONSTANT HAS-SOUND

0 CONSTANT S-FLOOR  1 CONSTANT S-WALL

HAS-SOUND [IF]
ALSO AUDIO
8000 CONSTANT WAVE-RATE
CREATE WAVE WAVE-RATE ALLOT             \ room for a second of sound
FVARIABLE WAVE-PHASE
VARIABLE IMPACT-SEED
\ A rubber-ball impact: a brief contact sound and damped body resonances.
\ Pitch settles during the first 16 ms, rather than sweeping throughout the note.
: CONTACT ( -- ) ( F: -- noise )
   IMPACT-SEED @ 1103515245 * 12345 + $7FFFFFFF AND DUP IMPACT-SEED !
   16 RSHIFT 255 AND 128 - S>F 128e0 F/ ;
: POP { n high low -- }
   0e0 WAVE-PHASE F!  1 IMPACT-SEED !
   n 0 ?DO
      WAVE-PHASE F@ FSIN
      WAVE-PHASE F@ 1.47e0 F* FSIN 0.28e0 F* F+
      WAVE-PHASE F@ 2.1e0 F* FSIN 0.12e0 F* F+
      CONTACT 48 I - 0 MAX S>F 48e0 F/ FDUP F* F* 0.20e0 F* F+
      n I - S>F n S>F F/ FDUP F* FDUP F* F*
      I 8 MIN S>F 8e0 F/ F* 74e0 F* F>S  WAVE I + C!
      high low - 128 I - 0 MAX * 128 / low + S>F
      PI 2e0 F* F* WAVE-RATE S>F F/  WAVE-PHASE F@ F+ WAVE-PHASE F!
   LOOP ;
\ The first n samples of the wave as sample k.
: KEEP ( n k -- )   >R WAVE SWAP WAVE-RATE R> SAMPLE ;
: EFFECT ( k -- )   SFX ;
: MAKE-SOUNDS ( -- )
   1600 150 100 POP  1600 S-FLOOR KEEP        \ a low floor impact, 200 ms
   1120 210 150 POP  1120 S-WALL KEEP ;        \ a tighter wall impact, 140 ms
PREVIOUS
[ELSE]
: EFFECT ( k -- )   DROP ;
: MAKE-SOUNDS ( -- ) ;
[THEN]

\ ---- Sizes --------------------------------------------------------------------------

6 CONSTANT DETAIL      \ pixels per pixel of the original composition
320 DETAIL * CONSTANT W
200 DETAIL * CONSTANT H
120 CONSTANT TARGET-FPS
1000000 TARGET-FPS / CONSTANT FRAME-US

$AAAAAA CONSTANT GRAY   $AA00AA CONSTANT PURPLE
$FF0000 CONSTANT RED    $FFFFFF CONSTANT WHITE
$FF00FF CONSTANT KEY-COLOR              \ not copied from the picture of the shadow

\ The grid: 15 by 12 squares on the wall, and a floor below that comes toward the eye.
40 DETAIL * CONSTANT GRID-X      8 DETAIL * CONSTANT GRID-Y
16 DETAIL * CONSTANT CELL-W      12 DETAIL * CONSTANT CELL-H
15 CONSTANT COLUMNS     12 CONSTANT ROWS
6 CONSTANT FLOOR-ROWS   \ floor rows get deeper toward the viewer
GRID-X COLUMNS CELL-W * + CONSTANT GRID-RIGHT
GRID-Y ROWS CELL-H * + CONSTANT GRID-BOTTOM
192 DETAIL * CONSTANT FLOOR-Y    \ the near edge of the floor
24 DETAIL * CONSTANT SPREAD      \ how far the near edge reaches beyond the wall on each side

\ The ball.
44 DETAIL * CONSTANT RADIUS
RADIUS 2* 1+ CONSTANT BALL-SIZE         \ the side of its picture
12 DETAIL * CONSTANT SUB         \ the stripes in a checker
SUB 2* CONSTANT PERIOD  \ the stripes in a red checker and the white one beside it
PI 8e0 F/ FCONSTANT SECTOR              \ a checker: 8 from pole to pole, 16 around
0.3e0 FCONSTANT TILT    \ the axis leans to the right by this angle

\ Positions use 1/1024 pixel; velocity and gravity are per second. The ball leaves
\ the floor always with the same speed,
\ so that it bounces for ever.
1024 CONSTANT ONE
70 DETAIL * ONE * CONSTANT X-MIN         \ the middle of the ball at the left and right walls
246 DETAIL * ONE * CONSTANT X-MAX
142 DETAIL * ONE * CONSTANT GROUND       \ and on the floor
1250 DETAIL * 1000000 16000 */ CONSTANT X-SPEED
76 DETAIL * 1000000 16000 */ 1000000 16000 */ CONSTANT GRAVITY
3648 DETAIL * 1000000 16000 */ CONSTANT JUMP              \ same bounce height and timing relative to the original scene
26 DETAIL * CONSTANT SHADOW-DX   4 DETAIL * CONSTANT SHADOW-DY
100 CONSTANT SHADOW-ALPHA

VARIABLE BX  VARIABLE BY  VARIABLE VX  VARIABLE VY
VARIABLE PHASE          \ stripe position in units of 1/16000 stripe
VARIABLE SPIN           \ DETAIL or -DETAIL: the way the ball turns, changed by a wall
VARIABLE STOPPED  VARIABLE FINISHED
VARIABLE BACKDROP  VARIABLE SHADOW      \ images
VARIABLE LAST-X  VARIABLE LAST-Y
VARIABLE LAST-TIME  VARIABLE NEXT-FRAME

BALL-SIZE BALL-SIZE INDEXED: BALL
PALETTE: COLORS

\ ---- The picture of the ball --------------------------------------------------------

FVARIABLE ACROSS  FVARIABLE ALONG  FVARIABLE AWAY
: UNIT ( F: x -- x' )   -1e0 FMAX 1e0 FMIN ;
: HALF-TURN+ ( F: angle -- angle' )   PI 2e0 F/ F+ ;      \ -π/2 .. π/2 to 0 .. π

\ The color number of the pixel dx dy from the middle of the ball: 0 outside the ball.
\ The point of the sphere there is turned back by the tilt; its latitude gives the row
\ of checkers and its longitude the stripe.
: BALL-INDEX { dx dy -- n }
   dx dx * dy dy * +  RADIUS RADIUS * RADIUS +  > IF  0 EXIT  THEN
   dx S>F TILT FCOS F*  dy S>F TILT FSIN F*  F+  ACROSS F!
   dx S>F TILT FSIN F*  dy S>F TILT FCOS F*  F-  ALONG F!
   RADIUS RADIUS *  dx dx * -  dy dy * -  0 MAX  S>F FSQRT  AWAY F!
   ALONG F@ RADIUS S>F F/ UNIT FASIN  HALF-TURN+ SECTOR F/  FLOOR F>S  0 MAX 7 MIN
   ACROSS F@ AWAY F@ FATAN2  HALF-TURN+ SECTOR F/  SUB S>F F*  FLOOR F>S  0 MAX
   SWAP SUB * +  PERIOD MOD 1+ ;

: MAKE-BALL ( -- )
   BALL-SIZE 0 ?DO  BALL-SIZE 0 ?DO
      I RADIUS - J RADIUS - BALL-INDEX  I J BALL INDEX!
   LOOP LOOP ;

\ Red for half of the numbers and white for the others, from where PHASE is.
: SET-COLORS ( -- )
   PERIOD 0 ?DO
      I PHASE @ 16000 / + PERIOD MOD  SUB < IF RED ELSE WHITE THEN  I 1+ COLORS PALETTE!
   LOOP ;

\ ---- The grid and the shadow --------------------------------------------------------

\ The floor at the height y (GRID-BOTTOM .. FLOOR-Y) is wider than the wall by this
\ much on each side.
: WIDER ( y -- n )   GRID-BOTTOM - SPREAD *  FLOOR-Y GRID-BOTTOM - / ;
: FLOOR-LINE ( y -- )   DUP WIDER { y n }  GRID-X n - y  GRID-RIGHT n + y  LINE ;

: MAKE-BACKDROP ( -- )
   W H NEW-IMAGE DUP BACKDROP !  DRAW-TO
   GRAY GFX-CLS  PURPLE COLOR!
   COLUMNS 1+ 0 DO
      GRID-X I CELL-W * +  DUP GRID-Y OVER GRID-BOTTOM LINE         \ on the wall
      GRID-BOTTOM                                                    \ and on the floor
      GRID-X SPREAD -  I  GRID-RIGHT GRID-X - SPREAD 2* +  *  COLUMNS /  +  FLOOR-Y  LINE
   LOOP
   ROWS 1+ 0 DO  GRID-X  GRID-Y I CELL-H * +  GRID-RIGHT OVER LINE  LOOP
   \ Six floor rows: close together at the wall, wider toward the near edge.
   FLOOR-ROWS 1+ 1 DO
      GRID-BOTTOM  FLOOR-Y GRID-BOTTOM -  I I 3 + * *
      FLOOR-ROWS FLOOR-ROWS 3 + * / + FLOOR-LINE
   LOOP
   SCREEN DRAW-TO ;

: MAKE-SHADOW ( -- )
   BALL-SIZE BALL-SIZE NEW-IMAGE DUP SHADOW !  DRAW-TO
   KEY-COLOR GFX-CLS  0 COLOR!  RADIUS RADIUS RADIUS FILL-CIRCLE
   SCREEN DRAW-TO ;

\ ---- The movement -------------------------------------------------------------------

: START ( -- )
   X-MIN BX !  GROUND JUMP JUMP * GRAVITY 2* / - BY !  X-SPEED VX !  0 VY !
   0 PHASE !  DETAIL SPIN !  FALSE STOPPED !  FALSE FINISHED ! ;

: HIT-WALL ( x -- )   BX !  VX @ NEGATE VX !  SPIN @ NEGATE SPIN !  S-WALL EFFECT ;

: MOVE-STEP { us -- }
   VX @ us 1000000 */ BX +!
   BX @ X-MAX > IF  X-MAX HIT-WALL  THEN
   BX @ X-MIN < IF  X-MIN HIT-WALL  THEN
   \ Include half the acceleration in displacement for stable bounce height.
   VY @ us 1000000 */
   GRAVITY us 1000000 */ us 2000000 */ + BY +!
   GRAVITY us 1000000 */ VY +!
   BY @ GROUND >= IF  GROUND BY !  JUMP NEGATE VY !  S-FLOOR EFFECT  THEN
   PHASE @ SPIN @ us * + PERIOD 16000 * + PERIOD 16000 * MOD PHASE ! ;

: MOVE-BALL { us -- }
   \ At most 8 ms per physics step, including after a slow frame.
   BEGIN us 0> WHILE
      us 8000 MIN DUP MOVE-STEP  us SWAP - TO us
   REPEAT ;

\ ---- The frame ----------------------------------------------------------------------

: CORNER ( -- x y )   \ the top left of the picture of the ball
   BX @ ONE / RADIUS -  BY @ ONE / RADIUS - ;

: DRAW ( -- )
   BACKDROP @ LAST-X @ LAST-Y @
   BALL-SIZE SHADOW-DX + BALL-SIZE SHADOW-DY +
   LAST-X @ LAST-Y @ COPY-RECT
   CORNER LAST-Y ! LAST-X !
   KEY-COLOR TRANSPARENT  3 IMAGE-MODE  SHADOW-ALPHA IMAGE-ALPHA
   SHADOW @  CORNER SWAP SHADOW-DX + SWAP SHADOW-DY +  PUT-IMAGE
   0 IMAGE-MODE  -1 TRANSPARENT
   SET-COLORS  CORNER BALL COLORS 0 DRAW-INDEXED ;

: KEY! ( key -- )
   CASE
      BL       OF  STOPPED @ 0= STOPPED !  ENDOF
      [CHAR] q OF  TRUE FINISHED !  ENDOF
      [CHAR] Q OF  TRUE FINISHED !  ENDOF
      27       OF  TRUE FINISHED !  ENDOF
   ENDCASE ;
: KEYS ( -- )   BEGIN INKEY DUP -1 <> WHILE KEY! REPEAT DROP ;

: PREPARE ( -- )
   W H GFX-INIT  1280 800 WINDOW-SIZE
   MAKE-BACKDROP MAKE-SHADOW MAKE-BALL MAKE-SOUNDS START
   BACKDROP @ 0 0 PUT-IMAGE  CORNER LAST-Y ! LAST-X ! ;

: PRESENT { | now -- }
   \ Keep the deadline, but never sleep longer than one frame after a clock jump.
   UTIME DROP TO now
   NEXT-FRAME @ FRAME-US + now - 0 MAX FRAME-US MIN
   DUP now + NEXT-FRAME ! 999 + 1000 / MS  SHOW ;

: ADVANCE-BALL ( -- )
   UTIME DROP DUP LAST-TIME @ - 0 MAX 100000 MIN
   SWAP LAST-TIME !
   STOPPED @ IF DROP ELSE MOVE-BALL THEN ;

: BOING-HFR ( -- )
   PREPARE
   CR ." Resolution: " W . H . ." Target fps: " TARGET-FPS .
   ." Space pauses; Q or Esc quits." CR
   UTIME DROP DUP LAST-TIME ! NEXT-FRAME !
   BEGIN KEYS ADVANCE-BALL DRAW PRESENT FINISHED @ UNTIL ;

BOING-HFR BYE
