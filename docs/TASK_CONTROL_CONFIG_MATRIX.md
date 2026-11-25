# タスク制御の構成試験表（1378／06-B）

作成日：2026-11-23。対象：1048配下のタスク制御。本文は現行ソースの調査結果と、実装後に行う試験の提案を区別する。試験・ビルド・速度／時間の測定は実行していない。既存スクリプトの記載は試験能力の確認であり、現在の成功実績を示すものではない。

## 1. 設計上の境界

タスク語の所属はEXTENSIONが第一候補であり、graphics/audioからextensionを自動で有効化しない。graphics単独でタスク語が必要かはD06の判断事項である（`docs/TASK_CONTROL_DETAILED_PLAN.md:307`、`docs/TASK_CONTROL_DETAILED_PLAN.md:308`、`docs/TASK_CONTROL_DETAILED_PLAN.md:475`）。追加のbuild optionを採用済みとはしない（`docs/TASK_CONTROL_PLAN.md:39`）。

652はdebug専用のままとし、通常ビルドのタスク取消しを別経路で成立させる。ワーカー専用経路も採用前の候補であり、本書は独立Forth VMの採用を確定しない（`docs/TASK_CONTROL_DETAILED_PLAN.md:95`、`docs/TASK_CONTROL_DETAILED_PLAN.md:100`、`docs/TASK_CONTROL_DETAILED_PLAN.md:253`、`docs/CORE_EXTENSION_DETAILED_DESIGN.md:818`、`docs/CORE_EXTENSION_DETAILED_DESIGN.md:822`）。

レビューR13は公開語群依存と内部通知の依存の分離を求めている（`docs/CORE_EXTENSION_REVIEW_RESPONSE.md:26`）。レビューR04の当時の未着手記載を現在の実装状態とは扱わず、以下ではソースを根拠にする（`docs/CORE_EXTENSION_REVIEW_RESPONSE.md:17`）。debugなしの取消しを652に依存させない判断も維持する（`docs/CORE_EXTENSION_DESIGN_DECISIONS.md:23`）。

## 2. 現在のビルドオプションと除外処理

| オプション | 既定値 | 現在の意味・根拠 |
|---|---|---|
| `debug` | true | デバッグ機能と語を選択する。`EXEC-LIMITED`とASSERT系も除外対象である（`build.zig:20`、`src/core/defs.zig:67`） |
| `extension` | true | 公開EXTENSION語群を選択する。共通ホストRuntimeとは独立である（`build.zig:19`、`src/core/defs.zig:34`、`src/core/defs.zig:66`） |
| `graphics` | true | REQUIRE-GRAPHICSとGFX語群を選択する（`build.zig:16`、`src/core/defs.zig:64`） |
| `audio` | true | REQUIRE-AUDIOとSND語群を選択する（`build.zig:18`、`src/core/defs.zig:65`） |
| `files` | true | ファイル語・ブロック語・SLURP等を除外する。include配布と実パイプ試験にも条件がある（`build.zig:12`、`src/core/defs.zig:60`、`build.zig:100`、`build.zig:209`） |
| `float` | true | 浮動小数点語と関連定義語を選択する（`build.zig:10`、`src/core/defs.zig:59`） |
| `help` | true | HELP・LICENSEとテキストを選択する（`build.zig:13`、`src/core/defs.zig:20`、`src/core/defs.zig:61`） |
| `tools` | true | SEE・LOCATE・WHEREやソース操作語を選択する。trace語はdebugとの重複がある（`build.zig:14`、`src/core/defs.zig:62`、`src/core/defs.zig:67`） |
| `image` | true | SAVE・LOAD・SAVESYS・APP-ENTRY系の公開語を選択する（`build.zig:15`、`src/core/defs.zig:63`） |
| `x11` | true | Linuxでgraphicsと共に有効なときX11用Cソースを追加する。EXTENSIONの選択ではない（`build.zig:17`、`build.zig:81`） |
| `strip` | fast/smallでtrue、それ以外false | デバッグ情報の除去であり、debug語群の選択とは別である（`build.zig:7`、`build.zig:8`） |

