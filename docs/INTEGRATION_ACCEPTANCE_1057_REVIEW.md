# 1057: Document and decision reconciliation (1415)

[日本語](INTEGRATION_ACCEPTANCE_1057_REVIEW.ja.md)

2026-11-26, Roku. Recording base: `99afe6d`. Static review only; no execution, remeasurement or decision change. IA-14 is reconciled after the corrections below; IA-15–17 agree. IA-18 and overall 1057 remain incomplete.

## 1. IA-14: Plan section 5 comparison

Quotations are short pre-correction excerpts, retained in their original languages. Sources are under `docs/` except HELP (`src/core/help_text.zig`). OK means semantic agreement, F a correction and N a note below. Existing fixture words are included; this is not a translation of all historical material.

| ID | 文書・節 / Document and section | 英語の引用 / English quotation | 日本語の引用 / Japanese quotation | 根拠 / Evidence | 判断 / Finding |
|---|---|---|---|---|---|
| C01 | USER_MANUAL: Starting and input / 起動と入力 | “SAVE, LOAD-DICTIONARY, and SAVESYS still write and read image files” | 「`SAVE`・`LOAD-DICTIONARY`・S01の組込辞書・メモリー配置変更前のイメージは拒否」 | COMPATIBILITY §Independent extension group / 独立した拡張語群; saved-app design 機能除外と予約引数 | F1 |
| C02 | USER_MANUAL: Saved application autostart / 保存アプリの自動起動 | “Only a leading `--sigma` enables host options” | 「先頭に`--sigma`を置き」 | SAVED_APPLICATION_STARTUP_DESIGN: アプリ引数とホストオプション; HELP ARG/ARGC/APP-ENTRY! | OK |
| C03 | USER_MANUAL: Saved application autostart / 保存アプリの自動起動 | “Normal return and BYE exit through common block writeback and cleanup” | 「正常復帰とBYEは共通のblock保存・後始末を通って終了」 | SAVED_APPLICATION_STARTUP_DESIGN: 起動順と終了（全体レビューを反映）; plan §2 IA-09 | OK |
| C04 | USER_MANUAL + COMPATIBILITY: Standard event waiting / 標準イベントの待機 | “A non-stdin INFILE-EXECUTE selection throws -21” | 「非stdinを選択している場合は入力を消費せず-21をTHROW」 | COMPATIBILITY same section: “also supports files selected”; FILE_INPUT_WAIT_DESIGN / IMPLEMENTATION | F2 |
| C05 | USER_MANUAL + COMPATIBILITY: Terminal presentation / 端末表示の拡張 | “Caught THROW retains them” | 「CATCHしたTHROWでは維持」 | TERMINAL_CONTROL_DESIGN; ASYNC_COMMON_RULES §3/6; HELP TERM-MODE! | OK |
| C06 | USER_MANUAL + COMPATIBILITY: EXEC-LIMITED (652) | “debug and extension must both be enabled”; “The 20ms target is not a guarantee” | 「debugとextensionの両方が必要です」; 「20msは目標で、保証ではありません」 | EXECUTION_CONTROL_DESIGN; plan §4 M9 / §11 final D3 | OK |
| C07 | GRAPHICS_AND_SOUND: PCM streams / PCMストリーム; COMPATIBILITY: PCM | “Full restore while owning one is busy (-528); LOAD-DICTIONARY append preserves the target stream” | 「所有中の完全復元はbusy（-528）、LOAD-DICTIONARYの追記は対象のPCMを保持」 | PCM_STREAM_DESIGN: 所有と保存; HELP PCM-WAIT/PCM-CLOSE; plan §11 PCM | OK |
| C08 | WORD_REFERENCE: TASK-CANCEL / TASK-RELEASE / TASK-SNAPSHOT-RELEASE | “A successful request does not establish a cancelled outcome”; “Does not join or prove termination” | 「要求の成功だけでは取消し終端は確定せず」; 「joinも停止完了の保証も行わず、内部資源は引渡し・回収まで保持する」 | HELP same words; TASK_CONTROL_ACCEPTANCE_SUMMARY §2 AC-01/08/22, §3a; plan §11 T6–T9 | OK |
| C09 | WORD_REFERENCE: TASK-WAIT-MANY; HELP same entry | “PAINTED, not physical presentation”; “NO-CAPABILITY -311” | 「物理提示の保証ではない」; 「NO-CAPABILITY（-311）」 | CORE_EXTENSION_DETAILED_DESIGN §10.4/11.3; plan IA-07; graphics capability table | OK |
| C10 | WORD_REFERENCE: GFX-TK-WINDOW-CLOSE; HELP same entry | “( action -- closes )”; “action 2 closes without counting, 3 reads and acknowledges close requests” | 「( action -- closes )」; 「2なら明示的に閉じて回数を増やさず、3なら回数を読み」 | src/core/words_graphics.zig gfx_tk_window_close; tools §3; diagnosis REPORT | OK |
| C11 | WORD_REFERENCE: GFX-FRAME-WAIT; HELP same entry | “a wait of at most ms, 0 to 60000” | 「最大msミリ秒（0〜60000）待ちます。範囲外のmsは-24」 | src/core/words_graphics.zig: ms < 0 or ms > 60000 => InvalidNumber | N1 |
| C12 | WORD_REFERENCE: APP-ENTRY!; HELP same entry | “completed, non-compile-only colon definition” | 「完成したcolon定義」 | HELP APP-ENTRY!; SAVED_APPLICATION_STARTUP_DESIGN: 公開APIと登録 | F3 |
| C13 | WORD_REFERENCE: LOAD-DICTIONARY; USER_MANUAL: Saved application autostart | “LOAD-DICTIONARY preserves the receiving setting”; HELP “LOAD keeps” | 「LOAD-DICTIONARYは追加先の登録を未登録も含め維持」; HELP訳「LOADは追加先の設定を保ち」 | SAVED_APPLICATION_STARTUP_DESIGN: 保存・完全復元・追加読込み; standard LOAD is block input | N2 |
| C14 | TASK_CONTROL_ACCEPTANCE_SUMMARY §2/3/3a/5, both languages | “U1-U5 were completed on 2026-11-26”; old “remaining” clauses | 「U1〜U5の確認は2026-11-26に完了」; 旧「未確認」文 | R7 §3a/5; plan §1 historical precedence and §11 N2 | N3 |

