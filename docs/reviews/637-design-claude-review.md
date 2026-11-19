# 637 Claude Code review: design

2026-11-19。読み取り専用CLIレビュー。以下はレビュー原文であり、指摘の採否・実行確認とは区別する。

## 依頼

```text
637ターミナル制御の具体案を読み取り専用でレビューしてください。Read/Glob/Grepのみ、編集/Git/テスト/外部アクセスなし。docs/ASYNC_CORE_PLAN.mdの第1節、CORE_EXTENSION_DETAILED_DESIGN.md関連、src/host_input.zig、host_wait.zig、main.zigの入出力とSYSTEM・終了、core/words_terminal.zig、words_extension.zigを確認してください。
利用者はClaude Codeのレビューと並行して進めることを希望。共通基盤1055はMac実機も含め完了。637を実装します。
具体案：EXTENSIONにTERM-MODE! ( mask -- ior ) とTERM-MODE@ ( -- mask )、COLS/ROWS。定数TERM-ALT-SCREEN=1 TERM-PASTE=2 TERM-HIDE-CURSOR=4 TERM-MOUSE=8。未知/負maskはior=-24、コールバックなし/端末非対応-21、OS失敗-265。Windowsは従来ReadConsoleInputW維持、PASTEだけ無視して成功しgetterにそのbitを立てない（利用者決定）。getは実際に適用できたmask。要求maskと適用maskを分離。mouseは既存MOUSE-ON/OFFと同じ一つの要求へ統合、raw時だけ有効、それ以外は要求保持しgetのmousebitは0。alt/cursor/pasteはrawと無関係に設定できる。Linux/macはisatty入出力とTERM=dumb以外を能力の最低条件、実端末の対応を能動照会して保証はしない。COLS/ROWSは既存FORMと同じ出力先・capture・fallback(24x80)規則を共有。既存FORMは基本語群のまま、新語のみextension。
新しいhost_terminal.zigに差替えBackendを持つ状態管理を置く。変更したbit/失敗中のbitを記録し、途中失敗は旧状態へのbest-effort復旧、復旧失敗はdirtyとして残し後続操作/終了で再試行し、成功を偽らない。既存NS保留復元はhost_input.before_mode_change経由で先に回復。共有中のRuntime等の契約は変更しない。
line入力/KEY/KEY?/ACCEPT/SYSTEMでは表示モードをsuspendしてから既存host_input.leave、戻る際resumeするスコープ。ネスト可。旧MOUSEONだけの通常経路はrawへ再入するまではmouse要求だけ保持。終了はrequestedを0にしてdisplayを復元し、Raw未使用でもalt画面を戻す。CATCHされたTHROWは設定維持、未捕捉エラーで実行体が終わるときdeferで解除。CTRL-Cや終端の試験とSignalBrokerの復元の順を確認。
具体案の欠陥と、残る値・動作の推奨を重大度付き最大8点で日本語出力へ。設計を具体化するため、mask取得 semantics/unsupported/rollback/suspend nestingと読み取り経路に抜けがないか重点確認。将来638の貼付けイベントの実装は今回の範囲外として扱いますが、POSIX端末へpaste要求を送る仕様の意味は明記します。
```

## レビュー原文

# 637 具体案のレビュー結果

レモン、ご指定のファイルを読み取り専用で確認しました。編集・Git・テスト・外部アクセスは行っていません。指摘は重大度の高い順に8点です。

---

