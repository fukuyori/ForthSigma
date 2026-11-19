# 638 固定スナップショットレビュー原文

2026-11-19、読み取り専用。レビュー時点の指摘であり、現状の未解決一覧ではない。実行結果と採否は638-review-response.mdおよび実装記録を参照。

## 依頼

```text
Final fixed-snapshot638 review, read-only. Review ONLY .work/638-review/frozen/src/core/{event_input,standard_event,input_redirect,words_xchar,words_files,host_interface}.zig and frozen/event_queue_test.zig. This snapshot fixes pushback-result items: canonical rawDecoder bytes precede legacy pending; checked beforeBytes flushes legacy then decoder via beforeFileRead. No-checked mixed case leavesbytes in core; nextKey rawKey prioritizes Decoder. New typed XKEY/line unread prepends to Decoder instead of old pending_key (putByte), preserving order. Returning buffer byte3 outsidepaste nowinterrupts. Paste clears after successful transfer/byte consumption; failed checked rejection leaves it. Test peek KEY yieldsXYZ bothchecked/no-unread, XKEY invalid continuation preservesFF Q, atomic rejection and voidacceptederror do notduplicate. stdin-file-stdin shares oldlegacy too. ExplicitSTDIN file read/query helpers see buffereddecoderbytes; legacyhosts no standard_event_fn remainunchanged. Tests latest Win23steps/core1050pass8skip/host96pass11skip +nativeconsole3 +old36+6378+ConPTY, Linuxcore/host/runtimeand13newPTY13oldPTY/NSpassed, Maccross14steps, matrixrunning. Seek only remaining material acceptance/order/dataloss regressions under valid callbacks (checked pushback error=>notaccepted; voidlegacy implies acceptance), not cosmetic or malformed host behavior. No changes/commands. Japanese concise, distinguish actual defect from speculation.
```

## 原文

## 結論

凍結スナップショット6ファイルと `event_queue_test.zig` の範囲で、有効なコールバックでも起きる順序の不具合を1件見つけました。依頼された pushback 修正（checked/void の受理判定、decoder→legacy の順序、paste のクリア、XKEY/行の unread）は、コードを追った範囲では正しく動いています。コマンドは実行していません。

## 実際の欠陥

**1. 押し戻した後も `eof` フラグが core に残り、EOF がバイトより先に出る（順序の欠陥）**

- 場所: `event_input.zig:167-192`（`beforeStdinBytes`）と `standard_event.zig:155-160`
- `beforeStdinBytes` は decoder のバイトをホストへ押し戻した後、`length`・`escape_at`・`paste` はクリアしますが、`standard_input.eof` はクリアしません。
- `standard.read` は `length == 0 && eof` のとき `.eof` を返します。このときホスト側に押し戻したバイトが残っているかは確かめていません。
- 再現手順（パイプ入力のように、EOF 後も毎回 EOF を返すホストを想定）:
  1. ホストが `ESC` `[` と送った後に EOF を返す。
  2. `EKEY?` で peek すると、`ESC` と `[` を読み、EOF を受けて `eof=true` になる。parse は `ended` 扱いで `scalar(27,1)` を返し、2バイトとも decoder に残る。
  3. `KEY` を実行すると `beforeBytes` → `beforeFileRead` で2バイトがホストへ押し戻され、`KEY` は `ESC` を受け取る。
  4. 次の `EKEY` では decoder が空で `eof=true` なので `.eof` を返し、`eof` もクリアされる。
  5. その次の `EKEY` で `[` が出て、その後にまた EOF が出る。
- 結果: プログラムには「ESC → EOF → `[` → EOF」の順で見えます。EOF がバイトより先に来て、しかも2回出ます。UTF-8 の途中（`E3 81` の後に EOF）でも同じことが起き、`READ-LINE`/`READ-FILE` の STDIN 経由でも起きます。
- checked（`unread_byte_fn`）と void（`unread_fn`）の両方の経路で起きます。unread を持たないホストでは decoder の中で `takeByte` するので起きません。
- 直し方の候補: 押し戻すときに `eof` を残したまま decoder を空にしない、または押し戻しとあわせて EOF をどう扱うかを決める。ホストの EOF が一度きりかどうかで正しい処理が変わるため、修正の前にどちらの方針にするかを決めてください。

## 推測を含む指摘（欠陥と断定はしません）

**2. EOF だけを peek した後に KEY を実行すると、その EOF が KEY に見えない**※推測です
- decoder が空で `eof=true` の状態（`EKEY?` の peek が `.eof` を受けて false を返した後）で `KEY` を実行すると、`beforeStdinBytes` は何もせず `key_fn` を呼びます。
- ホストの EOF が一度きり（コンソールの Ctrl-Z/Ctrl-D のような形）の場合、`KEY` は次の入力を待ち続けます。後で `EKEY` を呼ぶと古い EOF が返ると推測されます。
- 実際に起きるかは、ホスト側 EOF の仕様次第です。今回の範囲のファイルでは確認できないため、未確認です。

**3. void のみのホストで legacy pending が残っていると、STDIN の明示読み取りが `HostUnavailable` になる**（データは失われない）
- 場所: `event_input.zig:208-209`
- legacy の押し戻しには `unread_byte_fn` が必須なので、void の `unread_fn` しか持たないホストでは、受け取れる状況でもエラーで拒否します。状態は保たれるので、データの消失や重複はありません。
- 起きるのは stdin→file→stdin の入れ子で legacy が残っている場合だけと推測されます。仕様どおりなら問題ありません。

**4. `KEY?-FILE` を STDIN に使うと legacy pending を見落とす**（readiness の誤りのみ）
- 場所: `words_files.zig:80`
- 判定しているのは `standard_input.length` だけで、`pending_key` や `pending_event_count` は見ていません。このため `KEY-FILE` ならすぐ読めるのに `KEY?-FILE` が false を返すことがあり得ます。順序やデータの問題ではありません。

## 設計どおりと判断し、指摘から外したもの

- **未完成の ESC/UTF-8 より deferred の特殊イベントが先に出る件**: テスト「completed native resize does not split an unfinished escape sequence」で明示されている仕様です。
- **バイト API で paste 中に `paste=false` になる件**: その後の paste の中身にある `0x03` は割り込みになり得ますが、宣言された設計の範囲です。

1 の扱いを決めていただければ、tque への登録と修正方針の整理を進めます。
