# P04 implementation and validation

2026-11-13. P04 (547) is in progress. P04a (563) is implemented: basic/borrowed strings (632, 21 words) and owned/editing/Unicode access (633, seven words). P04b (564) is in progress: $VALUE/MACRO: (634) are implemented; macro vocabulary/callback substitution (635, three words) remains pending. P03 review fixes and the first 21 P04a words were committed/pushed as a6ab243. The six edit/owned-string words were committed/pushed as 5b2c8a4.

## Basic characters and borrowed strings (632)

Implemented in src/core/words_text.zig. Startup builtins and tags are appended after P03c, preserving existing execution-token numbers. HELP covers every new word.

- #BELL=7, #BS=8, #CR=13, #DEL=127, #EOF=4, #ESC=27, #FF=12, #LF=10, #TAB=9; INVALID-CHAR=65533.
- NEWLINE returns a borrowed LF at logical 0x0d38 with length 1, consistent with Sigma's logical CR output. The system slot is initialized once and preserved in images; compile-time checks guard adjacent source names and BLK.
- TOUPPER folds ASCII a-z only. Other values, including Unicode letters, are unchanged.
- CAPSCOMPARE returns -1/0/1 with ASCII byte folding. CAPSSTRING-PREFIX? tests whether the second string prefixes the first. STRING-SUFFIX? and STR< use bytewise comparison.
- CAPSSEARCH returns a borrowed suffix at the first ASCII-folded match; a failed search returns the original descriptor and false. Empty patterns match at the beginning.
- SAFE/STRING clamps a signed skip to zero through the declared length. SCAN-BACK returns the original address and a prefix length including the last matching byte, or zero.
- NOSPLIT? retains four operands and tests that the second descriptor is empty exactly at the first descriptor's end. It does not dereference the descriptors.
- TYPEWHITE emits a space for every byte except TAB, which is preserved. Negative lengths are empty. UTF-8 is treated as bytes for this word, as documented by Gforth.

Range/depth/capacity checks precede operand changes. Native comparison/search/scan/output loops use the existing bounded-work check for --max-steps; ordinary fixed-cost VM execution is unchanged. Only borrowed regions are returned; these words do not allocate owned strings or infer pointer types.

## Validation

Six regressions in src/tests/p04a_basic_test.zig cover execution/compilation, borrowed slices, empty/missing/boundary cases, exact TYPEWHITE bytes, range/capacity failures and operand preservation, NEWLINE persistence and native step limits.

Normal and minimal zig build test plus the normal build pass. Logs: .zig-cache/p04a-basic-test.log, p04a-basic-minimal.log, p04a-basic-build.log. scripts/verify-p04a-basic.py passes 323 cases against the designated Gforth, including all byte values for TOUPPER, non-ASCII values and exact whitespace output. Report: .work/p04a-basic-check/results.json.

Gforth sources were consulted only to confirm behavior; no GPL implementation was copied. Windows/Linux checks were not performed here. No version or package change was made.

## Remaining work

633: APPEND, CSTRING>SSTRING, DELETE, INSERT, S+ and STRING, are implemented (see below). XC@+? is implemented with the confirmed empty-input rule (see below). P04a is complete; proceed to 564 ($VALUE, .SUBSTITUTE, MACRO:, MACROS-WORDLIST, REPLACER:). Keep 547 and 542 incomplete until their actual remaining work is finished.

The basic words are in a6ab243; the six edit words are in 5b2c8a4.

## Owned and editing strings (633, six words implemented)

src/core/words_string_edit.zig implements S+, APPEND, CSTRING>SSTRING, DELETE, INSERT and STRING,. Tags and startup words are appended without renumbering existing words.

- S+ allocates an owned concatenation; FREE releases it. APPEND resizes the first owned block and returns its new address. NULL with length zero is accepted. Update external owners with the returned address.
- APPEND preserves a source inside the first allocation across movement. If overlap extends into bytes that resizing would discard, a temporary copy is used before resizing. Errors free temporary allocations and leave the original block intact.
- INSERT clips the source length to the fixed destination size, shifts the destination right, then reads/copies the source. When source aliases destination, it observes that preceding shift, matching the designated Gforth. DELETE clips the deletion length, shifts left and fills the tail with blanks.
- CSTRING>SSTRING scans to NUL within logical memory and returns a borrowed slice; an absent terminator is InvalidAddress.
- STRING, writes the low-byte count before copying every source byte to dictionary space. Lengths above 255 still allocate/copy all bytes, as the reference does. No implicit alignment is added. Overlap observes the prefix-before-copy order.

address_registry.preflightCopies simulates registration keys across compound copies. INSERT checks both stages before modifying bytes, including metadata created by its first stage. STRING, preflights before changing HERE/count. S+ cleans up a new destination if either copy cannot fit the registry; APPEND checks capacity before resizing the original. Existing types and partial-write damage remain connected to the P03 registry.