Individually compared stack effects: `ARGC`, `ARG`, `NEXT-ARG`, `SHIFT-ARGS`, `APP-ENTRY!`, `APP-ENTRY@`, `APP-ENTRY-OFF`, `SAVE`, `SAVESYS`, `LOAD-DICTIONARY`, `CATCH`, `THROW`, `BYE`, `QUIT`, `TERM-MODE!`, `EKEY-WAIT`, `WAIT-FILES`, `READ-AVAILABLE`, `WRITE-AVAILABLE`, `WAIT-WRITABLE`, `PROC-NEW`, `PROC-ARG`, `PROC-START`, `PROC-STDIN`, `PROC-STDOUT`, `PROC-STDERR`, `PROC-WAIT`, `PROC-FREE`, `CLOSE-FILE`, `TASK-SNAPSHOT`, `TASK-SNAPSHOT-RELEASE`, `TASK-SUBMIT`, `TASK-STATE`, `TASK-WAIT`, `TASK-RESULT`, `TASK-CANCEL`, `TASK-RELEASE`, `TASK-WAIT-MANY`, `PCM-OPEN`, `PCM-WRITE`, `PCM-QUEUED`, `PCM-WAIT`, `PCM-STOP`, `PCM-CLOSE`, `PCM-UNDERRUNS`, `GFX-WINDOW-FRAMES`, `GFX-WINDOW-FLAGS`, `GFX-AUTO-DISPLAY!`, `GFX-SHOW-WINDOW`, `GFX-SHOW-TK`, `GFX-SHOW-BLOCKS`, `GFX-TK-WINDOW-CLOSE`, `GFX-FRAME-WAIT`.

I/O and child-process details (same-named WORD_REFERENCE sections, HELP, ASYNC_IO_DESIGN and PROCESS_MANAGEMENT_DESIGN final public API table):

