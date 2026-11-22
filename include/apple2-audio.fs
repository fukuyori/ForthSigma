\ Original declared Apple II/II+ speaker and Mockingboard (two AY-3-8910) audio model; no CPU/ROM/real I/O.
DECIMAL
S" ./zx-ay-levels.fs" REQUIRED
48000 CONSTANT A2-RATE
\ CPU cycles per 48 kHz frame: (315/22 MHz x 65/912) / 48000 = 284375/13376.
284375 CONSTANT A2-NUM 13376 CONSTANT A2-DEN
\ One AY and its 6522 are worked on in A2-STATE; A2-CHIP! swaps the other one's copy in.
43 CONSTANT A2-CHIP-CELLS
CREATE A2-STATE A2-CHIP-CELLS CELLS ALLOT
CREATE A2-CHIPS A2-CHIP-CELLS 2 * CELLS ALLOT
VARIABLE A2-CURRENT 0 A2-CURRENT !
: A2-CHIP-COPY ( chip -- address ) A2-CHIP-CELLS * CELLS A2-CHIPS + ;
: A2-CHIP! ( chip -- )
  DUP A2-CURRENT @ = IF DROP EXIT THEN
  A2-STATE A2-CURRENT @ A2-CHIP-COPY A2-CHIP-CELLS CELLS MOVE
  DUP A2-CHIP-COPY A2-STATE A2-CHIP-CELLS CELLS MOVE A2-CURRENT ! ;
: A2-FIELD ( offset "name" -- ) CELLS A2-STATE + CONSTANT ;
0 A2-FIELD A2-REGS 16 A2-FIELD A2-TONE-COUNT 19 A2-FIELD A2-TONE-HIGH
22 A2-FIELD A2-NOISE-COUNT 23 A2-FIELD A2-NOISE-HALF 24 A2-FIELD A2-LFSR
25 A2-FIELD A2-ENV-COUNT 26 A2-FIELD A2-ENV-STEP 27 A2-FIELD A2-ENV-ATTACK
28 A2-FIELD A2-ENV-HOLD 29 A2-FIELD A2-ENV-ALTERNATE 30 A2-FIELD A2-ENV-HOLDING
31 A2-FIELD A2-LATCH 32 A2-FIELD A2-FUNC 33 A2-FIELD A2-HELD
34 A2-FIELD A2-ORB 35 A2-FIELD A2-ORA 36 A2-FIELD A2-DDRB 37 A2-FIELD A2-DDRA
\ The periods in steps, kept from the registers when they are written (0 counts as 1).
38 A2-FIELD A2-TONE-PERIODS 41 A2-FIELD A2-NOISE-STEPS 42 A2-FIELD A2-ENV-STEPS
CREATE A2-MASKS 255 , 15 , 255 , 15 , 255 , 15 , 31 , 255 , 31 , 31 , 31 , 255 , 255 , 15 , 255 , 255 ,
VARIABLE A2-SLOT VARIABLE A2-NEXT-SLOT VARIABLE A2-SPEAKER VARIABLE A2-HIGH VARIABLE A2-WINDOW
VARIABLE A2-CYCLE VARIABLE A2-DIV VARIABLE A2-FRACTION VARIABLE A2-SLOW
CREATE A2-EVENTS 3072 CELLS ALLOT VARIABLE A2-EVENT-COUNT VARIABLE A2-EVENT-INDEX
: A2-R@ ( reg -- byte ) CELLS A2-REGS + @ ;
: A2-CARD! ( slot -- ) DUP 0 8 WITHIN 0= IF -24 THROW THEN A2-NEXT-SLOT ! ;
\ The AY's RESET pin: registers, generators and the address latch; not the shared divider.
: A2-PSG-RESET ( -- )
  A2-REGS 16 CELLS 0 FILL A2-TONE-COUNT 3 CELLS 0 FILL A2-TONE-HIGH 3 CELLS 0 FILL
  0 A2-NOISE-COUNT ! 0 A2-NOISE-HALF ! 1 A2-LFSR !
  0 A2-ENV-COUNT ! 31 A2-ENV-STEP ! 0 A2-ENV-ATTACK !
  TRUE A2-ENV-HOLD ! FALSE A2-ENV-ALTERNATE ! TRUE A2-ENV-HOLDING ! 0 A2-LATCH !
  1 A2-TONE-PERIODS ! 1 A2-TONE-PERIODS CELL+ ! 1 A2-TONE-PERIODS 2 CELLS + ! 1 A2-NOISE-STEPS ! 1 A2-ENV-STEPS ! ;
