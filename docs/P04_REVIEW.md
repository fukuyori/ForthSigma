# P04 review

P04の33語は6a9c4e3までコミット・プッシュ済み。Claude Codeレビューの指摘を修正し、再レビューで対応必須の不具合がないことを確認しました。tque 636は完了（進捗auto）です。

Claude Code Sonnet is reviewing the final P04 implementation with Read/Grep/Glob only. Execution, modifications, Git operations, external access and delegation are disabled. Codex performs reproduction, fixes and validation. Raw reports are kept under `.work/p04-review/` and are not tracked. The initial report found B1/B2, L1/L4 and hardening/documentation points; no P0/P1 finding. The follow-up accepted the fixes and found no blocking correctness defect in supported programs. Raw reports: initial-sonnet.txt and followup-sonnet.txt.

## Confirmed during Codex boundary checks

APPEND's registry-capacity preflight used the old destination address before RESIZE. With an eight-byte first allocation, a registered adjacent allocation and a full registry, a registered source cell could appear to overwrite the neighbour's existing registration. RESIZE then had to move the first allocation, and the actual copy needed a new registration. The later capacity failure left the old first allocation freed while the input operands still held it.

`address_registry.preflightAppend` now models retained first-block keys in a disjoint virtual range, including retained self-aliases and registrations removed by shrinking. This prevents occupied neighbours from supplying false destination capacity. The virtual range is used only for metadata simulation, never for memory accesses. Actual allocation and copy behavior is unchanged.

Two regressions in `p04_review_test.zig` verify preservation of the original allocation/operands on the neighbouring-block failure and reuse of metadata capacity released by shrinking. The first test failed on the reviewed implementation and passes with the fix.

## Claude Code findings and resolutions

| Finding | Resolution |
|---|---|
| B1: +TO changes length/content before metadata exhaustion | Reproduced: `kept` became `kept` followed by eight NUL bytes. Reserve the owner and preflight both post-resize copies in insertString before changing length, ownership or bytes. The shared virtual-range model handles relocation, self-aliases and compound shifts. |
| B2: geometric capture allocation can fail when the exact result fits | Reproduced with a 64-byte remaining heap and a three-byte result. Retry the exact required allocation after speculative growth fails, and shrink the final buffer before TMP promotion. |
| L1: a source overlapping HERE's new owner is zeroed | Reproduced with twelve input bytes at HERE. Snapshot overlapping source before creating the owner cell. |
| L2: failed-buffer errdefer spans the commit | Scope allocation/copy cleanup to the preparation transaction. Reject owners overlapping their old/new allocation (a self-owned owner otherwise disappears when freed). Commit uses a checked logical cell and pre-reserved metadata with no fallible operation. |
| L4: macro lint folds case | Use byte-exact comparison for the fixed macro namespace while retaining ordinary case-insensitive lint. Regression distinguishes Case/case and still reports a repeated Case. |
| HELP/manual/status drift | Describe constants and comparison words individually; update REPLACES/SUBSTITUTE tables and reserved former-list comment, and record pushed P04 status. |

Eight regressions in `p04_review_test.zig` plus one lint regression cover these fixes. The follow-up requested additional same-string/full-registry and in-place/full-registry boundary coverage; both tests are included. B1/B2/L1/L4 each failed before the relevant fix. The Codex APPEND regression also failed before its fix. Logs: `.zig-cache/p04-review-reproduce.log`, `.zig-cache/p04-review-{test,minimal,build}.log`.

L3 and Q1–Q3 concern invalid callbacks or raw-memory ownership limits rather than changes to the specified API. Callbacks must preserve the caller's existing stack cells and output-buffer lifetime. Runtime validation checks depth and returned ranges, not isolation of arbitrary Forth code. Percent-containing names are legal dictionary names but cannot be reached by delimiter syntax. Raw owner aliasing can be created by ! at runtime; image validation checks explicit pointer structure and length bounds, not unique ownership. These limits are now explicit in both manuals; no new pointer inference or restrictive image ownership model is introduced.

Validation: normal/minimal test suites and normal build pass. Designated-Gforth comparisons pass 48 editing, 27 string-value and 50 macro cases. The two added macro comparisons cover delimiter-containing names and a 300-byte unknown macro name. Reports: `.work/p04-review/`. CLI save, repeated append/load and callback output capture also pass (`cli.json`). Earlier P04 coverage remains recorded in P04_IMPLEMENTATION.md.

Windows/Linux native verification remains outside this session in task607. No version or package changes were made. Review fixes are recorded in the same commit as this report; use git log for the commit id. Task636 is complete (auto). Non-blocking observations about invalid self-owned raw-memory structures and conservative detached-copy capacity are documented; the supported-owner preflight paths retain their proven no-failure-after-resize invariant.
