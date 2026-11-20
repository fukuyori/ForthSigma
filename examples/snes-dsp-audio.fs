\ Original declared S-DSP sample-boundary model. No CPU/ROM/SDK/real I/O.
DECIMAL
S" examples/snes-gauss.fs" INCLUDED
32000 CONSTANT SD-RATE 1024000 CONSTANT SD-CLOCK
CREATE SD-REGS 128 ALLOT CREATE SD-ARAM 65536 ALLOT
\ Per voice: on,pos,nibble,header,previous,older,phase,env,mode,delay,hist0..3.
CREATE SD-VOICES 112 CELLS ALLOT
0 CONSTANT SD-ON 1 CONSTANT SD-POS 2 CONSTANT SD-NIB 3 CONSTANT SD-HEADER
4 CONSTANT SD-P1 5 CONSTANT SD-P2 6 CONSTANT SD-PHASE 7 CONSTANT SD-ENV
8 CONSTANT SD-MODE 9 CONSTANT SD-DELAY
CREATE SD-RATES 0 , 2048 , 1536 , 1280 , 1024 , 768 , 640 , 512 ,
384 , 320 , 256 , 192 , 160 , 128 , 96 , 80 , 64 , 48 , 40 , 32 ,
24 , 20 , 16 , 12 , 10 , 8 , 6 , 5 , 4 , 3 , 2 , 1 ,
CREATE SD-GLOBALS 10 CELLS ALLOT
SD-GLOBALS 0 CELLS + CONSTANT SD-CYCLE
SD-GLOBALS 1 CELLS + CONSTANT SD-DIV
SD-GLOBALS 2 CELLS + CONSTANT SD-FRAME
SD-GLOBALS 3 CELLS + CONSTANT SD-PENDING
SD-GLOBALS 4 CELLS + CONSTANT SD-NOISE
SD-GLOBALS 5 CELLS + CONSTANT SD-EOFF
SD-GLOBALS 6 CELLS + CONSTANT SD-ELEN
SD-GLOBALS 7 CELLS + CONSTANT SD-EHI
SD-GLOBALS 8 CELLS + CONSTANT SD-LEFT
SD-GLOBALS 9 CELLS + CONSTANT SD-RIGHT
VARIABLE SD-FRAMES-XT 0 SD-FRAMES-XT !
: SD-USE-FORTH 0 SD-FRAMES-XT ! ;
CREATE SD-EHIST 16 CELLS ALLOT CREATE SD-MIX 2 CELLS ALLOT CREATE SD-EMIX 2 CELLS ALLOT
CREATE SD-EVENTS 3072 CELLS ALLOT VARIABLE SD-EVENT-COUNT VARIABLE SD-EVENT-INDEX
: SD-ASR ( n bits -- q ) ARSHIFT ;
: SD-S8 255 AND DUP 128 AND IF 256 - THEN ;
: SD-S15 32767 AND DUP 16384 AND IF 32768 - THEN ;
: SD-S16 65535 AND DUP 32768 AND IF 65536 - THEN ;
: SD-SAT -32768 MAX 32767 MIN ;
: SD-V@ { v field -- n } v 14 * field + CELLS SD-VOICES + @ ;
: SD-V! { n v field -- } n v 14 * field + CELLS SD-VOICES + ! ;
: SD-R@ SD-REGS + C@ ;
: SD-B@ 65535 AND SD-ARAM + C@ ;
: SD-B! 65535 AND SD-ARAM + C! ;
: SD-W@ { a -- n } a SD-B@ a 1+ SD-B@ 8 LSHIFT OR ;
: SD-W! { n a -- } n 255 AND a SD-B! n 8 RSHIFT 255 AND a 1+ SD-B! ;
: SD-RESET ( -- )
  SD-REGS 128 0 FILL SD-ARAM 65536 0 FILL SD-VOICES 112 CELLS 0 FILL
  8 0 DO 3 I SD-MODE SD-V! LOOP 224 108 SD-REGS + C!
  0 SD-CYCLE ! 0 SD-DIV ! 0 SD-FRAME ! 0 SD-PENDING ! 16384 SD-NOISE !
  0 SD-EOFF ! 4 SD-ELEN ! 0 SD-EHI ! 0 SD-LEFT ! 0 SD-RIGHT !
  SD-EHIST 16 CELLS 0 FILL SD-MIX 2 CELLS 0 FILL SD-EMIX 2 CELLS 0 FILL
  0 SD-EVENT-COUNT ! 0 SD-EVENT-INDEX ! ;
