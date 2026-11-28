\ Jingle Bells (James Lord Pierpont, 1857; public-domain melody).
\ Original arrangement and drawing; no external images or sound files.
\ Run: zig-out/bin/sigma.exe examples/jingle-bells.fs
\ Loops the chorus until stopped.
\ Space: toss extra presents!  Q / Esc (or window close): stop and close.
\ Requires a build with graphics and audio.

REQUIRE-GAME REQUIRE-AUDIO
ALSO GRAPHICS ALSO GAME ALSO AUDIO DECIMAL

\ ---- State & Palette ---------------------------------------------------------

VARIABLE JB-TICK      VARIABLE JB-BAR#      VARIABLE JB-BAR-TICK
VARIABLE JB-X         VARIABLE JB-Y         VARIABLE JB-STOP
VARIABLE JB-CLOSES    VARIABLE JB-RNG       VARIABLE JB-THROW-CD
VARIABLE JB-BUBBLE-T  VARIABLE JB-BUBBLE-ID VARIABLE JB-LAST-BEAT
VARIABLE JB-BG        VARIABLE JB-HILLS-IMG VARIABLE JB-TITLE-IMG

$FF00FF CONSTANT JB-KEY
$FFF4D6 CONSTANT JB-WHITE
$EAF4FC CONSTANT JB-SNOW
$B8D6EC CONSTANT JB-ICE
$E83F52 CONSTANT JB-RED
$B4263B CONSTANT JB-RED-DK
$F8D264 CONSTANT JB-GOLD
$C9962B CONSTANT JB-GOLD-DK
$288557 CONSTANT JB-GREEN
$1B5E3E CONSTANT JB-GREEN-DK
$FF7EA8 CONSTANT JB-PINK
$62D6FF CONSTANT JB-CYAN
$FF8C32 CONSTANT JB-ORANGE
$B97F4B CONSTANT JB-BROWN
$DFB17F CONSTANT JB-TAN
$F5C8A4 CONSTANT JB-SKIN
$13182E CONSTANT JB-DARK

\ ---- Math, Random & Rhythm Helpers -------------------------------------------

CREATE JB-SIN-TAB
    0 ,   10 ,   20 ,   29 ,   38 ,   47 ,   56 ,   63 ,
   71 ,   77 ,   83 ,   88 ,   92 ,   96 ,   98 ,  100 ,
  100 ,  100 ,   98 ,   96 ,   92 ,   88 ,   83 ,   77 ,
   71 ,   63 ,   56 ,   47 ,   38 ,   29 ,   20 ,   10 ,
    0 ,  -10 ,  -20 ,  -29 ,  -38 ,  -47 ,  -56 ,  -63 ,
  -71 ,  -77 ,  -83 ,  -88 ,  -92 ,  -96 ,  -98 , -100 ,
 -100 , -100 ,  -98 ,  -96 ,  -92 ,  -88 ,  -83 ,  -77 ,
  -71 ,  -63 ,  -56 ,  -47 ,  -38 ,  -29 ,  -20 ,  -10 ,

: JB-SIN ( angle -- -100..100 )  63 AND CELLS JB-SIN-TAB + @ ;
: JB-COS ( angle -- -100..100 )  16 + JB-SIN ;

: JB-RAND ( n -- 0..n-1 )
  JB-RNG @ 1103515245 * 12345 + DUP JB-RNG ! 16 RSHIFT $7FFF AND SWAP MOD ;

\ Beat timing (~28 ticks per quarter note at T132, 60 fps).
: JB-BEAT# ( -- n )       JB-BAR-TICK @ 28 / ;
: JB-BEAT-PH ( -- n )     JB-BAR-TICK @ 28 MOD ;
: JB-GLOBAL-BEAT ( -- n ) JB-BAR# @ 0 MAX 4 * JB-BEAT# + ;

\ Snappy beat bounce: 10 right on the beat, easing quickly back to 0.
: JB-BOUNCE ( -- 0..10 )
  JB-BEAT-PH DUP 14 < IF 14 SWAP - 10 * 14 / ELSE DROP 0 THEN ;

: JB-BIG-BAR? ( -- flag )
  JB-BAR# @ DUP 3 = OVER 7 = OR OVER 11 = OR SWAP 15 = OR ;

\ ---- Fast Drawing Helpers ----------------------------------------------------

\ Fast midpoint filled circle using GFX-HLINE (no per-row ISQRT).
: JB-DISC { cx cy r | x y err col -- }
  r 0< IF EXIT THEN
  COLOR@ TO col
  r TO x  0 TO y  1 r - TO err
  BEGIN x y >= WHILE
    cx x - cx x + cy y + col GFX-HLINE
    y IF cx x - cx x + cy y - col GFX-HLINE THEN
    err 0< IF
      y 1+ TO y
      err y 2* 1+ + TO err
    ELSE
      cx y - cx y + cy x + col GFX-HLINE
      cx y - cx y + cy x - col GFX-HLINE
      x 1- TO x  y 1+ TO y
      err y x - 2* 1+ + TO err
    THEN
  REPEAT ;

\ Upper half-circle dome (for crisp mini-parachutes without background cutout).
: JB-DOME { cx cy r | x y err col -- }
  r 0< IF EXIT THEN
  COLOR@ TO col
  r TO x  0 TO y  1 r - TO err
  BEGIN x y >= WHILE
    cx x - cx x + cy y - col GFX-HLINE
    err 0< IF
      y 1+ TO y
      err y 2* 1+ + TO err
    ELSE
      cx y - cx y + cy x - col GFX-HLINE
      x 1- TO x  y 1+ TO y
      err y x - 2* 1+ + TO err
    THEN
  REPEAT ;

\ Relative drawing helpers anchored at (JB-X, JB-Y).
: JB-RECT { x y w h -- } x JB-X @ + y JB-Y @ + w h FILL-RECT ;
: JB-CIRCLE { x y r -- } x JB-X @ + y JB-Y @ + r JB-DISC ;
: JB-LINE { x y xx yy -- }
  x JB-X @ + y JB-Y @ + xx JB-X @ + yy JB-Y @ + LINE ;

\ Fast filled isosceles triangle pointing up (tip at cx, ty).
: JB-TRI { cx ty hw h | w -- }
  h 1 < IF EXIT THEN
  h 0 DO
    hw I 1+ * h / TO w
    cx w -  cx w +  ty I +  COLOR@ GFX-HLINE
  LOOP ;

\ Twinkling 4-point sparkle star.
: JB-SPARKLE { x y r -- }
  x r - x r + y COLOR@ GFX-HLINE
  x y r - x y r + LINE ;

