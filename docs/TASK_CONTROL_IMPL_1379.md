# タスク制御06-C：公開語と文書の実装（1379）

作成日：2026-11-24。作成者：ロク。対象は専用worktree `D:/tmp/forthz-1379` である。

## 1. 仕様と現時点の範囲

利用者の今回の指示により、[公開API提案書](TASK_CONTROL_PUBLIC_API_PROPOSAL.md)9節の問1〜10の推奨案を確定仕様として扱う。提案書内に残る「未決定」という記述を、今回の指示より優先しない。前提は判断記録D03〜D08、利用条件、状態機械、待機登録である。

操作語10個、定数48個をEXTENSIONへ登録した。通常失敗はior、引数・論理メモリ・操作口・端末中断は既存のTHROW経路を用いる。描画kind=5は8節の2026-11-24の利用者決定に従い、1370のtask_paintとhost_paintへ接続した。

## 2. 変更ファイルと要点

| ファイル | 変更の要点 |
|---|---|
| `src/core/defs.zig`、`words_extension.zig`、`words_task.zig` | 操作語・定数のbuiltin、EXTENSION登録、語群除外、固定数値、スタック検査とホスト操作口である。EXEC-LIMITEDをdebug除外用の末尾に保つ |
| `src/core/host_interface.zig`、`src/main.zig` | メイン専用のTask callbackと固定位置のServiceを結合する。既存Runtimeの共通Wakeを借用する |
| `src/host_task_api.zig` | 正の不透明ID、Snapshot対応表、タスク対応表、遅延初期化、予算、公開操作、待機adapter、回収処理である |
| `src/core/task_snapshot.zig`、`task_permissions.zig` | 保存イメージ上の検索順・大文字小文字条件とコードを検査する投入前検査である。workerでは復元・最適化後に従来の検査を再実行する |
| `src/core/task_job.zig`、`task_job_queue.zig` | workerの実行例外を既存THROWコードで保持する。取消し専用帰還の-282を公開診断へ流さない |
| `src/core/task_wait.zig` | 同一対象の読取・書込等を併記するmask、内部paint種別とpainted/capability_lost理由を追加する。Zig enumの序数を公開値にしない |
| `src/host_task_wait.zig`、`host_wake.zig` | 最大64対象の両方向I/Oとsignal pipeを収容するPOSIX監視容量である。1370の描画登録・照会・解除を共通待機へ接続する。Windowsの同時handle上限は維持する |
| `src/host_window.zig` | macOS子の描画通知の進行処理と共通待機用のパイプ監視口を公開する |
| `src/core/help_text.zig`、`words_help.zig` | 新しい全58語の英日説明、worker欄である。既存語のHELPにもworker分類を加える |
| `scripts/word-reference.py`、`docs/word-reference/*` | builtin許可表・登録種別によるworker欄、英日原稿、使用例、生成元照合記録である |
| `docs/WORD_REFERENCE*.md`、`docs/README*.md`、ルートの`README*.md` | 全登録を残した1,987項目の英日一覧、最小例、制限と詳細資料へのリンクである |
| `src/tests/task_public_api_test.zig`、`src/runtime_test.zig` | 実Wakeを使う公開API試験をruntimeへ登録する |
| `src/tests/help_test.zig`、`graphics_test.zig`、`extension_test.zig` | worker欄の表示期待値、新しいbuiltin・定数の除外イメージ拒否である |
| `tests/scripts/check-task-public.fs`、`verify-task-public-matrix.py` | 実行体でのForth ABI試験、代表構成の試験・build・58語の有無の照合である |

作業開始時から存在した `CORE_EXTENSION_DESIGN_DECISIONS.md`、`TASK_CONTROL_DETAILED_PLAN.md` の変更と、未追跡の提案書・1386測定文書は本実装による変更ではない。これらの内容は保持している。

## 3. 設計上の選択

### ハンドルと所有権