: SD-BRR { nibble header old older | n shift f -- sample }
  nibble 8 >= IF nibble 16 - ELSE nibble THEN TO n
  header 4 RSHIFT TO shift header 2 RSHIFT 3 AND TO f
  shift 12 <= IF n 1 shift LSHIFT * 1 SD-ASR ELSE n 0< IF -2048 ELSE 0 THEN THEN TO n
  f CASE
    1 OF n old + old NEGATE 4 SD-ASR + TO n ENDOF
    2 OF n old 2 * + old -3 * 5 SD-ASR + older - older 4 SD-ASR + TO n ENDOF
    3 OF n old 2 * + old -13 * 6 SD-ASR + older - older 3 * 4 SD-ASR + TO n ENDOF
  ENDCASE n SD-SAT SD-S15 ;
: SD-DIR-ADDR { v -- addr } 93 SD-R@ 256 * v 16 * 4 + SD-R@ 4 * + 65535 AND ;
: SD-START { v -- }
  TRUE v SD-ON SD-V! v SD-DIR-ADDR SD-W@ v SD-POS SD-V!
  0 v SD-NIB SD-V! 0 v SD-HEADER SD-V! 0 v SD-P1 SD-V! 0 v SD-P2 SD-V!
  0 v SD-PHASE SD-V! 0 v SD-ENV SD-V! 0 v SD-MODE SD-V! 5 v SD-DELAY SD-V!
  4 0 DO 0 v 10 I + SD-V! LOOP
  124 SD-R@ 1 v LSHIFT INVERT AND 124 SD-REGS + C! ;
: SD-CONSUME { v | nib pos header b value -- }
  v SD-NIB SD-V@ TO nib v SD-POS SD-V@ TO pos
  nib 0= IF pos SD-B@ v SD-HEADER SD-V! THEN v SD-HEADER SD-V@ TO header
  pos 1+ nib 2 / + SD-B@ TO b
  nib 1 AND IF b 15 AND ELSE b 4 RSHIFT THEN header v SD-P1 SD-V@ v SD-P2 SD-V@ SD-BRR TO value
  v SD-P1 SD-V@ v SD-P2 SD-V! value v SD-P1 SD-V!
  3 0 DO v 11 I + SD-V@ v 10 I + SD-V! LOOP value v 13 SD-V!
  nib 1+ TO nib nib 16 = IF
    0 TO nib header 1 AND IF
      124 SD-R@ 1 v LSHIFT OR 124 SD-REGS + C!
      v SD-DIR-ADDR 2 + SD-W@ TO pos
      header 2 AND 0= IF 0 v SD-ENV SD-V! 3 v SD-MODE SD-V! THEN
    ELSE pos 9 + 65535 AND TO pos THEN
  THEN nib v SD-NIB SD-V! pos v SD-POS SD-V! ;
: SD-RATE? { rate -- flag } rate 0= IF FALSE EXIT THEN SD-FRAME @ rate CELLS SD-RATES + @ MOD 0= ;
: SD-ENV-PHASE { v | level -- }
  v SD-ENV SD-V@ TO level
  v SD-MODE SD-V@ 0= level 2016 >= AND IF 1 v SD-MODE SD-V! THEN
  v SD-MODE SD-V@ 1 = level v 16 * 6 + SD-R@ 5 RSHIFT 1+ 256 * <= AND IF 2 v SD-MODE SD-V! THEN ;
