\ Headless turtle acceptance tests (task 1476).
\ Run: zig-out/bin/sigma.exe emu/logo/test-turtle.fs
\ Expected pixels below are hand-calculated; no reference renderer is used.
\ No SHOW, FRAME, TURTLE-RUN, or sound is executed.
VOCABULARY TTEST-CALLER
ALSO TTEST-CALLER DEFINITIONS
VARIABLE TTEST-CURRENT ( -- addr )
GET-CURRENT TTEST-CURRENT !
GET-ORDER CONSTANT TTEST-ORDER-N ( -- n )
CREATE TTEST-ORDER 256 CELLS ALLOT ( -- addr )
: TTEST-STORE ( wid... -- )
   TTEST-ORDER-N 0 DO TTEST-ORDER I CELLS + ! LOOP
;
TTEST-STORE
HEX
INCLUDE emu/logo/turtle.fs
BASE @ 10 = CONSTANT TTEST-BASE-OK ( -- flag )
GET-CURRENT TTEST-CURRENT @ = CONSTANT TTEST-CURRENT-OK ( -- flag )
DECIMAL
CREATE TTEST-AFTER-ORDER 256 CELLS ALLOT ( -- addr )
GET-ORDER CONSTANT TTEST-AFTER-N ( -- n )
: TTEST-STORE-AFTER ( wid... -- )
   TTEST-AFTER-N 0 DO TTEST-AFTER-ORDER I CELLS + ! LOOP
;
TTEST-STORE-AFTER
ALSO GRAPHICS ALSO TURTLE
VARIABLE TTEST-PASSED ( -- addr )
VARIABLE TTEST-FAILED ( -- addr )
VARIABLE TTEST-LABEL ( -- addr )
VARIABLE TTEST-LEN ( -- addr )
CREATE TTEST-PIXELS 4096 CELLS ALLOT ( -- addr )
: TTEST-CHECK { actual expected addr len -- }
   actual expected = IF 1 TTEST-PASSED +! ELSE
      1 TTEST-FAILED +!
      ." FAIL " addr len TYPE ."  expected " expected . ." actual " actual . CR
   THEN
;
: TTEST-FLOAT { addr len F: actual F: expected -- }
   actual expected F- FABS 0.000000001e F<= IF 1 TTEST-PASSED +! ELSE
      1 TTEST-FAILED +!
      ." FAIL " addr len TYPE ."  expected " expected F. ." actual " actual F. CR
   THEN
;
: TTEST-NAME ( addr len -- ) TTEST-LEN ! TTEST-LABEL ! ;
: TTEST-RESET-EXPECTED ( -- ) TTEST-PIXELS 4096 CELLS ERASE ;
: TTEST-NEW ( w h -- )
   TURTLE-DISPOSE TURTLE-INIT TTEST-RESET-EXPECTED
;
: TTEST-AT { x y color -- }
   color TTEST-PIXELS y TT@W @ * x + CELLS + !
;
: TTEST-WHITE ( x y -- ) $FFFFFF TTEST-AT ;
: TTEST-RECT { x y w h color -- }
   h 0 DO w 0 DO x I + y J + color TTEST-AT LOOP LOOP
;
: TTEST-ROW { addr len row -- }
   len 0 DO addr I + C@ [CHAR] # = IF I row TTEST-WHITE THEN LOOP
;
: TTEST-PIX ( -- )
   TT@H @ 0 DO TT@W @ 0 DO
      TURTLE-IMAGE I J GFX-PIXEL
      TTEST-PIXELS J TT@W @ * I + CELLS + @
      2DUP <> IF ." pixel (" I . J . ." ) " THEN
      TTEST-LABEL @ TTEST-LEN @ TTEST-CHECK
   LOOP LOOP
