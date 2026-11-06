# The Tcl side of FORTH/Sigma's TCL words: the host runs wish with this script, and
# Sigma talks to it through wish's standard input and output.
#
# Sigma sends scripts as "<length>\n<script>", the length in bytes of the UTF-8 script.
# This side answers each with "R <code> <length>\n<result>" (code as catch gives it: 1
# for an error, whose result is the message) and sends, whenever they happen, events
# "E 0 <length>\n<text>" (sigma_event), keys "K 0 <length>\n<codes>" (the codes INKEY
# gives, separated by spaces), releases "U 0 <length>\n<code>" of keys that went down
# (also when the window loses the focus), and the mouse "M 0 <length>\n<x> <y> <buttons>".

wm withdraw .
fconfigure stdin -translation binary -blocking 0
# Standard output does not wait: what Sigma has not read yet stays in Tcl's buffer,
# and this side goes on reading Sigma's scripts, so neither waits for the other.
fconfigure stdout -translation binary -buffering full -blocking 0
set sigma_input ""
# Events, keys pressed, and the mouse are dropped while this many bytes wait for Sigma
# to read them (it reads them only in the TCL words, INKEY, KEY-HELD?, and MOUSE).
# Results are always sent, as Sigma waits for them, and so are the releases of keys,
# few as they are, so that no key stays held.
set sigma_pending_limit [expr {4 * 1024 * 1024}]

proc sigma_send {kind code text} {
    if {$kind ne "R" && $kind ne "U" && [chan pending output stdout] > $::sigma_pending_limit} return
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
    # Sigma closed the pipes: it has ended or stopped this program, and what it has not
    # read is dropped.
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
# WINDOW-SIZE as the last image came with it, and how the shown copy of the image is
# made from it: zoomed by sigma_zoom after taking every sigma_sub-th pixel.
set sigma_size ""
set sigma_image_size ""
set sigma_zoom 1
set sigma_sub 1

# Shows a PNG image given in base64 in a part of the window "." w by h pixels large (0 0:
# the image's size), opening the window the first time; closing the window only hides
# it, until the next image. The image keeps its proportions, as large as fits by a whole
# factor (Tk's photo images zoom only so), in the middle with black around it, also
# when the window is resized.
proc sigma_show {w h data} {
    if {![winfo exists .sigma]} {
        image create photo sigma_image
        image create photo sigma_view
        label .sigma -image sigma_view -borderwidth 0 -highlightthickness 0 -background black
        pack .sigma -expand 1 -fill both
        bind .sigma <Configure> sigma_fit
        bind .sigma <Motion> {sigma_mouse %x %y}
        bind .sigma <ButtonPress> {sigma_button %b 1 %x %y}
        bind .sigma <ButtonRelease> {sigma_button %b 0 %x %y}
        bind . <KeyPress> {sigma_key %K %A %k}
        bind . <KeyRelease> {sigma_key_release %k}
        bind . <FocusOut> {sigma_keys_released}
        wm protocol . WM_DELETE_WINDOW {wm withdraw .}
        wm title . "FORTH/Sigma graphics"
    }
    sigma_image configure -data $data -format png
    set image_size "[image width sigma_image] [image height sigma_image]"
    # The window fits again when WINDOW-SIZE changed, or, without it, the image's size.
    if {"$w $h" ne $::sigma_size || ($w == 0 && $image_size ne $::sigma_image_size)} {
        set ::sigma_size "$w $h"
        if {$w == 0} {
            # The image's own size: the window fits a copy of factor 1.
            sigma_copy 1 1
            wm geometry . {}
        } else {
            wm geometry . ${w}x${h}
        }
        # The window takes its new size before the copy is fitted to it.
        update idletasks
    }
    set ::sigma_image_size $image_size
    sigma_fit
    if {[wm state .] ne "normal"} { wm deiconify . }
}

proc sigma_copy {zoom sub} {
    set ::sigma_zoom $zoom
    set ::sigma_sub $sub
    # A photo image does not shrink by itself: its size is set first.
    set width [expr {([image width sigma_image] + $sub - 1) / $sub * $zoom}]
    set height [expr {([image height sigma_image] + $sub - 1) / $sub * $zoom}]
    sigma_view blank
    sigma_view configure -width $width -height $height
    sigma_view copy sigma_image -subsample $sub $sub -zoom $zoom $zoom
}

# Makes the shown copy as large as fits the label (or, before the window is shown, the
# size asked for).
proc sigma_fit {} {
    set iw [image width sigma_image]
    set ih [image height sigma_image]
    if {$iw == 0 || $ih == 0} return
    set cw [winfo width .sigma]
    set ch [winfo height .sigma]
    if {![winfo ismapped .sigma]} {
        lassign $::sigma_size cw ch
        if {$cw == 0} { set cw $iw; set ch $ih }
    }
    set zoom [expr {min($cw / $iw, $ch / $ih)}]
    set sub 1
    if {$zoom < 1} {
        set zoom 1
        set sub [expr {max(($iw + $cw - 1) / $cw, ($ih + $ch - 1) / $ch)}]
    }
    sigma_copy $zoom $sub
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

# The pixel of the image under a point of the label, where the copy is in the middle.
proc sigma_mouse {x y} {
    set left [expr {([winfo width .sigma] - [image width sigma_view]) / 2}]
    set top [expr {([winfo height .sigma] - [image height sigma_view]) / 2}]
    set x [expr {($x - $left) * $::sigma_sub / $::sigma_zoom}]
    set y [expr {($y - $top) * $::sigma_sub / $::sigma_zoom}]
    sigma_send M 0 "$x $y $::sigma_buttons"
}

# A key pressed: its name, its character, and the keyboard's code of the key, by which
# its release is known (the name and the character may change while it is held, with
# Shift).
proc sigma_key {name char key} {
    if {[info exists ::sigma_keys($name)]} {
        set codes $::sigma_keys($name)
    } else {
        if {$char eq ""} return
        binary scan [encoding convertto utf-8 $char] cu* codes
    }
    # A held key that gives another code: the code it gave before is released.
    if {[info exists ::sigma_down($key)] && $::sigma_down($key) ne $codes} { sigma_key_release $key }
    # A key of one code is held until it goes up (KEY-HELD?).
    if {[llength $codes] == 1} { set ::sigma_down($key) $codes }
    sigma_send K 0 $codes
}

# Releases "U 0 <length>\n<code>" of the keys that went down.
proc sigma_key_release {key} {
    if {![info exists ::sigma_down($key)]} return
    sigma_send U 0 $::sigma_down($key)
    unset ::sigma_down($key)
}

# Keys that go up while the window has not the focus do not tell it.
proc sigma_keys_released {} {
    foreach key [array names ::sigma_down] { sigma_key_release $key }
}
