\ Demo setup for the Apple II audio model (include/apple2-audio.fs). Run from the repository root.
S" include/apple2-audio.fs" REQUIRED
\ The Mockingboard manual's sequence on the 6522 at base: address, LATCH, inactive, data, WRITE, inactive.
: A2-DEMO-PSG! { value reg base tick -- }
  reg base 1+ tick A2-EVENT! 7 base tick A2-EVENT! 4 base tick A2-EVENT!
  value base 1+ tick A2-EVENT! 6 base tick A2-EVENT! 4 base tick A2-EVENT! ;
\ Ports to outputs; ORB is 0, so this also resets the AY until the 4.
: A2-DEMO-INIT { base -- } 255 base 3 + 0 A2-EVENT! 7 base 2 + 0 A2-EVENT! 4 base 0 A2-EVENT! ;
\ Toggles the speaker count times, every period cycles, from cycle start.
: A2-DEMO-CLICKS { count period start -- } count 0 ?DO I period * start + A2-TOGGLE-EVENT! LOOP ;
\ A Mockingboard in slot 4: a major chord on the first AY (left), a slow envelope bass and
\ noise on the second (right), and one second of a 440 Hz speaker tone after half a second.
: A2-DEMO-SETUP ( -- )
  4 A2-CARD! A2-RESET 50176 A2-DEMO-INIT 50304 A2-DEMO-INIT
  244 0 50176 1 A2-DEMO-PSG! 0 1 50176 1 A2-DEMO-PSG! 194 2 50176 1 A2-DEMO-PSG! 0 3 50176 1 A2-DEMO-PSG!
  163 4 50176 1 A2-DEMO-PSG! 0 5 50176 1 A2-DEMO-PSG! 56 7 50176 1 A2-DEMO-PSG!
  11 8 50176 1 A2-DEMO-PSG! 10 9 50176 1 A2-DEMO-PSG! 10 10 50176 1 A2-DEMO-PSG!
  208 0 50304 2 A2-DEMO-PSG! 3 1 50304 2 A2-DEMO-PSG! 20 6 50304 2 A2-DEMO-PSG! 46 7 50304 2 A2-DEMO-PSG!
  16 8 50304 2 A2-DEMO-PSG! 6 9 50304 2 A2-DEMO-PSG! 0 11 50304 2 A2-DEMO-PSG! 16 12 50304 2 A2-DEMO-PSG!
  14 13 50304 2 A2-DEMO-PSG! 880 1160 510242 A2-DEMO-CLICKS ;
\ No card: the speaker alone, 900 toggles 1160 cycles apart (about 440 Hz for one second).
: A2-SPEAKER-SETUP ( -- ) 0 A2-CARD! A2-RESET 900 1160 0 A2-DEMO-CLICKS ;
