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
\   SND-DEVICE ( -- flag )
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

\ ---- The device ------------------------------------------------------------------

: AUDIO? ( -- flag )   SND-DEVICE ;
