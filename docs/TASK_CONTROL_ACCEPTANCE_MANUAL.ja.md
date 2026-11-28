# タスク制御の手動受け入れ（1382）

英語版：[TASK_CONTROL_ACCEPTANCE_MANUAL.md](TASK_CONTROL_ACCEPTANCE_MANUAL.md)。

## 共通の準備と記録

リポジトリのルートから、前景の実端末で1項目ずつ実行する。
WindowsはPowerShellと `zig-out/bin/sigma.exe`、別機械のLinuxはClaudeが
`zig-out/bin/sigma` を使用する。Zig 0.17.1で
`zig build -Doptimize=ReleaseFast -Ddebug=false -Dtask-trace=false` を実行して準備する。
本測定は固定計画に対する利用者の確認後に行う。この手順では進行を観察し、時間を測らない。
AC番号、OS/kernel、端末、backendと能力、コマンド、入力キー、期待と実際の結果、終了コード、
画面/ログ、ソースと実行体のSHA-256、不足資源を `.work/acceptance/manual-<OS>/` に残す。
能力がなければ未確認とし、確認方法を提案する。合格にはしない。OS間で合格を転記しない。
別端末から試験プロセスのスレッドと子プロセスを確認する。終了操作の対象は試験自身だけとする。
Ctrl+C後はシェルのecho、カーソル、入力、新しいsigma起動を確認する。

検索は `zig-out/bin/sigma tests/task/task-search.fs`、I/Oは `zig-out/bin/sigma tests/task/task-checksum.fs` で起動する。Windowsではsigma.exeに置き換える。自動examples群を先に実行した場合は `.work/1380/checksum-chunks.fs` も使用できる。3塊の期待するchecksumは8355840、8355840、21である。短すぎて処理中の終了操作を観察できなければ、その操作は未確認と記録する。

## AC-02

実行：`zig-out/bin/sigma tests/task/task-path.fs`（Windowsはsigma.exe）。

- **準備：**前景端末でG1を起動する。

- **操作：**`n` と無関係な文字を交互に入力し、計算中に `q` で終了する。

- **期待する結果：**入力とframe/generation出力が進み、旧世代が最新表示を上書きせず終了する。

- **記録すること：**入力順、表示世代、取消し診断、終了状態。端末例だけではネイティブ画面の合格にはならない。

ネイティブ画面とカーソルは1394で題材を追加し、1397〜1399で各OSのClaudeが記録して、利用者が目視確認する。

## AC-05

実行：`zig-out/bin/sigma tests/scripts/check-task-console.fs`（Windowsはsigma.exe）。

- **準備：**`.work` を作り結合fixtureを起動する。

- **操作：**`active` で `r`、`replaced` で `c`、`bye-active` で `b` を押す。

- **期待する結果：**frame=r/c/b、cancelled、releasedが表示され、計算中もファイルI/Oが進み終了する。

- **記録すること：**出力、一時ファイル回収、プロセス/スレッド所有。複数タスク・音・実画面の同時所有は専用fixtureがなく未確認とする。

端末のKEYは行入力でありEnterを要する（USER_MANUAL.mdのKEY）。この題材はEKEY EKEY>CHARを使う。改行が次の入力にならないようEnterを送らず、1文字ずつ送る。verify-task-examples.pyでパイプも確認する。複数タスク・音・窓の同時所有は1394で題材を追加し、1397〜1399で各OSのClaudeが実行して、利用者が画面と音を確認する。

## AC-18

リポジトリのルートで `zig build` 後に実行する（Windowsは `sigma.exe`）。

```sh
export ZIG_GLOBAL_CACHE_DIR=$PWD/.work/codex-cache/global ZIG_LOCAL_CACHE_DIR=$PWD/.work/codex-cache/local
python3 tests/scripts/manual-acceptance-tty.py --cases mixed --sigma zig-out/bin/sigma
```

Windows PowerShell:

```powershell
$env:ZIG_GLOBAL_CACHE_DIR = "$PWD/.work/codex-cache/global"
$env:ZIG_LOCAL_CACHE_DIR = "$PWD/.work/codex-cache/local"
zig build
python tests/scripts/manual-acceptance-tty.py --cases mixed --sigma zig-out/bin/sigma.exe
```

- **準備：**Python 3.9以上、extension/files有効、書込可能な `.work/` が必要。一時ファイル名が固定なのでAC-18の題材を同時に複数起動しない。道具はLinux/macOSでpty、Windowsで包含Job内のConPTYを使う。入力は道具がEnterなしで送る。
- **操作：**`check-task-wait-real.fs` が `task-wait-real-common.fs` を読み込む。`.work/ac18-real.tmp` に実際に書いて開き、実I1タスクを投入する。同じ整列済み配列へ端末入力（kind=1）、ファイル読取可用（kind=2）、成功終端（kind=3）、時計（kind=4）を登録する。別途30 msの時計待機でタイマー通知を確認し、混合集合の時計は0にする。実ファイルが常に可用でも正の相対期限を毎回作り直さないためである。道具はINPUT-READY後に `x`、INTERRUPT-READY後にCtrl+Cを送る。
- **期待結果：**SOURCES=15、SIMULTANEOUS=4。各イベントの添字・タグ・理由を照合し、入力とファイルの実データが後で消費できる。80回の配列再利用、Ctrl+CのTHROW -28を捕捉した後の再登録、close後のHANDLE、開き直しての再登録が成立する。PASS、一時ファイル削除、正常終了、端末復元、同じ端末で新しい検索プロセスの入力を確認する。
- **記録：**`ac18-real-composite/output.bin`、`output.txt`、`events.jsonl`、`processes.json`、`results.json`。解除の公開動作を確認するもので、内部参照数は見えない。Zigのwait/host/public API試験で失敗・巻戻し・解除の経路も確認する。通常ファイルは実供給元だが、遮断したパイプが可用になる試験ではない。

