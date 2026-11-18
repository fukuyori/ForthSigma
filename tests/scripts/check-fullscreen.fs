\ Check by hand of FULLSCREEN and MOUSE-CURSOR in Sigma's own window (tque #1019).
\ Run from the repository root, after `zig build`:
\   zig-out/bin/sigma tests/scripts/check-fullscreen.fs
\ The window opens fullscreen on the screen it is on, without changing the screen's
\ mode: the image (a frame and a circle) keeps its proportions, black around it, and
\ the window should have the keys. Then, in the window:
\   Alt+Enter (Control+Command+F on macOS)  leaves fullscreen; the terminal prints
\                                           "fullscreen: 0" and no key for it
\   F   fullscreen again          W   a window again (FALSE FULLSCREEN)
\   C   hide or show the mouse cursor over the window (not over the title bar)
\   other keys are printed with their codes      Q   quit
\ Also check: the window goes back to its place and size when it leaves fullscreen;
\ closing the window while fullscreen, the next image opens it fullscreen again (FRAME
\ shows one each 20 ms); Alt+Tab (Command+Tab) and the taskbar or the Dock.
\ With DISPLAY-TK in front of the program, the Tk window is checked instead.

REQUIRE-GRAPHICS ALSO GRAPHICS
DECIMAL

VARIABLE CURSOR-SHOWN   TRUE CURSOR-SHOWN !
VARIABLE LAST-STATE     0 LAST-STATE !

: PICTURE ( -- )
   CLS 255 255 0 COLOR
   0 0 GFX-WIDTH GFX-HEIGHT RECT
   GFX-WIDTH 2/ GFX-HEIGHT 2/ GFX-HEIGHT 3 / CIRCLE ;

: TELL ( -- )
   FULLSCREEN? DUP LAST-STATE @ <> IF
      DUP LAST-STATE !  CR ." fullscreen: " DUP 0<> 1 AND . CR
   THEN DROP ;

: CHECK-FULLSCREEN ( -- )
   320 200 GFX-INIT PICTURE
   TRUE FULLSCREEN SHOW TELL
   BEGIN
      INKEY DUP -1 <> IF
         DUP [CHAR] q = OVER [CHAR] Q = OR IF DROP EXIT THEN
         DUP [CHAR] f = OVER [CHAR] F = OR IF TRUE FULLSCREEN THEN
         DUP [CHAR] w = OVER [CHAR] W = OR IF FALSE FULLSCREEN THEN
         DUP [CHAR] c = OVER [CHAR] C = OR IF
            CURSOR-SHOWN @ 0= DUP CURSOR-SHOWN ! MOUSE-CURSOR
         THEN
         CR ." key " . CR
      ELSE DROP THEN
      TELL
      20 FRAME
   AGAIN ;

CHECK-FULLSCREEN CR ." done" CR BYE
