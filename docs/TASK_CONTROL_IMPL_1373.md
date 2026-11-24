# タスク1373：タスク制御04-A 取消しの実装

作成日：2026-11-24。作成者：ロク。基準は専用worktreeのHEAD `83987a2ce1ea22d333eae4a05cc532928d9cd275` である。

## 1. 実装内容

タスク固有の取消しトークン、ホスト台帳の要求の写し、実行結果による終端確定を接続した。MemoryGateをワーカーのcomptime実体へ接続し、task_jobのメモリ入口一律拒否を外した。公開Forth語・公開エラー値は追加していない。

| 変更ファイル | 要点 |
|---|---|
| `src/core/task_memory.zig`（新規） | 許可済みメモリ語全種類の範囲・処理量の事前検査、nativeの前後の取消し確認、VM固有の許可領域表である |
| `src/core/task_cancel.zig`（新規） | ホスト所有のBindingで台帳ID・owner・固定したJobを対応付ける。取消し／RELEASEを転送し、キューが公開した結果から台帳を一度だけ終端へ進める |
| `src/core/task_job_queue.zig`（新規） | キューのrunnerからtask_jobを呼ぶ。Job固有のCancellationを渡し、TaskCancelledだけをcancelledへ変換する。未実行取消しでもAdmissionを解放する |
| `src/core/task_context.zig` | threadlocalスコープにMemoryGateとnative上限を保持する。Stateのフィールドは増やさない。入れ子・別VMの退避復帰を保つ |
| `src/core/task_job.zig` | 復元したVMの許可領域表を作り、inspectと実行に同じGateを渡す。native上限指定用の内部Optionsを設ける。入口前の取消し確認を加える |
| `src/core/task_queue.zig` | ロック下でphaseを照会するphaseOfを加える。sealed後・ホスト受領前の要求もトークンへラッチするが、封印済み結果は変えない |
| `src/core/task_ledger.zig` | 内部終了・停止診断等で設定された原子的要求を、ホストが台帳へ写すlatchCancellationを加える |
| `src/core/task_permissions.zig` | 既存policyを実行時防壁と共有するため内部公開する。許可集合そのものは変えない |
| `src/core/task_policy.zig` | 検査未接続の語種・Op・builtinへ抜けないよう実行時防壁を狭める。スカラー出力・KEY-IORを既定では拒否する。テスト実行体で明示設定した境界試験だけに例外を限定する |
| `src/forth.zig` | ワーカー専用入口WithMemory、builtin／直接primitive／文字列リテラルへのcomptime worker側の接続である |
| `src/tests/task_cancel_memory_test.zig`（新規） | メモリ防壁・native上限・実用入口・状態隔離・通常実行との結果比較である |
| `src/tests/task_cancel_queue_test.zig`（新規） | 実キュー・新規VM・台帳の結合、未実行取消し、D04の偽の公開同期点による順序試験である |
| `src/tests/task_job_test.zig` | メモリ操作を一律拒否する旧期待を、実行時の領域拒否へ更新する |
| `src/forth_test.zig`／`src/runtime_test.zig` | コア試験と実ホストWakeを使う結合試験を別のルートに登録する |
| `build.zig` | runtime-testで新規VMを実行するため、既存のbuild_options・埋込み文書・CORE-MATHを同ルートへ渡す |
| `scripts/compare-task-1373-code.py`（新規） | 1355方式のPDB／ELFシンボル抽出、静的逆アセンブル比較を再現する補助である |
| `docs/measurements/2026-11-24-task-1373-generated-code.json`（新規） | 生成比較のサイズ・命令行数・ハッシュ・正規化条件・ソースハッシュを記録する |

## 2. 設計上の選択

### 取消しと終端

workerはJobの原子的Cancellationだけを読む。ホスト台帳はworkerへ渡さない。Bindingのcancel／releaseが台帳とキューを結び、pollでキューの取得と封印済み結果を受領する。ホストの終了等で設定されたトークンもpollで台帳へ写す。要求は解除せず、Jobを再利用しない。

既存の1024 Opごとのworker専用確認を維持し、メモリnative操作の直前・直後と文字列リテラルのヘッダー読取り前後にも確認する。TaskCancelledのCATCH回復除外は1384の実装を維持する。初期版のworker自身のCATCH／THROWは禁止のままである。