paintと窓のcloseは選択実行とする。画面のあるセッションでClaudeが上のコマンドへ `--native-paint --timeout 120` を付けて実行する（1397〜1399）。`check-task-wait-paint-real.fs` は**同じ**配列へkind=5を追加する。ネイティブのホスト窓id=0、arg0は `GFX-WINDOW-FRAMES` のshown、arg1=0。SOURCES=31、SIMULTANEOUS=5を期待する。赤い128×128の画像を観察し、CLOSE-WINDOW-NOWで窓の標準close操作を行う。題材はネイティブのopenフラグが消えるまで待ち、窓がない状態で新しいpaint登録がNO-CAPABILITYになることを確認する。目視結果は別途記録する。paint成立後の利用者によるcloseを確認するもので、未描画の登録中にcloseする競合は別の試験（1394）である。補助の `public paint real native window wait (opt in)` は明示的なOKを確認する。この補助試験のmacOSでのskipは未確認であり、5供給元の題材の失敗ではない。

`--native-paint` なしではpaint/closeを**未確認**として記録する。`--display-reason` に実際の理由を書く。このLinuxサンドボックスではソケット制限によりX11へ接続できない。時計でpaintを代用せず、画面の合格を推定しない。1397〜1399でClaudeが画面のあるネイティブ環境で再実行する。道具はDISPLAYを `:0` に固定せず引き継ぐ。

OS差の根拠：`src/main.zig` の `ioWaitProbe`/`filePollByte` は照会したバイトを保持し、意味上のEOFを扱う。POSIXの記述子待機はpollを使う。Windowsの通常ファイルはstdio、ネイティブパイプは有界Reader/Writerと共通Wake通知を使う（`host_file_reader.zig`）。この題材はPOSIX専用FIFO作成を避け、通常ファイルと実READ-FILE・バイト照合を使う。既存のmainホスト試験はファイル待機の中断・先読み復元、公開API試験はI/O理由の変換を確認する。Windows/macOSでは可用・EOF/reposition・Ctrl+C・端末復元・プロセス後始末をClaudeが実機確認する。Linux結果で他OSを合格にしない。

## AC-19

上の `--cases mixed` コマンドを使う。`check-task-fair-real.fs` は**1つのsigmaプロセス**でT1検索とI1チェックサムを反復し、端末入力と実LICENSEファイル読取を同時に流す。入力・ファイル・両タスク終端・0時計を一緒に登録する。メインの各巡回で完了を照会し、端末イベントを最大1件消費し、終了した仕事を解放して補充し、実行を譲る。成功した検索結果とチェックサム値も照合する。`q` まで続く。

道具は4観測区間（`--fair-window`、既定2秒）にわたり `a/b/a/b` を送り、最後に `q` を送る。`progress.json` に成功した検索・チェックサムの件数、入力回数、ファイルのバイト数、受信出力バイト数、時刻、sigma PIDを累積記録する。記録した標本間の各区間ですべての件数の進みを要求する。途中終了・結果不正・件数の停止・後始末失敗は小項目を不合格にする。処理速度・応答時間の閾値は設けない。区間は有限の観測期間を選ぶもので、`--timeout` はハング検出だけに使う。遅い実機では証拠と理由を残して観測区間を延ばせる。

観測した実行での進行の証拠であり、全スケジュールの証明ではない。満杯時の再投入・滞留・Snapshot投入可能時刻は別範囲（1396）、ワーカー間待機の禁止は公開APIのままである。広い受入範囲やOS採取の不足によりAC全体が未確認でも、各小項目の結果を確認する。

## AC-20

同じプロセスの題材を `ac20-same-process` として別ログ・別件数で再実行する。終了操作までT1・I1・端末入力・ファイルデータ・出力が同時に進み、記録区間でどの件数も停止しないことを確認する。`results.json`、両方の `progress.json`、実行ファイルとソースのハッシュ、OSを記録する。`--self-test` で既存の包含確認も行う。後始末で道具が起動したセッション・プロセスグループの外へ信号を送ってはならない（Windowsは非離脱Job）。新場面は既存の後始末をそのまま使う。

`--cases all`（既定）では以前の別セッションの検索・checksum同時進行も残す。それだけで同一ホスト内の公平性を認定しない。混在題材は単一VMの時間確認（1390〜1393）や画面・音の所有確認（1394）を代替しない。Windows ConPTY・macOS pty、ネイティブプロセス採取、選択式の実画面観察は1397〜1399でClaudeが実行する。