;
: TTEST-STATE ( -- )
   TT@X F@ 0e S" initial x" TTEST-FLOAT
   TT@Y F@ 0e S" initial y" TTEST-FLOAT
   TT@HEADING F@ 0e S" initial heading" TTEST-FLOAT
   TT@PEN @ TRUE S" initial pen" TTEST-CHECK
   TT@COLOR @ $FFFFFF S" initial color" TTEST-CHECK
   TT@BG @ 0 S" initial background" TTEST-CHECK
   TT@SIZE @ 1 S" initial width" TTEST-CHECK
   TT@VISIBLE @ TRUE S" initial visible" TTEST-CHECK
   TT@MODE @ 0 S" initial wrap" TTEST-CHECK
   TT@SPEED @ 10 S" initial speed" TTEST-CHECK
;

\ ---- Environment, defaults, movements, aliases ----
: TTEST-BASICS ( -- )
   TTEST-BASE-OK TRUE S" load restores hexadecimal BASE" TTEST-CHECK
   TTEST-CURRENT-OK TRUE S" load restores current wordlist" TTEST-CHECK
   TTEST-AFTER-N TTEST-ORDER-N S" load restores order length" TTEST-CHECK
   TTEST-ORDER-N TTEST-AFTER-N MIN 0 DO
      TTEST-AFTER-ORDER I CELLS + @ TTEST-ORDER I CELLS + @
      S" load restores each wordlist in order" TTEST-CHECK
   LOOP
   640 480 TTEST-NEW TTEST-STATE
   TURTLE-IMAGE IMAGE-SIZE 480 S" default height" TTEST-CHECK
   640 S" default width" TTEST-CHECK
   9 9 TTEST-NEW
   2e FORWARD 90e RIGHT 2e FD
   4 4 TTEST-WHITE 4 3 TTEST-WHITE 4 2 TTEST-WHITE
   5 2 TTEST-WHITE 6 2 TTEST-WHITE
   S" chapter 10 five pixels" TTEST-NAME TTEST-PIX
   TURTLE-PAINT
   S" paint preserves every canvas pixel" TTEST-NAME TTEST-PIX
   DRAWING TURTLE-IMAGE S" paint restores target" TTEST-CHECK
   9 9 TTEST-NEW PENUP 2e FORWARD 90e RIGHT -2e BACK
   TT@X F@ 2e S" negative BACK" TTEST-FLOAT
   TT@Y F@ 2e S" forward y" TTEST-FLOAT
   1e BK -1e FD
   TT@X F@ 0e S" backward and negative FD" TTEST-FLOAT
   450e SETHEADING 810e RT 90e LEFT 90e LT
   TT@HEADING F@ 0e S" angle aliases normalization" TTEST-FLOAT
   -450e SETH TT@HEADING F@ 270e S" negative heading" TTEST-FLOAT
   1080e RIGHT TT@HEADING F@ 270e S" multiple turns" TTEST-FLOAT
   S" penup leaves canvas black" TTEST-NAME TTEST-PIX
   PENDOWN 0e FD 4 2 TTEST-WHITE
   S" pendown zero distance dot" TTEST-NAME TTEST-PIX
   HOME TT@HEADING F@ 0e S" home heading" TTEST-FLOAT
   TT@X F@ 0e S" home x" TTEST-FLOAT TT@Y F@ 0e S" home y" TTEST-FLOAT
   4 3 TTEST-WHITE 4 4 TTEST-WHITE S" home draws" TTEST-NAME TTEST-PIX
   8 8 TTEST-NEW 0e 0e SETXY
   4 4 TTEST-WHITE S" even image half ties to even" TTEST-NAME TTEST-PIX
   1e 1e SETXY 5 3 TTEST-WHITE 6 2 TTEST-WHITE
   \ Both 3.5 and 4.5 round to 4: x=1 maps to 4, y=1 maps to 2.
   TTEST-RESET-EXPECTED 4 4 TTEST-WHITE 4 3 TTEST-WHITE 4 2 TTEST-WHITE
   S" even image endpoint ties" TTEST-NAME TTEST-PIX
   2 2 TTEST-NEW 0e FD 0 0 TTEST-WHITE
   S" minimum canvas and half ties" TTEST-NAME TTEST-PIX
   TURTLE-DISPOSE 4096 2 TURTLE-INIT
   TURTLE-IMAGE IMAGE-SIZE 2 S" maximum canvas height companion" TTEST-CHECK
   4096 S" maximum canvas width" TTEST-CHECK
