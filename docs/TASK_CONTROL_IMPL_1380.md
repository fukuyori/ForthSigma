# タスク制御06-D：利用例と結合試験（1380）

作成日：2026-11-24。作成者：ロク。対象は `D:/tmp/forthz-1380`、
開始時のHEADは `29f3d03`（detached HEAD）である。開始時の作業ツリーは空であった。
公開APIの決定、利用条件、構成計画、1379の実装を前提とする。

## 1. 作成物と実装範囲

利用者向けの主文書は英語の[利用例](../examples/TASK_EXAMPLES.md)であり、
[日本語版](../examples/TASK_EXAMPLES.ja.md)も作成した。docsの英日READMEから案内する。
既存のboing・calculator・trigの例に合わせ、冒頭に用途・必要なビルド条件・起動方法・操作を記す。
新しいForth例の先頭にもライセンス行は置かない。ライセンスの案内は英日利用文書に記す。
第三者のコード・ライブラリは追加していない。

| ファイル | 内容 |
|---|---|
| `examples/task-path-worker.fs`、`task-path.fs` | G1の幅優先探索と端末UI。64〜256四方のバイト盤面、4近傍、障害物、到達不能、始点＝終点。例の盤面は64四方である |
| `examples/task-search-worker.fs`、`task-search.fs` | T1の固定バイト列検索。重複一致の総件数、最大1,000件の位置、切詰め。例の本文は1 MiB、入力する検索語は1バイトである |
| `examples/task-checksum-worker.fs`、`task-checksum.fs` | I1のファイル読取りと塊番号付きバイト和。1塊最大64 KiB、modulo 2^32。ファイル操作はメイン専用である |
| `examples/task-console.fs` | 公開語による投入、期限0の照会、世代照合、状態表示、ID解放。メインの入力と端末描画を続ける |
| `tests/scripts/check-task-examples.fs` | 公開語だけによるアルゴリズム・結果・世代照合試験である |
| `tests/scripts/check-task-console.fs` | 終わらない計算中の実プロセス入力、端末表示、64 KiBファイル読書き・全バイト比較・削除、置換え・取消し・RELEASE・BYEである |
| `tests/scripts/verify-task-examples.py` | Forth試験、3例、連続置換え、複数塊の独立したチェックサム照合を駆動し、ログを保存する |
| `src/tests/task_examples_test.zig`、`src/runtime_test.zig` | 公開語による20回の取消し・解放、未完了RELEASE、BYE終了後の管理資源ゼロを検査する |
| `docs/word-reference/translation-sources.json` | 試験登録・追加だけで公開語の意味・英日説明が変わらないことを確認し、生成元記録を更新した |

workerは `( input-addr input-u -- result-addr result-u )` に従い、BEGIN系で反復する。
動的実行、CATCH、PAD、DO系、ファイル、出力をworkerに含めない。
タスク操作はすべて公開TASK語であり、例から内部APIを呼ばない。
G1はFIFOと親頂点を保持し、訪問済み頂点を再投入しない。
経路は終点から始点の順の32 bit little-endian頂点IDであり、最大結果は262,160 bytesである。
nativeの1回64 KiB上限を超えるworkerの一括初期化は行わない。
入力形式と呼出し側が守る条件は英日文書に記す。

G1/T1は同一profile・stream 7で要求を置き換える。新規投入成功後に旧公開IDを解放する。
入力・要求に世代を含め、投入時の世代と結果内の世代の両方が現在世代に一致する場合だけ
表示へ適用する。旧要求の投入失敗時も、新しい画面へ古い結果を適用しない。
G1の端末表示は経路を`*`、始点を`S`、終点を`G`で示す。
T1は件数・格納数・切詰め・先頭位置、I1は塊番号とチェックサムを表示する。
G1/T1の失敗・取消しは従前の表示を保持して状態を示す。I1ではエラーとして停止する。

