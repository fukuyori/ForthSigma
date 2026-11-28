# 1057 統合受入れの題材と道具（1411）

[English](INTEGRATION_ACCEPTANCE_1057_TOOLS.md)

2026-11-26、ロク。対象は ForthSigma / Zig 0.17.1。契約は[計画](INTEGRATION_ACCEPTANCE_PLAN_1057.ja.md)の §2〜4・7・8・10・11 と末尾の利用者の決定。これは道具の説明であり、3 OS の統合受入れ完了記録ではない。構成・測定・復元は B、D1〜D5 は A を維持する。

## 1. Windows での起動

リポジトリのルートで PowerShell を使う。

```powershell
$env:ZIG_GLOBAL_CACHE_DIR="$PWD/.work/codex-cache/global"
$env:ZIG_LOCAL_CACHE_DIR="$PWD/.work/codex-cache/local"
$env:SIGMA_ACCEPTANCE_SMOKE='1'
python tests/scripts/integration-acceptance.py --smoke --configs M0 M1 M2 M4 M7 M9
```

構成ごとに `zig build -Doptimize=ReleaseFast -Dtask-acceptance=true --prefix <run>/<構成>/build` と除外オプションを使う。既存ビルドを使う場合は、例えば `--configs M0 --binary zig-out/bin/sigma.exe` を指定する。既存ビルドの構成・計測フラグは実施者が保証する。SHA-256 と指定した構成は記録するが、バイナリだけからビルドオプションを推定しない。

毎回 `.work/integration-acceptance/<日時>-<乱数>/` を作り、既存の証跡を上書きしない。`--output` で親ディレクトリを指定できる。窓が開く。通常の smoke は無音。`--frames` の既定は smoke で 240、functional で 1,200。native の描画あり構成では終了用フレーム枠とし、Tk・terminal・GRAPHICS 除外構成では枠×16,667 µs を終了期限に使う（`IA-BUDGET deadline reached`）。端末への画像出力の速さに終了を依存させない。この期限は応答の合否には使わない。機能検査を短く実行する場合は `--functional --frames 240` を指定できる。`--functional` は時間の合否を出さず通常の機能検査を実施する。全構成の本実行は Claude が行う。

## 2. 保存側と起動側

`tests/integration/` は定義と永続データの初期化だけを置く。`core.fs` は入口と段階的な取得・後始末、`extension.fs` はタスクと入力、`requests.fs` は既存 path/search の要求と描画定義、`audio.fs` は PCM、`graphics.fs` は描画、`pipe.fs` は子/pipe、`loop.fs` は複合待機・資源の比較・再保存前のリセットを定義する。`measurement.fs` は測定モード用の描画再生の準備である。

adapter は構成に合う定義を `definitions.fs` に連結する。worker は `task-path-worker.fs` / `task-search-worker.fs`、タスク操作は `task-console.fs`、描画ヘッダーは `task-native-common.fs` の定義を再利用する。実行を始める `task-native-path/search/bye.fs` の末尾は読み込まない。FILES 除外構成にも `INCLUDED` を持ち込まない。ホストのコマンド行によるソース読込みは FILES 語群とは独立している。

保存側は `definitions.fs` を読み込んだ後、別の `-e` 引数で `' IA-ENTRY APP-ENTRY! SAVESYS <app> BYE` を実行する。保存時には入力・窓・PCM・Snapshot・タスク・子を取得しない。別プロセスで保存実行体を起動すると、入口が1回だけ呼ばれ、現在の引数を読み、資源を順番に取得する。`IA-FRESH` は取得前の所有変数とネイティブ窓の不在を検査する。古い整数 ID が新プロセスで必ず無効になるという判定はしない。

