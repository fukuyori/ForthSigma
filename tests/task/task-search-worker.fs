\ Fixed byte-string search.
\ Input cells: generation, pattern length (1..256); pattern then text bytes.
\ Result cells: generation, total matches, stored matches, truncated flag;
\ then up to 1000 zero-based byte offsets. Overlapping matches count.
REQUIRE-EXTENSION ALSO EXTENSION
CREATE TS-RESULT 8032 ALLOT
VARIABLE TS-PAT VARIABLE TS-LEN VARIABLE TS-TEXT VARIABLE TS-SIZE
VARIABLE TS-I VARIABLE TS-TOTAL VARIABLE TS-STORED
VARIABLE TS-END VARIABLE TS-RUN VARIABLE TS-CHUNK
\ Record a consecutive run, expanding only the stored prefix (at most 1000).
: TS-RECORD ( start count -- )
  DUP TS-TOTAL +! 1000 TS-STORED @ - MIN
  0 BEGIN 2DUP > WHILE
    2 PICK OVER + TS-STORED @ CELLS TS-RESULT + 32 + !
    1 TS-STORED +! 1+
  REPEAT 2DROP DROP ;
\ SCAN and SKIP each receive at most 65536 bytes; COMPARE at most 512.
: TS-SCAN
  TS-TEXT @ TS-I @ + TS-END @ TS-I @ - 65536 MIN
  TS-PAT @ C@ SCAN DUP TS-CHUNK !
  DROP TS-TEXT @ - TS-I ! ;
: TS-SEARCH ( input-addr input-u -- result-addr result-u )
  DUP 16 < IF 2DROP TS-RESULT 0 EXIT THEN
  0 TS-TOTAL ! 0 TS-STORED !
  OVER @ TS-RESULT ! OVER CELL+ @ TS-LEN !
  TS-LEN @ DUP 1 >= SWAP 256 <= AND IF
    OVER 16 + TS-PAT ! 16 - TS-LEN @ - TS-SIZE !
    TS-PAT @ TS-LEN @ + TS-TEXT ! DROP
    TS-SIZE @ TS-LEN @ - 1+ 0 MAX TS-END !
    0 TS-I ! BEGIN TS-I @ TS-END @ < WHILE
      TS-SCAN TS-CHUNK @ IF
        TS-LEN @ 1 = IF
          TS-TEXT @ TS-I @ + TS-CHUNK @ TS-PAT @ C@ SKIP
          NIP TS-CHUNK @ SWAP - TS-RUN !
          TS-I @ TS-RUN @ TS-RECORD TS-RUN @ TS-I +!
        ELSE
          TS-TEXT @ TS-I @ + TS-LEN @ TS-PAT @ TS-LEN @ COMPARE 0= IF
            TS-I @ 1 TS-RECORD
          THEN 1 TS-I +!
        THEN
      THEN
    REPEAT
  ELSE 2DROP THEN
  TS-TOTAL @ TS-RESULT CELL+ ! TS-STORED @ TS-RESULT 16 + !
  TS-TOTAL @ TS-STORED @ > TS-RESULT 24 + !
  TS-RESULT TS-STORED @ CELLS 32 + ;
