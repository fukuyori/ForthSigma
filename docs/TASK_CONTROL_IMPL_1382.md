# タスク1382：Windows・Linux実機受け入れの準備

> 現行の固定値・再測定手順は末尾「2026-11-25 決定B」を参照。以下の旧固定値と結果は履歴として保持する。

作成者はロクである。基点は `6a1b387009e8af9adc27730644becc8b1b748a21` である。Git commit・branch・push・tque変更は行わない。速度の本測定は実施しない。

測定器・最大負荷題材・runnerを追加し、2026-11-24の縮小計画を固定した。本測定と実機受け入れ判定は未実施である。位相の取り逃し、OSメモリの採取間隔、未対応のAC-29比較は後述の制約として残す。自動試験成功をAC全項目の実機合格へ読み替えない。

作成物：[測定計画](TASK_CONTROL_ACCEPTANCE_PLAN.md)、[英語手順書](TASK_CONTROL_ACCEPTANCE_MANUAL.md)、[日本語手順書](TASK_CONTROL_ACCEPTANCE_MANUAL.ja.md)、[実行スクリプト](../tests/scripts/run-acceptance.py)。

## 1. 項目ごとの区分と方法

(a)は自動試験、(b)はD07測定、(c)は手動確認である。複数必要な項目は併記する。WindowsとLinuxで独立して実行・記録する。Linuxは利用者指定の別機械 `/home/fuk/source/zig/ForthSigma` でClaudeが担当する。WSLの証拠へ転用しない。macOSは1383である。

既存証拠欄のコミットは該当文書を最後に更新した履歴であり、その時点で今回再試験した意味ではない。全て本依頼の基点に含まれる。試験名の一覧は5節に示す。

`A` = `python tests/scripts/run-acceptance.py --only test runtime plain`。全試験を実行し、表の対象ファイルに定義された試験を含める。`E` = 同runnerの `--only examples`、`C` = `--only matrix`、`D` = `--only docs` である。

| AC | 区分 | 受け入れ時の方法と対象試験 | 既存の実装段階の証拠：文書・節・コミット |
|---|---|---|---|
| AC-01 | (a) | A：`src/tests/task_control_w1_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1373.md](TASK_CONTROL_IMPL_1373.md)「3. 試験結果」、`fa6b0db` |
| AC-02 | (a)+(c)+(b) | Eを補助として実行し、手順書AC-02で実端末・資源を確認。時間は計画の専用測定へ分離 | [TASK_CONTROL_IMPL_1380.md](TASK_CONTROL_IMPL_1380.md)「3. Windowsでの実行結果」、`39e23f9` |
| AC-03 | (a) | A：`src/tests/task_control_1384_test.zig`、`task_control_w1_test.zig`、`task_permissions_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1384.md](TASK_CONTROL_IMPL_1384.md)「5. 試験と実行結果」、`6f5d596` |
| AC-04 | (a) | A：`src/tests/task_cancel_memory_test.zig`、`task_job_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1362.md](TASK_CONTROL_IMPL_1362.md)「試験と実行結果」、`83987a2` |
| AC-05 | (a)+(c)+(b) | Eを補助として実行し、手順書AC-05で実端末・資源を確認。時間は計画の専用測定へ分離 | [TASK_CONTROL_IMPL_1380.md](TASK_CONTROL_IMPL_1380.md)「3. Windowsでの実行結果」、`39e23f9` |
| AC-06 | (a) | A：`src/tests/task_permissions_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1360.md](TASK_CONTROL_IMPL_1360.md)「試験と実行結果」、`6f5d596` |
| AC-07 | (a)+(b) | A：`src/tests/task_snapshot_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1359.md](TASK_CONTROL_IMPL_1359.md)「試験と実行結果」、`6f5d596` |
| AC-08 | (a) | A：`src/tests/task_snapshot_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1359.md](TASK_CONTROL_IMPL_1359.md)「試験と実行結果」、`6f5d596` |
| AC-09 | (a)+(b) | A：`src/tests/task_transfer_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1361.md](TASK_CONTROL_IMPL_1361.md)「試験と実行結果」、`6f5d596` |
| AC-10 | (a) | A：`src/tests/task_results_test.zig`、`task_public_api_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1365.md](TASK_CONTROL_IMPL_1365.md)「試験と実行結果」、`83987a2` |
| AC-11 | (a) | A：`src/tests/task_state_machine_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1367.md](TASK_CONTROL_IMPL_1367.md)「試験と実行結果」、`fa6b0db` |
| AC-12 | (a) | A：`src/tests/task_ledger_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1364.md](TASK_CONTROL_IMPL_1364.md)「試験と実行結果」、`83987a2` |
| AC-13 | (a)+(b) | A：`src/tests/task_queue_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1366.md](TASK_CONTROL_IMPL_1366.md)「試験と実行結果」、`83987a2` |
| AC-14 | (a) | A：`src/tests/task_wait_reproduction_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1372.md](TASK_CONTROL_IMPL_1372.md)「5. 試験と実行結果」、`cfac327` |
| AC-15 | (a) | A：`src/tests/task_wait_reproduction_host_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1372.md](TASK_CONTROL_IMPL_1372.md)「5. 試験と実行結果」、`cfac327` |
| AC-16 | (a) | A：`src/tests/task_wait_host_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1369.md](TASK_CONTROL_IMPL_1369.md)「試験と実行結果」、`fa6b0db` |
| AC-17 | (a) | A：`src/tests/task_paint_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1370.md](TASK_CONTROL_IMPL_1370.md)「5. 試験と実行結果」、`83987a2` |
| AC-18 | (a)+(c)+(b) | Eを補助として実行し、手順書AC-18で実端末・資源を確認。時間は計画の専用測定へ分離 | [TASK_CONTROL_IMPL_1379.md](TASK_CONTROL_IMPL_1379.md)「5. 試験と結果」、`39e23f9` |
| AC-19 | (a) | A：`src/tests/task_schedule_host_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1387.md](TASK_CONTROL_IMPL_1387.md)「試験と実行結果」、`fa6b0db` |
| AC-20 | (a)+(c)+(b) | Eを補助として実行し、手順書AC-20で実端末・資源を確認。時間は計画の専用測定へ分離 | [TASK_CONTROL_IMPL_1380.md](TASK_CONTROL_IMPL_1380.md)「3. Windowsでの実行結果」、`39e23f9` |
| AC-21 | (a)+(b) | A：`src/tests/task_reap_reproduction_host_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1376.md](TASK_CONTROL_IMPL_1376.md)「試験と実行結果」、`abadd1b` |
| AC-22 | (a) | A：`src/tests/task_reap_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1374.md](TASK_CONTROL_IMPL_1374.md)「試験と実行結果」、`cfac327` |
| AC-23 | (a) | A：`src/tests/task_reap_reproduction_host_test.zig`（5節の全試験）。既存の注入・順序・状態assertを現候補で再確認 | [TASK_CONTROL_IMPL_1375.md](TASK_CONTROL_IMPL_1375.md)「試験と実行結果」、`cfac327` |
| AC-24 | (a)+(c)+(b) | Eを補助として実行し、手順書AC-24で実端末・資源を確認。時間は計画の専用測定へ分離 | [TASK_CONTROL_IMPL_1376.md](TASK_CONTROL_IMPL_1376.md)「試験と実行結果」、`abadd1b` |
| AC-25 | (a)+(c)+(b) | Eを補助として実行し、手順書AC-25で実端末・資源を確認。時間は計画の専用測定へ分離 | [TASK_CONTROL_IMPL_1380.md](TASK_CONTROL_IMPL_1380.md)「3. Windowsでの実行結果」、`39e23f9` |
| AC-26 | (a)+(b) | C：C00〜C16、語登録・ビルド・回帰。skipは実機成功へ数えない | [TASK_CONTROL_IMPL_1381.md](TASK_CONTROL_IMPL_1381.md)「3. Windowsの計画と結果」、`33f37f7` |
| AC-27 | 対象外 | macOSの実行は1383 | 受け入れ表3節 |
| AC-28 | (a) | DとC：公開58語・HELP英日・全語資料・READMEを照合。構成試験文書に示す隠し語/HELP残件は未確認 | [TASK_CONTROL_IMPL_1379.md](TASK_CONTROL_IMPL_1379.md)「5. 試験と結果」、`39e23f9` |
| AC-29 | (a)+(b) | 通常ReleaseFast/debug=falseのA/B/A′逆アセンブル比較とサイズ。1386の2・6・8節を参照。現候補の逆アセンブル比較は未対応。PE/ELFの.text抽出はsize群に実装 | [TASK_CONTROL_IMPL_1373.md](TASK_CONTROL_IMPL_1373.md)「3. 試験結果」、`fa6b0db` |

AC-21の「再利用」は現実装の同一Queue/workerによる新規VMの連続実行と、VM内部状態の再利用を区別する。温めたVMプールの性能や安全性を合格としない。AC-03はEXECUTE等の拒否も契約どおりの結果であり、全経路を許可する試験ではない。

## 2. 利用者の判断を反映した固定計画

2026-11-24の判断に従い、生成/実行取消しは25対象×100回、代表nativeのFILL/MOVE/COMPARE/SEARCH/ROLLは3位相×各100回、待ち取消しは100回、対話は各ケース10分×1回とした。利用条件8節の正式な出発点とは異なる縮小計画であり、計画とresults.jsonに記録する。観測最大が目標の80%を超える項目だけを追加確認する規則も計画へ記載した。

runnerは測定前に要求された計画SHA-256を確認し、原本と同一のコピー・ハッシュを保存する。終了時にも一致を確認する。WindowsとLinuxの本測定はClaudeが行う。今回、ロクは受け入れ用の時間標本を記録・評価していない。

## 3. 今回実装した測定器と制約

`-Dtask-acceptance=true` を追加した。既定はfalse。通常のReleaseFast/debug=false経路へ固定領域のatomicと必要な時計読み出しを追加する。task-traceはfalseで、06-Hの内訳とは別runにする。メインのログは区間終了後にまとめて書く。

- 要求→runner停止、要求→task資源の回収、待ち取消し→公開、投入→公開、公開→回収を採取する。回収は物理handback/retirement後、台帳・入力・結果・実行参照・VM・slotを解放した時点。共有workerを個別taskごとにjoinした意味ではない。
- Service.pollの管理1巡、TASK-SNAPSHOT API全体のメイン占有と投入可能までを採取する。初回のservice初期化を含む。取得したimage bytesも保存する。
- pipe注入→状態store後marker受信を採取する。輸送・scheduler・出力を含む上界であり、物理的な画面反映を測ったものではない。画面は英日手順書で手動確認する。
- WindowsのVirtualQueryEx/PrivateUsage/WorkingSet、Linux smapsのSize/accountable mappings/Rssとprivate/shared/stack/swapを記録する。基準と負荷のピーク差、128MiB予算、80%規則をJSONへ保存する。10ms採取のため絶対ピークとカテゴリ帰属の証明にはならない。
- 起動ready受信、PE/ELFの実行体/.textサイズは通常実行体で採取する。対照AはClaudeが同構成で用意する。

G1は256×256の開放/壁/蛇行、G2は幅28〜256の決定的な地雷・隣接数生成、T1は1MiB、I1は64KiB塊を最大実行1＋待ち4へ補充する題材を実装した。I1は初回busy workerで待ち4を作ってから解除する。mainの入出力とワーカーの許可集合を分けた。Forth結果の状態、G1頂点数、G2代表セル、T1件数、I1 checksumをassertする。

生成の狙った位相から要求時に進んでいた場合とnative区間の分類不能を、当該位相の有効速度標本にしない。生データと欠測を保持する。100回の要求試行が100回の有効位相標本になるとは保証しない。Snapshotは約3.45MiBの3世代を確認したが4MiB上限そのものではない。VMプール・温めた復元、A/A′/B単一VM比較、逆アセンブル採取、ネイティブ画面/音の結合実機確認は未対応または未実施であり、AC-29全体や実機合格を主張しない。

## 4. 前回準備時の検証結果

Windows PowerShell、Zig 0.17.1で次を確認した。本測定・Linux実行・手動実機確認は未実施である。

| 検査 | 結果・証拠 |
|---|---|
| `zig build test --summary all` | 成功。25/25 steps、1655/1688成功、33 skip。`.work/acceptance/test.log` |
| runner `--only runtime plain docs examples` | 成功。`.work/acceptance/20261124T091346Z-02dcd76a/results.json` |
| `zig build runtime-test --summary all` | 成功。8/8 steps。上記runのruntime.log |
| `zig build test -Ddebug=false --summary all` | 成功。25/25 steps、1580成功・108 skip。plain.log |
| 通常/診断ReleaseFastのbuild | 各成功。normal-buildとtrace-buildを分離 |
| 既存例ドライバー | 15群成功。examples.logとexamples-rawに保存 |
| `python scripts/check-docs.py` | 成功、findings 0。最終確認は `.work/acceptance/20261124T094206Z-44c16cbc/docs.log` |
| 取消しsmoke | 25位相×1回成功。取消しsmokeの最終実行は `.work/acceptance/20261124T092053Z-1f8c46e8/`。時刻差・速度統計は計算していない |
| 起動/サイズsmoke | 成功。A/Bに同一通常実行体を指定した動作確認のみ。`.work/acceptance/20261124T093125Z-c78696ab/`。ready_nsはnull |
| PE/ELFセクション | Windowsの実PEと合成ELF32/64の両endianで形式確認成功。Linux実行はしていない。sizeの最新smokeは `.work/acceptance/20261124T092128Z-3302bfa3/` |
| AC別指定 | 最終runnerの `--only AC-02` がexamples/runtimeへ展開して成功。`.work/acceptance/20261124T092048Z-6994440e/`。手動部分の合格ではない |
| Python構文と統計境界 | py_compile成功、空集合・偶数中央値・nearest-rank p95・超過件数を確認 |
| 事前確認なしのmeasure起動 | 引数検査で終了2、実行体を起動しないことを確認 |
| 変更ファイルの `zig fmt --check` | Zigファイルの変更なしのため対象なし。参考実行した既存build.zigは終了1で不整形を検出した。既存ファイルは変更していない |

構成C00〜C16はWindowsネイティブの全17構成が成功した。fresh-cacheで実行した。結果は `.work/acceptance/20261124T091516Z-efe608b3/results.json`、構成ごとの詳細は同ディレクトリの `matrix-raw/results.json`・commands.json・各ログ、生成物ハッシュは `matrix-binaries.json` に保存した。元の実行体は `.work/task-public-matrix/` に残している。

構成ごとのruntime成功/skipは以下のとおりである。構成による機能の無効化や実機opt-in未実施によるskipを、画面・音・端末の合格として数えない。

| 構成 | runtime成功 | runtime skip |
|---|---:|---:|
| C00 | 152 | 28 |
| C01 | 172 | 8 |
| C02 | 155 | 27 |
| C03 | 175 | 7 |
| C04 | 152 | 28 |
| C05 | 172 | 8 |
| C06 | 155 | 27 |
| C07 | 175 | 7 |
| C08 | 171 | 9 |
| C09 | 171 | 9 |
| C10 | 173 | 9 |
| C11 | 170 | 10 |
| C12 | 152 | 28 |
| C13 | 155 | 27 |
| C14 | 174 | 8 |
| C15 | 174 | 8 |
| C16 | 174 | 8 |

ビルドログにZig自身が出す経過時間を性能標本として利用していない。第三者コード・ライブラリは追加していない。全5新規ファイルを `git diff --no-index --check` でも検査し、空白エラーはない。外部JSONLの形式確認は合成データだけであり、実測ではない。重複試行・診断と通常の混在指定を拒否することも確認した。


## 5. 自動試験の正確な名称

下記は基点ソースから抽出した一覧である。Aのtestは全体、runtimeはホスト接続の明示的再実行、plainはdebug=falseである。plainはReleaseFastの意味ではない。

### src/tests/task_cancel_memory_test.zig

- `1373 job reads input writes result and isolates dictionary writes between jobs`
- `1373 every admitted memory builtin preflights before operand mutation`
- `1373 worker memory rejects protected regions overflow and native budget before effects`
- `1373 actual heap payload grant excludes its header free blocks and locals`
- `1373 native cancellation checks immediately before and after bounded memory work`
- `1373 memory gate covers primitive builtin call_builtin and word fallback encodings`
- `1373 default native limit accepts 64 KiB and rejects the next byte without writing`
- `1373 admitted memory builtins preserve ordinary results on granted data`
- `1373 all memory primitive Ops reject protected operands unchanged`
- `1373 copied inline body colon call and string literal cannot bypass gate`
- `1373 direct worker denies host probes and bounds variable stack work`
- `1373 variable stack preflight accepts exactly 64 KiB and rejects next cell`

### src/tests/task_control_1384_test.zig

- `1384 native executeWord reentry keeps worker mode and token`
- `1384 worker wordInLoop fallback and synonym keep restrictions`
- `1384 pending cancellation prevents native and data entry effects`
- `1384 scopes restore tokens across nested VMs and calling threads`
- `1384 worker rejects unverified DO family before operand consumption`

### src/tests/task_control_w1_test.zig

- `W1 cross-thread cancellation of BEGIN AGAIN without counted execution`
- `W1 worker ignores step_limit and keep_counting in debug configuration`
- `W1 cancellation survives nested colon frames and specialized operations`
- `W1 cancellation survives inline expansion inside a loop`
- `W1 native reentry retains an already active worker context`
- `W1 cancellation propagates through interpreted and compiled outer CATCH`
- `W1 pending cancellation is checked at loop entry and has a registered code`
- `W1 provisional exclusions reject dynamic execution and PAD`
- `W1 worker diagnostic registry refuses callbacks`
- `W1 rejects source interpretation and FAST-THROW at word and compiled boundaries`
- `W1 ordinary numeric minus 282 THROW remains catchable`
- `W1 successful worker entry restores ordinary VM context`

