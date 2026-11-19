# 652 設計レビュー原文

2026-11-20。固定コピーの読取り専用レビュー。

設計書（`.work/652/design-review/design.md`）を既存コードと照合しました。読み取りのみで、ファイルは変更していません。高 4件・中 7件・低 2件があり、どれも既存の決定の範囲で解決方法を決められるので、新しく確認していただく事項はありません。

最も大きい問題は 6節の入力保持です。`deferred_packets` と `nextStandardPacket` を流用する案は、KEY・FILE・GRAPHICS の読み取りと噛み合いません（H1）。

## 高

### H1. Raw 入力を `deferred_packets` と `nextStandardPacket` で保持する案は成り立たない
- `nextStandardPacket` は `enter()` を呼びます（`src/host_input.zig:172`）。cooked の端末を raw に切り替えてしまいます。
- 同じ関数は、ほかにも状態を変えます。
  - `standard_keyboard=true` にする。これで `leave()` の flush の判定が変わる（`host_input.zig:263`, `339`）。
  - 世代リセットと resize を取り出して消費する。
  - Windows では `next(true)` が console mode に 0x0008 を立てる（`host_input.zig:570`）。
  - Windows では `press`/`down` を更新せず、`key_release` と focus を捨てる（`host_input.zig:185`）。このため、GRAPHICS 用のイベントは packet から正しく作り直せません。
- `deferred_packets` を読むのは `terminalStandardEvent` だけです（`src/main.zig:3137`）。次の経路は読みません。
  - KEY（`readByte`、`main.zig:3047-3056`）
  - FILE（`stdinProbeByte`、`fileStdinByte`、`main.zig:1396`, `1880`）
  - GRAPHICS（`inputEvent` から `host_input.next`、`main.zig:3226`）
  
  このため、保持した文字が後から来た入力に追い越されるか、届かなくなります。
- さらに、`deferred_packets` が満杯だと `stdinProbeByte` は EIO を返します（`main.zig:1402`）。

**解決：保持はデコードの手前で行う。**
- **POSIX**
  - raw の byte を `host_input.queued` に積みます。KEY・FILE・EKEY・GRAPHICS のどの読み取りも、すでに `takePendingByte` でここを先に読みます。
  - poll は `input_is_terminal and isRaw()` のときだけ動かし、`enter()` は呼びません。fd 0 から空き容量分だけ `read` します。
  - 空きは 32 byte 残します。DSR の応答（`cursor()`）と、Windows の `pending` を queue に移す分のためです。`queue()` は満杯になると黙って捨てるので（`host_input.zig:138`）、この余白が必要です。
- **Windows**
  - `host_input.windows` に INPUT_RECORD の ring（64件）を設けます。`next()` は、`GetNumberOfConsoleInputEvents` と `ReadConsoleInputW` より先に ring を読むようにします。
  - poll が読むのは record だけです。デコードはせず、`down`/`pending`/mode にも触れません。
  - 読む条件は `queued_len + 4*(ring_len+1) + 32 <= 256` とします。1 record から出る UTF-8 は最大 4 byte だからです。
  - `leave()` での扱い：
    - `standard_keyboard` が偽のとき：ring も消します。`FlushConsoleInputBuffer` と同じ扱いです。
    - 真のとき：ring の文字を UTF-8 にして `queued` へ移し、文字以外の record は捨てます。cooked の `ReadConsoleW` が文字以外の record を無視するのと同じ扱いです。
- `deferred_packets` は今の用途のまま残し、背景の poll では使いません。

### H2. 中断印が消費されず、EXEC の中で -28 が繰り返される
- `inputInterrupted()` は印を消費しません（`src/host_wait.zig:256`）。消費するのは depth が 0 に戻ったときの `endInput` だけです（`host_wait.zig:265`）。
- EXEC が depth を保持している間に一度 Ctrl+C が来ると、そのあと次の箇所がすべて即座に -1 または -28 になります。`' KEY CATCH` を回すループは止まらなくなります。
  - `rawStandardInputByte`（`main.zig:2392`, `2395`, `2407`）
  - `readByte`（`main.zig:3038`, `3057`）
  - EXEC の poll