| モード / キー | 動作 |
|---|---|
| `normal` / `path`、n、f | path の要求差し替え、worker 故障、最後の有効結果の保持 |
| `search`、a/b、f | search の要求差し替え、worker 故障後の保持と回復 |
| `fault-input/window/pcm/task/pipe` | 当該段階の取得直後に -4100。取得済み資源を解放し、元の失敗を保つ |
| `cancel`、c、n | 実行中と待ち状態の専用タスクを取消し、要求・終端・RELEASE を別々に記録して再投入 |
| `normal`、q / 枠の終端 | 明示解放後に入口から正常復帰、status 0 |
| `bye` / `quit` / `throw` | 終了直前に実行中タスクを用意し、PCM・窓・Snapshot・子/pipe を持ったまま BYE / QUIT / -4123 THROW。期待 status は 0 / 1 / 1 |
| `append` | 活動中の LOAD-DICTIONARY。APP 登録、所有 ID、端末要求、窓の要求フレーム数を前後比較。source の入口は呼ばない |
| `resave` | 正規に解放し runtime 変数をリセットして再保存。adapter が新プロセスで再起動 |
| `measure-path/search` | 固定フレーム枠、PAINTTRACE、PCM の区間両端・書込み記録。下記の専用起動で使う |
| `audible` | PS-DEMO-SETUP の既知の合成音を1秒ごとに約0.25秒鳴らす。q で終了 |

q は正常な終了要求。Ctrl+C の -28 はループで捕捉して記録し、資源を持ったまま継続する。既存 worker の検査に従い、f はゼロ除算で故障させる。worker で許可されない THROW を埋め込んで入口検査を回避することはしない。

## 3. 構成と待機

| 構成 | 実際に使う資源 |
|---|---|
| M0 | 入力/端末、窓、PCM、Snapshot/タスク、子と stdout/stderr pipe |
| M1 | 入力/端末、PCM、Snapshot/タスク、子/pipe。窓なし |
| M2 | 入力/端末、窓、Snapshot/タスク、子/pipe。PCM なし |
| M3 | 窓と PCM。公開 EXTENSION/タスク/端末/pipe 語なし |
| M4 | 入力/端末、Snapshot/タスク、子/pipe |
| M5 | 窓。公開タスクなし |
| M6 | PCM。公開タスクなし |
| M7 | 保存入口・引数・永続データ。後発資源なし |
| M8 / M9 | 入力/端末、窓、PCM、Snapshot/タスク。FILES/pipe なし。M9 は DEBUG も除外 |
| M10 | 保存アプリなし。SAVESYS / APP-ENTRY! の不在を静的境界として検査 |
| M11 | Linux のみ。M2 相当、DEBUG/X11 なし。既定は terminal。`--backend tk` も選択可能 |

`--backend native/tk/terminal` は実際の描画語を選択する。ネイティブの frame 番号を Tk に流用しない。Tk/terminal はネイティブ frame 待機の能力拒否を検査し、期限と入力で進む。画面が利用できないことを語群の除外と混同しない。

Tk の明示的な後始末は `2 GFX-TK-WINDOW-CLOSE DROP` とし、action と返される close 件数を処理する。EXTENSION を含む Tk・terminal の IA-07 は、能力拒否の記録に加え、normal の期限到達、空引数での q 終了、path/search の結果更新後の正常終了と所有資源の回収を自動判定する。native および EXTENSION を除外した描画あり構成の能力観察は未確認として残す。

EXTENSION がある場合、同一のループで入力、タスク、clock、利用可能なら stdout/stderr と native paint を `TASK-WAIT-MANY` に登録する。各回で新しい対象一覧を作り、終端・解放済み ID を再利用しない。イベントには通し番号・tag・reason を付ける。pipe は非同期に排出し、正常解放では子に stdin EOF を渡し、孫を待たせてから FREE する。故障とプロセス終了の回収はホストの所有規則でも確かめる。

PCM は 48,000 Hz mono s16LE、capacity 4,096、512 フレーム/1,024 bytes のブロック。空き容量まで書き、部分/ゼロ書込みでは残りを保持し、受理フレームだけ進める。PCM-WAIT は need=1 / timeout=1,000 ms。固定 sleep で供給しない。入力・I/O・描画・タスクを処理するターンの間に供給する。最初の充填と消費確認の後に開始 underrun を読み、ループ終了直後、STOP/close や子の回収より前に終了 underrun を読む。供給の時刻・受理数・累積数を記録する。

## 4. 判定と証跡

`manifest.json` に HEAD、実行引数、OS/Python、計画英日 SHA-256、題材と道具の指紋を残す。`working-tree.stdout` は dirty diff。構成ごとの `binary.json` は元実行体と保存アプリの SHA-256、設定、定義の指紋。build/save は argv・status・stdout/stderr を分離して記録する。

