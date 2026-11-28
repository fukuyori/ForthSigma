\ Run from repository root. INCLUDE is relative to the working directory.
INCLUDE emu/chip8/chip8.fs
DECIMAL
VARIABLE CH8-PASSED
VARIABLE CH8-FAILED

\ ---- Assertions and setup ----
: CH8-CHECK { actual expected label len -- }
   actual expected = IF
      1 CH8-PASSED +!
   ELSE
      1 CH8-FAILED +! ." FAIL " label len TYPE SPACE ." expected " expected . ." actual " actual .
      CR
   THEN
;

: CH8-OP { op -- }
   op 8 RSHIFT 512 CH8-M!
   op 255 AND 513 CH8-M!
   512 CH8-PC !
   CH8-STEP
;

: CH8-NEW ( -- )
   CH8-CHIP48 0 CH8-ROM-SIZE !
   CH8-RESET
;

: CH8-REG { op a b expected flag -- }
   CH8-NEW
   a 1 CH8-V!
   b 2 CH8-V!
   77 15 CH8-V!
   op CH8-OP
   1 CH8-V@ expected S" ALU Vx" CH8-CHECK
   15 CH8-V@ flag S" ALU VF" CH8-CHECK
;

\ ---- CPU and existing behaviour ----
: CH8-TEST-CPU ( -- )
   CH8-NEW
   $0123 CH8-OP
   CH8-PC @ $202 S" cpu $0123 PC $202" CH8-CHECK
   $612A CH8-OP
   $1 CH8-V@ $2A S" cpu $612A $1 V@ $2A" CH8-CHECK
   $71F0 CH8-OP
   $1 CH8-V@ $1A S" cpu $71F0 $1 V@ $1A" CH8-CHECK
   $311A CH8-OP
   CH8-PC @ $204 S" cpu $311A PC $204" CH8-CHECK
   $3100 CH8-OP
   CH8-PC @ $202 S" cpu $3100 PC $202" CH8-CHECK
   $4100 CH8-OP
   CH8-PC @ $204 S" cpu $4100 PC $204" CH8-CHECK
   $411A CH8-OP
   CH8-PC @ $202 S" cpu $411A PC $202" CH8-CHECK
   $1A $2 CH8-V!
   $5120 CH8-OP
   CH8-PC @ $204 S" cpu $5120 PC $204" CH8-CHECK
   $9120 CH8-OP
   CH8-PC @ $202 S" cpu $9120 PC $202" CH8-CHECK
   $0 $2 CH8-V!
   $5120 CH8-OP
   CH8-PC @ $202 S" cpu $5120 PC $202" CH8-CHECK
   $9120 CH8-OP
   CH8-PC @ $204 S" cpu $9120 PC $204" CH8-CHECK
   $1ABC CH8-OP
   CH8-PC @ $ABC S" cpu $1ABC PC $ABC" CH8-CHECK
   $2345 CH8-OP
   CH8-PC @ $345 S" cpu $2345 PC $345" CH8-CHECK
   CH8-SP @ $1 S" cpu $2345 SP $1" CH8-CHECK
   $00EE CH8-OP
   CH8-PC @ $202 S" cpu $00EE PC $202" CH8-CHECK
   CH8-SP @ $0 S" cpu $00EE SP $0" CH8-CHECK
   $AFFF CH8-OP
   CH8-I @ $FFF S" cpu $AFFF I $FFF" CH8-CHECK
   $60FE CH8-OP
   $BFFF CH8-OP
   CH8-PC @ $10FD S" cpu $BFFF PC $10FD" CH8-CHECK
   $C100 CH8-OP
   $1 CH8-V@ $0 S" cpu $C100 $1 V@ $0" CH8-CHECK
   $C1A5 CH8-OP
   $1 CH8-V@ $5A AND $0 S" cpu $C1A5 $1 V@ $5A AND $0" CH8-CHECK
   $8120 12 34 34 77 CH8-REG
   $8121 12 34 46 77 CH8-REG
   $8122 12 34 0 77 CH8-REG
   $8123 12 34 46 77 CH8-REG
   $8124 250 10 4 1 CH8-REG
   $8124 2 3 5 0 CH8-REG
   $8125 10 10 0 1 CH8-REG
   $8125 1 2 255 0 CH8-REG
   $8127 1 2 1 1 CH8-REG
   $8127 2 1 255 0 CH8-REG
   $8126 3 8 1 1 CH8-REG
   $812E 128 3 0 1 CH8-REG
   TRUE CH8-SHIFT-VY !
   3 1 CH8-V!
   130 2 CH8-V!
   $8126 CH8-OP
   1 CH8-V@ 65 S" cpu $8126 1 V@ 65" CH8-CHECK
   2 CH8-V@ 130 S" cpu $8126 2 V@ 130" CH8-CHECK
   15 CH8-V@ 0 S" cpu $8126 15 V@ 0" CH8-CHECK
   129 2 CH8-V!
   $812E CH8-OP
   1 CH8-V@ 2 S" cpu $812E 1 V@ 2" CH8-CHECK
   15 CH8-V@ 1 S" cpu $812E 15 V@ 1" CH8-CHECK
   FALSE CH8-SHIFT-VY !
