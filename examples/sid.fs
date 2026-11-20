\ Original PAL SID register model. Not 6581/8580 analog or ROM compatibility.
\ Load from repository root; loading alone never opens audio.
S" examples/sid-filter-coeffs.fs" INCLUDED
DECIMAL
985248 CONSTANT SI-CPU
48000 CONSTANT SI-RATE
16777215 CONSTANT SI-MASK
CREATE SI-REGS 25 CELLS ALLOT
CREATE SI-STATE 30 CELLS ALLOT
\ Per voice: phase,lfsr,envelope,stage(0attack/1decay/2release),rate-counter,
\            exp-counter,hold-zero,frequency,width,exp-period.
: SI@ ( voice field -- n ) SWAP 10 * + CELLS SI-STATE + @ ;
: SI! ( value voice field -- ) SWAP 10 * + CELLS SI-STATE + ! ;
: SI-R@ ( offset -- n ) CELLS SI-REGS + @ ;
: SI-CONTROL ( voice -- n ) 7 * 4 + SI-R@ ;
CREATE SI-RATES 9 , 32 , 63 , 95 , 149 , 220 , 267 , 313 , 392 , 977 , 1954 , 3126 , 3907 , 11720 , 19532 , 31251 ,
CREATE SI-NOISE-TAPS 22 , 20 , 16 , 13 , 11 , 7 , 4 , 2 ,
CREATE SI-RISE 3 CELLS ALLOT
VARIABLE SI-CYCLE VARIABLE SI-FRACTION VARIABLE SI-SLOW
VARIABLE SI-LOW VARIABLE SI-BAND
VARIABLE SI-CLIPS VARIABLE SI-FILTER-LIMITS
CREATE SI-EVENTS 3072 CELLS ALLOT
VARIABLE SI-EVENT-COUNT VARIABLE SI-EVENT-INDEX
: SI-RESET ( -- )
  SI-REGS 25 CELLS 0 FILL SI-STATE 30 CELLS 0 FILL
  3 0 DO 8388600 I 1 SI! 2 I 3 SI! 1 I 6 SI! 1 I 9 SI! LOOP
  SI-RISE 3 CELLS 0 FILL
  0 SI-CYCLE ! 0 SI-FRACTION ! 0 SI-SLOW ! 0 SI-LOW ! 0 SI-BAND !
  0 SI-EVENT-COUNT ! 0 SI-EVENT-INDEX ! 0 SI-CLIPS ! 0 SI-FILTER-LIMITS ! ;
: SI-ENV-RATE ( voice -- clocks )
  DUP 3 SI@ CASE
    0 OF 7 * 5 + SI-R@ 4 RSHIFT ENDOF
    1 OF 7 * 5 + SI-R@ 15 AND ENDOF
    2 OF 7 * 6 + SI-R@ 15 AND ENDOF
  ENDCASE CELLS SI-RATES + @ ;
: SI-EXP-UPDATE { voice | level -- }
  voice 2 SI@ TO level
  level CASE
    255 OF 1 voice 9 SI! ENDOF 93 OF 2 voice 9 SI! ENDOF
    54 OF 4 voice 9 SI! ENDOF 26 OF 8 voice 9 SI! ENDOF
    14 OF 16 voice 9 SI! ENDOF 6 OF 30 voice 9 SI! ENDOF
    0 OF 1 voice 9 SI! ENDOF
  ENDCASE ;
: SI-ENV { voice | level stage sustain exp -- }
  voice 2 SI@ TO level voice 3 SI@ TO stage
  stage 0= IF
    0 voice 5 SI! level 255 < IF level 1+ TO level THEN
    level voice 2 SI! voice SI-EXP-UPDATE level 255 = IF 1 voice 3 SI! THEN EXIT
  THEN
  voice 5 SI@ 1+ TO exp
  exp voice 9 SI@ >= IF
    0 voice 5 SI!
    voice 6 SI@ 0= IF
      voice 7 * 6 + SI-R@ 4 RSHIFT 17 * TO sustain
      stage 2 = level sustain > OR IF
        level 0> IF level 1- DUP voice 2 SI! 0= IF 1 voice 6 SI! THEN voice SI-EXP-UPDATE THEN
      THEN
    THEN
  ELSE exp voice 5 SI! THEN ;
