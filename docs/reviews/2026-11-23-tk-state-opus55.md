# Tk状態通知のOpus 5.5レビュー（2026-11-23）

Claude Code CLIへ`--model claude-opus-5-5 --tools Read,Grep,Glob`を指定した。すべての応答のmodelUsageは`claude-opus-5-5`。読み取り専用で依頼し、実行確認はCodexが担当した。各段階の原文を以下に保存する。

## 設計と初稿

# Task1298 レビュー: 共通 Tk window state(Linux 先行)

レビュー中に実装が入ってきたので、計画と現在のソース(`src/core/tcl.zig`、`src/graphics/sigma_tk.tcl`、`src/graphics/graphics.fs:345-355`、`words_graphics.zig:370`)の両方を見ました。builtin を末尾に追加していること、wish を起動しないこと、delta 観測、W を backpressure の対象外にしたこと、ensureRunning で seen だけを reset すること、stop の drain に上限があることは、計画どおりです。テストはまだ1本もありません(`src/tests` に該当なし)。

## 具体的なバグ(修正を推奨)

1. **状態の問い合わせがユーザーの TCL 結果を壊す。** `windowState` は `eval()` を通るので(`tcl.zig:328`)、`run()` が `tcl.result` と `error_text` を free して上書きします(`tcl.zig:306-308`)。
   - `TCL-EVAL` の後に `WINDOW-OPEN?` を呼ぶと、先に受け取った c-addr が解放済みの heap を指します。
   - Tcl 側がエラーを返した場合は、`TCL-ERROR$` が `sigma_window_state` のエラー文に置き換わります。
   - 対策: R の text を slot に入れず、読んだらすぐ free する内部用の run を作る。既存の `(TK-WINDOW-ID)` と `(TK-RECT-ASK)` にも同じ問題があります(別件)。

2. **TCL-STOP の drain が -265 を握りつぶす。** drain 中に protocol 違反や read 失敗が起きると、`lost()` が `halt()` の戻り値(bool)を捨てます。その後 `stop` は `running == false` なので halt を呼ばず、`HostFailed` を無視します(`tcl.zig:394-395`)。結果として、終了や cleanup の失敗が報告されません。halt の結果を保持して、`HostFailed` を返すべきです。

3. **drain が W 以外の message も処理してしまう。** E/K/M は `heapAllocate` に失敗すると `MemoryExhausted`、K は `windowKey` の error を返すので、TCL-STOP が無関係な event のせいで失敗し得ます。また、停止後に K が INKEY に、E が TCL-EVENT に残ります。
   - 対策: drain 中は W 以外を heap を使わずに skip し、W だけを処理する。

4. **W を heap に置いていることによる取りこぼし。**
   - SAVE(`releaseHeap`)や restore(`forgetHeap`)で W が partial のまま drop されて `skip` に入ると、復元できるのは次の query だけです。その前に TCL-STOP や wish の喪失があると、count が消えます。
   - W の header を受けた時点で heap が尽きていると、wish が halt され count も失われます。
   - 対策: W は 19 byte 以下なので、`TclState` 内の固定 buffer に読み込む。これで SAVE/restore/OOM のどれでも残ります。

5. **Tcl 側: `sigma_send` が例外を出すと window を閉じられない。** `sigma_window_close_request` の中で `sigma_send` が throw すると(stdout の EPIPE など)、`wm withdraw .` に到達しません。`catch {sigma_send W ...}` で囲むべきです。

## lifecycle / 選択の懸念