;

\ Flag destinations alias VF; operands must be captured before writes.
: CH8-TEST-FLAGS ( -- )
   CH8-NEW
   250 15 CH8-V!
   10 2 CH8-V!
   $8F24 CH8-OP
   15 CH8-V@ 1 S" flags $8F24 15 V@ 1" CH8-CHECK
   1 15 CH8-V!
   2 2 CH8-V!
   $8F25 CH8-OP
   15 CH8-V@ 0 S" flags $8F25 15 V@ 0" CH8-CHECK
   3 15 CH8-V!
   $8F26 CH8-OP
   15 CH8-V@ 1 S" flags $8F26 15 V@ 1" CH8-CHECK
   1 15 CH8-V!
   2 2 CH8-V!
   $8F27 CH8-OP
   15 CH8-V@ 1 S" flags $8F27 15 V@ 1" CH8-CHECK
   128 15 CH8-V!
   $8F2E CH8-OP
   15 CH8-V@ 1 S" flags $8F2E 15 V@ 1" CH8-CHECK
   TRUE CH8-SHIFT-VY !
   3 2 CH8-V!
   $8F26 CH8-OP
   15 CH8-V@ 1 S" flags $8F26 15 V@ 1" CH8-CHECK
   128 2 CH8-V!
   $8F2E CH8-OP
   15 CH8-V@ 1 S" flags $8F2E 15 V@ 1" CH8-CHECK
;

: CH8-TEST-F ( -- )
   CH8-NEW
   42 CH8-DT !
   $F107 CH8-OP
   1 CH8-V@ 42 S" f $F107 1 V@ 42" CH8-CHECK
   $F115 $F118 SWAP CH8-OP
   CH8-OP
   CH8-DT @ 42 S" f $F107 DT 42" CH8-CHECK
   CH8-ST @ 42 S" f $F107 ST 42" CH8-CHECK
   65530 CH8-I !
   10 1 CH8-V!
   99 15 CH8-V!
   $F11E CH8-OP
   CH8-I @ 4 S" f $F11E I 4" CH8-CHECK
   15 CH8-V@ 99 S" f $F11E 15 V@ 99" CH8-CHECK
   16 0 DO
      I 240 OR 1 CH8-V!
      $F129 CH8-OP
      CH8-I @ I 5 * 80 + S" f $F129 I I 5 * 80 +" CH8-CHECK
   LOOP
   CH8-MEM 80 + C@ 240 S" f $F129 MEM 80 + byte 240" CH8-CHECK
   CH8-MEM 159 + C@ 128 S" f $F129 MEM 159 + byte 128" CH8-CHECK
   8191 CH8-I !
   254 1 CH8-V!
   $F133 CH8-OP
   4095 CH8-M@ 2 S" f $F133 4095 M@ 2" CH8-CHECK
   0 CH8-M@ 5 S" f $F133 0 M@ 5" CH8-CHECK
   1 CH8-M@ 4 S" f $F133 1 M@ 4" CH8-CHECK
   2 0 DO
      I CH8-LOAD-INC !
      8191 CH8-I !
      12 0 CH8-V!
      34 1 CH8-V!
      $F155 CH8-OP
      4095 CH8-M@ 12 S" f $F155 4095 M@ 12" CH8-CHECK
      0 CH8-M@ 34 S" f $F155 0 M@ 34" CH8-CHECK
      CH8-I @ 8191 I IF
         2 +
      THEN
      S" f $F155 I 8191 I IF 2 + THEN" CH8-CHECK
      8191 CH8-I !
      0 0 CH8-V!
      0 1 CH8-V!
      $F165 CH8-OP
      0 CH8-V@ 12 S" f $F165 0 V@ 12" CH8-CHECK
      1 CH8-V@ 34 S" f $F165 1 V@ 34" CH8-CHECK
      CH8-I @ 8191 I IF
         2 +
      THEN
      S" f $F165 I 8191 I IF 2 + THEN" CH8-CHECK
   LOOP
   31 1 CH8-V!
   1 CH8-KEYS 15 + C!
   $E19E CH8-OP
   CH8-PC @ 516 S" f $E19E PC 516" CH8-CHECK
   $E1A1 CH8-OP
   CH8-PC @ 514 S" f $E1A1 PC 514" CH8-CHECK
   0 CH8-KEYS 15 + C!
   $E19E CH8-OP
   CH8-PC @ 514 S" f $E19E PC 514" CH8-CHECK
   $E1A1 CH8-OP
   CH8-PC @ 516 S" f $E1A1 PC 516" CH8-CHECK
   $F10A CH8-OP
   CH8-PC @ 512 S" f $F10A PC 512" CH8-CHECK
   1 CH8-KEYS 7 + C!
   CH8-STEP CH8-PC @ 512 S" f $F10A 1 KEYS 7 + C! STEP PC 512" CH8-CHECK
   CH8-STEP CH8-PC @ 512 S" f $F10A STEP PC 512" CH8-CHECK
   0 CH8-KEYS 7 + C!
   CH8-STEP CH8-PC @ 514 S" f $F10A 0 KEYS 7 + C! STEP PC 514" CH8-CHECK
   1 CH8-V@ 7 S" f $F10A 1 V@ 7" CH8-CHECK
   0 CH8-SPEED !
   2 CH8-DT !
   1 CH8-ST !
   CH8-TICK CH8-DT @ 1 S" f $F10A DT 1" CH8-CHECK
   CH8-ST @ 0 S" f $F10A ST 0" CH8-CHECK
   3 CH8-TICKS CH8-DT @ 0 S" f $F10A 3 TICKS DT 0" CH8-CHECK
   10 CH8-SPEED !
