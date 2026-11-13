# P05 implementation and validation

2026-11-13. P05 (548) is in progress. P05a (565) has two of sixteen words implemented in task653: EMIT-FILE and SLURP-FID. P05a, P05 and 542 remain incomplete. Source changes are uncommitted.

## File output and stream slurp (653)

EMIT-FILE ( c fileid -- ior ) writes the low eight bits through FileOps.write, without adding a newline, flushing, or closing. It returns the host write error. Input depth is checked before host access.

SLURP-FID ( fileid -- addr u ) reads from the current position through EOF into a new owned raw heap allocation; release addr with FREE. The caller retains the open handle. Empty input still returns a valid FREE-able allocation. Neither size nor seek support is required, so nonseekable streams can use the same host interface. Positive short reads are accumulated; FileOps.read defines only a zero-byte read as EOF. This accommodates the existing host contract rather than assuming every short read ends a stream. Regular-file behavior matches the designated Gforth.

Reads use a 1,024-byte scratch buffer. Growth retries exact capacity if speculative doubling fails; successful results shrink to their length (allocator minimum/alignment still apply). Read/allocation errors propagate through THROW; private allocations are released and the input handle remains on the data stack. Output stack room is checked before reading. Reads already performed are not rolled back, including when allocation subsequently fails. Native-loop work checks honor an enabled --max-steps limit. Host over-reporting of read length is rejected before copying.

Implementation: words_files.zig dispatch and file_streams.zig. Builtin tags/startup entries are appended, preserving earlier execution-token numbers. Membership in words_files automatically excludes the two words in -Dfiles=false builds. New tags change the strict image ABI signature as previously documented; same-magic files from older builtin tables are not promised compatible. No GPL implementation code was copied; local Gforth sources were used for behavioral reference only.

## Validation

Seven regressions in p05a_stream_test.zig cover byte truncation and host write errors, binary/current-position reads, continued short reads with size/position unavailable, empty-owned allocation, cleanup after read and heap failures, stack preflight before I/O, and work-budget failure. Normal/minimal zig build test and normal zig build pass. Logs: .zig-cache/p05a-stream-{test,minimal,build}.log.

scripts/verify-p05a-stream.py passes 29 designated-Gforth comparisons: low-byte EMIT-FILE values and lengths 0/1/1023/1024/1025/4097 at beginning/middle/EOF/beyond EOF, binary checksums, final position, handle closure by the caller and balanced stacks. Files include Japanese names. Report: .work/p05a-stream-check/comparison.json.

## Remaining work

- 654: KEY-FILE, KEY?-FILE, FILE-EOF?. Gforth FILE-EOF? observes a stream EOF indicator, not a position/size comparison; KEY?-FILE requires nonblocking readiness. Existing FileOps has read/size/position but no readiness/EOF-indicator callback. Determine the host contract before implementing these words; retain terminal/pipe behavior and existing input semantics.
- 655: +FMODE, .INCLUDED and the three-backslash source terminator. Investigate permission-mode representation, source-file listing and nested-input behavior before implementation.
- 656: eight path words. Determine path descriptor ownership, search order, borrowed/owned resolved filenames, failures, and integration with INCLUDE/REQUIRE. ABSOLUTE-FILE? is part of this group.
- 566: P05b directory/time fourteen words remain pending.

Task progress remains auto. Windows/Linux native verification is not performed here (607). No version bump, release package, commit or push was performed for this stage.
