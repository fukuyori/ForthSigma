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