;

: CH8-TEST-DRAW ( -- )
   CH8-NEW
   4095 CH8-I !
   255 4095 CH8-M!
   128 0 CH8-M!
   127 1 CH8-V!
   63 2 CH8-V!
   $D122 CH8-OP
   CH8-SCREEN 2047 + C@ 1 S" draw $D122 SCREEN 2047 + byte 1" CH8-CHECK
   CH8-SCREEN 1984 + C@ 0 S" draw $D122 SCREEN 1984 + byte 0" CH8-CHECK
   CH8-SCREEN 63 + C@ 0 S" draw $D122 SCREEN 63 + byte 0" CH8-CHECK
   15 CH8-V@ 0 S" draw $D122 15 V@ 0" CH8-CHECK
   CH8-I @ 4095 S" draw $D122 I 4095" CH8-CHECK
   $D122 CH8-OP
   CH8-SCREEN 2047 + C@ 0 S" draw $D122 SCREEN 2047 + byte 0" CH8-CHECK
   15 CH8-V@ 1 S" draw $D122 15 V@ 1" CH8-CHECK
   TRUE CH8-WRAP !
   $D122 CH8-OP
   CH8-SCREEN 1984 + C@ 1 S" draw $D122 SCREEN 1984 + byte 1" CH8-CHECK
   CH8-SCREEN 63 + C@ 1 S" draw $D122 SCREEN 63 + byte 1" CH8-CHECK
   $00E0 CH8-OP
   CH8-SCREEN 2047 + C@ 0 S" draw $00E0 SCREEN 2047 + byte 0" CH8-CHECK
   CH8-SCREEN 63 + C@ 0 S" draw $00E0 SCREEN 63 + byte 0" CH8-CHECK
   128 15 CH8-V!
   0 2 CH8-V!
   $DF21 CH8-OP
   CH8-SCREEN C@ 1 S" draw $DF21 SCREEN byte 1" CH8-CHECK
   15 CH8-V@ 0 S" draw $DF21 15 V@ 0" CH8-CHECK
;

: CH8-RETURN ( -- )
   $00EE CH8-OP
;

: CH8-CALL ( -- )
   $2200 CH8-OP
;

: CH8-UNKNOWN ( -- )
   $FFFF CH8-OP
;

: CH8-INVALID5 ( -- )
   $5121 CH8-OP
;

: CH8-INVALID9 ( -- )
   $9121 CH8-OP
;

: CH8-INVALID8 ( -- )
   $8128 CH8-OP
;

: CH8-INVALIDE ( -- )
   $E100 CH8-OP
;

: CH8-TOO-LARGE ( -- )
   S" emu/chip8/chip8.fs" CH8-LOAD
;

: CH8-TEST-ERRORS ( -- )
   CH8-NEW
   ['] CH8-RETURN CATCH -4103 S" errors $E100 NEW ['] RETURN CATCH -4103" CH8-CHECK
   16 0 DO
      CH8-CALL
   LOOP
   CH8-SP @ 16 S" errors $E100 16 0 DO CALL LOOP SP 16" CH8-CHECK
   ['] CH8-CALL CATCH -4104 S" errors $E100 ['] CALL CATCH -4104" CH8-CHECK
   ['] CH8-UNKNOWN CATCH -4102 S" errors $E100 ['] UNKNOWN CATCH -4102" CH8-CHECK
   ['] CH8-INVALID5 CATCH -4102 S" errors $E100 ['] INVALID5 CATCH -4102" CH8-CHECK
   ['] CH8-INVALID9 CATCH -4102 S" errors $E100 ['] INVALID9 CATCH -4102" CH8-CHECK
   ['] CH8-INVALID8 CATCH -4102 S" errors $E100 ['] INVALID8 CATCH -4102" CH8-CHECK
   ['] CH8-INVALIDE CATCH -4102 S" errors $E100 ['] INVALIDE CATCH -4102" CH8-CHECK
   ['] CH8-TOO-LARGE CATCH -4100 S" errors $E100 ['] TOO-LARGE CATCH -4100" CH8-CHECK
;