\ Pixel-art musical note (kind 0 = single eighth note, 1 = beamed pair).
: JB-DRAW-NOTE { x y col kind -- }
  col COLOR!
  x y 2 JB-DISC
  x 2 + y x 2 + y 9 - LINE
  kind 0= IF
    x 2 + y 9 - x 6 + y 6 - LINE
    x 2 + y 8 - x 6 + y 5 - LINE
  ELSE
    x 9 + y 1- 2 JB-DISC
    x 11 + y 1- x 11 + y 10 - LINE
    x 2 + y 9 - x 11 + y 10 - LINE
    x 2 + y 8 - x 11 + y 9 - LINE
  THEN ;

\ ---- Pre-rendered Offscreen Layers (Silky Smooth 60 fps) ---------------------

: JB-INIT-ASSETS ( -- )
  \ 1) Smooth twilight-to-midnight winter night sky gradient (640x360).
  640 360 NEW-IMAGE JB-BG !
  JB-BG @ DRAW-TO
  360 0 DO
    I 320 MIN { t }
    7  t 35 * 320 / +
    16 t 60 * 320 / +
    44 t 94 * 320 / +
    RGB >R  0 639 I R> GFX-HLINE
  LOOP

  \ 2) Seamless 640x120 scrolling distant snowy hills & silhouette pines.
  640 120 NEW-IMAGE JB-HILLS-IMG !
  JB-HILLS-IMG @ DRAW-TO
  JB-KEY GFX-CLS
  \ Far hill ridge (wrap-seamless across x = 0..640).
  8 0 DO
    I 80 * { hx }
    $1E3666 COLOR! hx 116 68 JB-DISC
    hx 640 + 116 68 JB-DISC  hx 640 - 116 68 JB-DISC
  LOOP
  \ Nearer snow-lit hill ridge + distant pine silhouettes.
  8 0 DO
    I 80 * 38 + { hx }
    $162A52 COLOR!
    hx 26 - 40 7 18 JB-TRI  hx 26 - 640 + 40 7 18 JB-TRI
    hx 14 + 44 6 16 JB-TRI  hx 14 + 640 - 44 6 16 JB-TRI
    $2D4D82 COLOR! hx 124 62 JB-DISC
    hx 640 + 124 62 JB-DISC  hx 640 - 124 62 JB-DISC
  LOOP

  \ 3) Crisp pre-rendered 2x title ("JINGLE BELLS") with shadow.
  140 24 NEW-IMAGE JB-TITLE-IMG !
  JB-TITLE-IMG @ DRAW-TO
  JB-KEY GFX-CLS
  2 TEXT-SCALE
  JB-DARK COLOR! S" JINGLE BELLS" 4 4 TEXT
  JB-GOLD COLOR! S" JINGLE BELLS" 2 2 TEXT
  1 TEXT-SCALE

  SCREEN DRAW-TO ;

: JB-FREE-ASSETS ( -- )
  JB-BG @        ?DUP IF FREE-IMAGE 0 JB-BG ! THEN
  JB-HILLS-IMG @ ?DUP IF FREE-IMAGE 0 JB-HILLS-IMG ! THEN
  JB-TITLE-IMG @ ?DUP IF FREE-IMAGE 0 JB-TITLE-IMG ! THEN ;

\ ---- Particle Pools ----------------------------------------------------------

\ 1) Sleigh magic stardust trail (18 entries: x, y).
18 CONSTANT JB-TRAIL-N
CREATE JB-TRAIL-X  JB-TRAIL-N CELLS ALLOT
CREATE JB-TRAIL-Y  JB-TRAIL-N CELLS ALLOT
VARIABLE JB-TRAIL-I

\ 2) Flying presents (10 entries x 8 cells: active, x16, y16, vx16, vy16, col, rib, kind).
10 CONSTANT JB-GIFT-N
8 CONSTANT /JB-GIFT
CREATE JB-GIFTS  JB-GIFT-N /JB-GIFT * CELLS ALLOT
: JB-GIFT@ ( i -- addr )  /JB-GIFT * CELLS JB-GIFTS + ;

\ 3) Landing confetti sparkle pops (10 entries x 4 cells: life, x, y, seed).
10 CONSTANT JB-POP-N
4 CONSTANT /JB-POP
CREATE JB-POPS  JB-POP-N /JB-POP * CELLS ALLOT
: JB-POP@ ( i -- addr )  /JB-POP * CELLS JB-POPS + ;

\ 4) Floating musical notes (10 entries x 5 cells: life, x, y, col, kind).
10 CONSTANT JB-NOTE-N
5 CONSTANT /JB-NOTE
CREATE JB-NOTES  JB-NOTE-N /JB-NOTE * CELLS ALLOT
: JB-NOTE@ ( i -- addr )  /JB-NOTE * CELLS JB-NOTES + ;

CREATE JB-GIFT-COLS
  JB-RED , JB-GREEN , JB-CYAN , JB-PINK , JB-ORANGE , $9A6BFF ,
CREATE JB-RIB-COLS
  JB-GOLD , JB-RED , JB-WHITE , JB-GOLD , JB-WHITE , JB-GOLD ,
CREATE JB-NOTE-COLS
  JB-GOLD , JB-PINK , JB-CYAN , JB-WHITE , $7CF5A4 ,

: JB-CLEAR-FX ( -- )
  JB-TRAIL-N 0 DO -9999 JB-TRAIL-X I CELLS + ! 0 JB-TRAIL-Y I CELLS + ! LOOP
  0 JB-TRAIL-I !
  JB-GIFTS JB-GIFT-N /JB-GIFT * CELLS ERASE
  JB-POPS  JB-POP-N  /JB-POP  * CELLS ERASE
  JB-NOTES JB-NOTE-N /JB-NOTE * CELLS ERASE ;

: JB-SAY ( id ticks -- )  JB-BUBBLE-T ! JB-BUBBLE-ID ! ;

: JB-SPAWN-POP { x y | p -- }
  JB-POP-N 0 DO
    I JB-POP@ TO p
    p @ 0= IF
      24 p !  x p 1 CELLS + !  y p 2 CELLS + !  1000 JB-RAND p 3 CELLS + !
      UNLOOP EXIT
    THEN
  LOOP ;

: JB-SPAWN-NOTE { x y | n -- }
  JB-NOTE-N 0 DO
    I JB-NOTE@ TO n
    n @ 0= IF
      46 n !
      x n 1 CELLS + !
      y n 2 CELLS + !
      5 JB-RAND CELLS JB-NOTE-COLS + @ n 3 CELLS + !
      2 JB-RAND n 4 CELLS + !
      UNLOOP EXIT
    THEN
  LOOP ;

