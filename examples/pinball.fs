\ Wyrm's Delve: a pinball table of a dungeon, with dice, monsters and a dragon, in a window.
\ The table, the pictures, the sounds, the names and the rules are this file's own, made
\ at レモン's request.
\
\   sigma.exe examples/pinball.fs      (in a window; Tk on Linux/macOS)
\
\ Flippers: Z or the left arrow or the left mouse button, and / or the right arrow or
\ the right mouse button. Plunger: hold Space or the down arrow (or a mouse button while
\ the ball waits) and let go. P pauses, R starts again, Q or Esc ends the game.
\
\ The three monsters are the bumpers: each hit rolls for damage. When all three are
\ slain the dragon wakes at the top of the table; slay it to go a floor deeper. The four
\ targets on the left spell RUNE, which lights the chest on the right: hit it for a
\ fireball, double damage for a while. The shrine on the right holds the ball and rolls
\ a d20: 1 is a fumble, 11 and more hit the nearest monster, 20 is an extra ball. The
\ three lanes at the top give a blessing when all are lit. Up the left of the orbit and
\ round to the right scores, and turns the spinner on the way; a fast shot up the bridge
\ on the left brings the ball back to the left flipper and lights the kickback in the
\ left outlane. Experience raises your level, and your level raises your damage.

REQUIRE-GRAPHICS  ALSO GRAPHICS

\ ---- Sound ------------------------------------------------------------------------

