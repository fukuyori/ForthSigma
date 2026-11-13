# P05 implementation and validation

2026-11-13. P05 (548) is in progress. P05a (565) has eight of sixteen words implemented:653 stream helpers,654 input/EOF and655 modes/history/source termination. P05a, P05 and 542 remain incomplete. Task653 was committed/pushed as d8da5e7. Task654 was committed/pushed as7964014. Task655 is implemented and validated, uncommitted.

## File output and stream slurp (653)

EMIT-FILE ( c fileid -- ior ) writes the low eight bits through FileOps.write, without adding a newline, flushing, or closing. It returns the host write error. Input depth is checked before host access.

SLURP-FID ( fileid -- addr u ) reads from the current position through EOF into a new owned raw heap allocation; release addr with FREE. The caller retains the open handle. Empty input still returns a valid FREE-able allocation. Neither size nor seek support is required, so nonseekable streams can use the same host interface. Positive short reads are accumulated; FileOps.read defines only a zero-byte read as EOF. This accommodates the existing host contract rather than assuming every short read ends a stream. Regular-file behavior matches the designated Gforth.

Reads use a 1,024-byte scratch buffer. Growth retries exact capacity if speculative doubling fails; successful results shrink to their length (allocator minimum/alignment still apply). Read/allocation errors propagate through THROW; private allocations are released and the input handle remains on the data stack. Output stack room is checked before reading. Reads already performed are not rolled back, including when allocation subsequently fails. Native-loop work checks honor an enabled --max-steps limit. Host over-reporting of read length is rejected before copying.

Implementation: words_files.zig dispatch and file_streams.zig. Builtin tags/startup entries are appended, preserving earlier execution-token numbers. Membership in words_files automatically excludes the two words in -Dfiles=false builds. New tags change the strict image ABI signature as previously documented; same-magic files from older builtin tables are not promised compatible. No GPL implementation code was copied; local Gforth sources were used for behavioral reference only.

## Validation

Seven regressions in p05a_stream_test.zig cover byte truncation and host write errors, binary/current-position reads, continued short reads with size/position unavailable, empty-owned allocation, cleanup after read and heap failures, stack preflight before I/O, and work-budget failure. Normal/minimal zig build test and normal zig build pass. Logs: .zig-cache/p05a-stream-{test,minimal,build}.log.

scripts/verify-p05a-stream.py passes 29 designated-Gforth comparisons: low-byte EMIT-FILE values and lengths 0/1/1023/1024/1025/4097 at beginning/middle/EOF/beyond EOF, binary checksums, final position, handle closure by the caller and balanced stacks. Files include Japanese names. Report: .work/p05a-stream-check/comparison.json.

## Remaining work

- 656: eight path words. Determine path descriptor ownership, search order, borrowed/owned resolved filenames, failures, and integration with INCLUDE/REQUIRE. ABSOLUTE-FILE? is part of this group.
- 566: P05b directory/time fourteen words remain pending.

Task progress remains auto. Windows/Linux native verification is not performed here (607). No version bump or release package was made. Task653 was committed/pushed as d8da5e7.


## File input / EOF investigation (654, before implementation)

The local designated-Gforth probes in `.work/p05a-input-check/{regular-probe,state-probes}.json` confirm KEY-FILE returns byte values (including NUL and 255) or -1 on EOF. FILE-EOF? stays false after the last successfully read byte until a read attempts EOF. Repeated KEY?-FILE does not consume bytes; a regular stream at its end reports false. A successful reposition clears the EOF indication. FILE-SIZE does not clear an already-set indication in the designated Gforth.

At investigation time, host FileOps provided read/size/position but no readiness or EOF-state callback. The main host uses buffered C streams for ordinary files and separate byte/queued-input paths for STDIN. Readiness must account for buffered/unread bytes, must not block and must not steal input from the established APIs. Comparing position and size would not implement an EOF indicator, and the current seek-based fileSize can clear the C indicator as an internal side effect. These interactions must be handled explicitly when exposing EOF state. The implementation below adds optional readiness/EOF hooks and per-stream state.

