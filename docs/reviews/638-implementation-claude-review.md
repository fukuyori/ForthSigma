# 638 実装レビュー原文

2026-11-19、読み取り専用。実行結果や採否とは区別する。

## 依頼

```text
Read-only implementation review for task638. Read docs/EVENT_QUEUE_DESIGN.md (original proposal; design review .work/638-review/design-result.json is being incorporated), src/core/standard_event.zig, event_input.zig modern/sourceRead/beforeBytes, standard_sequence.zig, words_extension.zig EKEY-WAIT/MOUSE, input_redirect.zig, graphics_input.zig readInput, host_interface.zig new source callbacks, host_input.zig nextStandardPacket, main.zig terminalStandardEvent and terminalUnread, src/tests/event_queue_test.zig. Design findings adopted: host passes byte3 unchanged; raw bytes retained and peek no semantic commit; complete event wins over deadline after read; byte API flush, GRAPHICS clears paste without throwing; selected file must not decode ESC and must preserve ior. Legacy callback path remains unchanged. Existing pending legacy fields remain for compatibility instead of merging/removing. Whole native timeout and source Clock/Deadline shared. Check concrete bugs, loss/order, recursion between beforeBytes and sourceRead, EOF and INFILE-EXECUTE, error classifications, deadlines (ms=0 should drain immediately available prefix), SGR and Windows mouse, restart semantic state. Do not change files or execute commands. Identify remaining defects with exact remedy, Japanese. Tests ongoing; previous legacy suite passed before newest fixes.
```

## 原文

レビューが終わりました。ファイルの変更とコマンドの実行はしていないので、テストとビルドの結果は未確認です。指定ファイルはすべて読みました。

## 結論
採用済みの設計指摘のうち次の項目は、実装と合っています。
- 完成イベントは読取り後の期限切れより優先される
- ms=0 は、すぐ読める範囲の途中列を読み切ってから timeout を返す
- 先読みは状態を確定しない
- GRAPHICS は貼り付け状態を例外なしで解除する
- 選択ファイルでは ESC を復号せず、ior を保持する

`beforeBytes` と `sourceRead` の間に再帰はありません。`sourceRead` は `nextKey` も `input_redirect.ready` も呼ばず、`beforeBytes` から呼ぶのは unread 系だけです。

残っている欠陥は次のとおりです(重要度の高い順)。

## 欠陥と修正方法

**1. 選択ファイルで EKEY? の後に KEY/ACCEPT/KEY? を使うと、複数バイトの ungetc に依存する(中)**
- 場所: `event_input.zig:192-197`、`main.zig:917-920`
- 何が起きるか: EKEY? の先読みで、デコーダーは最大4バイト(UTF-8の1文字)を持ちます。`beforeBytes` はそれを `fileUnread` で1バイトずつ返しますが、`fileUnread` の中身は `ungetc` です。C 標準が保証する押し戻しは1バイトだけで、2バイト目以降は CRT によって失敗し HostFailed になり得ます(※推測です。MSVCRT の実際の挙動は未確認)。
- 修正: 選択ファイルのときは、`beforeBytes` でファイルへ unread しないでデコーダーに残します。
  - `input_redirect.byte()` と `line()` は先に `standard_input.takeByte()` から読む。
  - `input_redirect.ready()` の選択ファイル側でも `standard_input.length != 0` なら true を返す。
  - `line()` の 73行目にある `return error.HostUnavailable` を削除する。

**2. unread_fn のない埋込みホストでは、EKEY? の後の ACCEPT が -21 になる(低〜中)**
- 場所: `input_redirect.zig:73`
- 修正案は2つあります。
  - 推奨: `line()` でデコーダーのバイトを先にバッファへ移します。改行に達したらそこで返し、残りだけを `read_fn` で読みます。
  - 代案: `standard_event_fn` があるのに `unread_fn` がない構成を、`modern()` で HostUnavailable として拒否します。

**3. 先読み(peek)でも EOF フラグを消している(低)**
- 場所: `standard_event.zig:141`
- 何が起きるか: EOF を毎回は返さないホストでは、EKEY? が false になった後の EKEY が EOF を失い、待ち続けます。
- 修正: `self.eof = false;` を `if (!peek) self.eof = false;` に変えます。