: A2-RESET ( -- )
  A2-NEXT-SLOT @ A2-SLOT !
  2 0 DO I A2-CHIP! A2-PSG-RESET 0 A2-FUNC ! FALSE A2-HELD !
    0 A2-ORB ! 0 A2-ORA ! 0 A2-DDRB ! 0 A2-DDRA ! LOOP
  0 A2-SPEAKER ! 0 A2-HIGH ! 0 A2-WINDOW !
  0 A2-CYCLE ! 0 A2-DIV ! 0 A2-FRACTION ! FALSE A2-SLOW !
  0 A2-EVENT-COUNT ! 0 A2-EVENT-INDEX ! ;
\ PSG helpers below use a CPU/8 step and 32 hidden envelope sublevels, for the chip of A2-CHIP!.
: A2-TONE-PERIOD ( channel -- steps ) CELLS A2-TONE-PERIODS + @ ;
: A2-NOISE-PERIOD ( -- steps ) A2-NOISE-STEPS @ ;
: A2-ENV-PERIOD ( -- steps ) A2-ENV-STEPS @ ;
: A2-PERIODS ( reg -- )
  DUP 6 < IF 2 / DUP 2 * DUP A2-R@ SWAP 1+ A2-R@ 15 AND 8 LSHIFT OR 1 MAX SWAP CELLS A2-TONE-PERIODS + ! EXIT THEN
  DUP 6 = IF DROP 6 A2-R@ 31 AND 1 MAX A2-NOISE-STEPS ! EXIT THEN
  11 13 WITHIN IF 11 A2-R@ 12 A2-R@ 8 LSHIFT OR 1 MAX A2-ENV-STEPS ! THEN ;
: A2-ENV-LEVEL ( -- level ) A2-ENV-STEP @ A2-ENV-ATTACK @ XOR ;
: A2-ENV-START { | shape -- }
  13 A2-R@ 15 AND TO shape
  shape 4 AND IF 31 ELSE 0 THEN A2-ENV-ATTACK !
  shape 8 AND 0= IF TRUE A2-ENV-HOLD ! A2-ENV-ATTACK @ 0<> A2-ENV-ALTERNATE !
  ELSE shape 1 AND 0<> A2-ENV-HOLD ! shape 2 AND 0<> A2-ENV-ALTERNATE ! THEN
  31 A2-ENV-STEP ! 0 A2-ENV-COUNT ! FALSE A2-ENV-HOLDING ! ;
: A2-ENV-NEXT ( -- )
  A2-ENV-STEP @ 0> IF -1 A2-ENV-STEP +! ELSE
    A2-ENV-ALTERNATE @ IF A2-ENV-ATTACK @ 31 XOR A2-ENV-ATTACK ! THEN
    A2-ENV-HOLD @ IF TRUE A2-ENV-HOLDING ! ELSE 31 A2-ENV-STEP ! THEN
  THEN ;
: A2-NOISE-NEXT ( -- )
  A2-LFSR @ DUP 3 RSHIFT XOR 1 AND 16 LSHIFT A2-LFSR @ 1 RSHIFT OR A2-LFSR ! ;
