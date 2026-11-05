\ The graphics library of FORTH/Sigma, written in Forth.
\
\ REQUIRE-GRAPHICS interprets this file, which is built into the program, after it
\ has put the GFX- words in the GRAPHICS vocabulary. While the file loads, new words go
\ into GRAPHICS and GRAPHICS is searched first; afterwards the search order and the
\ current word list are what they were before REQUIRE-GRAPHICS.
\
\ To try a changed copy of this file without rebuilding, load the built-in one first
\ and then include the copy into GRAPHICS:
\   REQUIRE-GRAPHICS  ALSO GRAPHICS DEFINITIONS  INCLUDE src/graphics/graphics.fs
\
\ The GFX- words (colors are 0xRRGGBB):
\   GFX-INIT    ( w h -- )          a new black image, each side 1 to 8192 pixels
\   GFX-WIDTH   ( -- w )            GFX-HEIGHT ( -- h ), 0 before GFX-INIT
\   GFX-PSET    ( x y rgb -- )      set a pixel; outside the image nothing happens
\   GFX-PGET    ( x y -- rgb )      read a pixel; -1 outside the image
\   GFX-HLINE   ( x1 x2 y rgb -- )  a horizontal line from x1 to x2, both included
\   GFX-CLS     ( rgb -- )          fill the whole image
\   GFX-SAVE-PPM ( c-addr u -- ior )  GFX-SAVE-BMP ( c-addr u -- ior )
\
\ The drawing words (LINE, RECT, CIRCLE, ...) come in the next stage (G2).
