\ The audio library of FORTH/Sigma, written in Forth.
\
\ REQUIRE-AUDIO interprets this file, which is built into the program, after it has put
\ the SND- words in the AUDIO vocabulary. While the file loads, new words go into AUDIO,
\ AUDIO is searched first, and BASE is decimal; afterwards the search order, the current
\ word list, and BASE are what they were before REQUIRE-AUDIO.
\
\ To try a changed copy of this file without rebuilding, load the built-in one first
\ and then include the copy into AUDIO (its words then replace the built-in ones):
\   REQUIRE-AUDIO  ALSO AUDIO DEFINITIONS  DECIMAL  INCLUDE src/audio/audio.fs
\
\ The SND- words underneath:
\   SND-PLAY ( c-addr1 u1 c-addr2 u2 c-addr3 u3 -- )  the three voices of one PLAY
\   SND-SOUND ( reg value -- )  SND-BEEP ( -- )  SND-PLAYING ( n -- flag )
\   SND-DEVICE ( -- flag )  SND-PLAYS ( c-addr1 u1 ... c-addrn un n -- )
\   SND-CHIP ( n -- )  SND-INSTRUMENT ( n -- )  SND-WAVE ( n -- )
\   SND-DUTY ( percent -- )  SND-ADSR ( a d s r -- )  SND-RING ( flag -- )
\   SND-SYNC ( flag -- )  SND-FILTER ( mode cutoff resonance -- )
\   SND-WAVETABLE ( c-addr n -- )  SND-LOAD-SAMPLE ( c-addr u n -- ior )
\   SND-SAMPLE ( c-addr u rate n -- )  SND-LOOP-SAMPLE ( start end n -- )
\   SND-SAMPLE-INSTRUMENT ( n -- )  SND-SFX ( n -- )  SND-AMIGA-FILTER ( flag -- )
\   SND-FREE-SAMPLES ( -- )  SND-CHIPS ( mask -- )  SND-LOAD-MOD ( c-addr u -- ior )
\   SND-PLAY-MOD ( flag -- )  SND-STOP-MOD ( -- )  SND-MOD-PLAYING ( -- flag )
\
\ The sound is MSX BASIC's: an AY-3-8910 at the MSX's clock, played by the host's audio
\ thread. PLAY takes MSX BASIC's music macro language (MML) and returns as soon as the
\ notes fit in the queues (32 places for each voice); the music goes on while the
\ program runs.

\ ---- MSX BASIC -------------------------------------------------------------------

: PLAY ( c-addr u -- )   0 0 0 0 SND-PLAY ;
: PLAY2 ( c-addr1 u1 c-addr2 u2 -- )   0 0 SND-PLAY ;
: PLAY3 ( c-addr1 u1 c-addr2 u2 c-addr3 u3 -- )   SND-PLAY ;
: PLAY? ( n -- flag )   SND-PLAYING ;
: SOUND ( reg value -- )   SND-SOUND ;
: BEEP ( -- )   SND-BEEP ;

\ ---- Chips ----------------------------------------------------------------------
\
\ PLAY plays on one chip at a time. Choosing one stops the music, as BEEP does without
\ its sound; the PSG of SOUND and BEEP sounds with every chip.

: MSX-SOUND ( -- )   0 SND-CHIP ;     \ the MSX's AY-3-8910, 3 voices (at start)
: ST-SOUND ( -- )   1 SND-CHIP ;      \ the Atari ST's YM2149 at 2 MHz, 3 voices
: NES-SOUND ( -- )   2 SND-CHIP ;     \ the NES: pulse, pulse, triangle, noise
: C64-SOUND ( -- )   3 SND-CHIP ;     \ the C64's SID (PAL), 3 voices
: SCC-SOUND ( -- )   4 SND-CHIP ;     \ Konami's SCC, 5 voices
: AMIGA-SOUND ( -- )   5 SND-CHIP ;   \ the Amiga's Paula (PAL): samples, 4 voices
: PLAYS ( c-addr1 u1 ... c-addrn un n -- )   SND-PLAYS ;

\ Several chips together: CHIPS takes their bits, e.g. MSX SCC OR CHIPS, and numbers
\ the voices in this order (there voices 1 to 3 are the PSG's, 4 to 8 the SCC's). At
\ most 8 voices in all, and not MSX and ST together (they are one PSG).

1 CONSTANT MSX   2 CONSTANT ST   4 CONSTANT NES   8 CONSTANT C64
16 CONSTANT SCC   32 CONSTANT AMIGA
: CHIPS ( mask -- )   SND-CHIPS ;

\ ---- Instruments ----------------------------------------------------------------
\
\ MML's @n plays with instrument n (0 to 63) on the chips that have instruments (the
\ NES, the C64, the SCC, and the Amiga). INSTRUMENT chooses the one the words after it change, e.g.
\   1 INSTRUMENT  PULSE 25 DUTY  0 6 8 4 ADSR
\   2 INSTRUMENT  SAW  1 400 8 FILTER       ( the C64: low-pass, cutoff, resonance )

: INSTRUMENT ( n -- )   SND-INSTRUMENT ;
: SQUARE ( -- )   0 SND-WAVE ;
: PULSE ( -- )   1 SND-WAVE ;
: TRIANGLE ( -- )   2 SND-WAVE ;
: SAW ( -- )   3 SND-WAVE ;
: NOISE ( -- )   4 SND-WAVE ;
: DUTY ( percent -- )   SND-DUTY ;
: ADSR ( attack decay sustain release -- )   SND-ADSR ;
: RING ( flag -- )   SND-RING ;
: SYNC ( flag -- )   SND-SYNC ;
: FILTER ( mode cutoff resonance -- )   SND-FILTER ;
\ The SCC plays instrument n with the 32 signed bytes at c-addr as its wave.
: SCC-WAVE ( c-addr n -- )   SND-WAVETABLE ;

\ ---- Samples --------------------------------------------------------------------
\
\ Samples 0 to 63 are recorded sound in the host's pool (16 MiB, outside the
\ dictionary's memory). The Amiga plays an instrument's sample with its notes, O4's C
\ at the sample's own rate; SFX plays one at once beside the music, on any chip.

: LOAD-SAMPLE ( c-addr u n -- )   SND-LOAD-SAMPLE THROW ;   \ a WAV file, 8 or 16 bits
: SAMPLE ( c-addr u rate n -- )   SND-SAMPLE ;              \ signed 8-bit bytes
: LOOP-SAMPLE ( start end n -- )   SND-LOOP-SAMPLE ;        \ 0 0 for no loop
: SAMPLE-INSTRUMENT ( n -- )   SND-SAMPLE-INSTRUMENT ;      \ -1 for none
: SFX ( n -- )   SND-SFX ;
: FREE-SAMPLES ( -- )   SND-FREE-SAMPLES ;                  \ stops the music too
: AMIGA-FILTER ( flag -- )   SND-AMIGA-FILTER ;             \ the LED filter

\ ---- Modules ----------------------------------------------------------------------
\
\ A ProTracker module (MOD, 4 channels) plays beside PLAY and SFX, on the Amiga's
\ periods and filters; its data is in the pool of samples, which FREE-SAMPLES empties.

: LOAD-MOD ( c-addr u -- )   SND-LOAD-MOD THROW ;
: PLAY-MOD ( flag -- )   SND-PLAY-MOD ;     \ again from the start after the end when true
: STOP-MOD ( -- )   SND-STOP-MOD ;
: MOD? ( -- flag )   SND-MOD-PLAYING ;

\ ---- The device ------------------------------------------------------------------

: AUDIO? ( -- flag )   SND-DEVICE ;
