\ Main-side helpers for the task examples. Requires EXTENSION.
\ Load after a worker definition; see TASK_EXAMPLES.md for build and run commands.
\ No TASK-WAIT with a positive/infinite timeout in the display loop.
VARIABLE TC-SNAP VARIABLE TC-JOB VARIABLE TC-GEN VARIABLE TC-JOB-GEN
VARIABLE TC-APPLIED VARIABLE TC-FRAMES VARIABLE TC-STOP
VARIABLE TC-PROFILE VARIABLE TC-ADDR VARIABLE TC-SIZE
VARIABLE TC-NAME VARIABLE TC-NAME-U
VARIABLE TC-DRAW-GEN VARIABLE TC-DRAW-APPLIED VARIABLE TC-DRAW-STOP
VARIABLE TC-CLOSE-IOR
VARIABLE TC-PENDING VARIABLE TC-SUBMIT-IOR
CREATE TC-RESULT 262160 ALLOT
CREATE TC-TURN 4 , 0 , 0 , 0 , 0 , CREATE TC-EVENT 32 ALLOT
\ A zero-time clock poll also services released tasks when TC-JOB is zero.
: TC-TICK TC-TURN 1 TC-EVENT 1 0 TASK-WAIT-MANY THROW 2DROP ;
: TC-OPEN TASK-SNAPSHOT THROW TC-SNAP ! ;
: TC-RELEASE TC-JOB @ IF TC-JOB @ TASK-RELEASE THROW 0 TC-JOB ! THEN ;
: TC-TRY-SUBMIT
  TC-SNAP @ TC-NAME @ TC-NAME-U @ TC-ADDR @ TC-SIZE @ TC-PROFILE @ 7
  TASK-SUBMIT DUP TC-SUBMIT-IOR ! DUP IF
    DUP TASK-E-FULL = IF
      ." submit deferred ior=" . DROP CR
    ELSE NIP THROW THEN
  ELSE DROP TC-RELEASE TC-JOB ! TC-GEN @ TC-JOB-GEN !
    0 TC-PENDING ! THEN ;
\ Caller keeps the latest input/name alive until acceptance; newer requests
\ overwrite that pending input. Retry once per display turn, never busy-wait.
: TC-SUBMIT -1 TC-PENDING ! TC-TRY-SUBMIT ;
: TC-FRESH? ( result-generation -- flag )
  TC-GEN @ = TC-JOB-GEN @ TC-GEN @ = AND ;
: TC-SUMMARY
  ." result generation=" TC-APPLIED @ .
  TC-PROFILE @ TASK-G1 = IF ." vertices=" TC-RESULT CELL+ @ . THEN
  TC-PROFILE @ TASK-T1 = IF
    ." matches=" TC-RESULT CELL+ @ . ." stored=" TC-RESULT 16 + @ .
    ." truncated=" TC-RESULT 24 + @ .
    TC-RESULT 16 + @ IF ." first offset=" TC-RESULT 32 + @ . THEN
  THEN
  TC-PROFILE @ TASK-I1 = IF
    ." chunk=" TC-RESULT CELL+ @ . ." checksum=" TC-RESULT 16 + @ .
  THEN CR ;
: TC-POLL
  TC-TICK
  TC-JOB @ IF
    TC-JOB @ 0 TASK-WAIT THROW DROP DUP TASK-SUCCEEDED >= IF
      TASK-SUCCEEDED = IF
        TC-JOB @ TC-RESULT 262160 TASK-RESULT THROW DROP DROP
        TC-RESULT @ TC-FRESH? IF
          TC-RESULT @ TC-APPLIED !
          TC-SUMMARY
        ELSE ." discarded stale result" CR THEN
      ELSE ." failed/cancelled; previous display retained" CR
        TC-JOB-GEN @ TC-GEN @ = IF -1 TC-PENDING ! THEN
      THEN
      TC-RELEASE
    ELSE DROP THEN
  THEN
  TC-PENDING @ IF TC-TRY-SUBMIT THEN ;
: TC-DRAW
  TC-GEN @ TC-DRAW-GEN @ <> TC-APPLIED @ TC-DRAW-APPLIED @ <> OR
  TC-STOP @ TC-DRAW-STOP @ <> OR IF
    TC-GEN @ TC-DRAW-GEN ! TC-APPLIED @ TC-DRAW-APPLIED !
    TC-STOP @ TC-DRAW-STOP !
    1 TC-FRAMES +! ." frame=" TC-FRAMES @ .
    ." generation=" TC-GEN @ . CR
  THEN ;
: TC-KEY ( -- c )
  EKEY? IF EKEY EKEY>CHAR IF DUP ." input=" . CR ELSE DROP 0 THEN
  ELSE 0 THEN ;
\ Attempt both releases before throwing the first cleanup error.
: TC-FIRST ( original-ior cleanup-ior -- first-ior )
  OVER IF DROP ELSE NIP THEN ;
: TC-CLOSE
  0 TC-PENDING ! 0 TC-CLOSE-IOR !
  TC-JOB @ IF
    TC-JOB @ TASK-RELEASE TC-CLOSE-IOR !
    TC-CLOSE-IOR @ 0= IF 0 TC-JOB ! THEN
  THEN
  TC-SNAP @ IF
    TC-SNAP @ TASK-SNAPSHOT-RELEASE
    DUP 0= IF 0 TC-SNAP ! THEN
    TC-CLOSE-IOR @ SWAP TC-FIRST TC-CLOSE-IOR !
  THEN TC-CLOSE-IOR @ THROW ;
: TC-FINISH ( run-ior -- ) ['] TC-CLOSE CATCH TC-FIRST THROW ;