成功・失敗の帰還後に要求を読んで結果を置き換える処理は設けない。取消しを確認してTaskCancelledで帰還した場合だけ取消しとする。結果コピーが失敗した場合はfailedである。RELEASE後も内部結果を受領し、実行側参照を落とすのは受領後である。未実行項目はキューが排他的に取り出し、Admissionを解放してから取消しを公開する。Bindingはホスト専用であり、Job・Execution・owner・台帳IDの対応と寿命を固定して使う。

### MemoryGateとnative量

builtin入口、call／call_builtin／builtin Op、特殊化された直接primitiveを同じ事前検査へ通す。入力・辞書データ領域と使用中ヒープペイロードを許可し、system・従来の入力バッファ・block buffer・heap header・空きheap・local frameは許可しない。入力ABIのバイト列は従来どおり辞書データ領域に所有コピーされる。データ領域の上端はtransferのABIと同じdataLimitである。

アドレスの加算・配列indexの乗算・処理量の合算はオーバーフローを検査する。MOVE等は全ての読取り・書込み範囲を検査してから実行する。読取り変更書込みでは両方のAccessを渡す。Gateとその領域表は実行VMだけに属し、範囲検索は整列済み領域表の二分探索とする。未接続の論理メモリ経路は実行時にも拒否する。

native上限の既定値は64 KiBであり、内部Optionsで設定できる。量はアクセスする範囲の合計である。したがってMOVEの既定の最大コピー長は32 KiBである。SEARCHはさらにtext長×max(1, pattern長)で比較仕事量を保守的に制限する。超過は実行前に既存のInvalidAddressで失敗させ、公開エラー値を増やさない。

+PLACEはカウントのヘッダーを事前検査中に読まない。全範囲をまとめて検査するため、宛先256バイトと最大入力長を保守的に要求する。このため、小さなheapペイロードへの+PLACEは、実際の追記が収まる場合でも拒否することがある。通常経路の仕様は変えない。

既存のaddress_registryはイメージ再配置の追跡用であり、MOVEやセル書込みに付随する台帳処理・heap探索がnative量の制限を迂回する。task_jobは入力準備後、実行直前に使い捨てVMの私有再配置台帳を破棄する。workerではイメージ保存・再配置・heapの確保解放を許可せず、結果は独立した生バイト列としてコピーするためである。直接のworker呼出しで再配置台帳が残る場合は、メモリ語をInvalidExecutionTokenで拒否する。元Snapshot・メインVMの台帳やデータは変えない。

### 担当外ファイルの変更理由

forth.zigの接続は直接primitiveとbuiltinの両経路を閉じるために必要である。MemoryGateをStateに追加せずtask_contextへ保持するため、同モジュールも変更した。task_permissionsのpolicy公開とtask_policyの縮小は、未検査の論理メモリ経路を拒否するためである。task_jobの旧拒否解除と私有再配置台帳の破棄は1362の引継ぎに対応する。task_queueのphase照会とsealed時のラッチ、task_ledgerの要求の写しはホスト台帳とworkerの対応を安全に結ぶためである。

試験ルート2本とbuild.zigの3行の追加は、実ホストを使う新規VMの結合試験をruntime-testへ置くために必要である。既存task_job試験の期待変更は、一律拒否を外した後の実際の領域検査へ合わせたものである。その他のホスト実装・転送ABI・Snapshot形式・公開語・バージョンは変更していない。

## 3. 試験結果

最終結果は後述の検証欄に記載する。PowerShell、Zig 0.17.1で実行した。速度・時間の測定、パッケージ作成、tque変更、Gitのcommit・branch・tag・pushは行っていない。テスト内の期限はハング検出用のwatchdogであり、応答時間の測定ではない。

