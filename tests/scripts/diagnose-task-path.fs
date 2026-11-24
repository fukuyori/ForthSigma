\ Run from repository root with sigma tests/scripts/diagnose-task-path.fs.
\ n replaces the request; d prints diagnostics; q releases and exits.
\ Set TD-KEEP-OLD to -1 for a separate run retaining old public IDs.
\ Default 0 preserves task-path.fs's release-after-submit ordering.
S" examples/task-path-worker.fs" INCLUDED
S" examples/task-console.fs" INCLUDED
0 CONSTANT TD-KEEP-OLD
CREATE TD-INPUT 4128 ALLOT
CREATE TD-IDS 4 CELLS ALLOT
CREATE TD-TEXT 256 ALLOT
VARIABLE TD-DEST VARIABLE TD-TURN VARIABLE TD-I VARIABLE TD-STATE
VARIABLE TD-POLLED-GEN VARIABLE TD-PENDING
VARIABLE TD-U VARIABLE TD-CODE VARIABLE TD-IOR
: TD-DIAGNOSTIC ( id channel -- )
  TD-TEXT 256 TASK-DIAGNOSTIC
  TD-IOR ! TD-CODE ! TD-U !
  ." ior=" TD-IOR @ . ." code=" TD-CODE @ . ." bytes=" TD-U @ .
  TD-IOR @ 0= IF TD-TEXT TD-U @ TYPE THEN CR ;
: TD-ONE ( id -- )
  DUP ." id=" . DUP TASK-STATE
  TD-IOR ! ." state-ior=" TD-IOR @ .
  ." diagnostic-bytes=" . ." result-bytes=" . ." cancel=" .
  DUP TD-STATE ! ." state=" . CR
  DUP ." primary: " 0 TD-DIAGNOSTIC
  ." stop: " 3 TD-DIAGNOSTIC ;
: TD-DUMP
  ." requested-generation=" TC-GEN @ . ." applied=" TC-APPLIED @ . CR
  TD-KEEP-OLD IF
    0 TD-I ! BEGIN TD-I @ TC-GEN @ 4 MIN < WHILE
      TD-IDS TD-I @ CELLS + @ DUP IF TD-ONE ELSE DROP THEN
      1 TD-I +!
    REPEAT
  ELSE TC-JOB @ DUP IF TD-ONE ELSE DROP THEN THEN ;
: TD-TRY
  TC-SNAP @ S" TP-SEARCH" TD-INPUT 4128 TASK-G1 7 TASK-SUBMIT
  DUP TC-SUBMIT-IOR ! DUP IF
    ." submit generation=" TC-GEN @ . ." ior=" DUP . CR
    DUP TASK-E-FULL = IF 2DROP TD-DUMP ELSE NIP THROW THEN
  ELSE
    DROP TD-KEEP-OLD 0= IF TC-RELEASE THEN TC-JOB !
    TC-GEN @ TC-JOB-GEN ! 0 TD-PENDING !
    TC-GEN @ 4 <= IF TC-JOB @ TD-IDS TC-GEN @ 1- CELLS + ! THEN
  THEN ;
: TD-REQUEST
  S" TP-SEARCH" TC-NAME-U ! TC-NAME !
  TD-INPUT TC-ADDR ! 4128 TC-SIZE !
  1 TC-GEN +! TC-GEN @ TD-INPUT ! 64 TD-INPUT CELL+ !
  0 TD-INPUT 16 + ! TD-DEST @ TD-INPUT 24 + !
  TASK-G1 TC-PROFILE ! -1 TD-PENDING ! TD-TRY ;
: TD-CLOSE
  TD-KEEP-OLD IF
    \ TC-POLL may already have released the latest ID; release only older IDs.
    0 TD-I ! BEGIN TD-I @ TC-GEN @ 1- 4 MIN < WHILE
      TD-IDS TD-I @ CELLS + @ TASK-RELEASE DROP 1 TD-I +!
    REPEAT
  THEN TC-CLOSE ;
: TD-RUN
  TD-INPUT 4128 0 FILL TD-IDS 4 CELLS 0 FILL
  4095 TD-DEST ! TC-OPEN TD-REQUEST
  ." G1 diagnostic: n replaces (maximum three), d dumps, q quits; keep-old="
  TD-KEEP-OLD . CR
  BEGIN TC-KEY
    DUP 110 = TC-GEN @ 4 < AND IF
      TD-DEST @ 4095 = IF 2047 ELSE 4095 THEN TD-DEST ! TD-REQUEST
    THEN
    DUP 100 = IF TD-DUMP THEN 113 = TC-STOP !
    \ Observe before TC-POLL releases a terminal public ID.
    TC-JOB @ IF
      TC-JOB @ TASK-STATE THROW 2DROP DROP TD-STATE !
      TD-STATE @ TASK-SUCCEEDED >= IF TD-DUMP THEN
    THEN
    TC-JOB-GEN @ TD-POLLED-GEN !
    TC-POLL
    TD-KEEP-OLD TC-JOB @ 0= AND IF
      0 TD-IDS TD-POLLED-GEN @ 1- CELLS + !
    THEN
    TD-PENDING @ IF TD-TRY THEN TC-DRAW
    1 TD-TURN +! TD-TURN @ 100 MOD 0= IF TD-DUMP THEN
    10 MS TC-STOP @ UNTIL ;
: TD-MAIN ['] TD-RUN CATCH ['] TD-CLOSE CATCH TC-FIRST THROW ;
TD-MAIN BYE