Gforth documents raw one-key input for KEY-FILE on STDIN. Sigma's current terminalKey/readByte path leaves raw mode and uses its existing line-input path; terminalKeyReady also calls standardInputByte. The user approved the recommended policy: one-key STDIN with terminal Ctrl+C as an interrupt like EKEY, while retaining existing input API behavior.

A further designated-Gforth probe (`buffered-ready-probe.json`) with AB prints `-1 65 0 66`: readiness is initially true, KEY-FILE reads A, readiness becomes false, yet KEY-FILE immediately returns B. The local non-LEGACY implementation queries descriptor FIONREAD and reads via fgetc, which explains the buffered-byte mismatch. This is not the documented "a character can be read without blocking" goal. The user also approved the documented readiness semantics including already-buffered bytes, rather than reproducing this designated-build quirk.


## File input / EOF implementation (654, 7964014 pushed)

- KEY-FILE ( fileid -- c ) returns a byte 0..255 or -1 on EOF. I/O errors THROW. STDIN reads raw terminal bytes, interrupts on terminal Ctrl+C, and shares host lookahead/pending input with existing APIs. Redirected byte3 remains binary data. On a Windows console, character bytes are UTF-8; extended non-character key events are skipped (use EKEY for those).
- KEY?-FILE ( fileid -- flag ) does not wait for future input, consume a byte, or change the semantic EOF indication. Library-buffered and unread bytes count as ready. This deliberately fixes the measured Gforth false-readiness case.
- FILE-EOF? ( fileid -- flag ) returns an observed read-end indicator, not a position comparison. Ordinary-file KEY-FILE, READ-FILE, READ-LINE and stream slurp feed the shared state. Successful reposition clears it. Internal FILE-SIZE seeks and zero-length reads preserve it, including after EOF. STDIN tracks its shared byte transport, clearing EOF when input is successfully consumed/unread. These are runtime resources, not image data.

FileOps has optional key (RuntimeError!FileKeyResult), ready (RuntimeError!FileResult), and eof (FileResult) callbacks. Missing capabilities raise FileUnavailable instead of silently using blocking or position-based substitutes. Errors leave the handle operand in place. The fake host also models read-end and reposition state, and the core remains freestanding-compatible. Tags/startup entries are appended and the three words belong to the files feature group.

The main host uses a serial C-stream probe on POSIX: temporarily enable descriptor nonblocking mode, get/unget one byte, clear speculative EOF/EAGAIN and restore original descriptor flags. The stream's existing buffering is retained. Windows disk streams retain normal buffering; only Windows pipe streams are opened unbuffered so PeekNamedPipe plus tracked query pushback can account for every available byte. Target stdio/fcntl constants come from a small translate-C header, using the build's existing libc/translation infrastructure. Other Windows character streams apart from STDIN return an unsupported/invalid I/O result rather than blocking. Native Windows/Linux verification is deferred to657 under607.

Validation: five core regressions in p05a_input_test.zig and two main-host regressions cover all256 byte values, EOF timing/reposition, repeated readiness, compiled execution, missing hooks, host errors/interrupt, invalid handles, full-stack operation, real stdio prefetch, descriptor-flag restoration, READ-FILE/READ-LINE mixing, FILE-SIZE and empty reads after EOF. Normal/minimal tests and the normal build pass. Logs: .zig-cache/p05a-input-{test,minimal,build}.log.

scripts/verify-p05a-input.py passes 258 Gforth comparisons (257 regular-file byte/empty cases and redirected binary STDIN), one intentionally different buffered-readiness case, five Sigma PTY cases and one named-FIFO case. PTYs confirm input without Enter, ESC without continuation wait, UTF-8 bytes, lookahead shared with legacy KEY, terminal Ctrl+C interruption and terminal restoration. The FIFO test keeps a writer alive while checking empty readiness, then verifies queued/library-buffered bytes and final EOF. Report: .work/p05a-input-check/comparison.json.

