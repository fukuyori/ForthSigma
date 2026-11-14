# P09 diagnostics and development support

## P09a — exceptions and assertions (15 words, tque576)

Implemented `)`, `?ERRNO-THROW`, `?IOR`, `ASSERT-LEVEL`, `ASSERT0(` through `ASSERT3(`, `CATCH-NOBT`, `EXCEPTION`, `EXCEPTIONS`, `FAST-THROW`, `NOTHROW`, `WARNING"`, and `WARNINGS`. P09b/c are also complete; P09 covers50/50 words.

### Reference and decisions

The designated Gforth1.0.1 build (c479e1eec66dd57a2441c3020177267ba70d3bdc) was measured before implementation using `scripts/probe-p09a.py`; no GPL implementation code was copied. Observations are in `.work/p09a-check/spec-probes.json`. `scripts/verify-p09a.py` checks55 matching behaviors,15 explicit Sigma policies, and2 native SAVE/LOAD-DICTIONARY/SAVESYS cases.

- ASSERT-LEVEL is initially1; the chosen level is tested when parsing/compiling each assertion. Level-1 disables all. Existing ASSERT( uses level1. Enabled bodies retain the existing512-byte, current-line limit; nested assertions are bounded to16. Quoted closing parentheses are supported. False assertions retain Sigma's source-place diagnostic and THROW-2. Unmatched `)` is-22 and missing close is-259. Existing interpreted ASSERT behavior is retained; new assertion words are omitted with-Ddebug=false, while legacy ASSERT( stays available.
- CATCH-NOBT restores the enclosing suppression state on normal return, caught errors, QUIT and step-limit escape. Compiled/deferred/synonym calls enter the existing VM loop. FAST-THROW skips capture, propagates through CATCH, and treats0 as a no-op; uncaught use is safely reported. NOTHROW clears pending backtrace information. Ordinary CATCH continues Sigma's existing behavior of clearing handled traces.
- ?IOR consults host errno only for-1; ?ERRNO-THROW does so for any nonzero flag. errno0 does nothing; positive C-int errno maps to-512-errno. No getter gives-21; invalid errno gives-24. The native host reads errno without clearing it. No platform-native Windows/Linux execution was performed.
- EXCEPTION copies up to4096 message bytes. EXCEPTIONS takes `( xt count -- first-code )`; the callback receives `first-code - thrown-code` and returns `( addr u )`. Zero count allocates nothing; negative counts give-24. Allocation starts at-4294967296 and descends for at most4096 codes, outside standard Sigma and C-int errno ranges. Codes are engine-specific; comparisons test relative allocation. Formatting failures fall back to the original numeric exception rather than replacing it.
- Records are anonymous dictionary entries, hidden from LATEST/LATESTXT, owned by dictionary lifetime. FORGET invalidates removed messages but never rewinds the counter. Full image restore restores records/settings; both append routes relocate message storage and group callback IDs, retain destination warning/assert settings, and merge counters monotonically. Overlapping code ranges reject append before mutation; codes embedded in raw constants cannot safely be guessed or renumbered. Malformed counters, headers, ranges and callback IDs are rejected. New builtins/WordKind change the image ABI; recreate earlier images.
- WARNINGS initially-1 (the measured Gforth build initializes it to-2). Zero disables warnings; other nonzero values enable them; -4 prints then throws Sigma-281 (Gforth-2054). WARNING" is immediate/compile-only, consumes a runtime flag, and writes literal text to stderr. Existing redefinition warnings retain stdout placement; warning-as-error rejects before replacing the old definition. No additional Gforth warning-category filtering is introduced.

### Validation

Nine Zig regressions cover compile-time/nested assertions, CATCH/FAST/suppression restoration including step-limit escape, errno triggers, warning/redefinition policy, copied/group messages, all three image routes, nonmutating collision rejection, malformed records, formatter failure and FORGET allocation lifetime. Normal tests pass (1013 passed,6 skipped); the minimal configuration passes (576 passed,414 skipped), including freestanding build checks. Normal build and both P08 verifiers pass (P08a163 matches/7 policies/2 native cases; P08b54/10/2). Verification logs and comparison output are under `.work/p09a-*` and `.work/p09a-check/`. No Windows/Linux native checks, package creation, version change or unrequested external review were performed.

## P09b — stack/source browsing and editor diagnostics (30 words, tque577)

All30 public words are implemented. Measurements precede implementation in `scripts/probe-p09b.py`; additional diagnostic probes are under `.work/p09b-check/diagnostics-extra.json` and `fancy-tty.json`. Gforth WHERE on this reference build timed out or faulted for several formats; those known-abnormal cases are not repeated. Their partial output, the public manual and Sigma's existing WHERE layout establish the presentation policy, rather than reproducing the failures.

### Stack and source browsing

- CLEARSTACK/FCLEARSTACK/CLEARSTACKS preserve independent return/call/loop/local state. MAXDEPTH-.S is a variable initially9 shared by .S/F.S; a negative limit throws-24 before output. F.S-PRECISION is a VALUE initially14, set with TO. Width1..4096 controls Sigma's established F.RDP field style;0/negative gives-24 and excessive width-18. Gforth's current smart float rendering differs; Sigma's existing F.S output is retained.
- BEFORE-LOCATE and AFTER-LOCATE are VALUEs initially3/12. LOCATE retains its old definition-only output while selecting a copied file name and definition line. XT-LOCATE does the same by xt. L shows context, N/B page forward/back, bounded at physical line1. A page has before+1+after lines, at most256; unsupported sizes give-24. This is deterministic, rather than reproducing Gforth's terminal-dependent window formatting. Long physical lines are skipped as one line; files are closed after each view. Embedded sources need no file callbacks. A reported include error selects its line. Full restore invalidates a cursor by dictionary generation; FORGET does not turn a copied file name into another table entry.
- WW selects a zero-based WHERE/BROWSE result; NW/BW move through a none state at either end and then wrap to the opposite end. They display immediately, as confirmed by BROWSE-based Gforth measurements. BROWSE uses Sigma MWORDS' case-sensitive substring, first search-list and oldest-first rules; unavailable source has an explicit numbered row. Snapshots exclude later uses/definitions, survive append, and invalidate on dictionary deletion/full restore. Negative WW indices give-24 without consuming them. Missing locations follow WARNINGS, including-281 at warning-as-error.
- SHORT-WHERE retains the recorded name on each row. EXPAND-WHERE qualifies relative names through the host cwd, expands existing tilde paths and keeps embedded names; it does not resolve symlinks. Missing cwd support gives a file error; malformed callback results are rejected. Drive-relative/root-relative Windows paths requiring unavailable per-drive cwd state are rejected. PREPEND-WHERE groups consecutive file rows under a recorded-name heading on stdout. Sigma retains its existing line/column formatting; it does not adopt Gforth's absolute stderr headings/alignment. Style0..2 is saved and validated, restored on full load and kept local on append.
- UNUSED-WORDS lists named entries in CURRENT, oldest first, with no recorded file uses. This CURRENT rule was confirmed separately from the search order. Terminal execution, indirect numeric xt use and uses lost in dictionary images are not inferred. A saturated use table gives-259 instead of false unused claims. Anonymous internal entries are omitted.
- `\G` is an immediate line comment. It stops at the next LF within EVALUATE as well as normal input, so following lines remain executable.

### Editor integration

EDIT selects a definition without printing it; G opens the selected line, or the first line of the last N/B window. Showing surrounding context with L does not move the editor's original target. The host receives a typed, synchronously borrowed file/text request. Native execution uses EDITOR with a `+line` argument; configure an editor that accepts this convention and a wait option for GUI clients. An unset/blank EDITOR gives-21; nonzero editor status gives a host error. There is no implicit vi launch.

GG/LL select editor/Forth output for the next result or trace selection; repeating the same command twice sets the default. One-shot choices are consumed by selection errors/missing results, and defaults reset on full restore. Direct LOCATE/L/G/EDIT and WHEREG do not consume that choice. Safe BROWSE-based probes confirm the corresponding Gforth mode behavior.

WHEREG captures expanded WHERE rows privately and restores the caller's capture and listing settings before invoking the editor. Its query remains available to WW. Embedded sources and WHEREG open temporary inspection copies; edits to those copies are not imported into the VM. The native host exclusively creates temporary files (POSIX0600), waits for the configured command and removes them on success and failure. It shares SYSTEM's terminal handoff. Source paths are separately quoted from the trusted EDITOR command prefix; Windows cmd filenames containing quote, percent, exclamation or line terminators are rejected rather than reinterpreted. A dictionary-generation guard prevents freeing an old capture allocation after a host restores a new heap.

`verify-p09b-editor.py` uses a recording Python stand-in, not an interactive editor: Unicode/spaces/quotes, selected line, default/one-shot modes, private report contents/permissions, unset/failed editor, cleanup and SAVE/SAVESYS behavior are exercised. Windows/Linux native execution remains deferred.

### Exception and smart display

TT selects a zero-based saved VM exception frame; NT/BT move forward/back through a none state. This follows the observed source-selection role of these Gforth words, not a dump of the CPU return stack. Reporting an exception retains up to32 VM/inline-frame locations after the immediate backtrace is cleared. New VM traces replace the saved trace; browser/host errors without a new trace preserve it. NOTHROW, dictionary deletion and full restore invalidate it; FAST-THROW and suppressed traces are not retained. Gforth's caught-trace persistence is intentionally not introduced into Sigma CATCH. Trace selection participates in GG/LL and requires both debug and tools.

`...` is non-destructive: decimal cells have a # prefix regardless of BASE; bounded, valid UTF-8 string pairs in live VM heap blocks or compiled string literals are quoted, escaped and previewed to80 bytes without cutting UTF-8. Floats use Sigma's shortest compact representation. MAXDEPTH-.S limits both stacks. Ordinal Sigma xts cannot be distinguished from ordinary integers and remain numeric. FANCY-AFTER-L is a presentation compatibility hook with no extra output in Sigma's plain browser; plain/stdout-PTY reference probes observed the same lack of stack/cursor effects.

The new builtin entries change the dictionary ABI; recreate images from earlier commits. New transient cursor/query/editor/trace state is not serialized. Persistent settings occupy0x0d98..0x0db8; host function pointers are never saved.

## P09c — return-stack extensions (5 words, tque578)

F>R, FR>, FR@, R'@ and RPICK are implemented. `scripts/probe-p09c.py` measured all five words and normal/loop/CATCH/local/recursive combinations before implementation. `verify-p09c.py` compares21 reference cases, checks5 Sigma boundary policies and2 native image routes.

A float uses exactly one64-bit logical return cell, with bits preserved, including signed zero, infinity and NaN payloads. FR@ retains that cell; FR> consumes it. Integer/float returns deliberately share the untyped user return stack. VM calls, DO loops and locals have separate storage and are never exposed through RPICK. R'@ copies the second user item; RPICK0 is R@. Negative/oversized indices give-6 without consuming u; a missing u gives-4. New transfer words check destination capacity before consuming source values. Interpreted use follows Sigma's existing >R/R> model. The floating trio is omitted with-Dfloat=false; R'@ and RPICK remain. Builtin additions change the image ABI.

Regressions cover bit-exact values, nonmutating under/overflow, mixed stacks, CATCH restoration, loops, recursion, locals and full restore/both append paths. No native return addresses are read, saved or exposed.


## Final validation (P09 complete)

All50 P09 words are implemented; tque577,578 and parent552 are complete with automatic progress. On macOS, `zig build test` passed1053 tests (6 skipped), `-Ddebug=false` passed993 (66 skipped), `-Dfloat=false` passed988 (45 skipped), and the minimal configuration passed584 (446 skipped). The normal build and freestanding compilation also passed. Logs are `.work/p09-final-{test,nodebug,nofloat,minimal,build}.log`.

P09a comparison passed55 reference cases and15 Sigma policies; P09b passed80 reference cases,6 basic policies, listing/search/navigation/diagnostic checks and11 native editor stand-in checks; P09c passed21 reference cases and5 boundary policies. Native image checks passed for each suite, including the editor paths. Evidence is in `.work/p09a-final-verify.log`, `.work/p09b-final-verify.log` and `.work/p09c-verify.log`. Windows/Linux native execution remains deferred; no interactive editor or Claude Code review is claimed.

Builtin initialization now preflights dictionary capacity at compile time. Both `-Dwords=1024` and2048 built and started with1011 builtin entries;1024 is sufficient for this revision. A formatting API probe also passed for the diagnostic used by the insufficient-capacity branch. No package or version change was made.


## P09 review follow-up (701)

The requested complete review and omitted-path pass are recorded in [P09_REVIEW.md](P09_REVIEW.md). Fixes preserve64-column block comment boundaries, reject negative ALLOT through live hidden exception records before mutation, register WHEREG cleanup before style changes, and preserve original diagnostic stacks/traces across lazy message formatting. Four new regressions cover these reproduced paths. Normal/minimal tests, build, P09a/b/c comparisons and native checks pass. Windows quoted EDITOR prefixes remain an explicitly unverified platform concern under702/607. No builtin or wire ABI change was added by the fixes.
