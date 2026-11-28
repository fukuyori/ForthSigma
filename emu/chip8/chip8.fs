\ Original 64x32 CHIP-8 interpreter for Sigma (task 1469).
\ Run: sigma emu/chip8/chip8.fs emu/roms/c8games/PONG [vip|chip48]
\ Keys: 1234/QWER/ASDF/ZXCV maps to 123C/456D/789E/A0BF; Esc exits, F5 resets.
\ Options: CH8-SHIFT-VY, CH8-LOAD-INC, CH8-LOGIC-VF, CH8-DISPLAY-WAIT,
\ CH8-VIP-FONT and CH8-WRAP; CH8-SPEED is instructions per 60 Hz tick.
\ CH8-CHIP48 (default) clears all switches; CH8-VIP sets the first five.
\ SHIFT-VY selects Vy shifts; LOAD-INC advances I after transfers.
\ LOGIC-VF clears VF; DISPLAY-WAIT limits drawing to one sprite per tick.
\ VIP-FONT selects VIP digit shapes; WRAP wraps overflowing sprite pixels.
\ Profiles preserve speed; font selection takes effect at RESET/LOAD.
DECIMAL
64 CONSTANT CH8-WIDTH
32 CONSTANT CH8-HEIGHT
2048 CONSTANT CH8-PIXELS
4096 CONSTANT CH8-MEM-SIZE
$200 CONSTANT CH8-ENTRY
$50 CONSTANT CH8-FONT-ADDR
3584 CONSTANT CH8-ROM-MAX
16667 CONSTANT CH8-TICK-US
-4100 CONSTANT CH8-ERR-ROM-SIZE
-4101 CONSTANT CH8-ERR-ROM-READ
-4102 CONSTANT CH8-ERR-OPCODE
-4103 CONSTANT CH8-ERR-STACK-UNDERFLOW
-4104 CONSTANT CH8-ERR-STACK-OVERFLOW
\ ---- Memory and registers ----
CREATE CH8-MEM CH8-MEM-SIZE ALLOT
CREATE CH8-V 16 ALLOT
CREATE CH8-SCREEN CH8-PIXELS ALLOT
CREATE CH8-HISTORY CH8-PIXELS 3 * ALLOT
CREATE CH8-SHOWN CH8-PIXELS ALLOT
CREATE CH8-LAST-SHOWN CH8-PIXELS ALLOT
CH8-LAST-SHOWN CH8-PIXELS 255 FILL
VARIABLE CH8-BLEND 3 CH8-BLEND !
CREATE CH8-KEYS 16 ALLOT
CREATE CH8-STACK 16 CELLS ALLOT
CREATE CH8-ROM CH8-ROM-MAX ALLOT
VARIABLE CH8-ROM-SIZE
VARIABLE CH8-I
VARIABLE CH8-PC
VARIABLE CH8-SP
VARIABLE CH8-DT
VARIABLE CH8-ST
VARIABLE CH8-DIRTY
VARIABLE CH8-SHIFT-VY
VARIABLE CH8-LOAD-INC
VARIABLE CH8-WRAP
VARIABLE CH8-LOGIC-VF
VARIABLE CH8-DISPLAY-WAIT
VARIABLE CH8-VIP-FONT
VARIABLE CH8-DREW
: CH8-CHIP48 ( -- )
   FALSE CH8-SHIFT-VY !
   FALSE CH8-LOAD-INC !
   FALSE CH8-LOGIC-VF !
   FALSE CH8-DISPLAY-WAIT !
   FALSE CH8-VIP-FONT !
   FALSE CH8-WRAP !
;

: CH8-VIP ( -- )
   TRUE CH8-SHIFT-VY !
   TRUE CH8-LOAD-INC !
   TRUE CH8-LOGIC-VF !
   TRUE CH8-DISPLAY-WAIT !
   TRUE CH8-VIP-FONT !
   FALSE CH8-WRAP !
;

