\ The bouncing ball demonstration of the Amiga: a red and white checkered ball turns
\ and bounces in front of a purple grid on gray, and throws a shadow on the grid.
\ It needs a build with graphics and floating-point numbers.
\
\   sigma.exe examples/boing.fs      (in a window; Tk on Linux/macOS)
\
\ Keys: Space stops the ball and lets it go again, Q or Esc ends the demonstration.
\ On Windows the keys go to the console Sigma runs in, as INKEY reads them there.
\
\ As on the Amiga, the ball is drawn once and turns by its colors alone. The picture
\ of the ball holds color numbers: every checker is cut into SUB stripes along its
\ longitude, and each stripe has its own number. A frame gives red to half of the
\ numbers and white to the other half, one number further than the frame before, so
\ the checkers move around the ball although no pixel of the picture changes.
\ The ball booms off the floor and the walls, when the build has the audio words.

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
VARIABLE WAVE-SEED  VARIABLE LOW
: HISS ( -- n )   \ -100 .. 99
   WAVE-SEED @ 1103515245 * 12345 + DUP WAVE-SEED !  16 RSHIFT 200 MOD 100 - ;
\ A boom: n samples of noise through a low-pass filter (a larger k is duller), n/gain
\ times as loud, fading out.
: BOOM { n k gain -- }
   0 LOW !
   n 0 ?DO
      HISS 16 * LOW @ - k / LOW +!
      LOW @ gain *  n I - *  n /  16 /  -127 MAX 127 MIN  WAVE I + C!
   LOOP ;
\ The first n samples of the wave as sample k.
: KEEP ( n k -- )   >R WAVE SWAP WAVE-RATE R> SAMPLE ;
: EFFECT ( k -- )   SFX ;
: MAKE-SOUNDS ( -- )
   3200 24 14 BOOM  3200 S-FLOOR KEEP        \ a deep boom from the floor
   2400 12 8 BOOM  2400 S-WALL KEEP ;        \ a shorter, brighter one from a wall
PREVIOUS
[ELSE]
: EFFECT ( k -- )   DROP ;
: MAKE-SOUNDS ( -- ) ;
[THEN]

\ ---- Sizes --------------------------------------------------------------------------

320 CONSTANT W          \ the size of the image, as the Amiga showed it
200 CONSTANT H
3 CONSTANT ZOOM         \ the window shows a pixel as ZOOM by ZOOM

$AAAAAA CONSTANT GRAY   $AA00AA CONSTANT PURPLE
$FF0000 CONSTANT RED    $FFFFFF CONSTANT WHITE
$FF00FF CONSTANT KEY-COLOR              \ not copied from the picture of the shadow

\ The grid: 15 by 12 squares on the wall, and a floor below that comes toward the eye.
40 CONSTANT GRID-X      8 CONSTANT GRID-Y
16 CONSTANT CELL-W      12 CONSTANT CELL-H
15 CONSTANT COLUMNS     12 CONSTANT ROWS
GRID-X COLUMNS CELL-W * + CONSTANT GRID-RIGHT
GRID-Y ROWS CELL-H * + CONSTANT GRID-BOTTOM
192 CONSTANT FLOOR-Y    \ the near edge of the floor
24 CONSTANT SPREAD      \ how far the near edge reaches beyond the wall on each side

\ The ball.
44 CONSTANT RADIUS
RADIUS 2* 1+ CONSTANT BALL-SIZE         \ the side of its picture
12 CONSTANT SUB         \ the stripes in a checker
SUB 2* CONSTANT PERIOD  \ the stripes in a red checker and the white one beside it
PI 8e0 F/ FCONSTANT SECTOR              \ a checker: 8 from pole to pole, 16 around
0.3e0 FCONSTANT TILT    \ the axis leans to the right by this angle

\ The movement, in 1/1024 pixel. The ball leaves the floor always with the same speed,
\ so that it bounces for ever.
1024 CONSTANT ONE
70 ONE * CONSTANT X-MIN         \ the middle of the ball at the left and right walls
246 ONE * CONSTANT X-MAX
142 ONE * CONSTANT GROUND       \ and on the floor
1250 CONSTANT X-SPEED
76 CONSTANT GRAVITY
3648 CONSTANT JUMP              \ 86 pixels high, 96 frames from floor to floor
26 CONSTANT SHADOW-DX   4 CONSTANT SHADOW-DY
100 CONSTANT SHADOW-ALPHA

VARIABLE BX  VARIABLE BY  VARIABLE VX  VARIABLE VY
VARIABLE PHASE          \ how far the colors have turned, 0 .. PERIOD-1
VARIABLE SPIN           \ 1 or -1: the way the ball turns, changed by a wall
VARIABLE STOPPED  VARIABLE FINISHED
VARIABLE BACKDROP  VARIABLE SHADOW      \ images

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
      I PHASE @ + PERIOD MOD  SUB < IF RED ELSE WHITE THEN  I 1+ COLORS PALETTE!
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
   GRID-BOTTOM 5 + FLOOR-LINE  GRID-BOTTOM 14 + FLOOR-LINE  FLOOR-Y FLOOR-LINE
   SCREEN DRAW-TO ;

: MAKE-SHADOW ( -- )
   BALL-SIZE BALL-SIZE NEW-IMAGE DUP SHADOW !  DRAW-TO
   KEY-COLOR GFX-CLS  0 COLOR!  RADIUS RADIUS RADIUS FILL-CIRCLE
   SCREEN DRAW-TO ;

\ ---- The movement -------------------------------------------------------------------

: START ( -- )
   X-MIN BX !  GROUND JUMP JUMP * GRAVITY 2* / - BY !  X-SPEED VX !  0 VY !
   0 PHASE !  1 SPIN !  FALSE STOPPED !  FALSE FINISHED ! ;

: HIT-WALL ( x -- )   BX !  VX @ NEGATE VX !  SPIN @ NEGATE SPIN !  S-WALL EFFECT ;

: MOVE-BALL ( -- )
   VX @ BX +!
   BX @ X-MAX > IF  X-MAX HIT-WALL  THEN
   BX @ X-MIN < IF  X-MIN HIT-WALL  THEN
   VY @ BY +!  GRAVITY VY +!
   BY @ GROUND >= IF  GROUND BY !  JUMP NEGATE VY !  S-FLOOR EFFECT  THEN
   PHASE @ SPIN @ + PERIOD + PERIOD MOD PHASE ! ;

\ ---- The frame ----------------------------------------------------------------------

: CORNER ( -- x y )   \ the top left of the picture of the ball
   BX @ ONE / RADIUS -  BY @ ONE / RADIUS - ;

: DRAW ( -- )
   BACKDROP @ 0 0 PUT-IMAGE
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
   W H GFX-INIT  W ZOOM * H ZOOM * WINDOW-SIZE
   MAKE-BACKDROP MAKE-SHADOW MAKE-BALL MAKE-SOUNDS START ;

: BOING ( -- )
   PREPARE
   CR ." Space stops the ball and lets it go again; Q or Esc ends." CR
   BEGIN  KEYS  STOPPED @ 0= IF MOVE-BALL THEN  DRAW  16 FRAME  FINISHED @ UNTIL ;

BOING BYE
