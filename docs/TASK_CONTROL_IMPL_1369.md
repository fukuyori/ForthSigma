# タスク制御03-B（1369）実装記録

作成日：2026-11-24。基点は detached HEAD `83987a2` である。公開Forth語・公開エラー値の追加はない。

## 変更ファイルと要点

| ファイル | 変更内容 |
|---|---|
| `src/core/task_wait.zig` | 固定容量の待機登録、全対象検証・接続・逆順解除、成立集合、独立した中断・呼出し期限・障害印、最早期限、登録世代を追加した |
| `src/host_task_wait.zig` | 非消費の入力adapter、task_queueの完了受領adapter、ホスト中断印の合成、共通Wakeとnative対象の同時待機を追加した |
| `src/host_signal_pipe.zig` | POSIX信号ハンドラーの非待機writeと、所有ホストでの有限量の排出を追加した |
| `src/host_wake.zig` | 共通Wake＋複数fd、Windowsコンソールの多重待機を追加した。POSIXのread→pending.swap(false)→世代再照合を維持した |
| `src/host_input.zig` | Windows入力レコードの保持処理を共用化し、複合待機のprobeから利用可能にした。未処理のnative／保持レコードがあれば眠らない |
| `src/main.zig` | I/Oの非消費probeを分離し、WAIT-FILESから再利用した。内部I/O adapterとnative監視対象の取得を追加した。初回reader/writer起動より前にRuntimeの共通Wakeへ接続した |
| `src/host_runtime.zig` | native producerがWakeを借用中である場合、Runtimeの破棄をResourceBusyで拒否する保護を追加した |
| `src/host_wait.zig` | POSIX信号scopeの開始・復旧にセルフパイプの寿命を結合した |
| `src/tests/task_wait_test.zig` | OSに依存しない登録・競合・偽時計・容量の試験を追加した |
| `src/tests/task_wait_host_test.zig` | 実Wake、タスク終端、入力peek、native待機、POSIX信号パイプ、借用中Wakeの保護を試験する |
| `src/forth_test.zig`、`src/runtime_test.zig` | 前者にコア試験、後者に実ホスト依存試験を登録した |
| `build.zig` | runtime試験で参照するState・入力型のため、既存build_optionsをruntime試験moduleにも渡した |

## 設計上の選択と理由

### 登録・結果・寿命

一つのRegistrationの対象上限は64件である。台帳16件を待機対象上限へ読み替えてはいない。対象一覧と結果配列は固定領域であり、途中の成立で走査を打ち切らない。重複対象は元の対象番号ごとに結果を残す。native待機側は同じ監視条件を重複除去する。

このAPIは公開ハンドルを受け取るAPIではなく、所有ホストが検査・保持した内部参照を受け取る。対象の所属・資源世代を外側の台帳で検査した後に使用する契約である。Source.validateで全件を検証してからattachする。失敗したattachは自身の部分取得を戻し、既に接続したSourceは逆順でdetachする。具体的adapterは登録のスタックや返却配列をproducerへ渡さず、producerは資源寿命の共通Wakeだけへ通知する。

RegistrationとSource context、入力VM、Queue、Job、ファイルslotはcloseまで固定・保持する。登録中に同じfileidをclose・再利用してはならない。Task adapterはqueue.pollを使うため、Queueへ受理済みの、当該Queueに属するJobを渡す契約である。公開ハンドルの解決と保持参照管理をこのモジュールへ重複実装してはいない。登録世代は再利用時に増加し、枯渇時は登録を拒否する。

返却集合を得た時点を封印点とし、その後のcloseは通知接続だけを解除する。解除中の成立を既に返した集合へ追加せず、供給元の保持状態から次回取得する。現在のadapterのdetachには失敗するnative操作やproducer callbackの差し替えがない。readerは登録解除で停止せず、ファイル本来の所有者が終了させる。

### 時計・終端・取消し

毎巡、Wake世代を観測し、全Sourceのprepareでタスク完了をacquire受領してから全対象をprobeする。Task adapterはRELEASE済みJobの完了も排出した後、外部解放を返す。取消し要求だけでタスク終端を作らず、結果も消費しない。キュー期限はqueue.nextDeadlineから得る。

個別時計対象と呼出し全体の期限は別々に保持する。同時成立は対象番号・kind・識別値・成立理由・補助情報の配列で返し、中断、D到来、ホスト障害を別印で保持する。再起床でDを延長しない。Clockは注入可能である。ESC確定待ちの期限も最早期限へ含める。

