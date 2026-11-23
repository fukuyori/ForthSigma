# タスク制御01-B1：executeWord再入・取消しエラー監査

作成日：2026-11-23。対象：1048配下・1349。静的ソース監査である。実装、実行試験、速度・時間の測定は行っていない。

## 1. 根拠と判定の範囲

設計根拠は [詳細計画](TASK_CONTROL_DETAILED_PLAN.md)2・5〜13節、[補完計画](TASK_CONTROL_PLAN.md)、[詳細設計](CORE_EXTENSION_DETAILED_DESIGN.md)11節、[State隔離監査](CORE_EXTENSION_WORKER_STATE_AUDIT.md)、[レビュー対応](CORE_EXTENSION_REVIEW_RESPONSE.md)、[判断記録](CORE_EXTENSION_DESIGN_DECISIONS.md)である。方式採用・許可語の確定・取消し実装の完了を意味しない。

`src/` 全体の `.executeWord(` を列挙した結果は58箇所である。内訳は実行用29箇所（coreの15ファイル22箇所、forth.zigの7箇所）、テスト29箇所であり、他ディレクトリの追加呼出しはなかった。宣言 `src/forth.zig:1538` とコメント `src/tests/core_words_test.zig:75` は呼出しではない。集計方法は付録に示す。

詳細計画5節はカテゴリの案であり、確定したbuiltin一覧ではない。到達欄の「到達する」は入口・通常ディスパッチとして利用し得る構造、「条件付き」は保存辞書の語種別・採用する許可語次第、「許可集合から外す」は本監査での初期試作向け提案である。現状のソースにワーカーの拒否検査が実装済みであることを示さない。純粋な算術などと同じファイルにあることだけを許可根拠にはしない。詳細計画7.2・12.2節の静的走査と動的境界検査が成立するまで、到達しないとの保証は未確認である。

表の「伝播」は当該呼出し元での扱いである。その外側にCATCHや診断コールバックがあれば、そこで捕捉され得る。「局所なし」は当該箇所で取消しを変換しないという意味であり、取消し全体の安全性を示さない。

## 2. 実行用呼出し一覧

