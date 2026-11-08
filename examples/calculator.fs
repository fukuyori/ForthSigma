\ A calculator in a Tk window: the window is Tcl/Tk's, and the arithmetic is Forth's.
\ It needs a build with graphics and Tcl/Tk (wish); see "Tcl/Tk" in the user manual.
\
\   sigma.exe < examples/calculator.fs        (or INCLUDE examples/calculator.fs)
\
\ The buttons and the keyboard (0-9 + - * / = Enter, Esc or C to clear, BackSpace)
\ send events "k<key>" with sigma_event; closing the window sends "quit". Numbers are
\ whole numbers of one cell; / rounds toward zero, as a calculator does, and a result
\ too large for a cell or a division by zero shows Error.

REQUIRE-GRAPHICS  ALSO GRAPHICS

\ ---- The Tcl script to send, built in a buffer -------------------------------------

CREATE SCRIPT 256 CHARS ALLOT
VARIABLE SCRIPT#
: SCRIPT{ ( -- )   0 SCRIPT# ! ;
: +S ( c-addr u -- )   TUCK SCRIPT SCRIPT# @ CHARS + SWAP CMOVE  SCRIPT# +! ;
\ The digits come from the absolute value as a double, which holds that of the smallest
\ cell too.
: +N ( n -- )   DUP S>D DABS <# #S ROT SIGN #> +S ;
: }TCL ( -- )   SCRIPT SCRIPT# @ TCL ;

\ ---- The window -------------------------------------------------------------------

: BUTTON ( c-addr u -- )   \ "name text key row column span", for calc_button
   SCRIPT{ S" calc_button " +S +S }TCL ;

: WINDOW ( -- )
   \ The window stays hidden until it has all its widgets: on macOS, a window shown
   \ while it grows can be left partly undrawn.
   S" catch {destroy .calc}; toplevel .calc; wm withdraw .calc; wm title .calc {FORTH/Sigma Calculator}" TCL
   S" wm resizable .calc 0 0; wm protocol .calc WM_DELETE_WINDOW {sigma_event quit}" TCL
   S" label .calc.d -text 0 -anchor e -width 16 -font {Courier 20 bold} -relief sunken -bg white -fg black" TCL
   S" grid .calc.d -row 0 -column 0 -columnspan 4 -sticky ew -padx 4 -pady 4" TCL
   S" proc calc_button {name text key row column span} { button .calc.$name -text $text -font {Helvetica 14} -width 3 -command [list sigma_event k$key]; grid .calc.$name -row $row -column $column -columnspan $span -sticky nsew -padx 2 -pady 2 }" TCL
   S" clear C C 1 0 1" BUTTON  S" sign ± N 1 1 1" BUTTON
   S" back ← B 1 2 1" BUTTON   S" div ÷ / 1 3 1" BUTTON
   S" n7 7 7 2 0 1" BUTTON  S" n8 8 8 2 1 1" BUTTON  S" n9 9 9 2 2 1" BUTTON  S" mul × * 2 3 1" BUTTON
   S" n4 4 4 3 0 1" BUTTON  S" n5 5 5 3 1 1" BUTTON  S" n6 6 6 3 2 1" BUTTON  S" sub − - 3 3 1" BUTTON
   S" n1 1 1 4 0 1" BUTTON  S" n2 2 2 4 1 1" BUTTON  S" n3 3 3 4 2 1" BUTTON  S" add + + 4 3 1" BUTTON
   S" n0 0 0 5 0 3" BUTTON  S" equal = = 5 3 1" BUTTON
   \ The keyboard: %A is the character typed; Enter, Esc, and BackSpace send the keys
   \ of their buttons.
   S" bind .calc <KeyPress> {sigma_event k%A}; bind .calc <Return> {sigma_event k=}; bind .calc <KP_Enter> {sigma_event k=}" TCL
   S" bind .calc <Escape> {sigma_event kC}; bind .calc <BackSpace> {sigma_event kB}" TCL
   S" update idletasks; wm deiconify .calc; focus -force .calc" TCL ;

: SHOW-NUMBER ( n -- )   SCRIPT{ S" .calc.d configure -text " +S +N }TCL ;
: SHOW-ERROR ( -- )   S" .calc.d configure -text Error" TCL ;