\ The ROMs are not in the repository (emu/roms/ is ignored by Git).
\ A ROM smoke test is skipped, with an INFO line, when its file is missing.
: CH8-ROM? ( addr u -- flag )
   R/O BIN OPEN-FILE IF
      DROP FALSE
   ELSE
      CLOSE-FILE DROP TRUE
   THEN
;

: CH8-MAZE ( -- )
   S" emu/roms/c8games/MAZE" CH8-LOAD 300 CH8-TICKS CH8-DUMP
;

: CH8-PONG ( -- )
   S" emu/roms/c8games/PONG" CH8-LOAD 300 CH8-TICKS
;

: CH8-SMOKE { xt a u -- }
   a u CH8-ROM? IF
      xt CATCH 0 a u CH8-CHECK
   ELSE
      ." INFO skipped, ROM not found: " a u TYPE CR
   THEN
;

: CH8-TEST-EXTRA ( -- )
   CH8-NEW
   77 15 CH8-V!
   $61FF CH8-OP
   $7101 CH8-OP
   1 CH8-V@ 0 S" extra $7101 1 V@ 0" CH8-CHECK
   15 CH8-V@ 77 S" extra $7101 15 V@ 77" CH8-CHECK
   255 4095 CH8-M!
   255 0 CH8-M!
   4095 CH8-PC !
   ['] CH8-STEP CATCH -4102 S" extra $7101 ['] STEP CATCH -4102" CH8-CHECK
   CH8-NEW
   $7001 8 RSHIFT 512 CH8-M!
   1 513 CH8-M!
   $1200 8 RSHIFT 514 CH8-M!
   0 515 CH8-M!
   4 CH8-SPEED !
   CH8-TICK 0 CH8-V@ 2 S" extra $7101 4 SPEED ! TICK 0 V@ 2" CH8-CHECK
   CH8-PC @ 512 S" extra $7101 PC 512" CH8-CHECK
   10 CH8-SPEED !
   \ A two-byte ROM image in memory: reset must restore it from the copy.
   $12 CH8-ROM C! $34 CH8-ROM 1+ C! 2 CH8-ROM-SIZE ! CH8-RESET
   512 CH8-M@ >R 0 512 CH8-M!
   99 1 CH8-V!
   CH8-RESET
   512 CH8-M@ R> S" extra $7101 512 M@ R>" CH8-CHECK
   1 CH8-V@ 0 S" extra $7101 1 V@ 0" CH8-CHECK
   CH8-SP @ 0 S" extra $7101 SP 0" CH8-CHECK
   CH8-PC @ 512 S" extra $7101 PC 512" CH8-CHECK
   CH8-NEW
   TRUE CH8-SHIFT-VY !
   128 1 CH8-V!
   3 15 CH8-V!
   $81F6 CH8-OP
   1 CH8-V@ 1 S" extra $81F6 1 V@ 1" CH8-CHECK
   15 CH8-V@ 1 S" extra $81F6 15 V@ 1" CH8-CHECK
;


\ ---- COSMAC VIP switches and profiles ----
: CH8-TEST-LOGIC { enabled op expected -- }
   CH8-NEW
   enabled CH8-LOGIC-VF !
   12 1 CH8-V!
   34 2 CH8-V!
   77 15 CH8-V!
   op CH8-OP
   1 CH8-V@ expected S" logic result" CH8-CHECK
   15 CH8-V@ enabled IF
      0
   ELSE
      77
   THEN
   S" logic VF" CH8-CHECK
   12 15 CH8-V!
   34 2 CH8-V!
   op $0F00 OR CH8-OP
   15 CH8-V@ enabled IF
      0
   ELSE
      expected
   THEN
   S" logic x=F" CH8-CHECK
;


: CH8-PUT-OP { op addr -- }
   op 8 RSHIFT addr CH8-M!
   op $FF AND addr 1+ CH8-M!
;


: CH8-TEST-DISPLAY ( -- )
   2 0 DO
      CH8-NEW
      I 0<> CH8-DISPLAY-WAIT !
      10 CH8-SPEED !
      $D011 $200 CH8-PUT-OP
      $D011 $202 CH8-PUT-OP
      $627B $204 CH8-PUT-OP
      CH8-TICK CH8-PC @ I IF
         $202
      ELSE
         $214
      THEN
      S" display burst PC" CH8-CHECK
      2 CH8-V@ I IF
         0
      ELSE
         $7B
      THEN
      S" display burst register" CH8-CHECK
      I IF
         CH8-TICK CH8-PC @ $204 S" display second tick" CH8-CHECK
         CH8-TICK 2 CH8-V@ $7B S" display third tick" CH8-CHECK
      THEN
      CH8-NEW
      TRUE CH8-DISPLAY-WAIT !
      $D011 $200 CH8-PUT-OP
      $D011 $202 CH8-PUT-OP
      CH8-STEP CH8-STEP CH8-PC @ $204 S" standalone steps ignore display wait" CH8-CHECK
   LOOP
;