| file:line | 呼出し元の語・関数 | 呼ばれる経路 | 呼出し後のエラー処理 | 取消しを握り潰す可能性 | 初期許可集合からの到達 |
|---|---|---|---|---|---|
| src/forth.zig:647 | State.runEntry | ホストから登録入口を直接実行 | tryで伝播。入力文脈をdeferで復元、失敗時はquotationを中止 | 局所なし | 到達する：入口候補。採用する起動方法は未確認 |
| src/forth.zig:1428 | handleWord | 解釈語／コンパイル中の即時実行 | tryで伝播 | 局所なし | 許可集合から外す：任意ソース解釈・コンパイルを初期APIに含めない |
| src/forth.zig:1547 | executeWord (.forward) | 前方参照の実体へ再帰 | tryで伝播 | 局所なし | 条件付き：保存入口にforwardがあれば到達し得る。解決先検査が必要 |
| src/forth.zig:1549 | executeWord (.synonym) | 別名の実体へ再帰 | tryで伝播 | 局所なし | 条件付き：既存別名を許せば到達。別名先まで検査する |
| src/forth.zig:1581 | executeWord (.deferred) | 遅延語のセルにあるaction | tryで伝播、call_depthをdeferで戻す | 局所なし。未初期化時は呼出し前に警告して正常復帰（1568〜1574行） | 条件付き：遅延語は最小集合への採否未決。初期試作では外す提案 |
| src/forth.zig:1732 | wordInLoop | 未初期化遅延語をexecuteWordへ戻す | エラー共用体をそのままreturn | 局所なし。未初期化actionの場合だけ入り、警告を書き出して正常復帰する（src/forth.zig:1570〜1574）。id自身が未初期化DEFERなら1570〜1574で確実に戻る。連鎖先で未初期化を検出した場合は途中のDEFERに1581の再帰と1578の深さ検査がある | 条件付き：遅延語を許す場合。初期試作では外す提案 |
| src/forth.zig:1754 | wordInLoop | builtin直接処理・CATCH特例以外の語。DEFER、DOES>、VALUE/FIELD等、.execute、.local_executeから到達（下記参照） | tryで伝播 | 局所なし。ただし外側runOperationsの回復対象 | 到達する：VALUE/FIELD等のワーカー内メモリ語を許す場合も含む。動的先・辞書変更語の採否は別途判断 |
| src/core/csv_reader.zig:137 | run / READ-CSV | CSVのフィールドcallback xt | tryで伝播 | 局所なし | 許可集合から外す：入力・ファイル |
| src/core/exception_registry.zig:134 | writeMessage / EXCEPTIONSの変換callback | 診断時の遅延メッセージ生成 | catch return false。元例外の既定診断へ戻る | あり：現在もQuit・StepLimitをfalse化し、将来追加する取消しも同じcatchでfalse化する | 許可集合から外す：診断callback実行。復元済み登録からの暗黙到達にも注意 |
| src/core/execution_control.zig:76 | runEnabled / EXEC-LIMITED | debug予算内でxt実行 | failureへ保存。自身のStepLimitだけ復元して-280、他は伝播。ただしendの失敗が優先（80〜94行） | 取消しは現判定ではown_limitにならないが、endの別エラーで置換され得る | 許可集合から外す：debug実行制限。許す場合は取消しとの優先順位を定義する |
| src/core/input_redirect.zig:35 | run | 入力先を切り替えたxt | tryで伝播、deferで入力文脈復元 | 局所なし | 許可集合から外す：入力 |
| src/core/macro_substitute.zig:139 | substitute | マクロ語彙の語を実行して置換文字列を得る | tryで伝播。成功後のcapture失敗だけiorへ変換 | 局所なし | 許可集合から外す：マクロcallbackは最小集合にない |
| src/core/output_redirect.zig:27 | run | 出力先を切り替えたxt | tryで伝播。成功後だけcheckOutputError | 局所なし | 許可集合から外す：ファイル出力 |
| src/core/words_compiling.zig:75 | execute (.execute) / EXECUTE | スタック上のxt | tryで伝播 | 局所なし | 許可集合から外す案：詳細計画5節により初回試作で拒否可能 |
| src/core/words_debug.zig:341 | runDbg / DBG | 指定したコロン定義をstepper付きで実行 | tryで伝播、deferでstepper解除 | 局所なし | 許可集合から外す：debug機能の採否未決 |
| src/core/words_dictionary.zig:57 | execute / TRAVERSE-WORDLIST | 辞書各項目のcallback | tryで伝播、成功後だけflagを読む | 局所なし | 許可集合から外す：辞書列挙callbackは最小集合にない |
| src/core/words_names.zig:32 | oneShot | 一時CURRENTで次の語を実行 | tryで伝播、世代一致時のみCURRENT復元 | 局所なし | 許可集合から外す：ソースから語名を読む辞書文脈操作 |
| src/core/words_names.zig:147 | execute / MAP-VOCS | 通常語彙のcallback | tryで伝播、成功後guard検査 | 局所なし | 許可集合から外す：語彙列挙callback |
| src/core/words_names.zig:156 | execute / MAP-VOCS | Macros語彙のcallback | tryで伝播、成功後guard検査 | 局所なし | 許可集合から外す：語彙列挙callback |
| src/core/words_numeric.zig:31 | execute / BASE-EXECUTE | 一時BASEでxt実行 | tryで伝播、deferでBASE復元 | 局所なし | 許可集合から外す案：算術カテゴリでも動的xt実行の追加許可が必要 |
| src/core/words_parsing.zig:118 | execute / EXECUTE-PARSING | 文字列入力文脈のxt | tryで伝播、deferでSource復元 | 局所なし | 許可集合から外す：入力・動的xt実行 |
| src/core/words_parsing.zig:165 | execute / EXECUTE-PARSING-FILE | ファイル入力文脈のxt | tryで伝播、失敗時もdeferでclose。成功後のclose iorは別処理 | 局所なし。失敗時close結果は元エラーを置換しない | 許可集合から外す：入力・ファイル |
| src/core/words_strings.zig:123 | execute / $ITER | 分割文字列ごとのxt | tryで伝播 | 局所なし | 許可集合から外す案：文字列処理でも動的callbackを別審査する |
| src/core/words_strings.zig:179 | execute / $[]MAP | 文字列配列各要素のxt | tryで伝播 | 局所なし | 許可集合から外す案：動的callback |
| src/core/words_strings.zig:271 | captureOutput / $TMP・$EXEC | xt出力を文字列へ捕捉 | result保存、出力文脈復元後276行でtry result。成功後のみENOMEMをior化 | 局所なし：実行失敗がcapture失敗より優先 | 許可集合から外す案：出力捕捉・動的callback |
| src/core/words_strings.zig:298 | captureOwned / >STRING-EXECUTE | xt出力を私有バッファへ捕捉 | tryで伝播、defer/errdeferで復元・解放。成功後のみENOMEMをior化 | 局所なし | 許可集合から外す案：出力捕捉・動的callback |
| src/core/words_system.zig:268 | execute / PERFORM | メモリセルからxtを読み実行 | tryで伝播 | 局所なし | 許可集合から外す案：EXECUTEと同じ動的先検査が必要 |
| src/core/words_system.zig:297 | runCatch / CATCH・CATCH-NOBT | xtを回復文脈で実行 | 成功は0、失敗はhandleErrorでスタック等を復元しthrow codeへ変換 | あり：124行の除外へ取消しを追加しなければ回復経路へ入る | 許可集合から外す案：詳細計画5節。公開許可時は非捕捉の試験必須 |
| src/core/words_value_extensions.zig:124 | execute / WRAP-XT | 一時的に遅延語actionを変更してcallback実行 | tryで伝播、deferでaction復元とguard解除 | 局所なし | 許可集合から外す：遅延先変更・動的callback |

