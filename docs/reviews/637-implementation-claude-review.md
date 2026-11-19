# 637 Claude Code review: implementation

2026-11-19。読み取り専用CLIレビュー。以下はレビュー原文であり、指摘の採否・実行確認とは区別する。

## 依頼

```text
637の実装レビューを読み取り専用でお願いします。Read/Glob/Grepのみ、編集・Git・実行試験・外部アクセスなし。固定コピー.work/637-review/implementation/src/を対象に、host_terminal.zig、host_input.zig、host_wait.zig、main.zig、core/words_extension.zig、core/words_terminal.zig、core/input_redirect.zig、core/words_xchar.zig、core/graphics_input.zig、tests/terminal_modes_test.zigを確認してください。元srcは進行中なので指摘対象と混ぜないでください。
採用：TERM-MODE! (mask--ior)、TERM-MODE@は受理済み要求mask(非対応/dirty bit除外)、1alt/2paste/4hide/8mouse。mouse/pasteはraw時だけ実適用、Windowspaste無視。COLS/ROWSはFORMの出力・capture規則を共用。未知mask -24、非端末/TERM未設定空/dumb/WindowsVT不能-21、OS失敗-265。既存MOUSEONと要求を共有、TERM-MODE成功時VM gfx_input.mouse_onも更新。
Managerは要求/適用/dirty/退避depthを別管理、途中失敗は旧要求へのbest effort回復、dirty解除を再試行。Backend書込みとSetConsoleModeをチェック。SYSTEM全体だけ表示を退避しresumeのエラーも伝える。REPLは入力中退避して一行の実行中だけ復帰。KEY/KEY?/ACCEPTはalt/cursorを維持し、rawをleaveしてpaste/mouseを止める。raw/cooked中のSIGINTで表示を放置しないよう、visual要求があるときだけhost_waitの既存プロセス信号ゲートでinterrupt-only InputGuardを開始、入れ子は一つのnative ticketを共有。legacy nullable callbacksのエラーはWriter.input_error_fnでcoreへ伝える。coreでCATCHされたTHROWは表示を維持、未捕捉のhost reportは回復→表示解除→raw解除の後に出力。終了のprofileより前にも同じcleanup。stdoutへのエスケープはVMのcapture/outfileを経由しない。
主な懸念：signal ticket寿命・nested/復旧、入力エラーがEOF扱いにならないか、SIGINT後のEINTRリトライ、REPLpauseの整合、SYSTEM例外順、Manager失敗/再試行、Windows mouseとraw/VT、既存入力バッファの保持、HELPと機能除外、VM/Writer共有境界。Windows全体試験は一度成功し、追加試験/PTY/Windowsコンソールは並行実行準備中。Mac新機能はコンパイルのみと実機を区別します。
重大度・場所・具体的条件・修正案を最大10件。現欠陥と将来案を分け、読んだ範囲/未実行を明記、日本語で返してください。
```

## レビュー原文

# 637 実装レビュー（固定コピー `.work/637-review/implementation/src/`、読み取り専用）

修正が必要な欠陥が8件ありました。重大度「高」が2件で、どちらも Ctrl+C の扱いです。行編集の REPL では打ちかけの行がそのまま実行され、Windows では Ctrl+C 以降の入力がすべて EOF になります（Windows の件は API の挙動を推測しています）。このほか将来の改善案が2件あります。

**読んだ範囲:**
- 全体: `host_terminal.zig`、`host_input.zig`、`host_wait.zig`、`core/words_extension.zig`、`core/words_terminal.zig`、`core/input_redirect.zig`、`tests/terminal_modes_test.zig`
- 一部: `main.zig`（230–310、330–410、920–1300、1760–2420行）、`core/words_xchar.zig`（100–160行）、`core/graphics_input.zig`（440–583行）
- 参照として: `host_line.zig`（560–650行）、`core/event_input.zig`（1–60行）、`core/graphics_terminal.zig`（55–94行）
- 未読: `host_signal_broker.zig`、`host_runtime.zig`、`main.zig` の残りの部分。broker の begin/recover はコメントどおりに動くものとして読んでいます。

