\ LOGO to Forth translator for Sigma (task 1477).
\ Load from the repository root. LG@ is reserved, including generated names.
\ Source is parsed as data; it is never passed directly to EVALUATE.
BASE @ GET-CURRENT GET-ORDER
FORTH DEFINITIONS DECIMAL
VARIABLE LG@LOAD-CURRENT ( -- addr )
VARIABLE LG@LOAD-BASE ( -- addr )
CREATE LG@LOAD-ORDER 256 CELLS ALLOT ( -- addr )
VARIABLE LG@LOAD-N ( -- addr )
DUP LG@LOAD-N !
: LG@STORE-LOAD ( wid... n -- ) 0 ?DO LG@LOAD-ORDER I CELLS + ! LOOP ;
LG@STORE-LOAD LG@LOAD-CURRENT ! LG@LOAD-BASE !
VARIABLE LG@LOAD-DONE ( -- addr )
: LG@RESTORE-LOAD ( -- )
   LG@LOAD-N @ 0 ?DO LG@LOAD-ORDER LG@LOAD-N @ 1- I - CELLS + @ LOOP
   LG@LOAD-N @ SET-ORDER LG@LOAD-CURRENT @ SET-CURRENT LG@LOAD-BASE @ BASE !
;
: LG@READ-LOAD ( -- )
   BEGIN REFILL WHILE SOURCE EVALUATE LG@LOAD-DONE @ IF EXIT THEN REPEAT