I1は未完了1件に制限して順序を保つ。待ち4件の満杯や持続供給率の達成を示す例ではない。
メインのファイル操作は有限の同期呼出しであり、低速・停止したデバイスでの
非同期I/Oや、その呼出し中の入力応答を保証するものではない。
10 MSの休止は照会の反復を抑えるものであり、60 Hzの達成を意味しない。
状態表示は要求世代・適用済み世代・終了状態が変わったときだけ出力する。
今回、タスク制御の製品実装は変更していない。

## 2. 自動検査の根拠

Forth試験は実TASK-SUBMIT経由でworkerを実行する。G1は64四方の開放盤面、
全幅の壁による到達不能、端に回り込む壁、256四方、始点＝終点を検査する。
既知の最短頂点数127・190・511・1を照合し、返された全頂点について、
盤面内、通行可能、前後のManhattan距離1、両端の一致を検査する。
最大盤面を試験しているが、最大長65,536頂点の経路fixtureは未実施である。
T1は重複一致の位置、0件、2,000件中1,000件への切詰めを検査する。
I1は64 KiBと空の塊を検査する。世代の真偽だけでなく、実際に成功した旧結果を
TC-POLLへ渡し、適用済み世代を変更せずIDを解放することも検査する。

Pythonは実プロセスからの出力を待ってからキーを送る。終わらないworkerがRUNNINGである
ことをForthで確認した後、入力→ファイル書込み→読戻し→全量比較→端末出力を行う。
旧要求の取消し終端、新要求のRUNNING、明示取消し、未完了RELEASE直後のID無効化、
新たなRUNNING要求とSnapshotを残したBYEを通す。
G1/T1の連続置換えでは最後の世代の結果と表示世代の非逆行を検査する。
検索UIの件数と切詰めも照合する。I1は2個の64 KiB塊と7 bytesの端数を持つfixtureで、
Pythonの独立したバイト和と、塊番号・結果順を照合する。

Zigの追加試験は台帳16件を超える20回の投入・取消し・解放を行い、
未完了RELEASEと、ID・Snapshotを残したBYE相当のホスト終了を追加する。
終了後の台帳件数、タスク/Snapshotスロット、転送予約、task allocator使用量が
すべて0であることを検査する。OSの予約・commit・ハンドル数の検査ではない。

## 3. Windowsでの実行結果

PowerShell、Zig 0.17.1で実行した。`ZIG_GLOBAL_CACHE_DIR`をworktree内の
`.zig-global-cache`へ設定した。ベンチマーク、速度・時間・資源量の測定は行っていない。
試験のtimeoutはハング検出用であり、受け入れ期限の判定には使わない。

| コマンド | 結果 |
|---|---|
| `zig build -j2` | 成功。Windowsの実行体を作成した |
| `zig build test -j2` | 成功 |
| `zig build test -Ddebug=false -j2` | 成功 |
| `zig build runtime-test -j2` | 成功。追加した1380の資源回収試験を含む |
| `python tests/scripts/verify-task-examples.py --sigma zig-out/bin/sigma.exe` | 成功。公開語の計算・世代照合、実プロセス結合、G1通常/連続置換え、T1通常/連続置換え、I1通常/複数塊の8群である |
| `python scripts/check-docs.py` | 成功、findings: 0。初回は試験ソース追加による生成元記録の不一致を検出し、記録更新後に成功した |
| `zig fmt --check src/runtime_test.zig src/tests/task_examples_test.zig` | 成功。初回のruntime登録位置の整形を修正後に確認した |
| `git diff --check` | 成功 |

Forth試験と3例の実行をPythonから行ったWindowsのログは `.work/1380/` の
`algorithms.log`、`integration.log`、`path.log`、`path-replace.log`、`search.log`、
`search-replace.log`、`checksum.log`、`checksum-chunks.log`、`results.json`である。
このログは未追跡の作業領域に保持する。実端末・実画面の手動確認とは区別する。

## 4. 受け入れ項目との対応

受け入れ表自体の状態はすべて「未実施」のまま変更しない。
次の「自動確認」は各AC全体の合格を意味しない。手動手順は
[利用例の日本語版](../examples/TASK_EXAMPLES.ja.md)にも記す。

