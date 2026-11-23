# FORTH/Σ Graphics and Sound Manual

Linux builds enable the local X11/XWayland window by default; use `-Dx11=false` to omit it. Automatic display selection tries native, Tk, then terminal within a shared five-second budget. Direct Wayland and native TCP/SSH connections are unsupported. See [Linux validation](LINUX_NATIVE_VALIDATION.md) for tested environments and limits.

Japanese version: [GRAPHICS_AND_SOUND.ja.md](GRAPHICS_AND_SOUND.ja.md). This English version is the primary one.

The graphics and the sound of Sigma are extensions of this port: the FORTH/Σ of the magazine has neither. This manual describes them: drawing, text, Tcl/Tk, keys, the mouse, and animation (`REQUIRE-GRAPHICS`), and music, sound chips, recorded sound, and modules (`REQUIRE-AUDIO`). For starting Sigma, the language, and the other words, see the [user manual](USER_MANUAL.md); for where `SHOW` shows the image and with how many colors, see the [graphics modes manual](GRAPHICS_MODES.md).

## Boing demos

The red-and-white checkered ball rotates by changing its palette and bounces in front of a grid. Run one source file per process. All three demos need graphics and floating-point words; builds with `-Daudio=false` run silently.

| Source | Rendered image | Initial window | Frame pacing |
| --- | --- | --- | --- |
| [boing.fs](../examples/boing.fs) | 320×200 | 960×600 (3× pixels) | 16 ms per frame |
| [boing-hd.fs](../examples/boing-hd.fs) | 960×600 | 960×600 | 16 ms per frame |
| [boing-hfr.fs](../examples/boing-hfr.fs) | 1920×1200 | 1280×800 | 120 fps target |

From the repository root:

```sh
zig build -Doptimize=ReleaseFast
zig-out/bin/sigma examples/boing-hd.fs
zig-out/bin/sigma examples/boing-hfr.fs
```

Space pauses/resumes; Q or Esc quits. Keys go to the focused window or terminal. Resize/maximize the window to suit your screen. HD and HFR include six floor rows and synthesized rubber-ball impacts, with different sounds for the floor and walls.

HFR restores only the previous ball/shadow area and advances motion by elapsed time, so a lower frame rate does not slow the simulation. Physics uses steps of at most 8 ms; elapsed time is capped at 100 ms after a stall. For less work, change `DETAIL` from 6 to 4 for 1280×800 rendering, or `TARGET-FPS` from 120 to 60. Keep `DETAIL` within 1–10 to fit the indexed palette.