- **選択が切り替わると count が飛ぶ。** auto モードで Tk の SHOW が -265 になると、`(AUTO-SHOW-TK)` が `GFX-AUTO-DISPLAY` を 1 にします(`graphics.fs:463`)。すると WINDOW-CLOSES は native の値(通常 0)に変わり、「値が変わったら終了する」という使い方では誤って終了します。少なくとも document が必要で、可能なら fallback 後も Tk の count を返す方がよいです。
- **Ctrl+C で Tk window ごと消える。** query 待ちの間に Ctrl+C すると、`run` の errdefer が wish を halt します。毎フレーム `WINDOW-FOCUSED?` を呼ぶ program では、Ctrl+C で Tk window も閉じます。毎回 blocking の往復が発生する点と合わせて document してください。
- **drain の上限は byte でなく message 数(64)。** mouse motion が大量に溜まっていると、その後ろの W は失われます。許容でよいですが、document してください。
- **重複していて無害な点。** W の dispatch 内の `forgetTkKeys`(`tcl.zig:246`)は、Tcl 側が先に U を送っているので重複です。害はありません。
- **ユーザーの TCL が `wm protocol . WM_DELETE_WINDOW` を上書きすると count は止まる。** これも document が必要です。
- **native 専用の setter。** Tk 選択中は WINDOW-KEEP-OPEN、WINDOW-CLOSE、WINDOW-CHANGES が native にしか効きません。`graphics.fs:346` のコメントはありますが、`docs/WORD_REFERENCE*` と COMPATIBILITY にも書いて、1326 で扱うことを明記してください。
- **細かい点。**
  - `Message` の doc comment(`tcl.zig:60`)と `sigma_tk.tcl` 冒頭の protocol 説明に U/W が入っていません。
  - `parseInt(u64)` が `+5` を受け付ける可能性があります。厳密にするなら数字だけを許可してください。

## Linux 実機で確認が必要な点

- `focus -displayof .` は X11 上で、他の app に focus が移ったときに "" を返すか(stale にならないか)。
- XWayland/GNOME での最小化が `wm state` で `iconic` として見えるか。見えない compositor では minimized が false になることを記録してください。
- fullscreen 中に閉じる → 次の SHOW で再表示、の流れ。
- `.sigma_ime` が focus を持っているとき、focused が true になるか。

## 必要なテスト

**fake process(Zig)で:**
- parseHeader: `W 0 n` を受け付け、code≠0、size 0、20 以上、数字でない text、maxInt(Cell) 超えを拒否する。
- delta: W1, W2 の後に query が 2 → closes = 2。W2 の重複 → 2。W を飛ばして query が 3 → 3。
- W が `TCL-EVAL` や `INKEY` の poll 中に届いても数えられる。
- 再起動: 2 回数えた後 TCL-STOP し、新しい wish から W1 → 3。
- TCL-STOP の drain:
  - buffer に溜まった W が残る。
  - read の途中で分割された W。
  - drain 中の protocol 違反で -265 になる(バグ2)。
  - drain 中の E/K で MemoryExhausted にならない。
- SAVE や restore の途中に partial W があっても count が残る。
- wish が動いていないとき 0 0 0 と観測済み count を返し、`process_start_fn` を呼ばない。
- Tcl error 時や host 喪失時は flag が false で count は維持し、`running` が false になる。
- interrupt と MemoryExhausted は伝播する。
- `TCL-EVAL` の結果 address と `TCL-ERROR$` が `WINDOW-OPEN?` の後も壊れていない(バグ1)。
- 公開 4 word の stack effect が native と Tk の両方で変わらない。DISPLAY-WINDOW では `GFX-WINDOW-CLOSES`(read mark)の経路を通る。
- word の順序と古い image の互換、help と translations の整合。
- 新しい State と SAVESYS 後の起動で count が 0。

**実機(`tests/scripts` の Linux 用 script、`DISPLAY-TK` を使用):**
- xdotool で close、minimize、focus 移動を行い、4 つの値と U が W より先に届くこと(KEY-HELD? が解除されること)を確認する。
- 閉じた後の SHOW で再び open になる。
- pending limit を超える負荷の下でも W が届く。

Windows(1295)と macOS(1299)の受け入れは未実施のまま、ということで合っています。

## 制御通知と終了処理の修正後

実際のバグ（Critical/High）は見つかりませんでした。ただし、Medium 1件と Low 数件を挙げます。ここで挙げた以前の修正6点は、いずれもコード上で確認できました。ファイルは読んだだけで、テストやスクリプトは実行していません。

