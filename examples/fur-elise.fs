\ Fuer Elise (Bagatelle No. 25 in A minor, WoO 59) by Ludwig van Beethoven: the
\ theme with its repeats, the first episode, and the theme again (bars 1 to 58),
\ on the Amiga's Paula with a piano of samples that the program makes itself.
\ About 97 seconds. examples/fur-elise-simple.fs is a short program that
\ plays the theme alone.
\
\   sigma.exe examples/fur-elise.fs      (Windows)
\   sigma examples/fur-elise.fs          (Linux, macOS)
\
\ The notes are those of the Mutopia Project's edition of the piece (after
\ Breitkopf & Haertel, 1888; public domain), arranged for the 8 voices of PLAY.

REQUIRE-AUDIO
ALSO AUDIO
DECIMAL

: WAIT-MUSIC ( -- )   BEGIN 0 PLAY? WHILE 10 MS REPEAT ;

\ ---- The piano's samples --------------------------------------------------------

\ A sample is a struck string: 100 cycles in which the six harmonics go from BRIGHT
\ to MELLOW, then one cycle of MELLOW that is played round and round while the
\ instrument's ADSR lets the note die away.
6 CONSTANT HARMONICS
CREATE BRIGHT   46 C, 30 C, 20 C, 12 C, 8 C, 6 C,      \ the harmonics' levels; each
CREATE MELLOW   64 C, 20 C,  8 C,  3 C, 1 C, 0 C,      \ row's sum is at most 127
100 CONSTANT CYCLES
128 CONSTANT LONGEST                                    \ the longest cycle, in samples
CREATE TONE   CYCLES 1+ LONGEST * ALLOT
VARIABLE PERIOD                                         \ the samples in a cycle
VARIABLE STRIKE                                         \ the samples before the loop

