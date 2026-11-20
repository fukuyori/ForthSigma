\ Original declared Paula register model; no Agnus bus/ROM/analog fidelity.
\ Register addresses are custom-chip offsets. Loading never opens audio.
DECIMAL
3546895 CONSTANT PA-CPU
48000 CONSTANT PA-RATE
CREATE PA-MEMORY 524288 ALLOT PA-MEMORY 524288 0 FILL
CREATE PA-REGS 24 CELLS ALLOT
CREATE PA-STATE 56 CELLS ALLOT
\ ptr,remaining,timer,mode(0idle1DMA2manual),phase,word,sample,period,volume,first,attach-phase,fetches,pending-word,pending-valid
: PA@ ( voice field -- n ) SWAP 14 * + CELLS PA-STATE + @ ;
: PA! ( value voice field -- ) SWAP 14 * + CELLS PA-STATE + ! ;
: PA-R@ ( voice field -- n ) SWAP 6 * + CELLS PA-REGS + @ ;
: PA-R! ( value voice field -- ) SWAP 6 * + CELLS PA-REGS + ! ;
VARIABLE PA-DMA VARIABLE PA-ADK VARIABLE PA-INTENA VARIABLE PA-INTREQ
VARIABLE PA-CYCLE VARIABLE PA-FRACTION VARIABLE PA-SLOW VARIABLE PA-PER-CLAMPS
CREATE PA-DUE 4 CELLS ALLOT
CREATE PA-EVENTS 3072 CELLS ALLOT
VARIABLE PA-EVENT-COUNT VARIABLE PA-EVENT-INDEX
: PA-RESET ( -- )
  PA-REGS 24 CELLS 0 FILL PA-STATE 56 CELLS 0 FILL PA-DUE 4 CELLS 0 FILL
  4 0 DO 65536 I 7 PA! LOOP
  0 PA-DMA ! 0 PA-ADK ! 0 PA-INTENA ! 0 PA-INTREQ !
  0 PA-CYCLE ! 0 PA-FRACTION ! 0 PA-SLOW ! 0 PA-PER-CLAMPS !
  0 PA-EVENT-COUNT ! 0 PA-EVENT-INDEX ! ;
: PA-MEM! { byte address -- }
  byte 0 256 WITHIN address 0 524288 WITHIN AND 0= IF -24 THROW THEN
  byte PA-MEMORY address + C! ;
: PA-PERIOD ( word -- ticks ) DUP 0= IF DROP 65536 THEN ;
: PA-VOLUME ( word -- volume ) DUP 64 AND IF DROP 64 ELSE 63 AND THEN ;
: PA-LENGTH ( voice -- words ) 2 PA-R@ DUP 0= IF DROP 65536 THEN ;
: PA-LOCATION ( voice -- address ) DUP 0 PA-R@ 16 LSHIFT SWAP 1 PA-R@ OR ;
: PA-IRQ ( voice -- ) 128 SWAP LSHIFT PA-INTREQ @ OR PA-INTREQ ! ;
: PA-IRQ? ( -- flag ) PA-INTENA @ 16384 AND 0<> PA-INTENA @ PA-INTREQ @ AND 1920 AND 0<> AND ;
: PA-ENABLED ( voice -- flag ) 1 SWAP LSHIFT PA-DMA @ AND 0<> PA-DMA @ 512 AND 0<> AND ;
: PA-RELOAD ( voice -- ) DUP PA-LOCATION OVER 0 PA! DUP PA-LENGTH OVER 1 PA! 0 SWAP 10 PA! ;
: PA-START ( voice -- )
  DUP PA-RELOAD 1 OVER 2 PA! 1 OVER 3 PA! 0 OVER 4 PA! 1 OVER 9 PA! 0 SWAP 13 PA! ;
: PA-ATTACH { voice word | av ap target -- }
  PA-ADK @ 1 voice LSHIFT AND 0<> TO av
  PA-ADK @ 16 voice LSHIFT AND 0<> TO ap
  voice 3 = av ap OR 0= OR IF EXIT THEN
  voice 1+ TO target
  av ap AND IF
    voice 10 PA@ IF FALSE TO av ELSE FALSE TO ap THEN
    voice 10 PA@ 1 XOR voice 10 PA!
  THEN
  av IF word PA-VOLUME target 8 PA! THEN
  ap IF
    word PA-PERIOD DUP 123 < IF DROP 123 1 PA-PER-CLAMPS +! THEN
    target 7 PA!
  THEN ;
