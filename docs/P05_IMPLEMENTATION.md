# P05 implementation and validation

Updated2026-11-14. P05a (565) has all sixteen words implemented and validated. Tasks653/654/655 were pushed as d8da5e7/7964014/2b97309;659 was pushed as3af3c9f. Task660 was committed/pushed as9d57d8e. P05b task663 implements the first two of fourteen words, committed/pushed as b9e5099. Task664 adds FILENAME-MATCH, uncommitted; P05b is3/14. P05 (548) and542 remain incomplete: P05b566 and separate INCLUDE/REQUIRE integration661 remain pending. Native Windows/Linux checks are tracked separately under607.

## File output and stream slurp (653)

EMIT-FILE ( c fileid -- ior ) writes the low eight bits through FileOps.write, without adding a newline, flushing, or closing. It returns the host write error. Input depth is checked before host access.

SLURP-FID ( fileid -- addr u ) reads from the current position through EOF into a new owned raw heap allocation; release addr with FREE. The caller retains the open handle. Empty input still returns a valid FREE-able allocation. Neither size nor seek support is required, so nonseekable streams can use the same host interface. Positive short reads are accumulated; FileOps.read defines only a zero-byte read as EOF. This accommodates the existing host contract rather than assuming every short read ends a stream. Regular-file behavior matches the designated Gforth.

Reads use a 1,024-byte scratch buffer. Growth retries exact capacity if speculative doubling fails; successful results shrink to their length (allocator minimum/alignment still apply). Read/allocation errors propagate through THROW; private allocations are released and the input handle remains on the data stack. Output stack room is checked before reading. Reads already performed are not rolled back, including when allocation subsequently fails. Native-loop work checks honor an enabled --max-steps limit. Host over-reporting of read length is rejected before copying.

Implementation: words_files.zig dispatch and file_streams.zig. Builtin tags/startup entries are appended, preserving earlier execution-token numbers. Membership in words_files automatically excludes the two words in -Dfiles=false builds. New tags change the strict image ABI signature as previously documented; same-magic files from older builtin tables are not promised compatible. No GPL implementation code was copied; local Gforth sources were used for behavioral reference only.

## Validation

Seven regressions in p05a_stream_test.zig cover byte truncation and host write errors, binary/current-position reads, continued short reads with size/position unavailable, empty-owned allocation, cleanup after read and heap failures, stack preflight before I/O, and work-budget failure. Normal/minimal zig build test and normal zig build pass. Logs: .zig-cache/p05a-stream-{test,minimal,build}.log.

scripts/verify-p05a-stream.py passes 29 designated-Gforth comparisons: low-byte EMIT-FILE values and lengths 0/1/1023/1024/1025/4097 at beginning/middle/EOF/beyond EOF, binary checksums, final position, handle closure by the caller and balanced stacks. Files include Japanese names. Report: .work/p05a-stream-check/comparison.json.

## Remaining work

- 661: separately design INCLUDE/REQUIRE integration; the user approved keeping existing source loading unchanged in660.
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


## Modes, included names and source termination (655, 2b97309 pushed)

+FMODE ( fam mode -- fam2 ) packs a nine-bit rwxrwxrwx value into the existing fam, following Gforth's OR/XOR encoding (default438 decimal /0666). R/O, R/W, W/O and BIN retain their values. OPEN-FILE accepts and ignores permission fields; CREATE-FILE decodes them. The default mode uses the existing open callback, while nondefault permissions require optional FileOps.create_mode; unsupported requests return an ior before creating/truncating anything. The old error regression used fam99, which now has a valid permission encoding; it now tests reserved bit3 (fam8).

The main host creates explicit-mode files with open/_wopen and fdopen, rather than chmod after creation. POSIX permissions are applied at creation subject to umask, and the supplied mode does not replace an existing file's permissions during truncation. Windows maps owner read/write bits to CRT permissions; group/execute bits do not provide POSIX permissions or ACL management there. The existing CREATE-FILE access-mode mapping is retained. Descriptor ownership transfers to the C stream, with cleanup on fdopen failure and slot checks before creation. Native Windows/Linux checks are in658 under607 and were not performed here.