- 全ての許可済みメモリbuiltinについて、system領域を使った拒否と、拒否前のオペランド不変を確認する。
- 全ての許可済みメモリbuiltinについて、正当なデータ領域で通常実行とworker実行のスタック・メモリ結果を比較する。
- storeをprimitive／builtin／call_builtin／callの4エンコードで実行し、拒否と成功を確認する。
- system・block buffer・heap header・local frame・負数・最大セル値・領域末尾をまたぐアクセス、index乗算オーバーフローを拒否する。
- 使用中heapペイロードの成功と、その前後・local frameの拒否を確認する。
- MOVEの宛先が正当でも元が不正なら書き込まないこと、設定した7／8バイト上限の境界、既定65536／65537バイトの境界を確認する。
- nativeの前では要求を確認して効果を出さず、Gateの偽の同期点で要求した場合はnativeの後にTaskCancelledを返すことを確認する。
- 入力を読む入口、FILLで結果を書く入口、変数への書込みを含む仕事の連続実行、元VMの変数不変を確認する。再配置台帳を持つSnapshotも含む。
- 実キューのworkerから新規VMを動かし、結果BBBと台帳succeededを確認する。未実行取消しではタスク固有トークン、台帳の写し、Admission解放を確認する。
- 偽の公開同期点で、要求→TaskCancelled、正常帰還→RELEASE→封印、成功確定→要求、他エラー帰還→RELEASEを再現する。既存task_queue試験の要求→未確認の正常帰還も含め、D04の結果不変を確認する。
- 純ForthのBEGIN系、入れ子、特殊化・インライン後、通常側のinterpreted／compiled CATCHを通過する取消し、禁止語・未検証DO系・context復帰は既存W1／1384試験を含めて再実行する。

## 4. レビュー修正前の通常経路の生成コード比較

本節と測定JSONは修正前の記録である。今回の修正後の生成コード比較は再実行していない。最新ソースの生成結果を示す証拠としては使用しない。

基準ソースは同じworktree内の `.zig-cache/1373-base/` へ `git archive HEAD` から展開した。Gitの別worktree・branchは作らず、作業ツリー外へ書き込んでいない。1355と同様にWindows／Linux x86_64、Fast／Small、debug=false、strip=false、CPU baseline、既定の語群・容量で比較した。

```powershell
$env:ZIG_GLOBAL_CACHE_DIR = "$PWD/.zig-cache/global"
# 基準側と変更側で、次の4組を実行する。
zig build -Dtarget=x86_64-windows -Doptimize=fast -Ddebug=false -Dstrip=false --prefix zig-out/1373/windows-fast
zig build -Dtarget=x86_64-windows -Doptimize=small -Ddebug=false -Dstrip=false --prefix zig-out/1373/windows-small
zig build -Dtarget=x86_64-linux -Doptimize=fast -Ddebug=false -Dstrip=false --prefix zig-out/1373/linux-fast
zig build -Dtarget=x86_64-linux -Doptimize=small -Ddebug=false -Dstrip=false --prefix zig-out/1373/linux-small
# 変更側ルートで抽出・比較する。
python scripts/compare-task-1373-code.py
```

Windowsはllvm-pdbutilのS_LPROC32、Linuxはllvm-objdumpのELFシンボルから対象を特定し、llvm-objdumpのIntel形式の静的逆アセンブルを比較する。命令アドレス、関数内分岐先、関数外call先のシンボル、RIP相対再配置を正規化する。その他の即値・State参照変位・レジスタ・命令順は保持する。正規化の限界はJSONにも記録した。補助ツールはLLVM 22.1.8である。

| 構成 | plain runOperationsのbyte／命令行 | plain executeWordModeのbyte／命令行 | executeBuiltinのbyte／命令行 |
|---|---:|---:|---:|
| Windows Fast | 11308／2159 | 2515／549 | 21033／4433 |
| Windows Small | 8690／1770 | 1323／329 | 119323／24425 |
| Linux Fast | 10868／2178 | 2474／538 | 21158／4429 |
| Linux Small | 8165／1729 | 1280／313 | 118437／24741 |

各欄のサイズ・命令行数は基準と変更側で一致する。plain runOperationsとexecuteWordModeは4組全てで正規化後の命令列が一致する。executeWordは単独関数として残らずインライン化されるため、そのplain本体のexecuteWordModeと包含先runOperationsを比較した。メモリprimitiveも単独関数として残らず、runOperations／executeBuiltinのインライン本体に含まれる。

executeBuiltinはWindows Fast／SmallとLinux Fastで正規化後の命令列が一致する。Linux Smallには3か所のデータアドレス即値の差が残る。`0x109eae8` → `0x109ef40` であり、ELFのいずれもサイズ2バイトのrodataオブジェクトを指し、内容は両方 `00 00` である。ソース行付き逆アセンブルではwords_filesのFileAccessのoptional値の選択に対応する。この3アドレスを対応付けた後に他の命令差はない。ただし機械語そのものが完全一致したとは記載しない。

