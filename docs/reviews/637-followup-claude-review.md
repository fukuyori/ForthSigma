# 637 追加修正の再レビュー原文

2026-11-19。読み取り専用。原文の軽微な指摘2件は、その後に反映して再検証した。

## 依頼

```text
Follow-up read-only review after your final review in .work/637-review/final-result.json. Review only the small recent fixes: host_terminal.Manager.update no longer retries old ON before applying new mask (new dirty reset test); host_wait.awaitConsoleInterrupt keeps handler scope for <=100 Sleep(1) checks after zero/failed ReadConsoleW; main utf8_console.fill latches HostFailed for unexplained guarded zero/error instead of EOF, retains explicit Ctrl+Z EOF; POSIX rawStandardInputByte now bounded poll(20ms) checks interrupted before and after readiness to close signal-before-read race; new tests/scripts/verify-terminal-modes-conpty.py sends actual Ctrl+C byte through private ConPTY, clearing Python launcher stdhandles around CreateProcess to avoid copying redirected parent handles. ConPTY Ctrl+C CATCH -28 and next KEY Q=81 PASSED, as did8GenerateConsoleCtrlEvent console cases. Check fixes for concrete defects. Do not modify files or run commands. Japanese concise, separate confirmed issues from hypotheses. No permission questions.
```

## レビュー原文

# 637 小修正の追加レビュー（読み取り専用）

修正が必要な重大な欠陥は見つかりませんでした。軽微な問題が2件あります。

読んだのは `host_terminal.zig` 全体、`host_wait.zig` 全体、`main.zig` の該当箇所（1083–1313、1894–1924、2036–2067 行、`stdin_eof` を使う箇所）、`verify-terminal-modes-conpty.py` 全体です。`git diff` は読んでいないので、修正前との差分は現在のコードから判断しています。ビルドとテストは実行していません。

## 確認できた問題

### 1. 低: 割込みで終わった読み取りの後、`stdin_eof` が true になる
- 場所: `main.zig:1259-1261`、`main.zig:1291`、`main.zig:1294`
- `standardInputByte` は先に `clearErrno()` を呼びます。そのため、`rawStandardInputByte` が errno を設定せずに -1 を返すと、`stdin_eof = true` になります。
- 今回追加された POSIX の poll 前後の確認（1291、1294 行）は、errno が 0 のまま -1 を返します。その結果、Ctrl+C による中断が EOF として記録されます。
- 次に1バイト読めるまで、stdin に対する `fileEof` は true を返します（`main.zig:928`）。KEY や ACCEPT は `input_failure` で -28 になるので、影響は stdin の EOF 判定だけです。
- 1305–1306 行の EINTR 経路では errno が EINTR のまま残るので、この問題は起きません。
- Windows の `utf8_console.readByte` も、UserInterrupt や HostFailed を latch した後、errno を設定せずに -1 を返します。同じ現象になるとコードからは読めます。修正前から同じだったかは、差分を見ていないので未確認です。
- 修正案: 割込みや latch で -1 を返すときは errno を設定するか、`input_failure` が設定されている間は `stdin_eof` を更新しないようにします。

### 2. 低（試験スクリプトのみ）: `python -O` で実行すると、試験の中身が実行されない
- 場所: `verify-terminal-modes-conpty.py` の 53、55、57、61、62、78、79、98、105、107 行
- `CreatePipe`、`CreatePseudoConsole`、`SetStdHandle`、`CreateProcessW`、`WriteFile`、`WaitForSingleObject` などの呼び出しが `assert` の中に書かれています。
- `-O` を付けて実行すると assert ごと消えるので、子プロセスが起動されません。その後どう失敗するかは追っていません。
- 修正案: API を呼ぶ処理は assert の外に出し、失敗したら明示的に `raise` します。

## 仮説（※推測です）

- **H1: ハンドラが 100ms 以上遅れた場合**
  - `awaitConsoleInterrupt` の待ち時間内に `onControl` が動かないと、HostFailed が latch されます。その後 `endInput` でハンドラの登録が外れます。
  - この状態で遅れていた CTRL_C_EVENT が処理されると、残っているのは `restoreOnSignal`（0 を返す）だけです。既定の処理でプロセスが終了し、alt 画面とカーソル非表示が残る可能性があります。
  - 前回の 1 件目の問題が、100ms を超える遅れの場合だけに縮まったことになります。高負荷のときに起きるかどうかは未確認です。
- **H2: ConPTY 試験の範囲**
  - ConPTY 試験の合格は、試行1回での順序を示しているだけです。「ReadConsoleW が先に戻り、ハンドラが後から動く」順序を再現できているかは、出力からは判別できません。
  - 確かめるには、`awaitConsoleInterrupt` が true を返した回数を記録するログが必要です。

## 欠陥を見つけなかった点

- **`Manager.update`**
  - 新しいマスクで遷移し、失敗したら旧マスクに戻して再試行する順序になっています。OFF を先に処理するので、dirty な ON を `set(0)` で回収できます。
  - 新しいテスト（`host_terminal.zig:200-212`）の `fail_at = calls+2` は、旧実装（ON を再試行してから OFF）なら2回目の書き込みで失敗し、新実装は1回で済みます。修正前と修正後を正しく区別できています。
  - 失敗後の巻き戻しで旧 ON を再適用しようとするのは、巻き戻しの意図どおりです。それも失敗したときは dirty が残り、`get()` からは外れます。
- **`awaitConsoleInterrupt`**
  - `fill` の defer の `endConsoleRead` より前に呼ばれます。そのため、待っている間も `read_thread` と世代番号は公開されたままです。
  - この間にハンドラが動くと、Sleep 中のスレッドに `CancelSynchronousIo` が空振りします。メインスレッドは 1ms 以内に割込みを検出し、defer で登録を外すので、ハンドラのループも止まります。
  - 待ち時間が次の読み取りを取り消すことはありません。
  - 割込みが届いた場合は、defer で `read_cancelled` が立ち、ハンドルが閉じられます。
- **`fill` の EOF 判定**
  - EOF として扱うのは `wide[0]==0x1A` のときだけです。latch がないので `readByte` で `ended` になります。
  - ガード中に原因の分からない 0 文字や失敗で戻った場合は HostFailed です。`ended` は立たず、次の `fill` で読み取りを再開します。
- **POSIX の poll ループ**
  - poll が「読める」と返してから `read` までの間に SIGINT が届いても、`read` はすぐ戻ります。割込みは `readByte` の 1919 行か `endInput` で回収されます。
  - SA_RESTART を付けていないので、他の読み手に入力を取られて `read` が待つ状態になっても、EINTR で抜けます。
- **ConPTY スクリプト**
  - 標準ハンドルを外してから `CreateProcessW` を呼び、`finally` で元に戻しています。その間に動いている他のスレッドはありません。
  - `TERM-MODE!` に 5（alternate と hidden cursor）を渡しているので、`beginInputGuard` の条件（`wanted & 5`）を満たします。
