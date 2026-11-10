\ The game library of FORTH/Sigma, written in Forth.
\
\ REQUIRE-GAME interprets this file, which is built into the program, after it has loaded
\ the graphics words (REQUIRE-GRAPHICS) and put the GAME vocabulary in the Forth word
\ list. While the file loads, new words go into GAME, and GAME and then GRAPHICS are
\ searched first; afterwards the search order, the current word list, and BASE are what
\ they were before REQUIRE-GAME.
\
\ The words are small and work on data the program makes and keeps: a sprite or a map
\ is a structure in the dictionary (SPRITE: and TILEMAP:, or /SPRITE and /TILEMAP bytes
\ the program allots, for an array of them), and the program's own loop decides what to
\ move, draw, and test, and when. Nothing here calls the program back.
\   GFX-PIXEL ( img x y -- rgb | -1 )
\   GFX-TILEMAP ( addr cols rows img tw th sx sy x y w h key -- )

\ ---- Sprites ---------------------------------------------------------------------------

\ A sprite: where it is, the rectangle of an image it shows (its first frame), the
\ frames of its animation side by side to the right of the first, how it is flipped
\ (as IMAGE-FLIP), its transparent color (-1 for none), and whether it is shown.
BEGIN-STRUCTURE /SPRITE
   FIELD: SPRITE-X       FIELD: SPRITE-Y
   FIELD: SPRITE-IMAGE   FIELD: SPRITE-SX   FIELD: SPRITE-SY
   FIELD: SPRITE-W       FIELD: SPRITE-H
   FIELD: SPRITE-FRAMES  FIELD: SPRITE-FRAME
   FIELD: SPRITE-DELAY   FIELD: SPRITE-TICK
   FIELD: SPRITE-FLIP    FIELD: SPRITE-KEY   FIELD: SPRITE-SHOWN
END-STRUCTURE

\ Makes the /SPRITE bytes at spr a sprite showing the w by h rectangle at sx sy of img:
\ at 0 0, shown, one frame, not flipped, no transparent color.
: INIT-SPRITE { img sx sy w h spr -- }
   spr /SPRITE ERASE
   img spr SPRITE-IMAGE !  sx spr SPRITE-SX !  sy spr SPRITE-SY !
   w spr SPRITE-W !  h spr SPRITE-H !
   1 spr SPRITE-FRAMES !  1 spr SPRITE-DELAY !  -1 spr SPRITE-KEY !  TRUE spr SPRITE-SHOWN ! ;

\ Defines a sprite: name gives its address.
: SPRITE: ( img sx sy w h "name" -- )   CREATE HERE /SPRITE ALLOT INIT-SPRITE ;

\ Puts a sprite at x y.
: PUT-SPRITE ( x y spr -- )   TUCK SPRITE-Y ! SPRITE-X ! ;

\ An animation of n frames, each shown for `delay` calls of ANIMATE; it starts again
\ from the first frame.
: SPRITE-ANIM { n delay spr -- }
   n 1 MAX spr SPRITE-FRAMES !  delay 1 MAX spr SPRITE-DELAY !
   0 spr SPRITE-FRAME !  0 spr SPRITE-TICK ! ;

\ One step of the animation: once a frame has been shown for its delay, the next one.
: ANIMATE { spr -- }
   1 spr SPRITE-TICK +!
   spr SPRITE-TICK @ spr SPRITE-DELAY @ < IF EXIT THEN
   0 spr SPRITE-TICK !
   spr SPRITE-FRAME @ 1+ spr SPRITE-FRAMES @ MOD spr SPRITE-FRAME ! ;

\ Where the frame shown is in the image.
: (FRAME-X) ( spr -- sx )   DUP SPRITE-SX @  OVER SPRITE-FRAME @  ROT SPRITE-W @ * + ;

\ Draws a sprite that is shown on the image drawn on, as COPY-RECT copies (over what is
\ there, at its own size).
: DRAW-SPRITE { spr -- }
   spr SPRITE-SHOWN @ 0= IF EXIT THEN
   spr SPRITE-IMAGE @  spr (FRAME-X)  spr SPRITE-SY @  spr SPRITE-W @  spr SPRITE-H @
   spr SPRITE-X @  spr SPRITE-Y @  spr SPRITE-KEY @  spr SPRITE-FLIP @  0 128 1 GFX-COPY ;

\ Whether the rectangles of two shown sprites overlap.
: HIT? { a b -- flag }
   a SPRITE-SHOWN @ 0= b SPRITE-SHOWN @ 0= OR IF FALSE EXIT THEN
   a SPRITE-X @  b SPRITE-X @ b SPRITE-W @ +  <
   b SPRITE-X @  a SPRITE-X @ a SPRITE-W @ +  <  AND
   a SPRITE-Y @  b SPRITE-Y @ b SPRITE-H @ +  <  AND
   b SPRITE-Y @  a SPRITE-Y @ a SPRITE-H @ +  <  AND ;

