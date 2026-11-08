"""Makes src/core/char_width.zig, the column widths of XC-WIDTH and X-WIDTH, from the
Unicode Character Database (https://www.unicode.org/Public/15.1.0/ucd/: UnicodeData.txt,
EastAsianWidth.txt, and PropList.txt, under the Unicode License v3).

The rules give the same widths as gforth 0.7.9_20260410 with glibc 2.39 (which takes
wcwidth from the C library), checked for every code point from U+0000 to U+10FFFF:

- U+0000 is 0 columns.
- Code points with no character (surrogates included), controls (Cc), and the line and
  paragraph separators (Zl, Zp) are -1.
- The prepended concatenation marks are 1 column, though they are format characters.
- Nonspacing and enclosing marks (Mn, Me), format characters (Cf) other than U+00AD,
  the medial vowels and final consonants of Hangul (U+1160 to U+11FF, U+D7B0 to U+D7FF),
  and U+200B are 0 columns.
- East Asian Wide and Fullwidth characters, and U+3248 to U+324F and U+4DC0 to U+4DFF,
  as glibc has them, are 2 columns.
- Everything else is 1 column.

    python scripts/make-width-table.py path/to/ucd
"""

import sys
from pathlib import Path

OUTPUT = Path(__file__).resolve().parent.parent / "src" / "core" / "char_width.zig"
LAST = 0x10FFFF


def ranges(path, wanted=None):
    """The ranges and values of a UCD file of `code..code ; value` lines."""
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        codes, value = [field.strip() for field in line.split(";")[:2]]
        if wanted is not None and value != wanted:
            continue
        first, _, last = codes.partition("..")
        yield int(first, 16), int(last or first, 16), value


def categories(path):
    category = {}
    lines = path.read_text(encoding="utf-8").splitlines()
    index = 0
    while index < len(lines):
        fields = lines[index].split(";")
        code = int(fields[0], 16)
        last = code
        if fields[1].endswith(", First>"):
            index += 1
            last = int(lines[index].split(";")[0], 16)
        for each in range(code, last + 1):
            category[each] = fields[2]
        index += 1
    return category


def widths(ucd):
    category = categories(ucd / "UnicodeData.txt")
    wide = set()
    for first, last, value in ranges(ucd / "EastAsianWidth.txt"):
        if value in ("W", "F"):
            wide.update(range(first, last + 1))
    prepended = set()
    for first, last, _ in ranges(ucd / "PropList.txt", "Prepended_Concatenation_Mark"):
        prepended.update(range(first, last + 1))

    def width(code):
        if code == 0:
            return 0
        kind = category.get(code)
        if kind in (None, "Cs", "Cc", "Zl", "Zp"):
            return -1
        if code in prepended or code == 0xAD:
            return 1
        if kind in ("Mn", "Me", "Cf"):
            return 0
        if 0x1160 <= code <= 0x11FF or 0xD7B0 <= code <= 0xD7FF or code == 0x200B:
            return 0
        if code in wide or 0x3248 <= code <= 0x324F or 0x4DC0 <= code <= 0x4DFF:
            return 2
        return 1

    return [width(code) for code in range(LAST + 1)]


def runs(values):
    """The runs of equal widths other than 1, as (first, last, width)."""
    result = []
    start = 0
    for code in range(1, LAST + 2):
        if code <= LAST and values[code] == values[start]:
            continue
        if values[start] != 1:
            result.append((start, code - 1, values[start]))
        start = code
    return result


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    table = runs(widths(Path(sys.argv[1])))
    lines = [
        "//! The column widths of characters for XC-WIDTH and X-WIDTH, made by",
        "//! scripts/make-width-table.py from the Unicode Character Database 15.1.0",
        "//! (Unicode License v3, see THIRD_PARTY_NOTICES.md). Do not edit by hand.",
        "",
        "const std = @import(\"std\");",
        "",
        "/// The runs of code points whose width is not 1, in order: first, last, and width.",
        "/// Only `runs` below goes into the program.",
        "const listed = [_]struct { u21, u21, i8 }{",
    ]
    lines += [f"    .{{ 0x{first:X}, 0x{last:X}, {width} }}," for first, last, width in table]
    lines += [
        "};",
        "",
        "/// The same runs in 6 bytes each, a little-endian 48-bit number: the first code point",
        "/// in bits 0 to 20, the last in bits 21 to 41, and the width in bits 42 and 43",
        "/// (0 for -1, 1 for 0, 2 for 2).",
        "pub const runs: [listed.len][6]u8 = blk: {",
        "    @setEvalBranchQuota(100_000);",
        "    var result: [listed.len][6]u8 = undefined;",
        "    for (listed, &result) |run, *bytes| {",
        "        const code: u48 = switch (run[2]) {",
        "            -1 => 0,",
        "            0 => 1,",
        "            2 => 2,",
        "            else => unreachable,",
        "        };",
        "        bytes.* = @bitCast(std.mem.nativeToLittle(u48, @as(u48, run[0]) | (@as(u48, run[1]) << 21) | (code << 42)));",
        "    }",
        "    break :blk result;",
        "};",
        "",
        "fn first(index: usize) u21 {",
        "    return @truncate(std.mem.readInt(u48, &runs[index], .little));",
        "}",
        "",
        "/// The width of a code point: 0, 1, or 2 columns, or -1 for one that is not shown",
        "/// (no character, a control, or a value above U+10FFFF).",
        "pub fn width(code: u64) i8 {",
        "    if (code > 0x10FFFF) return -1;",
        "    var low: usize = 0;",
        "    var high: usize = runs.len;",
        "    while (low < high) {",
        "        const middle = (low + high) / 2;",
        "        const run = std.mem.readInt(u48, &runs[middle], .little);",
        "        if (code < first(middle)) {",
        "            high = middle;",
        "        } else if (code > @as(u21, @truncate(run >> 21))) {",
        "            low = middle + 1;",
        "        } else return switch (@as(u2, @truncate(run >> 42))) {",
        "            0 => -1,",
        "            1 => 0,",
        "            else => 2,",
        "        };",
        "    }",
        "    return 1;",
        "}",
        "",
    ]
    OUTPUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"{len(table)} runs written to {OUTPUT}")


if __name__ == "__main__":
    main()