| AC | 自動で確かめた範囲 | 用意した手順 | 未実施・限界 |
|---|---|---|---|
| AC-02 | 実worker計算中の入力・端末出力・取消し・終了時の管理資源回収 | 前面端末でG1/T1を操作し、計算中の取消し・終了と表示継続を確認する | 実端末・実画面、停止/回収期限、OS資源の観測、Linux実行 |
| AC-05 | workerにhost操作を含めず、実workerとメインのファイル往復・端末出力を併用する | 計算中に入力し、出力先とファイル内容が混ざらないことを確認する | 実表示・音・共有状態の隔離全般の受け入れ。本試験だけで許可集合全体の監査を代替しない |
| AC-18 | 関連する確認として、期限0の公開照会によるイベントループ、入力と実タスクの共存 | 連続入力・処理中終了、実端末Ctrl+Cを行う。複合待機の実接続は下記の未実施項目である | 本追加試験はTASK-WAIT-MANYを使っていない。複合待機による実入力/I/O/期限/描画の同時接続、closeの実backend確認は未実施である |
| AC-20 | 計算が終わらない間もメインが入力・ファイル往復・端末出力を進める | I1を複数塊のファイルで動かし、処理中の操作と排出を確認する | 持続供給、満杯時の他stream排出、公平性・時間目標、低速I/O |
| AC-21/22 | 取消し・置換え・RELEASE・BYEとホスト終了後の台帳・参照・allocator回収 | 計算中終了を繰り返し、OS資源を観測する | OS全資源、停止未確認の保持、回収期限。既存reap試験の結果と混同しない |
| AC-25 | G1/T1の実要求置換え、最終世代の表示、旧成功結果の不適用、I/Oとの結合、I1の順序・和 | G1の経路表示、T1の件数/位置、処理中の入力・終了を実端末で確認する | 実端末・画面の応答、マップ生成G2、全最大負荷、Linux/macOS実行 |
| 利用条件の期限・応答 | 測定なし。機能試験のtimeoutから達成を判定しない | 下記5節の別途許可が必要な測定手順である | 全時間目標は未実施である |

## 5. 手動確認と期限測定の引継ぎ

実端末確認ではG1の`n`、T1の`a`/`b`を連続して入力し、結果待ち中も入力と状態変更時の表示が
続くこと、世代が逆行しないこと、計算中の`q`で終了できることを確認する。
G1の`*`が4近傍の経路であること、T1の`a`が1,048,576件、`b`が0件であることを照合する。
I1は複数塊で独立したバイト和と順序を照合する。行入力・EOF・Ctrl+Cは別ケースとし、
端末名、OS、実行体、ソース、入力、終了方法、表示とOS資源の根拠を記録する。
1380では実端末での操作、物理提示、OS資源の手動確認は未実施である。

期限を評価する場合は、実行前にレモンへ測定の許可を得る。
利用条件3・5・6・8節に従い、入力fixture、頻度、上限、対照、負荷、反復、順序、除外規則を
固定する。投入、結果公開、入力取得、状態反映、描画、取消し要求、停止、回収を別々に観測する。
G1/T1の入力→状態反映16.67 ms、TUI端末更新50 ms、要求→停止10 ms、回収100 ms等を
対応する区間ごとに評価し、中央値・p95・最大・超過件数・生データを残す。
60 Hzや入力→画面2周期の判定を単なる論理フレーム番号から行わない。
本作業ではこの測定手順を実行していない。

## 6. Linux担当Claude向けコマンド

Linuxでの実行は別の機械のClaude担当であり、こちらでは実行していない。
変更ファイル一式を適用したリポジトリ直下で、Zig 0.17.1を使って次を実行する。
キャッシュ、実行体、一時ファイル、ログはすべて当該作業ツリー内とする。

```sh
set -e
export ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache"
zig version
zig build test -j2
zig build test -Ddebug=false -j2
zig build runtime-test -j2
zig build -j2
python3 tests/scripts/verify-task-examples.py --sigma zig-out/bin/sigma
python3 scripts/check-docs.py
zig fmt --check src/runtime_test.zig src/tests/task_examples_test.zig
git diff --check
git status --short
```

