# P03 review

P03cは`98be4f8`でコミット・プッシュ済みです。Claude Codeの指摘を修正し、再レビューと最終確認で新たな具体的不具合がないことを確認しました。通常・全機能群無効構成のテスト、専用10回帰、指定Gforthとの1,742ケース比較が成功しています。修正分はa6ab243でコミット・push済み、tque 631は完了（auto）です。

P03c was committed and pushed as 98be4f8. Claude Code Sonnet reviewed the cumulative changes from 1c39b75 using Read/Grep/Glob only. Execution, modification, Git operations, external access and delegation were disabled. Codex performed reproduction, fixes and validation.

The initial review reported no P0/P1 findings, three P2 and ten P3 findings, plus documentation and follow-up checks. Raw reports are in .work/p03-review/ (not tracked). The second review raised minor index-rebuild, restore invalidation and documentation points. They were corrected. The final read-only review accepted N-1 through N-4 and reported no new concrete defect.

| Finding | Resolution |
|---|---|
| P2-1 registry capacity and temporary duplication | Keep the specified 2,048-entry limit and document array ownership costs. RESIZE transfers registrations without duplication. Check capacity before growing array elements; replace line contents only after a successful read. |
| P2-2 linear write notifications | Use linear notifications during frequent mutations; after 32 stable writes, build a sorted slot index for binary search. Heap classification still traverses blocks, like the existing allocator, but ordinary unregistered stores no longer scan every record. |
| P2-3 raw heap addresses | Keep explicit typing and heap compaction. Document that raw interpreted strings and ALLOCATE addresses do not survive SAVE/SAVESYS and may alias a different restored object. |
| P3-1 sizing fallback | Return RuntimeError!usize from encodedSize and propagate its original error. |
| P3-2 owner at HERE | Check full-cell persistent storage and reject unallocated dictionary owners before allocation. |
| P3-3 zero allocation | Allocate at least one cell, supporting explicit references, persistence and FREE. |
| P3-4 invalid explicit references | Retain the specified save-time rejection. A complete ! can repair a typed memory cell. |
| P3-5 raw MOVE into typed storage | Clarify that a complete overwrite retains an existing destination type like !; it does not infer a new source type. |
| P3-6 missing notifications | Notify every SUBSTITUTE write, including writes preceding errors, plus UNESCAPE and gamepad output. |
| P3-7 failed string ownership | Free failed copies; reserve owners before other registrations and roll back new reservations on error. Preflight TMP before releasing its prior value. |
| P3-8 restore state | Clear last_created_word. |
| P3-9 ABI signature | Include WordKind/OpKind/Builtin field names and actual tags. |
| P3-10 SAVE/LOAD asymmetry | Clarify that SAVE retains the reachable graph while LOAD preserves and validates all destination registrations. |

Stale HELP and image-format descriptions were corrected. Existing Tcl pre-save message disposal and unaligned append behavior are preserved. Windows/Linux checks remain in task 607, including thread-stack headroom for large local workspaces; they were not run here.

Validation: ten dedicated review regressions, normal/minimal zig build test and the normal build passed. The designated Gforth comparisons passed 1,376 + 288 + 18 + 60 cases. A 1,100-element string array, CLI typed saves and repeated appends, and preservation of existing SAVE/SAVESYS files on invalid-reference failure also passed.

A single identical CLI measurement with 1,000 registrations and 100,000 stores improved from about 0.50 to 0.03 seconds in the final version. A mixed workload with 1,000 registrations and 10,000 string replacements/stores improved from about 0.50 to 0.31 seconds. This is a reference measurement, not a general performance guarantee. Logs: .zig-cache/p03-review-*.log; reports and measurements: .work/p03-review/.

Fixes were committed and pushed as a6ab243. Task 631 is complete with auto progress. Final reports: followup-sonnet.txt and final-sonnet.txt under .work/p03-review/. No version or release package was changed.