: SI-NOISE-SHIFT ( voice -- )
  DUP 1 SI@ DUP 22 RSHIFT OVER 17 RSHIFT XOR 1 AND
  SWAP 1 LSHIFT OR 8388607 AND SWAP 1 SI! ;
: SI-PHASES { clocks | voice old raw fresh -- }
  3 0 DO
    I TO voice voice 0 SI@ TO old
    voice SI-CONTROL 8 AND IF 0 TO raw
    ELSE old clocks voice 7 SI@ * + TO raw THEN
    raw SI-MASK AND TO fresh
    fresh voice 0 SI!
    old 8388608 + 24 RSHIFT raw 8388608 + 24 RSHIFT < SI-RISE I CELLS + !
    old 524288 + 20 RSHIFT raw 524288 + 20 RSHIFT < IF voice SI-NOISE-SHIFT THEN
  LOOP
  3 0 DO
    I SI-CONTROL 2 AND SI-RISE I 2 + 3 MOD CELLS + @ AND IF 0 I 0 SI! THEN
  LOOP ;
: SI-COUNTERS { clocks | voice count -- }
  3 0 DO
    I TO voice voice 4 SI@ clocks + 32767 AND TO count
    count voice 4 SI! count voice SI-ENV-RATE = IF 0 voice 4 SI! voice SI-ENV THEN
  LOOP ;
: SI-TICK ( -- ) 1 SI-PHASES 1 SI-COUNTERS 1 SI-CYCLE +! ;
: SI-EDGE { phase frequency half | pos distance -- clocks }
  phase half 2 * MOD TO pos
  pos half < IF half pos - ELSE half 3 * pos - THEN TO distance
  distance frequency 1- + frequency / ;
: SI-STEP-LIMIT { clocks | voice count distance frequency phase -- n }
  3 0 DO
    I TO voice voice 4 SI@ TO count
    voice SI-ENV-RATE count - 32767 AND DUP 0= IF DROP 32768 THEN
    clocks MIN TO clocks
    voice 7 SI@ TO frequency voice 0 SI@ TO phase
    frequency voice SI-CONTROL 8 AND 0= AND IF
      phase frequency 524288 SI-EDGE clocks MIN TO clocks
      phase frequency 8388608 SI-EDGE clocks MIN TO clocks
    THEN
  LOOP clocks ;
: SI-FAST { clocks | n -- }
  BEGIN clocks 0> WHILE
    clocks SI-STEP-LIMIT TO n n SI-PHASES n SI-COUNTERS n SI-CYCLE +!
    n NEGATE +TO clocks
  REPEAT ;
: SI-RAW-RUN ( clocks -- )
  DUP 0< IF -24 THROW THEN
  DUP 9223372036854775807 SI-CYCLE @ - > IF -24 THROW THEN
  SI-SLOW @ IF 0 ?DO SI-TICK LOOP ELSE SI-FAST THEN ;
: SI-RAW-TO ( cycle -- ) DUP SI-CYCLE @ < IF -24 THROW THEN SI-CYCLE @ - SI-RAW-RUN ;
: SI-CHECK-WRITE { value address cycle | waveform -- }
  value 0 256 WITHIN 0= IF -24 THROW THEN
  address 54272 54297 WITHIN 0= IF -24 THROW THEN
  cycle SI-CYCLE @ < IF -24 THROW THEN
  address 54272 - DUP 21 < SWAP 7 MOD 4 = AND IF
    value 240 AND TO waveform waveform waveform 1- AND IF -21 THROW THEN
  THEN ;
