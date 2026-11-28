# 1057: Integrated acceptance plan for all of 613

[日本語](INTEGRATION_ACCEPTANCE_PLAN_1057.ja.md)

Date: 2026-11-26. Author: Roku. This is the stage-one plan, not an acceptance result. Scope: ForthSigma, Zig 0.17.1, Windows x86_64 as the starting platform, plus Linux and macOS. This stage does not implement fixtures/tools, build, measure performance or operate devices.

## 1. Scope and existing passes

Sources: [Overall plan](CORE_EXTENSION_PLAN.md), “進める順序”, stage E row 1057 and its concluding requirement to record decisions for 999/1001; [detailed design](CORE_EXTENSION_DETAILED_DESIGN.md), section 14. Completion of 1055, 1002, 1003, 1037, 1048, 999 and 1001 is supplied by the user. Attempts to run `tque show 1057` and `tque ls --root 613 --tree --all` failed because access to the storage lock was denied. Retry those read operations at execution time and check titles, hierarchy and dependencies. Do not change tque.

These references are existing evidence, not new runs. Prefer dated completion updates and user decisions over historical “incomplete” statements; preserve discrepancies with their sources.

| Record | Existing acceptance and source sections | New boundary for 1057 |
|---|---|---|
| R1 | [Common infrastructure](CORE_EXTENSION_IMPLEMENTATION.md), “2026-11-19：1065 Mac実機受け入れ”, “最終の検証結果” | Concurrent resources started by a saved application |
| R2 | [Terminal/events](CORE_EXTENSION_IMPLEMENTATION.md), “2026-11-19：637 ターミナル制御（1070〜1073）”, “2026-11-19：638 イベントキュー（1074〜1077）”; [I/O](ASYNC_IO_IMPLEMENTATION.md), “検証と再現”, “Mac実機受け入れ（1092/1096）”; [processes](PROCESS_MANAGEMENT_IMPLEMENTATION.md), “実行した確認”, “Mac実機受け入れ（1101）” | Input, I/O, task completion and paint waits inside one saved-app process |
| R3 | [Unicode](GRAPHEME_IMPLEMENTATION.md), “確認結果”, “Mac実機受け入れ（1111）”; [files](FILESYSTEM_IMPLEMENTATION.md), “確認結果”, “Mac実機受け入れ（1116）”; [execution control](EXECUTION_CONTROL_IMPLEMENTATION.md), “最終集計”, “Mac実機受け入れ（1122）” | Only the combined fixture's Japanese text, files and interrupt paths |
| R4 | [Saved applications](SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md), “実行結果”, “Mac実機受け入れ（1124）”; final paragraph of [1069 acceptance table](SAVED_APPLICATION_STARTUP_ACCEPTANCE.md), “1069での受け入れ表（設計レビュー後に固定）” | Later PCM, frame presentation and task resources explicitly deferred to 1057 |
| R5 | [PCM lifetime](PCM_HOST_LIFETIME_IMPLEMENTATION.md), “実行結果”; [public PCM implementation](PCM_PUBLIC_IMPLEMENTATION.md); [final audio decisions](AUDIO_TARGET_AUDIT.md), “最終採否（1140、2026-11-22、利用者の決定）” | PCM coexistence after saved startup and stopping on exit; no full chip-model retest |
| R6 | [Detailed design](CORE_EXTENSION_DETAILED_DESIGN.md), section 10.4, “受け入れの状況（2026-11-23更新）”; [Windows display](WINDOWS_DISPLAY_CONTRACT_VALIDATION.md), “実行方法と結果”; [Linux physical check](LINUX_DISPLAY_HOTPLUG_VALIDATION.md), “最終実機確認：完了”; [Windows final decision](WINDOWS_NATIVE_DISPLAY_VALIDATION.md), “1276・1037の完了判定” | Saved startup combined with tasks, PCM and I/O; do not repeat 1047 placement/hotplug checks |
| R7 | [Task acceptance summary](TASK_CONTROL_ACCEPTANCE_SUMMARY.md), sections 2 and 3a (pass on 2026-11-26, AC-01–29), section 5 user decisions | Startup, cancellation, exit and restoration through SAVESYS; no repeat of existing ACs or single-VM comparisons |

## 2. Acceptance conditions

18 conditions: startup 3, waiting/responsiveness 4, reclamation/restoration 4, configurations 2, documentation 2, decisions 2, evidence 1. Sources define contracts; R references identify existing passes. Proposed methods require later implementation and do not imply existing tool support.

Check all conditions against Windows, Linux and macOS. M identifiers refer to section 4. Documentation, decisions and evidence are shared static checks. For unavailable capabilities, require the documented rejection rather than implementation of that capability.