### src/tests/task_examples_test.zig

- `1380 public cancellation release and BYE reclaim every host allocation`
- `1380 public G1 replacement is accepted and expires while released runner is stop-unconfirmed`

### src/tests/task_ledger_test.zig

- `ledger capacity includes released running and unreclaimed terminal records`
- `ledger identity validation follows ResourceTable order and never wraps`
- `ledger terminal is immutable and cancellation is independent of outcome`
- `ledger RELEASE rejects external operations but preserves internal completion and refs`
- `ledger owner ending retains released and stopped-unconfirmed work`
- `default ledger has exactly sixteen slots including private reservations`
- `owner ending preserves terminal state and created rollback with outstanding refs`
- `ledger rejects invalid transitions without changing records`
- `ledger queued failure is separate from cancellation and execution completion`
- `ledger execution slots remain occupied until physical stop and submissions stay open`
- `sixteen slots count mixed states and released running records`

### src/tests/task_paint_test.zig

- `paint registration validates backend window and fixed target`
- `paint close reopen capability loss and notifications are retained`
- `paint notification failure stays observable`
- `paint lifetime generation exhaustion refuses registration`
- `POSIX drawing child pipe shares wake without consuming child input`
- `POSIX extra fd alone and cancellation after wait precheck`

### src/tests/task_permissions_test.zig

- `worker admission accepts optimized arithmetic BEGIN and recursive static calls`
- `worker admission rejects direct and indirect forbidden definitions`
- `worker admission decodes actual Op dispatch and inline bodies`
- `worker memory contract requires grants bounds write permission and native budget`
- `protected worker regions cannot be granted even for reading`
- `worker denies every non-admitted control operation in copied code`
- `worker builtin forms cannot hide forbidden implementations`
- `worker rejects protected overlaps before accepting payload grants`
- `worker admission rejects dirty state and counted settings individually`
- `worker admission covers word kinds strings malformed guards and builtin escapes`
- `worker admission checks compiled string and abort quote bodies`
- `worker gate invokes supplied checker and enforces total native budget`

### src/tests/task_public_api_test.zig

- `public Forth task lifecycle copies, short retry, nonconsuming and stale IDs`
- `public submission rejects missing and forbidden entries before acceptance`
- `public argument THROW preserves inputs and does not initialize host`
- `public handles are process unique and bound to the source VM`
- `public many wait returns duplicate clock events in index order and timeout together`
- `public failed ABI has nonconsuming diagnostics and no successful result`
- `public cancellation and release retain resources until worker handback`
- `public limits, busy capture, unavailable capability and exhausted identities`
- `public task operations reject the worker thread and missing host`
- `public many wait preserves inputs on Ctrl-C equivalent and combines IO reasons`
- `public host errors retain fixed outputs; capability absence does not register`
- `public old snapshot values survive ordinary writes and REPL recovery`
- `public allocation failure distinguishes exhausted budget from allocator failure`
- `public diagnostic adapters preserve queue expiry and stop codes without changing terminal state`
- `public VM execution exception is a diagnostic, not a failed state query`
- `public worker VM partition counts State and every Storage allocation`
- `public paint many validates arguments, backend, lifetime and simultaneous events`
- `public paint real native window wait (opt in)`
- `terminal wait releases snapshot version slot before another capture`

### src/tests/task_queue_test.zig

- `task queue bounded waiting cancellation release expiry and next sweep publication`
- `task queue deterministic host win and worker win repeated; notification recovery and join`
- `task queue deterministic cancellation before receipt and after runner entry`
- `task queue unresponsive retains worker slot and stop retains running completion`
- `task queue clock fault and per item deadlines are distinguishable`
- `task queue worker expiry and runner failure cancellation preserve diagnostics`
- `task queue failed completion notify recovers from real host Wake wait`
- `task queue private kick failure recovers and unstarted join succeeds`
- `task queue worker clock and wait faults retain cause and fail queued work`

### src/tests/task_reap_test.zig

- `reap every exit cause closes admission, releases queued records exactly once`
- `restore busy is nonmutating and retained references block collection`
- `running timeout retains storage and late handback is joined and reclaimed`
- `owner collection leaves other owners and shared worker available`
- `idle complete restore keeps host and worker open`
- `fresh VM result and shared Snapshot survive until reaper disposal`
- `main host hook handles QUIT ABORT BYE and rejects busy restoration`
- `unbound hooks and REPL typo preserve tasks`
- `finish uses real common Wake`
- `owner exit grants a fresh collection deadline and retains terminal refs`
- `terminal is published before retirement; collection and next execution wait for cleanup`

### src/tests/task_reap_reproduction_host_test.zig

- `1376 actual Execution cancellation then fresh VM successes and failure on one Queue`
- `1376 unreturned runner retains Budget Snapshot ledger and diagnostics until late return`
- `1376 production disposal matrix seals success failure cancellation RELEASE owner and BYE once`

### src/tests/task_results_test.zig

- `task results boundaries, retry and non consuming reads`
- `task results aggregate reservation and release`
- `task results failure and cancellation discard partial result and retain diagnostics`
- `task Writer exact limit, sticky overflow and cancellation precedence`
- `task results VM copy integration and allocation rollback`
- `task diagnostic boundaries and Writer shared budget failure`
- `task Writer preallocation, byte writes and successful output ownership`
- `task Writer worker handback and partial reservation lifetime`
- `task Writer empty output owns full reservation until completion destruction`

### src/tests/task_schedule_host_test.zig

- `stop deadlines retain resources and late handback restores worker`
- `shutdown preserves active storage and reports fatal exit until late return`
- `three rapid replacements survive coalesced wakes and cancelled runner handback`
- `three replacements when worker acquires the proposed waiting replacement`
- `schedule binding derives worker and dependency denial without caller flags`
- `schedule binding replaces FIFO cancels real queue and keeps failure atomic`
- `schedule binding rejects stale late success and completed results after replacement`
- `schedule binding ledger exhaustion throttles reads and collection resumes admission`
- `schedule binding stopped-unconfirmed VM accepts waiting work and expires it`
- `schedule binding bounds combined copies and gates final publication by generation`
- `schedule binding owner kind and stream isolate replacement and copying`
- `schedule queue acquisition race preserves old work when append fails`
- `schedule binding splits result diagnostic boundary within shared copy budget`
- `schedule binding rejects real worker runner outside any Forth execution scope`
- `schedule binding rejects foreign queue jobs without undefined behavior`
- `shutdown deadline ignores old stopped cancellation diagnostic`
- `handback synchronization rejects stale unresponsive mark before collection`

### src/tests/task_snapshot_test.zig

- `snapshot immutable versions resolve local entry after main changes`
- `snapshot FORGET and MARKER reject admission but keep running version alive`
- `snapshot complete restore invalidates only after successful preflight`
- `snapshot error abort and quotation abort do not change structural epoch`
- `snapshot typed and State append invalidate old versions`
- `snapshot library rollback invalidates previously captured epoch`
- `snapshot VM reference outlives external and admission owners`
- `snapshot fresh restore cannot inherit main host callbacks or runtime resources`
- `snapshot allocation failures release capture workspace plan storage and references`
- `snapshot rejects unrelated owners and fails closed on epoch exhaustion`
- `snapshot capture rejects each incomplete transaction state`
- `snapshot image byte limit accepts equality and returns reservation on failure`
- `snapshot manager counts versions through final admitted reference`
- `snapshot capture rejects open quotation and compile-only state at input boundaries`

### src/tests/task_state_machine_test.zig

- `1367 T02-T04 T06-T08 T11 T13 T18-T20 execution CANCEL RELEASE ordering matrix`
- `1367 T01 T03 T07-T10 T12 T15-T17 queue host wins expiry identity and owner exit`
- `1367 T08 T12-T14 T17-T18 worker wins owner exit retains released active and four waiting`
- `1367 T19 result limit fails before publication while destination shortage preserves success`
- `1367 T09-T11 coalesced lost repeated notifications ledger reference model and RELEASE recheck`
- `1367 T01 T17 stale admission rolls back while admitted queued snapshot executes`
- `1367 T03 T08 worker acquisition before entry cancellation release owner exit and expiry`

### src/tests/task_transfer_test.zig

- `task transfer executes byte ABI and owns input and result independently`
- `task transfer zero length including exact data limit`
- `task transfer input failures do not mutate caller bytes HERE stacks or destination`
- `task transfer distinguishes result ABI diagnostics without consuming stacks`
- `task transfer rejects forbidden regions even for empty ranges and crossing data end`
- `task transfer checks every active preflight category before installing input`
- `task transfer input and result limits are independent and static data is copied`
- `task transfer result allocation failure preserves VM for retry`
- `task transfer enforces product ceilings and stopped result state`
- `task transfer aligns odd HERE and input and invalidates overwritten address records`
- `task transfer checks borrowed and diagnostic preflight fields`

### src/tests/task_wait_host_test.zig

- `registration preserves simultaneous source deadline and cancellation, detach retains state`
- `native wait adapter instantiates and false clock deadline does not sleep`
- `task wait sleep uses absolute clock and task publication is acquired without consuming`
- `POSIX signal self pipe joins common native wait without handler calling Wake`
- `input wait peek retains events and decoder deadline`
- `borrowed common Wake survives failed native producer cleanup`
- `sleep rejects a foreign Wake and observes publication without recovery clock`
- `cancellation and user interruption remain independent`

### src/tests/task_wait_reproduction_test.zig

- `1372 W01 W02 W03 scripted publication boundaries retain readiness and paint`
- `1372 W09 sealed return excludes detach publication and next registration retains it`
- `1372 W04 W05 W06 W14 coalesced hints preserve full set and independent flags`
- `1372 W16 synthetic scheduler events retain quotas rotation and WAIT deadline`

### src/tests/task_wait_reproduction_host_test.zig

- `1372 T09 T10 production WAIT timeout interruption leave queue and ledger unchanged`
- `1372 W07 W08 real queue expiry and released publication survive absent common notify`
- `1372 W01 W04 W06 production input task clock and paint retain simultaneous state`
- `1372 T10 W08 release before terminal return reports released and reconciles cancelled`

### src/tests/task_job_test.zig

- `task job releases every allocation on success failure and requested cancellation`
- `task job results outlive final snapshot reference and jobs do not share state`
- `cancellation at every setup boundary stops before the next stage without leaks`
- `queue retirement owner releases every allocation on success failure and OOM`
- `second allocation zeroing and State initialization chunks cancel without leaks`
- `snapshot version slot is reusable with retirement destruction withheld`

## 6. 旧版作成時の作業ツリー（履歴）

HEADは `6a1b387009e8af9adc27730644becc8b1b748a21` のままである。既存の追跡ファイルに変更はなく、新規5ファイルを未コミットで残す。Git commit・branch・push・タグ・tque変更、Linux実行、本測定は行っていない。

```text
?? docs/TASK_CONTROL_ACCEPTANCE_MANUAL.ja.md
?? docs/TASK_CONTROL_ACCEPTANCE_MANUAL.md
?? docs/TASK_CONTROL_ACCEPTANCE_PLAN.md
?? docs/TASK_CONTROL_IMPL_1382.md
?? tests/scripts/run-acceptance.py
```

## 6. 測定前レビュー11点の確認と対応（2026-11-24）

11点とも根拠を確認し、指摘を誤りと判断した項目はない。以下が現在の状態であり、前節までの旧作業ツリー・旧smokeの記述に優先する。

| 番号 | 確認結果と修正 |
|---|---|
| 1 | 直前に期待値を計算する手順は改変検出にならなかった。下記と英日手順書は固定した文字列を使う。計画を-textにし、core.autocrlf=true / input / no-filtersで同じGit blobになることを確認した。Linux実機のSHA照合はClaudeが下記で実施する |
| 2 | latest一致だけを待つと取り逃して無期限に近い待ちになった。通過済み不一致は即phase_missed＋取消し、未観測は250msで親が打切り。最初の3試行に有効な要求がなければ残りを省略し欠測にする。下記の事前確認を加えた |
| 3 | responseもprobe buildになっていた。通常ビルドを別に生成し、response専用の実行体パスとSHAを保存。fixtureの1 MSも外した。親受信は引き続きpipeとschedulerを含む上界 |
| 4 | 生成段階は要求時latestが対象から進んでいれば除外する。100試行を100有効標本としない。所要時間表にも欠測の扱いを記した |
| 5 | 0の終点が黙って飛ばされていた。stopped/published/reclaimedの欠落、適用対象の区間の不正な始終点、task行なし、位相不一致、イベント喪失をmissingへ理由付き保存 |
| 6 | 10msだけでは短命なVMを取り逃す。メモリ専用に、Snapshot画像＋workspace、entry検証workspace、workerの各段階の初回、結果コピー後grants解放前を保持して親が採取確認してから再開する。Snapshot3世代にも保持点を置いた。基準は同じmainデータ＋service初期化＋Snapshot1世代を保持した最後のBASELINE-READYの標本。起動途中の最大を混ぜない。停止点の速度統計は作らない。I1診断で-313（待機期限切れ）を確認し、メモリ専用runだけ待機期限を120秒に延長する |
| 7 | 同一区間だったsnapshot_ready_nsを削除。snapshot_image_bytes（4MiB）、queue_waiting（4件）をLIMITSと結果表へ追加。単位もbytes/countに分けた |
| 8 | 要求と境界が同時刻ならunresolved-tieとして欠測にする。隣の位相に割り当てない |
| 9 | AUTOに変更したZigファイルを確認するfmtを追加した |
| 10 | JSONLは群ごとに1回開き、fixtureのSHAはcaseごとに1回だけ計算する |
| 11 | 対照Aのコミットとビルド条件を下記に固定した |

メモリ停止点は保持資源の取り逃しを防ぐためのものであり、OS内部の一時割当てやページ常駐の絶対最大の証明ではない。128MiBの厳密な上限についてはallocator境界試験とOS側の証拠を併せて評価する。

## 7. 再固定とClaudeの最終コマンド

計画をv3へ改訂後に再固定したSHA-256：`7b341c1b6f6b12eeab2c6aa5bf31f24cde48c4e8bb555a89856744496dfc6032`。
計画そのものに自己ハッシュは書かず、本報告書の文字列を期待値にする。測定直前に期待値を再計算しない。改訂した場合は改訂理由を記録し、再レビュー・再固定後の新しい文字列へ置き換える。

Windows PowerShell、cwd `D:/tmp/forthz-1382`：

```powershell
$planHash = '7b341c1b6f6b12eeab2c6aa5bf31f24cde48c4e8bb555a89856744496dfc6032'
if ((Get-FileHash docs/TASK_CONTROL_ACCEPTANCE_PLAN.md -Algorithm SHA256).Hash.ToLowerInvariant() -ne $planHash) { throw 'frozen plan mismatch' }
git check-attr text -- docs/TASK_CONTROL_ACCEPTANCE_PLAN.md
python tests/scripts/run-acceptance.py --only fmt test runtime plain docs
python tests/scripts/run-acceptance.py --mode smoke --only reclaim --probe-cases native-roll native-fill --repetitions 3 --plan-sha256 $planHash
python tests/scripts/run-acceptance.py --mode smoke --only workloads snapshot response reclaim memory --plan-sha256 $planHash
# 以下はClaudeによる本測定。REFはレモンの実行確認参照に置換する。
python tests/scripts/run-acceptance.py --mode measure --only reclaim snapshot memory workloads response --plan-sha256 $planHash --confirmed REF
python tests/scripts/run-acceptance.py --mode measure --only startup size --baseline .work/control-A/out/bin/sigma.exe --build-manifest .work/A-build-manifest.json --plan-sha256 $planHash --confirmed REF
```

Linux別機械、同じソース一式を置いたリポジトリのルート：

```sh
plan_hash='7b341c1b6f6b12eeab2c6aa5bf31f24cde48c4e8bb555a89856744496dfc6032'
printf '%s  %s\n' "$plan_hash" docs/TASK_CONTROL_ACCEPTANCE_PLAN.md | sha256sum --check || exit 1
git check-attr text -- docs/TASK_CONTROL_ACCEPTANCE_PLAN.md
python3 tests/scripts/run-acceptance.py --only fmt test runtime plain docs
python3 tests/scripts/run-acceptance.py --mode smoke --only reclaim --probe-cases native-roll native-fill --repetitions 3 --plan-sha256 "$plan_hash"
python3 tests/scripts/run-acceptance.py --mode smoke --only workloads snapshot response reclaim memory --plan-sha256 "$plan_hash"
# 以下はClaudeによる本測定。REFはレモンの実行確認参照に置換する。
python3 tests/scripts/run-acceptance.py --mode measure --only reclaim snapshot memory workloads response --plan-sha256 "$plan_hash" --confirmed REF
python3 tests/scripts/run-acceptance.py --mode measure --only startup size --baseline .work/control-A/out/bin/sigma --build-manifest .work/A-build-manifest.json --plan-sha256 "$plan_hash" --confirmed REF
```

両OSでSHA照合とtext: unsetを確認してから進む。Linuxのcheckoutで属性ファイルも同時に配布する。変更が未コミットなので、HEADだけを取得しても今回のソースにはならない。runnerのsource_manifestでWindows/Linuxの対象ソースを照合する。ロクはLinux実機の実行をしていない。

対照Aは[1386の記録](TASK_CONTROL_MEAS_1386.md)と同じW1導入前の `35523f676836134c4fbaed19e3d01d2a23ec2a92`。現在のworktreeのファイルを差し戻さず、次のように別のソース配置へ展開する（以下も未実行の引継ぎ手順）。既に同名ディレクトリがある場合はその内容を確認し、別名の新規ディレクトリを使う。

Windows：

```powershell
New-Item -ItemType Directory .work/control-A
 git archive --format=tar -o .work/control-A.tar 35523f676836134c4fbaed19e3d01d2a23ec2a92
 tar -xf .work/control-A.tar -C .work/control-A
 Push-Location .work/control-A
 zig build -Doptimize=ReleaseFast -Ddebug=false -Dstrip=true --prefix out -j2
 Pop-Location
 Get-FileHash .work/control-A.tar,.work/control-A/out/bin/sigma.exe -Algorithm SHA256
```

