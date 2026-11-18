\ Manual native-window display check (#984), Linux experimental build:
\   zig build -Dx11=true
\   zig-out/bin/sigma tests/scripts/check-window-display.fs < /dev/null
\ Keys: 0 full color, 2 black/white, 6 ANSI16, 5 xterm256, D toggle dither.
\ In full color, move the window between screens, resize it and click the four
\ outlined boxes. The yellow cross should appear where clicked. Test the palette
\ keys and dithering, then Escape to finish. This does not change display settings.
\ Click coordinates and mode changes are logged; visual results need user report.
\ SHOW reopens a normally closed native window; use Escape to finish.
\ A SHOW error is logged and rethrown after leaving the redraw loop.

REQUIRE-GRAPHICS ALSO GRAPHICS
DECIMAL
CREATE DISPLAY-BARS $000000 , $FFFFFF , $FF0000 , $00FF00 ,
                    $0000FF , $FFFF00 , $FF00FF , $00FFFF ,
VARIABLE CHECK-COLORS
VARIABLE CHECK-DITHER
VARIABLE OLD-COLORS
VARIABLE OLD-DITHER
VARIABLE CLICK-X
VARIABLE CLICK-Y
VARIABLE DISPLAY-DONE
VARIABLE DISPLAY-SHOW-ERROR

: DISPLAY-NUMBER { n x y -- }
   n S>D DUP >R DABS <# #S R> SIGN #> x y TEXT ;
: DISPLAY-LOG ( -- )
   SPACE ." processed-ms " UTIME DROP 1000 / . CR STDOUT FLUSH-FILE DROP ;
: GREY-RGB ( n -- rgb )   DUP 8 LSHIFT OVER 16 LSHIFT OR OR ;
: DISPLAY-PATTERN ( -- )
   CLS $FFFFFF COLOR!
   S" Escape ends; closing reopens" 10 10 TEXT
   S" 0 full / 2 mono / 6 16 / 5 256 / D dither" 10 40 TEXT
   S" Move/resize; click 4 boxes in full color" 10 70 TEXT
   8 0 DO
      DISPLAY-BARS I CELLS + @ COLOR!
      I 80 * 40 + 110 80 50 FILL-RECT
   LOOP
   $FFFFFF COLOR! 39 109 642 52 RECT
   640 0 DO
      I 255 * 639 / GREY-RGB COLOR!
      I 40 + 180 1 48 FILL-RECT
   LOOP
   $FFFFFF COLOR! S" Check both screens, then Escape" 10 240 TEXT
   4 0 DO
      I 1+ I 170 * 92 + 265 DISPLAY-NUMBER
      I 170 * 60 + 290 80 50 RECT
   LOOP
   S" Colors:" 10 355 TEXT CHECK-COLORS @ 140 355 DISPLAY-NUMBER
   S" Dither:" 300 355 TEXT CHECK-DITHER @ ABS 440 355 DISPLAY-NUMBER
   S" Click x:" 10 380 TEXT CLICK-X @ 155 380 DISPLAY-NUMBER
   S" y:" 350 380 TEXT CLICK-Y @ 415 380 DISPLAY-NUMBER
   CLICK-X @ 0< 0= CLICK-Y @ 0< 0= AND IF
      $FFFF00 COLOR!
      CLICK-X @ 4 - CLICK-Y @ 9 1 FILL-RECT
      CLICK-X @ CLICK-Y @ 4 - 1 9 FILL-RECT
   THEN ;
: DISPLAY-MODE-LOG ( -- )
   CHECK-COLORS @ OLD-COLORS @ <>
   CHECK-DITHER @ OLD-DITHER @ <> OR IF
      ." colors " CHECK-COLORS @ . ." dither " CHECK-DITHER @ ABS . DISPLAY-LOG
      CHECK-COLORS @ OLD-COLORS ! CHECK-DITHER @ OLD-DITHER !
   THEN ;
: DISPLAY-KEY ( n -- )
   CASE
      48 OF 0 CHECK-COLORS ! ENDOF
      50 OF 2 CHECK-COLORS ! ENDOF
      54 OF 16 CHECK-COLORS ! ENDOF
      53 OF 256 CHECK-COLORS ! ENDOF
      100 OF CHECK-DITHER @ 0= CHECK-DITHER ! ENDOF
      68 OF CHECK-DITHER @ 0= CHECK-DITHER ! ENDOF
      27 OF TRUE DISPLAY-DONE ! ENDOF
   ENDCASE ;
: DISPLAY-INPUT ( -- )
   BEGIN INKEY DUP -1 <> WHILE DISPLAY-KEY REPEAT DROP ;
: DISPLAY-MOUSE { x y button kind -- }
   ." mouse kind " kind . ." button " button . ." at " x . y . DISPLAY-LOG
   kind 1 = button 1 = AND IF x CLICK-X ! y CLICK-Y ! THEN ;
: DISPLAY-SHOW ( -- )
   ['] SHOW CATCH ?DUP IF DISPLAY-SHOW-ERROR ! TRUE DISPLAY-DONE ! THEN ;
: WINDOW-DISPLAY-CHECK ( -- )
   DISPLAY-WINDOW 720 400 GFX-INIT 1080 600 WINDOW-SIZE 2 TEXT-SCALE
   0 CHECK-COLORS ! FALSE CHECK-DITHER ! -1 OLD-COLORS ! -1 OLD-DITHER !
   -1 CLICK-X ! -1 CLICK-Y ! FALSE DISPLAY-DONE ! 0 DISPLAY-SHOW-ERROR !
   ." native display check started" DISPLAY-LOG
   BEGIN
      DISPLAY-INPUT
      BEGIN MOUSE-EVENT WHILE DISPLAY-MOUSE REPEAT
      DISPLAY-MODE-LOG DISPLAY-PATTERN
      CHECK-COLORS @ DISPLAY-COLORS CHECK-DITHER @ DITHER DISPLAY-SHOW
      DISPLAY-DONE @ 0= IF 100 MS THEN
      DISPLAY-DONE @
   UNTIL
   DISPLAY-SHOW-ERROR @ ?DUP IF
      ." native display check aborted: " DUP . DISPLAY-LOG THROW
   THEN
   ." native display check finished" DISPLAY-LOG BYE ;

WINDOW-DISPLAY-CHECK