| 構成 | 実行体byte：基準→変更側 | .text byte：基準→変更側 |
|---|---:|---:|
| Windows Fast | 2450432→2450432 | 1431366→1431366 |
| Windows Small | 1911296→1911296 | 913942→913942 |
| Linux Fast | 10359728→10360912 | 1285651→1285651 |
| Linux Small | 7152072→7153224 | 820101→820101 |

Linux実行体の増加は.textの増加ではない。全体の増分から速度・起動費用を推定しない。

通常経路のソース変更は、builtinInLoopへのcomptime worker引数と、plainではインライン化して元のexecuteBuiltinへ帰着するexecuteBuiltinModeを通す変更である。メモリの検査・native前後の取消し確認・追加の文字列検査は全てcomptime worker側にある。State配置と通常側のメモリprimitive実装は変更していない。plainへ命令ごとの定期取消し確認は追加していない。

比較対象は通常アプリの実行体である。現時点でmainからタスク投入入口は到達せず、workerの独立実体はこの実行体に残らない。workerの機能は試験実行体で検証した。したがって上記の実行体/.text増分は、将来公開入口を結合した場合のworker全体の容量費用を表さない。全関数の意味的等価性を証明する比較でもない。

証拠は `zig-out/1373/analysis/` のシンボル一覧、asm、normalized、diffと、追跡対象JSONである。実行体・ソースのSHA-256はJSONに保存した。

## 5. 未確認事項と利用者の判断事項

Linux・macOS実機での実行は行っていない。Linuxでの実行は別機のClaudeへ引き継ぐ。要求→停止10 ms・回収100 ms、60 Hz・管理1 ms/巡、追加メモリ128 MiBおよび通常経路の時間目安の達成は、本作業からは判定しない。速度・時間は測定していない。

64 KiBの検査は許可したForthのnativeメモリ操作に対するものであり、Snapshot復元・VM初期化・入力準備・結果コピーの各ホスト側処理を64 KiB単位へ分割する変更は行っていない。これらの途中での取消し応答とタスク全体の停止・回収期限は、結合時の検証事項として残る。転送ABIの入出力上限は変更していない。

公開SUBMIT／CANCEL／RELEASEやホスト全体のTaskManagerは本タスクで導入しない。Binding・Executionを接続する上位所有者は、投入前の資源予約、入力・入口名の所有、固定したJobと台帳IDの対応、Snapshot／結果／予算の寿命を保つ必要がある。既存のqueue/results/ledgerの契約を置き換えるものではない。

利用者の判断対象は、4節の生成差分と比較範囲の限界、および+PLACE・SEARCH・MOVEの保守的なworker制限である。機械語差分が小さいことを自動承認や性能保証とは扱わない。追加の公開仕様・公開エラー値の決定は行っていない。


## 6. レビュー修正（2026-11-24）

5点とも修正した。ただし指摘4のPICKは、ソース上は指定深さの1セルを参照する操作であり、深さ分のセル移動ではない。workerの制限を保守的に揃えるため、PICKにも深さ制限を適用した。その他に退けた指摘はない。

### 変更ファイルと設計判断

