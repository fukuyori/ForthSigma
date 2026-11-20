\ Original Forth NTSC NES APU register-model prototype. No audio on load.
\ Source facts: docs/NES_APU_FORTH.md. DMC: docs/NES_DMC_FORTH.md. PAL/bus races/filtering excluded.
DECIMAL
1789773 CONSTANT NA-CPU
48000 CONSTANT NA-RATE
CREATE NA-STATE 44 CELLS ALLOT
\ Per channel: control,period,timer,sequence,length,env-start,env-div,decay,
\              sweep-register,sweep-divider,sweep-reload.
: NA@ ( channel field -- value ) SWAP 11 * + CELLS NA-STATE + @ ;
: NA! ( value channel field -- ) SWAP 11 * + CELLS NA-STATE + ! ;
CREATE NA-LENGTHS
10 , 254 , 20 , 2 , 40 , 4 , 80 , 6 , 160 , 8 , 60 , 10 , 14 , 12 , 26 , 14 ,
12 , 16 , 24 , 18 , 48 , 20 , 96 , 22 , 192 , 24 , 72 , 26 , 16 , 28 , 32 , 30 ,
CREATE NA-NOISE-PERIODS
4 , 8 , 16 , 32 , 64 , 96 , 128 , 160 , 202 , 254 , 380 , 508 , 762 , 1016 , 2034 , 4068 ,
CREATE NA-DUTIES 2 , 6 , 30 , 249 ,
VARIABLE NA-CYCLE VARIABLE NA-FRAME VARIABLE NA-MODE VARIABLE NA-INHIBIT
VARIABLE NA-IRQ VARIABLE NA-ENABLE VARIABLE NA-LINEAR VARIABLE NA-RELOAD
VARIABLE NA-LFSR VARIABLE NA-NOISE-MODE VARIABLE NA-RESET-AT VARIABLE NA-PENDING-MODE
VARIABLE NA-FRACTION VARIABLE NA-SLOW
CREATE NA-EVENTS 3072 CELLS ALLOT
VARIABLE NA-EVENT-COUNT VARIABLE NA-EVENT-INDEX
CREATE NA-DMC 15 CELLS ALLOT
CREATE NA-DMC-MEMORY 32768 ALLOT
CREATE NA-DMC-RATES
428 , 380 , 340 , 320 , 286 , 254 , 226 , 214 , 190 , 160 , 142 , 128 , 106 , 84 , 72 , 54 ,
\ DMC: ctrl,dac,start-reg,length-reg,period,timer,address,remaining,
\      buffer,full,shift,bits,silent,irq,fetch-count.
: ND@ ( field -- value ) CELLS NA-DMC + @ ;
: ND! ( value field -- ) CELLS NA-DMC + ! ;
: NA-MEM! { value address -- }
  value 0 256 WITHIN 0= IF -24 THROW THEN
  address 32768 65536 WITHIN 0= IF -24 THROW THEN
  value address 32768 - NA-DMC-MEMORY + C! ;
: NA-DMC-RESTART ( -- ) 2 ND@ 64 * 49152 + 6 ND! 3 ND@ 16 * 1+ 7 ND! ;
: NA-DMC-FETCH ( -- )
  9 ND@ 0= 7 ND@ 0> AND IF
    6 ND@ 32768 - NA-DMC-MEMORY + C@ 8 ND! 1 9 ND!
    6 ND@ 1+ DUP 65536 = IF DROP 32768 THEN 6 ND!
    7 ND@ 1- DUP 7 ND! 0= IF
      0 ND@ 64 AND IF NA-DMC-RESTART
      ELSE 0 ND@ 128 AND IF 1 13 ND! THEN THEN
    THEN
    14 ND@ 1+ 14 ND!
  THEN ;
: NA-DMC-OUTPUT ( -- )
  12 ND@ 0= IF
    10 ND@ 1 AND IF 1 ND@ 125 <= IF 1 ND@ 2 + 1 ND! THEN
    ELSE 1 ND@ 2 >= IF 1 ND@ 2 - 1 ND! THEN THEN
  THEN
  10 ND@ 1 RSHIFT 10 ND!
  11 ND@ 1- DUP 11 ND! 0= IF
    8 11 ND!
    9 ND@ IF 0 12 ND! 8 ND@ 10 ND! 0 9 ND!
    ELSE 1 12 ND! THEN
  THEN ;