: JB-SPAWN-GIFT { | g ci -- }
  JB-GIFT-N 0 DO
    I JB-GIFT@ TO g
    g @ 0= IF
      1 g !
      JB-X @ 14 + 16 * g 1 CELLS + !
      JB-Y @ 28 - 16 * g 2 CELLS + !
      36 JB-RAND 18 - g 3 CELLS + !      \ playful horizontal toss
      -42 18 JB-RAND - g 4 CELLS + !     \ cheerful upward pop
      6 JB-RAND TO ci
      ci CELLS JB-GIFT-COLS + @ g 5 CELLS + !
      ci CELLS JB-RIB-COLS  + @ g 6 CELLS + !
      3 JB-RAND 0= IF 1 ELSE 0 THEN g 7 CELLS + !  \ 1 in 3 opens a mini-parachute!
      10 JB-THROW-CD !
      UNLOOP EXIT
    THEN
  LOOP ;

: JB-UPDATE-POS ( -- )
  JB-TICK @ 2 * 600 + 900 MOD 240 - JB-X !
  134
  JB-TICK @ 2 / JB-SIN 20 * 100 / +
  JB-BOUNCE 2 / -
  JB-BAR# @ 7 = IF
    \ Joyous "HEY!!" skyward leap on bar 7!
    JB-BAR-TICK @ 56 - ABS 56 SWAP - 0 MAX 2 / -
  THEN
  JB-Y ! ;

: JB-ON-BAR ( -- )
  JB-BAR# @ DUP 0 = IF DROP 1 75 JB-SAY JB-SPAWN-GIFT EXIT THEN
  DUP 3 = IF DROP 2 85 JB-SAY JB-SPAWN-GIFT JB-SPAWN-GIFT EXIT THEN
  DUP 7 = IF DROP 3 95 JB-SAY JB-SPAWN-GIFT JB-SPAWN-GIFT JB-SPAWN-GIFT EXIT THEN
  DUP 11 = IF DROP 2 85 JB-SAY JB-SPAWN-GIFT JB-SPAWN-GIFT EXIT THEN
  DUP 14 = IF DROP 1 70 JB-SAY JB-SPAWN-GIFT JB-SPAWN-GIFT EXIT THEN
  15 = IF 4 115 JB-SAY JB-SPAWN-GIFT JB-SPAWN-GIFT JB-SPAWN-GIFT THEN ;

: JB-STEP ( -- )
  JB-UPDATE-POS
  JB-THROW-CD @ 0> IF -1 JB-THROW-CD +! THEN
  JB-BUBBLE-T @ 0> IF -1 JB-BUBBLE-T +! THEN

  \ Record stardust trail every 2 frames behind sleigh runners.
  JB-TICK @ 1 AND 0= IF
    JB-TRAIL-I @ { ti }
    JB-X @ 16 - JB-TRAIL-X ti CELLS + !
    JB-Y @ 16 + JB-TRAIL-Y ti CELLS + !
    ti 1+ JB-TRAIL-N MOD JB-TRAIL-I !
  THEN

  \ On every beat: spawn musical notes and drop a gift over the village.
  JB-GLOBAL-BEAT DUP JB-LAST-BEAT @ <> IF
    JB-LAST-BEAT !
    JB-X @ -80 540 WITHIN IF
      JB-X @ 180 + JB-Y @ 38 - JB-SPAWN-NOTE
      JB-X @ 112 + JB-Y @ 26 - JB-SPAWN-NOTE
    THEN
    JB-X @ -10 560 WITHIN IF JB-SPAWN-GIFT THEN
  ELSE
    DROP
  THEN

  \ Extra rhythmic sparkle note mid-beat during big moments.
  JB-BEAT-PH 14 = JB-BIG-BAR? AND JB-X @ -40 520 WITHIN AND IF
    JB-X @ 48 + JB-Y @ 56 - JB-SPAWN-NOTE
  THEN

  \ Step flying presents.
  JB-GIFT-N 0 DO
    I JB-GIFT@ { g }
    g @ IF
      g 1 CELLS + @ g 3 CELLS + @ + g 1 CELLS + !
      g 2 CELLS + @ g 4 CELLS + @ + g 2 CELLS + !
      g 7 CELLS + @ IF
        \ Parachute gift slows down and sways gently side-to-side.
        g 4 CELLS + @ 3 + 18 MIN g 4 CELLS + !
        g 4 CELLS + @ 10 > IF
          JB-TICK @ I 11 * + JB-SIN 16 * 100 / g 3 CELLS + !
        THEN
      ELSE
        \ Tumbling gift with gravity.
        g 4 CELLS + @ 4 + 90 MIN g 4 CELLS + !
      THEN
      g 2 CELLS + @ 16 / 326 >= IF
        g 1 CELLS + @ 16 / 326 JB-SPAWN-POP
        0 g !
      THEN
    THEN
  LOOP

  \ Step confetti pops.
  JB-POP-N 0 DO
    I JB-POP@ { p }
    p @ 0> IF -1 p +! THEN
  LOOP

  \ Step floating musical notes.
  JB-NOTE-N 0 DO
    I JB-NOTE@ { n }
    n @ 0> IF
      -1 n +!
      -1 n 2 CELLS + +!
    THEN
  LOOP ;

\ ---- Sky, Aurora, Stars & Jolly Moon -----------------------------------------