Linux：

```sh
mkdir .work/control-A
git archive --format=tar -o .work/control-A.tar 35523f676836134c4fbaed19e3d01d2a23ec2a92
tar -xf .work/control-A.tar -C .work/control-A
(cd .work/control-A && zig build -Doptimize=ReleaseFast -Ddebug=false -Dstrip=true --prefix out -j2)
sha256sum .work/control-A.tar .work/control-A/out/bin/sigma
```

Zig 0.17.1、OSごとのnative x86_64、既定語群・VM容量でA/Bをそろえる。Aにはtask-trace/task-acceptanceのオプションがないので指定しない。`.work/A-build-manifest.json`へAのコミット、archiveと実行体のSHA、Zig版・実体SHA、上記コマンド、target・語群・容量を記録してからstartup/sizeを実行する。このAはW1導入前との比較であり、1382直前との差だけを示すものではない。ブランチ作成・コミット・プッシュは不要。

通常のresponseと内部probeはrunner内で別ビルドになる。外部Bを指定する場合は単独のresponse runを通常ビルドで実行し、`--sigma`と`--build-manifest`で来歴を保存する。電源・CPU・背景負荷・端末/backend・表示周期の記録と、実画面・実端末の手動確認もClaude側で行う。

## 8. 修正後の所要時間の見積り

本測定は実行していない。旧v2の数秒というメモリ見積りは、停止点の追加後には使わない。計画上の固定時間と、短い動作確認の壁時間を分けて扱う。

| 項目 | 実行枠・見積りの条件 |
|---|---|
| 生成25位相＋native15位相＋待ち1 | 今回の41ケース1巡は0.884秒。※推測です：100巡換算約88秒は準備費用の下限で、位相観測窓は別。各100試行。生成は要求時latest不一致の試行が多くなりうるが、その試行も100回に含め、有効数は別に報告する。補充して100成功にはしない |
| nativeの観測待ち | ※推測です：全1500試行が各250msの窓を使う場合375秒（6.25分）＋起動・取消し・回収。最初3回が全て欠測の位相は最大0.75秒の観測窓＋その3回分の起動・回収で打切り。取消し後の障害は別途120秒guard |
| Snapshot | 100プロセス、各3取得。今回の1プロセスは0.048秒。※推測です：100回約4.8秒、ビルドは別枠 |
| OSメモリ7題材 | 各3回、基準と負荷を別起動。今回の7題材1巡は負荷12.096秒＋基準0.480秒、合計12.576秒。※推測です：各3回は約37.7秒（ビルド別）。各段階の初回停止＋親のOS採取・確認を含む。メモリ保持の時間を速度標本に混ぜない |
| G1の3形状/G2/T1/I1 | 6×600秒＝60分/OS。完了処理・起動終了は別枠 |
| 入力→状態 | 今回の注入と終了は0.016秒。600秒＝10分/OS。通常ビルド、pipe受信の上界 |
| 起動・サイズ | A/B各5 warmup＋100試行、サイズ各1。※推測です：旧smoke換算で起動約3秒＋ファイル読取り数秒。ただしAのビルド、環境記録、逆アセンブル確認は別枠 |

対話だけで70分/OS。※推測です：native観測窓を全て使う場合、これに最大6.25分と短い試行の起動・回収・メモリ保持費用を加える。ビルド、事前確認、異常時guard、80%超過時の追加試行、手動確認は含まない。Linuxの壁時間は未採取であり、Windowsの費用をLinuxの実測として扱わない。

## 9. 今回の最終検証

検証結果は以下に追記する。本測定、Git commit・branch・push、tque変更は行っていない。

Windows PowerShell、Zig 0.17.1で以下を確認した。

| 検査 | 結果・証拠 |
|---|---|
| `zig build test` | 成功、25/25 steps、1655/1688 tests成功、33 skip。`.work/review-final-test.log` |
| `zig build runtime-test` | 成功、8/8 steps。`.work/review-runtime.log` |
| `zig build -Dtask-acceptance=true` | 成功、11/11 steps。`.work/review-build.log` |
| `python scripts/check-docs.py` | findings 0。計測以外のTASK公開契約・英日説明に変更がないことを確認し、source指紋を更新。`.work/review-docs.log` |
| 変更したZig 10ファイルのfmt | 成功。build.zig、runtime_base、task_memory、task_queue、task_trace、task_acceptance、task_job、task_snapshot、host_task_api、main。AUTOのfmtも成功：`20261124T102928Z-77a5adc6` |
| Python構文 | 3スクリプトのpy_compile成功 |
| メモリsmoke | `20261124T102935Z-76b58a10`：7題材成功。基準は各2停止点（最後がBASELINE-READY）、G1各形状/G2/T1は各36点、I1は199点、Snapshotは4点。全確認数がログと一致、OS採取エラーなし。I1の5結果を確認 |
| native事前確認 | `20261124T103054Z-caec7c93`：ROLL/FILL各位相3回、計18試行、0.721秒。FILLの実行区間以外は最初の3回が欠測として記録された。これは到達性の形式確認であり、速度・受入れ合格ではない |
| 取消し/Snapshot/最大題材smoke | `20261124T103056Z-5d49133e`：取消し41対象、Snapshot3取得、6題材の結果検証が終了。取消しのnative位相欠測11件も保存。6題材合計0.967秒 |
| response通常ビルドsmoke | `20261124T103022Z-10660c75`：task-acceptance=falseのReleaseFast。入力marker確認、q終了、管理時間ログなし、input_state_nsはnull |
| 最初3回欠測の打切り | `20261124T103148Z-2c38ad62`：ROLL直前に5回を要求し、3回だけ実行、残り2回を省略した理由がmissingへ残ることを確認 |
| 集計の境界条件 | `.work/review-edits/check-aggregation.py`：子プロセスを起動しない合成データ検査。0およびキー自体が欠けた終点が理由付きmissingへ入り、同時刻がunresolved-tieになることを確認。本測定の実行ではない |
| 固定照合・改行 | 不正な固定SHAをsmokeに渡しbuild/probe前の拒否を確認。計画のtextはunset。core.autocrlf=true、input、no-filtersともGit blobは`6bb60e2749190c885b72722204d00e62137de1f3`で一致。Linux実機のSHA照合手順は7節 |
| 非測定性 | 最終smokeの内部時刻は0、入力時間はnull、速度統計は空。計画のSHAは再固定値から不変 |

途中の失敗も保持した。`20261124T102139Z-0fe2cb14`は同段階の反復停止を初回だけに修正する前のtimeout。`20261124T102425Z-70bec47c`のI1は停止による待機期限切れで、`.work/review-I1-diagnostic/diagnostic.raw.log`のDIAGNOSTIC-CODE=-313で確認した。`20261124T102703Z-0e03b1ad`では不要な管理ログの増大と全ログ再読取りが問題になり、メモリ専用の時間ログ抑制と追記部分だけの読取りへ修正した。初期AUTO fmtの全src走査は既存ファイルの改行でも失敗したため、要求どおり変更Zigだけを対象にした。これらの失敗runを最終成功runや速度標本へ合算していない。

本測定・Linux実行・Aの新規ビルド・実画面/実端末の受入れ確認は未実施。git commit・branch・push・タグ・tque変更は行っていない。

## 10. Windows の本測定の結果と分析

### 10.1 対象と判定の範囲

2026-11-24 19:34〜20:48 JSTに実施されたWindows本測定を、今回ロクが保存済み生データとコードから分析した。証拠は次の2 runである。

- 本測定：`.work/acceptance/20261124T103616Z-d293af93/`（以下「本run」）。`results.json`、各caseのJSON/raw.log、生成済みfixtureを照合した。
- 起動・サイズ：`.work/acceptance/20261124T114824Z-42f4b3be/`。本節の内部時間へ合算していない。
- 両runの固定計画はv3、SHA-256 `7b341c1b6f6b12eeab2c6aa5bf31f24cde48c4e8bb555a89856744496dfc6032`。今回も原本の一致を確認した。追記前の現在ソースは本runのsource_manifestの全ファイルと一致した。本測定実行体はSHA-256 `5b38b41af15cadfc080956b8fb9961188e3c0e2241583f41a868f0fbdc6ba221`、ReleaseFast/debug=false/task-trace=false/task-acceptance=true。

既存の7〜9節の「本測定は未実施」は当時の引継ぎ時点の記録であり、現在のWindowsの状態は本節による。Linuxは別機械で進行中とのレモンの情報による。Linuxの結果は本節へ混ぜていない。runner自身のacceptance_verdictはnot-evaluatedである。本節でも全体合格とはしない。v3の縮小試行と利用条件8節の正式な出発回数は区別する。

再集計と短い調査の証拠を `.work/windows-analysis/` に保存した。`analyze.py`/`raw-analysis.json`はcase別の終点差分、`details.py`/`details.json`は最大標本周辺の管理巡、`summary.py`はrunnerの統計と追加対象、`check.py`は位相の照合に使った。nsを1,000,000で割りmsとした。中央値とp95は計画どおり。今回の調査用値は本runの標本数・最大・合否に加えていない。

### 10.2 T1：1 MiB検索の投入→公開

本run `workloads-T1-none-0000.json` の1,037件すべてが200msを超えた。投入→公開は中央値460.6821ms、p95 473.7523ms、最大503.0903ms（task 252）。投入→runner帰還は最大標本で503.0900ms、帰還→公開は0.0003msである。帰還→公開の全標本最大も0.0011msにとどまる。従って公開直前の処理だけで約300msの超過が生じたわけではない。

**本測定の内訳には保存上の限界がある。** `task_acceptance.Storage`が時刻として保存するのはsubmitted/requested/stopped/published/reclaimedとnative境界である。生成段階はseen/latestだけで、各段階の時刻配列はtask-trace専用である。本runには次の値を後から復元する情報がない。

| 区間 | 本runから確認できる範囲 |
|---|---|
| admission・ホスト入力コピー・実行待ち | submitted→stoppedに含む。取得(acquired)時刻がないので個別のmsは未分離。queue_waitingは全件1で、先行T1の完了・release後に次を投入するfixtureである。待ち100msを実際に消費した意味ではない |
| VM生成・初期化・Snapshot復元・許可検査 | submitted→stoppedに含む。個別の時刻は未保存 |
| 入力のコピー | `Service.submit`の入力複製と、`task_job.runWithOptions`のVM領域へのprepareInputの2箇所。両方とも投入→公開に含むが、個別の時刻は未保存 |
| Forthの計算 | runAsWorkerWithMemory→forth_return。個別の時刻は未保存 |
| 結果のコピーと実行参照の後始末 | forth_return→runner_returnに含む。結果は8,032 bytes、個別の時刻は未保存 |
| seal・公開 | stopped→published。中央値0.0003ms、最大0.0011ms |

短い調査では本runと同じ実行体で、元の1回検索と、検索をせず同じサイズの結果領域を返す調査用入口を各3回交互に実行した（`prepare.py`、`compare.py`、`comparison.json`と各raw.log）。元の投入→公開は515.0765 / 550.5199 / 513.1212ms、調査用入口は6.0325 / 6.0502 / 7.4135msだった。調査用入口の件数メタ情報は検査通過用の固定値であり、検索の正しさや改善版の性能を示さない。別の診断ビルド作成と並行した条件であり、本測定と速度を直接比較しない。※推測です：同じ1MiB入力とほぼ同じSnapshotで検索ループを省くと大きく短縮したことから、Forthの計算が支配的であり、VM準備だけでは本runの長さを説明しにくい。

さらに別ビルドの06-H traceで、元のT1を独立プロセス3回実行した。証拠は `.work/windows-analysis/trace.py`、`trace-T1.json`、`trace-T1-0/1/2.raw.log`。task-trace=true、task-acceptance=falseであり、本runの統計には混ぜない。observed/host_stoppedに同じtaskの記録が出るので、observedだけを採用し二重計上していない。

| 診断用区間（ms） | 試行0 | 試行1 | 試行2 |
|---|---:|---:|---:|
| acquired→vm_start（worker入口） | 0.0061 | 0.0055 | 0.0047 |
| vm_start→initialized（VM生成・初期化） | 0.1194 | 0.1510 | 0.1042 |
| initialized→restored（plan作成・検証・復元） | 3.1326 | 3.1364 | 2.9775 |
| restored→permissions_checked（plan解放・解決・許可検査等） | 0.0180 | 0.0215 | 0.0168 |
| permissions_checked→input_ready（VMへの入力コピー） | 0.2900 | 0.3006 | 0.2806 |
| input_ready→executing（実行準備） | 0.0053 | 0.0032 | 0.0031 |
| executing→forth_return（Forth実行） | 428.3929 | 431.0516 | 424.7783 |
| forth_return→runner_return（結果コピー・実行参照解放等） | 0.0147 | 0.0159 | 0.0158 |
| runner_return→published（seal・公開） | 0.0002 | 0.0004 | 0.0004 |
| published→observed（ホストによる結果の観測） | 9.7614 | 2.6830 | 7.9093 |

この診断ではForth実行だけで200msを超え、主な費用が検索計算であることを確認した。ただし元の本測定1,037件それぞれのForth時間ではない。ホスト入力複製と実行待ちはtraceにもsubmit始点がないので未分離、結果コピーもその後の参照解放との合計であり単独値ではない。内訳を完全に分離するには、今後submit開始・ホスト入力コピー終了・enqueue・acquired・結果コピー終了の時刻を同じtaskに追加する必要がある。診断のtrace出力が公開後の観測・回収へ与える影響も含め、診断値を通常経路の受入れ値へ読み替えない。

入口は `tests/task/task-search-worker.fs` の `TS-SEARCH`。各開始位置TS-IについてTS-Jを0へ戻し、パターンの各byteをC@で逐次比較する。最悪O(本文長×パターン長)。今回の検索語は1byteのaなので比較回数自体は1,048,576回でO(n)だが、変数読書き、境界判定、アドレス計算、許可されたメモリアクセスの検査をForthの各反復で行う。全件を数える仕様なので、保存が1,000件に達しても本文末尾まで計算を続ける。保存上限を走査上限と読み替えることはできない。

取りうる改善は次のとおりである。いずれも今回、製品コードには実装していない。

- 1byte検索は許可集合のSCAN/SKIPで最大64KiB単位に走査する。特に今回の連続aではSKIPで連続一致の長さをまとめて数え、保存する先頭1,000件だけを展開できる。`task_permissions.zig`はSCAN/SKIPをmemoryとして許可し、`words_memory.zig`はnativeのbyte走査を行う。※推測です：全件一致の題材ではForth反復数を大きく減らせる。一般の交互一致では同じ効果を保証しない。
- 長い語にはKMP等の線形検索をBEGIN/WHILE系と私有作業領域で組む候補がある。※推測です：不一致の再比較を減らせるが、今回の1byte全件一致で計算量の次数は変わらず、実装後の検証が必要。
- 許可済みSEARCHも候補だが、1MiBを一度に渡せない。`task_memory.before`は2入力領域の合計と `text_length × max(1, pattern_length)` の両方を64KiB以下に検査する。境界をまたぐ一致・重複一致を保ちながら分割する必要がある。SEARCHは最初の一致だけを返すため、全件一致で毎byte呼び直すだけでは速くなると断定できない。実装は `std.mem.indexOf` を利用し、T1の手書き二重ループとは別である。

利用条件3節の題材は「テキスト1MiB＋検索語・版等、入力上限2MiB」であり、2MiBは本文を2MiBにする指示ではない。今回の入力は1,048,593 bytes（版・長さ16＋検索語1＋本文1,048,576）、結果は8,032 bytesで容量内である。入力停止100msのdebounceは投入前で、投入→公開200msとは別枠。待ち期限100msも総時間に追加できる猶予ではなく、投入→公開に含まれる。今回の固定fixtureは完了後100ms待って次を投入し、実キー入力のdebounce・最新版置換えそのものを再現していない。従って「入力が止まってから200ms以内」とも「10件/秒持続」とも主張できない。

現行題材で200ms未達は確定している。優先する対応は計算の改善と内訳計測の補充である。本文量、全件件数を返す仕様、目安200msを変える案は用途の変更になるため、**目安・題材・利用条件の見直しにはレモンの判断が必要**である。測定結果に合わせて自動的に緩和しない。

### 10.3 対話の公開→回収：11,796件の超過の所在

本runの各 `workloads-<case>-none-0000.json` の全task行を再集計した。

| 題材 | 標本 | 100ms超過 | 中央値ms | p95 ms | 最大ms |
|---|---:|---:|---:|---:|---:|
| G1-open | 3,140 | 3,139 | 111.7220 | 124.9577 | 139.9893 |
| G1-wall | 3,616 | 3,615 | 122.7581 | 125.6562 | 128.6635 |
| G1-snake | 3,491 | 3,490 | 115.9792 | 120.7751 | 125.5402 |
| G2 | 517 | 516 | 1,017.3548 | 1,025.8558 | 1,030.7657 |
| T1 | 1,037 | 1,036 | 117.9480 | 124.1525 | 127.1491 |
| I1 | 47,951 | 0 | 43.9849 | 55.1722 | 71.8721 |
| 合計 | 59,752 | 11,796 | — | — | 1,030.7657 |

**主因はrelease後の回収巡を題材の投入間隔待ちの後まで遅らせる構造である。** fixtureはAWで終端確認→TASK-RESULT→結果検査→TASK-RELEASE→100 MS（G2は1000 MS）→次のTASK-SUBMITと進む。`host_task_api`は各APIの処理前にpollする。TASK-RELEASEはそのpollの後にvalid=falseを設定するため、その同じ事前pollではまだ当該entryを回収しない。回収は次のAPI/pollに持ち越され、MSの間に必ずService.pollが走る構造ではない。最後の1件はその待ちを抜けるか、次のSnapshot解放・終了処理で回収されるため、各逐次題材の超過が標本数−1であることとも整合する。

