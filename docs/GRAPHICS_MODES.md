# Graphics modes

FORTH/Sigma has no numbered screen modes, such as `SCREEN 1` of BASIC. A program draws on one image in memory, of any size, and chooses separately where `SHOW` shows it and with how many colors. This manual describes these choices; for the drawing words themselves, see the [graphics and sound manual](GRAPHICS_AND_SOUND.md).

All the words here are in the `GRAPHICS` vocabulary:

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
```

## The three choices

| Choice | Words | Default |
| --- | --- | --- |
| The size of the image | `GFX-INIT` ( w h -- ) | none: no image before `GFX-INIT` |
| Where `SHOW` shows it | `DISPLAY-TERMINAL`, `DISPLAY-WINDOW`, `DISPLAY-TK`, with `TERMINAL-BLOCKS` and `TERMINAL-SIXEL` for the terminal | the window when the host has one (Windows); else the Tk window on a desktop when `wish` starts (Linux, macOS); else the terminal with half blocks |
| With how many colors | `DISPLAY-COLORS` ( n -- ), `DITHER` ( flag -- ) | full color, no dithering |

The three are independent: any image size goes with any place and any number of colors. They change only how the image is shown. The image itself always keeps full 24-bit color, and `SAVE-PPM`, `SAVE-BMP`, and `SAVE-PNG` save it in full color whatever was chosen.

## The image

`GFX-INIT` ( w h -- ) makes a new black image, each side 1 to 16384 pixels, so the image is at most 1 GiB (4 bytes a pixel). There is one image at a time; a new `GFX-INIT` replaces it. Coordinates start at 0 0 in the top left corner.

The size can be chosen to look like an older computer, for example 320 by 200 or 640 by 400, or to suit the program. `WINDOW-SIZE` (below) then shows a small image larger.

## Where the image is shown

| Mode | How to choose it | Where it works | What it shows |
| --- | --- | --- | --- |
| Terminal, half blocks | `DISPLAY-TERMINAL TERMINAL-BLOCKS` | every system | Each character is two pixels, one above the other, in 24-bit color escapes. |
| Terminal, Sixel | `DISPLAY-TERMINAL TERMINAL-SIXEL` | terminals that support Sixel | Real pixels. |
| Window | `DISPLAY-WINDOW` | Windows | A window of Sigma's own. |
| Tk window | `DISPLAY-TK` | where Tcl/Tk (`wish`) is installed, on every system | The Tk window `.`, which gets the image as a PNG. |

Until one of `DISPLAY-TERMINAL`, `DISPLAY-WINDOW`, and `DISPLAY-TK` is used, `SHOW` uses the window when the host has one. `GFX-WINDOW?` ( -- flag ) tells whether the host has the window. `DISPLAY-WINDOW` on a host without it gives `HOST FUNCTION UNAVAILABLE !`. Linux and macOS have no window yet, so there the first `SHOW` tries the Tk window when Sigma runs on a desktop: when the environment variable `DISPLAY` or `WAYLAND_DISPLAY` is set (X11, Wayland), or `__CFBundleIdentifier` (a terminal app of macOS; it is not set over SSH). When `wish` starts and shows the image, `SHOW` keeps to the Tk window, as after `DISPLAY-TK`; otherwise (no desktop, no Tcl/Tk), it keeps to the terminal, as after `DISPLAY-TERMINAL`. So `sigma examples/hopper.fs` opens a window on a Linux or macOS desktop with Tcl/Tk installed. A program that wants the terminal there uses `DISPLAY-TERMINAL`.

`TERMINAL-BLOCKS` and `TERMINAL-SIXEL` choose how the terminal shows the image; they do not themselves make `SHOW` use the terminal. Half blocks are the default.

### Terminal, half blocks

- Most terminals show it: Windows Terminal and the Windows console, xterm, GNOME Terminal, and so on.
- An image larger than the terminal is made smaller to fit, keeping its proportions, and each new pixel has the average color of the pixels it stands for. One line is left for the prompt. A smaller image is not made larger: one character is one pixel wide and two pixels high.
- When the output is not a terminal (a pipe or a file), 80 columns and 24 rows are assumed.
- On Windows, Sigma sets the console to the UTF-8 code page while it writes the blocks, and then sets it back.

### Terminal, Sixel

- A terminal without Sixel may show stray characters or nothing.
- The image is made smaller to fit the terminal's size in pixels (10 by 20 pixels a character when the terminal does not tell it), at most 4096 pixels wide. A smaller image is not made larger.
- In full color, the colors are the 216 of a 6 × 6 × 6 cube; with `DISPLAY-COLORS`, they are those of its palette.

### Window (Windows)

- The window has a thread of its own: while Forth waits for input it can be moved, resized, and closed. The keyboard stays with the console, and keys pressed in the window come to `INKEY` too.
- Each `SHOW` draws the current image in it again, and fits the window to a new image size or to the size `WINDOW-SIZE` gave. Without `WINDOW-SIZE`, an image larger than 1600 by 1200 pixels is shown smaller.
- When the window is resized, the image keeps its proportions in it, with black around it.
- A window that was closed is opened again by the next `SHOW`.

### Tk window

- Sigma starts the Tcl/Tk program (`wish`) the first time it is needed; see "Tcl/Tk" in the [graphics and sound manual](GRAPHICS_AND_SOUND.md) for where it is looked for.
- Each `SHOW` sends the whole image as a PNG, so large images update slowly.
- With `WINDOW-SIZE`, the image is shown as large as fits by a whole factor, since Tk zooms only so, or smaller by a whole factor when it does not fit; also when the window is resized.
- Closing the window hides it until the next `SHOW`.

### Keys and the mouse in each mode

`INKEY` reads the terminal's keys in every mode; the window and the Tk window add their own.

| Mode | Keys (`INKEY`, `KEY-HELD?`) | `MOUSE` |
| --- | --- | --- |
| Terminal | the terminal's | after `MOUSE-ON`, from the first `SHOW` after it |
| Window | the terminal's and the window's | the window always reports it: the pixel of the stretched image under the mouse |
| Tk window | the terminal's and the Tk window's | the mouse in the Tk window |

See "Keys, the mouse, and animation" in the [graphics and sound manual](GRAPHICS_AND_SOUND.md) for the details.

## The colors

`DISPLAY-COLORS` ( n -- ) chooses the colors `SHOW` uses, for terminals that show fewer colors or for the look of older computers. It applies to every place: the terminal (half blocks and Sixel), the window, and the Tk window.

| n | Colors |
| --- | --- |
| 0 | Full color (the default). Sixel shows 216 colors. |
| 2 | Black and white, by brightness. |
| 16 | The 16 ANSI colors (escapes 30 to 37 and 90 to 97). The nearest is chosen as xterm shows them by default; other terminals may show them differently. |
| 256 | The colors 16 to 255 of xterm's 256: a 6 × 6 × 6 cube and 24 grays (`ESC [ 38 ; 5 ; n m`). Sixel uses the same 240 colors. |

Other values give `NUMBER ERROR !`, and the colors stay as they were.

`DITHER` ( flag -- ) chooses how fewer colors are made: true mixes them in a 4 × 4 Bayer pattern, false (the default) takes the nearest color. The pattern stays in place, so animation does not flicker. Full color is not dithered.

## The size it is shown at

`WINDOW-SIZE` ( w h -- ) shows the image, from the next `SHOW`, in an area w by h pixels large in the window and in the Tk window, each side 1 to 16384. 0 0 (the default) shows the image at its own size. The image keeps its proportions, as large as fits, in the middle with black around it. It does not change the image, nor the terminal.

## Examples

An image of 160 by 120 shown in the window with each pixel as 4 by 4:

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
160 120 GFX-INIT  640 480 WINDOW-SIZE
255 255 0 COLOR  80 60 40 CIRCLE
SHOW
```

Continuing, the same image on the terminal in 16 colors, dithered:

```forth
DISPLAY-TERMINAL  TERMINAL-BLOCKS
16 DISPLAY-COLORS  TRUE DITHER
SHOW
```

As Sixel in black and white, and back to full color:

```forth
TERMINAL-SIXEL  2 DISPLAY-COLORS  SHOW
0 DISPLAY-COLORS  FALSE DITHER
```

In a Tk window, also on Linux and macOS:

```forth
DISPLAY-TK  SHOW
```

## The words underneath

The words above are Forth definitions in the graphics library (`src/graphics/graphics.fs`), so `SEE` shows them. `SHOW` passes the colors to the host with `GFX-COLOR-MODE` ( n flag -- ) and then calls one of `GFX-SHOW-BLOCKS`, `GFX-SHOW-SIXEL`, `GFX-SHOW-WINDOW`, and `GFX-SHOW-TK`. A program that calls these directly sets the colors with `GFX-COLOR-MODE` itself.

## Saving

The image is not part of the dictionary: `SAVE` and `SAVESYS` do not keep its pixels, so a saved program makes its image with `GFX-INIT` after it starts, and chooses the place, the colors, and `WINDOW-SIZE` there too.