: JB-SKY ( -- )
  \ Blit smooth pre-rendered night sky gradient.
  -1 TRANSPARENT  JB-BG @ 0 0 PUT-IMAGE

  \ Shimmering Aurora Borealis ribbons undulating across the upper sky.
  32 0 DO
    I 5 * JB-TICK @ 3 / + JB-SIN 14 * 100 / 62 +
    I 9 * JB-TICK @ 2 / - JB-SIN 8 * 100 / 24 + { ay ah }
    $12415E COLOR! I 20 * ay 6 - 20 ah 12 + FILL-RECT
    $1C6F70 COLOR! I 20 * ay 20 ah FILL-RECT
    I 3 * JB-TICK @ 2 / + JB-SIN 0> IF
      $2B9986 COLOR! I 20 * ay 5 + 20 ah 2 / FILL-RECT
    THEN
  LOOP

  \ Twinkling stars and pulsing 4-point sparkles.
  64 0 DO
    I 137 * 29 + 640 MOD  I 71 * 13 + 225 MOD { sx sy }
    I JB-TICK @ 10 / + 9 MOD 0= IF
      JB-GOLD COLOR! sx sy 2 JB-SPARKLE
    ELSE
      I JB-TICK @ 14 / + 5 MOD 0= IF JB-SNOW ELSE $8CA8D0 THEN COLOR!
      sx sy 1 JB-DISC
    THEN
  LOOP

  \ Occasional golden shooting star streaking across the sky.
  JB-TICK @ 190 MOD DUP 22 < IF
    { st }
    460 st 14 * -  24 st 4 * + { x y }
    JB-GOLD COLOR! x y x 26 + y 8 - LINE
    JB-WHITE COLOR! x y 2 JB-DISC
  ELSE DROP THEN

  \ Jolly crescent moon with glowing halo, winking smile, and Santa nightcap!
  $162E60 COLOR! 556 64 34 JB-DISC
  $22427A COLOR! 556 64 28 JB-DISC
  JB-WHITE COLOR! 556 64 23 JB-DISC
  $162E60 COLOR! 544 58 19 JB-DISC
  \ Cute smiling face on the crescent.
  JB-DARK COLOR!
  JB-TICK @ 95 MOD 14 < IF
    563 60 568 60 LINE                   \ cheeky wink!
  ELSE
    566 60 2 JB-DISC
  THEN
  $F29CA8 COLOR! 570 66 2 JB-DISC        \ rosy cheek
  JB-DARK COLOR! 561 69 566 71 LINE  566 71 570 69 LINE
  \ Jaunty little Santa nightcap perched on top of the moon.
  JB-TICK @ 4 / JB-SIN 3 * 100 / { mp }
  JB-RED COLOR! 563 30 10 15 JB-TRI
  JB-RED COLOR! 565 32 580 35 mp + LINE
  JB-RED COLOR! 565 33 580 36 mp + LINE
  JB-SNOW COLOR! 552 43 21 5 FILL-RECT
  JB-SNOW COLOR! 581 36 mp + 4 JB-DISC ;

\ ---- Fireworks (Bars 14-15 Finale & Bar 7 "HEY!!") ---------------------------

: JB-FIREWORK { cx cy phase col1 col2 | r dx dy -- }
  phase 0 36 WITHIN 0= IF EXIT THEN
  phase 2 * 4 + TO r
  12 0 DO
    I 5 * JB-COS r * 100 / TO dx
    I 5 * JB-SIN r * 100 / TO dy
    I 1 AND IF col1 ELSE col2 THEN COLOR!
    cx dx 2 / +  cy dy 2 / +  cx dx +  cy dy +  LINE
    phase 22 < IF
      JB-WHITE COLOR! cx dx + cy dy + 1 JB-DISC
    THEN
  LOOP ;

: JB-DRAW-FIREWORKS ( -- )
  JB-BAR# @ 7 = IF
    120 82  JB-BAR-TICK @ 4 -   JB-GOLD JB-PINK JB-FIREWORK
    495 112 JB-BAR-TICK @ 24 -  JB-CYAN JB-GOLD JB-FIREWORK
  THEN
  JB-BAR# @ 14 >= IF
    115 92  JB-TICK @ 48 MOD        JB-GOLD JB-RED  JB-FIREWORK
    320 74  JB-TICK @ 18 + 48 MOD   JB-CYAN JB-SNOW JB-FIREWORK
    465 104 JB-TICK @ 34 + 48 MOD   JB-PINK JB-GOLD JB-FIREWORK
  THEN ;

\ ---- Parallax Hills, Village, Trees & Dancing Snowmen ------------------------

: JB-HILLS ( -- )
  JB-TICK @ 4 / 640 MOD { s }
  JB-KEY TRANSPARENT
  JB-HILLS-IMG @ s 0 640 s - 120 0 218 COPY-RECT
  s 0> IF JB-HILLS-IMG @ 0 0 s 120 640 s - 218 COPY-RECT THEN
  -1 TRANSPARENT ;

: JB-SMOKE { x y phase -- }
  3 0 DO
    phase I 14 * + 42 MOD { t }
    $D6E6F5 COLOR!
    x t 2 / -  y t -  3 t 14 / +  JB-DISC
  LOOP ;

: JB-COTTAGE { x y w h body roof light-seed -- }
  \ Chimney & animated puffing smoke.
  x w + 15 - y 23 - JB-TICK @ 2 / light-seed 7 * + JB-SMOKE
  $7C393B COLOR! x w + 19 - y 21 - 9 21 FILL-RECT
  JB-SNOW COLOR! x w + 20 - y 23 - 11 3 FILL-RECT
  \ House body.
  body COLOR! x y w h FILL-RECT
  \ Cozy pitched snow-blanketed roof!
  JB-SNOW COLOR! x w 2 / + y 30 - w 2 / 8 + 30 JB-TRI
  roof    COLOR! x w 2 / + y 23 - w 2 / 7 + 24 JB-TRI
  \ Fluffy snow eaves.
  JB-SNOW COLOR! x 6 - y 2 - w 12 + 4 FILL-RECT
  \ Warm glowing paned windows.
  JB-BEAT-PH 10 < IF $FFE484 ELSE JB-GOLD THEN COLOR!
  x 7 + y 11 + 11 12 FILL-RECT
  x w + 18 - y 11 + 11 12 FILL-RECT
  body COLOR!
  x 12 + y 11 + x 12 + y 22 + LINE
  x 7 + y 17 + x 17 + y 17 + LINE
  x w + 13 - y 11 + x w + 13 - y 22 + LINE
  x w + 18 - y 17 + x w + 8 - y 17 + LINE
  \ Cozy wooden door + tiny Christmas wreath!
  $5A3324 COLOR! x w 2 / + 6 - y h + 19 - 12 19 FILL-RECT
  JB-GREEN COLOR! x w 2 / + y h + 11 - 3 JB-DISC
  JB-RED COLOR! x w 2 / + y h + 14 - 1 JB-DISC
  \ Colorful blinking Christmas fairy lights along the eaves!
  6 0 DO
    I JB-GLOBAL-BEAT + light-seed + 4 MOD
    DUP 0= IF DROP JB-RED ELSE
    DUP 1 = IF DROP JB-GOLD ELSE
    DUP 2 = IF DROP JB-CYAN ELSE
    DROP JB-PINK THEN THEN THEN COLOR!
    x 3 - I 11 * + y 2 + 2 JB-DISC
  LOOP ;