- また `NativeScope.begin` は印を消します（`host_wait.zig:172`）。

**解決**
- `host_wait.takeInterrupt()`（swap で消費）を追加します。
- Forth へ -28 を渡す箇所で消費します。対象は `latchInput(error.UserInterrupt)` と、`inputInterrupted()` の後の `return error.UserInterrupt` です（`main.zig:1328`, `1371`, `1545`, `1682`, `1837`, `2075`, `2150`, `2255`, `2263`, `2309`, `3039`, `3058`）。
- ループを抜けるための判定は、消費しない今の形のままにします。
- EXEC の poll も swap で消費します。

### H3. EXEC の中の NS と音は、今のままでは borrow できない
- `beginInput` は `signal_broker.fallback`（owner 1）を使います（`host_wait.zig:252`）。
- NS は runtime 側の broker を使うので、`process_owner` の gate で HostFailed になります（`host_signal_broker.zig:26`）。音の待機は `.host_failed` になります。今あるテストもこれを期待しています（`host_wait.zig:458`）。

**解決**
- `host_wait` に `exec_depth` を追加します。EXEC の begin は `beginInput()` を直接呼び、続けて `exec_depth += 1` とします。`beginInputGuard` の `wanted & 5` の条件は通しません。
- `waitUsing` と `audioWait` は、`exec_depth != 0` なら `beginNative` を呼ばず、`active` による入れ子の拒否だけ残します。
  - 割込みは `takeInterrupt` で確かめます。
  - Raw のときは、20ms ごとに EXEC の begin で登録した poll callback を呼びます。
  - 印は消しません。
- EXEC の外でのふるまい（入力ガード中の NS が拒否されること）は変えません。

### H4. 予算の owner と -280 THROW の区別
- `-280 THROW` は `error_codes` をたどって StepLimit になります（`src/core/words_system.zig:274`）。設計書の「owner なし＝CLI」では、利用者の THROW と CLI の上限を区別できません。
- owner を消す時点が決まっていないので、前回の値が残って、別の入口が誤って ior に変えるおそれがあります。

**解決**
- StepLimit を出すすべての箇所で owner を明示的に設定します。
  - counted ループ（`src/forth.zig:1921`）と `checkWorkBlock`：尽きた入口の index、または CLI
  - `.throw` の -280：none
- 入口は `owner == 自分の index` のときだけ -280 の ior に変え、変えた時点で none に戻します。`report` と `resetSteps` でも none に戻します。
- `-280 THROW` は既存の決定どおり CATCH を通り抜けます。その結果、`EXEC-LIMITED THROW` で受けた -280 は捕捉できない停止になります。このことを設計書に明記し、テストにも入れます。

## 中

### M1. Ctrl+C の位置を byte 数から求める方法は誤る
次の場合に計算が合わなくなります。
- 非 byte の packet が `deferred` に入る（`src/core/standard_event.zig:185`）
- `.restart` がある
- `pending_event_bytes` が末尾から取り出される（`src/core/event_input.zig:144`）
- 最初から `bytes[0]==3` になっている
- Windows では 1 record から複数の byte が出る

**解決**
- replay の source は、各 item について（層、index）を持ちます。arrival の 3 では `read` がその場で UserInterrupt を返すので（`standard_event.zig:178`）、「最後に渡した item」がそのまま Ctrl+C の位置です。
- 削除するのは host の層（`queued` と ring）にある 3 だけです。それより前の層にある 3 は、paste の判定にだけ使い、各読み取りの既存の規則に任せます。
- replay の層の順序は次のとおりです。
  1. clone の bytes/deferred
  2. `pending_key`
  3. `pending_event_bytes`（末尾から）
  4. `pending_standard_event`
  5. `deferred_packets`
  6. `lookahead`、`unread_bytes`（末尾から）
  7. Windows の utf8 の pending
  8. 世代差の restart（読み取り専用の accessor を追加）
  9. host の層