待機側Cancellationは対象JobのCancellationとは別である。requestCancellationは当該登録のトークンを公開してから共通notifyする。ホスト側は `host_task_wait.poll(&registration, guard.inputInterrupted())` を使用し、入力対象がない場合も信号中断印を結果へ合成する。信号scopeは呼出し側が既存host_waitの所有規則で保持する。

native待機にはprobeが得た最早期限を渡す。1msの周期的打切りは撤去した。既存Wakeの20ms回復確認上限は維持する。描画・フレーム・子入力等のホスト巡回が必要な呼出し側は、それらを進め、その次回期限もResult.nextへ合成する。againが立った場合は眠らず次のホスト巡回へ戻る。

### 入力・I/O・OS待機

通常入力は既存decoderのmodern(..., 0, true)を使い、意味イベントを消費しない。modern_depth中の再入probeはHostFailedで拒否する。リダイレクト入力ではmodernを呼ばず、専用の非消費I/O Sourceを使用する。イベント・EOF・障害・中断を区別する。

Windowsではフォーカス・キー解放を含め、OSのレコードを既存のホスト所有64件キューへ順番どおり保持する。既存decoderが順に解釈するため、物理キー状態の更新も捨てない。容量・一巡の予算で処理が残ればagainを返す。既存EXECの保持処理も同じread／retain操作を使う。

I/Oは設計6.2節の起動時統合案である。mainのRuntime初期化直後、reader/writer起動前にcommon_io_runtimeを結び付ける。ioWakeは以後Runtimeのnative_wakeを返す。reader/writerのstartや通知コードの変更、稼働中の通知先差し替えは不要である。既存file_wakeはRuntimeを持たない単独ホスト試験用のfallbackとしてのみ残る。共通待機へfile_wakeを加えない。WAIT-FILESと共通待機の消費者はいずれも同一の所有ホストであり、同時に別スレッドから待機してはならない。

Windowsで追加可能なnative対象はコンソールだけであり、GetConsoleModeによる検査で別の自動リセットイベントを拒否する。共通Wakeを含むOS上限に従い、追加63ハンドルまでである。POSIXは共通Wakeのfd＋追加最大64fdである。host側sleepは信号パイプの枠もこの上限へ算入し、超過を拒否する。対象数64と、必要なnative監視数は別々に検査する。監視集合はInput.interest／IoWaitSource.interestから構築する。

POSIX信号ハンドラーは中断印の設定とセルフパイプへのwriteだけを行い、Wake.notifyは呼ばない。パイプは非待機・CLOEXECであり、ハンドラーのerrnoを保存する。所有ホストが有限量を読んで共通notifyする。旧ハンドラーの復旧後に書込fdを無効化し、借用中ハンドラーの終了を同期してからcloseする。非Linuxのpipe＋fcntl設定は、既存Wakeと同様、同じ所有ホストでの子生成と直列化する前提である。

### 容量予算

Registration＋Resultの静的サイズが32KiB未満であることを試験で検査する。この領域を、決定済み128MiB内の「キュー・台帳・通知・取消しトークン1MiB」から32KiBの枠として計上する。一つの所有ホストで活動中の共通登録は一つとする。native対象の固定配列と信号パイプ等のOS管理分も同じ通知枠に含める。入力レコードは既存の64件領域を再利用し、新しいreaderスレッド・VM・動的キューは作らない。OS別の実予約量・全機能結合時の合計は未測定であり、128MiB全体の適合を証明したものではない。

## 担当外の変更と通常経路への影響

上表のhost側既存ファイル、試験root、build.zigを変更した理由は、実際の供給元と共通登録の接続、通知先の寿命保護、OS依存試験の分離である。task_queueを含む他タスクのcoreモジュールは変更していない。

通常経路の変更は次のとおりである。

- I/Oの通知先が起動時からRuntimeの共通Wakeとなり、寿命の借用数を保持する。
- WAIT-FILESのprobeを同じ処理内容の共用関数へ移した。先頭成立の返却、byteの戻し、期限と中断の扱いは維持する。
- 既存Wake.wait／waitReadableは多重待機実装へ委譲する。Windowsで追加対象がない場合は従来どおりWaitForSingleObjectを使う。
- WindowsのEXEC入力レコード保持をread／retainに分け、共通待機からも使用する。
- POSIXの既存信号scopeにセルフパイプの作成・復旧を追加した。復旧失敗の優先規則は変更していない。
- Runtime.deinitはnative producerが借用中のWakeも破棄しない。

