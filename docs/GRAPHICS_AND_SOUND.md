# FORTH/Σ Graphics and Sound Manual

Japanese version: [GRAPHICS_AND_SOUND.ja.md](GRAPHICS_AND_SOUND.ja.md). This English version is the primary one.

The graphics and the sound of Sigma are extensions of this port: the FORTH/Σ of the magazine has neither. This manual describes them: drawing, text, Tcl/Tk, keys, the mouse, and animation (`REQUIRE-GRAPHICS`), and music, sound chips, recorded sound, and modules (`REQUIRE-AUDIO`). For starting Sigma, the language, and the other words, see the [user manual](USER_MANUAL.md); for where `SHOW` shows the image and with how many colors, see the [graphics modes manual](GRAPHICS_MODES.md).

## Graphics

Sigma draws on one image in memory and saves it as a PPM, BMP, or PNG file. The graphics words are not in the dictionary at start-up: `REQUIRE-GRAPHICS` adds the `GRAPHICS` vocabulary, with the `GFX-` words and the graphics library written in Forth (`src/graphics/graphics.fs` and, with the floating-point words, `src/graphics/graphics_float.fs`, built into the program), the first time it runs; later it does nothing. It does not change the search order, so make the words visible with `ALSO GRAPHICS` (or `GRAPHICS`). Where `SHOW` shows the image and with how many colors are summed up in the [graphics modes manual](GRAPHICS_MODES.md).

```forth
REQUIRE-GRAPHICS
ALSO GRAPHICS
320 200 GFX-INIT                  \ a black image of 320 by 200 pixels
255 0 0 COLOR                     \ the current color: red
10 10 300 190 LINE
0 255 0 COLOR
160 100 50 CIRCLE
0 0 255 COLOR
20 120 80 50 FILL-RECT            \ 80 by 50 pixels from 20 120
S" picture.bmp" SAVE-BMP
PREVIOUS
```

Coordinates start at 0 0 in the top left corner, and everything drawn outside the image is cut off; drawing far outside costs no more than drawing inside. The drawing words use the current color, which `COLOR` sets and which starts white. A color as one cell is `$RRGGBB` (the bits above the low 24 are ignored), and every pixel is opaque.