: PA-FETCH { voice | address word -- }
  voice 0 PA@ TO address
  PA-MEMORY address + C@ 8 LSHIFT PA-MEMORY address 1+ 524287 AND + C@ OR TO word
  word voice 5 PA! word voice 5 PA-R!
  address 2 + 524287 AND voice 0 PA!
  voice 11 PA@ 1+ voice 11 PA!
  voice word PA-ATTACH
  voice 9 PA@ IF voice PA-IRQ 0 voice 9 PA! THEN
  voice 1 PA@ 1- DUP voice 1 PA! 0= IF voice PA-RELOAD voice PA-IRQ THEN ;
: PA-SIGNED ( byte -- sample ) DUP 128 AND IF 256 - THEN ;
: PA-TRANSITION { voice | phase mode -- }
  voice 4 PA@ TO phase voice 3 PA@ TO mode
  mode 0= IF EXIT THEN
  phase 0= IF
    mode 1 = IF voice PA-FETCH ELSE
      voice 12 PA@ voice 5 PA! 0 voice 13 PA!
      voice 11 PA@ 1+ voice 11 PA! voice voice 5 PA@ PA-ATTACH
    THEN
    voice 5 PA@ 8 RSHIFT PA-SIGNED voice 6 PA! 1 voice 4 PA!
  ELSE phase 1 = IF
    voice 5 PA@ 255 AND PA-SIGNED voice 6 PA!
    mode 1 = IF 0 ELSE 2 THEN voice 4 PA!
  ELSE
    voice PA-IRQ
    voice 13 PA@ IF 0 voice 4 PA! voice RECURSE
    ELSE 0 voice 3 PA! 0 voice 2 PA! THEN EXIT
  THEN THEN
  voice 7 PA@ voice 2 PA! ;
: PA-ADVANCE { ticks -- }
  4 0 DO
    I 3 PA@ IF I 2 PA@ ticks - DUP I 2 PA! 0= ELSE FALSE THEN
    PA-DUE I CELLS + !
  LOOP
  4 0 DO PA-DUE I CELLS + @ IF I PA-TRANSITION THEN LOOP
  ticks PA-CYCLE +! ;
: PA-STEP-LIMIT ( ticks -- n ) 4 0 DO I 3 PA@ IF I 2 PA@ MIN THEN LOOP ;
: PA-RAW-RUN { ticks | n -- }
  ticks 0< ticks 9223372036854775807 PA-CYCLE @ - > OR IF -24 THROW THEN
  BEGIN ticks 0> WHILE
    PA-SLOW @ IF 1 ELSE ticks PA-STEP-LIMIT THEN TO n
    n PA-ADVANCE n NEGATE +TO ticks
  REPEAT ;
: PA-RAW-TO ( tick -- ) DUP PA-CYCLE @ < IF -24 THROW THEN PA-CYCLE @ - PA-RAW-RUN ;
: PA-AUDIO-REG? ( offset -- flag ) DUP 160 220 WITHIN SWAP 15 AND 12 < AND ;
: PA-CHECK { value address tick | mask -- }
  value 0 65536 WITHIN address 0 512 WITHIN AND address 1 AND 0= AND 0= IF -24 THROW THEN
  tick PA-CYCLE @ < IF -24 THROW THEN
  address PA-AUDIO-REG? IF
    address 15 AND 6 = IF value 0> value 123 < AND IF -21 THROW THEN THEN EXIT
  THEN
  address CASE
    150 OF 527 ENDOF 158 OF 255 ENDOF 154 OF 18304 ENDOF 156 OF 1920 ENDOF
    -24 THROW
  ENDCASE TO mask
  value 32767 AND mask INVERT AND IF -21 THROW THEN ;
: PA-BITS ( value old -- new ) OVER 32768 AND IF OR 32767 AND ELSE SWAP INVERT AND THEN ;
: PA-STORE { value address | voice field old was now -- }
  address PA-AUDIO-REG? IF
    address 160 - 4 RSHIFT TO voice address 15 AND 2 / TO field
    field CASE
      0 OF value 7 AND TO value ENDOF
      1 OF value 65534 AND TO value ENDOF
      3 OF value PA-PERIOD voice 7 PA! ENDOF
      4 OF value PA-VOLUME voice 8 PA! ENDOF
    ENDCASE
    value voice field PA-R!
    field 5 = voice PA-ENABLED 0= AND IF
      value voice 12 PA! 1 voice 13 PA!
      voice 3 PA@ 2 <> IF
        2 voice 3 PA! 0 voice 4 PA! 1 voice 2 PA! 0 voice 10 PA!
      THEN
    THEN EXIT
  THEN
  address CASE
    150 OF
      PA-DMA @ TO old value old PA-BITS PA-DMA !
      4 0 DO
        old 512 AND 0<> old 1 I LSHIFT AND 0<> AND TO was
        I PA-ENABLED TO now
        now was 0= AND IF I PA-START THEN
        was now 0= AND IF 0 I 3 PA! 0 I 2 PA! THEN
      LOOP
    ENDOF
    158 OF value PA-ADK @ PA-BITS PA-ADK ! ENDOF
    154 OF value PA-INTENA @ PA-BITS PA-INTENA ! ENDOF
    156 OF value PA-INTREQ @ PA-BITS PA-INTREQ ! ENDOF
  ENDCASE ;
