\ Demo setup for the ZX Spectrum audio model (include/zx-spectrum-audio.fs). Run from the repository root.
S" include/zx-spectrum-audio.fs" REQUIRED
: ZX-DEMO-BEEPER { count -- }
  count 0 ?DO I 1 AND IF 0 ELSE 16 THEN 254 I 8000 * ZX-OUT-EVENT! LOOP ;
: ZX-DEMO-SETUP ( -- )
  1 ZX-RESET
  28 0 0 ZX-AY! 1 1 0 ZX-AY! 227 2 0 ZX-AY! 1 3 0 ZX-AY!
  82 4 0 ZX-AY! 2 5 0 ZX-AY! 9 6 0 ZX-AY! 48 7 0 ZX-AY!
  12 8 0 ZX-AY! 10 9 0 ZX-AY! 16 10 0 ZX-AY!
  100 11 0 ZX-AY! 0 12 0 ZX-AY! 14 13 0 ZX-AY! 512 ZX-DEMO-BEEPER ;
: ZX-BEEPER-SETUP ( -- ) 0 ZX-RESET 900 ZX-DEMO-BEEPER ;