### 1. 【高】KEY/KEY?/REPL で表示を退避すると、全画面アプリでも1キーごとに通常画面へ戻る
- `readByte` は1バイトごとに `host_input.leave()` を呼んでいます（`src/main.zig:1797`）。REPL（`main.zig:2260`）、ACCEPT（`terminalRead` 内の `main.zig:1924`）、行編集（`lineByte` 経由の `main.zig:1976`）も同じ呼び方です。
- 「leave の前で suspend、戻るときに resume」とすると、1キーごとに `?1049h/l` が出て画面が切り替わります。さらに `KEY` で入力を待つ間は、代替画面が消えて通常画面が見えます。
- **推奨**: bit ごとに退避の扱いを分けます。
  - **mouse と paste**: 入力に影響するので、raw でないときは常に止めます。
  - **alt と cursor**: 表示だけなので、退避するのは SYSTEM・エディター、REPL のプロンプト行、終了、未捕捉エラーに限ります。KEY/KEY?/ACCEPT では維持します。
  - 退避の範囲は1バイト単位にせず、行単位（`editedLine` と `terminalRead` の全体）と SYSTEM の全体に置きます。こうすると、入れ子のスコープはほぼ不要になります。

### 2. 【高】未捕捉エラーと終了時の出力が代替画面に書かれ、そのまま消える
- 未捕捉エラーのメッセージは、`machine.report(err)` が `return 1` より前に出します（`main.zig:2214-2242`）。REPL でも `interpretAndPrompt` の中で出します（`main.zig:1983`）。どちらも、端末を戻す defer（`main.zig:2127-2132`）が走る前です。
- `--profile` と `--lint` の出力を出す defer（`main.zig:2175-2189`）は、端末を戻す defer より後に宣言されています。Zig の defer は逆順に実行されるので、これらの出力は代替画面に書かれます。
- **推奨**: `report` の前に表示を解除する口を用意します。ホストのフックで `machine.report` を包む形です。あわせて、表示の復元を profile/lint の出力より前に行います（明示的に呼ぶか、defer の宣言位置を移します）。
- REPL で未捕捉エラーが起きたとき（QUIT へ戻るとき）に、requested を残すか 0 にするかを決めておく必要があります。推奨は「suspend して requested は残す」です。この場合、alt が戻るのは次に raw へ入ったときです。

### 3. 【高】PASTE を raw と無関係に有効にすると、入力に印が混ざる
- cooked で読む間（ACCEPT/REPL/KEY）に bracketed paste が有効だと、`ESC[200~` が行の中にそのまま入ります。
- raw で読む場合も、638 の前は `EKEY`/`INKEY` に未知のエスケープ列として届きます。
- **推奨**: PASTE は mouse と同じく「raw の間だけ有効、それ以外は要求だけ保持」にします。
- 仕様に書く意味の案は次のとおりです。
  > TERM-PASTE は POSIX 端末へ `ESC[?2004h` を送り、貼り付けの前後を `ESC[200~`/`ESC[201~` で囲むよう要求する。本版ではこの印を解釈せず、raw 読取りにはエスケープ列として届く。印の解釈は 638 で行う。端末が要求を無視しても Sigma は検出しないので、getter の bit は「要求を送った」という意味である。

### 4. 【中】TERM-MODE@ の「実際に適用できた mask」が、関係のない入出力で変わる
- raw へは最初の読取りで暗黙に入ります（`host_input.zig:194`）。DSR（`host_input.zig:167`）でも raw に入ります。
- そのため mouse の bit が 0/1 のどちらになるかは、TERM-MODE! の直後か、INKEY の後か、KEY の後かで変わります。アプリからは「非対応で 0」なのか「まだ raw でないので 0」なのかを区別できません。
- **推奨**: getter は「受理済みの mask」（requested から非対応の bit と失敗した bit を除いたもの）を返します。今が raw かどうかで変えません。Windows の PASTE の bit を 0 にする決定とも矛盾しません。
- 非対応のときは、どの bit も適用せずに -21 を返します（一部だけ適用することはしない）。requested == 受理済みで dirty でもない場合は、何も出力せずに 0 を返します。

