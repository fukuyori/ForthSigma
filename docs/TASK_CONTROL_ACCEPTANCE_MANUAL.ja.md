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
能力がなければ未確認とし、合格にしない。OS間で合格を転記しない。
別端末から試験プロセスのスレッドと子プロセスを確認する。終了操作の対象は試験自身だけとする。
Ctrl+C後はシェルのecho、カーソル、入力、新しいsigma起動を確認する。

検索は `zig-out/bin/sigma examples/task-search.fs`、I/Oは `zig-out/bin/sigma examples/task-checksum.fs` で起動する。Windowsではsigma.exeに置き換える。自動examples群を先に実行した場合は `.work/1380/checksum-chunks.fs` も使用できる。3塊の期待するchecksumは8355840、8355840、21である。短すぎて処理中の終了操作を観察できなければ、その操作は未確認と記録する。

## AC-02

実行：`zig-out/bin/sigma examples/task-path.fs`（Windowsはsigma.exe）。

- **準備：**前景端末でG1を起動する。

- **操作：**`n` と無関係な文字を交互に入力し、計算中に `q` で終了する。

- **期待する結果：**入力とframe/generation出力が進み、旧世代が最新表示を上書きせず終了する。

- **記録すること：**入力順、表示世代、取消し診断、終了状態。端末例だけではネイティブ画面の合格にはならない。

## AC-05

実行：`zig-out/bin/sigma tests/scripts/check-task-console.fs`（Windowsはsigma.exe）。

- **準備：**`.work` を作り結合fixtureを起動する。

- **操作：**`active` で `r`、`replaced` で `c`、`bye-active` で `b` を押す。

- **期待する結果：**frame=r/c/b、cancelled、releasedが表示され、計算中もファイルI/Oが進み終了する。

- **記録すること：**出力、一時ファイル回収、プロセス/スレッド所有。複数タスク・音・実画面の同時所有は専用fixtureがなく未確認とする。

## AC-18

実行：`zig-out/bin/sigma examples/task-path.fs`（Windowsはsigma.exe）。

- **準備：**端末入力モードと実画面backendを記録する。

- **操作：**`n`、`q` を入力し、検索・checksumでも繰り返す。

- **期待する結果：**入力、タスク終端、ファイルデータ、出力が進む。

- **記録すること：**Enterの要否と実資源の種類。既存例は全供給元を一つの複合待機へ接続する試験ではない。実I/O可用・paint/close・同時成立の専用fixtureは未対応であり、例や偽backend試験から合格を推定しない。

実画面の補助試験として、利用可能なbackendで次を実行する。`public paint real native window wait (opt in)` がOKであり、skipでないことをログで確認する。128×128の試験画面が開いて閉じることを観察する。この試験だけで入力・I/O・paint全供給元を結合した合格とはしない。

Windows PowerShell:

```powershell
$previousAcceptancePaint = $env:FORTHZ_PAINT_SMOKE
$env:FORTHZ_PAINT_SMOKE = '1'
try { zig build runtime-test --summary all } finally { $env:FORTHZ_PAINT_SMOKE = $previousAcceptancePaint }
```

Linux:

```sh
FORTHZ_PAINT_SMOKE=1 zig build runtime-test --summary all
```

## AC-20

実行：`zig-out/bin/sigma examples/task-search.fs`（Windowsはsigma.exe）。

- **準備：**T1と別セッションのchecksumを起動する。

- **操作：**`a`/`b` を反復し、checksum出力も確認して `q` で終了する。

- **期待する結果：**入力、検索件数、表示、ファイル結果が進み世代が逆戻りしない。

- **記録すること：**各供給元の進行と出力停止。別セッションは同一hostの公平性の証明ではなく、混在host fixtureは未対応である。

## AC-24

実行：`zig-out/bin/sigma examples/task-path.fs`（Windowsはsigma.exe）。

- **準備：**WindowsはGet-Process、LinuxはpsでPID・スレッド・子の開始状態を記録する。

- **操作：**処理中に `q`、新規起動してCtrl+C、検索とchecksumでも繰り返す。

- **期待する結果：**所有タスクが終了し端末が復元する。タスク終端・出力排出・プロセス終了を区別する。

- **記録すること：**前後の所有資源と端末状態。子・音・画面および隔離した停止不能hostの結合fixtureは未対応である。workerの強制終了を回収成功としない。

## AC-25

実行：`zig-out/bin/sigma examples/task-path.fs`（Windowsはsigma.exe）。

- **準備：**G1を起動し、次にT1で繰り返す。

- **操作：**G1は `nnn`、T1は `ba` を入力し、`q` で終了する。

- **期待する結果：**最新世代のみ反映し、G1の世代4は95頂点、T1のaは1048576一致・1000件保存、bは0件である。

- **記録すること：**失敗時の従前表示維持、世代、回収。G2・最大負荷・混在I/Oのfixtureは未対応であり、該当部分は未確認とする。

## 確認結果の記録

各項目を合格・失敗・未確認に分け、未確認の理由と次に必要なfixtureを残す。速度・容量の合否は別の固定計画に従う。

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
OS採取の欠測は未確認として残し、推定した成功データで補わない。
