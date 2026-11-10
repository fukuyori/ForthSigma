\ The GUI library of FORTH/Sigma, written in Forth.
\
\ REQUIRE-GUI interprets this file, which is built into the program, after it has loaded
\ the graphics words (REQUIRE-GRAPHICS) and put the GUI vocabulary in the Forth word
\ list. While the file loads, new words go into GUI, and GUI and then GRAPHICS are
\ searched first; afterwards the search order, the current word list, and BASE are what
\ they were before REQUIRE-GUI.
\
\ The parts are drawn again each frame, into the image drawn on (DRAW-TO): between
\ GUI-BEGIN and GUI-END, each part's word draws it and gives what the user did to it
\ in this frame. What a part keeps (a check box's flag, a field's text, a list's choice)
\ is in the program's own variables. GUI-BEGIN reads the mouse, the keys, and the first
\ gamepad once for the frame; keys the parts do not take wait for GUI-KEY.
\
\ Every color is a role that GUI-COLOR! changes, and the widths of the lines are
\ GUI-BORDER-WIDTH and GUI-FOCUS-WIDTH. Words whose names are in parentheses are helpers.

\ ---- Colors and lines ----------------------------------------------------------------

0 CONSTANT GUI-BACKGROUND    \ panels, dialogs, menus, the menu and key bars
1 CONSTANT GUI-FACE          \ buttons
2 CONSTANT GUI-HOVER         \ a button under the mouse
3 CONSTANT GUI-PRESSED       \ a button held down
4 CONSTANT GUI-TEXT
5 CONSTANT GUI-DISABLED      \ the text of parts that cannot be used
6 CONSTANT GUI-BORDER
7 CONSTANT GUI-FIELD-FACE    \ text fields and check boxes
8 CONSTANT GUI-FOCUS         \ the border of the part the keys go to
9 CONSTANT GUI-SELECTION     \ the chosen item of a list or a menu
10 CONSTANT GUI-SELECTED-TEXT
11 CONSTANT (ROLES)

CREATE (GUI-COLORS)  (ROLES) CELLS ALLOT
VARIABLE (BORDER-W)
VARIABLE (FOCUS-W)

\ Every color and line width back to the start.
: GUI-DEFAULT ( -- )
   $F0F0F0 $E1E1E1 $EBEBEB $C8C8C8 $000000 $8C8C8C $8A8A8A $FFFFFF $3A73D9 $3A73D9 $FFFFFF
   (ROLES) 0 DO  (GUI-COLORS) (ROLES) 1- I - CELLS + !  LOOP
   1 (BORDER-W) !  1 (FOCUS-W) ! ;
GUI-DEFAULT

: (ROLE) ( role -- addr )   DUP 0 (ROLES) WITHIN 0= IF DROP -24 THROW THEN  CELLS (GUI-COLORS) + ;
: GUI-COLOR! ( rgb role -- )   (ROLE) SWAP $FFFFFF AND SWAP ! ;
: GUI-COLOR@ ( role -- rgb )   (ROLE) @ ;
: GUI-BORDER-WIDTH ( n -- )   DUP 0 9 WITHIN 0= IF DROP -24 THROW THEN (BORDER-W) ! ;
: GUI-FOCUS-WIDTH ( n -- )   DUP 0 9 WITHIN 0= IF DROP -24 THROW THEN (FOCUS-W) ! ;

: (USE) ( role -- )   GUI-COLOR@ COLOR! ;

\ ---- Sizes --------------------------------------------------------------------------

\ The space between the text and the border of a part.
: (PAD-X) ( -- n )   6 ;
: (PAD-Y) ( -- n )   3 ;
\ The height of a button, a field, a list row, and a bar.
: (ROW-H) ( -- h )   TEXT-HEIGHT (PAD-Y) 2* +  (BORDER-W) @ 2* + ;

\ ---- Drawing helpers --------------------------------------------------------------------

\ A rectangle filled with one role's color, with a border n pixels wide of another's.
: (BOX) { x y w h fill line n -- }
   w 1 < h 1 < OR IF EXIT THEN
   fill (USE)  x y w h FILL-RECT
   line (USE)  n 0 ?DO  x I + y I + w I 2* - h I 2* - RECT  LOOP ;

\ The border of the part the keys go to, over its own border.
: (FOCUS-RING) { x y w h -- }
   GUI-FOCUS (USE)  (FOCUS-W) @ 0 ?DO  x I + y I + w I 2* - h I 2* - RECT  LOOP ;

\ Text in one role's color.
: (TEXT) ( addr u x y role -- )   (USE) TEXT ;

\ UTF-8: the start of the character before place n of a string, and after it.
: (BACK) { addr n -- n2 }
   n 0 > 0= IF 0 EXIT THEN
   n 1- BEGIN DUP 0> WHILE  addr OVER + C@ $C0 AND $80 <> IF EXIT THEN  1- REPEAT ;
: (FORTH) { addr u n -- n2 }
   n u < 0= IF u EXIT THEN
   n 1+ BEGIN DUP u < WHILE  addr OVER + C@ $C0 AND $80 <> IF EXIT THEN  1+ REPEAT ;

\ The bytes at the start of a string that fit in w pixels, whole characters only.
: (FIT) { addr u w | used n next -- n }
   0 TO used  0 TO n
   BEGIN n u < WHILE
      addr u n (FORTH) TO next
      addr n + next n - TEXT-WIDTH used + DUP w > IF DROP n EXIT THEN  TO used
      next TO n
   REPEAT  n ;

\ The item `i` of a list "a|b|c", and how many items it has.
: (ITEM) { addr u which | start n -- addr2 u2 }
   0 TO start  0 TO n
   u 0 ?DO
      addr I + C@ [CHAR] | = IF
         n which = IF  addr start +  I start -  UNLOOP EXIT THEN
         n 1+ TO n  I 1+ TO start
      THEN
   LOOP
   n which = IF addr start +  u start - ELSE addr 0 THEN ;
: (ITEMS) ( addr u -- n )   1 -ROT 0 ?DO  DUP I + C@ [CHAR] | = IF SWAP 1+ SWAP THEN  LOOP DROP ;

\ ---- Input of the frame ------------------------------------------------------------

VARIABLE (MX)  VARIABLE (MY)  VARIABLE (MOVED)     \ where the mouse is; whether it moved
VARIABLE (PRESS)  VARIABLE (PX)  VARIABLE (PY)      \ the left button went down
VARIABLE (RELEASE)  VARIABLE (RX)  VARIABLE (RY)    \ the left button went up
VARIABLE (WHEEL)
32 CONSTANT (KEY-ROOM)
CREATE (KEYS)  (KEY-ROOM) CELLS ALLOT
VARIABLE (KEY-COUNT)
VARIABLE (PAD-HELD)

: (ADD-KEY) ( key -- )
   (KEY-COUNT) @ (KEY-ROOM) < IF  (KEYS) (KEY-COUNT) @ CELLS + !  1 (KEY-COUNT) +!  ELSE DROP THEN ;
\ Takes out key i of the frame; the next one comes to its place.
: (DROP-KEY) ( i -- i )
   >R  (KEYS) R@ 1+ CELLS +  (KEYS) R@ CELLS +  (KEY-COUNT) @ R@ - 1- CELLS MOVE
   -1 (KEY-COUNT) +!  R> ;
\ Takes a key of the frame: whether it was there.
: (TAKE) { key -- flag }
   (KEY-COUNT) @ 0 ?DO
      (KEYS) I CELLS + @ key = IF  I (DROP-KEY) DROP  TRUE UNLOOP EXIT  THEN
   LOOP  FALSE ;
\ The next key the parts did not take, or -1.
: GUI-KEY ( -- key | -1 )
   (KEY-COUNT) @ 0= IF -1 EXIT THEN
   (KEYS) @  (KEYS) CELL+ (KEYS) (KEY-COUNT) @ 1- CELLS MOVE  -1 (KEY-COUNT) +! ;

\ The first gamepad as keys: its D-pad as the arrows, A as Enter, B as Esc, each when
\ it is pressed.
: (PAD-KEYS) ( -- )
   GAMEPAD-POLL 1 < IF EXIT THEN
   0 GAMEPAD-BUTTONS  DUP (PAD-HELD) @ INVERT AND  SWAP (PAD-HELD) !
   DUP 1 11 LSHIFT AND IF K-UP (ADD-KEY) THEN
   DUP 1 12 LSHIFT AND IF K-DOWN (ADD-KEY) THEN
   DUP 1 13 LSHIFT AND IF K-LEFT (ADD-KEY) THEN
   DUP 1 14 LSHIFT AND IF K-RIGHT (ADD-KEY) THEN
   DUP 1 AND IF 13 (ADD-KEY) THEN
   2 AND IF 27 (ADD-KEY) THEN ;

\ ---- Parts and focus ------------------------------------------------------------------

VARIABLE (ID)          \ the parts of this frame, counted
VARIABLE (ACTIVE)      \ the part the left button went down on, 0 for none
VARIABLE (FOCUS)       \ the part the keys go to, counted from 1 among those that take it
VARIABLE (FOCUS-N)     \ the parts of this frame that take the focus
VARIABLE (LAST-FOCUS-N)
VARIABLE (ENABLED)
\ The open pull-down menu takes the mouse inside it and all the keys.
VARIABLE (BX)  VARIABLE (BY)  VARIABLE (BW)  VARIABLE (BH)
VARIABLE (MENU-OPEN)   \ the open menu of the bar, -1 for none
VARIABLE (MENU-X)      \ where its title is
VARIABLE (MENU-ITEM)   \ its highlighted item
2VARIABLE (PULL)       \ its items, drawn by GUI-END
VARIABLE (CURSOR)      \ the place of the text cursor in the focused field
VARIABLE (CURSOR-OF)   \ the part the cursor belongs to
-1 (MENU-OPEN) !

: (IN) { px py x y w h -- flag }   px x - w U<  py y - h U< AND ;
: (BLOCKED) ( px py -- flag )
   (MENU-OPEN) @ 0< IF 2DROP FALSE EXIT THEN  (BX) @ (BY) @ (BW) @ (BH) @ (IN) ;
\ Whether the mouse, or the press, is over a part (and not over the open menu).
: (HOT) { x y w h -- flag }
   (MX) @ (MY) @ (BLOCKED) IF FALSE EXIT THEN  (MX) @ (MY) @ x y w h (IN) ;
: (PRESSED-ON) { x y w h -- flag }
   (PRESS) @ 0= IF FALSE EXIT THEN  (PX) @ (PY) @ (BLOCKED) IF FALSE EXIT THEN
   (PX) @ (PY) @ x y w h (IN) ;
: (RELEASED-ON) { x y w h -- flag }   (RELEASE) @ IF (RX) @ (RY) @ x y w h (IN) ELSE FALSE THEN ;

\ A new part: its number, and whether it may take the focus, which then gives its
\ number among those.
: (NEW-PART) ( -- id )   1 (ID) +!  (ID) @ ;
: (FOCUSABLE) ( -- n )   1 (FOCUS-N) +!  (FOCUS-N) @ ;
: (FOCUSED?) ( n -- flag )   (FOCUS) @ =  (MENU-OPEN) @ 0< AND ;

\ Parts made after GUI-ENABLE with false are drawn grey and take no input.
: GUI-ENABLE ( flag -- )   0<> (ENABLED) ! ;

\ Starts the GUI of a frame: reads the mouse, the keys, and the first gamepad.
: GUI-BEGIN ( -- )
   0 (ID) !  0 (FOCUS-N) !  TRUE (ENABLED) !  0 (KEY-COUNT) !
   FALSE (PRESS) !  FALSE (RELEASE) !  0 (WHEEL) !
   BEGIN MOUSE-EVENT WHILE
      { x y b k }
      k 3 = IF  b (WHEEL) +!  ELSE b 1 = IF
         k 1 = IF  TRUE (PRESS) !  x (PX) !  y (PY) !  THEN
         k 2 = IF  TRUE (RELEASE) !  x (RX) !  y (RY) !  THEN
      THEN THEN
   REPEAT
   MOUSE DROP  2DUP (MY) @ <> SWAP (MX) @ <> OR (PRESS) @ OR (MOVED) !  (MY) ! (MX) !
   BEGIN INKEY DUP 0< 0= WHILE (ADD-KEY) REPEAT DROP
   (PAD-KEYS)
   \ Tab gives the focus to the next part, also to the first after the last.
   (MENU-OPEN) @ 0< IF  9 (TAKE) IF
      (FOCUS) @ 1+  DUP (LAST-FOCUS-N) @ > IF DROP 1 THEN  (FOCUS) !
   THEN THEN
   \ Without a part that has it, the first part takes the focus.
   (FOCUS) @ 1 < (FOCUS) @ (LAST-FOCUS-N) @ > OR IF 1 (FOCUS) ! THEN ;

\ ---- Panels -------------------------------------------------------------------------

VARIABLE (TILES)  VARIABLE (TILE)
\ Draw panels with 9 tiles of an image instead of a border: corners, edges, and middle,
\ each `size` pixels square, three by three from its top left corner. 0 0 draws borders.
: GUI-TILES ( img size -- )   (TILE) !  (TILES) ! ;
: (PIECE) ( sx sy w h dx dy -- )   >R >R >R >R >R >R (TILES) @ R> R> R> R> R> R>  -1 0 0 128 1 GFX-COPY ;
\ Tiles across from x to x + w: tile column c, as many as fit, the last cut.
: (TILE-ROW) { c r x y w h | s at -- }
   (TILE) @ TO s  0 TO at
   BEGIN at w < WHILE
      c s *  r s *  s w at - MIN  s h MIN  x at +  y (PIECE)  at s + TO at
   REPEAT ;
: (TILED) { x y w h | s at -- }
   (TILE) @ TO s
   0 0 x y s s (PIECE)  2 s * 0 x w + s - y s s (PIECE)
   0 2 s * x y h + s - s s (PIECE)  2 s * 2 s * x w + s - y h + s - s s (PIECE)
   1 0 x s + y w 2 s * - s (TILE-ROW)  1 2 x s + y h + s - w 2 s * - s (TILE-ROW)
   s TO at
   BEGIN at h s - < WHILE
      0 1 x y at + s  s h s - at - MIN (TILE-ROW)
      2 1 x w + s - y at + s  s h s - at - MIN (TILE-ROW)
      1 1 x s + y at + w 2 s * -  s h s - at - MIN (TILE-ROW)
      at s + TO at
   REPEAT ;
\ A panel: the background of a group of parts, with its border or tiles.
: GUI-PANEL { x y w h -- }
   (TILES) @ IF x y w h (TILED) EXIT THEN
   x y w h GUI-BACKGROUND GUI-BORDER (BORDER-W) @ (BOX) ;
\ Text in the text color (GUI-TEXT), as labels are.
: GUI-LABEL ( addr u x y -- )   GUI-TEXT (TEXT) ;

\ ---- Buttons and check boxes ---------------------------------------------------------

\ The size a button of this text takes.
: GUI-BUTTON-SIZE ( addr u -- w h )   TEXT-WIDTH (PAD-X) 2* + (BORDER-W) @ 2* +  (ROW-H) ;

\ A button at x y; true when it was clicked, or Enter or Space was pressed while it
\ has the focus.
: GUI-BUTTON { addr u x y | w h id f hot clicked face -- flag }
   addr u GUI-BUTTON-SIZE TO h TO w  (NEW-PART) TO id  FALSE TO clicked
   (ENABLED) @ IF
      (FOCUSABLE) TO f
      x y w h (PRESSED-ON) IF  id (ACTIVE) !  f (FOCUS) !  THEN
      (ACTIVE) @ id = IF x y w h (RELEASED-ON) TO clicked THEN
      f (FOCUSED?) IF  13 (TAKE) 32 (TAKE) OR clicked OR TO clicked  THEN
      x y w h (HOT) TO hot
      GUI-FACE  hot IF DROP GUI-HOVER THEN  hot (ACTIVE) @ id = AND IF DROP GUI-PRESSED THEN  TO face
   ELSE  GUI-FACE TO face  0 TO f  THEN
   x y w h face GUI-BORDER (BORDER-W) @ (BOX)
   f (FOCUSED?) IF x y w h (FOCUS-RING) THEN
   addr u  x w addr u TEXT-WIDTH - 2/ +  y (BORDER-W) @ + (PAD-Y) +
   (ENABLED) @ IF GUI-TEXT ELSE GUI-DISABLED THEN (TEXT)
   clicked ;

\ A check box with a label: the flag at addr changes when it is clicked, or Space or
\ Enter was pressed while it has the focus; true when it changed.
: GUI-CHECK { flag-addr addr u x y | s id f changed -- flag }
   TEXT-HEIGHT 2 + (BORDER-W) @ 2* + TO s  (NEW-PART) TO id  FALSE TO changed
   (ENABLED) @ IF
      (FOCUSABLE) TO f
      x y s (PAD-X) + addr u TEXT-WIDTH + s (PRESSED-ON) IF  id (ACTIVE) !  f (FOCUS) !  THEN
      (ACTIVE) @ id = IF x y s (PAD-X) + addr u TEXT-WIDTH + s (RELEASED-ON) TO changed THEN
      f (FOCUSED?) IF  32 (TAKE) 13 (TAKE) OR changed OR TO changed  THEN
      changed IF flag-addr @ 0= flag-addr ! THEN
   ELSE 0 TO f THEN
   x y s s GUI-FIELD-FACE GUI-BORDER (BORDER-W) @ (BOX)
   f (FOCUSED?) IF x y s s (FOCUS-RING) THEN
   flag-addr @ IF
      (ENABLED) @ IF GUI-TEXT ELSE GUI-DISABLED THEN (USE)
      \ The mark: a tick across the box.
      x 3 + (BORDER-W) @ +  y s 2/ +  x s 2/ +  y s + 4 - (BORDER-W) @ -  LINE
      x s 2/ +  y s + 4 - (BORDER-W) @ -  x s + 4 - (BORDER-W) @ -  y 3 + (BORDER-W) @ +  LINE
   THEN
   addr u  x s + (PAD-X) +  y s TEXT-HEIGHT - 2/ +
   (ENABLED) @ IF GUI-TEXT ELSE GUI-DISABLED THEN (TEXT)
   changed ;

\ ---- Text fields --------------------------------------------------------------------

\ The field the keys are going to: its bytes, its room, and its length.
VARIABLE (F-BUF)  VARIABLE (F-MAX)  VARIABLE (F-LEN)

\ Takes the bytes from place `from` to `to` out of the field.
: (F-CUT) { from to -- }
   (F-BUF) @ to +  (F-BUF) @ from +  (F-LEN) @ to - MOVE
   (F-LEN) @ to from - - (F-LEN) ! ;

\ What a key does to the field: whether it used it. Bytes of text (as INKEY gives them,
\ also those of UTF-8) go in at the cursor while there is room.
: (EDIT) { key | c -- flag }
   (CURSOR) @ TO c
   key 8 = IF  c 0> IF  (F-BUF) @ c (BACK)  DUP c (F-CUT)  (CURSOR) !  THEN  TRUE EXIT THEN
   key K-DELETE = IF  c (F-LEN) @ < IF  c  (F-BUF) @ (F-LEN) @ c (FORTH)  (F-CUT)  THEN  TRUE EXIT THEN
   key K-LEFT = IF  (F-BUF) @ c (BACK) (CURSOR) !  TRUE EXIT THEN
   key K-RIGHT = IF  (F-BUF) @ (F-LEN) @ c (FORTH) (CURSOR) !  TRUE EXIT THEN
   key K-HOME = IF  0 (CURSOR) !  TRUE EXIT THEN
   key K-END = IF  (F-LEN) @ (CURSOR) !  TRUE EXIT THEN
   key 32 256 WITHIN key 127 <> AND IF
      (F-LEN) @ (F-MAX) @ < IF
         (F-BUF) @ c +  DUP 1+  (F-LEN) @ c - MOVE
         key (F-BUF) @ c + C!  1 (F-LEN) +!  1 (CURSOR) +!
      THEN  TRUE EXIT
   THEN
   FALSE ;

\ A field of one line of text, w pixels wide, editing the bytes at buf (at most room),
\ whose count is at len-addr. With the focus it takes the keys: text, Backspace,
\ Delete, the arrows, Home, and End. True when Enter was pressed in it.
: GUI-FIELD { buf room len-addr x y w | h id f entered len start inner -- flag }
   (ROW-H) TO h  (NEW-PART) TO id  FALSE TO entered  len-addr @ 0 MAX room MIN TO len
   (ENABLED) @ IF
      (FOCUSABLE) TO f
      x y w h (PRESSED-ON) IF  f (FOCUS) !  THEN
   ELSE 0 TO f THEN
   f (FOCUSED?) IF
      (CURSOR-OF) @ id <> IF  len (CURSOR) !  id (CURSOR-OF) !  THEN
      (CURSOR) @ 0 MAX len MIN (CURSOR) !
      buf (F-BUF) !  room (F-MAX) !  len (F-LEN) !
      \ The keys of the frame, in order; those the field does not use stay for others.
      0 BEGIN DUP (KEY-COUNT) @ < WHILE
         (KEYS) OVER CELLS + @
         DUP 13 = IF  DROP TRUE TO entered TRUE  ELSE (EDIT) THEN
         IF (DROP-KEY) ELSE 1+ THEN
      REPEAT DROP
      (F-LEN) @ TO len  len len-addr !
   THEN
   x y w h GUI-FIELD-FACE GUI-BORDER (BORDER-W) @ (BOX)
   f (FOCUSED?) IF x y w h (FOCUS-RING) THEN
   w (BORDER-W) @ 2* - (PAD-X) 2* - 1- TO inner
   \ The text from where the cursor shows.
   0 TO start
   f (FOCUSED?) IF
      BEGIN buf start + (CURSOR) @ start - TEXT-WIDTH inner > WHILE  buf len start (FORTH) TO start  REPEAT
   THEN
   buf start +  buf start + len start - inner (FIT)
   x (BORDER-W) @ + (PAD-X) +  y (BORDER-W) @ + (PAD-Y) +
   (ENABLED) @ IF GUI-TEXT ELSE GUI-DISABLED THEN (TEXT)
   f (FOCUSED?) IF
      GUI-TEXT (USE)
      x (BORDER-W) @ + (PAD-X) +  buf start + (CURSOR) @ start - TEXT-WIDTH +  y (BORDER-W) @ + 2 +
      OVER  y h + (BORDER-W) @ - 3 -  LINE
   THEN
   entered ;

\ ---- Lists ---------------------------------------------------------------------------

\ A list of items "a|b|c", one under another, w pixels wide (0: as wide as the widest).
\ The cell at var is the chosen item: the mouse over an item chooses it, and with the
\ focus so do the up and down arrows (the gamepad's D-pad too). True when an item was
\ clicked, or Enter or Space was pressed (A on the gamepad).
: GUI-LIST { addr u var x y w | n h id f picked iy -- flag }
   addr u (ITEMS) TO n  (ROW-H) TO h  (NEW-PART) TO id  FALSE TO picked
   w 0= IF  0  n 0 DO addr u I (ITEM) TEXT-WIDTH MAX LOOP  (PAD-X) 2* + TO w  THEN
   var @ 0 MAX n 1- MIN var !
   (ENABLED) @ IF
      (FOCUSABLE) TO f
      n 0 DO
         (MOVED) @ IF  x y I h * + w h (HOT) IF I var ! THEN  THEN
         x y I h * + w h (PRESSED-ON) IF  I var !  id (ACTIVE) !  f (FOCUS) !  THEN
         (ACTIVE) @ id = IF x y I h * + w h (RELEASED-ON) IF  I var !  TRUE TO picked  THEN THEN
      LOOP
      f (FOCUSED?) IF
         BEGIN K-UP (TAKE) WHILE  var @ 1- DUP 0< IF DROP n 1- THEN var !  REPEAT
         BEGIN K-DOWN (TAKE) WHILE  var @ 1+ DUP n >= IF DROP 0 THEN var !  REPEAT
         13 (TAKE) 32 (TAKE) OR picked OR TO picked
      THEN
   ELSE 0 TO f THEN
   n 0 DO
      y I h * + TO iy
      I var @ = (ENABLED) @ AND IF
         GUI-SELECTION (USE)  x iy w h FILL-RECT
         addr u I (ITEM)  x (PAD-X) +  iy (BORDER-W) @ + (PAD-Y) +  GUI-SELECTED-TEXT (TEXT)
      ELSE
         addr u I (ITEM)  x (PAD-X) +  iy (BORDER-W) @ + (PAD-Y) +
         (ENABLED) @ IF GUI-TEXT ELSE GUI-DISABLED THEN (TEXT)
      THEN
   LOOP
   f (FOCUSED?) IF x y w n h * (FOCUS-RING) THEN
   picked ;

\ ---- The menu bar and pull-down menus -------------------------------------------------

\ A bar across the top of the image drawn on with the titles "a|b|c": a click on a title
\ opens its menu, and a click on it again closes it. Gives the open menu, -1 for none;
\ its items come from GUI-MENU right after.
: GUI-MENUBAR { addr u | n h at tw -- open }
   addr u (ITEMS) TO n  (ROW-H) TO h
   0 0 GFX-WIDTH h GUI-BACKGROUND GUI-BACKGROUND 0 (BOX)
   GUI-BORDER (USE)  0 h 1- GFX-WIDTH 1- h 1- LINE
   0 TO at
   n 0 DO
      addr u I (ITEM) TEXT-WIDTH (PAD-X) 2* + TO tw
      at 0 tw h (PRESSED-ON) IF  (MENU-OPEN) @ I = IF -1 ELSE I THEN (MENU-OPEN) !  0 (MENU-ITEM) !  THEN
      \ With a menu open, the mouse over another title opens that one.
      (MENU-OPEN) @ 0< 0= (MENU-OPEN) @ I <> AND IF  at 0 tw h (HOT) IF I (MENU-OPEN) ! 0 (MENU-ITEM) ! THEN  THEN
      (MENU-OPEN) @ I = IF
         at (MENU-X) !
         GUI-SELECTION (USE)  at 0 tw h 1- FILL-RECT
         addr u I (ITEM)  at (PAD-X) +  (BORDER-W) @ (PAD-Y) +  GUI-SELECTED-TEXT (TEXT)
      ELSE
         addr u I (ITEM)  at (PAD-X) +  (BORDER-W) @ (PAD-Y) +  GUI-TEXT (TEXT)
      THEN
      at tw + TO at
   LOOP
   \ The arrows go from menu to menu; Esc closes it.
   (MENU-OPEN) @ 0< 0= IF
      BEGIN K-LEFT (TAKE) WHILE  (MENU-OPEN) @ 1- DUP 0< IF DROP n 1- THEN (MENU-OPEN) ! 0 (MENU-ITEM) !  REPEAT
      BEGIN K-RIGHT (TAKE) WHILE  (MENU-OPEN) @ 1+ DUP n >= IF DROP 0 THEN (MENU-OPEN) ! 0 (MENU-ITEM) !  REPEAT
      27 (TAKE) IF -1 (MENU-OPEN) ! THEN
      \ Its place again, as the titles may have moved it.
      0 TO at
      n 0 DO  (MENU-OPEN) @ I = IF at (MENU-X) ! THEN  addr u I (ITEM) TEXT-WIDTH (PAD-X) 2* + at + TO at  LOOP
   THEN
   (MENU-OPEN) @ ;

\ An item of a pull-down menu: "-" is a line between items, and an item that starts
\ with ~ cannot be chosen.
: (SEPARATOR?) ( addr u -- flag )   S" -" COMPARE 0= ;
: (DISABLED?) ( addr u -- flag )   IF C@ [CHAR] ~ = ELSE DROP FALSE THEN ;
: (ITEM-H) ( addr u -- h )   (SEPARATOR?) IF 5 ELSE (ROW-H) THEN ;

\ The items "a|-|~b|c" of the open menu, under its title: gives the item chosen in this
\ frame by a click or Enter, else -1. A click elsewhere closes the menu. Up and down
\ move between the items that can be chosen.
: GUI-MENU { addr u | n w h iy chosen -- item | -1 }
   -1 TO chosen  (MENU-OPEN) @ 0< IF -1 EXIT THEN
   addr u (ITEMS) TO n
   0  n 0 DO  addr u I (ITEM) DUP IF OVER C@ [CHAR] ~ = IF 1 /STRING THEN THEN TEXT-WIDTH MAX  LOOP
   (PAD-X) 4 * +  (BORDER-W) @ 2* + TO w
   (BORDER-W) @ 2*  n 0 DO addr u I (ITEM) (ITEM-H) + LOOP TO h
   (MENU-X) @ (BX) !  (ROW-H) (BY) !  w (BW) !  h (BH) !
   \ The mouse over an item, a click on it, and the keys.
   (ROW-H) (BORDER-W) @ + TO iy
   n 0 DO
      addr u I (ITEM) 2DUP (SEPARATOR?) >R (DISABLED?) R> OR 0= IF
         (MOVED) @ IF  (MX) @ (MY) @ (MENU-X) @ iy w (ROW-H) (IN) IF I (MENU-ITEM) ! THEN  THEN
         (RELEASE) @ IF (RX) @ (RY) @ (MENU-X) @ iy w (ROW-H) (IN) IF I TO chosen THEN THEN
      THEN
      addr u I (ITEM) (ITEM-H) iy + TO iy
   LOOP
   BEGIN K-UP (TAKE) WHILE  (MENU-ITEM) @  n 0 DO 1- DUP 0< IF DROP n 1- THEN  DUP addr u ROT (ITEM) 2DUP (SEPARATOR?) >R (DISABLED?) R> OR 0= IF LEAVE THEN LOOP  (MENU-ITEM) !  REPEAT
   BEGIN K-DOWN (TAKE) WHILE  (MENU-ITEM) @  n 0 DO 1+ DUP n >= IF DROP 0 THEN  DUP addr u ROT (ITEM) 2DUP (SEPARATOR?) >R (DISABLED?) R> OR 0= IF LEAVE THEN LOOP  (MENU-ITEM) !  REPEAT
   13 (TAKE) IF  addr u (MENU-ITEM) @ (ITEM) 2DUP (SEPARATOR?) >R (DISABLED?) R> OR 0= IF (MENU-ITEM) @ TO chosen THEN  THEN
   \ A press outside the menu and the bar closes it.
   (PRESS) @ IF  (PX) @ (PY) @ (BX) @ (BY) @ (BW) @ (BH) @ (IN)  (PY) @ (ROW-H) < OR 0= IF -1 (MENU-OPEN) ! THEN  THEN
   addr u (PULL) 2!
   chosen 0< 0= IF -1 (MENU-OPEN) ! THEN
   chosen ;

\ The open menu, over the other parts.
: (DRAW-PULL) { | addr u n iy item -- }
   (PULL) 2@ TO u TO addr
   (BX) @ (BY) @ (BW) @ (BH) @ GUI-BACKGROUND GUI-BORDER (BORDER-W) @ (BOX)
   addr u (ITEMS) TO n  (BY) @ (BORDER-W) @ + TO iy
   n 0 DO
      addr u I (ITEM) 2DUP (SEPARATOR?) IF
         2DROP GUI-BORDER (USE)  (BX) @ (PAD-X) +  iy 2 +  (BX) @ (BW) @ + (PAD-X) - 1-  OVER LINE
         iy 5 + TO iy
      ELSE
         2DUP (DISABLED?) IF
            1 /STRING  (BX) @ (BORDER-W) @ + (PAD-X) 2* +  iy (PAD-Y) +  GUI-DISABLED (TEXT)
         ELSE
            I (MENU-ITEM) @ = IF
               GUI-SELECTION (USE)  (BX) @ (BORDER-W) @ +  iy  (BW) @ (BORDER-W) @ 2* -  (ROW-H) FILL-RECT
               (BX) @ (BORDER-W) @ + (PAD-X) 2* +  iy (PAD-Y) +  GUI-SELECTED-TEXT (TEXT)
            ELSE
               (BX) @ (BORDER-W) @ + (PAD-X) 2* +  iy (PAD-Y) +  GUI-TEXT (TEXT)
            THEN
         THEN
         iy (ROW-H) + TO iy
      THEN
   LOOP ;

\ ---- The function key bar --------------------------------------------------------------

\ A bar at the bottom of the image drawn on with the labels "a|b|c" of F1, F2, ...: gives
\ the key, 0 for F1, that was pressed or whose label was clicked in this frame, else -1.
: GUI-FKEYS { addr u | n h y w at key -- n | -1 }
   addr u (ITEMS) TO n  (ROW-H) TO h  GFX-HEIGHT h - TO y  GFX-WIDTH n / TO w  -1 TO key
   0 y GFX-WIDTH h GUI-BACKGROUND GUI-BACKGROUND 0 (BOX)
   GUI-BORDER (USE)  0 y GFX-WIDTH 1- y LINE
   n 0 DO
      I w * TO at
      (MENU-OPEN) @ 0< IF  K-F1 I + (TAKE) IF I TO key THEN  THEN
      at y w h (PRESSED-ON) IF I TO key THEN
      \ The key's number, then its label.
      <# I 1+ 0 #S [CHAR] F HOLD #>  at (PAD-X) +  y (BORDER-W) @ + (PAD-Y) +  GUI-SELECTION (TEXT)
      addr u I (ITEM)  at (PAD-X) + S" F00 " TEXT-WIDTH +  y (BORDER-W) @ + (PAD-Y) +  GUI-TEXT (TEXT)
      I 0> IF GUI-BORDER (USE) at y 2 + at y h + 3 - LINE THEN
   LOOP
   key ;

\ ---- Dialogs --------------------------------------------------------------------------

\ A dialog in the middle of the image drawn on, with a message and the buttons "a|b":
\ gives the button clicked or chosen with Enter in this frame, 0 for the first, else -1.
\ Esc chooses the last. The first button has the focus at first.
: GUI-DIALOG { msg u buttons bu | n bw w h x y at chosen -- n | -1 }
   buttons bu (ITEMS) TO n  -1 TO chosen
   0  n 0 DO buttons bu I (ITEM) GUI-BUTTON-SIZE DROP (PAD-X) + + LOOP  (PAD-X) - TO bw
   msg u TEXT-WIDTH bw MAX  (PAD-X) 4 * +  TO w
   (ROW-H) 2*  TEXT-HEIGHT +  (PAD-X) 3 * +  TO h
   GFX-WIDTH w - 2/ TO x  GFX-HEIGHT h - 2/ TO y
   x y w h GUI-PANEL
   msg u  x w msg u TEXT-WIDTH - 2/ +  y (PAD-X) 2* +  GUI-TEXT (TEXT)
   x w bw - 2/ + TO at
   n 0 DO
      buttons bu I (ITEM)  at  y h + (ROW-H) - (PAD-X) -  GUI-BUTTON IF I TO chosen THEN
      buttons bu I (ITEM) GUI-BUTTON-SIZE DROP (PAD-X) + at + TO at
   LOOP
   27 (TAKE) IF n 1- TO chosen THEN
   chosen ;

\ Yes and No: 1 for yes, 0 for no, -1 while there is no answer.
: GUI-YES-NO ( addr u -- n )   S" Yes|No" GUI-DIALOG  DUP 0< IF EXIT THEN  0= 1 AND ;

\ Ends the GUI of a frame: draws the open menu over the other parts.
: GUI-END ( -- )
   (MENU-OPEN) @ 0< 0= IF  (PULL) 2@ NIP IF (DRAW-PULL) THEN  THEN
   0 0 (PULL) 2!
   (RELEASE) @ IF 0 (ACTIVE) ! THEN
   (FOCUS-N) @ (LAST-FOCUS-N) ! ;

\ ---- Waiting for an answer -----------------------------------------------------------

\ The words below show the screen again each frame until the user answers, over what
\ the screen had when they started, and then put it back. They draw on the screen.
VARIABLE (SAVED)  VARIABLE (WAS-DRAWING)
: (SAVE-SCREEN) ( -- )
   DRAWING (WAS-DRAWING) !  SCREEN DRAW-TO  0 (SAVED) !
   SCREEN IMAGE-SIZE ['] NEW-IMAGE CATCH IF 2DROP EXIT THEN
   DUP (SAVED) !  DRAW-TO  SCREEN 0 0 SCREEN IMAGE-SIZE 0 0 -1 0 0 128 1 GFX-COPY  SCREEN DRAW-TO
   0 (LAST-FOCUS-N) !  0 (FOCUS) ! ;
: (RESTORE-SCREEN) ( -- )
   (SAVED) @ ?DUP IF  0 0 SCREEN IMAGE-SIZE 0 0 -1 0 0 128 1 GFX-COPY  THEN ;
: (END-WAIT) ( -- )
   (RESTORE-SCREEN)  SHOW  (SAVED) @ ?DUP IF FREE-IMAGE THEN  0 (SAVED) !
   (WAS-DRAWING) @ DRAW-TO  0 (LAST-FOCUS-N) !  0 (FOCUS) ! ;
: (NEXT-FRAME) ( -- )   GUI-END SHOW 16 FRAME ;

\ Asks a question with Yes and No and waits: true for yes. Esc answers no.
: GUI-ASK ( addr u -- flag )
   (SAVE-SCREEN)
   BEGIN  (RESTORE-SCREEN) GUI-BEGIN  2DUP GUI-YES-NO  (NEXT-FRAME)  DUP 0< WHILE DROP REPEAT
   NIP NIP  (END-WAIT)  1 = ;
\ Shows a message with OK and waits until it is closed (OK, Enter, or Esc).
: GUI-MESSAGE ( addr u -- )
   (SAVE-SCREEN)
   BEGIN  (RESTORE-SCREEN) GUI-BEGIN  2DUP S" OK" GUI-DIALOG  (NEXT-FRAME)  0< 0= UNTIL
   2DROP (END-WAIT) ;
\ A list "a|b|c" in the middle of the screen: waits for a choice and gives it, 0 for
\ the first, or -1 for Esc.
VARIABLE (CHOICE)
: GUI-CHOOSE { addr u | w h x y chosen -- n }
   0 (CHOICE) !
   0  addr u (ITEMS) 0 DO addr u I (ITEM) TEXT-WIDTH MAX LOOP  (PAD-X) 2* + TO w
   addr u (ITEMS) (ROW-H) * TO h
   GFX-WIDTH w - 2/ TO x  GFX-HEIGHT h - 2/ TO y
   (SAVE-SCREEN)
   BEGIN
      (RESTORE-SCREEN) GUI-BEGIN
      x 4 - y 4 - w 8 + h 8 + GUI-PANEL
      addr u (CHOICE) x y w GUI-LIST IF (CHOICE) @ ELSE -2 THEN TO chosen
      27 (TAKE) IF -1 TO chosen THEN
      (NEXT-FRAME)
   chosen -2 <> UNTIL
   (END-WAIT)  chosen ;