**未実行:** ビルド、テスト、PTY、Windows コンソールでの確認は行っていません。以下はすべてコードを読んだ結果です。

## 現在の欠陥

**1. 高: 行編集の REPL で、Ctrl+C を押すと打ちかけの行が実行される（POSIX）**
- 場所: `main.zig:1987-1991`、`main.zig:2082-2085`、`main.zig:2380-2383`、`host_line.zig:615-622`、`host_line.zig:631-641`
- 条件:
  - プログラムが 1 か 4 を要求したまま REPL に戻ると、表示は退避されますが `modes.wanted` は残ります。そのため REPL の入力中にも InputGuard が張られます。
  - ここで行を途中まで打って Ctrl+C を押すと、`host_line` が `raise(SIGINT)` し、ガードのハンドラがそれを受け取ります。
  - 次の `lineByte` で `readByte` が -1 を返し、`host_line` はこれを EOF とみなして打ちかけの行を返します（履歴にも残ります）。その行を `interpretAndPrompt` が実行します。
  - 行が空なら `line=null` となり、REPL は終了コード 0 で終わります。UserInterrupt は報告されません。
- 修正案: `beginInputGuard` を張る条件を「`wanted & 5` があり、かつ `pauses == 0`」にします。REPL の入力中は表示を退避済みなので、ガードは不要です。あわせて `host_line` に割込みという結果を設け、EOF と区別できるようにします。

**2. 高（※`ReadConsoleW` の挙動は推測です）: Windows の cooked 入力で、Ctrl+C の後はずっと EOF になる**
- 場所: `main.zig:1160-1164`、`main.zig:1174`
- 条件:
  - 1 か 4 を要求中に KEY や ACCEPT で待っている間に Ctrl+C を押すと、`onControl` が 1 を返します。
  - このとき `ReadConsoleW` は 0 文字で戻ると推測されます。すると `fill()` が false になり、`ended=true` が立ったまま戻りません。
  - CATCH で処理を続けても、以後の KEY/ACCEPT はすべて EOF になります。REPL は終了します。
- 修正案: `fill` が失敗したとき、`inputInterrupted()` が真（または `GetLastError()==995`）なら `ended` を立てずに -1 を返します。

**3. 中: REPL の pause/resume の対応が崩れ、それ以降どの行も実行できなくなる**
- 場所: `main.zig:2088-2091`、`host_terminal.zig:91-95`、`host_terminal.zig:97-101`
- 条件:
  - `resumeModes` は pauses を 1→0 にしてから失敗を返します。
  - そのあと `reportDiagnostic` から呼ばれる `finish` が pauses を 0 にし、defer の pause はまだ登録されていません。
  - 次の行からは pauses==0 のため、毎回 `HostFailed` になります。
- 修正案: resume が失敗した分岐でも `pausePresentation()` を呼び、深さを元に戻します。

**4. 中: 保存された入力エラーが、後の無関係な語で投げられる**
- 場所: `main.zig:1962-1972`、`main.zig:1993`、`main.zig:2092`、`main.zig:359`
- 条件: 次のエラーは `input_failure` に保存されますが、REPL は `inputError` を呼びません。
  - REPL の `readByte`/`editedLine` で、ガードの開始・終了に失敗したとき
  - `interpretAndPrompt` の defer の pause に失敗したとき
  - SYSTEM の defer の resume に失敗したとき

  そのため、後の行で最初に実行された KEY、KEY?、ACCEPT、INKEY、MOUSE-ON などが、そのエラーで THROW します。
- 修正案: REPL で各行を実行する前に、保存されたエラーを取り出して報告するか捨てます。pause の失敗はその場で報告します。