\ Fast caller splits at each output clock, so at most one clock is due.
: NA-DMC-CLOCK { clocks -- }
  clocks 0= IF EXIT THEN
  clocks 5 ND@ <= IF 5 ND@ clocks - 5 ND!
  ELSE 4 ND@ 5 ND! NA-DMC-OUTPUT THEN ;
: NA-DMC-NEXT ( -- cpu-clocks ) 5 ND@ 1+ 2 * NA-CYCLE @ 1 AND - ;
: NA-RESET ( -- )
  NA-STATE 44 CELLS 0 FILL
  NA-DMC 15 CELLS 0 FILL 213 4 ND! 8 11 ND! 1 12 ND!
  0 NA-CYCLE ! 0 NA-FRAME ! 0 NA-MODE ! 0 NA-INHIBIT !
  0 NA-IRQ ! 0 NA-ENABLE ! 0 NA-LINEAR ! 0 NA-RELOAD !
  1 NA-LFSR ! 0 NA-NOISE-MODE ! 0 NA-RESET-AT ! 0 NA-PENDING-MODE !
  0 NA-FRACTION ! 0 NA-SLOW ! 1 3 1 NA!
  0 NA-EVENT-COUNT ! 0 NA-EVENT-INDEX ! ;
: NA-ENV { ch | ctl -- }
  ch 0 NA@ TO ctl
  ch 5 NA@ IF
    0 ch 5 NA! 15 ch 7 NA! ctl 15 AND ch 6 NA!
  ELSE
    ch 6 NA@ IF ch 6 NA@ 1- ch 6 NA!
    ELSE
      ctl 15 AND ch 6 NA!
      ch 7 NA@ IF ch 7 NA@ 1- ch 7 NA!
      ELSE ctl 32 AND IF 15 ch 7 NA! THEN THEN
    THEN
  THEN ;
: NA-QUARTER ( -- )
  0 NA-ENV 1 NA-ENV 3 NA-ENV
  NA-RELOAD @ IF 2 0 NA@ 127 AND NA-LINEAR !
  ELSE NA-LINEAR @ IF -1 NA-LINEAR +! THEN THEN
  2 0 NA@ 128 AND 0= IF 0 NA-RELOAD ! THEN ;
: NA-TARGET { ch | period sweep delta -- target }
  ch 1 NA@ TO period ch 8 NA@ TO sweep
  period sweep 7 AND RSHIFT TO delta
  sweep 8 AND IF period delta - ch 0= IF 1- THEN 0 MAX
  ELSE period delta + THEN ;
: NA-MUTED? ( ch -- flag ) DUP 1 NA@ 8 < SWAP NA-TARGET 2047 > OR ;
: NA-HALF { | halt ch sweep -- }
  4 0 DO
    I TO ch ch 2 = IF 128 ELSE 32 THEN TO halt
    ch 0 NA@ halt AND 0= ch 4 NA@ 0> AND IF ch 4 NA@ 1- ch 4 NA! THEN
  LOOP
  2 0 DO
    I TO ch ch 8 NA@ TO sweep
    ch 9 NA@ 0= sweep 128 AND 0<> AND sweep 7 AND 0<> AND
    ch NA-MUTED? 0= AND IF ch NA-TARGET ch 1 NA! THEN
    ch 9 NA@ 0= ch 10 NA@ OR IF
      sweep 4 RSHIFT 7 AND ch 9 NA! 0 ch 10 NA!
    ELSE ch 9 NA@ 1- ch 9 NA! THEN
  LOOP ;
: NA-NEXT-FRAME ( -- frame )
  NA-FRAME @ DUP 7457 < IF DROP 7457 EXIT THEN
  DUP 14913 < IF DROP 14913 EXIT THEN
  DUP 22371 < IF DROP 22371 EXIT THEN
  NA-MODE @ IF 37281 < IF 37281 ELSE 37282 THEN
  ELSE DUP 29828 < IF DROP 29828 EXIT THEN
    29829 < IF 29829 ELSE 29830 THEN THEN ;