- clone では `peek=false` で `read` します。peek では paste の状態が進まないためです。
- 割込みの判定は `writer.standard_interrupts` だけを使います。
- replay は source が尽きるまで回します。`.timeout` だけで止めません。
- 処理を軽くするため、host の層に 3 がなければ replay しません。
- `standard.read` が実行中のとき（`modern` の中）は、replay しないフラグを立てます。

### M2. POSIX では EXEC の間ずっと EINTR が出る
`sigaction` の flags が 0 で SA_RESTART がないので（`host_wait.zig:117-120`）、計算中の任意の OS 呼び出しが EINTR を返します。

**解決**
- EXEC が最初の所有者になるときは、`NativeScope` に `restart=true` を持たせて SA_RESTART で入れます。設計書の「OS呼出しはpreemptしない」とも合います。
- 入力の 20ms poll ループと NS の nanosleep は SA_RESTART を付けても再開されません（signal(7) の記載による）。そのため中断の遅れは今と同じです。macOS は未確認です。

### M3. 解釈実行は数えられない
EVALUATE の中の `[BEGIN] [AGAIN]` などは予算の単位に入らないので、上限にも Ctrl+C にもかかりません。

**解決**：`exec_depth` が 0 でない間は、解釈 loop の語の dispatch ごとに 1 を charge します。

### M4. 入口の順序と、エラーの優先順位
次の順にします。
1. 検査
2. 入口の dispatch を charge する（CLI には計上しない）
3. host の begin
4. ここまで成功したら xt と u を pop する（3 までの失敗では引数が残る）
5. 予算を push して実行する
6. 予算を pop する。終了と例外のどちらでも、host の end より先に行う
7. host の end

結果の優先順位は次のとおりです。
- 最優先は end の失敗（HostFailed）
- 次に xt から伝わる例外。このとき残っている印は外側で消費して捨てる
- 0 または -280 で戻り、印が残っている場合は -28

-280 への変換には `handleError` を使えません。StepLimit のときは先に戻ってしまうためです（`words_system.zig:125`）。同じ復元を行う関数を別に追加します。

### M5. 全段の charge は O(depth) になる
**解決**：単調な `exec_count` と、`next_stop = min(各入口の期限, 次の poll)` を使います。1命令あたりの処理は比較 1 回です。期限は飽和加算で求めます。同時に尽きたときは、CLI、外側の順で選びます。

### M6. Windows の `leave()` で ring を変換すると、cooked の行編集を通らない
raw の間に受けた Backspace などが、そのままの byte として渡ります。POSIX でも同じことが起きます。OS 側の既存のふるまいと違うかどうかは未確認（※推測）なので、試験項目に入れます。

### M7. EXEC の中では cooked の読み取りも guard 付きになる
`inputGuardActive()` が常に真になるので（`main.zig:2390`）、cooked の Ctrl+C も -28 になります。これは目的どおりの変化です。試験に明示します。

## 低
- **画像**
  - 実行中に復元が走る経路は LOAD だけでした。LOAD は別の State を作り、`restoreFreshImage` と `appendImage` を行います（`main.zig:2787-2795`）。
  - 予算のフィールドは、画像のエンコードにも、`image_restore.apply` にも含めません。
  - その別の State は同じ writer を共有するので、`init`/`restore` から ExecutionOps を呼ばないことを規則にします。
  - テストとして「EXEC の中で LOAD した後でも -280 になる」を追加します。
  - `appendImage` の全体はまだ読んでいません（未確認）。
- **ネイティブの hook**：`checkWorkBlock` の呼び出し元 15 箇所は、すべて `try` で伝えています。-28 が増えたときの後始末は、各所で監査します。