この例は端末表示なのでX11・Tkは不要である。既定構成のビルド依存を用意できない場合は、
構成計画の該当行と照合して`-Dx11=false -Daudio=false`等を全コマンドへ一貫して指定し、
既定構成と区別して報告する。extensionとfilesは有効にする。
前面端末の手動確認は`zig-out/bin/sigma examples/task-path.fs`、
`zig-out/bin/sigma examples/task-search.fs`、`zig-out/bin/sigma examples/task-checksum.fs`で行う。
速度・時間測定の許可をこの引継ぎに含めない。Linuxの実行結果・端末・資源・未実施項目を
Windowsの記録へ混ぜず、別に報告する。

## 7. Gitと作業上の制約

コミット・タグ・ブランチ作成・push・tque変更は行っていない。
作業ツリー外への変更、外部データ取得、ベンチマーク、パッケージ作成は行っていない。
公開API仕様・利用条件・受け入れ表の状態は変更していない。
最終の `git status --short` と試験結果を利用者への日本語報告にも載せる。

## 8. レビュー指摘への対応（2026-11-24）

今回の修正開始時には1380の作成物が追跡済み変更・未追跡ファイルとして存在していた。
それらを引き継いで修正した。HEADは引き続き`29f3d03`である。

| 指摘 | 確認と対応 |
|---|---|
| 1 | BUSYの取消し後の無期限待機を確認した。Zig試験とconsole試験を30,000 msの有限待機へ変更し、TASK-CANCELLEDとTASK-WAIT-EXPIREDが立たないことを照合する。時間値はハング防止用であり、受け入れ期限ではない。指摘中のZigの26行目は待機ではなくBYEの回収対象を残す投入であったため、この投入は維持した |
| 2 | メインにCATCHがなく、THROW時に明示解放へ到達しない経路を確認した。各MAINが初期化・主ループ全体をCATCHで囲み、I1はファイルを閉じ、共通処理でタスクとSnapshotを解放してから再THROWする。TC-CLOSEは片方の解放がiorを返してももう片方を試み、最初のエラーを返す。主処理の例外がある場合はそれを優先する。CATCHはメイン専用でありworkerには追加していない |
| 3 | I1も失敗・取消し後に次の塊へ進む経路を確認した。I1の成功以外の終端は-4095をTHROWし、後始末後に処理を停止する |
| 4 | 毎巡回で改行する実装を確認した。要求世代・適用済み世代・終了状態が変わった場合だけ状態行を出す。盤面を流し続けない。実端末での視認確認は未実施である |
| 5 | EKEY?の後にKEYを呼ぶ実装と、EKEY>CHARが0〜255の文字だけを真とする実装を確認した。EKEYとEKEY>CHARで取得し、文字でない事象は捨てる。特殊キーで停止するという現象自体は未確認であり、実Windowsコンソールでの操作試験は未実施である |
| 6 | .work/を作らずファイルを作成する前提を確認した。試験先頭に、リポジトリ直下で実行し.work/を事前に用意すること、Python駆動では自動作成することを明記した |
| 7 | boing・calculator・trigの先頭にライセンス行がなく、ビルド条件を記すことを確認した。新しいForth例のライセンス行を除き、UI例にはビルド条件・コマンド・キー操作を追記した。本報告書1節の説明も更新した |

指摘を誤りとして退けた項目はない。指摘1の行番号と、指摘5の現象の確認範囲は上表のとおりである。
公開語の意味・登録・日本語説明は変更していない。試験の変更だけであることを確認した上で、
文書検査用の生成元ハッシュを更新した。

追加の公開Forth試験では、I1の実取消し終端をTC-POLLへ渡して例外になること、
例外を再送出してもタスクとSnapshotを明示解放すること、無効タスクIDの解放が失敗しても
Snapshotの解放を試みることを検査する。Pythonは引数省略時に当該OSのzig-out/bin/sigmaを使う。

初回のZig試験では、新しい検査値が次の反復へ残る試験コードの不備を検出した。
検査後に検査値2個をpopするよう修正した。初回のfmt検査の整形差分も修正した。
初回の文書検査は試験ソースのハッシュ差分を検出し、上記確認後に更新した。
Linuxでは6節の全コマンドを実行する。追加の例外試験もPythonから実行される。
ベンチマークと期限測定、Linux実行、実端末の手動確認は今回も未実施である。