forth.zig、通常命令ループ、State配置、worker許可集合は変更していない。通常経路へ命令ごとの定期取消し確認を追加していない。

## 試験と実行結果

前回実装時には次の検証が成功した。今回の再検証結果は末尾に記す。Zigは0.17.1である。PowerShellから実行し、ZIG_GLOBAL_CACHE_DIRとZIG_LOCAL_CACHE_DIRを作業ツリー内の.zig-cacheへ指定した。既定キャッシュではmanifest_create AccessDeniedとなったためである。並列数は-j2に制限した。

| 実行項目 | 結果 |
|---|---|
| `zig build test -j2` | 成功 |
| `zig build test -Ddebug=false -j2` | 成功 |
| `zig build runtime-test -j2` | 成功 |
| `zig build -Dtarget=x86_64-linux -j2` | 成功。実行は未実施である |
| `zig build -Dtarget=aarch64-macos -j2` | 成功。実行は未実施である |
| `zig build runtime-check -Dtarget=x86_64-linux -j2` | 成功。追加のPOSIX待機・信号パイプを含む試験実体のコンパイルである |
| `zig build runtime-check -Dtarget=aarch64-macos -j2` | 成功。追加のPOSIX待機・信号パイプを含む試験実体のコンパイルである |
| 変更した全Zigファイルの `zig fmt --check` | 成功 |
| `git diff --check` | 成功。GitのCRLF変換予告は出るが、空白エラーはない |

追加試験は、登録前／attach中の成立、解除中の状態保持、probe直後の通知、複数対象の同時成立、中断と期限の同時成立、固定D、通知併合、部分登録の巻き戻し、対象数超過、静的容量、偽時計、タスク終端の非消費受領とRELEASE、入力peekとESC期限を扱う。Windowsのフォーカス・キー解放・キー押下の保持順序は注入readerで検査する。POSIXセルフパイプ試験はクロスコンパイルのみであり、Windows上ではskipする。

試験作成中に、偽時計を進めず未到来の期限を待つ不備で自分の試験セッションが待ち続けた。該当セッションを中断し、既到来の絶対期限を明示する試験へ修正して再実行した。識別子重複と取消しAPIの呼出し不一致によるコンパイルエラーも修正した。これらの途中結果を最終成功として扱わない。

## 未確認事項

- Linuxでの実行はClaude側の別機械で行う対象であり、ここでは実施していない。macOSの実行も未実施である。
- 実Windowsコンソールへフォーカス・キー解放が大量到着する場合の手動操作と、POSIX実SIGINT配送中の復旧競合は未確認である。注入reader／セルフパイプ単体試験を実機受け入れの代わりにしない。
- フレーム・描画・子入力を含む最終ホスト巡回と、公開ハンドル台帳による参照保持を結合した利用側の受け入れは後続である。今回の内部APIの寿命契約を守る必要がある。
- 要求→停止10ms、回収100ms、60Hz、管理1ms／巡、全体128MiBの測定は行っていない。性能・時間条件の達成を主張しない。
- インストーラー・パッケージは作成していない。コミット・タグ・ブランチ・push・tque変更は行っていない。

## 利用者の判断が必要な事項

今回の内部APIのために公開仕様を決める必要はない。方式全体の受け入れ、公開語・公開値、性能条件の判定は従来どおり保留である。今回追加した通常経路の変更は上記の一覧をもとに差分確認の対象となる。

## 最終作業ツリー

`git status --short`で変更・新規ファイルは次の14件である。基点のコミットは変更していない。

```text
 M build.zig
 M src/forth_test.zig
 M src/host_input.zig
 M src/host_runtime.zig
 M src/host_wait.zig
 M src/host_wake.zig
 M src/main.zig
 M src/runtime_test.zig
?? docs/TASK_CONTROL_IMPL_1369.md
?? src/core/task_wait.zig
?? src/host_signal_pipe.zig
?? src/host_task_wait.zig
?? src/tests/task_wait_host_test.zig
?? src/tests/task_wait_test.zig
```

## レビュー修正（2026-11-24）

指摘1〜10をソースと設計に照合し、すべて妥当と判断した。

