# 1057：文書・採否の照合記録（1415）

[English](INTEGRATION_ACCEPTANCE_1057_REVIEW.md)

2026-11-26、ロク。記録基点は `99afe6d`。静的照合のみ。実行・再測定・採否の変更はしていない。IA-14は下記の修正後に照合済み、IA-15〜17は一致。IA-18と1057全体は未完了。

## 1. IA-14：計画§5の対応表

引用は修正前の短い抜粋で、英日とも原文を残す。表の出典は `docs/` 配下（HELPは `src/core/help_text.zig`）。OKは意味一致、Fは修正、Nは以下の注意事項。結合題材の既存語も対象とし、一般文書の全履歴を翻訳する作業ではない。

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

スタック効果を個別照合した語：`ARGC`, `ARG`, `NEXT-ARG`, `SHIFT-ARGS`, `APP-ENTRY!`, `APP-ENTRY@`, `APP-ENTRY-OFF`, `SAVE`, `SAVESYS`, `LOAD-DICTIONARY`, `CATCH`, `THROW`, `BYE`, `QUIT`, `TERM-MODE!`, `EKEY-WAIT`, `WAIT-FILES`, `READ-AVAILABLE`, `WRITE-AVAILABLE`, `WAIT-WRITABLE`, `PROC-NEW`, `PROC-ARG`, `PROC-START`, `PROC-STDIN`, `PROC-STDOUT`, `PROC-STDERR`, `PROC-WAIT`, `PROC-FREE`, `CLOSE-FILE`, `TASK-SNAPSHOT`, `TASK-SNAPSHOT-RELEASE`, `TASK-SUBMIT`, `TASK-STATE`, `TASK-WAIT`, `TASK-RESULT`, `TASK-CANCEL`, `TASK-RELEASE`, `TASK-WAIT-MANY`, `PCM-OPEN`, `PCM-WRITE`, `PCM-QUEUED`, `PCM-WAIT`, `PCM-STOP`, `PCM-CLOSE`, `PCM-UNDERRUNS`, `GFX-WINDOW-FRAMES`, `GFX-WINDOW-FLAGS`, `GFX-AUTO-DISPLAY!`, `GFX-SHOW-WINDOW`, `GFX-SHOW-TK`, `GFX-SHOW-BLOCKS`, `GFX-TK-WINDOW-CLOSE`, `GFX-FRAME-WAIT`.

I/Oと子プロセスの補足（WORD_REFERENCEの同名節、HELP、ASYNC_IO_DESIGNおよびPROCESS_MANAGEMENT_DESIGN「公開API（レビュー後の確定契約）」）：

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

## 2. 食い違い・修正・判断

- F1：日本語USER_MANUAL「起動と入力」の文中に、S01の古い画像を拒否する注意が入り込み、files除外時もSAVE/LOAD-DICTIONARY/SAVESYSを使えるという説明が崩れていた。注意の混入を除いて英文と同じ列挙へ修正。S01の注意は「辞書の保存と単独実行ファイル」に既存のまま残す。
- F2：英日USER_MANUAL「標準イベントの待機」は古いstdin専用契約を現在形で記載していた。英日COMPATIBILITYの同節とFILE_INPUT_WAIT_DESIGN/IMPLEMENTATIONにある、optional FileOps.event_waitを備えるホストで選択ファイルも使える説明へ置換。UTF-8、ESC/byte3、保留バイト、callbackがない場合の-21も転記。新仕様は加えていない。
- F4：英日USER_MANUAL「起動と入力」の旧「グループの違う版でも読み込める」（英語“loads into a build with other groups”）には、追加組込み語・直接builtin命令の読込み前のInvalidImage拒否条件が欠けていた。英日COMPATIBILITY「独立した拡張語群」の既定契約を補い、予約済みの基本辞書の呼出しとの境界を区別した。
- F3：APP-ENTRY!の日本語説明にnon-compile-onlyの条件が欠けていた。`docs/word-reference/translations.ja.tsv`を修正し、既存の`python scripts/word-reference.py`でWORD_REFERENCE.ja.mdへ反映した。英語HELPとスタック効果は変更していない。
- N1：GFX-FRAME-WAITの日本語は範囲外-24を補足し、英語HELPは有効範囲のみを記す。実装のInvalidNumberと一致し、相反する条件ではない。仕様判断は不要、変更しない。
- N2：APP-ENTRYの英日HELPにはともに“LOAD”という省略があるが、標準LOADはブロック入力である。利用者マニュアルと専用LOAD-DICTIONARY項目は正しい。選択肢A：次回HELP整備で英日ともLOAD-DICTIONARYへ表記を統一／B：省略を残す。推奨A。今回HELPソースを変えると実行体・生成資料の指紋に関わるため、略称の注意をここへ残した。契約の変更や未決仕様ではない。
- N3：R7 §2の旧「残る実機結合」や§3の旧N2提案は、§3aと2026-11-25/26の決定より古い履歴。英日とも同じ区別が必要。1057保存起動の合格にR7の既存合格を転用しない。