### レビュー修正後の再試験結果

| コマンド | 結果 |
|---|---|
| `zig build test` | 成功 |
| `zig build test -Ddebug=false` | 成功 |
| `zig build runtime-test` | 成功 |
| `zig build` | 成功。結合試験用実行体を更新した |
| `python tests/scripts/verify-task-examples.py` | 成功。従来8群と例外経路4群、計12群である |
| `python scripts/check-docs.py` | 成功。findings: 0 |
| `zig fmt --check src/runtime_test.zig src/tests/task_examples_test.zig` | 成功 |
| `git diff --check` | 成功 |

追加ログは`.work/1380/checksum-read-error.log`、`checksum-submit-error.log`、
`path-wait-error.log`、`search-result-error.log`である。READ-FILE・WAIT・RESULTの
ケースは呼出し直後に例外を注入したものであり、実デバイス障害の再現ではない。
投入失敗は存在しないworker名を実際に投入する。各MAINの外側で例外を捕捉し、
タスク/Snapshotの公開ID保持変数と、I1のファイル所有フラグが0であることを検査した。

### 修正後のGit状態

`git status --short`の結果は次のとおりである。開始時から引き継いだ1380の作成物を含む。

```text
 M docs/README.ja.md
 M docs/README.md
 M docs/word-reference/translation-sources.json
 M src/runtime_test.zig
?? docs/TASK_CONTROL_IMPL_1380.md
?? examples/TASK_EXAMPLES.ja.md
?? examples/TASK_EXAMPLES.md
?? examples/task-checksum-worker.fs
?? examples/task-checksum.fs
?? examples/task-console.fs
?? examples/task-path-worker.fs
?? examples/task-path.fs
?? examples/task-search-worker.fs
?? examples/task-search.fs
?? src/tests/task_examples_test.zig
?? tests/scripts/check-task-console.fs
?? tests/scripts/check-task-examples.fs
?? tests/scripts/verify-task-examples.py
```

## LinuxでのG1連続置換え停止の調査（2026-11-24）

### 結論と確認範囲

原因は未特定であり、Linuxの現象を修正済みとは扱わない。今回追加した決定的な
同期点付き試験ではWindows上で停止を再現できなかった。本番コードの変更はない。
Linuxでの実行はClaudeに依頼する前提で、公開診断を採取する手順を追加した。
作業対象はメイン作業ツリー（HEAD `29f3d03` と既存の1380・1381の未コミット変更）である。
Gitの変更操作、tqueの変更、速度測定は行っていない。

報告された現象は、Linux x86_64・Zig 0.17.1でG1の表示後に`nnn`をまとめて送ると、
フレームはgeneration=4へ進むが最後の結果が出ず、`q`では正常終了する、というものだった。
これは利用者から提供されたLinuxでの観測であり、今回こちらでLinux実行した結果ではない。

### コードで確認したこと

- `Host.submit`はキューのViewから置換え候補を選び、`Queue.submitReplacing`は
  キューのゲート内で候補がまだ待ち中かを確認する。候補が既に取得されていれば新要求を追加する。
  新要求を受け入れた後、同じowner・kind・streamの既存Entryに取消しを要求する。
  新Entryはこの巡回の後に登録されるため、この巡回では新要求自身を取消さない。
- 待ち中の置換えと取消しによる取り出しは同じゲートで直列化される。
  `latchCancellation`は台帳の取消しフラグを立てる処理であり、単独では終端へ遷移させない。
- `Queue.work`は通知の回数を数えて要求を取得するのではなく、ゲート内の`count`を再確認する。
  待機も10msの有限期限付きである。完了の`ready`と`acquired`は永続するatomic値で、
  `Host.poll`は通知がなくてもそれらを照会する。