| ID / category | New integrated condition, source and existing evidence | Method and pass criteria | OS / configuration |
|---|---|---|---|
| IA-01 Startup | Start later resources from the saved entry. [Saved design](SAVED_APPLICATION_STARTUP_DESIGN.md), “起動順と終了（全体レビューを反映）”; R1/R4/R7 | Proposed separate-process saved executable: entry runs once; fresh input, PCM, window, Snapshot and task initialize after restore; no runtime IDs from the saving process | All three / M0 |
| IA-02 Startup | Combined fixture arguments and diagnostic bypass. Same design, “アプリ引数とホストオプション”; R3/R4 | Automatically compare empty, spaced, Japanese and `-e` fixture arguments. `--sigma --no-app --` must start no fixture resources. Do not rerun the generic argument suite | All three / M0, M9 |
| IA-03 Startup | Partial initialization failure cleanup. Same design, “起動順と終了（全体レビューを反映）”; [common rules](ASYNC_COMMON_RULES.md), section 6; R4/R5/R7 | Proposed fixture faults immediately after each acquisition: input, window, PCM, Snapshot/task, child/pipe. Reclaim acquired resources only, preserve failure status, and successfully start a fresh process afterward | All three / M0, M1, M2, M9 |
| IA-04 Waiting | Real input, I/O, completion, paint/close and deadlines in one saved app. [Detailed design](CORE_EXTENSION_DETAILED_DESIGN.md), section 11.3; R2/R7 AC-18/20 | Reuse providers from the mixed fixture. Assign sequence IDs and reconcile processed/pending/discarded counts with reasons. No input/completion monopoly; drain pipes; close releases waits. Separate sessions cannot establish this condition | All three / M0, M1, M2, M9, omitting absent providers |
| IA-05 Response | Requested and accepted generations after saved startup. [Detailed design](CORE_EXTENSION_DETAILED_DESIGN.md), section 11.2; R7 AC-25 | Reuse task-native-path/search rendering and logs. After repeated n and a/b requests, never adopt stale results; f worker failure retains the last valid image; next request succeeds. Automatic comparison plus MNL-01 | All three / M0 |
| IA-06 Response | Input/display response while supplying PCM. [Detailed design](CORE_EXTENSION_DETAILED_DESIGN.md), sections 8 and 9.4; R5/R7 AC-02 | Frozen measurement in section 8: input→paint completion within 33.34 ms, terminal writer drain within 50 ms; count per-frame request→completion exceeding 16,666,667 ns. Additional misses versus equivalent no-task baseline must be zero; PCM underrun delta zero. No physical-presentation claim. Separate numerical verdict from MNL-02 listening | All three / M0 |
| IA-07 Waiting | Progress without presentation capability. [Detailed design](CORE_EXTENSION_DETAILED_DESIGN.md), section 10.4, “能力の取得とエラー”; R6/R7 | Compare native/Tk/terminal separately with implemented capabilities. Unsupported frame waits must not report fabricated success. Deadline/input/cancellation alternatives must terminate without indefinite waiting. Never reuse native frame numbers for Tk | All three / M0 per backend, M1 |
| IA-08 Reclamation | Ownership after caught failure and cancellation. [Common rules](ASYNC_COMMON_RULES.md), sections 3/6; [detailed design](CORE_EXTENSION_DETAILED_DESIGN.md), section 12; R5/R7 AC-01/05/24 | Cancel running and waiting tasks; observe request, terminal state and reclamation separately. CATCH does not automatically free all app resources. Reclaim failed task, continue window/PCM, successfully resubmit. MNL-03 | All three / M0, M1, M2, M9 |
| IA-09 Reclamation | Common cleanup on return/BYE/QUIT/uncaught THROW. [Saved design](SAVED_APPLICATION_STARTUP_DESIGN.md), “起動順と終了（全体レビューを反映）”; R4/R7 AC-24 | Independent starts: return/BYE status 0, QUIT/uncaught THROW status 1. Adapt task-native-bye to PCM. Exit with audio/window/task/Snapshot/owned child/pipe live; reconcile lifetime and exit records. Record residual resources on failure. MNL-04/05 | All three / M0, M9 |
| IA-10 Restoration | Exclude runtime state from saved images. [Common rules](ASYNC_COMMON_RULES.md), section 7; [saved design](SAVED_APPLICATION_STARTUP_DESIGN.md), “保存・完全復元・追加読込み”; R4–R7 | After mixed-resource use, stop legally, save and start a new process. Preserve entry registration and persistent data; never revive old PCM/window/task/pipe/input queue; fresh acquisitions succeed | All three / M0, M9 |
| IA-11 Restoration | Distinguish full restore from dictionary append. [Detailed design](CORE_EXTENSION_DETAILED_DESIGN.md), section 12; [saved design](SAVED_APPLICATION_STARTUP_DESIGN.md), “保存・完全復元・追加読込み”; R4/R7 AC-22 | Proposed preflight/append checks before and after resource shutdown. Before implementation, freeze expected busy/stop behavior against current resource contracts, source and final designs. Rejection changes neither dictionary/APP registration nor active resources; full restore succeeds after stop; append preserves target registration without dispatch | All three / M0, M9 |
| IA-12 Configuration | Saved entry does not implicitly require excluded groups. [Common rules](ASYNC_COMMON_RULES.md), section 8; [saved design](SAVED_APPLICATION_STARTUP_DESIGN.md), “機能除外と予約引数”; R1/R4/R7 AC-26–28 | Proposed per-configuration saved apps: remaining resources in section 4 work together; excluded calls fail as documented. Do not transplant a full-feature image into a different ABI configuration | All three / M0–M9 |
| IA-13 Configuration | image/debug and related boundaries. [Task matrix](TASK_CONTROL_CONFIG_MATRIX.md), sections 2/5 and “AC-28：構成別の検査（1400）”; R7 | M9 cancels tasks without debug-only EXEC-LIMITED. M10 has no SAVESYS/APP words and generates no saved fixture. Reference existing image rejection/58-word checks rather than rerunning the generic matrix. M11 checks capabilities without X11 | All three / M9, M10; Linux / M11 |
| IA-14 Documentation | English/Japanese user contracts. [Overall plan](CORE_EXTENSION_PLAN.md), “項目ごとの着手条件と完了確認”; R1–R7 | Complete section 5 comparison: no differences in words, arguments, capabilities, interrupts, exit, restoration or exclusions. Structural checks alone do not establish semantic equivalence | Shared across OSes / all configurations |
| IA-15 Documentation | Separate plans, results and history. [Detailed design](CORE_EXTENSION_DETAILED_DESIGN.md), sections 14/15; R6/R7 | English/Japanese IA IDs, configurations, limits, procedures and unverified items agree. Later bilingual results distinguish tested revisions, recording revisions and raw logs; do not confuse old incomplete statements with new completion updates. check-docs.py and reference validation pass | Shared across OSes / all configurations |
| IA-16 Decision | Confirm final 999 decision in aggregate. [Overall plan](CORE_EXTENSION_PLAN.md), “進める順序”; [detailed design](CORE_EXTENSION_DETAILED_DESIGN.md), section 8; R5 | Eight targets, declared models, selected versions, measurement limits, deferred reasons and SNES exception in section 6 match user decision 1140. Do not use old progress values as current verdicts or remeasure | Shared across OSes / descriptions with/without audio |
| IA-17 Decision | Evidence for no native additions in 1001. [Emulator plan](EMULATOR_CORE_PLAN.md), “背景1画面の試作と測定（1001、2026-11-22）” | Section 6 agrees on input, seven-run medians, exclusion of SHOW, keeping Forth, unmeasured scope and reopening criteria. Do not add generic rendering helper implementation to this plan | Shared across OSes / descriptions with/without graphics |
| IA-18 Evidence | Aggregate all three OSes and native gaps. [Detailed design](CORE_EXTENSION_DETAILED_DESIGN.md), section 14; R7 sections 1–3a | Section 7 ledger classifies every applicable IA/OS/configuration as pass/fail/unverified/N/A with evidence, reason and next method. Separate cross-builds, WSL, substituted tests and human observations; exit 0 cannot fill evidence gaps | Shared across OSes / all configurations |