DOES>本体は `src/forth.zig:1563` からexecuteOperationsへ入る。コロン定義は `src/forth.zig:1566` からexecuteColonへ入る。これらはexecuteWordの追加呼出し行ではない。通常のコロン呼出しのフレーム移行（call Opは`src/forth.zig:2065`、ループ内EXECUTEは`src/forth.zig:2094`。`src/forth.zig:1711`はenterCatchのCATCH入口）とexecuteWord再入を区別する必要がある。worker文脈を再入入口で再選択する設計は、ローカルなcounted値だけでなくStateに紐づく実行文脈を引き継ぐ条件で評価する。

### 2.1 wordInLoopへの経路とデータ語のコンパイル形

`wordInLoop`のelse（`src/forth.zig:1753`、`src/forth.zig:1754`）は保存したCREATE/DOES>専用ではない。ループからの入口は次のとおりである。入口がwordInLoopへ達することと、そこから必ず1754へ進むことは区別する。

| 入口のfile:line | 経路と分岐 |
|---|---|
| src/forth.zig:2019 | `.call`のDEFER。未初期化・不正action、または別名解決後の行先がコロン以外の場合に入る（src/forth.zig:2008、src/forth.zig:2009）。CATCH特例と未初期化分岐以外は1754へ進む。コロン行先なら2065のフレーム移行である |
| src/forth.zig:2043 | `.call`のvariable/createdでhas_doesがある場合。1754からexecuteWord、DOES>本体のexecuteOperationsへ再入する（src/forth.zig:1559、src/forth.zig:1563） |
| src/forth.zig:2058 | `.call`のkind分岐のelse。VALUE、文字列VALUE、FVALUE、2CONSTANT、2VALUE、FCONSTANT、FIELD、MARKER、VOCABULARY、forward等。builtinなら直接処理され得るが、これら非builtinは1754へ進む（src/forth.zig:1751、src/core/defs.zig:1290） |
| src/forth.zig:2088 | `.execute`で別名解決後の行先がコロン以外。単純なbuiltinは直接、DEFER/CATCHは専用分岐、それ以外は1754へ進む。コロン行先は2094のフレーム移行でexecuteWordを経ない（src/forth.zig:2076、src/forth.zig:2078、src/forth.zig:2094） |
| src/forth.zig:2280 | `.local_execute`がローカルセルのxtを読み、wordInLoopへ渡す。builtin/CATCH/未初期化の分岐以外は1754へ進み、コロン行先もexecuteWordへ再入する（src/forth.zig:1738、src/forth.zig:1751、src/forth.zig:1754） |