: SD-ENV-STEP { v | env mode a b gain rate delta -- }
  v SD-ENV SD-V@ TO env v SD-MODE SD-V@ TO mode
  mode 3 = IF env 8 - 0 MAX v SD-ENV SD-V! EXIT THEN
  v 16 * 5 + SD-R@ TO a v 16 * 6 + SD-R@ TO b v 16 * 7 + SD-R@ TO gain
  a 128 AND IF
    mode CASE
      0 OF a 15 AND 2 * 1+ TO rate a 15 AND 15 = IF 1024 ELSE 32 THEN TO delta ENDOF
      1 OF a 4 RSHIFT 7 AND 2 * 16 + TO rate env 255 + 256 / NEGATE TO delta ENDOF
      2 OF b 31 AND TO rate env 255 + 256 / NEGATE TO delta ENDOF
    ENDCASE
    rate SD-RATE? IF env delta + TO env THEN
  ELSE
    gain 128 AND 0= IF gain 127 AND 16 * TO env ELSE
      gain 31 AND SD-RATE? IF
        gain 5 RSHIFT 3 AND CASE
          0 OF env 32 - TO env ENDOF
          1 OF env env 255 + 256 / - TO env ENDOF
          2 OF env 32 + TO env ENDOF
          3 OF env env 1536 < IF 32 ELSE 8 THEN + TO env ENDOF
        ENDCASE
      THEN
    THEN
  THEN env 0 MAX 2047 MIN v SD-ENV SD-V! v SD-ENV-PHASE ;
: SD-GAUSS-SAMPLE { v | phase sum coefficient -- sample }
  v SD-PHASE SD-V@ 4 RSHIFT 255 AND TO phase 0 TO sum
  4 0 DO
    I CASE 0 OF 255 phase - ENDOF 1 OF 511 phase - ENDOF
      2 OF 256 phase + ENDOF 3 OF phase ENDOF ENDCASE
    CELLS SD-GAUSS + @ TO coefficient
    I 3 = IF sum SD-S16 TO sum THEN
    sum v 10 I + SD-V@ coefficient * 10 SD-ASR + TO sum
  LOOP sum SD-SAT 1 SD-ASR ;
: SD-PUBLISH { value v -- }
  v SD-ENV SD-V@ 4 RSHIFT v 16 * 8 + SD-REGS + C!
  value 7 SD-ASR 255 AND v 16 * 9 + SD-REGS + C! ;
: SD-VOICE { v previous | value pitch phase -- sample }
  v SD-ON SD-V@ 0= IF 0 v SD-PUBLISH 0 EXIT THEN
  v SD-DELAY SD-V@ DUP 0> IF
    1- DUP v SD-DELAY SD-V! 0= IF v SD-CONSUME THEN
    0 v SD-PUBLISH 0 EXIT
  THEN DROP
  61 SD-R@ 1 v LSHIFT AND IF SD-NOISE @ SD-S15 ELSE v SD-GAUSS-SAMPLE THEN
  v SD-ENV SD-V@ * 11 SD-ASR TO value
  value v SD-PUBLISH v SD-ENV-STEP
  v 16 * 2 + SD-R@ v 16 * 3 + SD-R@ 63 AND 8 LSHIFT OR TO pitch
  v 0> 45 SD-R@ 1 v LSHIFT AND 0<> AND IF
    pitch previous 4 SD-ASR 1024 + * 10 SD-ASR 0 MAX 16383 MIN TO pitch
  THEN
  v SD-PHASE SD-V@ pitch + TO phase
  BEGIN phase 4096 >= WHILE v SD-CONSUME phase 4096 - TO phase REPEAT
  phase v SD-PHASE SD-V! value ;
: SD-ADD-MIX { value channel base -- }
  base channel CELLS + DUP @ value + SD-SAT SWAP ! ;
: SD-FIR { channel | sum h coefficient -- n }
  0 TO sum
  8 0 DO
    SD-EHI @ I 1+ + 7 AND 2 * channel + CELLS SD-EHIST + @ TO h
    I 16 * 15 + SD-R@ SD-S8 TO coefficient
    I 7 = IF sum SD-S16 TO sum THEN
    sum h coefficient * 6 SD-ASR + TO sum
  LOOP sum SD-SAT ;