| 語 / Word | 英日共通スタック / Shared stack | 英語 / English | 日本語 / Japanese | 判断 / Finding |
|---|---|---|---|---|
| WAIT-FILES | ` ( addr n ms -- index ior ) ` | Wait for the first readable file ID in a 1..64-cell array; EOF and I/O errors are ready. Validate all IDs first. Zero polls, negative waits indefinitely; timeout returns -1 0. Ctrl+C throws -28. Requires optional host file I/O support. | 1〜64個のファイルIDを検査してから、読取り可能な先頭の添字とiorを返します。観測済みEOFとエラーも準備完了です。ms=0は即時確認、負数は無期限待機、時間切れは-1 0、中断は-28です。 | OK |
| READ-AVAILABLE | ` ( c-addr u fid -- u2 eof? ior ) ` | Read currently available bytes without waiting for a producer; distinguish temporary emptiness from observed EOF. Return the transferred count even with an I/O error. An empty buffer validates without consuming input. Host partial bytes are shared with ordinary file words. | いま取得できるバイトを待たずに読み、読めた数・観測済みEOFの真偽・iorを返します。部分データとエラーを同時に返せます。空のバッファでは入力を消費しません。通常のファイル語と保留バイトを共有します。 | OK |
| WRITE-AVAILABLE | ` ( c-addr u fid -- u2 ior ) ` | Accept as many bytes as can be queued without waiting for a consumer. The host copies accepted bytes before returning; the count does not guarantee delivery. Later pipe errors remain sticky until close. FLUSH-FILE and close wait for delivery. | 待たずに受け付けられる分を書き込み、受付数とiorを返します。ホストは戻る前にデータをコピーします。受付数は相手への配送完了を意味しません。後続エラーはcloseまで保持され、FLUSH-FILEとcloseで配送完了を待ちます。 | OK |
| WAIT-WRITABLE | ` ( addr n ms -- index ior ) ` | Wait for the first file ID that can accept output or report an I/O error; validate all 1..64 IDs first. Zero polls, negative waits indefinitely; timeout returns -1 0. Ctrl+C throws -28. Native resource ownership stays at the host. | 1〜64個のファイルIDを検査してから、出力を受け付けられる先頭の添字とiorを返します。ms=0は即時確認、負数は無期限待機、時間切れは-1 0、中断は-28です。ネイティブ資源はホストが所有します。 | OK |
| PROC-NEW | ` ( -- proc ior ) ` | Create an owned process configuration; the host supports 64 public records. | 子プロセスの設定を作り、不透明IDとiorを返します。公開枠は64件です。 | OK |
| PROC-ARG | ` ( addr len proc -- ior ) ` | Copy an argument before startup; the first is argv\[0\]. No implicit shell. | 起動前の設定へ引数をコピーします。最初の引数が実行ファイルargv\[0\]で、暗黙にシェルは起動しません。 | OK |
| PROC-START | ` ( proc -- ior ) ` | Start the configured executable with copied argv, environment and directory. | コピーした引数・環境・作業ディレクトリで直接起動し、起動失敗をiorで返します。 | OK |
| PROC-STDIN | ` ( proc -- fid ior ) ` | Return the writable child input FILE ID; zero if not piped. | 子の標準入力へ親が書き込むFILE IDとiorを返します。pipe以外は0です。CLOSE-FILEで子へEOFを渡せます。 | OK |
| PROC-STDOUT | ` ( proc -- fid ior ) ` | Return the readable child output FILE ID; zero if not piped. | 子の標準出力を親が読むFILE IDとiorを返します。pipe以外は0です。子の終了後もclose/FREEまで読み出せます。 | OK |
| PROC-STDERR | ` ( proc -- fid ior ) ` | Return the readable child error FILE ID; zero if not piped or merged. | 子の標準エラーを親が読むFILE IDとiorを返します。pipe以外とstdoutへの統合時は0です。 | OK |
| PROC-WAIT | ` ( proc ms -- state code ior ) ` | Wait with one monotonic deadline: zero polls, negative waits indefinitely. Timeout retains state 1; Ctrl+C throws -28 without killing the child. | 単調時計の一つの期限で待ち、state・code・iorを返します。ms=0は即時確認、負数は無期限。時間切れはstate=1、中断は-28で子を止めません。 | OK |
| PROC-FREE | ` ( proc -- ior ) ` | Release configuring or terminal records, discard remaining pipe data and reap the root child. Running returns EBUSY; failed cleanup retains ownership for retry. | 設定中または終了済みの資源を解放し、未読・未配送データを破棄して直接の子を回収します。実行中はEBUSY、回収できない資源は再試行用に保持します。 | OK |

## 2. Differences, corrections and judgments