\ Whether a sprite shows a pixel at x y: inside it and not of its transparent color.
: SPRITE-PIXEL? { x y spr | dx dy c -- flag }
   x spr SPRITE-X @ - TO dx  y spr SPRITE-Y @ - TO dy
   dx 0 spr SPRITE-W @ WITHIN  dy 0 spr SPRITE-H @ WITHIN  AND 0= IF FALSE EXIT THEN
   spr SPRITE-FLIP @ 1 AND IF  spr SPRITE-W @ 1- dx - TO dx  THEN
   spr SPRITE-FLIP @ 2 AND IF  spr SPRITE-H @ 1- dy - TO dy  THEN
   spr SPRITE-IMAGE @  spr (FRAME-X) dx +  spr SPRITE-SY @ dy +  GFX-PIXEL TO c
   c 0< IF FALSE EXIT THEN
   spr SPRITE-KEY @ DUP 0< IF DROP TRUE ELSE $FFFFFF AND c <> THEN ;

\ Whether two shown sprites show a pixel at the same place.
: PIXEL-HIT? { a b | x0 x1 y0 y1 -- flag }
   a b HIT? 0= IF FALSE EXIT THEN
   a SPRITE-X @ b SPRITE-X @ MAX TO x0
   a SPRITE-X @ a SPRITE-W @ +  b SPRITE-X @ b SPRITE-W @ +  MIN TO x1
   a SPRITE-Y @ b SPRITE-Y @ MAX TO y0
   a SPRITE-Y @ a SPRITE-H @ +  b SPRITE-Y @ b SPRITE-H @ +  MIN TO y1
   y1 y0 ?DO  x1 x0 ?DO
      I J a SPRITE-PIXEL?  I J b SPRITE-PIXEL? AND IF TRUE UNLOOP UNLOOP EXIT THEN
   LOOP LOOP  FALSE ;

\ ---- Tile maps -------------------------------------------------------------------------