A restoration check initially reported a termios mismatch. A separate probe showed existing EKEY and new KEY-FILE both restore all settings apart from Darwin's transient PENDIN bit. The PTY check ignores that one driver-maintained bit and checks all stable settings. Evidence: terminal-state-probe.json under the same report directory; no terminal-control implementation was changed to mask this test result.

At completion of654, P05a had5/16 words implemented. Task655 completion is recorded below; P05b566 is pending. Keep565/548/542 incomplete. Progress remains auto. No native Windows/Linux checks, version bump or package creation were performed for654; it was subsequently committed/pushed as7964014.


## Modes, included names and source termination (655, uncommitted)

+FMODE ( fam mode -- fam2 ) packs a nine-bit rwxrwxrwx value into the existing fam, following Gforth's OR/XOR encoding (default438 decimal /0666). R/O, R/W, W/O and BIN retain their values. OPEN-FILE accepts and ignores permission fields; CREATE-FILE decodes them. The default mode uses the existing open callback, while nondefault permissions require optional FileOps.create_mode; unsupported requests return an ior before creating/truncating anything. The old error regression used fam99, which now has a valid permission encoding; it now tests reserved bit3 (fam8).

The main host creates explicit-mode files with open/_wopen and fdopen, rather than chmod after creation. POSIX permissions are applied at creation subject to umask, and the supplied mode does not replace an existing file's permissions during truncation. Windows maps owner read/write bits to CRT permissions; group/execute bits do not provide POSIX permissions or ACL management there. The existing CREATE-FILE access-mode mapping is retained. Descriptor ownership transfers to the C stream, with cleanup on fdopen failure and slot checks before creation. Native Windows/Linux checks are in658 under607 and were not performed here.

.INCLUDED ( -- ) displays each currently loaded registered name once, in source-table registration order. Each name is preceded by a newline; there is no added trailing newline. MARKER's existing loaded flags control visibility. Names opened before a source interpretation error remain registered under the existing REQUIRE-history policy. Saved/restored/appended source metadata supplies the same list. The user explicitly approved unique names: Gforth lists repeated INCLUDE occurrences, whereas Sigma's source table and existing MARKER/image mechanisms manage distinct registered names. Path normalization remains part of656.

The immediate three-backslash word ( -- ) seeks the current physical source file to its end, observes/drains EOF without replacing the current source buffer, and skips the rest of the current line. The caller resumes normally and the include owner closes the skipped file. Size/seek/read failures propagate; nonseekable sources can therefore report an I/O error. Embedded source files advance their embedded offset without host I/O. Per the user's confirmed policy, terminal, EVALUATE and block sources do nothing with no stack changes; EVALUATE inside a file does not terminate the outer file. This avoids the designated Gforth build's extra SOURCE-ID stack cell / invalid handle access outside physical files. Existing incomplete-definition checks are retained.

Validation: nine regressions in p05a_misc_test.zig cover interpreted/compiled mode transport, unsupported hosts without truncation, existing permissions, unique loaded history/MARKER/error history, append/restore listing, immediate/no-op contexts, nested/embedded/evaluated sources, POSTPONE and all three skip I/O failures with handle cleanup. Normal/minimal tests and normal build pass. Logs: .zig-cache/p05a-misc-{test,minimal,build}.log.

scripts/verify-p05a-misc.py compares3,072 mode values (512 modes across six access/BIN combinations),29 POSIX permission/umask/existing-file cases, two history stages and three file-source cases with the designated Gforth. It separately checks the confirmed non-file no-op policy and intentional duplicate-history difference. Report: .work/p05a-misc-check/comparison.json. The umask is set only in child processes. Earlier probes are in initial-probes.json in the same directory. No GPL implementation code was copied.

Tasks653/654/655 are complete (auto). P05a now has8/16 words implemented; remaining eight path words are656. Keep565/548/542 incomplete; P05b566 is pending. Task655 changes are uncommitted. No version bump or release package was made.