: CH8-DIGIT { digit b0 b1 b2 b3 b4 | addr -- }
   CH8-FONT-ADDR digit 5 * + TO addr addr CH8-M@ b0 S" font byte 0" CH8-CHECK
   addr 1+ CH8-M@ b1 S" font byte 1" CH8-CHECK
   addr 2 + CH8-M@ b2 S" font byte 2" CH8-CHECK
   addr 3 + CH8-M@ b3 S" font byte 3" CH8-CHECK
   addr 4 + CH8-M@ b4 S" font byte 4" CH8-CHECK
;


: CH8-TEST-PROFILES ( -- )
   17 CH8-SPEED !
   TRUE CH8-WRAP !
   CH8-VIP CH8-SHIFT-VY @ TRUE S" VIP shift" CH8-CHECK
   CH8-LOAD-INC @ TRUE S" VIP load" CH8-CHECK
   CH8-LOGIC-VF @ TRUE S" VIP logic" CH8-CHECK
   CH8-DISPLAY-WAIT @ TRUE S" VIP display" CH8-CHECK
   CH8-VIP-FONT @ TRUE S" VIP font" CH8-CHECK
   CH8-WRAP @ FALSE S" VIP wrap" CH8-CHECK
   CH8-SPEED @ 17 S" VIP preserves speed" CH8-CHECK
   CH8-RESET
   1 $60 $20 $20 $20 $70 CH8-DIGIT
   4 $A0 $A0 $F0 $20 $20 CH8-DIGIT
   7 $F0 $10 $10 $10 $10 CH8-DIGIT
   $B $F0 $50 $70 $50 $F0 CH8-DIGIT
   $D $F0 $50 $50 $50 $F0 CH8-DIGIT
   TRUE CH8-WRAP !
   CH8-CHIP48 CH8-SHIFT-VY @ FALSE S" CHIP48 shift" CH8-CHECK
   CH8-LOAD-INC @ FALSE S" CHIP48 load" CH8-CHECK
   CH8-LOGIC-VF @ FALSE S" CHIP48 logic" CH8-CHECK
   CH8-DISPLAY-WAIT @ FALSE S" CHIP48 display" CH8-CHECK
   CH8-VIP-FONT @ FALSE S" CHIP48 font" CH8-CHECK
   CH8-WRAP @ FALSE S" CHIP48 wrap" CH8-CHECK
   CH8-SPEED @ 17 S" CHIP48 preserves speed" CH8-CHECK
   CH8-RESET
   1 $20 $60 $20 $20 $70 CH8-DIGIT
   4 $90 $90 $F0 $10 $10 CH8-DIGIT
   7 $F0 $10 $20 $40 $40 CH8-DIGIT
   $B $E0 $90 $E0 $90 $E0 CH8-DIGIT
   $D $E0 $90 $90 $90 $E0 CH8-DIGIT
   10 CH8-SPEED !
;


: CH8-TEST-VIP ( -- )
   2 0 DO
      I 0<> $8121 46 CH8-TEST-LOGIC
      I 0<> $8122 0 CH8-TEST-LOGIC
      I 0<> $8123 46 CH8-TEST-LOGIC
   LOOP
   CH8-TEST-DISPLAY CH8-TEST-PROFILES
;

\ ---- Optional audio: open/close only, never submit samples ----
CH8-AUDIO-LOAD [IF]
ALSO AUDIO
: CH8-TEST-SOUND-CYCLE ( -- )
   CH8-SOUND-OPEN
   ." INFO sound stream opened: " CH8-PCM @ 0<> . CR
   CH8-PCM @ IF
      0 CH8-ST !
      123 CH8-PHASE !
      CH8-WAVE 1600 90 FILL
      CH8-SOUND
      CH8-PHASE @ 123 S" silent sound phase unchanged" CH8-CHECK
      1600 0 DO
         CH8-WAVE I + C@ 90 S" silent sound buffer unchanged" CH8-CHECK
      LOOP
      CH8-PCM @ PCM-QUEUED THROW 0 S" silent sound queued frames" CH8-CHECK
   THEN
   CH8-SOUND-CLOSE
;