: SD-ECHO { | address left right value -- }
  SD-EOFF @ 0= IF 125 SD-R@ 15 AND 2048 * 4 MAX SD-ELEN ! THEN
  109 SD-R@ 256 * SD-EOFF @ + 65535 AND TO address
  address SD-W@ SD-S16 1 SD-ASR SD-EHI @ 2 * CELLS SD-EHIST + !
  address 2 + SD-W@ SD-S16 1 SD-ASR SD-EHI @ 2 * 1+ CELLS SD-EHIST + !
  0 SD-FIR TO left 1 SD-FIR TO right
  2 0 DO
    I IF right ELSE left THEN TO value
    SD-MIX I CELLS + @ I 16 * 12 + SD-R@ SD-S8 * 7 SD-ASR SD-S16
    value I 16 * 44 + SD-R@ SD-S8 * 7 SD-ASR SD-S16 + SD-SAT
    108 SD-R@ 64 AND IF DROP 0 THEN
    I IF SD-RIGHT ELSE SD-LEFT THEN !
    108 SD-R@ 32 AND 0= IF
      SD-EMIX I CELLS + @ value 13 SD-R@ SD-S8 * 7 SD-ASR SD-S16 + SD-SAT -2 AND
      address I 2 * + SD-W!
    THEN
  LOOP
  SD-EOFF @ 4 + DUP SD-ELEN @ >= IF DROP 0 THEN SD-EOFF !
  SD-EHI @ 1+ 7 AND SD-EHI ! ;
: SD-STEP { | pending previous value term -- }
  1 SD-FRAME +!
  108 SD-R@ 31 AND SD-RATE? IF
    SD-NOISE @ DUP 1 RSHIFT XOR 1 AND 14 LSHIFT SD-NOISE @ 1 RSHIFT OR SD-NOISE !
  THEN
  SD-PENDING @ TO pending
  8 0 DO
    108 SD-R@ 128 AND IF 0 I SD-ENV SD-V! 3 I SD-MODE SD-V! THEN
    SD-FRAME @ 1 AND IF
      92 SD-R@ 1 I LSHIFT AND IF 3 I SD-MODE SD-V! THEN
      pending 1 I LSHIFT AND IF I SD-START THEN
    THEN
  LOOP SD-FRAME @ 1 AND IF 0 SD-PENDING ! THEN
  SD-MIX 2 CELLS 0 FILL SD-EMIX 2 CELLS 0 FILL 0 TO previous
  8 0 DO
    I previous SD-VOICE TO value
    2 0 DO
      value J 16 * I + SD-R@ SD-S8 * 6 SD-ASR TO term
      term I SD-MIX SD-ADD-MIX
      77 SD-R@ 1 J LSHIFT AND IF term I SD-EMIX SD-ADD-MIX THEN
    LOOP value TO previous
  LOOP SD-ECHO ;
: SD-CHECK-TICK ( tick -- ) SD-CYCLE @ < IF -24 THROW THEN ;
: SD-APPLY-FRAMES { frames | gap -- }
  SD-FRAMES-XT @ ?DUP IF frames SWAP EXECUTE EXIT THEN
  frames 0 ?DO 32 SD-DIV @ - TO gap SD-STEP gap SD-CYCLE +! 0 SD-DIV ! LOOP ;
: SD-RAW-RUN { ticks | frames rem target finaldiv -- }
  ticks 0< ticks 9223372036854775807 SD-CYCLE @ - > OR IF -24 THROW THEN
  SD-CYCLE @ ticks + TO target
  ticks 32 /MOD TO frames TO rem
  SD-DIV @ rem + 32 /MOD frames + TO frames TO finaldiv
  frames SD-APPLY-FRAMES finaldiv SD-DIV ! target SD-CYCLE ! ;
: SD-RAW-TO DUP SD-CHECK-TICK SD-CYCLE @ - SD-RAW-RUN ;
: SD-CHECK { value target tick -- }
  value 0 256 WITHIN target 0 65664 WITHIN AND 0= IF -24 THROW THEN tick SD-CHECK-TICK ;
: SD-STORE { value target -- }
  target 128 < IF
    target 124 = IF 0 ELSE value THEN target SD-REGS + C!
    target 76 = IF value SD-PENDING ! THEN
  ELSE value target 128 - SD-B! THEN ;
: SD-COMPACT
  SD-EVENTS SD-EVENT-INDEX @ 3 * CELLS + SD-EVENTS
  SD-EVENT-COUNT @ SD-EVENT-INDEX @ - 3 * CELLS MOVE
  SD-EVENT-INDEX @ NEGATE SD-EVENT-COUNT +! 0 SD-EVENT-INDEX ! ;