保存アプリは既存の `manual-acceptance-tty.py` の `Terminal.launch_argv` で起動する。Windows は ConPTY と非 breakaway Job、POSIX は pty と既存 supervisor。起動・実行中・終了後の process/thread 採取、所有した子/孫、端末状態の前後比較、shell 復帰を再利用する。adapter が別の Job/supervisor を作り直すことはない。ConPTY/pty の stdout/stderr は端末上で混合されるため、分離したふりをせず `output.bin` と `events.jsonl` に元バイトを保管する。`output.txt`、`result.json`、`processes.json` が対応する。強制回収が必要なら合格にしない。採取不能は未確認。macOS の polling だけでは短命・離脱した子の生涯を証明できない。

`ledger.json` は IA × OS × 構成 × backend ごとに `pass/fail/unverified/N/A`、run ID、試験/記録 revision、証跡、理由、機器/経路、人の回答、次の手順を持つ。終了 status だけでは合格にしない。IA-01/02/03/05/08/09/10/11/12/13 は対象 endpoint と端末/所有の確認を結ぶ。IA-04 は readiness 通知を単位に通し番号と処理/保留/破棄を照合し、pipe byte 数と task 結果も別に照合する。破棄には入口終了という理由を付ける。`automated_result` に自動判定を残し、人による close 確認が揃うまでは全体を未確認にする。IA-06 は smoke で合格にしない。IA-07 は窓なしの進行と、他 backend の能力を区別する。IA-14〜18 は英日意味照合、999/1001 の採否照合、3 OS と手作業の集約が必要で、自動起動だけで合格にしない。

IA-11 の完全復元は製品の新語ではなく Zig 試験で扱う。`src/tests/task_reap_test.zig` の `1057 bound restore ...` は PCM・タスク・窓を同時に持ち、bound host では **task Busy → PCM -528** の順となること、拒否時の辞書・APP・資源の不変、PCM-CLOSE/タスク静止後の成功、窓保持/画像解放を検査する。窓は差替え host であり、実 paint との競合の実機証明にはしない。`src/main.zig` の `1057 D2 ...` は実 OS 子（Windows sort、POSIX cat）と生きた pipe を持つ target を完全復元し、子の存続、同じ pipe ID、復元前後のデータ転送、正常終了/回収を検査する。core 直呼びの task Busy は保証に含めず、active EXEC の途中から完全復元しない。

## 5. IA-06 の形式確認と後続の測定

```powershell
# smoke: 各題材で負荷→基準。出力された run の M0/results.json を次に渡す。
python tests/scripts/integration-acceptance.py --smoke --measure path
python tests/scripts/integration-acceptance.py --smoke --measure path --baseline --load-schedule <load-run>/M0/results.json
# search も同じ2コマンドを使う。
```

1405 の `Runner.native` を再利用し、負荷側の結果進行に合わせてキーを送り、基準側では同じフレーム番号で再生する。保存アプリは基準側でも**負荷側の同じ実行体**を使い、引数でだけ追加タスク投入を止める。両側で資源取得前に同じ決定的 worker 結果を準備する。負荷側の結果は準備データとバイト比較し、基準側は負荷側のフレームごとの結果・要求世代を描画に再生する。基準側の論理的な task generation は1のまま保持し、描画だけを再生する。`render_schedule` を一致検査する。上限 8,192 bytes/結果は固定題材の範囲であり、任意の path/search 入力の上限ではない。

`paint.log` は元端末記録から PAINTTRACE JSON を取り出したもの。ConPTY の改行の代わりのカーソル移動でレコードが同じ行に並んでも、JSON の区切りで抽出し、元バイトを保持する。`run-acceptance.py` の paint 取込み（`--mode smoke --only paint --paint-log ... --paint-baseline-log ...`）に使える。区間の PCM counters と accepted frames は `results.json`、全供給は端末ログに残る。smoke では差分・閾値・分布を計算しない。

正式測定は Claude がレモンの明示確認後にだけ行う。`SIGMA_ACCEPTANCE_SMOKE` を解除し、`--smoke` の代わりに `--confirmed <確認参照> --plan-sha256 <日本語計画の完全なSHA-256>` を指定する。`--measure path/search` の枠は 1,200 固定。別題材の計画や不一致のハッシュは拒否する。各題材で新しい負荷→基準を独立に2組実施し、計画 §8 の80%規則に該当すればさらに2組、元を含む4組を残す。adapter の単一呼出しは1 runで、組数・追加の判断は計画どおり実施者が管理する。