- F1: An S01 obsolete-image warning interrupted the Japanese USER_MANUAL “起動と入力” list, obscuring that SAVE/LOAD-DICTIONARY/SAVESYS remain usable without FILES. Removed the inserted warning from that sentence and restored the English list. The existing S01 warning in the dictionary-saving section remains.
- F2: Both USER_MANUAL “Standard event waiting” sections stated the historical stdin-only contract as current. Replaced it with the corresponding COMPATIBILITY paragraph: selected files work with optional FileOps.event_wait, including UTF-8, literal ESC/byte3, retained partial bytes and -21 when the callback is absent. This follows FILE_INPUT_WAIT_DESIGN/IMPLEMENTATION, with no new specification.
- F4: Both USER_MANUAL introductions said images load across different groups without qualifying the feature guard. Added the existing COMPATIBILITY independent-extension contract: added builtins/direct builtin operations from excluded groups fail before loading, while reserved base-dictionary calls retain runtime rejection. No contract change.
- F3: The Japanese APP-ENTRY! description omitted non-compile-only. Corrected `docs/word-reference/translations.ja.tsv` and regenerated WORD_REFERENCE.ja.md with the existing `python scripts/word-reference.py`. English HELP and stack effects are unchanged.
- N1: Japanese GFX-FRAME-WAIT adds the out-of-range -24 detail; English HELP states the valid range. The implementation returns InvalidNumber. These are compatible; no specification decision or change is needed.
- N2: Both APP-ENTRY HELP descriptions abbreviate dictionary append as “LOAD”, although standard LOAD is block input. The user manual and dedicated LOAD-DICTIONARY entry are correct. Option A: spell LOAD-DICTIONARY consistently in both languages during the next HELP update; B: retain the abbreviation. Recommend A. Changing HELP source affects executable/generated-source fingerprints, so this review records the abbreviation without changing source. This is editorial, not an undecided contract.
- N3: R7 section 2's old remaining-integration clause and section 3's old N2 proposal are history superseded by section 3a and the dated 2026-11-25/26 decisions. Both languages need this precedence. Existing R7 passes do not establish saved-startup acceptance in 1057.

No new conflicting contract requiring a specification decision was found. Plan section 11 D1–D5 already have final A decisions; the final IA-11 method decision is B. Preserve active child/pipe retention, full restore only after EXEC ends and bound-host-only task Busy. Substituted tests do not establish real native paint concurrency.

## 3. IA-15: Bilingual plan review

| 節 / Section | 照合結果 / Result |
|---|---|
| §1–3 | 18 IA IDs (IA-01–18), R1–R7, separate saved entry, staged failures, original proposal/history versus tools: agree |
| §4 | M0–M11, A/G/E 8 combinations, files/debug/image/float/x11 exclusions, M11 Linux only: agree |
| §5–7 | User-document mapping, 999/1001 evidence, MNL-01a/01b/02/03a/03b/04/05, per-OS observations and gaps: agree |
| §8 | 33.34 ms / 50 ms / 16,666,667 ns; 1,200 frames; 1,199 deadline samples; 2 pairs, 8 runs/OS; extension 26.672/40 ms, 4 pairs total: agree |
| §8 PCM | 48,000 Hz mono s16LE, 512 frames/1,024 bytes, capacity 4,096, WAIT 1 / 1,000 ms, underrun delta 0 per run, matching supply: agree |
| §9–10 | Stage estimates remain estimates; final B/B/B decisions agree; no measurement approval inferred |
| §11 | Resource rows, T1–T14, D1–D5, final A decisions and IA-11 B method agree; earlier pending wording is history |

The plans and decision tables are unchanged. Tools sections 1–6 were also reviewed: functional exit budgets are distinct from timing limits, and Zig full-restore tests from physical paint evidence.

## 4. IA-16: Existing 999 decision

Authority: [AUDIO_TARGET_AUDIT](AUDIO_TARGET_AUDIT.md), final user decision 1140 dated 2026-11-22, subsections 1–3. It agrees with plan section 6. The following existing values describe the selected batched versions, not new measurements.