今回、新たな仕様判断を必要とする相反する契約は見つからなかった。計画§11のD1〜D5は末尾の利用者決定A、IA-11の方法は最後の決定Bで既決。D2活動中の子/pipe保持、D3 EXEC終了後だけの完全復元、D4 bound hostだけのBusy保証を維持する。実paintとの競合と差替え試験を同じ合格にはしない。

## 3. IA-15：計画の英日照合

| 節 / Section | 照合結果 / Result |
|---|---|
| §1–3 | 18 IA IDs (IA-01–18), R1–R7, separate saved entry, staged failures, original proposal/history versus tools: agree |
| §4 | M0–M11, A/G/E 8 combinations, files/debug/image/float/x11 exclusions, M11 Linux only: agree |
| §5–7 | User-document mapping, 999/1001 evidence, MNL-01a/01b/02/03a/03b/04/05, per-OS observations and gaps: agree |
| §8 | 33.34 ms / 50 ms / 16,666,667 ns; 1,200 frames; 1,199 deadline samples; 2 pairs, 8 runs/OS; extension 26.672/40 ms, 4 pairs total: agree |
| §8 PCM | 48,000 Hz mono s16LE, 512 frames/1,024 bytes, capacity 4,096, WAIT 1 / 1,000 ms, underrun delta 0 per run, matching supply: agree |
| §9–10 | Stage estimates remain estimates; final B/B/B decisions agree; no measurement approval inferred |
| §11 | Resource rows, T1–T14, D1–D5, final A decisions and IA-11 B method agree; earlier pending wording is history |

計画・決定表は変更していない。英日の道具説明§1〜6とも照合し、functionalの終了枠と時間閾値、完全復元のZig試験と実paintを分離した。

## 4. IA-16：999の既決採否

最終根拠は[AUDIO_TARGET_AUDIT](AUDIO_TARGET_AUDIT.md)「最終採否（1140、2026-11-22、利用者の決定）」§1〜3。計画§6と一致。以下は採用したまとめ処理版の最重負荷の既存値であり、今回の測定ではない。

| 対象 | 宣言したモデル | 最も重い負荷 | Windows | Linux | Mac | 採否 | 文書 |
| --- | --- | --- | ---: | ---: | ---: | --- | --- |
| CHIP-8 | 原型とSUPER-CHIPのブザー、XO-CHIPのpatternとpitch | xo_8khz_pattern_pitch | 33.78倍 | 38.23倍 | 50.59倍 | Forthで維持 | [CHIP8_AUDIO_FORTH.md](CHIP8_AUDIO_FORTH.md) |
| ZX Spectrum | 48Kのbeeper、128Kのbeeper＋AY | 128k_period_zero | 3.59倍 | 4.14倍 | 5.34倍 | Forthで維持 | [ZX_SPECTRUM_AUDIO_FORTH.md](ZX_SPECTRUM_AUDIO_FORTH.md) |
| NES | NTSCの5声（DMCを含む） | fast_max_noise_dmc | 6.17倍 | 6.88倍 | 9.17倍 | Forthで維持 | [NES_DMC_FORTH.md](NES_DMC_FORTH.md) |
| Commodore 64 | 3声のレジスタモデルと独自のフィルター近似（PAL） | 最大フィルター・同期・混在 | 1.03倍 | 1.17倍 | 1.43倍 | Forthで維持 | [SID_FORTH.md](SID_FORTH.md) |
| SNES | S-DSPの8声、BRR、envelope、noise、pitch modulation、echoとFIR | dense_8khz_reg_ram（`SNES-FRAMES`を使う場合） | 28.69倍 | 30.34倍 | 28.04倍 | `SNES-FRAMES`を本体に残す（1188） | [SNES_DSP_AUDIO_FORTH.md](SNES_DSP_AUDIO_FORTH.md) |
| Apple II | II／II+（NTSC）の内蔵スピーカー、Mockingboard | card_8khz_bus | 5.82倍 | 2.74倍 | 7.49倍 | Forthで維持 | [APPLE2_AUDIO_FORTH.md](APPLE2_AUDIO_FORTH.md) |
| Amiga | Paulaの4声ステレオ、DMA、手動DAT、IRQ、attach（PAL） | volume/period変調 | 5.52倍 | 6.44倍 | 7.95倍 | Forthで維持 | [PAULA_FORTH.md](PAULA_FORTH.md) |
| Atari ST | YM2149の3声、noise、envelope、I/O、STのbyte bus | fast_period1 | 3.21倍 | 3.83倍 | 4.87倍 | Forthで維持 | [YM2149_FORTH.md](YM2149_FORTH.md) |

