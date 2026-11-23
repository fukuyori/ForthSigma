# タスク1352：W1取消し経路の試作

作成日：2026-11-23。対象は1049配下の1352である。本書は方式判断の材料であり、方式の採用記録ではない。
作業場所は `D:/tmp/forthz-1352`、開始HEADは `35523f6`（detached HEAD）である。

## 1. 前提と対象範囲

根拠は `docs/TASK_CONTROL_DETAILED_PLAN.md:29`、同`:121`、同`:129`、同`:251`、同`:368`、
`docs/TASK_CONTROL_AUDIT_REENTRY.md:17`、`docs/TASK_CONTROL_AUDIT_SHARED_STATE.md:5`、
`docs/TASK_CONTROL_AUDIT_ALLOWED_SET.md:5`、`docs/TASK_CONTROL_ACCEPTANCE.md:35`、
`docs/TASK_CONTROL_METHOD_COMPARISON.md:90` である。

G1に対する**暫定条件**は、動的実行（EXECUTE、.execute Op、.local_execute、DEFER、DOES>、CATCH/THROW）を拒否し、
ワーカーではcountedを選ばず、PADを除外することである。これを公開仕様の採用とはしない。
拒否は `src/forth.zig:1855`、`src/forth.zig:1862`、`src/forth.zig:1868` に実装した。

本試作は取消し経路と暫定の拒否処理に限定する。1353/1360の完全な許可集合検査、Snapshot、TaskManager、
投入・結果転送・通知・資源所有の実装ではない。任意のForthを安全にワーカーへ投入できる状態ではない。
試験の出力callbackとKEY-IOR callbackは試験専用の同期・再入手段であり、初期許可集合へ入力・出力を追加するものではない
（`src/tests/task_control_w1_test.zig:9`、同`:24`、同`:52`）。

## 2. 変更ファイルと設計上の選択

| ファイル | 要点・理由と根拠 |
|---|---|
| `src/forth.zig` | Stateに既定nullの `worker_cancellation` と確認間隔1024を追加した（`:204`）。入口ではworkerを先に判定し、`counted=false, worker=true` を選ぶ（`:1908`）。通常は従来のdebug条件とplain実体へ進む。 |
| `src/forth.zig` | `runOperations` と `runOperationsLoop` に独立したcomptime引数workerを追加した（`:1913`、`:1957`）。worker/countの同時指定はコンパイルエラーとした（`:1960`）。 |
| `src/forth.zig` | 入口と1024 Opごとの確認をworker実体に限定した（`:1963`、`:1976`、`:2014`）。フレーム境界自体ではカウンターを消費せず、取得するOpごとに1減らす。inlineガードも1 Opである。 |
| `src/forth.zig` | workerだけが展開後のOpを検査する（`:2016`）。直接Op、辞書経由のbuiltin、DEFER、DOES>を拒否する（`:1855`〜`:1878`）。ホストからの直接語入口にも暫定拒否を置いた（`:1546`）。executeBuiltinのworker判定はレビュー後に削除した（現 `src/forth.zig:2347`）。 |
| `src/core/defs.zig` | `RuntimeError.TaskCancelled` とコード -282を追加した（`:1266`、`:1532`）。既存表の末尾 -281に続く試作値である。 |
| `src/core/words_system.zig` | `CatchContext.handleError` が取消しを回復・スタック復元・コード化する前に返す（`:124`）。VM内のCATCH回復ループでもresumeCatchより前に返す（`src/forth.zig:1930`）。 |
| `src/core/error_reporting.zig` | 既存のメッセージ選択に `TASK CANCELLED !` を追加した（`:109`）。Quitの無表示・スタック保持契約は流用しない。 |
| `src/core/exception_registry.zig` | workerではメッセージレジストリを走査・実行せずfalseを返す（`:85`〜`:87`）。bool APIのまま取消しを伝播させることはできないため、callbackを呼ばない側を選んだ。 |
| `src/forth_test.zig` | 新しい試験ファイルをルートへ登録した（`:4`）。 |
| `src/tests/task_control_w1_test.zig` | 下記10試験を追加した（`:74`以降）。 |
| `docs/TASK_CONTROL_PROTO_1352.md` | 本報告書である。 |