| Word | Stack | Description |
| --- | --- | --- |
| `REQUIRE-GRAPHICS` | ( -- ) | Load the graphics words, the first time only. It is a parsing word (like `TO`) and cannot be used inside a definition. The library is read in decimal whatever `BASE` is, and `BASE` stays as it was. |
| `RGB` | ( r g b -- rgb ) | The color `$RRGGBB` of red, green, and blue, each 0 to 255 (only the low 8 bits are used). |
| `COLOR` | ( r g b -- ) | Set the current color. |
| `COLOR!`, `COLOR@` | ( rgb -- ), ( -- rgb ) | Set and get the current color as `$RRGGBB`. |
| `PSET` | ( x y -- ) | Set one pixel. |
| `CLS` | ( -- ) | Make the whole image black. |
| `LINE` | ( x1 y1 x2 y2 -- ) | A line between two points, both included (Bresenham's algorithm). |
| `RECT` | ( x y w h -- ) | The outline of a w by h rectangle whose top left corner is x y. Nothing when w or h is 0 or less. |
| `FILL-RECT` | ( x y w h -- ) | A filled w by h rectangle. |
| `CIRCLE` | ( x y r -- ) | A circle of radius r around x y, with the pixels of the midpoint circle algorithm. Nothing when r is less than 0; one pixel when r is 0. |
| `FILL-CIRCLE` | ( x y r -- ) | A filled circle; it covers every pixel of `CIRCLE` with the same arguments. |
| `PAINT` | ( x y -- ) | Fill the area around x y that has the color of x y (pixels joined left, right, up, or down) with the current color. Nothing outside the image or when the area has the current color already. |
| `SAVE-PPM`, `SAVE-BMP`, `SAVE-PNG` | ( c-addr u -- ) | Write the image to a new file as a binary PPM (P6), a 24-bit BMP, or a PNG, and `THROW` the error of the file operation if there is one. The PNG has 8-bit red, green, and blue and is not compressed, so it is about as large as the BMP; any program that reads PNG files reads it. |
| `SHOW` | ( -- ) | Show the image: in a window when the host has one (Windows), else in the Tk window on a desktop when `wish` starts (Linux, macOS; see the [graphics modes](GRAPHICS_MODES.md)), else on the terminal; or where `DISPLAY-TERMINAL`, `DISPLAY-WINDOW`, or `DISPLAY-TK` said. |
| `DISPLAY-TERMINAL`, `DISPLAY-WINDOW` | ( -- ) | Make `SHOW` use the terminal, or the window. `DISPLAY-WINDOW` gives `HOST FUNCTION UNAVAILABLE !` when the host has no window. |
| `WINDOW-SIZE` | ( w h -- ) | From the next `SHOW`, show the image in the window (and in the Tk window of `DISPLAY-TK`) in an area w by h pixels large, each side 1 to 8192; 0 0 (the default) for the image's own size. The image keeps its proportions, as large as fits, in the middle with black around it; for example `160 120 GFX-INIT 640 480 WINDOW-SIZE` shows each pixel as 4 by 4. It does not change the image, nor the terminal. |
| `TERMINAL-BLOCKS`, `TERMINAL-SIXEL` | ( -- ) | Show the image on the terminal with half block characters (the default), or as Sixel graphics. |
| `DISPLAY-COLORS` | ( n -- ) | Make `SHOW` use full color (0, the default), or 2, 16, or 256 colors, for terminals that show fewer colors or for the look of older computers. 2 is black and white by brightness, 16 the ANSI colors (escapes 30 to 37 and 90 to 97; the nearest is chosen as xterm shows them by default, and other terminals may show them differently), 256 xterm's 6 × 6 × 6 cube and 24 grays (`ESC [ 38 ; 5 ; n m`). Sixel and the window use the same colors. The image keeps its colors, so files are saved in full color. Other values give `NUMBER ERROR !`. |
| `DITHER` | ( flag -- ) | With fewer colors, mix them in a 4 × 4 Bayer pattern (true) instead of taking the nearest (false, the default). The pattern stays in place, so animation does not flicker. |
| `GFX-INIT` | ( w h -- ) | Make a new black image. Each side is 1 to 8192 pixels and the image at most 64 MiB (4 bytes a pixel, so 4096 by 4096 at most for a square). The previous image stays when the new one cannot be made. |
| `GFX-WIDTH`, `GFX-HEIGHT` | ( -- n ) | The size of the image, 0 before `GFX-INIT`. |
| `GFX-PSET` | ( x y rgb -- ) | Set one pixel to the color rgb. |
| `GFX-PGET` | ( x y -- rgb ) | The color of one pixel, -1 outside the image. |
| `GFX-HLINE` | ( x1 x2 y rgb -- ) | A horizontal line from x1 to x2, both included. |
| `GFX-CLS` | ( rgb -- ) | Fill the whole image with the color rgb. |
| `GFX-SAVE-PPM`, `GFX-SAVE-BMP`, `GFX-SAVE-PNG` | ( c-addr u -- ior ) | As `SAVE-PPM`, `SAVE-BMP`, and `SAVE-PNG`, but return ior (0 or the error) instead. They also work in a build with `-Dfiles=false`. |
| `GFX-SHOW-BLOCKS`, `GFX-SHOW-SIXEL`, `GFX-SHOW-WINDOW` | ( -- ) | Show the image on the terminal with half blocks, as Sixel, or in the window. |
| `GFX-WINDOW?` | ( -- flag ) | True when the host can show the image in a window. |
| `GFX-COLOR-MODE` | ( n flag -- ) | The colors of the `GFX-SHOW-` words, as `DISPLAY-COLORS` and `DITHER` (which `SHOW` passes each time). |

The `GFX-` words are the base the library is written with; the other words are Forth definitions, so `SEE`, `LOCATE`, and `WHERE` show them. So that the arithmetic cannot overflow, coordinates and sizes are first limited to -2^61 .. 2^61 for `LINE`, `RECT`, and `FILL-RECT`, and to -2^30 .. 2^30 for the circles (a circle with a value beyond that is drawn with the value moved to the limit). `PAINT` keeps the rows still to fill in the heap; a very complicated area can need more than the heap has and then gives `CANNOT ALLOCATE MEMORY !` (THROW -524, the area is then partly filled).

Errors: a size outside the limits gives `NUMBER ERROR !`; an image the host cannot allocate gives `OUT OF MEMORY !`; using the image before `GFX-INIT` gives `NO GRAPHICS IMAGE !` (THROW -271); and `REQUIRE-GRAPHICS` in a build with `-Dgraphics=false` gives `GRAPHICS UNAVAILABLE !` (THROW -270). If the library fails to load, everything `REQUIRE-GRAPHICS` added is removed again. `REQUIRE-GRAPHICS` loads the words again after `FORGET` or a `MARKER` has removed the `GRAPHICS` vocabulary or `GFX-INIT`; when only later words were forgotten (such as `FORGET GFX-WIDTH`), it does nothing and they stay removed.

To try a changed copy of the library without rebuilding Sigma, load the built-in one and then include the copy into `GRAPHICS`; its words replace the built-in ones: `REQUIRE-GRAPHICS ALSO GRAPHICS DEFINITIONS DECIMAL INCLUDE src/graphics/graphics.fs`.

On the terminal, each character shows two pixels, one above the other, with 24-bit color escapes, which most terminals understand (Windows Terminal and the Windows console, xterm, GNOME Terminal, and so on). An image larger than the terminal is made smaller to fit, keeping its proportions, and each new pixel has the average color of the pixels it stands for; one line is left for the prompt. When the output is not a terminal (a pipe or a file), 80 columns and 24 rows are assumed. Sixel graphics (`TERMINAL-SIXEL`) show real pixels on terminals that support it, with 216 colors; a terminal without Sixel may show stray characters or nothing. On Windows, the console shows the half blocks with the UTF-8 code page, which Sigma sets while it writes them and then sets back.

On Windows, the window has a thread of its own: while Forth waits for input it can be moved, resized (the image is stretched to fit), and closed, and the keyboard stays with the console. Each `SHOW` draws the current image in it again and fits the window to a new image size, or to the size `WINDOW-SIZE` gave (without it, an image larger than 1600 by 1200 pixels is shown smaller). When the window is resized, the image keeps its proportions in it, with black around it, and `MOUSE` gives the pixel of the image under the mouse. A window that was closed is opened again by the next `SHOW` (an image shown at the very moment the window is being closed may not appear until then). Linux and macOS have no window yet; `SHOW` uses the Tk window there on a desktop with Tcl/Tk, and the terminal otherwise.

The image is not part of the dictionary: `SAVE` and `SAVESYS` keep the graphics words and the words that use them, but not the pixels, so a program makes its image with `GFX-INIT` after it starts. A dictionary keeps the graphics library it loaded: `REQUIRE-GRAPHICS` does not add the words of a newer library to it, so build such a dictionary again from its source to use them.

### Text

`TEXT` draws a string with the current font. At first that is the built-in font: the ASCII characters of Misaki Gothic (美咲ゴシック by Num Kadoma, free to use; see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)), 4 pixels wide and 8 high. `LOAD-FONT` reads a BDF font file instead, on every system, and `SYSTEM-FONT` uses a font installed in the system by its name, on Windows. The string is read as UTF-8; a character the font does not have is drawn as one `?` (or not at all when the font has no `?` either), and so is each byte that is not UTF-8. Control characters are not drawn.

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
160 40 GFX-INIT
255 255 0 COLOR  S" Hello, Sigma!" 4 4 TEXT
2 TEXT-SCALE  0 255 255 COLOR
S" FORTH/Sigma" 2DUP TEXT-WIDTH  160 SWAP - 2/  20 TEXT     \ centered
SHOW
```

| Word | Stack | Description |
| --- | --- | --- |
| `TEXT` | ( c-addr u x y -- ) | Draw the string with the top left of its line at x y, with the current color. The pixels between the strokes are left as they are; where a system font is smoothed, the edges mix the color with the image. |
| `TEXT-SCALE` | ( n -- ) | Draw each pixel of the font as n by n pixels, 1 to 256 (`NUMBER ERROR !` otherwise); 1 at first. |
| `TEXT-WIDTH` | ( c-addr u -- w ) | How many pixels wide `TEXT` draws the string, at the current scale. It needs no image. |
| `TEXT-HEIGHT` | ( -- h ) | The height of a line of the current font, at the current scale. |
| `LOAD-FONT` | ( c-addr u -- ) | Read the named BDF font file and use it. A file that cannot be opened throws its error, and one that is not a BDF font it can read `FONT ERROR !` (THROW -272); the font stays as it was then. A line is at most 256 pixels high and a glyph 512 pixels wide. The font in use is kept until the new one has been read whole. |
| `SYSTEM-FONT` | ( c-addr u height -- ) | Use the system's font of that name (such as `Consolas`, `MS Gothic`, or `メイリオ`), height pixels a line (1 to 256), smoothed in shades of gray. Characters from U+10000 up are drawn as `?`. `FONT ERROR !` when the system has no font of the name; `HOST FUNCTION UNAVAILABLE !` on Linux and macOS. |
| `BUILTIN-FONT` | ( -- ) | Use the built-in font again. |
| `GFX-GLYPH-LOAD` | ( code -- advance \| -1 ) | Load the glyph of a code point in the current font and give how far it moves the pen; -1 when the font has none. |
| `GFX-GLYPH-BOX` | ( -- left width height ) | The box of the loaded glyph: from `left` pixels right of the pen (negative: to the left) and from the top of the line. |
| `GFX-GLYPH-ALPHA` | ( x y -- a ) | The coverage of the loaded glyph at x y of its box, 0 (none) to 255 (full); 0 outside the box. |
| `GFX-FONT-HEIGHT` | ( -- h ) | The height of a line of the current font. |
| `GFX-FONT-LOAD`, `GFX-FONT-SYSTEM`, `GFX-FONT-BUILTIN` | ( c-addr u -- ior ), ( c-addr u height -- ior ), ( -- ) | As `LOAD-FONT`, `SYSTEM-FONT`, and `BUILTIN-FONT`, but returning ior (0, the file's error, or -272). |

The font is not part of the dictionary: `SAVE` and `SAVESYS` do not keep it, and a program starts with the built-in font, as it starts without an image. A BDF font is kept outside logical memory. With `LOAD-FONT`, any BDF font can be used, for example the whole of Misaki Gothic with its kanji (`misaki_gothic.bdf` from <https://littlelimit.net/misaki.htm>); the same program then draws the same pixels on every system. A system font draws differently on different systems, and the names of the fonts differ too.

### Tcl/Tk

The TCL words run Tcl scripts in a Tcl/Tk interpreter (`wish`) that Sigma starts as a program of its own, the first time it is needed, and talks to through pipes; no Tcl library is linked into Sigma. With it, a program can use Tk's widgets, and `DISPLAY-TK` shows the image in a Tk window, also on Linux and macOS, which have no window of Sigma's own. Tcl/Tk must be installed: Sigma uses the program named by `TCL-PROGRAM`, else by the environment variable `SIGMA_WISH`, else `wish` on the `PATH`, and on Windows, else the one Git for Windows comes with (`Git\mingw64\bin\wish.exe` under `%ProgramW6432%`, `%ProgramFiles%`, or `%LOCALAPPDATA%\Programs`; usually `C:\Program Files\Git\mingw64\bin\wish.exe`). On Linux it is in the `tk` package. On macOS, install it with `brew install tcl-tk`: the system's `/usr/bin/wish` (Tcl/Tk 8.5) no longer starts on recent macOS, so Sigma passes over it on the `PATH`, and when the `PATH` has no other `wish`, uses Homebrew's (`/opt/homebrew/bin/wish`, `/usr/local/bin/wish`) or MacPorts's (`/opt/local/bin/wish`), the first that is there.

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
S" expr {6 * 7}" TCL-EVAL TYPE                  \ 42
S" button .b -text Press -command {sigma_event pressed}; pack .b; wm deiconify ." TCL
: WAIT-PRESS   BEGIN TCL-EVENT 0= WHILE 10 MS REPEAT TYPE ;
WAIT-PRESS                                       \ pressed, after the button is pressed
```