\ 1000 times the sine of i / h of a half turn, 0 <= i <= h (Bhaskara's formula).
: HALF-SINE ( i h -- n )
   TUCK OVER - *  SWAP DUP * 5 *  OVER 4 * -  SWAP 16000 * SWAP / ;

\ 1000 times the sine of i / p of a turn; p is even.
: SINE ( i p -- n )
   TUCK MOD  SWAP 2/
   2DUP < IF HALF-SINE ELSE TUCK - SWAP HALF-SINE NEGATE THEN ;

\ How bright sample n is: 1000 at the start, falling ever more slowly to 0 at the loop.
: FADE ( n -- f )   STRIKE @ SWAP - 0 MAX  1000 STRIKE @ */  DUP 1000 */ ;

\ Harmonic h (from 0) of sample n, 1000 times too large.
: PARTIAL ( n f h -- x )
   >R
   R@ BRIGHT + C@  R@ MELLOW + C@ -  * 1000 /  R@ MELLOW + C@ +     ( n level )
   SWAP R> 1+ *  PERIOD @ SINE  * ;

: SAMPLE-AT ( n -- byte )
   DUP FADE 0                                           ( n f sum )
   HARMONICS 0 DO  2 PICK 2 PICK I PARTIAL +  LOOP
   NIP NIP 1000 / ;

\ Sample `number`, with `period` samples in a cycle. O4's C plays a sample at the
\ rate it was recorded at, so the rate is the period times that note's 261.63 Hz.
: MAKE-TONE ( period rate number -- )
   >R >R  DUP PERIOD !  CYCLES * STRIKE !
   STRIKE @ PERIOD @ +  0 DO  I SAMPLE-AT  TONE I + C!  LOOP
   TONE  STRIKE @ PERIOD @ +  R> R@ SAMPLE
   STRIKE @  DUP PERIOD @ +  R> LOOP-SAMPLE ;

\ Paula plays a sample at 3546895 / period samples a second, and its period is a
\ whole number of at least 124. A high note of a long cycle would need a shorter
\ period, and a low note of a short cycle sounds coarse, so the piano has four
\ samples, as an Amiga's instrument has one for each part of the keyboard:
\   @1  128 samples a cycle   up to O3's F
\   @2  64                    up to O4's F
\   @3  32                    up to O5's F
\   @4  16                    above that
\ The low strings ring longer than the high ones.
: PIANO ( -- )
   AMIGA-SOUND
   128 33488 0 MAKE-TONE   64 16744 1 MAKE-TONE
    32  8372 2 MAKE-TONE   16  4186 3 MAKE-TONE
   1 INSTRUMENT  0 SAMPLE-INSTRUMENT  0 11 0 9 ADSR
   2 INSTRUMENT  1 SAMPLE-INSTRUMENT  0 11 0 9 ADSR
   3 INSTRUMENT  2 SAMPLE-INSTRUMENT  0 10 0 8 ADSR
   4 INSTRUMENT  3 SAMPLE-INSTRUMENT  0 10 0 8 ADSR ;

\ ---- The voices ---------------------------------------------------------------

\ A voice's music is one string, put together a line at a time: VOICE chooses the
\ voice (1 to 8), and M| adds the text up to the next | to that voice's string.
3072 CONSTANT VOICE-SIZE
CREATE TUNE   8 VOICE-SIZE * ALLOT
CREATE USED   8 CELLS ALLOT   USED 8 CELLS ERASE
VARIABLE CHOSEN

: VOICE ( n -- )   1- CHOSEN ! ;
: TEXT ( -- addr )   CHOSEN @ VOICE-SIZE * TUNE + ;
: FILLED ( -- addr )   CHOSEN @ CELLS USED + ;
: +MML ( c-addr u -- )
   DUP FILLED @ + 1+ VOICE-SIZE > ABORT" The voice's string is full"
   TUCK  TEXT FILLED @ +  SWAP MOVE
   FILLED +!  BL TEXT FILLED @ + C!  1 FILLED +! ;
: M| ( "text|" -- )   [CHAR] | PARSE +MML ;

: PLAY-TUNE ( -- )
   8 0 DO  I CHOSEN !  TEXT FILLED @  LOOP  8 PLAYS ;

\ ---- The music ----------------------------------------------------------------

\ The lines below were made by a program from the score. Paula's voices are on
\ the left, right, right, and left, and so on round. The right hand's top note is
\ played on both sides (voices 1 and 2), and its other notes on voices 7 and 8.
\ The left hand's notes go to voices 3 to 6 in turn, and each rings on, as with the
\ piano's pedal, for up to a second or until its voice has the next note.
\
\ Poco moto: at T75 a 16th note is 10 ticks of 1/50 second, so a bar of 3/8 is
\ 1.2 seconds, and a 32nd note is the shortest note PLAY has. A note's length is
\ a whole number of ticks; one that no length at T75 gives is written at another
\ tempo that does (T158 C2 is 37 ticks).

\ Voice 1: the right hand's top note, on the left
1 VOICE
\ bars 1 to 8, first ending
M| T75 L16 V12 @3O5E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3G# B >C8 R16 @2<E     |
M| @3>E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3>C <B A4                           |
\ bars 1 to 7 again
M| >E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3G# B >C8 R16 @2<E @3>E D# E D# E <B  |
M| >D C <A8 R16 @2C E @3A B8 R16 @2E @3>C <B                                                |
\ bar 8, second ending
M| A8 R16 B >C D                                                                            |
\ bars 9 to 22, first ending
M| E8. <G @4>F @3E D8. <F >E D C8. @2<E @3>D C <B8 R16 @2E @3>E R8 E @4>E R8 @3<D# E8 R16   |
M| D# E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3G# B >C8 R16 @2<E @3>E D# E D# E   |
M| <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3>C <B A8 R16 B >C D                               |
\ bars 9 to 21 again
M| E8. <G @4>F @3E D8. <F >E D C8. @2<E @3>D C <B8 R16 @2E @3>E R8 E @4>E R8 @3<D# E8 R16   |
M| D# E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3G# B >C8 R16 @2<E @3>E D# E D# E   |
M| <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3>C <B                                             |
\ bar 22, second ending
M| A8 R16 >C C C20 <A32                                                                     |
\ bars 23 to 58: the first episode and the theme again
M| T158>C2 T75@4F. @3E32 E8 D8 @4B-. A32 A G F @3E D C <B-8 A8 A32 G32 A32 B-32 >C4 D D#    |
M| E8. E @4F @3<A >C4 D. <B32 >C32 @4G32 @3<G32 @4>G32 @3<A32 @4>G32 @3<B32 @4>G32 @3C32    |
M| @4G32 @3D32 @4G32 @3E32 @4G32 >C32 <B32 A32 G32 F32 @3E32 D32 @4G32 F32 @3D32 C32 @4G32  |
M| @3<G32 @4>G32 @3<A32 @4>G32 @3<B32 @4>G32 @3C32 @4G32 @3D32 @4G32 @3E32 @4G32 >C32 <B32  |
M| A32 G32 F32 @3E32 D32 @4G32 F32 @3D32 E32 @4F32 @3E32 D#32 E32 <B32 >E32 D#32 E32 <B32   |
M| >E32 D#32 E8. <B >E D# E8. <B >E D# E D# E D# E D# E D# E <B >D C <A8 R16 @2C E @3A B8   |
M| R16 @2E @3G# B >C8 R16 @2<E @3>E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3>C <B  |
M| A8 R16 B >C D E8. <G @4>F @3E D8. <F >E D C8. @2<E @3>D C <B8 R16 @2E @3>E R8 E @4>E R8  |
M| @3<D# E R8 D# E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3G# B >C8 R16 @2<E @3>E  |
M| D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3>C <B                                   |
\ the last bar
M| A4                                                                                       |

\ Voice 2: the same, on the right
2 VOICE
\ bars 1 to 8, first ending
M| T75 L16 V12 @3O5E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3G# B >C8 R16 @2<E     |
M| @3>E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3>C <B A4                           |
\ bars 1 to 7 again
M| >E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3G# B >C8 R16 @2<E @3>E D# E D# E <B  |
M| >D C <A8 R16 @2C E @3A B8 R16 @2E @3>C <B                                                |
\ bar 8, second ending
M| A8 R16 B >C D                                                                            |
\ bars 9 to 22, first ending
M| E8. <G @4>F @3E D8. <F >E D C8. @2<E @3>D C <B8 R16 @2E @3>E R8 E @4>E R8 @3<D# E8 R16   |
M| D# E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3G# B >C8 R16 @2<E @3>E D# E D# E   |
M| <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3>C <B A8 R16 B >C D                               |
\ bars 9 to 21 again
M| E8. <G @4>F @3E D8. <F >E D C8. @2<E @3>D C <B8 R16 @2E @3>E R8 E @4>E R8 @3<D# E8 R16   |
M| D# E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3G# B >C8 R16 @2<E @3>E D# E D# E   |
M| <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3>C <B                                             |
\ bar 22, second ending
M| A8 R16 >C C C20 <A32                                                                     |
\ bars 23 to 58: the first episode and the theme again
M| T158>C2 T75@4F. @3E32 E8 D8 @4B-. A32 A G F @3E D C <B-8 A8 A32 G32 A32 B-32 >C4 D D#    |
M| E8. E @4F @3<A >C4 D. <B32 >C32 @4G32 @3<G32 @4>G32 @3<A32 @4>G32 @3<B32 @4>G32 @3C32    |
M| @4G32 @3D32 @4G32 @3E32 @4G32 >C32 <B32 A32 G32 F32 @3E32 D32 @4G32 F32 @3D32 C32 @4G32  |
M| @3<G32 @4>G32 @3<A32 @4>G32 @3<B32 @4>G32 @3C32 @4G32 @3D32 @4G32 @3E32 @4G32 >C32 <B32  |
M| A32 G32 F32 @3E32 D32 @4G32 F32 @3D32 E32 @4F32 @3E32 D#32 E32 <B32 >E32 D#32 E32 <B32   |
M| >E32 D#32 E8. <B >E D# E8. <B >E D# E D# E D# E D# E D# E <B >D C <A8 R16 @2C E @3A B8   |
M| R16 @2E @3G# B >C8 R16 @2<E @3>E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3>C <B  |
M| A8 R16 B >C D E8. <G @4>F @3E D8. <F >E D C8. @2<E @3>D C <B8 R16 @2E @3>E R8 E @4>E R8  |
M| @3<D# E R8 D# E D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3G# B >C8 R16 @2<E @3>E  |
M| D# E D# E <B >D C <A8 R16 @2C E @3A B8 R16 @2E @3>C <B                                   |
\ the last bar
M| A4                                                                                       |

\ Voice 3: the left hand
3 VOICE
\ bars 1 to 8, first ending
M| T75 L16 V10 R2 @1O2A4. R16 >E4 R8. @2A4 R2. @1<E4. R16 >E8.                              |
\ bars 1 to 7 again
M| R4. R4 @2A4 R4. @1<A4. R4. R16 >E4 R8. @2G#4                                             |
\ bar 8, second ending
M| R4.                                                                                      |
\ bars 9 to 22, first ending
M| @1C4. R16 @2G4 R8. A4 R4 R16 >E R4. R16 @3>D#4 R4.. @2O3A4 R4. @1<A4. R4. R16 >E4 R8.    |
M| @2G#4 R4.                                                                                |
\ bars 9 to 21 again
M| @1C4. R16 @2G4 R8. A4 R4 R16 >E R4. R16 @3>D#4 R4.. @2O3A4 R4. @1<A4. R4. R16 >E4 R8.    |
M| @2G#4                                                                                    |
\ bar 22, second ending
M| R8. B-8 G                                                                                |
\ bars 23 to 58: the first episode and the theme again
M| R16 A4 A R8. B-8. R16 >E8 E8 E R8. <A8. R16 A4 A R8. A8. G4 G8 R8. @3>F8 @2D E4 <G8 R8.  |
M| @3>G8 F G4 @2<B8 R4. R4. R4. R4. R4. R16 @1E4 R8. @2G#4 R2. @1<A4. R16 >E4 R8. @2A4 R4.  |
M| @1<G4. R16 >E4 R8. @2>E4 R4 @3>E8 R4. R4. R16 @1O3E4 R8. @2G#4 R2. @1<A4. R16 >E4 R8.    |
\ the last bar
M| @2A8                                                                                     |

\ Voice 4: the left hand
4 VOICE
\ bars 1 to 8, first ending
M| T75 L16 V10 R4.. @1O3E4 R8. @2G#4 R2. @1<A4. R16 >E4 R8. @2A8                            |
\ bars 1 to 7 again
M| R4. R4. R8 @1<E4. R16 >E4 R4.. @2A4 R4.                                                  |
\ bar 8, second ending
M| @1<A4.                                                                                   |
\ bars 9 to 22, first ending
M| R16 @2>G4 R8. B4 R4. @1<E4. @3O5E4. R8 E4 R2. @1O2E4. R16 >E4 R4.. @2A4 R4. @1<A4.       |
\ bars 9 to 21 again
M| R16 @2>G4 R8. B4 R4. @1<E4. @3O5E4. R8 E4 R2. @1O2E4. R16 >E4 R4.. @2A4 R4.              |
\ bar 22, second ending
M| @1<A8. @2O4C8 <B-                                                                        |
\ bars 23 to 58: the first episode and the theme again
M| R8 >C4 <F4 >D8 R8 <F8 F8 F4 >C8 R8 C4 @1<E4 D8 R16 @2>E4 @3F R8. G8 F G4 @2<B8 R4 >E @3G |
M| R8 @2<F4 G#4. R4. R4. R4. R4. R8 A4 R4. @1<A4. R4. R16 >E4 R8. @2G#4 R4. @1C4. R16 @2G4  |
M| R8. A4 R4 R16 >E R4. R16 @3>D#4 R4.. @2O3A4 R4. @1<A4. R4. R16 >E4 R8. @2G#4             |
\ the last bar
M| R4                                                                                       |

\ Voice 5: the left hand
5 VOICE
\ bars 1 to 8, first ending
M| T75 L16 V10 R4. R4 @2O3A4 R4. @1<A4. R4. R16 >E4 R8. @2G#4 R2.                           |
\ bars 1 to 7 again
M| @1<A4. R16 >E4 R8. @2A4 R2. @1<E4.                                                       |
\ bar 8, second ending
M| R16 >E4 R8.                                                                              |
\ bars 9 to 22, first ending
M| @2>C4 R4. @1O2A4. R16 >E4 R4 @3O5D#8. R2. @1O2A4. R16 >E4 R8. @2A4 R2. @1<E4. R16 >E4    |
M| R8.                                                                                      |
\ bars 9 to 21 again
M| @2>C4 R4. @1O2A4. R16 >E4 R4 @3O5D#8. R2. @1O2A4. R16 >E4 R8. @2A4 R2. @1<E4.            |
\ bar 22, second ending
M| R16 >E8. @2A >C                                                                          |
\ bars 23 to 58: the first episode and the theme again
M| R8. <A8. R16 B-4 B- R8 G8 G8 R16 A4 A R8. A8. R16 A8. >D8 R8 <G4 >C4 E @3G R8 @2<F4 >C4  |
M| @3G8 @2C8 <A4 B4. R4. R4. R4. R4. R4. @1<E4. R16 >E4 R4.. @2A4 R4. @1<A4. R16 @2>G4 R8.  |
M| B4 R4. @1<E4. @3O5E4. R8 E4 R2. @1O2E4. R16 >E4 R4.. @2A4 R4.                            |
\ the last bar
M| @1<A4                                                                                    |

\ Voice 6: the left hand
6 VOICE
\ bars 1 to 8, first ending
M| T75 L16 V10 R4. R4. R8 @1O2E4. R16 >E4 R4.. @2A4 R4. @1<A4                               |
\ bars 1 to 7 again
M| R4.. >E4 R8. @2G#4 R2. @1<A4. R16 >E4 R8.                                                |
\ bar 8, second ending
M| @2A4                                                                                     |
\ bars 9 to 22, first ending
M| R4. @1<G4. R16 >E4 R8. @2>E4 R4 @3>E8 R4. R4. R16 @1O3E4 R8. @2G#4 R2. @1<A4. R16 >E4    |
M| R8. @2A4                                                                                 |
\ bars 9 to 21 again
M| R4. @1<G4. R16 >E4 R8. @2>E4 R4 @3>E8 R4. R4. R16 @1O3E4 R8. @2G#4 R2. @1<A4. R16 >E4    |
M| R8.                                                                                      |
\ bar 22, second ending
M| @2A8 >C8                                                                                 |
\ bars 23 to 58: the first episode and the theme again
M| <F4 >C8 R8 D4 <F8 B-8 B-8 R8 >C4 <F4 >C8 R8 C8. <F R8. >E8. E4 @3G8 @2C8 <A4 R8. @3>F8   |
M| @2D E4 <G8 R4. R4. R4. R4. R4. @1<A4. R16 >E4 R8. @2A4 R2. @1<E4. R16 >E4 R8. @2>C4 R4.  |
M| @1O2A4. R16 >E4 R4 @3O5D#8. R2. @1O2A4. R16 >E4 R8. @2A4 R2. @1<E4.                      |
\ the last bar
M| R16 >E8.                                                                                 |

\ Voice 7: the right hand's other notes
7 VOICE
\ bars 1 to 8, first ending
M| T75 L16 V10 R4. R4. R4. R4. R4. R4. R4. R4.                                              |
\ bars 1 to 7 again
M| R4. R4. R4. R4. R4. R4. R4. R4.                                                          |
\ bar 8, second ending
M| R4.                                                                                      |
\ bars 9 to 22, first ending
M| R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4.                                  |
\ bars 9 to 21 again
M| R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4                                       |
\ bar 22, second ending
M| R16 @2O4E R16 @3G32 R4.                                                                  |
\ bars 23 to 58: the first episode and the theme again
M| R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4.  |
M| R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4                                   |
\ the last bar
M| R32                                                                                      |

\ Voice 8: the right hand's other notes
8 VOICE
\ bars 1 to 8, first ending
M| T75 L16 V10 R4. R4. R4. R4. R4. R4. R4. R4.                                              |
\ bars 1 to 7 again
M| R4. R4. R4. R4. R4. R4. R4. R4.                                                          |
\ bar 8, second ending
M| R4.                                                                                      |
\ bars 9 to 22, first ending
M| R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4.                                  |
\ bars 9 to 21 again
M| R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4.                                      |
\ bar 22, second ending
M| @3O4F @2E32 R4.                                                                          |
\ bars 23 to 58: the first episode and the theme again
M| R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4.  |
M| R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4. R4                                   |
\ the last bar
M| R32                                                                                      |

: FUR-ELISE ( -- )
   PIANO PLAY-TUNE
   WAIT-MUSIC 1500 MS ;                                 \ the last chord dies away

CR .( Fuer Elise - Ludwig van Beethoven)
FUR-ELISE
MSX-SOUND CR