除外は各語群のbuiltin集合の論理和であり、他の語群を有効化する処理ではない。重複する語はどちらかの除外条件で除外される（`src/core/defs.zig:69`）。extensionの読込み入口は除外時にUnknownWordを返す（`src/core/words_extension.zig:62`）。

語群以外に標準target・optimize設定と、`memory-mib=32`、`locals-kib=64`、`stack-cells=4096`、`words=65535`、`names-kib=1024`がある。これらは容量・対象環境の設定であり、新しいタスク用スイッチではない（`build.zig:4`、`build.zig:5`、`build.zig:32`〜`build.zig:36`）。

## 3. 既存の構成試験が選ぶ組合せ

以後、ビット列は既存スクリプトと同じ **A/G/E = audio/graphics/extension** の順である。1はtrue、0はfalseである。省略するオプションは既定値である。

| 試験入口 | 組合せ・検査範囲 | 根拠 |
|---|---|---|
| `verify-extension-matrix.py` 基本部 | 000、001、010、011、100、101、110、111。各構成で`zig build test`と実行体buildを行い、REQUIRE・語彙・代表語の有無を検査する | `tests/scripts/verify-extension-matrix.py:48`、`tests/scripts/verify-extension-matrix.py:55`、`tests/scripts/verify-extension-matrix.py:59`、`tests/scripts/verify-extension-matrix.py:64` |
| 同追加部 | 001＋files=false、001＋debug=false、111＋files/debug=false、001＋files/debug/float/image/x11=false。基本部と合わせて12構成である | `tests/scripts/verify-extension-matrix.py:49` |
| 同読込み・復元 | E=1でHOST-OSとMARKER後の再読込み。001で保存したextensionイメージを000へ読み込み、失敗時に辞書が維持されることを検査する | `tests/scripts/verify-extension-matrix.py:75`、`tests/scripts/verify-extension-matrix.py:84` |
| `verify-feature-matrix.py` | float/files/help/tools/image/graphics/audio/extension/debugをそれぞれ単独でfalseにする既定9構成。任意の直積ではない。LinuxをWindowsから指定した場合はcross build後にWSLでcore/host/runtimeを実行する | `tests/scripts/verify-feature-matrix.py:12`、`tests/scripts/verify-feature-matrix.py:33`、`tests/scripts/verify-feature-matrix.py:39`、`tests/scripts/verify-feature-matrix.py:45`、`tests/scripts/verify-feature-matrix.py:51`、`tests/scripts/verify-feature-matrix.py:61` |
| release workflow | testジョブのOSはwindows-latest、ubuntu-latest、ubuntu-24.04-arm、macos-latestである。通常、float=false、000、float/files/help/tools/image/graphics/debug=falseは全OSで実行する定義である。最後の構成はaudioとextensionを指定していないためA/G/E=101であり、000と101はmacOSも対象である。baselineとbaseline＋optimize=fastの2実行だけはrunner.archがX64の場合に限る。実行結果は未確認である | `.github/workflows/release.yml:25`、`.github/workflows/release.yml:32`、`.github/workflows/release.yml:35`、`.github/workflows/release.yml:36`、`.github/workflows/release.yml:37`、`.github/workflows/release.yml:38`、`.github/workflows/release.yml:41`、`.github/workflows/release.yml:44`、`.github/workflows/release.yml:46` |
| Zigの`test` step | 選択された同一optionsでcore/hostを試験する。独立Runtime試験とCortex-M0+ freestandingコンパイルも含む。全組合せの生成はこのstep自体では行わない | `build.zig:135`、`build.zig:161`、`build.zig:164`、`build.zig:171`、`build.zig:178`、`build.zig:191`、`build.zig:203` |

上表の件数は付録の静的集計による。各入口の件数を足して独立した構成総数とはしない。設定の重複があるためである。feature matrixは引数で対象群を変更できる（`tests/scripts/verify-feature-matrix.py:12`）。release workflowにextension matrix全体の実行は記載されていない（`.github/workflows/release.yml:32`〜`.github/workflows/release.yml:46`）。

既存の除外イメージ単体試験は、HOST-OS・SND-BEEP・OPEN-FILE・DBGについてbuiltinとinline Opの除外を検査する。将来のタスクbuiltinが自動でこの列挙に加わるわけではない（`src/tests/extension_test.zig:166`、`src/tests/extension_test.zig:170`）。

