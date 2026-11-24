\ Fixed byte-string search.
\ Input cells: generation, pattern length (1..256); pattern then text bytes.
\ Result cells: generation, total matches, stored matches, truncated flag;
\ then up to 1000 zero-based byte offsets. Overlapping matches count.
REQUIRE-EXTENSION ALSO EXTENSION
CREATE TS-RESULT 8032 ALLOT
VARIABLE TS-PAT VARIABLE TS-LEN VARIABLE TS-TEXT VARIABLE TS-SIZE
VARIABLE TS-I VARIABLE TS-J VARIABLE TS-TOTAL VARIABLE TS-STORED
: TS-SEARCH ( input-addr input-u -- result-addr result-u )
  DUP 16 < IF 2DROP TS-RESULT 0 EXIT THEN
  0 TS-TOTAL ! 0 TS-STORED !
  OVER @ TS-RESULT ! OVER CELL+ @ TS-LEN !
  TS-LEN @ DUP 1 >= SWAP 256 <= AND IF
    OVER 16 + TS-PAT ! 16 - TS-LEN @ - TS-SIZE !
    TS-PAT @ TS-LEN @ + TS-TEXT ! DROP
    0 TS-I ! BEGIN TS-I @ TS-LEN @ + TS-SIZE @ <= WHILE
      0 TS-J ! BEGIN TS-J @ TS-LEN @ < WHILE
        TS-PAT @ TS-J @ + C@ TS-TEXT @ TS-I @ + TS-J @ + C@ <> IF
          TS-LEN @ 1+ TS-J !
        ELSE 1 TS-J +! THEN
      REPEAT
      TS-J @ TS-LEN @ = IF
        1 TS-TOTAL +! TS-STORED @ 1000 < IF
          TS-I @ TS-STORED @ CELLS TS-RESULT + 32 + ! 1 TS-STORED +!
        THEN
      THEN 1 TS-I +!
    REPEAT
  ELSE 2DROP THEN
  TS-TOTAL @ TS-RESULT CELL+ ! TS-STORED @ TS-RESULT 16 + !
  TS-TOTAL @ TS-STORED @ > TS-RESULT 24 + !
  TS-RESULT TS-STORED @ CELLS 32 + ;
