# P07 review

Claude Code Sonnet reviewed the current P07 implementation at `cae67e3`, then reviewed omitted areas and the fixes. Scope: the four assignment prework words plus P07a/b/c/d's40 new items. The initial pass inspected current code rather than diffing every commit since8177973. Access was restricted to Read/Grep/Glob, with no commands, edits, delegation or external resources. Codex reproduced issues and ran tests. Raw prompts/reports and native observations are in `.work/p07-review/` (not tracked). Task: tque699, progress auto.

## Findings and treatment

- **C1 (Medium/Low): runtime-opened quotations under CATCH.** `POSTPONE [:` followed by THROW bypassed the source interpreter's quotation cleanup. CATCH removed a dictionary entry but left quote_depth and frames pointing to it. The new regression failed with depth1 instead of0; a nested-open case failed with depth2. The native trigger could no longer complete a subsequent KEEP definition. CatchFrame now saves quote depth/current word; changed active quotation trees are discarded before ordinary exception restoration. Unchanged active quotations survive CATCH.
- **C1a (Low, re-review): closing the last quote before THROW.** The first fix covered opening but missed depth returning to0. A new regression with different inner/outer locals and an outer IF reproduced the incorrect compiler restoration. Changed quotation contexts now also abandon an unfinished restored parent, so inner locals and controls are not installed into it. The whole unfinished outer definition is removed, matching existing malformed-quotation policy. A completed top-level quotation is retained. Code after the caught failure is interpreted once the unfinished compiler is abandoned.
- **C2 (Low): file ownership/preflight.** An invalid id ran the callback before close failed; an enclosing INCLUDED source could be closed by EXECUTE-PARSING-FILE, breaking its next read. Both native triggers were reproduced. Preflight now rejects standard streams, current input/output redirects and all active include-stack handles with bad-file ior(-521), then validates an open id using a zero-byte read. Rejections do not consume arguments, run the callback or take ownership. A redirect regression also failed before its guard. Zero-byte reads retain position, EOF and pushback; the native and fake implementations already obey that contract. Read access and arbitrary other aliases remain the caller's responsibility: supply an exclusively owned readable ordinary file, not a pipe. Callback/close error priority is unchanged. Native close already validates integer ids and leaves standard streams open; the initial review's possible unsafe-host-close concern was not confirmed.
- **C3 (Low): missing helper names in SEE/step.** Unnamed assignment compiler and postponed string/bracket helpers produced empty or generic output. SEE and stepping now share descriptive POSTPONE names without creating searchable words. The combined SEE/step regression failed before the fix and passes after it. FORWARD's over-escaped HELP stack text was also corrected.
- **C4 (Low compatibility limitation): parser-only tokens inside `]]`.** Sigma cannot postpone parser-only syntax absent from its dictionary, including ['], [CHAR], CHAR, POSTPONE, local declarations, :NONAME, FORGET and REQUIRE-*. The documented standalone [ and ] and string forms are exceptions. Three local Gforth probes confirm ['], [CHAR] and POSTPONE succeed there. This review does not extend that parser: English/Japanese manuals, compatibility lists and implementation notes now state the limitation; a regression verifies the Sigma error/report cleanup. The prior broad “square-bracket operations” wording now specifically says standalone [ and ].
- **C5 (Low): missing coverage blocks for extended controls.** P07c controls did not trigger the existing coverage hook. startsBlock now includes the extended loop entries/endings, DONE and conditional-dup words. A regression failed before the fix and now verifies entered, skipped and conditional block counts through the actual .COVERAGE report.

The coverage follow-up also inspected compile-only gates, assignment/local paths, compilation-token words, postponed literal/local generation, image normalization and both append routes, lint and new-op display paths. It reported no additional memory-safety or state-corruption defect. Its extra test suggestions were coverage gaps, not demonstrated failures.

The final narrow static review accepted the fixes and reported no actionable findings. It inspected the supplied code/test diff; the review's test count says seven, while this change adds eight regressions. Runtime stepping and exact coverage counts were explicitly left to Codex's execution evidence below. This is not a claim of exhaustive verification of every host path.

## Validation

Eight regressions were added (P07b5, P07c1, P07d2); seven failed before their respective fixes. Evidence logs: `.zig-cache/p07-review-before.log`, `p07-review-closed-before.log`, `p07-review-redirect-before.log`, `p07-review-tools-before.log`.

Final normal tests, all-optional-groups-disabled minimal tests (including freestanding checks), and normal build pass. Logs: `.zig-cache/p07-review-all-{test,minimal,build}.log`. All P07 verifiers pass:

| Unit | Matching reference cases | Sigma policy/error checks | Native image checks | EOF checks |
| --- | ---: | ---: | ---: | ---: |
| Prework |51|12|2|0|
| P07a |57|13|2|0|
| P07b |70|6|2|2|
| P07c |149|13|2|2|
| P07d |50|4|2|0|

Five final native execution checks pass: runtime quote opening, quote closing before THROW, invalid file id without callback side effects, active INCLUDED ownership protection, and STDIN rejection. Reports: `.work/p07-review/native-{before,after,final}.json`; supplementary Gforth observations: `parser-only-gforth.json`. HELP FORWARD displays ordinary quoted name text.

These fixes add no dictionary entries, operation tags or wire ABI changes. No Windows/Linux native execution, package creation, version change or GPL implementation copying was performed. Platform verification remains under607. Task699 is complete; review fixes and documentation are included with P08a in the corresponding commit; see git history.