## 問題なしと確認した点
- **パーサと途中で切れたメッセージ**
  - W は固定バッファで読み、ヒープを使いません。SAVE（`tcl.zig:117-130`）でも restore（`tcl.zig:78-85`）でも、読みかけの W がそのまま残ります。
  - 読みかけのヘッダも残ります。
  - 普通のメッセージを読みかけで捨てるときは `skip` に残りを足すので（`tcl.zig:94`）、次のメッセージの境界はずれません。
  - `discard_kind` が残るのは TCL-STOP の中だけで、その後の halt で必ず消えます。
- **後片付けの失敗**：`halt` が `cleanup_failed = !ended` を記録し、次の3か所で再試行されます。
  - `ensureRunning`（`tcl.zig:135`）
  - `stop` が動いていないとき（`tcl.zig:440`）
  - `stop` の最後（`tcl.zig:454`）

  stop 中のプロトコルエラーは、後片付けが成功したときも呼び出し元に返ります（`tcl.zig:456`）。
- **結果文字列の寿命**：`windowState` は R を受け取って自分で解放します（`tcl.zig:390-391`）。利用者の `result`/`error_text` には触れません。
- **閉じた回数の集計**
  - `window_closes_seen` は wish を起動したときだけ 0 に戻します（`tcl.zig:140`）。
  - 値が増えたときだけ差分を足し、上限で止めます（`tcl.zig:370-375`）。W とスナップショットの両方で同じ回数が来ても、二重には数えません。
  - 同じ State への restore では値が残り、fresh image では 0 から始まります。どちらもテスト（`graphics_test.zig:3415-3434`）の通りです。
- **Tcl 側**：W の送信とキー解放を `catch` してから withdraw しています（`sigma_tk.tcl:97-104`）。W は送信待ちの上限でも捨てられません（`sigma_tk.tcl:26`）。

## 指摘

**[Medium] 状態を問い合わせる R の応答が論理ヒープに置かれる**（`tcl.zig:259-262`、`tcl.zig:386-389`）
- 利用者がヒープを使い切った状態で Tk 選択中に `WINDOW-OPEN?` などを呼ぶと、`heapAllocate` が失敗します。そのとき次の2つが起きます。
  - `halt` で wish が止まり、Tk ウィンドウが消えます。
  - `MemoryExhausted` が例外として上がります。
- 以前は `GFX-WINDOW-FLAGS` を見るだけで、メモリは確保しませんでした。そのため、ループで `WINDOW-CLOSES` を見張るプログラムには挙動の後退になります。
- 応答は最大でも「1 1 1 <19桁>」程度です。W と同じように、固定バッファで受けるのが自然です。

**[Low] TCL-STOP の上限（64件）を超えた後ろの W が数えられない**（`tcl.zig:446-453`）
- 読まれていないマウス移動などが 64 件より多く溜まっていると、その後ろの W は捨てられます。
- 文書の「受信済みの閉じた回数は残る」とは矛盾しません。ただ、ヘルプか `graphics.fs:345-347` に、TCL-STOP は上限までしか読まないことを書いておくと誤解がありません。

**[Low] stop 中に `lost()` が起きると `process_stop_fn` が2回呼ばれる**（`tcl.zig:158` と `tcl.zig:454`）
- `lost()` 内の `halt` で後片付けに失敗すると、最後の `halt` がもう一度呼びます。
- テストの偽物では問題になりません。本物のホストの stop 関数が2回呼んでも安全かどうかは確認していません。

**[Low] 値を積む途中で失敗すると中途半端な状態になる**（`words_graphics.zig:371`）
- 4値を積む途中でデータスタックがあふれると、一部だけ積まれた状態で止まります。
- 閉じた回数は先に記録済みなので、実害はほぼありません。

**[Low] テストが足りない部分**（`graphics_test.zig`）
- poll で E を読みかけのまま TCL-STOP し、その後ろに W が続く場合。
- 読み捨ての上限（`tcl.zig:219` の 65536 バイト）を超える場合。
- 読みかけの普通のメッセージがある状態で SAVE し、その後に W が来る場合。

**[Low] `verify-linux-tk-state.py` の待ち方が不安定になりうる**
- 状態の変化を待つ繰り返しがなく、0.2秒と 300 MS の決め打ちで待っています（65行目、99行目）。デスクトップが遅いと失敗しうるつくりです。
- 129行目の `minimized` で `held==0` を期待しているのは、最小化したときに WM が FocusOut を送る前提です。WM によっては成り立たないかもしれません。
- それ以外の期待値の流れ（1→1→2→2→2→3→4、終了後に `tcl=0`、SAVESYS 後の fresh で全部 0）は、コアの意味と合っています。