G1のfixtureは置換えを連続実行していない。完了後に次を投入するため、この結果をG1最新版置換えの回収速度とは呼べない。I1は初回busy workerで待ち4件を作り、その後5slotをFEEDで確認・回収・補充し50 MS待つ。待ち4件の持続供給で常時4待ちを維持したわけではなく、queue_waitingの中央値2、p95/最大4だった。I1は今回の100ms超過の原因ではない。

最大標本を、公開から最初のpoll、release前の最後のpollから回収巡、回収巡内の残りへ分けると以下になる。厳密なTASK-RESULT入口・release完了時刻・VM解放開始/終了は保存されていないので、その代わりの観測境界である。

| 標本 | 生時刻(ns)と内訳 |
|---|---|
| G1-open task1793 | 公開262996361911600→最初のpoll262996394756500：32.8449ms。release前のpoll開始262996394770300→回収巡開始262996501873500：107.1032ms。そこから回収262996501900900：0.0274ms。計139.9893ms |
| G2 task167 | 公開264646532579000→最初のpoll264646547973600：15.3946ms。release前poll開始264646548009000→回収巡開始264647563303100：1,015.2941ms。そこから回収264647563344700：0.0416ms。計1,030.7657ms |
| T1 task252（投入→公開最大） | 公開265201375548000→最初のpoll265201390059300：14.5113ms。release前poll開始265201390084700→回収巡開始265201497997700：107.9130ms。そこから回収265201498047200：0.0497ms。公開→回収計122.4992ms |
| I1 task38640 | 公開266141042351600→最初のpoll266141096665500：54.3139ms。FEED内で他slotも扱い、回収巡開始266141114207000、回収266141114223700。公開→回収計71.8721ms。最初のpoll後の約17.56msをVM解放時間と断定しない |

公開後の最初のpollまでの中央値/最大はG1-open 2.2510/32.8449ms、wall 13.7849/16.4661ms、snake 6.4570/15.1116ms、G2 8.9528/15.3946ms、T1 8.5780/16.0249ms、I1 41.4034/58.8008ms。AWの `1 MS` は実測上1ms刻みを保証しない。TASK-RESULTで利用者領域へコピーし、ログ出力・結果検査・release・次巡までを含む総回収時間と、poll自身の実行時間を区別する。

06-Hで公開後に移したのは主にState/Storageの物理解放である。`task_job_queue.Execution.run`はRetiredを作り、帰還前にreleaseExecutionResources（画像・復元plan・Snapshot実行参照）を処理する。`task_queue.workerMain`はrunner_return→seal→ready公開→通知→Retired.destroy→cleaning解除と進み、その後に次taskを取る。hostはcleaningが消えるまでcollectしない。これによりVM物理解放は投入→公開から外れ、公開→回収へ入る。解放が次taskの実行開始を遅らせる場合、その待ちも次taskの投入→公開へ入る。

**本runにはRetired.destroyの開始・終了時刻がなく、VM解放そのもののmsは未分離である。** 最初のpollやcleaning状態の観測だけでは解放完了時刻を特定できない。ただし上表の約107/1,015msのpoll間隔は生データで確認でき、1秒の総時間をVM解放1秒と解釈する根拠はない。reclaim群も同じ解放順序を通るため、workloadsとの差をすべて06-Hの変更のせいにはできない。

reclaim群の最大91.6066msは `reclaim-cancel-return_allocated-0047.json` のtask3。公開262547811022900→最初の公開後poll262547902601800が91.5789ms、そこから回収262547902629500まで0.0277msだった。この標本も長いpoll不在が大部分で、VM解放91.6msを測ったものではない。要求262547810924100→回収は91.7054msだが、要求時latestは対象位相と異なり、この値をreturn_allocatedの有効な要求→回収標本として採用しない。一方、公開→回収は位相に依存しないためrunnerの統計に残っている。

D07との照合では、利用条件5節に取消しの「要求→回収100ms」、6節に別途「公開→回収100ms」がある。本runのpublish_reclaim_nsは後者の区間そのものであり、前者の代用ではない。始点はreadyのrelease-store直前、終点は物理handback確認後にtask台帳・結果・入力・名前・実行参照・VM・slotを解放した後。利用条件5節が別扱いとする外部ハンドルの小さな終端レコードも、この実装の終点ではrelease待ちにより含まれる。実行資源が先に解放されても終点は進まないので、要求→「外部記録を除く所有資源回収」の厳密な分離測定には不足する。独立して保持する公開Snapshot自体の所有参照と共有workerの終了joinはこの区間に含めない。

取りうる対応は、release後に次の管理巡を確保してから投入間隔を待つ、待機中にも有限周期で管理する、release後のcollectを安全な条件で進めることである。計測にはresult取得・release・VM解放・handback・poll入口を別境界として追加し、実資源と外部記録を分ける。計画の総区間を都合よく短縮して超過を消さず、現行生データの超過を残す。G1置換えは独立シナリオで確認する。**100ms目安の変更はレモンの判断が必要**であり、まず回収を遅らせる題材/ホストの構造を改善する候補を優先する。

### 10.4 待ち取消しの1件：54.4829ms

対象は本run `reclaim-queued-none-0026.json` / `.raw.log` のtask4。100件中1件が10msを超えた。要求262603723892300、公開262603778375200、回収262603778409700である。公開→回収は0.0345msだった。

要求を処理するAPIの事前pollは262603723892400〜262603723892800。要求時計からこのpoll開始までは0.0001msである。取消し処理を経て次のpollが始まるのは262603778374700で、前poll開始から54.4823ms空く。次poll開始から公開までは0.0005ms、次poll全体も0.0020ms。待ちから取り除かれたtaskはForth/nativeを実行しておらず、stopped=0が正常である。1件の54msをForth停止やVM解放の遅さとする根拠はない。

`task_queue.cancel`は待ちentryを除去・sealし、次host pollで公開する。従って「次巡で公開」はこの記録と整合するが、「かつ10ms以内」は未達である。※推測です：次巡までの遅れにホストのスケジューリング、API後のログflush/pipe出力、競合が関与した可能性がある。時計が示すのは空白の長さであり、保存済みログにはcontext switch・ready時刻・flush開始終了がないため、この候補間の特定はできない。ログ出力が計測区間の外でも、次の巡の開始を遅らせることはある。

対応候補は、取消しAPI帰還とflushの前後、待ち除去完了、次poll入口の時刻を追加し、必要ならOSスケジューラの記録を同時取得すること。待ち取消しの安全な即時公開または管理巡の期限管理もコード改善候補である。短い再現で外れ値が出ないことをもってこの1件を除外しない。**10ms目安や次巡の契約変更はレモンの判断が必要**である。

### 10.5 80%規則と追加試行

計画v3の6節は「最大が目標の80%を超えるcase/位相/metricだけ追加」であり、目標以内なら不要という規則ではない。今回の依頼は原因調査なので、以下の受入れ用追加試行は実行していない。実行時は元run・追加理由・固定条件を新runへ記録し、Linuxと合算しない。超過や欠測が既にある項目は、回数だけ増やして合格に転じるものではない。

| 項目 | 照合 | v3による扱い |
|---|---|---|
| G1-open投入→公開87.7227ms | 100msの87.72%。超過0 | 当該caseの10分を独立に2回追加。wall/snakeはこのmetricだけなら80%未満だが、公開→回収の超過により別途対象 |
| workloads公開→回収 | G1各形状/G2/T1はいずれも100ms超過 | 各case10分×2追加が規則上の対象。先に原因と計測/回収方法を整理。変更後の値を元の標本へ混ぜない |
| reclaim公開→回収91.6066ms | 100msの91.61%、超過0 | cancelのmemory_allocated（86.6619ms）、data_allocated（81.9347ms）、return_allocated（91.6066ms）、loops_allocated（81.6802ms）、storage_zeroed（87.0721ms）の各対象位相に追加1,000回。位相不一致の問題は別に残る |
| 待ち取消し終端公開54.4829ms | 10ms超過 | queued case追加1,000回の対象。位相指定なし。既存の1超過は保持 |
| Snapshot画像3,619,645 bytes | 4,194,304 bytesの86.30%。3.62MB＝約3.45MiB。超過0 | snapshot case追加1,000プロセス（各3取得）。時間ではなくbytesも規則の対象 |
| memoryのSnapshot画像3,619,732 bytes | 4MiBの86.30% | memory/snapshot case追加10回。通常snapshot群とは保持・初期化条件が異なるので別集計 |
| workloads/I1のqueue_waiting=4 | 上限4の100%、上限超過ではない | I1の10分×2追加。容量を使い切る意図した負荷でも、現行v3には80%規則の例外がない |
| memory/I1のqueue_waiting=4 | 同上 | memory/I1追加10回。時間の受入れ標本にはしない |

Snapshotの3.6MBは「大きな盤面の辞書」ではない。`snapshot` fixtureは共通AR結果領域524,288 bytesに加え、専用に `CREATE AI 3000000 ALLOT` を置く。3回の取得間に1 ALLOTずつ増やし、画像も3,619,643→3,619,644→3,619,645 bytesと増える。`task_snapshot.captureReserved`はmainの辞書/私有データをimage_encoderで保存するため、この3,000,000byteの私有データが含まれる。G1盤面fixtureの実画像はopen 2,003,047、wall 2,003,351、snake 2,003,863 bytesであり、3.6MBの値とは別である。4MiB画像境界そのものの確認でもない。memory群の87byte程度の差は別fixtureの定義・初期化条件を含むため、本測定snapshot群と同一画像と扱わない。

回数を増やしても同じ画像のbytesを反復確認する性質は変わらない。bytes/countを時間と同じ80%規則から外す、あるいは境界機能試験を別の確認へ置き換える案は再計画候補であり、**現行規則を事後に免除する判断・目安の見直しにはレモンの判断が必要**である。

### 10.6 生成位相の取り逃しとnative打切り

生成・実行対象25位相×100試行＝2,500のうち、要求時latestが一致したのは859、取り逃しは1,641だった。`phase_observations`のtarget/actualから再確認した。指定段階を通った事実(seen)と、その段階にいる間に要求した事実(latest一致)は違う。workerを止めるbarrierは設けず、メインのTASK-STATE巡でseenを確認して要求する。短い段階はこの間に進む。

具体例はframes_allocated→storage_allocated 98件、catches_allocated→storage_allocated 97件、storage_zeroed→storage_allocated 97件、initialized→plan_allocated 97件、restore_applied→restored 96件、input_ready→prepared 54件。初期化のチェック通過後に次段階へ進んだことがactualへ記録されている。※推測です：段階滞在時間に対してpoll・OSスケジューリングの間隔が長いことが取り逃しを増やす。保存データだけでは各要因の寄与率は分離できない。

| 有効数/100 | 生成・実行対象位相 |
|---|---|
| 100 | storage_allocated、executing |
| 97 / 96 / 95 / 92 | plan_allocated / restore_validated / grants_ready / restored |
| 79 / 76 / 58 / 45 | resolved / permissions_checked / plan_released / input_ready |
| 15 / 2 / 2 / 1 / 1 | return_allocated / snapshot_retained / loops_allocated / float_allocated / fresh_checked |
| 0 | vm_start、state_reserved、state_allocated、memory_allocated、data_allocated、frames_allocated、catches_allocated、storage_zeroed、initialized、restore_applied |

nativeは最初3試行に有効要求がない位相を計画どおり打ち切った。ROLL/SEARCHは直前・実行区間・直後すべて各3試行で有効0、各残り97を未実行にした。FILL/MOVE/COMPAREも直前と直後は同じ扱い。実行区間だけFILL 32/100、MOVE 91/100、COMPARE 94/100の有効標本がある。

ROLLのnative_running試行0はbefore262622839536200、running262622839536300、after262622839536800で、要求262622839574700はafterの37.9µs後だった。64KiB枠内の4,000cell移動自体の境界は非常に短く、スタックを作るForth反復や後処理の時点で要求している。SEARCHのnative_running試行1は要求262622449195700がbeforeと同値なのでunresolved-tie、試行2は要求262622495075000がrunning262622495075300より前で、実行区間ではなかった。試行0は時間境界だけなら実行区間に見えるがphase_missed=trueで採用されない。繰返し呼出しのbefore/running/afterが、hostのseen/latest確認と要求固定の間にも更新されるため、後から残った3時刻だけで取り逃しを成功へ救済しない。

native SEARCH題材はゼロ初期化された256byte領域同士で、最初の位置で一致しうる構造であり、256×256という許容仕事量が常に実行される題材ではない。ROLLも4,000cellの構築を毎回行う。※推測です：この短いnative区間と前後のForth処理の長さの差が、位相を取りにくくしている。測定不能は取消し不能・停止失敗の証明でも、当該位相の合格でもない。

要求→停止1,176件の内訳は生成/実行859＋native実行区間217＋queuedケースの先行busy worker100である。待ちから除去したtask自身のstoppedは0で、待ち取消し100件を停止標本へ重複加算していない。最大はplan_allocatedの1.6893msで10ms以内だが、**1,176件の合計では位相別の不足を埋められない**。v3でも各位相100「試行」であり100「有効標本」の保証ではなく、不足位相は受入れ未確認。正式な利用条件8節の各位相1,000回を完了したことにもならない。要求→回収も位相が合わない標本を採らず、公開→回収だけの標本数と区別する。

対応候補は、各位相を安全に観測できる診断用hook、要求時刻とnative呼出し番号を一体に保存する仕組み、OS側の要求発行記録、許可量内で滞在を確保する別の代表入力である。barrierで止める試験は境界の機能確認に使えても、無停止の取消し遅延の代替にしない。成功するまで無制限に補充しない。観測方法・題材・必要な位相別標本数を変える場合は先に再計画し、**必要標本数や利用条件の見直しにはレモンの判断が必要**である。

### 10.7 現時点の結論

Windowsの本測定では、T1の200ms、G1/G2/T1の公開→回収100ms、待ち取消し1件の10msが未達だった。回収の多発超過は題材の待ちと管理巡の構造で説明できる部分が大きく、VM解放時間そのものとは区別する。T1はForthの全件逐次検索の費用を優先して改善検討する。Snapshot 3.6MBとqueue_waiting=4は上限内だが、v3の追加規則に該当する。位相の欠測は残り、停止1,176件の合計をもって全位相合格にしない。今後の受入れ測定・Linux照合・実画面/実端末確認と、今回の調査用再現は別の作業である。

## 11. Linux の本測定の結果と分析

### 11.1 対象と再集計

提供された `.work/acceptance-linux/20261124T104746Z-72d85108/`（本測定）と `20261124T115919Z-67af5f0d/`（起動・サイズ）を読み直した。新しいLinux本測定は行っていない。集計スクリプトと結果は `.work/post-measure/analyze-linux.py`、`linux-summary.json`、最大回収標本の分解は `detail.py` に保存した。標本を除外せず、中央値は中央2値平均、p95はnearest rankである。計画原本のSHA-256は引き続き `7b341c1b6f6b12eeab2c6aa5bf31f24cde48c4e8bb555a89856744496dfc6032`。計画の定義・回数は変更していない。

| 題材 | 投入→公開の標本数 | 中央値ms | p95 ms | 最大ms | 目安超過 |
|---|---:|---:|---:|---:|---:|
| G1-open | 2,422 | 147.1180 | 148.8513 | 164.7216 | 2,422（100ms） |
| G1-wall | 3,308 | 80.7912 | 81.6600 | 90.7177 | 0（100ms） |
| G1-snake | 3,039 | 96.8086 | 97.7259 | 105.4204 | 15（100ms） |
| T1 | 576 | 941.2009 | 954.8613 | 965.9537 | 576（200ms） |

G1合計8,769件のうち2,437件が超過した。WindowsのG1最大87.7227ms・超過0と区別する。T1もWindowsより長いが、OS以外の機械・負荷条件まで同一とする根拠はない。

### 11.2 G1の区間と盤面の大きさ

**本runにはacquired、VM各段階、executing、forth_returnの時刻がない。従ってLinux本測定の待ち／VM生成／復元／計算／結果コピーの個別時間は、保存済み生データからは復元できない。** `task_acceptance` の時刻と `task_trace` の段階時刻は別物である。seen/latestを時刻の代わりにせず、Windowsの区間時間や旧06-Hの値をLinux本測定から差し引かない。

| 区間 | Linux本runで確認した内容 |
|---|---|
| 投入、入力のホスト側コピー、実行待ち | submitted→stoppedに含む。acquired/enqueue/copy終了の時刻がなく未分離。逐次完了後の投入であり、待ち期限100msを消費した意味ではない |
| VM生成・初期化 | 同じ区間に含み未分離。State、Storageの各配列、初期化の個別時刻なし |
| Snapshot検証・復元、許可検査、VMへの入力コピー | 同じ区間に含み未分離 |
| Forth計算 | 同じ区間に含み未分離 |
| 結果のコピーと実行参照解放 | 同じ区間に含み未分離。open結果2,060 bytes、wall 16 bytes、snake 131,600 bytes |
| 公開（runner帰還→ready公開） | open中央値0.085µs・最大0.448µs、wall中央値0.088µs・最大13.150µs、snake中央値0.085µs・最大23.489µs |

帰還→公開の最大でも0.024ms未満なので、公開の最後の操作がopenの約65msの超過を生んだとは説明できない。

盤面別の照合では、本runのopen/wall/snakeは**全て256×256、65,536セル、入力65,568 bytes**である。64×64・128×128のLinux本測定標本はない。このため「大きさ別」の本測定表は256の1行しか作れず、形状差をサイズ差として扱えない。形状別にはopenとwallの中央値に約66.327msの差があるが、異なるプロセスの値であり、この差をそのまま計算時間とは呼ばない。