Prefer a native window for HFR; Tk and terminal output may be slower. The Linux ReleaseFast probe on a dedicated Xvfb produced about 110–116 drawing-loop iterations per second over 240 iterations. This is a short software test, not a monitor-FPS measurement. Asynchronous `SHOW` can combine frames, and actual presentation depends on the backend, display refresh rate and workload. The 16 ms and 120 fps settings are pacing targets, not guaranteed rates.

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
| `CLS` | ( -- ) | Make the whole image black; with a `CLIP!`, the part that may be drawn in. |
| `LINE` | ( x1 y1 x2 y2 -- ) | A line between two points, both included (Bresenham's algorithm). |
| `RECT` | ( x y w h -- ) | The outline of a w by h rectangle whose top left corner is x y. Nothing when w or h is 0 or less. |
| `FILL-RECT` | ( x y w h -- ) | A filled w by h rectangle. |
| `CIRCLE` | ( x y r -- ) | A circle of radius r around x y, with the pixels of the midpoint circle algorithm. Nothing when r is less than 0; one pixel when r is 0. |
| `FILL-CIRCLE` | ( x y r -- ) | A filled circle; it covers every pixel of `CIRCLE` with the same arguments. |
| `PAINT` | ( x y -- ) | Fill the area around x y that has the color of x y (pixels joined left, right, up, or down) with the current color. Nothing outside the image or when the area has the current color already. |
| `SAVE-PPM`, `SAVE-BMP`, `SAVE-PNG` | ( c-addr u -- ) | Write the image to a new file as a binary PPM (P6), a 24-bit BMP, or a PNG, and `THROW` the error of the file operation if there is one. The PNG has 8-bit red, green, and blue and is not compressed, so it is about as large as the BMP; any program that reads PNG files reads it. |
| `SAVE-PNG-ALPHA` | ( c-addr u -- ) | Save the whole drawing target as RGBA8 PNG, retaining alpha and zero-alpha RGB. Screen pixels are opaque. Ignores CLIP! and display color settings; THROW on errors. SAVE-PNG remains RGB. |
| `SHOW` | ( -- ) | Show the image: in Sigma's own window when the host has one (Windows, macOS, and Linux on X11 or XWayland), else in the Tk window on a desktop when `wish` starts (see the [graphics modes](GRAPHICS_MODES.md)), else on the terminal; or where `DISPLAY-TERMINAL`, `DISPLAY-WINDOW`, or `DISPLAY-TK` said. |
| `DISPLAY-AUTO` | ( -- ) | Clear the explicit display choice and the automatic choice remembered for this process. The next `SHOW` tries Sigma's own window, then Tk on a desktop, then the terminal, and remembers the first that starts. Saved dictionaries keep only the automatic choice, not the selected backend. Explicit `DISPLAY-WINDOW` and `DISPLAY-TK` do not fall back. |
| `DISPLAY-TERMINAL`, `DISPLAY-WINDOW` | ( -- ) | Make `SHOW` use the terminal, or the window. `DISPLAY-WINDOW` gives `HOST FUNCTION UNAVAILABLE !` when the host has no window. |
| `WINDOW-SIZE` | ( w h -- ) | From the next `SHOW`, show the image in the window (and in the Tk window of `DISPLAY-TK`) in an area w by h pixels large, each side 1 to 16384; 0 0 (the default) for the image's own size. The image keeps its proportions, as large as fits, in the middle with black around it; for example `160 120 GFX-INIT 640 480 WINDOW-SIZE` shows each pixel as 4 by 4. It does not change the image, nor the terminal. |
| `FULLSCREEN` | ( flag -- ) | Make Sigma's own window cover its screen (true) or be a window again at the place and size it had (false), without changing the screen's mode. The image is drawn as in the window: as large as fits with its proportions, black around it. The window takes the keys when it becomes fullscreen, as far as the system lets it: on Windows, not while another program the user works in is in front (a click then gives the window the keys). The user leaves fullscreen with Alt+Enter (Control+Command+F on macOS), which `INKEY` does not get. Asked before `SHOW` has chosen where to show, the window opens fullscreen; when the window is closed, the next `SHOW` opens it fullscreen again. `HOST FUNCTION UNAVAILABLE` with `DISPLAY-TERMINAL`. The windows of Windows, macOS (a fullscreen Space), and Linux (the window manager covers the screen, by EWMH fullscreen) and the Tk window of `DISPLAY-TK` (`wm attributes -fullscreen`; its image is zoomed by a whole factor, as Tk does) do it. |
| `FULLSCREEN?` | ( -- flag ) | Whether fullscreen is wanted now; false after the user left it with its key. |
| `DISPLAYS` | ( -- n ) | Take the displays of the machine as they are now and give how many there are. The `DISPLAY-` words below tell of display i (0 to n − 1) as `DISPLAYS` took it, until the next `DISPLAYS`; a display that is not there gives `NUMBER ERROR !`. Windows tells the displays, wherever `SHOW` shows and also before a window is open; Linux tells them where there is an X server with RandR 1.5 (also the X server of Wayland desktops). Each call uses a separate X connection with a two-second limit for the whole call; if the monitor list does not arrive, it gives 0 displays. If a refresh rate cannot be found or does not arrive in time, its fraction is 0 0. Places, sizes and the primary display come from the monitor list; the scale is unknown, and `DISPLAY-WORK` is the overlap of the current desktop's window-manager work area with each display. If `_NET_WORKAREA` is absent, invalid or unavailable, the whole display is used; if there is no overlap, the result is anchored at that display's position with width and height 0. macOS reads the display list, bounds, work area, backing scale and refresh rate in a short-lived AppKit/CoreGraphics child on each call. That probe is limited to three seconds; if it fails, `DISPLAYS` is 0. On macOS the reported pixel dimensions use backing pixels (logical points multiplied by backing scale), not necessarily the panel's native pixel count. Windows before Windows 10 1703 reports places and sizes as seen by a program unaware of display scales, and the scales are unknown. At most 16 displays are kept. |
| `DISPLAY-RECT` | ( i -- x y w h ) | The place and size of display i in desktop pixels, whose origin is the primary display's top left corner: a display left of it or above it has a negative x or y. On macOS these are backing pixels (logical points multiplied by the display's backing scale), not necessarily the panel's native pixel count. |
| `DISPLAY-WORK` | ( i -- x y w h ) | The part of display i an ordinary window may cover (for example, excluding the Windows taskbar or the macOS menu bar and Dock), in the same pixels. Linux clips the current desktop's work area to each display and can return width and height 0 when there is no overlap. On macOS these are backing pixels, not necessarily the panel's native pixel count. |
| `DISPLAY-SCALE` | ( i -- num den ) | The scale of display i as a fraction in its smallest terms: 1 1 for 100%, 3 2 for 150%. A denominator of 0 says the scale is not known. |
| `DISPLAY-HZ` | ( i -- num den ) | The refresh rate of display i in Hz as a fraction: 60 1, or 59951 1000 for 59.951 Hz. A denominator of 0 says it is not known. |
| `DISPLAY-PRIMARY` | ( -- i ) | The primary display among those `DISPLAYS` took, -1 when there are none. |
| `WINDOW-DISPLAY` | ( -- i ) | The display Sigma's window is on (the one that holds most of it) among those `DISPLAYS` took: the host's own window, or the Tk window when `SHOW` shows there (`DISPLAY-TK`) on Windows. Tk gives -1 on Linux and macOS, even if the native window stays open. macOS gives -1 if its native-window query fails or gets no reply within about one second; the call can take up to about two seconds. It also gives -1 without a window, or when its display was not there at the last `DISPLAYS`. |
| `WINDOW-PIXELS` | ( -- w h ) | The size of the part of the host's own window that can be drawn in, as it is now, in physical pixels: what the user made it by dragging its frame, a fullscreen window's whole screen, or the size it took on a display of another scale. `WINDOW-SIZE` asks for a size; this is the size the window has. When `SHOW` shows in the Tk window (`DISPLAY-TK`), it is that window's size in the same physical pixels, which on a display of another scale is not the number Tk gives (Tk 8.6 is shown stretched there: 640 by 400 for Tk is 800 by 500 pixels at 125%); asking does not start Tk, and each time it asks Tk, so it is slower than for the host's own window. 0 0 without such a window (also before `SHOW` has shown in the Tk window, with the terminal, and when the size cannot be told in physical pixels); Linux's own window under X tells it too, and so does macOS's own window, in backing pixels (points times the display's backing scale; on macOS the Tk window gives 0 0). A minimized window of the host's own keeps the size it had. On Windows before Windows 10 1703 the size is as Windows gives it to a program unaware of the displays' scales. |
| `WINDOW-CHANGES` | ( -- n ) | A count that goes up each time the size `WINDOW-PIXELS` gives, the window's scale, the display it is on, or the displays themselves (one added, removed, or with another mode) change while the host's own window is open; opening and closing the window count too. A program keeps the count it saw and, when it differs, reads `WINDOW-PIXELS`, `DISPLAYS`, and `WINDOW-DISPLAY` again. Changes between two reads are not told one by one: the words give the state as it is when they are asked. The count and the list `DISPLAYS` takes are not of one moment: when a display was put back, the count went up a quarter of a second after the list had changed. 0 where the host cannot tell. On Linux the changes of the displays themselves are not counted, only those of the window. macOS counts them too; one change there may count more than once (a change of the display mode counted 3 to 5). It counts the host's own window only: the Tk window's changes are not counted, so a program that shows there reads `WINDOW-PIXELS` when it needs it. |
| `WINDOW-OPEN?` | ( -- flag ) | Whether the selected Tk image window, or otherwise the native window, is open now. A minimized window is open; a withdrawn/closed Tk window is not. Asking does not start wish. |
| `WINDOW-FOCUSED?` | ( -- flag ) | Whether the selected Tk window, or otherwise the native window, has keyboard focus. Tk includes its IME widget, but excludes widgets in another toplevel. |
| `WINDOW-MINIMIZED?` | ( -- flag ) | Whether the selected Tk window, or otherwise the native window, is minimized. Linux builds with X11 prefer the window manager's WM_STATE when available, otherwise Tk's cache. On macOS with Stage Manager on, the minimize button moves the window aside without minimizing it; macOS then does not call it minimized, and neither does this word. |
| `WINDOW-CLOSES` | ( -- n ) | User close count for the selected Tk window, or otherwise the native window. Tk withdraws by default and the next SHOW reopens it. With WINDOW-KEEP-OPEN true it retains the first request; reading this word acknowledges it. Received Tk counts survive TCL-STOP/restart; a new State or saved app starts at zero. Tk and native have separate counters. |
| `WINDOW-KEEP-OPEN` | ( flag -- ) | With true, the host's own window stays when the user presses its close button or the system's key: that is counted by `WINDOW-CLOSES`, and the program decides (it may tell the user of work not saved and ask). To close, it calls `WINDOW-CLOSE`; to stay open, it goes on. False (at first) is as before: the window goes at once. One rule keeps a program that does not look from holding the window open against the user: when the user asks again and the program has not read `WINDOW-CLOSES` since the time before, the window closes. A program that keeps its window open reads `WINDOW-CLOSES` often (each frame). It holds for the windows opened later too. Native Windows, Linux/X, and macOS windows support it. The common Tk implementation is verified on Windows and macOS; Linux Tk execution remains separate. Elsewhere the setting is kept. |
| `WINDOW-CLOSE` | ( -- ) | Close the selected Tk window by withdrawing it, or otherwise the native window (native waits until the window is gone, about 5 seconds at most; when that runs out the window goes later, and the next `SHOW` waits for it before it opens the window again), also with `WINDOW-KEEP-OPEN` true; it is not counted by `WINDOW-CLOSES`, and nothing happens without a window. The next `SHOW` opens the window again. Native Windows, Linux/X, and macOS support it. Tk is verified on Windows and macOS; Linux Tk execution remains separate. Elsewhere nothing happens. |
| `WINDOW-FIT` | ( n -- ) | How the image is laid out in the host's own window, whatever size the window has: 0 (at first) the largest rectangle with the image's proportions, in the middle; 1 each pixel of the image as a square of a whole number of pixels, the largest that fits, in the middle, so that every pixel is as large as every other (where the window is smaller than the image, as 0); 2 the whole of the window, whatever its proportions. What is left is black, and `MOUSE` gives the image's pixel under the mouse in each. Other numbers give `NUMBER ERROR !`. It holds for the windows opened later too. Windows's own window, Linux's under X, and macOS's own window do it; elsewhere the wish is kept and nothing changes (the Tk window always lays the image out by whole factors, as `WINDOW-IMAGE-RECT` tells). The numbers have names: `FIT-ASPECT` (0), `FIT-INTEGER` (1), `FIT-STRETCH` (2), as in `FIT-INTEGER WINDOW-FIT`. |
| `WINDOW-ON` | ( i -- ) | Put the host's own window on display i as `DISPLAYS` took it; -1 (at first) leaves the place to the system. A window not open yet opens there at the next `SHOW`; an open one moves there now, into the middle of the display's work area, as large as it was where that fits (a window keeps its size in the system's units, so on a display of another scale `WINDOW-PIXELS` changes as when the user moves it). A fullscreen window leaves fullscreen, moves, and covers the new display. It holds for the windows opened later too. It does not tell whether that worked: `WINDOW-DISPLAY` tells where the window is. When the display is gone by the time the window opens, the system chooses the place (usually the primary display), and the window is not moved back when the display returns. A number `DISPLAYS` did not count gives `NUMBER ERROR !`. The Tk window and the terminal keep the wish only. Not kept in a dictionary image. macOS's own window is verified; the code for Windows and Linux under X is written but not yet run on those systems. |
| `WINDOW-IMAGE-RECT` | ( -- x y w h ) | The rectangle in which the window lays the image out now, in the pixels of the window's drawable part (`WINDOW-PIXELS`), x and y from its top left corner. A 200 by 120 image in a 700 by 500 window gives `0 40 700 420` with `0 WINDOW-FIT`, `50 70 600 360` with 1 (3 times), and `0 0 700 500` with 2. It is reckoned from the window's size, the image's size, and `WINDOW-FIT` as they are when it is asked: just after one of them changed the window may not have drawn the image there yet, and a minimized window of the host's own gives the rectangle of the size it had. Four zeros without such a window, and before an image is shown. When `SHOW` shows in the Tk window, it is the rectangle there, in the same physical pixels (four zeros when Tk reports the window unmapped or hidden; XWayland may minimize without unmapping and retain the rectangle; just after the window was made smaller, the rectangle may reach outside it; it asks Tk three times, and up to nine while the window is being resized, so it is slower than for the host's own window): Tk lays the image out by whole factors with its proportions, in the middle, whatever `WINDOW-FIT` asked for (a 200 by 120 image in a 700 by 500 Tk window gives `50 70 600 360` with every `WINDOW-FIT`, and `62 87 750 450` on a display at 125%, where the window is 875 by 625 pixels). |
| `WINDOW-SMOOTH` | ( flag -- ) | How the host's own window makes the pixels it shows when the image is shown larger or smaller than it is. False (at first): each pixel shown takes the one pixel of the image it falls in; where the factor is not a whole number, some pixels of the image are wider or higher than others (letters and thin lines look uneven), and an image made smaller loses rows and columns. True: each pixel shown is the mean of the part of the image it covers; every pixel of the image is as large as every other, only the pixels on a border are a mix of the two sides (the picture is not blurred), and an image made smaller keeps something of every pixel. True is slower: on the machine measured, a loop that changes a pixel, calls `SHOW`, and waits with `WINDOW-PAINT-WAIT` took 0.9 to 4.3 milliseconds a frame (the median of the means of 200 frames, in four ways of showing), where false took 0.2 to 0.8 (a release build; a 320 by 200 to a 1280 by 800 image in a window up to 1700 by 1000). By a whole factor both show the same, and take the same time. It holds for the windows opened later too. Native Windows, Linux/X, and macOS windows support it. The common Tk implementation is verified on Windows; Linux/macOS Tk execution remains separate. Elsewhere the setting is kept. `IMAGE-SMOOTH` is another setting: how the words that turn an image read their source. |
| `WINDOW-FRAMES` | ( -- shown painted-through ) | `SHOW` gives the image to the host's own window and returns; the window draws it soon after, and when images come faster than it draws, only the latest. `shown` is the number of images `SHOW` gave the window in this run, and `painted-through` how many of them it had been given when it last drew: the two are equal when the window has drawn the latest. Both 0 where the host cannot tell. `painted-through` is a place in that count, not a number of images drawn: it passes over the images the window left out. |
| `WINDOW-PAINT-WAIT` | ( ms -- flag ) | Wait until the host's own window has drawn the whole of the image the last `SHOW` gave it, and tell whether it has. It waits ms milliseconds at most (a larger number than 60000 is taken as 60000); beside that, the call takes as long as the window takes to draw one image when it is drawing just then, and an image drawn in that time counts as drawn. False at once without such a window, false when the window is closed during the wait, and false when the time ran out (a minimized window does not draw). A key or Ctrl+C does not stop the wait, so give it a short time. It tells that the window drew the image, not that the image has reached the screen. On Linux the image counts as drawn when the X server has done the drawing it was sent. On macOS it counts as drawn when AppKit has drawn the window, which the window server then shows at its next composition; a minimized window still draws there (macOS keeps its picture in the Dock up to date), so the wait can tell true while minimized. |
| `VSYNC-WAIT` | ( -- flag ) | Wait until the system has next composed its screen, which it does at a display's refresh, and tell whether it has; false at once where the host cannot, and false when that took longer than a tenth of a second (a display that sleeps). While it tells true, a loop that draws, calls `SHOW`, and calls `VSYNC-WAIT` runs at the pace the system composes at, without `FRAME`; when it tells false it has not waited, so such a loop should fall back on `FRAME` then. After a wait that took too long, the word tells false at once until that composing has come; on a machine whose displays differ in their refresh rates, which display's pace that is is the system's choice. The system does not tell when an image has reached the screen, and this word does not either. Windows waits, using DwmFlush, until the screen has been composed once unless `SHOW` is using Tk (`DISPLAY-TK` or `DISPLAY-AUTO` choosing Tk), when it tells false at once; it is not the vertical sync of one display. Linux tells false at once because X has no simple way to wait for composition; macOS is unsupported and also tells false at once. |
| `MOUSE-CURSOR` | ( flag -- ) | Show (true) or hide (false) the mouse cursor over the graphics view in the native or Tk window; it shows at first. |
| `TERMINAL-BLOCKS`, `TERMINAL-SIXEL` | ( -- ) | Show the image on the terminal with half block characters (the default), or as Sixel graphics. |
| `DISPLAY-COLORS` | ( n -- ) | Make `SHOW` use full color (0, the default), or 2, 16, or 256 colors, for terminals that show fewer colors or for the look of older computers. 2 is black and white by brightness, 16 the ANSI colors (escapes 30 to 37 and 90 to 97; the nearest is chosen as xterm shows them by default, and other terminals may show them differently), 256 xterm's 6 × 6 × 6 cube and 24 grays (`ESC [ 38 ; 5 ; n m`). Sixel and the window use the same colors. The image keeps its colors, so files are saved in full color. Other values give `NUMBER ERROR !`. |
| `DITHER` | ( flag -- ) | With fewer colors, mix them in a 4 × 4 Bayer pattern (true) instead of taking the nearest (false, the default). The pattern stays in place, so animation does not flicker. |
| `GFX-INIT` | ( w h -- ) | Make a new black image. Each side is 1 to 16384 pixels, so the image is at most 1 GiB (4 bytes a pixel). The previous image stays when the new one cannot be made. |
| `GFX-WIDTH`, `GFX-HEIGHT` | ( -- n ) | The size of the image drawn on (see [Images](#images)), 0 for the screen before `GFX-INIT`. |
| `GFX-PSET` | ( x y rgb -- ) | Set one pixel to the color rgb. |
| `GFX-PGET` | ( x y -- rgb ) | The color of one pixel, -1 outside the image. |
| `CLIP!` | ( x y w h -- ) | From now on the drawing words change only the pixels of the image drawn on that are in the w by h rectangle at x y, and leave the others as they are: a game's playing field, its score panel, and its small map can each be drawn without care for the others. It holds for points, lines, rectangles, circles, `PAINT` (the area filled ends at the rectangle's edges), `CLS` (only the rectangle is cleared), text, `COPY-RECT` and `PUT-IMAGE`, `GFX-RGB`, and the game words that draw (sprites, tile maps, pictures of color numbers, `RASTER-SCROLL` and `RASTER-COLOR`). The rectangle is cut to the image; one that lies outside it leaves nothing to draw in. Each image has its own: after `DRAW-TO` another image the drawing goes by that image's, and back on this one by this one's again. A new image has none. Reading (`GFX-PGET`, the image a copy comes from) and `SHOW` are not clipped. A negative w or h gives `NUMBER ERROR !`. `DRAW-SPRITES` counts the sprites of each row whatever `CLIP!` says: a sprite outside the part that may be drawn in still takes its place on its rows. Of the GUI words (`REQUIRE-GUI`) only the drawing is cut, by the `CLIP!` of the image they draw on (`GUI-ASK`, `GUI-MESSAGE`, `GUI-CHOOSE`, and `GUI-CHOOSE-XT` draw on the screen, whatever image was drawn on before): where a part takes the mouse stays, so a part that is not drawn still takes a click; they leave `CLIP!` as it was. |
| `CLIP@` | ( -- x y w h ) | The part of the image drawn on that may be drawn in: `CLIP!`'s rectangle as it was cut to the image, or the whole image (0 0 and its size) without one. w or h is 0 when nothing may be drawn. |
| `NO-CLIP` | ( -- ) | Let the drawing words draw in all of the image drawn on again. |
| `IMAGE-KEEP-ALPHA` | ( flag -- ) | Whether `LOAD-IMAGE` keeps the file's alpha (how much each pixel shows, from an alpha channel, a PNG `tRNS` chunk, or a BMP alpha mask) in the image's pixels (true), or makes the image opaque, with the `TRANSPARENT` color for the pixels more than half transparent (false, at first, as before). An image with alpha is for `IMAGE-MODE` 4 and 5: soft edges, smoke, glass. Its colors are as in the file, not multiplied by the alpha. |
| `IMAGE-MODE` 4, 5 | | Beside the modes 0 to 3: 4 puts each pixel of the source over the pixel there by the source pixel's own alpha (0 leaves the pixel there, 255 replaces it, and over an opaque pixel 128 mixes the two half and half), and 5 by that alpha times `IMAGE-ALPHA` / 255, to fade the whole. On an opaque image the result is opaque; on an image with alpha the alphas are combined, so that images can be composed before they are shown. The `TRANSPARENT` color is left out first, as in the other modes, which keep their results: they do not look at the alpha. |
| `GFX-ALPHA-PSET` | ( x y a -- ) | Give pixel x y of the image drawn on the alpha a (0 to 255); its color stays. For an image of `NEW-IMAGE`, to make one with alpha by drawing; it follows `CLIP!`. The screen has no alpha to set (`INVALID IMAGE HANDLE`): it is always opaque, whatever is copied to it. |
| `GFX-ALPHA-CLS` | ( a -- ) | Give every pixel of the image drawn on (the part `CLIP!` lets be drawn in) the alpha a; their colors stay. Without a `CLIP!`, `0 GFX-ALPHA-CLS` makes the image wholly transparent. Not for the screen. The drawing words (lines, shapes, text) make the pixels they draw opaque; to draw a half-transparent shape, draw it on an image made transparent with `0 GFX-ALPHA-CLS` and copy that image with `IMAGE-MODE` 5 and `IMAGE-ALPHA` (for example 128 for half). |
| `GFX-IMAGE-ALPHA@` | ( img x y -- a \| -1 ) | The alpha of pixel x y of any image: 255 for an opaque pixel (every pixel of the screen, and of an image made without alpha), -1 outside the image. |
| `COPY-ROTATED-RECT` | ( src sx sy w h cx cy angle100 xscale1000 yscale1000 -- ) | Put the w by h rectangle at sx sy of image src on the image drawn on, turned and made larger or smaller: a ship that turns, a shot that spins, a picture that zooms. The rectangle's pixel at w/2 h/2 comes to the pixel cx cy, and the rectangle is turned around it clockwise by angle100, in hundredths of a degree (9000 is a quarter turn; any number, also negative), and made xscale1000 and yscale1000 thousandths as large along its own width and height (1000 as it is, 2000 twice, 500 half; 1 to 64000). `TRANSPARENT`, `IMAGE-MODE`, `IMAGE-ALPHA`, and `CLIP!` hold as for `COPY-RECT`; `IMAGE-FLIP` and `IMAGE-SCALE` do not. Parts outside either image are left out. With angle100 0 and both factors 1000 it draws what `COPY-RECT` draws at cx − w/2, cy − h/2. The image drawn on cannot be its own source (`NUMBER ERROR !`, as for factors outside 1 to 64000). All is reckoned in whole numbers when it runs, so an executable draws the same pixels on every machine, and a build without the floating-point words draws them too. |
| `PUT-ROTATED` | ( src cx cy angle100 scale1000 -- ) | The whole image src with its middle at cx cy, turned by angle100 and scale1000 thousandths as large both ways: `SHIP 160 100 4500 1000 PUT-ROTATED` draws it turned by 45 degrees. |
| `IMAGE-SMOOTH` | ( flag -- ) | How `COPY-ROTATED-RECT` and `PUT-ROTATED` take each pixel they draw from the source: the pixel of the source the place falls in (false, at first; sharp, as old machines drew), or the four pixels around it weighed by how near they are (true; smoother, and slower). When smooth, a pixel at the rectangle's edge, or beside the `TRANSPARENT` color, shows only in part: `IMAGE-MODE` 4 puts it over the ground by that part, which gives soft edges; the modes 0 to 3 draw it when it shows at least half. Made smaller than half, each pixel still reads only the four source pixels around it, so thin lines can be lost; for a much smaller picture, prepare a smaller image beforehand. |
| `GFX-HLINE` | ( x1 x2 y rgb -- ) | A horizontal line from x1 to x2, both included. |
| `GFX-CLS` | ( rgb -- ) | Fill the whole image with the color rgb; with a `CLIP!`, the part that may be drawn in. |
| `GFX-SAVE-PPM`, `GFX-SAVE-BMP`, `GFX-SAVE-PNG` | ( c-addr u -- ior ) | As `SAVE-PPM`, `SAVE-BMP`, and `SAVE-PNG`, but return ior (0 or the error) instead. They also work in a build with `-Dfiles=false`. |
| `GFX-SAVE-PNG-ALPHA` | ( c-addr u -- ior ) | Save as SAVE-PNG-ALPHA but return ior; available with -Dfiles=false too. |
| `GFX-SHOW-BLOCKS`, `GFX-SHOW-SIXEL`, `GFX-SHOW-WINDOW` | ( -- ) | Show the image on the terminal with half blocks, as Sixel, or in the window. |
| `GFX-WINDOW?` | ( -- flag ) | True when the host can show the image in a window. |
| `GFX-COLOR-MODE` | ( n flag -- ) | The colors of the `GFX-SHOW-` words, as `DISPLAY-COLORS` and `DITHER` (which `SHOW` passes each time). |

The `GFX-` words are the base the library is written with; the other words are Forth definitions, so `SEE`, `LOCATE`, and `WHERE` show them. So that the arithmetic cannot overflow, coordinates and sizes are first limited to -2^61 .. 2^61 for `LINE`, `RECT`, and `FILL-RECT`, and to -2^30 .. 2^30 for the circles (a circle with a value beyond that is drawn with the value moved to the limit). `PAINT` keeps the rows still to fill in the heap; a very complicated area can need more than the heap has and then gives `CANNOT ALLOCATE MEMORY !` (THROW -524, the area is then partly filled).

Errors: a size outside the limits gives `NUMBER ERROR !`; an image the host cannot allocate gives `OUT OF MEMORY !`; using the image before `GFX-INIT` gives `NO GRAPHICS IMAGE !` (THROW -271); and `REQUIRE-GRAPHICS` in a build with `-Dgraphics=false` gives `GRAPHICS UNAVAILABLE !` (THROW -270). If the library fails to load, everything `REQUIRE-GRAPHICS` added is removed again. `REQUIRE-GRAPHICS` loads the words again after `FORGET` or a `MARKER` has removed the `GRAPHICS` vocabulary or `GFX-INIT`; when only later words were forgotten (such as `FORGET GFX-WIDTH`), it does nothing and they stay removed.

To try a changed copy of the library without rebuilding Sigma, load the built-in one and then include the copy into `GRAPHICS`; its words replace the built-in ones: `REQUIRE-GRAPHICS ALSO GRAPHICS DEFINITIONS DECIMAL INCLUDE src/graphics/graphics.fs`.

On the terminal, each character shows two pixels, one above the other, with 24-bit color escapes, which most terminals understand (Windows Terminal and the Windows console, xterm, GNOME Terminal, and so on). An image larger than the terminal is made smaller to fit, keeping its proportions, and each new pixel has the average color of the pixels it stands for; one line is left for the prompt. When the output is not a terminal (a pipe or a file), 80 columns and 24 rows are assumed. Sixel graphics (`TERMINAL-SIXEL`) show real pixels on terminals that support it, with 216 colors; a terminal without Sixel may show stray characters or nothing. On Windows, the console shows the half blocks with the UTF-8 code page, which Sigma sets while it writes them and then sets back.

On Windows, the window has a thread of its own: while Forth waits for input it can be moved, resized (the image is stretched to fit), and closed, and the keyboard stays with the console. Each `SHOW` draws the current image in it again and fits the window to a new image size, or to the size `WINDOW-SIZE` gave (without it, an image larger than 1600 by 1200 pixels, or than the work area of the monitor without the taskbar, is shown smaller), and moves the window into the work area as far as it fits. From Windows 10 1703 the window is aware of each monitor's DPI: its sizes are the screen's pixels, so Windows does not stretch the image, and on a monitor scaled above 100% a window of the same `WINDOW-SIZE` looks smaller than in versions of Sigma before this (where Windows enlarged it). A window moved to a monitor of another DPI keeps its client area in proportion to the DPIs (640 by 400 at 100% becomes 960 by 600 at 150%). On older Windows the window is unaware of DPI. When the window is resized, the image keeps its proportions in it, with black around it, and `MOUSE` gives the pixel of the image under the mouse. Buttons held when the window loses the focus or the mouse are released (`MOUSE-EVENT` tells the release), and after the window is closed `MOUSE` gives -1 -1. A window that was closed is opened again by the next `SHOW` (an image shown at the very moment the window is being closed may not appear until then). `SHOW` waits at most 5 seconds for a window to be made (when automatic display chooses for the first time, the window and the Tk window share 5 seconds, the window at most 2), and when the time runs out the window is not tried again until Sigma ends. Automatic display then goes on to the Tk window or the terminal when it is choosing for the first time; when it had already chosen the window, that `SHOW` gives `HOST FUNCTION ERROR` (-265) and the next goes on. With `DISPLAY-WINDOW`, `SHOW` gives -265. macOS has a window of its own too (AppKit), and Linux has one on X11 or XWayland (see the top of this page); elsewhere `SHOW` uses the Tk window on a desktop with Tcl/Tk, and the terminal otherwise.

The image is not part of the dictionary: `SAVE` and `SAVESYS` keep the graphics words and the words that use them, but not the pixels, so a program makes its image with `GFX-INIT` after it starts. A dictionary keeps the graphics library it loaded: `REQUIRE-GRAPHICS` does not add the words of a newer library to it, so build such a dictionary again from its source to use them.

### Where the display and window words work

On Linux these coordinates and sizes use X server pixels. Under XWayland, compositor scaling can make these differ from physical display pixels. Tk geometry was checked at scale 1; other physical display scales remain unverified. Each Linux Tk size query opens a bounded X connection (up to two seconds); `WINDOW-IMAGE-RECT` may query up to three times. Avoid querying it on every frame when the window size is unchanged.

The words that begin with `DISPLAY-` are of two kinds: `DISPLAY-WINDOW`, `DISPLAY-TK`, `DISPLAY-TERMINAL`, and `DISPLAY-AUTO` choose where `SHOW` shows, `DISPLAY-COLORS` sets how many colors `SHOW` uses, and `DISPLAYS`, `DISPLAY-RECT`, `DISPLAY-WORK`, `DISPLAY-SCALE`, `DISPLAY-HZ`, and `DISPLAY-PRIMARY` tell of the displays (the monitors) connected. The words that draw (`CLIP!`, the alpha of pixels, `COPY-ROTATED-RECT`, `GFX-RGB`, and all the others on an image) work the same on every system and wherever `SHOW` shows. The display words need the host's help: Windows provides them, Linux under X provides display data, native-window state and Tk size/image-rectangle data, and macOS provides display data plus `WINDOW-DISPLAY` for its own native AppKit window. macOS starts a short-lived probe for each `DISPLAYS` call. Its approximate mixed-scale layout can differ from macOS's arrangement. On a 2x built-in and a 1x external display, a nonzero offset along the shared edge, changes of arrangement and resolution, unplugging and replugging, and mirroring were each seen by the next `DISPLAYS`; mirrored displays count as one display, as macOS shows them as one screen. Changing either display's backing scale between 1x and 2x while Sigma ran was seen too. When the display holding the window was unplugged, macOS moved the window and `WINDOW-DISPLAY` gave the primary display; after replugging, macOS moved it back and `WINDOW-DISPLAY` gave the external display again. macOS may give the number of a removed display to another monitor; Sigma tells displays apart by that number together with the monitor's vendor, model and serial numbers, so a window on such another monitor gives -1 until the next `DISPLAYS` rather than the index of the removed one (two monitors of one model without serial numbers cannot be told apart). The Tk-window and terminal columns describe runs where the host's own window was never opened; in that terminal case `WINDOW-DISPLAY` is -1 on macOS too. Counts of windows that were opened and closed remain as they were. Choosing `DISPLAY-TK` or `DISPLAY-TERMINAL` does not close the host's own window. With the terminal selected, `WINDOW-DISPLAY` still reports that native window while it stays open. With the terminal selected, the four state words report the native window. With Tk selected, `WINDOW-DISPLAY` gives -1 on Linux and macOS even if the native window stays open; the four state words (`WINDOW-OPEN?`, `WINDOW-FOCUSED?`, `WINDOW-MINIMIZED?`, `WINDOW-CLOSES`) report the Tk window instead. On macOS, Aqua Tk sends no focus-out event when the window is minimized, so Sigma also releases held keys when the Tk window is unmapped. `WINDOW-FIT` always lays out the native window.

| Words | Windows, own window | Windows, Tk window | Windows, terminal | Linux with X, own window | Linux with X, Tk | macOS | Linux terminal |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `DISPLAYS`, `DISPLAY-RECT`, `DISPLAY-WORK`, `DISPLAY-SCALE`, `DISPLAY-HZ`, `DISPLAY-PRIMARY` | yes | yes | yes | yes with RandR 1.5 and X11 build (separate X connection; two seconds for the whole call; 0 if the monitor list times out; scale unknown) | as with own window | yes; three-second probe, 0 displays on failure | as with own window |
| `WINDOW-DISPLAY` | yes | yes | -1 | yes | -1 | own native window; Tk gives -1; terminal gives -1 if no native window is open | -1 |
| `WINDOW-PIXELS` | yes | yes | 0 0 | yes | yes | own native window, in backing pixels; 0 0 with Tk or the terminal | 0 0 |
| `WINDOW-CHANGES` | yes | 0 | 0 | yes (display changes are not counted) | 0 | own native window | 0 |
| `WINDOW-OPEN?`, `WINDOW-FOCUSED?`, `WINDOW-MINIMIZED?`, `WINDOW-CLOSES` | yes | Windows transitions verified | false, 0 | yes | yes | own native window; Tk: yes (verified by Tcl-driven transitions) | false, 0 |
| `WINDOW-KEEP-OPEN`, `WINDOW-CLOSE` | yes | yes, verified on Windows | native setting/control | yes | implemented, unverified | own native window; Tk: yes (verified by Tcl-driven close requests) | native setting/control |
| `WINDOW-FIT` | yes | wish kept; Tk uses whole factors | wish kept | yes | wish kept; Tk uses whole factors | own native window; wish kept with Tk or the terminal | wish kept |
| `WINDOW-ON` | written, not yet run | wish kept | wish kept | written, not yet run | wish kept | own native window; wish kept with Tk or the terminal | wish kept |
| `WINDOW-IMAGE-RECT` | yes | yes | four zeros | yes | yes (whole factors) | own native window, in backing pixels; four zeros with Tk or the terminal | four zeros |
| `WINDOW-SMOOTH` | yes | wish kept | wish kept | yes | native only | own native window; wish kept with Tk or the terminal | wish kept |
| `WINDOW-FRAMES`, `WINDOW-PAINT-WAIT` | yes | 0 0, false | 0 0, false | yes | 0 0, false | own native window; 0 0, false with Tk or the terminal | 0 0, false |
| `VSYNC-WAIT` | yes | false (Tk unsupported) | yes | false | false | false | false |

A program finds out by asking: the words without a display's number do not fail where they are not supported. `DISPLAY-RECT`, `DISPLAY-WORK`, `DISPLAY-SCALE`, and `DISPLAY-HZ` give `NUMBER ERROR !` for a number `DISPLAYS` did not count, so they are not to be called where `DISPLAYS` gave 0. `DISPLAYS` giving 0 says the displays cannot be told; `WINDOW-OPEN?` false after `SHOW` says the selected target has no open window when that state is supported (for Tk it refers to the Tk window); on hosts without state support it also means that no state is available; `VSYNC-WAIT` false says the program must keep its own pace with `FRAME`. No value is made up: what cannot be told is 0, -1, false, or, for a display that is there, a fraction with the denominator 0. `VSYNC-WAIT` is always false when `SHOW` is using Tk (`DISPLAY-TK` or `DISPLAY-AUTO` choosing Tk); it can also be false on Windows when `DwmFlush` cannot wait.

The four Tk state words query the selected Tk window. WINDOW-CLOSE also follows the selected Tk window. WINDOW-KEEP-OPEN sets native and Tk behavior. WINDOW-CHANGES still reports native information. With Tk selected, WINDOW-FRAMES returns 0/0 and both waits return false, without borrowing native results. Changing the selected backend does not close an existing native window. Do not compare close-counter deltas across backend selections.

Tk state queries wait for a reply and process pending input/events, while preserving user TCL-EVAL results and TCL-ERROR$. Snapshot replies and close controls do not allocate logical heap memory; pending user events or Ctrl+C can still raise exceptions and stop wish to avoid consuming an abandoned reply. TCL-STOP drains at most 64 messages and at most 64 KiB of ordinary payload per read, retaining only close controls. Notifications beyond that bound are not counted. Replacing the WM_DELETE_WINDOW handler also replaces the standard close notification.

Without X11 support Linux can only use Tk's minimization cache. It may miss XWayland minimization that leaves the X window mapped; the normal X11 build prefers WM_STATE when available. Immediately after an iconify request it can still report false until the WM changes the state; focus may also briefly report false while Tk and the WM disagree. Each state word makes a Tcl round trip and, while open, a separate bounded X connection for WM_STATE (up to two seconds); avoid redundant calls every frame. Windows Tk state acceptance (1295) is complete. Linux Tk close-control testing remains (tque 1337); macOS Tk state and close-control testing remains (tque 1299 and 1338).

All of this is of the run: the displays `DISPLAYS` took, `CLIP!`, `WINDOW-FIT`, and the counts are not kept in a dictionary image (`SAVESYS`, `SAVE`), and a newly started Sigma begins with none. Restoring an image into a Sigma that is running clears the screen and the images, and leaves the host's window, the `WINDOW-FIT` chosen, the counts, and the displays `DISPLAYS` took as they were. A build without the graphics words (`-Dgraphics=false`) has none of these words.

### Images

Besides the image of `GFX-INIT`, the screen, a program can make images to draw on and copy from, as the pages of the MSX2 and the blitter of the Amiga do: sprites, tiles, a background, or a picture drawn once and copied many times. A handle names each image, and `SCREEN` (0) names the screen. The drawing words (`PSET`, `LINE`, `TEXT`, `PAINT`, and so on), `GFX-WIDTH`, `GFX-HEIGHT`, and the `SAVE-` words use the image `DRAW-TO` chose; `SHOW` always shows the screen.

| Word | Stack | What it does |
|---|---|---|
| `NEW-IMAGE` | ( w h -- img ) | Make a black image, each side 1 to 16384. At most 256 images, 1 GiB in all (the screen not counted); more gives `OUT OF MEMORY !`. |
| `FREE-IMAGE` | ( img -- ) | Free an image. Its handle no longer names an image; when it was drawn on, drawing goes back to the screen. |
| `IMAGE-SIZE` | ( img -- w h ) | The width and height of an image, or of the screen (0 0 before `GFX-INIT`). |
| `SCREEN` | ( -- 0 ) | The handle of the screen. |
| `DRAW-TO` | ( img -- ) | Draw on an image from now on; `SCREEN DRAW-TO` draws on the screen again. |
| `DRAWING` | ( -- img ) | The handle of the image drawn on. |
| `COPY-RECT` | ( src sx sy w h dx dy -- ) | Copy the w by h rectangle at sx sy of image src to dx dy of the image drawn on. Parts outside either image are left out. Within one image the two rectangles may overlap; each pixel is read before it is written over. |
| `PUT-IMAGE` | ( src x y -- ) | Copy the whole image src to x y of the image drawn on. |
| `TRANSPARENT` | ( rgb\|-1 -- ) | `COPY-RECT` and `PUT-IMAGE` leave out the pixels of this color; -1 (the start) leaves out none. |
| `IMAGE-FLIP` | ( n -- ) | `COPY-RECT` and `PUT-IMAGE` flip the rectangle: 0 not (the start), 1 left and right, 2 top and bottom, 3 both. Other values give `NUMBER ERROR !`. |
| `IMAGE-MODE` | ( n -- ) | How `COPY-RECT` and `PUT-IMAGE` put the pixels: 0 over those there (the start), 1 XOR, 2 added (each of red, green, and blue at most 255), 3 mixed with them by `IMAGE-ALPHA`. The transparent color is left out first. 4 and 5 are in the table above. The numbers have names: `MODE-COPY` (0), `MODE-XOR` (1), `MODE-ADD` (2), `MODE-BLEND` (3), `MODE-SOURCE-OVER` (4), `MODE-SOURCE-OVER-FADE` (5). |
| `IMAGE-ALPHA` | ( n -- ) | How much of the copy mode 3 shows: 0 none, 255 all, 128 at the start. Each color is `(copy × n + there × (255 − n) + 127) ÷ 255`. |
| `IMAGE-SCALE` | ( n -- ) | `COPY-RECT` and `PUT-IMAGE` draw each pixel n by n, 1 (the start) to 16, so the rectangle is w × n by h × n on the image drawn on; flipping, the transparent color, and the mode apply as well. The pixels are not mixed; for a smooth enlargement that mixes colors and alpha, use `COPY-ROTATED-RECT` with the angle 0 and `TRUE IMAGE-SMOOTH`. |
| `LOAD-IMAGE` | ( c-addr u -- img ) | Read a PNG, BMP, or PPM/PGM file into a new image (see below). |

`LOAD-IMAGE` reads PNG files of every color type and bit depth, also interlaced (Adam7); BMP files of 1, 4, 8, 16, 24, and 32 bits, with the rows from the bottom or from the top, with color masks (`BI_BITFIELDS`), and with the old 12-byte header, but not RLE-compressed ones; and PPM and PGM files, binary (P6, P5) and plain text (P3, P2), with any maximum value up to 65535. Samples of 16 bits keep their high byte; fewer bits are spread over 0 to 255. Images are opaque, so a pixel more than half transparent (alpha below 128, from an alpha channel, a PNG `tRNS` chunk, or a BMP alpha mask) gets the color `TRANSPARENT` gave, and black when it gave -1: load a sprite after `TRANSPARENT` and `PUT-IMAGE` leaves out its transparent part. A file that cannot be opened or read throws its ior; a file of another kind, or a damaged one (PNG checks the CRC of each chunk and the checksum of the compressed data), gives `IMAGE FORMAT ERROR !` (THROW -279); a picture larger than 16384 a side gives `NUMBER ERROR !`. The whole file is read into memory outside the dictionary for a moment, so a file can be at most 2 GiB. It also works in a build with `-Dfiles=false`.

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
320 200 GFX-INIT
16 16 NEW-IMAGE CONSTANT BALL
BALL DRAW-TO  $FF00FF GFX-CLS  255 255 0 COLOR  8 8 7 FILL-CIRCLE  SCREEN DRAW-TO
$FF00FF TRANSPARENT
: BALLS ( -- )   10 0 DO  BALL I 30 * 10 + 90 PUT-IMAGE  LOOP ;
BALLS  1 IMAGE-FLIP BALL 0 0 PUT-IMAGE  0 IMAGE-FLIP  SHOW
```

A handle that names no image (never made, freed, or kept from before `SAVE` or `SAVESYS`) gives `INVALID IMAGE HANDLE !` (THROW -278). Flipping or scaling a rectangle onto an overlapping place of the same image gives `NUMBER ERROR !`; copy it through another image. Other values of `IMAGE-FLIP`, `IMAGE-MODE`, `IMAGE-ALPHA`, and `IMAGE-SCALE` give `NUMBER ERROR !` too. Images are not part of the dictionary, like the screen: restoring a dictionary (and starting an executable made by `SAVESYS`) frees them all, so a program makes its images after it starts. A handle kept in a variable of a saved dictionary may then name a new image by chance, when the new image has the same place and generation; make the images again rather than keep their handles. `TRANSPARENT`, `IMAGE-FLIP`, `IMAGE-MODE`, `IMAGE-ALPHA`, and `IMAGE-SCALE` are variables of the library, saved with the dictionary as `COLOR` is. The `GFX-` words underneath are `GFX-IMAGE-NEW` ( w h -- img ), `GFX-IMAGE-FREE` ( img -- ), `GFX-IMAGE-SIZE` ( img -- w h ), `GFX-TARGET` ( img -- ), `GFX-TARGET@` ( -- img ), `GFX-COPY` ( src sx sy w h dx dy key flip mode alpha scale -- ), whose key is the transparent color or a negative number for none, and `GFX-IMAGE-LOAD` ( c-addr u key -- img ior ), whose key is the color of the transparent pixels.

### Text

`TEXT` draws a string with the current font. At first that is the built-in font: the ASCII characters of Misaki Gothic (美咲ゴシック by Num Kadoma, free to use; see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)), 4 pixels wide and 8 high. `LOAD-FONT` reads a BDF font file instead, on every system, and `SYSTEM-FONT` uses a font installed in the system by its name, on Windows, macOS, and Linux. The string is read as UTF-8; a character the font does not have is drawn as one `?` (or not at all when the font has no `?` either), and so is each byte that is not UTF-8. Control characters are not drawn.

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
| `SYSTEM-FONT` | ( c-addr u height -- ) | Use the system's font of that name (on Windows such as `Consolas`, `MS Gothic`, or `メイリオ`; on macOS such as `Hiragino Sans`, `HiraginoSans-W3`, `ヒラギノ角ゴシック`, or `Osaka`; on Linux such as `DejaVu Sans` or `Noto Sans CJK JP`), height pixels a line (1 to 256), smoothed in shades of gray. On macOS the name is a family, full, or PostScript name, also as the user's language shows it. On Linux Sigma reads the font files itself (TrueType and OpenType: `.ttf`, `.otf`, `.ttc`, `.otc`) under `/usr/share/fonts`, `/usr/local/share/fonts`, `~/.local/share/fonts` (or `$XDG_DATA_HOME/fonts`), and `~/.fonts`, and takes the font whose family, full, or PostScript name is the given one, in any language and without regard to the case of ASCII letters; of a family it takes the regular font. A name with a `/` in it is the path of a font file there (the first font of a collection). No font is part of Sigma. Some OpenType fonts that build accented letters from two glyphs (URW's `C059`, for one) show them without the accent, and a font file is not checked for damage, so give only font files you trust. A character the font does not have is drawn as `?`, not taken from another font; on Windows so are the characters from U+10000 up. `FONT ERROR !` when the system has no font of the name (on Linux also when the file at the path is no font). |
| `BUILTIN-FONT` | ( -- ) | Use the built-in font again. |
| `GFX-GLYPH-LOAD` | ( code -- advance \| -1 ) | Load the glyph of a code point in the current font and give how far it moves the pen; -1 when the font has none. |
| `GFX-GLYPH-BOX` | ( -- left width height ) | The box of the loaded glyph: from `left` pixels right of the pen (negative: to the left) and from the top of the line. |
| `GFX-GLYPH-ALPHA` | ( x y -- a ) | The coverage of the loaded glyph at x y of its box, 0 (none) to 255 (full); 0 outside the box. |
| `GFX-FONT-HEIGHT` | ( -- h ) | The height of a line of the current font. |
| `GFX-FONT-LOAD`, `GFX-FONT-SYSTEM`, `GFX-FONT-BUILTIN` | ( c-addr u -- ior ), ( c-addr u height -- ior ), ( -- ) | As `LOAD-FONT`, `SYSTEM-FONT`, and `BUILTIN-FONT`, but returning ior (0, the file's error, or -272). |

The font is not part of the dictionary: `SAVE` and `SAVESYS` do not keep it, and a program starts with the built-in font, as it starts without an image. A BDF font is kept outside logical memory. With `LOAD-FONT`, any BDF font can be used, for example the whole of Misaki Gothic with its kanji (`misaki_gothic.bdf` from <https://littlelimit.net/misaki.htm>); the same program then draws the same pixels on every system. A system font draws differently on different systems, and the names of the fonts differ too.

### Tcl/Tk

The TCL words run Tcl scripts in a Tcl/Tk interpreter (`wish`) that Sigma starts as a program of its own, the first time it is needed, and talks to through pipes; no Tcl library is linked into Sigma. With it, a program can use Tk's widgets, and `DISPLAY-TK` shows the image in a Tk window, also where Sigma has no window of its own. Tcl/Tk must be installed: Sigma uses the program named by `TCL-PROGRAM`, else by the environment variable `SIGMA_WISH`, else `wish` on the `PATH`, and on Windows, else the one Git for Windows comes with (`Git\mingw64\bin\wish.exe` under `%ProgramW6432%`, `%ProgramFiles%`, or `%LOCALAPPDATA%\Programs`; usually `C:\Program Files\Git\mingw64\bin\wish.exe`). On Linux it is in the `tk` package. On macOS, install it with `brew install tcl-tk`: the system's `/usr/bin/wish` (Tcl/Tk 8.5) no longer starts on recent macOS, so Sigma passes over it on the `PATH`, and when the `PATH` has no other `wish`, uses Homebrew's (`/opt/homebrew/bin/wish`, `/usr/local/bin/wish`) or MacPorts's (`/opt/local/bin/wish`), the first that is there.

```forth
REQUIRE-GRAPHICS  ALSO GRAPHICS
S" expr {6 * 7}" TCL-EVAL TYPE                  \ 42
S" button .b -text Press -command {sigma_event pressed}; pack .b; wm deiconify ." TCL
: WAIT-PRESS   BEGIN TCL-EVENT 0= WHILE 10 MS REPEAT TYPE ;
WAIT-PRESS                                       \ pressed, after the button is pressed
```

`examples/calculator.fs` is a whole program: a calculator whose buttons and keys are Tk's and whose arithmetic is Forth's (`sigma.exe < examples/calculator.fs`). `examples/graphs-tk.fs` draws the eight graphs of `examples/graphs.fs` on a Tk canvas, as its lines, rectangles, arcs, ovals, and text: Forth works out where everything goes and sends the Tcl script of each frame in one piece.

| Word | Stack | Description |
| --- | --- | --- |
| `TCL` | ( c-addr u -- ) | Run a Tcl script (UTF-8) at the global level. `TCL ERROR !` (THROW -273) when it fails. |
| `TCL-EVAL` | ( c-addr u -- c-addr2 u2 ) | Run a Tcl script and give its result, which stays until the next script. |
| `TCL-ERROR$` | ( -- c-addr u ) | The message of the last script that failed. |
| `TCL-EVENT` | ( -- c-addr u true \| false ) | The next text the Tcl side sent with `sigma_event` (for example from a button's `-command`), without waiting; the text stays until the next `TCL-EVENT`. |
| `TCL-PROGRAM` | ( c-addr u -- ) | The program to start next time (a name on the `PATH` or a path); empty for `SIGMA_WISH`, `wish`, Git for Windows's, or on macOS Homebrew's or MacPorts's. |
| `TCL-STOP` | ( -- ) | Stop the Tcl program. Retain received close controls within the drain limits above and discard other unread messages. Cleanup failure raises HOST FUNCTION ERROR and is retried. |
| `DISPLAY-TK` | ( -- ) | Make `SHOW` show the image in the Tk window `.` (sent as a PNG, in the colors of `DISPLAY-COLORS`). Keys pressed and the mouse in it come to `INKEY` and `MOUSE`. Closing the window hides it until the next `SHOW`. With `WINDOW-SIZE`, the image is shown as large as fits by a whole factor (Tk zooms only so), or smaller by a whole factor when it does not fit, also when the window is resized. |
| `GFX-TCL`, `GFX-TCL-ERROR`, `GFX-TCL-EVENT`, `GFX-TCL-PROGRAM`, `GFX-TCL-STOP`, `GFX-SHOW-TK` | | The words underneath; `GFX-TCL` ( c-addr u -- c-addr2 u2 flag ) gives the result, or for an error of the script the message with a true flag, instead of throwing. When the program cannot be started or has ended, it too gives `HOST FUNCTION ERROR !`. |

When the program cannot be started or ends, the word gives `HOST FUNCTION ERROR !` (THROW -265), and the next one starts it again. A script runs until it returns, so a script that waits (such as `vwait`) holds Sigma too; Ctrl+C pressed in the Tk window meanwhile throws `USER INTERRUPT !` and ends the program, which the next script starts again. A script ending with `return`, `break`, or `continue` gives its result as any other; only an error is `TCL ERROR !`. The results and events are kept in the heap, and `SAVE` and `SAVESYS` free them first, so a string a TCL word gave before is not valid after them; a message still coming at that moment is dropped, and the program goes on. While more than 4 MiB that Sigma has not read wait in the program (Sigma reads only in the TCL words, `INKEY`, `KEY-HELD?`, and `MOUSE`), the program drops new events, keys pressed, and mouse reports; results and the releases of keys are always sent. Each `SHOW` sends the whole image, so large images update slowly. The Tcl side's protocol is in `src/graphics/sigma_tk.tcl`.

### Keys, the mouse, and animation

`INKEY` reads a key without waiting, from the terminal and from the window, and `MOUSE` gives the pixel of the image under the mouse. `KEY`, `KEY?`, and `ACCEPT` are not changed: they still read a line (which Sigma edits for `ACCEPT` on a terminal on Linux and macOS).

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

`examples/paddle.fs` is a whole game with these words: a ball that bounces off three walls and a paddle moved with the Up and Down keys (`sigma.exe examples/paddle.fs`). `examples/runner.fs` (Classic Runner) is a larger one: a tile game where the runner climbs ladders, hangs on ropes, digs holes, and collects gold while guards chase it; the line at the bottom shows how long the game's work takes each frame and the frames shown each second. `examples/hopper.fs` (Sky Hopper) is a side-scrolling platform game: the hopper runs and jumps through two courses, stamps on enemies, kicks shells, bumps blocks for coins and a berry that makes it big, and rides the balloon at the end; it takes the keys and a mapped gamepad. `examples/shmup.fs` (Sigma Storm) is a vertical scrolling shooter: three stages with their waves, a carrier half way, and bosses in parts, a weapon of five levels, bombs, and a chain that multiplies the score. It takes the keys and a mapped gamepad, has tunes and sound effects of its own, and F1 shows the time each frame takes. `examples/shmup-c64.fs` and `examples/shmup-amiga.fs` are the same vertical shooter as `examples/shmup.fs` in the style of the Commodore 64 and of the Amiga, with the screens, colors, and sound of those machines. The three are drawn with the game words: their pictures are sprites on a sheet, a shot hits an enemy where their pixels meet (`PIXEL-HIT?`), the backgrounds are pictures of color numbers whose water colors turn on the ocean (the Amiga's copper is a palette for each band of lines, drawn with `GFX-INDEXED`), and clouds are half seen, explosions, lasers, and shots glow by adding their light, and a bomb or a boss blowing up ripples the rows (`RASTER-SCROLL`). `examples/klondike.fs` is the Klondike patience game, played with `MOUSE`: drag cards and runs, click a card to send it where it can go, draw 1 or 3, undo, and hints. It paints all its cards when it starts and draws them as spans of `GFX-HLINE`. `examples/waterworks.fs` (Waterworks) is a game of laying pipe ahead of the water on a blueprint, with 8 stages of rocks, tanks, pumps, tunnels, and drains; it takes the mouse or the keys. `examples/sweeper.fs` (Sonar Sweep) is a game of finding mines on the sea bed from numbers: three sea areas of different sizes, where the first square opened and those around it never hold a mine; it takes the mouse or the keys. `examples/pinball.fs` (Ninth Inning) is a pinball table of a ballpark on painted wood, laid out after a picture of an old table: four lanes that raise the bonus multiplier, a bank of four drop targets, three targets, a dugout hole and a kickout hole, and runners on a diamond who score runs when they come home. The ball's physics is in fixed point, 8 steps to a frame.

| Word | Stack | Description |
| --- | --- | --- |
| `INKEY` | ( -- key \| -1 ) | The next key pressed, without waiting; -1 when there is none. A character gives its byte (each byte of a UTF-8 character in turn), Enter 13, Backspace 8, Tab 9, Esc 27. Ctrl+C throws `USER INTERRUPT !` (-28). |
| `K-UP`, `K-DOWN`, `K-LEFT`, `K-RIGHT`, `K-HOME`, `K-END`, `K-PRIOR`, `K-NEXT`, `K-INSERT`, `K-DELETE`, `K-F1` .. `K-F12` | ( -- key ) | The codes `INKEY` gives for the keys that are not characters: 256 to 277. |
| `MOUSE` | ( -- x y buttons ) | The pixel of the image under the mouse when it last moved, and the buttons held: 1 left, 2 right, 4 middle. -1 -1 while the position is not known. Keys pressed meanwhile wait for `INKEY`. |
| `MOUSE-EVENT` | ( -- x y button kind true \| false ) | The oldest event of the mouse not yet read, without waiting, or false: kind 1 a button pressed, 2 released (button 1 left, 2 right, 4 middle), 3 a notch of the wheel (button 1 up, away from the user, -1 down), at the pixel x y of the image. A press and a release between two reads are both kept, unlike `MOUSE`. 64 events are kept; when more come, the oldest are dropped. Keys read meanwhile wait for `INKEY`. The terminal reports the wheel when `MOUSE-ON` asked it (sideways turns are not told); the Tk window reports it from `<MouseWheel>` and, on X11, from buttons 4 and 5. |
| `MOUSE-ON`, `MOUSE-OFF` | ( -- ) | Have the terminal report the mouse, or stop. The window always reports it. |
| `FRAME` | ( ms -- ) | Wait until ms milliseconds have passed since the last `FRAME`, then `SHOW`. A loop that draws and calls `FRAME` runs at a steady pace; when the drawing took longer, it does not wait. |
| `KEY-HELD?` | ( key -- flag ) | Whether the key (a character of one byte, or `K-UP` and the other codes) is held down now. A game moves while a key is held, without waiting for the keyboard to repeat it (it waits about 0.5 s first). The Windows console, the window, and the Tk window tell when a key is released, and when they lose the focus; a terminal on Linux and macOS does not, so its keys count as held for 0.6 s after they were last pressed (a key held down is repeated, which holds it on; once it is repeating, 0.12 s after the last repeat, so it stops soon after it is released), and a cursor key stops counting as held when another cursor key is pressed, since a terminal repeats only the key pressed last. Keys read meanwhile wait for `INKEY`. |
| `GFX-INKEY`, `GFX-MOUSE`, `GFX-KEY-HELD` | as `INKEY`, `MOUSE`, `KEY-HELD?` | The words underneath. |
| `GFX-MOUSE-MODE` | ( flag -- ) | As `MOUSE-ON` (true) and `MOUSE-OFF` (false). |

The first `INKEY` or `MOUSE` sets the terminal to give each key at once, without echo; Sigma sets it back to its line input, dropping what was typed for the program, when it next reads a line or a `KEY`, runs `SYSTEM`, or ends. While the terminal gives single keys, Ctrl+C does not end Sigma: it reaches `INKEY`, which throws, so a loop that reads keys can be stopped with it (a loop that no longer calls `INKEY` or `MOUSE` then cannot). When standard input is not a terminal, `INKEY` gets only the window's keys.

On Linux and macOS, the keys that are not characters come from the terminal as escape sequences, which `INKEY` decodes; a sequence whose bytes come apart (over a slow connection) waits up to 50 ms for the rest, and an Esc that nothing follows within that time is the Esc key. The mouse comes as the reports of xterm in the SGR form, which most terminals send (xterm, GNOME Terminal, iTerm2, Windows Terminal, and others); `MOUSE-ON` asks for them and `MOUSE-OFF`, the return to line input, and the end stop them. On Windows, the console gives the keys and the mouse itself; the console's selection with the mouse is off while the terminal gives single keys. Keys pressed in the window come to `INKEY` as well, and the mouse in the window gives the pixel of the stretched image under it.

To find the pixel under the mouse on the terminal, Sigma asks the terminal where the cursor is after `SHOW` draws the image (only after `MOUSE-ON`), so the position is known from the first `SHOW` after `MOUSE-ON`. With half blocks, each character is two pixels; with Sixel the cell size comes from the terminal, or 10 by 20 pixels is assumed.

A `SHOW` on the terminal draws over the image it drew last when nothing was written in between, so an animation stays in place instead of scrolling; anything written in between (such as the prompt) starts a new picture below. With Sixel, the rows the picture takes are counted from the cell height, which may not match every terminal. Direct `STDOUT WRITE-FILE`/`WRITE-LINE` output also starts a new picture; writes to other files and private string captures do not. `SYSTEM`, `SH` and external editor callbacks conservatively start a new picture even when silent or unsuccessful, because their terminal output is not counted by the VM.

### GUI

`REQUIRE-GUI` loads the GUI words into the `GUI` vocabulary (and the graphics words first, if they are not loaded); `ALSO GUI` makes them usable. The words are Forth only, so a dictionary with them is saved as one with the graphics words. They draw buttons, check boxes, text fields, lists, a menu bar with pull-down menus, a function key bar, panels, and dialogs into the image drawn on (`DRAW-TO`), with a flat look whose colors and line widths are settings. Every name starts with `GUI-`, so none hides a word of the program.

The parts are drawn again each frame: between `GUI-BEGIN` and `GUI-END`, the word of each part draws it and gives what the user did to it in this frame. What a part shows (a check box's flag, a field's text, a list's choice) is in the program's own variables. `GUI-BEGIN` reads the mouse (`MOUSE-EVENT`, so a click between frames is not lost), the keys, and the first gamepad once; the keys no part takes can be read with `GUI-KEY` until the next `GUI-BEGIN`. The keys go to the part with the focus: a click gives it the focus, Tab gives it to the next part, and without a part that has it, the first part that can take it has it. The first gamepad works as keys when `GAMEPAD-MAPPED?` is true: its D-pad as the arrows, A as Enter, and B as Esc. Raw gamepads are ignored by the GUI. Static Linux musl builds expose raw evdev controls; see the [Linux backend limits](LINUX_NATIVE_VALIDATION.md).

On the tested USB 0583:a021 controller, raw axes read -32768 at startup and after reconnect until the controller reports input. Do not treat these initial readings as a neutral position. After operation, its resting axes read 128. The evdev backend does not apply the device dead zone; programs using raw axes must handle their own dead zone. Mapped layouts and GAMEPAD-MAP are unavailable in this backend.

Parts are numbered in the order the program makes them in a frame. What the GUI keeps from frame to frame is in four variables, which the program may read and set as it does `BASE`: `GUI-FOCUSED`, the part the keys go to, counted from 1 among the parts that can take the focus (out of range, the first takes it in the next frame); `GUI-ACTIVE`, the part the left button went down on, counted from 1 among all the parts, 0 for none; `GUI-MENU-OPEN`, the open menu of the bar, from 0, -1 for none; and `GUI-MENU-ITEM`, the highlighted item of the open menu. A part the program makes in some frames and not in others moves the numbers of the parts after it; a program that does this can set `GUI-FOCUSED` again, or make such parts last.

| Word | Stack | What it does |
|---|---|---|
| `GUI-BEGIN`, `GUI-END` | ( -- ) | Start and end the GUI of a frame. `GUI-END` draws the open pull-down menu over the other parts. |
| `GUI-BUTTON` | ( c-addr u x y -- flag ) | A button; true when it was clicked, or Enter or Space was pressed while it has the focus. `GUI-BUTTON-SIZE` ( c-addr u -- w h ) gives its size. |
| `GUI-CHECK` | ( addr c-addr u x y -- flag ) | A check box with a label: the flag at addr changes when it (or its label) is clicked, or with Space or Enter; true when it changed. |
| `GUI-FIELD` | ( buf room len-addr x y w -- flag ) | A field of one line, w pixels wide, editing the text at buf (at most room bytes, its length at len-addr): the bytes of text that `INKEY` gives (UTF-8 too), Backspace, Delete, the left and right arrows, Home, and End. In the Tk window and in Sigma's own window (Windows, macOS, and Linux on X11 or XWayland), while it has the focus, the input method (IME) can be used to type and convert Japanese: the text being converted shows at the cursor, underlined, the candidate window follows the cursor, and only the committed text goes in. True when Enter was pressed in it. |
| `GUI-LIST` | ( c-addr u var x y w -- flag ) | A list "a\|b\|c", one item under another, w pixels wide (0: as wide as the widest). The cell at var is the chosen item: the mouse over an item chooses it, and so do the up and down arrows with the focus. True when an item was clicked, or Enter or Space was pressed. |
| `GUI-LIST-XT` | ( xt n var x y w -- flag ) | The same with n items that xt ( i -- c-addr u ) gives, so they can be in any data of the program (an array of strings, a directory listing, ...) and may hold \|. With no items it draws nothing. |
| `GUI-MENUBAR` | ( c-addr u -- n ) | A bar across the top with the titles "a\|b\|c". A click on a title opens its menu (and closes it again); with a menu open, the mouse over another title, or the left and right arrows, open that one, and Esc closes it. Gives the open menu, -1 for none. Call it first after `GUI-BEGIN`. |
| `GUI-MENU` | ( c-addr u -- item \| -1 ) | The items of the open menu, right after `GUI-MENUBAR`: "-" is a line between items, and an item that starts with `~` is shown grey and cannot be chosen. Gives the item chosen by a click or Enter in this frame, else -1; up and down move between the items. A click outside the menu closes it. While a menu is open, it takes the keys and the mouse over it. |
| `GUI-FKEYS` | ( c-addr u -- n \| -1 ) | A bar along the bottom with the labels "a\|b\|c" of F1, F2, ...; gives the key, 0 for F1, that was pressed or whose label was clicked, else -1. |
| `GUI-PANEL` | ( x y w h -- ) | A panel: the background of a group of parts, with its border. |
| `GUI-TILES` | ( img size -- ) | Draw panels with 9 tiles of an image instead, each size pixels square, three by three from the image's top left corner (corners, edges, and middle). `0 0 GUI-TILES` draws borders again. |
| `GUI-LABEL` | ( c-addr u x y -- ) | Text in the color of `GUI-TEXT`. |
| `GUI-ENABLE` | ( flag -- ) | The parts made after false are drawn grey and take no input, until true (or the next `GUI-BEGIN`). |
| `GUI-KEY` | ( -- key \| -1 ) | The next key of the frame that no part took. |
| `GUI-DIALOG` | ( c-addr u c-addr2 u2 -- n \| -1 ) | A dialog in the middle with a message and the buttons "a\|b": gives the button chosen in this frame, 0 for the first, else -1. Esc chooses the last. |
| `GUI-YES-NO` | ( c-addr u -- n ) | A dialog with Yes and No: 1 for yes, 0 for no (also Esc), -1 while there is no answer. |
| `GUI-ASK` | ( c-addr u -- flag ) | Ask with Yes and No and wait for the answer: true for yes. |
| `GUI-MESSAGE` | ( c-addr u -- ) | Show a message with OK and wait until it is closed (OK, Enter, or Esc). |
| `GUI-CHOOSE` | ( c-addr u -- n ) | Show a list "a\|b\|c" in the middle and wait for a choice: 0 for the first, -1 for Esc. |
| `GUI-CHOOSE-XT` | ( xt n -- n ) | The same with n items that xt ( i -- c-addr u ) gives; -1 at once without items. |

`GUI-ASK`, `GUI-MESSAGE`, and `GUI-CHOOSE` draw on the screen and show it each frame (`SHOW`, `16 FRAME`) until there is an answer, over what the screen had when they started, which they then put back; meanwhile the program does not run. Ctrl+C stops them (`USER INTERRUPT`).

```forth
REQUIRE-GUI  ALSO GRAPHICS ALSO GUI
320 200 GFX-INIT
VARIABLE SOUND-ON   CREATE NAME 16 ALLOT  VARIABLE NAME-LEN
: SETTINGS ( -- )
   BEGIN
      GUI-BACKGROUND GUI-COLOR@ GFX-CLS
      GUI-BEGIN
      SOUND-ON S" Sound" 10 10 GUI-CHECK DROP
      NAME 16 NAME-LEN 10 30 120 GUI-FIELD DROP
      S" OK" 10 60 GUI-BUTTON
      GUI-END  SHOW  16 FRAME
   UNTIL ;
```

The colors are roles that `GUI-COLOR!` ( rgb role -- ) sets and `GUI-COLOR@` ( role -- rgb ) gives; `GUI-DEFAULT` puts every color and width back.

| Role | For | At the start |
|---|---|---|
| `GUI-BACKGROUND` | panels, dialogs, menus, and the bars | F0F0F0 |
| `GUI-FACE` | buttons | E1E1E1 |
| `GUI-HOVER` | a button under the mouse | EBEBEB |
| `GUI-PRESSED` | a button held down | C8C8C8 |
| `GUI-TEXT` | text | 000000 |
| `GUI-DISABLED` | the text of parts that cannot be used | 8C8C8C |
| `GUI-BORDER` | borders and lines | 8A8A8A |
| `GUI-FIELD-FACE` | text fields and check boxes | FFFFFF |
| `GUI-FOCUS` | the border of the part with the focus | 3A73D9 |
| `GUI-SELECTION` | the chosen item of a list or a menu | 3A73D9 |
| `GUI-SELECTED-TEXT` | the text of the chosen item | FFFFFF |

`GUI-BORDER-WIDTH` ( n -- ) and `GUI-FOCUS-WIDTH` ( n -- ) set the widths of the borders and of the focus border, 0 to 8 pixels (1 at the start); other values give `NUMBER ERROR !`. The text uses the font and the scale of `TEXT`, and the sizes of the parts follow `TEXT-HEIGHT`. A field shows the text from where its cursor can be seen. Like the other graphics words, the GUI keeps nothing outside the dictionary, and its settings and the choices in the program's variables are saved with it.

### Sprites and tile maps

`REQUIRE-GAME` loads the game words into the `GAME` vocabulary (and the graphics words first, if they are not loaded); `ALSO GAME` makes them usable. They are small Forth words over data the program makes and keeps: a sprite or a map is a structure in the dictionary, made with `SPRITE:` or `TILEMAP:` (or `INIT-SPRITE` on `/SPRITE` bytes of an array), whose fields the program reads and sets with `@` and `!`. The program's own loop decides what to move, draw, and test, and when; nothing calls the program back.

| Word | Stack | What it does |
|---|---|---|
| `SPRITE:` | ( img sx sy w h "name" -- ) | Define a sprite showing the w by h rectangle at sx sy of image img: at 0 0, shown, one frame, not flipped, no transparent color. name gives its address. |
| `INIT-SPRITE` | ( img sx sy w h spr -- ) | The same for the `/SPRITE` bytes at spr, as in an array: `CREATE ENEMIES 8 /SPRITE * ALLOT`. |
| `PUT-SPRITE` | ( x y spr -- ) | Put a sprite at x y. |
| `SPRITE-ANIM` | ( n delay spr -- ) | An animation of n frames side by side to the right of the first, each shown for delay calls of `ANIMATE`. |
| `ANIMATE` | ( spr -- ) | One step of the animation. |
| `DRAW-SPRITE` | ( spr -- ) | Draw a shown sprite on the image drawn on, with its frame, flip, and transparent color. |
| `HIT?` | ( spr1 spr2 -- flag ) | Whether the rectangles of two shown sprites overlap. |
| `PIXEL-HIT?` | ( spr1 spr2 -- flag ) | Whether two shown sprites show a pixel at the same place (their transparent colors left out). |
| `SPRITE-PIXEL?` | ( x y spr -- flag ) | Whether a sprite shows a pixel at x y. |
| `TILEMAP:` | ( img tw th cols rows "name" -- ) | Define a map of cols by rows tiles, all tile 0. Tile n is the tw by th rectangle of image img that is n tiles from its top left corner, counted along its rows. name gives its address. |
| `TILE@`, `TILE!` | ( col row map -- n ), ( n col row map -- ) | Read and set a tile, 0 to 255. Outside the map, `NUMBER ERROR !`. |
| `>TILE` | ( x y map -- col row ) | The tile under pixel x y of the map. |
| `DRAW-TILEMAP` | ( sx sy x y w h map -- ) | Draw the w by h rectangle at x y of the image drawn on with the map seen from its pixel sx sy. Only that rectangle is drawn, and only the tiles in it are reckoned. What lies outside the map, and the pixels of the map's transparent color, are left as they are. |

The fields of a sprite (each gives an address) are `SPRITE-X`, `SPRITE-Y`, `SPRITE-IMAGE`, `SPRITE-SX`, `SPRITE-SY`, `SPRITE-W`, `SPRITE-H`, `SPRITE-FRAMES`, `SPRITE-FRAME`, `SPRITE-DELAY`, `SPRITE-TICK`, `SPRITE-FLIP` (as `IMAGE-FLIP`), `SPRITE-KEY` (the transparent color, -1 for none), and `SPRITE-SHOWN`; those of a map are `TILEMAP-IMAGE`, `TILEMAP-TW`, `TILEMAP-TH`, `TILEMAP-COLS`, `TILEMAP-ROWS`, and `TILEMAP-KEY`, with its tile bytes, row by row, at `TILEMAP-DATA` ( map -- addr ). Two playfields, as on the Amiga, are two maps: draw the back one, then the front one with a transparent color. Scrolling is changing sx and sy.

```forth
REQUIRE-GAME  ALSO GRAPHICS ALSO GAME
256 192 GFX-INIT
S" tiles.png" LOAD-IMAGE CONSTANT SHEET
SHEET 16 16 32 12 TILEMAP: LEVEL
SHEET 0 32 16 16 SPRITE: HERO   4 6 HERO SPRITE-ANIM
VARIABLE SCROLL
: STEP ( -- )
   1 SCROLL +!  HERO ANIMATE
   SCROLL @ 0  0 0 256 192 LEVEL DRAW-TILEMAP
   HERO DRAW-SPRITE  SHOW 16 FRAME ;
```

The words under them are `GFX-PIXEL` ( img x y -- rgb | -1 ), the color of a pixel of any image, and `GFX-TILEMAP` ( addr cols rows img tw th sx sy x y w h key -- ), which draws a map of tile bytes at any address. The structures are in the dictionary, so `SAVE` and `SAVESYS` keep them; their image handles are no longer valid after a restore, so a program makes its images and sets `SPRITE-IMAGE` and `TILEMAP-IMAGE` again after it starts.

### Palettes and effects on rows

These are game words too. A palette is 256 cells, the colors of the numbers 0 to 255; a picture of color numbers has one byte for each pixel. Changing a color of the palette changes every pixel of that number the next time the picture is drawn, which is how running water or lights were made by turning colors. The effects on rows change the image drawn on after it is drawn, each row by its own cell of a table, as the video chips that changed a register on each scan line did. How many colors, how many sprites on a line, and what the table holds are the program's numbers.

| Word | Stack | What it does |
|---|---|---|
| `PALETTE:` | ( "name" -- ) | Define a palette, all black. name gives its address. |
| `PALETTE!`, `PALETTE@` | ( rgb n pal -- ), ( n pal -- rgb ) | Set and read the color of number n. Outside 0 to 255, `NUMBER ERROR !`. |
| `ROTATE-PALETTE` | ( first count pal -- ) | Turn the colors of the numbers first to first + count - 1 one place up: each takes the color of the number below it, and the first that of the last. |
| `INDEXED:` | ( w h "name" -- ) | Define a picture of w by h color numbers, all 0. Its fields are `INDEXED-W` and `INDEXED-H`, and its bytes, row by row, are at `INDEXED-DATA` ( pic -- addr ). |
| `INDEX@`, `INDEX!` | ( x y pic -- n ), ( n x y pic -- ) | Read and set the color number of a pixel. Outside the picture, `NUMBER ERROR !`. |
| `DRAW-INDEXED` | ( x y pic pal key -- ) | Draw a picture at x y of the image drawn on with the colors of a palette, leaving out the pixels of number key (-1 for none). |
| `RASTER-SCROLL` | ( table x y w h -- ) | Move each row of the w by h rectangle at x y to the right by its cell of a table of h cells (a negative cell moves it left); what leaves on one side comes in on the other. |
| `RASTER-COLOR` | ( table rgb x y w h -- ) | Give the pixels of color rgb in each row of the rectangle the color in its cell of the table. |
| `DRAW-SPRITES` | ( array n limit -- ) | Draw n sprites of an array of `/SPRITE` structures in order, but on each row only the first limit sprites shown on that row; the later ones lose that row. A limit of 0 draws them all. |

```forth
REQUIRE-GAME  ALSO GRAPHICS ALSO GAME
256 192 GFX-INIT
PALETTE: PAL   16 16 INDEXED: WAVE
$0000AA 1 PAL PALETTE!  $3355FF 2 PAL PALETTE!  $AACCFF 3 PAL PALETTE!
: MAKE-WAVE ( -- )   16 0 DO 16 0 DO  I J + 3 MOD 1+  I J WAVE INDEX!  LOOP LOOP ;  MAKE-WAVE
CREATE WOBBLE 192 CELLS ALLOT
: STEP ( n -- )
   192 0 DO  DUP I + 8 / 1 AND 2*  WOBBLE I CELLS + !  LOOP DROP
   1 3 PAL ROTATE-PALETTE
   0 GFX-CLS  100 80 WAVE PAL 0 DRAW-INDEXED
   WOBBLE 0 0 256 192 RASTER-SCROLL  SHOW 16 FRAME ;
```

The words under them are `GFX-INDEXED` ( addr w h palette x y key -- ), which draws color numbers at any address with any 256 cells of colors, `GFX-ROW-SHIFT` ( table x y w h -- ), and `GFX-ROW-COLOR` ( table rgb x y w h -- ).

`GFX-RGB` ( addr w h stride x y key -- ) draws colors themselves from memory, for a picture with more than 256 colors in a row (an emulator's screen after its own mixing, for example). Each pixel is four bytes, the color `$RRGGBB` as `L!` stores it; the fourth byte is not used. A row starts `stride` bytes after the one before, so a part of a wider buffer can be drawn; 0 stands for w × 4, and a smaller number is refused. The color `key` is left out (a negative number for none), and so is what falls outside the image drawn on. The whole picture must lie in memory. It is not flipped or enlarged: draw it on an image and copy that with `IMAGE-SCALE`.

```forth
CREATE FRAME-BUFFER 256 240 * 4 * ALLOT
: PIXEL! ( rgb x y -- )   256 * + 4 * FRAME-BUFFER + L! ;
: SHOW-FRAME ( -- )   FRAME-BUFFER 256 240 0 0 0 -1 GFX-RGB  SHOW ;
```

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

`examples/trig.fs` draws sin x, cos x, and tan x with a grid, labels, and a legend; it gives `PLOT` NaN where tan x is far beyond the image, so that the graph has gaps at the asymptotes (`sigma.exe examples/trig.fs`). `examples/graphs.fs` shows eight graphs one after another, each growing into place: a bar chart, a line chart, a pie chart, a scatter plot with its least-squares line, a histogram, the graph of a function, a Lissajous figure, and a rose in polar coordinates (Space or Enter for the next, Q or Esc to end).

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

Sigma plays music in the manner of MSX BASIC's `PLAY`, with a standard sound of 16 voices that has no chip's limits, and it plays recorded sound (WAV files) and ProTracker modules (MOD files). The character of a sound chip (the MSX, the Atari ST, the NES, the Commodore 64, Konami's SCC, the Amiga) is added by the libraries in `include/`, which are written with the standard sound's own words. The sound is made by an audio thread of its own, so the program goes on while the music plays. The audio words are not in the dictionary at start-up: `REQUIRE-AUDIO` adds the `AUDIO` vocabulary, with the `SND-` words and the audio library written in Forth (`src/audio/audio.fs`, built into the program), the first time it runs; later it does nothing. As with the graphics words, it does not change the search order, so make the words visible with `ALSO AUDIO`.

```forth
REQUIRE-AUDIO
ALSO AUDIO
S" T150 O4 L8 CDEFGAB>C" PLAY               \ voice A, as MSX BASIC's PLAY "..."
S" O4 C2" S" O4 E2" S" O4 G2" PLAY3         \ a chord: the three voices start together
BEEP
1 INSTRUMENT PULSE 16384 DUTY 5 150 35000 100 ADSR   \ instrument 1: a quarter pulse that fades
2 INSTRUMENT TRIANGLE
: TUNE S" T120 L8 O4 @1 V12 CEGE CEGE" S" T120 L4 O3 @2 V12 CGCG" PLAY2 ;
TUNE
REQUIRE nes-sound.fs                        \ a library of include/
NES-SOUND                                   \ from now on the instruments have the NES's steps
TUNE
```

`PLAY` returns as soon as the notes fit in the voices' queues (32 places for each), as on the MSX; the music then goes on by itself. While the queues are full, `PLAY` waits; Ctrl+C then stops the music and gives `USER INTERRUPT !` (THROW -28). Outside such a wait, Ctrl+C works as before. When there is no audio device, the words work the same without sound, in time (`AUDIO?` tells which).

When the session ends, Sigma stops the audio worker and releases its output device; it does not wait for queued music to finish. If audio shutdown cannot complete, Sigma reports `audio shutdown incomplete` and exits with status 1.

The units are the same for every word: frequencies in Hz, times in milliseconds, ratios 0 to 65535, pitch differences in cents (hundredths of a semitone). All arguments are integers.

### The music macro language (MML)

`PLAY` and the words like it take the music macro language of MSX BASIC (the MSX1 ROM's, as the MSX Red Book describes it). Upper and lower case letters are the same, and spaces are skipped. Each voice keeps its octave, length, tempo, volume, and instrument from one `PLAY` to the next, also over `0 PLAYS`; `BEEP` sets them back to the defaults. A `PLAY` of commands alone (`S" @1 V12" PLAY`) sets them for the next one.

| Command | Meaning |
| --- | --- |
| `A` to `G` | A note, with `+` or `#` (sharp) or `-` (flat), then a length 1 to 64 (or `L`'s), then dots (each one and a half times as long). `B+` is the same octave's `C`, and `C-` the same octave's `B`, as the ROM's table has it. |
| `R` | A rest of length 1 to 64 (4 when left out), with dots. |
| `N` | A note by its number, 0 to 96: octave n / 12 + 1, semitone n mod 12 (`N36` is `O4 C`); 0 is a rest. |
| `O` | The octave, 1 to 8 (4 at first; 4 when the number is left out). |
| `<`, `>` | One octave down or up. |
| `L` | The length of the notes without one, 1 to 64 (4: quarter notes). |
| `T` | The tempo, 32 to 255 quarter notes a minute (120). A note lasts 12000 / (length × tempo) fiftieths of a second, at least 5. |
| `V` | The volume, 0 to 15 (8): `V15` is the loudest, each step down is 3 dB quieter, and `V0` is silent. An instrument with `V-STEPS` (the chip libraries set it) takes its own 16 levels instead. `V` ends `S`. |
| `S` | An envelope shape, 0 to 15 (0), one of the PSG's eight, which the notes after it use in place of their instrument's envelope. Such notes sound at full volume, whatever `V` was. |
| `M` | The period of `S`'s envelope, 1 to 65535 (255): one rise or fall takes 256 × M / 1789773 seconds, as on the MSX. |
| `@` | The instrument, 0 to 63 (0). |
| `P` | The left and right levels of the voice, `Pleft,right`, each -100 to 100 percent (a negative side is inverted): `P100,0` is the left alone, `P70,30` nearer the left, `P100,100` the middle. They multiply the instrument's `INSTRUMENT-PAN` and the voice's `VOICE-PAN`. `P` alone is `P100,100`. |
| `Y` | The vibrato, `Ydepth,speed`: cents and whole Hz (1 and up), in place of the instrument's `VIBRATO` (whose delay stays). `Y0`, or `Y` alone, stops the vibrato, the instrument's too. Until a `Y`, the notes have their instrument's vibrato. |
| `K` | Cents added to the pitch, -100 to 100 (0). |
| `Q` | How much of its length a note sounds, in eighths, 1 to 8 (8): after `length × Q / 8` (the dots counted, at least a fiftieth of a second) the note stops as at its end, and the rest of its length is silent. An instrument's `NOTE-LIMIT` still stops it earlier. |
| `&` | After a note: go on to the next note without starting it anew. With the same pitch it is a tie, with another a slur; the envelope, the wave, and the vibrato go on. |
| `_` | After a note: as `&`, sliding to the next note's pitch, in the instrument's `PORTAMENTO` time, or over the whole of the next note when that is 0. |

A number left out takes the default in brackets (as the ROM does), except for `N`, which needs one. Anything else, or a number out of its range, gives `INVALID MML !` (THROW -274), and nothing of that `PLAY` is played. BASIC's variables (`X` and `=name;`) are not taken: a Forth program joins the strings itself.

`@`, `P`, `Y`, `K`, `Q`, `&`, and `_` are Sigma's own; MSX BASIC has none of them. `P`, `Y`, `K`, and `Q` work from the next note that starts, stay from one `PLAY` to the next and over `@`, and go back to their defaults with `BEEP`. Spaces may stand between a command and its numbers and around the `,`. The `-` right after `P`, `K`, or `P`'s comma is a sign; right after a note it is still a flat. `P` with one number, `Y` with a depth and no speed, and a `,` too many are errors.

A note that `&` or `_` joins to the next sounds all its length; `Q` works on the last of the joined notes. Commands may stand between the two notes (`C&>C`, `C_V12E`), and the joined note takes the new volume and `K`, but `P`, `Y`, and the instrument are those the first note started with. A rest or `@` between them, and `&` or `_` after the last note of a `PLAY`, are errors: a note is not joined to the next `PLAY`. When the first note has already ended (its envelope came to 0, or `NOTE-LIMIT` stopped it), the joined note is silent.

```forth
S" P100,0 O4 L4 C&E_>C2" S" P0,100 Y20,6 O3 L2 Q6 C G" PLAY2   \ left: a slur and a slide; right: vibrato, detached
```

Outside a definition, each `S"` string has its own place, so a `PLAYS` of eight voices can be written on one line; inside a definition the strings are compiled, which is the better place for music that is played more than once.

### Playing

The standard sound has 16 voices: `PLAY` has voices 1 to 8, `SFX` and `PLAY-TONE` 9 to 12, and a module 13 to 16. They do not take voices from each other.

| Word | Stack | Description |
| --- | --- | --- |
| `REQUIRE-AUDIO` | ( -- ) | Load the audio words, the first time only. It is a parsing word (like `REQUIRE-GRAPHICS`) and cannot be used inside a definition. |
| `PLAY` | ( c-addr u -- ) | Play the MML on voice A. Voices B and C, which have no notes, still start the next `PLAY` together with A. |
| `PLAY2`, `PLAY3` | ( c-addr1 u1 c-addr2 u2 -- ), ( c-addr1 u1 c-addr2 u2 c-addr3 u3 -- ) | Play voices A and B, or A, B, and C, starting together. |
| `PLAY-RESET` | ( -- ) | Stop MML and its voices as `0 PLAYS` does, and put the voices' MML settings (octave, length, tempo, volume, instrument, `S` and `M`, `P`, `Y`, `K`, `Q`) back as at start, without a sound. SFX, MOD, samples, and instruments stay. `BEEP` does the same with its sound, and stops SFX and MOD too. |
| `PLAYS` | ( c-addr1 u1 ... c-addrn un n -- ) | Play the first n voices, starting together; n is 1 to 8. `0 PLAYS` stops MML and its voices while keeping SFX, MOD, samples, instruments, and the voices' MML settings. It returns after the audio thread takes the stop. |
| `PLAY?` | ( n -- flag ) | Whether voice n (1 to 8) still has notes to play, or any voice for 0, as MSX BASIC's `PLAY(n)`. A voice without notes counts until the audio thread takes its end of the `PLAY` (within a fiftieth of a second). |
| `PLAY-TONE` | ( hz ms -- ) | Sound a square of hz (0 to 1000000) for ms milliseconds beside the music, on one of `SFX`'s voices. |
| `BEEP` | ( -- ) | Stop the music, the sound effects, and the module, set the voices' MML settings as at start, and beep (a square of about 1316 Hz at `V7` for 40 ms). It returns when the audio thread has stopped the music. The instruments and the settings of all the voices together stay. |
| `AUDIO?` | ( -- flag ) | Whether the sound reaches an audio device. If the output fails while the program runs (on Linux, the command that plays it ends, for example), it becomes false and there is no more sound until the program is started again. |

### Instruments

MML's `@n` plays with instrument n. `INSTRUMENT` chooses the one that the words of this table change; a change is heard from the next note that starts with the instrument. An instrument keeps what it was given until it is set again.

```forth
1 INSTRUMENT  PULSE 16384 DUTY  10 200 40000 300 ADSR  12 6 150 VIBRATO
2 INSTRUMENT  SAW  1 800 20000 FILTER  65535 20000 INSTRUMENT-PAN
S" @1 V12 CDEF" S" @2 V12 O3 C2G2" PLAY2
```

| Word | Stack | Description |
| --- | --- | --- |
| `INSTRUMENT` | ( n -- ) | Choose instrument n (0 to 63) for the words below to change. |
| `SQUARE`, `PULSE`, `TRIANGLE`, `SAW`, `NOISE` | ( -- ) | The instrument's wave: a square (a pulse of half its cycle; this at first), a pulse of `DUTY`'s width, a triangle, a sawtooth, or noise from its shift register. |
| `DUTY` | ( ratio -- ) | The width of `PULSE`, 0 to 65535 of a cycle (32768 at first). |
| `WAVETABLE` | ( addr n -- ) | Make one cycle of the n (1 to 65536) signed 16-bit values in the cells at addr the instrument's wave. It takes n places of the pool of samples. |
| `SAMPLE-INSTRUMENT` | ( n -- ) | Have the instrument play sample n (0 to 63) with its notes, `O4 C` at the sample's own rate; -1 for none, back to the square. |
| `NOISE-LFSR` | ( bits tap -- ) | The noise's shift register: bits (2 to 32) long, with bit tap (1 to bits - 1) fed back with bit 0; `15 1` at first. The noise shifts 16 times in a cycle of the note, so a higher note is a brighter noise. |
| `NOISE-RATE` | ( hz -- ) | Shift the noise hz times a second (in 1/1000 Hz) whatever the note; 0 for 16 times a cycle of the note, as at first. |
| `NOISE-MIX` | ( mode -- ) | Mix the noise with the instrument's tone: 0 not at all, 1 added, 2 gated (high only when both are high, as the PSG mixes them). |
| `ADSR` | ( attack-ms decay-ms sustain release-ms -- ) | The envelope, written shortly: a straight attack, an exponential decay to sustain (0 to 65535), held until the note stops, and an exponential release. It sets `ENVELOPE`'s segments. |
| `ENVELOPE` | ( addr n loop release -- ) | The envelope as n (0 to 16) segments of three cells at addr: the level to reach (0 to 65535), the time in ms, and the curve (0 straight, 1 exponential). loop is the segment to go back to after the last, release the segment held until the note stops (-1 for none). n = 0 for no envelope. |
| `PITCH-SWEEP` | ( cents ms -- ) | Change the pitch by cents every ms milliseconds while a note sounds (negative: down). |
| `PITCH-SWEEP-LIMIT` | ( low-hz high-hz -- ) | Silence the note while its pitch is outside low-hz to high-hz; `0 0` for no limit. |
| `PORTAMENTO` | ( ms -- ) | Slide to each note from the one before in ms milliseconds; 0 for none. |
| `VIBRATO` | ( cents hz delay-ms -- ) | A vibrato of cents at hz, from delay-ms after the note starts; `0 0 0` for none. |
| `RING`, `SYNC` | ( voice -- ) | Multiply the instrument's wave by the oscillator of source voice 1 to 16, or restart its wave with each cycle of that voice; 0 for none. |
| `PITCH-MOD` | ( voice cents -- ) | Bend the pitch by up to cents with the output of source voice 1 to 16; voice 0 for none. |
| `VOLUME-MOD` | ( voice ratio -- ) | Change the volume by up to ratio (0 to 65535) with the output of source voice 1 to 16; voice 0 for none. |
| `MOD-ONLY` | ( flag -- ) | When true, the instrument's voice is not heard and serves only as a source of modulation. |
| `PHASE-RESET` | ( flag -- ) | When true, each note starts its wave from the beginning. |
| `NOTE-LIMIT` | ( ms -- ) | Stop each note ms milliseconds after it starts; 0 for no limit. |
| `FILTER` | ( mode hz resonance -- ) | Send the instrument through a filter of its own: mode 0 none, 1 low-pass, 2 band-pass, 3 high-pass, 4 low-pass and high-pass added (a notch), 5 low-pass and band-pass, 6 band-pass and high-pass, 7 all three; cutoff 0 to 1000000 Hz, resonance 0 to 65535. |
| `INSTRUMENT-PAN` | ( left right -- ) | The instrument's left and right levels, -65535 to 65535 (a negative side is inverted); `65535 65535` at first. |
| `REVERB-SEND` | ( ratio -- ) | How much of the instrument goes to the reverb, 0 to 65535 (0 at first). |

A time is 0 to 3600000 ms. A number out of its range gives `NUMBER ERROR !`.

A note that starts on a voice still sounding begins its envelope at the level the voice has, not at 0, so that a row of notes without rests has no click at each start; a voice that was silent begins at 0.

### A chip's steps

These words round what the standard sound does to the steps a chip has. The libraries of the next section are written with them; a program can also use them directly. The first six set the instrument that `INSTRUMENT` chose, the last three all the voices at once. Clocks are in 1/1000 Hz, so that a clock that is not a whole number of Hz can be given.

| Word | Stack | Description |
| --- | --- | --- |
| `PITCH-PERIOD` | ( clock divider offset min max -- ) | Round the pitch to clock / (divider × (period + offset)) with a whole period of min to max (min + offset at least 1). An instrument with a sample has its playing rate rounded instead. clock 0 for none. |
| `PITCH-STEP` | ( clock bits -- ) | Round the pitch to clock × n / 2^bits with a whole n (bits 1 to 32), as the SID's frequency register does; clock 0 for none. |
| `VOLUME-STEPS` | ( addr n -- ) | Round the volume and the envelope to the nearest in decibels of the n (0 to 128) ascending levels (0 to 65535) in the cells at addr; 0 for none. |
| `V-STEPS` | ( addr n -- ) | Have MML's `V0` to `V15` choose the 16 levels (0 to 65535) in the cells at addr, as a chip's volume register does; n is 16, or 0 for 3 dB a step. `S`'s envelopes do not use it. |
| `DUTY-STEPS` | ( n -- ) | Round the pulse's duty to n steps (never 0 or a whole cycle); 0 for none. |
| `INTERPOLATION` | ( mode -- ) | How a wavetable and a sample are read: 0 as steps (at first), 1 with straight lines between the values. |
| `VOICE-LIMIT` | ( n -- ) | Sound only `PLAY`'s voices 1 to n (1 to 8; 8 at first). |
| `MIXER` | ( mode -- ) | Mix the voices with 0 a sum (at first), or 1 the NES's formulas for voices 1 to 5: 1 and 2 as the pulses, 3 as the triangle, 4 as the noise, 5 as the DMC, without their pan, filter, and reverb. |
| `OUTPUT-BITS` | ( bits rate -- ) | Round the output to bits (1 to 16; 0 for none) and hold it at rate Hz (0 for every frame). |

### All the voices together

These take effect at once and stay over `BEEP` and the stops.

| Word | Stack | Description |
| --- | --- | --- |
| `REVERB` | ( delay-ms feedback volume -- ) | The reverb: a delay of 0 to 341 ms, a feedback of -65535 to 65535, and a volume of 0 to 65535 (0 turns it off). It hears what the instruments send it with `REVERB-SEND`. |
| `REVERB-FIR` | ( addr n -- ) | Filter the reverb's feedback with the n (0 to 8) signed coefficients in the cells at addr, 128 as 1; 0 for none. |
| `VOICE-PAN` | ( left right voice -- ) | The left and right levels of voice 1 to 16, -65535 to 65535 (a negative side is inverted), whatever the voice plays; `65535 65535` at first. They multiply the instrument's `INSTRUMENT-PAN` and MML's `P`. |
| `MASTER-FILTER` | ( mode hz stage -- ) | Filter all the voices in stage 1 or 2; stage 1 runs first, so two filters can follow each other. Mode 0 none, 1 low-pass, 3 high-pass (two poles, 12 dB an octave), 11 low-pass, 13 high-pass (one pole, 6 dB an octave), at hz. |
| `TONE-CONTROL` | ( bass treble -- ) | Raise or lower the bass (below about 200 Hz) and the treble (above about 4 kHz), -12 to 12 dB. |
| `MASTER-VOLUME` | ( ratio -- ) | The volume of all the voices, 0 to 65535 (65535 at first). |
| `VOICE-HOLD` | ( instrument hz volume voice -- ) | Sound instrument (0 to 63) on voice 1 to 16 at hz (in 1/1000 Hz) and volume (0 to 65535) until told otherwise. The same instrument again goes on, its envelope too, at the new pitch and volume, and takes the instrument's settings as they are now (the wave, the duty, the filter, and the others, but not the envelope), so a program can change them while the note sounds; another instrument starts anew. An envelope that ends at 0 keeps the voice at 0, and volume 0 silences the voice at once. `PLAY`, `SFX`, the module, and the stops take their voices back. |
| `VOICE-OSC` | ( voice -- n ) | The oscillator of voice 1 to 16, -32768 to 32767. |
| `VOICE-ENV` | ( voice -- ratio ) | The voice's envelope level, 0 to 65535. |
| `VOICE-POS` | ( voice -- n ) | The voice's place in its sample, or -1 when it plays no sample. |
| `VOICE-ENDS` | ( voice -- n ) | How many times the voice's sample has ended or looped; it only grows. |
| `VOICE-ON?` | ( voice -- flag ) | Whether the voice sounds. |

The audio thread writes what the `VOICE-` words read every few milliseconds; it does not call Forth, so a program learns of an end or a loop by reading `VOICE-ENDS` again. Sixteen loud voices together can go past the output's limit, which cuts them off; the mix is not turned down for them.

### The chip libraries

The files in `include/` give the standard sound the character of a chip. They are Forth source that sets the words of the sections above, and their words go into the `AUDIO` vocabulary. `FPATH` at start-up is the current directory and then the `include` folder beside the program, so `REQUIRE msx-sound.fs` finds a library from any directory (see the [user manual](USER_MANUAL.md) for `FPATH`).

```forth
REQUIRE-AUDIO  ALSO AUDIO
REQUIRE chips.fs
NES-SOUND                                    \ every instrument gets the NES's steps
1 INSTRUMENT NES-TRIANGLE  2 INSTRUMENT NES-NOISE
S" O5 L8 CEGE" S" O5 L8 EGBG" S" @1 O3 L4 CG" S" @2 O8 L8 BBBB" 4 PLAYS
STANDARD-SOUND                               \ no chip any more
3 INSTRUMENT SCC STYLE  4 INSTRUMENT C64 STYLE SAW
S" @3 O4 L8 CDEF" S" @4 O3 L4 CG" PLAY2      \ two chips in one PLAY
```

| File | Word | Stack | Description |
| --- | --- | --- | --- |
| `chip-sound.fs` | `STANDARD-SOUND` | ( -- ) | Back to the standard sound: no chip's steps on any of the 64 instruments, and `VOICE-LIMIT`, `MIXER`, `OUTPUT-BITS`, `MASTER-FILTER`, `MOD-FILTER`, and every voice's `VOICE-PAN` as at start. The instruments' waves, envelopes, and the like stay, and so do `MASTER-VOLUME`, the reverb, and `TONE-CONTROL`. |
| | `STANDARD-STEPS` | ( -- ) | No chip's steps on the chosen instrument. |
| `msx-sound.fs` | `MSX-SOUND` | ( -- ) | The MSX's AY-3-8910 at 1789773 Hz: three voices, periods 1 to 4095, the AY's 16 levels, a 17-bit noise. |
| | `MSX-STEPS`, `AY-STEPS` | ( -- ), ( clock -- ) | The PSG's steps on the chosen instrument, at the MSX's clock or at clock. |
| | `SOUND` | ( reg value -- ) | Write value (0 to 255) to the PSG's register reg (0 to 13), as MSX BASIC's `SOUND`. It plays on voices 1 to 3 with instruments 61 to 63, which it chooses with `INSTRUMENT` on the way; R7 starts at 184 (tones on, noise off), as in MSX BASIC. A `PLAY`, `BEEP`, or stop takes those voices back, and the next `SOUND` sounds them again. |
| `st-sound.fs` | `ST-SOUND`, `ST-STEPS` | ( -- ) | The Atari ST's YM2149 at 2 MHz: three voices and its 32 levels, 1.5 dB apart. |
| | `STE-SOUND` | ( -- ) | The STE: `ST-SOUND` with five voices, two of them for its samples. Its bass and treble control is `TONE-CONTROL`. |
| | `STE-LEFT`, `STE-RIGHT`, `STE-STEPS` | ( -- ) | Make the chosen instrument one of the STE's sample channels: its sample plays at 50066 / period values a second (periods 1 to 8, not only the STE's 1, 2, 4, and 8), on the left or the right. `STE-STEPS` sets the rate alone. A WAV file of two channels is read as one, so the left and the right are two samples on two voices. |
| `nes-sound.fs` | `NES-SOUND` | ( -- ) | The NES's APU (NTSC): five voices mixed with its formulas (`MIXER` 1), 11-bit timers, 16 levels, duties in eighths, and the output's filters (a high-pass at 90 Hz and a low-pass at 14 kHz, one pole each, as `MASTER-FILTER`'s two stages). |
| | `NES-STEPS`, `NES-PULSE` | ( -- ) | A pulse's steps on the chosen instrument; `NES-PULSE` also makes it a pulse. |
| | `NES-TRIANGLE` | ( -- ) | Make the chosen instrument the triangle of 32 steps, at full volume whatever `V` says. Each call takes 32 places of the pool. |
| | `NES-NOISE` | ( -- ) | Make the chosen instrument the noise. Its period follows the note (any of 4 to 4068, not only the chip's 16): a low note is a rumble, a high note a hiss. |
| | `NES-SHORT-NOISE` | ( -- ) | As `NES-NOISE`, in the noise's short mode: it repeats after 93 (or 31) steps and sounds as a metallic tone. |
| | `NES-DMC` | ( -- ) | Make the chosen instrument the DMC, for an instrument that plays a sample (`SAMPLE-INSTRUMENT`): its values go by at 1789773 / period a second (any period of 54 to 428, not only the chip's 16), at full volume whatever `V` says. Play it on voice 5. The sample has one value for each of the DMC's bits; its 1-bit differences are made into values beforehand. |
| `c64-sound.fs` | `C64-SOUND`, `C64-STEPS` | ( -- ) | The C64's SID (PAL): three voices, its frequency register (985248 Hz × n / 2^24), 12-bit pulse widths, and a 23-bit noise. |
| | `C64-FILTER` | ( mode cutoff resonance -- ) | Give the chosen instrument the SID's filter from its registers' values: mode is its bits added (1 low-pass, 2 band-pass, 4 high-pass; 0 for none), cutoff 0 to 2047 (here 30 Hz and 5.8 Hz a step), resonance 0 to 15. Each voice has its own filter, without the 6581's distortion. To move it while a note sounds, set it again and name the instrument with `VOICE-HOLD`. |
| `scc-sound.fs` | `SCC-SOUND`, `SCC-STEPS` | ( -- ) | Konami's SCC: five voices at 3579545 / (32 × (period + 1)) Hz with 16 levels. |
| | `SCC-WAVE` | ( c-addr n -- ) | Make the 32 signed bytes at c-addr the wave of instrument n, with the SCC's steps; the instrument is chosen afterwards. Each call takes 32 places of the pool. |
| `amiga-sound.fs` | `AMIGA-SOUND`, `AMIGA-STEPS` | ( -- ) | The Amiga's Paula (PAL): four voices, samples at 3546895 / period a second (periods of 123 and up), 65 levels, and the A500's low-pass (one pole, about 4.9 kHz) as `MASTER-FILTER`'s first stage. Voices 1 and 4 are on the left and 2 and 3 on the right (`VOICE-PAN`); the voices after them, for a raised `VOICE-LIMIT`, stay in the middle. |
| | `AMIGA-FILTER` | ( flag -- ) | Turn the LED filter (a low-pass at about 3.3 kHz after the 4.9 kHz one, as `MASTER-FILTER`'s second stage) on or off. A module's effect `E0x` uses the same filter on its voices. |
| `chips.fs` | `STYLE` | ( chip -- ) | Give the chosen instrument the steps of `MSX` (1), `ST` (2), `NES` (4), `C64` (8), `SCC` (16), or `AMIGA` (32), or the standard sound's for 0, so that the voices of one `PLAY` can sound like different chips. Anything else gives `NUMBER ERROR !`. The file loads the six libraries above. |

`MSX-SOUND` and the words like it set the chip's steps on all 64 instruments (instrument 0 is chosen afterwards), limit `PLAY` to the chip's number of voices with `VOICE-LIMIT`, and set `MIXER`, `OUTPUT-BITS`, `MASTER-FILTER`, `MOD-FILTER`, and the voices' `VOICE-PAN` for the chip. They do not stop the music and do not change the voices' MML settings: stop it with `0 PLAYS`, and choose the instruments and volumes in the MML. For more voices than the chip has, raise `VOICE-LIMIT` after the chip's word. Set an instrument's wave and envelope after the chip's word, since `NES-TRIANGLE`, `NES-NOISE`, `NES-SHORT-NOISE`, `NES-DMC`, `STE-LEFT`, `STE-RIGHT`, and `SCC-WAVE` set steps of their own.

The libraries round the pitches and the volumes as the chips do, by their documented behavior. They do not reproduce these: the NES's four duties only (every eighth sounds), its 16 periods of the noise and of the DMC only, and the DMC's 1-bit differences (the program makes them into values); the PSG's one envelope and one noise shared by its three voices (each voice has its own), and envelope periods shorter than 1 ms; the C64's one filter for the voices sent to it and its distortion (each voice has its own), combined waves (a `WAVETABLE` plays one), and 8-bit noise output. The models that follow a chip register by register are separate libraries, described under [PCM streams](#pcm-streams).

### Recorded sound

Samples 0 to 63 are recorded sound kept in a pool of 64 MiB outside the dictionary's memory. The pool only grows: loading a sample again takes new room, and `FREE-SAMPLES` empties it. Wavetables are in the same pool.

| Word | Stack | Description |
| --- | --- | --- |
| `LOAD-SAMPLE` | ( c-addr u n -- ) | Read a WAV file of 8- or 16-bit PCM, mono or stereo (made mono), into sample n. A file it cannot read gives its error; a file that is not such a WAV gives `SAMPLE ERROR !` (THROW -276); a full pool gives `OUT OF MEMORY !`. Nothing changes on an error. A file whose data ends before the size it gives makes a sample of the frames there are. |
| `SAMPLE` | ( c-addr u rate n -- ) | Make the u signed 8-bit bytes at c-addr sample n, recorded at rate Hz (1000 to 192000). |
| `LOOP-SAMPLE` | ( start end n -- ) | Repeat the frames from start to end of sample n while it plays; `0 0` for no loop. |
| `SFX` | ( n -- ) | Play sample n once at its rate, at once and beside the music, on voices 9 to 12. Four can sound together; a fifth takes the place of the oldest. |
| `FREE-SAMPLES` | ( -- ) | Stop the music, the sound effects, and the module, and forget every sample, wavetable, and the module. |

`SAMPLE-INSTRUMENT` (under [Instruments](#instruments)) plays a sample with the notes of MML.

### Modules

| Word | Stack | Description |
| --- | --- | --- |
| `LOAD-MOD` | ( c-addr u -- ) | Read a ProTracker module of four channels (`M.K.`, `M!K!`, `FLT4`, `4CHN`) into the pool. Other files give `MOD ERROR !` (THROW -277); a full pool gives `OUT OF MEMORY !`. |
| `PLAY-MOD` | ( flag -- ) | Play the module from its start, beside `PLAY` and `SFX`, on voices 13 to 16; again after its end when flag is true. With a false flag, the song ends where it comes to a row it has played: after its last row, or at a jump back (`Bxx`, `Dxx`). A `Dxx` at the end of the song that goes to rows not played yet plays them first. |
| `STOP-MOD` | ( -- ) | Stop the module. |
| `MOD?` | ( -- flag ) | Whether the module plays. |
| `MOD-FILTER` | ( mode hz -- ) | The filter that the module's effect `E0x` turns on and off for its voices: mode as `FILTER`'s, 0 (none, at first) to 7. `AMIGA-SOUND` sets the Amiga's LED filter here. |

The module plays on Paula's periods (the PAL clock), its channels left, right, right, left, as the format has them. These effects are played: arpeggio, portamento up and down, tone portamento, vibrato, tremolo, the volume slides, sample offset, position jump, pattern break, set volume, set speed and tempo, fine portamento and fine volume slides, pattern loop, retrigger, note cut, note delay, and pattern delay. The vibrato and the tremolo are always a sine (`E4x`, `E7x`), and `E3x`, `E5x`, `E8x`, and `EFx` do nothing. A row with a sample number and no note starts no new sound: the new sample's loop follows when the sound comes to its end or goes round its loop (at once if the sound has already ended), and silence follows if the new sample has no loop. In a module tagged `FLT4`, such a row does not change what is sounding.

### The audio device

| System | Device |
| --- | --- |
| Windows | waveOut, 48 kHz 16-bit stereo; a note starts about 80 ms after the audio thread takes it. |
| Linux (the release builds, static) | The first of the commands `pacat`, `pw-play`, and `aplay` that starts, through a pipe (about 40 ms). |
| Linux (a build that can load libraries) | PulseAudio, then ALSA, then the commands above. |
| macOS | An AudioQueue of AudioToolbox on the default output device, 48 kHz 16-bit stereo (about 80 ms); the framework is loaded when the program runs. |

`BEEP`, `FREE-SAMPLES`, and Ctrl+C while `PLAY` waits stop the music, the sound effects, and the module. `0 PLAYS` stops the music alone, `STOP-MOD` the module, and a `VOICE-HOLD` with volume 0 one voice (9 to 12 for the sound effects). The sound (instruments, samples, queues) is not part of the dictionary: `SAVE` and `SAVESYS` keep the audio words and the words that use them, but a program sets its instruments and loads its samples after it starts. A dictionary that has loaded the audio words is saved as `SIGIMG47`. A library of `include/` that was loaded before `SAVESYS` is in the saved program, which then needs no `include` folder.

The `SND-` words are the base the library is written with: `SND-PLAY`, `SND-PLAYS`, `SND-PLAY-TONE`, `SND-BEEP`, `SND-PLAYING`, `SND-DEVICE`, `SND-INSTRUMENT`, `SND-WAVE`, `SND-DUTY`, `SND-ADSR`, `SND-RING`, `SND-SYNC`, `SND-FILTER`, `SND-WAVETABLE`, `SND-TONE` (the other instrument words, by a number), `SND-GLOBAL` (the words for all the voices), `SND-VOICE` (the `VOICE-` words that read), `SND-HOLD`, `SND-LOAD-SAMPLE`, `SND-SAMPLE`, `SND-LOOP-SAMPLE`, `SND-SAMPLE-INSTRUMENT`, `SND-SFX`, `SND-FREE-SAMPLES`, `SND-LOAD-MOD`, `SND-PLAY-MOD`, `SND-STOP-MOD`, `SND-MOD-PLAYING`, and `SND-MOD-FILTER`. `HELP` describes each of them. `SND-LOAD-SAMPLE` and `SND-LOAD-MOD` return an ior instead of throwing. `SND-SOUND`, `SND-CHIP`, `SND-CHIPS`, `SND-STYLE`, and `SND-AMIGA-FILTER` are kept only so that the numbers of the other words stay; they give `HOST FUNCTION UNAVAILABLE !` (THROW -21).

Errors: `REQUIRE-AUDIO` in a build with `-Daudio=false` gives `AUDIO UNAVAILABLE !` (THROW -275); a number out of its range gives `NUMBER ERROR !`; a host without an audio thread gives `HOST FUNCTION UNAVAILABLE !`. As with `REQUIRE-GRAPHICS`, a library that fails to load is removed again, and `REQUIRE-AUDIO` loads it again after `FORGET` or a `MARKER` removed it.

`examples/music.fs` plays a short tune with the standard sound, with each chip's steps, with several chips in one `PLAY`, and a sound effect made with `SAMPLE`. `examples/fur-elise.fs` plays the theme, the first episode, and the theme again of Beethoven's Für Elise (bars 1 to 58) with Paula's steps and a piano of samples that the program makes itself. `examples/fur-elise-simple.fs` is a short program that plays the theme alone on two voices with `PLAY2`. `examples/pastoral.fs` plays the exposition of the first movement of Beethoven's Symphony No. 6 (bars 1 to 138) on 8 voices, with waves for the strings and the winds that it makes.

## Physical keys

Load with `REQUIRE-GRAPHICS GRAPHICS`. `SCAN-INPUT?` queries native-window input availability; `scan SCAN-SUPPORTED?` queries both press/release support for a particular physical key. Neither opens a window. Terminal, SIXEL and Tk-only output are unsupported. `scan SCAN-HELD?` reads held state; `KEY-EVENT` returns `scan kind true`, or just `false` when empty. This queue is independent of INKEY/EKEY/KEY.

Numbers are USB HID Keyboard/Keypad page 0x07 usages 0..255, for example `SC-A`, `SC-LSHIFT`, `SC-RSHIFT`; outside this range throws -24. `SC-PRESS` (1) and `SC-RELEASE` (2) represent changes, excluding autorepeat. SCAN-SUPPORTED? is false for keys lacking both edges, including Mac CapsLock, Windows Pause, and the left/right Windows keys on Linux (GNOME takes their release). Physical positions are independent of layout characters and IME committed text. Windows also excludes usages 53 (US grave/tilde, JIS zenkaku/hankaku position) and 136 (Kana), because IME-processed messages can leave them held. Support and held queries return false and no physical events are generated for these keys. Normal text input and IME switching remain available.

The queue holds256 edges. Overflow preserves the first256, drops subsequent edges, and keeps updating held state. After the preserved history, KEY-EVENT repeatedly returns `0 SC-RESYNC true` (kind3). `addr KEY-RESYNC` copies a32-byte bitmap, discards unread history and acknowledges resync. Usage n is bit(n%8) of byte n/8. While a transport snapshot is pending, resync stays requested; read again after the authoritative state arrives. Lost tap counts/timestamps cannot be recovered. An invalid32-byte address throws -9 without changing host state.

```forth
REQUIRE-GRAPHICS GRAPHICS
SC-A SCAN-SUPPORTED? .
SC-LSHIFT SCAN-HELD? .
CREATE HELD-BITS 32 ALLOT
HELD-BITS KEY-RESYNC
: PRINT-EDGE KEY-EVENT IF . . ELSE ." none" THEN ;
PRINT-EDGE
```

Focus loss and closure release all held keys; queued history remains readable after closure. Dictionary images contain neither bitmap nor history; successful restore creates a tracker boundary. OS/Mac pipe notifications still unread at that point are applied when they arrive after restore. No filtering by OS occurrence time is guaranteed. See the [design](PHYSICAL_KEY_DESIGN.md) and [validation record](PHYSICAL_KEY_IMPLEMENTATION.md).

## PCM streams

`REQUIRE-AUDIO ALSO AUDIO` exposes signed 16-bit little-endian interleaved mono/stereo PCM, mixed with MML, SFX and modules. Input rates are 8000..192000 Hz; capacity is a power of two from 256..65536 input frames and must represent 40 ms..1 s. One stream per audio host. Missing hardware consumes silently; use `AUDIO?` to distinguish it.

| Word | Stack effect | Meaning |
| --- | --- | --- |
| PCM-OPEN | hz channels capacity -- pcm ior | Open one stream; positive process-local ID |
| PCM-WRITE | addr frames pcm -- written ior | Copy complete frames without blocking; full returns 0,0 |
| PCM-QUEUED | pcm -- frames ior | Input frames not consumed by the engine, including its held frame |
| PCM-WAIT | frames ms pcm -- flag ior | Wait for free input frames; 0 ms polls, negative waits indefinitely |
| PCM-STOP | mode ms pcm -- flag ior | 0 discards, 1 drains the engine, then detaches |
| PCM-CLOSE | pcm -- ior | Discard and detach, with a 1000 ms deadline; invalidate only on success |
| PCM-UNDERRUNS | pcm -- u ior | Saturating empty episodes after the first sample, excluding intentional drain tails |

```forth
REQUIRE-AUDIO ALSO AUDIO
CREATE PCM-ZERO 16384 ALLOT
PCM-ZERO 16384 0 FILL
48000 2 4096 PCM-OPEN THROW CONSTANT PCM-ID
PCM-ZERO 4096 PCM-ID PCM-WRITE THROW .
1 1000 PCM-ID PCM-STOP THROW .
PCM-ID PCM-CLOSE THROW
```

This submits silence. A frame contains one sample per channel; stereo s16LE uses four bytes. WRITE copies accepted input, so its source can be reused immediately. QUEUED and drain refer to engine consumption, not device playback position. Rate conversion uses sample hold without anti-alias filtering.

WAIT/STOP timeout returns false,0; interruption throws -28. Before detach, a cancelled drain keeps accepted input writable. Once detach is published, STOP can be retried to observe acknowledgment. CLOSE returns -528 on timeout or -516 on interruption and retains a closing ID for retry. WRITE/WAIT on stopping or closing streams return -534; invalid handles return -521. Invalid numbers throw -24 and invalid memory throws -9 before side effects. Host/scope restoration failure throws -265. Capacity-sized WAIT is permitted.

The internal `SND-PCM-OPEN`, `SND-PCM-WRITE`, `SND-PCM-QUEUED`, `SND-PCM-WAIT`, `SND-PCM-STOP`, `SND-PCM-CLOSE` and `SND-PCM-UNDERRUNS` have the same effects. All are excluded with audio=false, independently of graphics/debug/extension. IDs belong to the opening State and are not reused within a process. Images contain no live stream. Full restore while owning one is busy (-528); LOAD-DICTIONARY append preserves the target stream. Saved applications start with no PCM owner. The seven new Builtin tags change the image ABI: recreate older images from source. See [implementation and validation](PCM_PUBLIC_IMPLEMENTATION.md).

The original [Forth synthesis workload](../examples/pcm-synth.fs) defines four generic voices without opening audio. [PCM streaming wrapper](../examples/pcm-synth-play.fs) supports partial writes and cleanup retry. From the repository root, `sigma examples/pcm-synth-play.fs -e "PS-DEMO-SETUP 96 FALSE PS-STREAM BYE"` runs about one second of synthesis and submits silence. TRUE explicitly enables the generated waveform. This is a synthetic workload, not chip emulation; see [specification, measurements and remaining work](PCM_SYNTH_PROTOTYPE.md).

The [NES APU Forth example](NES_APU_FORTH.md) adds a source-backed NTSC register subset for two pulse channels, triangle and noise, including envelope, length, sweep and linear counters. Scheduled writes retain CPU-cycle order during PCM rendering. It defines no new built-in words. CPU/PPU bus races and analog filtering remain outside this prototype; DMC is covered by the extension below. `sigma examples/nes-apu-play.fs -e "NA-DEMO-SETUP 16 FALSE NA-STREAM BYE"` submits silence; TRUE explicitly enables the generated waveform. Loading alone plays nothing.

The [DMC extension](NES_DMC_FORTH.md) adds the fifth NES voice, an owned sample-memory map, reader/buffer/IRQ/loop and direct DAC writes to the Forth example. It models zero DMA delay and excludes CPU/PPU bus conflicts. The five-voice and 8kHz direct-DAC workloads are measured separately; loading still plays nothing.

The [C64 SID Forth model](SID_FORTH.md) provides three timestamped register voices, TEST/SYNC/RING, ADSR and a declared integer filter proxy. Combined waveforms, actual 6581/8580 analog response and ROM compatibility are excluded. `sigma examples/sid-play.fs -e "SI-DEMO-SETUP 16 FALSE SI-STREAM BYE"` synthesizes then submits silence; TRUE explicitly sends generated sound. Loading plays nothing.

The [Paula Forth register model](PAULA_FORTH.md) adds four stereo sample voices, explicit DMA/manual-data state, IRQ masks, attachment and scheduled writes. It declares a zero-bus-delay subset without Agnus arbitration, analog filters or ROM compatibility. `sigma examples/paula-play.fs -e "PA-DEMO-MEMORY PA-DEMO-SETUP 16 FALSE PA-STREAM BYE"` synthesizes then submits stereo silence; TRUE explicitly sends generated sound. Loading alone plays nothing. Mac acceptance remains under task1137 as1147.

The [YM2149/ST Forth model](YM2149_FORTH.md) supplements the existing asynchronous ST-SOUND/SOUND path with timed registers, reads, virtual I/O ports and a declared ST select/data frontend. Its point-sampled PCM is separate from the native step-averaged output. Native fixed-volume zero now mutes the PSG source; envelope level1 and the coupling-filter decay remain intact. Loading plays nothing. `sigma examples/ym2149-play.fs -e "YM-DEMO-SETUP 16 FALSE YM-STREAM BYE"` submits silence; TRUE explicitly enables generated sound. Physical peripherals and complete ST/TOS compatibility are excluded; Mac acceptance1154 remains under1138.

WINDOW-SMOOTH is unsupported for Tk (1318). Pixel comparisons on Windows confirm that both values use integer nearest-neighbor photo copies, not interpolated scaling.

Turning WINDOW-KEEP-OPEN false while a request is held discards the pending request without closing native or Tk windows; the next user request closes them. A host failure during a setting request stops that wish, and the next SHOW supplies the current setting again.