## 固定応答とLinuxのWM照合後

残る問題は軽微なものだけで、Medium以上の不具合は見つかりませんでした。ただし、ホストコールバックの意味がドキュメントの説明（「補う」）と合っていない点が1つあります。

## 指摘

**1. Low〜Medium：コールバックがTkの判定を両方向に上書きしている**（`src/core/tcl.zig:427-431`）
- `values[2] = @intFromBool(minimized)` なので、WM_STATEが通常または非表示（1/0）なら、Tkが `iconic` と答えていても「最小化していない」に変わります。
- ドキュメント（`docs/GRAPHICS_AND_SOUND.md:85,159`、`ja.md:85,159`）は「Tkのキャッシュを補う／加えて照合」と書いており、実装と合いません。
- タイミング競合が起きます。`wm iconify .` の直後はTkの状態がすぐ `iconic` になりますが、WMがWM_STATE=3にするまでは「最小化していない」と返ります。
- 単体テスト `src/tests/graphics_test.zig:3552` は true の場合だけで、false で上書きする経路はテストしていません。
- 対応案は2つです。
  - true のときだけ反映する：`if (minimized) { values[2]=1; values[1]=0; }`
  - 「WM_STATEを優先する」とドキュメントに明記する。

**2. Low：問い合わせのたびに新しいX接続を開いている**（`src/host_display_linux.zig:42-68`）
- 毎回、接続、InternAtom、最大32段の GetProperty と QueryTree を同期で行います。上限は2秒なので、正しさの問題ではありません。
- 4つのTk状態語はどれも `GFX-TK-WINDOW-FLAGS` を通ります（`graphics.fs:350-357`）。そのため最小化を必要としない `WINDOW-CLOSES` や `WINDOW-OPEN?` でもこの処理が走ります。フレームごとに呼ぶと負担になり、Xサーバーが止まると1回につき最大2秒止まります。
- 対応案：ウィンドウIDと祖先の対応をキャッシュするか、MINIMIZED/FOCUSED のときだけ問い合わせます。

**3. Low：96バイトを超えるR応答でwishごと停止する**（`src/core/tcl.zig:270`）
- 正規の応答は最大でも約46バイトなので、通常は起きません。
- 利用者が `sigma_window_state` を再定義した場合や、code 1 の長いエラー文が返った場合は、`lost()` でwishが止まり、利用者のTkセッションが失われます。
- 対応案：`tcl.skip = header.size` で読み捨てて、noWindowを返せば停止せずに済みます。

## 問題なしと確認した点
- **固定応答のパーサーと寿命**：`fixed_text` は `request` が返った直後に読まれ、その間に他の読み取りはありません。`fixed_result` は `defer` で戻ります（`tcl.zig:369`）。エラー時は errdefer の `halt` から `resetReading` が `fixed_pending` を消します（`tcl.zig:119-121`）。SAVE/restore は fixed にも `close_pending` にも触れません（`dropPartial` は `partial` だけを扱います）。
- **W制御**：19バイトの固定バッファです。`closeCount` が数字だけかを確かめ、`maxInt(Cell)` で上限をかけています（`tcl.zig:218-223,285-294`）。
- **境界とエラー処理**：
  - IDは0とu32を超える値を拒否します。
  - GetProperty は応答長36以上、format 32、型がWM_STATE、要素数が0でないことを確かめます。
  - QueryTree は応答長32以上で、親が0・root・自分自身なら null です。
  - 32段で打ち切ります。
  - X Error や転送されたDISPLAYでは null になり、Tkの値にフォールバックします。
  - `src/main.zig:3746` は Linux、graphics、x11 がそろう場合だけ設定し、それ以外は `host_display.zig:30-33` が null を返します。