正式結果の判定では、各 run の underrun 増分、受理フレームと供給、同じ実行体/構成/backend、描画再生、フレームごとの request→complete、input→paint/writer を照合する。欠測・供給や描画の不一致は未確認であり、成功した代替 run で埋めない。paint の33.34 ms、writer の50 ms、個別 frame の16,666,667 ns、追加 miss 0、各 run の underrun 増分0と80%延長は計画 §8 に従う。最初の frame だけ期限統計から除き、生ログに保持する。物理的な表示/キー/音の判断は別に残す。

## 6. 手作業と残る確認

各単位は `python tests/scripts/integration-acceptance.py --manual <単位> --configs M0` で起動する。キーは窓ではなく、実行した PowerShell の `キー>` に1行ずつ入力し Enter を押す。`Ctrl+C` は文字列で入力する。実際の Ctrl+C キー操作はキー入力を終了する操作なので区別する。`done` はアプリに q を送り回答へ進む。q 終了は自動で回答へ進む。窓を閉じた場合は「保存アプリ終了」の通知後、`キー>` で Enter を押して回答へ進む。`観察結果>` が空または空白だけなら再度尋ねる。回答は `human-reply.json` に証跡パス・raw hash とともに保存する。

| 単位 | 場面・操作・人が確認する合格条件 |
|---|---|
| MNL-01a | path。`キー>` に n。窓の要求・採用世代が進み、古い結果に戻らない。q で終了 |
| MNL-01b | search。`キー>` に a、b を別々に入力。窓の検索結果が切り替わる。q で終了 |
| MNL-01b-f | search。有効な画像の後、`キー>` に f。端末に NATIVE-FAILED、窓は画像を保持。q で終了 |
| MNL-02 | audible。約1秒ごとに約0.25秒の既知の合成音。`キー>` に n。音が乱れず窓が応答。q で終了 |
| MNL-03a | audible。`キー>` に Ctrl+C。端末に IA-CAUGHT、窓と音が継続。n で結果更新、q で終了 |
| MNL-03b | cancel-audible。同じ合成音。`キー>` に c。端末の IA-CANCEL requested / terminal / released / resubmitted の後に n。新しい結果と窓・音・入力の継続。q で終了 |
| MNL-04 | bye-audible。同じ合成音。`キー>` に q。端末に IA-EXIT live BYE、窓消滅と音停止、回答への復帰を確認 |
| MNL-05 | normal、無音。窓の閉じるボタンを直接クリック。キー入力は不要。端末に IA-WINDOW-CLOSED、IA-CLEAN error=0、IA-END。終了通知後 Enter で回答へ |

手作業中は確認に関係する IA-READY / IA-CAUGHT / IA-CANCEL / IA-EXIT / IA-WINDOW-CLOSED / IA-END / IA-CLEAN、NATIVE-INPUT / NATIVE-FAILED、result generation=、PCM-START / PCM-END を `[app]` 付きで逐次表示する。PAINTTRACE・PCM-SUPPLY などの大量記録は表示せず、元バイトは従来どおり保存する。入力待ちでも収集と表示を継続する。

中断は単なるバイト 3 の送信ではない。raw の通常キーは `extension.fs` の IA-KEY / IA-HANDLE が扱い、常時コンソール信号を捕捉する契約ではない（`src/host_input.zig` の windows.enter、`src/host_wait.zig` の win.Scope.begin/end、waitUsing）。そこで題材専用の予約キー 29 で IA-INTERRUPT-WAIT を記録し、10秒上限の `NS` に入る。adapter は Windows の ENABLE_PROCESSED_INPUT / POSIX の ISIG が有効になったことを期限付きで確認してから信号を送る。`NS` の -28 を既存の IA-STEP CATCH が捕捉し、資源を保持して戻る。これは中断を有効にした待機中の検査であり、raw ループの任意の瞬間で信号を捕捉する保証にはしない。Windows は別 Python プロセスを専用 ConPTY のアンカーに AttachConsole し、そのコンソール内だけに GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0) を送る（CTRL_C_EVENT は非ゼロ group ID で対象を限定できない）。利用者のコンソールは切り離さない。POSIX は未回収の supervisor が予約している pty のプロセスグループへ os.killpg(SIGINT) する。製品ソースは変更しない。

閉じる操作は題材の IA-DRAW が再表示の前に窓の状態を確認し、閉じていれば IA-STOP を設定する。これにより IA-SHOW による窓の再作成を避ける。

