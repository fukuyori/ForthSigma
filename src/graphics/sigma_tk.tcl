# The Tcl side of FORTH/Sigma's TCL words: the host runs wish with this script, and
# Sigma talks to it through wish's standard input and output.
#
# Sigma sends scripts as "<length>\n<script>", the length in bytes of the UTF-8 script.
# This side answers each with "R <code> <length>\n<result>" (code as catch gives it: 1
# for an error, whose result is the message) and sends, whenever they happen, events
# "E 0 <length>\n<text>" (sigma_event), keys "K 0 <length>\n<codes>" (the codes INKEY
# gives, separated by spaces), and the mouse "M 0 <length>\n<x> <y> <buttons>".

wm withdraw .
fconfigure stdin -translation binary -blocking 0
# Standard output does not wait: what Sigma has not read yet stays in Tcl's buffer,
# and this side goes on reading Sigma's scripts, so neither waits for the other.
fconfigure stdout -translation binary -buffering full -blocking 0
set sigma_input ""

proc sigma_send {kind code text} {
    set data [encoding convertto utf-8 $text]
    puts -nonewline stdout "$kind $code [string length $data]\n$data"
    flush stdout
}

# For Tk widgets' commands: TCL-EVENT gives the text to Forth.
proc sigma_event {text} {
    sigma_send E 0 $text
}

proc sigma_read {} {
    global sigma_input
    append sigma_input [read stdin]
    while 1 {
        set newline [string first "\n" $sigma_input]
        if {$newline < 0} break
        set length [string range $sigma_input 0 [expr {$newline - 1}]]
        if {![string is integer -strict $length]} { exit 1 }
        set end [expr {$newline + $length}]
        if {[string length $sigma_input] <= $end} break
        set script [encoding convertfrom utf-8 [string range $sigma_input [expr {$newline + 1}] $end]]
        set sigma_input [string range $sigma_input [expr {$end + 1}] end]
        set code [catch {uplevel #0 $script} result]
        sigma_send R $code $result
    }
    # Sigma closed the pipe: it has ended or stopped this program.
    if {[eof stdin]} { exit 0 }
}
fileevent stdin readable sigma_read

# ---- DISPLAY-TK: the image in the window "." ----------------------------------------

array set sigma_keys {
    Up 256 Down 257 Left 258 Right 259 Home 260 End 261 Prior 262 Next 263
    Insert 264 Delete 265 F1 266 F2 267 F3 268 F4 269 F5 270 F6 271 F7 272 F8 273
    F9 274 F10 275 F11 276 F12 277
}
set sigma_buttons 0

# Shows a PNG image given in base64, opening the window the first time; closing the
# window only hides it, until the next image.
proc sigma_show {data} {
    if {![winfo exists .sigma]} {
        image create photo sigma_image
        label .sigma -image sigma_image -borderwidth 0 -highlightthickness 0
        pack .sigma
        bind .sigma <Motion> {sigma_mouse %x %y}
        bind .sigma <ButtonPress> {sigma_button %b 1 %x %y}
        bind .sigma <ButtonRelease> {sigma_button %b 0 %x %y}
        bind . <KeyPress> {sigma_key %K %A}
        wm protocol . WM_DELETE_WINDOW {wm withdraw .}
        wm title . "FORTH/Sigma graphics"
    }
    sigma_image configure -data $data -format png
    if {[wm state .] ne "normal"} { wm deiconify . }
}

proc sigma_button {button down x y} {
    global sigma_buttons
    # 1 left, 2 right, 4 middle, as MOUSE gives them.
    switch -- $button {
        1 { set bit 1 }
        2 { set bit 4 }
        3 { set bit 2 }
        default { return }
    }
    if {$down} {
        set sigma_buttons [expr {$sigma_buttons | $bit}]
    } else {
        set sigma_buttons [expr {$sigma_buttons & ~$bit}]
    }
    sigma_mouse $x $y
}

proc sigma_mouse {x y} {
    sigma_send M 0 "$x $y $::sigma_buttons"
}

proc sigma_key {name char} {
    if {[info exists ::sigma_keys($name)]} {
        sigma_send K 0 $::sigma_keys($name)
        return
    }
    if {$char eq ""} return
    binary scan [encoding convertto utf-8 $char] cu* codes
    sigma_send K 0 $codes
}
