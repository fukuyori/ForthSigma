\ Terminal byte search in 1 MiB of text.
\ Requires Zig 0.17.1 with EXTENSION and files; graphics/audio are unnecessary.
\ Run from the repository root: zig-out/bin/sigma.exe tests/task/task-search.fs
\ Keys: Type a byte to search; q quits.
S" tests/task/task-search-worker.fs" INCLUDED
S" tests/task/task-console.fs" INCLUDED
CREATE TS-INPUT 1048593 ALLOT
VARIABLE TS-CHAR
: TS-REQUEST
  1 TC-GEN +! TC-GEN @ TS-INPUT ! 1 TS-INPUT CELL+ !
  TS-CHAR @ TS-INPUT 16 + C!
  TS-INPUT TC-ADDR ! 1048593 TC-SIZE ! TASK-T1 TC-PROFILE !
  S" TS-SEARCH" TC-NAME-U ! TC-NAME ! TC-SUBMIT ;
: TS-RUN
  TS-INPUT 17 + 65536 97 FILL
  1 BEGIN DUP 16 < WHILE
    TS-INPUT 17 + OVER 65536 * + 65536 97 FILL 1+
  REPEAT DROP
  97 TS-CHAR ! TC-OPEN TS-REQUEST
  ." T1: type a byte to search (q quits). Text: 1 MiB of a; offsets are bytes." CR
  BEGIN TC-KEY DUP 0<> OVER 113 <> AND IF TS-CHAR ! TS-REQUEST 0 THEN
    113 = TC-STOP ! TC-POLL TC-DRAW 10 MS TC-STOP @ UNTIL ;
: TS-MAIN ['] TS-RUN CATCH TC-FINISH ;
TS-MAIN BYE