- POSIX Wakeは`pending`と非ブロッキングpipeで通知を併合する一方、Windowsはauto-reset eventを使う。
  両方とも世代番号を先に更新し、待機側は世代番号と期限を再確認する。
  POSIXはpipeをreadしてから`pending`をclearし、世代番号を再確認する。
  したがって「3回の通知が1回に併合された」という事実だけでは、今回の長時間停止を説明できない。
  OS待機から戻らない場合や、runner／cleanup自体が戻らない場合まで証明したものではない。
- 公開APIは旧IDの解放後も物理的な引渡しまでJobを保持する。
  例の`TC-SUBMIT`は新IDの受入れ成功後に旧IDを解放し、`TC-POLL`はtimeout=0で照会する。

POSIX固有の待機経路はWindowsの実行では検証できない。※推測です：Linux固有の待機、
workerの実行・cleanup、または別の競合順序が関係する可能性は残る。
この段階で通知処理を変更する根拠はないため、追加の推測修正はせず、以下の診断で停止位置を絞る。

### 追加した本番モジュールの試験

`src/tests/task_schedule_host_test.zig`に次の2試験を追加した。Host、Queue、Ledgerは
本番モジュールを直接使用し、runnerと時計／通知だけを試験用の同期点に差し替える。

1. `three rapid replacements survive coalesced wakes and cancelled runner handback`
   はgeneration=1のrunnerを止めたまま2・3・4を投入する。
   2と3が待ち中から取り出され、4だけが待ち中に残ることを確認する。
   ホストが最初の実行開始を既に観測した場合と未観測の場合の両方を実行する。
   各投入後の旧ID解放は例と同じ順序で、共通通知はすべて捨てる。
   同期点の解放後、4の台帳上の成功、旧要求の回収、結果の一度だけの適用、
   実行参照の解除と4件すべてのcleanupを検査する。
2. `three replacements when worker acquires the proposed waiting replacement`
   はgeneration=2を待ち中に置いた後、3の投入処理がViewを取得してからキューのゲートを取るまでの間に、
   1を返却させて2を取得させる。時計のコールバックを同期点にして、この順序を強制する。
   3は追加へ切り替わり、4が3を置換える。2の取得と3の未取得、4の待機位置、
   4が取消されていないこと、および解放後の成功・回収・結果適用を検査する。
   この試験はprivate wakeも通知を捨ててtimeoutを返すバックエンドに差し替える。
   POSIXのpipeの模倣ではなく、通知を受けなくても述語を再確認する経路の試験である。

両試験ともWindowsで成功した。これらの競合順序での停止は再現しなかった、という範囲の結果である。

### LinuxでClaudeが実行する診断

リポジトリ直下で、対象のZig 0.17.1と今回のソースから作った実行体を使う。
Linuxでのビルド・実行結果はまだ未確認である。

```sh
zig version
zig build
python3 tests/scripts/diagnose-task-path.py
python3 tests/scripts/diagnose-task-path.py --keep-old
python3 tests/scripts/verify-task-examples.py
```

診断ドライバーは`G1 diagnostic:`を受信してから`nnn`を一度に送る。
既定では20秒間公開診断を観察してから`dq`を送り、終了を確認する。
この待ち時間は診断用であり、性能や停止期限の合否を測るものではない。
必要なら`--observe-seconds 45`で観察期間を変更できる。通常の例と異なり盤面の出力は省くが、
同じworker、入力、profile、stream、10 MSの巡回とTC-POLLを使用する。
診断の追加自体が実行順序に影響する可能性があるため、元の`path-replace`の結果も併せて残す。

- 既定モードは、新要求の受入れ直後に旧IDを解放する。最新IDだけを照会する。
- `--keep-old`は旧IDを保持する比較用の別実行である。通常の解放順序の再現とは区別する。
  4世代の取消し・状態・診断を照会し、最後に旧IDを解放する。
  成功した最新IDはTC-POLLで解放した後、照会対象から外す。
- 出力は`.work/1380/diagnose-task-path-released.log`と
  `.work/1380/diagnose-task-path-retained.log`へ保存する。
  観測中に例外が起きた場合も、そこまでに受信した出力を保存する。

Forthだけで実行する場合は次を使い、バナーの後に`nnn`、停止中に`d`、最後に`q`を入力する。

