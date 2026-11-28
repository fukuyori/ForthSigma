\ Read and checksum file chunks in order.
\ Requires Zig 0.17.1 with EXTENSION and files; graphics/audio are unnecessary.
\ Run from the repository root: zig-out/bin/sigma.exe tests/task/task-checksum.fs
\ Keys: q quits. Edit TI-PATH to read another file.
S" tests/task/task-checksum-worker.fs" INCLUDED
S" tests/task/task-console.fs" INCLUDED
CREATE TI-INPUT 65552 ALLOT
VARIABLE TI-FILE VARIABLE TI-CHUNK VARIABLE TI-EOF VARIABLE TI-OPENED
S" LICENSE" CONSTANT TI-PATH-U CONSTANT TI-PATH
: TI-NEXT
  TI-INPUT 16 + 65536 TI-FILE @ READ-FILE THROW DUP 0= IF
    DROP -1 TI-EOF !
  ELSE
    16 + TC-SIZE ! 1 TI-CHUNK +! TI-CHUNK @ TI-INPUT CELL+ !
    TC-GEN @ TI-INPUT ! TI-INPUT TC-ADDR ! TASK-I1 TC-PROFILE !
    S" TI-CHECKSUM" TC-NAME-U ! TC-NAME ! TC-SUBMIT
  THEN ;
: TI-RUN
  TI-PATH TI-PATH-U R/O OPEN-FILE THROW TI-FILE ! -1 TI-OPENED !
  1 TC-GEN ! TC-OPEN
  BEGIN TC-KEY 113 = TC-STOP ! TC-POLL
    TC-JOB @ TC-PENDING @ OR 0= TI-EOF @ 0= AND IF TI-NEXT THEN
    TC-DRAW 10 MS TI-EOF @ TC-JOB @ TC-PENDING @ OR 0= AND TC-STOP @ OR
  UNTIL ;
: TI-MAIN
  ['] TI-RUN CATCH
  TI-OPENED @ IF TI-FILE @ CLOSE-FILE 0 TI-OPENED ! TC-FIRST THEN
  TC-FINISH ;
TI-MAIN BYE
