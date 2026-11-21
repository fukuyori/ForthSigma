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
\   SND-BEEP ( -- )  SND-PLAYING ( n -- flag )  SND-DEVICE ( -- flag )
\   SND-PLAYS ( c-addr1 u1 ... c-addrn un n -- )
\     n=0 stops MML and its voices, keeping SFX/MOD and MML settings.
\   SND-INSTRUMENT ( n -- )  SND-WAVE ( n -- )  SND-DUTY ( ratio -- )
\   SND-ADSR ( attack-ms decay-ms sustain release-ms -- )  SND-RING ( voice -- )
\   SND-SYNC ( voice -- )  SND-FILTER ( mode hz resonance -- )
\   SND-WAVETABLE ( addr n -- )  SND-LOAD-SAMPLE ( c-addr u n -- ior )
\   SND-SAMPLE ( c-addr u rate n -- )  SND-LOOP-SAMPLE ( start end n -- )
\   SND-SAMPLE-INSTRUMENT ( n -- )  SND-SFX ( n -- )  SND-FREE-SAMPLES ( -- )
\   SND-LOAD-MOD ( c-addr u -- ior )  SND-PLAY-MOD ( flag -- )  SND-STOP-MOD ( -- )
\   SND-MOD-PLAYING ( -- flag )  SND-TONE ( ... key -- )  SND-PLAY-TONE ( hz ms -- )
\   SND-MOD-FILTER ( mode hz -- )
\   SND-SOUND, SND-CHIP, SND-CHIPS, SND-STYLE, and SND-AMIGA-FILTER are left for the
\   images that have them; they throw -21. The chips' words are in include/.
\
\ The standard sound has 16 voices with no chip's limits: PLAY has voices 1 to 8, SFX 9
\ to 12, and MOD 13 to 16. PLAY takes MSX BASIC's music macro language (MML) and returns
\ as soon as the notes fit in the queues (32 places for each voice); the music goes on
\ while the program runs. Units: ratios 0 to 65535, Hz, milliseconds, cents.

\ ---- MSX BASIC -------------------------------------------------------------------

: PLAY ( c-addr u -- )   0 0 0 0 SND-PLAY ;
: PLAY2 ( c-addr1 u1 c-addr2 u2 -- )   0 0 SND-PLAY ;
: PLAY3 ( c-addr1 u1 c-addr2 u2 c-addr3 u3 -- )   SND-PLAY ;
: PLAY? ( n -- flag )   SND-PLAYING ;
: BEEP ( -- )   SND-BEEP ;
: PLAYS ( c-addr1 u1 ... c-addrn un n -- )   SND-PLAYS ;
\ Stops the music as 0 PLAYS does, and puts the voices' MML settings (octave, length,
\ tempo, volume, instrument, and the others) back as at start, without a sound.
: PLAY-RESET ( -- )   10 SND-GLOBAL ;
\ A square of hz for ms milliseconds, beside the music (on an SFX voice).
: PLAY-TONE ( hz ms -- )   SND-PLAY-TONE ;

\ ---- Instruments ----------------------------------------------------------------
\
\ MML's @n plays with instrument n (0 to 63). INSTRUMENT chooses the one the words
\ after it change, e.g.
\   1 INSTRUMENT  PULSE 16384 DUTY  10 200 40000 300 ADSR
\   2 INSTRUMENT  SAW  1 800 20000 FILTER     ( low-pass, 800 Hz, resonance )

