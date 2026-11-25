\ Breadth-first search on a byte board.
\ Load definitions before TASK-SNAPSHOT. No host operations in worker code.
\ Input cells: generation, width (64..256), start, goal; then width^2 bytes.
\ Zero is walkable. Result cells: generation, vertex count; then 32-bit LE
\ vertex IDs, goal first and start last. Count zero means unreachable/invalid.
\ Neighbours are tried left, right, up, down; the first visit fixes the parent.
\ The board is copied into a 258-wide grid walled on every side, so the inner
\ loop needs no bounds tests. A grid byte is 0 free, 1 wall, or 2..6 visited:
\ the move that reached it (2 left, 3 right, 4 up, 5 down; 6 start).
REQUIRE-EXTENSION ALSO EXTENSION
258 CONSTANT TP-P
CREATE TP-GRID 66564 ALLOT ALIGN
CREATE TP-QUEUE 65536 CELLS ALLOT
CREATE TP-RESULT 262160 ALLOT
VARIABLE TP-BOARD VARIABLE TP-W VARIABLE TP-N VARIABLE TP-START VARIABLE TP-GOAL
VARIABLE TP-HEAD VARIABLE TP-TAIL VARIABLE TP-COUNT
: TP-PUT32 ( u addr -- )
  2DUP SWAP 255 AND SWAP C!
  2DUP SWAP 8 RSHIFT 255 AND SWAP 1+ C!
  2DUP SWAP 16 RSHIFT 255 AND SWAP 2 + C!
  SWAP 24 RSHIFT 255 AND SWAP 3 + C! ;
\ Board vertex to grid vertex, and back.
: TP>GRID ( v -- g ) TP-W @ /MOD 1+ TP-P * SWAP 1+ + ;
: TP>BOARD ( g -- v ) TP-P /MOD 1- TP-W @ * SWAP 1- + ;
\ Walls everywhere, then each board row at its offset; FILL stays within 64 KiB.
: TP-COPY
  TP-GRID 65536 1 FILL TP-GRID 65536 + 1028 1 FILL
  0 BEGIN DUP TP-W @ < WHILE
    DUP TP-W @ * TP-BOARD @ +
    OVER 1+ TP-P * 1+ TP-GRID + TP-W @ MOVE 1+
  REPEAT DROP ;
: TP-VISIT ( g code -- )
  OVER TP-GRID + DUP C@ IF DROP 2DROP EXIT THEN
  C! TP-TAIL @ ! CELL TP-TAIL +! ;
: TP-SEARCH ( input-addr input-u -- result-addr result-u )
  DUP 32 < IF 2DROP TP-RESULT 0 EXIT THEN
  TP-RESULT CELL+ 0 SWAP !
  OVER @ TP-RESULT !
  OVER CELL+ @ TP-W !
  TP-W @ DUP 64 >= SWAP 256 <= AND 0= IF 2DROP TP-RESULT 16 EXIT THEN
  TP-W @ DUP * TP-N !
  TP-N @ 4 CELLS + <> IF DROP TP-RESULT 16 EXIT THEN
  DUP 2 CELLS + @ TP-START ! DUP 3 CELLS + @ TP-GOAL !
  4 CELLS + TP-BOARD !
  TP-START @ 0 TP-N @ WITHIN TP-GOAL @ 0 TP-N @ WITHIN AND 0= IF
    TP-RESULT 16 EXIT THEN
  TP-START @ TP-BOARD @ + C@ TP-GOAL @ TP-BOARD @ + C@ OR IF
    TP-RESULT 16 EXIT THEN
  TP-COPY
  TP-GOAL @ TP>GRID TP-GOAL ! TP-START @ TP>GRID TP-START !
  6 TP-START @ TP-GRID + C!
  TP-START @ TP-QUEUE ! TP-QUEUE TP-HEAD ! TP-QUEUE CELL+ TP-TAIL !
  BEGIN TP-HEAD @ TP-TAIL @ < TP-GOAL @ TP-GRID + C@ 0= AND WHILE
    TP-HEAD @ @ CELL TP-HEAD +!
    DUP 1- 2 TP-VISIT DUP 1+ 3 TP-VISIT
    DUP TP-P - 4 TP-VISIT TP-P + 5 TP-VISIT
  REPEAT
  0 TP-COUNT !
  TP-GOAL @ TP-GRID + C@ IF
    TP-GOAL @ BEGIN
      DUP TP>BOARD TP-COUNT @ 4 * TP-RESULT + 16 + TP-PUT32 1 TP-COUNT +!
      DUP TP-START @ <> WHILE
      DUP TP-GRID + C@ CASE
        2 OF 1+ ENDOF 3 OF 1- ENDOF 4 OF TP-P + ENDOF 5 OF TP-P - ENDOF
      ENDCASE
    REPEAT DROP
  THEN
  TP-COUNT @ TP-RESULT CELL+ ! TP-RESULT TP-COUNT @ 4 * 16 + ;