\ A counter at count with a period, over n ticks: where it ends and how often it expired.
\ It expires when it reaches the period, or on the next tick when a shortened period is already passed.
: A2-EXPIRE ( count period n -- count' expiries )
  >R 2DUP SWAP - 1 MAX R@ OVER < IF 2DROP R> + 0 EXIT THEN
  R> SWAP - SWAP /MOD 1+ ROT DROP ;
\ Any number of steps at once: a tone flips on each expiry, the noise shifts on each
\ (it counts every second step), the envelope moves one sublevel on each until it holds.
\ The noise repeats after 131071 shifts and an envelope that does not hold after 64 sublevels.
: A2-ADVANCE-STEPS { steps | noise expiries -- }
  3 0 DO
    A2-TONE-COUNT I CELLS + @ I A2-TONE-PERIOD steps A2-EXPIRE
    1 AND IF A2-TONE-HIGH I CELLS + DUP @ 0= SWAP ! THEN A2-TONE-COUNT I CELLS + !
  LOOP
  steps 1 + A2-NOISE-HALF @ - 2 / TO noise
  A2-NOISE-HALF @ steps 1 AND + 1 AND A2-NOISE-HALF !
  noise IF
    A2-NOISE-COUNT @ A2-NOISE-PERIOD noise A2-EXPIRE 131071 MOD 0 ?DO A2-NOISE-NEXT LOOP A2-NOISE-COUNT !
  THEN
  A2-ENV-HOLDING @ 0= IF
    A2-ENV-COUNT @ A2-ENV-PERIOD steps A2-EXPIRE TO expiries A2-ENV-COUNT !
    A2-ENV-HOLD @ 0= IF expiries 64 MOD TO expiries THEN
    BEGIN expiries 0> A2-ENV-HOLDING @ 0= AND WHILE A2-ENV-NEXT -1 +TO expiries REPEAT
    A2-ENV-HOLDING @ IF 0 A2-ENV-COUNT ! THEN
  THEN ;
\ An AY held in reset by its pin does not run.
: A2-ADVANCE-CHIP ( steps -- ) A2-HELD @ IF DROP ELSE A2-ADVANCE-STEPS THEN ;
: A2-CHECK-TICK ( tick -- ) A2-CYCLE @ < IF -24 THROW THEN ;
: A2-RAW-RUN { clocks | steps remainder -- }
  clocks 0< clocks 9223372036854775807 A2-CYCLE @ - > OR IF -24 THROW THEN
  A2-SPEAKER @ IF clocks A2-HIGH +! THEN
  A2-SLOT @ IF
    A2-SLOW @ IF
      clocks 0 ?DO A2-DIV @ 1+ DUP 8 = IF
          DROP 0 0 A2-CHIP! 1 A2-ADVANCE-CHIP 1 A2-CHIP! 1 A2-ADVANCE-CHIP
        THEN A2-DIV ! LOOP
    ELSE
      clocks 8 /MOD TO steps TO remainder
      A2-DIV @ remainder + 8 /MOD steps + TO steps A2-DIV !
      steps IF 0 A2-CHIP! steps A2-ADVANCE-CHIP 1 A2-CHIP! steps A2-ADVANCE-CHIP THEN
    THEN
  THEN clocks A2-CYCLE +! ;
: A2-RAW-TO ( tick -- ) DUP A2-CHECK-TICK A2-CYCLE @ - A2-RAW-RUN ;
\ Bus decodes: C030-C03F is the speaker; page C0+slot is the card, bit 7 the 6522, bits 0-3 its register.
: A2-SPEAKER? ( target -- flag ) 65520 AND 49200 = ;
: A2-CARD? ( target -- flag ) A2-SLOT @ IF 8 RSHIFT A2-SLOT @ 192 + = ELSE DROP FALSE THEN ;
: A2-VIA-REG? ( reg -- flag ) DUP 4 < SWAP 15 = OR ;
: A2-CHECK { value target tick -- }
  value 0 256 WITHIN target 0 65568 WITHIN AND 0= IF -24 THROW THEN
  tick A2-CHECK-TICK target 65535 > A2-SLOT @ 0= AND IF -21 THROW THEN ;
: A2-REG-STORE { value reg -- }
  value reg CELLS A2-MASKS + @ AND reg CELLS A2-REGS + !
  reg A2-PERIODS reg 13 = IF A2-ENV-START THEN ;
\ Ports A and B in input mode read high (the AY's pull-ups), as the datasheet says.
: A2-REG-READ ( reg -- byte )
  DUP 14 = IF 7 A2-R@ 64 AND 0= IF DROP 255 EXIT THEN THEN
  DUP 15 = IF 7 A2-R@ 128 AND 0= IF DROP 255 EXIT THEN THEN A2-R@ ;
\ Pin levels of the 6522 ports. Undriven lines are declared: PB0 and PB1 low, the rest high.
: A2-PB ( -- byte ) A2-ORB @ A2-DDRB @ AND 252 A2-DDRB @ INVERT AND OR 255 AND ;
: A2-DRIVEN ( -- byte )
  A2-FUNC @ 1 = A2-HELD @ 0= AND A2-LATCH @ 16 < AND IF A2-LATCH @ A2-REG-READ ELSE 255 THEN ;
: A2-PA ( -- byte ) A2-ORA @ A2-DDRA @ AND A2-DRIVEN A2-DDRA @ INVERT AND OR 255 AND ;
\ PB2 low holds the AY in reset: it stays as reset, does not run and takes no writes. Otherwise BDIR (PB1) and BC1 (PB0) give the function,
\ which acts once, when it changes: 3 latches the address, 2 writes, 1 lets the AY drive port A.
: A2-BUS { | function -- }
  A2-PB 4 AND 0= IF
    A2-HELD @ 0= IF A2-PSG-RESET TRUE A2-HELD ! THEN 0 A2-FUNC ! EXIT
  THEN
  FALSE A2-HELD ! A2-PB 3 AND TO function
  function A2-FUNC @ = IF EXIT THEN function A2-FUNC !
  function 3 = IF A2-PA A2-LATCH ! THEN
  function 2 = IF A2-LATCH @ 16 < IF A2-PA A2-LATCH @ A2-REG-STORE THEN THEN ;
: A2-VIA! { value reg -- }
  reg 0 = IF value A2-ORB ! THEN reg 1 = reg 15 = OR IF value A2-ORA ! THEN
  reg 2 = IF value A2-DDRB ! THEN reg 3 = IF value A2-DDRA ! THEN
  reg A2-VIA-REG? IF A2-BUS THEN ;
: A2-VIA@ ( reg -- byte )
  DUP 0 = IF DROP A2-PB EXIT THEN DUP 2 = IF DROP A2-DDRB @ EXIT THEN
  3 = IF A2-DDRA @ ELSE A2-PA THEN ;
: A2-STORE { value target -- }
  target 65535 > IF
    target 65536 - 16 /MOD A2-CHIP! A2-HELD @ IF DROP EXIT THEN value SWAP A2-REG-STORE EXIT
  THEN
  target A2-SPEAKER? IF A2-SPEAKER @ 1 XOR A2-SPEAKER ! EXIT THEN
  target A2-CARD? IF target 7 RSHIFT 1 AND A2-CHIP! value target 15 AND A2-VIA! THEN ;
: A2-COMPACT ( -- )
  A2-EVENTS A2-EVENT-INDEX @ 3 * CELLS + A2-EVENTS
    A2-EVENT-COUNT @ A2-EVENT-INDEX @ - 3 * CELLS MOVE
  A2-EVENT-INDEX @ NEGATE A2-EVENT-COUNT +! 0 A2-EVENT-INDEX ! ;
: A2-EVENT! { value target tick | entry -- }
  value target tick A2-CHECK
  A2-EVENT-COUNT @ A2-EVENT-INDEX @ - 1024 >= IF -528 THROW THEN
  A2-EVENT-COUNT @ IF A2-EVENTS A2-EVENT-COUNT @ 1- 3 * 2 + CELLS + @ tick > IF -24 THROW THEN THEN
  A2-EVENT-COUNT @ 1024 >= IF A2-COMPACT THEN
  A2-EVENTS A2-EVENT-COUNT @ 3 * CELLS + TO entry
  value entry ! target entry CELL+ ! tick entry 2 CELLS + ! 1 A2-EVENT-COUNT +! ;
: A2-TO { tick | entry at -- }
  tick A2-CHECK-TICK
  BEGIN A2-EVENT-INDEX @ A2-EVENT-COUNT @ < WHILE
    A2-EVENTS A2-EVENT-INDEX @ 3 * CELLS + TO entry entry 2 CELLS + @ TO at
    at tick > IF tick A2-RAW-TO EXIT THEN
    at A2-RAW-TO entry @ entry CELL+ @ A2-STORE 1 A2-EVENT-INDEX +!
  REPEAT tick A2-RAW-TO ;
: A2-RUN ( clocks -- )
  DUP 0< IF -24 THROW THEN DUP 9223372036854775807 A2-CYCLE @ - > IF -24 THROW THEN
  A2-CYCLE @ + A2-TO ;
: A2-WRITE { value target tick -- } value target tick A2-CHECK tick A2-TO value target A2-STORE ;
\ A read of the speaker toggles it and returns 0: the model does not make the floating bus.
: A2-READ { target tick -- byte }
  target 0 65568 WITHIN 0= IF -24 THROW THEN tick A2-CHECK-TICK
  target 65535 > IF
    A2-SLOT @ 0= IF -21 THROW THEN
    tick A2-TO target 65536 - 16 /MOD A2-CHIP! A2-REG-READ EXIT
  THEN
  target A2-SPEAKER? IF tick A2-TO 0 target A2-STORE 0 EXIT THEN
  target A2-CARD? target 15 AND A2-VIA-REG? AND 0= IF -21 THROW THEN
  tick A2-TO target 7 RSHIFT 1 AND A2-CHIP! target 15 AND A2-VIA@ ;
: A2-TOGGLE ( tick -- ) 0 49200 ROT A2-WRITE ;
: A2-TOGGLE-EVENT! ( tick -- ) 0 49200 ROT A2-EVENT! ;
: A2-AY-TARGET ( reg chip -- target )
  OVER 0 16 WITHIN OVER 0 2 WITHIN AND 0= IF -24 THROW THEN 16 * + 65536 + ;
: A2-AY! { value reg chip tick -- } value reg chip A2-AY-TARGET tick A2-WRITE ;
: A2-AY-EVENT! { value reg chip tick -- } value reg chip A2-AY-TARGET tick A2-EVENT! ;
: A2-AY@ { reg chip tick -- byte } reg chip A2-AY-TARGET tick A2-READ ;
: A2-CHANNEL ( channel -- amplitude )
  >R A2-TONE-HIGH R@ CELLS + @ 7 A2-R@ DUP 1 R@ LSHIFT AND ROT OR 0<>
  SWAP 8 R@ LSHIFT AND A2-LFSR @ 1 AND OR 0<> AND 0= IF R> DROP 0 EXIT THEN
  R> 8 + A2-R@ DUP 16 AND IF DROP A2-ENV-LEVEL 1 RSHIFT ELSE 15 AND THEN CELLS ZX-LEVELS + @ ;
: A2-PSG-SAMPLE ( chip -- n ) A2-CHIP! 0 A2-CHANNEL 1 A2-CHANNEL + 2 A2-CHANNEL + 6 / ;
\ The speaker is the mean of its level over the cycles since the last rendered frame.
: A2-SPEAKER-SAMPLE ( -- n )
  A2-CYCLE @ A2-WINDOW @ - DUP 0= IF DROP A2-SPEAKER @ 4096 * ELSE A2-HIGH @ 4096 ROT */ THEN ;
\ The second chip first: it is the one an advance leaves in A2-STATE.
: A2-SAMPLE ( -- left right )
  A2-SPEAKER-SAMPLE DUP A2-SLOT @ IF 1 A2-PSG-SAMPLE + SWAP 0 A2-PSG-SAMPLE + SWAP THEN ;
: A2-LE! ( n address -- ) OVER 255 AND OVER C! SWAP 8 RSHIFT 255 AND SWAP 1+ C! ;
: A2-MAX-FRAMES ( -- frames )
  9223372036854775807 A2-CYCLE @ - A2-DEN UM*
  A2-DEN 1- A2-FRACTION @ - S>D D+ A2-NUM UM/MOD SWAP DROP ;
: A2-CHECK-FRAMES ( frames -- )
  DUP 0< IF -24 THROW THEN A2-MAX-FRAMES > IF -24 THROW THEN ;
: A2-RENDER { address frames -- }
  frames A2-CHECK-FRAMES
  frames 0 ?DO A2-FRACTION @ A2-NUM + A2-DEN /MOD A2-RUN A2-FRACTION !
    A2-SAMPLE address 2 + A2-LE! address A2-LE! address 4 + TO address
    0 A2-HIGH ! A2-CYCLE @ A2-WINDOW ! LOOP ;
0 A2-CARD! A2-RESET