\ A tile map: the image of its tiles (tile n is the tw by th rectangle n tiles from the
\ top left corner, counted along the image's rows), its size in tiles, and its transparent
\ color (-1 for none). One byte for each tile, row by row, follows it.
BEGIN-STRUCTURE /TILEMAP
   FIELD: TILEMAP-IMAGE  FIELD: TILEMAP-TW    FIELD: TILEMAP-TH
   FIELD: TILEMAP-COLS   FIELD: TILEMAP-ROWS  FIELD: TILEMAP-KEY
END-STRUCTURE

\ The tile numbers of a map.
: TILEMAP-DATA ( map -- addr )   /TILEMAP + ;

\ Defines a map of cols by rows tiles, all tile 0: name gives its address.
: TILEMAP: { img tw th cols rows | map -- }
   cols 0< rows 0< OR  tw 1 < OR  th 1 < OR IF -24 THROW THEN
   CREATE  HERE TO map  /TILEMAP cols rows * + ALLOT ALIGN
   img map TILEMAP-IMAGE !  tw map TILEMAP-TW !  th map TILEMAP-TH !
   cols map TILEMAP-COLS !  rows map TILEMAP-ROWS !  -1 map TILEMAP-KEY !
   map TILEMAP-DATA cols rows * ERASE ;

: (TILE-ADDR) { col row map -- addr }
   col 0 map TILEMAP-COLS @ WITHIN  row 0 map TILEMAP-ROWS @ WITHIN  AND 0= IF -24 THROW THEN
   map TILEMAP-DATA  row map TILEMAP-COLS @ * +  col + ;
\ The tile at col row, and setting it; NUMBER ERROR outside the map.
: TILE@ ( col row map -- n )   (TILE-ADDR) C@ ;
: TILE! ( n col row map -- )   (TILE-ADDR) C! ;

\ The tile under pixel x y of the map (which may be outside it).
: >TILE { x y map -- col row }   x map TILEMAP-TW @ /  y map TILEMAP-TH @ / ;

\ Draws the w by h rectangle at x y of the image drawn on with the map seen from its
\ pixel sx sy. Only the tiles in the rectangle are drawn; what lies outside the map, and
\ the pixels of the transparent color, are left as they are, so a second map can be
\ drawn over a first (as the two playfields of the Amiga).
: DRAW-TILEMAP { sx sy x y w h map -- }
   map TILEMAP-DATA  map TILEMAP-COLS @  map TILEMAP-ROWS @
   map TILEMAP-IMAGE @  map TILEMAP-TW @  map TILEMAP-TH @
   sx sy x y w h  map TILEMAP-KEY @  GFX-TILEMAP ;

\ ---- Palettes and pictures of color numbers -------------------------------------------

\ A palette: 256 cells, the colors of the numbers 0 to 255, all black at first.
: PALETTE: ( "name" -- )   CREATE HERE 256 CELLS ALLOT 256 CELLS ERASE ;
: (COLOR#) ( n pal -- addr )   SWAP DUP 0 256 WITHIN 0= IF -24 THROW THEN CELLS + ;
: PALETTE! ( rgb n pal -- )   (COLOR#) SWAP $FFFFFF AND SWAP ! ;
: PALETTE@ ( n pal -- rgb )   (COLOR#) @ ;

\ Turns the colors of the numbers first to first + count - 1 one place up: each takes
\ the color of the number below it, and the first the color of the last, as palettes
\ were turned to make water flow or lights run. Draw again to see it.
: ROTATE-PALETTE { first count pal | last -- }
   count 2 < IF EXIT THEN
   first count + 1- pal PALETTE@ TO last
   first pal (COLOR#)  DUP CELL+  count 1- CELLS MOVE
   last first pal PALETTE! ;

\ A picture of color numbers: its size, and one byte for each pixel, row by row.
BEGIN-STRUCTURE /INDEXED
   FIELD: INDEXED-W  FIELD: INDEXED-H
END-STRUCTURE
: INDEXED-DATA ( pic -- addr )   /INDEXED + ;
\ Defines a picture of w by h pixels, all color number 0.
: INDEXED: { w h | pic -- }
   w 0 16385 WITHIN h 0 16385 WITHIN AND 0= IF -24 THROW THEN
   CREATE  HERE TO pic  /INDEXED w h * + ALLOT ALIGN
   w pic INDEXED-W !  h pic INDEXED-H !  pic INDEXED-DATA w h * ERASE ;
: (INDEX-ADDR) { x y pic -- addr }
   x 0 pic INDEXED-W @ WITHIN  y 0 pic INDEXED-H @ WITHIN  AND 0= IF -24 THROW THEN
   pic INDEXED-DATA  y pic INDEXED-W @ * +  x + ;
\ The color number of pixel x y, and setting it; NUMBER ERROR outside the picture.
: INDEX@ ( x y pic -- n )   (INDEX-ADDR) C@ ;
: INDEX! ( n x y pic -- )   (INDEX-ADDR) C! ;
\ Draws a picture at x y of the image drawn on with the colors of a palette; the pixels
\ of color number key are left out (-1 for none).
: DRAW-INDEXED { x y pic pal key -- }
   pic INDEXED-DATA  pic INDEXED-W @  pic INDEXED-H @  pal  x y key  GFX-INDEXED ;

\ ---- Effects on each row -------------------------------------------------------------

\ After drawing, as the video chips that changed a register on each scan line: the rows
\ of the w by h rectangle at x y of the image drawn on, each with its cell of a table of
\ h cells. RASTER-SCROLL moves each row to the right by its cell inside the rectangle
\ (what leaves on the right comes in on the left); RASTER-COLOR gives the pixels of one
\ color in each row the color in its cell.
: RASTER-SCROLL ( table x y w h -- )   GFX-ROW-SHIFT ;
: RASTER-COLOR ( table rgb x y w h -- )   GFX-ROW-COLOR ;

\ ---- Sprites on a line -----------------------------------------------------------------

\ Draws n sprites of an array of /SPRITE structures in order, but on each row of the
\ image drawn on only the first `limit` sprites shown on that row: the later ones lose
\ that row, as on the video chips that could show only so many sprites on a scan line.
\ A limit of 0 draws them all.
VARIABLE (ON-LINE)
: (SPRITE-ROW) { row spr | sy -- }
   spr SPRITE-FLIP @ 2 AND IF spr SPRITE-H @ 1- row - ELSE row THEN  spr SPRITE-SY @ + TO sy
   spr SPRITE-IMAGE @  spr (FRAME-X)  sy  spr SPRITE-W @  1
   spr SPRITE-X @  spr SPRITE-Y @ row +  spr SPRITE-KEY @  spr SPRITE-FLIP @ 1 AND  0 128 1 GFX-COPY ;
\ The sprites, with the counts of the rows at (ON-LINE).
: (DRAW-LIMITED) { array n limit lines | spr y -- }
   n 0 ?DO
      array I /SPRITE * + TO spr
      spr SPRITE-SHOWN @ IF
         spr SPRITE-H @ 0 ?DO
            spr SPRITE-Y @ I + TO y
            y 0 lines WITHIN IF
               (ON-LINE) @ y CELLS +  DUP @ limit < IF  1 SWAP +!  I spr (SPRITE-ROW)  ELSE DROP THEN
            THEN
         LOOP
      THEN
   LOOP ;
\ The counts are freed also when drawing fails (an invalid image of a sprite).
: DRAW-SPRITES { array n limit | lines -- }
   limit 0= IF  n 0 ?DO array I /SPRITE * + DRAW-SPRITE LOOP  EXIT THEN
   GFX-HEIGHT TO lines
   lines CELLS ALLOCATE THROW (ON-LINE) !  (ON-LINE) @ lines CELLS ERASE
   array n limit lines ['] (DRAW-LIMITED) CATCH
   (ON-LINE) @ FREE DROP
   ?DUP IF  NIP NIP NIP NIP THROW  THEN ;