## 4. 内部Runtimeと652の境界

| 要素 | 現在確認した実装 | タスク追加時の試験提案 |
|---|---|---|
| Clock／Deadline | ClockとWakeOpsの契約はcoreにある。ホストRuntimeは時計を保持し、期限付きwaitへ渡す（`src/core/runtime_base.zig:6`、`src/core/runtime_base.zig:16`、`src/host_runtime.zig:26`、`src/host_runtime.zig:56`） | 偽時計で期限成立と通知競合を制御する。公開時計語の有無とは分ける |
| WakeOps | 実起床または注入起床を選び、observe/notify/waitを提供する（`src/host_runtime.zig:28`、`src/host_runtime.zig:39`、`src/host_runtime.zig:43`） | 完了・取消し通知を状態確定後に行う。通知併合でも結果を回収する |
| Cancellation | atomicな取消し型があり、Runtimeは全体終了時に要求する（`src/core/runtime_base.zig:52`、`src/host_runtime.zig:30`、`src/host_runtime.zig:72`） | タスク固有トークンと全体終了を分離し、1件の取消しで他を止めない |
| ResourceTable | taskを含む資源種別と型付き台帳がある。RuntimeのinitTableは呼出し側が用意したOwnedTableの記憶域を初期化し、Runtimeへの参照と固定アドレスを結び付け、関連付けた台帳数を加算する。台帳の記憶域はRuntimeが所有するものではない（`src/core/runtime_base.zig:67`、`src/core/runtime_base.zig:73`、`src/host_runtime.zig:88`〜`src/host_runtime.zig:94`、`src/host_runtime.zig:98`〜`src/host_runtime.zig:103`） | 台帳更新は所有ホストへ戻す。別所有者・古い世代・別種ID・満杯・解放競合を検査する |
| 652 | execution状態はdebugで型が変わり、activeもdebugなしではfalseである。counted経路の選択もdebug条件下にある（`src/forth.zig:330`、`src/core/execution_control.zig:20`、`src/forth.zig:1877`） | debug=falseでもタスク取消しを成立させる。debug=trueでは予算と取消しが相互に消費・解除されないことを確認する |

ホストの起動処理はRuntimeを初期化してHostContextへ渡す。独立Runtime試験はForth辞書・UIなしでRuntime等をimportし、build_optionsを追加せず構築する（`src/main.zig:3732`、`src/main.zig:3748`、`src/runtime_test.zig:1`、`build.zig:178`）。したがってE=0を内部Runtimeの不存在と同一視しない。ただし実行体に残る全コード量や、将来のTaskManagerの配置は未確認である。

タスク側への接続は今後の提案である。タスク台帳をワーカーから直接変更せず、タスク固有の取消しと全体終了を分ける設計に従う（`docs/TASK_CONTROL_DETAILED_PLAN.md:168`、`docs/TASK_CONTROL_DETAILED_PLAN.md:173`）。Stateの値コピーは禁止であり、専用Writerと許可語検査が必要である。構成が有効でもUI・音・メインファイルの権限をワーカーへ与える理由にはならない（`docs/CORE_EXTENSION_WORKER_STATE_AUDIT.md:6`、`docs/CORE_EXTENSION_WORKER_STATE_AUDIT.md:14`、`docs/TASK_CONTROL_DETAILED_PLAN.md:139`、`docs/TASK_CONTROL_DETAILED_PLAN.md:194`）。

## 5. タスク追加後の代表構成案

以下はD06でEXTENSION所属を採った場合の**未実行の提案**である。「有」はREQUIRE-EXTENSIONで読込み、EXTENSIONを探索順序へ加えた後に公開タスク語を使えることを指す。語名・ABI・エラー値は未確定であり、TASK-SUBMIT等は設計候補である（`docs/TASK_CONTROL_DETAILED_PLAN.md:294`）。

Runtime欄の「接続」はタスク機能からClock/WakeOps/Cancellation/ResourceTableのすべてを利用する提案、「基盤」はそのすべてを公開タスク語と独立して検証し、タスク資源を公開しない提案である。debug欄の1は652有効、0は652除外である。各行は`zig build test`、実行体による語の有無、対象のタスク契約試験を組み合わせる。