## 3. Proposed integrated fixture and tooling

Implemented in 1411: see [fixture and adapter tools](INTEGRATION_ACCEPTANCE_1057_TOOLS.md). The proposals below remain planning history, not execution results.

These are later implementation proposals. Separate definition loading from execution, register an entry colon with `APP-ENTRY!`, then `SAVESYS`. Existing `tests/task/task-native-path.fs`, `task-native-search.fs` and `task-native-bye.fs` execute at their ends; do not simply INCLUDE them and save. Later create a minimal fixture reusing their definitions. Prefer generation/frame display from `task-native-common.fs`, task/Snapshot handling from `task-console.fs`, and the worker in `task-path-worker.fs`.

Existing bye audio uses `VOICE-HOLD`, which is not PCM integration evidence. Connect PCM supply using the existing public PCM examples' format/API. Do not require integration of all eight chip models or emulator CPUs. Render path/search results and generations. Do not repeat R6 reference-image tests for clipping, coordinates, rotation and alpha; check only correct initial state after restoration.

Sequence: (1) save side-effect-free definitions and persistent data; (2) a fresh executable receives current arguments; (3) acquire input/terminal, window, PCM, Snapshot/task and owned child/pipe in stages; (4) process input/I/O/paint/task results through one process's composite wait; (5) replace requests, inject faults and cancel; (6) run return/BYE/QUIT/THROW separately; (7) use separate starts for full restore, append and resave. Limit file/Unicode use to Japanese fixture arguments and temporary filenames; exercise execution control only through cooperative interruption in supported configurations.

Do not invent Forth ledger APIs for restoration or cleanup. Inspect and use existing public words and host test hooks. Section 12 of the detailed design still contains proposals: gate IA-11 busy/stop expectations and resource limits against final implementation before implementation begins. Present any contract discrepancy, evidence and alternatives to Claude rather than inventing a new contract. Unstoppable workers, forced termination and default SIGINT are not successful normal cleanup; inherit R7 guarantees and limits.

| Existing tool | Reuse | Proposed 1057 adaptation / limitation |
|---|---|---|
| `tests/scripts/verify-saved-application.py`, `verify-saved-application-windows.py` | Owned temporary SAVESYS output, separate startup, status/argv assertions | Combined fixture and staged faults; per-configuration artifact manifest. Do not repeat all 1069 tests |
| `tests/scripts/manual-acceptance-tty.py` | Windows ConPTY/Job, POSIX PTY/supervisor, owned-process cleanup, terminal comparison, native baseline input replay | Currently sends fixtures to ordinary sigma; needs a saved-entry launch adapter. Existing `--cases native/mixed` does not establish saved-app support |
| `tests/scripts/run-acceptance.py`, `acceptance-probes.py`, `acceptance-fixtures.py` | `--plan`, SHA-256, confirmation reference, measurement/smoke separation, paint/baseline aggregation | Saved-startup runs must be separate from existing AC reruns. Paint imports logs rather than opening windows. Consider an adapter preserving required 1057 endpoints |
| `tests/scripts/verify-task-public-matrix.py`, `verify-feature-matrix.py`, `verify-extension-matrix.py` | Configuration definitions, exclusions and build provenance | Map C identifiers to section 4; reference passed generic matrices and run only saved-entry deltas |
| `tests/scripts/verify-async-io-read.py`, `verify-async-io-write.py`, `verify-async-io-stdin-spawn.py` | Pipe providers, sequence data, drain/EOF expectations | Connect providers to saved-app composite wait. Separate runs do not satisfy IA-04 |
| `tests/scripts/verify-windows-display-contract.py`, `verify-linux-display-contract.py`, `verify-macos-display-contract.py` | Backend selection, capabilities and initial dictionary-state observations | Adapt OS methods to saved startup without rerunning the display matrix. Reference physical hotplug evidence R6 |

Proposed evidence destination: a fresh run directory inside the repository. Preserve executable SHA-256, HEAD/dirty diff, Zig/Python versions, build command, groups, OS/CPU/terminal/display backend/audio route, fixture/tool hashes, argv, stdout/stderr, status, acquisition/terminal/reclamation records and human replies. Link replies to run ID and raw-result hash. Add no third-party code, ROMs or audio data; retain existing fixture license notices.

## 4. Representative group configurations

A=audio, G=graphics, E=extension. Exclude only the zero-valued options using `-D<name>=false`; files/image/debug otherwise retain defaults. Generate each saved application from its own configuration's executable. Native execution on all three OSes except Linux-only M11. Existing C00–C17 passes provide the foundation; do not repeat generic checks.

