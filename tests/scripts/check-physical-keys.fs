\ Manual physical-key check for tque1082/1087. Run after zig build:
\   zig-out/bin/sigma tests/scripts/check-physical-keys.fs
\ Click the native window. Press/release A, both Shift keys and each side alone,
\ left/right Ctrl/Alt/GUI, arrows, keypad Enter and available international keys.
\ Compare positions across JIS/US layouts and try IME on/off. Hold a key: only the
\ first press is an edge. Alt+Tab/Command+Tab must release every held key.
\ The terminal prints HID usage, kind (1 press/2 release/3 resync) and modifiers.
\ Q or closing the window finishes. Ctrl+C retains its existing interrupt meaning.
REQUIRE-GRAPHICS ALSO GRAPHICS
DECIMAL
VARIABLE PH-DONE
CREATE PH-BITS 32 ALLOT
: PH-BOOL ( flag -- ) 0<> 1 AND . ;
: PH-MODS ( -- )
   ." ctrl L/R=" SC-LCTRL SCAN-HELD? PH-BOOL SC-RCTRL SCAN-HELD? PH-BOOL
   ." shift L/R=" SC-LSHIFT SCAN-HELD? PH-BOOL SC-RSHIFT SCAN-HELD? PH-BOOL
   ." alt L/R=" SC-LALT SCAN-HELD? PH-BOOL SC-RALT SCAN-HELD? PH-BOOL
   ." gui L/R=" SC-LGUI SCAN-HELD? PH-BOOL SC-RGUI SCAN-HELD? PH-BOOL ;
: PH-EDGE { scan kind -- }
   CR ." usage=" scan . ." kind=" kind . PH-MODS CR
   kind SC-RESYNC = IF PH-BITS KEY-RESYNC ." snapshot read; repeat if resync persists" CR THEN
   scan SC-Q = kind SC-PRESS = AND IF TRUE PH-DONE ! THEN ;
: CHECK-PHYSICAL-KEYS ( -- )
   FALSE PH-DONE !
   480 160 GFX-INIT DISPLAY-WINDOW
   CLS 255 255 0 COLOR 0 0 480 160 RECT SHOW
   ." Click the graphics window; Q or close to finish." CR
   ." supported CapsLock/Pause/PrintScreen: "
   SC-CAPSLOCK SCAN-SUPPORTED? PH-BOOL
   SC-PAUSE SCAN-SUPPORTED? PH-BOOL
   SC-PRINTSCREEN SCAN-SUPPORTED? PH-BOOL CR
   BEGIN
      KEY-EVENT IF PH-EDGE THEN
      SCAN-INPUT? 0= IF TRUE PH-DONE ! THEN
      16 MS PH-DONE @
   UNTIL ;
\ Run the checker only after all definitions have compiled.
CHECK-PHYSICAL-KEYS CR ." physical check finished" CR BYE
