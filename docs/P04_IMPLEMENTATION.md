# P04 implementation and validation

2026-11-13. P04 (547) is in progress. P04a (563) is split into basic/borrowed strings (632, 21 words) and owned/editing/Unicode access (633, seven words). P04b (564, five words) remains pending. The previous P03 review fixes remain uncommitted; no Git operation was requested for this turn.

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

633: APPEND, CSTRING>SSTRING, DELETE, INSERT, S+, STRING,, XC@+?. Check ownership, allocator failures, overlap, dictionary lifetime and malformed/truncated UTF-8. Then complete 563 and proceed to 564 ($VALUE, .SUBSTITUTE, MACRO:, MACROS-WORDLIST, REPLACER:). Keep 547 and 542 incomplete until their actual remaining work is finished.

The P04 changes are uncommitted.