Eight regressions cover forced APPEND movement/self overlap, sequential INSERT overlap, clamped deletion, long/overlapping STRING,, bounded NUL scanning, compound metadata exhaustion, input/owner/HERE preservation and failed-allocation cleanup. Normal/minimal zig build test and the normal build pass. Logs: .zig-cache/p04a-edit-test.log, p04a-edit-minimal.log, p04a-edit-build.log. verify-p04a-edit.py passes 48 cases against the designated Gforth; report .work/p04a-edit-check/results.json.

The XC@+? empty-input decision was confirmed by the user on 2026-11-13. The designated Gforth advances one byte and returns remaining length -1 even for empty input; Sigma's existing X@+/STRING advances similarly but returns U+FFFD without reading a byte. The implemented word follows the confirmed Sigma rule; 633 and 563 are complete. Keep 547 incomplete until P04b is finished.

An additional 12-case probe compared Sigma X@+/STRING with the designated Gforth XC@+?. All 11 nonempty inputs matched, including truncated/invalid UTF-8, overlong encodings and surrogates. Empty input alone differed in the returned code point (Sigma U+FFFD, Gforth 0); both advanced one byte and returned remaining length -1. Results: .work/p04a-edit-check/xc-probe.json. The subsequent implementation follows the confirmed Sigma empty-input rule.

## XC@+? (633, final word)

XC@+? ( addr u -- addr2 u2 xc ) shares the existing bounded UTF-8 decoder with X@+/STRING. Valid, truncated and malformed nonempty input follows the established Sigma rules, including overlong encodings and surrogates. The caller receives the remaining borrowed span and decoded code point.

The user confirmed empty input returns U+FFFD, advances one byte and leaves remaining length -1, without reading memory. It is safe even when the original empty span starts at logical memory's end. Consumers must not pass a negative remaining length back as a valid string. This deliberately differs from the designated Gforth's empty-input code point 0.

Both entry points now check input ranges and the extra output cell before consuming operands. The new builtin is appended after the other six edit words, preserving prior execution-token numbers. HELP documents the empty-input rule.

Four regressions in p04a_xc_test.zig cover 11 UTF-8 forms, empty input at memory end, range/capacity preservation, compilation and save/restore/append execution. Normal/minimal zig build test and the normal build pass. Logs: .zig-cache/p04a-xc-test.log, p04a-xc-minimal.log, p04a-xc-build.log. verify-p04a-xc.py passes 301 nonempty comparisons with designated Gforth and three Sigma-specific empty cases. Report: .work/p04a-xc-check/results.json.

P04a totals: 28 words, 672 nonempty/general Gforth comparison cases (323+48+301), three separate empty-input cases and 18 regression tests. XC@+? was committed/pushed as fa2afe9. P04b (564) is now in progress; P04 (547) and 542 remain incomplete.

## String values (634, two words)

$VALUE ( addr u "name" -- ) copies its input into an owned dynamic string. Executing the value returns a borrowed addr/u. TO replaces the string and +TO appends; both work interpreted and compiled. MACRO: is an alias for the same defining behavior in the current wordlist. It does not, by itself, change the current wordlist.

A new string_value WordKind is appended without renumbering existing kinds. Its eight-byte dictionary body owns an explicitly registered heap pointer; >BODY returns that owner cell. The runtime, compiled store/add operations, image data-field relocation, decompiler and linter recognize its two-cell stack effects. Multiline names and defining words containing $VALUE use the existing pending-definition mechanism.

Replacement allocates and copies before releasing the old string. Setters preserve their operands and prior contents on allocation/range/metadata failures. Failed creation restores word count, names, HERE and lookup state. Borrowed addresses remain subject to normal lifetime invalidation when the underlying block is replaced or freed.

FORGET/MARKER remove the value and its registered dictionary owner. They do not automatically free arbitrary dynamic heap blocks, consistent with existing dynamic-string ownership. To release storage before forgetting, use ' name >BODY $FREE. Unrooted blocks are omitted from subsequent images; surviving explicit references retain their reachable objects.

Image validation requires a string_value owner to have an explicit relocation record. A non-NULL owner must point to the beginning of a reachable heap payload with a valid eight-byte length header and sufficient bytes. Missing type records and corrupt headers fail before restore changes the target. A freed/null string owner remains valid.

Nine regressions in p04b_values_test.zig cover interpreted/compiled replacement and append, self assignment, MACRO: and multiline definers, allocation/capacity/range preservation, creation rollback, two independent appended copies and re-save/restore, borrowed-alias invalidation, MARKER roots and malformed owner images. Normal/minimal zig build test and normal build pass. Logs: .zig-cache/p04b-values-test.log, p04b-values-minimal.log, p04b-values-build.log. verify-p04b-values.py passes 27 cases against designated Gforth. CLI save/repeated load and compiled setters also pass; reports in .work/p04b-values-check/.

These changes are uncommitted. P04b and P04 remain incomplete. Next is 635: MACROS-WORDLIST, REPLACER: and .SUBSTITUTE, including case-sensitive macro lookup, existing REPLACES/SUBSTITUTE integration, callback stack ownership and persistence.
