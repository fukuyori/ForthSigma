\ Check by hand of WINDOW-SIZE 0 0 in Sigma's own window (tque #1023): the window
\ fits the work area of its screen (Windows: without the taskbar; macOS: the visible
\ frame, without the menu bar and the Dock; Linux: the desktop's _NET_WORKAREA, or the
\ screen). Run from the repository root, after `zig build`:
\   zig-out/bin/sigma tests/scripts/check-auto-size.fs
\ It shows three images in turn, each for 4 seconds:
\   1. 320 by 200: shown at its own size, 320 by 200.
\   2. 1600 by 1200: at most 1600 by 1200, smaller when the screen's work area is
\      smaller (on a screen 1080 high, about 1365 to 1390 by 1020 to 1045).
\   3. 4000 by 1000: a wide image, at most 1600 wide.
\ For each, check that the whole window, title bar and frame included, is on the
\ screen and not under the menu bar, the Dock, or a panel, and that the image keeps
\ its proportions (the circle is round). The terminal prints the image's size; the
\ window's size is what the screen shows. Move the window to another screen before
\ an image comes to check that screen too. Ctrl+C in the terminal ends the check.

REQUIRE-GRAPHICS ALSO GRAPHICS
DECIMAL

: SHOW-SIZE ( w h -- )
   2DUP GFX-INIT
   CR ." image " SWAP . ." by " . CR
   CLS
   255 255 0 COLOR
   \ A round mark in the middle and a frame on the image's edge.
   GFX-WIDTH 2/ GFX-HEIGHT 2/ GFX-HEIGHT 3 / CIRCLE
   0 0 GFX-WIDTH GFX-HEIGHT RECT
   0 0 WINDOW-SIZE SHOW 4000 MS ;

: AUTO-SIZE-CHECK ( -- )
   DISPLAY-WINDOW
   320 200 SHOW-SIZE
   1600 1200 SHOW-SIZE
   4000 1000 SHOW-SIZE
   CR ." done" CR ;

AUTO-SIZE-CHECK BYE