| Configuration | A/G/E and other exclusions | Existing C mapping | Saved-startup integration delta |
|---|---|---|---|
| M0 | 1/1/1 | C07 | All resources, all exits, restoration and response baseline/load pairs |
| M1 | 1/0/1 | C05 | PCM, terminal, tasks and I/O; no window/physical graphics keys/paint requirement |
| M2 | 0/1/1 | C03 | Input, window, tasks and I/O; do not acquire PCM |
| M3 | 1/1/0 | C06 | PCM/rendering internal waits and saved startup; no EXTENSION/task/TUI public words |
| M4 | 0/0/1 | C01 | Terminal, tasks and I/O, exit/restoration |
| M5 | 0/1/0 | C02 | Rendering/input saved startup, exit and internal waits; no public tasks |
| M6 | 1/0/0 | C04 | PCM-only startup, stop and restoration; no public tasks |
| M7 | 0/0/0 | C00 | Saved entry/persistent data without requiring later resources |
| M8 | 1/1/1, files=0 | C10 with debug restored to default | SAVESYS, window, PCM and tasks; no file words or file-dependent pipe tests |
| M9 | 1/1/1, files=0, debug=0 | C10 | M8 plus ordinary task cancellation/reclamation; no EXEC-LIMITED/trace. Compare with files-enabled M0 |
| M10 | 0/0/1, files=0, debug=0, float=0, image=0, x11=0 | C11 | Static image-exclusion boundary; saved fixture N/A. Reference C11 evidence for non-saved minimal startup and task operation |
| M11 | 0/1/1, debug=0, x11=0 | C16 | Linux saved startup and Tk/terminal capabilities; no X11-only requirements |

M3/M5/M6 use common internal clocks/wakeups without enabling E implicitly. M8/M9 retain image and therefore SAVESYS. Distinguish internal image restoration from public image words. Record N/A reasons for excluded branches; do not skip an entire fixture and call it a pass.

## 5. English/Japanese document comparison

| Document / source | Items to compare |
|---|---|
| `docs/USER_MANUAL.md` / `.ja.md` | APP-ENTRY, SAVESYS, `--sigma`/`--no-app`, arguments, TUI/I/O, PCM, rendering capabilities/completion versus presentation, TASK cancellation/waits/reclamation, save/restore and exclusions |
| `docs/COMPATIBILITY.md` / `.ja.md` | Groups, OS differences, unsupported values and debug/files/image prerequisites agree with the manuals |
| `docs/WORD_REFERENCE.md` / `.ja.md`, `src/core/help_text.zig` | Used words' spelling, stack effects, ior/THROW, ownership and lifetime, including existing words rather than only additions |
| This plan's language pair, `docs/TASK_CONTROL_ACCEPTANCE_SUMMARY.md` / `.ja.md` | IA IDs, configurations, numbers, pass boundaries, unverified scope and decisions dated 2026-11-26 |
| R1–R7, `CORE_EXTENSION_PLAN.md`, `CORE_EXTENSION_DETAILED_DESIGN.md`, saved design | Cite sections/dates of monolingual history so both result languages reference the same decisions; translating all history is outside scope |

`python scripts/check-docs.py` compares heading-level sequences, table-row counts and code fences in language pairs; checks added words against HELP/compatibility, CLI items, versions, all registered words/full word references and generated grapheme tables. It does not check heading translation, semantic equivalence, section-link existence, native acceptance or numerical correctness. Compare source/translated sections row by row and return to registrations/HELP/final designs for contracts. Record differences with document, section, English/Japanese quotations, evidence and decision; do not silently change contracts.

## 6. Finalizing 999 and 1001 decisions

For 999, use [AUDIO_TARGET_AUDIT.md](AUDIO_TARGET_AUDIT.md), “最終採否（1140、2026-11-22、利用者の決定）”, subsections 1 targets, 2 deferred variants and 3 native components. CHIP-8, ZX Spectrum, NES, Commodore 64, Apple II, Amiga and Atari ST retain their declared Forth models. SNES retains native `SNES-FRAMES` under exception 1188, alongside reference Forth. Add no common native component. It suffices to reconcile and carry into the aggregate result all eight models, model documents/measurement links, selected versions, heaviest workloads, OS/hardware, listening/stop/replay scope and deferred variants.

Respect the decision not to remeasure NES/SID/Paula/ST results obtained without stopping other applications. Preserve the distinction between mostly WSL Linux results and native Apple II results, SID Windows 1.03× being synthesis-only rather than whole-machine margin, and evidence that Forth-only SNES was insufficient. Variants are deferred because the corresponding CPU-side emulator does not yet need them, not because investigation found them unnecessary.

For 1001, use [EMULATOR_CORE_PLAN.md](EMULATOR_CORE_PLAN.md), “背景1画面の試作と測定（1001、2026-11-22）”, and the user decision in that section. Reconcile the Windows 256×240 background, two bitplanes, attribute-selected palettes, seven-run medians and exclusion of `SHOW` against [Windows measurements](measurements/2026-11-22-background-prototype-windows.json). Eight-pixel Forth decoding plus existing GFX-INDEXED transfers justified no new native helper in that scope. Do not confuse later Mac measurements with the Windows decision/environment. Sprites, priority composition and four-plus bitplanes were unmeasured; if needed, establish a machine-independent input contract and a separate task. Remeasurement/reopening is not a 1057 requirement.

## 7. Manual steps and unverified scope

Request one manual step per OS at a time, record the reply, then proceed. Every request identifies executable absolute path, OS/backend/audio route, command, target window, action, expected result and stop method. Each row is a request unit, not a batch; request MNL-01a/01b and 03a/03b separately too.

