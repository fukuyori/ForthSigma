\ All the chip libraries, and STYLE (tque 1190): an instrument with one chip's steps,
\ so that PLAY's voices can sound like different chips (choose them with @n).
\
\   REQUIRE chips.fs  1 INSTRUMENT NES STYLE  2 INSTRUMENT SCC STYLE
\   S" @1 O4 L8 CDEF" S" @2 O5 L8 EFGA" PLAY2
S" ./msx-sound.fs" REQUIRED
S" ./st-sound.fs" REQUIRED
S" ./nes-sound.fs" REQUIRED
S" ./c64-sound.fs" REQUIRED
S" ./scc-sound.fs" REQUIRED
S" ./amiga-sound.fs" REQUIRED
REQUIRE-AUDIO
GET-CURRENT ALSO AUDIO DEFINITIONS
DECIMAL

1 CONSTANT MSX  2 CONSTANT ST  4 CONSTANT NES  8 CONSTANT C64  16 CONSTANT SCC  32 CONSTANT AMIGA

\ The chosen instrument gets chip's steps (one of MSX ST NES C64 SCC AMIGA), or the
\ standard sound's for 0.
: STYLE ( chip -- )
  CASE
    0 OF STANDARD-STEPS ENDOF
    MSX OF MSX-STEPS ENDOF
    ST OF ST-STEPS ENDOF
    NES OF NES-STEPS ENDOF
    C64 OF C64-STEPS ENDOF
    SCC OF SCC-STEPS ENDOF
    AMIGA OF AMIGA-STEPS ENDOF
    -24 THROW
  ENDCASE ;
PREVIOUS SET-CURRENT
