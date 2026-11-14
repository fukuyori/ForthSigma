# P08 review

Claude Code Sonnet reviewed all29 P08 words at `4033ef1` (P08a23 and P08b6), followed by an omitted-path coverage pass and a re-review of the fixes. Tools were restricted to Read/Grep/Glob: no commands, edits, delegation, external-resource access or outside-repository reads. Codex reproduced issues and ran validation. Prompts/reports and native observations are in `.work/p08-review/` (not tracked). Review task: tque700, progress auto.

## Findings and treatment

- **C1 (Medium): a removed saved WRAP-XT action could be restored into a surviving DEFER.** The guard tracked the target word but not the entry action. A callback could FORGET that action while keeping the target, and cleanup wrote its stale/reusable id back. The new regression failed before the fix; native execution returned success with the stale id. Guards now track saved-action lifetime. Removing the action replaces the fallback with the uninitialized sentinel(-1); a surviving target receives that sentinel. Normal return then throws InvalidExecutionToken(-261), while callback errors retain priority. A malformed entry action is rejected before any mutation. Tests cover target reuse, saved-action reuse, nested independent saved actions and callback-error priority.
- **C2 (Low): NEXTNAME/NONAME leaked into lazy library loading.** Internal appendWord consumed the user's one-shot name, renaming the library vocabulary and losing the user's pending choice. The new regression and native REQUIRE-GRAPHICS trigger reproduced it. require now copies/clears/restores naming state around prerequisites and its own loading, on success and failure. Library-defined internal NEXTNAME uses remain isolated.
- **C3 (Low): MAP-VOCS could continue with a removed/reused callback id.** A range recheck alone would not catch same-id reuse. A deferred callback whose retained action replaced its DEFER caused three later invocations of an unrelated replacement action (native TIMES=297). MAP-VOCS now joins the existing live-word guard chain and checks immediately after every callback, including the final Macros callback. Normal return from an invalidated callback gives-261; an existing callback error is propagated. Guarded MAP/WRAP scopes share the64-level host nesting limit. The original preflight now keeps the xt until checks succeed, consistent with WRAP's preflight; CATCH still restores its saved stack depth.
- **C4 (Codex additional): IN/IN-WORDLIST could reinstall CURRENT from a replaced dictionary.** A full restore inside the parsed word returned to a defer that unconditionally wrote the old wid. The new regression failed (expected1, found4), and the final test also covers a wid number that is valid again but names another list. A private full-image generation changes only after successful preflight; one-shot cleanup restores old CURRENT only if the generation is unchanged. Successful full restore retains its new CURRENT; failed preflight restores the old one. This counter is runtime state, not serialized.
- **C5 (Codex additional): failed lazy loading left case/table bits for rolled-back wordlists.** The loader restored allocation count but not P08's masks. The regression failed with mask40 instead of8. Failure cleanup now restores both masks captured after prerequisites. A chain with one successful and one failing prerequisite verifies that the successful library and its table bits survive, the failed/outer libraries do not, the user name survives, and the resulting image encodes/restores successfully.
- **Harness observation:** both P08 verifiers now reject policy overrides whose names match no reference case. This addresses the coverage review's suggestion and prevents an override typo from silently dropping a check.

## Review coverage

The initial pass read both P08 test modules in full and inspected wordlist/name/value operations, mask validation/rebase, CATCH/name restoration and integration. The coverage follow-up inspected ADDR token selection, compiled dispatch, image normalization/restore planning, AVALUE registry/string-owner interactions, PRESERVE operation relocation and scripts. It found no additional actionable defect. It did not exhaustively trace unrelated builtin modules or every graphics/audio host path.

The fix re-review accepted all five fixes for the traced cases and reported no blocking findings. Its non-blocking coverage suggestions were addressed with nested saved-action, final Macros callback and prerequisite-chain tests. Claude ran no tests; runtime evidence below is Codex's work.

## Validation

Five new regressions failed before fixes in `.zig-cache/p08-review-all-before.log` (the first two also failed in `p08-review-before.log`). Eight final regressions in p08_review_test.zig pass, adding the nested/final-callback/prerequisite cases and stronger generation/error-priority checks.

Final normal/minimal tests (all optional groups disabled, including freestanding checks) and normal build pass. Logs: `.zig-cache/p08-review-final-{test,minimal,build}.log`. P08a passes163 reference comparisons,7 Sigma policy checks and2 native image checks; P08b passes54 comparisons,10 policy checks and2 native image checks. All P07 prework/a/b/c/d comparison, image and EOF verifiers also passed after the functional fixes. Both script policy-name assertions pass.

Three native before/after checks pass in `.work/p08-review/native-{before,after}.json`:

| Trigger | Before | After |
| --- | --- | --- |
| Removed saved action | Success, stale action id | -261, surviving DEFER uninitialized |
| Reused MAP callback | Success, replacement called3 times (297) | -261, replacement never called (0) |
| NEXTNAME before REQUIRE-GRAPHICS | Missing GRAPHICS name, stack error | GRAPHICS found; pending user definition returns7 |

These fixes add no dictionary entries, Word/Op fields or wire ABI changes. The P08 implementation's existing ABI boundary remains. Windows/Linux native tests remain deferred under607. No package/version change was made. Unrelated music examples, CHANGELOG and graphics/sound documentation changes are separate workspace work and were not included in the P08b commit or review fixes.

Task700 is complete. P08b was committed/pushed as4033ef1; review fixes and this record are included in the corresponding commit; see git history.