公開IDの発行元はプロセス内で共通の単調増加atomicである。0と負数を認めず、符号付きセルの正数範囲で枯渇を拒否する。スロット番号やポインターを公開しない。Snapshotとtaskの表を分け、VM所有者と内部Handleのepoch・serialを検査する。解放後の数値複製は同時に無効であり、スロットを再利用してもIDを再使用しない。

SUBMITは入力と入口名を所有コピーし、受付失敗では既存要求を変えない。Snapshotの実行参照はキューへ渡し、cleanupまで保つ。RELEASEは外部IDを無効化し、未完了なら取消しを要求する。同期joinは行わず、物理的な引渡し後に管理側が回収する。

### 1 VMと予算

投入前検査のために別のFreshVmを作ると、worker実行中に2 VMが共存する。このため、Snapshotの保存済み検索順・case flag・Word・Opを直接読む検査を追加した。Stateの値コピーやメインVMの実行は行わない。実際のworkerは毎回新規VMを作り、復元・特殊化後のコードと実行時メモリを再検査する。投入前の検査結果を実行権限の代わりに使わない。

用途別入力/結果上限はG1が128/512 KiB、G2が128/128 KiB、T1が2 MiB/64 KiB、I1が128/4 KiBである。待ち期限は50/100/100/200 msとする。所有入力と最大結果の予約を16 MiB枠へ算入し、解放されるまで戻さない。

worker VMはStateとStorage.allocateの全領域の合計を76 MiB以下に事前検査する。共有allocatorはメインとworkerの同時確保量をatomicで制限する。128 MiBからOS等4 MiB、管理・丸め等の余裕10 MiB、Service、待機一時領域128 KiBを差し引く。allocator枠超過はLIMIT、確保元の失敗は-257とする。OSが実際に予約・コミットする総量の受入れ確認は未実施であり、物理的な128 MiB保証の検証結果とはしない。

### 遅延初期化と終了

Serviceは固定位置に置くが、操作語を呼ぶまでキュー、worker、Reaperを初期化しない。定数の実行とREQUIRE-EXTENSIONだけでは初期化しない。mainの既存の共通Wakeを借用し、I/O通知とタスク通知を別のWakeへ分断しない。テスト・組込み用にはServiceが専用Wakeを所有する経路もある。

初期化後に既存のhost_task_reapへReaperを結合する。BYEと明示的所有者終了で受付を止め、取消し・回収・worker joinを行う。REPLエラー・ABORT・QUITはServiceを終了しない。停止不能ではService・VM等を解放せず、既存のhost_task_stopの終了コード1の経路へ進む。

### 待機と診断

TASK-WAIT-MANYは対象と出力の全範囲・整列・重複領域・件数・容量を事前検査する。SHORTでは登録せず必要件数を返す。内部登録を呼出し中だけ保ち、タスク台帳の内部参照をattachからdetachまで保持する。成立全件を公開index順に並べ、タグをそのまま返す。単一期限と個別時計を分け、期限と成立を同時に返す。I/Oの読取・書込の同時成立をbit集合で返す。

Ctrl+C相当では登録を解除してUserInterrupt（-28）を返す。出力配列へのcommitは中断scopeの復元後に行い、THROW前の部分コピーを避ける。files=falseではI/O kindをNO-CAPABILITYで拒否する。描画は1370の登録・照会・解除を使い、窓の寿命世代と固定目標を保持する。macOSではAppKit子の通知パイプを共通待機へ追加し、probe前に有限量の入力を進める。pipeのreadiness自体を描画成立とはしない。

worker実行例外、ABI違反、キュー期限超過はfailed終端と主診断へ記録する。STATE自体のiorとは分ける。結果と診断は全量・非消費コピーであり、SHORTでは領域を変更しない。取消しは状態5で区別し、数値-282は公開しない。

## 4. 既存の挙動への影響

通常VMの命令ごとの取消し確認は追加していない。変更したworker実行例外の保存はtask_job経路に限定する。タスクを呼ばない実行でworkerを作らないことを試験する。性能・起動速度・サイズの測定は行わない。

