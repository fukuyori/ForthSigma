\ Generic gamepad inspector, no graphics window required.
\ sigma.exe "include examples/gamepad.fs"
\ SDL3.dll beside sigma.exe on Windows, or an absolute SIGMA_SDL3 path.
\ For mapping strings use the GUID shown here and GAMEPAD-MAP. Raw pad button
\ and axis numbers vary by model. HELP GAMEPAD-BUTTONS describes mapped layout.
REQUIRE-GRAPHICS ALSO GRAPHICS
: .PAD ( index -- )
   { index } ." Pad " index . ." ID " index GAMEPAD-ID .
   PAD 128 index GAMEPAD-NAME PAD SWAP TYPE CR
   ." GUID " PAD 32 index GAMEPAD-GUID PAD SWAP TYPE
   ."  mapped=" index GAMEPAD-MAPPED? . CR
   ." buttons=" index GAMEPAD-BUTTONS .
   ."  axes=" index GAMEPAD-AXES 0 ?DO I index GAMEPAD-AXIS . LOOP
   ."  hats=" index GAMEPAD-HATS 0 ?DO I index GAMEPAD-HAT . LOOP CR ;
: .GAMEPADS ( -- )
   GAMEPAD-POLL DUP -1 = IF DROP ." SDL3 unavailable; see HELP GAMEPAD-POLL" CR EXIT THEN
   DUP 0= IF ." No gamepads connected" CR THEN
   0 ?DO I .PAD LOOP ;
.GAMEPADS
\ Run .GAMEPADS again to sample current controls, connection or disconnection.