### 5. 【中】既存の Backend は成否を返さないので、-265 も dirty も判定できない
- `report` は送る前に `mouse_reporting = on` を書きます（`host_input.zig:210`）。
- `posix.writeAll` は void で、エラーのときは黙って戻ります（`host_input.zig:267-277`）。
- `windows.setMouse` は `SetConsoleMode` の戻り値を捨てています（`host_input.zig:433`）。
- Windows の VT 出力を有効にした結果も記録していません（`main.zig:1031-1038`）。
- **推奨**:
  - Backend の書込みと mode 設定は bool か error を返すようにし、成功してから applied を更新します。
  - Windows の alt/cursor は、VT processing を有効にできたことを対応の条件にし、できなければ -21 にします。
  - Windows 側の書込み経路も新しく必要です。`flushOutput` の後に同じ出力先へ書き、順序を保ちます。
  - 書込みが途中で失敗したときは、その bit を「不明」にします。復旧と終了では、不明な bit にも解除の列を必ず送ります（何度送っても結果は同じなので安全です）。

### 6. 【中】MOUSE-ON の VM 側の印と、新しい要求がずれる
- `MOUSE-ON` は VM の `gfx_input.mouse_on` を設定してからホストへ渡します（`graphics_input.zig:576-578`）。この印は SHOW の後のカーソル問合せに使われます（`graphics_terminal.zig:74`）。
- TERM-MODE! がホストの要求だけを変えると、この印とずれます。
- 既存の `setMouse(on)` は `cursor_unanswered` も解除しています（`host_input.zig:161`）。TERM-MODE! の MOUSE も同じ副作用を共有する必要があります。
- TERM-MODE! は mask を丸ごと設定するので、MOUSE の bit がない mask を渡すと MOUSE-ON の要求も消えます。これを仕様に明記してください。

### 7. 【中】読取り経路の一覧から漏れているもの
- leave する経路は `readByte`、`terminalKeyReady`（KEY?、`main.zig:1890`）、`editedLine`（`main.zig:1949`）、`runShellCommand`（`main.zig:356`）です。エディターも `runShellCommand` を通ります。
- 一方、stdin の `KEY-FILE`/`READ-FILE`/`KEY?` 系は `fileStdinByte` → `nextByte` を通り、raw のまま読みます（`main.zig:987-993`）。どちらも「KEY」系に見えますが、入る経路が逆です。
- そのため、suspend を掛ける場所は語の名前ではなく `leave` の呼出し元で決めてください。
- Ctrl+C の扱いは次のとおりです。
  - raw の間: キー 3 として `UserInterrupt` になり、2 の経路に乗ります。
  - cooked の間: ISIG の既定の SIGINT でプロセスが終わり、alt 画面は戻りません（設計どおり対象外）。これを文書に明記してください。
  - 待機中: NS のスコープでは ISIG を有効にしますが、cc を変えるだけで表示の状態には触れません（`host_wait.zig:68-87`）。
- 終了時の順序は「`host_wait.recover()` → 表示の復元 → `host_input.leave()`」を推奨します。今の defer（`main.zig:2127`）の中にこの順で置けば、`flushOutput`（2053）と `utf8_console.finish`（2058）より前に実行されます。

### 8. 【低】出力先、COLS/ROWS、能力条件の値
- TERM-MODE! のエスケープ列は `self.write` を通さず、ホストから端末へ直接送ってください。`self.write` を通すと、capture や OUTFILE が有効なときに文字列やファイルへ混ざります。fd1 が端末でなければ -21 にします。
- COLS/ROWS は `.form` の処理（`words_terminal.zig:50-67`）を共通の関数にして使ってください。capture 中は ROWS=1、COLS=maxInt になります。スタック効果 `( -- u )` は WSL の gforth で照合が必要です（未確認）。
- `TERM` が未設定か空のときも dumb と同じく非対応とするよう推奨します。ただし、これは利用者の判断が必要な事項です。
- `ASYNC_CORE_PLAN.md:77-82` の未決の点（非対応時の扱い、スタック効果）は、決定に合わせて更新が必要です。

---

### 判断をお願いしたい点
- 1 について: KEY/KEY?/ACCEPT で alt と cursor を維持する案でよいか。
- 3 について: PASTE を raw の間だけ有効にする案でよいか。
- 8 について: `TERM` が未設定のときの扱い。