| Unit | Action and observation | IA |
|---|---|---|
| MNL-01a | Press n in the saved path fixture; visually reconcile requested/accepted generations and ensure no regression to stale results | IA-05 |
| MNL-01b | Switch a/b in the saved search fixture, then request f separately; visually confirm retention of the last valid image on failure. Switching and f are separate requests | IA-05 |
| MNL-02 | During saved-fixture PCM playback, press the specified key once; confirm the short known sound and screen response. Listening checks glitches; logs judge numerical timing | IA-06 |
| MNL-03a | After a wait-capable interval is announced, press Ctrl+C once in the target terminal; observe caught result, input/cursor recovery and designed audio stop/continuation | IA-08 |
| MNL-03b | After task cancellation, resubmit with the specified key; observe continuing screen/audio/input and a fresh result | IA-08 |
| MNL-04 | Press q once in the saved bye fixture; observe window disappearance and sound stopping separately from automatic process/thread evidence | IA-09 |
| MNL-05 | Close the separately started saved fixture's window; confirm close releases waiting and restores terminal input/display | IA-04/09 |

Proposed result ledger: IA × OS × configuration × backend, with pass/fail/unverified/N/A, run ID, tested/recording revisions, raw log/hash, devices, method, automated result, human reply, limitations and next procedure. Missing endpoints or owned-child exit evidence means unverified. Do not count unverified as passed; attach reason and the same procedure on an available device. N/A means a contractual exclusion, not missing hardware.

A cross-build proves no native execution; WSL/PulseAudio/RDPSink proves only that route; Xvfb proves automated reference pixels; substituted functions prove their substituted contract. Do not infer physical keys, listening, DPI/multimonitor behavior or actual presentation. R6 records the user's exclusion of real DwmFlush-unavailable environments from completion requirements: retain “unperformed” and do not demand it again. At this planning stage all new IA executions are unperformed; available Linux/macOS terminals, displays and audio routes remain unverified.

## 8. Timing conditions and plan freeze

IA-06 proposes measuring only the new saved-startup integration path. Reuse endpoints/baseline replay from [TASK_CONTROL_ACCEPTANCE_PLAN.md](TASK_CONTROL_ACCEPTANCE_PLAN.md), “1394：ネイティブ窓の描画と終了（本版で追加）” and “60Hz期限の判定の改訂（2026-11-26、利用者の決定 案1、tque 1405・1406）”. Do not repeat the existing 70-minute/OS workload suite or 4,100 cancellation trials.

Before measurement, freeze both plan languages, configurations, fixtures, tools, counts, input schedules, limits and exclusions in a SHA-256 manifest. The Japanese plan is authoritative; pass its exact byte hash as `--plan-sha256`. Store the English/manifest hashes in the run record, not self-referential hashes inside these files. Passing this file as `--plan` does not make the current runner select 1057 fixtures; the later adapter must validate actual-plan identity.

Claude performs formal measurement only after Lemon's explicit confirmation, recorded as `--confirmed`. This planning request is not measurement approval. Smoke is untimed preparation, never a passing timing sample. Proposed IA-06 counts: M0 on all three OSes, path/search each 1,200 frames, two independent load→baseline pairs. Replay load-side keys on matching frame numbers in the baseline; match rendering workload, PCM samples/supply, window size/backend, binary and configuration, stopping only task submissions. Retain both first frames in raw logs but exclude them from deadline statistics. Missing baselines/endpoints or unequal rendering/PCM workloads mean unverified; do not replace missing samples with successful ones.

Input starts at first host key acquisition; screen ends at corresponding backend paint completion; terminal ends at writer drain. Exclude OS input waiting, physical key actuation and panel illumination. Preserve each request/completion independently; do not reconstruct missing completions from later painted-through values. Record PCM underrun delta and accepted-frame counts. Apply 33.34/50 ms to maximum durations and retain raw values, violations and distributions. Baseline input endpoints establish schedule agreement only; response verdicts use the load run. Retain cumulative cadence misses diagnostically but do not judge acceptance by them.

Proposed adaptation of the existing 80% extension rule: if the maximum reaches 80% of its limit, or additional misses/underruns occur, add two independent pairs for that OS/fixture, retain original results and judge causes and all pairs together. Freeze the rule/counts after review and before measurement; do not select only favorable pairs. Investigate functional failure/missing evidence rather than treating it as grounds to keep measuring. Hang timeouts protect execution and are not response limits.

### Fixed conditions (1410, 2026-11-26)

These conditions supersede the proposals above; they are a measurement contract, not results. Counts and the 80% rule are fixed here. Claude freezes hashes in an external manifest after Lemon confirms; no plan hash is embedded here.

| Item | Fixed condition |
|---|---|
| Scope/count | M0 on three OSes; path/search each 1,200 frames, two independent load→baseline pairs. Each run starts a new process/PCM session; no state crosses pairs. Eight runs/OS before extensions |
| Comparison | Same binary, configuration, backend, window size, rendered content, PCM sample sequence and supply algorithm. Replay load keys at matching baseline frame numbers; disable only task submissions. Record accepted frames, supply timestamps, partial/zero writes and waits on both sides. Missing evidence or different supply algorithms means unverified |
| PCM format | PS-RATE=48,000 Hz from `tests/audio/pcm-synth.fs:6`; mono signed16 little-endian. Follow `tests/audio/pcm-synth-play.fs:6,18–36`: 512 frames/1,024 bytes per block, capacity 4,096 frames. Use identical PS-DEMO-SETUP samples and identical audible/silenced selection in each pair. MNL-02 is audible |
| Supply interval | Continuous capacity-driven supply as PS-SEND/PS-RUN, with no fixed sleep. Generate/write 512 frames and advance by accepted frames only. Retain unsent data after partial/zero writes; retry with PCM-WAIT need=1 and timeout=1,000 ms. Initial filling up to capacity is allowed. 512/48,000 seconds (about 10.667 ms) is consumption duration, not a fixed call period. The later adapter must keep supply waits from monopolizing input/paint processing |
| Underrun | Read PCM-UNDERRUNS immediately before/after the measurement interval on the same opened handle. Do not use the pre-attach-ack zero as the starting observation: establish actual consumption first. API-defined initial silence and intentional drain tails do not count. A continuous starvation episode counts once, not per callback/frame; starvation after resupply is a new episode. End before STOP/drain. Require delta=0 separately in each load and baseline run; do not cancel one against the other. Retain raw counters/accepted frames |
| Response/deadline | Load input→corresponding paint maximum ≤33.34 ms; input→writer drain maximum ≤50 ms. Count individual frame request→complete durations >16,666,667 ns separately in load/baseline. Additional misses=max(0,load misses−baseline misses)=0. Later completion cannot fill missing endpoints |
| 80% extension | For the affected OS/fixture, paint maximum ≥26.672 ms or writer maximum ≥40 ms, additional misses>0, or any run's underrun delta>0 triggers one extension of two independent pairs, four pairs total. Keep/judge all pairs including originals; extensions cannot erase a failure. Remaining threshold failures fail acceptance. Investigate functional failures/missing data; no favorable replacement runs or unlimited retries |
| Exclusions | Only each run's first frame is excluded from deadline aggregation, retained raw (1,199 deadline samples/run). All smoke is excluded. Do not retrospectively exclude underrun/response observations because they occur in the first frame. OS input wait, physical actuation and presentation are outside endpoints. Missing/mismatched data, functional failure and safety timeout remain unverified/failed evidence. Ordinary scheduling delays are not removable outliers |