Builtin列挙を追加したため、保存イメージのABI署名の計算対象も変わる。これは[既存のイメージ形式の方針](IMAGE_FORMAT45.md)に従うものであり、同じmagicでも異なる実装版の保存イメージとの互換性を保証しない。作業前の保存イメージを用いた読込み互換試験は行っていない。

2026-11-24の利用者決定とレビュー対応により、HELPは既存どおり英語だけとする。worker欄はEXTENSION有効時だけ表示し、説明対象のbuiltinに対する許可表から分類する。コロン定義・synonymは`worker: depends on definition`とする。日本語の説明は全語リファレンスの日本語版に置く。詳細は11節を参照する。

## 5. 試験と結果

以下は終了コード0で完了した結果である。コマンドはPowerShellから実行し、`ZIG_GLOBAL_CACHE_DIR`をworktree内の`.zig-global-cache`に設定した。既定キャッシュではAccessDeniedとなったためである。ビルドの並列数には`-j2`を指定した。速度・時間の測定コマンドと、時間を含む`--summary all`は使っていない。

| 検証 | 結果 |
|---|---|
| `zig build test` | 成功。既存のcore・host・runtime・freestanding検査を含む |
| `zig build test -Ddebug=false` | 成功 |
| `zig build runtime-test` | 成功。前回追加16試験を含む |
| `zig build`と`zig-out/bin/sigma.exe tests/scripts/check-task-public.fs` | 成功。Forthファイルは検査後にBYEで終了する |
| `python tests/scripts/verify-task-public-matrix.py` | C00/C01/C06/C07/C08/C09/C11/C13/C14/C15/C16の11構成で成功。各構成のtest・実行体build・全58語の有無を確認し、EXTENSION有効構成ではForth ABI試験も実行した |
| Linuxクロスビルド | `-Dtarget=x86_64-linux-musl -Dx11=false -Daudio=false`で成功。graphics・extension・filesは有効である |
| macOSクロスビルド | `-Dtarget=aarch64-macos -Dgraphics=false -Daudio=false -Dx11=false`で成功。extension・filesは有効である |
| 変更・追加した全Zigファイルの`zig fmt --check` | 成功 |
| `python scripts/word-reference.py --check --sigma zig-out/bin/sigma.exe` | 成功。全語辞書照合に欠落なし。ガイド例28件、個別使用例484件が成功した |
| `python scripts/check-docs.py` | 成功、指摘0件 |
| `git diff --check` | 成功 |

構成試験の特徴指定は`verify-task-public-matrix.py`のCONFIGSに明示した。実行記録はworktree内の`.work/task-public-matrix/results.json`と各構成の`*-test.log`・`*-build.log`・`*-forth.log`等に保持する。クロスビルドの出力先は`.work/task-public-cross/linux`と`.work/task-public-cross/macos`である。別OS上では実行していない。

初回の全体試験では、HELPのworker行を追加したことによる既存の出力比較が失敗した。期待値を更新して再実行し、成功を確認した。Forthファイルの検査スクリプトではWindowsのCRLFを正規化した。個別使用例の照合で生成された`translucent.png`は削除した。初回失敗を成功実績として扱わない。

## 6. 公開試験の範囲

公開語をForthから呼び、正常な投入・待機・状態・結果・両ID解放、コピー、容量不足後の再取得、非消費、古いID、別VMのID、失効Snapshot、入口なし、許可外、未終端RESULT、ABI違反、失敗終端、取消し終端、通常変数更新後の旧Snapshot、ABORT/QUIT後の結果保持を確認する。

BUSY、Snapshot本数・画像サイズ、正数ID枯渇、allocator失敗と追加予算超過、共通時計の障害、複合待機の容量不足、同時成立、重複、期限との併記、I/O理由bitの合成、Ctrl+C相当の解除も試験対象である。QUEUE-EXPIREDとSTOP-UNCONFIRMEDの公開診断変換は、物理帰還後のホスト所有メタデータ注入で検査する。実際の遷移・停止不能・正常帰還と取消しの競合は既存のqueue・schedule・reap試験と分けて確認する。