: INSTRUMENT ( n -- )   SND-INSTRUMENT ;
: SQUARE ( -- )   0 SND-WAVE ;
: PULSE ( -- )   1 SND-WAVE ;
: TRIANGLE ( -- )   2 SND-WAVE ;
: SAW ( -- )   3 SND-WAVE ;
: NOISE ( -- )   4 SND-WAVE ;
: DUTY ( ratio -- )   SND-DUTY ;
: ADSR ( attack-ms decay-ms sustain release-ms -- )   SND-ADSR ;
: RING ( voice -- )   SND-RING ;
: SYNC ( voice -- )   SND-SYNC ;
\ mode 0 none, 1 low-pass, 2 band-pass, 3 high-pass, 4 low + high (notch), 5 low + band,
\ 6 band + high, 7 all three.
: FILTER ( mode hz resonance -- )   SND-FILTER ;
\ One cycle of n signed 16-bit values in cells at addr.
: WAVETABLE ( addr n -- )   SND-WAVETABLE ;
: NOISE-LFSR ( bits tap -- )   0 SND-TONE ;
: NOISE-MIX ( mode -- )   1 SND-TONE ;
\ n segments of three cells (level, ms, curve) at addr.
: ENVELOPE ( addr n loop release -- )   2 SND-TONE ;
: PITCH-SWEEP ( cents ms -- )   3 SND-TONE ;
: PITCH-SWEEP-LIMIT ( low-hz high-hz -- )   4 SND-TONE ;
: PORTAMENTO ( ms -- )   5 SND-TONE ;
: VIBRATO ( cents hz delay-ms -- )   6 SND-TONE ;
: PITCH-MOD ( voice cents -- )   7 SND-TONE ;
: VOLUME-MOD ( voice ratio -- )   8 SND-TONE ;
: MOD-ONLY ( flag -- )   9 SND-TONE ;
: PHASE-RESET ( flag -- )   10 SND-TONE ;
: NOTE-LIMIT ( ms -- )   11 SND-TONE ;
: INSTRUMENT-PAN ( left right -- )   12 SND-TONE ;   \ -65535 to 65535 each
: REVERB-SEND ( ratio -- )   13 SND-TONE ;
\ The steps of a chip (3.5 of docs/SOUND_CORE_DESIGN_STUDY.md); clocks in 1/1000 Hz.
: PITCH-PERIOD ( clock divider offset min max -- )   14 SND-TONE ;   \ clock 0: none
: PITCH-STEP ( clock bits -- )   15 SND-TONE ;
\ n (0 to 128) ascending levels (0 to 65535) in cells at addr.
: VOLUME-STEPS ( addr n -- )   16 SND-TONE ;
: DUTY-STEPS ( n -- )   17 SND-TONE ;            \ 0: none
: INTERPOLATION ( mode -- )   18 SND-TONE ;      \ 0 none, 1 linear
: NOISE-RATE ( hz -- )   19 SND-TONE ;   \ 1/1000 Hz; 0: 16 shifts a cycle of the note
\ MML's V0 to V15 as the 16 levels (0 to 65535) in cells at addr; 0 for 3 dB a step.
: V-STEPS ( addr n -- )   20 SND-TONE ;

\ ---- Samples --------------------------------------------------------------------
\
\ Samples 0 to 63 are recorded sound in the host's pool (64 MiB, outside the
\ dictionary's memory). An instrument with a sample plays it with its notes, O4's C at
\ the sample's own rate; SFX plays one at once beside the music.

: LOAD-SAMPLE ( c-addr u n -- )   SND-LOAD-SAMPLE THROW ;   \ a WAV file, 8 or 16 bits
: SAMPLE ( c-addr u rate n -- )   SND-SAMPLE ;              \ signed 8-bit bytes
: LOOP-SAMPLE ( start end n -- )   SND-LOOP-SAMPLE ;        \ 0 0 for no loop
: SAMPLE-INSTRUMENT ( n -- )   SND-SAMPLE-INSTRUMENT ;      \ -1 for none
: SFX ( n -- )   SND-SFX ;
: FREE-SAMPLES ( -- )   SND-FREE-SAMPLES ;                  \ stops the music too

