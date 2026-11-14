# P06 implementation and validation

P06a567 covers five words. Task684 implements >STRING-EXECUTE; task685 retains INFILE-ID/OUTFILE-ID and their EXECUTE wrappers. P06a/P06 remain incomplete. Progress uses tque auto. P05 review fixes were committed/pushed as734e6d0 before this work.

## Owned output capture (684)

`>STRING-EXECUTE ( xt -- addr u )` executes the callback once, captures its normal interpreter output and transfers an independent raw VM-heap allocation to the caller. The caller must `FREE addr`; empty output also returns a valid allocation. Callback stack results remain below addr/u. No temporary-string owner or persistent root is created. This word belongs to the ordinary strings group and remains available with files/float/graphics/audio disabled.

The implementation reuses the existing private Captured sink. It saves/restores target, sink and failure state through normal return and exceptions, so nested captures and $TMP/$EXEC composition retain their enclosing destinations. THROW propagates after freeing private output. Failed capture allocation becomes the existing out-of-memory THROW; callback side effects are not rolled back. Input token validation and one extra data-stack slot are checked before execution; after execution, two return slots must remain. Callback result overflow also frees captured output. Callback code must preserve the underlying caller stacks and private resource lifetimes, as for existing capture APIs.

After successful capture the length-prefix scratch layout is compacted into a raw FREE-able block and shrunk. Growth, exact-size fallback and cleanup use the existing Captured/heap implementation. Builtin enum tag is appended; startup entry is inserted before the existing final three-backslash entry. Earlier builtin-table images remain outside the strict image ABI contract.

Five regressions in p06a_capture_test.zig cover owned/empty output, nesting and TMP composition, THROW cleanup/restoration, invalid token/full-stack preflight, allocation failure and callback result overflow. scripts/verify-p06a-capture.py compares six ordinary/empty/UTF-8/nested/formatted/multiline cases with designated Gforth; all return balanced stacks and free their result. Report: .work/p06a-capture-check/comparison.json. Logs: .zig-cache/p06a-capture-{test,minimal,build}.log. Initial test-helper naming collided with the existing FILL word and was corrected before final validation.

No Windows/Linux native verification, version bump or packaging. This capture chunk remains uncommitted; only the preceding P05 review changes were committed/pushed in this turn.

Final validation: normal and minimal zig build test (including freestanding checks), normal zig build and six Gforth comparisons pass. Task684 is complete(auto); task685 is next and567/549/542 remain incomplete.

## Borrowed output-file selection (686 under685)

`OUTFILE-ID ( -- fileid )` returns the selected output file, or STDOUT outside a redirection. `OUTFILE-EXECUTE ( xt fileid -- )` executes xt once with normal text/number output routed to the borrowed file. It neither closes nor flushes the file, including on THROW. The caller retains ownership; file position and bytes already written remain changed. Callback stack results remain. Nested scopes restore the previous file, output-error state and capture sink/target/failure state on every exit. An inner capture overrides file output, while an inner OUTFILE-EXECUTE overrides enclosing capture. OUTFILE-ID continues to describe the selected file during capture, matching the reference.

State.write remains nonthrowing for host/capture clients. A first file-write error stops further writes in the current output word and is raised at its Forth builtin boundary; compiled print-string operations check their boundary too. Thus callback CATCH can handle a failed EMIT/TYPE/compiled dot-quote before subsequent execution. Non-output primitive fast paths remain unchanged. File write errors are consumed before propagation and do not poison restored scopes. Explicit WRITE-FILE retains its explicit handle/ior API.

The two words use the files feature group. Output selection/error fields are runtime-only State fields, not serialized file resources. Entry validates operand depth, xt and the FileOps capability before changing scope or consuming operands. File validity/access is checked by the actual host write; a callback that writes nothing does not force a probe or seek.

Five regressions in p06a_output_test.zig cover nested IDs/destinations, borrowed handles, THROW with retained bytes/restoration, capture nesting in both directions, EMIT and compiled dot-quote write errors including callback-local CATCH, invalid token preservation, closed handles and ID stack overflow. scripts/verify-p06a-output.py passes eight designated-Gforth comparisons of stdout and both output files, covering normal/UTF-8/line output, nesting, THROW/inner CATCH and both owned/temporary capture composition. Report: .work/p06a-output-check/comparison.json. Logs: .zig-cache/p06a-output-{test,minimal,build}.log.

684 (>STRING-EXECUTE) was committed/pushed as4b68762. Output changes remain uncommitted. Input selection (687 under685) remains: KEY/XKEY/EKEY/readiness, ACCEPT/REFILL and numeric input need shared routing plus isolation of pending bytes/events. No input-routing change has been made in this output chunk. P06a is3/5 words;567/685/549/542 remain incomplete. Native Windows/Linux verification remains outside this session under607; no packages or version changes.

Final output-chunk validation: normal/minimal zig build test (including freestanding), normal build, output8 and capture6 Gforth comparisons all pass. Task686 is complete(auto).