## 7. 未確認事項

- Linux・macOS上の実行と、実端末Ctrl+C・実I/Oの結合である。Windowsの描画実窓は10節で確認済みである。クロスビルドを他OS上の実行確認へ読み替えない。Linux実行は利用者指定どおり別の機械のClaude担当である。
- 速度、起動、実行体サイズ、OS資源を含む予約・コミット量と、D07の時間・容量目標の受入れである。今回は測定しない。
- 描画待機のLinux・macOS実backend実行は未確認である。Windowsの任意試験結果は10節に記載した。

## 8. 利用者決定による描画待機の解決（2026-11-24）

レモンの回答により、公開表示先IDと目標幅の判断待ちは解決した。現在のkind=5は次の仕様である。

- id=0はホスト自身の単一ネイティブ窓である。id≠0は既存の対象検査と同じTASK-E-HANDLE（-300）を返す。
- arg0は既存のGFX-WINDOW-FRAMESが返すshown（1セル）である。arg1は0のみを認め、非0ならホスト初期化・登録前にTHROW -24とする。
- Tk、DISPLAY-AUTOがTkを選んだ経路、ネイティブ窓なし、graphics=falseではTASK-E-NO-CAPABILITY（-311）を返す。未解決のAUTO・端末経路も1370どおり能力なしである。
- 目標0、未投入番号、現在の窓の寿命に属さない番号は1370のInvalidTargetをTASK-E-HANDLE（-300）へ対応させる。能力・窓有無を先に検査する。内部ホスト障害はTASK-E-HOST（-312）である。
- 登録後のclose・再表示による旧寿命の終端はRELEASED（512）、能力喪失はCAPABILITY-LOST（4096）、固定目標までのbackend描画完了はPAINTED（2048）である。closeは達成済み目標より優先する。物理提示の完了を保証しない。
- 将来の複数表示先にはidの意味を広げ、2セル目標への拡張用にarg1を残す。今回、新たなID発行語や2セル目標は追加しない。

通常の対象配列検査とSHORT判定を先に行い、登録済みの描画対象は正常帰還・エラー・中断の各経路で解除する。今回の範囲に残る利用者判断事項はない。上位3文書への判断記録は担当作業者に委ね、本作業では変更しない。

## 9. 作業ツリー

HEADは`abadd1b`のままである。コミット・タグ・ブランチ作成・push・tque変更は行っていない。作業ツリー外のファイル変更と速度・時間の測定は行っていない。既存差分を保持し、今回の変更は未コミットで残す。最終の`git status --short`は利用者への報告に掲載する。第三者コード・ライブラリの追加はない。

## 10. 描画kind=5接続の追試

公開API試験に、登録後の描画完了、達成済み目標、pending、登録後close、id≠0、arg1≠0、目標0・未投入・旧寿命、窓なし、DISPLAY-TKとAUTO→Tk、I/O・描画・時計の同時成立を追加した。graphics=falseの拒否は同じ公開試験と代表構成の実行体試験で確認する。

任意試験`public paint real native window wait (opt in)`は既存のFORTHZ_PAINT_SMOKEに合わせる。ネイティブ窓を開き、実GFX-WINDOW-FRAMESのshownをarg0へ格納して公開TASK-WAIT-MANYを呼び、PAINTEDと達成済みの再照会を検査する。待ちの上限はハング防止であり、時間の測定ではない。

Windows実窓試験は成功した。`zig build runtime-check -j2`で配置した`zig-out/runtime-tests/x86_64-windows/test.exe`を、`FORTHZ_PAINT_SMOKE=1`で直接起動した。公開API実窓試験と既存1370実窓試験がともにOK、全174件中169件成功・5件skip・失敗0である。ビルド側の実行キャッシュによるskipと区別するため、任意試験の証拠は直接起動の`.work/1379-paint-smoke.log`とする。