: SD-QUEUE { value target tick | p -- }
  value target tick SD-CHECK
  SD-EVENT-COUNT @ SD-EVENT-INDEX @ - 1024 >= IF -528 THROW THEN
  SD-EVENT-COUNT @ IF SD-EVENTS SD-EVENT-COUNT @ 1- 3 * 2 + CELLS + @ tick > IF -24 THROW THEN THEN
  SD-EVENT-COUNT @ 1024 >= IF SD-COMPACT THEN
  SD-EVENTS SD-EVENT-COUNT @ 3 * CELLS + TO p
  value p ! target p CELL+ ! tick p 2 CELLS + ! 1 SD-EVENT-COUNT +! ;
: SD-TO { tick | p at -- }
  tick SD-CHECK-TICK
  BEGIN SD-EVENT-INDEX @ SD-EVENT-COUNT @ < WHILE
    SD-EVENTS SD-EVENT-INDEX @ 3 * CELLS + TO p p 2 CELLS + @ TO at
    at tick > IF tick SD-RAW-TO EXIT THEN
    at SD-RAW-TO p @ p CELL+ @ SD-STORE 1 SD-EVENT-INDEX +!
  REPEAT tick SD-RAW-TO ;
: SD-RUN DUP 0< IF -24 THROW THEN DUP 9223372036854775807 SD-CYCLE @ - > IF -24 THROW THEN SD-CYCLE @ + SD-TO ;
: SD-WRITE { value target tick -- } value target tick SD-CHECK tick SD-TO value target SD-STORE ;
: SD-CHECK-REG 0 128 WITHIN 0= IF -24 THROW THEN ;
: SD-CHECK-RAM 0 65536 WITHIN 0= IF -24 THROW THEN ;
: SD-REG! { value reg tick -- } reg SD-CHECK-REG value reg tick SD-WRITE ;
: SD-REG-EVENT! { value reg tick -- } reg SD-CHECK-REG value reg tick SD-QUEUE ;
: SD-REG@ { reg tick -- byte } reg SD-CHECK-REG tick SD-TO reg SD-R@ ;
: SD-RAM! { value addr tick -- } addr SD-CHECK-RAM value addr 128 + tick SD-WRITE ;
: SD-RAM-EVENT! { value addr tick -- } addr SD-CHECK-RAM value addr 128 + tick SD-QUEUE ;
: SD-RAM@ { addr tick -- byte } addr SD-CHECK-RAM tick SD-TO addr SD-B@ ;
: SD-SAMPLE SD-LEFT @ SD-RIGHT @ ;
: SD-MAX-FRAMES 9223372036854775807 SD-CYCLE @ - 32 / ;
: SD-LE! { n addr -- } n 255 AND addr C! n 8 RSHIFT 255 AND addr 1+ C! ;
: SD-RENDER { address frames -- }
  frames 0< frames SD-MAX-FRAMES > OR IF -24 THROW THEN
  frames 0 ?DO 32 SD-RUN SD-LEFT @ address SD-LE! SD-RIGHT @ address 2 + SD-LE! address 4 + TO address LOOP ;
CREATE SD-DEMO-DATA 2 C, 70 C, 118 C, 66 C, 14 C, 172 C, 154 C, 206 C,
: SD-DEMO-SETUP ( -- )
  SD-RESET 512 256 SD-W! 512 258 SD-W! 195 512 SD-B!
  8 0 DO SD-DEMO-DATA I + C@ 513 I + SD-B! LOOP
  1 93 SD-STORE 64 12 SD-STORE 64 28 SD-STORE
  32 44 SD-STORE 32 60 SD-STORE 48 13 SD-STORE 64 127 SD-STORE
  64 109 SD-STORE 1 125 SD-STORE 255 77 SD-STORE
  8 0 DO
    901 I 73 * + DUP 255 AND I 16 * 2 + SD-STORE 8 RSHIFT I 16 * 3 + SD-STORE
    I 1 AND IF 8 ELSE 20 THEN I 16 * SD-STORE
    I 1 AND IF 20 ELSE 8 THEN I 16 * 1+ SD-STORE
    48 I 16 * 7 + SD-STORE
  LOOP 0 108 SD-STORE 255 76 SD-STORE ;
SD-RESET