取消し印は既存の `Cancellation.request` のrelease storeと `isRequested` のacquire loadを使う
（`src/core/runtime_base.zig:52`〜`:60`）。Stateのポインターは実行中に別スレッドから変更しない。
要求スレッドが変更するのはCancellationのatomic値だけである。トークンは停止・join後まで保持する
（`src/tests/task_control_w1_test.zig:19`、同`:58`〜`:63`）。

1024は試作定数であり、取消し期限の保証値ではない。native処理の内部にはこのループの確認点がない。
ネイティブ呼出しを含む実時間の停止上限は未確認である（`src/forth.zig:1976`、同`:2014`）。

### エラーコードと診断

`throwCodeOf` は登録済み表にないエラーでunreachableとなるため、コード表への登録も行った
（`src/core/error_reporting.zig:273`〜`:280`）。StepLimitと同様にコード登録とCATCH非捕捉を両方実装する。
-282は公開TASK APIの決定値ではなく、1357/D06へ引き継ぐ暫定値である。
THROWの逆引きからTaskCancelledだけを除外し、通常VMの -282 THROWは従来どおりThrownとなるよう修正した
（`src/core/words_system.zig:275`〜`:285`）。初期workerではTHROW自体を拒否する（`src/forth.zig:1855`）。

診断表示は既存reportの通常失敗と同じ後始末・debugログ・backtrace条件を使う
（`src/core/error_reporting.zig:22`〜`:79`、同`:109`）。reportをタスクの終端通知として使う実装は追加していない。
将来のTaskManagerでは診断前にTaskCancelledを識別しcancelledへ接続する判断が必要である。

## 3. 再入と変換箇所の確認

`rg -n 'executeWord\(' src/core` で監査表の22箇所を現ソースと照合した。
次表の「拒否」はW1の暫定builtin拒否（`src/forth.zig:1855`）であり、完全な許可集合検査を意味しない。
「伝播」は呼出し元のtry/returnの局所的な確認であり、未試験の経路を実証済みとは扱わない。

| 現在のfile:line | 局所的な処理とW1での扱い |
|---|---|
| `src/core/csv_reader.zig:137` | tryで伝播する。READ-CSVを拒否する。 |
| `src/core/exception_registry.zig:136` | catch return falseで元の失敗を失う。`:87`でworkerのレジストリ処理自体を止め、callbackへ到達させない。 |
| `src/core/execution_control.zig:76` | 失敗を保存する。`:80`は自身のStepLimitのみコード化するが、`:88`のend失敗が元エラーを置換し得る。EXEC-LIMITEDを拒否し、countedも選ばない。 |
| `src/core/input_redirect.zig:35` | tryで伝播する。INFILE-EXECUTEを拒否する。 |
| `src/core/macro_substitute.zig:139` | tryで伝播し、成功後のみcapture失敗をior化する。SUBSTITUTE系を拒否する。 |
| `src/core/output_redirect.zig:27` | tryで伝播し、成功後のみ出力エラーを確認する。OUTFILE-EXECUTEを拒否する。 |
| `src/core/words_compiling.zig:75` | tryで伝播する。EXECUTEとその直接Opを拒否する。 |
| `src/core/words_debug.zig:341` | tryで伝播する。DBGを拒否する。 |
| `src/core/words_dictionary.zig:57` | tryで伝播する。TRAVERSE-WORDLISTを拒否する。 |
| `src/core/words_names.zig:32` | tryで伝播する。IN-VOCABULARY/IN-WORDLISTを拒否する。 |
| `src/core/words_names.zig:147` | tryで伝播する。MAP-VOCSを拒否する。 |
| `src/core/words_names.zig:156` | tryで伝播する。MAP-VOCSのMacros側も同じ拒否である。 |
| `src/core/words_numeric.zig:31` | tryで伝播する。BASE-EXECUTEを拒否する。 |
| `src/core/words_parsing.zig:118` | tryで伝播する。EXECUTE-PARSINGを拒否する。 |
| `src/core/words_parsing.zig:165` | tryで伝播しdeferでcloseする。EXECUTE-PARSING-FILEを拒否する。 |
| `src/core/words_strings.zig:123` | tryで伝播する。$ITERを拒否する。 |
| `src/core/words_strings.zig:179` | tryで伝播する。$[]MAPを拒否する。 |
| `src/core/words_strings.zig:271` | 結果を保存し、`:276`でcapture失敗より先にtry resultを評価する。$TMP/$EXECを拒否する。 |
| `src/core/words_strings.zig:298` | tryで伝播し、成功後のみcapture失敗をior化する。>STRING-EXECUTEを拒否する。 |
| `src/core/words_system.zig:268` | tryで伝播する。PERFORMを拒否する。 |
| `src/core/words_system.zig:297` | CATCH共通handleErrorの取消し除外を追加した（`:124`）。workerでCATCH自体を拒否する。 |
| `src/core/words_value_extensions.zig:124` | tryで伝播する。WRAP-XTを拒否する。 |