- `src/core/task_cancel.zig`：pollは実行予約ではなく排他的取得の写しである。startからobserveStartへ切り替え、台帳の占有を再検査しない。キュー取得履歴を参照するので、最初のpollより前に取消し帰還した場合もobserveStart→finish→executionStoppedを通る。未取得取消しはqueued→cancelledを維持する。最終Recordには新たな履歴を追加しない。
- `src/core/task_ledger.zig`：担当外の追加変更はobserveStartだけである。queuedを検査してrunning・execution_refを記録する。既存startとcheckWorkerAvailableは変更していない。未受領の実行側参照は複数残り得るが、キューの同時実行数を増やすものではない。1387での結合では、占有予約と取得履歴の写しを区別する必要がある。
- `src/core/task_queue.zig`：担当外の追加変更はJob.acquiredと既存2か所のrunning遷移直前のrelease-storeである。Bindingはacquire-loadで履歴を読む。Jobは再利用しない。終了後のphaseから取得履歴を推測しないための変更であり、占有・予約ロジックは変えていない。
- `src/core/task_permissions.zig`・`src/core/task_policy.zig`：既定falseの内部Options.test_host_probesを追加した。dot・key_iorの例外はbuiltin.is_testかつ同設定がtrueの場合だけ有効である。本番実行体では設定を渡しても有効にならない。inspectの許可集合は変更していない。
- `src/tests/task_control_w1_test.zig`・`src/tests/task_control_1384_test.zig`：担当外の変更は、ホストcallbackを同期点に使う既存試験の入口で上記設定を明示する変更だけである。
- `src/core/task_memory.zig`：worker専用before/afterでROLL・PICK・N>R・NR>も検査する。深さまたは個数に1を加えたセル数×8をオーバーフロー検査し、max_native_bytes超過を効果の前にInvalidAddressで拒否する。NR>は戻りスタックの個数を使う。これらにはMemoryGateを要求しない。
- `src/tests/task_cancel_memory_test.zig`：全30種のメモリprimitive Op、実際のコロン本体からコピーしたインラインcall_colon、非builtinコロン語へのcall、Gate設置下で保護アドレスを返すstring_literalの拒否を追加した。既定の直接worker呼出しでdot・key_iorを拒否する試験、可変スタック操作の効果前拒否・65536/65544バイト境界も追加した。大容量VMを確保せず、予算の境界はbeforeを直接試験する。
- `src/tests/task_cancel_queue_test.zig`：偽の公開同期点でA取得受領→A封印→B取得→B先行受領→A受領を追加した。最初のpoll時点ですでに取得・取消し帰還済みの順序も追加した。既存の直接runner試験には実キュー相当の取得履歴を設定した。

今回、通常経路の追加変更はない。新たな検査は既存のcomptime worker接続先とworker policyでのみ動く。通常経路に命令ごとの取消し確認を追加していない。公開Forth語・公開エラー値・Snapshot形式・スタック実装は変更していない。速度・時間の測定、パッケージ作成、tque変更、Gitのcommit・branch・tag・pushは行っていない。

### 未確認事項と利用者判断

Linux・macOS実機での実行、性能・停止期限・回収期限・追加メモリ予算の測定は未実施である。Linuxの実行は別機のClaudeへ引き継ぐ。追加の利用者判断を要する未確定仕様はない。PICKにも深さ制限を適用する保守的な制限と、1387での占有予約と写しの区別を引継ぎ事項とする。生成コード比較の従前の証拠は修正前のものとして区別した。

### 最終検証結果
| 実行項目 | 結果 |
|---|---|
| `zig build test` | 終了コード0、23/23 step成功。コア1281成功・10 skip（1291件）。host/runtimeも成功である |
| `zig build test -Ddebug=false` | 終了コード0、23/23 step成功。コア1208成功・83 skip（1291件）。host/runtimeも成功である |
| `zig build runtime-test` | 終了コード0、6/6 step成功、57成功・3 skip（60件）である |
| `zig build -Dtarget=x86_64-linux` | 終了コード0、13/13 step成功。実行はしていない |
| `zig build -Dtarget=aarch64-macos` | 終了コード0、11/11 step成功。実行はしていない |
| 変更した全Zigファイルの `zig fmt --check` | 終了コード0である |
| `git diff --check` | 終了コード0である |

取消し帰還済みの初回受領の試験では、実台帳への呼出しを観測する薄いラッパーによりobserveStartとexecutionStoppedの両方を通ったことも確認した。単に最終状態を比較するだけにはしていない。

検証中に報告書更新用PythonがWindows既定文字コードでUTF-8を読めず終了した。報告書をUTF-8で読み書きする方法に切り替えて更新した。ソースの試験失敗はない。

最終の `git status --short` は以下である。開始時から存在した差分を含む。

```text
 M build.zig
 M src/core/task_context.zig
 M src/core/task_job.zig
 M src/core/task_ledger.zig
 M src/core/task_permissions.zig
 M src/core/task_policy.zig
 M src/core/task_queue.zig
 M src/forth.zig
 M src/forth_test.zig
 M src/runtime_test.zig
 M src/tests/task_control_1384_test.zig
 M src/tests/task_control_w1_test.zig
 M src/tests/task_job_test.zig
?? docs/TASK_CONTROL_IMPL_1373.md
?? docs/measurements/2026-11-24-task-1373-generated-code.json
?? scripts/compare-task-1373-code.py
?? src/core/task_cancel.zig
?? src/core/task_job_queue.zig
?? src/core/task_memory.zig
?? src/tests/task_cancel_memory_test.zig
?? src/tests/task_cancel_queue_test.zig
```