;

\ ---- Clearing preserves settings; resize resets them ----
: TTEST-SETTINGS ( -- )
   9 9 TTEST-NEW WINDOW 4 SETPENCOLOR 3 SETPENSIZE
   25 SETSPEED HIDETURTLE PENUP 1e 2e SETXY 123e SETHEADING
   1 SETBACKGROUND
   TT@BG @ 255 S" background number" TTEST-CHECK
   0 0 9 9 255 TTEST-RECT
   S" background fills canvas" TTEST-NAME TTEST-PIX
   CLEAN
   TT@X F@ 1e S" clean keeps x" TTEST-FLOAT
   TT@Y F@ 2e S" clean keeps y" TTEST-FLOAT
   TT@HEADING F@ 123e S" clean keeps heading" TTEST-FLOAT
   CLEARSCREEN
   TT@X F@ 0e S" clearscreen x" TTEST-FLOAT
   TT@Y F@ 0e S" clearscreen y" TTEST-FLOAT
   TT@HEADING F@ 0e S" clearscreen heading" TTEST-FLOAT
   TT@COLOR @ $FF0000 S" clear keeps color" TTEST-CHECK
   TT@SIZE @ 3 S" clear keeps size" TTEST-CHECK
   TT@PEN @ FALSE S" clear keeps pen" TTEST-CHECK
   TT@VISIBLE @ FALSE S" clear keeps visibility" TTEST-CHECK
   TT@MODE @ 1 S" clear keeps mode" TTEST-CHECK
   TT@SPEED @ 25 S" clear keeps speed" TTEST-CHECK
   S" clean and cs background" TTEST-NAME TTEST-PIX
   SHOWTURTLE TT@VISIBLE @ TRUE S" showturtle" TTEST-CHECK
   HT TT@VISIBLE @ FALSE S" ht" TTEST-CHECK
   ST TT@VISIBLE @ TRUE S" st" TTEST-CHECK
   7 7 SETSCREENSIZE TTEST-RESET-EXPECTED TTEST-STATE
   S" resize black" TTEST-NAME TTEST-PIX
   TURTLE-IMAGE IMAGE-SIZE 7 S" resized height" TTEST-CHECK 7 S" resized width" TTEST-CHECK
;

