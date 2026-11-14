# P05 review

Claude Code Sonnet reviewed P05 at e38b694 with Read/Grep/Glob only: all30 original words plus FPATH integration. No commands, modifications, external access or delegation were allowed. Codex reproduced findings and performed fixes/tests. Raw reports are under .work/p05-review/ (not tracked). tque683 is complete with auto progress.

## Findings and treatment

- C1: LOCATE/WHERE reopened recorded ~/ names without home expansion. A regression failed before the fix. Both source-display opens now use paths.openedName on the stored spelling, retaining existing history keys and avoiding a second source-relative search. The regression covers FPATH with INCLUDED/REQUIRED, LOCATE, WHERE and file closure.
- C2: raw byte writes can corrupt the ordinary FPATH owner; CLEAR-PATH is not a memory-repair API. This is outside the existing dynamic-string ownership contract. Keep invalid-address/image damage checks; do not silently treat corrupted owners as empty or change all dynamic-string ownership semantics. Manuals now state this boundary.
- C3: removed obsolete manual statements that INCLUDE/REQUIRE cannot use path lookup; corrected implementation/commit status and builtin-order wording.
- Q1: retain the previously documented Gforth-compatible home selection and empty-home expansion policy. No new root fallback or distinct semantics for individual shared-helper consumers were introduced.
- Q2: stored relative source names remain dependent on process cwd after SET-DIR. A new configured source-relative/chdir comparison matches Gforth. No captured cwd, canonical identity or altered legacy REQUIRE cache policy was added.
- Q3: KEY?-FILE preserves ordinary bytes, while terminal Ctrl+C interrupts like EKEY?. The manual now makes this exception explicit; a readiness-interrupt PTY case supplements existing KEY-FILE interruption/restoration checks.
- Q4: Builtin enum tags are appended, but startup words are inserted before the final three-backslash entry, whose execution token can shift. Strict image ABI signature, builtin count and per-entry kind/tag validation reject incompatible earlier tables. The claim that all earlier execution-token numbers are preserved was corrected.

No Windows/Linux native checks were performed; they remain under607. No version/package changes. Review fixes are uncommitted.

Validation: normal/minimal zig build test and normal build pass. The new source-display regression failed before the fix; after adding an actual recorded use, both LOCATE and WHERE pass. Configured source lookup matches13 designated-Gforth cases. File input validation passes258 comparisons, the documented buffered-readiness correction,6 PTY cases (including readiness Ctrl+C and terminal restoration) and1 FIFO case. Logs: .zig-cache/p05-review-{reproduce,test,minimal,build}.log. Reports: .work/p05-review/input-comparison.json and .work/p05-include-path-check/comparison.json.


## Follow-up

The follow-up accepted C1 and the policy/documentation decisions, with no high-severity or data-corrupting supported-API defect. It found an additional low-severity regression: home-expansion errors escaped LOCATE/WHERE instead of suppressing unavailable source text. Both opens now catch expansion failures, with a regression for a missing home hook.

The follow-up's literal-tilde legacy-name case and changed HOME are documented source-display limits: no load-time home/cwd or resolution-mode metadata is stored. Source inspection expands tilde using the current provider, so a literal tilde directory loaded in legacy mode can display different source text. This limitation remains; source execution/history is unchanged. Cross-build image hardening beyond current enum/layout/count/kind checks is outside this review; earlier builtin tables remain unsupported.

The readiness-interrupt PTY test passed, and now includes1 MS per iteration to avoid a possible work-budget race on faster systems. Existing PTY cooked/raw timing observations were not reproduced. The258 comparison count excludes the Sigma-only AB buffered-readiness correction, recorded separately. Raw follow-up report: .work/p05-review/followup-sonnet.txt.

Final validation after expansion-error handling and the paced readiness loop: normal/minimal tests, normal build and input258 comparisons/PTY6/FIFO1 pass. Two new Zig regressions cover source reopening and unavailable expansion. No commit/push was performed in this continuation turn.