初回の追加試験では試験用の表示語名と配列整列を修正した。実窓追試では疑似試験が残したフレーム番号によるHANDLEを確認し、疑似試験のSourceを終了時に復元して再実行した。初回失敗は成功に含めない。

指定検証のうち、`zig build test -j2`、`zig build test -Ddebug=false -j2`、`zig build runtime-test -j2`は追試でも成功した。全語リファレンスの生成元記録を試験ソースの修正後に更新し、`python scripts/word-reference.py --check`、`python scripts/check-docs.py`（指摘0件）も成功した。代表構成以降もすべて終了コード0で完了した。

| 今回の追試 | 結果 |
|---|---|
| `zig build test -j2` | 成功 |
| `zig build test -Ddebug=false -j2` | 成功 |
| `zig build runtime-test -j2` | 成功 |
| `python tests/scripts/verify-task-public-matrix.py` | 11構成すべて成功。各構成のtest・build・公開58語の有無、EXTENSION有効時のForth ABI、files/graphics除外時のNO-CAPABILITYを確認 |
| Linux：`zig build -Dtarget=x86_64-linux-musl -Dx11=false -Daudio=false -j2 --prefix .work/task-public-cross/linux` | 成功。対象OS上では未実行 |
| macOS：`zig build -Dtarget=aarch64-macos -Dgraphics=false -Daudio=false -Dx11=false -j2 --prefix .work/task-public-cross/macos` | 成功。対象OS上では未実行 |
| `zig build -j2` | 成功 |
| 変更・追加された全Zigファイルの`zig fmt --check` | 成功。初回はHELP表の整形差分を検出し、`zig fmt`後に再検査した |
| `python scripts/word-reference.py --check --sigma zig-out/bin/sigma.exe` | 成功。全1,987項目、実辞書照合に欠落なし、ガイド例28件・個別例484件成功 |
| `python scripts/check-docs.py` | 成功、指摘0件 |
| `git diff --check` | 成功 |

最終の整形差分はHELP表の空白であり、整形後に実行体を再ビルドして文書の実行例照合を行った。生成元記録も最終ソースに更新した。照合で生成された`translucent.png`は削除した。結果一覧は`.work/1379-validation.json`、各コマンドの出力は`.work/1379-*.log`に保持する。矩形の描画完了は機能試験であり、速度・時間・サイズ・資源量は測定していない。

利用者決定を反映して今回のkind=5接続と指定の検証は完了した。残りは7節の他OS上での実行と別範囲の受入れ確認であり、今回の実装を止める判断事項はない。

### 描画追試時のgit status --short

指定された3文書の既存差分・未追跡状態を維持している。今回、これら3文書への書込みは行っていない。コミット・タグ・ブランチ・push・tque変更も行っていない。

```text
 M README.ja.md
 M README.md
 M docs/CORE_EXTENSION_DESIGN_DECISIONS.md
 M docs/README.ja.md
 M docs/README.md
 M docs/TASK_CONTROL_DETAILED_PLAN.md
 M docs/WORD_REFERENCE.ja.md
 M docs/WORD_REFERENCE.md
 M docs/WORD_REFERENCE_GUIDE.ja.md
 M docs/WORD_REFERENCE_GUIDE.md
 M docs/word-reference/guide.en.txt
 M docs/word-reference/guide.ja.txt
 M docs/word-reference/translation-sources.json
 M docs/word-reference/translations.ja.tsv
 M docs/word-reference/usage-overrides.json
 M scripts/word-reference.py
 M src/core/defs.zig
 M src/core/help_text.zig
 M src/core/host_interface.zig
 M src/core/task_job.zig
 M src/core/task_job_queue.zig
 M src/core/task_permissions.zig
 M src/core/task_snapshot.zig
 M src/core/task_wait.zig
 M src/core/words_extension.zig
 M src/core/words_help.zig
 M src/host_task_wait.zig
 M src/host_wake.zig
 M src/host_window.zig
 M src/main.zig
 M src/runtime_test.zig
 M src/tests/extension_test.zig
 M src/tests/graphics_test.zig
 M src/tests/help_test.zig
?? docs/TASK_CONTROL_IMPL_1379.md
?? docs/TASK_CONTROL_MEAS_1386.md
?? docs/TASK_CONTROL_PUBLIC_API_PROPOSAL.md
?? src/core/words_task.zig
?? src/host_task_api.zig
?? src/tests/task_public_api_test.zig
?? tests/scripts/check-task-public.fs
?? tests/scripts/verify-task-public-matrix.py
```