Linuxでの記録（2026-11-25、main `6856d99` に作業ツリーの変更を加えた状態）：新しい画面不要の3小項目は合格。AC-18は4供給元の同時返却、80回の再利用、中断後の再登録、ファイル再open、端末復元を確認した。AC-19の検索/チェックサムは23/22 → 90/90、AC-20は23/22 → 90/89へ進み、両方で入力は1 → 4、出力バイト数は60 → 240、ファイルバイト数も毎標本で進んだ。これは観測件数であり、性能目標ではない。paint/closeはサンドボックスのソケット制限でX11へ接続できないため未確認。Windows/macOSもClaudeの実行までは未確認。[Linux結果要約](measurements/2026-11-25-task-1395-linux.json)に範囲と件数を保存し、全ログは `.work/acceptance/1395-linux/` に残す。既存例の検証17グループと端末の自己試験は合格。`zig build test` は既知のX11 send=-1の2件だけ失敗（1662成功、48 skip）し、`zig build test -Dx11=false` は合格した。文書検査は指摘0件で合格。

## AC-24

実行：`zig-out/bin/sigma tests/task/task-path.fs`（Windowsはsigma.exe）。

- **準備：**WindowsはGet-Process、LinuxはpsでPID・スレッド・子の開始状態を記録する。

- **操作：**処理中に `q`、新規起動してCtrl+C、検索とchecksumでも繰り返す。

- **期待する結果：**所有タスクが終了し端末が復元する。タスク終端・出力排出・プロセス終了を区別する。

- **記録すること：**前後の所有資源と端末状態。子・音・画面および隔離した停止不能hostの結合fixtureは未対応である。workerの強制終了を回収成功としない。

子・音・窓を保持した終了は1394で題材を追加し、1397〜1399で各OSのClaudeと利用者が確認する。止められないhostの終了回収はabadd1bのreap再現試験（src/tests/task_reap_reproduction_host_test.zig）で確認済みであり、今回の実行とは別の証拠として扱う。専用の無限ループワーカーでTASK-STATEがTASK-RUNNINGを返した後にWORKER-RUNNINGを出し、その印を受信してからqまたはCtrl+Cを送る。これは専用題材の実行中の確認であり、有限の各アルゴリズムの実行中を証明するものではない。checksumは生成した64 MiBファイルで途中終了を確認する。

## AC-25

実行：`zig-out/bin/sigma tests/task/task-path.fs`（Windowsはsigma.exe）。

- **準備：**G1を起動し、次にT1で繰り返す。

- **操作：**G1は `nnn`、T1は `ba` を入力し、`q` で終了する。

- **期待する結果：**最新世代のみ反映し、G1の世代4は95頂点、T1のaは1048576一致・1000件保存、bは0件である。

- **記録すること：**失敗時の従前表示維持、世代、回収。実画面での失敗注入・混在する実供給元の題材は未対応であり、該当部分は未確認とする。

道具は最大負荷のG1-open/wall/snake、G2、T1、I1を端末で実行し、結果とq後の復帰を確認する。response.fsではbとqのINPUT-APPLIEDを確認する。失敗注入時のネイティブ表示維持は1394、実供給元の混在は上記AC-18/19/20の題材を使い、1397〜1399で各OSのClaudeと利用者が確認する。この時間を測らない筋書きは、別途合意した10分間の確認を代替しない。

## 確認結果の記録

各項目を合格・失敗・未確認に分け、証拠を残す。確かめられない項目は未確認とし、確認方法を提案する。提案には、理由、必要な道具や題材、使う機械、誰が行うか（Claudeが自動で行うか、利用者が立ち会うか）を書く。提案はtqueのタスクとして登録し、未確認のまま残さない。速度・容量の合否は別の固定計画に従う。

## 最大負荷の題材と縮小した試行計画

2026-11-24の判断により、取消しは各位相100試行、代表5種類のメモリ操作も
各位相100試行、対話は各ケース10分×1回に固定する。利用条件8節の正式な出発点とは
異なる縮小計画であり、すべての結果にその区別を残す。目標の80%を超える項目の
追加試行は固定計画に従い、元のrunと追加理由を記録する。

リポジトリのルートで対話用の題材を生成する。

```text
python -c "import runpy; from pathlib import Path; runpy.run_path('tests/scripts/acceptance-fixtures.py')['generate'](Path('.'), Path('.work/manual-1382'), 1000000000)"
zig-out/bin/sigma .work/manual-1382/G1-open.fs
zig-out/bin/sigma .work/manual-1382/G1-wall.fs
zig-out/bin/sigma .work/manual-1382/G1-snake.fs
zig-out/bin/sigma .work/manual-1382/G2.fs
zig-out/bin/sigma .work/manual-1382/T1.fs
zig-out/bin/sigma .work/manual-1382/I1.fs
```

PowerShellではsigma.exe、Linuxではpython3を使う。手動用の通常実行体は
 task-trace、task-acceptanceとも無効にする。結果サイズ・件数の出力とメインの巡回・供給が
