\ Manual native-window keyboard check (#985). Run from the repository root:
\   .work/linux-native/current/bin/sigma tests/scripts/check-window-keys.fs < /dev/null
\ Or build Linux with `zig build -Dx11=true` and use zig-out/bin/sigma.
\ Press arrows, Home/End, Page Up/Down, Insert/Delete, F1/F2/F12.
\ Hold A for two seconds, release it, then hold A while switching to a different
\ window (not the launching terminal), release it there and return. Focus loss
\ should log "held A 0" after "held A -1"; the screen should show Held A: 0.
\ Redirect stdin from /dev/null so terminal keys cannot contaminate the result.
\ Escape ends the check. Ctrl+C in the window logs throw -28 and does not end it.
\ A key event code is logged; repeated codes are not by themselves proof of
\ physical repeat. Correlate the log with the operator's report. processed-ms is
\ the VM processing time, not the original event timestamp.

REQUIRE-GRAPHICS ALSO GRAPHICS
DECIMAL
VARIABLE KEY-LAST
VARIABLE A-HELD
VARIABLE KEY-DONE

: KEY-NUMBER { n x y -- }
   n S>D DUP >R DABS <# #S R> SIGN #> x y TEXT ;
: KEY-LOG ( -- )
   SPACE ." processed-ms " UTIME DROP 1000 / . CR STDOUT FLUSH-FILE DROP ;
: KEY-READ ( -- n )
   ['] INKEY CATCH ?DUP IF ." throw " . KEY-LOG -1 THEN ;
: KEY-DRAIN ( -- )
   BEGIN KEY-READ DUP -1 <> WHILE
      DUP KEY-LAST ! DUP ." key " . KEY-LOG
      27 = IF TRUE KEY-DONE ! THEN
   REPEAT DROP ;
: KEY-STATE ( -- )
   97 KEY-HELD? 65 KEY-HELD? OR DUP A-HELD @ <> IF
      DUP A-HELD ! ." held A " . KEY-LOG
   ELSE DROP THEN ;
: KEY-STATE-SAFE ( -- )
   ['] KEY-STATE CATCH ?DUP IF ." throw " . KEY-LOG THEN ;
: KEY-DRAW ( -- )
   CLS $FFFFFF COLOR!
   S" Linux keyboard check - Escape ends" 10 10 TEXT
   S" Arrows, Home/End, PgUp/PgDn, Ins/Del" 10 40 TEXT
   S" F1 F2 F12; hold A for 2 seconds" 10 70 TEXT
   S" Hold A, switch windows, release, return" 10 100 TEXT
   S" Last code:" 10 150 TEXT KEY-LAST @ 210 150 KEY-NUMBER
   S" Held A:" 10 190 TEXT A-HELD @ ABS 210 190 KEY-NUMBER
   SHOW ;
: WINDOW-KEY-CHECK ( -- )
   DISPLAY-WINDOW 720 240 GFX-INIT 1080 360 WINDOW-SIZE 2 TEXT-SCALE
   0 KEY-LAST ! 0 A-HELD ! FALSE KEY-DONE !
   ." native keyboard check started" KEY-LOG
   BEGIN
      KEY-DRAW KEY-DRAIN KEY-STATE-SAFE
      KEY-DONE @ 0= IF 100 MS THEN
      KEY-DONE @
   UNTIL
   ." native keyboard check finished" KEY-LOG BYE ;

WINDOW-KEY-CHECK
