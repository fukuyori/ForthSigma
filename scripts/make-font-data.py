"""Makes src/graphics/font_misaki.zig, the font of TEXT, from the BDF file of Misaki
Gothic (misaki_gothic.bdf in misaki_bdf_2021-05-05.zip, https://littlelimit.net/misaki.htm).

Only the printable ASCII characters (U+0020 to U+007E, 4 pixels wide) are kept. Each
glyph becomes 8 rows of 8 pixels in one 64-bit number, the top row
in the highest byte and the leftmost pixel in the highest bit of its byte.

    python scripts/make-font-data.py path/to/misaki_gothic.bdf
"""

import sys
from pathlib import Path

OUTPUT = Path(__file__).resolve().parent.parent / "src" / "graphics" / "font_misaki.zig"


def is_kept(code):
    return 0x20 <= code <= 0x7E


def read_glyphs(path):
    ascent = None
    glyphs = []
    glyph = None
    bitmap = None
    for line in path.read_text(encoding="ascii", errors="strict").splitlines():
        parts = line.split()
        if not parts:
            continue
        key = parts[0]
        if key == "FONT_ASCENT":
            ascent = int(parts[1])
        elif key == "STARTCHAR":
            glyph = {}
        elif key == "ENCODING":
            glyph["code"] = int(parts[1])
        elif key == "DWIDTH":
            glyph["width"] = int(parts[1])
        elif key == "BBX":
            glyph["bbx"] = [int(part) for part in parts[1:5]]
        elif key == "BITMAP":
            bitmap = []
        elif key == "ENDCHAR":
            glyph["bitmap"] = bitmap
            glyphs.append(glyph)
            glyph = None
            bitmap = None
        elif bitmap is not None:
            # Glyphs are at most 8 pixels wide: one byte a row.
            if len(key) != 2:
                raise SystemExit(f"U+{glyph['code']:04X}: a row wider than 8 pixels")
            bitmap.append(int(key, 16))
    if ascent is None:
        raise SystemExit("no FONT_ASCENT")
    return ascent, glyphs


def cell_rows(ascent, glyph):
    """The 8 rows of the glyph's cell, the top row first (bit 7 is the leftmost pixel)."""
    width, height, x_offset, y_offset = glyph["bbx"]
    rows = [0] * 8
    for index, bits in enumerate(glyph["bitmap"]):
        # Row `index` of the box is at y_offset + height - 1 - index above the baseline;
        # the cell's top row is ascent - 1 above it.
        row = ascent - 1 - (y_offset + height - 1 - index)
        if not 0 <= row < 8:
            if bits:
                raise SystemExit(f"U+{glyph['code']:04X}: a pixel outside the cell")
            continue
        # The box starts x_offset pixels right of the cell's left edge.
        if x_offset < 0 or bits & ((1 << x_offset) - 1):
            raise SystemExit(f"U+{glyph['code']:04X}: a pixel outside the cell")
        rows[row] |= bits >> x_offset
    return rows


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    source = Path(sys.argv[1])
    ascent, glyphs = read_glyphs(source)
    kept = sorted((glyph for glyph in glyphs if is_kept(glyph["code"])), key=lambda glyph: glyph["code"])
    lines = [
        "//! The font of TEXT: the printable ASCII glyphs of Misaki Gothic (美咲ゴシック,",
        "//! 2021-05-05). Made by scripts/make-font-data.py from misaki_gothic.bdf; do not edit.",
        "//!",
        "//! Copyright (C) 2002-2021 Num Kadoma",
        "//! These fonts are free softwares.",
        "//! Unlimited permission is granted to use, copy, and distribute it, with or without",
        "//! modification, either commercially and noncommercially.",
        "//! THESE FONTS ARE PROVIDED \"AS IS\" WITHOUT WARRANTY.",
        "//! (The license as misaki.txt gives it; see also THIRD_PARTY_NOTICES.md.)",
        "",
        "/// A glyph: its code point, its width (4 pixels), and its 8 rows of 8 pixels,",
        "/// the top row in the highest byte and the leftmost pixel in the highest bit.",
        "pub const Glyph = struct { code: u21, width: u8, rows: u64 };",
        "",
        "/// Sorted by code point.",
        "pub const glyphs = [_]Glyph{",
    ]
    for glyph in kept:
        value = 0
        for bits in cell_rows(ascent, glyph):
            value = (value << 8) | bits
        lines.append(f"    .{{ .code = 0x{glyph['code']:04X}, .width = {glyph['width']}, .rows = 0x{value:016X} }},")
    lines.append("};")
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(kept)} glyphs written to {OUTPUT}")


if __name__ == "__main__":
    main()
