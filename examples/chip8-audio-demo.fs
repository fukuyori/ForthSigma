\ Demo setup for the CHIP-8 audio model (include/chip8-audio.fs). Run from the repository root.
S" include/chip8-audio.fs" REQUIRED
CREATE C8-DEMO-PATTERN 0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C,
  255 C, 255 C, 255 C, 255 C, 255 C, 255 C, 255 C, 255 C,
: C8-DEMO-SETUP ( -- ) C8-RESET 255 0 C8-TIMER! ;
: C8-XO-DEMO-SETUP ( -- )
  C8-RESET 1 0 C8-MODE! C8-DEMO-PATTERN 0 C8-PATTERN!
  247 0 C8-PITCH! 255 0 C8-TIMER! ;