VM内の `wordInLoop` はDEFERやDOES>をexecuteWordへ戻す経路を持つ（`src/forth.zig:1731`）。
workerのOp検査とexecuteWord入口の検査でこれらを拒否する（同`:1546`、同`:1862`、同`:2016`）。
コロン呼出しは同じループ内のフレームを使い、nativeからexecuteWordへ再入した場合はStateの印で専用経路を再選択する
（同`:1881`〜`:1910`）。試験でも既にworker印を持つ状態でのnative再入を確認する
（`src/tests/task_control_w1_test.zig:89`）。

## 4. 追加試験と実行結果

試験はPowerShellからZig 0.17.1で実行した。キャッシュは作業ツリー内に限定した。
速度・時間の測定、ベンチマーク、逆アセンブル比較は行っていない。

```powershell
$env:ZIG_GLOBAL_CACHE_DIR = 'D:\tmp\forthz-1352\.zig-global-cache'
$env:ZIG_LOCAL_CACHE_DIR = 'D:\tmp\forthz-1352\.zig-cache'
zig build test --summary failures
zig build test -Ddebug=false --summary failures
zig build test -Ddebug=false -Doptimize=fast --summary failures
```

| 追加試験 | 確認対象・根拠 |
|---|---|
| 無限ループ | 別スレッドから要求しBEGIN AGAINがTaskCancelledとなる（`src/tests/task_control_w1_test.zig:77`）。step_limitとkeep_countingを設定してもworkerが予算を消費しないことも確認する（同`:54`〜`:69`）。 |
| コロン定義の入れ子 | INNER→MIDDLE→JOBの呼出しとspecialize済みone_plusを含むループで取り消す（同`:78`）。 |
| inline展開 | ループ内のINCがinlineガードを持ち、specialize済みOpも存在することを確認して取り消す（同`:37`〜`:47`、同`:82`）。 |
| native再入 | 既にworkerのJOBから試験用KEY-IOR callbackを通じSPINへ入り、同じ取消しで戻る（同`:23`、同`:86`）。 |
| CATCH非捕捉 | 外側の解釈CATCHとコンパイル済みCATCHから試験callbackでworkerへ入り、TaskCancelledが外へ届く（同`:90`）。worker自身のCATCHを許す試験ではない。 |
| 入口確認・コード・診断 | 先に要求済みなら99をpushする前に取り消す。コード-282、共通CatchContextの非捕捉、診断文字列も確認する（同`:95`）。 |
| 暫定拒否 | EXECUTE Op、XTローカル、DEFER、DOES>付き語、CATCH、THROW、PADを拒否する（同`:112`）。 |
| 診断callback遮断 | 登録済みcallbackがworkerではSEENを書き換えず、印を外すと呼ばれることを確認する（同`:135`）。 |

要求側は試験専用write callbackが入口通過を示すまでatomicで待ち、Cancellation.requestを実行する。
時計・sleepを使わない。戻った後にrequesterをjoinし、フレーム・catch深さの復元を検査する。
印を外した同じVMで40 2 +が42となることも検査する（`src/tests/task_control_w1_test.zig:9`〜`:75`）。
これはState全項目の再利用合格ではない。

修正版（追加10試験を含む）で、3構成とも終了コード0、失敗出力なしとなった。
`--summary failures` のため成功時の件数表示はない。構成・OSによる既存のskipを、全構成で実行済みとは扱わない。
実行ラッパーの出力は次のとおりである。

```text
PASS: zig build test --summary failures (exit 0)
PASS: zig build test -Ddebug=false --summary failures (exit 0)
PASS: zig build test -Ddebug=false -Doptimize=fast --summary failures (exit 0)
```