※推測です：同じ盤面寸法でも探索量の多いopenが全件超過し、wallは超過しないことは計算費用の影響を示唆する。一方、VM生成・復元も計測されていないので、計算だけが原因ともLinuxの確保だけが原因とも確定できない。推測を重ねず、下記の短い段階診断で確かめる。

06-Hの旧Linuxログ `docs/06h-linux-trace.log` ではvm_start→restoredが約38.6〜39.3msだった。ただし取消しを含む旧経路・旧条件の診断で、本runの成功taskの内訳ではない。現行の内訳は `TASK_CONTROL_INVEST_06H.md` の表のとおり、State確保、Storage各配列確保、必要時のゼロ化、State初期化、Plan確保、復元検証、復元反映、Plan解放、許可検査へ分かれる。OS確保、最初のページ接触、実メモリ書込み、OSでの実行待ちは各段階の時間に入り、段階記録だけでもこれらを個別には分けられない。

確保・復元が支配する場合の対応候補は、長い単独段階の分割、Snapshotの検証結果の安全な再利用、必要容量を減らす設計、OSの新規ゼロページ保証を保った確保経路の確認である。容量変更や検証結果再利用は所有権・1361の転送契約を再確認してから判断する。使用済みVMの無条件再利用、未ゼロ化領域の返却、許可検査省略は採用していない。runtime safety有効時のundefined書込み・明示ゼロ化と、ReleaseFast/debug=falseの経路を混同しない。OS要因の特定が必要ならClaude側でpage fault／スケジューラの記録も採る。

計算側では、`TP-SEARCH` の親配列初期化が全セルをForthで反復している。許可集合内のFILLを最大65,536 bytesずつ使えば、全セルを-1にする意味を保てる。今回は実題材を変更せず、診断候補として `diagnose-task-workloads.py --parent-fill` で比較できるようにした。幅64/128/256・3形状の結果件数チェックを通した。Windowsの各1回の計算部分は下表であり、環境変動を含む参考値で、Linuxの改善量でも受入れ値でもない。

| 幅 | open 元／FILL ms | wall 元／FILL ms | snake 元／FILL ms |
|---|---:|---:|---:|
| 64 | 4.3537 / 4.0186 | 2.2260 / 2.0720 | 2.8340 / 2.6925 |
| 128 | 17.5145 / 16.5782 | 9.3060 / 8.2769 | 11.6177 / 11.0065 |
| 256 | 71.0196 / 66.4664 | 37.8399 / 33.5437 | 47.1151 / 43.8481 |

証拠は `.work/post-measure/stages/` と `parent-fill/` のfixture・raw.log・summary.json。各1回の比較なので改善の保証にはしない。ほかに訪問済み判定を先にして盤面読出しを減らす候補がある。探索順を保った親・キュー操作の削減も候補だが、経路そのものの一致の追加検証が必要。Linuxの段階診断前に探索方式を変更して原因を覆い隠すことはしていない。

### 11.3 公開→回収と待ち取消し

| 題材 | 公開→回収標本数 | 100ms超過 | 中央値ms | p95 ms | 最大ms |
|---|---:|---:|---:|---:|---:|
| G1-open | 2,422 | 2,421 | 100.8195 | 101.3379 | 104.1223 |
| G1-wall | 3,308 | 3,307 | 100.8530 | 101.3385 | 101.6141 |
| G1-snake | 3,039 | 3,038 | 100.9063 | 101.3490 | 116.4071 |
| G2 | 472 | 471 | 1,000.8768 | 1,001.3562 | 1,001.5123 |
| T1 | 576 | 575 | 100.8692 | 101.3836 | 101.5115 |
| I1 | 52,531 | 0 | 26.3734 | 44.9566 | 51.5532 |

合計9,812件超過。各逐次題材で標本数−1の超過であり、Windowsと同じrelease後の待機構造を確認した。最大回収標本での「公開→最初のpoll／回収巡の直前poll→回収巡開始／回収巡開始→回収」は、G1-open task822で3.881908／100.183108／0.045703ms、G2 task44で0.955935／1,000.193323／0.348821ms。VM解放が1秒掛かった値ではない。VM解放自体の開始・終了時刻はなく、厳密なfree時間は未分離のままである。

待ち取消しは100件、要求→終端公開の中央値3.282µs、p95 3.532µs、最大6.166µsで10ms以内だった。Forthを実行しない待ちtaskのstopped=0を欠測扱いせず、先行busy workerと区別した。

起動・サイズの別runはstartup/sizeともrecorded。起動は各100件、親のmarker受信までの中央値A 0.895740ms／B 0.895050msで、内部起動時間ではない。ELFはA 2,380,304／B 2,539,424 bytes、.textはA 1,279,043／B 1,386,467 bytes。逆アセンブル・D01・AC-29全体の受入れを完了した意味ではない。

## 12. 測定後の改善

### 12.1 題材のメイン巡とD07

`acceptance-fixtures.py` にゼロ時間の時計targetを使う `TASK-WAIT-MANY` の管理巡ATICKを追加した。100ms／1000ms（I1は50ms）の供給間隔はAPACEで絶対期限として保ち、その間に次のメイン巡を進める。最初の管理巡はrelease直後、sleepより前である。VMのcleaningが残る場合も待機中の後続巡で回収できる。1 MSの呼出し回数を100回固定する方式にはせず、Windowsのsleep粒度によって供給間隔が約1.5秒になることを避けた。OSによる期限超過はあり得る。

`tests/task/task-console.fs` でもTC-POLLの先頭で管理巡を進める。これにより結果をreleaseしてTC-JOB=0となった後も、次の表示・入力の巡で回収を進める。回収のための新しい要求や新しいSnapshotは作らない。既存例の10 MSの表示待ちの次巡でも管理できる。

**D07の公開→回収100msを正しく測るための題材修正であり、計測始点・終点を動かしたものではない。** publishedはready公開、reclaimedは物理handbackと所有資源・台帳・slot回収後のままで、結果取得・検査・release・VM解放・次の管理巡の費用を区間から差し引かない。解放APIに掛かった時間だけに置き換えていない。独立Snapshotの所有参照や共有workerのjoinの扱いも10.3節のまま。待機終了まで管理しなかった題材を、決定済みの「公開後の次のメイン巡で回収」に合わせた。

短いWindows調査では同じ通常probe実行体で旧／新の各2要求を実行した（`.work/post-measure/check-pace.py`、`pace-comparison.json`、各raw.log）。公開→回収はG1-open旧114.6069／122.8411ms→新0.6140／2.8138ms、G2旧1,016.5971／1,014.7578ms→新10.9652／9.4581ms、T1旧111.2379／115.7082ms→新6.6695／9.1179msだった。旧／新とも検索の実装は改善後を使用し、ホスト待機の差を見る調査である。本測定の最大値・件数には加えていない。100msの保証や全ケースの合格とはせず、新ソースの本測定で再確認する。

### 12.2 T1の検索

`tests/task/task-search-worker.fs` のTS-SEARCHを次のように改めた。受入れfixtureもこのファイルをINCLUDEDするため、例と受入れで同じ実装を使う。

- 1バイト検索はSCANで次の候補、SKIPで連続一致の末尾を探す。一致区間全体を件数に加算し、位置を展開するのは保存する先頭1,000件だけ。
- 複数バイト検索はSCANで先頭バイトの候補を絞り、最大256バイトずつCOMPAREする。一致／不一致とも次は候補の1バイト後からなので、重複一致を維持する。
- SCAN／SKIPの領域は毎回最大65,536 bytes、COMPAREの2領域合計は最大512 bytes。SEARCHの仕事量制限を迂回する呼出しは使わず、許可集合・nativeの64KiB/回上限を維持する。
- 件数、0始点のバイト位置、先頭1,000件、truncated、generationの意味は維持する。1,000件に達しても総件数の計算は続ける。

`verify-task-examples.py` にPythonの独立した全位置走査との比較を12ケース追加した。空本文、本文より長い語、不一致、重複、交互一致、NUL、65,535位置からの境界跨ぎ、256バイトの語、複数chunk、1,000件超を含め、総件数・保存件数・truncated・保存した全位置・generation・結果byte長を確認した。受入れT1のチェックも総件数1,048,576だけでなく、先頭1,000位置とtruncatedを検査する。

短いWindows traceの改善後T1の計算部分は2回で0.3378／0.3196ms（`short-trace.json`）、大きさ別診断では0.3328msだった。10.2節の旧T1診断424〜431msとは異なる時点・条件の短い診断であり、正式な速度比較・Linuxの200ms達成判定ではない。

### 12.3 Windowsの待ち取消し54ms

旧fixture `fixtures/reclaim/queued.fs` と `AC` の呼出しを確認した。対象の順序はTASK-CANCEL→THROW→AW→最初のTASK-STATEで、**取消しと次の管理巡の間に100／1000 MSも1 MSもない**。AWの1 MSは、最初のTASK-STATEがまだ非終端だった場合にだけ実行される。54ms標本では最初の次巡の中で公開されている。従って供給間隔待ちによる公開→回収超過とは別の事象である。

API末尾には `acceptance.flush()` があり、取消しAPIの事前pollと次APIのpollの間には取消し処理・API帰還・ログ出力・Forthディスパッチ・OSでの実行待ちが入る。生データに各境界の時刻やOSの実行記録がないので、このうちどれが54msを占めたかは確定できない。「ホストの巡の間に54ms空いた」は確認済みだが、「題材が54ms待った」は確認できない。

今回のAPACE／TC-TICKは、この既存queued経路の取消し→最初の状態確認の順序を変更しない。したがって修正(1)でこの54msも改善したとは報告しない。新題材の短い1試行では待ちtaskの要求→公開0.0033msだったが、外れ値解消の証拠にはならない。10.4節の未達標本を残し、Claudeのqueued再測定対象とする。再発時はcancel API帰還・flush前後・次poll開始とOS実行記録を追加で採り、原因を特定する。

### 12.4 検証とClaudeへの再測定引継ぎ

今回ロクが実行した検証：`zig build test`、`zig build test -Ddebug=false`、`zig build runtime-test`、`python tests/scripts/verify-task-examples.py`（16グループ）、`python scripts/check-docs.py`（findings: 0）、`git diff HEAD --name-only -- '*.zig'` が列挙する全Zigファイルへの `zig fmt --check`。ログは `.work/post-measure/`。既定キャッシュはAccessDeniedとなったため、ZIG_GLOBAL_CACHE_DIR／ZIG_LOCAL_CACHE_DIRをworktree内へ設定して成功した。本測定、commit、branch作成・変更、push、tque変更は行っていない。

再測定は変更前runを保持し、新runとして採取する。まずG1各形状／G2／T1／I1の公開→回収とT1投入→公開を新題材で再確認する。G1はLinux投入→公開の未達・80%規則、Windows openの80%規則もある。対話は各case10分を独立2回追加する規則を維持し、下のworkloadsコマンドを各OSで独立に2回実行する。旧runと変更後runの標本は混ぜず、改善後版の再確認として残す。既存超過を追加回数だけで合格にしない。

Windows queuedは追加1,000回。Linux queuedは今回最大が80%未満であり、この事象だけなら追加対象ではない。10.5節のWindows取消し各位相、Snapshot・メモリ、10.6節の欠測位相についても既存の追加／未確認状態は残る。今回の題材修正で解消した扱いにはしない。計画変更を要する場合は理由と代案をレモンの判断事項とし、ここでは回数を緩和しない。

以下は**Claudeが実行するコマンドであり、ロクは実行していない**。REFは変更後版の再測定を識別する実行確認参照に置き換える。Windows PowerShellでは次のとおり（workloads行を独立に2回）：

```powershell
$hash = '7b341c1b6f6b12eeab2c6aa5bf31f24cde48c4e8bb555a89856744496dfc6032'
python tests/scripts/run-acceptance.py --mode measure --only workloads --probe-cases G1-open G1-wall G1-snake G2 T1 I1 --plan-sha256 $hash --confirmed REF
python tests/scripts/run-acceptance.py --mode measure --only reclaim --probe-cases queued --repetitions 1000 --plan-sha256 $hash --confirmed REF
```

Linux（workloads行を独立に2回）：

```sh
hash=7b341c1b6f6b12eeab2c6aa5bf31f24cde48c4e8bb555a89856744496dfc6032
python3 tests/scripts/run-acceptance.py --mode measure --only workloads --probe-cases G1-open G1-wall G1-snake G2 T1 I1 --plan-sha256 "$hash" --confirmed REF
```

LinuxのG1の原因を分ける短い診断は本測定と別ビルド・別runにする。計画の標本や判定には入れない。64／128／256の各形状を1回ずつ、T1を1回実行する。生成各段階・復元・計算・結果コピー等のraw時刻と差分を保存する。submit→acquiredの待ち・ホスト入力コピーはこのtraceでも未分離であり、結果コピーも実行参照解放込みである。これらが必要なら追加の境界記録が必要になる。

```sh
zig build -Doptimize=ReleaseFast -Ddebug=false -Dtask-trace=true -Dtask-acceptance=false --prefix .work/linux-post-trace-build -j2
python3 tests/scripts/diagnose-task-workloads.py --sigma .work/linux-post-trace-build/bin/sigma --out .work/linux-post-trace --only G1 T1
python3 tests/scripts/diagnose-task-workloads.py --sigma .work/linux-post-trace-build/bin/sigma --out .work/linux-post-parent-fill --only G1 --parent-fill
```

`--parent-fill` は、親の配列を初期化するループを持つ b7073ab 以前の G1 ワーカーだけが対象である。その後のワーカー（壁で囲んだ作業用の盤面に親の方向を書く版）には親の配列がないので、この選択肢は説明を出して止まる。

Windowsで同じ大きさ別診断を必要とする場合：

```powershell
zig build -Doptimize=ReleaseFast -Ddebug=false -Dtask-trace=true -Dtask-acceptance=false --prefix .work/windows-post-trace-build -j2
python tests/scripts/diagnose-task-workloads.py --sigma .work/windows-post-trace-build/bin/sigma.exe --out .work/windows-post-trace --only G1 T1
python tests/scripts/diagnose-task-workloads.py --sigma .work/windows-post-trace-build/bin/sigma.exe --out .work/windows-post-parent-fill --only G1 --parent-fill
```

本測定の区間を変更する必要は今のところ認めていない。Linux各段階の実時間・VM確保のOS内訳とWindows54msの原因は、既存生データでは未確定であり、上記診断・再発時ログで埋める項目として残す。

## 2026-11-25 決定B：取消し位相を固定して再測定する準備

**ここからの計画が現行。以前の節の固定値とコマンドは当時の測定記録である。** レモンは「B: 段階を確実に狙える測り方に変えて、測り直す」を採用した。3 OSとも生成段階を狙った取消しの約7割を取り逃し、nativeのFILL・SEARCH・ROLLは最初の3回とも取り逃して打ち切ったためである。旧結果の欠測・超過を残し、新方式の標本と混ぜない。

| 現行固定計画 | SHA-256（この文字列を期待値として渡す） |
|---|---|
| [Windows/Linux v4](TASK_CONTROL_ACCEPTANCE_PLAN.md) | `f4994e515253eac7cd10a71906d628a6760a998878b44d619cd80b1be856a36e` |
| [macOS v2](TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md) | `aefdfe0e1e411c4d20eaf5aa520ebb68072a5ac686e38a7dd51f4d68288c0e36` |

両計画の`.gitattributes`の`-text`は維持した。今回変えたのは取消し位相の測り方と、最大量を通すためのnative題材であり、試行回数は変更していない。対象はWindows・Linux・Macのそれぞれ生成25段階、native 5種×3位相、待ち中、計41ケース×各100回（4,100回/OS、合計12,300回）。他群の追加・未確認項目は従前のまま残す。この取消し再測定はWindows queuedの既存追加1,000回等を完了扱いにしない。

### 実装とClaude案に対する選択

`task_acceptance.Storage.hold`が指定段階をatomicで通知し、workerは取消しtokenを確認するまで同じ位置で待つ。ホストTASK-STATEの巡回は通知を確認し、同じtask idで公開語TASK-CANCELのハンドラーを呼ぶ。requestedはその入口なので、holdで到達を待った時間は要求→停止/回収に入らない。stopped/reclaimedの意味と通常の取消し処理は維持した。holdは5秒の実時計guard、時計異常、shutdownのtokenで解除し、時間切れはhold_timeout=trueの理由付き欠測にする。通常ビルドはcomptimeで除去する。

生成・native before/afterは指定位置でholdする。duringについて旧通知方式を残すと取り逃しが続くため、**事前確認後のnative入口でholdし、要求後に最大量のnative全体を実行する保守的な代案**を選んだ。次の通常checkpointでtokenを検出する。method=`guarded-native-entry-full-call`で識別し、実処理中に要求したとは記録しない。nativeの残仕事量全体を要求→停止10msの区間に含めるD07確認であり、特定のOSスケジュールや全入力について最遅時間を証明するものではない。

FILLは64KiB、MOVE/COMPAREは32KiBの2領域。SEARCHは旧256×256の最初の候補一致を避け、65,535 bytesのaから1 byteのbを探す全文不一致（領域合計64KiB）とした。COMPAREは同値の全領域を読む。ROLLは旧4,000 cellsから8,192 cells（64KiB）へ変更し、この子プロセスだけ`--data-stack-size 16384`を付ける。題材と容量差はfixture manifestと子commandで識別する。これは最大量の代表題材であり、全パターンの中で最も遅い入力を選び切った証拠とは区別する。

phase_okは指定段階=hold_stage=request_stage、かつhold_timeout=false。native_runningは上記入口という意味で一致を確認する。待ち中はqueued=trueかつ未実行を確認する。native境界とrequestedが同時刻でもatomicによる位相確認を使い、旧方式の時刻推定とは混ぜない。smokeでもphase_okを保存し、端点0と空の速度統計を維持する。task行欠落・位相不一致・時間切れは欠測とし、最初の3回での打切りを廃止、成功数に達するまで補充もしない。