Windows の自動通し試験は `python tests/scripts/integration-manual-self-test.py`。指定キャッシュ環境変数を設定した PowerShell で実行する。03a → 03b → 04 → 05 を実際の `--manual` の標準入力で操作し、05 はその実行の所有窓だけに WM_CLOSE を送る。各操作の出力を待ってから次のキーを送り、03a の捕捉後の generation=2、03b の取消し後の generation=3、BYE、close、空回答の再質問、正常終了と強制回収なしを検査する。各実行の M0/manual-console.txt に利用者向け出力を保存する。自動回答には「聴取・目視は未確認」と記録し、人の合格回答として扱わない。Linux/macOS の信号経路は現地実行が必要。

Windows smoke、Zig 試験、文書検査は実装の検証であり、Linux/macOS の実行、全構成の本実行、MNL-01a〜05、実 paint/復元競合、物理表示、聴取、正式な時間測定と組数/供給の同等性確認は別である。R6 の DwmFlush 不可実環境の除外決定は維持する。Git/tque は変更しない。

POSIX では、継承した TERM が未設定・空・`dumb` の場合、adapter が所有する ANSI 解釈対応 PTY に `TERM=xterm-256color` を設定し、manifest.json に継承値と有効値を記録する。`dumb` を継承すると保存アプリでも `TERM-MODE!` は -21 を返す。provider のパイプ総バイト数は PTY 変換前の値で、POSIX は LF（各 6 バイト）、Windows は CRLF（各 7 バイト）を数える。物理端末の表示を確認したことにはならない。

統合 adapter は、PAINTTRACE の draw-generation・terminal・input と、測定専用 IA-TRACE の input・failure・render から、既存の結果駆動スケジューラへ渡す情報を組み立てます。JSON の抽出前に CSI 制御列を除去し、接頭辞・フィールド・数値の途中への挿入にも対応します。manual-acceptance-tty.py の clean() の解釈は維持し、output.bin を人が読むための原証跡として保持します。PCM 区間の文字列は、カーソル位置指定を改行にせず、CSI のみ除去して読みます。`python tests/scripts/integration-acceptance.py --self-test` で CSI 挿入の回帰検査を行えます。`--recheck-output <output.bin>` は窓を開かず、過去の 1,200 フレームの記録を検査します。旧題材のキーと描画内容は CSI 除去後の旧形式マーカーから補い、その旨を明記します。この検査は観測側の送信予定を復元せず、復旧・時間測定の合格も示しません。欠落・途中終了した過去の基準出力は合格にできません。

Windows の入力始点の修正（2026-11-26、1417）：従来の入力記録は INKEY 用 inputEvent にしかありませんでした。統合題材の TC-KEY / EKEY? による標準イベントの peek はそこを通らず、pending_input が未設定となって input の始点が0になっていました。計測ビルド限定で、TASK-WAIT-MANY/EXEC の先行保持と直接読み出しの両方に、Windows のキー押下レコードの初回取得時点の記録を追加しました。再生や繰り返し peek でも最初の時刻を保持します。通常ビルドでは comptime で記録処理を除外し、別に作った通常実行ファイルに PAINTTRACE の文字列がないことも確認しました。公開入力の動作と日本語の EKEY・EKEY?・TASK-WAIT-MANY の説明に変更はなく、実装2ファイルの翻訳元指紋を確認して再記録しました。

検証ログと smoke-summary.json は .work/1417-input/ にあります。指定された検査と両 parser の自己試験はすべて成功しました。受け入れ用ホスト試験の直接実行は成功189・skip16・失敗0で、追加した初回取得・peek・再生の試験も成功しました。計測時計の有効化は単体試験内だけで行っています。他の端点が正しくても非 smoke の input=0 を拒否する回帰試験も成功しました。既定キャッシュの書き込み拒否を避けるため、リポジトリ内の Zig キャッシュを使いました。Windows smoke の組（負荷あり → 基準）は .work/integration-acceptance/ 以下の path 20261126-212317-3141e480 → 20261126-212352-2fe6d5cc、search 20261126-212400-31c2e547 → 20261126-212417-45206bb5 です。全 run は各240フレーム・input 6件・paint 端点の欠測なし・format-only です。基準は負荷側の保存実行ファイルを再利用し、描画予定の一致も確認しました。smoke の端点は引き続き0です。本測定は行っておらず、統合実行での非0端点と応答時間の条件は未確認です。
