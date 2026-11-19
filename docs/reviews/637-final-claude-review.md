# 637 最終レビュー原文

2026-11-19。読み取り専用。指摘を受けた後に追加修正・再検証を行っているため、現状の未解決一覧ではない。評価は637-review-response.mdを参照。

## 依頼

```text
Read-only final review of terminal task637 implementation. Review current src/host_terminal.zig, host_input.zig, host_wait.zig, main.zig and core changes via git diff (tools Read/Glob/Grep only, inspect current files), tests/scripts/verify-terminal-modes*.py, docs/TERMINAL_CONTROL_DESIGN.md. Previous reviews: .work/637-review/design-result.json, implementation-result.json, windows-investigation-result.json. Earlier 8 findings have been addressed, especially nullable errors, REPL partial-line abort, raw ownership and mouse accepted state. Windows investigation: double-line probe PASSED (first line lost after CancelSync). Fix now uses owned CONIN$ handle for ReadConsoleW, keeps it between normal reads (preserves long cooked lines), closes it after cancellation to terminate stale conhost read; all8Windows cases then passed. Final code additionally unpublishes reader thread before CloseHandle, retains ownership on close failure, removed tracing. Check actual regressions/lifetime/races, not scope expansion. Process-global broker gate excludes foreign runtime signal scopes. CATCH preserves requested modes, uncaught diagnostics clears. Default SIGINT outside input/wait scopes is out of task scope and will be documented. Report remaining concrete problems ranked, or none. Japanese. Do not ask user permission, change files or run commands.
```

## レビュー原文

# 637 最終レビュー（読み取り専用）

修正が必要な問題が1件、軽微な問題が2件あります。

**読んだもの:** `host_terminal.zig`、`host_input.zig`、`host_wait.zig`、`main.zig`（340–400、990–1300、1860–2160、2380–2500行）、`words_extension.zig` と `graphics_input.zig` の該当箇所、`verify-terminal-modes-windows.py`、設計文書の該当節、過去のレビュー結果2件
**読んでいないもの:** `git diff`（コマンドを使わない条件のため、現在のファイルだけを読みました）、`host_signal_broker.zig`、`verify-terminal-modes.py`、`design-result.json`
**実行していないもの:** ビルド、テスト、probe。以下はすべてコードを読んだ結果です。

## 1. 中〜高: Windows で物理キーの Ctrl+C を押すと、入力が永久に EOF になるか、プロセスが終了することがある

- 場所: `main.zig:1176-1186`、`main.zig:1214-1223`、`host_wait.zig:76-81`
- 前提（※推測です）: 物理キーの Ctrl+C では、conhost が cooked read を終わらせる処理と、ハンドラのスレッドを作る処理が別々に進みます。そのため、`ReadConsoleW` が 0 文字で戻った時点では、`onControl` がまだ動いていない可能性があります。
  - 根拠: 調査結果の `readDataCooked.cpp` の `Notify(CtrlC)` の経路。
  - 記憶による補足: CPython の `myreadline.c` は、`ERROR_OPERATION_ABORTED` の後に割込みイベントを最大 100ms 待っています。これは、この順序が保証されていないことを示していると考えます。
- 起きること:
  1. `fill()` が false を返します。この時点では、defer の `inputInterrupted()` も `readByte` の 1180 行の確認も偽です。そのため `ended = true` が立ち、その後の KEY/ACCEPT はすべて EOF になります。REPL では `ch < 0` のため終了コード 0 で静かに終わります。
  2. さらに、`endInputGuard` → `endInput` で `accepting_interrupts=false` になり、ハンドラの登録も外れます。その後にハンドラのスレッドが動くと、`restoreOnSignal` が 0 を返します。結果は既定の終了で、alt 画面とカーソル非表示が残ります。