.INCLUDED ( -- ) displays each currently loaded registered name once, in source-table registration order. Each name is preceded by a newline; there is no added trailing newline. MARKER's existing loaded flags control visibility. Names opened before a source interpretation error remain registered under the existing REQUIRE-history policy. Saved/restored/appended source metadata supplies the same list. The user explicitly approved unique names: Gforth lists repeated INCLUDE occurrences, whereas Sigma's source table and existing MARKER/image mechanisms manage distinct registered names. Path normalization remains part of656.

The immediate three-backslash word ( -- ) seeks the current physical source file to its end, observes/drains EOF without replacing the current source buffer, and skips the rest of the current line. The caller resumes normally and the include owner closes the skipped file. Size/seek/read failures propagate; nonseekable sources can therefore report an I/O error. Embedded source files advance their embedded offset without host I/O. Per the user's confirmed policy, terminal, EVALUATE and block sources do nothing with no stack changes; EVALUATE inside a file does not terminate the outer file. This avoids the designated Gforth build's extra SOURCE-ID stack cell / invalid handle access outside physical files. Existing incomplete-definition checks are retained.

Validation: nine regressions in p05a_misc_test.zig cover interpreted/compiled mode transport, unsupported hosts without truncation, existing permissions, unique loaded history/MARKER/error history, append/restore listing, immediate/no-op contexts, nested/embedded/evaluated sources, POSTPONE and all three skip I/O failures with handle cleanup. Normal/minimal tests and normal build pass. Logs: .zig-cache/p05a-misc-{test,minimal,build}.log.

scripts/verify-p05a-misc.py compares3,072 mode values (512 modes across six access/BIN combinations),29 POSIX permission/umask/existing-file cases, two history stages and three file-source cases with the designated Gforth. It separately checks the confirmed non-file no-op policy and intentional duplicate-history difference. Report: .work/p05a-misc-check/comparison.json. The umask is set only in child processes. Earlier probes are in initial-probes.json in the same directory. No GPL implementation code was copied.

Tasks653/654/655 are complete (auto). P05a now has8/16 words implemented; remaining eight path words are656. Keep565/548/542 incomplete; P05b566 is pending. Task655 was committed/pushed as2b97309. No version bump or release package was made.


## Path descriptors (659, 2026-11-14, 3af3c9f pushed)

Six words are implemented in core/paths.zig through the files dispatch/feature group. Path addresses are ordinary initialized dynamic-string owner cells (e.g. VARIABLE P), with NUL-separated directory bytes. They interoperate with $@/$@LEN/$FREE and existing typed owner/image relocation; no new dictionary kind or OS resource is introduced.

- ABSOLUTE-FILE? is Gforth's syntactic search-bypass test, not OS realpath: leading slash/tilde/./ or a second-character colon in a name longer than two bytes. Other embedded slashes and ../ are relative. Empty spans return false without reading memory, even at the memory endpoint.
- CLEAR-PATH replaces with an owned empty string. ALSO-PATH appends raw directory bytes, inserting one NUL when the old string has nonzero length. PATH+ parses one token and appends; PATH= replaces from one token, translating | to NUL in a private copy. PATH= retains the caller's original source bytes. These two parsing words work when called by compiled helpers.
- .PATH prints each nonempty component followed by a space, stopping at the first empty component as the reference does. This includes leading/interior empty components; it does not reinterpret them as the working directory.
- Updates assemble privately and commit once. Known full-cell type metadata follows copies; separator and | conversions notify partial-write damage. Allocation/metadata failures preserve the old owner/content. Borrowed $@ bytes expire on replacement/clear. Display snapshots input when output capture could grow the source owner, including self-capture via $EXEC.

Seven regressions in p05a_path_test.zig cover binary separators, Unicode/spaces, compiled parsing and source preservation, empty components, self-append, heap/metadata failure atomicity, full-stack CLEAR-PATH, self-captured display, repeated append/restore, prefix classification and safe empty spans. Normal/minimal tests and normal build pass. scripts/verify-p05a-path.py passes37 Gforth comparisons; report .work/p05a-path-check/comparison.json and logs .zig-cache/p05a-path-{test,minimal,build}.log. No GPL implementation code was copied.

659 is complete (auto), committed/pushed as3af3c9f. Task660 completion follows below.

## Path lookup (660, 2026-11-14, 9d57d8e pushed)