`zig fmt --check` は変更したZigファイルすべてで終了コード0であった。
`git diff --check` も終了コード0であった（改行形式LF/CRLFについてのGitの警告は出た）。
追加試験の実装箇所は上表のfile:line、試験登録は `src/forth_test.zig:4` である。

初回の失敗と修正も区別する。最初はキャッシュ作成がAccessDeniedとなりコンパイル前に止まった。
環境変数で作業ツリー内へ限定して解消した。Zig 0.17.1のbuildで `--global-cache-dir` を渡した試行は
未対応引数として失敗したため、最終コマンドは上記の環境変数方式とした。
初回試験では `.zig-cache` が存在せずホスト試験15件がファイル作成等で失敗し、
追加CATCH試験1件はcallbackへ接続しないKEYを使ったため期待エラーを得られなかった。
`.zig-cache`を用意し、試験をKEY-IORへ修正した。最終結果とは混同しない。

## 5. 詳細計画4.1の停止条件に照らした結果

| 条件（`docs/TASK_CONTROL_DETAILED_PLAN.md:121`〜`:127`） | 今回の結果と限界 |
|---|---|
| debug=falseの無限ループを取り消せない | BEGIN AGAIN、入れ子、inline/specializeに対する取消し試験はdebug=falseと最適化構成で成功した（4節）。今回の確認範囲では停止不能を認めなかった。native処理中の時間上限は未確認である。 |
| 再入・inlineから通常経路へ抜ける | Stateの印による再選択、動的実行拒否、外側CATCHからの伝播の追加試験は成功した（4節）。今回の試験では通常経路への逸脱を認めなかった。許可集合全体と全callbackの実行試験は未確認である。 |
| メインのメモリ・I/O・UI等へ干渉する | 未確認である。試験専用State/Storage/Writerを使うが、1353/1358の並行隔離証明ではない。 |
| 回収前解放・再利用時の残留 | 試験では取消しが返りrequesterをjoinしてからトークン・VMを破棄する（`src/tests/task_control_w1_test.zig:36`、同`:58`〜`:63`）。結果転送と本番再利用は未確認である。 |
| 費用が利用条件を満たさない | 未確認である。閾値の採用も速度・時間の測定もしていない。1355/1356/1357へ渡す。 |

未確認条件を合格扱いにせず、本試作だけで独立Forth VMの採用可とは判断しない。
受け入れ表AC-01/AC-03のうち取消し経路の部分証拠であり、AC-02のメイン操作継続を含む実タスク受け入れではない
（`docs/TASK_CONTROL_ACCEPTANCE.md:40`〜`:42`）。

## 6. 通常経路の生成コードと1355への手掛かり

入口は `.never_inline` で `runOperations(false, false, ...)` と `runOperations(false, true, ...)` を別に呼ぶ
（`src/forth.zig:1908`〜`:1910`）。確認カウンター、atomic load、Op拒否検査はworkerのcomptime条件内にある
（同`:1957`〜`:1964`、同`:1976`、同`:2014`）。これがplain実体を分離するソース上の手掛かりである。

**機械語が不変であることは未確認である。** executeBuiltinの印判定は削除したが、executeWordの印判定は残る。通常の解釈実行とnative再入にも分岐を1つ加える（`src/forth.zig:1546`）。State配置、エラー集合、呼出し先、最適化・inline判断の変化も比較対象となる。
詳細計画9.1の「入口の1読取りだけ」の見込みを、試作全体の生成コードへそのまま適用しない。

1355には次の方法を提案する。

1. 同じZig 0.17.1、target、最適化、語群、strip設定で、開始HEADと本試作を別出力先へビルドする。
2. debug=false、strip=falseでシンボル・呼出し関係を取得し、plainとworkerのrunOperations実体を呼出し元と引数から識別する。最適化後の名前・ループ関数の独立残存は未確認である。
3. plainのループ本体とその呼出し先を逆アセンブル比較する。再配置・アドレス差と命令列差を分け、atomic loadや1024カウンターの混入がないことを確認する。
4. executeOperationsとexecuteWordの追加分岐、およびexecuteBuiltinの呼出し側への影響、Stateフィールドの参照オフセット、エラー集合変更も別々に記録する。
5. 実行体・セクションのバイト数差を記録する。サイズ一致だけで命令列の不変を主張しない。

## 7. 未確認事項と1357への判断事項