CH8-CHIP48
VARIABLE CH8-SPEED 10 CH8-SPEED !
VARIABLE CH8-WAIT -1 CH8-WAIT !
VARIABLE CH8-SEED 12345 CH8-SEED !
CREATE CH8-FONT
HEX
F0 C, 90 C, 90 C, 90 C, F0 C, 20 C, 60 C, 20 C, 20 C, 70 C,
F0 C, 10 C, F0 C, 80 C, F0 C, F0 C, 10 C, F0 C, 10 C, F0 C,
90 C, 90 C, F0 C, 10 C, 10 C, F0 C, 80 C, F0 C, 10 C, F0 C,
F0 C, 80 C, F0 C, 90 C, F0 C, F0 C, 10 C, 20 C, 40 C, 40 C,
F0 C, 90 C, F0 C, 90 C, F0 C, F0 C, 90 C, F0 C, 10 C, F0 C,
F0 C, 90 C, F0 C, 90 C, 90 C, E0 C, 90 C, E0 C, 90 C, E0 C,
F0 C, 80 C, 80 C, 80 C, F0 C, E0 C, 90 C, 90 C, 90 C, E0 C,
F0 C, 80 C, F0 C, 80 C, F0 C, F0 C, 80 C, F0 C, 80 C, 80 C,
\ VIP ROM shapes only; stored contiguously here rather than overlapped at 81xx.
CREATE CH8-VIP-DIGITS
F0 C, 90 C, 90 C, 90 C, F0 C,
60 C, 20 C, 20 C, 20 C, 70 C,
F0 C, 10 C, F0 C, 80 C, F0 C,
F0 C, 10 C, F0 C, 10 C, F0 C,
A0 C, A0 C, F0 C, 20 C, 20 C,
F0 C, 80 C, F0 C, 10 C, F0 C,
F0 C, 80 C, F0 C, 90 C, F0 C,
F0 C, 10 C, 10 C, 10 C, 10 C,
F0 C, 90 C, F0 C, 90 C, F0 C,
F0 C, 90 C, F0 C, 10 C, F0 C,
F0 C, 90 C, F0 C, 90 C, 90 C,
F0 C, 50 C, 70 C, 50 C, F0 C,
F0 C, 80 C, 80 C, 80 C, F0 C,
F0 C, 50 C, 50 C, 50 C, F0 C,
F0 C, 80 C, F0 C, 80 C, F0 C,
F0 C, 80 C, F0 C, 80 C, 80 C,
DECIMAL

\ ---- Pad mapping and configuration (36 cells; overlay -2 means not set) ----
CREATE CH8-PAD-MAP 36 CELLS ALLOT
CREATE CH8-PAD-OVERLAY 36 CELLS ALLOT
VARIABLE CH8-PAD-SEEN
: CH8-PAD-OVERLAY-CLEAR ( -- )
   36 0 DO -2 CH8-PAD-OVERLAY I CELLS + ! LOOP FALSE CH8-PAD-SEEN !
;
CH8-PAD-OVERLAY-CLEAR
CREATE CH8-PAD-KEYS 16 ALLOT
CREATE CH8-PC-KEYS 16 ALLOT
: CH8-PAD! { key input -- }
   input 0 36 WITHIN key -1 18 WITHIN AND IF
      key CH8-PAD-MAP input CELLS + !
   THEN
;
: CH8-PAD-DEFAULT ( mapped -- )
   36 0 DO -1 I CH8-PAD! LOOP
   2 0 CH8-PAD! 8 1 CH8-PAD! 4 2 CH8-PAD! 6 3 CH8-PAD! 5 4 CH8-PAD!
   IF 16 10 CH8-PAD! 17 8 CH8-PAD! THEN
;
FALSE CH8-PAD-DEFAULT
: CH8-PAD-OVERLAY-APPLY ( -- )
   36 0 DO CH8-PAD-OVERLAY I CELLS + @ DUP -2 <> IF I CH8-PAD! ELSE DROP THEN LOOP
;
: CH8-LOWER ( c -- c ) DUP 65 91 WITHIN IF 32 + THEN ;
: CH8-PAD-NAME= { a u b v -- flag }
   u v <> IF FALSE EXIT THEN
   u 0 ?DO
      a I + C@ CH8-LOWER b I + C@ CH8-LOWER <> IF FALSE UNLOOP EXIT THEN
   LOOP TRUE
;
: CH8-ROM-NAME { a u | start -- a u }
   0 TO start
   u 0 ?DO a I + C@ DUP 47 = SWAP 92 = OR IF I 1+ TO start THEN LOOP
   a start + u start -
;
: CH8-PAD-INDEX { a u | n c -- n }
   u 2 4 WITHIN IF
      a C@ CH8-LOWER 98 = IF
         0 TO n
         u 1 DO
            a I + C@ TO c
            c 48 58 WITHIN 0= IF -1 UNLOOP EXIT THEN
            n 10 * c 48 - + TO n
         LOOP
         n 32 < IF n 4 + ELSE -1 THEN EXIT
      THEN
   THEN
   a u S" up" CH8-PAD-NAME= IF 0 EXIT THEN
   a u S" down" CH8-PAD-NAME= IF 1 EXIT THEN
   a u S" left" CH8-PAD-NAME= IF 2 EXIT THEN
   a u S" right" CH8-PAD-NAME= IF 3 EXIT THEN
   a u S" a" CH8-PAD-NAME= IF 4 EXIT THEN
   a u S" b" CH8-PAD-NAME= IF 5 EXIT THEN
   a u S" x" CH8-PAD-NAME= IF 6 EXIT THEN
   a u S" y" CH8-PAD-NAME= IF 7 EXIT THEN
   a u S" l" CH8-PAD-NAME= IF 13 EXIT THEN
   a u S" r" CH8-PAD-NAME= IF 14 EXIT THEN
   a u S" back" CH8-PAD-NAME= IF 8 EXIT THEN
   a u S" start" CH8-PAD-NAME= IF 10 EXIT THEN -1