: CH8-TEST-SOUND { | before -- }
   DEPTH TO before
   ['] CH8-TEST-SOUND-CYCLE CATCH 0 S" sound cycle no THROW" CH8-CHECK
   DEPTH before S" sound cycle stack depth" CH8-CHECK
   CH8-PCM @ 0 S" sound cycle closed" CH8-CHECK
;
PREVIOUS
CH8-TEST-SOUND
[THEN]


\ ---- Host-free pad state, parser and formatting tests ----
: CH8-PAD@ ( input -- target ) CELLS CH8-PAD-MAP + @ ;
: CH8-PAD-TEST-LINE ( a u -- ) S" pong" CH8-PAD-LINE ;
: CH8-TEST-PADS ( -- )
   CH8-PAD-OVERLAY-CLEAR CH8-PAD-BEGIN
   FALSE CH8-PAD-DEFAULT
   0 CH8-PAD@ 2 S" default up" CH8-CHECK
   1 CH8-PAD@ 8 S" default down" CH8-CHECK
   2 CH8-PAD@ 4 S" default left" CH8-CHECK
   3 CH8-PAD@ 6 S" default right" CH8-CHECK
   4 CH8-PAD@ 5 S" default b0" CH8-CHECK
   36 5 DO I CH8-PAD@ -1 S" raw default unmapped" CH8-CHECK LOOP
   TRUE CH8-PAD-DEFAULT
   8 CH8-PAD@ 17 S" mapped back" CH8-CHECK
   10 CH8-PAD@ 16 S" mapped start" CH8-CHECK
   36 0 DO
      18 -1 DO I J CH8-PAD! J CH8-PAD@ I S" setter targets" CH8-CHECK LOOP
   LOOP
   99 0 CH8-PAD! 0 CH8-PAD@ 17 S" invalid target ignored" CH8-CHECK
;
: CH8-TEST-PAD-PARSER ( -- )
   CH8-PAD-OVERLAY-CLEAR FALSE CH8-PAD-DEFAULT
   S" PONG up=E down=- a=a b=B x=c y=D l=e r=F back=quit start=reset b31=0" CH8-PAD-TEST-LINE
   S" pong up=F # down=0" CH8-PAD-TEST-LINE
   0 CH8-PAD@ 15 S" accumulated override" CH8-CHECK
   1 CH8-PAD@ -1 S" accumulated clear" CH8-CHECK
   4 CH8-PAD@ 10 S" alias a" CH8-CHECK
   5 CH8-PAD@ 11 S" alias b" CH8-CHECK
   6 CH8-PAD@ 12 S" alias x" CH8-CHECK
   7 CH8-PAD@ 13 S" alias y" CH8-CHECK
   13 CH8-PAD@ 14 S" alias l" CH8-CHECK
   14 CH8-PAD@ 15 S" alias r" CH8-CHECK
   8 CH8-PAD@ 17 S" alias back" CH8-CHECK
   10 CH8-PAD@ 16 S" alias start" CH8-CHECK
   35 CH8-PAD@ 0 S" b31" CH8-CHECK
   S" B32" CH8-PAD-INDEX -1 S" invalid button" CH8-CHECK
   S" B10" CH8-PAD-INDEX 14 S" numbered button" CH8-CHECK
;
: CH8-TEST-PAD-STATE ( -- )
   CH8-NEW CH8-PAD-OVERLAY-CLEAR CH8-PAD-BEGIN FALSE CH8-DONE !
   0 80 FALSE CH8-PAD-STATE
   CH8-DONE @ FALSE S" raw b4 no quit" CH8-CHECK
   99 CH8-I ! 0 80 FALSE CH8-PAD-STATE
   CH8-I @ 99 S" raw b6 no reset" CH8-CHECK
   CH8-PAD-BEGIN 0 80 TRUE CH8-PAD-STATE
   CH8-I @ 0 S" mapped reset edge" CH8-CHECK
   CH8-DONE @ TRUE S" mapped quit edge" CH8-CHECK
   99 CH8-I ! FALSE CH8-DONE ! 0 80 TRUE CH8-PAD-STATE
   CH8-I @ 99 S" held reset" CH8-CHECK
   CH8-DONE @ FALSE S" held quit" CH8-CHECK
   0 0 TRUE CH8-PAD-STATE 0 80 TRUE CH8-PAD-STATE
   CH8-I @ 0 S" reset re-press" CH8-CHECK
   CH8-DONE @ TRUE S" quit re-press" CH8-CHECK
   CH8-PAD-OVERLAY-CLEAR
   S" pong b4=quit b6=reset" CH8-PAD-TEST-LINE
   CH8-PAD-BEGIN FALSE CH8-DONE ! 99 CH8-I ! 1 81 FALSE CH8-PAD-STATE
   CH8-DONE @ TRUE S" raw explicit quit" CH8-CHECK
   CH8-I @ 0 S" raw explicit reset" CH8-CHECK
   CH8-PAD-KEYS 2 + C@ 1 S" reset preserves held direction" CH8-CHECK
   CH8-PAD-KEYS 5 + C@ 1 S" reset preserves held button" CH8-CHECK
   1 CH8-PC-KEYS 7 + C! CH8-MERGE-KEYS
   CH8-KEYS 7 + C@ 1 S" keyboard merge" CH8-CHECK
   CH8-KEYS 5 + C@ 1 S" pad merge" CH8-CHECK
   CH8-PAD-BEGIN
   -32768 0 FALSE CH8-PAD-AXIS-VALUE 0 S" initial raw x ignored" CH8-CHECK
   0 0 FALSE CH8-PAD-AXIS-VALUE 0 S" raw x armed" CH8-CHECK
   -32768 0 FALSE CH8-PAD-AXIS-VALUE -32768 S" later raw extreme" CH8-CHECK
   -32768 1 FALSE CH8-PAD-AXIS-VALUE 0 S" y armed independently" CH8-CHECK
   -32768 1 TRUE CH8-PAD-AXIS-VALUE -32768 S" mapped extreme" CH8-CHECK
   9 20000 20000 0 FALSE CH8-PAD-DIRS 15 S" hat and stick OR" CH8-CHECK
   0 -16384 16384 0 FALSE CH8-PAD-DIRS 0 S" strict threshold" CH8-CHECK
   0 -16385 -16385 0 FALSE CH8-PAD-DIRS 5 S" negative stick" CH8-CHECK
   0 0 0 30720 TRUE CH8-PAD-DIRS 15 S" mapped dpad" CH8-CHECK
   0 0 0 30720 FALSE CH8-PAD-DIRS 0 S" raw buttons not dpad" CH8-CHECK
   16 0 DO
      I 0 0 0 FALSE CH8-PAD-DIRS
      I 1 AND I 4 AND 1 RSHIFT OR I 8 AND 1 RSHIFT OR I 2 AND 2 LSHIFT OR
      S" all hat combinations" CH8-CHECK
   LOOP
   S" emu/chip8/test-chip8.fs" CH8-PAD-FILE-U ! CH8-PAD-FILE-A !
   999 CH8-PAD-LINE-N !
   S" pong bad up=GG b32=0 b0=none b1=RESET b2=QuIt right=6#comment" CH8-PAD-TEST-LINE
   5 CH8-PAD@ 16 S" case reset target" CH8-CHECK
   6 CH8-PAD@ 17 S" case quit target" CH8-CHECK
   3 CH8-PAD@ 6 S" inline comment" CH8-CHECK
   ." INFO pad format expected: mapped=0 directions=- buttons=-" CR
   0 0 FALSE CH8-PAD-PRINT
   ." INFO pad format expected: mapped=0 directions=up,left buttons=0,9" CR
   5 513 FALSE CH8-PAD-PRINT
   S" emu/roms/c8games/PONG" CH8-PAD-LOAD
   0 CH8-PAD@ 1 S" ROM load" CH8-CHECK
   1 CH8-PAD@ 4 S" ROM down" CH8-CHECK
;
( Configuration fixture: read this source as pads.txt without creating files.
__CH8_TEST_ROM__ up=1 b1=A
* up=E down=3 b4=quit
__OTHER_ROM__ up=0
__CH8_TEST_ROM__ left=F
* down=7 b6=reset
)
: CH8-TEST-PAD-ORDER ( -- )
   CH8-PAD-OVERLAY-CLEAR FALSE CH8-PAD-DEFAULT
   \ The file reader makes these same two passes, each in file order.
   2 0 DO
      I IF S" pong" ELSE S" *" THEN
      2>R
      S" pong up=1 b1=A" 2R@ CH8-PAD-LINE
      S" * up=E down=3 b4=quit" 2R@ CH8-PAD-LINE
      S" other up=0" 2R@ CH8-PAD-LINE
      S" pong left=F" 2R@ CH8-PAD-LINE
      S" * down=7 b6=reset" 2R@ CH8-PAD-LINE
      2R> 2DROP
   LOOP
   0 CH8-PAD@ 1 S" ROM beats later wildcard" CH8-CHECK
   1 CH8-PAD@ 7 S" wildcard file order" CH8-CHECK
   2 CH8-PAD@ 15 S" ROM lines accumulate" CH8-CHECK
   5 CH8-PAD@ 10 S" earlier ROM assignment retained" CH8-CHECK
   CH8-PAD-BEGIN 0 0 FALSE CH8-PAD-STATE
   1 CH8-PAD@ 7 S" overlay after raw selection" CH8-CHECK
   8 CH8-PAD@ 17 S" wildcard raw quit retained" CH8-CHECK
   10 CH8-PAD@ 16 S" wildcard raw reset retained" CH8-CHECK
   S" dir/__CH8_TEST_ROM__" S" emu/chip8/test-chip8.fs" CH8-PAD-LOAD-FILE
   0 CH8-PAD@ 1 S" file ROM beats later wildcard" CH8-CHECK
   1 CH8-PAD@ 7 S" file wildcard order" CH8-CHECK
   2 CH8-PAD@ 15 S" file ROM accumulation" CH8-CHECK
   5 CH8-PAD@ 10 S" file retains earlier ROM field" CH8-CHECK
   CH8-PAD-BEGIN 0 0 TRUE CH8-PAD-STATE
   1 CH8-PAD@ 7 S" mapped overlay" CH8-CHECK
   S" missing" S" emu/chip8/no-such-pads.txt" CH8-PAD-LOAD-FILE
   0 CH8-PAD@ 2 S" missing defaults" CH8-CHECK
   S" dir\sub\PONG" CH8-PAD-LOAD
   0 CH8-PAD@ 1 S" backslash ROM basename" CH8-CHECK
;
: CH8-TEST-PAD-ALL ( -- )
   CH8-PAD-OVERLAY-CLEAR CH8-PAD-BEGIN 0 0 FALSE CH8-PAD-STATE
   36 0 DO
      36 0 DO -1 I CH8-PAD! LOOP
      I 15 AND I CH8-PAD!
      I 4 < IF 1 I LSHIFT 0 ELSE 0 1 I 4 - LSHIFT THEN
      FALSE CH8-PAD-STATE
      16 0 DO
         CH8-PAD-KEYS I + C@ I J 15 AND = IF 1 ELSE 0 THEN
         S" each physical input maps independently" CH8-CHECK
      LOOP
   LOOP
   -1 -1 CH8-PAD! 0 36 CH8-PAD! 0 -1 CH8-PAD!
   35 CH8-PAD@ 3 S" invalid input ignored" CH8-CHECK
   CH8-PAD-OVERLAY-CLEAR CH8-PAD-BEGIN 0 1 FALSE CH8-PAD-STATE
   CH8-PC-KEYS 16 0 FILL CH8-MERGE-KEYS
   5 1 CH8-V!
   $E19E CH8-OP CH8-PC @ $204 S" pad Ex9E" CH8-CHECK
   $E1A1 CH8-OP CH8-PC @ $202 S" pad ExA1 held" CH8-CHECK
   $F10A CH8-OP CH8-WAIT @ 5 S" pad Fx0A press" CH8-CHECK
   $F10A CH8-OP CH8-PC @ $200 S" pad Fx0A held" CH8-CHECK
   0 0 FALSE CH8-PAD-STATE CH8-MERGE-KEYS
   CH8-STEP 1 CH8-V@ 5 S" pad Fx0A release" CH8-CHECK
   $E1A1 CH8-OP CH8-PC @ $204 S" pad ExA1 released" CH8-CHECK
;
CH8-TEST-PADS CH8-TEST-PAD-PARSER CH8-TEST-PAD-STATE
CH8-TEST-PAD-ORDER CH8-TEST-PAD-ALL


: CH8-TEST-FRAME ( -- )
   CH8-BLEND-FRAME
   CH8-SHOWN CH8-LAST-SHOWN CH8-PIXELS MOVE
;
: CH8-TEST-BLEND ( -- )
   CH8-BLEND @ 3 S" default blend" CH8-CHECK
   5 1 DO
      CH8-NEW I CH8-BLEND !
      CH8-LAST-SHOWN CH8-PIXELS 0 FILL
      CH8-TEST-FRAME
      CH8-DIRTY @ FALSE S" unchanged blank" CH8-CHECK
      1 CH8-SCREEN C! CH8-TEST-FRAME
      CH8-DIRTY @ TRUE S" new pixel redraw" CH8-CHECK
      0 CH8-SCREEN C!
      I 1 ?DO
         CH8-TEST-FRAME
         CH8-SHOWN C@ 1 S" retained pixel" CH8-CHECK
         CH8-DIRTY @ FALSE S" retained image no redraw" CH8-CHECK
      LOOP
      CH8-TEST-FRAME
      CH8-SHOWN C@ 0 S" expired pixel" CH8-CHECK
      CH8-DIRTY @ TRUE S" expiration redraw" CH8-CHECK
      CH8-TEST-FRAME
      CH8-DIRTY @ FALSE S" stable image no redraw" CH8-CHECK
   LOOP
   3 CH8-BLEND ! CH8-NEW
   1 CH8-SCREEN C! CH8-TEST-FRAME
   $00E0 CH8-OP CH8-TEST-FRAME
   CH8-SHOWN C@ 0 S" clear immediate" CH8-CHECK
   CH8-DIRTY @ TRUE S" clear redraw" CH8-CHECK
   1 CH8-SCREEN C! CH8-TEST-FRAME
   CH8-RESET CH8-TEST-FRAME
   CH8-SHOWN C@ 0 S" reset immediate" CH8-CHECK
   CH8-DIRTY @ TRUE S" reset redraw" CH8-CHECK
   -10 CH8-BLEND ! 1 CH8-SCREEN C! CH8-TEST-FRAME
   0 CH8-SCREEN C! CH8-TEST-FRAME
   CH8-SHOWN C@ 0 S" clamp lower" CH8-CHECK
   99 CH8-BLEND ! 1 CH8-SCREEN C! CH8-TEST-FRAME
   0 CH8-SCREEN C!
   3 0 DO CH8-TEST-FRAME CH8-SHOWN C@ 1 S" clamp upper retention" CH8-CHECK LOOP
   CH8-TEST-FRAME CH8-SHOWN C@ 0 S" clamp upper expiration" CH8-CHECK
   3 CH8-BLEND !
;
CH8-TEST-BLEND

CH8-TEST-VIP

CH8-TEST-EXTRA
CH8-TEST-CPU CH8-TEST-FLAGS CH8-TEST-F CH8-TEST-DRAW CH8-TEST-ERRORS
   ' CH8-MAZE S" emu/roms/c8games/MAZE" CH8-SMOKE
   ' CH8-PONG S" emu/roms/c8games/PONG" CH8-SMOKE
   DEPTH 0 S" final stack depth" CH8-CHECK
.( passed ) CH8-PASSED @ . .( failed ) CH8-FAILED @ . CR
CH8-FAILED @ [IF] -4105 THROW [THEN]
BYE