続くことを確認し、qで終了する。qはジョブ間（I1は補充の巡回間）で読む。
シェルへ戻り、所有資源が解放されたことを確認する。このループから60Hzの入力応答を
保証したと判断しない。G1の開放/壁/蛇行の頂点数は511、0、32896で、蛇行の終点は65280。
G2は256四方の地雷と隣接数、T1は1048576件の一致と最大1000件の保存を返す。
I1は64KiBの固定パターンを使い、checksumは8355840。実行1件＋待ち4件の補充を試みる。
自動probeはqueue深さを記録するが、完了出力だけで常時4件が待っていたとは判断しない。

入力注入の確認には `.work/manual-1382/response.fs` を使う。INPUT-READYの後で
b、qを入力し、INPUT-APPLIEDと端末上の変化を確認する。自動の書込み→marker時間は
通信を含む状態反映時間の上界であり、物理キー→画面・実際の提示は手動確認で扱う。
既存の実ウィンドウ/paint確認も行い、画面・音・複数資源の同時所有を確認できなければ
未確認と記録する。この端末の題材だけではネイティブ画面・音の合格証拠にならない。

Claudeの測定前に、PowerShellのGet-FileHash、Linuxのsha256sumで計画の実際のSHA-256を調べ、
実装報告書に固定した文字列と比較する。不一致なら停止する。--plan-sha256には報告書の
固定文字列を渡し、直前に計算した実際のハッシュを期待値として渡さない。計画の-text属性も確認する。runnerは計画の同一コピー、題材ハッシュ、生ログ、JSONを保存する。
コマンドは実装報告書を参照する。--mode smokeは時間の評価を行わない。位相の取り逃しと
OS採取の欠測は未確認として残し、推定した成功データで補わない。各OSのClaudeが1397〜1399でエラーと採取コマンドを記録して再採取する。

## macOSでの実行（1383）

[macOS専用計画](TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md) と
[1383報告書のコマンド](TASK_CONTROL_IMPL_1383.md) に従う。Claudeは
~/source/zig/ForthSigmaでzsh -lc、/opt/homebrew/binのPython、bin/sigmaを使い、
native arm64で実行する。メモリsmoke前に実機SDKのABIを照合する。まずTTYなしの
pipe smokeを行い、上記の前景端末の手動確認は別に行う。該当する各内訳をAC-27の
macOSの証拠として記録する。native paint・音・複合fixtureの不足は未確認とする。1394〜1396で題材を整え、1399でmacOSのClaudeが実行し、利用者が画面と音を確認する。
所有process/threadはpsで確認し、q・Ctrl+C後の端末復帰を観察する。上記の縮小回数を
1383にも使うかは、本測定前に別途利用者へ確認する。

## 取消し位相の改訂（2026-11-25、決定B）

レモンは、3 OSとも生成段階を狙った取消しの約7割が対象を取り逃し、nativeのFILL・SEARCH・ROLLでは最初の3回とも取り逃して打ち切った結果を受け、「B: 段階を確実に狙える測り方に変えて、測り直す」を採用した。回数は変更しない。Windows・Linux・macOSそれぞれ生成25段階、native 5種×3位相、待ち中の計41ケースを各100試行（4,100試行/OS）で新runへ採取する。旧runの有効値・欠測・超過は保持し、新方式と混ぜない。既存の他群の追加規則も消さない。

`-Dtask-acceptance=true`だけで、workerは対象段階を固定領域のatomic `hold_stage`へrelease-storeし、取消しtokenをacquire-loadして待つ。ホストのTASK-STATEによる巡回が到達を確認すると、Forthスタック上の同じtask idを使って公開語TASK-CANCELのハンドラーを呼び出す。取消し経路を別実装しない。requestedはそのTASK-CANCEL入口、stoppedはrunner帰還、reclaimedは従来どおり物理handback・所有資源とslot回収後。hold待機はrequestedより前に置かれるので要求→停止/回収へ加算しない。到達からtokenまでのholdは実時計で最大5秒（OSによる実行待ちを除く）、時計異常も解除して欠測にする。ホストが要求しない場合は時間切れで再開し、BYEのshutdown取消しtokenでも解除する。段階通過時に繰り返しholdしない。

生成各段階およびnative before/afterは到達した位置でholdする。native_runningは**実処理中の要求ではなく、事前確認後の入口でholdし、要求後にnative全体を実行する保守的な代替**を採用する。理由は、短い非分割nativeの内部に停止点を追加せず、外側から要求を確実に重ねることはできず、旧方式では取り逃しが残るため。入口は既存checkpointの後、次のcheckpointはnative直後にあり、holdはtoken確認後にエラーを返さず通常処理へ戻る。最大量のnative全体が要求→停止に含まれるため、途中で要求する場合の残仕事量を上から覆う検証になる。ただしOSのスケジューリングを含む全入力・全実行の最悪遅延を証明するものではない。method=`guarded-native-entry-full-call`と記録し、実際のduringを観測したと表現しない。

最大量の題材はFILL 65,536 bytes、MOVE 32,768読＋32,768書、COMPARE各32,768（同値の領域）、SEARCHは65,535 bytesのaと末尾に置く1 byteのb（不一致で全文走査、領域合計65,536、仕事量65,535）、ROLLは8,192 cells=65,536 bytes。SEARCHの旧256×256は最初の候補で一致するため全文走査を検証できず変更した。ROLLの旧4,000 cellsは64KiB未満なので、native-rollプロセスだけ`--data-stack-size 16384`を付け、8,191 ROLLを実行する。他の題材の容量は従来どおり。回数は変えず、題材・構成の差はmanifestとcommandに保存する。D07の64KiB/回以下と要求→停止10msをこの全量実行で照合する。