- W1を採用するか、W2/W3および他方式を選ぶかは未決である（`docs/TASK_CONTROL_DETAILED_PLAN.md:255`〜`:259`）。
- 暫定の動的実行拒否、PAD除外、counted非選択を初期公開の制限とするかを判断する。公開を広げる場合は本試験を根拠に全動的経路が安全とは扱わず、個別に監査・試験する。
- 1024 Opの間隔と確認対象native処理、取消し期限、ワーカー数・上限を判断する。費用の大小・応答上限は未確認である。
- エラー-282、診断形式、成功・失敗・取消しの優先規則、output_errorなど他エラーとの競合、終端通知と資源回収は未決である。既存executeBuiltinは出力エラーをresultより先に返す（`src/forth.zig:2357`〜`:2358`）。任意callbackを許す際にはこの優先順位も確認が必要である。
- 暫定拒否を実行時境界へ置く費用と、1353/1360の到達検査へ寄せる案を比較する。plainループに取消し処理がなくても通常経路全体の追加分岐がゼロとはしない。
- 複数workerの同時実行、TaskManager、結果回収、Snapshotの寿命、再利用の全項目、Linux/WSL/macOS実機は未確認である。
- 試験追加以外の既存文書は編集していない。開始時から `docs/TASK_CONTROL_PLAN.md` の変更と根拠文書等の未追跡状態があった。コミット・タグ・ブランチ作成・push・tque更新は行っていない。


## 8. レビュー指摘に対する修正と再評価

本節は修正後の根拠を記録する。前節までの初回調査の行番号には追加行によるずれがあるため、修正対象は本節の現行行番号で示す。

### 8.1 通常経路の費用

指摘1は妥当である。通常のbuiltinInLoopもexecuteBuiltinを呼ぶ（`src/forth.zig:1726`）。
executeBuiltinのworker判定を削除した（`src/forth.zig:2347`）。workerの拒否はexecuteWord入口
（`src/forth.zig:1546`）とworker専用のOp検査（`src/forth.zig:2016`）で行う。
FAST-THROWは内部でexecuteBuiltin(.throw)へ進むため（`src/core/words_diagnostics.zig:27`）、
代わりにFAST-THROW自体を暫定拒否へ加えた（`src/forth.zig:1858`）。
executeBuiltin APIをホストから直接呼ぶ場合はこの拒否を通らない。任意のホストcallbackや直接API呼出しまで
安全にする変更ではなく、完全な許可集合・ホスト契約は1353/1360の未確認事項である。

指摘2も妥当である。executeWordの印判定は通常の解釈実行・native再入で分岐を1つ加える
（`src/forth.zig:1546`）。1355ではexecuteOperations入口だけでなく、executeWordとその呼出し先を
比較対象にする。分岐削除後のexecuteBuiltinと通常ループの呼出し関係も確認する。
生成コード・サイズの比較、速度・時間の測定は今回行っていない。

判定をworker専用入口へ寄せる案を検討した。Op検査は既にworker専用であるが、executeWordには
forward/synonymの再帰とbuiltin実行があり（`src/forth.zig:1548`）、nativeからの再入もある。
入口1回の検査だけで、将来許可するcallbackからの再入先まで検査済みとはならない。
専用executeWordを設けるなら、nativeの呼出し契約の分離または投入前の全到達検査と、実行中に到達先が変化しない
保証が必要となる（設計上の検討であり実装可否は未確認）。本修正では判定を残した。
この費用を許容するか、1353/1360の検査へ寄せるか、W2/W3を選ぶかを1357へ渡す。

