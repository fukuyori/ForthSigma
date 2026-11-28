\ Extra direct comparison of every specialised arithmetic opcode over all
\ source byte pairs and carry states, including destination result and cost.
INCLUDE emu/arduboy/bench/avr-opt.fs
: O-DIRECT { op | d r a b flags value cost -- }
 op AB-D TO d op AB-R TO r
 256 0 DO I TO a 256 0 DO I TO b 2 0 DO
 a d AB-R! b r AB-R! 192 I OR AB-SREG !
 op O-BASE op CELLS + @ EXECUTE TO cost
 d AB-R@ TO value AB-SREG @ TO flags
 a d AB-R! b r AB-R! 192 I OR AB-SREG !
 op O-SPEC op CELLS + @ EXECUTE cost <> IF -4310 THROW THEN
 d AB-R@ value <> AB-SREG @ flags <> OR IF -4311 THROW THEN
 LOOP LOOP LOOP ;
: O-DIRECT-ALL
 3841 O-DIRECT 7937 O-DIRECT 5920 O-DIRECT
 8993 O-DIRECT 11041 O-DIRECT 10017 O-DIRECT
 ." specialised ALU: 786432 direct result/flags/cost comparisons PASS" CR ;
: O-IMM-DIRECT { op | d flags value cost -- }
 op AB-ID TO d
 256 0 DO 256 0 DO
 J d AB-R! I AB-SREG ! op O-BASE op CELLS + @ EXECUTE TO cost
 d AB-R@ TO value AB-SREG @ TO flags
 J d AB-R! I AB-SREG ! op O-SPEC op CELLS + @ EXECUTE cost <>
 d AB-R@ value <> OR AB-SREG @ flags <> OR IF -4312 THROW THEN
 LOOP LOOP ;
: O-EXTRA
 O-DIRECT-ALL 20513 O-IMM-DIRECT 12335 O-IMM-DIRECT 14960 O-IMM-DIRECT
 ." specialised immediate: 196608 direct comparisons PASS" CR
 O-VERIFY
 \ RETI defers pending IRQ through precisely one resumed instruction.
 1 O-WORK ! 5 O-SELECT O-RESET 1 O-FLAG !
 1 O-DELAY ! O-IRQ O-IRQS @ IF -4313 THROW THEN
 O-IRQ O-IRQS @ 1 <> IF -4315 THROW THEN
 \ Multiple masked overflows coalesce; entry adds four peripheral cycles.
 O-RESET 0 AB-SREG ! 49155 AB-CYC ! O-SYNC O-IRQ
 O-OVER @ 3 <> O-FLAG @ 1 <> OR IF -4316 THROW THEN
 128 AB-SREG ! O-IRQ O-IRQS @ 1 <> O-FLAG @ 0<> OR
 AB-CYC @ 49159 <> OR IF -4317 THROW THEN
 DEPTH IF -4318 THROW THEN
 ." IRQ delay, coalescing, entry cycles PASS" CR ;

: O-IRQ-EXPECTED
 6 0 DO
 1 O-WORK ! I O-SELECT O-RESET
 12 AB-PC ! 229 AB-SREG ! 125 0 AB-R! 51 24 AB-R!
 1 O-FLAG ! O-IRQ
 AB-SP @ 2813 <> AB-PC @ 46 <> OR
 2815 AB-R@ 12 <> OR 2814 AB-R@ 0<> OR
 AB-SREG @ 101 <> OR AB-CYC @ 4 <> OR IF -4320 THROW THEN
 12 0 DO O-ONE LOOP
 AB-PC @ 12 <> AB-SP @ 2815 <> OR
 AB-SREG @ 229 <> OR 0 AB-R@ 125 <> OR
 24 AB-R@ 51 <> OR 769 AB-R@ 52 <> OR
 AB-CYC @ 27 <> OR O-N @ 12 <> OR IF -4321 THROW THEN
 LOOP
 ." six variants: IRQ byte order, saved SREG/registers, RETI PC/SP, 27 cycles PASS" CR ;
: O-UNARY-RESULTS { | a old op want -- }
 256 0 DO I TO a 256 0 DO I TO old
 4 0 DO
 I 0= IF 37891 a 1+ ELSE
 I 1 = IF 37898 a 1- ELSE
 I 2 = IF 37894 a 1 RSHIFT ELSE
 37895 a 1 RSHIFT old 1 AND 7 LSHIFT OR THEN THEN THEN
 255 AND TO want TO op
 a 0 AB-R! old AB-SREG ! op O-BASE op CELLS + @ EXECUTE
 1 <> 0 AB-R@ want <> OR IF -4322 THROW THEN
 a 0 AB-R! old AB-SREG ! op O-LOCAL op CELLS + @ EXECUTE
 1 <> 0 AB-R@ want <> OR IF -4323 THROW THEN
 LOOP LOOP LOOP
 ." unary result bytes: 262144 cases, baseline and locals-free PASS" CR ;
O-EXTRA O-IRQ-EXPECTED O-UNARY-RESULTS BYE