\ ---- Exact hand masks for edge modes ----
: TTEST-WRAP ( -- )
   9 9 TTEST-NEW 6e 0e SETXY
   S" ##..#####" 4 TTEST-ROW
   S" wrap one edge" TTEST-NAME TTEST-PIX
   TT@X F@ -3e S" wrap x endpoint" TTEST-FLOAT
   9 9 TTEST-NEW 6e 6e SETXY
   4 4 TTEST-WHITE 5 3 TTEST-WHITE 6 2 TTEST-WHITE 7 1 TTEST-WHITE 8 0 TTEST-WHITE
   0 8 TTEST-WHITE 1 7 TTEST-WHITE
   S" wrap simultaneous corner" TTEST-NAME TTEST-PIX
   TT@X F@ -3e S" corner x" TTEST-FLOAT TT@Y F@ -3e S" corner y" TTEST-FLOAT
   9 9 TTEST-NEW 9e 3e SETXY
   4 4 TTEST-WHITE 5 3 TTEST-WHITE 6 3 TTEST-WHITE 7 2 TTEST-WHITE 8 2 TTEST-WHITE
   0 2 TTEST-WHITE 1 2 TTEST-WHITE 2 1 TTEST-WHITE 3 1 TTEST-WHITE 4 1 TTEST-WHITE
   S" wrap unequal boundary fractions" TTEST-NAME TTEST-PIX
   9 9 TTEST-NEW 29e 0e SETXY
   0 4 9 1 $FFFFFF TTEST-RECT
   S" wrap several laps" TTEST-NAME TTEST-PIX
   TT@X F@ 2e S" laps endpoint" TTEST-FLOAT
   9 9 TTEST-NEW PU -4.5e 0e SETXY PD -6e 0e SETXY
   S" .......##" 4 TTEST-ROW
   S" boundary outward negative" TTEST-NAME TTEST-PIX
   TT@X F@ 3e S" boundary endpoint" TTEST-FLOAT
   9 9 TTEST-NEW -6e 0e SETXY
   S" #####..##" 4 TTEST-ROW
   S" wrap negative direction" TTEST-NAME TTEST-PIX
   9 9 TTEST-NEW 4.5e 0e SETXY
   S" ....#####" 4 TTEST-ROW
   S" positive boundary endpoint" TTEST-NAME TTEST-PIX
   TT@X F@ -4.5e S" positive boundary normalizes negative" TTEST-FLOAT
   9 9 TTEST-NEW PU WINDOW 20e -20e SETXY WRAP
   TT@X F@ 2e S" window to wrap x" TTEST-FLOAT
   TT@Y F@ -2e S" window to wrap y" TTEST-FLOAT
   S" mode switch draws no connection" TTEST-NAME TTEST-PIX
   9 9 TTEST-NEW WINDOW 20e 0e SETXY
   S" ....#####" 4 TTEST-ROW
   S" window clips line" TTEST-NAME TTEST-PIX
   TT@X F@ 20e S" window retains outside position" TTEST-FLOAT
