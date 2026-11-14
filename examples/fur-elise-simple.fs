\ The theme of Fuer Elise by Ludwig van Beethoven (bars 1 to 22, with both
\ repeats), as a short program: two voices on the MSX's PSG, the right hand and
\ the left hand, each a string of music for PLAY2. About 55 seconds.
\ examples/fur-elise.fs plays more of the piece, with a piano of samples.
\
\   sigma.exe examples/fur-elise-simple.fs      (Windows)
\   sigma examples/fur-elise-simple.fs          (Linux, macOS)
\
\ In the strings, a letter is a note, R a rest, O the octave, < and > an octave
\ down and up, and a number after a note or a rest its length (8 an eighth note,
\ 4. a dotted quarter). A note without a number is a 16th note, as L16 says.

REQUIRE-AUDIO
ALSO AUDIO

: WAIT-MUSIC ( -- )   BEGIN 0 PLAY? WHILE 10 MS REPEAT ;

\ The tempo, the length of a note without a number, and the volume of each hand.
: SETUP ( -- )   S" T75 L16 V12" S" T75 L16 V9" PLAY2 ;

\ The two notes before bar 1.
: PICKUP ( -- )
   S" O5 E D#"
   S" R8" PLAY2 ;

\ Bars 1 to 7 (and 15 to 21).
: THEME ( -- )
   S" O5 E D# E <B> D C  <A8 R16 C E A  B8 R16 E G# B  >C8 R16 <E> E D#  E D# E <B> D C  <A8 R16 C E A  B8 R16 E >C< B"
   S" R4.  O2 A >E A R16 R8  <E >E G# R16 R8  <A >E A R16 R8  R4.  <A >E A R16 R8  <E >E G# R16 R8" PLAY2 ;

\ Bar 8 the first time: back to bar 1.
: ENDING-1 ( -- )
   S" O4 A4 >E D#"
   S" O2 A >E A R16 R8" PLAY2 ;

\ Bar 8 the second time, and bar 22 the first time: on to bar 9.
: ENDING-2 ( -- )
   S" O4 A8 R16 B >C D"
   S" O2 A >E A R16 R8" PLAY2 ;

\ Bars 9 to 14. In bars 12 to 14 the hands answer each other.
: MIDDLE ( -- )
   S" O5 E8. <G >F E  D8. <F >E D  C8. <E >D C  <B8 R16 E >E R16  R16 E >E R16 R16 <D#  E8 R16 D# E D#"
   S" O3 C G >C R16 R8  O2 G >G B R16 R8  <A >E A R16 R8  <E >E >E R16 R16 E  >E R16 R16 D# E R16  R16 D# E R16 R8" PLAY2 ;

\ Bar 22 the last time.
: LAST-BAR ( -- )
   S" O4 A4."
   S" O2 A >E A R4" PLAY2 ;

: FUR-ELISE ( -- )
   SETUP
   PICKUP THEME ENDING-1  THEME ENDING-2
   MIDDLE THEME ENDING-2  MIDDLE THEME LAST-BAR
   WAIT-MUSIC ;

FUR-ELISE