;
: LG@LOAD ( -- ) ['] LG@READ-LOAD CATCH LG@RESTORE-LOAD THROW ;
LG@LOAD
DECIMAL
INCLUDE emu/logo/turtle.fs
REQUIRE-EXTENSION
ALSO EXTENSION
VOCABULARY LOGO ( -- )
ALSO GRAPHICS ALSO TURTLE ALSO LOGO DEFINITIONS

\ ---- Bind turtle words now, without exposing turtle to generated code ----
: LG@POLL ( -- ) TT@POLL ;
: LG@FINITE ( F: x -- x ) TT@FINITE ;
: LG@INT ( F: x -- ) ( -- n )
   LG@FINITE FDUP FLOOR FOVER F<> IF -4201 THROW THEN F>S
;
: LG@COND ( F: x -- ) ( -- flag )
   LG@FINITE FDUP 0e F= IF FDROP FALSE EXIT THEN
   -1e F<> IF -4201 THROW THEN TRUE
;
: LG@COUNT ( F: x -- ) ( -- n )
   LG@FINITE 0e FMAX FLOOR FDUP 2147483647e F> IF -4201 THROW THEN F>S
;
: LG@RANDOM ( F: x -- n )
   LG@FINITE FLOOR FDUP 1e F< IF -4201 THROW THEN
   FDUP 2147483647e F> IF -4201 THROW THEN F>S RANDOM S>F
;
: LG@DIV ( F: x y -- z )
   FDUP 0e F= IF -4201 THROW THEN F/ LG@FINITE
;
: LG@FD ( F: x -- ) FD ;
: LG@BK ( F: x -- ) BK ;
: LG@RT ( F: x -- ) RT ;
: LG@LT ( F: x -- ) LT ;
: LG@PU ( -- ) PU ;
: LG@PD ( -- ) PD ;
: LG@HOME ( -- ) HOME ;
: LG@CS ( -- ) CS ;
: LG@CLEAN ( -- ) CLEAN ;
: LG@SETXY ( F: x y -- ) SETXY ;
: LG@SETH ( F: x -- ) SETH ;
: LG@SETPC ( n -- ) SETPC ;
: LG@SETBG ( n -- ) SETBG ;
: LG@PC-RGB ( F: r g b -- ) SETPENCOLOR-RGB ;
: LG@BG-RGB ( F: r g b -- ) SETBACKGROUND-RGB ;
: LG@SETPENSIZE ( n -- ) SETPENSIZE ;
: LG@SETSPEED ( n -- ) SETSPEED ;
: LG@SETSCREENSIZE ( w h -- ) SETSCREENSIZE ;
: LG@ST ( -- ) ST ;
: LG@HT ( -- ) HT ;
: LG@WRAP ( -- ) WRAP ;
: LG@WINDOW ( -- ) WINDOW ;
: LG@FENCE ( -- ) FENCE ;
: LG@ARC ( F: a r -- ) ARC ;
: LG@LABEL ( a u -- ) LABEL ;
: LG@INIT ( w h -- ) TURTLE-INIT ;
: LG@DISPOSE ( -- ) TURTLE-DISPOSE ;
: LG@DISPLAY-RUN ( xt -- ) TURTLE-RUN ;
: LG@REALPATH ( a u buffer capacity -- needed ior ) FILE>REALPATH ;
PREVIOUS PREVIOUS PREVIOUS PREVIOUS
ALSO LOGO DEFINITIONS
: FD ( F: x -- ) LG@FD ;
: FORWARD ( F: x -- ) LG@FD ;
: BK ( F: x -- ) LG@BK ;
: BACK ( F: x -- ) LG@BK ;
: RT ( F: x -- ) LG@RT ;
: RIGHT ( F: x -- ) LG@RT ;
: LT ( F: x -- ) LG@LT ;
: LEFT ( F: x -- ) LG@LT ;
: PU ( -- ) LG@PU ;
: PENUP ( -- ) LG@PU ;
: PD ( -- ) LG@PD ;
: PENDOWN ( -- ) LG@PD ;
: HOME ( -- ) LG@HOME ;
: CS ( -- ) LG@CS ;
: CLEARSCREEN ( -- ) LG@CS ;
: CLEAN ( -- ) LG@CLEAN ;
: SETXY ( F: x y -- ) LG@SETXY ;
: SETH ( F: x -- ) LG@SETH ;
: SETHEADING ( F: x -- ) LG@SETH ;
: SETPC ( n -- ) LG@SETPC ;
: SETPENCOLOR ( n -- ) LG@SETPC ;
: SETBG ( n -- ) LG@SETBG ;
: SETBACKGROUND ( n -- ) LG@SETBG ;
: SETPENSIZE ( n -- ) LG@SETPENSIZE ;
: SETSPEED ( n -- ) LG@SETSPEED ;
: SETSCREENSIZE ( w h -- ) LG@SETSCREENSIZE ;
: ST ( -- ) LG@ST ;
: SHOWTURTLE ( -- ) LG@ST ;
: HT ( -- ) LG@HT ;
: HIDETURTLE ( -- ) LG@HT ;
: WRAP ( -- ) LG@WRAP ;
: WINDOW ( -- ) LG@WINDOW ;
: FENCE ( -- ) LG@FENCE ;
: ARC ( F: a r -- ) LG@ARC ;
: LABEL ( a u -- ) LG@LABEL ;
: LG@CHECK-CONTROL ( a u -- )
   GET-CURRENT FIND-NAME-IN IF -4202 THROW THEN
;
S" IF" LG@CHECK-CONTROL S" ELSE" LG@CHECK-CONTROL S" THEN" LG@CHECK-CONTROL
S" DO" LG@CHECK-CONTROL S" ?DO" LG@CHECK-CONTROL S" LOOP" LG@CHECK-CONTROL
S" BEGIN" LG@CHECK-CONTROL S" AGAIN" LG@CHECK-CONTROL S" EXIT" LG@CHECK-CONTROL
S" UNLOOP" LG@CHECK-CONTROL S" RECURSE" LG@CHECK-CONTROL

\ ---- Resident ownership and diagnostic state ----
VARIABLE LG@LINE ( -- addr )
VARIABLE LG@CATEGORY ( -- addr )
VARIABLE LG@MESSAGE ( -- addr )
VARIABLE LG@MESSAGE-N ( -- addr )
VARIABLE LG@FILE ( -- addr )
VARIABLE LG@FILE-N ( -- addr )
VARIABLE LG@OUTFILE ( -- addr )
VARIABLE LG@OUTFILE-N ( -- addr )
VARIABLE LG@FID ( -- addr )
VARIABLE LG@SOURCE ( -- addr )
VARIABLE LG@SIZE ( -- addr )
VARIABLE LG@TOKENS ( -- addr )
VARIABLE LG@NT ( -- addr )
VARIABLE LG@PROCS ( -- addr )
VARIABLE LG@NP ( -- addr )
VARIABLE LG@VARS ( -- addr )
VARIABLE LG@NV ( -- addr )
VARIABLE LG@NG ( -- addr )
VARIABLE LG@NS ( -- addr )
VARIABLE LG@TEXT ( -- addr )
VARIABLE LG@TEXT-N ( -- addr )
VARIABLE LG@TEXT-CAP ( -- addr )
VARIABLE LG@MARK ( -- addr )
VARIABLE LG@HEADLESS ( -- addr )
VARIABLE LG@SAVED-BASE ( -- addr )
VARIABLE LG@SAVED-CURRENT ( -- addr )
VARIABLE LG@SAVED-N ( -- addr )
CREATE LG@SAVED-ORDER 256 CELLS ALLOT ( -- addr )
CREATE LG@REAL-A 4096 ALLOT ( -- addr )
CREATE LG@REAL-B 4096 ALLOT ( -- addr )
VARIABLE LG@POS ( -- addr )
VARIABLE LG@LIMIT ( -- addr )
VARIABLE LG@PROC ( -- addr )
VARIABLE LG@NEST ( -- addr )
VARIABLE LG@LOOPS ( -- addr )
VARIABLE LG@BRANCHES ( -- addr )
VARIABLE LG@CALL-END ( -- addr )
VARIABLE LG@CALL-TOKEN ( -- addr )
VARIABLE LG@FRAGMENTS ( -- addr )
VARIABLE LG@NF ( -- addr )
VARIABLE LG@FRAG-END ( -- addr )
VARIABLE LG@ERROR ( -- addr )
VARIABLE LG@CLEAN-ERROR ( -- addr )
VARIABLE LG@NEEDS-TEMP ( -- addr )
CREATE LG@NAME-BUFFER 128 ALLOT ( -- addr )
: LG@AT ( line -- ) LG@LINE ! 4 LG@CATEGORY ! ;
: LG@FAIL ( a u -- ) LG@MESSAGE-N ! LG@MESSAGE ! -4202 THROW ;
: LG@BAD ( -- ) S" invalid syntax or missing input" LG@FAIL ;
: LG@SAVE-ENV ( -- )
   BASE @ LG@SAVED-BASE ! GET-CURRENT LG@SAVED-CURRENT !
   GET-ORDER DUP LG@SAVED-N !
   0 ?DO LG@SAVED-ORDER I CELLS + ! LOOP
;
: LG@RESTORE-ENV ( -- )
   LG@SAVED-N @ 0 ?DO LG@SAVED-ORDER LG@SAVED-N @ 1- I - CELLS + @ LOOP
   LG@SAVED-N @ SET-ORDER LG@SAVED-CURRENT @ SET-CURRENT LG@SAVED-BASE @ BASE !
;
: LG@ENV ( -- ) ONLY FORTH ALSO LOGO DEFINITIONS DECIMAL ;
: LG@FIRST ( first second -- error ) OVER IF DROP ELSE NIP THEN ;
: LG@CLOSE ( -- ) LG@FID @ ?DUP IF 0 LG@FID ! CLOSE-FILE THROW THEN ;
: LG@FREE ( slot -- ) DUP @ ?DUP IF 0 ROT ! FREE THROW ELSE DROP THEN ;
: LG@ALLOC ( n slot -- ) >R ALLOCATE THROW R> ! ;
: LG@APPEND { a u -- }
   LG@TEXT-N @ u + LG@TEXT-CAP @ > IF
      LG@TEXT-N @ u + 2 * DUP LG@TEXT-CAP !
      LG@TEXT @ SWAP RESIZE THROW LG@TEXT !
   THEN
   a LG@TEXT @ LG@TEXT-N @ + u MOVE u LG@TEXT-N +!
;
: LG@EMIT ( a u -- ) LG@APPEND S"  " LG@APPEND ;
: LG@NL ( -- ) 10 PAD C! PAD 1 LG@APPEND ;
: LG@NUM ( n -- ) 0 <# #S #> LG@APPEND ;
: LG@NAME { id a u -- } a u LG@APPEND id LG@NUM S"  " LG@APPEND ;
: LG@LOCATION ( line -- ) LG@NUM S"  LG@AT LG@POLL " LG@APPEND ;

\ ---- Token table: address, length, kind, line, unary-minus, matching end ----
\ Kinds: 0 EOF, 1 identifier, 2 number, 3 quoted word, 4 variable,
\ 5 punctuation, 6 newline. Source slices retain original spelling.
: LG@T ( i field -- addr ) SWAP 6 * + CELLS LG@TOKENS @ + ;
: LG@T@ ( i field -- n ) LG@T @ ;
: LG@SLICE ( i -- a u ) DUP 0 LG@T@ SWAP 1 LG@T@ ;
: LG@UP ( c -- c ) DUP 97 123 WITHIN IF 32 - THEN ;
: LG@EQ { a u b v -- flag }
   u v <> IF FALSE EXIT THEN
   u 0 ?DO a I + C@ LG@UP b I + C@ LG@UP <> IF FALSE UNLOOP EXIT THEN LOOP TRUE
;
: LG@IS ( i a u -- flag ) ROT LG@SLICE 2SWAP LG@EQ ;
: LG@ALPHA ( c -- flag ) LG@UP DUP 65 91 WITHIN SWAP 95 = OR ;
: LG@DIGIT ( c -- flag ) 48 58 WITHIN ;
: LG@IDCHAR ( c -- flag ) DUP LG@ALPHA OVER LG@DIGIT OR SWAP 63 = OR ;
: LG@IDENT { a u -- flag }
   u 0= IF FALSE EXIT THEN a C@ LG@ALPHA 0= IF FALSE EXIT THEN
   u 1 ?DO a I + C@ LG@IDCHAR 0= IF FALSE UNLOOP EXIT THEN LOOP TRUE
;
: LG@WS ( c -- flag ) DUP 32 = OVER 9 = OR SWAP 10 = OR ;
: LG@DELIM ( c -- flag )
   DUP LG@WS OVER 13 = OR OVER 59 = OR
   OVER 91 = OR OVER 93 = OR OVER 40 = OR SWAP 41 = OR
;
: LG@BYTE ( i -- c ) DUP LG@SIZE @ < IF LG@SOURCE @ + C@ ELSE DROP 0 THEN ;
: LG@ADD-TOKEN { start len kind line unary -- }
   LG@SOURCE @ start + LG@NT @ 0 LG@T ! len LG@NT @ 1 LG@T !
   kind LG@NT @ 2 LG@T ! line LG@NT @ 3 LG@T ! unary LG@NT @ 4 LG@T !
   -1 LG@NT @ 5 LG@T ! 1 LG@NT +!
;
\ Strict UTF-8 validation is independent of identifier restrictions.
: LG@UTF8 { | offset c n cp lo -- }
   0 TO offset
   BEGIN offset LG@SIZE @ < WHILE
      offset LG@BYTE TO c c 10 = IF 1 LG@LINE +! THEN
      c 128 < IF 1 +TO offset ELSE
         c 194 224 WITHIN IF 2 TO n 128 TO lo c 31 AND TO cp ELSE
         c 224 240 WITHIN IF 3 TO n 2048 TO lo c 15 AND TO cp ELSE
         c 240 245 WITHIN IF 4 TO n 65536 TO lo c 7 AND TO cp ELSE
            S" invalid UTF-8" LG@FAIL
         THEN THEN THEN
         offset n + LG@SIZE @ > IF S" truncated UTF-8" LG@FAIL THEN
         n 1 DO offset I + LG@BYTE DUP 128 192 WITHIN 0= IF S" invalid UTF-8" LG@FAIL THEN
            63 AND cp 6 LSHIFT OR TO cp LOOP
         cp lo < cp 1114111 > OR cp 55296 57344 WITHIN OR IF S" invalid UTF-8" LG@FAIL THEN
         n +TO offset
      THEN
   REPEAT 1 LG@LINE !
;
: LG@LEX { | i start c kind unary digits exponent -- }
   1 LG@CATEGORY ! 1 LG@LINE ! LG@UTF8 0 LG@NT ! 0 TO i
   LG@SIZE @ 3 >= IF 0 LG@BYTE 239 = 1 LG@BYTE 187 = AND 2 LG@BYTE 191 = AND IF 3 TO i THEN THEN
   BEGIN i LG@SIZE @ < WHILE
      i LG@BYTE TO c
      c 32 = c 9 = OR IF 1 +TO i ELSE
      c 13 = IF i 1+ LG@BYTE 10 <> IF S" bare carriage return" LG@FAIL THEN 1 +TO i ELSE
      c 10 = IF i 1 6 LG@LINE @ 0 LG@ADD-TOKEN 1 LG@LINE +! 1 +TO i ELSE
      c 59 = IF BEGIN i LG@SIZE @ < i LG@BYTE 10 <> AND WHILE 1 +TO i REPEAT ELSE
         i TO start 0 TO unary 5 TO kind
         c 34 = c 58 = OR IF
            c 34 = IF 3 ELSE 4 THEN TO kind 1 +TO i
            kind 4 = IF
               BEGIN i LG@BYTE LG@IDCHAR i LG@SIZE @ < AND WHILE 1 +TO i REPEAT
            ELSE
               BEGIN i LG@SIZE @ < i LG@BYTE LG@DELIM 0= AND WHILE 1 +TO i REPEAT
            THEN
            i start - 1 <= IF LG@BAD THEN
            kind 4 = IF LG@SOURCE @ start + 1+ i start - 1- LG@IDENT 0= IF LG@BAD THEN THEN
         ELSE c LG@ALPHA IF
            1 TO kind 1 +TO i
            BEGIN i LG@BYTE LG@IDCHAR i LG@SIZE @ < AND WHILE 1 +TO i REPEAT
         ELSE c LG@DIGIT c 46 = OR IF
            2 TO kind 0 TO digits
            BEGIN i LG@BYTE LG@DIGIT WHILE 1 +TO digits 1 +TO i REPEAT
            i LG@BYTE 46 = IF 1 +TO i
               BEGIN i LG@BYTE LG@DIGIT WHILE 1 +TO digits 1 +TO i REPEAT THEN
            digits 0= IF S" invalid number" LG@FAIL THEN
            i LG@BYTE LG@UP 69 = IF 1 +TO i
               i LG@BYTE DUP 43 = SWAP 45 = OR IF 1 +TO i THEN
               i TO exponent BEGIN i LG@BYTE LG@DIGIT WHILE 1 +TO i REPEAT
               i exponent = IF S" invalid exponent" LG@FAIL THEN
            THEN
            i LG@BYTE DUP LG@ALPHA SWAP 46 = OR IF S" invalid number" LG@FAIL THEN
         ELSE
            c 45 = IF start 0= IF TRUE ELSE start 1- LG@BYTE LG@WS THEN
               start 1+ LG@BYTE LG@WS 0= AND TO unary THEN
            c 40 = c 41 = OR c 91 = OR c 93 = OR c 43 = OR c 45 = OR
            c 42 = OR c 47 = OR c 61 = OR c 60 = OR c 62 = OR 0= IF S" invalid character" LG@FAIL THEN
            1 +TO i c 60 = c 62 = OR IF
               i LG@BYTE 61 = c 60 = i LG@BYTE 62 = AND OR IF 1 +TO i THEN THEN
         THEN THEN THEN
         start i start - kind LG@LINE @ unary LG@ADD-TOKEN
      THEN THEN THEN THEN
   REPEAT
   i 0 0 LG@LINE @ 0 LG@ADD-TOKEN
;

\ ---- Builtin signatures, kept as data rather than executable source ----
\ Each entry has token spelling, target name, arity, and conversion kind.
\ Kind 0 float command, 1 integer command, 2 colour, 3 label, 4 syntax/value.
VARIABLE LG@NB ( -- addr )
CREATE LG@BT 1600 CELLS ALLOT ( -- addr )
: LG@BUILTIN { a u b v arity kind -- }
   LG@NB @ 6 * CELLS LG@BT + { slot -- }
   a slot ! u slot CELL+ ! b slot 2 CELLS + ! v slot 3 CELLS + !
   arity slot 4 CELLS + ! kind slot 5 CELLS + ! 1 LG@NB +!
;
S" FD" S" LG@FD" 1 0 LG@BUILTIN
S" FORWARD" S" LG@FD" 1 0 LG@BUILTIN
S" BK" S" LG@BK" 1 0 LG@BUILTIN
S" BACK" S" LG@BK" 1 0 LG@BUILTIN
S" RT" S" LG@RT" 1 0 LG@BUILTIN
S" RIGHT" S" LG@RT" 1 0 LG@BUILTIN
S" LT" S" LG@LT" 1 0 LG@BUILTIN
S" LEFT" S" LG@LT" 1 0 LG@BUILTIN
S" PU" S" LG@PU" 0 0 LG@BUILTIN
S" PENUP" S" LG@PU" 0 0 LG@BUILTIN
S" PD" S" LG@PD" 0 0 LG@BUILTIN
S" PENDOWN" S" LG@PD" 0 0 LG@BUILTIN
S" HOME" S" LG@HOME" 0 0 LG@BUILTIN
S" CS" S" LG@CS" 0 0 LG@BUILTIN
S" CLEARSCREEN" S" LG@CS" 0 0 LG@BUILTIN
S" CLEAN" S" LG@CLEAN" 0 0 LG@BUILTIN
S" SETXY" S" LG@SETXY" 2 0 LG@BUILTIN
S" SETH" S" LG@SETH" 1 0 LG@BUILTIN
S" SETHEADING" S" LG@SETH" 1 0 LG@BUILTIN
S" SETPC" S" LG@SETPC" 1 2 LG@BUILTIN
S" SETPENCOLOR" S" LG@SETPC" 1 2 LG@BUILTIN
S" SETBG" S" LG@SETBG" 1 2 LG@BUILTIN
S" SETBACKGROUND" S" LG@SETBG" 1 2 LG@BUILTIN
S" SETPENSIZE" S" LG@SETPENSIZE" 1 1 LG@BUILTIN
S" SETSPEED" S" LG@SETSPEED" 1 1 LG@BUILTIN
S" SETSCREENSIZE" S" LG@SETSCREENSIZE" 2 1 LG@BUILTIN
S" ST" S" LG@ST" 0 0 LG@BUILTIN
S" SHOWTURTLE" S" LG@ST" 0 0 LG@BUILTIN
S" HT" S" LG@HT" 0 0 LG@BUILTIN
S" HIDETURTLE" S" LG@HT" 0 0 LG@BUILTIN
S" WRAP" S" LG@WRAP" 0 0 LG@BUILTIN
S" WINDOW" S" LG@WINDOW" 0 0 LG@BUILTIN
S" FENCE" S" LG@FENCE" 0 0 LG@BUILTIN
S" ARC" S" LG@ARC" 2 0 LG@BUILTIN
S" LABEL" S" LG@LABEL" 1 3 LG@BUILTIN
S" TO" S" " 0 4 LG@BUILTIN
S" END" S" " 0 4 LG@BUILTIN
S" REPEAT" S" " 0 4 LG@BUILTIN
S" REPCOUNT" S" " 0 4 LG@BUILTIN
S" IF" S" " 0 4 LG@BUILTIN
S" IFELSE" S" " 0 4 LG@BUILTIN
S" STOP" S" " 0 4 LG@BUILTIN
S" OUTPUT" S" " 0 4 LG@BUILTIN
S" MAKE" S" " 0 4 LG@BUILTIN
S" LOCAL" S" " 0 4 LG@BUILTIN
S" THING" S" " 0 4 LG@BUILTIN
S" TRUE" S" " 0 4 LG@BUILTIN
S" FALSE" S" " 0 4 LG@BUILTIN
S" RANDOM" S" " 0 4 LG@BUILTIN
: LG@B { token -- slot }
   LG@NB @ 0 ?DO token LG@SLICE LG@BT I 6 * CELLS + DUP @ SWAP CELL+ @ LG@EQ IF
      LG@BT I 6 * CELLS + UNLOOP EXIT THEN LOOP 0
;
\ Procedure: name token, header token, body token, END token, arity, value?, locals.
: LG@P ( id field -- addr ) SWAP 7 * + CELLS LG@PROCS @ + ;
: LG@P@ ( id field -- n ) LG@P @ ;
: LG@FIND-P { token -- id }
   LG@NP @ 0 ?DO token LG@SLICE I 0 LG@P@ LG@SLICE LG@EQ IF I UNLOOP EXIT THEN LOOP -1
;
\ Variable: name slice, scope (-1 global), kind (0 argument,1 local,2 global), index.
: LG@V ( id field -- addr ) SWAP 5 * + CELLS LG@VARS @ + ;
: LG@V@ ( id field -- n ) LG@V @ ;
: LG@V-SLICE ( id -- a u ) DUP 0 LG@V@ SWAP 1 LG@V@ ;
: LG@FIND-V { a u scope -- id }
   LG@NV @ 0 ?DO I 2 LG@V@ scope = IF a u I LG@V-SLICE LG@EQ IF I UNLOOP EXIT THEN THEN LOOP -1
;
: LG@ADD-V { a u scope kind index -- id }
   LG@NV @ { id -- }
   a id 0 LG@V ! u id 1 LG@V ! scope id 2 LG@V ! kind id 3 LG@V ! index id 4 LG@V !
   1 LG@NV +! id
;
: LG@GLOBAL { a u -- }
   a u -1 2 LG@NG @ LG@ADD-V DROP 1 LG@NG +!
;
: LG@TOKEN-NAME ( token -- a u ) LG@SLICE 1 /STRING ;
: LG@DECLARE-V { token scope kind index -- }
   token LG@TOKEN-NAME 2DUP LG@IDENT 0= IF LG@BAD THEN
   2DUP scope LG@FIND-V -1 <> IF S" duplicate variable declaration" LG@FAIL THEN
   scope kind index LG@ADD-V DROP
;
: LG@LINE-AT ( token -- ) 3 LG@T@ LG@LINE ! ;
\ Pre-pass lookahead follows the parser's newline rule only inside delimiters.
: LG@DEPTH-AT { token depth -- depth' }
   token S" [" LG@IS token S" (" LG@IS OR IF depth 1+ EXIT THEN
   token S" ]" LG@IS token S" )" LG@IS OR IF depth 1- EXIT THEN depth
;
: LG@INPUT-AT { token depth -- next }
   token 1+ TO token
   depth 0> IF BEGIN token 2 LG@T@ 6 = WHILE 1 +TO token REPEAT THEN token
;
: LG@COLLECT { | i p body ending args locals kind depth next -- }
   2 LG@CATEGORY ! 0 LG@NP ! 0 LG@NV ! 0 LG@NG ! 0 TO i
   BEGIN i LG@NT @ 1- < WHILE
      i LG@LINE-AT
      i S" TO" LG@IS IF
         i 0> IF i 1- 2 LG@T@ 6 <> IF S" TO must start a line" LG@FAIL THEN THEN
         i 1+ 2 LG@T@ 1 <> IF LG@BAD THEN
         i 1+ LG@B i 1+ LG@FIND-P -1 <> OR IF S" duplicate or reserved procedure" LG@FAIL THEN
         LG@NP @ TO p 1 LG@NP +! i 1+ p 0 LG@P ! i p 1 LG@P !
         i 2 + TO body 0 TO args
         BEGIN body 2 LG@T@ 4 = WHILE
            body p 0 args LG@DECLARE-V 1 +TO args 1 +TO body
         REPEAT
         body 2 LG@T@ 6 <> IF S" procedure header must end at newline" LG@FAIL THEN
         body 1+ TO body body p 2 LG@P ! args p 4 LG@P ! 0 p 5 LG@P !
         body TO ending 0 TO locals 0 TO depth
         BEGIN ending LG@NT @ 1- < ending S" END" LG@IS 0= AND WHILE
            ending LG@LINE-AT
            ending depth LG@DEPTH-AT TO depth
            ending S" TO" LG@IS IF S" nested TO" LG@FAIL THEN
            ending S" OUTPUT" LG@IS IF TRUE p 5 LG@P ! THEN
            ending S" LOCAL" LG@IS IF
               ending depth LG@INPUT-AT TO next
               next 2 LG@T@ 3 <> IF LG@BAD THEN
               next p 1 locals LG@DECLARE-V 1 +TO locals
            THEN 1 +TO ending
         REPEAT
         ending LG@NT @ 1- >= IF S" missing END" LG@FAIL THEN
         ending LG@LINE-AT
         ending 1- 2 LG@T@ 6 <> ending 1+ 2 LG@T@ DUP 6 <> SWAP 0 <> AND OR IF
            S" END must be alone on its line" LG@FAIL THEN
         args locals 2 * + 64 > IF i LG@LINE-AT S" more than 64 locals" LG@FAIL THEN
         ending p 3 LG@P ! locals p 6 LG@P ! ending 1+ TO i
      ELSE
         i S" END" LG@IS IF S" END without TO" LG@FAIL THEN
         1 +TO i
      THEN
   REPEAT
   \ Resolve names only after every LOCAL has been collected.
   -1 TO p 0 TO i 0 TO depth
   BEGIN i LG@NT @ 1- < WHILE
      i S" TO" LG@IS IF i 1+ LG@FIND-P TO p p 2 LG@P@ TO i ELSE
      i S" END" LG@IS IF -1 TO p 1 +TO i ELSE
         i depth LG@DEPTH-AT TO depth
         i LG@LINE-AT i 2 LG@T@ TO kind
         kind 4 = IF
            i LG@TOKEN-NAME p LG@FIND-V -1 = IF
               i LG@TOKEN-NAME -1 LG@FIND-V -1 = IF i LG@TOKEN-NAME LG@GLOBAL THEN
            THEN
         THEN
         i S" MAKE" LG@IS i S" THING" LG@IS OR IF
            i depth LG@INPUT-AT TO next
            next 2 LG@T@ 3 = IF
               next LG@TOKEN-NAME 2DUP LG@IDENT 0= IF LG@BAD THEN
               p LG@FIND-V -1 = IF
                  next LG@TOKEN-NAME -1 LG@FIND-V -1 = IF next LG@TOKEN-NAME LG@GLOBAL THEN
               THEN
            THEN
         THEN
         i S" LOCAL" LG@IS p -1 = AND IF S" LOCAL outside procedure" LG@FAIL THEN
         1 +TO i
      THEN THEN
   REPEAT
;
: LG@FRAGMENT { offset first last -- }
   LG@FRAGMENTS @ LG@NF @ 4 * CELLS + { slot -- }
   offset slot ! LG@TEXT-N @ offset - slot CELL+ !
   first slot 2 CELLS + ! last slot 3 CELLS + ! 1 LG@NF +!
;

\ ---- Parser and code generation ----
\ Matching delimiters are established before declarations and parsing.
: LG@MATCH { | depth stack token opening -- }
   LG@NT @ CELLS ALLOCATE THROW TO stack 0 TO depth
   \ Use the resident text buffer as the temporary delimiter stack owner.
   stack LG@TEXT ! LG@NT @ CELLS LG@TEXT-CAP !
   LG@NT @ 0 ?DO
      I LG@LINE-AT
      I S" [" LG@IS I S" (" LG@IS OR IF I stack depth CELLS + ! 1 +TO depth THEN
      I S" ]" LG@IS I S" )" LG@IS OR IF
         depth 0= IF S" unmatched closing delimiter" LG@FAIL THEN
         -1 +TO depth stack depth CELLS + @ TO opening
         opening S" [" LG@IS I S" ]" LG@IS <> IF S" mismatched delimiter" LG@FAIL THEN
         I opening 5 LG@T !
      THEN
   LOOP depth IF S" unclosed delimiter" LG@FAIL THEN
   0 LG@TEXT-N !
;
: LG@SKIP ( -- )
   LG@NEST @ IF BEGIN LG@POS @ 2 LG@T@ 6 = WHILE 1 LG@POS +! REPEAT THEN
;
: LG@CURRENT ( a u -- flag ) LG@SKIP LG@POS @ ROT ROT LG@IS ;
: LG@TAKE ( a u -- ) LG@CURRENT 0= IF LG@BAD THEN 1 LG@POS +! ;
: LG@NEXT ( -- token ) LG@SKIP LG@POS @ DUP LG@LINE-AT 1 LG@POS +! ;
: LG@GENERATED { id a u -- }
   \ Reject a preexisting generated name before creating a program marker.
   a LG@NAME-BUFFER u MOVE id 0 <# #S #> { digits n -- }
   digits LG@NAME-BUFFER u + n MOVE
   LG@NAME-BUFFER u n + FIND-NAME IF S" generated name collision" LG@FAIL THEN
;
: LG@VNAME { id -- }
   id 3 LG@V@ CASE
      0 OF id 4 LG@V@ S" LG@A" LG@NAME ENDOF
      1 OF id 4 LG@V@ S" LG@L" LG@NAME ENDOF
      2 OF id 4 LG@V@ S" LG@G" LG@NAME ENDOF
   ENDCASE
;
: LG@FLAG-NAME { id -- }
   id 3 LG@V@ 2 = IF id 4 LG@V@ S" LG@V" ELSE id 4 LG@V@ S" LG@U" THEN LG@NAME
;
: LG@RESOLVE { token -- id }
   token LG@TOKEN-NAME LG@PROC @ LG@FIND-V DUP -1 = IF DROP token LG@TOKEN-NAME -1 LG@FIND-V THEN
   DUP -1 = IF LG@BAD THEN
;
: LG@READ-V { id line -- }
   line LG@LOCATION
   id 3 LG@V@ 0<> IF
      id LG@FLAG-NAME id 3 LG@V@ 2 = IF S" @ " LG@APPEND THEN
      S" 0= IF -4203 THROW THEN " LG@APPEND
   THEN
   id LG@VNAME id 3 LG@V@ 2 = IF S" F@ " LG@APPEND THEN
;
: LG@WRITE-V { id -- }
   id 3 LG@V@ 2 = IF
      id LG@VNAME S" F! TRUE " LG@APPEND id LG@FLAG-NAME S" ! " LG@APPEND
   ELSE
      S" TO " LG@APPEND id LG@VNAME
      id 3 LG@V@ 1 = IF S" TRUE TO " LG@APPEND id LG@FLAG-NAME THEN
   THEN
;
: LG@NUMBER { token -- }
   token LG@SLICE 2DUP >FLOAT 0= IF S" invalid number" LG@FAIL THEN
   LG@FINITE FDROP LG@APPEND
   \ Appending e only when no exponent is already present preserves decimals.
   token LG@SLICE { a u -- } FALSE { exponent -- }
   u 0 ?DO a I + C@ LG@UP 69 = IF TRUE TO exponent THEN LOOP
   exponent 0= IF S" e" LG@APPEND THEN S"  " LG@APPEND
;
: LG@OP { token -- precedence }
   token S" =" LG@IS token S" <>" LG@IS OR token S" <" LG@IS OR
   token S" >" LG@IS OR token S" <=" LG@IS OR token S" >=" LG@IS OR IF 1 EXIT THEN
   token S" +" LG@IS IF 2 EXIT THEN
   token S" -" LG@IS token 4 LG@T@ 0= AND IF 2 EXIT THEN
   token S" *" LG@IS token S" /" LG@IS OR IF 3 EXIT THEN 0
;
: LG@OP-CODE { token -- }
   token S" +" LG@IS IF S" F+ LG@FINITE" LG@EMIT EXIT THEN
   token S" -" LG@IS IF S" F- LG@FINITE" LG@EMIT EXIT THEN
   token S" *" LG@IS IF S" F* LG@FINITE" LG@EMIT EXIT THEN
   token S" /" LG@IS IF S" LG@DIV" LG@EMIT EXIT THEN
   token S" =" LG@IS IF S" F= S>F" LG@EMIT EXIT THEN
   token S" <>" LG@IS IF S" F<> S>F" LG@EMIT EXIT THEN
   token S" <" LG@IS IF S" F< S>F" LG@EMIT EXIT THEN
   token S" >" LG@IS IF S" F> S>F" LG@EMIT EXIT THEN
   token S" <=" LG@IS IF S" F<= S>F" LG@EMIT EXIT THEN
   S" F>= S>F" LG@EMIT
;
\ Cross-recursive parser entries use resident deferred vectors. This avoids
\ putting parser forward declarations in the public LOGO namespace.
VARIABLE LG@EXPR-XT ( -- addr )
VARIABLE LG@STATEMENTS-XT ( -- addr )
: LG@EXPRESSION ( min -- ) LG@EXPR-XT @ EXECUTE ;
: LG@BLOCK { value tail -- }
   S" [" LG@TAKE 1 LG@NEST +!
   value IF 1 LG@EXPRESSION ELSE tail LG@STATEMENTS-XT @ EXECUTE THEN
   S" ]" LG@TAKE -1 LG@NEST +!
;
: LG@LAST? { | i -- flag }
   LG@POS @ TO i BEGIN i LG@LIMIT @ < i 2 LG@T@ 6 = AND WHILE 1 +TO i REPEAT
   i LG@LIMIT @ >= IF TRUE EXIT THEN i S" ]" LG@IS
;
: LG@AFTER-LAST? { pos | saved answer -- flag }
   LG@POS @ TO saved pos LG@POS ! LG@LAST? TO answer saved LG@POS ! answer
;
: LG@IFELSE { value tail -- }
   LG@LINE @ { line -- }
   1 LG@EXPRESSION line LG@LOCATION S" LG@COND IF" LG@EMIT
   tail IF
      LG@SKIP S" [" LG@CURRENT 0= IF LG@BAD THEN
      LG@POS @ 5 LG@T@ 1+ { next -- }
      BEGIN next 2 LG@T@ 6 = WHILE 1 +TO next REPEAT
      next S" [" LG@IS 0= IF LG@BAD THEN
      next 5 LG@T@ 1+ LG@AFTER-LAST? TO tail
   THEN
   1 LG@BRANCHES +!
   value tail LG@BLOCK S" ELSE" LG@EMIT value tail LG@BLOCK S" THEN" LG@EMIT
   -1 LG@BRANCHES +!
;
: LG@CALL { p token -- }
   p 4 LG@P@ 0 ?DO 1 LG@EXPRESSION LOOP token 3 LG@T@ LG@LOCATION
   p LG@PROC @ = IF S" RECURSE" LG@EMIT ELSE p S" LG@P" LG@NAME THEN
   LG@POS @ LG@CALL-END ! token LG@CALL-TOKEN !
;
: LG@ATOM { | token p -- }
   LG@NEXT TO token
   token 2 LG@T@ 2 = IF token LG@NUMBER EXIT THEN
   token 2 LG@T@ 4 = IF token LG@RESOLVE token 3 LG@T@ LG@READ-V EXIT THEN
   token S" +" LG@IS IF 4 LG@EXPRESSION EXIT THEN
   token S" -" LG@IS IF 4 LG@EXPRESSION S" FNEGATE LG@FINITE" LG@EMIT EXIT THEN
   token S" (" LG@IS IF 1 LG@NEST +! 1 LG@EXPRESSION S" )" LG@TAKE -1 LG@NEST +! EXIT THEN
   token S" TRUE" LG@IS IF S" -1e" LG@EMIT EXIT THEN
   token S" FALSE" LG@IS IF S" 0e" LG@EMIT EXIT THEN
   token S" REPCOUNT" LG@IS IF
      LG@LOOPS @ IF S" I 1+ S>F" ELSE S" -1e" THEN LG@EMIT EXIT THEN
   token S" THING" LG@IS IF LG@NEXT DUP 2 LG@T@ 3 <> IF LG@BAD THEN
      LG@RESOLVE token 3 LG@T@ LG@READ-V EXIT THEN
   token S" RANDOM" LG@IS IF 1 LG@EXPRESSION token 3 LG@T@ LG@LOCATION S" LG@RANDOM" LG@EMIT EXIT THEN
   token S" IFELSE" LG@IS IF TRUE FALSE LG@IFELSE EXIT THEN
   token LG@FIND-P TO p p -1 <> IF
      p 5 LG@P@ 0= IF S" command procedure used as value" LG@FAIL THEN p token LG@CALL EXIT THEN
   S" expected a value or missing input" LG@FAIL
;
: LG@PARSE-EXPR { min | token precedence comparison -- }
   FALSE TO comparison LG@ATOM
   BEGIN LG@SKIP LG@POS @ LG@OP DUP TO precedence min >= precedence 0> AND WHILE
      LG@NEXT TO token
      precedence 1 = IF comparison IF S" chained comparison" LG@FAIL THEN TRUE TO comparison THEN
      precedence 1+ RECURSE token 3 LG@T@ LG@LOCATION token LG@OP-CODE
   REPEAT
;
' LG@PARSE-EXPR LG@EXPR-XT !

\ ---- Commands, lexical loops, and self-tail calls ----
: LG@UNLOOPS ( -- ) LG@LOOPS @ 0 ?DO S" UNLOOP" LG@EMIT LOOP ;
: LG@RESET-LOCALS ( -- )
   LG@NV @ 0 ?DO I 2 LG@V@ LG@PROC @ = I 3 LG@V@ 1 = AND IF
      S" 0e TO" LG@EMIT I LG@VNAME S" FALSE TO" LG@EMIT I LG@FLAG-NAME THEN LOOP
;
: LG@TAIL-TRANSFER { p token -- }
   TRUE LG@NEEDS-TEMP !
   p 4 LG@P@ 0 ?DO S" TO" LG@EMIT p 4 LG@P@ 1- I - S" LG@T" LG@NAME LOOP
   p 4 LG@P@ 0 ?DO I S" LG@T" LG@NAME S" TO" LG@EMIT I S" LG@A" LG@NAME LOOP
   LG@RESET-LOCALS token 3 LG@T@ LG@LOCATION LG@UNLOOPS
   S" [ " LG@APPEND LG@BRANCHES @ LG@LOOPS @ + LG@NUM S"  CS-PICK ] AGAIN" LG@EMIT
;
\ Duplicate the outer BEGIN's compile-time destination before AGAIN. Nested
\ IF destinations remain on the control stack and can still be closed normally.
: LG@FINISH ( -- )
   LG@PROC @ -1 = IF LG@BAD THEN
   LG@UNLOOPS
   LG@PROC @ 5 LG@P@ IF S" -4204 THROW" ELSE S" EXIT" THEN LG@EMIT
;
: LG@QUOTED ( -- token ) LG@NEXT DUP 2 LG@T@ 3 <> IF LG@BAD THEN ;
: LG@LABEL-TEXT { token -- }
   token 4 LG@T@ S" LG@S" LG@NAME token 1 LG@T@ 1- LG@NUM S"  " LG@APPEND
;
: LG@COLOUR-NUMBER { | negative -- }
   FALSE TO negative
   S" -" LG@CURRENT IF TRUE TO negative 1 LG@POS +! ELSE
      S" +" LG@CURRENT IF 1 LG@POS +! THEN THEN
   LG@NEXT DUP 2 LG@T@ 2 <> IF LG@BAD THEN LG@NUMBER
   negative IF S" FNEGATE" LG@EMIT THEN
;
: LG@COLOUR { slot line -- }
   S" [" LG@CURRENT IF
      S" [" LG@TAKE 1 LG@NEST +!
      3 0 DO LG@COLOUR-NUMBER LOOP
      S" ]" LG@TAKE -1 LG@NEST +! line LG@LOCATION
      slot 2 CELLS + @ slot 3 CELLS + @ S" LG@SETPC" LG@EQ IF S" LG@PC-RGB" ELSE S" LG@BG-RGB" THEN LG@EMIT
   ELSE 1 LG@EXPRESSION line LG@LOCATION S" LG@INT" LG@EMIT
      slot 2 CELLS + @ slot 3 CELLS + @ LG@EMIT THEN
;
: LG@COMMAND { token slot | n kind line -- }
   token 3 LG@T@ TO line slot 4 CELLS + @ TO n slot 5 CELLS + @ TO kind
   kind 2 = IF slot line LG@COLOUR EXIT THEN
   kind 3 = IF LG@QUOTED LG@LABEL-TEXT line LG@LOCATION S" LG@LABEL" LG@EMIT EXIT THEN
   n 0 ?DO 1 LG@EXPRESSION kind 1 = IF S" LG@INT" LG@EMIT THEN LOOP
   line LG@LOCATION slot 2 CELLS + @ slot 3 CELLS + @ LG@EMIT
;
: LG@STATEMENT { tail | token p slot ending oldpos -- }
   LG@NEXT TO token token 3 LG@T@ LG@LOCATION
   token S" REPEAT" LG@IS IF
      1 LG@EXPRESSION token 3 LG@T@ LG@LOCATION S" LG@COUNT 0 ?DO LG@POLL" LG@EMIT
      1 LG@LOOPS +! FALSE FALSE LG@BLOCK -1 LG@LOOPS +! S" LOOP" LG@EMIT EXIT THEN
   token S" IF" LG@IS IF
      1 LG@EXPRESSION token 3 LG@T@ LG@LOCATION S" LG@COND IF" LG@EMIT 1 LG@BRANCHES +!
      LG@SKIP LG@POS @ 5 LG@T@ 1+ LG@AFTER-LAST? tail AND TO tail
      FALSE tail LG@BLOCK -1 LG@BRANCHES +! S" THEN" LG@EMIT EXIT THEN
   token S" IFELSE" LG@IS IF FALSE tail LG@IFELSE EXIT THEN
   token S" STOP" LG@IS IF LG@FINISH EXIT THEN
   token S" OUTPUT" LG@IS IF
      LG@PROC @ -1 = IF S" OUTPUT outside procedure" LG@FAIL THEN
      LG@POS @ TO oldpos LG@TEXT-N @ TO ending
      1 LG@EXPRESSION
      oldpos LG@CALL-TOKEN @ = LG@CALL-END @ LG@POS @ = AND
      oldpos LG@FIND-P LG@PROC @ = AND IF
         ending LG@TEXT-N ! oldpos 1+ LG@POS !
         LG@PROC @ 4 LG@P@ 0 ?DO 1 LG@EXPRESSION LOOP
         LG@PROC @ token LG@TAIL-TRANSFER
      ELSE token 3 LG@T@ LG@LOCATION LG@UNLOOPS S" EXIT" LG@EMIT THEN EXIT THEN
   token S" MAKE" LG@IS IF
      LG@QUOTED LG@RESOLVE TO p 1 LG@EXPRESSION token 3 LG@T@ LG@LOCATION p LG@WRITE-V EXIT THEN
   token S" LOCAL" LG@IS IF LG@PROC @ -1 = IF LG@BAD THEN LG@QUOTED DROP EXIT THEN
   token LG@B TO slot slot IF
      slot 5 CELLS + @ 4 = IF S" unused value or unsupported syntax" LG@FAIL THEN
      token slot LG@COMMAND EXIT THEN
   token LG@FIND-P TO p p -1 <> IF
      p 5 LG@P@ IF S" unused procedure value" LG@FAIL THEN
      p 4 LG@P@ 0 ?DO 1 LG@EXPRESSION LOOP
      p LG@PROC @ = tail AND LG@LAST? AND LG@LOOPS @ 0= AND IF
         p token LG@TAIL-TRANSFER
      ELSE token 3 LG@T@ LG@LOCATION
         p LG@PROC @ = IF S" RECURSE" LG@EMIT ELSE p S" LG@P" LG@NAME THEN THEN EXIT THEN
   S" unknown command or unused value" LG@FAIL
;
: LG@PARSE-STATEMENTS { tail -- }
   BEGIN LG@SKIP LG@POS @ LG@LIMIT @ < S" ]" LG@CURRENT 0= AND WHILE
      LG@POS @ 2 LG@T@ 6 = IF 1 LG@POS +! ELSE
      LG@POS @ S" TO" LG@IS LG@PROC @ -1 = AND IF
         LG@POS @ 1+ LG@FIND-P 3 LG@P@ 1+ LG@POS !
      ELSE tail LG@STATEMENT LG@NL THEN THEN
   REPEAT
;
' LG@PARSE-STATEMENTS LG@STATEMENTS-XT !
: LG@PROCEDURE { p -- }
   p LG@PROC ! 0 LG@NEST ! 0 LG@LOOPS ! 0 LG@BRANCHES !
   p 2 LG@P@ LG@POS ! p 3 LG@P@ LG@LIMIT !
   \ Parse once to discover actual optimized self calls. Only those procedures
   \ need argument-update temporaries; ordinary procedures retain all 64 slots.
   LG@TEXT-N @ { saved -- } FALSE LG@NEEDS-TEMP ! TRUE LG@PARSE-STATEMENTS
   LG@NEEDS-TEMP @ { temporary -- } saved LG@TEXT-N !
   p 4 LG@P@ p 6 LG@P@ 2 * + temporary IF p 4 LG@P@ + THEN
   64 > IF p 1 LG@P@ LG@LINE-AT S" more than 64 locals" LG@FAIL THEN
   temporary IF p 4 LG@P@ 0 ?DO I S" LG@T" LG@GENERATED LOOP THEN
   p 2 LG@P@ LG@POS ! 0 LG@NEST ! 0 LG@LOOPS ! 0 LG@BRANCHES !
   S" :" LG@EMIT p S" LG@P" LG@NAME S" {" LG@EMIT
   p 4 LG@P@ 0 ?DO S" F:" LG@EMIT I S" LG@A" LG@NAME LOOP
   p 6 LG@P@ temporary IF p 4 LG@P@ + THEN IF S" |" LG@EMIT
      p 6 LG@P@ 0 ?DO S" F:" LG@EMIT I S" LG@L" LG@NAME I S" LG@U" LG@NAME LOOP
      temporary IF p 4 LG@P@ 0 ?DO S" F:" LG@EMIT I S" LG@T" LG@NAME LOOP THEN THEN
   S" -- }" LG@EMIT LG@NL
   temporary IF S" BEGIN" LG@EMIT THEN
   LG@RESET-LOCALS p 2 LG@P@ 3 LG@T@ LG@LOCATION
   TRUE LG@PARSE-STATEMENTS
   p 5 LG@P@ IF p 3 LG@P@ 3 LG@T@ LG@LOCATION S" -4204 THROW" LG@EMIT THEN
   temporary IF
      p 5 LG@P@ 0= IF S" EXIT" LG@EMIT THEN S" AGAIN" LG@EMIT
   THEN S" ;" LG@EMIT LG@NL
;
: LG@TRANSLATE { | depth next -- }
   LG@LEX LG@MATCH LG@COLLECT 0 LG@TEXT-N ! 0 LG@NF !
   0 LG@NS !
   0 TO depth
   LG@NT @ 1- 0 ?DO
      I depth LG@DEPTH-AT TO depth
      I S" LABEL" LG@IS IF
         I depth LG@INPUT-AT TO next
         next 2 LG@T@ 3 = IF
            LG@NS @ S" LG@S" LG@GENERATED LG@NS @ next 4 LG@T ! 1 LG@NS +!
         THEN
      THEN
   LOOP
   LG@NP @ 0 ?DO I S" LG@P" LG@GENERATED LOOP
   LG@NP @ 0 ?DO
      I 4 LG@P@ 0 ?DO I S" LG@A" LG@GENERATED LOOP
      I 6 LG@P@ 0 ?DO I S" LG@L" LG@GENERATED I S" LG@U" LG@GENERATED LOOP
   LOOP
   LG@NV @ 0 ?DO I 3 LG@V@ 2 = IF
      I 4 LG@V@ S" LG@G" LG@GENERATED I 4 LG@V@ S" LG@V" LG@GENERATED THEN LOOP
   S" LG@PROGRAM" FIND-NAME IF S" generated marker collision" LG@FAIL THEN
   0 LG@TEXT-N !
   LG@NV @ 0 ?DO I 3 LG@V@ 2 = IF
      S" FVARIABLE" LG@EMIT I LG@VNAME S" VARIABLE" LG@EMIT I LG@FLAG-NAME
      S" FALSE" LG@EMIT I LG@FLAG-NAME S" !" LG@EMIT LG@NL THEN LOOP
   \ Sigma's S" literals are limited to 255 bytes. Dictionary byte arrays
   \ preserve arbitrary-length UTF-8 words, quotes, and backslashes safely.
   0 TO depth
   LG@NT @ 1- 0 ?DO
      I depth LG@DEPTH-AT TO depth
      I S" LABEL" LG@IS IF
         I depth LG@INPUT-AT TO next
         next 2 LG@T@ 3 = IF
            S" CREATE" LG@EMIT next 4 LG@T@ S" LG@S" LG@NAME
            next LG@TOKEN-NAME { bytes length -- }
            length 0 ?DO bytes I + C@ LG@NUM S"  C," LG@EMIT LOOP LG@NL
         THEN
      THEN
   LOOP
   \ The declaration interval excludes LOGO's public turtle FORWARD.
   S" ONLY FORTH" LG@EMIT LG@NL
   LG@NP @ 0 ?DO S" FORWARD" LG@EMIT I S" LG@P" LG@NAME LG@NL LOOP
   S" ALSO LOGO" LG@EMIT LG@NL
   0 1 LG@NT @ 1- 3 LG@T@ LG@FRAGMENT
   LG@NP @ 0 ?DO LG@TEXT-N @ I LG@PROCEDURE
      I 1 LG@P@ 3 LG@T@ I 3 LG@P@ 3 LG@T@ LG@FRAGMENT LOOP
   -1 LG@PROC ! 0 LG@NEST ! 0 LG@LOOPS ! 0 LG@BRANCHES !
   0 LG@POS ! LG@NT @ 1- LG@LIMIT !
   LG@TEXT-N @ S" :NONAME" LG@EMIT LG@NL FALSE LG@PARSE-STATEMENTS
   S" ; EXECUTE" LG@EMIT LG@NL
   1 LG@NT @ 1- 3 LG@T@ LG@FRAGMENT
;

\ ---- File handling, exception boundary, and public entries ----
: LG@READ-FILE ( -- )
   LG@FILE @ LG@FILE-N @ R/O OPEN-FILE THROW LG@FID !
   LG@FID @ FILE-SIZE THROW DUP IF -11 THROW THEN DROP LG@SIZE !
   LG@SIZE @ 1+ LG@SOURCE LG@ALLOC
   LG@SOURCE @ LG@SIZE @ LG@FID @ READ-FILE THROW LG@SIZE @ <> IF -37 THROW THEN LG@CLOSE
   LG@SIZE @ 2 + DUP 6 * CELLS LG@TOKENS LG@ALLOC
   DUP 7 * CELLS LG@PROCS LG@ALLOC 5 * CELLS LG@VARS LG@ALLOC
   LG@SIZE @ 3 + 4 * CELLS LG@FRAGMENTS LG@ALLOC
;
: LG@EMIT-FILE ( -- )
   LG@OUTFILE-N @ IF
      LG@OUTFILE @ LG@OUTFILE-N @ W/O CREATE-FILE THROW LG@FID !
      LG@TEXT @ LG@TEXT-N @ LG@FID @ WRITE-FILE THROW LG@CLOSE
   THEN
;
: LG@SAME-FILE? { a u b v | na nb -- flag }
   a u b v LG@EQ IF TRUE EXIT THEN
   a u LG@REAL-A 4096 LG@REALPATH IF DROP FALSE EXIT THEN TO na
   b v LG@REAL-B 4096 LG@REALPATH IF DROP FALSE EXIT THEN TO nb
   LG@REAL-A na LG@REAL-B nb LG@EQ
;
: LG@EXECUTE-TEXT ( -- )
   LG@NF @ 0 ?DO
      LG@FRAGMENTS @ I 4 * CELLS + { slot -- }
      slot 2 CELLS + @ LG@LINE ! slot 3 CELLS + @ LG@FRAG-END !
      3 LG@CATEGORY ! LG@TEXT @ slot @ + slot CELL+ @ EVALUATE
   LOOP
;
: LG@RUN ( -- )
   LG@READ-FILE LG@TRANSLATE LG@EMIT-FILE
   S" LG@PROGRAM" FIND-NAME IF S" generated marker collision" LG@FAIL THEN
   S" MARKER LG@PROGRAM" EVALUATE S" LG@PROGRAM" FIND-NAME NAME>INTERPRET LG@MARK !
   640 480 LG@INIT
   LG@HEADLESS @ IF LG@EXECUTE-TEXT ELSE ['] LG@EXECUTE-TEXT LG@DISPLAY-RUN THEN
;
: LG@FREE-SOURCE ( -- ) LG@SOURCE LG@FREE ;
: LG@FREE-TOKENS ( -- ) LG@TOKENS LG@FREE ;
: LG@FREE-PROCS ( -- ) LG@PROCS LG@FREE ;
: LG@FREE-VARS ( -- ) LG@VARS LG@FREE ;
: LG@FREE-FRAGMENTS ( -- ) LG@FRAGMENTS LG@FREE ;
: LG@FREE-TEXT ( -- ) LG@TEXT LG@FREE ;
: LG@FORGET ( -- ) LG@MARK @ ?DUP IF 0 LG@MARK ! EXECUTE THEN ;
: LG@TRY-CLEAN ( xt -- )
   CATCH LG@CLEAN-ERROR @ SWAP LG@FIRST LG@CLEAN-ERROR !
;
: LG@RELEASE ( -- )
   \ No cleanup arguments or saved errors remain on CATCH's restored stacks.
   0 LG@CLEAN-ERROR !
   ['] LG@CLOSE LG@TRY-CLEAN ['] LG@FREE-SOURCE LG@TRY-CLEAN
   ['] LG@FREE-TOKENS LG@TRY-CLEAN ['] LG@FREE-PROCS LG@TRY-CLEAN
   ['] LG@FREE-VARS LG@TRY-CLEAN ['] LG@FREE-FRAGMENTS LG@TRY-CLEAN
   ['] LG@FREE-TEXT LG@TRY-CLEAN ['] LG@FORGET LG@TRY-CLEAN
   LG@CLEAN-ERROR @ THROW
;
: LG@MESSAGE-FOR ( error -- a u )
   CASE
      -4200 OF S" turtle out of bounds" ENDOF
      -4201 OF S" invalid input" ENDOF
      -4202 OF S" translation failed" ENDOF
      -4203 OF S" variable has no value" ENDOF
      -4204 OF S" procedure did not output" ENDOF
      -4205 OF S" drawing cancelled" ENDOF
      S" Sigma or file error" ROT
   ENDCASE
;
: LG@DIAGNOSTIC { error -- }
   LG@FILE @ LG@FILE-N @ TYPE [CHAR] : EMIT
   LG@LINE @ ?DUP IF 0 <# #S #> TYPE ELSE [CHAR] ? EMIT THEN
   S" : " TYPE
   LG@CATEGORY @ CASE
      1 OF S" lexical" ENDOF 2 OF S" translation" ENDOF
      3 OF S" forth-compile" ENDOF 4 OF S" runtime" ENDOF
      5 OF S" usage" ENDOF S" runtime" ROT
   ENDCASE TYPE S" : " TYPE
   LG@MESSAGE-N @ IF LG@MESSAGE @ LG@MESSAGE-N @ ELSE error LG@MESSAGE-FOR THEN TYPE
   S"  (" TYPE error . [CHAR] ) EMIT CR
   LG@CATEGORY @ 3 = IF
      ." generated definition lines " LG@LINE @ . ." through " LG@FRAG-END @ . CR
   THEN
;
: LG@RESET ( -- )
   0 LG@FID ! 0 LG@SOURCE ! 0 LG@TOKENS ! 0 LG@PROCS ! 0 LG@VARS !
   0 LG@TEXT ! 0 LG@TEXT-N ! 0 LG@TEXT-CAP ! 0 LG@MARK !
   0 LG@FRAGMENTS ! 0 LG@NF !
   0 LG@CALL-END ! -1 LG@CALL-TOKEN !
   0 LG@LINE ! 4 LG@CATEGORY ! 0 LG@MESSAGE-N !
;
: LG@DO { a u -- }
   a LG@FILE ! u LG@FILE-N ! LG@SAVE-ENV LG@ENV LG@RESET
   ['] LG@RUN CATCH LG@ERROR !
   ['] LG@RELEASE CATCH LG@ERROR @ SWAP LG@FIRST LG@ERROR !
   LG@ERROR @ IF ['] LG@DISPOSE CATCH LG@ERROR @ SWAP LG@FIRST LG@ERROR ! THEN
   LG@ERROR @ DUP -4205 <> SWAP 0<> AND IF LG@ERROR @ LG@DIAGNOSTIC THEN
   LG@RESTORE-ENV LG@ERROR @ DUP -4205 = IF DROP ELSE THROW THEN
;
: LOGO-HEADLESS ( a u -- ) TRUE LG@HEADLESS ! 0 LG@OUTFILE-N ! LG@DO ;
: LG@USAGE ( -- )
   5 LG@CATEGORY ! S" <command-line>" LG@FILE-N ! LG@FILE !
   0 LG@LINE ! S" invalid command line" LG@MESSAGE-N ! LG@MESSAGE ! -4202 LG@DIAGNOSTIC
   ." Usage: LOGO [--emit-forth output.fs] input.lg" CR -4202 THROW
;
: LG@ARGS { | a u -- }
   FALSE LG@HEADLESS ! 0 LG@OUTFILE-N ! NEXT-ARG TO u TO a
   a u S" --emit-forth" LG@EQ IF
      NEXT-ARG DUP 0= IF LG@USAGE THEN LG@OUTFILE-N ! LG@OUTFILE !
      NEXT-ARG TO u TO a
   THEN
   u 0= IF LG@USAGE THEN a C@ 45 = IF LG@USAGE THEN
   NEXT-ARG NIP IF LG@USAGE THEN
   LG@OUTFILE-N @ IF
      a u LG@OUTFILE @ LG@OUTFILE-N @ LG@SAME-FILE? IF LG@USAGE THEN
   THEN
   a u LG@DO
;
: LOGO-MAIN ( -- ) LG@ARGS ;
: LG@START ( -- )
   1 ARG NIP 0= IF EXIT THEN
   1 ARG S" -e" LG@EQ IF EXIT THEN LOGO-MAIN BYE
;
LG@START
PREVIOUS
TRUE LG@LOAD-DONE !