phase_okはhold_stage、要求直前に保存したrequest_stage、指定段階の3つが一致し、hold_timeout=falseの場合だけtrue。待ち中はqueued=trueと未実行（request_stage=api_entryの初期値）を確認する。native境界の時刻は残すが、同時刻による区間推定から位相を決めない。smokeでも全位相のphase_okを保存し、端点は0、速度統計は空のままにする。holdの時間切れ・時計異常・位相不一致・task行欠落は理由付き欠測とし、速度標本に使わない。最初の3回での打切りと250msの観測窓は廃止する。全100試行を記録し、成功数までの補充はしない。nativeの出力観測guardは6秒、プロセスの異常停止guardは120秒で、いずれも速度標本ではない。

通常ビルドではenabled=falseのcomptime分岐、空のStorage、voidのtoken付帯フィールドによりholdを除去する。通常経路の変更有無は同条件のReleaseFast/debug=false/task-trace=false/task-acceptance=falseで変更前後の.textを比較して確認する。検証では取消し成功、要求なしの5秒時間切れ、要求なしのBYE終了を短い動作確認として実施する。本測定はClaudeが担当する。

## 擬似端末による自動操作（決定B、2026-11-25）

`tests/scripts/manual-acceptance-tty.py` は、WindowsではConPTY、Linux/macOSでは
POSIX ptyの監督プロセスからsigmaを直接起動し、AC-02/05/18/20/24/25を実行する。
外部Pythonパッケージは不要で、Python 3.9以上に対応する。macOSの
`/usr/bin/python3` 3.9.6も使用できる。通常ビルドを準備してから、リポジトリのルートで実行する。
SSH側のTTY割り当ては不要であり、接続先で道具自身がptyを作る。
LinuxとmacOSはClaudeがそれぞれの機械へSSH接続して実行し、Windowsの結果を転用しない。

Windows PowerShell:

```powershell
python tests/scripts/manual-acceptance-tty.py --self-test
python tests/scripts/manual-acceptance-tty.py --sigma zig-out/bin/sigma.exe
```

Linux（`ssh -t` を使わず `ssh HOST` で接続した後に実行）:

```sh
python3 tests/scripts/manual-acceptance-tty.py --sigma zig-out/bin/sigma
```

macOS（ログインシェルからHomebrew Pythonを使用。作業場所は実際の配置に合わせる）:

```sh
zsh -lc 'cd ~/source/zig/ForthSigma && /opt/homebrew/bin/python3 tests/scripts/manual-acceptance-tty.py --sigma bin/sigma'
# システムのPythonも使用可能:
/usr/bin/python3 tests/scripts/manual-acceptance-tty.py --sigma bin/sigma
```

既定の保存先は `.work/acceptance/manual-<os>/<UTC時刻>/`。
セッションごとに出力の元バイト列、読める出力、時刻付きの送信キーと受信バイト列、
プロセスの記録、終了コード、端末復元の記録を保存する。POSIXでは親が保持したslaveの
`tcgetattr` と `stty -a` をsigmaの前後で比較する。WindowsではConPTY内の補助プログラムで
コンソールモードを取得し、前後の一致を確認する。
終了後に同じ端末で新しいsigmaを起動し、入力が通ることも確認する。
`results.json` には実行体のSHA-256、ソースのコミット、作業ツリーの状態も保存する。
`--output` で新規の保存先を指定でき、既存の記録は上書きしない。
`--timeout` と `--paint-timeout` は異常検出用の期限であり、時間の合否には使わない。

`--native-paint` 指定時は実画面の補助試験 `FORTHZ_PAINT_SMOKE=1 zig build runtime-test --summary all`
も実行し、DISPLAYを引き継いで全ログを保存する。指定がなければpaint/closeは理由付きの未確認とする。
`public paint real native window wait (opt in)` の明示的なOKだけを補助項目の合格とし、
skipまたは名前付きの結果がない場合は未確認とし、各OSのClaudeが実バックエンドで再実行する（1394、1397〜1399）。ログだけで画面の目視確認とはしない。

AC全体の状態と各小項目の結果を併せて読むこと。すべての結果に擬似端末の証拠であると明記する。
ネイティブ画面・複合供給元・音・混在hostなどの不足fixtureは未確認のまま残すため、
端末の小項目が成功してもAC全体の合格にはならない。
専用ワーカーの実行中の印を待ってからq/Ctrl+Cを送り、checksumには64 MiBファイルを使う。
最大負荷6題材とresponse.fsも端末で確認する。各題材の範囲と不足分の確認方法は各ACに記す。
道具の終了コード0は失敗した小項目がないことを示し、未確認を含み得る。1は小項目の失敗を示す。
`--self-test` はPython 3.9構文、共通の期待判定、所有する子・孫の回収、外部ダミーの生存を検査する。WindowsではJob登録失敗も注入し、シェルが再開されないことを確認する。実行したOS上で実プロセスを使う試験であり、WindowsでPOSIX実装を
実行したことにはならない。時間・容量の受入れ判定は行わない。