: SI-STORE { value address | offset voice field old -- }
  address 54272 - TO offset offset 25 >= IF EXIT THEN
  offset 21 < IF
    offset 7 / TO voice offset 7 MOD TO field
    field 3 = IF value 15 AND TO value THEN
    field 4 = IF
      voice SI-CONTROL TO old
      old value XOR 1 AND IF
        value 1 AND IF 0 voice 3 SI! 0 voice 6 SI! ELSE 2 voice 3 SI! THEN
      THEN
      value 8 AND IF 0 voice 0 SI! 8388600 voice 1 SI!
      ELSE old 8 AND IF 8388600 voice 1 SI! THEN THEN
    THEN
    value offset CELLS SI-REGS + !
    field 2 < IF
      voice 7 * SI-R@ voice 7 * 1+ SI-R@ 8 LSHIFT OR voice 7 SI!
    THEN
    field 2 = field 3 = OR IF
      voice 7 * 2 + SI-R@ voice 7 * 3 + SI-R@ 8 LSHIFT OR voice 8 SI!
    THEN
  ELSE
    offset 21 = IF value 7 AND TO value THEN
    value offset CELLS SI-REGS + !
  THEN ;
: SI-COMPACT ( -- )
  SI-EVENT-INDEX @ 3 * CELLS SI-EVENTS + SI-EVENTS
  SI-EVENT-COUNT @ SI-EVENT-INDEX @ - 3 * CELLS MOVE
  SI-EVENT-INDEX @ NEGATE SI-EVENT-COUNT +! 0 SI-EVENT-INDEX ! ;
: SI-EVENT! { value address cycle | entry -- }
  value address cycle SI-CHECK-WRITE
  SI-EVENT-COUNT @ SI-EVENT-INDEX @ - 1024 >= IF -528 THROW THEN
  SI-EVENT-COUNT @ IF
    SI-EVENT-COUNT @ 1- 3 * 2 + CELLS SI-EVENTS + @ cycle > IF -24 THROW THEN
  THEN
  SI-EVENT-COUNT @ 1024 >= IF SI-COMPACT THEN
  SI-EVENT-COUNT @ 3 * CELLS SI-EVENTS + TO entry
  value entry ! address entry CELL+ ! cycle entry 2 CELLS + ! 1 SI-EVENT-COUNT +! ;
: SI-TO { cycle | entry at -- }
  cycle SI-CYCLE @ < IF -24 THROW THEN
  BEGIN SI-EVENT-INDEX @ SI-EVENT-COUNT @ < WHILE
    SI-EVENT-INDEX @ 3 * CELLS SI-EVENTS + TO entry entry 2 CELLS + @ TO at
    at cycle > IF cycle SI-RAW-TO EXIT THEN
    at SI-RAW-TO entry @ entry CELL+ @ SI-STORE 1 SI-EVENT-INDEX +!
  REPEAT cycle SI-RAW-TO ;
: SI-RUN ( clocks -- )
  DUP 0< IF -24 THROW THEN
  DUP 9223372036854775807 SI-CYCLE @ - > IF -24 THROW THEN SI-CYCLE @ + SI-TO ;
: SI-WRITE { value address cycle -- }
  value address cycle SI-CHECK-WRITE cycle SI-TO value address SI-STORE ;
: SI-WAVE { voice | phase control waveform fold noise -- wave12 }
  voice SI-CONTROL TO control control 240 AND TO waveform
  waveform 0= IF 0 EXIT THEN
  control 8 AND IF waveform 64 = IF 4095 ELSE 0 THEN EXIT THEN
  voice 0 SI@ TO phase
  waveform CASE
    16 OF
      phase 8388608 AND TO fold
      control 4 AND IF fold voice 2 + 3 MOD 0 SI@ 8388608 AND XOR TO fold THEN
      phase 12 RSHIFT 2047 AND fold IF 2047 XOR THEN 1 LSHIFT
    ENDOF
    32 OF phase 12 RSHIFT ENDOF
    64 OF
      voice 8 SI@ DUP 0= IF DROP 4095 ELSE
        DUP 4095 = IF DROP 0 ELSE phase 12 RSHIFT SWAP >= IF 4095 ELSE 0 THEN THEN
      THEN
    ENDOF
    128 OF
      0 TO noise
      8 0 DO noise 1 LSHIFT voice 1 SI@ SI-NOISE-TAPS I CELLS + @ RSHIFT 1 AND OR TO noise LOOP
      noise 4 LSHIFT
    ENDOF
  ENDCASE ;
