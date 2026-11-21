\ The Amiga's sound (tque 1190): Paula on a PAL machine, four voices, samples at
\ 3546895 / period a second (periods 123 and up, the PAL machine's shortest), 65 volume
\ steps, the samples played as steps, through the A500's low-pass (one pole, about
\ 4.9 kHz); AMIGA-FILTER turns on the LED filter (about 3.3 kHz) after it, which MOD's
\ E0x also uses. Voices 1 and 4 are on the left and 2 and 3 on the right, as Paula's are
\ (VOICE-PAN); the voices after them, for a raised VOICE-LIMIT, stay in the middle.
\
\   REQUIRE amiga-sound.fs  AMIGA-SOUND  S" drum.wav" 0 LOAD-SAMPLE  0 SAMPLE-INSTRUMENT
S" ./chip-sound.fs" REQUIRED
REQUIRE-AUDIO
GET-CURRENT ALSO AUDIO DEFINITIONS
DECIMAL

3546895000 CONSTANT AMIGA-CLOCK
CREATE AMIGA-LEVELS
  0 , 1024 , 2048 , 3072 , 4096 , 5120 , 6144 , 7168 , 8192 , 9216 , 10240 , 11264 , 12288 ,
  13312 , 14336 , 15360 , 16384 , 17408 , 18432 , 19456 , 20480 , 21504 , 22528 , 23552 , 24576 , 25600 ,
  26624 , 27648 , 28672 , 29696 , 30720 , 31744 , 32768 , 33791 , 34815 , 35839 , 36863 , 37887 , 38911 ,
  39935 , 40959 , 41983 , 43007 , 44031 , 45055 , 46079 , 47103 , 48127 , 49151 , 50175 , 51199 , 52223 ,
  53247 , 54271 , 55295 , 56319 , 57343 , 58367 , 59391 , 60415 , 61439 , 62463 , 63487 , 64511 , 65535 ,
\ MML's V as Paula's volume V x 64 / 15, rounded.
CREATE (AMIGA-V)
  0 , 4096 , 9216 , 13312 , 17408 , 21504 , 26624 , 30720 ,
  34815 , 38911 , 44031 , 48127 , 52223 , 56319 , 61439 , 65535 ,

: AMIGA-STEPS ( -- )
  AMIGA-CLOCK 1 0 123 65535 PITCH-PERIOD  AMIGA-LEVELS 65 VOLUME-STEPS  0 DUTY-STEPS
  0 INTERPOLATION  0 NOISE-RATE  15 1 NOISE-LFSR  (AMIGA-V) 16 V-STEPS ;
\ The LED filter, MASTER-FILTER's second stage, after the A500's low-pass (the first).
: AMIGA-FILTER ( flag -- )   IF 1 ELSE 0 THEN 3275 2 MASTER-FILTER ;
: AMIGA-SOUND ( -- )
  (STANDARD-GLOBALS)  4 VOICE-LIMIT  11 4900 1 MASTER-FILTER  FALSE AMIGA-FILTER
  1 3275 MOD-FILTER
  65535 0 1 VOICE-PAN  0 65535 2 VOICE-PAN  0 65535 3 VOICE-PAN  65535 0 4 VOICE-PAN
  ['] AMIGA-STEPS (EACH-INSTRUMENT) ;
PREVIOUS SET-CURRENT