\ ---- The calculator ----------------------------------------------------------------

VARIABLE ACC        \ the result so far
VARIABLE ENTRY      \ the number being typed
VARIABLE OP         \ the operation waiting for its second number, or 0
VARIABLE TYPING     \ true while a number is being typed
VARIABLE DONE

: CLEAR ( -- )   0 ACC !  0 ENTRY !  0 OP !  FALSE TYPING !  0 SHOW-NUMBER ;
: FAIL ( -- )   CLEAR SHOW-ERROR ;

\ A double that fits in a cell, as that cell; or Error (THROW 1, caught below).
: >CELL ( d -- n )   OVER 0< OVER <> IF 2DROP 1 THROW THEN DROP ;

: APPLY ( n1 n2 op -- n3 )
   CASE
      [CHAR] + OF  >R S>D R> S>D D+ >CELL  ENDOF
      [CHAR] - OF  >R S>D R> S>D D- >CELL  ENDOF
      [CHAR] * OF  M* >CELL  ENDOF
      [CHAR] / OF  DUP 0= IF 1 THROW THEN  >R S>D R> SM/REM NIP  ENDOF
      ROT DROP     \ no operation waiting: the second number
   ENDCASE ;

: DIGIT ( n -- )
   TYPING @ IF
      ENTRY @ ABS 100000000000000000 < IF  ENTRY @ 10 *  ENTRY @ 0< IF SWAP - ELSE + THEN  ENTRY !  ELSE DROP THEN
   ELSE  ENTRY !  TRUE TYPING !  THEN
   ENTRY @ SHOW-NUMBER ;

\ Ends the number being typed: the waiting operation is done with it.
: RESULT ( -- )
   TYPING @ IF  ACC @ ENTRY @ OP @ APPLY ACC !  FALSE TYPING !  THEN
   ACC @ SHOW-NUMBER ;

: OPERATION ( char -- )   RESULT  OP ! ;
: EQUALS ( -- )   RESULT  0 OP ! ;
: BACK ( -- )   TYPING @ IF  ENTRY @ S>D 10 SM/REM NIP ENTRY !  ENTRY @ SHOW-NUMBER  THEN ;
\ The sign changed as a double, so that the smallest cell, whose opposite does not fit,
\ is Error.
: OPPOSITE ( n -- -n )   S>D DNEGATE >CELL ;
: CHANGE-SIGN ( -- )
   TYPING @ IF  ENTRY @ OPPOSITE ENTRY !  ENTRY @ SHOW-NUMBER
   ELSE  ACC @ OPPOSITE ACC !  ACC @ SHOW-NUMBER  THEN ;

: PRESS ( char -- )
   DUP [CHAR] 0 [CHAR] 9 1+ WITHIN IF  [CHAR] 0 - DIGIT EXIT  THEN
   CASE
      [CHAR] + OF  [CHAR] + OPERATION  ENDOF
      [CHAR] - OF  [CHAR] - OPERATION  ENDOF
      [CHAR] * OF  [CHAR] * OPERATION  ENDOF
      [CHAR] / OF  [CHAR] / OPERATION  ENDOF
      [CHAR] = OF  EQUALS  ENDOF
      [CHAR] C OF  CLEAR  ENDOF
      [CHAR] c OF  CLEAR  ENDOF
      [CHAR] B OF  BACK  ENDOF
      [CHAR] N OF  CHANGE-SIGN  ENDOF
   ENDCASE ;

\ An event from the window: "k<key>" or "quit".
: EVENT ( c-addr u -- )
   2DUP S" quit" COMPARE 0= IF  2DROP TRUE DONE !  EXIT  THEN
   2 = IF  DUP C@ [CHAR] k = IF  CHAR+ C@  ['] PRESS CATCH IF DROP FAIL THEN  EXIT  THEN  THEN
   DROP ;

: CALCULATOR ( -- )
   FALSE DONE !  WINDOW  CLEAR
   BEGIN
      TCL-EVENT IF EVENT ELSE 10 MS THEN
   DONE @ UNTIL
   S" destroy .calc" TCL ;

CALCULATOR
