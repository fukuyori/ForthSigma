# P06 implementation and validation

P06a567 covers five words. Task684 implements >STRING-EXECUTE; task685 retains INFILE-ID/OUTFILE-ID and their EXECUTE wrappers. P06a/P06 remain incomplete. Progress uses tque auto. P05 review fixes were committed/pushed as734e6d0 before this work.

## Owned output capture (684)

`>STRING-EXECUTE ( xt -- addr u )` executes the callback once, captures its normal interpreter output and transfers an independent raw VM-heap allocation to the caller. The caller must `FREE addr`; empty output also returns a valid allocation. Callback stack results remain below addr/u. No temporary-string owner or persistent root is created. This word belongs to the ordinary strings group and remains available with files/float/graphics/audio disabled.

The implementation reuses the existing private Captured sink. It saves/restores target, sink and failure state through normal return and exceptions, so nested captures and $TMP/$EXEC composition retain their enclosing destinations. THROW propagates after freeing private output. Failed capture allocation becomes the existing out-of-memory THROW; callback side effects are not rolled back. Input token validation and one extra data-stack slot are checked before execution; after execution, two return slots must remain. Callback result overflow also frees captured output. Callback code must preserve the underlying caller stacks and private resource lifetimes, as for existing capture APIs.

After successful capture the length-prefix scratch layout is compacted into a raw FREE-able block and shrunk. Growth, exact-size fallback and cleanup use the existing Captured/heap implementation. Builtin enum tag is appended; startup entry is inserted before the existing final three-backslash entry. Earlier builtin-table images remain outside the strict image ABI contract.

Five regressions in p06a_capture_test.zig cover owned/empty output, nesting and TMP composition, THROW cleanup/restoration, invalid token/full-stack preflight, allocation failure and callback result overflow. scripts/verify-p06a-capture.py compares six ordinary/empty/UTF-8/nested/formatted/multiline cases with designated Gforth; all return balanced stacks and free their result. Report: .work/p06a-capture-check/comparison.json. Logs: .zig-cache/p06a-capture-{test,minimal,build}.log. Initial test-helper naming collided with the existing FILL word and was corrected before final validation.

No Windows/Linux native verification, version bump or packaging. This capture chunk remains uncommitted; only the preceding P05 review changes were committed/pushed in this turn.

Final validation: normal and minimal zig build test (including freestanding checks), normal zig build and six Gforth comparisons pass. Task684 is complete(auto); task685 is next and567/549/542 remain incomplete.
