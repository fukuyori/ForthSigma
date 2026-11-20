\ Demo setup for the Amiga Paula model (include/paula.fs). Run from the repository root.
S" include/paula.fs" REQUIRED
: PA-DEMO-MEMORY ( -- ) 1024 0 DO I 37 * 11 + 255 AND I PA-MEM! LOOP ;
: PA-DEMO-SETUP ( -- )
  PA-RESET 4 0 DO
    I 128 * I 16 * 162 + 0 PA-WRITE 32 I 16 * 164 + 0 PA-WRITE
    I 107 * 214 + I 16 * 166 + 0 PA-WRITE 32 I 16 * 168 + 0 PA-WRITE
  LOOP 33295 150 0 PA-WRITE ;