: JB-TREE { x y phase | sway -- }
  JB-TICK @ 4 / phase + JB-SIN 2 * 100 / TO sway
  \ Trunk.
  $5E3A24 COLOR! x 4 - y 20 + 8 20 FILL-RECT
  \ Three layered pine tiers with snow tips.
  JB-GREEN-DK COLOR! x sway 2 / + y 2 - 22 26 JB-TRI
  JB-GREEN    COLOR! x sway +     y 16 - 18 22 JB-TRI
  JB-GREEN    COLOR! x sway +     y 32 - 13 19 JB-TRI
  JB-SNOW     COLOR! x sway +     y 32 - 5 6 JB-TRI
  \ Blinking ornaments.
  JB-GLOBAL-BEAT phase + 1 AND IF JB-RED ELSE JB-CYAN THEN COLOR!
  x 7 - sway + y 4 + 2 JB-DISC
  x 8 + sway + y 14 + 2 JB-DISC
  JB-GLOBAL-BEAT phase + 1 AND IF JB-GOLD ELSE JB-PINK THEN COLOR!
  x 6 + sway + y 8 - 2 JB-DISC
  x 9 - sway + y 16 + 2 JB-DISC
  JB-PINK COLOR! x sway + y 12 + 2 JB-DISC
  \ Glowing star on top!
  JB-GOLD COLOR! x sway + y 34 - JB-BOUNCE 5 > IF 4 ELSE 3 THEN JB-SPARKLE
  JB-WHITE COLOR! x sway + y 34 - 1 JB-DISC ;

: JB-SNOWMAN { x y phase | hop arm hat-lift scarf -- }
  \ Bounces enthusiastically on every beat, leaps extra high on big bars!
  JB-BOUNCE JB-BIG-BAR? IF 2 * THEN
  phase 1 AND IF JB-BEAT-PH 14 - ABS 14 SWAP - 0 MAX 2 / MAX THEN
  TO hop
  hop 2 / TO hat-lift
  JB-GLOBAL-BEAT phase + 1 AND IF -10 ELSE 6 THEN TO arm
  phase 1 AND IF JB-CYAN ELSE JB-RED THEN TO scarf
  \ Soft shadow on snow.
  JB-ICE COLOR! x 9 - y 9 + 18 4 FILL-RECT
  \ Plump snowballs.
  JB-SNOW COLOR!
  x y hop - 11 JB-DISC
  x y 15 - hop - 8 JB-DISC
  x y 27 - hop - 6 JB-DISC
  \ Waving stick arms with bright colorful mittens!
  $6E472B COLOR!
  x 7 - y 16 - hop -  x 17 - y 15 - hop - arm +  LINE
  x 7 - y 15 - hop -  x 17 - y 14 - hop - arm +  LINE
  x 7 + y 16 - hop -  x 17 + y 15 - hop - arm -  LINE
  x 7 + y 15 - hop -  x 17 + y 14 - hop - arm -  LINE
  scarf COLOR!
  x 18 - y 14 - hop - arm + 2 JB-DISC
  x 18 + y 14 - hop - arm - 2 JB-DISC
  \ Colorful fluttering scarf.
  x 6 - y 21 - hop - 12 3 FILL-RECT
  x 4 + y 23 - hop - 3 7 FILL-RECT
  \ Coal eyes, smile, buttons & carrot nose.
  JB-DARK COLOR!
  x 2 - y 29 - hop - 1 JB-DISC
  x 2 + y 29 - hop - 1 JB-DISC
  x y 16 - hop - 1 JB-DISC
  x y 11 - hop - 1 JB-DISC
  JB-ORANGE COLOR!
  x y 27 - hop - x 7 + y 26 - hop - LINE
  x y 26 - hop - x 7 + y 26 - hop - LINE
  \ Top hat that pops playfully off his head when jumping!
  JB-DARK COLOR!
  x 8 - y 34 - hop - hat-lift - 16 2 FILL-RECT
  x 5 - y 42 - hop - hat-lift - 10 8 FILL-RECT
  JB-RED COLOR!
  x 5 - y 36 - hop - hat-lift - 10 2 FILL-RECT ;

: JB-GROUND-BACK ( -- )
  $D8ECF9 COLOR! 0 326 640 34 FILL-RECT
  JB-SNOW COLOR! 0 331 640 29 FILL-RECT ;

: JB-VILLAGE ( -- )
  JB-TICK @ 2 / { s }
  9 0 DO
    I 100 * s - 900 + 900 MOD 100 - { vx }
    I 3 MOD
    DUP 0= IF DROP
      vx 284 52 46 $8E5B3C JB-RED-DK I JB-COTTAGE
    ELSE DUP 1 = IF DROP
      vx 18 + 292 I JB-TREE
      vx 66 + 322 I JB-SNOWMAN
    ELSE DROP
      vx 278 54 52 $3A527A $6F364C I JB-COTTAGE
    THEN THEN
  LOOP ;

: JB-GROUND-FRONT ( -- )
  \ Gentle low snowdrifts along the very bottom edge (leaving doors & snowmen visible!).
  JB-TICK @ 2 / { s }
  9 0 DO
    I 95 * s - 855 + 855 MOD 95 - { gx }
    $F6FBFF COLOR! gx 372 34 JB-DISC
  LOOP
  JB-ICE COLOR! 0 353 640 7 FILL-RECT ;

\ ---- Santa, Overflowing Sleigh & Prancing Reindeer ---------------------------

