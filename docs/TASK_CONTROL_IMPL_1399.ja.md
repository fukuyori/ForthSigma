# tque 1399：macOSでの追加題材の実機確認

2026-11-26、MacBook Air（Apple M5、macOS 27.2.1、arm64、AC電源）、Zig 0.17.1。時間の測定はレモンの指示（2026-11-26「時間測定は、いつ開始してもよい」）で行った。[英語版](TASK_CONTROL_IMPL_1399.md)も参照。

## 1. 滞留とSnapshot（1396）

`run-acceptance.py --mode measure --only workloads snapshot`、計画macOS v5、独立2回。証拠はMac機の `.work/acceptance/20261125T224425Z-06333bfd`・`20261125T234525Z-bf6ec10a`。

| 指標 | run1の最大 | run2の最大 | 目安 |
|---|---:|---:|---:|
| G1 enqueued→acquired（3場面） | 0.050 ms | 0.118 ms | 50 ms |
| G2 enqueued→acquired | 0.059 ms | 0.044 ms | 100 ms |
| T1 enqueued→acquired | 0.066 ms | 0.071 ms | 100 ms |
| I1 enqueued→acquired | 30.4 ms | 29.2 ms | 200 ms |
| Snapshot取得（300回） | 33.4 ms | 31.7 ms | 50 ms |

すべて目安内。I1の`queue_waiting`は最大4（上限4）、Snapshotの大きさは3,620,338 bytesで、80%規則の追加の試行の対象。

## 2. 複合待機・公平性・後始末と、子孫のプロセスの追跡

`--cases mixed`（AC-18・19・20）は動作が成功した（`.work/1399/mixed`・`mixed2`）。`--self-test` は成功し、試験の外で起動した`sleep`も試験の後に生きていた（`.work/1399/self-test`）。

macOSの間欠的な調査では子孫の寿命を証明できないため、レモンの決定（案A）で、レモンがMacのターミナルで `sudo eslogger fork exec exit` を実行し、その間にClaudeがAC-18・19・20とネイティブの題材（負荷あり・基準）を実行した。記録は `.work/1399/eslogger.jsonl`（2,273件、06:23:46〜06:26:35 UTC）で、実行の期間（06:24:08〜06:25:51 UTC）を含む。[eslogger-process-tree.py](../tests/scripts/eslogger-process-tree.py)で集計した。

- 計測用のSigmaのプロセス16個は、すべて終了した。
- Sigmaがforkした子は5個（ネイティブの題材ごとに1個：負荷ありのG1・T1・BYE、基準のG1・T1）で、すべて終了した。孫は作っていない。
- 終了していないプロセスは0個。

## 3. ネイティブ画面（1394、AC-02・05・25、D07）

最初の組（`.work/1399/native-load`・`native-baseline`、計画macOS v6）では、T1の入力→画面が最大40.9 msで、3回中2回、起動後の最初の入力が目安33.34 msを超えた。レモンの決定（案1）で先に原因を調べ、TASK-SUBMITの入口の検査を毎回やり直していたことを直した（[1408](TASK_CONTROL_IMPL_1408.ja.md)）。

直した後（`.work/1408/native-load1`〜`3`・`native-baseline1`、取り込みは `.work/acceptance/20261126T070828Z-b42c39db`（経路）・`20261126T070828Z-39b23625`（検索））：

| 指標 | G1 | T1 | 目安・判定 |
|---|---:|---:|---|
| フレーム数・入力数 | 1,200・6（基準と一致） | 1,200・6（基準と一致） | 比較の条件を満たす |
| 各フレームの期限超過（負荷あり／基準） | 0／0 | 0／1 | 合格 |
| タスクによる追加の超過 | 0 | 0 | 合格 |
| 入力→画面の最大（3回） | 16.7 ms | 16.7 ms | 33.34 ms、合格 |
| 入力→端末の最大 | 16.7 ms | 16.7 ms | 50 ms、合格 |

目視と聴取（レモン、2026-11-26）：Macのターミナルで通常ビルドの題材（G1・T1・BYE）を1つずつ手で動かし、「3つOK」の返答を得た。ClaudeはこれをG1・T1でGenerationが減らずfの後も前の結果が残ること、BYEで音が鳴りqで止まり窓が閉じたことと受け取って記録した。

## 4. 判定

- 滞留・Snapshot・入力→画面・入力→端末・各フレームの期限：macOSで目安内。タスクによる追加の超過なし。
- AC-18・19・20、AC-05・25の子孫の回収：eslogger で全プロセスの終了を確認。
- AC-25・AC-05の窓と音：目視・聴取で確認。