### Claudeが実行する再測定コマンド（今回は未実行）

各OSのリポジトリルートで実行する。runnerがReleaseFast/debug=false/strip=true/task-trace=false/task-acceptance=trueをビルドする。実行前後に固定計画を照合し、既存runを保持して新しいrunへ保存する。確認参照は今回の決定Bを示す。所要時間は、Windowsの新方式smoke 123試行の全体約10秒を単純換算すると約5分/OS。**※推測です：正常時はビルド・環境確認を除き5〜15分/OS、3 OSで15〜45分。** OS差や負荷で変動する。hold対象4,000件がすべて5秒で時間切れなら約5.6時間/OSに起動・回収費用が加わり、120秒の異常停止guardは別枠になる。

Windows（PowerShell）:

```powershell
python tests/scripts/run-acceptance.py --mode measure --only reclaim --repetitions 100 --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN.md --plan-sha256 f4994e515253eac7cd10a71906d628a6760a998878b44d619cd80b1be856a36e --confirmed lemon-approved-2026-11-25-phase-hold-B
```

Linux（Python 3）:

```sh
python3 tests/scripts/run-acceptance.py --mode measure --only reclaim --repetitions 100 --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN.md --plan-sha256 f4994e515253eac7cd10a71906d628a6760a998878b44d619cd80b1be856a36e --confirmed lemon-approved-2026-11-25-phase-hold-B
```

Mac（SSH先でもzsh -lcを使う）:

```sh
zsh -lc 'cd ~/source/zig/ForthSigma && caffeinate -i python3 tests/scripts/run-acceptance.py --mode measure --only reclaim --repetitions 100 --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md --plan-sha256 aefdfe0e1e411c4d20eaf5aa520ebb68072a5ac686e38a7dd51f4d68288c0e36 --confirmed lemon-approved-2026-11-25-phase-hold-B'
```

### ロクによるWindowsの短い検証

証拠は`.work/phase-hold/`。本測定は実施していない。`zig build test`、`zig build test -Ddebug=false`、`zig build runtime-test`、`zig build -Dtask-acceptance=true`、`python tests/scripts/verify-task-examples.py`（16グループ）、`python tests/scripts/test-acceptance-macos.py`（14件）、`zig build -Dtarget=aarch64-macos -Dtask-acceptance=true`、`zig build -Dtarget=x86_64-linux -Dtask-acceptance=true`は終了コード0。Zigのキャッシュはworktree内を使用した。クロスビルドは実機実行の代わりではない。

最大量題材で`--mode smoke --only reclaim --repetitions 3 --sigma zig-out/bin/sigma.exe`を実行し、`.work/acceptance/20261124T215513Z-149d9962/`で41ケース×3回=123件すべてphase_ok=true、phase_missing_count=0、missingなし、速度統計空を確認した。内部時刻は0なので10ms/100msの合否は判定していない。このrunは計画改訂前に動作確認した記録であり、新しい固定計画の本測定ではない。最終版の再確認は追記する。

`python tests/scripts/test-acceptance-hold.py`は、ホストがTASK-CANCELを呼ばずにBYEへ進む場合と、5秒guard後に取消し・回収する場合を各1回検証した。両方hold_stage=vm_startで到達を確認し、BYEはhold_timeout=false、時間切れはtrue、終了コード0。証拠は`.work/phase-hold/guards/`。

通常ビルドは変更前相当のソースコピーと現ソースを同じReleaseFast/debug=false/task-trace=false/task-acceptance=falseでビルドし、PEの.text全バイトを比較した。両方1,532,928 bytes、SHA-256=`1510320cab491aa5d634347d440bfa6c09c19423fea13e76992e84ea0102f15d`で完全一致した（`normal-control.py`、`compare.py`、`normal-comparison.json`）。比較元は今回変更のなかったHEADのruntime_base/host_task_apiと、作業開始時からあった変更を維持して新holdだけを除いたtask_acceptanceである。A/A′/Bの既存AC-29全体や通常単一VMの速度比較を完了した意味ではない。

今回もgit commit・branch・push、tque変更は行っていない。

最終版の固定計画v4を照合したsmokeは`.work/acceptance/20261124T220109Z-86a87405/`。41ケース×3回=123件すべてphase_ok=true、欠測0、速度統計空、runner終了コード0を再確認した。`python scripts/check-docs.py`（findings: 0）、変更されたZig全5ファイルの`zig fmt --check`、両計画のtext属性unsetを確認した。語リファレンスの日本語説明に通常APIの意味の変更がないことを確認し、出典ハッシュと生成文書を更新した。今回のログは`.work/phase-hold/`に保存した。

## 決定 B の測り直しの結果と、Windows の回収の外れ値

### 3 OS の結果（2026-11-25）

Windowsはmain `0019f97`でのv4本測定、07:06〜07:10 JST、`.work/acceptance/20261124T220657Z-67318d59/`の`results.json`と全raw.logをロクが再集計した。Linux/Macはレモンから提示されたClaude確認済みの値であり、ロクによる実機再実行・生データ再集計は行っていない。以下は変更前の本測定の結果であり、下記の調査用試行と混ぜない。

| OS / run | phase_ok / 位相の欠測 | 要求→停止 最大 | 要求→回収 最大 | 待ち中の取消し 最大 | 管理の1巡 最大 |
|---|---:|---:|---:|---:|---:|
| Windows / `20261124T220657Z-67318d59` | 4,100/4,100 / 0 | 0.5537ms | 192.2701ms | 0.0138ms | 0.1905ms |
| Linux / `20261124T220656Z-69534690` | 4,100/4,100 / 0 | 0.162ms | 1.28ms | 0.016ms | 0.089ms |
| Mac / `20261124T220659Z-ecc430ed` | 4,100/4,100 / 0 | 0.020ms | 1.62ms | 0.011ms | 0.036ms |

Windowsは`phase_complete=true`、`phase_missing_count=0`、`missing`なし。41ケース×100回=4,100試行だが、queued題材では待機taskと実行中のblockerの両方を取り消すため、要求→回収のtask標本は4,200件になる。100ms超過は8件。全taskをまとめた要求→回収の中央値は0.26675ms、p95は16.0848ms。各段階の中央値が約0.26msでも、外れ値の合否は別に残す。待ち中の取消しの列は要求→公開（`queued_cancel_publish_ns`）である。Linux/Macでは提示された最大値に100ms超過はない。

### 元の8件の管理巡の時刻

再集計器は`tests/scripts/diagnose-task-reclaim.py --analyze`。出力は`.work/reclaim-diagnostics/original.json`。各raw.logのACCEPTANCE行から、公開の直前の巡と、公開から回収までの全巡を抽出した。下表の巡は**publishedを0msとしたstart〜end**、各行の左から時刻順であり、ログの出力順ではない。表の試行名には`reclaim-`と`.raw.log`を補う。

| 試行 | 要求→回収 ms | 直前の巡 ms | 区間内の全管理巡 ms |
|---|---:|---|---|
| cancel-catches_allocated-0066 | 101.4732 | −0.0016〜−0.0014 | 101.4393〜101.4410; 101.4476〜101.4479; 101.4511〜101.4513; 101.4566〜101.4716 |
| cancel-frames_allocated-0007 | 168.2126 | −0.0030〜−0.0026 | 168.1747〜168.1762; 168.1908〜168.1910; 168.1946〜168.1948; 168.2002〜168.2097 |
| cancel-loops_allocated-0032 | 192.2701 | −0.0020〜−0.0015 | 192.2337〜192.2353; 192.2485〜192.2487; 192.2524〜192.2526; 192.2584〜192.2681 |
| cancel-loops_allocated-0035 | 109.2639 | −0.0019〜−0.0016 | 109.2339〜109.2355; 109.2427〜109.2429; 109.2463〜109.2464; 109.2519〜109.2620 |
| cancel-return_allocated-0052 | 100.4714 | −0.0021〜−0.0018 | 100.4350〜100.4363; 100.4505〜100.4507; 100.4543〜100.4545; 100.4601〜100.4694 |
| cancel-state_reserved-0016 | 172.0684 | −0.0053〜−0.0049 | 172.0296〜172.0314; 172.0441〜172.0443; 172.0480〜172.0482; 172.0534〜172.0632 |
| cancel-state_reserved-0018 | 125.8004 | −0.0148〜−0.0145 | 125.7544〜125.7554; 125.7670〜125.7673; 125.7708〜125.7710; 125.7761〜125.7857 |
| native-search-native_running-0005 | 140.7037 | −0.0177〜−0.0172 | 140.6334〜140.6357; 140.6564〜140.6568; 140.6631〜140.6633; 140.6720〜140.6860 |

8件とも公開後の最初の巡が100〜192ms遅れている。巡の再開から回収までは約0.03〜0.05msであり、管理巡自身の長時間実行ではない。生成取消しの7件のfixtureは`BEGIN AP ... REPEAT`で待ち、ここで`MS`は使わない。したがって、この7件をWindowsのSleep分解能だけでは説明できない。native題材の`AW`は`1 MS`を使うため、約16msの巡間隔は別に存在し得る。10.3節の通常題材の解析を、今回の取消しfixtureへそのまま当てはめない。

### 解放・引渡し・join・ログ出力の内訳

`-Dtask-acceptance=true -Dtask-reclaim-diagnostics=true`だけで追加時計を有効にした。通常はcomptimeで除去する。`worker_retirement_ns`は公開後の独立retirement ownerのdestroy開始〜終了（FreshVmのdeinit、storage/stateの解放とretirement owner自身の解放を含む）。`worker_handback_ns`はその終了〜queue gate取得後のcleaning解除直前。workerはcleaningで保持されるJobにだけ時刻を書き、ホストは同期してcleaning解除を確認してから読む。`host_destroy_ns`はExecutionのdeinit、入力・名前・Taskの解放〜slotクリア。`worker_join_ns`は共有workerのthread.joinの開始〜終了であり、各taskのreclaimedより後のshutdown費用である。

さらに`acceptance_flush_ns`でACCEPTANCEの整形・ファイル出力全体を測った。この区間だけは出力の外側を囲み、結果は次のflushで出す。最後のflush自身の時間は次の出力がなければ記録されない。この値を回収端点へ加算・減算しない。workerはイベント配列に書かず、ホストだけがシリアライズする。

調査用runnerは`tests/scripts/diagnose-task-reclaim.py`。本測定runnerのmeasure/smokeを呼ばず、同じfixtureとholdを使い、過去に超過した生成5段階とSEARCHのnative_runningを各300回、計1,800試行実行した。ReleaseFast/debug=false/strip=true/task-trace=false。生ログ・実行ファイルハッシュ・統計は`.work/reclaim-diagnostics/`の各run。sampler onは従来と同じ10ms周期のOSメモリ監視、offは監視なしである。以下の値はms。

| 調査用run | 要求→回収 最大 | worker解放 最大 | 解放後の引渡し 最大 | host解放 最大 | join 最大 | 管理巡 最大 | flush 最大 |
|---|---:|---:|---:|---:|---:|---:|---:|
| `sampler-on`（修正前） | 72.8226 | 0.2446 | 0.0007 | 0.1060 | 0.1738 | 0.1113 | 179.5307 |
| `sampler-off`（修正前） | 167.1065 | 0.3115 | 0.0013 | 0.0282 | 0.2081 | 0.0313 | 167.0608 |
| `fixed-sampler-on`（修正後） | 16.6478 | 0.3225 | 0.0011 | 0.0724 | 0.4833 | 0.0752 | 45.1991 |

修正前sampler-offの`catches_allocated-0090.raw.log`では、要求を0とするとflushは**0.0008〜167.0616ms**、worker解放は**0.0035〜0.0240ms**、引渡しは0.0241ms、回収は167.1065ms。管理巡の外のACCEPTANCE出力中に時間がかかったことを直接確認した。sampler-onの`catches_allocated-0288`も要求→回収72.8226msのうちflushが0.0012〜72.7806msを占める。メモリ監視なしでも再現したため、VirtualQueryExによる監視だけを必要条件とする説明は成立しない。

**原因として確認できたのは、計測用コードが取消し要求後の各API出口で同期ログ出力し、次の管理巡を遅らせること。** 元の8件にはflushの端点がないため、それぞれの遅延が全て同じ出力呼出しで生じたとは断定しない。※推測です：元の8件も同じ出力待ちが主因と考えられる。Defender、他プロセス、ファイルシステム、スレッドのスケジューリングのどれが出力を遅らせたかは、今回の時計だけでは特定できない。特定プロセスやVirtualFree内部のページ処理を原因とは断定しない。少なくとも再現した167msはVM解放やjoinに費やされた時間ではなく、コードで避けられる同期出力の配置に問題がある。

### 修正とD07の扱い

計測用のホストがTASK-CANCELを初めて受けたときに未回収数を増やし、taskの物理解放・slot回収後のdumpで減らす。未回収の取消しがある間はACCEPTANCEのflushを保留し、既存のイベント配列に時刻を保存する。複数taskの取消しにも対応し、全て回収してから出力する。smokeはrequested=0なので、時刻をフラグとして使わず`request_recorded`で1回だけ登録する。管理巡の時刻と要求・停止・公開・回収の端点は維持し、解放時間や巡間の待ちを計測値から差し引かない。イベント配列の容量は従来の512件で、溢れたら従来どおり`lost_events`を出し、受入れrunnerは欠測にする。無制限に保持できるとは扱わない。

workerのVM解放は既に管理巡の外で行われ、今回0.323ms以下だった。解放の細分化や別の解放threadを追加する根拠は今回得られなかったため、通常の実行・回収経路は変更していない。修正後の調査用1,800試行は全て指定位相に一致、欠測0、`lost_events`0、要求→回収100msと管理巡1msの超過0。ただし、本測定の合格・全OSでの保証とは区別する。約16msの最大はnative題材の`1 MS`による巡間隔と整合するが、OSの待ちの内訳までは計測していない。

通常経路への影響は、HEADのarchiveと変更後の4 Zigファイルを**同じソース配置**で順にビルドして比較した。ReleaseFast/debug=false/strip=true/task-trace=false/task-acceptance=falseのPE `.text`は両方1,532,928 bytes、SHA-256=`955e53b3e44a95130d83f768441e815a60dad1bf064967988316c536794c5016`で全バイト一致（`normal-comparison-same-path.json`）。別配置での最初の比較はアドレスを含む`.text`が一致しなかったため、同一配置で確認し直した。通常経路の命令に差はなく、中央値+1%/p95+2%の速度影響を導入していない根拠とする。速度の実測を行った意味ではなく、AC-29全体も未完のまま残す。

### 検証とClaudeへの引継ぎ

検証ログは`.work/reclaim-diagnostics/checks/`。`zig build test`、`zig build test -Ddebug=false`、`zig build runtime-test`、`zig build -Dtask-acceptance=true`、`python tests/scripts/verify-task-examples.py`、`python tests/scripts/test-acceptance-hold.py`を実行した。hold試験には取消し後・release前にAPを呼んでもACCEPTANCE行が出ず、回収後にはtask行が出る回帰確認を加えた（時刻0のsmokeでも確認）。文書とfmtの最終確認結果は下記に追記する。

Claudeが調査を再現する場合（受入れ本測定とは別、Windows PowerShell）：

```powershell
$env:ZIG_GLOBAL_CACHE_DIR = "$PWD\.work\zig-global-cache"
zig build -Doptimize=ReleaseFast -Ddebug=false -Dstrip=true -Dtask-trace=false -Dtask-acceptance=true -Dtask-reclaim-diagnostics=true --prefix .work/reclaim-diagnostics/final-build -j2
python tests/scripts/diagnose-task-reclaim.py --sigma .work/reclaim-diagnostics/final-build/bin/sigma.exe --out .work/reclaim-diagnostics/claude-investigation --repetitions 300
```

`--sampler off`で監視なしを選べる。`--out`は新規ディレクトリを指定し、旧runを上書きしない。最終ソースの調査時計は、retirement ownerがない場合に公開後のJobへ触れないguardも含む。

Claudeが行う修正後のWindows本測定は以下。追加内訳の時計を付けない通常のacceptanceビルドをrunnerが作成する。固定計画v4と端点は変更していない。旧8件の超過記録を消さず、新runの結果を追記する。Linux/Macを再測定する場合は前節の各OS用コマンドを使い、新ソースの識別情報と新runを残す。

```powershell
python tests/scripts/run-acceptance.py --mode measure --only reclaim --repetitions 100 --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN.md --plan-sha256 f4994e515253eac7cd10a71906d628a6760a998878b44d619cd80b1be856a36e --confirmed lemon-approved-2026-11-25-phase-hold-B
```

ロクは受入れの本測定、git commit・branch・push、tque変更を行っていない。

最終検証は`.work/reclaim-diagnostics/checks-final/results.json`。上記6コマンドと`python scripts/check-docs.py`（findings: 0）、`zig fmt --check build.zig src/core/task_acceptance.zig src/core/task_queue.zig src/host_task_api.zig`の全8件が終了コード0。語リファレンスのTASK-CANCEL/TASK-RELEASEの日本語説明に通常APIの意味の変更がないことを確認し、実装の出典ハッシュを更新した。最終の診断用ビルドでも各対象3回とqueued題材1回を確認し、イベント欠落なし（`final-guard-check/`）。この確認は上表の1,800試行へ混ぜていない。

## 出力保留の修正後の取消し位相の本測定（2026-11-25）

main `ff7363b`、計画v4（`f4994e51…a36e`）・macOS計画v2（`aefdfe0e…0e36`）、確認参照 `lemon-approved-2026-11-25-phase-hold-B`。Claudeが3 OSで同時に実行した（07:27〜07:30 JST）。各OSとも41ケース×100回。

