\ Ordered byte sums, modulo 2^32.
\ Input: generation cell, chunk-number cell, <=64 KiB bytes.
\ Result: generation cell, chunk-number cell, checksum cell.
REQUIRE-EXTENSION ALSO EXTENSION
CREATE TI-RESULT 24 ALLOT
VARIABLE TI-SUM
: TI-CHECKSUM ( input-addr input-u -- result-addr result-u )
  DUP 16 < IF 2DROP TI-RESULT 0 EXIT THEN
  OVER @ TI-RESULT ! OVER CELL+ @ TI-RESULT CELL+ !
  16 - SWAP 16 + SWAP 0 TI-SUM !
  BEGIN DUP 0> WHILE
    OVER C@ TI-SUM @ + 4294967295 AND TI-SUM ! 1- SWAP 1+ SWAP
  REPEAT 2DROP
  TI-SUM @ TI-RESULT 16 + ! TI-RESULT 24 ;