**5. 中: raw 中に表示の再適用が失敗し続けると、KEY-IOR などが永久に待つ**
- 場所: `main.zig:999-1009`、`main.zig:1029-1030`、`host_input.zig:256-261`
- 条件:
  - raw に入った後、`dirty` の再試行が失敗し続ける場合です（stdout に書けない、Windows で `SetConsoleMode` が失敗する、など）。
  - `enter()` は false を返しますが raw は true のままなので、`fileStdinByte` は 1ms ずつ再試行を繰り返します。
  - Ctrl+C（byte 3）も読まれません。
  - `terminalEventKey`（1897行）は `takePresentationError` を確認していますが、`fileStdinByte` は確認していません。
- 修正案: `nextByte` が null を返した後に `try host_input.takePresentationError()` を入れます。

**6. 中（※推測: コンソールの既定入力モードに 0x10 が含まれる場合）: Windows の raw で、要求していないマウス入力が届く**
- 場所: `host_input.zig:470`、`host_input.zig:489-493`、`host_terminal.zig:36`
- 条件:
  - `raw_mode` を作るとき、`saved_mode` の `mouse_input` を落としていません。
  - Manager の `applied` は mouse=0 なので、OFF の適用は省略されます。
  - その結果、要求が 0 でもマウスのレコードが MOUSE の状態を更新し、MOUSE-OFF でも止まりません。
- 修正案: `windows.enter` で `mouse_input` も落とします。

**7. 低〜中: mouse 要求が VM とホストで食い違う**
- 場所: `host_input.zig:213-216`、`words_extension.zig:52`、`main.zig:1995-2003`
- 条件は次の3つです。
  - (a) 従来の `setMouse` は `supported` のマスクを通しません。そのため POSIX の非端末や TERM=dumb で MOUSE-ON を実行すると、TERM-MODE@ が 8 を返します（TERM-MODE! 8 なら -21 になる環境です）。
  - (b) TERM-MODE! が成功すると、mouse が対応外で落とされていても `mouse_on` が true になります。
  - (c) 未捕捉エラーで `finish()` が要求を 0 にしても、`gfx_input.mouse_on` は true のまま残ります（`graphics_terminal.zig:74` の DSR が実行されます）。
- 修正案: `setMouse` に `& supported` を適用します。`mouse_on` はホストの `get()` の結果から設定し、後始末のときに VM 側も更新します。

**8. 低: XKEY が継続バイトの読み取りで入力エラーを捨てる**
- 場所: `words_xchar.zig:156-158`
- 条件: 端末入力のとき、UserInterrupt や HostFailed が `break` で捨てられ、保存されたエラーも消えます。
- 修正案: `InputUnavailable` 以外のエラーは常に返します。
- 同じ種類の問題: 従来の `key_fn` の経路（`words_terminal.zig:23-24`、`event_input.zig:28-32`）も `input_error_fn` を確認していません。ただし main では `key_ior_fn` と `event_key_fn` があるため、現状では到達しません。

## 将来案・仕様の確認

**A. 入力中以外の SIGINT（仕様の範囲を確認したい点です）**
- cooked でプログラムが動いている最中（MS で待っているとき、出力しているとき）に Ctrl+C を押すと、既定の動作で終了し、alt 画面やカーソル非表示が残ります。
- Windows の Ctrl+Break（event 1）は `onControl` が 0 を返すため、同じ結果になります。SIGTERM と SIGHUP も同様です。

**B. 単一の `native_scope` を2つの broker が共有している**
- 入力ガードは `fallback`、NS は runtime の broker を使い、どちらも同じ `native_scope` を使います。
- 現状は重ならないので問題は出ません。将来入れ子になると、`self.*` が上書きされ、`endInput` で `scope.?` が null になります（安全ビルドでは panic）。
- 案: broker を一本化するか、使用中なら拒否するようにします。

## 問題を見つけなかった点

以下は読んだ範囲では懸念どおりの問題は見当たりませんでした（いずれも未実行です）。
- EINTR の再試行（`applyPresentation`、`posix.Scope.end`、cooked の read）
- SYSTEM で、退避 → leave → resume のエラーを伝える順序
- profile より前の後始末（`main.zig:2313`）
- COLS/ROWS と FORM の規則の共有
- エスケープを VM の capture を通さずに書くこと
- ネストした ticket の共有と、終了失敗時の `recovery_broker` の回収