| OS / run | phase_ok / 欠測 | 要求→停止 最大 | 要求→回収 最大 | 待ち中の取消し 最大 | 管理1巡 最大 |
|---|---|---|---|---|---|
| Windows / `20261124T222722Z-ce3f2f55` | 4,100/4,100 / 0 | 0.379ms | 16.72ms | 0.0034ms | 0.101ms |
| Linux / `20261124T222719Z-24000d52` | 4,100/4,100 / 0 | 0.167ms | 1.27ms | 0.0019ms | 0.134ms |
| Mac / `20261124T222720Z-457847ee` | 4,100/4,100 / 0 | 0.027ms | 1.60ms | 0.001ms | 0.081ms |

3 OSとも全指標で超過0件、80%超0件（追加試行なし）。Windowsの前回run（`20261124T220657Z-67318d59`）の8件の超過は、計測器自身の同期出力によるもので、修正後のrunでは再現しなかった。前回runの記録は消さずに残す。生成25段階・native 5種×3位相・待ち中の取消しについて、D07の要求→停止10ms、要求→回収100ms、待ち中の取消し10msを、3 OSの実機で満たした。

## 対話の場面の測り直し（2026-11-25）と G1 の遅れ

### 3 OS の本測定

Claude が `d6fa707` で07:31〜09:32 JSTに実施した。各題材10分×独立2回。Windowsは `.work/acceptance/20261124T223120Z-b8d5bf52` と `20261124T233128Z-a4d24036` の生ログを再集計した。Windowsの2値はrun順、Linux・macOSはClaude提供の集計。時間はms。

| 指標 | Windows | Linux | macOS |
|---|---:|---:|---:|
| G1-open 投入→公開 中央値 | 98.77 / 98.95 | 176 | 83〜85 |
| 同 100ms超過 | 408/2,748、445/2,747 | 全件 | 1件 |
| G1-wall 投入→公開 中央値 | 60.46 / 60.30 | 96 | 内訳未提供 |
| G1-snake 投入→公開 中央値 | 68.50 / 68.66 | 116（全件超過） | 内訳未提供 |
| T1 投入→公開 中央値（最大） | 6.97 / 7.01（8.42 / 8.18） | 未提供 | 未提供 |
| I1 公開→回収 中央値（最大） | 36.69 / 37.16（123.40 / 176.36） | 未提供 | 未提供 |
| I1 の最大待ち件数 | 4 | 4 | 4 |

改善前のG1最大はWindows 87.72、macOS 81.3。Linuxの旧中央値はopen 147.12、wall 80.79、snake 96.81で、3形状合計2,437/8,769件が超過、最大164.72だった。Windowsの今回の公開→回収はI1以外にT1（128.87）とG1-open（103.76）も各1件超過した。

### Windowsでの切り分け

`acceptance-probes.py` の `run` はstderrとstdoutを同一ファイルに直接書く。親は実行中に約10msの待ちを挟んでメモリを採取する。workloadsでは親がログを解析するのは子の終了後である。`Session.read(1)` は別の `response` 測定の経路である。またG1は逐次投入で、`APACE` が走るのは結果の取得・検査・releaseが済んだ後。実行中の `AW` は旧・新とも `TASK-STATE` と `1 MS` を使う。Windowsの `MS` は出力をflushして `Sleep` を呼ぶ。本測定の生ログでも管理巡は約15〜16ms間隔の箇所があり、1ms指定を毎秒1,000巡とは数えられない。

256×256のopenについて、同一実行体・同一辞書・同一入力で、供給待ちの呼び出しだけを `100 MS` と `100 APACE` に変えた。各プロセス10要求の短い診断である。下表はtrace＋acceptanceの同一実行体で取得した代表の連続2試行。各時間はタスク別区間の中央値。待ちにはホスト側の入力準備も、VM準備には復元・権限検査・入力コピーも、最後の区間には結果コピーも含む。親CPUは親プロセスのCPU秒÷子実行中の壁秒で1コアを100%とし、事後解析は含まない。

| 供給待ち | 投入→取得 ms | 取得→計算開始 ms | Forth計算 ms | Forth帰還→公開 ms | ACCEPTANCE行/秒 | bytes/秒 | 親CPU |
|---|---:|---:|---:|---:|---:|---:|---:|
| 100 MS | 3.370 | 3.672 | 90.178 | 0.012 | 61 | 6,790 | 0.0% |
| 100 APACE | 3.471 | 3.686 | 90.102 | 0.012 | 97 | 10,450 | 2.1% |

同じ組の逆順でも計算は91.013 / 89.797ms（APACE / MS）。短時間の親CPUは時計の粒度・実行順による振れが大きく、0.0%は丸め後の値。traceなしの本測定実行体でも、メモリ監視を外したopenの投入→公開はAPACE 98.54、MS 98.35だった。本測定のopenの出力量も両runで約96行・10.4kB/秒。出力量は増えたが、Windowsの約20ms以上の悪化を、親の読み取りや待ち方だけでは再現できない。

**差を再現した条件はワーカーのnative取消し位相の計測を組み込むかどうかだった。** `task_memory.zig` は組み込み語の前後で対象のnative名を調べる。workloadsは対象を指定しないためnative時刻を記録しないが、従来のacceptanceビルドには検査を含むコードが残る。現行ソースからこの観測呼び出しだけを除いた対照を作り、APACE・監視・ログ出力を維持した。openの中央値は現行98.996 / 99.009ms、対照68.758 / 68.855ms（順序を反転、各10要求）。同じ題材を `bce27b9` の計測器で動かすと75.65 / 76.66msだった。これは保存された初回本測定実行体そのものの再現ではない。差はプローブを含む**生成コード全体**の差であり、個々の分岐の消費時間や機械命令の配置の寄与は分離していない。Linux・macOSでの寄与は実機未確認。

`workloads` 用に `-Dtask-native-probe=false` を加えた。通常の製品ビルドでは従来からこのプローブは無効。取消し測定は従来のビルドを使う。runnerは使用した実行体のSHAを記録し、子の設定行を照合する。native観測を外した実行体にnative位相を要求すると起動時にエラーになる。D07の時刻、1巡1msの目安、全管理巡の個別記録、メモリ監視、供給・公開・回収経路は維持した。修正後の正式なビルド設定でも、各10要求でopen 107.30→75.62、wall 57.05→41.42、snake 69.61→49.68ms。別の検証ビルドが並行していた短い比較なので、この値で受入れ判定はしない。診断のfixture・rawは `.work/g1-study/`、runner経由の6題材smokeは `.work/acceptance/20261125T004719Z-078f76a3/`。

ほかの検証ビルド終了後、同じAPACE題材で旧→新→新→旧と順序を反転した。各10要求のopen投入→公開の中央値は **98.96→70.02→71.38→98.71ms**。新の管理1巡の最大は0.0275 / 0.0318msだった。別プロセスのtrace付き短時間診断でも、修正後のopenのForth計算はMSで55.13 / 54.25ms、APACEで54.41 / 54.68ms。修正後のAPACEで投入→取得は3.83 / 3.85ms、取得→計算開始は3.85 / 4.21ms、帰還→公開は0.014 / 0.011ms。元データは `.work/g1-study/clean*.log` と `paired-final/summary.json`。

### I1 の公開→回収

I1は5スロットを `FEED` で順に確認し、結果取得・検査・releaseを行い、次の周回まで `50 APACE` で待つ。`ATICK` は管理処理を進めるが、未releaseの結果の所有権を返さない。初回の待ち4件は実行中のblockerに続けて投入する題材設計と一致する。

| Windows run | 100ms超過のタスクID | 件数 | 区間周辺で隣り合う管理巡の終了→次の開始 |
|---|---|---:|---:|
| 1 | 21125〜21127 | 3 | 118.059ms |
| 2 | 12680〜12684 | 5 | 140.451ms |
| 2 | 45070〜45074 | 5 | 106.452ms |

13件は三つの長い巡間隔を共有する。公開から回収までに開始した管理巡そのものは、各群とも最大0.03ms以下。最大標本176.36msのうち140.45msは管理巡の間にあり、その間は次の結果確認・releaseに進めなかった。生ログにはsleepの入出時刻、ファイル書き込み中の待ち、OSのスレッド切替がない。この三つの空白をどの処理が占めたかまでは特定できない。再発時にOSレベルを切り分けるには、WindowsのスケジューリングとファイルI/Oのトレースを**別の診断**で取得し、該当する子のメインスレッドを同じQPC時刻に照合する。既存の13件を除外しない。

I1を100要求に限った追加診断では、APACE内の `1 MS` の前後でUTIMEを採り、値は終了時にまとめて出力した。84回の中央値は15.600ms、最大16.597ms。通常の待ちが1msより長いことは確認できたが、100ms超の空白はこの短い診断では再現しなかった（`.work/g1-study/I1-sleep.fs`、同 `.log`）。

### Claude の実機診断と再測定

Linux・macOSで先に原因を比較する場合は、リポジトリのルートで次を実行する。各試行10要求、順序はMS→APACE→APACE→MS。新しい出力先で実行する。trace付きの時間は本測定に入れない。

```sh
for probe in true false; do
  zig build -Doptimize=ReleaseFast -Ddebug=false -Dstrip=true -Dtask-trace=true -Dtask-acceptance=true -Dtask-native-probe=$probe --prefix .work/g1-diag-$probe -j2 || exit 1
  python3 tests/scripts/diagnose-g1-pacing.py --sigma .work/g1-diag-$probe/bin/sigma --out .work/g1-pacing-$probe || exit 1
done
```

本測定はClaudeが各OSで実施する。改訂理由は、対話で使わない取消し位相の測定コードが、同じ計算を行うワーカーの所要時間を変えたため。Windows・Linuxはv5、macOSはv3で固定した。下記の `REF` は実際の実行確認参照に置き換える。各コマンドは6題材×各10分のrunを独立に2回作る。第1回の失敗時は停止する。

Windows（PowerShell）

```powershell
foreach ($n in 1,2) {
    python tests/scripts/run-acceptance.py --mode measure --only workloads --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN.md --plan-sha256 e96ba422a56d0afa294f572443a745c7d34152adb77e984283fd5340a064a7e8 --confirmed "REF-workloads-$n"
    if ($LASTEXITCODE -ne 0) { throw "workloads run $n failed" }
}
```

Linux（リポジトリのルート）

```sh
for n in 1 2; do
  python3 tests/scripts/run-acceptance.py --mode measure --only workloads --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN.md --plan-sha256 e96ba422a56d0afa294f572443a745c7d34152adb77e984283fd5340a064a7e8 --confirmed "REF-workloads-$n" || exit 1
done
```

macOS（Claudeの既定の作業場所）

```sh
zsh -lc 'cd ~/source/zig/ForthSigma || exit 1; for n in 1 2; do caffeinate -i python3 tests/scripts/run-acceptance.py --mode measure --only workloads --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md --plan-sha256 44622846f887091e8a2a3dfcfdda48e149438594678523ae4121eae713b683b8 --confirmed "REF-workloads-$n" || exit 1; done'
```

### Windowsでの検証

`zig build test`、`zig build test -Ddebug=false`、`zig build runtime-test`、`zig build -Dtask-acceptance=true`、`python tests/scripts/verify-task-examples.py`（16グループ）、`python tests/scripts/test-acceptance-hold.py`、`python tests/scripts/test-acceptance-macos.py`（14件）、`python scripts/check-docs.py`（findings: 0）、変更した3つのZigファイルの `zig fmt --check` が成功した。native観測ありのFILL実行位相もsmokeで確認し、観測なしの実行体に同じnative指定を与えると `NativeProbeDisabled` で終了した。ロクが実行したのはWindowsの短い診断と機能試験までである。

## G1 ワーカーの高速化の後の対話の場面の本測定（2026-11-25）

main `0bb8a41`（G1 ワーカーを壁で囲んだ作業用の盤面で書き直した版）、計画v5（`e96ba422…a7e8`）・macOS計画v3（`44622846…83b8`）。Claudeが3 OSで同時に実行した（12:21〜14:22 JST）。各題材10分×独立2回。値は2回の中央値の範囲と、2回を通じた最大。

| 題材（目安） | Windows | Linux | Mac |
|---|---|---|---|
| G1-open 投入→公開（100ms） | 34.0〜34.2ms / 42.1ms | 46.8ms / 59.2ms | 46.1〜46.2ms / 56.6ms |
| G1-wall（100ms） | 19.8〜19.9ms / 38.3ms | 26.6ms / 32.3ms | 44.5ms / 52.7ms |
| G1-snake（100ms） | 32.0〜32.1ms / 40.6ms | 44.0ms / 53.4ms | 45.9〜46.0ms / 55.9ms |
| G2（500ms） | 136.4〜136.7ms / 157.1ms | 221.8〜222.0ms / 239.6ms | 142.2〜142.3ms / 163.5ms |
| T1（200ms） | 7.0〜7.1ms / 11.3ms | 8.0〜8.1ms / 9.7ms | 29.9〜30.2ms / 33.2ms |
| I1 投入→公開（250ms） | 18.0〜19.9ms / 45.5ms | 25.2ms / 62.3ms | 21.2〜21.7ms / 65.2ms |
| 管理の1巡 最大（1ms） | 0.592ms | 0.452ms | 0.192ms |

run：Windows `20261125T032146Z-2e4ed0af`・`20261125T042154Z-d358c634`、Linux `20261125T032136Z-45c9954c`・`20261125T042205Z-e63d6606`、Mac `20261125T032140Z-29144992`・`20261125T042150Z-34c7c910`。

- 投入→公開は、3 OSの全題材で超過0件、80%超0件。LinuxのG1-openは、前回（`b7073ab`、中央値116ms・全件超過）から目安内になった。
- LinuxとMacは、全指標で超過0件。80%超はI1のqueue_waiting=4だけで、I1の題材が待ち4件を保つ設計による。
- Windowsだけ、公開→回収の外れ値が残る：I1で13件（2回目、最大176.5ms）、G1-openで1件（1回目、117.0ms）。G1-open・T1の公開→回収は80%超もある。以前の調査で、メインのスレッドが100ms以上動かない空白に集中することまでは分かっているが、その原因は未確定。次にメインの巡の各段階に時刻を記録して調べる。

## Windows の公開→回収の外れ値の原因

### 調査の範囲と記録

main `04eddb5` からの調査。受入れの本測定は行っていない。以下はすべて原因調査用の独立runであり、直前の節の正式な標本・超過件数を置き換えない。コミット・ブランチ作成・プッシュ・tqueの変更は行っていない。

`-Dtask-main-diagnostics=true` を追加した。メインのtask API全体（TASK-WAIT-MANYを含む）、acceptanceログのflush、MS全体、Windows Sleepそのもの、stdoutのflush、標準イベント入力とKEY?を、既存のD07と同じホスト単調時計で囲む。WindowsではGetThreadTimesの差も保存する。CPU時間は更新粒度が粗く、記録値0を「命令を一切実行しなかった」という意味には使わない。262,144件の固定領域に保存し、終了時だけMAIN-SPAN行を出す。上書き件数を明示し、診断runnerは欠落・終了記録の不足を検出する。通常ビルドでは時計読み出し・保存領域・出力をcomptimeで除去する。

`tests/scripts/diagnose-task-main.py` は本測定runnerのmeasure/smokeを呼ばず、既存のworkloadsのfixtureと10msのメモリ監視を使う。各題材の10分を120秒×5プロセスに分け、公開・回収の時刻に重なる段階記録、各段階の最大時間、ホスト呼出しの外の100ms以上の空白を集計する。固定領域が全区間を保持できるように分割した診断であり、600秒連続プロセスの受入れ試行の代わりではない。

### 再現した空白

証拠は `.work/main-gap/run1/` と `.work/main-gap/run2/` のmanifest、raw、JSON、summary。実行体はいずれもReleaseFast/debug=false/strip=true、task-acceptance=true、task-native-probe=false、task-trace=false。run1は段階の壁時計、run2はそれにacceptance_flushの内訳とスレッドCPU時間を加えたビルドである。

- run1のI1は10分47,880タスク、100ms超過0件。G1-openは10分4,020タスクで1件（task 758、109.8201ms）再現した。TASK-STATEの入口62,371,354,864,000nsから出口62,371,453,136,000nsまで98.272ms、その中の管理巡は0.001ms。その後のSleepは11.8502ms。長い遅れはSleep内部ではなく、TASK-STATEの管理巡終了後にあった。
- run2のI1は10分47,885タスクで21件再現した。すべて最後の120秒プロセス `I1-004.raw.log` にあり、100ms超の三つの空白は下表のacceptance_flush内にあった。ホスト呼出しの外の100ms超の空白、段階記録の欠落はいずれも0件。

| acceptance_flushの開始→終了（ns） | 壁時間 | スレッドCPU増分の記録値 | 重なる公開→回収の外れ値 |
|---|---:|---:|---|
| 62,968,522,546,000 → 62,968,655,225,900 | 132.6799ms | 0 | task 1130〜1134（137.9962〜157.4436ms） |
| 62,999,626,755,300 → 62,999,753,504,800 | 126.7495ms | 0 | task 3601〜3605（159.8659〜181.1623ms） |
| 63,031,092,388,500 → 63,031,237,493,300 | 145.1048ms | 0 | task 6096〜6100（179.3227〜209.0329ms） |

残る6件も、39.6195msのflushと重なるtask 4850（103.0515ms）、74.9447msのflushと重なるtask 7344〜7348（111.3158〜132.4948ms）だった。100ms未満の出力待ちでも、結果確認・releaseまでの題材側の待ちと合わさるとD07を超える。既存ログの書き出しは管理巡の終了後なので、管理巡の短さだけでは検出できなかった。

stderrだけを専用スレッドへ移す案も診断したが、`.work/main-gap/fixed-run/I1-000.raw.log` のtask 960は101.9394msだった。MS全体103.3431msの内訳はstdout flush 96.5619ms、Sleep 6.7789ms。ForthのRESULT表示も同じログファイルへ書くため、stderrだけの変更では不十分だった。この案は撤回し、製品・acceptanceの出力コードは変更していない。後続の未完了プロセスは案の撤回時に中断し、完了済みのこの区間以外を比較値に混ぜていない。