The user approved Gforth-style ordered search and expansion, borrowed results, and separate INCLUDE/REQUIRE integration. OPEN-PATH-FILE ( addr u path -- fid addr2 u2 0 | ior ) opens the first successful candidate read-only. On failure it returns only the last open ior; an empty path or initial empty component returns -37. Empty interior components stop search. Names classified by ABSOLUTE-FILE? bypass the list without dereferencing the path owner. FILE>PATH ( addr u path -- addr2 u2 ) opens and closes the file, throwing open/close errors. No failing operation follows a successful open that could lose its handle.

Leading ./ is expanded using the current physical source file's directory, or the current working directory for terminal/EVALUATE contexts. ~+/ selects the working directory. Other relative names follow path order, including ../ and embedded slashes. Lexical normalization removes repeated slashes, ./ components and cancellable x/../ components without realpath or symlink resolution; leading ../ and /../ are retained, as are terminal x/. and x/.. spellings in the designated Gforth. Existing INCLUDE/REQUIRE behavior is unchanged (661).

The returned spelling retains ~. Opening expands ~/ through HOME; Windows falls back to HOMEDRIVE+HOMEPATH, TEMP and TMP when unset. The native host follows the designated Gforth's writable-home selection; hosts without a home callback use the available environment value. Missing current-home values expand to an empty prefix. Named ~user uses optional FileOps.user_home; the native POSIX host uses getpwnam, while unknown/unsupported users retain their literal spelling. Native Windows/Linux verification remains662 under607. The designated Gforth leaks an extra stack cell for bare ~+; Sigma retains the documented single-ior failure stack instead. The script records this one intentional difference separately. No GPL implementation code was copied.

Resolved and expanded candidates are limited to1,024 bytes. Longer names raise StringTooLong before that candidate is opened; embedded NUL returns an invalid-argument ior without opening a truncated name. Inputs and successful-output stack room are checked before host I/O. Each candidate checks the VM work budget. Borrowed returned bytes occupy the previously unused system string buffers at0x3000..0x3400; they are valid until the next path lookup (also invalid across image restoration/reset). Copy them if longer retention is needed; do not FREE them. Lookup has no heap allocation or persistent typed owner, and does not alter descriptors or input strings. This avoids additional fixed image roots. Failure may leave the old scratch bytes, but callers must not rely on their lifetime after another lookup.

Eight regressions in p05a_search_test.zig cover read-only order and returned spelling, empty-component termination/last ior, native versus returned tilde names, close-error cleanup, stack/range/length preflight, result aliases and image restoration, embedded-NUL rejection, and lookup with no free heap/no extra image root. Normal/minimal zig build test and normal zig build pass. scripts/verify-p05a-search.py passes42 designated-Gforth comparisons covering Unicode/spaces, order, bypass, source-relative paths, home/named-home expansion and lexical compaction, including EVALUATE inside a file. Report: .work/p05a-search-check/comparison.json; logs: .zig-cache/p05a-search-{test,minimal,build}.log.

660/656/565 are complete with progress auto. P05a is16/16. Next planned word group is P05b566 (directory/time); P05/542 remain incomplete. Changes for660 were committed/pushed as9d57d8e. No release package, version change or native Windows/Linux check was performed.

## Path splitting (P05b663, 2026-11-14, b9e5099 pushed)

BASENAME ( addr u -- addr2 u2 ) borrows the suffix after the last /; DIRNAME ( addr u -- addr u2 ) borrows the prefix including that /. No slash gives an empty directory prefix. A trailing slash gives an empty basename. Backslash, drive syntax, dot/dot-dot, NUL and Unicode bytes receive no special treatment. This is the designated Gforth's byte-oriented splitting, not POSIX basename/dirname normalization or OS path canonicalization.

Both words validate depth and the complete input range before replacing the two operands in place. Empty input at the memory endpoint is valid. They allocate nothing, preserve source bytes and need no extra stack room. Borrowed bytes have the lifetime of the caller's original source. Builtin tags/startup entries are appended and the files feature group owns both words. HELP and both user manuals are updated. No GPL implementation code was copied.

Three regressions in p05b_path_parts_test.zig cover exact addresses/lengths and unchanged binary/Unicode input, invalid depth/ranges with preserved operands, full-stack operation and compiled calls with no free heap. Normal/minimal tests and normal build pass. scripts/verify-p05b-path-parts.py passes108 Gforth comparisons of text, length, address displacement and final stack balance. Report: .work/p05b-path-parts-check/comparison.json; logs: .zig-cache/p05b-path-parts-{test,minimal,build}.log.