: SI-READ { address cycle -- byte }
  address 54272 54301 WITHIN 0= IF -24 THROW THEN
  cycle SI-CYCLE @ < IF -24 THROW THEN
  address 54299 < IF -21 THROW THEN
  cycle SI-TO
  address CASE
    54299 OF 2 SI-WAVE 4 RSHIFT ENDOF 54300 OF 2 2 SI@ ENDOF
  ENDCASE ;
: SI-CLAMP ( fp -- fp )
  DUP -8589934592 < OVER 8589934592 > OR IF 1 SI-FILTER-LIMITS +! THEN
  -8589934592 MAX 8589934592 MIN ;
: SI-FILTER { input | cutoff alpha damping high -- filtered }
  21 SI-R@ 22 SI-R@ 3 LSHIFT OR TO cutoff
  cutoff CELLS SI-FILTER-COEFFS + @ TO alpha
  1414 23 SI-R@ 4 RSHIFT 80 * - 65536 * 1000 / TO damping
  2 0 DO
    input 65536 * SI-LOW @ - damping SI-BAND @ * 65536 / - TO high
    SI-BAND @ alpha high * 65536 / + SI-CLAMP SI-BAND !
    SI-LOW @ alpha SI-BAND @ * 65536 / + SI-CLAMP SI-LOW !
  LOOP
  0 24 SI-R@ 16 AND IF SI-LOW @ + THEN
  24 SI-R@ 32 AND IF SI-BAND @ + THEN
  24 SI-R@ 64 AND IF high + THEN 65536 / ;
: SI-SAMPLE { | routed direct voice sample filtered -- s16 }
  0 TO routed 0 TO direct
  3 0 DO
    I TO voice voice SI-CONTROL 240 AND IF
      voice SI-WAVE 2048 - voice 2 SI@ * 255 / TO sample
    ELSE 0 TO sample THEN
    23 SI-R@ 1 voice LSHIFT AND IF routed sample + TO routed
    ELSE voice 2 = 24 SI-R@ 128 AND 0<> AND 0= IF direct sample + TO direct THEN THEN
  LOOP
  routed SI-LOW @ OR SI-BAND @ OR IF routed SI-FILTER ELSE 0 THEN TO filtered
  direct filtered + 24 SI-R@ 15 AND * 3 /
  DUP -32768 < OVER 32767 > OR IF 1 SI-CLIPS +! THEN -32768 MAX 32767 MIN ;
: SI-LE! ( n addr -- ) OVER 255 AND OVER C! SWAP 8 RSHIFT 255 AND SWAP 1+ C! ;
: SI-RENDER ( addr frames -- )
  DUP 0< IF -24 THROW THEN
  0 ?DO SI-FRACTION @ SI-CPU + SI-RATE /MOD SI-RUN SI-FRACTION !
    SI-SAMPLE OVER SI-LE! 2 + LOOP DROP ;
: SI-DEMO-SETUP ( -- )
  SI-RESET
  68 54272 0 SI-WRITE 29 54273 0 SI-WRITE 0 54274 0 SI-WRITE 8 54275 0 SI-WRITE
  34 54277 0 SI-WRITE 168 54278 0 SI-WRITE 65 54276 0 SI-WRITE
  230 54279 0 SI-WRITE 14 54280 0 SI-WRITE
  67 54284 0 SI-WRITE 136 54285 0 SI-WRITE 21 54283 0 SI-WRITE
  113 54286 0 SI-WRITE 9 54287 0 SI-WRITE
  50 54291 0 SI-WRITE 104 54292 0 SI-WRITE 33 54290 0 SI-WRITE
  7 54293 0 SI-WRITE 100 54294 0 SI-WRITE
  167 54295 0 SI-WRITE 31 54296 0 SI-WRITE ;
SI-RESET