- **容量ガード**（`src/core/words_graphics.zig:371`）：問い合わせの前に4セル分の空きを確かめるので、副作用の後にオーバーフローすることはありません。
- **Tcl側**（`src/graphics/sigma_tk.tcl:84-104`）と **`graphics.fs`**：スタック操作は正しいです。`[winfo id .] + 0` は10進数になり、`(TK-WINDOW-ID)` の読み取りと合っています。

## ドキュメント（Nit）
- `GRAPHICS_AND_SOUND.md:159` と `ja.md:159`：「Windows1295 and macOS1299」は空白がなく、番号が何を指すか分かりません。「Windows (tque 1295) / macOS (tque 1299)」のような書き方が良さそうです。
- `md:85` と `ja:85`：「補う／加えて」の表現は指摘1と合わせて直す必要があります。
- `md:249` と `ja:249`：TCL-STOPの説明「未読分は捨てる」は、157行目の「閉じる通知は記録する」と少し食い違います。157行目を参照させる程度で足ります。
- 上の点を除けば、157行目（64件・64 KiB/read）を含め英語版と日本語版の内容は一致しています。

`verify-linux-tk-state.py` は手順の構成とWM_PROTOCOLSの祖先探索を確認し、問題はありませんでした。`verify-linux-display-contract.py` の修正部分は詳しく読んでいません。

## 指摘3点の最終再確認

**結論：3点とも妥当です。ブロッカーになる欠陥はありません。**

1. **WM_STATEの優先（`src/core/tcl.zig:431-436`）：妥当**
   - `window_minimized_fn` が値を返したときは、true でも false でもそれで `values[2]` を上書きします。null のときだけTkのキャッシュを使います。
   - `windowMinimized`（`src/host_display_linux.zig:42-72`）は、WMが管理する祖先ウィンドウまでたどってWM_STATEを読みます。値が3ならtrue、0か1ならfalse、それ以外と失敗はnullです。
   - テスト（`src/tests/graphics_test.zig:3551`）は、ID 123（true）、456（false）、789（null）の3通りを確認しています。
   - 英語版・日本語版のドキュメントとも、WM_STATEを優先することと、最小化要求の直後は偽になりうることを書いています。

2. **96バイトを超えるRの応答：妥当**
   - `tcl.zig:269-274` で `skip` と `discard_kind='R'` を設定します。その後の `continue`（`tcl.zig:288`）で本文を読み捨て、`fixed=false` のメッセージを返します。
   - `windowState` は `!message.fixed` を見て `noWindow` を返します（`tcl.zig:423`）。
   - この経路では `halt` を呼ばず、ユーザーの result や error の欄にも触れません。読み捨て中に失敗した場合だけ、従来どおり `lost` になります。
   - テスト（`graphics_test.zig:3631`）では、次の問い合わせが正常に動くこと、result の "original" が残ること、`process_stops == 0` を確認しています。

3. **`stop()` の再試行：妥当**
   - `lost()` を通ったときは `running=false` になっています。そのため `tcl.zig:491` は `halt` を呼び直さず、`!cleanup_failed` で結果を判定します。
   - 後片付けの失敗は記録したまま、次の `stop` か `ensureRunning`（`tcl.zig:145`, `tcl.zig:477`）で再試行します。
   - テスト（`graphics_test.zig:3534`）は `process_stops == 1` で回数を確認しています。

**残っている問題（Low）**
- **競合中のフォーカス：** 最小化を要求した直後で、TkのキャッシュはiconicなのにWM_STATEがまだNormalの間は、`WINDOW-FOCUSED?` も偽になります。`sigma_window_state` がキャッシュでiconicを見た時点でfocusedを0にする（`src/graphics/sigma_tk.tcl:91`）のに、Zigの側はWM_STATEがfalseのときにフォーカスを計算し直さないためです。ドキュメントはこの間の最小化の偽にしか触れていません。直すなら、ドキュメントに「フォーカスも偽になりうる」と1行足すのがいちばん軽い方法です。
- **テストの不足（欠陥ではありません）：** `graphics_test.zig:3637` では、大きすぎる応答を受けた最初の `WINDOW-OPEN?` の結果を `DROP` で捨てていて、0になることを確かめていません。また、`R 1` の応答でも `error_text` が変わらないことを確かめていません。