At663 completion,566 had2/14 words. Task664 investigation and completion follow below. The seven directory words are665; four time words are666. Windows/Linux native checks remain outside this session under607. Task663 was committed/pushed as b9e5099. No version bump or release package was made.

## Filename matching investigation (664, before implementation)

The designated Gforth calls libc fnmatch with flags0 and initializes its locale from the environment. Forty probes (20 cases in each of C and en_US.UTF-8) are recorded in .work/p05b-filename-match-check/initial-probes.json. Both locales match / and leading . through wildcards, distinguish case, support bracket ranges, !/^ negation, POSIX named classes and backslash escaping. A trailing backslash does not match. Empty text matches * but not ?.

Unicode behavior differs: Japanese text matches nine question marks in C, three in UTF-8; é matches two question marks in C, one in UTF-8. The alpha class matches é only in the UTF-8 probe. Native fnmatch is therefore not an OS-independent character policy. The bundled Gforth fallback is GPL; it must not be copied into Sigma's implementation.

Before implementation, the native locale-dependent behavior and a portable documented policy were presented to the user. The recommendation presented is a common UTF-8 codepoint matcher across OSes, with ASCII POSIX named classes, case-sensitive literal matching, slash/dot matching through wildcards, bracket/range/negation/escape support, invalid UTF-8 treated one byte at a time, and embedded NUL rejected. Unicode classes and locale collation would be documented differences. The user approved proceeding with this recommendation. Implementation and validation follow below. Progress remains auto; Windows/Linux native execution remains outside this session.

## Portable filename matching (664, 2026-11-14, uncommitted)

FILENAME-MATCH ( name u pattern u2 -- flag ) performs case-sensitive filename globbing without host calls, heap allocation or locale changes. The user approved the portable UTF-8 policy after the investigation above. * matches zero or more codepoints and ? matches one; both include slash and a leading dot. Valid UTF-8 is decoded into codepoints, with no normalization, case folding or grapheme clustering. Each invalid byte is a distinct single unit, separate from all valid Unicode values. Backslash escapes the next codepoint, including bracket and wildcard characters. A terminal backslash never matches.

Bracket expressions support literal members, inclusive codepoint ranges, leading !/^ negation, a literal initial ], and leading/trailing or escaped hyphen. The twelve POSIX named classes (alnum, alpha, blank, cntrl, digit, graph, lower, print, punct, space, upper, xdigit) have ASCII definitions. Unknown classes and unsupported locale collating/equivalence constructs make that bracket fail; malformed/unclosed brackets do not match. Escape [ to match it literally. A named class cannot serve as a range endpoint. Embedded NUL in either argument raises the invalid-argument ior instead of silently truncating a C string.

Core implementation is filename_match.zig through the files feature group. Builtin tags/startup entries are appended. Input depth and both memory spans are validated before mutation. Errors/work-budget exhaustion preserve the four operands; the result replaces them only on success. Iterative star checkpoints avoid recursion and exponential branching. Repeated suffix comparisons can be quadratic, and native loops/bracket traversal check the existing work budget. A disabled debug/step-limit build retains its existing unlimited-execution policy. There is no fixed name-length cap beyond valid VM memory and no new image owner/root. No GPL implementation code was copied.

Five regressions in p05b_filename_match_test.zig cover wildcard/backtracking/bracket syntax, valid and invalid UTF-8, all twelve classes, malformed/NUL/range/stack checks with unchanged operands, full-stack empty spans, compiled execution without host hooks/free heap, and work-budget termination. Normal/minimal zig build test and normal zig build pass. scripts/verify-p05b-filename-match.py passes3,325 designated-Gforth comparisons under LC_CTYPE=en_US.UTF-8 and LC_COLLATE=C, plus verifies five intentional policy differences: C-locale character counting (two cases), Unicode alpha/print class membership (two), and native locale collation of A in [a-c] (one). The separate initial40 probes and malformed-bracket probes are retained. Report: .work/p05b-filename-match-check/comparison.json; logs: .zig-cache/p05b-filename-match-{test,minimal,build}.log.

664 is complete(auto), uncommitted. P05b566 is3/14 words and remains incomplete; next is665 directory operations7, then666 time4. Native Windows/Linux verification is667 under607 and was not performed here. P05/542 remain incomplete. No commit/push, version bump or release package was made for664.