コンパイル時は`compileCall`が`.call`を生成し、builtinとコロンだけをspecializeする（`src/forth.zig:1446`、`src/forth.zig:1457`、`src/forth.zig:1460`、`src/forth.zig:1461`）。inline候補もコロンに限る（`src/core/inline_calls.zig:26`）。したがってVALUE/FIELD等は`.call`のまま上表の2058へ進み、executeWordで値読出し・アドレス加算等を行う（`src/forth.zig:1552`、`src/forth.zig:1553`、`src/forth.zig:1555`、`src/forth.zig:1556`、`src/forth.zig:1583`）。ワーカー内メモリの利用を許す案でも、この再入を監査対象から外せない。MARKERとVOCABULARYは同じ経路を使うが、辞書破棄・検索順変更を行うため、メモリ読出し語と一括許可してはならない（`src/forth.zig:1589`、`src/forth.zig:1590`、`src/forth.zig:1596`）。一方、CONSTANT・ARRAY・DOES>なしのVARIABLE/CREATEはループ内でpushし、通常の`.call`ではexecuteWordへ再入しない（`src/forth.zig:1994`、`src/forth.zig:1998`）。

## 3. テスト内の呼出し一覧

テスト関数名と、該当する場合はその中のcallback関数を併記する。いずれもワーカーのForth許可集合から呼ばれる実行用入口ではなく、テストハーネスからの直接呼出しである。テストの存在は取消し専用エラーの検証済みを意味しない。