: NA-FRAME-EVENT ( -- )
  NA-FRAME @ DUP 7457 = OVER 22371 = OR IF DROP NA-QUARTER EXIT THEN
  DUP 14913 = IF DROP NA-QUARTER NA-HALF EXIT THEN
  NA-MODE @ IF
    DUP 37281 = IF NA-QUARTER NA-HALF THEN
    37282 = IF 0 NA-FRAME ! THEN
  ELSE
    DUP 29828 >= IF NA-INHIBIT @ 0= IF 1 NA-IRQ ! THEN THEN
    DUP 29829 = IF NA-QUARTER NA-HALF THEN
    29830 = IF 0 NA-FRAME ! THEN
  THEN ;
: NA-FRAME-END ( -- )
  NA-RESET-AT @ DUP 0<> SWAP NA-CYCLE @ = AND IF
    0 NA-RESET-AT ! 0 NA-FRAME ! NA-PENDING-MODE @ NA-MODE !
    NA-MODE @ IF NA-QUARTER NA-HALF THEN
  ELSE NA-FRAME-EVENT THEN ;
: NA-NOISE-SHIFT ( -- )
  NA-LFSR @ DUP NA-NOISE-MODE @ IF 6 ELSE 1 THEN RSHIFT XOR 1 AND
  14 LSHIFT NA-LFSR @ 1 RSHIFT OR NA-LFSR ! ;
\ Batch a divider's input clocks; same zero->reload semantics as reference tick.
: NA-CLOCK { clocks ch | timer period events rest -- }
  clocks 0= IF EXIT THEN
  ch 2 NA@ TO timer ch 1 NA@ TO period
  clocks timer <= IF timer clocks - ch 2 NA! EXIT THEN
  clocks timer - 1- TO rest
  rest period 1+ / 1+ TO events
  period rest period 1+ MOD - ch 2 NA!
  ch 2 < IF ch 3 NA@ events + 7 AND ch 3 NA! EXIT THEN
  ch 2 = IF
    ch 4 NA@ 0<> NA-LINEAR @ 0<> AND IF ch 3 NA@ events + 31 AND ch 3 NA! THEN EXIT
  THEN
  events 0 ?DO NA-NOISE-SHIFT LOOP ;
: NA-TICK ( -- )
  1 NA-CYCLE +! NA-DMC-FETCH
  NA-CYCLE @ 1 AND 0= IF 1 0 NA-CLOCK 1 1 NA-CLOCK 1 3 NA-CLOCK 1 NA-DMC-CLOCK THEN
  1 2 NA-CLOCK
  1 NA-FRAME +! NA-FRAME-END ;
: NA-FAST { clocks | n pulses -- }
  BEGIN clocks 0> WHILE
    NA-NEXT-FRAME NA-FRAME @ - clocks MIN TO n
    NA-RESET-AT @ IF NA-RESET-AT @ NA-CYCLE @ - n MIN TO n THEN
    NA-DMC-NEXT n MIN TO n
    9 ND@ 0= 7 ND@ 0> AND IF 1 n MIN TO n THEN
    NA-CYCLE @ n + 2 / NA-CYCLE @ 2 / - TO pulses
    pulses 0 NA-CLOCK pulses 1 NA-CLOCK n 2 NA-CLOCK pulses 3 NA-CLOCK
    n NA-CYCLE +! NA-DMC-FETCH pulses NA-DMC-CLOCK
    n NA-FRAME +! n NEGATE +TO clocks NA-FRAME-END
  REPEAT ;
: NA-RAW-RUN ( clocks -- )
  DUP 0< IF -24 THROW THEN
  DUP 9223372036854775807 NA-CYCLE @ - > IF -24 THROW THEN
  NA-SLOW @ IF 0 ?DO NA-TICK LOOP ELSE NA-FAST THEN ;
: NA-RAW-TO ( cycle -- ) DUP NA-CYCLE @ < IF -24 THROW THEN NA-CYCLE @ - NA-RAW-RUN ;
: NA-LOAD-LENGTH { value ch -- }
  NA-ENABLE @ 1 ch LSHIFT AND IF value 3 RSHIFT CELLS NA-LENGTHS + @ ch 4 NA! THEN ;