`--native-paint` 指定時にpaintの名前付き結果を得るため、道具は続けて `zig build runtime-check --summary all` で
同じ試験実行体を配置し、`zig-out/runtime-tests/<arch>-<os>/test`（Windowsは `test.exe`）を
ビルド用プロトコルなしで実行する。通常のビルド用プロトコルでは合格数とskip数しか
出ない場合があるためであり、両コマンドと出力を `native-paint.log` に保存する。

## POSIX起動待ち・端末復元・欠測の確認方法

POSIXの道具は対話シェルを使用しない。専用の監督プロセスが`setsid`でセッションを作り、ptyを制御端末として、同じプロセスグループにsigmaを直接起動する。監督プロセスは後始末まで生存させ、`waitpid`で回収しない。sigmaの終了後、短い補助プロセスで同じptyのechoと`stty -a`を確認し、新しいsigmaで入力も確認する。`stty`の終了コード0とspeed行の取得を必須とし、生出力を保存する。既知の`sh: child setpgid ... Operation not permitted`通知だけを位置に関係なく除去する。後述のPENDINだけを除き、他の設定行と別採取の`tcgetattr`は復元判定に残す。

Linuxでは補助プロセスやsigmaの起動前に、監督で`prctl(PR_SET_CHILD_SUBREAPER, 1)`（36）を設定し、起動時に監督の応答を確認する。sigma終了後、引き取った終了済みの子をwaitし、子孫一覧が監督自身だけであることを必須とする。元のセッション・グループを離れていても、子孫が残れば自然回収の失敗とする。後始末では監督自身が直接の子を列挙し、`waitid(P_PID, ..., WEXITED | WNOHANG | WNOWAIT)`で確認してからSIGKILLを送り、waitで回収する。新たに引き取った子孫も繰り返し処理する。確認・送信・waitは同一スレッドで行い、確認から送信まで直接の子のPIDを解放しない。孫のPID一覧を信号送信の根拠にしない。最後に監督自身だけであることを確認し、強制回収を自然回収成功にはしない。直接の子は監督の`/proc/self/task/<pid>/children`でも取得し、空であることを確認する。これにより、全体のppid一覧を採取中に親が変わる競合だけで回収成功としない。問い合わせ失敗時も、親は未回収の監督が保持するグループを終了させてから監督をwaitする。利用可能ならpidfdも保持する。子孫が特権や別のsubreaperで意図的に監督を回避しないことが前提であり、敵対的なプロセスの隔離機構ではない。

macOSにはsubreaperがない。専用スレッドが`/usr/lib/libproc.dylib`の`proc_listchildpids`を監督から再帰的に呼び、要求間隔20msで子孫を採取する。実際の開始・終了時刻とPID一覧を`child-polling.json`に保存し、実間隔には採取時間と実行待ちが加わる。返り値はバイト数ではなくPID数であり、バッファが満杯なら拡大して再取得する。エラーは未確認とする。採取PIDには信号を送らず、後始末は監督が保持するグループだけを対象とする。採取間のfork・終了・親の付け替え、離脱した子孫、PID再利用により寿命全体の所有・回収は証明できず、未確認を維持する。ClaudeがMacでsigma起動前から終了後までnativeのfork/exitを追跡する（1399）。許可されたInstruments/System TraceまたはDTraceを使い、接続エラーやイベント欠落を保存する。特権が必要なら利用者へ協力を求め、追跡不可・不完全の場合は未確認を維持する。離脱した生存プロセスは利用者が調査し、推定PIDで回収しない。

別の`reproduce-tty-shell-ready.py`は従来の対話シェル起動問題を調べる補助道具として残す。現在の筋書きの起動方式ではない。

WindowsではConPTY内でPython補助プログラムを起動し、その入力・出力のコンソールハンドルでGetConsoleModeを実行する。sigmaの前後で取得に成功し、値が一致することを確認する。親のパイプハンドルからは取得しない。実カーソルと画面は1394の題材で、各OSのClaudeが記録して利用者が観察する（1397〜1399）。

各所のネイティブ画面・音・複合題材の不足は1394〜1396で題材を整え、1397〜1399で各OSのClaudeが実行し、利用者が画面・音を観察する。macOSの不足も1399で確認する。OS採取の欠測やプロセス・スレッド採取失敗は、各OSのClaudeが1397〜1399で該当コマンドとエラーを残し、利用可能なOSの道具で再採取する。欠測から回収成功を推定しない。単一VM実行時間は1390〜1393で扱う。ここでの番号は登録済みの後続タスクの参照であり、この続きではtqueを変更しない。


## プロセスの所有と採取失敗

Windowsでは`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`付きの専用Job Objectを作り、breakawayを許可しない。`PROC_THREAD_ATTRIBUTE_JOB_LIST`で`CreateProcessW(CREATE_SUSPENDED)`時にシェルを原子的に登録する。続く`AssignProcessToJobObject`も成功してから`ResumeThread`する。起動時のJob指定が未対応、または登録失敗なら起動を中止する。後始末はこのJobの終了・ハンドルのクローズだけで行い、PIDを開いて終了させない。現在の所有はJobObjectBasicProcessIdListで取得するので、起動待ち後に作られた子も対象になる。自然終了後に子が残れば失敗であり、強制回収を回収成功とは扱わない。実行名の許可一覧は、名前や親PIDではなくJobへの所属で所有を保証するため削除した。