| 対象 | 保留 |
| --- | --- |
| CHIP-8 | 原機のスピーカーの電気特性 |
| ZX Spectrum | +2、+3、クローン、ULAのバス競合、AYのポートB |
| NES | PALとDendy、カートリッジの拡張音源、DMAによるCPUの停止とバス競合 |
| Commodore 64 | 6581と8580のアナログ特性、D418のデジ再生、合成波形、NTSC |
| SNES | SPC700、DSPの細かいスロットの時刻 |
| Apple II | IIe、IIc、IIgs（DOCを含む）、PAL、カセット出力、SC-01とSSI263、Mockingboard以外のカード、6522のタイマーと割込み |
| Amiga | NTSC、ECS、アナログとLEDのフィルター、Agnusのスロット |
| Atari ST | STEのDMA、Falcon、アナログの混合 |

8対象とも、各文書の宣言モデルについてWindows・Linux・Macの実聴、物理Ctrl+C後の停止・再再生が完了と1140に記録されている。1057の新しいMNLの合格ではない。WindowsはRyzen 7 7700の既存記録、LinuxはApple IIだけ実機i7-8700K（pw-play/PipeWire、直接ALSA未確認）、ほかはRyzen 7 7700のWSL経路である。Macの環境・出力経路は下表の各OS記録を参照し、同一機器や全backendの保証へ広げない。

NES/SID/Paula/STは他アプリを止めていない既存測定を採用し再測定しない。SIDのWindows 1.03倍は音源単独でありC64全体の余裕ではない。SNESのForth単独の最重brr_filter3_pitchmaxはLinux実機0.74倍で不足し、1188の例外としてSNES-FRAMESを本体に残す。参照Forth版とaudio除外用の版も残る。ほかの7対象はForthを維持し、機種共通の本体部品を追加しない。保留理由は必要なCPU側エミュレータがまだないこと。各文書のその他のモデル外条件も保留であり、調べて不要とした意味ではない。

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

## 5. IA-17：1001の既決採否

出典：[EMULATOR_CORE_PLAN](EMULATOR_CORE_PLAN.md)「背景1画面の試作と測定（1001、2026-11-22）」と同節の利用者決定、[Windowsの原記録](measurements/2026-11-22-background-prototype-windows.json)。

| 負荷 / Workload | 7回中央値 / Seven-run median (µs) | 60 Hz (%) |
|---|---|---|
| naive8 | 4276.55 | 25.66 |
| fast8 | 691.38 | 4.15 |
| to32 | 1969.0 | 11.81 |
| put_indexed | 24.59 | 0.15 |
| put_rgb | 24.63 | 0.15 |
| put_rows | 43.24 | 0.26 |

Windows 11 Pro 10.0.26300、Ryzen 7 7700、Zig 0.17.1、`-Doptimize=fast -Dcpu=baseline`。256×240、32×30タイル、2ビットプレーン、属性パレット。各負荷を別プロセスで7回、順番を回し、語だけの時間を測定。SHOW・スクロール・スプライトなし。Pythonの独立計算とのバッファ・画像一致を原記録で確認し、保存された7値の中央値を再計算して文書の6値と一致を確認した（再測定ではない）。8画素をまとめて復号しGFX-INDEXED等へ転送するForthを維持し、測定範囲で本体追加なし。スプライト・優先順位・4枚以上のビットプレーンは未測定。将来Forthで不足が出たときだけ、機種共通の入力形式を決め別タスクで再検討する。Macの後続結果をWindowsの決定へ混ぜない。graphics除外構成へ描画能力を要求しない。

## 6. 検証

`python scripts/check-docs.py`、`git diff --check`、参照先ファイル・節、英日表構成・数値、LFを確認する。実行結果は結果台帳§6に記す。