;
: TTEST-FENCE-MOVE ( -- ) 5e 1e SETXY ;
: TTEST-FENCE-ARC ( -- ) 180e 3e ARC ;
: TTEST-FENCE-POS-X ( -- ) 4.5e -4.5e SETXY ;
: TTEST-FENCE-POS-Y ( -- ) -4.5e 4.5e SETXY ;
: TTEST-FENCE-NEG-X ( -- ) -4.5001e -4.5e SETXY ;
: TTEST-FENCE ( -- )
   9 9 TTEST-NEW FENCE 2e FD
   4 2 TTEST-WHITE 4 3 TTEST-WHITE 4 4 TTEST-WHITE
   ['] TTEST-FENCE-MOVE CATCH -4200 S" fence move code" TTEST-CHECK
   TT@X F@ 0e S" fence keeps x" TTEST-FLOAT TT@Y F@ 2e S" fence keeps y" TTEST-FLOAT
   S" fence move atomic pixels" TTEST-NAME TTEST-PIX
   PU ['] TTEST-FENCE-MOVE CATCH -4200 S" fence checks penup" TTEST-CHECK PD
   180e SETH
   ['] TTEST-FENCE-ARC CATCH -4200 S" fence arc code" TTEST-CHECK
   S" fence arc atomic pixels" TTEST-NAME TTEST-PIX
   WINDOW PU 5e 1e SETXY
   ['] FENCE CATCH -4200 S" fence switch code" TTEST-CHECK
   TT@MODE @ 1 S" fence switch keeps mode" TTEST-CHECK
   TT@X F@ 5e S" fence switch keeps position" TTEST-FLOAT
   WRAP TT@MODE @ 0 S" wrap alias" TTEST-CHECK
   9 9 TTEST-NEW FENCE PU -4.5e -4.5e SETXY
   TT@X F@ -4.5e S" fence includes negative x boundary" TTEST-FLOAT
   TT@Y F@ -4.5e S" fence includes negative y boundary" TTEST-FLOAT
   ['] TTEST-FENCE-POS-X CATCH -4200 S" fence excludes positive x boundary" TTEST-CHECK
   ['] TTEST-FENCE-POS-Y CATCH -4200 S" fence excludes positive y boundary" TTEST-CHECK
   ['] TTEST-FENCE-NEG-X CATCH -4200 S" fence excludes below negative boundary" TTEST-CHECK
   S" fence half-open boundary atomic pixels" TTEST-NAME TTEST-PIX
;

\ ---- Square brush and small-radius chord approximation ----
: TTEST-SHAPES ( -- )
   9 9 TTEST-NEW 3 SETPENSIZE 2e 0e SETXY
   3 3 5 3 $FFFFFF TTEST-RECT
   S" odd brush width 3" TTEST-NAME TTEST-PIX
   9 9 TTEST-NEW 2 SETPENSIZE 2e 0e SETXY
   4 4 4 2 $FFFFFF TTEST-RECT
   S" even brush width 2 positive pixel bias" TTEST-NAME TTEST-PIX
   9 9 TTEST-NEW 4 SETPENSIZE 0e FD
   3 3 4 4 $FFFFFF TTEST-RECT
   S" even brush width 4 dot" TTEST-NAME TTEST-PIX
   3 3 TTEST-NEW 64 SETPENSIZE 0e FD
   0 0 3 3 $FFFFFF TTEST-RECT
   S" maximum brush width 64" TTEST-NAME TTEST-PIX
   9 9 TTEST-NEW 3 SETPENSIZE PU 4e 0e SETXY PD 0e FD
   7 3 2 3 $FFFFFF TTEST-RECT
   S" thick wrap edge clips without duplicating thickness" TTEST-NAME TTEST-PIX
   9 9 TTEST-NEW 90e 2e ARC
   \ Four chords at 0,22.5,45,67.5,90 degrees: (4,2),(5,2),
   \ (5,3),(6,3),(6,4), including Bresenham endpoints.
   4 2 TTEST-WHITE 5 2 TTEST-WHITE 5 3 TTEST-WHITE 6 3 TTEST-WHITE 6 4 TTEST-WHITE
   S" arc radius 2 quarter turn" TTEST-NAME TTEST-PIX
   TT@X F@ 0e S" arc keeps x" TTEST-FLOAT TT@Y F@ 0e S" arc keeps y" TTEST-FLOAT
   TT@HEADING F@ 0e S" arc keeps heading" TTEST-FLOAT
   CLEAN TTEST-RESET-EXPECTED -90e 2e ARC
   4 2 TTEST-WHITE 3 2 TTEST-WHITE 3 3 TTEST-WHITE 2 3 TTEST-WHITE 2 4 TTEST-WHITE
   S" arc negative angle" TTEST-NAME TTEST-PIX
   CLEAN TTEST-RESET-EXPECTED 0e 2e ARC
   S" zero angle no pixels" TTEST-NAME TTEST-PIX
   90e 0e ARC 4 4 TTEST-WHITE S" zero radius dot" TTEST-NAME TTEST-PIX
   CLEAN TTEST-RESET-EXPECTED PU 90e 2e ARC
   S" arc penup no pixels" TTEST-NAME TTEST-PIX
;

\ ---- Built-in Misaki ASCII A: source font_misaki.zig, code 0041 ----
\ Rows 40 A0 A0 E0 A0 A0 00 00, high bits first, advance 4.
: TTEST-TEXT ( -- )
   17 17 TTEST-NEW WINDOW PU -6e 6e SETXY
   5 SETPENCOLOR 6 SETPENSIZE 137e SETH
   S" A" LABEL
   3 2 $FF00FF TTEST-AT
   2 3 $FF00FF TTEST-AT 4 3 $FF00FF TTEST-AT
   2 4 $FF00FF TTEST-AT 4 4 $FF00FF TTEST-AT
   2 5 3 1 $FF00FF TTEST-RECT
   2 6 $FF00FF TTEST-AT 4 6 $FF00FF TTEST-AT
   2 7 $FF00FF TTEST-AT 4 7 $FF00FF TTEST-AT
   S" label exact ASCII A ignores pen heading size" TTEST-NAME TTEST-PIX
   TT@X F@ -6e S" label keeps x" TTEST-FLOAT TT@Y F@ 6e S" label keeps y" TTEST-FLOAT
   TT@HEADING F@ 137e S" label keeps heading" TTEST-FLOAT
   CLEAN TTEST-RESET-EXPECTED PU 8e 8e SETXY S" AA" LABEL
   \ Origin (16,0); the x=1 top pixel and x=2 strokes are clipped.
   16 1 $FF00FF TTEST-AT 16 2 $FF00FF TTEST-AT 16 3 $FF00FF TTEST-AT
   16 4 $FF00FF TTEST-AT 16 5 $FF00FF TTEST-AT
   S" label clips and never wraps" TTEST-NAME TTEST-PIX
;

\ ---- Color table independently transcribed from specification 3.3 ----
CREATE TTEST-COLORS ( -- addr )
$000000 , $0000FF , $00FF00 , $00FFFF , $FF0000 , $FF00FF , $FFFF00 , $FFFFFF ,
$A52A2A , $D2B48C , $228B22 , $7FFFD4 , $FA8072 , $800080 , $FFA500 , $808080 ,
: TTEST-COLORS-RUN ( -- )
   3 3 TTEST-NEW
   16 0 DO
      I SETPC 0e FD
      TURTLE-IMAGE 1 1 GFX-PIXEL TTEST-COLORS I CELLS + @ S" numbered pen color" TTEST-CHECK
      I SETBG
      TTEST-RESET-EXPECTED 0 0 3 3 TTEST-COLORS I CELLS + @ TTEST-RECT
      S" numbered background full canvas" TTEST-NAME TTEST-PIX
   LOOP
   100e 50e 0e SETPENCOLOR-RGB 0e FD
   TURTLE-IMAGE 1 1 GFX-PIXEL $FF8000 S" rgb includes 100 and rounds 127.5 up" TTEST-CHECK
   0e 0.19607843137254902e 100e SETBACKGROUND-RGB
   TTEST-RESET-EXPECTED 0 0 3 3 $0001FF TTEST-RECT
   S" percentage background rounding" TTEST-NAME TTEST-PIX
;

\ ---- Invalid inputs, pure cancellation polling, idempotent disposal ----
: TTEST-BAD-PC ( -- ) 16 SETPC ;
: TTEST-BAD-BG ( -- ) -1 SETBG ;
: TTEST-BAD-RGB ( -- ) 0e 101e 0e SETPENCOLOR-RGB ;
: TTEST-BAD-RGB-NEG ( -- ) -0.1e 0e 0e SETBACKGROUND-RGB ;
: TTEST-BAD-SIZE ( -- ) 0 SETPENSIZE ;
: TTEST-BIG-SIZE ( -- ) 65 SETPENSIZE ;
: TTEST-BAD-SPEED ( -- ) -1 SETSPEED ;
: TTEST-BIG-SPEED ( -- ) 1001 SETSPEED ;
: TTEST-BAD-W ( -- ) 1 9 SETSCREENSIZE ;
: TTEST-BAD-H ( -- ) 9 4097 SETSCREENSIZE ;
: TTEST-BIG-FD ( -- ) 1000001e FD ;
: TTEST-BIG-XY ( -- ) 0e -1000001e SETXY ;
: TTEST-BAD-ARC ( -- ) 90e -1e ARC ;
: TTEST-BIG-ARC ( -- ) 1000001e 1e ARC ;
: TTEST-BIG-RADIUS ( -- ) 1e 1000001e ARC ;
: TTEST-INF ( -- ) 1e 0e F/ FD ;
: TTEST-NAN ( -- ) 0e 0e F/ SETH ;
: TTEST-INF-RGB ( -- ) 0e 1e 0e F/ 0e SETPENCOLOR-RGB ;
: TTEST-RESULT ( -- ) WINDOW PU 1000000e 0e SETXY 90e SETH 1e FD ;
: TTEST-ESC ( -- ) 27 TT@CLOSES @ TT@INPUT ;
: TTEST-CLOSE ( -- ) -1 TT@CLOSES @ 1+ TT@INPUT ;
: TTEST-ERROR { xt addr len -- }
   xt CATCH -4201 addr len TTEST-CHECK
;
: TTEST-ERRORS ( -- )
   9 9 TTEST-NEW
   ['] TTEST-BAD-PC S" invalid color" TTEST-ERROR
   ['] TTEST-BAD-BG S" invalid background" TTEST-ERROR
   ['] TTEST-BAD-RGB S" invalid rgb high" TTEST-ERROR
   ['] TTEST-BAD-RGB-NEG S" invalid rgb negative" TTEST-ERROR
   ['] TTEST-BAD-SIZE S" invalid width low" TTEST-ERROR
   ['] TTEST-BIG-SIZE S" invalid width high" TTEST-ERROR
   ['] TTEST-BAD-SPEED S" invalid speed low" TTEST-ERROR
   ['] TTEST-BIG-SPEED S" invalid speed high" TTEST-ERROR
   ['] TTEST-BAD-W S" invalid canvas width" TTEST-ERROR
   ['] TTEST-BAD-H S" invalid canvas height" TTEST-ERROR
   ['] TTEST-BIG-FD S" distance upper bound" TTEST-ERROR
   ['] TTEST-BIG-XY S" coordinate upper bound" TTEST-ERROR
   ['] TTEST-BAD-ARC S" negative radius" TTEST-ERROR
   ['] TTEST-BIG-ARC S" angle upper bound" TTEST-ERROR
   ['] TTEST-BIG-RADIUS S" radius upper bound" TTEST-ERROR
   ['] TTEST-INF S" infinite distance" TTEST-ERROR
   ['] TTEST-NAN S" nan heading" TTEST-ERROR
   ['] TTEST-INF-RGB S" infinite percentage" TTEST-ERROR
   TTEST-STATE
   S" invalid commands preserve canvas" TTEST-NAME TTEST-PIX
   ['] TTEST-RESULT S" computed coordinate upper bound" TTEST-ERROR
   9 9 TTEST-NEW
   -1 TT@CLOSES @ TT@INPUT 65 TT@CLOSES @ TT@INPUT
   ['] TTEST-ESC CATCH -4205 S" pure poll escape" TTEST-CHECK
   ['] TTEST-CLOSE CATCH -4205 S" pure poll close counter" TTEST-CHECK
   -4200 -278 TT@FIRST -4200 S" cleanup preserves original error" TTEST-CHECK
   0 -278 TT@FIRST -278 S" cleanup reports first cleanup error" TTEST-CHECK
   0 0 TT@FIRST 0 S" cleanup success" TTEST-CHECK
   0 SETSPEED TT@POLL 1000 SETSPEED TT@POLL
   TURTLE-IMAGE >R TURTLE-DISPOSE
   TURTLE-IMAGE 0 S" dispose clears ownership" TTEST-CHECK
   TURTLE-DISPOSE TURTLE-IMAGE 0 S" second dispose safe" TTEST-CHECK
   R> ['] IMAGE-SIZE CATCH -278 S" disposed handle invalid" TTEST-CHECK DROP
;
TTEST-BASICS TTEST-SETTINGS TTEST-WRAP TTEST-FENCE TTEST-SHAPES TTEST-TEXT
TTEST-COLORS-RUN TTEST-ERRORS
DEPTH 0 S" final data stack depth" TTEST-CHECK
FDEPTH 0 S" final float stack depth" TTEST-CHECK
.( passed ) TTEST-PASSED @ . .( failed ) TTEST-FAILED @ . CR
TTEST-FAILED @ [IF] -4201 THROW [THEN]
BYE