: NA-PERIOD-LOW { value ch -- } ch 1 NA@ 1792 AND value OR ch 1 NA! ;
: NA-PERIOD-HIGH { value ch -- } ch 1 NA@ 255 AND value 7 AND 8 LSHIFT OR ch 1 NA! ;
: NA-CHECK-WRITE { value address cycle -- }
  value 0 256 WITHIN 0= IF -24 THROW THEN
  address 16384 16408 WITHIN 0= IF -24 THROW THEN
  cycle NA-CYCLE @ < IF -24 THROW THEN
  address 16404 = address 16406 = OR IF -24 THROW THEN
  address 16407 = cycle 9223372036854775803 > AND IF -24 THROW THEN
  ;
: NA-STORE { value address | ch reg -- }
  address 16405 = IF
    value 31 AND NA-ENABLE !
    0 13 ND!
    value 16 AND IF 7 ND@ 0= IF NA-DMC-RESTART THEN ELSE 0 7 ND! THEN
    4 0 DO value 1 I LSHIFT AND 0= IF 0 I 4 NA! THEN LOOP EXIT THEN
  address 16400 16404 WITHIN IF
    address 16400 - CASE
      0 OF value 0 ND! value 15 AND CELLS NA-DMC-RATES + @ 2 / 1- 4 ND!
        value 128 AND 0= IF 0 13 ND! THEN ENDOF
      1 OF value 127 AND 1 ND! ENDOF
      2 OF value 2 ND! ENDOF
      3 OF value 3 ND! ENDOF
    ENDCASE EXIT THEN
  address 16407 = IF
    value 64 AND NA-INHIBIT ! NA-INHIBIT @ IF 0 NA-IRQ ! THEN
    value 128 AND NA-PENDING-MODE !
    NA-CYCLE @ DUP 1 AND IF 4 ELSE 3 THEN + NA-RESET-AT ! EXIT THEN
  address 16384 - 4 / TO ch address 3 AND TO reg
  ch 2 < IF
    reg CASE
      0 OF value ch 0 NA! ENDOF
      1 OF value ch 8 NA! 1 ch 10 NA! ENDOF
      2 OF value ch NA-PERIOD-LOW ENDOF
      3 OF value ch NA-PERIOD-HIGH value ch NA-LOAD-LENGTH
        0 ch 3 NA! 1 ch 5 NA! ENDOF
    ENDCASE EXIT THEN
  ch 2 = IF
    reg CASE
      0 OF value ch 0 NA! ENDOF
      2 OF value ch NA-PERIOD-LOW ENDOF
      3 OF value ch NA-PERIOD-HIGH value ch NA-LOAD-LENGTH 1 NA-RELOAD ! ENDOF
    ENDCASE EXIT THEN
  reg CASE
    0 OF value 3 0 NA! ENDOF
    2 OF value 128 AND NA-NOISE-MODE !
      value 15 AND CELLS NA-NOISE-PERIODS + @ 2 / 1- 3 1 NA! ENDOF
    3 OF value 3 NA-LOAD-LENGTH 1 3 5 NA! ENDOF
  ENDCASE ;
\ Reclaim consumed entries only after all admission checks have succeeded.
: NA-COMPACT ( -- )
  NA-EVENT-INDEX @ 3 * CELLS NA-EVENTS + NA-EVENTS
  NA-EVENT-COUNT @ NA-EVENT-INDEX @ - 3 * CELLS MOVE
  NA-EVENT-INDEX @ NEGATE NA-EVENT-COUNT +! 0 NA-EVENT-INDEX ! ;
: NA-EVENT! { value address cycle | entry -- }
  value address cycle NA-CHECK-WRITE
  NA-EVENT-COUNT @ NA-EVENT-INDEX @ - 1024 >= IF -528 THROW THEN
  NA-EVENT-COUNT @ IF
    NA-EVENT-COUNT @ 1- 3 * 2 + CELLS NA-EVENTS + @ cycle > IF -24 THROW THEN
  THEN
  NA-EVENT-COUNT @ 1024 >= IF NA-COMPACT THEN
  NA-EVENT-COUNT @ 3 * CELLS NA-EVENTS + TO entry
  value entry ! address entry CELL+ ! cycle entry 2 CELLS + !
  1 NA-EVENT-COUNT +! ;
