\ Terminal pathfinding on a 64 by 64 board.
\ Requires Zig 0.17.1 with EXTENSION and files; graphics/audio are unnecessary.
\ Run from the repository root: zig-out/bin/sigma.exe tests/task/task-path.fs
\ Keys: n changes the destination; q quits.
S" tests/task/task-path-worker.fs" INCLUDED
S" tests/task/task-console.fs" INCLUDED
CREATE TP-INPUT 4128 ALLOT
VARIABLE TP-DEST
VARIABLE TP-DISPLAY-GEN VARIABLE TP-X VARIABLE TP-Y
CREATE TP-VIEW 4096 ALLOT
: TP-GET32 ( addr -- u )
  DUP C@ OVER 1+ C@ 8 LSHIFT OR
  OVER 2 + C@ 16 LSHIFT OR SWAP 3 + C@ 24 LSHIFT OR ;
: TP-DRAW-BOARD
  TP-VIEW 4096 46 FILL
  0 BEGIN DUP TC-RESULT CELL+ @ < WHILE
    DUP 4 * TC-RESULT 16 + + TP-GET32 TP-VIEW + 42 SWAP C! 1+
  REPEAT DROP
  83 TP-VIEW C! 71 TP-VIEW TP-DEST @ + C!
  0 TP-Y ! BEGIN TP-Y @ 64 < WHILE
    0 TP-X ! BEGIN TP-X @ 64 < WHILE
      TP-VIEW TP-Y @ 64 * + TP-X @ + C@ EMIT 1 TP-X +!
    REPEAT CR 1 TP-Y +!
  REPEAT ;
: TP-REQUEST
  1 TC-GEN +! TC-GEN @ TP-INPUT ! 64 TP-INPUT CELL+ !
  0 TP-INPUT 16 + ! TP-DEST @ TP-INPUT 24 + !
  TP-INPUT TC-ADDR ! 4128 TC-SIZE ! TASK-G1 TC-PROFILE !
  S" TP-SEARCH" TC-NAME-U ! TC-NAME ! TC-SUBMIT ;
: TP-RUN
  TP-INPUT 4128 0 FILL 4095 TP-DEST ! TC-OPEN TP-REQUEST
  ." G1: n changes destination, q quits; result vertices are goal-to-start." CR
  BEGIN TC-KEY DUP 110 = IF
    TP-DEST @ 4095 = IF 2047 ELSE 4095 THEN TP-DEST ! TP-REQUEST
  THEN 113 = TC-STOP ! TC-POLL
    TC-APPLIED @ TP-DISPLAY-GEN @ <> IF
      TC-APPLIED @ TP-DISPLAY-GEN ! TP-DRAW-BOARD
    THEN TC-DRAW 10 MS TC-STOP @ UNTIL ;
: TP-MAIN ['] TP-RUN CATCH TC-FINISH ;
TP-MAIN BYE