| ID | A/G/E | debug | 追加のfalse指定 | タスク語 | Runtime依存 | 652との関係・期待される結果 |
|---|---|---|---|---|---|---|
| C00 | 000 | 1 | なし | 無 | 基盤 | 652は残る。タスク・各追加語彙なしでも内部基盤と通常実行が成立する |
| C01 | 001 | 1 | なし | 有 | 接続 | 表示・音なしで投入・成功・結果・取消し・解放が成立する。652予算と取消しを分離する |
| C02 | 010 | 1 | なし | 無を仮置き、D06待ち | 基盤 | graphicsのみで描画と内部時計・通知が使える。652からタスク語を生やさない |
| C03 | 011 | 1 | なし | 有 | 接続 | 描画と計算結果の回収を結合する。ワーカーからUIへ直接触れず、652との混同がない |
| C04 | 100 | 1 | なし | 無 | 基盤 | 音の有効化だけでタスク語を公開しない。652と音側の終了処理を分離する |
| C05 | 101 | 1 | なし | 有 | 接続 | 音とタスクを併用し、一件の取消しで音・他タスク・Runtime全体を止めない |
| C06 | 110 | 1 | なし | 無 | 基盤 | graphics/audio双方があってもEを自動有効化しない。652は独立して残る |
| C07 | 111 | 1 | なし | 有 | 接続 | 全語群の結合、入力・I/O・描画・完了通知を確認し、652との入れ子条件を照合する |
| C08 | 001 | 0 | なし | 有 | 接続 | 652なしで計算・無限ループ取消しが成立し、メインが処理を続ける |
| C09 | 001 | 1 | files | 有 | 接続 | ファイル語なしでもメモリ上のSnapshotと入力コピーが成立することを確認する。652は有効 |
| C10 | 111 | 0 | files | 有 | 接続 | 652・ファイル語なしで表示・音とタスクが結合でき、終了時に回収できる |
| C11 | 001 | 0 | files,float,image,x11 | 有 | 接続 | 既存の縮小構成を継承する。公開SAVE/LOADなしでも内部Snapshot方式が成立することを確認する。未成立なら内部依存を判断へ戻す |
| C12 | 000 | 0 | なし | 無 | 基盤 | Eも652もない構成でタスク語・タスク資源を要求せず、内部Runtimeの取消し・起床・台帳試験が成立する |
| C13 | 010 | 0 | なし | 無を仮置き、D06待ち | 基盤 | graphics単独の内部利用が652に依存しない。公開タスク語の要否はこの試験だけでは決めない |
| C14 | 111 | 0 | help | 有 | 接続 | HELPなしでも公開タスク語と取消し・回収が成立する。652を再導入しない |
| C15 | 111 | 0 | tools | 有 | 接続 | ソース操作語なしでもタスクが成立する。debug/tools双方に属する語の復活を防ぐ |
| C16 | 011 | 0 | x11 | 有 | 接続 | LinuxでX11なしの対応backend・端末との結合を確認する。未対応の描画待機は永久待機にしない |

全A/G/E組合せを残す理由は公開語群の独立性を守るためである。debug/filesの全直積を要求するのではなく、取消し・Snapshot・内部Runtimeの境界が異なる構成を代表として加える。C00〜C11は既存extension matrixの設定を継承し、C12以降はタスク向けの追加案である。

共通の期待結果は次のとおりである。

- E=0では公開タスク語・HELP項目・保存イメージ中の追加builtinと直接Opの除外を検査し、復元拒否時に既存辞書を保つ。内部Runtimeの再利用を拒否する条件とはしない。
- E=1では読み込み失敗の巻戻し・再試行、MARKER/FORGET後の再読込みを検査する。活動中タスクとの辞書変更・復元の可否はD03等の確定契約に従い、安全な拒否と回収を確認する。
- 各接続構成では成功・失敗・取消し・所有者終了の後に資源を回収する。許可する入れ子EXECUTE/CATCH・inline Opでも取消し・権限検査を維持し、拒否する場合は迂回せず拒否する。
- ClockとWakeOpsを注入し、登録前後・通知併合・完了と取消しの競合を操作順で再現する。経過時間・速度の測定は含めない。