`src/host_process_native.c`は子を停止状態で起動し、内側のJobと`CREATE_NEW_PROCESS_GROUP`を使う。`CREATE_BREAKAWAY_FROM_JOB`は指定しない。内側のJobはbreakawayを許可するが、道具の外側のJobは許可しないため、子も外側のJobの制約を受ける。プロセス・スレッド一覧は観測用の情報であり、終了対象の決定には使わない。

採取失敗・欠測は`processes.json`と`results.json`へ記録し、該当小項目を未確認にする。Linuxの`/proc`採取時のENOENTは、別の存在確認でESRCHを確認できた場合だけ終了による競合として扱う。消滅を確認できなければ欠測を維持する。失敗した採取処理を実OSで再実行し、エラーと終了コードを保存する（1397〜1399）。AC-20でchecksumがq送信または継続的な重なりの確認より先に終了した場合は、各OSで終了操作まで継続する題材を用意し、両ptyの進行と実行中のq送信を再確認する（1395、1397〜1399）。同一プロセス内の公平性とは別の確認である。

## PENDINと残留入力（2026-11-25）

復元判定ではlflagの各OSの`termios.PENDIN`だけを除外し、元の前後値を保存して他の項目は比較する。`stty -a`は独立した`pendin`/`-pendin`トークンだけを置換する。Appleの[tty実装](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/tty.c)には、カノニカル切替え・入力再処理に伴うPENDIN操作がある。Linuxの[termios資料](https://github.com/mkerrisk/man-pages/blob/master/man3/termios.3)ではPENDINは未対応であり、macOSのビットを流用せずLinux自身の定数を使う。この除外だけで入力の消費を確認したことにはしない。

監督が終了を検知した直後（巡回20ms、実際には実行待ちが加わる）、終了マーカーや補助コマンドより前に、termiosとslaveのFIONREADを保存する。続いてflushせずICANON/ECHOを一時的に外し、FIONREADを再取得して残留バイトをノンブロッキングで読み、属性を復元する。可能な範囲で未完のカノニカル入力も調べる。観測自体が入力を消費し一時的にモードを変えるため、その後の入力確認は診断の介入後となる。復元比較には介入前の属性を使う。採取失敗は未確認とする。

各recoveryと場面の`residual_input_observations`に、ソース、送信キー、通常時と非カノニカル時の入力数、残留hex/text、時刻を記録し、eventsにも残す。残留は場面名と表示するが、それだけで失敗にしない。q・b・n・Ctrl+Cなどの送信と照合する。端末が信号として処理したり入力を破棄することもあるため、空でもsigmaが読んだ証拠にはならない。ClaudeがLinux/MacでEKEY・入力マーカーとnativeのread追跡を照合し、読み手や残ったキーを確認する（1397/1399）。PENDINだけで原因を断定しない。

ソース上の補助根拠として、task-path/search/checksumと対応worker、task-map-worker、task-console、check-task-console、生成するrunning・受入れ題材は、worker・端末・ファイル操作を使い、SYSTEMやOPEN-PIPEを呼んでいない。例のinclude先は上記worker・共通ファイルである。意図した題材が子を生成しないことの補助根拠であり、runtime/native実装での子生成の不在を証明せず、macOSの寿命追跡も代替しない。各runで実際のソースを再確認する。道具は`source-evidence.json`に題材と関連ソースのSHA-256を保存する。

ClaudeがLinuxとMacで自己試験と全筋書きを再実行し、試験前に外で起動したプロセスが終了後も同じPIDで生存することを確認する。Linuxの自己試験ではsetsid/setpgidで離れた子孫も作り、後始末後の子孫一覧が監督自身だけであることを必須とする。Windowsでも共通自己試験としてPENDINだけの差・他のフラグ・子孫のたどり方・直接の子でない場合の信号送信拒否を確認するが、POSIX APIの実行確認にはしない。旧runを保持して新規の保存先を使う。欠測には上記の確認方法を残す。既存タスク番号の参照は、この続きでのtque変更を許可するものではない。


## 1394 ネイティブ画面と音を残したBYE

WindowsではPowerShell、macOS/Linuxでは表示可能なローカルセッションで実行する。LinuxはX11を有効にしたビルドを使う。窓に一時的にフォーカスが移る。短い確認では時刻を測らない（SIGMA_ACCEPTANCE_SMOKE=1）。

目視・聴取で題材を手で操作するときは、計測なしの通常ビルド（`zig build`）を使う。`-Dtask-acceptance=true` は管理の1巡ごとに `ACCEPTANCE {"metric":"management_turn_ns",...}` を出すため、案内が流れて読めなくなる。ビルド設定は変更せず、実行体を使い分ける。

Windows（PowerShell、Windows Terminal）:

```powershell
zig build
./zig-out/bin/sigma.exe tests/task/task-native-path.fs
./zig-out/bin/sigma.exe tests/task/task-native-search.fs
./zig-out/bin/sigma.exe tests/task/task-native-bye.fs
```

Linux（X11を有効にしたビルド）・macOS（表示可能なローカル端末）:

```sh
zig build
./zig-out/bin/sigma tests/task/task-native-path.fs
./zig-out/bin/sigma tests/task/task-native-search.fs
./zig-out/bin/sigma tests/task/task-native-bye.fs
```

時刻の記録は計測用ビルドを `manual-acceptance-tty.py` で起動して行う。以下は時刻を取らない既定の短い確認。本測定は時間測定の確認後、以下のコマンド中の設定をPowerShellでは `$env:SIGMA_ACCEPTANCE_SMOKE="0"`、Linux/macOSでは `export SIGMA_ACCEPTANCE_SMOKE=0` に置き換える。Linux/macOSは実行体末尾の `.exe` を外す。手作業の目視・聴取は上の通常ビルドで別に記録する。

Windows (PowerShell):

```powershell
$env:SIGMA_ACCEPTANCE_SMOKE="1"
zig build -Dtask-acceptance=true --prefix .work/1405/acceptance
python tests/scripts/manual-acceptance-tty.py --native-paint --cases native --sigma .work/1405/acceptance/bin/sigma.exe --output .work/1405/load4
python tests/scripts/manual-acceptance-tty.py --native-paint --cases native --sigma .work/1405/acceptance/bin/sigma.exe --native-baseline --native-baseline-schedule .work/1405/load4/results.json --output .work/1405/baseline4
```

Linux (X11) / macOS:

```sh
export SIGMA_ACCEPTANCE_SMOKE=1
zig build -Dtask-acceptance=true --prefix .work/1405/acceptance
python3 tests/scripts/manual-acceptance-tty.py --native-paint --cases native --sigma .work/1405/acceptance/bin/sigma --output .work/1405/load4
python3 tests/scripts/manual-acceptance-tty.py --native-paint --cases native --sigma .work/1405/acceptance/bin/sigma --native-baseline --native-baseline-schedule .work/1405/load4/results.json --output .work/1405/baseline4
```

macOS/Linuxの実行体には.exeを付けない。直接操作する場合は通常ビルドの実行体でtests/task/task-native-path.fs、task-native-search.fs、task-native-bye.fsを実行する。G1はn、T1はa/bで要求世代が進み、fはworker失敗、qは終了。窓内のGeneration（採用結果）とRequested（現在要求）を端末のNATIVE-DRAW行と照合する。連続入力で古い世代に戻らず、fの後も以前の結果が残ることを目視する。

BYE題材は440Hzの持続音と窓を保ちworkerがRUNNINGの間にqでBYEする。音が聞こえたか、終了時に止まったか、窓が閉じたかを人が記録する。終了コードと端末復旧・process/threadの回収は保存された証拠と照合する。画面内容・聴取・macOSの子孫寿命が未観測なら未確認のまま、Claudeが各実機で確認する。

本測定は利用者が時間の測定を確認してからClaudeが行う。回数は計画v7/macOS v5を維持する。計測用ビルドのPAINTTRACEを保存し、runnerのpaint取込みで同一時計の端点を集計する。D07の画面の終点はbackendの描画完了。パネルの発光は対象外。端末writer完了と端末エミュレーターの画面反映も区別する。詳しい端点・60Hz期限・基準比較・欠測の扱いは計画の1394節を参照。

負荷ありを先に実行し、世代1の描画後にn/b、世代2の描画後にf、`NATIVE-FAILED retained=2` に続く世代2の描画後にn/aを送る。その後は世代4・5・6の描画を待って次の要求を送り、世代7が上限前に描画されなければ失敗とする。キーの並びはG1がn/f/n/n/n/n、T1がb/f/a/b/a/b。描画ループはINKEY/TC-KEYを非同期に読み、道具のキーを待たない。待機用キーや終了キーは送らない。

両実行は `NV-FRAME-LIMIT` で同じ固定上限（既定1200フレーム、約20秒）まで描画して終了する。変更する場合は両コマンドに同じ `--native-frame-limit N` を付ける。直接操作時の既定値0は従来どおり無制限。`--native-baseline` は初回以外は世代（TC-GEN）を進めずタスク投入を止め、キー受信と入力端点の記録を維持する。`--native-baseline-schedule` で渡した負荷ありのresults.jsonのキーと送信フレームを再生する。結果ファイルを渡さなければ、比較できない理由を表示して停止する。予定フレーム以上の最初の観測で送信する。遅れは2フレームまで許容し、超えたら失敗とする。再実行時は新しい出力ディレクトリを指定する。

`input_schedule` は送信直前に最後に観測したNATIVE-DRAWのframeとキー、`received_inputs` はNATIVE-INPUTの世代・受信フレーム・キーを記録する。受信は送信フレームより遅れる場合がある。`frame_count`、`input_count`（PAINTTRACEのinput端点数）、`input_sequence`、キーの並びで一致を判定する。`input_schedule` の `planned_frame` と `frame_delta` は基準の予定フレームと実送信フレームとの差を記録し、比較時に報告する。paint取込みのフレーム数・入力数の一致検査は維持する。数の一致だけでは描画負荷の一致を保証しない。不一致、基準の期限超過、描画条件の未確認があれば期限超過比較は未確認のままとする。