- テストで見つからない理由: Windows の試験（`verify-terminal-modes-windows.py:129`）は `GenerateConsoleCtrlEvent` だけを使っています。この経路では、ハンドラが先に動いて取り消すので、順序が必ず逆になります。物理キーの経路は試していません（設計文書の69行目にも、物理キーでの受け入れとは別扱いと書かれています）。
- 修正案:
  - `ReadConsoleW` が失敗したとき、または `read == 0` で戻ったとき（`GetLastError()==995` を含む）は、スコープを張ったまま `interrupted` を一定時間（例: 100ms）待ちます。
  - 割込みが届かなかった場合も、`read == 0` は `ended` にしません。EOF とみなすのは `0x1A` のときだけにします。
  - 確認には、`WriteConsoleInputW` か ConPTY で物理キーに近い経路から Ctrl+C を入れる probe が必要です。

## 2. 低: POSIX で、割込みの確認から `read(0)` までの間に届いた SIGINT は、次の入力まで反映されない

- 場所: `main.zig:1877-1899`、`main.zig:1276-1286`
- 条件:
  - 1877行の確認の後、`flushOutput()` や `leave()` を実行している間に SIGINT が届く場合です。端末への書き込みが詰まって待たされると、この区間は長くなります。
  - このとき `read(0)` は EINTR にならず、そのまま待ちます。ユーザーが次のキーを押すと 1896 行で -28 になりますが、その時に読んだ1バイトは捨てられます。
- Windows 側には、公開後の確認と 250ms の再試行があるので、同じ問題はありません。
- 修正案: `pselect`/`ppoll` でシグナルを原子的に扱うか、self-pipe で起こします。影響が小さいので、tque に登録して後で対応する程度で足りると考えます。

## 3. 低: 適用の失敗が続く間は、`TERM-MODE! 0` で要求を下ろせない

- 場所: `host_terminal.zig:71-80`
- 条件:
  - `update` は、まず今の目標に合わせ直す `try self.transition(self.target())` を実行します。
  - ON の適用が失敗し続ける状態（`dirty` が残る状態）では、`set(0)` もここで失敗して戻ります。そのため `wanted` は下がりません。
  - 未捕捉のエラーになれば `finish` で回収されるので、実害は CATCH で処理を続ける場合に限られます。
- 修正案: 最初の合わせ直しに失敗しても、新しいマスクへの遷移は試みます。

## 問題を見つけなかった点（読んだ範囲）

- 専用 CONIN$ ハンドルの寿命
  - `endConsoleRead` で登録を外してから `CloseHandle` しています。登録の解除は `cancelConsoleRead` と同じロックの下で行われるので、閉じたハンドルを取り消しに使う競合はありません。
  - close に失敗したときは `read_cancelled` とハンドルを残し、次の `fill` で再試行します。その間、同じハンドルで読むことはありません。
  - `finish` で閉じています。
- `OpenThread(1=THREAD_TERMINATE)` は、`CancelSynchronousIo` が要求するアクセス権と一致しています。
- 世代番号の確認により、古いハンドラが次の読み取りを取り消すことはありません。
- REPL の pause/resume の対応
  - `interpretAndPrompt` で resume に失敗した場合は、`finish` の後に再び pause するので、深さが元に戻ります。
  - SYSTEM の経路でも深さは崩れません。
- REPL の打ちかけの行
  - 割込みが保存されると、`inputError` が先に報告して終了します。打ちかけの行は実行されません。
- 入れ子の入力は ticket を共有し、`interrupted` は最外側の `endInput` でだけ取り出されます。
- Manager
  - 部分的な失敗では元に戻し、`dirty` を残します。
  - `suspendModes` が失敗したときは pause を数えません。
  - `finish` は何度呼んでも同じ結果になります。
- Windows の raw で `mouse_input` を落としています。従来の MOUSE-ON は `supported` のマスクを通ります。

1件目は物理キーの Ctrl+C でしか再現しないので、Windows の自動試験では見つかりません。修正するなら、物理キーに近い経路で Ctrl+C を入れる probe も合わせて作ることをお勧めします。