| Target | Declared model | Heaviest load | Windows | Linux | Mac | Decision | Document |
|---|---|---|---|---|---|---|---|
| CHIP-8 | Original/SUPER-CHIP buzzer; XO-CHIP pattern/pitch | xo_8khz_pattern_pitch | 33.78x | 38.23x | 50.59x | Keep Forth | [CHIP8_AUDIO_FORTH.md](CHIP8_AUDIO_FORTH.md) |
| ZX Spectrum | 48K beeper; 128K beeper + AY | 128k_period_zero | 3.59x | 4.14x | 5.34x | Keep Forth | [ZX_SPECTRUM_AUDIO_FORTH.md](ZX_SPECTRUM_AUDIO_FORTH.md) |
| NES | NTSC five voices including DMC | fast_max_noise_dmc | 6.17x | 6.88x | 9.17x | Keep Forth | [NES_DMC_FORTH.md](NES_DMC_FORTH.md) |
| Commodore 64 | PAL three register voices, custom filter approximation | maximum filter/sync/mixed | 1.03x | 1.17x | 1.43x | Keep Forth | [SID_FORTH.md](SID_FORTH.md) |
| SNES | S-DSP eight voices, BRR/envelope/noise/PMON/echo/FIR | dense_8khz_reg_ram(with `SNES-FRAMES`) | 28.69x | 30.34x | 28.04x | Keep SNES-FRAMES native (1188) | [SNES_DSP_AUDIO_FORTH.md](SNES_DSP_AUDIO_FORTH.md) |
| Apple II | NTSC II/II+ speaker and Mockingboard | card_8khz_bus | 5.82x | 2.74x | 7.49x | Keep Forth | [APPLE2_AUDIO_FORTH.md](APPLE2_AUDIO_FORTH.md) |
| Amiga | PAL Paula four stereo voices, DMA/manual DAT/IRQ/attach | volume/periodmodulation | 5.52x | 6.44x | 7.95x | Keep Forth | [PAULA_FORTH.md](PAULA_FORTH.md) |
| Atari ST | YM2149 three voices/noise/envelope/I/O, ST byte bus | fast_period1 | 3.21x | 3.83x | 4.87x | Keep Forth | [YM2149_FORTH.md](YM2149_FORTH.md) |

| Target | Deferred variants |
|---|---|
| CHIP-8 | Original speaker electrical behavior |
| ZX Spectrum | +2/+3/clones, ULA contention, AY port B |
| NES | PAL/Dendy, cartridge expansion audio, DMA CPU stalls/bus contention |
| Commodore 64 | 6581/8580 analog behavior, D418 digital playback, combined waveforms, NTSC |
| SNES | SPC700, DSP fine slot timing |
| Apple II | IIe/IIc/IIgs including DOC, PAL, cassette, SC-01/SSI263, other cards, 6522 timer/interrupt |
| Amiga | NTSC/ECS, analog/LED filters, Agnus slots |
| Atari ST | STE DMA, Falcon, analog mixing |

1140 records Windows/Linux/Mac listening, physical Ctrl+C stop and replay as complete for each declared model. These are not new 1057 MNL passes. Existing Windows records use Ryzen 7 7700. Only Apple II's Linux result is native i7-8700K (pw-play/PipeWire; direct ALSA unverified); other Linux results use WSL on Ryzen 7 7700. See the per-OS records below for Mac environments/routes; do not assume one device or all backends.

NES/SID/Paula/ST retain measurements made without stopping other applications, with no remeasurement. SID's Windows 1.03x describes audio synthesis, not complete C64 headroom. SNES Forth alone reached only 0.74x for brr_filter3_pitchmax on native Linux, supporting the 1188 SNES-FRAMES native exception. Reference Forth and audio-excluded use remain. Keep the other seven in Forth; add no machine-independent native component. Variants are deferred because the required CPU-side emulators do not yet exist, not because investigation proved them unnecessary. Other model exclusions in the individual documents remain deferred too.