Underrun sources: Stream.sample in `src/core/sound_stream.zig:74–106`, execute in `src/core/words_pcm.zig:74–80`, and “SPSCと再標本化” in `docs/PCM_STREAM_DESIGN.md`. Tests in `src/tests/pcm_stream_test.zig`: “PCM hold, held frame accounting, silence episodes and restart”, “PCM initial silence is not an underrun episode”, “PCM intentional drain suppresses only its empty tail”; tests in `src/tests/pcm_words_test.zig`: “PCM copied stereo input can be reused immediately and silent tails count once”, “PCM query before attach acknowledges no previous underrun count”. Reviewed, not rerun here.

## 9. Sequence and duration estimates

All subsequent work is proposed. Estimates are not measured in this stage and exclude user-response waits, OS handoffs, environment recovery and defect repair.

| Stage | Deliverable / exit condition | Duration |
|---|---|---|
| 1 Plan reconciliation, this stage | Bilingual plan, IA/sources, check-docs.py, diff/reference validation | Estimate: 1–2 hours |
| 2 Contract gate and Claude review | Freeze IA-11 current contracts, IA-06 counts/limits and configuration scope; separate review from decisions | Estimate: 1–2 hours |
| 3 Fixtures/adapters, after a separate implementation request | Separate saved definitions/entry, PCM/pipe, fault/restore modes and evidence; untimed smoke | Estimate: 4–8 hours |
| 4 Per-OS automated integration deltas | M0–M9 saved entry/exits/restoration; static M10 boundary; Linux M11; record failures/gaps | Estimate: 1–3 hours/OS including builds; revise after first trial |
| 5 Per-OS manual checks | Request section 7 steps individually and record responses | Estimate: 20–40 minutes/OS excluding response waits |
| 6 Timing after approval | Two fixtures × two pairs × load/baseline in section 8; no execution before approval | Theoretical frame allowance: 2×2×2×1,200/60=160 seconds/OS. Estimate including preparation/reconciliation: 20–40 minutes/OS; extension pairs extra |
| 7 Documentation/decisions/aggregation | IA-14–18, bilingual results, unverified scope/next procedures and overall verdict | Estimate: 2–4 hours |

Stages 2–7 total for three OSes: estimate approximately 12–27 hours plus waits, repairs and extensions. If native gaps remain, distinguish completion of this plan from completion of 1057 acceptance. Commits, tags, pushes and tque updates are outside this plan's work.

## 10. Questions for Claude and current validation

No reopening of 999/1001 decisions is needed. Three candidate review decisions follow; none is implemented in this stage.

| Issue | Alternatives | Recommendation and reason |
|---|---|---|
| Final restoration expectations | A: treat the initial busy proposal as final / B: reconcile resource-specific final design/implementation and R7, then freeze | B: section 12 remains a proposal; avoid falsely classifying a stop/rejection difference as a contract failure |
| Saved-startup response measurement | A: reference R7 only / B: section 8's small delta measurement / C: rerun all AC measurements | B: cover saved startup plus PCM without duplicating prior passes; freeze counts/80% rule after review |
| Configuration execution scope | A: M0 only / B: M0–M9 plus Linux M11 deltas and M10 boundary review / C: rerun all 18 existing configurations | B: cover eight independent group combinations and files/debug/image/X11 boundaries without generic matrix reruns |

Current validation covers `python scripts/check-docs.py`, `git diff --check`, referenced files/sections, bilingual IA/configuration/table alignment and LF. Execution results belong in the final report. This plan claims no new acceptance-test or native-device passes.

### User decisions (2026-11-26)

| Point | Decision |
|---|---|
| Configuration scope | B: run the M0-M9 and Linux M11 differences; check M10 statically at its boundary |
| Response measurement through the saved entry | B: the §8 difference measurement (M0 on three OSes, path/search 1,200 frames each, two independent load→baseline pairs, zero PCM underrun increase). Counts and the 80% rule are frozen at the pre-measurement review |
| Final restore expectations | B: before writing fixtures, compare each resource's final design and implementation with R7 and freeze the expectations; ask the user about any conflict, with evidence and options |

## 11. Contract gate results (1410)

2026-11-26, Roku. Read the specified ef8e481 plan through the working-tree English/Japanese plans and use the three final B decisions. This is static reconciliation of current source, final designs and existing tests, not new acceptance passes. D1–D5 remain decisions for Claude to confirm with Lemon with evidence/options. No fixture/tool implementation, measurement, Git mutation or tque update occurs here.