`examples/calculator.fs` is a whole program: a calculator whose buttons and keys are Tk's and whose arithmetic is Forth's (`sigma.exe < examples/calculator.fs`).

| Word | Stack | Description |
| --- | --- | --- |
| `TCL` | ( c-addr u -- ) | Run a Tcl script (UTF-8) at the global level. `TCL ERROR !` (THROW -273) when it fails. |
| `TCL-EVAL` | ( c-addr u -- c-addr2 u2 ) | Run a Tcl script and give its result, which stays until the next script. |
| `TCL-ERROR$` | ( -- c-addr u ) | The message of the last script that failed. |
| `TCL-EVENT` | ( -- c-addr u true \| false ) | The next text the Tcl side sent with `sigma_event` (for example from a button's `-command`), without waiting; the text stays until the next `TCL-EVENT`. |
| `TCL-PROGRAM` | ( c-addr u -- ) | The program to start next time (a name on the `PATH` or a path); empty for `SIGMA_WISH`, `wish`, Git for Windows's, or on macOS Homebrew's or MacPorts's. |
| `TCL-STOP` | ( -- ) | End the program; the next `TCL` starts it again. It also ends with Sigma. What the program has written and Sigma has not read is dropped. `HOST FUNCTION ERROR !` when the host could not see the program end. |
| `DISPLAY-TK` | ( -- ) | Make `SHOW` show the image in the Tk window `.` (sent as a PNG, in the colors of `DISPLAY-COLORS`). Keys pressed and the mouse in it come to `INKEY` and `MOUSE`. Closing the window hides it until the next `SHOW`. With `WINDOW-SIZE`, the image is shown as large as fits by a whole factor (Tk zooms only so), or smaller by a whole factor when it does not fit, also when the window is resized. |
| `GFX-TCL`, `GFX-TCL-ERROR`, `GFX-TCL-EVENT`, `GFX-TCL-PROGRAM`, `GFX-TCL-STOP`, `GFX-SHOW-TK` | | The words underneath; `GFX-TCL` ( c-addr u -- c-addr2 u2 flag ) gives the result, or the message with a true flag, instead of throwing. |

When the program cannot be started or ends, the word gives `HOST FUNCTION ERROR !` (THROW -265), and the next one starts it again. A script runs until it returns, so a script that waits (such as `vwait`) holds Sigma too; Ctrl+C pressed in the Tk window meanwhile throws `USER INTERRUPT !` and ends the program, which the next script starts again. A script ending with `return`, `break`, or `continue` gives its result as any other; only an error is `TCL ERROR !`. The results and events are kept in the heap, and `SAVE` and `SAVESYS` free them first, so a string a TCL word gave before is not valid after them; a message still coming at that moment is dropped, and the program goes on. While more than 4 MiB that Sigma has not read wait in the program (Sigma reads only in the TCL words, `INKEY`, `KEY-HELD?`, and `MOUSE`), the program drops new events, keys pressed, and mouse reports; results and the releases of keys are always sent. Each `SHOW` sends the whole image, so large images update slowly. The Tcl side's protocol is in `src/graphics/sigma_tk.tcl`.

### Keys, the mouse, and animation

`INKEY` reads a key without waiting, from the terminal and from the window, and `MOUSE` gives the pixel of the image under the mouse. `KEY`, `KEY?`, and `ACCEPT` are not changed: they still read the terminal's line input.

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
80 40 GFX-INIT  DISPLAY-TERMINAL  MOUSE-ON
VARIABLE X  40 X !
: STEP ( -- flag )   \ false when q is pressed
   INKEY  DUP K-LEFT = IF -1 X +! THEN  DUP K-RIGHT = IF 1 X +! THEN
   [CHAR] q <>
   MOUSE 1 AND IF PSET ELSE 2DROP THEN ;
: RUN   BEGIN  0 0 255 COLOR  X @ 20 3 FILL-CIRCLE  255 255 255 COLOR  33 FRAME  STEP 0= UNTIL  MOUSE-OFF ;
RUN
```

`examples/paddle.fs` is a whole game with these words: a ball that bounces off three walls and a paddle moved with the Up and Down keys (`sigma.exe "include examples/paddle.fs"`). `examples/runner.fs` (Classic Runner) is a larger one: a tile game where the runner climbs ladders, hangs on ropes, digs holes, and collects gold while guards chase it; the line at the bottom shows how long the game's work takes each frame and the frames shown each second. `examples/hopper.fs` (Sky Hopper) is a side-scrolling platform game: the hopper runs and jumps through two courses, stamps on enemies, kicks shells, bumps blocks for coins and a berry that makes it big, and rides the balloon at the end; it takes the keys and a mapped gamepad.

| Word | Stack | Description |
| --- | --- | --- |
| `INKEY` | ( -- key \| -1 ) | The next key pressed, without waiting; -1 when there is none. A character gives its byte (each byte of a UTF-8 character in turn), Enter 13, Backspace 8, Tab 9, Esc 27. Ctrl+C throws `USER INTERRUPT !` (-28). |
| `K-UP`, `K-DOWN`, `K-LEFT`, `K-RIGHT`, `K-HOME`, `K-END`, `K-PRIOR`, `K-NEXT`, `K-INSERT`, `K-DELETE`, `K-F1` .. `K-F12` | ( -- key ) | The codes `INKEY` gives for the keys that are not characters: 256 to 277. |
| `MOUSE` | ( -- x y buttons ) | The pixel of the image under the mouse when it last moved, and the buttons held: 1 left, 2 right, 4 middle. -1 -1 while the position is not known. Keys pressed meanwhile wait for `INKEY`. |
| `MOUSE-ON`, `MOUSE-OFF` | ( -- ) | Have the terminal report the mouse, or stop. The window always reports it. |
| `FRAME` | ( ms -- ) | Wait until ms milliseconds have passed since the last `FRAME`, then `SHOW`. A loop that draws and calls `FRAME` runs at a steady pace; when the drawing took longer, it does not wait. |
| `KEY-HELD?` | ( key -- flag ) | Whether the key (a character of one byte, or `K-UP` and the other codes) is held down now. A game moves while a key is held, without waiting for the keyboard to repeat it (it waits about 0.5 s first). The Windows console, the window, and the Tk window tell when a key is released, and when they lose the focus; a terminal on Linux and macOS does not, so its keys count as held for 0.6 s after they were last pressed (a key held down is repeated, which holds it on). Keys read meanwhile wait for `INKEY`. |
| `GFX-INKEY`, `GFX-MOUSE`, `GFX-KEY-HELD` | as `INKEY`, `MOUSE`, `KEY-HELD?` | The words underneath. |
| `GFX-MOUSE-MODE` | ( flag -- ) | As `MOUSE-ON` (true) and `MOUSE-OFF` (false). |

The first `INKEY` or `MOUSE` sets the terminal to give each key at once, without echo; Sigma sets it back to its line input, dropping what was typed for the program, when it next reads a line or a `KEY`, runs `SYSTEM`, or ends. While the terminal gives single keys, Ctrl+C does not end Sigma: it reaches `INKEY`, which throws, so a loop that reads keys can be stopped with it (a loop that no longer calls `INKEY` or `MOUSE` then cannot). When standard input is not a terminal, `INKEY` gets only the window's keys.

On Linux and macOS, the keys that are not characters come from the terminal as escape sequences, which `INKEY` decodes; a sequence whose bytes come apart (over a slow connection) waits up to 50 ms for the rest, and an Esc that nothing follows within that time is the Esc key. The mouse comes as the reports of xterm in the SGR form, which most terminals send (xterm, GNOME Terminal, iTerm2, Windows Terminal, and others); `MOUSE-ON` asks for them and `MOUSE-OFF`, the return to line input, and the end stop them. On Windows, the console gives the keys and the mouse itself; the console's selection with the mouse is off while the terminal gives single keys. Keys pressed in the window come to `INKEY` as well, and the mouse in the window gives the pixel of the stretched image under it.

To find the pixel under the mouse on the terminal, Sigma asks the terminal where the cursor is after `SHOW` draws the image (only after `MOUSE-ON`), so the position is known from the first `SHOW` after `MOUSE-ON`. With half blocks, each character is two pixels; with Sixel the cell size comes from the terminal, or 10 by 20 pixels is assumed.

A `SHOW` on the terminal draws over the image it drew last when nothing was written in between, so an animation stays in place instead of scrolling; anything written in between (such as the prompt) starts a new picture below. With Sixel, the rows the picture takes are counted from the cell height, which may not match every terminal.

### Mathematical coordinates and graphs

In a build with the floating-point words, the library also draws in mathematical coordinates (`src/graphics/graphics_float.fs`; a build with `-Dfloat=false` leaves these words out). `X-RANGE` and `Y-RANGE` say which part of the plane the image shows: x grows to the right, from the left edge to the right one, and y grows upward, from the bottom edge to the top one. Both start as -1 to 1. A point is drawn at the pixel nearest to it.

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
320 200 GFX-INIT
-3.2e0 3.2e0 X-RANGE  -1.5e0 1.5e0 Y-RANGE
128 128 128 COLOR  AXES
255 255 0 COLOR  ' FSIN PLOT
: PARABOLA ( F: x -- y )  FDUP F* 1e0 F- ;
0 255 255 COLOR  ' PARABOLA PLOT
SHOW
```

`examples/trig.fs` draws sin x, cos x, and tan x with a grid, labels, and a legend; it gives `PLOT` NaN where tan x is far beyond the image, so that the graph has gaps at the asymptotes (`sigma.exe "include examples/trig.fs"`).

| Word | Stack | Description |
| --- | --- | --- |
| `X-RANGE` | ( F: lo hi -- ) | Show x from lo at the left edge to hi at the right one. |
| `Y-RANGE` | ( F: lo hi -- ) | Show y from lo at the bottom edge to hi at the top one. |
| `MPSET` | ( F: x y -- ) | Set the pixel of the point x y. |
| `MLINE` | ( F: x1 y1 x2 y2 -- ) | A line between two points. |
| `AXES` | ( -- ) | The axes x = 0 and y = 0 across the image; an axis outside the range is not drawn. |
| `PLOT` | ( xt -- ) | The graph of the function xt ( F: x -- y ): its y at the x of every column of the image, with a line between neighboring columns. |

The range needs lo less than hi, both finite; otherwise `X-RANGE` and `Y-RANGE` give `NUMBER ERROR !` and the range stays as it was. A coordinate that is not a number (NaN) draws nothing, and `PLOT` leaves a gap where y is NaN (for example where the function is not defined). Pixel positions beyond -2^61 .. 2^61, among them infinities, are moved to that limit as with `LINE`, so a line with such an end may go in a different direction.

## Sound

Sigma plays music in the manner of MSX BASIC's `PLAY` and `SOUND`, on the sound chips of the MSX, the Atari ST, the NES, the Commodore 64, Konami's SCC, and the Amiga, and it plays recorded sound (WAV files) and ProTracker modules (MOD files). The sound is made by an audio thread of its own, so the program goes on while the music plays. The audio words are not in the dictionary at start-up: `REQUIRE-AUDIO` adds the `AUDIO` vocabulary, with the `SND-` words and the audio library written in Forth (`src/audio/audio.fs`, built into the program), the first time it runs; later it does nothing. As with the graphics words, it does not change the search order, so make the words visible with `ALSO AUDIO`.

```forth
REQUIRE-AUDIO
ALSO AUDIO
S" T150 O4 L8 CDEFGAB>C" PLAY               \ voice A, as MSX BASIC's PLAY "..."
S" O4 C2" S" O4 E2" S" O4 G2" PLAY3         \ a chord: the three voices start together
BEEP
NES-SOUND                                   \ from now on PLAY plays on the NES
1 INSTRUMENT PULSE 25 DUTY 0 4 8 2 ADSR     \ instrument 1: a 25% pulse that fades
: TUNE S" T120 L8 O4 @1 CEGE CEGE" S" T120 L4 O3 CGCG" S" T120 L2 O2 CG" S" T120 L8 O3 C O4 D# O3 C O4 D#" 4 PLAYS ;
TUNE
```

`PLAY` returns as soon as the notes fit in the voices' queues (32 places for each), as on the MSX; the music then goes on by itself. While the queues are full, `PLAY` waits; Ctrl+C then stops the music and gives `USER INTERRUPT !` (THROW -28). Outside such a wait, Ctrl+C works as before. When there is no audio device, the words work the same without sound, in time (`AUDIO?` tells which).

### The music macro language (MML)

`PLAY` and the words like it take the music macro language of MSX BASIC (the MSX1 ROM's, as the MSX Red Book describes it). Upper and lower case letters are the same, and spaces are skipped. Each voice keeps its octave, length, tempo, volume, and instrument from one `PLAY` to the next; `BEEP` sets them back to the defaults.

| Command | Meaning |
| --- | --- |
| `A` to `G` | A note, with `+` or `#` (sharp) or `-` (flat), then a length 1 to 64 (or `L`'s), then dots (each one and a half times as long). `B+` is the same octave's `C`, and `C-` the same octave's `B`, as the ROM's table has it. |
| `R` | A rest of length 1 to 64 (4 when left out), with dots. |
| `N` | A note by its number, 0 to 96: octave n / 12 + 1, semitone n mod 12 (`N36` is `O4 C`); 0 is a rest. |
| `O` | The octave, 1 to 8 (4 at first; 4 when the number is left out). |
| `<`, `>` | One octave down or up. |
| `L` | The length of the notes without one, 1 to 64 (4: quarter notes). |
| `T` | The tempo, 32 to 255 quarter notes a minute (120). A note lasts 12000 / (length × tempo) fiftieths of a second, at least 5. |
| `V` | The volume, 0 to 15 (8); it ends `S`. |
| `S` | The PSG's envelope shape, 0 to 15 (0), which the notes after it use. |
| `M` | The PSG's envelope period, 1 to 65535 (255). |
| `@` | The instrument, 0 to 63 (0), on the chips that have instruments. |

A number left out takes the default in brackets (as the ROM does), except for `N`, which needs one. Anything else, or a number out of its range, gives `INVALID MML !` (THROW -274), and nothing of that `PLAY` is played. BASIC's variables (`X` and `=name;`) are not taken: a Forth program joins the strings itself.

Outside a definition, each `S"` string has its own place, so a `PLAYS` of eight voices can be written on one line; inside a definition the strings are compiled, which is the better place for music that is played more than once.

### MSX BASIC

| Word | Stack | Description |
| --- | --- | --- |
| `REQUIRE-AUDIO` | ( -- ) | Load the audio words, the first time only. It is a parsing word (like `REQUIRE-GRAPHICS`) and cannot be used inside a definition. |
| `PLAY` | ( c-addr u -- ) | Play the MML on voice A. Voices B and C, which have no notes, still start the next `PLAY` together with A. |
| `PLAY2`, `PLAY3` | ( c-addr1 u1 c-addr2 u2 -- ), ( c-addr1 u1 c-addr2 u2 c-addr3 u3 -- ) | Play voices A and B, or A, B, and C, starting together. |
| `PLAYS` | ( c-addr1 u1 ... c-addrn un n -- ) | Play the first n voices of the chip (or chips) chosen, starting together; n is 1 to the number of voices. |
| `PLAY?` | ( n -- flag ) | Whether voice n still has notes to play, or any voice for 0, as MSX BASIC's `PLAY(n)`. A voice without notes counts until the audio thread takes its end of the `PLAY` (within a fiftieth of a second). |
| `SOUND` | ( reg value -- ) | Write the value 0 to 255 to the PSG's register 0 to 13, as MSX BASIC's `SOUND`; the PSG sounds with every chip. |
| `BEEP` | ( -- ) | Stop the music, set the PSG and the voices' settings as at start, and beep (about 1316 Hz for 40 ms). It returns when the audio thread has stopped the music. |
| `AUDIO?` | ( -- flag ) | Whether the sound reaches an audio device. |

### Chips and instruments

`PLAY` plays on one chip, or on several together with `CHIPS`. Choosing a chip stops the music, as `BEEP` does without its sound. On a chip with instruments, the MML's `@n` chooses instrument n; a value a chip does not have is taken to the nearest one it has, and what a chip cannot do is left out.

| Word | Stack | Description |
| --- | --- | --- |
| `MSX-SOUND` | ( -- ) | The MSX's AY-3-8910 (3 voices), with the pitches of the MSX's ROM. This is the chip at start. |
| `ST-SOUND` | ( -- ) | The Atari ST's YM2149 at 2 MHz (3 voices), with its 32-step volume for the envelopes. |
| `NES-SOUND` | ( -- ) | The NES (4 voices): two pulses (duty 12.5, 25, 50, or 75%), a triangle (no volume: `V0` is silence), and a noise, whose notes from `O3 C` to `O4 D#` choose its 16 sounds from the lowest to the highest. |
| `C64-SOUND` | ( -- ) | The C64's SID (3 voices): triangle, sawtooth, pulse, and noise, with `RING`, `SYNC`, and `FILTER`. |
| `SCC-SOUND` | ( -- ) | Konami's SCC (5 voices), each playing its instrument's wave of 32 samples. |
| `AMIGA-SOUND` | ( -- ) | The Amiga's Paula (4 voices: left, right, right, left), playing the instruments' samples. |
| `CHIPS` | ( mask -- ) | Several chips together: the sum (`OR`) of `MSX` (1), `ST` (2), `NES` (4), `C64` (8), `SCC` (16), and `AMIGA` (32). The voices are numbered in that order: with `MSX SCC OR CHIPS`, voices 1 to 3 are the PSG's and 4 to 8 the SCC's. At most 8 voices in all, and not `MSX` with `ST` (they are one PSG); otherwise `NUMBER ERROR !`. |
| `INSTRUMENT` | ( n -- ) | Choose instrument n (0 to 63) for the words below to change. |
| `SQUARE`, `PULSE`, `TRIANGLE`, `SAW`, `NOISE` | ( -- ) | The instrument's wave (the C64 takes each; the NES's pulses take `PULSE`'s duty; the SCC and the Amiga make a wave of 32 samples of it). `SQUARE` at first. |
| `DUTY` | ( percent -- ) | The width of `PULSE`, 0 to 100 (50 at first). |
| `ADSR` | ( a d s r -- ) | The envelope, each 0 to 15 as on the SID: attack 2 ms to 8 s, decay and release three times as long, sustain level s / 15. `0 0 15 0` at first. A note's release starts when the note ends. |
| `RING`, `SYNC` | ( flag -- ) | On the C64, modulate the instrument's triangle by the voice before it (voice 1 by voice 3), or restart its wave with each cycle of that voice. |
| `FILTER` | ( mode cutoff resonance -- ) | On the C64, send the instrument through the filter: mode 0 none, 1 low-pass, 2 band-pass, 3 high-pass; cutoff 0 to 2047 (about 30 Hz to 12 kHz), resonance 0 to 15. The voices share one filter, set by the last note that uses it. |
| `SCC-WAVE` | ( c-addr n -- ) | Make the 32 signed bytes at c-addr the wave of instrument n on the SCC (and the Amiga). Without one, the instrument's wave word's shape. |

The chips are made of common parts and imitate them by their documented behavior: the pitches are rounded to each chip's period registers and the volumes to its steps, but the C64's combined waves and the 6581's filter curve, the NES's sweep and DPCM, and the like are not reproduced.

### Recorded sound

Samples 0 to 63 are recorded sound kept in a pool of 16 MiB outside the dictionary's memory. The pool only grows: loading a sample again takes new room, and `FREE-SAMPLES` empties it.

| Word | Stack | Description |
| --- | --- | --- |
| `LOAD-SAMPLE` | ( c-addr u n -- ) | Read a WAV file of 8- or 16-bit PCM, mono or stereo (made mono), into sample n. A file it cannot read gives its error; a file that is not such a WAV gives `SAMPLE ERROR !` (THROW -276); a full pool gives `OUT OF MEMORY !`. Nothing changes on an error. A file whose data ends before the size it gives makes a sample of the frames there are. |
| `SAMPLE` | ( c-addr u rate n -- ) | Make the u signed 8-bit bytes at c-addr sample n, recorded at rate Hz (1000 to 192000). |
| `LOOP-SAMPLE` | ( start end n -- ) | Repeat the frames from start to end of sample n while it plays; `0 0` for no loop. |
| `SAMPLE-INSTRUMENT` | ( n -- ) | Have the instrument (chosen with `INSTRUMENT`) play sample n on the Amiga, `O4 C` at the sample's own rate; -1 for none. |
| `SFX` | ( n -- ) | Play sample n once at its rate, at once and beside the music, on any chip. Four can sound together; a fifth takes the place of the oldest. |
| `FREE-SAMPLES` | ( -- ) | Stop the music, the sound effects, and the module, and forget every sample and the module. |
| `AMIGA-FILTER` | ( flag -- ) | Turn the Amiga's LED filter (a low-pass at about 3.3 kHz) on or off. The A500's fixed low-pass (about 4.9 kHz) is always there. |

### Modules

| Word | Stack | Description |
| --- | --- | --- |
| `LOAD-MOD` | ( c-addr u -- ) | Read a ProTracker module of four channels (`M.K.`, `M!K!`, `FLT4`, `4CHN`) into the pool. Other files give `MOD ERROR !` (THROW -277); a full pool gives `OUT OF MEMORY !`. |
| `PLAY-MOD` | ( flag -- ) | Play the module from its start, beside `PLAY` and `SFX`; again after its end when flag is true. |
| `STOP-MOD` | ( -- ) | Stop the module. |
| `MOD?` | ( -- flag ) | Whether the module plays. |

The module plays on Paula's periods, panned and filtered as the Amiga's (`AMIGA-FILTER` and the effect `E0x` turn the LED filter on and off). These effects are played: arpeggio, portamento up and down, tone portamento, vibrato, tremolo, the volume slides, sample offset, position jump, pattern break, set volume, set speed and tempo, fine portamento and fine volume slides, pattern loop, retrigger, note cut, note delay, and pattern delay. The vibrato and the tremolo are always a sine (`E4x`, `E7x`), and `E3x`, `E5x`, `E8x`, and `EFx` do nothing.

### The audio device

| System | Device |
| --- | --- |
| Windows | waveOut, 48 kHz 16-bit stereo; a note starts about 80 ms after the audio thread takes it. |
| Linux (the release builds, static) | The first of the commands `pacat`, `pw-play`, and `aplay` that starts, through a pipe (about 40 ms). |
| Linux (a build that can load libraries) | PulseAudio, then ALSA, then the commands above. |
| macOS | An AudioQueue of AudioToolbox on the default output device, 48 kHz 16-bit stereo (about 80 ms); the framework is loaded when the program runs. |

`BEEP`, the chip words, `CHIPS`, `FREE-SAMPLES`, and Ctrl+C while `PLAY` waits stop the music, the sound effects, and the module. The sound (instruments, samples, queues) is not part of the dictionary: `SAVE` and `SAVESYS` keep the audio words and the words that use them, but a program sets its instruments and loads its samples after it starts. A dictionary that has loaded the audio words is saved as `SIGIMG35`.

The `SND-` words are the base the library is written with: `SND-PLAY`, `SND-PLAYS`, `SND-SOUND`, `SND-BEEP`, `SND-PLAYING`, `SND-DEVICE`, `SND-CHIP`, `SND-CHIPS`, `SND-INSTRUMENT`, `SND-WAVE`, `SND-DUTY`, `SND-ADSR`, `SND-RING`, `SND-SYNC`, `SND-FILTER`, `SND-WAVETABLE`, `SND-LOAD-SAMPLE`, `SND-SAMPLE`, `SND-LOOP-SAMPLE`, `SND-SAMPLE-INSTRUMENT`, `SND-SFX`, `SND-AMIGA-FILTER`, `SND-FREE-SAMPLES`, `SND-LOAD-MOD`, `SND-PLAY-MOD`, `SND-STOP-MOD`, and `SND-MOD-PLAYING`. `HELP` describes each of them. `SND-LOAD-SAMPLE` and `SND-LOAD-MOD` return an ior instead of throwing.

Errors: `REQUIRE-AUDIO` in a build with `-Daudio=false` gives `AUDIO UNAVAILABLE !` (THROW -275); a number out of its range gives `NUMBER ERROR !`; a host without an audio thread gives `HOST FUNCTION UNAVAILABLE !`. As with `REQUIRE-GRAPHICS`, a library that fails to load is removed again, and `REQUIRE-AUDIO` loads it again after `FORGET` or a `MARKER` removed it.

`examples/music.fs` plays a short tune on each chip and a sound effect made with `SAMPLE`.