| モデル・採用版 / Model and selected version | 既存の測定・OS記録 / Existing measurements and OS records |
|---|---|
| [CHIP8_AUDIO_FORTH](CHIP8_AUDIO_FORTH.md) | [2026-11-20-chip8-os-acceptance.json](measurements/2026-11-20-chip8-os-acceptance.json), [2026-11-20-chip8-audio.json](measurements/2026-11-20-chip8-audio.json) |
| [ZX_SPECTRUM_AUDIO_FORTH](ZX_SPECTRUM_AUDIO_FORTH.md) | [2026-11-20-zx-spectrum-os-acceptance.json](measurements/2026-11-20-zx-spectrum-os-acceptance.json), [2026-11-20-zx-spectrum-audio.json](measurements/2026-11-20-zx-spectrum-audio.json) |
| [NES_DMC_FORTH](NES_DMC_FORTH.md) | [2026-11-20-linux-audio-listening.json](measurements/2026-11-20-linux-audio-listening.json), [2026-11-20-nes-sid-windows-listening.json](measurements/2026-11-20-nes-sid-windows-listening.json), [2026-11-20-nes-apu.json](measurements/2026-11-20-nes-apu.json), [2026-11-20-nes-dmc.json](measurements/2026-11-20-nes-dmc.json) |
| [SID_FORTH](SID_FORTH.md) | [2026-11-20-linux-audio-listening.json](measurements/2026-11-20-linux-audio-listening.json), [2026-11-20-nes-sid-windows-listening.json](measurements/2026-11-20-nes-sid-windows-listening.json), [2026-11-20-sid.json](measurements/2026-11-20-sid.json) |
| [SNES_DSP_AUDIO_FORTH](SNES_DSP_AUDIO_FORTH.md) | [2026-11-20-snes-dsp-audio.json](measurements/2026-11-20-snes-dsp-audio.json), [2026-11-20-snes-dsp-os-preparation.json](measurements/2026-11-20-snes-dsp-os-preparation.json), [2026-11-20-snes-dsp-os-acceptance.json](measurements/2026-11-20-snes-dsp-os-acceptance.json), [2026-11-20-snes-dsp-native.json](measurements/2026-11-20-snes-dsp-native.json), [2026-11-22-snes-dsp-macos-acceptance.json](measurements/2026-11-22-snes-dsp-macos-acceptance.json), [2026-11-22-snes-dsp-macos-timing.json](measurements/2026-11-22-snes-dsp-macos-timing.json), [2026-11-22-snes-dsp-macos-final-play.json](measurements/2026-11-22-snes-dsp-macos-final-play.json) |
| [APPLE2_AUDIO_FORTH](APPLE2_AUDIO_FORTH.md) | [2026-11-22-apple2-audio.json](measurements/2026-11-22-apple2-audio.json), [2026-11-22-apple2-audio-linux-acceptance.json](measurements/2026-11-22-apple2-audio-linux-acceptance.json), [2026-11-22-apple2-audio-macos-acceptance.json](measurements/2026-11-22-apple2-audio-macos-acceptance.json), [2026-11-22-apple2-audio-windows-acceptance.json](measurements/2026-11-22-apple2-audio-windows-acceptance.json) |
| [PAULA_FORTH](PAULA_FORTH.md) | [2026-11-20-linux-audio-listening.json](measurements/2026-11-20-linux-audio-listening.json), [2026-11-20-paula-ym-windows-listening.json](measurements/2026-11-20-paula-ym-windows-listening.json), [2026-11-20-paula.json](measurements/2026-11-20-paula.json) |
| [YM2149_FORTH](YM2149_FORTH.md) | [2026-11-20-linux-audio-listening.json](measurements/2026-11-20-linux-audio-listening.json), [2026-11-20-paula-ym-windows-listening.json](measurements/2026-11-20-paula-ym-windows-listening.json), [2026-11-20-ym2149.json](measurements/2026-11-20-ym2149.json) |

## 5. IA-17: Existing 1001 decision

Sources: [EMULATOR_CORE_PLAN](EMULATOR_CORE_PLAN.md), background prototype section dated 2026-11-22 and its user decision; [original Windows record](measurements/2026-11-22-background-prototype-windows.json).

| 負荷 / Workload | 7回中央値 / Seven-run median (µs) | 60 Hz (%) |
|---|---|---|
| naive8 | 4276.55 | 25.66 |
| fast8 | 691.38 | 4.15 |
| to32 | 1969.0 | 11.81 |
| put_indexed | 24.59 | 0.15 |
| put_rgb | 24.63 | 0.15 |
| put_rows | 43.24 | 0.26 |

Windows 11 Pro 10.0.26300, Ryzen 7 7700, Zig 0.17.1, `-Doptimize=fast -Dcpu=baseline`. One 256×240 background, 32×30 tiles, two bitplanes and attribute palettes. Seven fresh processes per workload in rotated order, timing words alone; no SHOW, scrolling or sprites. The original record confirms independent Python buffer/image checks. Recomputing medians from the stored seven values agrees with all six documented numbers; no remeasurement occurred. Keep the eight-pixel Forth decode and existing GFX-INDEXED transfers, with no native addition in this scope. Sprites, priority composition and four-or-more planes are unmeasured. Reopen only when an actual Forth emulator shows a deficit, defining machine-independent input in a separate task. Do not merge later Mac results into the Windows decision or require rendering in graphics-excluded builds.

## 6. Validation

Validate with `python scripts/check-docs.py`, `git diff --check`, referenced files/sections, bilingual table/numeric alignment and LF. Recorded outcomes are in results section 6.