: JB-DEER { x y phase rudolph? | bob kick1 kick2 ear-y -- }
  \ Dynamic gallop bounce & 4-leg kicking cycle!
  JB-TICK @ 2 * phase + JB-SIN 7 * 100 /
  JB-BAR# @ 7 = IF 5 - THEN TO bob
  JB-TICK @ 3 * phase + JB-SIN 11 * 100 / TO kick1
  JB-TICK @ 3 * phase + 32 + JB-SIN 11 * 100 / TO kick2
  y bob + TO y
  y 17 - TO ear-y

  \ Far legs (darker brown for depth).
  $8A5A32 COLOR!
  x 6 +  y 11 +  x 2 + kick2 -  y 29 +  JB-LINE
  x 7 +  y 11 +  x 3 + kick2 -  y 29 +  JB-LINE
  x 25 + y 11 +  x 29 + kick1 + y 29 +  JB-LINE
  x 26 + y 11 +  x 30 + kick1 + y 29 +  JB-LINE

  \ Fluffy wagging white tail!
  JB-SNOW COLOR!
  x 3 -  y 2 + JB-TICK @ 4 * phase + JB-SIN 2 * 100 / +  3 JB-CIRCLE

  \ Body & tan belly.
  JB-BROWN COLOR! x y 32 14 JB-RECT
  x 3 + y 7 + 7 JB-CIRCLE
  x 28 + y 7 + 7 JB-CIRCLE
  JB-TAN COLOR! x 7 + y 8 + 18 6 JB-RECT

  \ Near legs with lively hooves!
  JB-BROWN COLOR!
  x 5 +  y 11 +  x 1 + kick1 -  y 29 +  JB-LINE
  x 6 +  y 11 +  x 2 + kick1 -  y 29 +  JB-LINE
  x 24 + y 11 +  x 28 + kick2 + y 29 +  JB-LINE
  x 25 + y 11 +  x 29 + kick2 + y 29 +  JB-LINE
  JB-DARK COLOR!
  x 1 + kick1 -  y 29 + 2 JB-CIRCLE
  x 28 + kick2 + y 29 + 2 JB-CIRCLE

  \ Neck, head, snout & perked ear.
  JB-BROWN COLOR!
  x 26 + y 12 - 9 20 JB-RECT
  x 35 + y 11 - 8 JB-CIRCLE
  x 42 + y 9 -  5 JB-CIRCLE
  x 29 + ear-y  3 JB-CIRCLE

  \ Branching golden antlers.
  JB-GOLD COLOR!
  x 32 + y 18 - x 27 + y 32 - JB-LINE
  x 29 + y 25 - x 22 + y 28 - JB-LINE
  x 28 + y 27 - x 33 + y 34 - JB-LINE
  x 36 + y 18 - x 39 + y 30 - JB-LINE
  x 38 + y 25 - x 44 + y 27 - JB-LINE

  \ Cheerful bright eye & smile.
  JB-SNOW COLOR! x 37 + y 13 - 2 JB-CIRCLE
  JB-DARK COLOR! x 38 + y 13 - 1 JB-CIRCLE
  x 40 + y 7 - x 44 + y 8 - JB-LINE

  \ Festive red collar + jingling gold bell!
  JB-RED COLOR! x 25 + y 2 - 11 4 JB-RECT
  JB-GOLD COLOR! x 29 + y 4 + 3 JB-CIRCLE
  JB-BOUNCE 5 > IF
    JB-WHITE COLOR! x 24 + y 5 + x 22 + y 7 + JB-LINE
    x 34 + y 5 + x 36 + y 7 + JB-LINE
  THEN

  \ Rudolph's glowing red beacon nose!
  rudolph? IF
    $781E38 COLOR! x 48 + y 9 - JB-BOUNCE 3 / 8 + JB-CIRCLE
    $C42A44 COLOR! x 48 + y 9 - JB-BOUNCE 4 / 5 + JB-CIRCLE
    JB-RED  COLOR! x 48 + y 9 - 4 JB-CIRCLE
    JB-PINK COLOR! x 47 + y 10 - 1 JB-CIRCLE
    \ Twinkling headlight sparkles ahead of Rudolph's nose!
    JB-BOUNCE 4 > IF
      JB-GOLD COLOR!
      JB-X @ x 58 + + JB-Y @ y 9 - + 3 JB-SPARKLE
      JB-PINK COLOR!
      JB-X @ x 67 + + JB-Y @ y 14 - + 2 JB-SPARKLE
    THEN
  ELSE
    JB-DARK COLOR! x 47 + y 9 - 2 JB-CIRCLE
  THEN ;

: JB-DRAW-TRAIL ( -- )
  JB-TRAIL-N 0 DO
    JB-TRAIL-X I CELLS + @  JB-TRAIL-Y I CELLS + @ { tx ty }
    tx 0 640 WITHIN IF
      I JB-TICK @ 2 / + 3 MOD
      DUP 0= IF DROP JB-GOLD
      ELSE DUP 1 = IF DROP JB-WHITE
      ELSE DROP JB-CYAN THEN THEN COLOR!
      tx  ty I 3 AND 2 * +
      I 1 AND IF 2 JB-SPARKLE ELSE 1 JB-DISC THEN
    THEN
  LOOP ;

: JB-BUBBLE-STR ( id -- addr u )
  DUP 1 = IF DROP S" JINGLE!"     EXIT THEN
  DUP 2 = IF DROP S" HO HO HO!"   EXIT THEN
  DUP 3 = IF DROP S" HEY!!"       EXIT THEN
  DROP            S" MERRY XMAS!" ;

: JB-BUBBLE { | bx by bw id addr u -- }
  JB-BUBBLE-T @ 0<= IF EXIT THEN
  JB-X @ 10 490 WITHIN 0= IF EXIT THEN
  JB-BUBBLE-ID @ TO id
  id JB-BUBBLE-STR TO u TO addr
  addr u TEXT-WIDTH 16 + TO bw
  JB-X @ 46 + bw 2 / - TO bx
  JB-Y @ 106 - JB-BOUNCE 2 / - TO by
  \ Crisp fitted speech bubble + border + pointer toward Santa.
  JB-DARK COLOR! bx 1- by 2 - bw 2 + 22 FILL-RECT
  JB-DARK COLOR! bx 2 - by 1- bw 4 + 20 FILL-RECT
  JB-SNOW COLOR! bx by bw 18 FILL-RECT
  JB-SNOW COLOR!
  bx bw 2 / + 4 - by 18 +  bx bw 2 / + 1+ by 25 + LINE
  bx bw 2 / + 3 - by 18 +  bx bw 2 / + 1+ by 25 + LINE
  bx bw 2 / + 2 - by 18 +  bx bw 2 / + 1+ by 25 + LINE
  \ Centered cheerful text!
  id 3 = IF JB-RED ELSE JB-RED-DK THEN COLOR!
  addr u bx 8 + by 5 + TEXT ;