1. sleepの1ms打切りを撤去した。通知・native対象・最早期限で起床する。既存Wakeの20ms回復確認は維持する。probe後の公開を、時計アクセスが失敗する注入条件でも通知世代だけで受領する試験を追加した。回復期限の返却に依存しない試験である。
2. WindowsのCtrlハンドラーは中断印を立て、借用中の共通Wakeへnotifyする。sleep入口で接続し出口で解除する。接続前の中断も接続時に通知する。ハンドラーと解除はread_lockで同期し、借用後の参照を防ぐ。ハンドラー関数の直接呼出しによる通知試験を追加した。実Ctrl+C配送は未確認である。
3. sleepは登録のWakeOpsとnative Wakeのcontextおよび全操作関数の同一性を検査する。不一致やinjected WakeをHostFailedとして拒否する。別Wakeを渡す回帰試験を追加した。
4. 保持レコードのfor_execution印で用途を分けた。待機保持はexecution_capturedを立てず、EXEC候補走査とleave時のEXECバイト再投入に含めない。通常decoderは両用途を処理する。注入readerで順序・印の不変・EXEC走査からの除外を検査する。
5. modernへの再入probeをHostFailedとし、againによる無制限再試行を防いだ。再入拒否の試験を追加した。
6. host_task_waitとmainは消費前のpendingを使うため、フォーカス・キー解放だけのレコードの後に眠らない巡が1回余分に起き得る。有限のため変更しない。
7. Result.cancelledを追加し、登録取消しをinterrupted（SIGINT／入力UserInterrupt）から分離した。両印・成立集合・期限・障害は独立して保持する。単一処理を選ぶ呼出し側の優先順は、障害、利用者割込み、登録取消し、成立集合、呼出し期限である。結果自体は情報を捨てない。復旧失敗の優先は従来どおりである。Windowsの追加コンソール成立時もPOSIXと同じく取消しを先に確認する。同時成立の試験を追加した。
8. reader停止失敗でnative_usersが残るとRuntime.deinitはResourceBusyとなり、runは資源保持の診断と終了コード1を返す。従来のfile_wakeを保持して正常終了する挙動から変わる。借用先の解放後使用を防ぐ保護である。
9. POSIX信号Scope.beginのパイプ作成失敗はHostFailedになる。EMFILE等によりNS／KEYの信号scope開始が失敗し得る点は通常経路に加わった失敗条件である。
10. 入力adapter試験はsupport.createMachine／destroyMachineでStateを正規に初期化する。必要な埋込みテキストと浮動小数点実装をruntime試験モジュールへ追加した。

今回修正したファイルはsrc/core/task_wait.zig、src/host_task_wait.zig、src/host_wait.zig、src/host_wake.zig、src/host_input.zig、src/tests/task_wait_test.zig、src/tests/task_wait_host_test.zig、build.zigと本報告書である。担当外変更の理由は上記2・4・7・10に対応する。通常命令ループ・worker許可集合・公開Forth語と公開エラー値には変更がない。

新たな利用者判断事項はない。性能・時間測定は行っていない。Linux実行はClaude側、macOS実行と実端末操作の受入れは未確認である。

### レビュー修正後の最終検証結果

PowerShellで作業ツリー内のキャッシュを指定し、Zig 0.17.1で次を実行した。すべて終了コード0である。並列数は-j2とした。測定は行っていない。

| コマンド | 結果 |
|---|---|
| `zig build test -j2` | 成功 |
| `zig build test -Ddebug=false -j2` | 成功 |
| `zig build runtime-test -j2` | 成功 |
| `zig build -Dtarget=x86_64-linux -j2` | 成功。実行は未実施 |
| `zig build -Dtarget=aarch64-macos -j2` | 成功。実行は未実施 |
| `zig build runtime-check -Dtarget=x86_64-linux -j2` | 成功。POSIXの試験実体のコンパイル |
| `zig build runtime-check -Dtarget=aarch64-macos -j2` | 成功。POSIXの試験実体のコンパイル |
| 変更した全13件のZigファイルの `zig fmt --check` | 成功 |
| `git diff --check` | 成功 |

途中の検証では、試験用Stateの正規初期化に伴う埋込みLICENSEとcr_*関数の未登録によるコンパイル・リンク失敗を検出した。build.zigに既存の登録関数を適用して修正し、上記の再実行で成功を確認した。試験用レコードの初期化に混入した未定義識別子も修正済みである。途中の失敗を成功結果へ含めていない。

最終のgit status --shortは前節の14件と同じである。HEADは83987a2のままである。コミット・タグ・ブランチ・push・tqueの変更は行っていない。