\ ---- Modules ----------------------------------------------------------------------
\
\ A ProTracker module (MOD, 4 channels) plays beside PLAY and SFX on voices 13 to 16;
\ its data is in the pool of samples, which FREE-SAMPLES empties. The effect E0x turns
\ on MOD-FILTER's filter (mode as FILTER's: 0 none, 1 low-pass, 2 band-pass, 3 high-pass,
\ 4 notch, 5 low and band, 6 band and high, 7 all three).

: LOAD-MOD ( c-addr u -- )   SND-LOAD-MOD THROW ;
: PLAY-MOD ( flag -- )   SND-PLAY-MOD ;     \ again from the start after the end when true
: STOP-MOD ( -- )   SND-STOP-MOD ;
: MOD? ( -- flag )   SND-MOD-PLAYING ;
: MOD-FILTER ( mode hz -- )   SND-MOD-FILTER ;

\ ---- All the voices together --------------------------------------------------
\
\ These take effect at once and stay over BEEP and stops. The reverb hears what the
\ instruments send it (REVERB-SEND).

: REVERB ( delay-ms feedback volume -- )   0 SND-GLOBAL ;   \ 0 to 341 ms; volume 0: off
: REVERB-FIR ( addr n -- )   1 SND-GLOBAL ;    \ n (0 to 8) cells, 128 is 1
\ Two stages, 1 then 2: mode 0 none, 1 low-pass, 3 high-pass (two poles), 11 low-pass,
\ 13 high-pass (one pole).
: MASTER-FILTER ( mode hz stage -- )   8 SND-GLOBAL ;
: TONE-CONTROL ( bass treble -- )   3 SND-GLOBAL ;   \ dB, -12 to 12
: MASTER-VOLUME ( ratio -- )   4 SND-GLOBAL ;
: VOICE-LIMIT ( n -- )   5 SND-GLOBAL ;   \ PLAY's voices 1 to n sound (1 to 8)
: MIXER ( mode -- )   6 SND-GLOBAL ;   \ 0 linear, 1 the NES's formulas for voices 1 to 5
: OUTPUT-BITS ( bits rate -- )   7 SND-GLOBAL ;   \ bits 0: none, rate 0: every frame
\ The left and right levels (-65535 to 65535) of voice 1 to 16, whatever it plays; they
\ multiply the instrument's INSTRUMENT-PAN and MML's P.
: VOICE-PAN ( left right voice -- )   9 SND-GLOBAL ;

\ A voice that sounds until told otherwise, beside PLAY (hz in 1/1000 Hz, volume 0 to
\ 65535, 0 silences it). The same instrument again goes on at the new pitch and
\ volume, with its settings as they are now.
: VOICE-HOLD ( instrument hz volume voice -- )   SND-HOLD ;

\ ---- What the voices do ---------------------------------------------------------
\
\ Voices 1 to 16, as the audio thread last left them (it writes them every few ms).

: VOICE-OSC ( voice -- n )   0 SND-VOICE ;     \ -32768 to 32767
: VOICE-ENV ( voice -- ratio )   1 SND-VOICE ;
: VOICE-POS ( voice -- n )   2 SND-VOICE ;     \ the sample's place, or -1
: VOICE-ENDS ( voice -- n )   3 SND-VOICE ;    \ the sample's ends and loops so far
: VOICE-ON? ( voice -- flag )   4 SND-VOICE ;

\ ---- The device ------------------------------------------------------------------

: AUDIO? ( -- flag )   SND-DEVICE ;

\ Streaming PCM (host-owned bounded frames).
: PCM-OPEN SND-PCM-OPEN ;
: PCM-WRITE SND-PCM-WRITE ;
: PCM-QUEUED SND-PCM-QUEUED ;
: PCM-WAIT SND-PCM-WAIT ;
: PCM-STOP SND-PCM-STOP ;
: PCM-CLOSE SND-PCM-CLOSE ;
: PCM-UNDERRUNS SND-PCM-UNDERRUNS ;

: SNES-FRAMES ( regs aram voices globals history frames layout -- ) SND-SNES-FRAMES ;