```sh
zig-out/bin/sigma tests/scripts/diagnose-task-path.fs
```

`tests/scripts/diagnose-task-path.fs`は環境変数や非公開ログを使わず、TASK-STATEと
TASK-DIAGNOSTICのchannel=0（primary）・3（stop）を照会する。
各出力の`state-ior`、`state`、`cancel`、`result-bytes`、および各診断の`ior`と`code`を確認する。

| 観測 | 次に絞る対象 |
|---|---|
| 最新IDがstate=1（queued）のまま | workerの取得・旧要求の物理返却・台帳への反映。公開状態だけでは物理取得の有無を断定しない |
| 最新IDがstate=2（running）のまま | runnerまたはcleanupからの返却と完了の公開 |
| state=3（succeeded）、396 bytes、cancel=0 | 今回のgeneration=4の経路結果に期待する状態。これでも適用されなければTC-POLLと世代判定を確認 |
| state=4（failed）か5（cancelled） | primary診断と取消しフラグを確認。`-313`はキュー滞在期限超過 |
| stopのcode=-314 | そのIDに停止未確認の履歴がある。終端後も履歴が残るため、現在も実行中とは断定しない |
| 診断のior=-306 | その照会では診断がまだ取得可能でない。診断呼出しの失敗とタスクの失敗を区別する |
| 診断版でだけ成功する | 元の例の停止は解消したと扱わず、観測による順序の変化も調べる |

まずこのログと元の例の結果をClaudeから受け取り、停止している状態を確認してから
本番コードの原因箇所を絞る。公開診断だけで分からない物理取得やOS待機の状態は、
その結果に応じてLinux側でスレッドのスタック等を採取する必要がある。

### Windowsでの検証結果

Zig 0.17.1、PowerShellから実行した。
最初の`zig build runtime-test`は既定のグローバルキャッシュへのアクセスが拒否された。
以後は`ZIG_GLOBAL_CACHE_DIR`を作業ツリー内の`.work/zig-global-cache`に指定して実行した。

| 検査 | 結果 |
|---|---|
| `zig build test` | 成功（追加した2試験を含む最終ソースで再実行） |
| `zig build test -Ddebug=false` | 成功 |
| `zig build runtime-test` | 成功（追加した2試験を含む） |
| `zig build` | 成功。診断・結合試験で使う実行体を確認 |
| `python tests/scripts/verify-task-examples.py` | 12群成功 |
| `zig fmt --check src/tests/task_schedule_host_test.zig` | 成功。今回変更したZigファイルはこの1件 |
| `python -m py_compile tests/scripts/diagnose-task-path.py` | 成功 |
| 診断ドライバー（既定と`--keep-old`、各`--observe-seconds 1`） | 両方ともgeneration=4、vertices=95、396 bytes、cancel=0、state=3を確認し正常終了 |

未完了なのはLinuxでの診断採取、原因の確定、および必要な本番修正とそのLinuxでの確認である。

## 追記：G1の連続差替えとFULL後の最新要求保持（2026-11-24）

対象はメインの作業ツリー `D:/home/source/zig/forthz`、Zig 0.17.1。
LinuxでClaudeが取得したログでは、generation=2の受理後、generation=3の
`TASK-SUBMIT`が `TASK-E-FULL (-301)` を返し、診断スクリプトがTHROWで終了した。
今回はGit操作・tque変更・速度測定を行っていない。Linuxでの修正後の確認はClaudeが担当する。

### 公開投入と決定的な再現

Service.submitに残っていたstop_unconfirmedによるResourceFullの検査を除去した。
公開APIのpollで停止未確認となった後も、他の上限に空きがあれば投入を受け付ける。
台帳16件、待ち4件、公開Task枠、入力・結果・総予算の上限は維持する。

公開API試験はrunnerの物理帰還をatomic同期点で止め、偽時計を取消し時刻＋10 ms＋1 nsへ進める。
同じstreamの3回目の投入成功、旧公開ID解放後の実行参照・停止未確認の保持、最新要求の待ち状態を確認する。
さらにG1の待ち期限50 msを超えるまで旧実行を帰還させず、最新要求のfailedと
公開診断TASK-E-QUEUE-EXPIRED (-313)を確認する。同期点解除後の所有者終了で台帳と割当量が0になることも確認する。
実時間やOSの停止速度を合否条件にしない。

