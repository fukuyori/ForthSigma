\ A test of the graphics mode: a ball game for one player. The ball bounces off the
\ walls at the top, the bottom, and the right; the player moves the paddle on the left
\ with the Up and Down keys and sends the ball back. A ball the paddle misses hits the
\ left side: that is out, and the game starts again.
\
\   sigma.exe examples/paddle.fs      (in a window; Tk on Linux/macOS)
\
\ Keys: Up and Down move the paddle, A lets the paddle play by itself (and stops it),
\ Q or Esc ends the game. On Windows the keys go to the console Sigma runs in, as
\ INKEY reads them there; on a terminal the picture is drawn with half blocks.
\ The ball clicks off the walls and the paddle, and a ball that is out falls away in
\ sound, when the build has the audio words.

REQUIRE-GRAPHICS  ALSO GRAPHICS

\ ---- Sound effects ----------------------------------------------------------------
\ Made with SAMPLE and played with SFX when the build has the audio words; a build
\ without them (-Daudio=false) plays the game silently.

: AUDIO-LOADED? ( -- flag )   S" REQUIRE-AUDIO" ['] EVALUATE CATCH  DUP IF NIP NIP THEN  0= ;
AUDIO-LOADED? CONSTANT HAS-SOUND

HAS-SOUND [IF]
ALSO AUDIO
8000 CONSTANT WAVE-RATE
CREATE WAVE WAVE-RATE ALLOT             \ room for a second of sound
VARIABLE WAVE-COUNT  VARIABLE WAVE-SIGN  VARIABLE WAVE-SEED
\ A square wave of n samples whose half period starts at p samples and changes by dp
\ every 64 samples (below 0: the pitch rises), fading out.
: SQUARE-SWEEP { n p dp -- }
   0 WAVE-COUNT !  1 WAVE-SIGN !
   n 0 DO
      1 WAVE-COUNT +!
      WAVE-COUNT @  p I 64 / dp * +  2 MAX  >= IF  0 WAVE-COUNT !  WAVE-SIGN @ NEGATE WAVE-SIGN !  THEN
      WAVE-SIGN @ 100 *  n I - *  n /  WAVE I + C!
   LOOP ;
\ Noise of n samples, fading out.
: NOISE-BURST { n -- }
   n 0 DO
      WAVE-SEED @ 1103515245 * 12345 + DUP WAVE-SEED !  16 RSHIFT 200 MOD 100 -
      n I - *  n /  WAVE I + C!
   LOOP ;
\ The first n samples of the wave as sample k.
: KEEP ( n k -- )   >R WAVE SWAP WAVE-RATE R> SAMPLE ;
: EFFECT ( k -- )   SFX ;
: JINGLE ( c-addr u -- )   PLAY ;
PREVIOUS
[ELSE]
: EFFECT ( k -- )   DROP ;
: JINGLE ( c-addr u -- )   2DROP ;
[THEN]

0 CONSTANT S-WALL  1 CONSTANT S-PADDLE  2 CONSTANT S-OUT
HAS-SOUND [IF]
: MAKE-SOUNDS ( -- )
   300 8 0 SQUARE-SWEEP  300 S-WALL KEEP         \ a short low click
   500 4 0 SQUARE-SWEEP  500 S-PADDLE KEEP       \ a higher one
   4000 6 1 SQUARE-SWEEP  4000 S-OUT KEEP ;      \ falling for half a second
[ELSE]
: MAKE-SOUNDS ( -- ) ;
[THEN]

160 CONSTANT W          \ the size of the image
120 CONSTANT H
3 CONSTANT WALL         \ the thickness of the walls
6 CONSTANT PX           \ the paddle: its left side, width, and height
3 CONSTANT PW
22 CONSTANT PH
3 CONSTANT BS           \ the size of the ball
3 CONSTANT STEP         \ how far the paddle moves in a frame while a key is held
40 CONSTANT OUT-FRAMES  \ how long OUT is shown

VARIABLE PY             \ the top of the paddle
VARIABLE BX  VARIABLE BY  VARIABLE DX  VARIABLE DY      \ the ball and its speed
VARIABLE HITS  VARIABLE BEST  VARIABLE OUTS
VARIABLE PAUSE          \ frames left showing OUT, 0 while the ball is in play
VARIABLE AUTO           \ true while the paddle plays by itself
VARIABLE DONE

\ ---- Numbers -----------------------------------------------------------------------

VARIABLE SEED
: RANDOM ( n -- 0..n-1 )   SEED @ 6364136223846793005 * 1442695040888963407 +  DUP SEED !  33 RSHIFT  SWAP MOD ;
: CLAMP ( n lo hi -- n' )   ROT MIN MAX ;
: N>S ( n -- c-addr u )   S>D <# #S #> ;

\ ---- The game ----------------------------------------------------------------------

: SERVE ( -- )   \ the ball from the middle, toward the right wall
   0 HITS !  0 PAUSE !
   W 2/ BX !  20 H 40 - RANDOM + BY !
   2 DX !  2 RANDOM IF 1 ELSE -1 THEN  2 RANDOM 1+ *  DY ! ;

: NEW-GAME ( -- )
   UTIME DROP SEED !  0 BEST !  0 OUTS !  FALSE AUTO !  FALSE DONE !
   H PH - 2/ PY !  SERVE ;

: MOVE-PADDLE ( n -- )   PY @ + WALL H WALL - PH - CLAMP PY ! ;

: KEY! ( key -- )
   CASE
      [CHAR] a OF  AUTO @ 0= AUTO !  ENDOF
      [CHAR] A OF  AUTO @ 0= AUTO !  ENDOF
      [CHAR] q OF  TRUE DONE !  ENDOF
      [CHAR] Q OF  TRUE DONE !  ENDOF
      27       OF  TRUE DONE !  ENDOF
   ENDCASE ;

\ The paddle moves while Up or Down is held (KEY-HELD?), not by the keys INKEY gives,
\ which come only as fast as the keyboard repeats a key held down.
: KEYS ( -- )
   BEGIN INKEY DUP -1 <> WHILE KEY! REPEAT DROP
   K-UP KEY-HELD? IF  STEP NEGATE MOVE-PADDLE  THEN
   K-DOWN KEY-HELD? IF  STEP MOVE-PADDLE  THEN ;

\ The paddle playing by itself follows the ball, at most 3 pixels a frame.
: FOLLOW ( -- )   BY @ BS 2/ + PY @ PH 2/ + - -3 3 CLAMP MOVE-PADDLE ;

: BOUNCE-WALLS ( -- )
   BY @ WALL < IF  WALL BY !  DY @ ABS DY !  S-WALL EFFECT  THEN
   BY @ BS + H WALL - > IF  H WALL - BS - BY !  DY @ ABS NEGATE DY !  S-WALL EFFECT  THEN
   BX @ BS + W WALL - > IF  W WALL - BS - BX !  DX @ ABS NEGATE DX !  S-WALL EFFECT  THEN ;

\ Where the ball meets the paddle sets its new slope: near an end it goes off steeply.
: HIT ( -- )
   PX PW + BX !  DX @ ABS DX !  S-PADDLE EFFECT
   BY @ BS 2/ +  PY @ PH 2/ +  -  4 /  -2 2 CLAMP
   DUP 0= IF DROP DY @ 0< IF -1 ELSE 1 THEN THEN  DY !
   1 HITS +!  HITS @ BEST @ MAX BEST !
   HITS @ 4 MOD 0= IF  DX @ 1+ 4 MIN DX !  THEN ;   \ faster every 4 hits

: MEETS-PADDLE? ( old-x -- flag )   \ the ball crossed the paddle's face, beside it
   PX PW + >=  BX @ PX PW + < AND
   BY @ BS + PY @ >  AND  BY @ PY @ PH + <  AND ;

: MOVE-BALL ( -- )
   BX @  DX @ BX +!  DY @ BY +!
   BOUNCE-WALLS
   DX @ 0< IF  MEETS-PADDLE? IF HIT THEN  ELSE DROP THEN
   BX @ BS + 0< IF  1 OUTS +!  OUT-FRAMES PAUSE !  S-OUT EFFECT  THEN ;

: UPDATE ( -- )
   AUTO @ IF FOLLOW THEN
   PAUSE @ IF  -1 PAUSE +!  PAUSE @ 0= IF SERVE THEN  ELSE MOVE-BALL THEN ;

\ ---- The picture -------------------------------------------------------------------

: CENTERED ( c-addr u y -- )   >R 2DUP TEXT-WIDTH W SWAP - 2/ R> TEXT ;

: DRAW ( -- )
   CLS
   160 160 160 COLOR
   0 0 W WALL FILL-RECT  0 H WALL - W WALL FILL-RECT  W WALL - 0 WALL H FILL-RECT
   \ the scores: misses on the left, hits on the right, and the best below
   1 TEXT-SCALE  120 120 120 COLOR
   S" OUT" 36 6 TEXT  S" HIT" 108 6 TEXT
   S" BEST " 60 H 14 - TEXT  BEST @ N>S 84 H 14 - TEXT
   AUTO @ IF  S" AUTO" W 26 - H 14 - TEXT  THEN
   3 TEXT-SCALE  220 220 220 COLOR
   OUTS @ N>S 30 16 TEXT  HITS @ N>S 102 16 TEXT
   255 255 255 COLOR
   PX PY @ PW PH FILL-RECT
   PAUSE @ IF
      2 TEXT-SCALE  255 80 80 COLOR  S" OUT" 50 CENTERED
   ELSE  255 255 0 COLOR  BX @ BY @ BS BS FILL-RECT  THEN ;

: GAME-STEP ( -- )   KEYS UPDATE DRAW ;

: PADDLE-GAME ( -- )
   W H GFX-INIT  W 4 * H 4 * WINDOW-SIZE  NEW-GAME     \ shown four times as large
   MAKE-SOUNDS
   BEGIN  GAME-STEP  20 FRAME  DONE @ UNTIL
   1 TEXT-SCALE
   CR ." Best: " BEST @ .  ." Out: " OUTS @ . CR ;

PADDLE-GAME
