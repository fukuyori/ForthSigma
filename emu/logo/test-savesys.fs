\ Child fixture for test-logo.fs. Build and run from the repository root.
INCLUDE emu/logo/logo.fs
ALSO GRAPHICS ALSO TURTLE ALSO LOGO
: LG@SAVED-SQUARE ( -- )
   S" emu/logo/examples/square.lg" LOGO-HEADLESS
   TT@W @ 9 <> TT@H @ 9 <> OR IF -1 THROW THEN
   9 0 DO 9 0 DO
      I 4 7 WITHIN J 2 5 WITHIN AND
      I 4 = I 6 = OR J 2 = OR J 4 = OR AND
      IF $FFFFFF ELSE 0 THEN
      TURTLE-IMAGE I J GFX-PIXEL <> IF -1 THROW THEN
   LOOP LOOP
   TURTLE-DISPOSE
   ." SAVESYS square pixels OK" CR
;
' LG@SAVED-SQUARE APP-ENTRY!
SAVESYS .work/1478/HEADLESS.EXE
BYE
