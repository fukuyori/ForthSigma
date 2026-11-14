# P06 review

Claude Code Sonnet reviewed P06a/P06b/P06c (all29 words) at78f79ae, followed by reviews of the fixes and image/test coverage. Access was limited to Read/Grep/Glob: no execution, edits, external access or delegation. Codex reproduced the findings and ran validation. Raw reports and the PTY observation are in `.work/p06-review/` (not tracked). Review task: tque697, progress auto.

## Findings and treatment

- C1 (Low): OUTFILE-EXECUTE with STDOUT bypassed `output_count`, allowing a following terminal SHOW to overwrite intervening text. A new regression failed before the fix (expected54, found53). State.write now counts explicit STDOUT bytes, including failed writes that may emit a prefix. Captures and other files do not change the count. The test verifies actual SHOW output as well as counter and destination isolation.
- C2 (Low, initially speculative impact): pipe commands inherit the shared terminal state rather than receiving SH/SYSTEM's foreground handoff. A macOS PTY probe confirmed raw inherited stdin after KEY-IOR and restoration on exit. This is a terminal-sharing constraint, not evidence that a blanket `leave()` would safely coordinate a long-lived pipe. English/Japanese manuals now describe the inheritance and direct foreground interactive commands to SYSTEM/SH. No terminal-mode changes were added to pipe creation.
- C3 (Low, follow-up): children may write inherited stdout/stderr without updating the host's cursor tracker. Pipe open and completed pclose now invalidate that position, without changing terminal mode. A native regression failed at the first invalidation assertion before the fix; it also checks invalidation after the parent establishes a fresh row during the child's lifetime. The prompt/wrap symptom itself was not reproduced interactively.
- C4 (Low, pre-existing): explicit EMIT-FILE/WRITE-FILE/WRITE-LINE and SYSTEM already bypassed SHOW's output counter before P06. Possible PNG/STDERR variants require investigation. These broader existing paths are tracked separately under tque698 (auto), rather than included in the P06 redirect fix.

The follow-up accepted the STDOUT fix and found no issue in SH-GET cache invalidation on validated full restore, preservation by both append routes, typed system-key-name pointer relocation, CSV builtin VALUE validation/destination settings, or omitted-files slot behavior. No High or Medium finding was reported. Claude's review was static: the initial review omitted image code/tests; the follow-up read the key tests in full and skimmed the remaining P06 tests, and inspected restore/append code. Execution evidence below is Codex's validation, not Claude's.

## Validation

Before fixes: normal/minimal tests, normal build, all P06a/b comparison scripts, P06c74 reference comparisons and6 PTY checks passed. The two new targeted regressions then failed before their respective fixes.

Final validation and final narrow re-review are recorded below. No Windows/Linux native checks, version changes or package creation were performed. Platform checks remain under607 (695/696).

Final normal/minimal tests and normal build pass. Explicit-output comparisons8, pipe comparisons7 plus3 Sigma checks, SH-GET comparisons8 plus1 alias check, and P06c comparisons74 plus6 PTY checks pass. Earlier full P06a/b comparisons also passed: capture6, input8 plus3 intentional differences/3 pushback checks, CSV input19/output28 and SH8. Logs are `.zig-cache/p06-review-*.log`.

The final narrow static review accepted both fixes and reported no actionable findings; it checked the pipe regression and relied on the preceding follow-up for the output regression. It explicitly retained the separately tracked pre-existing output paths and the documented shared-terminal approximation during a live pipe's lifetime. P06 review task697 is complete. Fixes and this record are committed together; see git history for the resulting commit.