## 11. レビュー修正（2026-11-24）

以下は指摘ごとにソースを確認した結果である。指定の設計判断・詳細計画・公開API提案書の3文書は変更していない。測定、コミット、タグ、ブランチ操作、push、tque変更は行っていない。

| 指摘 | 確認と対応 |
|---|---|
| 1 | `words_help.describe`はlookup結果のkindから分類していたため、検索順や同名語で説明と分類がずれる。説明対象の名前を起動時・EXTENSION・GRAPHICS・AUDIOのbuiltin定義表で引き、`task_permissions.policy`へ渡すよう修正した。利用者定義は従来のSEE案内と`depends on definition`を表示し、ライブラリのコロン定義・synonymにも同表示を使う。EXECUTEを含むPLOTを条件付きの許可として説明しない。HOST-OSは現在の許可表に登録されていないため、検索順にかかわらずforbiddenである。許可表そのものの拡張はしていない。 |
| 2 | worker欄はEXTENSION有効時だけ英語で表示する。58語のHELP本文から日本語の併記と重複するworker記述を除き、案内先を利用者向けの`docs/WORD_REFERENCE.md`へ変更した。日本語TSVの案内先も`WORD_REFERENCE.ja.md`へ変更した。英日マニュアルとHELP・graphicsの期待値、全語リファレンスの分類生成を更新した。語名・スタック効果は共通生成元、数値・単位・成功条件は既存の英日説明を照合した。TASK-FAILEDの日本語説明にも、TASK-STATEによる照会自体はior=0で成功しうることを明記した。 |
| 3 | notification_failedは確かに解除されず残っていた。CANCEL／RELEASEは呼出し前の印を解除し、今回の操作後の印を読むときにも解除する。終端済みでは過去の印や並行通知の印によって失敗させず0を返す。RELEASEによる外部IDの消費は従来の仕様どおり行う。 |
| 4 | STATE等のstate取得失敗は出力個数に合わせたゼロ値とior=-312に変更した。WAITの期限計算の時計失敗も`0 8 -312`を返し、HostFailedのTHROWにしない。 |
| 5 | 期限加算の失敗経路がensure後にあることを確認した。WAITの期限、WAIT-MANYの全体期限とkind=4の期限をensure前に一度だけ計算し、待機登録は計算済みの値を使う。補足としてmsはi64、加算はi128なので、通常の時計値では最大msそのものは溢れない。i128時計値との加算のオーバーフローは検査対象である。 |
| 6 | allocator入口でallocation_limitedを解除しており、別の確保で印が消えることを確認した。解除はallocationCodeで読む場所だけに限定した。上限超過後に成功する確保を挟んでも-305となり、読んだ後は-257へ戻る回帰試験を追加した。 |
| 7 | paintCapable内のpaint_source.selectを除去し、事前検査を照会だけにした。selectはregisterPaintとprobePaintで行い、登録・照会時の能力喪失検査を維持した。 |
| 8 | 下記の保存形式・復元処理・許可検査を照合した。保存形式だけに現れ、投入前検査が扱わないOp種別は見つからなかった。 |

### 保存Opとworker側Opの照合

