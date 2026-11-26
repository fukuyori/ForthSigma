# Task 1401: deterministic embedded text

## Inventory

The audit used `git grep -n "@embedFile"`. Documentation mentions are not embed calls. Anonymous import names are resolved by `addEmbeddedTexts` and the test module in `build.zig`. The image helper resolves names from `src/tests/images/expected.zig` and literal test arguments.

| Embed source | File(s) | Treatment |
|---|---|---|
| `src/core/words_audio.zig` | `src/audio/audio.fs` | CR removal |
| `src/core/words_extension.zig` | `src/extension/extension.fs` | CR removal |
| `src/core/words_game.zig` | `src/graphics/game.fs` | CR removal |
| `src/core/words_graphics.zig` | `src/graphics/graphics.fs`, `src/graphics/graphics_float.fs` | CR removal before concatenation |
| `src/core/words_gui.zig` | `src/graphics/gui.fs` | CR removal |
| `src/core/tcl.zig` | `src/graphics/sigma_tk.tcl` | CR removal |
| `src/core/words_help.zig` | `LICENSE`, `THIRD_PARTY_NOTICES.md` | Existing CR removal moved to shared helper |
| `src/main.zig` (two sites) | `VERSION` | CR removal before existing trailing whitespace trim |
| `src/tests/audio_test.zig` | `include/chip-sound.fs`, `include/msx-sound.fs`, `include/st-sound.fs`, `include/nes-sound.fs`, `include/c64-sound.fs`, `include/scc-sound.fs`, `include/amiga-sound.fs`, `include/chips.fs` | CR removal |
| `src/tests/filesystem_test.zig` | `tests/data/compact-filename.json` | CR removal |
| `src/tests/grapheme_test.zig` | `tests/data/unicode-18.0.0/GraphemeBreakTest.txt` | CR removal |
| `src/tests/load_image_test.zig` | `src/tests/images/` files listed below | Original bytes |

Image files (relative to `src/tests/images/`): `argb32_v5.bmp`, `core8.bmp`, `gray.pgm`, `gray1.png`, `gray16.png`, `gray2.png`, `gray2_adam7.png`, `gray4.png`, `gray8.png`, `gray_trns.png`, `la16.png`, `la8.png`, `mono1.bmp`, `pal4.bmp`, `pal4.png`, `pal8.bmp`, `pal8.png`, `plain.ppm`, `plain15.pgm`, `rgb.ppm`, `rgb16.png`, `rgb16.ppm`, `rgb24.bmp`, `rgb555.bmp`, `rgb565.bmp`, `rgb8.png`, `rgb8_adam7.png`, `rgb_trns.png`, `rgba16.png`, `rgba8.png`, `topdown24.bmp`, `xrgb32.bmp`.

## Method

Option b: `src/core/embedded_text.zig` removes CR bytes at comptime. Two linear passes count and copy bytes into an exactly sized constant array. This avoids repeated string concatenation and adds no runtime work. LF inputs, UTF-8, and a missing final newline retain their bytes. The existing license normalizer now uses the same helper. Binary image fixtures bypass it, including textual PPM/PGM files whose exact bytes are test input. `VERSION` is normalized before the existing trailing whitespace trim at both sites. Inspection of `.rdata` showed that trimming alone retained the original LF/CRLF backing array, so normalizing this input is necessary too.

This works for both autocrlf checkouts and manually converted files, without requiring a fresh checkout. `.gitattributes` is unchanged, including all `-text` entries for measurement and acceptance plans. Existing license notices and licensing terms are unchanged.

`src/core/source_input.zig:readEmbeddedLine` splits at LF and optionally removes a trailing CR. It does not require CR. The normalized libraries therefore use its existing LF path. Tcl receives the same script bytes as the LF input.

## Reproducibility

Environment: Windows x86_64, Zig 0.17.1. Archived HEAD: `792cf26a154cc2fed786ffb9d265c4c2d07cc63d`. Evidence is under `.work/1401/` (local artifacts, not versioned).

PowerShell environment used for all builds:

```powershell
$env:ZIG_GLOBAL_CACHE_DIR="$PWD/.work/codex-cache/global"
$env:ZIG_LOCAL_CACHE_DIR="$PWD/.work/codex-cache/local"
python .work/1401/reproduce.py
```

`git archive HEAD` produced `head.tar`, extracted independently to `lf/` and `crlf/`. The script converts all text embed targets to LF or CRLF, including licenses, VERSION and test text fixtures; binary images are untouched. It asserts that removing CR is equivalent to replacing CRLF with LF for these inputs. Each copy is built before the fix, then receives only the implementation files and is built again. All four builds use `zig build -Doptimize=ReleaseFast -Ddebug=false -Dstrip=true`. The PE section table determines `.text` PointerToRawData and SizeOfRawData; SHA-256 covers exactly those raw section bytes, including alignment padding. Build logs, extracted sections and `hashes.json` are retained. No original working-tree checkout or index mutation is used.

| Implementation | Line endings | `.text` SHA-256 |
|---|---|---|
| before | LF | `c929f33f2e6c3a376ea838f7a147d8e601d46b6548eec8eace3f280500b97848` |
| before | CRLF | `f08e94fdbd68c41fd3d78119942dc6317f11313e1b7a1dcfe3c820278eea3cca` |
| after | LF | `9702ed2043e5ec74ab0f0508283b4573e7bca7bcd1c334a9d0d2081806012510` |
| after | CRLF | `9702ed2043e5ec74ab0f0508283b4573e7bca7bcd1c334a9d0d2081806012510` |

Before the fix the hashes differ; after the fix they match. Each raw section is 1,532,928 bytes. Both copies receive the same frozen implementation snapshot, checked against the working tree again at the end. LF content hashes for all 20 text inputs are recorded in `lf-content-sha256.json`.

## Validation

All checks passed with exit code 0.

- `zig test src/core/embedded_text.zig` (1 test)
- `zig build test`
- `zig build runtime-test`
- `python scripts/check-docs.py` (findings: 0)
- `git diff --check`

The documentation check tracks implementation fingerprints. After confirming that word definitions and descriptions are unchanged, `python scripts/word-reference.py --record-reviewed-sources` updated `docs/word-reference/translation-sources.json`. Generated reference prose has no diff.

The helper test covers empty input, unchanged LF, CRLF, standalone CR, UTF-8 and no final LF. Source inspection establishes the LF reader behavior; the normal core suite exercises loading and embedded source navigation.

## Limits

The comparison establishes `.text` equality for the stated Windows build configuration. It does not establish whole-PE equality, cross-toolchain reproducibility, other operating systems, or every feature-option combination. No interactive Tcl/Tk GUI check was performed. New embedded text must explicitly use the helper; new binary assets must preserve their bytes.