### 仕様との判断

1364の決定と1387の確認に従い、停止未確認中でも投入を受け付け、実行開始だけを拒否する。
TASK_CONTROL_USAGE_CONDITIONS.mdとTASK_CONTROL_STATE_MACHINE.mdの
「新しい実行を拒否する」は投入拒否を意味しない。10 ms超過を理由とするFULLは返さない。
旧実行の物理帰還まではworker枠を保持し、期限経過を停止完了とみなさない。
受理済み要求が待ち期限を超えた場合は、期限切れの診断を持つ失敗として確定する。

例は他の上限によるFULLでは最新要求を保留し、最新要求の失敗・取消し・期限切れでも
保留へ戻して再投入する。古い要求の結果は適用しない。
WindowsとLinuxの取消し速度の違いは未測定であり、原因として断定しない。

### 修正した箇所

- `examples/task-console.fs`：最新の入力・語名・世代を参照する `TC-PENDING` を追加。
  FULLでは旧ハンドルを維持して要求を保留し、`TC-POLL`ごとに1回だけ再投入を試す。
  新たな入力が来れば保留要求を最新の内容で上書きし、成功時だけハンドルと投入世代を更新する。
  古い結果の世代照合は維持する。FULL以外のエラーはTHROWして既存の終了処理へ渡す。
  最新要求が失敗・取消し・期限切れなら保留へ戻し、再投入する。
  閉じる際は保留を解除する。呼出し側は受理まで入力と語名の領域を保持する。
- `examples/task-checksum.fs`：共通の保留処理に対応し、保留中に次の塊で入力を上書きしない。
  FULLを即THROWせず、保留がある間はEOFで終了しない。
- `tests/scripts/diagnose-task-path.fs`：FULL時の世代・ior・公開状態・診断を出力して継続。
  最新要求を保留して次の巡で再投入し、keep-old時には実際に解放した投入世代のID記録を消す。
  FULL以外の投入エラーは元のiorで終了する。
- `src/tests/task_examples_test.zig`：上記の公開API・停止未確認・外部ID解放・待ち期限切れの試験。
- `tests/scripts/verify-task-examples.py`：G1の例と診断版にそれぞれFULLを2回注入し、
  停止せずgeneration=4・vertices=95へ到達する2群を追加。
  この注入は呼出し側の再試行検証であり、本番APIからFULLを出す試験とは別である。

### Windowsでの検証

Zig 0.17.1、PowerShell、作業ツリー内のZIG_GLOBAL_CACHE_DIRで実行した。

| 検査 | 結果 |
|---|---|
| `zig build test` | 成功。公開投入受理・待ち期限切れ・診断を含む |
| `zig build test -Ddebug=false` | 成功 |
| `zig build runtime-test` | 成功 |
| `zig build` | 成功。例の結合試験用実行体を更新 |
| `python tests/scripts/verify-task-examples.py` | 15群成功。FULL注入による再投入、最新要求の終端失敗後の再投入を含む |
| `python tests/scripts/verify-task-public-matrix.py --configs C08` | 成功 |
| `zig fmt --check src/host_task_api.zig src/tests/task_examples_test.zig` | 成功 |

公開API試験は実際の待ち期限切れと診断を確認する。例の追加結合試験は、待機結果に最新要求の終端失敗を1回注入し、同じ世代の結果へ到達することを確認する。両試験の役割を区別する。
既存のI1取消し試験も、古い要求の取消しでは再投入せず解放する期待へ更新した。
診断版は共通の再投入処理でも最新入力・語名を参照できるよう設定する。

実行結果は `.work/1380/stop-unconfirmed-validation.json`、例の結果は
`.work/1380/results.json` と各群のログに保存する。
Linuxでの確認は未実施であり、Claudeが担当する。Git操作・tque変更・速度測定は行っていない。