ソース解釈を行うEVALUATE、INCLUDE、INCLUDED、REQUIRE、REQUIRED、INCLUDE-FILE、
ブロックのLOAD/THRU、ASSERT(/ASSERT0(〜ASSERT3(を暫定拒否へ加えた（`src/forth.zig:1858`）。
根拠は `src/core/words_input.zig:56`、`src/core/words_files.zig:117`、同`:230`、
`src/core/blocks.zig:197`、`src/core/words_tools.zig:339` である。
`INTERPRET`という辞書登録・Builtinは現ソースでは確認できない。`NAME>INTERPRET`は別の語である
（`src/forth.zig:870`）。存在しないBuiltinを追加する修正は行わず、実在する解釈入口を拒否した。
即時語全体の安全性を確認したものではない。

### 8.2 通常VMのTHROW互換性

指摘3は妥当である。THROWの逆引きでTaskCancelledだけを除外した（`src/core/words_system.zig:283`）。
数値-282はThrownとして扱い、解釈CATCH・コンパイル済みCATCH・FAST-THROW経由でも捕捉できる。
内部のerror.TaskCancelledは従来の試作どおりCATCHを抜ける（`src/core/words_system.zig:124`、
`src/forth.zig:1932`）。診断用throwCodeOfの暫定値-282は維持するが、数値から内部取消しを生成しない。
この値の公開仕様への採否は1357/D06の判断事項である。

### 8.3 修正後の追加試験

- `src/tests/task_control_w1_test.zig:154`：拒否対象16種のBuiltinをbuiltinWordで語IDへ変換し、直接executeWordと、手動で配置したcall、call_builtin、builtinの
  3種のOpから実行し、InvalidExecutionTokenで拒否されることを確認する。引数を消費する前の拒否を確認するため、引数は渡さない。
- `src/tests/task_control_w1_test.zig:178`：通常VMの-282 THROWを解釈CATCHとコンパイル済みCATCHで捕捉し、
  -282 FAST-THROWも捕捉して、スタックに-282が3個残ることを確認する。
- 既存の試作8試験も引き続き対象とする。内部取消しのCATCH非捕捉と、数値THROWの捕捉を区別する。

停止条件4.1に対しては、通常THROWの挙動変化を修正し、拒否経路を追加したが、5節の未確認条件は残る。
本修正を方式の採用判断とはしない。外部データと作業ツリー外のファイルは参照・変更していない。


試験修正中の失敗も記録する。debug=falseではASSERT0(〜ASSERT3(の辞書名が除外される
（`src/core/defs.zig:67`、`src/forth.zig:982`）。最初の追加試験はlookup(name).?で語IDを取得したため、
debug=falseでnullのunwrapによるpanic、最適化構成でStackUnderflowとなり失敗した。
その修正途中にはnamesからbuiltinsへの置換漏れによるコンパイルエラーも1回あった。
最終版はbuiltinWordによって名前を持たない登録も検査する（`src/tests/task_control_w1_test.zig:166`、
`src/forth.zig:1631`）。通常構成とdebug=falseは修正後の再実行で終了コード0、出力なしであった。

最終確認結果：以下の3コマンドはいずれも終了コード0、標準出力・標準エラーとも出力なしであった。
追加10試験を含む試験対象を通過した。キャッシュ環境変数は4節の作業ツリー内設定を使用した。

```text
zig build test --summary failures                                      exit 0
zig build test -Ddebug=false --summary failures                        exit 0
zig build test -Ddebug=false -Doptimize=fast --summary failures        exit 0
```

変更したZigファイルのzig fmt --checkとgit diff --checkも終了コード0であった。
GitはLFからCRLFへの変換予告を表示したが、空白エラーはなかった。
今回のレビュー対応で編集したファイルはsrc/forth.zig、src/core/words_system.zig、
src/tests/task_control_w1_test.zig、本報告書の4ファイルである。他の変更・未追跡ファイルは開始時から存在した。
コミット・タグ・ブランチ作成・push・tque更新は行っていない。

## 9. 追加修正：指摘5〜7

本節を今回の最終状態とする。4・8節の試験結果・行番号は前回の記録である。
G1への仮置きである動的実行拒否、workerのcounted非選択、PAD除外を維持する。方式の採用ではない。
今回編集したファイルは `src/forth.zig`、`src/tests/task_control_w1_test.zig`、本書の3ファイルである。

### 9.1 所有者と復元（指摘5）

Stateに同期入口 `runAsWorker` を追加し、取消し印を設定した後、成功・失敗ともdeferで呼出し前の値へ戻す。
通常VMからならnullへ、workerからの再入なら外側の印へ戻る。トークンは呼出し元が戻るまで保持する契約である
（`src/forth.zig:1541`〜`:1548`）。同一Stateを複数スレッドから同時実行してよいAPIではない。

試験の直接代入はすべて除去した。callbackもrunAsWorkerを使い、再入前後の印の一致を検査する
（`src/tests/task_control_w1_test.zig:33`〜`:40`）。TaskCancelled、拒否のInvalidExecutionToken、診断試験のHostFailed、
正常終了の各経路後にnullを検査する（同`:79`、`:123`、`:149`、`:175`、`:198`、`:220`）。
診断callback遮断の検査は、入口APIの有効範囲内で実行する試験専用KEY-IOR callbackへ移した（同`:153`〜`:180`）。

### 9.2 ハング対策（指摘6）

取消し要求スレッドに監視機能を加えた。開始時に単調時計による30秒の期限を設定し、入口到達前と要求後の両方で
finishedを監視する。期限超過または時計取得失敗ではpanicし、試験プロセスを失敗させる。
通常経路に逸脱して取消しを見なくなった場合も監視対象である（`src/tests/task_control_w1_test.zig:21`〜`:29`）。
これはハング対策であり、性能測定や本番workerの停止期限保証ではない。経過時間は収集・報告しない。
OSによる監視スレッドのスケジューリングまで保証しない。

実行が戻ったらfinishedをreleaseで公開し、監視側がacquireで読み、join後にトークンとVMを破棄する。
監視側はStateの印を変更せず、試験用atomicとCancellationだけを変更する
（`src/tests/task_control_w1_test.zig:24`〜`:25`、`:68`〜`:73`）。
期限超過時は停止していないVMの回収を試みず、プロセスを失敗させる設計を選んだ。
ポーリングを故意に壊した障害注入による期限超過の実行確認は未確認である。

### 9.3 debug条件（指摘7）

counted非選択の検査を独立させ、defs.debug_enabledがfalseならSkipZigTestを返す。
この試験だけstep_limit=1とkeep_counting=trueを設定し、TaskCancelledと予算不消費を検査する
（`src/tests/task_control_w1_test.zig:64`〜`:78`、`:91`〜`:94`）。debug=falseでこの検査を実証済みとはしない。
debug=falseでも基本のBEGIN AGAIN、入れ子、inline、native再入、外側CATCHの取消し試験は実行対象である
（同`:87`、`:96`〜`:110`）。正常終了時の復元とdebug限定の検査の2件を追加し、W1試験は計12件となった（同`:87`〜`:222`）。

### 9.4 停止条件と1357への判断事項

詳細計画4.1の取消し不能・再入逸脱・再利用残留のうち、今回は取消し伝播と入口の印の復元を確認対象とした。
State全項目の再利用、並行隔離、資源回収、native内の停止上限、通常経路の生成コードと費用は未確認のままである
（`docs/TASK_CONTROL_DETAILED_PLAN.md:121`〜`:127`）。今回の確認だけでは方式採用可と判断しない。
1357には同期入口の寿命契約・再入時復元を本番設計にも使うか、試験期限・プロセス失敗方針をCIで維持するかを渡す。
本番の取消し期限とは分けて判断する。指摘5〜7はすべて反映し、未反映とした項目はない。
コミット・タグ・ブランチ作成・push・tque更新は行っていない。作業ツリー外のファイルと外部データにはアクセスしていない。

### 9.5 今回の実行結果

PowerShell、Zig 0.17.1で以下を実行した。キャッシュは4節と同じ作業ツリー内設定である。
`--summary all` は結果件数を確認するための指定である。ビルドツールが自動表示する所要時間は測定結果として利用しない。

| コマンド | 実際の出力の要約 | 終了コード |
|---|---|---|
| `zig build test --summary all` | 最終ソースで23/23 steps succeeded。再実行されたcore試験は1206/1216 passed、10 skipped。他の試験・実行チェックはcached。 | 0 |
| `zig build test -Ddebug=false --summary all` | 23/23 steps succeeded、1314/1413 tests passed、99 skipped。core試験は1133 passed、83 skipped。 | 0 |

通常構成の初回実行は1387/1412 passed、25 skippedで成功したが、そのコンパイル開始後に正常終了時の復元試験を追加したため、
表の最終ソースで再実行した。debug=falseは正常終了試験追加後のソースで実行した。
core試験の総数はいずれも1216であり、debug=falseでは9.3の専用試験をskipする
（`src/tests/task_control_w1_test.zig:91`〜`:94`）。キャッシュされた別試験の件数を最終実行の表示件数へ加算していない。
`zig fmt --check src/forth.zig src/tests/task_control_w1_test.zig` と `git diff --check` は終了コード0であった。
後者には既存変更ファイルのLF/CRLF変換予告が出たが、空白エラーはなかった。
今回の追加修正では最適化構成の再実行、速度・時間の測定は行っていない。