: JB-SANTA { | arm pom laugh d1y d2y -- }
  JB-TICK @ 3 * JB-SIN 11 * 100 /
  JB-THROW-CD @ 0> IF 8 - THEN TO arm
  JB-TICK @ 3 * 20 + JB-SIN 5 * 100 / TO pom
  JB-BOUNCE 4 > JB-BUBBLE-T @ 0> OR TO laugh
  JB-TICK @ 2 * JB-SIN 7 * 100 / JB-BAR# @ 7 = IF 5 - THEN TO d1y
  JB-TICK @ 2 * 22 + JB-SIN 7 * 100 / JB-BAR# @ 7 = IF 5 - THEN TO d2y

  \ Overflowing gift sack & colorful presents behind Santa (jiggle on beat!).
  JB-GREEN-DK COLOR! 10 -24 JB-BOUNCE 3 / - 21 JB-CIRCLE
  JB-GREEN    COLOR! 12 -26 JB-BOUNCE 3 / - 17 JB-CIRCLE
  JB-GOLD     COLOR! 4 -42 JB-BOUNCE 3 / - 17 5 JB-RECT
  \ Colorful peeking gifts in the sack.
  JB-CYAN     COLOR! -6 -22 16 18 JB-RECT
  JB-GOLD     COLOR!  0 -22  3 18 JB-RECT
  JB-PINK     COLOR! 16 -46 JB-BOUNCE 2 / - 13 12 JB-RECT
  JB-WHITE    COLOR! 21 -46 JB-BOUNCE 2 / -  3 12 JB-RECT

  \ Santa's plump coat, white trim, belt & shiny gold buckle.
  JB-RED    COLOR! 42 -24 19 JB-CIRCLE
  JB-SNOW   COLOR! 36 -34 14 5 JB-RECT
  JB-DARK   COLOR! 26 -16 34 5 JB-RECT
  JB-GOLD   COLOR! 44 -17  8 7 JB-RECT
  JB-DARK   COLOR! 46 -15  4 3 JB-RECT

  \ Santa's cheerful head, rosy cheeks, fluffy beard & laughing mouth!
  JB-SKIN   COLOR! 45 -50 11 JB-CIRCLE
  JB-PINK   COLOR! 51 -47  3 JB-CIRCLE
  JB-SNOW   COLOR! 43 -41 11 JB-CIRCLE
  JB-SNOW   COLOR! 38 -36  8 JB-CIRCLE
  JB-SNOW   COLOR! 49 -38  7 JB-CIRCLE
  \ Laughing mouth & happy squinting eyes.
  laugh IF
    $8E1B2B COLOR! 49 -44 3 JB-CIRCLE
    JB-DARK COLOR! 47 -53 50 -55 JB-LINE  50 -55 53 -53 JB-LINE
  ELSE
    JB-DARK COLOR! 49 -53 2 JB-CIRCLE
    47 -44 51 -43 JB-LINE
  THEN

  \ Santa hat with bouncing floppy tail & pom-pom!
  JB-RED  COLOR! 31 -69 24 10 JB-RECT  23 -66 12 9 JB-RECT
  JB-RED  COLOR! 24 -64 16 -59 pom + JB-LINE
  JB-RED  COLOR! 24 -63 16 -58 pom + JB-LINE
  JB-SNOW COLOR! 30 -60 28 5 JB-RECT
  JB-SNOW COLOR! 16 -58 pom + 5 JB-CIRCLE

  \ Energetic waving / gift-tossing arm!
  JB-RED  COLOR! 54 -34 69 -46 arm + JB-LINE
  JB-RED  COLOR! 54 -33 69 -45 arm + JB-LINE
  JB-RED  COLOR! 54 -32 69 -44 arm + JB-LINE
  JB-SNOW COLOR! 66 -43 arm + 4 JB-CIRCLE
  JB-RED  COLOR! 70 -46 arm + 5 JB-CIRCLE

  \ Crimson sleigh bowl, decorative gold scroll & runners!
  JB-RED-DK COLOR! -10 -1 84 20 JB-RECT
  JB-RED    COLOR!  -8 -4 81 18 JB-RECT  68 -18 14 27 JB-RECT
  JB-GOLD   COLOR! -12 -5 95  3 JB-RECT
  JB-GOLD   COLOR!  76 -19 6 JB-CIRCLE
  JB-RED    COLOR!  76 -19 3 JB-CIRCLE
  \ Little gold bell hanging on the front prow.
  JB-GOLD   COLOR! 84 -10 JB-BOUNCE 3 / - 3 JB-CIRCLE
  \ Runners & struts.
  JB-GOLD   COLOR!
  3 17 3 25 JB-LINE  4 17 4 25 JB-LINE
  58 17 58 25 JB-LINE  59 17 59 25 JB-LINE
  -18 25 82 25 JB-LINE  -18 26 82 26 JB-LINE
  82 25 94 14 JB-LINE  82 26 94 15 JB-LINE
  94 14 93 7 JB-LINE

  \ Dynamic golden reins linking Santa to both prancing reindeer.
  JB-GOLD COLOR!
  62 -26  135 -16 d1y +  JB-LINE
  135 -16 d1y +  208 -26 d2y +  JB-LINE

  \ Two prancing reindeer: Dasher & glowing-nosed Rudolph in front!
  106 -16 0  FALSE JB-DEER
  179 -26 22 TRUE  JB-DEER
  JB-BUBBLE ;

\ ---- Render Flying Presents, Parachutes, Confetti & Musical Notes ------------

: JB-DRAW-GIFTS ( -- )
  JB-GIFT-N 0 DO
    I JB-GIFT@ { g }
    g @ IF
      g 1 CELLS + @ 16 /  g 2 CELLS + @ 16 /
      g 5 CELLS + @  g 6 CELLS + @  g 7 CELLS + @ { gx gy col rib kind }
      \ Cute striped mini-parachute when opened (crisp half-dome, no cutout!).
      kind g 4 CELLS + @ 10 > AND IF
        JB-SNOW COLOR!
        gx 3 - gy 16 - gx 1 + gy LINE
        gx 15 + gy 16 - gx 11 + gy LINE
        gx 6 + gy 16 - gx 6 + gy LINE
        JB-RED  COLOR! gx 6 + gy 16 - 11 JB-DOME
        JB-SNOW COLOR! gx 6 + gy 16 -  7 JB-DOME
        JB-RED  COLOR! gx 6 + gy 16 -  3 JB-DOME
        JB-GOLD COLOR! gx 5 - gx 17 + gy 16 - JB-GOLD GFX-HLINE
      THEN
      \ Wrapped gift box + cross ribbon + bow!
      col COLOR! gx gy 12 11 FILL-RECT
      rib COLOR! gx 5 + gy 2 11 FILL-RECT
      gx gy 4 + 12 2 FILL-RECT
      gx 4 + gy 2 - 2 JB-DISC
      gx 8 + gy 2 - 2 JB-DISC
    THEN
  LOOP ;

: JB-DRAW-POPS ( -- )
  JB-POP-N 0 DO
    I JB-POP@ { p }
    p @ 0> IF
      24 p @ -  p 1 CELLS + @  p 2 CELLS + @  p 3 CELLS + @ { age px py seed }
      8 0 DO
        I 8 * seed + JB-COS age * 50 / px +
        I 8 * seed + JB-SIN age * 60 / py + age - { sx sy }
        I 4 MOD
        DUP 0= IF DROP JB-GOLD ELSE
        DUP 1 = IF DROP JB-PINK ELSE
        DUP 2 = IF DROP JB-CYAN ELSE
        DROP JB-WHITE THEN THEN THEN COLOR!
        sx sy age 12 < IF 2 JB-SPARKLE ELSE 1 JB-DISC THEN
      LOOP
    THEN
  LOOP ;