`image_encoder.encode`はinline展開の先頭を元の語IDを持つ`.call`へ戻し、残りの領域を`.branch`にする。通常の`.call_colon`も`.call`、特殊化されたprimitiveは`.call_builtin`へ戻す。`image_format.writeOperation`は保存可能なOpKindの上限も検査する。

`task_permissions.Inspector.code`は保存側の`.call`、`.call_builtin`、`.branch`をすべて扱う。`.call`は同じ語IDをenqueueしてそのWordのkindを検査し、`.call_builtin`は同じbuiltinのpolicyを検査する。`image_restore.apply`は保存コードをコピーした後、`State.specializeCall`で`.call`／`.call_builtin`から同じWordを参照してprimitiveまたは`.call_colon`へ特殊化する。worker側の同じInspectorはこれらも扱う。保存側にだけある命令種別を未対応として拒否する経路はない。文字列、実行トークン、分岐、float、終了命令についても同じswitchを通る。

投入前のwhole-body検査は両分岐と実行されない領域も検査する保守的な方式である。この性質は変更していない。保存形式と復元形式の検査で一般的な同値性を証明したという意味ではなく、今回の確認は保存・特殊化で変換されるOp種別と同じ語IDの分類の対応である。

### 今回の検証

以下は今回の修正後にPowerShellから実行し、終了コード0を確認した結果である。Zigのグローバルキャッシュはworktree内の`.zig-global-cache`を使用した。前節までの実行記録とは区別する。

| 検証 | 結果 |
|---|---|
| `zig build test -j2` | 成功。最後のWAIT障害フラグ修正後にも単独で再実行し成功 |
| `zig build test -Ddebug=false -j2` | 成功。最終ソースで単独再実行も成功 |
| `zig build runtime-test -j2` | 成功。通知失敗の残留、LIMIT印、時計障害などの回帰試験を含む |
| `python tests/scripts/verify-task-public-matrix.py` | C00/C01/C06/C07/C08/C09/C11/C13/C14/C15/C16の全11構成が成功。test・実行体build・58語の有無、EXTENSION有効時のForth ABIを確認 |
| Linuxクロスビルド | `zig build -Dtarget=x86_64-linux-musl -Dx11=false -Daudio=false -j2 --prefix .work/task-public-cross/linux`が成功 |
| macOSクロスビルド | `zig build -Dtarget=aarch64-macos -Dgraphics=false -Daudio=false -Dx11=false -j2 --prefix .work/task-public-cross/macos`が成功 |
| `zig build -j2` | 成功 |
| 変更・追加された全Zigファイルの`zig fmt --check` | 成功 |
| `python scripts/word-reference.py --check` | 成功。全1,987項目、日本語説明・使用例・注意事項の生成整合を確認。今回は`--sigma`による全使用例の再実行は行っていない |
| `python scripts/check-docs.py` | 成功、指摘0件 |
| `git diff --check` | 成功 |

全58語のHELP本文について、日本語併記・重複worker欄・提案書への案内が残らず、対応する日本語TSVが存在することも照合した。追加の回帰試験は、検索順を変えたHOST-OSのHELP、DUP再定義時の説明、過去の通知失敗を持つ終端済みタスク、別の確保を挟んだLIMIT判定、WAIT時計障害の固定出力を対象とする。

実行結果一覧は`.work/1379-review-validation.json`、最終の単独再実行は`.work/1379-review-final-tests.json`、整形確認は`.work/1379-review-fmt.json`に保存した。各コマンドの出力は`.work/1379-review-*.log`、構成別の詳細は`.work/task-public-matrix/`に保存した。

今回の検証に失敗終了はない。Linux・macOSの成果物は対象OS上では実行していない。速度・時間・サイズ・資源量の測定、パッケージ作成、実窓の追加追試は行っていない。

最終確認時のHEADは`abadd1b`である。指定された3文書の既存差分・未追跡状態を維持し、これらへの書込みは行っていない。Gitの変更操作とtque変更は行っていない。今回の修正は未コミットの作業ツリーに残している。第三者コード・ライブラリの追加はない。