: NA-TO { cycle | entry at -- }
  cycle NA-CYCLE @ < IF -24 THROW THEN
  BEGIN NA-EVENT-INDEX @ NA-EVENT-COUNT @ < WHILE
    NA-EVENT-INDEX @ 3 * CELLS NA-EVENTS + TO entry
    entry 2 CELLS + @ TO at
    at cycle > IF cycle NA-RAW-TO EXIT THEN
    at NA-RAW-TO entry @ entry CELL+ @ NA-STORE 1 NA-EVENT-INDEX +!
  REPEAT cycle NA-RAW-TO ;
: NA-RUN ( clocks -- )
  DUP 0< IF -24 THROW THEN
  DUP 9223372036854775807 NA-CYCLE @ - > IF -24 THROW THEN
  NA-CYCLE @ + NA-TO ;
: NA-WRITE { value address cycle -- }
  value address cycle NA-CHECK-WRITE cycle NA-TO value address NA-STORE ;
: NA-IRQ? ( -- flag ) NA-IRQ @ 13 ND@ OR 0<> ;
: NA-STATUS ( cycle -- status )
  NA-TO 0 4 0 DO I 4 NA@ IF 1 I LSHIFT OR THEN LOOP
  7 ND@ IF 16 OR THEN 13 ND@ IF 128 OR THEN
  NA-IRQ @ IF 64 OR THEN 0 NA-IRQ ! ;
: NA-VOLUME ( ch -- volume ) DUP 0 NA@ DUP 16 AND IF 15 AND NIP ELSE DROP 7 NA@ THEN ;
: NA-PULSE { ch -- level }
  ch 4 NA@ 0= ch NA-MUTED? OR IF 0 EXIT THEN
  ch 0 NA@ 6 RSHIFT CELLS NA-DUTIES + @ ch 3 NA@ RSHIFT 1 AND
  IF ch NA-VOLUME ELSE 0 THEN ;
: NA-TRIANGLE ( -- level ) 2 3 NA@ DUP 16 < IF 15 SWAP - ELSE 16 - THEN ;
: NA-NOISE ( -- level ) 3 4 NA@ 0= NA-LFSR @ 1 AND OR IF 0 ELSE 3 NA-VOLUME THEN ;
\ Exact rational evaluation of the documented approximate DAC equations, including DMC.
\ Output = floor(pulse*32767) + floor(tnd*32767), using wide rational LUTs.
\ Unipolar; no analog filters or DC removal.
CREATE NA-PULSE-MIX 31 CELLS ALLOT
CREATE NA-TND-MIX 32768 CELLS ALLOT
: NA-INIT-MIX ( -- )
  31 0 DO I 9588 * 32767 * 8128 I 100 * + 100 * / I CELLS NA-PULSE-MIX + ! LOOP
  32768 0 DO
    I 2048 / 12241 * 22638 * I 128 / 15 AND 8227 * 22638 * +
    I 127 AND 8227 * 12241 * +
    DUP 15979 * 32767 UM* ROT 100 * 8227 12241 * 22638 * + 100 * UM/MOD NIP
    I CELLS NA-TND-MIX + !
  LOOP ;
: NA-SAMPLE ( -- s16 )
  0 NA-PULSE 1 NA-PULSE + CELLS NA-PULSE-MIX + @
  NA-TRIANGLE 16 * NA-NOISE + 128 * 1 ND@ + CELLS NA-TND-MIX + @ + 32767 MIN ;

: NA-LE! ( n addr -- ) OVER 255 AND OVER C! SWAP 8 RSHIFT 255 AND SWAP 1+ C! ;
: NA-RENDER ( addr frames -- )
  DUP 0< IF -24 THROW THEN
  0 ?DO
    NA-FRACTION @ NA-CPU + NA-RATE /MOD NA-RUN NA-FRACTION !
    NA-SAMPLE OVER NA-LE! 2 +
  LOOP DROP ;
NA-DMC-MEMORY 32768 0 FILL
NA-INIT-MIX NA-RESET