: JB-DRAW-NOTES ( -- )
  JB-NOTE-N 0 DO
    I JB-NOTE@ { n }
    n @ 0> IF
      n 1 CELLS + @  JB-TICK @ 2 * I 9 * + JB-SIN 5 * 100 / +
      n 2 CELLS + @
      n 3 CELLS + @
      n 4 CELLS + @
      JB-DRAW-NOTE
    THEN
  LOOP ;

\ ---- Foreground Snow & Swinging Jingle Bells HUD -----------------------------

: JB-DRAW-SNOW ( -- )
  \ Two-layer parallax drifting snow with gentle wind sway.
  55 0 DO
    I 97 * JB-TICK @ +  I 5 * JB-TICK @ 2 / + JB-SIN 10 * 100 / +  640 + 640 MOD
    I 43 * JB-TICK @ I 3 AND 1+ * + 356 MOD { fx fy }
    I 5 MOD 0= IF
      JB-SNOW COLOR! fx fy 2 JB-DISC
    ELSE
      JB-WHITE COLOR! fx fy 1 JB-DISC
    THEN
  LOOP ;

: JB-HUD-BELL { cx cy sw -- }
  \ Swinging golden bell.
  JB-GOLD-DK COLOR! cx sw + cy 10 + 7 JB-DISC
  JB-GOLD    COLOR! cx sw + cy  8 + 6 JB-DISC
  JB-GOLD    COLOR! cx sw 2 / + cy 1 + 4 JB-DISC
  JB-WHITE   COLOR! cx sw + 2 - cy 7 + 1 JB-DISC
  JB-GOLD-DK COLOR! cx sw + cy 16 + 2 JB-DISC ;

: JB-HUD ( -- )
  \ Swinging pair of Jingle Bells with red ribbon & holly leaves!
  JB-TICK @ 2 * JB-SIN 5 * 100 / { sw }
  30 16 sw JB-HUD-BELL
  46 16 sw NEGATE JB-HUD-BELL
  \ Holly leaves & bow.
  JB-GREEN COLOR! 25 14 4 JB-DISC  51 14 4 JB-DISC
  JB-RED   COLOR! 38 14 4 JB-DISC  33 17 3 JB-DISC  43 17 3 JB-DISC
  \ Ringing motion ticks on the beat!
  JB-BOUNCE 5 > IF
    JB-WHITE COLOR!
    17 24 13 22 LINE  17 29 13 31 LINE
    59 24 63 22 LINE  59 29 63 31 LINE
  THEN
  \ Bouncy festive pre-rendered title!
  JB-KEY TRANSPARENT
  JB-TITLE-IMG @ 63 10 JB-BOUNCE 3 / - PUT-IMAGE
  -1 TRANSPARENT
  $B9D2F0 COLOR! S" Space: gift!  Q / Esc: close" 65 32 TEXT ;

\ ---- Full Frame Composition --------------------------------------------------

: JB-DRAW ( -- )
  JB-SKY
  JB-DRAW-FIREWORKS
  JB-HILLS
  JB-GROUND-BACK
  JB-VILLAGE
  JB-GROUND-FRONT
  JB-DRAW-TRAIL
  JB-DRAW-GIFTS
  JB-DRAW-POPS
  JB-SANTA
  JB-DRAW-NOTES
  JB-DRAW-SNOW
  JB-HUD ;

\ ---- Input, Music & Main Loop ------------------------------------------------

: JB-KEYS ( -- )
  WINDOW-CLOSES JB-CLOSES @ <> IF TRUE JB-STOP ! THEN
  BEGIN INKEY DUP -1 <> WHILE
    DUP 27 = OVER [CHAR] q = OR OVER [CHAR] Q = OR IF
      DROP TRUE JB-STOP !
    ELSE 32 = IF
      \ Space bar: Santa laughs and tosses an extra shower of gifts!
      JB-SPAWN-GIFT JB-SPAWN-GIFT
      2 55 JB-SAY
    THEN THEN
  REPEAT DROP ;

\ Wait on the actual audio queue while continuing to animate and handle keys.
: JB-WAIT ( -- )
  BEGIN
    JB-KEYS
    JB-STEP
    JB-DRAW
    16 FRAME
    1 JB-TICK +!  1 JB-BAR-TICK +!
    0 PLAY? 0= JB-STOP @ OR
  UNTIL ;

: JB-BAR ( melody-addr melody-u bass-addr bass-u -- )
  JB-STOP @ IF 2DROP 2DROP EXIT THEN
  1 JB-BAR# +!  0 JB-BAR-TICK !
  JB-ON-BAR
  PLAY2 JB-WAIT ;

: JB-MUSIC ( -- )
  1 INSTRUMENT TRIANGLE 2 160 5000 100 ADSR
  2 INSTRUMENT TRIANGLE 5 80 24000 80 ADSR
  BEGIN
    -1 JB-BAR# !
    S" T132 O5 L4 V12 @1" S" T132 O2 L4 V8 @2" PLAY2
    S" E E E2" S" C G >C< G" JB-BAR
    S" E E E2" S" C G >C< G" JB-BAR
    S" E G C D" S" C G >C< G" JB-BAR
    S" E1" S" C G >C< G" JB-BAR
    S" F F F F" S" F >C F C<" JB-BAR
    S" F E E E8 E8" S" C G >C< G" JB-BAR
    S" E D D E" S" G >D G D<" JB-BAR
    S" D2 G2" S" G >D G D<" JB-BAR
    S" E E E2" S" C G >C< G" JB-BAR
    S" E E E2" S" C G >C< G" JB-BAR
    S" E G C D" S" C G >C< G" JB-BAR
    S" E1" S" C G >C< G" JB-BAR
    S" F F F F" S" F >C F C<" JB-BAR
    S" F E E E8 E8" S" C G >C< G" JB-BAR
    S" G G F D" S" G >D G D<" JB-BAR
    S" C1" S" C2 >C2<" JB-BAR
    JB-STOP @
  UNTIL ;

: JINGLE-BELLS ( -- )
  0 JB-TICK !  -1 JB-BAR# !  0 JB-BAR-TICK !
  -1 JB-LAST-BEAT !  0 JB-THROW-CD !  0 JB-BUBBLE-T !
  1225 JB-RNG !  FALSE JB-STOP !
  JB-CLEAR-FX
  640 360 GFX-INIT  960 540 WINDOW-SIZE
  JB-INIT-ASSETS
  WINDOW-CLOSES JB-CLOSES !
  JB-UPDATE-POS  JB-DRAW  0 FRAME
  CR ." Jingle Bells - Space: gift!  Q / Esc: close" CR
  JB-MUSIC 0 PLAYS
  JB-FREE-ASSETS ;

JINGLE-BELLS BYE