### Resource expectations for IA-10/IA-11

Every row assumes a valid ABI/layout/capacity/root, one restoration operation and no other busy cause. Post-stop success is conditional on validation, not a promise to accept corrupt images. Rejection preserves dictionary, APP registration and resource ownership without cancellation/closure/restart; natural completion observed by host.poll during task idle checks is not frozen. Successful full restore imports the image APP root; append preserves the target root including unset, without dispatch.

| Resource | Full restore/preflight while active | After explicit stop/release | Dictionary append | Excluded from saved images | Design, function/lines, existing tests |
|---|---|---|---|---|---|
| Input/terminal | No dedicated busy. Successful validation resets decoder/pending input/physical keys; sends no terminal settings. Do not require rejection | Success, empty input state; no image-driven terminal reapplication | Keep current input/terminal requests | Decoder, pending events, physical keys, OS modes/terminal requests/clocks | `EVENT_QUEUE_DESIGN.md`, “既存入力・復元との境界”; terminal save-boundary paragraph in `TERMINAL_CONTROL_DESIGN.md`. `image_restore.zig` restore:12, apply:33–39,112–115; `host_terminal.zig` Manager.set:61/finish:104. T1/T2; dedicated terminal restore test unverified |
| Window/images/pending paint | No blanket busy. Keep window, fit/smooth/keep-open, display list/host counts; release screen/image pool/clip. Pending paint: D1 | Success. Fresh State uses default window/list/runtime settings; restoring an existing State does not initialize the entire State | Keep target window/images/settings; do not create source OS window | Window, pixels/pool/clip, displays, host counters/settings. Dictionary IMAGE-* variables are saved | Detailed design §10.4 “状態の持ち主と辞書イメージ”. `image_restore.zig` apply:112–115; `words_graphics.zig` clearImage:587; `graphics_images.zig` releaseAll:329. T3/T4 |
| PCM | Nonzero current-State handle rejects before application: error.Thrown, throw_code=-528. STOP alone is insufficient while ownership remains | Success after successful PCM-CLOSE clears handle; explicit OPEN for new PCM | Keep target PCM ownership; no automatic restart | Live handle/ring/position/ack/underrun/native audio resources | `PCM_STREAM_DESIGN.md`, “所有と保存”. `image_restore.zig` restore:12–15/restoreFresh:20–23; `words_pcm.zig` execute:37. T5 |
| Snapshot/tasks | External Snapshot retention alone does not reject. Bound host rejects nonterminal/execution_ref/internal_refs/cleanup with error.Busy, not a numeric ior; keep admission/IDs and do not cancel. Core-call boundary: D4 | Idle validation permits success even with terminal records/idle worker. Success changes epoch: old Snapshot new admission returns StaleSnapshot; retained references survive until released | Invalidate old Snapshot new admission while retaining already-admitted versions; no task cancellation | Manager/versions/references, task IDs/queues/results/workers/WAIT registrations; distinct from explicitly captured dictionary data | `TASK_CONTROL_IMPL_1375.md`, “回収と復元”; detailed design §11.3; R7 AC-07/08/22. `host_task_reap.zig` restore:39–42; `task_reap.zig` requireRestoreIdle:52–58; `task_snapshot.zig` canSubmit:163/admit:169; `image_restore.zig` apply:34; `image_append.zig` apply:59–60. T6–T9 |
| Child/pipe | Restore path has no dedicated busy/stop. Host ProcessOps/FileOps survive, but final active-retention contract/direct tests remain D2 | Success subject to validation after child exit, drain, FREE/pipe close. Restore does not substitute for stopping children | Target host references survive this path; active guarantee remains D2 | Registry/settings/PID/Job, pipes/workers/unread and undelivered bytes | `PROCESS_MANAGEMENT_DESIGN.md`, save-boundary paragraph; opening of `ASYNC_IO_DESIGN.md`. `host_interface.zig` Writer.process_ops:192/file_ops:246; `image_restore.zig` apply:33–120; `image_append.zig` apply:59. No direct restore test; T10 tests dispatch only |
| Files/blocks | No dedicated busy. Preserve host file state and this process's runtime block buffer; no automatic close | Success after explicit close; no image-driven reopen | Preserve target host file state | OS fid/stream/position/workers/runtime block buffer; integer fids in dictionary cells may persist | Existing-file contract in `ASYNC_COMMON_RULES.md` §7 and detailed design §12 exception. `image_restore.zig` apply:59–63; `host_interface.zig` FileOps near:48/Writer.file_ops:246. T11/T12 |
| Execution control | No dedicated busy; apply does not assign State.execution. Confirm D3 before treating active-budget full restore as final | Success after active EXEC entry/scope ends. Fresh State does not inherit budget/owner/poll state | Retain active depth/remaining; no limit bypass | Budget stack/owner/poll counters, interrupt scopes/host references | Budget paragraph at `EXECUTION_CONTROL_DESIGN.md:74–75`. `forth.zig` execution:336; `image_restore.zig` apply:33–120; `execution_control.zig` run:58. T13 covers append/encoding only, not full restore |

Source paths in the table omit `src/core/`, except `host_*` and `forth.zig` under `src/`. Common encoding evidence: `src/core/image_encoder.zig` encode:24–70 (dictionary, selected memory and typed heap), `src/core/image_graph.zig` collect:20/collectForAppend:24. Ordinary handle-valued cells are not scrubbed. A later process can reuse their numbers; do not require every old integer to be invalid (common rules §7 and PCM/Process designs). APP source: `SAVED_APPLICATION_STARTUP_DESIGN.md`, “保存・完全復元・追加読込み”, T14.

### Reviewed test names and acceptance records

These test declarations exist; none was rerun here. General tests do not fill a missing direct test.