: AUDIO-LOADED? ( -- flag )   S" REQUIRE-AUDIO" ['] EVALUATE CATCH  DUP IF NIP NIP THEN  0= ;
[UNDEFINED] NO-SOUND [IF] AUDIO-LOADED? [ELSE] FALSE [THEN] CONSTANT HAS-SOUND

0 CONSTANT S-FLIP   1 CONSTANT S-BUMP   2 CONSTANT S-SLAIN  3 CONSTANT S-DROP
4 CONSTANT S-KICK   5 CONSTANT S-DICE   6 CONSTANT S-LANE   7 CONSTANT S-ROAR

HAS-SOUND [IF]
ALSO AUDIO
11025 CONSTANT S-RATE
CREATE S-WAVE S-RATE ALLOT
VARIABLE HISS-SEED
: HISS-BYTE ( -- n )   HISS-SEED @ 1103515245 * 12345 + DUP HISS-SEED !  16 RSHIFT 255 AND 128 - ;
: SWISH { at n k amp | v -- }
   n 0 DO
      HISS-BYTE v - k * 256 / v + TO v
      v amp * n I - * n / 256 /  S-WAVE at + I + C!
   LOOP ;
: CHIME { at n half amp -- }
   n 0 DO
      I half / 1 AND IF amp ELSE amp NEGATE THEN  n I - * n /
      S-WAVE at + I + DUP C@ DUP 127 > IF 256 - THEN ROT +  -127 MAX 127 MIN  SWAP C!
   LOOP ;
: BLOOP { at n half amp -- }
   n 0 DO
      I half I 16 / + / 1 AND IF amp ELSE amp NEGATE THEN  n I - * n /
      S-WAVE at + I + C!
   LOOP ;
: BLANK-WAVE ( -- )   S-WAVE S-RATE ERASE ;
: KEEP-WAVE ( n k -- )   >R S-WAVE SWAP S-RATE R> SAMPLE ;
: EFFECT ( k -- )   SFX ;
: JINGLE ( c-addr u -- )   PLAY ;
: MAKE-SOUNDS ( -- )
   BLANK-WAVE  0 500 120 180 SWISH                           500 S-FLIP KEEP-WAVE
   BLANK-WAVE  0 900 14 70 BLOOP                             900 S-BUMP KEEP-WAVE
   BLANK-WAVE  0 3000 90 260 SWISH  0 3000 20 40 CHIME      3000 S-SLAIN KEEP-WAVE
   BLANK-WAVE  0 700 9 60 CHIME                              700 S-DROP KEEP-WAVE
   BLANK-WAVE  0 1400 100 240 SWISH                         1400 S-KICK KEEP-WAVE
   BLANK-WAVE  6 0 DO  I 500 * 260 170 220 SWISH  LOOP      3000 S-DICE KEEP-WAVE
   BLANK-WAVE  0 1100 5 50 CHIME  300 800 4 40 CHIME        1100 S-LANE KEEP-WAVE
   BLANK-WAVE  0 9000 40 320 SWISH  0 9000 34 34 CHIME      9000 S-ROAR KEEP-WAVE ;
PREVIOUS
[ELSE]
: EFFECT ( k -- )   DROP ;
: JINGLE ( c-addr u -- )   2DROP ;
: MAKE-SOUNDS ( -- ) ;
[THEN]

\ ---- Numbers -----------------------------------------------------------------------

800 CONSTANT W          \ the image
800 CONSTANT H
560 CONSTANT TW         \ the table; the sheet is to the right of it

VARIABLE SEED
: RND ( n -- 0..n-1 )   SEED @ 6364136223846793005 * 1442695040888963407 +  DUP SEED !  33 RSHIFT  SWAP MOD ;
: NOW ( -- us )   UTIME DROP ;

: MIX1 { a b t -- c }   a 255 t - *  b t *  +  127 +  255 / ;
: MIX-RGB { c1 c2 t -- c }
   c1 16 RSHIFT 255 AND  c2 16 RSHIFT 255 AND  t MIX1  16 LSHIFT
   c1 8 RSHIFT 255 AND   c2 8 RSHIFT 255 AND   t MIX1   8 LSHIFT OR
   c1 255 AND            c2 255 AND            t MIX1  OR ;

: ISQRT { n | v -- r }
   n 2 < IF n EXIT THEN
   n TO v  BEGIN  v n v / + 2/  DUP v < WHILE  TO v  REPEAT DROP  v ;

4096 CONSTANT FX

CREATE QUARTER  0 , 100 , 200 , 297 , 392 , 483 , 569 , 650 , 724 , 792 , 851 , 903 , 946 , 980 , 1004 , 1019 , 1024 ,
: SIN64 { k | s -- v }
   k 63 AND TO k   1 TO s
   k 31 > IF  k 32 - TO k  -1 TO s  THEN
   k 16 > IF  32 k - TO k  THEN
   k CELLS QUARTER + @  s * ;
\ A sine and a cosine of angles of 4096 to the circle, as multiples of FX.
: SINT { a | k fr v0 -- v }
   a 4095 AND TO a   a 64 / TO k   a 63 AND TO fr
   k SIN64 TO v0
   k 1+ SIN64 v0 - fr * 64 / v0 +  4 * ;
: COST ( a -- v )   1024 + SINT ;

\ ---- Sprites ------------------------------------------------------------------------
\ A sprite: an image, its width, and its height. BAKE makes the image from xt
\ ( x y -- rgb | -1 ), which reads the picture painted on the image drawn on; -1 is a
\ hole, kept in the image as KEY-COLOR, which SPR leaves out.

$FF00FE CONSTANT KEY-COLOR

: BAKE { pw ph xt | img old row a -- a }
   pw 1 MAX ph 1 MAX NEW-IMAGE TO img  DRAWING TO old  pw 1 MAX CELLS ALLOCATE THROW TO row
   ph 0 ?DO
      pw 0 ?DO  I J xt EXECUTE  DUP 0< IF DROP KEY-COLOR THEN  row I CELLS + !  LOOP
      img DRAW-TO  pw 0 ?DO  I J row I CELLS + @ GFX-PSET  LOOP  old DRAW-TO
   LOOP
   row FREE THROW
   ALIGN HERE TO a  img , pw , ph ,  a ;

: SPR-W ( a -- w )   CELL+ @ ;
: SPR-H ( a -- h )   2 CELLS + @ ;
: SPR { x y a -- }   a @ 0 0 a SPR-W a SPR-H x y KEY-COLOR 0 0 128 1 GFX-COPY ;
: CENTERED { cx cy a -- }   cx a SPR-W 2/ -  cy a SPR-H 2/ -  a SPR ;

\ ---- Painting tools ----------------------------------------------------------------
\ Pictures are painted larger than they are shown, in units of 64 to CS pixels.

$E0CFA8 CONSTANT C-PAPER    $3E2412 CONSTANT C-INK    $7A5A38 CONSTANT C-FADED
$14121C CONSTANT C-DARK     $F0C060 CONSTANT C-GOLD

3 VALUE ZOOM
64 VALUE CS
: SCALED ( n -- n' )   CS ZOOM * *  64 / ;
: >CANVAS ( x y -- cx cy )   SCALED SWAP SCALED SWAP ;
: INK ( rgb -- )   COLOR! ;
: CANVAS-PX ( x y -- rgb | -1 )   GFX-PGET  DUP KEY-COLOR = IF DROP -1 THEN ;

CREATE PTS 32 2* CELLS ALLOT   VARIABLE #PTS
: [P ( -- )   0 #PTS ! ;
: DV ( x y -- )   >CANVAS  PTS #PTS @ 2* CELLS + 2!  1 #PTS +! ;
: PT@ ( n -- x y )   2* CELLS PTS + 2@ ;
VARIABLE ROW-LO   VARIABLE ROW-HI
: ROW-HIT ( x -- )   DUP ROW-LO @ MIN ROW-LO !  ROW-HI @ MAX ROW-HI ! ;
: EDGE { y x0 y0 x1 y1 -- }
   y y0 y1 MIN < IF EXIT THEN   y y0 y1 MAX > IF EXIT THEN
   y0 y1 = IF  x0 ROW-HIT  x1 ROW-HIT  EXIT THEN
   y y0 - x1 x0 - *  y1 y0 - /  x0 +  ROW-HIT ;
: P] { | top bot -- }
   99999 TO top  -99999 TO bot
   #PTS @ 0 DO  I PT@ NIP DUP top MIN TO top  bot MAX TO bot  LOOP
   bot 1+ top DO
      99999 ROW-LO !  -99999 ROW-HI !
      #PTS @ 0 DO  J  I PT@  I 1+ #PTS @ MOD PT@  EDGE  LOOP
      ROW-HI @ ROW-LO @ >= IF  ROW-LO @ ROW-HI @ I COLOR@ GFX-HLINE  THEN
   LOOP ;
: BOX { x1 y1 x2 y2 -- }   [P x1 y1 DV x2 y1 DV x2 y2 DV x1 y2 DV P] ;
: DISC ( x y r -- )   >R >CANVAS R> SCALED FILL-CIRCLE ;
\ A bar with round ends, in canvas units of the painting.
: BAR { x0 y0 x1 y1 r | dx dy d nx ny -- }
   x1 x0 - TO dx   y1 y0 - TO dy
   dx dx * dy dy * + ISQRT 1 MAX TO d
   dy NEGATE r * d / TO nx   dx r * d / TO ny
   [P x0 nx + y0 ny + DV  x1 nx + y1 ny + DV  x1 nx - y1 ny - DV  x0 nx - y0 ny - DV P]
   x0 y0 r DISC   x1 y1 r DISC ;

: ART-PX { x y | r g b n v -- rgb | -1 }
   x ZOOM * ZOOM 2/ +  y ZOOM * ZOOM 2/ +  GFX-PGET KEY-COLOR = IF -1 EXIT THEN
   ZOOM 0 DO ZOOM 0 DO
      x ZOOM * I +  y ZOOM * J +  GFX-PGET TO v
      v KEY-COLOR <> IF
         v 16 RSHIFT 255 AND r + TO r
         v 8 RSHIFT 255 AND g + TO g
         v 255 AND b + TO b
         n 1+ TO n
      THEN
   LOOP LOOP
   r n / 16 LSHIFT  g n / 8 LSHIFT OR  b n / OR ;
: ART-BEGIN ( side -- )   TO CS  KEY-COLOR GFX-CLS ;
: ART-DONE ( -- spr )   CS CS ['] ART-PX BAKE ;

: USE-FONT ( height -- )
   >R S" Georgia" R@ ['] SYSTEM-FONT CATCH
   IF  2DROP DROP  BUILTIN-FONT  R> 8 / 1 MAX TEXT-SCALE
   ELSE  R> DROP  1 TEXT-SCALE  THEN ;
: USE-PLAIN ( height -- )
   >R S" Segoe UI Semibold" R@ ['] SYSTEM-FONT CATCH
   IF  2DROP DROP  BUILTIN-FONT  R> 8 / 1 MAX TEXT-SCALE
   ELSE  R> DROP  1 TEXT-SCALE  THEN ;
: DIGIT$ ( n -- c-addr 1 )   S" 0123456789" DROP + 1 ;

: TEXT-SPRITE { a u fg bg | pw ph -- spr }
   a u TEXT-WIDTH TO pw   TEXT-HEIGHT TO ph
   bg GFX-CLS  fg INK  a u 0 0 TEXT
   pw ph ['] CANVAS-PX BAKE ;
: PAPER ( a u -- spr )   C-INK C-PAPER TEXT-SPRITE ;
: FADED ( a u -- spr )   C-FADED C-PAPER TEXT-SPRITE ;

\ ---- The table: its walls ----------------------------------------------------------
\ Positions and speeds are multiples of FX; speeds are per step, 8 steps to a frame.

8 CONSTANT SUBSTEPS
9 FX * CONSTANT BALL-R
2 FX * CONSTANT WALL-R
16 CONSTANT GRAVITY

0 CONSTANT K-WALL    1 CONSTANT K-SLING   2 CONSTANT K-GATE   3 CONSTANT K-CHEST   4 CONSTANT K-OW       \ K-OW lets the ball pass one way
5 CONSTANT K-DROP    \ 5 to 8 the four targets

240 CONSTANT MAX-SEGS
10 CONSTANT SEG-CELLS
CREATE SEGS MAX-SEGS SEG-CELLS * CELLS ALLOT    VARIABLE #SEGS
\ x0 y0 ux uy length xlo ylo xhi yhi kind
: SEG[] ( n -- a )   SEG-CELLS * CELLS SEGS + ;

: ADD-SEG { x0 y0 x1 y1 kind | a dx dy d m -- }
   #SEGS @ SEG[] TO a
   x1 x0 - TO dx   y1 y0 - TO dy
   dx dx * dy dy * + ISQRT 1 MAX TO d
   BALL-R WALL-R + 4096 + TO m
   x0 a !   y0 a CELL+ !
   dx FX * d /  a 2 CELLS + !    dy FX * d /  a 3 CELLS + !
   d a 4 CELLS + !
   x0 x1 MIN m -  a 5 CELLS + !   y0 y1 MIN m -  a 6 CELLS + !
   x0 x1 MAX m +  a 7 CELLS + !   y0 y1 MAX m +  a 8 CELLS + !
   kind a 9 CELLS + !
   1 #SEGS +! ;
: LN { x0 y0 x1 y1 kind -- }   x0 FX * y0 FX * x1 FX * y1 FX * kind ADD-SEG ;

: ARC { cx cy r a0 a1 n kind -- }
   n 0 DO
      a1 a0 - I * n / a0 + { p }
      a1 a0 - I 1+ * n / a0 + { q }
      cx FX * r p COST * +   cy FX * r p SINT * +
      cx FX * r q COST * +   cy FX * r q SINT * +
      kind ADD-SEG
   LOOP ;

: MIRROR ( x -- x' )   528 SWAP - ;
: LN2 { x0 y0 x1 y1 kind -- }      \ a line and its mirror image about the middle of the field
   x0 y0 x1 y1 kind LN   x0 MIRROR y0 x1 MIRROR y1 kind LN ;

: BUILD-WALLS ( -- )
   0 #SEGS !
   281 281 257 2048 4096 32 K-WALL ARC
   24 281 24 812 K-WALL LN
   538 281 538 812 K-WALL LN
   504 235 504 812 K-WALL LN
   504 776 538 776 K-WALL LN            \ the plunger's stop
   504 235 504 153 K-GATE LN
   \ the orbit: an inner wall on each side, with the way along the outer wall between
   281 281 223 2162 2560 8 K-WALL ARC
   281 281 223 3413 3732 6 K-WALL ARC
   99 99 123 123 K-OW LN                 \ up the left of the orbit only
   \ the rails beside the flippers
   58 600 58 636 K-WALL LN2
   58 636 164 692 K-WALL LN2
   \ the slingshots
   128 560 128 625 K-WALL LN2
   128 625 188 668 K-WALL LN2
   128 560 188 668 K-SLING LN2
   \ the rune bank
   34 310 34 470 K-WALL LN
   24 295 48 315 K-WALL LN
   48 465 24 490 K-WALL LN
   4 0 DO  48 320 I 37 * +  48 351 I 37 * +  K-DROP I + LN  LOOP
   \ the chest
   480 296 464 356 K-CHEST LN
   504 280 480 296 K-WALL LN
   464 356 504 380 K-WALL LN ;

\ ---- The ball, the flippers and the rest of what moves ------------------------------

VARIABLE BX   VARIABLE BY   VARIABLE VX   VARIABLE VY
VARIABLE NX   VARIABLE NY   VARIABLE LAST-VN   VARIABLE LAST-T
VARIABLE FLIP-W   VARIABLE FLIP-SIN   VARIABLE FLIP-COS   VARIABLE FLIP-MIR

0 CONSTANT B-LANE   1 CONSTANT B-ROLL   2 CONSTANT B-HOLD   3 CONSTANT B-RAMP
VARIABLE BSTATE    VARIABLE LANE-OPEN

\ Flippers: 0 left, 1 right. The angle is 0 level, positive down.
70 FX * CONSTANT FLIP-LEN
273 CONSTANT ANG-REST
-319 CONSTANT ANG-UP
26 CONSTANT FLIP-SPEED
CREATE FL-ANG 2 CELLS ALLOT
CREATE FL-DELTA 2 CELLS ALLOT
CREATE FL-HELD 2 CELLS ALLOT
: PIVOT-X ( n -- fx )   IF 353 ELSE 175 THEN FX * ;
: PIVOT-Y ( n -- fx )   DROP 716 FX * ;
: MIR-OF ( n -- m )   IF -1 ELSE 1 THEN ;

\ The contact: pushes the ball out, reflects its speed against a moving surface.
: RESOLVE { px py d r e pvx pvy | vn imp -- }
   d 0= IF  0 NX !  FX NEGATE NY !
   ELSE  px FX * d / NX !   py FX * d / NY !  THEN
   r d - NX @ * FX / BX +!
   r d - NY @ * FX / BY +!
   VX @ pvx - NX @ *  VY @ pvy - NY @ * +  FX /  TO vn
   vn LAST-VN !
   vn 0< IF
      vn FX e + * FX /  TO imp
      imp NX @ * FX / NEGATE VX +!
      imp NY @ * FX / NEGATE VY +!
   THEN ;

: HIT-LINE { x0 y0 ux uy len r e | rx ry t cx cy dx dy d2 pv pvx pvy -- hit? }
   BX @ x0 - TO rx   BY @ y0 - TO ry
   rx ux *  ry uy * + FX / TO t
   t 0 MAX len MIN TO t
   x0 ux t * FX / + TO cx
   y0 uy t * FX / + TO cy
   BX @ cx - TO dx    BY @ cy - TO dy
   dx dx *  dy dy * + TO d2
   d2 r r * >= IF FALSE EXIT THEN
   t LAST-T !
   FLIP-W @ IF
      t FLIP-W @ * FX / TO pv
      FLIP-MIR @ NEGATE FLIP-SIN @ * pv * FX / TO pvx
      FLIP-COS @ pv * FX / TO pvy
   THEN
   dx dy d2 ISQRT r e pvx pvy RESOLVE
   TRUE ;

: HIT-CIRCLE { cx cy cr e | dx dy r d2 -- hit? }
   BX @ cx - TO dx   BY @ cy - TO dy
   cr BALL-R + TO r
   dx ABS r >= IF FALSE EXIT THEN
   dy ABS r >= IF FALSE EXIT THEN
   dx dx * dy dy * + TO d2
   d2 r r * >= IF FALSE EXIT THEN
   dx dy d2 ISQRT r e 0 0 RESOLVE
   TRUE ;

: KICK ( k -- )  { k }  NX @ k * FX / VX +!   NY @ k * FX / VY +! ;

\ ---- The dungeon: what the game keeps -----------------------------------------------

0 CONSTANT M-TITLE   1 CONSTANT M-PLAY   2 CONSTANT M-OVER
VARIABLE GMODE   VARIABLE DONE   VARIABLE PAUSED   VARIABLE CLOCK
VARIABLE SCORE   VARIABLE BEST   VARIABLE BALLS    VARIABLE FLOOR-NO
VARIABLE LEVEL   VARIABLE XP     VARIABLE NEXT-XP
VARIABLE SAFE-T  VARIABLE SPELL-T  VARIABLE STILL-T
VARIABLE CHARGE  VARIABLE LOCK-INPUT
VARIABLE IN-L    VARIABLE IN-R     VARIABLE IN-P
VARIABLE WAS-P   VARIABLE SHIELD-OK

3 CONSTANT #MON
CREATE MON-HP   #MON CELLS ALLOT
CREATE MON-MAX  #MON CELLS ALLOT
CREATE MON-COOL #MON CELLS ALLOT
CREATE MON-FLASH #MON CELLS ALLOT
CREATE MON-X  175 , 353 , 264 ,
CREATE MON-Y  250 , 250 , 335 ,
25 FX * CONSTANT MON-R
VARIABLE DRAGON-HP   VARIABLE DRAGON-MAX   VARIABLE DRAGON-ON   VARIABLE DRAGON-COOL   VARIABLE DRAGON-FLASH
264 FX * CONSTANT DRAGON-X
158 FX * CONSTANT DRAGON-Y
34 FX * CONSTANT DRAGON-R

CREATE RUNE-UP  4 CELLS ALLOT
VARIABLE RUNE-RESET   VARIABLE CHEST-LIT   VARIABLE CHEST-COOL  VARIABLE SLING-COOL
CREATE LANE-LIT 3 CELLS ALLOT   CREATE LANE-IN 3 CELLS ALLOT
CREATE LANE-X  190 , 264 , 338 ,
105 CONSTANT LANE-Y
VARIABLE SHRINE-COOL   VARIABLE HOLD-T   VARIABLE DIE-FACE   VARIABLE DIE-SHOW

: POSTS-X ( n -- x )   IF 301 ELSE 227 THEN ;
100 CONSTANT POST-Y
6 FX * CONSTANT POST-R
430 CONSTANT SHRINE-X
420 CONSTANT SHRINE-Y

\ Floating damage.
8 CONSTANT #FLOAT
CREATE POPUPS #FLOAT 4 * CELLS ALLOT     \ x y life n
VARIABLE NEXT-FLOAT
: FLOAT[] ( n -- a )   4 * CELLS POPUPS + ;
: ADD-FLOAT { x y n | a -- }
   NEXT-FLOAT @ FLOAT[] TO a
   x a !  y a CELL+ !  40 a 2 CELLS + !  n a 3 CELLS + !
   NEXT-FLOAT @ 1+ #FLOAT MOD NEXT-FLOAT ! ;

\ Sparks.
64 CONSTANT #SPARKS
CREATE SPARKS #SPARKS 6 * CELLS ALLOT
VARIABLE NEXT-SPARK
: SPARK[] ( n -- a )   6 * CELLS SPARKS + ;
: SPARK { x y dx dy life c | a -- }
   NEXT-SPARK @ SPARK[] TO a
   x 16 * a !  y 16 * a CELL+ !  dx a 2 CELLS + !  dy a 3 CELLS + !  life a 4 CELLS + !  c a 5 CELLS + !
   NEXT-SPARK @ 1+ #SPARKS MOD NEXT-SPARK ! ;
: BURST { x y n spread c -- }
   n 0 DO
      x y  spread 2* 1+ RND spread -  spread 2* 1+ RND spread -  14 20 RND +  c SPARK
   LOOP ;

\ The messages on the sheet.
24 CONSTANT #MSG
CREATE MSG-ART #MSG CELLS ALLOT   VARIABLE MSG-NOW   VARIABLE MSG-T
0 CONSTANT TX-ENTER     1 CONSTANT TX-GOBLIN   2 CONSTANT TX-SKELETON  3 CONSTANT TX-ORC
4 CONSTANT TX-WAKES     5 CONSTANT TX-DRAGON   6 CONSTANT TX-LEVEL     7 CONSTANT TX-RUNE
8 CONSTANT TX-CHEST     9 CONSTANT TX-FIRE    10 CONSTANT TX-FUMBLE   11 CONSTANT TX-MISS
12 CONSTANT TX-HIT     13 CONSTANT TX-CRIT    14 CONSTANT TX-BLESS    15 CONSTANT TX-SHIELD
16 CONSTANT TX-LOST    17 CONSTANT TX-ROLL    18 CONSTANT TX-DEEPER
19 CONSTANT TX-ORBIT   20 CONSTANT TX-RAMP    21 CONSTANT TX-KICK
: MSG$ ( n -- a u )
   CASE
      TX-ENTER OF S" You enter the dungeon." ENDOF
      TX-GOBLIN OF S" The goblin is slain!" ENDOF
      TX-SKELETON OF S" The skeleton falls apart!" ENDOF
      TX-ORC OF S" The orc is slain!" ENDOF
      TX-WAKES OF S" The dragon awakes!" ENDOF
      TX-DRAGON OF S" The dragon is slain!" ENDOF
      TX-LEVEL OF S" You gain a level!" ENDOF
      TX-RUNE OF S" RUNE: the chest glows." ENDOF
      TX-CHEST OF S" In the chest: a fireball!" ENDOF
      TX-FIRE OF S" The fireball fades." ENDOF
      TX-FUMBLE OF S" A one: you fumble!" ENDOF
      TX-MISS OF S" Your blow misses." ENDOF
      TX-HIT OF S" A solid hit!" ENDOF
      TX-CRIT OF S" Twenty! An extra ball!" ENDOF
      TX-BLESS OF S" The lanes bless you." ENDOF
      TX-SHIELD OF S" The shield saves you." ENDOF
      TX-LOST OF S" You fall into the dark." ENDOF
      TX-ROLL OF S" Roll the die..." ENDOF
      TX-DEEPER OF S" Deeper you go..." ENDOF
      TX-ORBIT OF S" You circle the chamber." ENDOF
      TX-RAMP OF S" Across the bridge!" ENDOF
      TX-KICK OF S" A rope pulls you back." ENDOF
      S" " ROT
   ENDCASE ;
: SAY ( n -- )   MSG-NOW !  240 MSG-T ! ;

: +SCORE ( n -- )   SCORE +! ;
: LEVEL-UP ( -- )
   1 LEVEL +!
   LEVEL @ DUP * 60 * NEXT-XP +!
   TX-LEVEL SAY
   S" T180 L16 O5 CEGC>" JINGLE ;
: +XP ( n -- )
   XP +!
   BEGIN XP @ NEXT-XP @ >= WHILE LEVEL-UP REPEAT ;

: RESET-MONSTERS ( -- )
   #MON 0 DO
      6 I 3 * +  FLOOR-NO @ 1- 3 * +  DUP I CELLS MON-HP + !  I CELLS MON-MAX + !
   LOOP
   FALSE DRAGON-ON !  24 FLOOR-NO @ 12 * +  DUP DRAGON-HP !  DRAGON-MAX ! ;
: RESET-RUNES ( -- )   4 0 DO  TRUE RUNE-UP I CELLS + !  LOOP  0 RUNE-RESET ! ;

: DAMAGE ( -- n )     \ the roll, with level and fireball
   6 RND 1+  LEVEL @ 1- 2/ +   SPELL-T @ 0> IF 2* THEN ;

: MON-DEAD? ( n -- f )   CELLS MON-HP + @ 1 < ;
: ALL-DEAD? ( -- f )   #MON 0 DO  I MON-DEAD? 0= IF FALSE UNLOOP EXIT THEN  LOOP  TRUE ;

: SLAIN { n | px py -- }
   TX-GOBLIN n + SAY
   n 1+ 1000 * FLOOR-NO @ * +SCORE
   n 2 + 10 * +XP
   S-SLAIN EFFECT
   n CELLS MON-X + @ TO px   n CELLS MON-Y + @ TO py
   px py 20 30 $E0A060 BURST
   ALL-DEAD? IF
      TRUE DRAGON-ON !  TX-WAKES SAY  S-ROAR EFFECT
   THEN ;

: HURT-MON { n amount -- }
   n MON-DEAD? IF EXIT THEN
   amount NEGATE n CELLS MON-HP + +!
   n CELLS MON-X + @  n CELLS MON-Y + @  30 -  amount ADD-FLOAT
   12 n CELLS MON-FLASH + !
   n MON-DEAD? IF n SLAIN THEN ;

: NEXT-DEPTH ( -- )
   1 FLOOR-NO +!
   RESET-MONSTERS  RESET-RUNES
   TX-DEEPER SAY ;

: HURT-DRAGON { amount -- }
   DRAGON-ON @ 0= IF EXIT THEN
   amount NEGATE DRAGON-HP +!
   264 130 amount ADD-FLOAT
   12 DRAGON-FLASH !
   DRAGON-HP @ 1 < IF
      TX-DRAGON SAY
      FLOOR-NO @ 50000 * +SCORE
      200 +XP
      264 158 50 60 $FFB040 BURST
      S-ROAR EFFECT
      NEXT-DEPTH
   THEN ;

: CHIP-NEAREST ( amount -- )     \ the d20's blow goes to the first monster alive, or the dragon
   #MON 0 DO
      I MON-DEAD? 0= IF  I SWAP HURT-MON  UNLOOP EXIT  THEN
   LOOP
   HURT-DRAGON ;

: BUMP-MON { n -- }
   n CELLS MON-COOL + @ 0> IF EXIT THEN
   8 n CELLS MON-COOL + !
   3584 KICK
   100 FLOOR-NO @ * +SCORE
   S-BUMP EFFECT
   n DAMAGE HURT-MON
   1 +XP ;

: RUNE-HIT { n -- }
   RUNE-UP n CELLS + @ 0= IF EXIT THEN
   FALSE RUNE-UP n CELLS + !
   250 +SCORE  2 +XP
   S-DROP EFFECT
   4 0 DO  RUNE-UP I CELLS + @ IF UNLOOP EXIT THEN  LOOP
   TX-RUNE SAY  TRUE CHEST-LIT !  5000 +SCORE  20 +XP  120 RUNE-RESET ! ;

: CHEST-HIT ( -- )
   CHEST-COOL @ 0> IF EXIT THEN
   30 CHEST-COOL !
   CHEST-LIT @ IF
      FALSE CHEST-LIT !
      TX-CHEST SAY  900 SPELL-T !
      10000 +SCORE  30 +XP
      S-SLAIN EFFECT
      470 326 20 30 $F0C030 BURST
   ELSE
      100 +SCORE  S-DROP EFFECT
   THEN ;

: LANE-HIT { n -- }
   LANE-LIT n CELLS + @ 0= IF
      TRUE LANE-LIT n CELLS + !
      500 +SCORE  S-LANE EFFECT  1 +XP
   THEN
   3 0 DO  LANE-LIT I CELLS + @ 0= IF UNLOOP EXIT THEN  LOOP
   TX-BLESS SAY  3000 +SCORE  15 +XP
   3 0 DO  FALSE LANE-LIT I CELLS + !  LOOP ;

\ ---- Collision of one step ----------------------------------------------------------

: DROP-ACTIVE? ( kind -- f )   K-DROP - CELLS RUNE-UP + @ ;

: ON-SEG { kind -- }
   kind K-SLING = IF
      LAST-VN @ -1200 < SLING-COOL @ 0= AND IF
         2800 KICK  50 +SCORE  8 SLING-COOL !  S-KICK EFFECT
      THEN EXIT
   THEN
   kind K-CHEST = IF  LAST-VN @ -300 < IF CHEST-HIT THEN  EXIT  THEN
   kind K-DROP >= IF  LAST-VN @ -300 < IF  kind K-DROP - RUNE-HIT  THEN  EXIT  THEN ;

: TEST-SEGS ( -- )
   #SEGS @ 0 DO
      I SEG[] { a }
      BX @ a 5 CELLS + @ >  BX @ a 7 CELLS + @ < AND
      BY @ a 6 CELLS + @ > AND  BY @ a 8 CELLS + @ < AND IF
         a 9 CELLS + @ { kind }
         kind K-GATE = LANE-OPEN @ AND
         kind K-OW = IF  VX @ VY @ - 0> OR  THEN
         kind K-DROP >= IF  kind DROP-ACTIVE? 0= OR  THEN
         0= IF
            a @  a CELL+ @  a 2 CELLS + @  a 3 CELLS + @  a 4 CELLS + @
            BALL-R WALL-R +  1720  HIT-LINE IF  kind ON-SEG  THEN
         THEN
      THEN
   LOOP ;

: TEST-MONSTERS ( -- )
   #MON 0 DO
      I CELLS MON-X + @ FX *  I CELLS MON-Y + @ FX *  MON-R  1200  HIT-CIRCLE IF  I BUMP-MON  THEN
   LOOP ;

: TEST-POSTS ( -- )
   2 0 DO
      I POSTS-X FX *  POST-Y FX *  POST-R  2000  HIT-CIRCLE DROP
   LOOP ;

: TEST-DRAGON ( -- )
   DRAGON-ON @ 0= IF EXIT THEN
   DRAGON-X DRAGON-Y DRAGON-R  1600  HIT-CIRCLE IF
      DRAGON-COOL @ 0= IF
         10 DRAGON-COOL !
         2400 KICK
         500 FLOOR-NO @ * +SCORE
         S-BUMP EFFECT
         8 RND 1+ LEVEL @ 1- + SPELL-T @ 0> IF 2* THEN HURT-DRAGON
      THEN
   THEN ;

: STEP-FLIPPER { n | a d -- }
   n CELLS FL-ANG + @ TO a
   n CELLS FL-HELD + @ IF
      a FLIP-SPEED - ANG-UP MAX
   ELSE
      a FLIP-SPEED 3 * 4 / + ANG-REST MIN
   THEN
   DUP a - n CELLS FL-DELTA + !
   n CELLS FL-ANG + ! ;

: TEST-FLIPPER { n | a s c mir -- }
   n CELLS FL-ANG + @ TO a
   a SINT TO s   a COST TO c
   n MIR-OF TO mir
   s FLIP-SIN !  c FLIP-COS !  mir FLIP-MIR !
   n CELLS FL-DELTA + @ 6283 * 1000 / FLIP-W !
   n PIVOT-X  n PIVOT-Y  mir c *  s  FLIP-LEN  BALL-R 7 FX * +  2048  HIT-LINE DROP
   0 FLIP-W ! ;

: CLAMP-SPEED { | s2 s -- }
   VX @ DUP * VY @ DUP * + TO s2
   s2 15000 15000 * > IF
      s2 ISQRT TO s
      VX @ 15000 * s / VX !
      VY @ 15000 * s / VY !
   THEN ;

: STEP-BALL ( -- )
   GRAVITY VY +!
   VX @ BX +!  VY @ BY +!
   TEST-SEGS  TEST-POSTS  TEST-MONSTERS  TEST-DRAGON
   0 TEST-FLIPPER  1 TEST-FLIPPER
   CLAMP-SPEED ;

: STEP-PHYSICS ( -- )
   SUBSTEPS 0 DO
      0 STEP-FLIPPER  1 STEP-FLIPPER
      BSTATE @ DUP B-HOLD <> SWAP B-RAMP <> AND IF  STEP-BALL  THEN
   LOOP ;

\ ---- Once a frame -------------------------------------------------------------------

: SENSOR-X ( -- x )   BX @ FX / ;
: SENSOR-Y ( -- y )   BY @ FX / ;

: CHECK-LANES ( -- )
   3 0 DO
      SENSOR-X I CELLS LANE-X + @ - ABS 13 <
      SENSOR-Y LANE-Y - ABS 14 < AND IF
         LANE-IN I CELLS + @ 0= IF  I LANE-HIT  THEN
         TRUE LANE-IN I CELLS + !
      ELSE
         FALSE LANE-IN I CELLS + !
      THEN
   LOOP ;

\ Lines the ball crosses, tested once a frame.
VARIABLE PREV-X   VARIABLE PREV-Y
: SIDE { x0 y0 x1 y1 px py -- n }   x1 x0 - py y0 - *  y1 y0 - px x0 - *  - ;
: CROSSED? { x0 y0 x1 y1 | dx dy t -- flag }
   x1 x0 - TO dx   y1 y0 - TO dy
   BX @ FX / x0 - dx *  BY @ FX / y0 - dy * + TO t
   t 0<  t dx dx * dy dy * + > OR IF FALSE EXIT THEN
   x0 y0 x1 y1 PREV-X @ FX / PREV-Y @ FX / SIDE 0<
   x0 y0 x1 y1 BX @ FX / BY @ FX / SIDE 0<  <> ;
: SPEED-MAX ( -- n )   VX @ ABS VY @ ABS MAX ;

\ The orbit: up the left side, then along the top and past the right side.
VARIABLE ORBIT-T
: CHECK-ORBIT ( -- )
   BSTATE @ B-ROLL <> IF EXIT THEN
   ORBIT-T @ 0> IF -1 ORBIT-T +! THEN
   99 99 123 123 CROSSED? IF  180 ORBIT-T !  THEN
   ORBIT-T @ 0> IF
      392 88 409 59 CROSSED? IF
         0 ORBIT-T !
         2000 FLOOR-NO @ * +SCORE  5 +XP
         TX-ORBIT SAY  S-LANE EFFECT
      THEN
   THEN ;

\ The spinner, across the left of the orbit: as many turns as the ball gave it.
VARIABLE SPIN-A   VARIABLE SPIN-V
: CHECK-SPIN ( -- )
   BSTATE @ B-ROLL <> IF EXIT THEN
   79 187 48 172 CROSSED? IF  SPEED-MAX 8 * FX / SPIN-V @ MAX SPIN-V !  THEN ;
: STEP-SPIN { | before -- }
   SPIN-V @ 0= IF EXIT THEN
   SPIN-A @ 64 / TO before
   SPIN-V @ 3 * SPIN-A +!
   SPIN-A @ 64 / before <> IF
      100 FLOOR-NO @ * +SCORE
      S-DROP EFFECT
   THEN
   CLOCK @ 3 MOD 0= IF  -1 SPIN-V +!  THEN ;

\ The ramp: a bridge on the left, above the floor. On it the ball follows the bridge.
10 CONSTANT #RAMP
CREATE RAMP-X  205 , 170 , 140 , 118 ,  92 ,  72 ,  68 ,  78 ,  88 ,  92 ,
CREATE RAMP-Y  481 , 440 , 390 , 345 , 328 , 345 , 400 , 470 , 540 , 590 ,
CREATE RAMP-LEN #RAMP CELLS ALLOT      \ of the part after each point, times FX
VARIABLE RAMP-S   VARIABLE RAMP-V   VARIABLE KICK-LIT
: RAMP-PX ( n -- x y )   DUP CELLS RAMP-X + @  SWAP CELLS RAMP-Y + @ ;
: BUILD-RAMP { | dx dy -- }
   #RAMP 1- 0 DO
      I 1+ RAMP-PX  I RAMP-PX  ROT SWAP - TO dy  - TO dx
      dx dx * dy dy * + ISQRT FX *  RAMP-LEN I CELLS + !
   LOOP ;
: PLACE-ON-RAMP ( -- )        \ puts the ball where RAMP-S says
   RAMP-S @
   #RAMP 1- 0 DO
      DUP I CELLS RAMP-LEN + @ < IF
         { s }
         I RAMP-PX  I 1+ RAMP-PX { x0 y0 x1 y1 }
         I CELLS RAMP-LEN + @ { d }
         x0 FX *  x1 x0 - FX * s d */ +  BX !
         y0 FX *  y1 y0 - FX * s d */ +  BY !
         UNLOOP EXIT
      THEN
      I CELLS RAMP-LEN + @ -
   LOOP DROP ;
: OFF-RAMP ( -- )
   B-ROLL BSTATE !
   92 FX * BX !  590 FX * BY !
   0 VX !  3000 VY !
   TRUE KICK-LIT !
   1500 FLOOR-NO @ * +SCORE  10 +XP
   TX-RAMP SAY  S-LANE EFFECT ;
: RAMP-END ( -- n )   0  #RAMP 1- 0 DO  I CELLS RAMP-LEN + @ +  LOOP ;
: STEP-RAMP ( -- )
   RAMP-V @ RAMP-S +!
   RAMP-S @ RAMP-END >= IF  OFF-RAMP  EXIT  THEN
   PLACE-ON-RAMP ;
: CHECK-RAMP ( -- )
   BSTATE @ B-ROLL <> IF EXIT THEN
   VY @ 0< NOT IF EXIT THEN
   SPEED-MAX 3600 < IF EXIT THEN
   180 500 230 462 CROSSED? IF
      B-RAMP BSTATE !
      0 RAMP-S !   3 FX * RAMP-V !
      0 VX !  0 VY !
      S-KICK EFFECT
   THEN ;

\ The kickback, in the left outlane, once until the ramp lights it again.
: CHECK-KICK ( -- )
   BSTATE @ B-ROLL <>  KICK-LIT @ 0= OR IF EXIT THEN
   VY @ 0< IF EXIT THEN
   BX @ 58 FX * >= IF EXIT THEN
   BY @ 700 FX * <  BY @ 735 FX * > OR IF EXIT THEN
   FALSE KICK-LIT !
   40 FX * BX !  700 FX * BY !
   1300 VX !   13000 NEGATE VY !
   S-KICK EFFECT
   TX-KICK SAY
   41 720 16 22 $F0C030 BURST ;

: ROLL-FACE ( -- )   20 RND 1+ DIE-FACE ! ;

: ENTER-SHRINE ( -- )
   B-HOLD BSTATE !
   SHRINE-X FX * BX !   SHRINE-Y FX * BY !
   0 VX !  0 VY !
   80 HOLD-T !
   TRUE DIE-SHOW !
   TX-ROLL SAY
   S-DICE EFFECT ;

: CHECK-SHRINE { | dx dy s2 -- }
   BSTATE @ B-ROLL <> SHRINE-COOL @ 0> OR IF EXIT THEN
   BX @ SHRINE-X FX * - TO dx
   BY @ SHRINE-Y FX * - TO dy
   dx ABS 12 FX * >= dy ABS 12 FX * >= OR IF EXIT THEN
   VX @ DUP * VY @ DUP * + TO s2
   s2 4096 2* 4096 2* * < IF ENTER-SHRINE THEN ;

: SETTLE-ROLL { n -- }
   n DIE-FACE !
   n 1 = IF
      TX-FUMBLE SAY
      FALSE CHEST-LIT !
      RESET-RUNES
      EXIT
   THEN
   n 20 = IF
      TX-CRIT SAY
      BALLS @ 5 < IF 1 BALLS +! THEN
      25000 +SCORE  30 +XP
      n 3 * CHIP-NEAREST
      S-LANE EFFECT
      EXIT
   THEN
   n 11 < IF
      TX-MISS SAY  n 100 * +SCORE  n +XP
   ELSE
      TX-HIT SAY  n 500 * +SCORE  n 2/ +XP
      n CHIP-NEAREST
   THEN ;

: LET-GO ( -- )          \ out of the shrine
   B-ROLL BSTATE !
   60 SHRINE-COOL !
   2400 RND 6000 - VX !      \ up and to the left
   7000 NEGATE 3000 RND - VY !
   S-KICK EFFECT ;

: STEP-HOLD ( -- )
   HOLD-T @ 20 > IF
      CLOCK @ 4 MOD 0= IF ROLL-FACE THEN
   THEN
   -1 HOLD-T +!
   HOLD-T @ 20 = IF  20 RND 1+ SETTLE-ROLL  THEN
   HOLD-T @ 0= IF LET-GO THEN ;

: RESET-BALL ( -- )
   521 FX * BX !  760 FX * BY !  0 VX !  0 VY !
   B-LANE BSTATE !   TRUE LANE-OPEN !   0 CHARGE !  0 STILL-T ! ;

: GAME-OVER ( -- )
   SCORE @ BEST @ MAX BEST !
   M-OVER GMODE !
   S" T90 L8 O3 GFEDC2" JINGLE ;

: DRAINED ( -- )
   SAFE-T @ 0> IF
      TX-SHIELD SAY   0 SAFE-T !  FALSE SHIELD-OK !  S-LANE EFFECT
      RESET-BALL  EXIT
   THEN
   -1 BALLS +!
   BALLS @ 0> IF
      TX-LOST SAY  TRUE SHIELD-OK !
      RESET-BALL
   ELSE
      GAME-OVER
   THEN ;

: STEP-STILL ( -- )
   BSTATE @ B-ROLL <> IF  0 STILL-T !  EXIT  THEN
   VX @ ABS 400 < VY @ ABS 400 < AND IF
      1 STILL-T +!
      STILL-T @ 200 > IF         \ stuck: the dungeon shakes
         2400 RND 1200 - VX !
         4096 NEGATE VY !
         0 STILL-T !
      THEN
   ELSE 0 STILL-T ! THEN ;

: CHECK-LANE-BALL ( -- )
   BX @ 504 FX * < IF  FALSE LANE-OPEN !  THEN
   BSTATE @ B-ROLL = BX @ 504 FX * > AND BY @ 720 FX * > AND
   VX @ ABS 800 < AND VY @ ABS 800 < AND IF
      B-LANE BSTATE !  TRUE LANE-OPEN !  0 CHARGE !
   THEN ;

: LAUNCH ( -- )
   B-ROLL BSTATE !
   TRUE LANE-OPEN !
   7000 CHARGE @ 130 * + NEGATE VY !
   300 RND 150 - VX !
   SHIELD-OK @ IF 600 SAFE-T ! THEN
   S-KICK EFFECT ;

: STEP-PLUNGER ( -- )
   BSTATE @ B-LANE <> IF EXIT THEN
   BY @ 730 FX * < IF EXIT THEN
   IN-P @ IF
      CHARGE @ 60 < IF 1 CHARGE +! THEN
   ELSE
      CHARGE @ IF LAUNCH 0 CHARGE ! THEN
   THEN ;

: DOWN-COUNT ( a -- )   DUP @ 0> IF -1 SWAP +! ELSE DROP THEN ;

: STEP-TIMERS ( -- )
   SAFE-T DOWN-COUNT   SHRINE-COOL DOWN-COUNT   CHEST-COOL DOWN-COUNT   SLING-COOL DOWN-COUNT
   DRAGON-COOL DOWN-COUNT   DRAGON-FLASH DOWN-COUNT
   #MON 0 DO  I CELLS MON-COOL + DOWN-COUNT   I CELLS MON-FLASH + DOWN-COUNT  LOOP
   SPELL-T @ 1 = IF TX-FIRE SAY THEN  SPELL-T DOWN-COUNT
   MSG-T DOWN-COUNT
   RUNE-RESET @ 1 = IF RESET-RUNES THEN  RUNE-RESET DOWN-COUNT ;

: STEP-EFFECTS ( -- )
   #FLOAT 0 DO
      I FLOAT[] { a }
      a 2 CELLS + @ 0> IF  -1 a 2 CELLS + +!  -1 a CELL+ +!  THEN
   LOOP
   #SPARKS 0 DO
      I 6 * CELLS SPARKS + { a }
      a 4 CELLS + @ 0> IF
         a 2 CELLS + @ a +!   a 3 CELLS + @ a CELL+ +!
         -1 a 4 CELLS + +!
      THEN
   LOOP ;

: FLIP-INPUT ( -- )
   IN-L @ FL-HELD !   IN-R @ FL-HELD CELL+ ! ;

VARIABLE WAS-FLIP-L   VARIABLE WAS-FLIP-R

: TICK-PLAY ( -- )
   FLIP-INPUT
   IN-L @ WAS-FLIP-L @ 0=  AND  IN-R @ WAS-FLIP-R @ 0=  AND OR IF S-FLIP EFFECT THEN
   IN-L @ WAS-FLIP-L !  IN-R @ WAS-FLIP-R !
   BX @ PREV-X !  BY @ PREV-Y !
   STEP-PLUNGER
   STEP-PHYSICS
   BSTATE @ B-HOLD = IF STEP-HOLD THEN
   BSTATE @ B-RAMP = IF STEP-RAMP THEN
   CHECK-LANES  CHECK-SHRINE  CHECK-LANE-BALL  STEP-STILL
   CHECK-ORBIT  CHECK-SPIN  CHECK-RAMP  CHECK-KICK  STEP-SPIN
   STEP-TIMERS  STEP-EFFECTS
   BY @ 815 FX * > IF DRAINED THEN ;

: TICK-GAME ( -- )
   1 CLOCK +!
   PAUSED @ IF EXIT THEN
   GMODE @ M-PLAY = IF TICK-PLAY ELSE
      STEP-EFFECTS
   THEN ;

: NEW-GAME ( -- )
   0 SCORE !  3 BALLS !  1 FLOOR-NO !  1 LEVEL !  0 XP !  60 NEXT-XP !
   RESET-MONSTERS  RESET-RUNES
   TRUE KICK-LIT !  0 ORBIT-T !  0 SPIN-A !  0 SPIN-V !  0 RAMP-S !
   FALSE CHEST-LIT !  0 SPELL-T !  0 SAFE-T !  FALSE DIE-SHOW !  20 DIE-FACE !
   3 0 DO  FALSE LANE-LIT I CELLS + !  FALSE LANE-IN I CELLS + !  LOOP
   ANG-REST FL-ANG !  ANG-REST FL-ANG CELL+ !
   0 FL-DELTA !  0 FL-DELTA CELL+ !
   SPARKS #SPARKS 6 * CELLS ERASE  POPUPS #FLOAT 4 * CELLS ERASE
   #MON 0 DO  0 I CELLS MON-COOL + !  0 I CELLS MON-FLASH + !  LOOP
   0 DRAGON-COOL !  0 DRAGON-FLASH !  0 SHRINE-COOL !  0 CHEST-COOL !  0 SLING-COOL !
   TRUE SHIELD-OK !
   RESET-BALL
   FALSE PAUSED !
   M-PLAY GMODE !
   TRUE LOCK-INPUT !
   TX-ENTER SAY ;

\ ---- The pictures -------------------------------------------------------------------

VARIABLE TABLE-ART   VARIABLE SHEET-ART   VARIABLE BALL-ART
VARIABLE DIE-ART     VARIABLE HEART-ART
CREATE MON-ART 6 CELLS ALLOT      \ normal and flash, for each
CREATE TOMB-ART 1 CELLS ALLOT
CREATE DRAGON-ART 3 CELLS ALLOT   \ asleep, awake, flash
16 CONSTANT #FLIP
CREATE FLIP-ART #FLIP 2* CELLS ALLOT
CREATE RUNE-ART 8 CELLS ALLOT     \ up and down, for each letter
VARIABLE CHEST-ON-ART   VARIABLE LANE-ON-ART  VARIABLE SHRINE-ON-ART
CREATE BADGE-ART 21 CELLS ALLOT
CREATE DIE-DIGITS 10 CELLS ALLOT   VARIABLE DIE-DIGIT-W
CREATE DIGITS-S 10 CELLS ALLOT     VARIABLE DIGIT-W-S
CREATE DIGITS-B 10 CELLS ALLOT     VARIABLE DIGIT-W-B

: PAINT-RING ( -- )
   $20242E INK  32 32 31 DISC
   $B09058 INK  32 32 29 DISC
   $2E2A30 INK  32 32 25 DISC ;

: PAINT-EYES { c -- }
   c INK  24 28 4 DISC  40 28 4 DISC
   $101010 INK  24 28 2 DISC  40 28 2 DISC ;

: PAINT-GOBLIN { skin -- }
   PAINT-RING
   skin INK  [P 16 26 DV 4 18 DV 18 38 DV P]  [P 48 26 DV 60 18 DV 46 38 DV P]
   32 34 18 DISC
   $F0D040 PAINT-EYES
   $301810 INK  22 42 42 47 BOX
   $F0F0E0 INK  [P 24 42 DV 28 42 DV 26 46 DV P]  [P 36 42 DV 40 42 DV 38 46 DV P] ;

: PAINT-SKULL { bone -- }
   PAINT-RING
   bone INK  32 28 19 DISC  21 36 43 52 BOX
   $18141C INK  24 29 6 DISC  40 29 6 DISC
   [P 32 34 DV 36 42 DV 28 42 DV P]
   $18141C INK  25 46 27 52 BOX  31 46 33 52 BOX  37 46 39 52 BOX ;

: PAINT-ORC { skin -- }
   PAINT-RING
   skin INK  14 18 50 48 BOX  32 40 19 DISC
   $602018 INK  12 20 52 26 BOX
   $FF5030 PAINT-EYES
   $301810 INK  20 46 44 50 BOX
   $F0E8D0 INK  [P 21 50 DV 27 50 DV 24 39 DV P]  [P 37 50 DV 43 50 DV 40 39 DV P] ;

: PAINT-TOMB ( -- )
   PAINT-RING
   $6A6470 INK  22 24 42 52 BOX  32 24 10 DISC
   $3E3A44 INK  26 34 38 37 BOX  26 41 38 44 BOX ;

: PAINT-DRAGON { skin eyes? | dk -- }
   skin $181010 90 MIX-RGB TO dk
   dk INK    [P 12 20 DV 2 2 DV 24 12 DV P]   [P 52 20 DV 62 2 DV 40 12 DV P]
   skin INK  [P 10 26 DV 54 26 DV 58 44 DV 46 60 DV 18 60 DV 6 44 DV P]
   32 24 20 DISC
   dk INK    [P 16 44 DV 48 44 DV 44 60 DV 20 60 DV P]
   skin INK  [P 22 46 DV 42 46 DV 40 60 DV 24 60 DV P]
   $181010 INK  26 51 3 DISC  38 51 3 DISC
   eyes? IF
      $F8E040 INK  [P 14 28 DV 26 24 DV 26 36 DV 16 36 DV P]   [P 50 28 DV 38 24 DV 38 36 DV 48 36 DV P]
      $181010 INK  20 26 22 37 BOX  42 26 44 37 BOX
   ELSE
      $181010 INK  15 31 26 34 BOX  38 31 49 34 BOX
   THEN
   $F0E8D0 INK  [P 24 57 DV 27 57 DV 25 63 DV P]  [P 37 57 DV 40 57 DV 39 63 DV P] ;

: MAKE-MONSTERS ( -- )
   56 ART-BEGIN $5A9A38 PAINT-GOBLIN ART-DONE MON-ART !
   56 ART-BEGIN $C8E8A0 PAINT-GOBLIN ART-DONE MON-ART 1 CELLS + !
   56 ART-BEGIN $D8D0C0 PAINT-SKULL  ART-DONE MON-ART 2 CELLS + !
   56 ART-BEGIN $FFFFFF PAINT-SKULL  ART-DONE MON-ART 3 CELLS + !
   56 ART-BEGIN $7A6A50 PAINT-ORC    ART-DONE MON-ART 4 CELLS + !
   56 ART-BEGIN $C8B890 PAINT-ORC    ART-DONE MON-ART 5 CELLS + !
   56 ART-BEGIN PAINT-TOMB           ART-DONE TOMB-ART !
   96 ART-BEGIN $803028 FALSE PAINT-DRAGON ART-DONE DRAGON-ART !
   96 ART-BEGIN $C83820 TRUE PAINT-DRAGON  ART-DONE DRAGON-ART 1 CELLS + !
   96 ART-BEGIN $FF9060 TRUE PAINT-DRAGON  ART-DONE DRAGON-ART 2 CELLS + ! ;

: PAINT-BALL ( -- )
   $5A6068 INK  32 32 31 DISC
   $B8C0C8 INK  30 30 27 DISC
   $F8FAFC INK  24 22 11 DISC ;

\ A flipper on a canvas: the pivot at 14, 44 of the box of 96 by 88 (1 pixel to a unit).
: PAINT-FLIPPER { a mir | c s px tx ty -- }
   a COST TO c   a SINT TO s
   mir 0> IF 14 ELSE 82 THEN TO px
   px mir c * 70 * FX / + TO tx
   44 s 70 * FX / + TO ty
   $5A1810 INK  px 44 tx ty 7 BAR
   $C03828 INK  px 44 tx ty 5 BAR
   $F0C8A0 INK  px 44 tx ty 1 BAR
   $C8D0D8 INK  px 44 5 DISC
   $384048 INK  px 44 2 DISC ;
: FLIP-ANGLE ( k -- a )   ANG-REST ANG-UP -  *  #FLIP 1- /  ANG-REST SWAP - ;
: FLIP-BAKE ( -- spr )   96 88 ['] ART-PX BAKE ;
: MAKE-FLIPPERS ( -- )
   #FLIP 0 DO
      64 ART-BEGIN  I FLIP-ANGLE 1 PAINT-FLIPPER  FLIP-BAKE  FLIP-ART I CELLS + !
      64 ART-BEGIN  I FLIP-ANGLE -1 PAINT-FLIPPER  FLIP-BAKE  FLIP-ART I #FLIP + CELLS + !
   LOOP ;

: RUNE-LETTER$ ( n -- a u )   S" RUNE" DROP + 1 ;
: PAINT-RUNE { n up? | a u c -- }
   up? IF $A07030 ELSE $28242E THEN TO c
   $181418 INK  0 0 28 64 BOX
   c INK  2 2 26 62 BOX
   up? IF $F8E8B0 ELSE $48444E THEN INK
   n RUNE-LETTER$ TO u TO a
   a u  14 SCALED a u TEXT-WIDTH 2/ -  32 SCALED TEXT-HEIGHT 2/ -  TEXT ;

: MAKE-TARGETS ( -- )
   \ a target is 14 wide by 32 high; painted in a box of 64 units to 32 pixels
   48 USE-FONT
   4 0 DO
      32 ART-BEGIN  I TRUE PAINT-RUNE   14 32 ['] ART-PX BAKE  RUNE-ART I 2* CELLS + !
      32 ART-BEGIN  I FALSE PAINT-RUNE  14 32 ['] ART-PX BAKE  RUNE-ART I 2* 1+ CELLS + !
   LOOP ;

8 CONSTANT #SPIN
CREATE SPIN-ART #SPIN CELLS ALLOT
\ The blade across the lane: its width changes as it turns.
: PAINT-SPIN { n | th -- }
   n 256 * COST ABS  6 * FX / 1 MAX TO th
   32 15 + th 15 * 34 /  -  32 8 + th 31 * 34 / -
   32 15 + th 15 * 34 / +   32 8 + th 31 * 34 / +
   32 15 - th 15 * 34 / +   32 8 - th 31 * 34 / +
   32 15 - th 15 * 34 / -   32 8 - th 31 * 34 / -
   { x0 y0 x1 y1 x2 y2 x3 y3 }
   $F0D890 INK  [P x0 y0 DV x1 y1 DV x2 y2 DV x3 y3 DV P]
   $808890 INK  32 15 + 32 8 + 3 DISC  32 15 - 32 8 - 3 DISC ;
: MAKE-SPINNER ( -- )
   #SPIN 0 DO  64 ART-BEGIN I PAINT-SPIN ART-DONE SPIN-ART I CELLS + !  LOOP ;

: PAINT-LANE-ON ( -- )
   $F8E060 INK  32 32 28 DISC
   $FFFFFF INK  26 26 10 DISC ;
: PAINT-SHRINE-ON ( -- )
   $70F0B0 INK  32 32 30 DISC
   $0A2436 INK  32 32 21 DISC
   $70F0B0 INK  32 12 5 DISC ;
: PAINT-CHEST-ON ( -- )
   $F8D860 INK  8 18 56 46 BOX
   $FFF4C0 INK  12 22 52 30 BOX
   $806020 INK  28 28 36 40 BOX ;
: PAINT-HEART ( -- )
   $C82838 INK  20 24 15 DISC  44 24 15 DISC
   [P 5 28 DV 59 28 DV 32 60 DV P]
   $FF9090 INK  18 18 5 DISC ;
: PAINT-BADGE { n | a u -- }
   $18141C INK  32 32 31 DISC
   $F0C030 INK  32 32 27 DISC
   $181010 INK
   n S>D <# #S #> TO u TO a
   a u  32 SCALED a u TEXT-WIDTH 2/ -  32 SCALED TEXT-HEIGHT 2/ -  TEXT ;

: PAINT-DIE ( -- )
   $D82828 INK  [P 32 2 DV 58 18 DV 58 48 DV 32 62 DV 6 48 DV 6 18 DV P]
   $F05040 INK  [P 32 2 DV 58 18 DV 32 16 DV 6 18 DV P]
   $901818 INK  [P 6 48 DV 32 62 DV 58 48 DV 32 52 DV P]
   $B82020 INK  [P 6 18 DV 18 34 DV 6 48 DV P]  [P 58 18 DV 46 34 DV 58 48 DV P]
   $E84038 INK  [P 32 14 DV 54 44 DV 10 44 DV P] ;

: MAKE-SMALL ( -- )
   20 ART-BEGIN PAINT-BALL ART-DONE BALL-ART !
   24 ART-BEGIN PAINT-LANE-ON ART-DONE LANE-ON-ART !
   40 ART-BEGIN PAINT-SHRINE-ON ART-DONE SHRINE-ON-ART !
   24 ART-BEGIN PAINT-HEART ART-DONE HEART-ART !
   120 ART-BEGIN PAINT-DIE ART-DONE DIE-ART !
   42 USE-PLAIN
   21 1 DO  26 ART-BEGIN I PAINT-BADGE ART-DONE BADGE-ART I CELLS + !  LOOP ;

: MAKE-CHEST ( -- )
   56 ART-BEGIN PAINT-CHEST-ON ART-DONE CHEST-ON-ART ! ;

\ The digits on the sheet and on the die.
: MAKE-DIGITS ( -- )
   20 USE-PLAIN   S" 0" TEXT-WIDTH DIGIT-W-S !
   10 0 DO  I DIGIT$ PAPER DIGITS-S I CELLS + !  LOOP
   30 USE-PLAIN   S" 0" TEXT-WIDTH DIGIT-W-B !
   10 0 DO  I DIGIT$ PAPER DIGITS-B I CELLS + !  LOOP
   34 USE-PLAIN   S" 0" TEXT-WIDTH DIE-DIGIT-W !
   10 0 DO  I DIGIT$ $FFF8E0 $E84038 TEXT-SPRITE DIE-DIGITS I CELLS + !  LOOP ;

VARIABLE L-SCORE  VARIABLE L-LEVEL  VARIABLE L-DEPTH  VARIABLE L-XP   VARIABLE L-BALLS
VARIABLE L-TITLE  VARIABLE L-GOBLIN VARIABLE L-SKEL   VARIABLE L-ORC  VARIABLE L-DRAGON
VARIABLE L-FIRE   VARIABLE L-SHIELD VARIABLE L-BEST   VARIABLE L-HELP1 VARIABLE L-HELP2
VARIABLE L-HELP3  VARIABLE L-HELP4  VARIABLE L-HELP5
VARIABLE T-BIG    VARIABLE T-SUB    VARIABLE T-KEYS1  VARIABLE T-KEYS2 VARIABLE T-START
VARIABLE O-OVER   VARIABLE O-AGAIN  VARIABLE O-PAUSE

: MAKE-LABELS ( -- )
   32 USE-FONT  S" Wyrm's Delve" C-INK C-PAPER TEXT-SPRITE L-TITLE !
   15 USE-FONT
   S" SCORE" FADED L-SCORE !  S" LEVEL" FADED L-LEVEL !  S" FLOOR" FADED L-DEPTH !
   S" XP" FADED L-XP !  S" BALLS" FADED L-BALLS !
   S" Goblin" PAPER L-GOBLIN !  S" Skeleton" PAPER L-SKEL !  S" Orc" PAPER L-ORC !
   S" Dragon" PAPER L-DRAGON !
   S" Fireball" PAPER L-FIRE !  S" Shield" PAPER L-SHIELD !  S" BEST" FADED L-BEST !
   14 USE-PLAIN
   S" Z or Left: left flipper" FADED L-HELP1 !
   S" / or Right: right flipper" FADED L-HELP2 !
   S" Space or Down: plunger" FADED L-HELP3 !
   S" The mouse buttons work too" FADED L-HELP4 !
   S" P pause   R again   Q quit" FADED L-HELP5 !
   #MSG 0 DO  I MSG$ DUP IF  PAPER MSG-ART I CELLS + !  ELSE 2DROP  THEN  LOOP
   68 USE-FONT  S" Wyrm's Delve" C-GOLD C-DARK TEXT-SPRITE T-BIG !
   20 USE-FONT  S" A dungeon crawl on a pinball table" $E8DCC0 C-DARK TEXT-SPRITE T-SUB !
   15 USE-FONT
   S" Slay the monsters, wake the dragon, and go deeper." $C8BCA0 C-DARK TEXT-SPRITE T-KEYS1 !
   S" The shrine rolls a d20. A twenty is an extra ball." $C8BCA0 C-DARK TEXT-SPRITE T-KEYS2 !
   24 USE-FONT  S" Space or click to start" $F8E8B0 C-DARK TEXT-SPRITE T-START !
   44 USE-FONT  S" The party is lost" $FF9070 C-DARK TEXT-SPRITE O-OVER !
   S" Paused" C-GOLD C-DARK TEXT-SPRITE O-PAUSE !
   18 USE-FONT  S" Space or click to try again" $E8DCC0 C-DARK TEXT-SPRITE O-AGAIN ! ;

\ ---- The table picture -------------------------------------------------------------
\ Painted at twice its size, 560 by 800; stones first and then the rails.

: STONE { x0 y0 x1 y1 c -- }
   $0E0C12 INK  x0 y0 x1 y1 BOX
   c INK  x0 1+ y0 1+ x1 2 - y1 2 - BOX
   c $FFFFFF 26 MIX-RGB INK  x0 1+ y0 1+ x1 2 - y0 3 + BOX ;

: PAINT-FLOOR { | n c -- }
   12 0 DO
      I 1 AND IF -44 ELSE 0 THEN { ofs }
      9 0 DO
         J 97 * I 53 * + 5 MOD TO n
         n 0 = IF $2C2A36 THEN  n 1 = IF $33303E THEN  n 2 = IF $282632 THEN
         n 3 = IF $302C38 THEN  n 4 = IF $36343F THEN TO c
         I 88 * ofs +  J 68 *  OVER 88 +  OVER 68 +  c STONE
      LOOP
   LOOP ;

: PAINT-CIRCLES ( -- )        \ a summoning circle on the floor
   $4A3A70 INK  264 470 100 DISC
   $2E2A3A INK  264 470 96 DISC
   $4A3A70 INK  264 470 66 DISC
   $2E2A3A INK  264 470 62 DISC
   8 0 DO
      I 8 * SIN64 { s }   I 8 * 16 + SIN64 { c }
      $5A4688 INK
      264 c 97 * 1024 / +   470 s 97 * 1024 / +
      264 c 64 * 1024 / +   470 s 64 * 1024 / +  2 BAR
   LOOP ;

VARIABLE RAIL-PASS
: RAIL { x0 y0 x1 y1 -- }
   RAIL-PASS @ CASE
      0 OF  $181420 INK  x0 y0 x1 y1 6 BAR  ENDOF
      1 OF  $9C8050 INK  x0 y0 x1 y1 4 BAR  ENDOF
      2 OF  $D8C088 INK  x0 y0 x1 y1 1 BAR  ENDOF
   ENDCASE ;

: DRAW-RAILS-PASS ( -- )
   #SEGS @ 0 DO
      I SEG[] { a }
      a 9 CELLS + @ { kind }
      kind K-WALL = kind K-SLING = OR kind K-OW = OR IF
         a @ FX / { x0 }  a CELL+ @ FX / { y0 }
         a @  a 2 CELLS + @ a 4 CELLS + @ * FX / + FX / { x1 }
         a CELL+ @  a 3 CELLS + @ a 4 CELLS + @ * FX / + FX / { y1 }
         kind K-SLING = IF
            RAIL-PASS @ 1 = IF  $C83828 INK  x0 y0 x1 y1 6 BAR  THEN
            RAIL-PASS @ 2 = IF  $FFD060 INK  x0 y0 x1 y1 2 BAR  THEN
         ELSE kind K-OW = IF
            RAIL-PASS @ 2 = IF  $70D0E0 INK  x0 y0 x1 y1 2 BAR  THEN
         ELSE  x0 y0 x1 y1 RAIL  THEN THEN
      THEN
   LOOP ;
: DRAW-RAILS ( -- )   3 0 DO  I RAIL-PASS !  DRAW-RAILS-PASS  LOOP ;

: PAINT-SLING-BODIES ( -- )
   $5A1818 INK  [P 128 560 DV 128 625 DV 188 668 DV P]
                [P 400 560 DV 400 625 DV 340 668 DV P]
   $803028 INK  [P 134 582 DV 134 618 DV 168 643 DV P]
                [P 394 582 DV 394 618 DV 360 643 DV P] ;

: PAINT-SHRINE ( -- )
   $0A1A26 INK  SHRINE-X SHRINE-Y 26 DISC
   $4A7A90 INK  SHRINE-X SHRINE-Y 24 DISC
   $102838 INK  SHRINE-X SHRINE-Y 20 DISC
   $0A1A26 INK  SHRINE-X SHRINE-Y 12 DISC ;

: PAINT-LANE-CUPS ( -- )
   3 0 DO
      $181420 INK  I CELLS LANE-X + @ LANE-Y 12 DISC
      $4A4258 INK  I CELLS LANE-X + @ LANE-Y 10 DISC
   LOOP ;

: PAINT-CHEST ( -- )
   $2A1810 INK  [P 480 296 DV 464 356 DV 502 380 DV 502 280 DV P]
   $6A4820 INK  [P 484 306 DV 472 350 DV 496 366 DV 496 298 DV P]
   $C8A048 INK  [P 480 324 DV 476 340 DV 496 346 DV 496 330 DV P] ;

: PAINT-LANE-STRIP ( -- )
   $0E0C12 INK  504 235 538 800 BOX
   $1C1824 INK  508 239 534 800 BOX ;

: PAINT-APRON ( -- )
   $0E0C12 INK  24 760 504 800 BOX
   $241C2A INK  24 764 504 800 BOX
   [P 24 720 DV 58 680 DV 164 734 DV 164 800 DV 24 800 DV P]
   [P 504 720 DV 470 680 DV 364 734 DV 364 800 DV 504 800 DV P] ;

\ The bridge of the ramp, in two passes so the joints do not show.
: PAINT-RAMP ( -- )
   #RAMP 1- 0 DO  $B09058 INK  I RAMP-PX I 1+ RAMP-PX 16 BAR  LOOP
   #RAMP 1- 0 DO  $4A3424 INK  I RAMP-PX I 1+ RAMP-PX 13 BAR  LOOP
   #RAMP 1- 0 DO  $5E4630 INK  I RAMP-PX I 1+ RAMP-PX 5 BAR  LOOP
   $E0C078 INK  190 494 222 468 3 BAR
   $F0C060 INK  [P 190 462 DV 212 468 DV 198 486 DV P] ;

: PAINT-KICK ( -- )
   $181420 INK  41 650 9 DISC
   $4A4258 INK  41 650 7 DISC ;

: PAINT-POSTS ( -- )
   2 0 DO
      $181420 INK  I POSTS-X POST-Y 8 DISC
      $C8A048 INK  I POSTS-X POST-Y 6 DISC
   LOOP ;

: TABLE-PX ( x y -- rgb )   ART-PX $F8F8F8 AND ;

: MAKE-TABLE ( -- )
   64 TO CS  2 TO ZOOM
   1120 1600 GFX-INIT
   KEY-COLOR GFX-CLS
   PAINT-FLOOR
   PAINT-CIRCLES
   PAINT-LANE-STRIP
   PAINT-APRON
   PAINT-SLING-BODIES
   PAINT-SHRINE
   PAINT-LANE-CUPS
   PAINT-CHEST
   PAINT-POSTS
   PAINT-KICK
   PAINT-RAMP
   DRAW-RAILS
   TW H ['] TABLE-PX BAKE TABLE-ART !
   3 TO ZOOM ;

: SHEET-PX { x y -- rgb }
   x 8 < y 8 < OR  x 231 > OR  y 791 > OR IF C-FADED EXIT THEN
   x 12 < y 12 < OR  x 227 > OR  y 787 > OR IF C-PAPER $3E2412 40 MIX-RGB EXIT THEN
   C-PAPER ;

: BAKE-ALL ( -- )
   BUILD-WALLS
   1024 512 GFX-INIT
   BUILD-RAMP
   MAKE-MONSTERS  MAKE-FLIPPERS  MAKE-TARGETS  MAKE-SMALL  MAKE-CHEST  MAKE-SPINNER
   MAKE-DIGITS  MAKE-LABELS
   240 800 ['] SHEET-PX BAKE SHEET-ART !
   MAKE-TABLE ;

\ ---- Drawing ------------------------------------------------------------------------

: NUMBER-AT { n x y table dw -- }
   n S>D <# #S #>  0 DO
      DUP I + C@ [CHAR] 0 - CELLS table + @  { s }
      x I dw * +  y  s SPR
   LOOP DROP ;
: SMALL-AT ( n x y -- )   DIGITS-S DIGIT-W-S @ NUMBER-AT ;
: BIG-AT ( n x y -- )     DIGITS-B DIGIT-W-B @ NUMBER-AT ;

: DRAW-MONSTERS ( -- )
   #MON 0 DO
      I MON-DEAD? IF
         I CELLS MON-X + @  I CELLS MON-Y + @  TOMB-ART @ CENTERED
      ELSE
         I CELLS MON-X + @  I CELLS MON-Y + @
         I 2*  I CELLS MON-FLASH + @ 0> IF 1+ THEN  CELLS MON-ART + @  CENTERED
      THEN
   LOOP ;

: DRAW-DRAGON ( -- )
   264 158
   DRAGON-ON @ 0= IF 0 ELSE  DRAGON-FLASH @ 0> IF 2 ELSE 1 THEN  THEN
   CELLS DRAGON-ART + @  CENTERED ;

: DRAW-SPIN ( -- )
   63 179  SPIN-A @ 8 / #SPIN MOD CELLS SPIN-ART + @  CENTERED ;

: DRAW-RUNES ( -- )
   4 0 DO
      41  320 I 37 * +
      I 2*  RUNE-UP I CELLS + @ 0= IF 1+ THEN  CELLS RUNE-ART + @  SPR
   LOOP ;

: FLIP-FRAME ( n -- k )
   CELLS FL-ANG + @  ANG-REST SWAP -  #FLIP 1- *  ANG-REST ANG-UP - /  0 MAX #FLIP 1- MIN ;

: DRAW-FLIPPERS ( -- )
   175 14 -   716 44 -   0 FLIP-FRAME CELLS FLIP-ART + @  SPR
   353 82 -   716 44 -   1 FLIP-FRAME #FLIP + CELLS FLIP-ART + @  SPR ;

: DRAW-LIGHTS ( -- )
   3 0 DO
      LANE-LIT I CELLS + @ IF
         I CELLS LANE-X + @  LANE-Y  LANE-ON-ART @ CENTERED
      THEN
   LOOP
   CHEST-LIT @ CLOCK @ 16 AND 0= AND IF  482 334  CHEST-ON-ART @ CENTERED  THEN
   KICK-LIT @ IF  41 650 LANE-ON-ART @ CENTERED  THEN
   SHRINE-COOL @ 0=  BSTATE @ B-ROLL = AND IF  SHRINE-X SHRINE-Y SHRINE-ON-ART @ CENTERED  THEN ;

: DRAW-PLUNGER ( -- )
   $B0A080 COLOR!  516 776 CHARGE @ 2/ + 12 20 FILL-RECT
   $E0D0A0 COLOR!  518 776 CHARGE @ 2/ + 8 3 FILL-RECT ;

: DRAW-BALL ( -- )
   GMODE @ M-PLAY <> IF EXIT THEN
   BX @ FX /  BY @ FX /  BALL-ART @ CENTERED ;

: DRAW-EFFECTS ( -- )
   #SPARKS 0 DO
      I 6 * CELLS SPARKS + { a }
      a 4 CELLS + @ 0> IF
         a @ 16 / { sx }  a CELL+ @ 16 / { sy }
         sx 0 TW 3 - WITHIN  sy 0 H 2 - WITHIN AND IF
            sx DUP 2 + sy    a 5 CELLS + @ GFX-HLINE
            sx DUP 2 + sy 1+ a 5 CELLS + @ GFX-HLINE
         THEN
      THEN
   LOOP
   #FLOAT 0 DO
      I FLOAT[] { a }
      a 2 CELLS + @ 0> IF
         a @  a CELL+ @  a 3 CELLS + @ 1 MAX 20 MIN CELLS BADGE-ART + @  CENTERED
      THEN
   LOOP ;

: HP-BAR { x y hp mx c -- }
   C-INK COLOR!  x y 130 10 FILL-RECT
   C-PAPER $A08860 100 MIX-RGB COLOR!  x 1+ y 1+ 128 8 FILL-RECT
   hp 0> IF  c COLOR!  x 1+ y 1+  128 hp * mx / 1 MAX 8 FILL-RECT  THEN ;

: DRAW-HEARTS ( -- )
   BALLS @ 0 ?DO  I 28 * 648 +  208 HEART-ART @ SPR  LOOP ;

: DRAW-DIE ( -- )
   680 470 DIE-ART @ CENTERED
   DIE-FACE @ 10 < IF
      680 480  DIE-FACE @ CELLS DIE-DIGITS + @  CENTERED
   ELSE
      680 DIE-DIGIT-W @ 2/ -  480  DIE-FACE @ 10 / CELLS DIE-DIGITS + @  CENTERED
      680 DIE-DIGIT-W @ 2/ +  480  DIE-FACE @ 10 MOD CELLS DIE-DIGITS + @  CENTERED
   THEN ;

: DRAW-SHEET ( -- )
   560 0 SHEET-ART @ SPR
   680 40  L-TITLE @ CENTERED
   580 76 L-SCORE @ SPR
   SCORE @ 580 92 BIG-AT
   580 138 L-LEVEL @ SPR   LEVEL @ 640 134 SMALL-AT
   690 138 L-DEPTH @ SPR   FLOOR-NO @ 750 134 SMALL-AT
   580 174 L-XP @ SPR
   C-INK COLOR!  610 176 170 10 FILL-RECT
   C-PAPER $A08860 100 MIX-RGB COLOR!  611 177 168 8 FILL-RECT
   $4070C0 COLOR!  611 177  XP @ 168 * NEXT-XP @ 1 MAX / 168 MIN 0 MAX  8 FILL-RECT
   580 212 L-BALLS @ SPR
   DRAW-HEARTS
   580 256 L-GOBLIN @ SPR  650 260  MON-HP @ 0 MAX  MON-MAX @  $48A040 HP-BAR
   580 290 L-SKEL @ SPR    650 294  MON-HP CELL+ @ 0 MAX  MON-MAX CELL+ @  $909090 HP-BAR
   580 324 L-ORC @ SPR     650 328  MON-HP 2 CELLS + @ 0 MAX  MON-MAX 2 CELLS + @  $B06030 HP-BAR
   580 358 L-DRAGON @ SPR  650 362  DRAGON-ON @ IF DRAGON-HP @ 0 MAX ELSE 0 THEN  DRAGON-MAX @  $D03020 HP-BAR
   DRAW-DIE
   MSG-T @ 0> IF  680 570 MSG-NOW @ CELLS MSG-ART + @ CENTERED  THEN
   SPELL-T @ 0> IF  580 596 L-FIRE @ SPR  $E86020 COLOR!  660 602  120 SPELL-T @ * 900 / 6 FILL-RECT  THEN
   SAFE-T @ 0> IF  580 622 L-SHIELD @ SPR  $40A0E0 COLOR!  660 628  120 SAFE-T @ * 600 / 6 FILL-RECT  THEN
   580 655 L-BEST @ SPR   BEST @ 640 651 SMALL-AT
   680 694 L-HELP1 @ CENTERED
   680 712 L-HELP2 @ CENTERED
   680 730 L-HELP3 @ CENTERED
   680 748 L-HELP4 @ CENTERED
   680 766 L-HELP5 @ CENTERED ;

: DRAW-TITLE ( -- )
   C-DARK COLOR!  60 250 440 300 FILL-RECT
   C-GOLD COLOR!  60 250 440 3 FILL-RECT  60 547 440 3 FILL-RECT
   280 310 T-BIG @ CENTERED
   280 368 T-SUB @ CENTERED
   280 420 T-KEYS1 @ CENTERED
   280 446 T-KEYS2 @ CENTERED
   CLOCK @ 32 AND 0= IF  280 510 T-START @ CENTERED  THEN ;

: DRAW-OVER ( -- )
   C-DARK COLOR!  60 300 440 160 FILL-RECT
   C-GOLD COLOR!  60 300 440 3 FILL-RECT  60 457 440 3 FILL-RECT
   280 358 O-OVER @ CENTERED
   280 418 O-AGAIN @ CENTERED ;

: RENDER ( -- )
   0 0 TABLE-ART @ SPR
   DRAW-LIGHTS  DRAW-SPIN  DRAW-RUNES  DRAW-MONSTERS  DRAW-DRAGON
   DRAW-PLUNGER  DRAW-FLIPPERS  DRAW-BALL  DRAW-EFFECTS
   DRAW-SHEET
   GMODE @ M-TITLE = IF DRAW-TITLE THEN
   GMODE @ M-OVER = IF DRAW-OVER THEN
   PAUSED @ IF  280 400 O-PAUSE @ CENTERED  THEN ;

\ ---- Input -------------------------------------------------------------------------

: HELD2 ( c1 c2 -- flag )   KEY-HELD? SWAP KEY-HELD? OR ;

: GO-ON ( -- )   GMODE @ M-PLAY <> IF NEW-GAME THEN ;

: KEY! ( key -- )
   DUP [CHAR] A [CHAR] Z 1+ WITHIN IF 32 + THEN
   CASE
      [CHAR] q OF  TRUE DONE !  ENDOF
      27       OF  TRUE DONE !  ENDOF
      [CHAR] p OF  GMODE @ M-PLAY = IF PAUSED @ 0= PAUSED ! THEN  ENDOF
      [CHAR] r OF  NEW-GAME  ENDOF
      BL       OF  GO-ON  ENDOF
      13       OF  GO-ON  ENDOF
   ENDCASE ;
: READ-KEYS ( -- )   BEGIN INKEY DUP -1 <> WHILE KEY! REPEAT DROP ;

VARIABLE OLD-B
: READ-INPUT { | b -- }
   MOUSE TO b 2DROP
   b 1 AND 0<> OLD-B @ 1 AND 0= AND IF GO-ON THEN
   K-LEFT KEY-HELD?  [CHAR] z [CHAR] Z HELD2 OR   b 1 AND 0<> OR  IN-L !
   K-RIGHT KEY-HELD? [CHAR] / KEY-HELD? OR        b 2 AND 0<> OR  IN-R !
   BL KEY-HELD?  K-DOWN KEY-HELD? OR
   BSTATE @ B-LANE =  b 3 AND 0<> AND  OR  IN-P !
   LOCK-INPUT @ IF
      IN-P @ IF FALSE IN-P ! ELSE FALSE LOCK-INPUT ! THEN
   THEN
   b OLD-B ! ;

\ ---- The game loop -----------------------------------------------------------------

: GAME-STEP ( -- )   READ-KEYS  READ-INPUT  TICK-GAME  RENDER ;

: INIT-GAME ( -- )
   NOW SEED !  FALSE DONE !  0 BEST !  0 OLD-B !
   FALSE IN-L !  FALSE IN-R !  FALSE IN-P !
   NEW-GAME
   M-TITLE GMODE ! ;

: WYRMS-DELVE ( -- )
   BAKE-ALL  MAKE-SOUNDS
   W H GFX-INIT  MOUSE-ON
   INIT-GAME
   BEGIN  GAME-STEP  16 FRAME  DONE @ UNTIL
   MOUSE-OFF ;

[UNDEFINED] NO-AUTORUN [IF] WYRMS-DELVE BYE [THEN]
