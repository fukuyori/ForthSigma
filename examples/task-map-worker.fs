\ Deterministic bounded G2 map generation: two full board walks, eight bounded neighbor reads per cell.
\ Input: generation, width (28..256), seed. Result: generation, width, byte map.
REQUIRE-EXTENSION ALSO EXTENSION
CREATE TM-RESULT 65552 ALLOT
VARIABLE TM-W VARIABLE TM-N VARIABLE TM-SEED VARIABLE TM-I
VARIABLE TM-X VARIABLE TM-Y VARIABLE TM-C
: TM-MINE? ( x y -- n )
  DUP 0 TM-W @ WITHIN 2 PICK 0 TM-W @ WITHIN AND 0= IF 2DROP 0 EXIT THEN
  TM-W @ * + TM-RESULT 16 + + C@ 255 = IF 1 ELSE 0 THEN ;
: TM-COUNT
  TM-I @ TM-W @ MOD TM-X ! TM-I @ TM-W @ / TM-Y !
  TM-X @ 1- TM-Y @ 1- TM-MINE?
  TM-X @ TM-Y @ 1- TM-MINE? +
  TM-X @ 1+ TM-Y @ 1- TM-MINE? +
  TM-X @ 1- TM-Y @ TM-MINE? +
  TM-X @ 1+ TM-Y @ TM-MINE? +
  TM-X @ 1- TM-Y @ 1+ TM-MINE? +
  TM-X @ TM-Y @ 1+ TM-MINE? +
  TM-X @ 1+ TM-Y @ 1+ TM-MINE? + ;
: TM-GENERATE
  DUP 24 <> IF 2DROP TM-RESULT 0 EXIT THEN
  DROP DUP @ TM-RESULT ! DUP CELL+ @ TM-W ! 16 + @ TM-SEED !
  TM-W @ DUP 28 < SWAP 256 > OR IF TM-RESULT 0 EXIT THEN
  TM-W @ DUP * TM-N ! 0 TM-I !
  BEGIN TM-I @ TM-N @ < WHILE
    TM-I @ 17 * TM-SEED @ + 31 MOD 0= IF 255 ELSE 0 THEN
    TM-RESULT 16 + TM-I @ + C! 1 TM-I +!
  REPEAT
  0 TM-I ! BEGIN TM-I @ TM-N @ < WHILE
    TM-RESULT 16 + TM-I @ + C@ 255 <> IF
      TM-COUNT TM-RESULT 16 + TM-I @ + C!
    THEN 1 TM-I +!
  REPEAT
  TM-W @ TM-RESULT CELL+ ! TM-RESULT TM-N @ 16 + ;