: PA-COMPACT ( -- )
  PA-EVENT-INDEX @ 3 * CELLS PA-EVENTS + PA-EVENTS
  PA-EVENT-COUNT @ PA-EVENT-INDEX @ - 3 * CELLS MOVE
  PA-EVENT-INDEX @ NEGATE PA-EVENT-COUNT +! 0 PA-EVENT-INDEX ! ;
: PA-EVENT! { value address tick | entry -- }
  value address tick PA-CHECK
  PA-EVENT-COUNT @ PA-EVENT-INDEX @ - 1024 >= IF -528 THROW THEN
  PA-EVENT-COUNT @ IF PA-EVENT-COUNT @ 1- 3 * 2 + CELLS PA-EVENTS + @ tick > IF -24 THROW THEN THEN
  PA-EVENT-COUNT @ 1024 >= IF PA-COMPACT THEN
  PA-EVENT-COUNT @ 3 * CELLS PA-EVENTS + TO entry
  value entry ! address entry CELL+ ! tick entry 2 CELLS + ! 1 PA-EVENT-COUNT +! ;
: PA-TO { tick | entry at -- }
  tick PA-CYCLE @ < IF -24 THROW THEN
  BEGIN PA-EVENT-INDEX @ PA-EVENT-COUNT @ < WHILE
    PA-EVENT-INDEX @ 3 * CELLS PA-EVENTS + TO entry entry 2 CELLS + @ TO at
    at tick > IF tick PA-RAW-TO EXIT THEN
    at PA-RAW-TO entry @ entry CELL+ @ PA-STORE 1 PA-EVENT-INDEX +!
  REPEAT tick PA-RAW-TO ;
: PA-WRITE { value address tick -- } value address tick PA-CHECK tick PA-TO value address PA-STORE ;
: PA-RUN ( ticks -- )
  DUP 0< IF -24 THROW THEN DUP 9223372036854775807 PA-CYCLE @ - > IF -24 THROW THEN PA-CYCLE @ + PA-TO ;
: PA-READ { address tick -- word }
  address 0 512 WITHIN address 1 AND 0= AND 0= IF -24 THROW THEN
  tick PA-CYCLE @ < IF -24 THROW THEN
  address 2 = address 16 = OR address 28 = OR address 30 = OR 0= IF -21 THROW THEN
  tick PA-TO address CASE
    2 OF PA-DMA @ ENDOF 16 OF PA-ADK @ ENDOF 28 OF PA-INTENA @ ENDOF 30 OF PA-INTREQ @ ENDOF
  ENDCASE ;
: PA-SAMPLE { | left right value -- left right }
  0 TO left 0 TO right
  4 0 DO
    PA-ADK @ 17 I LSHIFT AND 0= IF
      I 6 PA@ I 8 PA@ * 2 * TO value
      I 0= I 3 = OR IF left value + TO left ELSE right value + TO right THEN
    THEN
  LOOP left right ;
: PA-LE! ( n address -- ) OVER 255 AND OVER C! SWAP 8 RSHIFT 255 AND SWAP 1+ C! ;
: PA-RENDER { address frames -- }
  frames 0< IF -24 THROW THEN
  frames 0 ?DO
    PA-FRACTION @ PA-CPU + PA-RATE /MOD PA-RUN PA-FRACTION !
    PA-SAMPLE address 2 + PA-LE! address PA-LE! address 4 + TO address
  LOOP ;
: PA-DEMO-MEMORY ( -- ) 1024 0 DO I 37 * 11 + 255 AND I PA-MEM! LOOP ;
: PA-DEMO-SETUP ( -- )
  PA-RESET 4 0 DO
    I 128 * I 16 * 162 + 0 PA-WRITE 32 I 16 * 164 + 0 PA-WRITE
    I 107 * 214 + I 16 * 166 + 0 PA-WRITE 32 I 16 * 168 + 0 PA-WRITE
  LOOP 33295 150 0 PA-WRITE ;
PA-RESET