### 候補の切り分けと修正

1. **Sleepの遅延**：再現した100ms超の主な空白はacceptance_flushまたはstdout flushの内部だった。MS全体をSleepの時間と読み替えない。timeBeginPeriodはソース内に呼出しがなく、電源プランは「バランス」だったが、これらを今回の原因とする根拠はない。製品のMSやOSのタイマー設定は変更していない。
2. **親の読取り遅れによるパイプ満杯**：旧workloadsのstdout/stderrは同じファイルへ直接接続され、出力パイプはなかった。この候補では旧runの空白を説明できない。一方、子が同期ログ書出しの中に長時間いたことは段階時刻で確認できた。
3. **Python・他プロセスとのCPUの取り合い**：長いflushのスレッドCPU時間の記録値は0で、メインが計算を続けていた記録ではない。ただし、待機とOSによる実行順の遅延はこの時計だけでは分けられない。瞬間的なCPU競合を完全に否定するデータはない。
4. **Defender等のファイル検査**：長い区間はログ書出しに一致するが、検査プロセスとの因果関係は未確定。※推測です：ファイルI/Oの待ちやファイル検査が寄与した可能性はある。DefenderやOSの設定は変更していない。
5. **ページフォールト・解放**：再現した長い空白は管理巡内の回収・解放ではなかった。ただし、ログ書出し内部のページフォールト等まで否定できるOS記録はない。

OSの実行待ち・I/O・ハードフォールトを分けるため `wpr -start GeneralProfile -filemode` も試したが、`Failed to enable the policy to profile system performance`、`0xc5585011`で開始できなかった。前後とも `wpr -status` は未記録。従って「Defenderが原因」「OS側で避けられない」とは断定しない。確定したのは、**測定器が子のstdout/stderrをファイルへ直接つなぎ、次の管理巡へ進むメインがその同期出力区間で長時間止まる経路**である。過去の正式runには段階記録がないため、過去の14件すべてのOS内部の原因を今回の記録で証明したとは扱わない。

Windowsのworkloadsだけ、親がstdout/stderrを同じパイプから専用スレッドで継続して読み取り、メモリへ保存する。ログファイルへ書くのは子の終了後である。読み取りの途中でファイル書出しを挟まない。ログ本体128MiBを上限とし、超過・読取りエラーは失敗として保存し、上限超過後もパイプを読み続けて子を詰まらせない。memory/nativeの実行中のログ照合、Linux/macOSの既存経路は変更しない。

D07のpublished/reclaimedと全管理巡の個別記録、fixture、供給待ち、結果取得・release、10msのメモリ監視は維持した。ログ受信時刻を子の時刻の代わりには使わない。`test-acceptance-output.py` は2万巡を実行し、全行の順序、子の終了前には親がログファイルを書かないこと、上限超過を失敗として扱いながら子を最後まで読み取ることを検証する。

### 修正後の診断と検証

証拠は `.work/main-gap/buffered-run/`。run2と**同じ実行体**（SHA-256 `d6573216fc6c9ac3c4f9f2826e66d2ae815d30a64c83a87c5216ceb680d437c7`）を使い、出力先と親の保存方法だけを変えた。I1・G1-openをそれぞれ120秒×5、計10分ずつ実行した。

| 題材 | タスク数 | 公開→回収100ms超 | 公開→回収の最大 | 管理1巡の最大 |
|---|---:|---:|---:|---:|
| I1 | 47,960 | 0 | 57.5116ms | 0.4897ms |
| G1-open | 3,854 | 0 | 16.4458ms | 0.2520ms |

100ms超のホスト区間、ホスト呼出しの外の100ms超の空白、段階記録の欠落も全プロセスで0件。D07の管理1巡1msの目安を維持した診断結果である。修正前にもI1で10分間超過0件のrunがあるため、この件数だけで正式な解消判定はしない。子の実行中のログファイル書出しを除いたことは、別の2万巡の回帰試験でも確認した。正式な再測定と受入れ判定はClaudeが行う。

通常経路は、HEADと変更後のソースを同じ配置で順にReleaseFast/debug=false/strip=true/task-acceptance=false/task-trace=falseにして比較した。計測呼出し側にもcomptime条件を付けた最終版のPE `.text` は、両方1,532,928 bytes、SHA-256 `955e53b3e44a95130d83f768441e815a60dad1bf064967988316c536794c5016`で全バイト一致（`.work/main-gap/normal-comparison/guarded-comparison.json`）。通常経路に計測命令の差分を導入していない根拠であり、速度の本測定を行った意味ではない。 呼出し側のcomptime条件を付けた後も、診断を有効にした最終実行体はrun2・buffered-runの実行体とSHA-256を含めて全バイト一致した（`.work/main-gap/diagnostic-final-comparison.json`）。上表は最終の計測コードに対応する。検証結果はこの節の末尾に記録する。

### Claude用の再測定コマンド

以下は手順であり、ロクは実行していない。リポジトリのルート、Windows PowerShellで実行する。通常の受入れビルドをrunnerが作る。task-main-diagnosticsは既定falseであり、本測定には付けない。計画v5とD07の区間定義は変更していない。確認参照は今回の測定器の変更を指す名前に置き換える。

```powershell
foreach ($n in 1,2) {
    python tests/scripts/run-acceptance.py --mode measure --only workloads --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN.md --plan-sha256 e96ba422a56d0afa294f572443a745c7d34152adb77e984283fd5340a064a7e8 --confirmed "REF-Windows-buffered-output-$n"
    if ($LASTEXITCODE -ne 0) { throw "workloads run $n failed" }
}
```

原因調査の再実行は本測定とは分ける。同じ計測実行体で `--output direct` と `--output buffered` を比べられる。各題材10分、120秒ごとに記録する。出力先は未使用のものに変える。

```powershell
zig build -Doptimize=ReleaseFast -Ddebug=false -Dstrip=true -Dtask-trace=false -Dtask-acceptance=true -Dtask-native-probe=false -Dtask-main-diagnostics=true --prefix .work/main-gap/recheck-build -j2
python tests/scripts/diagnose-task-main.py --sigma .work/main-gap/recheck-build/bin/sigma.exe --out .work/main-gap/recheck-direct --seconds 600 --only I1 G1-open --output direct
python tests/scripts/diagnose-task-main.py --sigma .work/main-gap/recheck-build/bin/sigma.exe --out .work/main-gap/recheck-buffered --seconds 600 --only I1 G1-open --output buffered
python tests/scripts/test-acceptance-output.py --sigma .work/main-gap/recheck-build/bin/sigma.exe
```

### 最終検証（Windows）

`.work/main-gap/checks-final/results.json` の11コマンドはすべて終了コード0。

- `zig build test`
- `zig build test -Ddebug=false`
- `zig build runtime-test`
- `zig build -Dtask-acceptance=true`
- `python tests/scripts/verify-task-examples.py`（17グループ）
- `python tests/scripts/test-acceptance-hold.py`
- `python tests/scripts/test-acceptance-macos.py`（14件）
- `python tests/scripts/test-acceptance-output.py --sigma zig-out/bin/sigma.exe`
- `python scripts/check-docs.py`（findings: 0）
- 変更したZig 5ファイル（build.zig、main、host_task_api、task_acceptance、task_main_diagnostics）の `zig fmt --check`
- `python tests/scripts/run-acceptance.py --mode smoke --only workloads`

最後のsmokeは `20261125T063740Z-e41a6347`。6題材すべてで親のメモリ保存経路、子の終了コード0、OS採取エラー0を確認した。正式な速度標本には使っていない。文書チェックの実装ハッシュ更新前の失敗は `.work/main-gap/checks/`、最終の成功は `checks-final/` に区別して保存した。日本語のTASK-STATE/TASK-RELEASE/TASK-WAIT-MANY/MS/EKEY?/KEY?の説明に意味の変更がないことを確認し、翻訳元の実装ハッシュを更新した。生成したリファレンス本文には差分がない。固定計画のSHA-256は `e96ba422…a7e8` のまま一致、`git diff --check` も成功した。本測定と禁止されたGit/tqueの操作は実施していない。

## 出力の保留の後の Windows の対話の場面の本測定（2026-11-25）

main `eb45fed`、計画v5（`e96ba422…a7e8`）。ClaudeがWindowsで実行した（15:46〜17:47 JST）。各題材10分×独立2回。run `20261125T064638Z-e22f81c2`・`20261125T074647Z-593d4db2`。

| 題材 | 投入→公開 最大（目安） | 公開→回収 最大（目安100ms） |
|---|---|---|
| G1-open | 38.6ms（100ms） | 16.2ms |
| G1-wall | 22.2ms（100ms） | 14.4ms |
| G1-snake | 42.4ms（100ms） | 16.8ms |
| G2 | 144.6ms（500ms） | 15.9ms |
| T1 | 8.4ms（200ms） | 11.7ms |
| I1 | 34.9ms（250ms） | 60.6ms |

2回とも、全題材・全指標で超過0件。管理の1巡の最大は0.517ms。80%超はI1のqueue_waiting=4だけで、題材の設計による。前回までWindowsだけに残っていた公開→回収の外れ値（I1で最大176.5ms）は、計測のログの同期の書き出しによるもので、親が出力をメモリに読み取る方式にした後は再現しなかった。前回までのrunの記録は消さずに残す。

## 最新のソースでの残りの項目の本測定（2026-11-25）

main `3a80b26`、計画v5（`e96ba422…a7e8`）・macOS計画v3（`44622846…83b8`）、確認参照 `lemon-approved-2026-11-25-final-rest`。Claudeが3 OSで同時に実行した（17:48〜18:01 JST）。対照Aは`35523f6`（Windows `D:/tmp/forthz-1382/.work/control-A`、Linux `.work/control-A`、Mac `.work/1383/control-a-build`）。

| 項目（目安） | Windows | Linux | Mac |
|---|---|---|---|
| run（Snapshot・メモリ・入力の反映） | `20261125T084814Z-8d7094e2` | `20261125T084806Z-4269e6d6` | `20261125T084809Z-72cea647` |
| Snapshotの取得 最大（50ms） | 12.8ms | 15.7ms | 31.0ms |
| Snapshotの大きさ 最大（4MiB） | 3,620,330 B（80%超） | 3,620,338 B（80%超） | 3,620,338 B（80%超） |
| 追加のメモリ（128MiB） | committed 差 最大77.1MB | committed 差 最大77.0MB | phys_footprint 差 最大68.9MB |
| 入力→状態の反映 最大（16.67ms） | 0.617ms | 1.349ms | 0.565ms |
| 起動時間 中央値・p95の増加（10ms・20ms） | +0.024ms・−0.068ms | −0.022ms・−0.022ms | 下記 |
| 実行ファイル全体の増加（256KiBかつ10%） | +155,136 B・+6.72% | +160,080 B・+6.73% | +131,456 B・+6.44% |
| コード部分（.text・__text）の増加（128KiBかつ10%） | +107,536 B・+7.54% | +107,424 B・+8.40% | +88,636 B・+8.84% |

- 起動時間の目安は、D07 7節の中央値増加10ms以内・p95増加20ms以内である。Macの起動時間は100回の測定を3回行った：`20261125T085914Z-93419dc0` 中央値+0.033ms（+1.61%）・p95+0.052ms（+2.23%）、`20261125T090056Z-b099dab4` −0.007ms・−0.063ms、`20261125T090057Z-24bac77a` +0.008ms・−0.004ms。3回とも目安内。1回目は中央値・p95の増加率が、単一VM実行時間の目安（+1%・+2%）を上回ったため、1,000回で測り直した（下記）。3回とも記録として残す。
- メモリの`missing 3`は、Snapshotの題材にタスクの行がないことによるもので、従前と同じ。queue_waiting=4はI1の題材の設計による。
- Windowsの待ち中の取消しの追加1,000回（`20261125T090001Z-7edefb21`）：要求→公開 最大0.0063ms、要求→停止 最大0.649ms、要求→回収 最大17.2ms。超過0件。最初の本測定の54msの1件は再現しなかった。
- サイズの目安は、D07 7節の実行ファイル増加256KiBかつ10%以内、.text増加128KiBかつ10%以内である。3 OSとも目安内。80%超は、.textの相対増加のLinux（84%）・Mac（88%）と、.textの絶対増加のWindows（82%）・Linux（82%）。7節は目安内でも自動承認せず、レモンが生成差分と個別に判断する。
- D07 7節の単一VM実行時間（負荷ごとの中央値増加1%以内・p95増加2%以内、A/A′/Bの比較）は、このrunnerでは測っていない。未確認として残す。

**Macの起動時間の測り直し（利用者の決定 2026-11-25、B）：** 1回目の増加率が+1%・+2%を上回ったため、起動の試行を100回から1,000回に増やして1回だけ測り直し、その結果で判定する。結果を見た後で、都合のよい集計の方法を選ばないためである。先の3回の記録は残す。

**Macの起動時間の1,000回の測定（2026-11-25）：** run `20261125T090233Z-49332dc5`（Macの作業ツリーは `3a80b26`、macOS計画v3）。A・Bとも1,000回。中央値 A 1.952ms・B 1.964ms（+0.012ms、+0.62%）、p95 A 2.096ms・B 2.102ms（+0.006ms、+0.27%）。D07の起動時間の目安（10ms・20ms）を満たし、増加率も+1%・+2%以内だった。決定Bに従い、Macの起動時間はこの結果で合格と判定する。

## コードの大きさの増加の内訳（2026-11-25、利用者の決定B）

D07 7節は、サイズが目安内でも自動承認せず、生成差分と個別に判断すると定める。そのため、Linux（main `ac01151`）で、対照A（`35523f6`）と新しい版Bを、どちらも `-Doptimize=ReleaseFast -Ddebug=false -Dstrip=false`（Bは `-Dtask-trace=false -Dtask-acceptance=false`）でビルドし、`nm -S` で関数（t/T）の大きさを比べた。ジェネリックな関数の名前の後ろの番号（`__func_N`・`__anon_N`）は、ビルドごとに変わるので取り除いて合算した。関数の合計は A 1,274,526 B → B 1,381,044 B（+106,518 B）で、本測定の.textの増加（+107,424 B）とほぼ一致する。

| 分類 | 増加 | 主な内容 |
|---|---|---|
| タスクのサービス・中核（新規） | +77,588 B | host_task_api +29,883、task_job_queue +13,704、task_schedule_host +9,935、host_task_wait +5,546、task_reap +5,033 など |
| Forth VM | +15,713 B | ワーカー用の実行ループ runOperationsLoop の2つ目の実体 +11,112、executeWordMode +4,464、executeBuiltin +2,077、executeWord −2,524 |
| Snapshotの画像 | +8,648 B | image_restore +4,741、image_encoder +2,504、image_restore_plan +1,403。core.dictionary_image −8,233 から分けて移したもので、差し引きはほぼ0 |
| Zigの標準ライブラリ | +2,352 B | Thread +2,116 など |
| その他 | +2,217 B | error_reporting +5,169 と main.reportDiagnostic −5,029（移動）、main.run +1,894、words_help +1,185 など |

Forth VMの増加の大部分は、取消しの確認をワーカーの実行ループにだけ入れるために、実行ループをコンパイル時に2通り作る方式（決定済み）による。通常の経路の実行ループに確認は入っていない。比較の生データは、Linuxの機械の `.work/sizediff/report2.txt` にある。

**コードの大きさの増加の承認（利用者の決定 2026-11-25、A）：** 上の内訳をもとに、レモンが3 OSの実行ファイル・コード部分の増加を承認した。

## 80%規則による追加の測定（2026-11-25、利用者の決定B）

Snapshotの大きさとI1のqueue_waitingは、題材の作り方で値が決まり、毎回同じになる。それでも、固定した計画の規則を結果を見てから解釈で外さないため、規則どおり回数を増やして測った（レモンの決定B）。main `f5dcd15`、計画v5・macOS計画v3、確認参照 `lemon-approved-2026-11-25-extension-80pct`、18:26〜18:29 JST。

| 項目（上限） | Windows | Linux | Mac |
|---|---|---|---|
| run（Snapshot 1,000プロセス×3世代） | `20261125T092612Z-992f9968` | `20261125T092605Z-7b4c10ee` | `20261125T092608Z-3fa3a22b` |
| Snapshotの大きさ 最大（4MiB） | 3,620,330 B | 3,620,338 B | 3,620,338 B |
| Snapshotの取得 最大（50ms） | 13.2ms | 16.5ms | 32.2ms |
| run（メモリ 7題材×10回） | `20261125T092700Z-552b637a` | `20261125T092712Z-c36d1684` | `20261125T092650Z-40ebbe5b` |
| 追加のメモリ 最大（128MiB） | committed 差 77.1MB | committed 差 77.0MB | phys_footprint 差 68.9MB |
| queue_waiting 最大（4） | 4 | 4 | 4 |

3 OSとも超過0件。Snapshotの大きさは、題材がSnapshotに約300万バイトのデータを持たせているため、毎回同じ値になる。queue_waiting=4は、I1の題材が待ちを常に4件に保つためで、上限で拒否などの不具合は起きていない。対話の場面のI1は、規則どおり各OSで独立に2回測った（前節まで）。メモリの`missing 10`は、Snapshotの題材にタスクの行がないことによる（従前と同じ）。

## 2026-11-25 受入れ全体の判定

最新runによるAC別・OS別の判定、過去runの置換、利用者決定、未確認事項の確認方法と担当は[受入れ総括（日本語）](TASK_CONTROL_ACCEPTANCE_SUMMARY.ja.md)・[Acceptance summary (English)](TASK_CONTROL_ACCEPTANCE_SUMMARY.md)に記録した。本報告の準備時点の「未実施」や旧runは履歴として保持し、現在の全体判定は総括を参照する。