これらは詳細計画の必須検証、通常ビルド・構成・OS境界を具体化した提案である（`docs/TASK_CONTROL_DETAILED_PLAN.md:419`、`docs/TASK_CONTROL_DETAILED_PLAN.md:425`、`docs/TASK_CONTROL_DETAILED_PLAN.md:439`、`docs/TASK_CONTROL_DETAILED_PLAN.md:441`）。Windows・Linux・macOSの実行範囲を別々に残し、cross buildだけを実機成功と扱わない（`docs/TASK_CONTROL_DETAILED_PLAN.md:442`）。freestandingも既存のcore/OS境界を保つ確認として継続する（`build.zig:191`）。

## 6. 未確認事項と判断事項

| 区分 | 内容・確定先 |
|---|---|
| 判断 D06 | graphics単独（C02/C13）で公開タスク語が必要か。必要ならEXTENSIONを利用者が明示併用する案と、所属を見直す案を比較する。内部時計・起床が使えることだけで公開所属を確定しない |
| 判断 D01 | ワーカー方式と専用実行経路、debug機能をワーカー内で許す範囲。C01/C07の652併用期待を確定する（`docs/TASK_CONTROL_DETAILED_PLAN.md:267`、`docs/TASK_CONTROL_DETAILED_PLAN.md:470`） |
| 判断 D06等 | 語名・ハンドル表現・エラー値と未対応待機の返し方。現行REQUIREのエラー値を新しいTASK語へ流用すると決めない |
| 確認済み（2026-11-25） | タスク実装後の全代表構成C00〜C16の成否。Windows・Linuxは1381（[実装報告](TASK_CONTROL_IMPL_1381.md)）、Macは実機で `verify-task-public-matrix.py --fresh-cache` を実行し17構成すべて合格（main `adcc38b`、[1383報告](TASK_CONTROL_IMPL_1383.md)）。各OSのネイティブ画面backendとの結合はtque 1394・1397〜1399で確かめる |
| 確認済み（2026-11-25） | image=falseでの内部Snapshot成立。C11（image=false、extensionあり）は3 OSで合格し、その検査 `tests/scripts/check-task-public.fs` はTASK-SNAPSHOTを実際に取得・解放する |
| 未確認（確認方法：tque 1400・1390） | 実行体に残るTaskManager等の範囲、通常ループの生成コードへの影響。語の不在だけでは証明しない。extension=false構成の隠れた組込みの語・HELP項目・保存イメージのOpの除外を検査する試験を1400で加え、通常ループの生成コードはA/A′/Bの逆アセンブル比較（1390）で確かめる |

## 付録：件数の集計コマンド

以下をPowerShellから実行した。スクリプトのimportやmain実行はせず、ASTと文字列だけを読み取った。結果はextension matrix 12構成、feature単独除外9群、明示bool option 11個であった。boolには語群以外のstrip/x11も含む。提案表の件数を既存試験の件数へ混ぜていない。

```powershell
@'
import ast,itertools,re
from pathlib import Path
p=Path('tests/scripts/verify-extension-matrix.py')
t=ast.parse(p.read_text(encoding='utf-8'))
n=next(n for n in ast.walk(t) if isinstance(n,ast.AugAssign) and isinstance(n.target,ast.Name) and n.target.id=='configs')
c=[(b,{}) for b in itertools.product((False,True),repeat=3)]+ast.literal_eval(n.value)
print('extension matrix:',len(c))
for b,e in c: print(''.join(str(int(x)) for x in b),e)
t=ast.parse(Path('tests/scripts/verify-feature-matrix.py').read_text(encoding='utf-8'))
n=next(n for n in ast.walk(t) if isinstance(n,ast.Call) and any(k.arg=='default' and isinstance(k.value,ast.List) for k in n.keywords))
g=ast.literal_eval(next(k.value for k in n.keywords if k.arg=='default'))
print('feature exclusions:',len(g),g)
s=Path('build.zig').read_text(encoding='utf-8')
opts=re.findall(r'b\.option\(bool, "([^"]+)"',s)
print('explicit bool options:',len(opts),opts)
'@ | python -
```