| file:line | 呼出し元のテスト・関数 | 呼ばれる経路 | 呼出し後のエラー処理 | 取消しを握り潰す可能性 | 初期許可集合からの到達 |
|---|---|---|---|---|---|
| src/tests/dictionary_test.zig:227 | test primitive instructions match dictionary calls including errors and full stacks | `const direct_result = direct.executeWord(probe_id);` | 結果を保存し成功／期待エラーを比較（229〜231行） | 比較対象として消費。実行用の回復ではない | 到達しない：テスト専用 |
| src/tests/dictionary_test.zig:228 | test primitive instructions match dictionary calls including errors and full stacks | `const generic_result = generic.executeWord(try generic.wordId(id));` | 結果を保存し成功／期待エラーを比較（229〜231行） | 比較対象として消費。実行用の回復ではない | 到達しない：テスト専用 |
| src/tests/debug_words_test.zig:91 | test compiled data words retain trace and profile operation counts | `try machine.executeWord(caller);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/catch_test.zig:278 | test PC at the u16 code limit branches and returns through both loop exits | `try machine.executeWord(try machine.lookupOrFail("CALL"));` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/catch_test.zig:317 | test host output reentry preserves an outer CATCH and its locals / Output.write | `m.executeWord(self.inner) catch /err/ {` | Output.writeでcatchしself.failureへ保存、voidでreturn | あり：実行元へ伝播しないテスト用callback | 到達しない：テスト専用 |
| src/tests/core_words_test.zig:135 | test compiled data-word references reject targets forgotten during execution | `try std.testing.expectError(error.InvalidExecutionToken, machine.executeWord(caller));` | expectErrorで期待エラーと比較。不一致はテスト失敗 | 期待値として検査するだけ。取消しは現期待値と不一致 | 到達しない：テスト専用 |
| src/tests/inline_calls_test.zig:78 | test inlined calls reject words removed during execution by FORGET or MARKER | `try std.testing.expectError(error.InvalidExecutionToken, machine.executeWord(caller));` | expectErrorで期待エラーと比較。不一致はテスト失敗 | 期待値として検査するだけ。取消しは現期待値と不一致 | 到達しない：テスト専用 |
| src/tests/inline_calls_test.zig:107 | test inlined calls preserve call-limit and stack-error ordering | `const actual = optimized.executeWord(optimized.lookup(name).?);` | エラー共用体を保存しexpectEqualで比較（109行） | 両側が同じ取消しなら比較だけでは検出不能 | 到達しない：テスト専用 |
| src/tests/inline_calls_test.zig:108 | test inlined calls preserve call-limit and stack-error ordering | `const expected = control.executeWord(control.lookup(name).?);` | エラー共用体を保存しexpectEqualで比較（109行） | 両側が同じ取消しなら比較だけでは検出不能 | 到達しない：テスト専用 |
| src/tests/inline_calls_test.zig:280 | test copied execution tokens relocate through repeated LOAD and another image round trip | `try source.executeWord(copy.c);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p05a_input_test.zig:48 | test P05a readiness neither consumes bytes nor sets an EOF indication | `try m.executeWord(m.lookup("READY").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p05a_input_test.zig:53 | test P05a readiness neither consumes bytes nor sets an EOF indication | `try m.executeWord(m.lookup("CHAR").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p05a_input_test.zig:57 | test P05a readiness neither consumes bytes nor sets an EOF indication | `try m.executeWord(m.lookup("READY").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p05a_input_test.zig:60 | test P05a readiness neither consumes bytes nor sets an EOF indication | `try m.executeWord(m.lookup("ENDED").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p04b_values_test.zig:81 | test P04b value execution checks output room and setters check input ranges | `try std.testing.expectError(error.StackOverflow, machine.executeWord(id));` | expectErrorで期待エラーと比較。不一致はテスト失敗 | 期待値として検査するだけ。取消しは現期待値と不一致 | 到達しない：テスト専用 |
| src/tests/p05b_path_parts_test.zig:75 | test P05b path parts execute in compiled words without heap allocation | `try m.executeWord(m.lookup("PARTS").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p05b_mkdir_test.zig:132 | test P05b mkdir needs no spare stack or heap and checks budget between attempts | `try m.executeWord(m.lookup("MAKE").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p06b_csv_output_test.zig:103 | test P06b omitted CSV VALUE slots keep image shape but cannot execute | `try std.testing.expectError(error.InvalidExecutionToken, m.executeWord(id));` | expectErrorで期待エラーと比較。不一致はテスト失敗 | 期待値として検査するだけ。取消しは現期待値と不一致 | 到達しない：テスト専用 |
| src/tests/p05b_timezone_test.zig:146 | test P05b timezone compiled calls and image restore need no file feature or heap | `try m.executeWord(m.lookup("ZONE").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p05b_filename_match_test.zig:136 | test P05b glob works without host hooks or heap and respects the work budget | `try m.executeWord(m.lookup("MATCH").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p05b_cwd_test.zig:153 | test P05b cwd writes invalidate typed addresses and need no spare stack or heap | `try m.executeWord(m.lookup("CWD").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p05b_ns_test.zig:93 | test P05b NS needs no spare stack file feature or VM heap and keeps destination hooks | `try m.executeWord(m.lookup("WAIT").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p05b_dir_iterator_test.zig:185 | test P05b directory words need no spare stack or free heap in compiled execution | `try m.executeWord(m.lookup("OPEN").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p05b_dir_iterator_test.zig:198 | test P05b directory words need no spare stack or free heap in compiled execution | `try m.executeWord(m.lookup("READ").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p05b_dir_iterator_test.zig:201 | test P05b directory words need no spare stack or free heap in compiled execution | `try m.executeWord(m.lookup("CLOSE").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p06b_csv_input_test.zig:113 | test P06b CSV I/O failures allocation failures stack preflight and nesting close all owned resources | `try std.testing.expectError(error.IncludeNesting, m.executeWord(m.lookup("CSV-RUN").?));` | expectErrorで期待エラーと比較。不一致はテスト失敗 | 期待値として検査するだけ。取消しは現期待値と不一致 | 到達しない：テスト専用 |
| src/tests/p06b_csv_input_test.zig:132 | test P06b CSV close errors oversized lines and full-stack preflight retain ownership rules | `try std.testing.expectError(error.StringTooLong, m.executeWord(m.lookup("CSV-RUN").?));` | expectErrorで期待エラーと比較。不一致はテスト失敗 | 期待値として検査するだけ。取消しは現期待値と不一致 | 到達しない：テスト専用 |
| src/tests/p08b_test.zig:171 | test P08b successful restore invalidates wrappers while failed preflight preserves them | `try m.executeWord(m.lookup("D").?);` | tryでテストへ伝播 | 局所なし | 到達しない：テスト専用 |
| src/tests/p08b_test.zig:182 | test P08b wrapper nesting is bounded and all deferred actions unwind on failure | `try std.testing.expectError(error.ReturnStackOverflow, m.executeWord(m.lookup("R").?));` | expectErrorで期待エラーと比較。不一致はテスト失敗 | 期待値として検査するだけ。取消しは現期待値と不一致 | 到達しない：テスト専用 |

## 4. Quit / StepLimitの捕捉除外と周辺経路の全数確認

`error.Quit` と `error.StepLimit` の明示参照をsrc全体で検索した。両者をForthの回復対象から除外する条件は次の2箇所である。CATCH-NOBTは別の除外条件を持たず、共通runCatchを使う（`src/core/words_diagnostics.zig:22`）。NOTHROWはトレースを消す語であり、Zigエラーのcatchではない（`src/core/words_diagnostics.zig:23`）。

| file:line | 現状の分類・処理 | 取消し専用エラーの対応案 |
|---|---|---|
| src/forth.zig:1898 | runOperationsの回復ループ。Quit・StepLimitならresumeCatchせずreturn failure | 必須：取消しを同じ非回復分岐へ加える。ここで除外しないとresumeCatchが先に状態を変更する |
| src/core/words_system.zig:124 | CatchContext.handleError。Quit・StepLimitはthrowCodeOf・restore・pushを行わず返す | 必須：取消しを除外へ加える。解釈CATCHとCATCH-NOBT、ループからの共通回復を覆う |

「ほか」に該当する明示参照は以下であり、上記2箇所以外に同形のCATCH除外条件はなかった。除外条件と、エラー生成・報告・検査を混同しない。

| file:line | 明示参照の用途 | 取消し追加時の扱い |
|---|---|---|
| src/core/execution_control.zig:32 | CLI予算枯渇によるStepLimit生成 | 取消し生成源とは分離する |
| src/core/execution_control.zig:41 | 入れ子の所有予算枯渇によるStepLimit生成 | 取消しで予算stopを立てない |
| src/core/execution_control.zig:80 | 自身のStepLimitだけを回復しior=-280へ変換する判定 | 取消しをown_limitへ追加してはならない。終了エラー優先の別問題は5節 |
| src/core/words_system.zig:158 | QUITからQuit生成 | タスクのQUIT契約は1052で決定する。取消しと同一視しない |
| src/core/defs.zig:1265 | StepLimitとForth code -280の対応表 | 取消しをForthのTHROW codeへ公開するかは未決。捕捉不能の契約と整合させる |
| src/core/error_reporting.zig:32 | Quit等ではbacktrace表示を省略 | タスク診断をここへ接続する場合に扱いを決める。捕捉除外ではない |
| src/core/error_reporting.zig:35 | Quit等ではdebugログを省略 | 同上 |
| src/core/error_reporting.zig:45 | Quit時の後処理をdeferで実行 | 取消し時に流用するかは未決。自動追加しない |
| src/core/error_reporting.zig:74 | Aborted/Quitを通常メッセージとは別扱い | タスク終端処理との境界を決める |
| src/core/error_reporting.zig:109 | StepLimitの表示メッセージを選択 | 必要なら取消し診断を別途定義する |

テスト中の明示参照は付録のコマンドで別途再列挙できる。これらはexpectError・report呼出し・テスト引数であり、実行用の非捕捉条件の追加箇所ではない。help_textの説明文やOSのQuit名称もエラー捕捉ではない。

`handleError`の直接呼出しも確認した。enterCatch内にはDEFERセル読出し失敗（`src/forth.zig:1672`）、深さ上限（`src/forth.zig:1680`）、action検証失敗（`src/forth.zig:1685`）、DOES>のpush失敗（`src/forth.zig:1696`）、深さ上限（`src/forth.zig:1700`）がある。runOperationsにもresumeCatch後の共通処理（`src/forth.zig:1903`）がある。いずれも`src/core/words_system.zig:124`の共通除外で覆われるため、独立した除外条件の追加箇所は増えない。ただし1903へ進む前のresumeCatchによる状態変更を防ぐため、1898側の除外も必要である。

### 4.1 トップレベルの受け口

以下はRuntimeErrorの種類を限定せず捕捉する既存の最終受け口である。取消し専用エラーが上流から伝播する実装を追加すればここへも到達し得るが、現状はタスク取消し専用の終端処理ではない。

| file:line | 捕捉後の処理 |
|---|---|
| src/main.zig:3581 | REPLのinterpretLine失敗を3582でreportDiagnosticへ渡し、pauseForRepl後に戻る |
| src/main.zig:3883 | 保存アプリのrunEntry失敗を3884で診断し、終了値1を返す |
| src/main.zig:3913 | `-e`のinterpretLine失敗を3914で診断し、終了値1を返す |
| src/main.zig:3918 | includeFile失敗を3924で診断し、終了値1を返す |
| src/freestanding_check.zig:31 | interpretLine失敗を32でstate.reportへ渡し、falseを返す |

reportDiagnosticはメインの診断表示の準備とStateの入力状態変更を行い、machine.reportを呼ぶ（`src/main.zig:3486`、`src/main.zig:3487`、`src/main.zig:3488`、`src/main.zig:3489`、`src/main.zig:3490`）。これをワーカーの受け口として流用することは提案しない。ワーカーには独自の受け口を設け、取消しを診断・通常失敗への変換より先に識別し、資源解放とcancelledの終端通知へ接続する必要がある（詳細計画8・9・13節に基づく提案、実装は未確認）。

## 5. 取消しを通すための変更候補一覧

本節は実装提案である。本タスクではソースを変更していない。

| 優先 | 対象 | 必要な対応・判断 |
|---|---|---|
| 必須 | src/forth.zig:1898 | 取消し専用エラーを回復対象外にする |
| 必須 | src/core/words_system.zig:124 | 同上。throwCodeOfより前に返す |
| 条件付き必須 | src/core/exception_registry.zig:134 | ワーカーで診断callbackを実行しない、または取消しだけを伝播できるインターフェースへ変更する。現在のwriteMessageはbool（src/core/exception_registry.zig:85）であり、catch内へ条件を足すだけでは伝播できない。呼出し元src/core/error_reporting.zig:223まで契約の見直しが必要である |
| 条件付き必須 | src/core/execution_control.zig:91 | EXEC-LIMITEDを許すなら、failureの取消しがendの別エラーに置換されない優先順位を定める。現状92行はown_limitでない失敗を返すが、その前の91行が別エラーを返し得る。endを省略してよいという意味ではない |
| 継承確認 | src/forth.zig:647・1428・1547・1549・1581・1732・1754、および2節のcore22箇所 | 許可する経路は同じStateのworker文脈を保持して専用経路へ入ることを検証する。try/return箇所への取消しcatch追加は不要である |
| 境界確認 | src/core/error_reporting.zig:273 | throwCodeOfは登録にないエラーでunreachable（280行）になる。取消しを先に除外しなければ、単なる握り潰しだけでなく未登録エラーの到達も問題となる。code表へ追加するだけで非捕捉を代替しない |
| テストのみ | src/tests/catch_test.zig:317 | void Writer callbackがエラーを記録して戻る。実行用修正箇所ではないが、取消し再入テストに転用するときはfailureの明示検査が必要である |

captureOutputは実行エラーを保存してから出力文脈を戻し、`try result` を先に評価するため、実行エラーをENOMEMへ変換しない（`src/core/words_strings.zig:271`、`src/core/words_strings.zig:276`）。captureOwned・マクロ置換もexecuteWordが成功した後だけcapture_failedをior化する（`src/core/words_strings.zig:298`、`src/core/words_strings.zig:299`、`src/core/macro_substitute.zig:139`、`src/core/macro_substitute.zig:140`）。これらへ機械的に取消し除外条件を追加する必要はない。

### 5.1 動的呼出しを拒否する場合のOp単位の境界案

builtinのEXECUTEだけを拒否しても十分ではない。`src/core/words_compiling.zig:75`は解釈時などbuiltinディスパッチからの実行であり、通常コンパイルではEXECUTEは専用`.execute` Opになる（`src/forth.zig:1458`、`src/core/defs.zig:1427`）。初期試作で動的呼出しを拒否する場合は、次を静的走査とワーカー実行時検査の両方で扱う提案である。

- `.execute`：Op自体を拒否する。コロン行先もexecuteWordを経ずにフレームを積むため、再入入口の拒否では代替できない（`src/forth.zig:2075`、`src/forth.zig:2088`、`src/forth.zig:2094`）。
- `.local_execute`：xtローカルの動的呼出しを拒否する。xtローカル参照のコンパイル形もこのOpである（`src/core/local_variables.zig:35`、`src/forth.zig:2270`、`src/forth.zig:2280`）。
- `.call`：行先を解決し、DEFERを拒否する場合はそのkindを拒否する。コロンactionはwordInLoopを経ずにフレーム移行するため、1754だけの検査では足りない（`src/forth.zig:2006`、`src/forth.zig:2023`、`src/forth.zig:2065`）。別名・forward等の解決先、DOES>本体、callback builtinの許可も検査する（`src/forth.zig:1547`、`src/forth.zig:1549`、`src/forth.zig:2043`）。VALUE/FIELDを再入するという理由だけで動的呼出しと同一視して拒否する案ではない。
- `.call_builtin`および`.call`等からのbuiltin実行：EXECUTE、PERFORM、BASE-EXECUTE等、2節のcallback語を個別の許可集合で拒否する。直接builtin経路とwordInLoop内のbuiltin経路も覆う（`src/forth.zig:2101`、`src/forth.zig:1724`、`src/core/words_compiling.zig:75`、`src/core/words_system.zig:268`、`src/core/words_numeric.zig:31`）。
- `.call_colon`：展開済み本体と通常の呼出し先を走査する。inlineのガード自体は動的xt呼出しではないが、元の語名だけの検査で展開後Opの検査を省略してはならない（`src/forth.zig:1978`、`src/forth.zig:1983`、`src/core/inline_calls.zig:49`、`src/core/inline_calls.zig:55`）。

これは拒否検査の実装済み一覧ではない。許可する経路では、コロンのフレーム移行とexecuteWord再入の双方で同じworker文脈を維持し、動的先を許可検査する必要がある。

## 6. 未確認事項と判断事項

- 未確認：worker専用経路の実装、debug=falseでの取消し、入れ子とinline/specialize後の実行、資源解放と終端通知。本書は静的監査であり、詳細計画13節の試験合格を主張しない。
- 未確認：保存辞書内の入口ごとの具体的な到達集合。確定したbuiltin許可一覧とSnapshotがないため、条件付きの行を一律に到達不能とはできない。
- 判断が必要：DOES>・forward・synonym・遅延語と各callback語を初期試作で許す範囲。builtinのEXECUTEだけの拒否では、専用.execute Op・.local_execute・DEFER・BASE-EXECUTE・PERFORM等が残る。拒否単位は5.1節のとおりである。
- 判断が必要：取消し専用エラーの名称、公開codeの有無、通常エラー・終了処理エラーとの優先順位、タスク失敗と取消し終端の区別。
- 判断が必要：例外診断callbackをワーカーから外すか、取消しを伝播できる診断APIへ変更するか。登録語を禁止するだけではSnapshotに既存登録がある場合を覆えない。
- 判断が必要：EXEC-LIMITED等のdebug機能の許可と、worker文脈とcounted文脈の共存規則。通常メインループ方針と方式採用は詳細計画9.1節・判断記録の判断に残す。

## 付録：実際に用いた列挙・集計コマンド

PowerShellで実行した。rgの1出力行を1呼出し箇所と数え、同一行に複数呼出しがないことは一覧と表の照合で確認した。宣言とコメントを含む広い検索でも別名経由の参照がないかを確認した。本集計は実行回数ではない。

```powershell
# 呼出し全体：58行
rg -n '\.executeWord\s*\(' src | Measure-Object
# core：22箇所、15ファイル
@(rg -n '\.executeWord\s*\(' src/core).Count
rg -l '\.executeWord\s*\(' src/core | Measure-Object
# forth.zig：7箇所
@(rg -n '\.executeWord\s*\(' src/forth.zig).Count
# テスト：29箇所
rg -n '\.executeWord\s*\(' src/tests | Measure-Object
# 宣言・コメント・別形の参照も検索
rg -n 'executeWord' src
rg -n '\bexecuteWord\b' src | Select-String -NotMatch '\.executeWord|pub fn executeWord|//'
# 最後のコマンドに該当行なし
# 明示エラー参照を全域で確認
rg -n 'executeWord|error\.(Quit|StepLimit)' src
# 実行用の生成・予算回復・CATCH除外：6行、うち両エラーの捕捉除外2行
rg -n 'error\.(Quit|StepLimit)' src -g '!**/tests/**' -g '!defs.zig' -g '!error_reporting.zig'
# 今回の再確認：結果は順に58、22、15、7、29である
@(rg -n '\.executeWord\s*\(' src).Count
@(rg -n '\.executeWord\s*\(' src/core).Count
@(rg -l '\.executeWord\s*\(' src/core).Count
@(rg -n '\.executeWord\s*\(' src/forth.zig).Count
@(rg -n '\.executeWord\s*\(' src/tests).Count
# ループ入口と全handleError呼出し、コンパイル形、診断受け口の再確認
rg -n 'wordInLoop|handleError|local_execute|compileCall|specializeCall' src/forth.zig src/core/local_variables.zig
rg -n 'reportDiagnostic|interpretLine|runEntry|includeFile' src/main.zig src/freestanding_check.zig
# CATCH-NOBT・NOTHROWの実体の確認
rg -n 'nothrow|handleError|runCatch' src/core
```

集計対象は当日の作業ツリーであり、同時作業でソースが変われば行番号と件数は再照合が必要である。他作業者の変更を含むgit差分を本書の作成結果へ取り込んでいない。書き込み対象は本ファイルのみである。