| ID | File under src/tests/ | Test name |
|---|---|---|
| T1 | event_queue_test.zig:162 | image restoration clears standard decoder state without serializing native events |
| T2 | physical_key_test.zig:124 | physical restore resets only after successful image preflight |
| T3 | graphics_test.zig:3369 | display support runtime state survives in-place restore but is absent in a new machine |
| T4 | graphics_test.zig:985 | restoring an image into a used machine drops its graphics image, and a failed restore keeps it |
| T5 | pcm_words_test.zig:227 | PCM full restore is busy before mutation while save and typed append retain ownership |
| T6 | task_snapshot_test.zig:135 | snapshot complete restore invalidates only after successful preflight |
| T7 | task_snapshot_test.zig:167 | snapshot typed and State append invalidate old versions |
| T8 | task_reap_test.zig:85 | restore busy is nonmutating and retained references block collection |
| T9 | task_reap_test.zig:170 | idle complete restore keeps host and worker open |
| T10 | process_test.zig:44 | process words dispatch arguments and retain stack on interruption or invalid memory |
| T11 | blocks_test.zig:137 | dictionary restore preserves this process's unsaved runtime block buffer |
| T12 | filesystem_test.zig:125 | filesystem compiled words survive image restore without OS resources |
| T13 | execution_control_test.zig:112 | runtime execution budgets survive image append and are not encoded |
| T14 | app_entry_test.zig:55 | app root roundtrip append policy and corrupt image fail before mutation |

Reconciled R7 `TASK_CONTROL_ACCEPTANCE_SUMMARY.md` §2 (three-OS passes for AC-07/08/22) and additional-measurement scope in §3a. Snapshot data/lifetime and busy/idle restore agree with T6–T9. The dated 2026-11-25 N2 update in §3 marks extra capacity measurement unnecessary because the accounting allocator enforces the bound. Do not reopen it based on the older proposal text remaining below. This gate adds no new capacity/timing/saved-startup passes. T8 includes terminal tasks retaining internal references: terminal state alone is insufficient for idle success.

### Discrepancies and questions for Claude to confirm

| ID | Discrepancy/evidence | Options | Recommendation, pending |
|---|---|---|---|
| D1 | Detailed design §12 initially proposes busy for pending display. Final §10.4/T3 succeed with host frames_shown=4/painted=3 while retaining window. T3's substitute does not establish native paint/restore race safety | A: retain final §10.4 window/image contract and later test real paint concurrency / B: newly design/implement pending-display busy | A: preserve final contract; do not turn initial proposal into blanket rejection |
| D2 | Common rules §7 leave child/reader restore retention/closure unresolved. Process image exclusion does not decide in-process restore. apply neither stops nor rejects; no direct active test | A: specify target host-resource retention and test it / B: active busy / C: automatically terminate/drain before restore | A: follows existing host ownership/file boundary. Do not freeze active IA-11 verdict until confirmed |
| D3 | EXEC design lines 74–75 require restore/append to preserve active limits. T13 covers append/encode only. apply retains execution but resets execution stack depths; active-entry full-restore safety is unproven | A: restrict full restore to after EXEC entry ends / B: guarantee active full restore, with dedicated tests/design changes as needed | A: avoid extending current guarantees. Active rejection value is unspecified; invent no new value |
| D4 | R7 AC-22 Busy comes from bound `host_task_reap.restore`. Core `dictionary_image.restoreImage:88`/restoreFreshImage:92 lack task checks and check PCM only. T9 and unbound test at task_reap_test:277 expose different boundaries | A: use bound host hook for IA-11 task preflight; exclude core direct calls from busy guarantee / B: add task guard to every restore path | A: test the actual host contract; add no fictional Forth restore word/numeric busy |
| D5 | Common rules §7 PCM/terminal unresolved text and §12 blanket-busy proposal predate final PCM ownership/save, terminal no-reapplication and §10.4 retention contracts. Reading IA-10 exclusion as closing every resource during in-process restore conflicts | A: prioritize resource-specific final contracts; retain old unresolved text as history / B: new uniform all-resource-stop contract | A: IA-10 prevents runtime resurrection in a new process; IA-11 checks resource-specific in-process behavior |

### Established scope and remaining verification

Established scope is the table's supported contracts and §8 measurement conditions. Claude must confirm D1–D5 with Lemon and record answers before freezing fixture prerequisites. Active child/pipe restore, active EXEC full restore, real native paint concurrency and integrated simultaneous observations of dictionary/APP/all live resources on rejection remain unperformed. Naming existing tests is not passing evidence for those cases. Host error.Busy has no numeric ior conversion in this API; no new public Forth rejection value is established. Three-OS saved-startup measurements, physical observations and plan-hash freeze are also unperformed.

### User decisions on D1-D5 (2026-11-26)

| ID | Decision |
|---|---|
| D1 | A: the final §10.4 contract (keep the window, release the image) is the expectation. The race with real native painting is checked in the 1057 integration tests |
| D2 | A: document that child processes and pipes stay as the target's host resources across a restore, and add a dedicated test |
| D3 | A: complete restore only after the EXEC entry has ended. No new rejection value is invented for a restore inside the entry |
| D4 | A: IA-11 checks task Busy through the bound-host path. Calling the core functions directly is recorded as outside the Busy guarantee. When writing fixtures, confirm that the public words go through the bound-host path |
| D5 | A: each resource's final contract takes precedence; the older undecided table and the blanket-busy proposal are history. IA-10 is judged as no runtime resource reviving in a separate process, IA-11 by the per-resource expectation table |
### User decision on how to check IA-11 (2026-11-26, found in 1411)

No public entry fully restores an active target after a saved application has acquired resources (the bound-host complete restore runs only at saved-application startup; `LOAD-DICTIONARY` restores into a temporary VM and appends). Decision B: the saved application checks the paths users can reach (restore at startup, `LOAD-DICTIONARY` while holding resources). Complete restore of an active target is checked by one added Zig test that holds PCM, a task and a window at the same time. No test entry is added to the product.