;
VARIABLE CH8-PAD-FILE-A VARIABLE CH8-PAD-FILE-U VARIABLE CH8-PAD-LINE-N
: CH8-PAD-WARN ( a u -- )
   ." WARNING " CH8-PAD-FILE-A @ CH8-PAD-FILE-U @ TYPE
   ." :" CH8-PAD-LINE-N @ . ." token " TYPE CR
;
: CH8-PAD-TOKEN { a u | eq input key c -- }
   -1 TO eq
   u 0 ?DO a I + C@ 61 = IF I TO eq LEAVE THEN LOOP
   eq 0> IF
      a eq CH8-PAD-INDEX TO input
      -2 TO key
      a eq + 1+ u eq - 1- S" reset" CH8-PAD-NAME= IF 16 TO key THEN
      a eq + 1+ u eq - 1- S" quit" CH8-PAD-NAME= IF 17 TO key THEN
      eq 2 + u = IF
         a eq + 1+ C@ CH8-LOWER TO c
         c 45 = IF -1 TO key THEN
         c 48 58 WITHIN IF c 48 - TO key THEN
         c 97 103 WITHIN IF c 87 - TO key THEN
      THEN
      input 0>= key -1 >= AND IF
         key CH8-PAD-OVERLAY input CELLS + ! key input CH8-PAD! EXIT
      THEN
   THEN
   a u CH8-PAD-WARN
;
\ Tokenizer: whitespace delimits tokens; # ends the line, even inside a token.
: CH8-PAD-NEXT { a u | n -- rest-a rest-u token-a token-u }
   BEGIN u 0> IF a C@ 32 <= ELSE FALSE THEN WHILE
      a 1+ TO a u 1- TO u
   REPEAT
   0 TO n
   BEGIN n u < IF a n + C@ DUP 32 > SWAP 35 <> AND ELSE FALSE THEN WHILE
      n 1+ TO n
   REPEAT
   n u < IF a n + C@ 35 = IF n TO u THEN THEN
   a n + u n - a n
;
: CH8-PAD-LINE { a u rom ru | t tu -- }
   a u CH8-PAD-NEXT TO tu TO t TO u TO a
   tu 0= IF EXIT THEN
   t tu rom ru CH8-PAD-NAME= 0= IF EXIT THEN
   BEGIN a u CH8-PAD-NEXT TO tu TO t TO u TO a tu 0> WHILE
      t tu CH8-PAD-TOKEN
   REPEAT
;
CREATE CH8-PAD-BUFFER 256 ALLOT
: CH8-PAD-READ { f rom ru | n more -- }
   BEGIN
      CH8-PAD-BUFFER 255 f READ-LINE THROW TO more TO n
      more
   WHILE
      1 CH8-PAD-LINE-N +!
      CH8-PAD-BUFFER n rom ru CH8-PAD-LINE
   REPEAT
