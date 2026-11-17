\ Check by hand of the input method in a GUI-FIELD, and of the system's font in it
\ (tque #889; Linux is #897). Run from the repository root, after `zig build`:
\   zig-out/bin/sigma tests/scripts/check-ime.fs -e "IME-TK"       the Tk window (needs wish)
\   zig-out/bin/sigma tests/scripts/check-ime.fs -e "IME-WINDOW"   Sigma's own window (Windows)
\ The terminal shows the font that was chosen (the first the system has of MS Gothic,
\ Hiragino Sans, Noto Sans CJK JP, Droid Sans Fallback; none: the built-in font, which
\ draws Japanese as ?). Type in the field, convert with the input method, and press
\ Enter. Each Enter prints the text of the field and its bytes to the terminal
\ (日本語 is E6 97 A5 E6 9C AC E8 AA 9E) and empties the field. The Quit button, or
\ Ctrl+C in the terminal, ends the check.
\ To look at: the text being converted shows underlined at the cursor; only the
\ committed text goes in; ASCII keys, Backspace, the arrows, Home, and End work as usual.

REQUIRE-GUI  ALSO GRAPHICS ALSO GUI
DECIMAL

CREATE TYPED 256 ALLOT   VARIABLE TYPED-LEN   0 TYPED-LEN !
VARIABLE IME-ENTERED   0 IME-ENTERED !

: .BYTES ( c-addr u -- )
   BASE @ >R HEX
   OVER + SWAP ?DO I C@ 0 <# # # #> TYPE SPACE LOOP
   R> BASE ! ;

: IME-REPORT ( -- )
   1 IME-ENTERED +!
   CR ." [" IME-ENTERED @ 0 .R ." ] " TYPED TYPED-LEN @ TYPE
   CR ."     " TYPED-LEN @ . ." bytes: " TYPED TYPED-LEN @ .BYTES CR
   0 TYPED-LEN ! ;

: TRY-FONT ( c-addr u -- flag )
   2DUP 16 ['] GFX-FONT-SYSTEM CATCH IF 2DROP DROP 2DROP FALSE EXIT THEN
   0= DUP IF CR ." font: " 2 PICK 2 PICK TYPE CR THEN NIP NIP ;

: JAPANESE-FONT ( -- )
   \ A font with Japanese characters, where the system has one by this name.
   S" MS Gothic" TRY-FONT IF EXIT THEN
   S" Hiragino Sans" TRY-FONT IF EXIT THEN
   S" Noto Sans CJK JP" TRY-FONT IF EXIT THEN
   S" Droid Sans Fallback" TRY-FONT DROP ;

: IME-CHECK ( -- )
   480 160 GFX-INIT
   JAPANESE-FONT
   BEGIN
      GUI-BACKGROUND GUI-COLOR@ GFX-CLS
      GUI-BEGIN
      S" Type here, convert, press Enter:" 10 10 GUI-LABEL
      TYPED 255 TYPED-LEN 10 40 460 GUI-FIELD IF IME-REPORT THEN
      S" The text of each Enter is printed in the terminal." 10 80 GUI-LABEL
      S" Quit" 10 120 GUI-BUTTON
      GUI-END  SHOW  16 FRAME
   UNTIL
   CR ." entered " IME-ENTERED @ . ." line(s)" CR ;

: IME-WINDOW ( -- ) DISPLAY-WINDOW IME-CHECK BYE ;
: IME-TK ( -- ) DISPLAY-TK IME-CHECK BYE ;
