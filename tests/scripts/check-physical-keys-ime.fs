\ Manual physical-key check with an active IME field (tque1088/1089/1090). Run after
\ zig build, from the repository root:
\   zig-out/bin/sigma tests/scripts/check-physical-keys-ime.fs
\ Click the field in the native window. Every physical edge is printed as HID usage,
\ kind (1 press/2 release/3 resync) and the left/right modifiers, while the field
\ keeps receiving text from the input method. Enter prints the field's text and bytes
\ (a is 61, あ is E3 81 82) and empties it. The Quit button or closing the window
\ ends the check. Ctrl+C in the terminal keeps its existing interrupt meaning.
REQUIRE-GUI  ALSO GRAPHICS ALSO GUI
DECIMAL

CREATE PI-BITS 32 ALLOT
CREATE PI-TEXT 256 ALLOT   VARIABLE PI-LEN   0 PI-LEN !
VARIABLE PI-LINES   0 PI-LINES !
VARIABLE PI-EDGES   0 PI-EDGES !

: PI-BOOL ( flag -- ) 0<> 1 AND 0 .R ;
: PI-HEX ( c-addr u -- )
   BASE @ >R HEX
   OVER + SWAP ?DO I C@ 0 <# # # #> TYPE SPACE LOOP
   R> BASE ! ;
: PI-NAME ( scan -- )
   CASE
      SC-INTERNATIONAL1 OF ." (ro)" ENDOF
      SC-INTERNATIONAL2 OF ." (kana)" ENDOF
      SC-INTERNATIONAL3 OF ." (yen)" ENDOF
      SC-INTERNATIONAL4 OF ." (henkan)" ENDOF
      SC-INTERNATIONAL5 OF ." (muhenkan)" ENDOF
      SC-GRAVE OF ." (grave/zenkaku)" ENDOF
   ENDCASE ;
: PI-MODS ( -- )
   ."  ctrl=" SC-LCTRL SCAN-HELD? PI-BOOL SC-RCTRL SCAN-HELD? PI-BOOL
   ."  shift=" SC-LSHIFT SCAN-HELD? PI-BOOL SC-RSHIFT SCAN-HELD? PI-BOOL
   ."  alt=" SC-LALT SCAN-HELD? PI-BOOL SC-RALT SCAN-HELD? PI-BOOL
   ."  gui=" SC-LGUI SCAN-HELD? PI-BOOL SC-RGUI SCAN-HELD? PI-BOOL ;
: PI-EDGE { scan kind -- }
   1 PI-EDGES +!
   CR ." edge " PI-EDGES @ 0 .R ." : usage=" scan 0 .R ."  kind=" kind 0 .R
   scan PI-NAME PI-MODS
   kind SC-RESYNC = IF PI-BITS KEY-RESYNC ."  snapshot read" THEN ;
: PI-DRAIN ( -- )   BEGIN KEY-EVENT WHILE PI-EDGE REPEAT ;
: PI-REPORT ( -- )
   1 PI-LINES +!
   CR ." text " PI-LINES @ 0 .R ." : " PI-TEXT PI-LEN @ TYPE
   ."  | bytes: " PI-TEXT PI-LEN @ PI-HEX
   0 PI-LEN ! ;
: PI-SUPPORT ( -- )
   CR ." supported ro/kana/yen/henkan/muhenkan/grave: "
   SC-INTERNATIONAL1 SCAN-SUPPORTED? PI-BOOL SC-INTERNATIONAL2 SCAN-SUPPORTED? PI-BOOL
   SC-INTERNATIONAL3 SCAN-SUPPORTED? PI-BOOL SC-INTERNATIONAL4 SCAN-SUPPORTED? PI-BOOL
   SC-INTERNATIONAL5 SCAN-SUPPORTED? PI-BOOL SC-GRAVE SCAN-SUPPORTED? PI-BOOL
   CR ." supported CapsLock/Pause/PrintScreen: "
   SC-CAPSLOCK SCAN-SUPPORTED? PI-BOOL SC-PAUSE SCAN-SUPPORTED? PI-BOOL
   SC-PRINTSCREEN SCAN-SUPPORTED? PI-BOOL CR ;
: PI-JAPANESE-FONT ( -- )
   S" Noto Sans CJK JP" 16 ['] GFX-FONT-SYSTEM CATCH IF 2DROP DROP THEN DROP ;
: CHECK-PHYSICAL-IME ( -- )
   480 160 GFX-INIT DISPLAY-WINDOW PI-JAPANESE-FONT
   FALSE
   BEGIN
      GUI-BACKGROUND GUI-COLOR@ GFX-CLS
      GUI-BEGIN
      S" Type here (IME on/off), press Enter:" 10 10 GUI-LABEL
      PI-TEXT 255 PI-LEN 10 40 460 GUI-FIELD IF PI-REPORT THEN
      S" Physical edges are printed in the terminal." 10 80 GUI-LABEL
      S" Quit" 10 120 GUI-BUTTON
      GUI-END SHOW
      SWAP 0= IF PI-SUPPORT THEN TRUE SWAP
      PI-DRAIN
      SCAN-INPUT? 0= OR
      16 FRAME
   UNTIL DROP
   PI-DRAIN
   CR ." edges " PI-EDGES @ . ." lines " PI-LINES @ . CR ;
CHECK-PHYSICAL-IME ." physical IME check finished" CR BYE