**4. restart で消す状態が過不足している(低〜中)**
- 場所: `standard_event.zig:166-169`
- 何が起きるか:
  - `buttons` が残る。cooked モードの間にボタンを離すと SGR の離す報告が届かないため、その後の motion 報告で押下中のままになる。
  - `escape_at = null` で ESC の 50ms 待ちが延びる。これは設計の「延長しない」に反する。
- 修正: `.restart => { self.paste = false; self.buttons = 0; }` に変え、`escape_at` は消しません。

**5. SGR の拡張ボタン(code & 128、ボタン8〜11)を左・中・右と誤認する(低)**
- 場所: `standard_event.zig:62-79`
- 修正:
  - `code & 128 != 0` のときは `ignored = true` にする。
  - 合わせて、ボタンを押したままの motion(`code & 32 != 0 and code & 64 == 0 and code & 3 != 3`)では `buttons |= bit` として、押下報告が抜けた場合に回復できるようにすることを推奨します。

**6. 標準経路でホストが Ctrl+C を THROW する経路が残っている(低)**
- 場所: `main.zig:1998`(`terminalBufferedKey` は byte 3 で UserInterrupt を投げる)、`event_input.zig:173`(`sourceRead` も同じ関数を呼ぶ)
- 何が起きるか: 採用した指摘「byte 3 はホストがそのまま渡す」に反し、`source.interrupts` と paste の判定を迂回します。到達するのはバイト API を挟んで lookahead に 3 が戻ったときに限られます。
- 修正:
  - `terminalStandardEvent` では `popLookahead()` を直接使い、`stdin_eof = false` にして byte 3 もそのまま返す。
  - `sourceRead` の `buffered_key_fn` 呼出しは、ホストの `standard_event_fn` が lookahead を処理するので削除する。

**7. 先読み中に「無視するマウス列」(横ホイール)を消費している(低)**
- 場所: `standard_event.zig:125-128`
- 何が起きるか: EKEY? の先読みで生バイトが消え、その後の KEY では見えません。
- 修正: peek のときはデコーダーの状態を変えずに、その列の後ろから解析を続けます(位置を表す引数を `parse` に追加)。採らない場合は、無視列は KEY でも見えない仕様として設計書に明記してください。

**8. INFILE-EXECUTE から戻るとき、内側デコーダーの先読みバイトを捨てている(低)**
- 場所: `input_redirect.zig:29-37`
- 何が起きるか: 内側のファイルでは位置が進んだまま、そのバイトが失われます。旧 pending 系も同じ挙動です。
- 修正: `defer` の復元前に、`changed` で内側の `standard_input.length != 0` なら、内側ファイルへ戻す処理を best-effort で行います。1と同じ制約を受けるので、1を先に直してください。

## 判断が必要な点(欠陥ではなく、方針の確認)
- **エラーの分類**: 選択していない stdin で読取りエラーが起きると、EKEY と EKEY? は `error.HostFailed` を投げます(`event_input.zig:58,75`)。一方、EKEY-WAIT は ior を返します。従来の stdin 経路と同じ扱いなので仕様どおりとも言えますが、EKEY は ior を THROW するという設計文言に合わせるなら、選択の有無にかかわらず `throwCode(ior)` にします。
- **イメージ復元**: `image_restore.zig:25` は、端末から既に読んだ生バイトと deferred のイベントも捨てます。設計どおりですが、打鍵が失われます。残すなら、`apply` で初期化するのを paste/escape/buttons/last_mouse に限り、bytes/length/deferred は保持します。
- **restart フラグの共有**: `host_input.zig` の `restarted` は1つのフラグで、`next()` と `nextStandardPacket()` が取り合います。EKEY が先に取ると、GRAPHICS は保持中のキーを捨てません。この挙動が旧 `nextStandard` から既にあったかどうかは未確認です。

## 問題なしと確認した点
- ms=0 の動作、ESC のタイムアウトが呼出しをまたいで延びないこと、deferred が1個に収まること、32バイトの上限(assert には到達しない)
- EOF で途中の UTF-8 と途中の終了マーカーを確定すること、paste 中の Ctrl+C を文字として扱うこと
- Windows のマウス(ボタン 1/2/4、ホイール、横ホイールの無視)
- EKEY-WAIT が消費前に3セル、EKEY-MOUSE が4セルの余地を確認していること
- terminalUnread の容量(64+1)は、デコーダーからの最大32バイトに足りること
- `nextStandardPacket` の `standard_keyboard = true; enter()` の重複は無害です。削除してよいです。

なお、テストスイートの現在の結果は、私は実行していないため未確認です。