;
: CH8-PAD-LOAD-FILE { rom ru file fu | f err -- }
   CH8-PAD-OVERLAY-CLEAR FALSE CH8-PAD-DEFAULT
   file CH8-PAD-FILE-A ! fu CH8-PAD-FILE-U ! 0 CH8-PAD-LINE-N !
   file fu R/O OPEN-FILE TO err TO f
   err IF EXIT THEN
   rom ru CH8-ROM-NAME TO ru TO rom
   f S" *" ['] CH8-PAD-READ CATCH TO err
   err 0= IF
      0 0 f REPOSITION-FILE TO err
      err 0= IF
         0 CH8-PAD-LINE-N !
         rom ru S" *" CH8-PAD-NAME= 0= IF
            f rom ru ['] CH8-PAD-READ CATCH TO err
            err IF 2DROP DROP THEN
         THEN
      THEN
   ELSE 2DROP DROP THEN
   f CLOSE-FILE DROP err THROW
;
: CH8-PAD-LOAD ( rom-addr rom-u -- )
   S" emu/chip8/pads.txt" CH8-PAD-LOAD-FILE
;
: CH8-MERGE-KEYS ( -- )
   16 0 DO
      CH8-PC-KEYS I + C@ CH8-PAD-KEYS I + C@ OR 0<> IF 1 ELSE 0 THEN
      CH8-KEYS I + C!
   LOOP
;

\ ---- Memory access and reset ----
: CH8-M@ ( addr -- byte )
   4095 AND CH8-MEM + C@
;

: CH8-M! ( byte addr -- )
   4095 AND CH8-MEM + C!
;

: CH8-V@ ( reg -- byte )
   CH8-V + C@
;

: CH8-V! ( byte reg -- )
   CH8-V + C!
;

: CH8-CLEAR ( -- )
   CH8-SCREEN CH8-PIXELS 0 FILL
   CH8-HISTORY CH8-PIXELS 3 * 0 FILL
   CH8-SHOWN CH8-PIXELS 0 FILL
   TRUE CH8-DIRTY !
;

: CH8-RESET ( -- )
   CH8-MEM CH8-MEM-SIZE 0 FILL
   CH8-V 16 0 FILL
   CH8-KEYS 16 0 FILL
   CH8-PC-KEYS 16 0 FILL
   CH8-PAD-KEYS 16 0 FILL
   CH8-STACK 16 CELLS 0 FILL
   CH8-CLEAR
   CH8-VIP-FONT @ IF
      CH8-VIP-DIGITS
   ELSE
      CH8-FONT
   THEN
   CH8-MEM CH8-FONT-ADDR + 80 MOVE
   CH8-ROM CH8-MEM CH8-ENTRY + CH8-ROM-SIZE @ MOVE
   CH8-ENTRY CH8-PC !
   0 CH8-I !
   0 CH8-SP !
   0 CH8-DT !
   0 CH8-ST !
   -1 CH8-WAIT !
;

\ ---- ROM loading and errors ----
: CH8-READ-ROM { f | lo hi n -- }
   f FILE-SIZE THROW
   TO hi TO lo
   hi 0<> lo CH8-ROM-MAX U> OR IF
      ." CHIP-8 ROM too large (maximum 3584 bytes)" CR CH8-ERR-ROM-SIZE THROW
   THEN
   CH8-ROM lo f READ-FILE THROW
   TO n
   n lo <> IF
      ." CHIP-8 short ROM read" CR CH8-ERR-ROM-READ THROW
   THEN
   n CH8-ROM-SIZE !
;

: CH8-LOAD { a u | f err close-err -- }
   CH8-PAD-OVERLAY-CLEAR FALSE CH8-PAD-DEFAULT
   a u R/O BIN OPEN-FILE THROW
   TO f
   f ['] CH8-READ-ROM CATCH TO err
   err IF
      DROP
   THEN
   f CLOSE-FILE TO close-err err THROW
   close-err THROW
   CH8-RESET
;

: CH8-BAD { op pc -- }
   BASE @ >R HEX ." CHIP-8 unknown opcode " op 0 <# # # # # #> TYPE
   ."  at " pc 0 <# # # # # #> TYPE CR R> BASE !
   CH8-ERR-OPCODE THROW
;

\ ---- Instruction execution ----
: CH8-SKIP ( -- )
   2 CH8-PC +!
;

\ Write VF last so the flag wins when x = F.
: CH8-FLAG { result flag x -- }
   result 255 AND x CH8-V!
   flag 1 AND 15 CH8-V!
;

: CH8-ALU { op x y | a b s -- }
   x CH8-V@ TO a
   y CH8-V@ TO b
   CH8-SHIFT-VY @ IF
      b
   ELSE
      a
   THEN
   TO s
   op 15 AND CASE
      $0 OF
         b x CH8-V!
      ENDOF
      $1 OF
         a b OR x CH8-V!
         CH8-LOGIC-VF @ IF
            0 15 CH8-V!
         THEN
      ENDOF
      $2 OF
         a b AND x CH8-V!
         CH8-LOGIC-VF @ IF
            0 15 CH8-V!
         THEN
      ENDOF
      $3 OF
         a b XOR x CH8-V!
         CH8-LOGIC-VF @ IF
            0 15 CH8-V!
         THEN
      ENDOF
      $4 OF
         a b + DUP 255 > x CH8-FLAG
      ENDOF
      $5 OF
         a b - a b >= x CH8-FLAG
      ENDOF
      $6 OF
         s 1 RSHIFT s 1 AND x CH8-FLAG
      ENDOF
      $7 OF
         b a - b a >= x CH8-FLAG
      ENDOF
      $E OF
         s 2* s 7 RSHIFT x CH8-FLAG
      ENDOF
      op CH8-PC @ 2 - CH8-BAD
   ENDCASE
;

: CH8-DRAW { x y n | sx sy bits px py addr hit -- }
   \ Start position wraps even when overflow pixels are clipped.
   x CH8-V@ 63 AND TO sx
   y CH8-V@ 31 AND TO sy
   0 TO hit
   n 0 ?DO
      CH8-I @ I + CH8-M@ TO bits
      8 0 DO
         bits 128 I RSHIFT AND IF
            sx I + TO px
            sy J + TO py
            \ Clip overflow unless wrapping was requested.
            CH8-WRAP @ px CH8-WIDTH < py CH8-HEIGHT < AND OR IF
               py 31 AND CH8-WIDTH * px 63 AND + CH8-SCREEN + TO addr
               addr C@ IF
                  1 TO hit
               THEN
               addr C@ 1 XOR addr C!
               TRUE CH8-DIRTY !
            THEN
         THEN
      LOOP
   LOOP
   hit 15 CH8-V!
   TRUE CH8-DREW !
;

\ Keep PC on Fx0A until the selected key has been released.
: CH8-KEY-WAIT { x | k -- }
   CH8-WAIT @ 0< IF
      -1 TO k
      16 0 DO
         CH8-KEYS I + C@ IF
            I TO k LEAVE
         THEN
      LOOP
      k CH8-WAIT !
      CH8-PC @ 2 - CH8-PC !
   ELSE
      CH8-WAIT @ CH8-KEYS + C@ IF
         -2 CH8-PC +!
      ELSE
         CH8-WAIT @ x CH8-V!
         -1 CH8-WAIT !
      THEN
   THEN
;

: CH8-FAMILY-F { op x | a -- }
   x CH8-V@ TO a
   op 255 AND CASE
      $07 OF
         CH8-DT @ x CH8-V!
      ENDOF
      $0A OF
         x CH8-KEY-WAIT
      ENDOF
      $15 OF
         a CH8-DT !
      ENDOF
      $18 OF
         a CH8-ST !
      ENDOF
      $1E OF
         CH8-I @ a + 65535 AND CH8-I !
      ENDOF
      $29 OF
         a 15 AND 5 * CH8-FONT-ADDR + CH8-I !
      ENDOF
      $33 OF
         a 100 / CH8-I @ CH8-M!
         a 10 / 10 MOD CH8-I @ 1+ CH8-M!
         a 10 MOD CH8-I @ 2 + CH8-M!
      ENDOF
      $55 OF
         x 1+ 0 DO
            I CH8-V@ CH8-I @ I + CH8-M!
         LOOP
         CH8-LOAD-INC @ IF
            CH8-I @ x + 1+ 65535 AND CH8-I !
         THEN
      ENDOF
      $65 OF
         x 1+ 0 DO
            CH8-I @ I + CH8-M@ I CH8-V!
         LOOP
         CH8-LOAD-INC @ IF
            CH8-I @ x + 1+ 65535 AND CH8-I !
         THEN
      ENDOF
      op CH8-PC @ 2 - CH8-BAD
   ENDCASE
;

: CH8-STEP { | pc op x y kk nnn -- }
   CH8-PC @ TO pc
   pc CH8-M@ 8 LSHIFT pc 1+ CH8-M@ OR TO op
   op 8 RSHIFT 15 AND TO x
   op 4 RSHIFT 15 AND TO y
   op 255 AND TO kk
   op 4095 AND TO nnn
   pc 2 + CH8-PC !
   op 12 RSHIFT CASE
      $0 OF
         op $E0 = IF
            CH8-CLEAR
         ELSE
            op $EE = IF
               CH8-SP @ 0= IF
                  ." CHIP-8 stack underflow" CR CH8-ERR-STACK-UNDERFLOW THROW
               THEN
               -1 CH8-SP +!
               CH8-STACK CH8-SP @ CELLS + @ CH8-PC !
            THEN
         THEN
      ENDOF
      $1 OF
         nnn CH8-PC !
      ENDOF
      $2 OF
         CH8-SP @ 16 >= IF
            ." CHIP-8 stack overflow" CR CH8-ERR-STACK-OVERFLOW THROW
         THEN
         CH8-PC @ CH8-STACK CH8-SP @ CELLS + !
         1 CH8-SP +!
         nnn CH8-PC !
      ENDOF
      $3 OF
         x CH8-V@ kk = IF
            CH8-SKIP
         THEN
      ENDOF
      $4 OF
         x CH8-V@ kk <> IF
            CH8-SKIP
         THEN
      ENDOF
      $5 OF
         op 15 AND IF
            op pc CH8-BAD
         THEN
         x CH8-V@ y CH8-V@ = IF
            CH8-SKIP
         THEN
      ENDOF
      $6 OF
         kk x CH8-V!
      ENDOF
      $7 OF
         x CH8-V@ kk + 255 AND x CH8-V!
      ENDOF
      $8 OF
         op x y CH8-ALU
      ENDOF
      $9 OF
         op 15 AND IF
            op pc CH8-BAD
         THEN
         x CH8-V@ y CH8-V@ <> IF
            CH8-SKIP
         THEN
      ENDOF
      $A OF
         nnn CH8-I !
      ENDOF
      $B OF
         nnn 0 CH8-V@ + CH8-PC !
      ENDOF
      $C OF
         CH8-SEED @ 1664525 * 1013904223 + 4294967295 AND DUP CH8-SEED !
         24 RSHIFT kk AND x CH8-V!
      ENDOF
      $D OF
         x y op 15 AND CH8-DRAW
      ENDOF
      $E OF
         kk CASE
            $9E OF
               x CH8-V@ 15 AND CH8-KEYS + C@ IF
                  CH8-SKIP
               THEN
            ENDOF
            $A1 OF
               x CH8-V@ 15 AND CH8-KEYS + C@ 0= IF
                  CH8-SKIP
               THEN
            ENDOF
            op pc CH8-BAD
         ENDCASE
      ENDOF
      $F OF
         op x CH8-FAMILY-F
      ENDOF
   ENDCASE
;

\ ---- Headless ticks ----
\ VIP approximation: stop after drawing, rather than waiting before drawing.
: CH8-TICK ( -- )
   FALSE CH8-DREW !
   CH8-SPEED @ 0 MAX 0 ?DO
      CH8-STEP
      CH8-DISPLAY-WAIT @ CH8-DREW @ AND IF
         LEAVE
      THEN
   LOOP
   CH8-DT @ IF
      -1 CH8-DT +!
   THEN
   CH8-ST @ IF
      -1 CH8-ST +!
   THEN
;

: CH8-TICKS ( n -- )
   0 ?DO
      CH8-TICK
   LOOP
;

: CH8-DUMP ( -- )
   CH8-HEIGHT 0 DO
      CH8-WIDTH 0 DO
         CH8-SCREEN J CH8-WIDTH * I + + C@
         IF
            35
         ELSE
            46
         THEN
         EMIT
      LOOP
      CR
   LOOP
;

\ ---- Display and optional sound ----
REQUIRE-GRAPHICS ALSO GRAPHICS
CREATE CH8-PALETTE 256 CELLS ALLOT
CH8-PALETTE 256 CELLS 0 FILL
14745568 CH8-PALETTE CELL+ !
\ Compose before shifting: history contains the three preceding ticks.
\ LAST-SHOWN is acknowledged only after the host actually calls SHOW.
: CH8-BLEND-FRAME { | n pixel -- }
   CH8-BLEND @ 1 MAX 4 MIN TO n
   FALSE CH8-DIRTY !
   CH8-PIXELS 0 DO
      CH8-SCREEN I + C@ TO pixel
      n 1 ?DO
         CH8-HISTORY I 1- CH8-PIXELS * J + + C@ pixel OR TO pixel
      LOOP
      pixel CH8-SHOWN I + C!
      pixel CH8-LAST-SHOWN I + C@ <> IF TRUE CH8-DIRTY ! THEN
   LOOP
   CH8-HISTORY CH8-PIXELS + CH8-HISTORY CH8-PIXELS 2 * + CH8-PIXELS MOVE
   CH8-HISTORY CH8-HISTORY CH8-PIXELS + CH8-PIXELS MOVE
   CH8-SCREEN CH8-HISTORY CH8-PIXELS MOVE
;

: CH8-PAINT ( -- )
   CH8-SHOWN CH8-WIDTH CH8-HEIGHT CH8-PALETTE 0 0 -1 GFX-INDEXED
;

: CH8-AUDIO-LOAD ( -- flag )
   S" REQUIRE-AUDIO" ['] EVALUATE CATCH DUP IF
      NIP NIP
   THEN
   0=
;

CH8-AUDIO-LOAD [IF]
ALSO AUDIO
VARIABLE CH8-PCM
VARIABLE CH8-PHASE
CREATE CH8-WAVE 1600 ALLOT
4096 CONSTANT CH8-PCM-CAPACITY
: CH8-TRY-SOUND-OPEN ( -- )
   AUDIO? IF
      48000 1 CH8-PCM-CAPACITY PCM-OPEN THROW CH8-PCM !
   THEN
;

: CH8-SOUND-OPEN ( -- )
   CH8-PCM @ IF EXIT THEN
   0 CH8-PCM !
   \ Catch with no arguments so THROW restores an empty stack segment.
   ['] CH8-TRY-SOUND-OPEN CATCH
   DUP -28 = IF THROW THEN
   DROP
;

: CH8-SOUND-CLOSE ( -- )
   CH8-PCM @ ?DUP IF
      0 0 ROT PCM-STOP 2DROP
      CH8-PCM @ PCM-CLOSE THROW
      0 CH8-PCM !
   THEN
;

: CH8-BLOCK ( -- )
   800 0 DO
      CH8-PHASE @ 24000 < IF
         3000
      ELSE
         -3000
      THEN
      DUP 255 AND CH8-WAVE I 2* + C!
      8 RSHIFT 255 AND CH8-WAVE I 2* 1+ + C!
      CH8-PHASE @ 440 + 48000 MOD CH8-PHASE !
   LOOP
;

: CH8-SOUND ( -- )
   CH8-PCM @ CH8-ST @ 0> AND IF
      BEGIN
         CH8-PCM @ PCM-QUEUED THROW
         1600 < WHILE
         CH8-BLOCK
         CH8-WAVE 800 CH8-PCM @ PCM-WRITE THROW
         0= IF
            EXIT
         THEN
      REPEAT
   THEN
;

PREVIOUS
[ELSE]
: CH8-SOUND-OPEN ( -- )
;

: CH8-SOUND-CLOSE ( -- )
;

: CH8-SOUND ( -- )
;

[THEN]
\ ---- Host input and interactive loop ----
CREATE CH8-HOST-KEYS S" x123qweasdzc4rfv" HERE SWAP DUP ALLOT MOVE
VARIABLE CH8-DONE
VARIABLE CH8-DEADLINE
VARIABLE CH8-CLOSES
VARIABLE CH8-PAD-OK
CREATE CH8-PAD-WAS 36 ALLOT
CREATE CH8-PAD-AXIS-SEEN 2 ALLOT
: CH8-PAD-BEGIN ( -- )
   FALSE CH8-PAD-SEEN !
   CH8-PAD-WAS 36 0 FILL CH8-PAD-AXIS-SEEN 2 0 FILL
;
: CH8-PAD-APPLY { input down | key -- }
   CH8-PAD-MAP input CELLS + @ TO key
   down IF
      key 0 16 WITHIN IF 1 CH8-PAD-KEYS key + C! THEN
      CH8-PAD-WAS input + C@ 0= IF
         key 16 = IF CH8-RESET THEN
         key 17 = IF TRUE CH8-DONE ! THEN
      THEN
   THEN
   down 0<> IF 1 ELSE 0 THEN CH8-PAD-WAS input + C!
;
: CH8-PAD-STATE { dirs buttons mapped -- }
   CH8-PAD-SEEN @ 0= IF
      mapped CH8-PAD-DEFAULT CH8-PAD-OVERLAY-APPLY TRUE CH8-PAD-SEEN !
   THEN
   \ Process actions first: reset clears keys, then rebuild all held keys.
   36 0 DO
      I 4 < IF dirs 1 I LSHIFT AND ELSE buttons 1 I 4 - LSHIFT AND THEN
      I SWAP CH8-PAD-APPLY
   LOOP
   CH8-PAD-KEYS 16 0 FILL
   36 0 DO
      CH8-PAD-WAS I + C@ IF
         CH8-PAD-MAP I CELLS + @ DUP 0 16 WITHIN IF
            1 SWAP CH8-PAD-KEYS + C!
         ELSE DROP THEN
      THEN
   LOOP
;
: CH8-PAD-AXIS-VALUE { value axis mapped -- value }
   mapped 0= IF
      value -32768 <> IF 1 CH8-PAD-AXIS-SEEN axis + C! THEN
      CH8-PAD-AXIS-SEEN axis + C@ 0= IF 0 EXIT THEN
   THEN value
;
: CH8-PAD-DIRS { hat x y buttons mapped | dirs -- dirs }
   0 TO dirs
   hat 1 AND y -16384 < OR IF dirs 1 OR TO dirs THEN
   hat 4 AND y 16384 > OR IF dirs 2 OR TO dirs THEN
   hat 8 AND x -16384 < OR IF dirs 4 OR TO dirs THEN
   hat 2 AND x 16384 > OR IF dirs 8 OR TO dirs THEN
   mapped IF dirs buttons 11 RSHIFT 15 AND OR TO dirs THEN
   dirs
;
: CH8-PAD-READ-STATE { | mapped hat x y buttons axes -- dirs buttons mapped }
   0 GAMEPAD-MAPPED? TO mapped
   0 TO hat 0 TO x 0 TO y 0 TO buttons
   0 GAMEPAD-HATS 0> IF 0 0 GAMEPAD-HAT TO hat THEN
   0 GAMEPAD-AXES TO axes
   axes 0> IF 0 0 GAMEPAD-AXIS 0 mapped CH8-PAD-AXIS-VALUE TO x THEN
   axes 1 > IF 1 0 GAMEPAD-AXIS 1 mapped CH8-PAD-AXIS-VALUE TO y THEN
   0 GAMEPAD-BUTTON-COUNT 32 MIN 0 ?DO
      I 0 GAMEPAD-BUTTON? IF buttons 1 I LSHIFT OR TO buttons THEN
   LOOP
   hat x y buttons mapped CH8-PAD-DIRS buttons mapped
;
: CH8-PAD-INPUT { | count -- }
   CH8-PAD-KEYS 16 0 FILL
   CH8-PAD-OK @ 0= IF EXIT THEN
   GAMEPAD-POLL TO count
   count 0< IF FALSE CH8-PAD-OK ! THEN
   count 1 < IF CH8-PAD-WAS 36 0 FILL EXIT THEN
   CH8-PAD-READ-STATE CH8-PAD-STATE
;
TRUE CH8-PAD-OK !

: CH8-NOW ( -- us )
   UTIME DROP
;

: CH8-PAD-PRINT { dirs buttons mapped | comma -- }
   ." mapped=" mapped 0<> IF 1 ELSE 0 THEN . ." directions="
   FALSE TO comma
   dirs 15 AND 0= IF ." -" THEN
   dirs 1 AND IF ." up" TRUE TO comma THEN
   dirs 2 AND IF comma IF ." ," THEN ." down" TRUE TO comma THEN
   dirs 4 AND IF comma IF ." ," THEN ." left" TRUE TO comma THEN
   dirs 8 AND IF comma IF ." ," THEN ." right" THEN
   ."  buttons=" FALSE TO comma
   buttons $FFFFFFFF AND 0= IF ." -" THEN
   32 0 DO buttons 1 I LSHIFT AND IF
      comma IF ." ," THEN I 0 <# #S #> TYPE TRUE TO comma
   THEN LOOP CR
;
: CH8-PAD-TEST { | deadline count -- }
   CH8-PAD-BEGIN CH8-NOW 30000000 + TO deadline
   BEGIN INKEY -1 = CH8-NOW deadline < AND WHILE
      GAMEPAD-POLL TO count count 0< IF EXIT THEN
      count 0> IF CH8-PAD-READ-STATE CH8-PAD-PRINT
      ELSE ." no pad" CR THEN
      100 MS
   REPEAT
;

: CH8-INPUT ( -- )
   BEGIN
      INKEY DUP -1 <> WHILE
      DUP 27 = IF
         TRUE CH8-DONE !
      THEN
      K-F5 = IF
         CH8-RESET
      THEN
   REPEAT
   DROP
   CH8-PAD-INPUT
   16 0 DO
      CH8-HOST-KEYS I + C@ DUP KEY-HELD? SWAP
      DUP 97 >= OVER 122 <= AND IF
         32 - KEY-HELD? OR
      ELSE
         DROP
      THEN
      IF
         1
      ELSE
         0
      THEN
      CH8-PC-KEYS I + C!
   LOOP
   CH8-MERGE-KEYS
   WINDOW-CLOSES CH8-CLOSES @ <> IF
      TRUE CH8-DONE !
   THEN
;

: CH8-LOOP ( -- )
   CH8-WIDTH CH8-HEIGHT GFX-INIT
   640 320 WINDOW-SIZE
   WINDOW-CLOSES CH8-CLOSES !
   FALSE CH8-DONE !
   CH8-SOUND-OPEN
   CH8-NOW CH8-DEADLINE !
   BEGIN
      CH8-INPUT CH8-DONE @ 0= WHILE
      CH8-NOW CH8-DEADLINE @ - DUP 0>= IF
         \ Catch up short delays; resync after more than five ticks.
         CH8-TICK-US 5 * > IF
            CH8-NOW CH8-DEADLINE !
         THEN
         CH8-TICK
         CH8-SOUND
         CH8-BLEND-FRAME
         CH8-DIRTY @ IF
            CH8-PAINT SHOW
            CH8-SHOWN CH8-LAST-SHOWN CH8-PIXELS MOVE
            FALSE CH8-DIRTY !
         THEN
         CH8-TICK-US CH8-DEADLINE +!
      ELSE
         DROP 1 MS
      THEN
   REPEAT
;

: CH8-RUN ( -- )
   TRUE CH8-PAD-OK !
   CH8-PAD-BEGIN
   UTIME DROP CH8-SEED !
   ['] CH8-LOOP CATCH >R
   ['] CH8-SOUND-CLOSE CATCH
   R> ?DUP IF
      NIP THROW
   THEN
   THROW
;

: CH8-PLAY ( addr len -- )
   2DUP CH8-LOAD
   CH8-PAD-LOAD
   CH8-RUN
;

CH8-RESET
\ ---- Command line ----
: CH8-USAGE ( -- )
   ." Usage: sigma emu/chip8/chip8.fs ROM [vip|chip48] | padtest" CR
;

: CH8-NAME= { a u b v -- flag }
   u v <> IF
      FALSE EXIT
   THEN
   u 0 ?DO
      a I + C@ DUP $41 $5B WITHIN IF
         $20 +
      THEN
      b I + C@ <> IF
         FALSE UNLOOP EXIT
      THEN
   LOOP
   TRUE
;

: CH8-PROFILE { a u -- flag }
   a u S" vip" CH8-NAME= IF
      CH8-VIP TRUE EXIT
   THEN
   a u S" chip48" CH8-NAME= IF
      CH8-CHIP48 TRUE EXIT
   THEN
   FALSE
;

: CH8-START ( -- )
   1 ARG 2DUP S" padtest" CH8-PAD-NAME= IF
      2DROP CH8-PAD-TEST BYE
   THEN 2DROP
   1 ARG DUP IF
      OVER C@ 45 <> IF
         2DROP NEXT-ARG
         1 ARG DUP IF
            2DROP NEXT-ARG CH8-PROFILE 0= IF
               2DROP CH8-USAGE BYE
            THEN
            1 ARG NIP IF
               2DROP CH8-USAGE BYE
            THEN
         ELSE
            2DROP
         THEN
         CH8-PLAY BYE
      THEN
   THEN
   2DROP
;

CH8-START
