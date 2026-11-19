# 638 最終指摘の再レビュー原文

2026-11-19、読み取り専用。レビュー時点の指摘であり、現状の未解決一覧ではない。実行結果と採否は638-review-response.mdおよび実装記録を参照。

## 依頼

```text
Focused final638 follow-up, read-only. In final-result.json all6items are addressed: (1) host_input.nextStandardPacket POSIX now directly consumes queued/std.c.read, never next(); unit standard restart leavesGRAPHICSrestart. (2) stdin Decoder is no longer swapped by INFILE-EXECUTE; byte/line/KEY-IOR paths gate access on selected()==null; nested stdin-file-stdin unit added. (3) fallback CR only reads next byte when pending/ready. (4) deferred noncharacters explicitly remain forEKEY acrossbyteAPIs, like legacy. (5) native event can complete ahead of partial rawbytes, preserving ESC/UTF8 and escapeage; parser no longer treats deferred asEOF; unit WINCH between ESC[ andA returnsWINCH thenUP. (6) KEY? never flushes/clears Decoder, beforeBytes preserves escapeage until actual byte transfer/consumption. Also Windowsfocusrelease recursion replacedbybounded releaseNext helper so notification flood cannot bypass32-recordlimit; uncaught diagnostic cancels paste. Read these functions plus tests newcases and identify only remaining concrete bugs/regressions. Don't re-open deliberate documented boundaries (stdin-only wait1078, excludedmousemessages filteredevenpeek, native deferred persists). Do not modify/execute. Japanese concise.
```

## 原文

レモン、6項目の修正箇所と新しいテストを読みました。実行はしていません。6項目そのものの実装には問題は見つかりませんでした。残っている具体的な問題は次の4点です。

## 残っている問題

**1. `beforeBytes` で、エラーが出ると1バイトが二重になる（中）**
`src/core/event_input.zig:167-172`
```zig
callback(self.writer.context, self.standard_input.bytes[at]);
if (self.writer.input_error_fn) |check| try check(self.writer.context);
self.standard_input.length = at;
```
- `unread_fn` でホストに戻した後に `check` がエラーを返すと、`length = at` が実行されません。
- そのため同じバイトがホスト側（lookahead）と Decoder の両方に残り、次の読み取りで重複します。
- 対策：`length = at` を `check` より前に移します。

**2. stdin→file→stdin の入れ子で、外側 stdin の `pending_*` が内側から見えない（中）**
`src/core/input_redirect.zig:16-34`
- 2番目の修正で Decoder は共有されるようになりました。一方、`pending_key`、`pending_event_bytes`、`pending_standard_event` は今も `changed` の判定で退避・消去されます。
- file→stdin の段階で消去されるのはファイル側の値です。外側 stdin の値は最初の段階で退避されたままなので、内側の stdin には戻りません。
- 例：`unread_fn` がないホストで、XKEY が `pending_key='x'` を残したとします。この状態で入れ子の内側で KEY/EKEY を実行すると、'x' より後のホストのバイトが先に返ります。'x' は外側に戻った後に返り、順序が入れ替わります。
- 新しいテスト `event_queue_test.zig:225` は Decoder の共有だけを確かめていて、`pending_*` は対象外です。

**3. `line()` の CR 処理が `pending_key` に退避したバイトを、次の ACCEPT が読まない（低）**
`src/core/input_redirect.zig:81-83` と `95-99`
- Decoder 経路の CR 処理は、次のバイトが LF でなければ `pending_key` に入れます。このバイトは Decoder か、ホストの `key_fn` から読んだものです。
- 次の `line()` で Decoder が空だと `read_fn` 経路に進みます。この経路は `pending_key` も `pending_event_count` も確認しません。そのバイトは ACCEPT を飛ばされ、後の KEY で返ります。
- 起きるのは `unread_fn` がないホストだけです（`beforeBytes` が Decoder を空にしない構成）。テスト `:196` は入力が `\r\n` なので、この経路を通りません。

**4. Windows の標準入力で、32レコードの上限が1回の `next` ごとにしか効かない（低）**
`src/host_input.zig:180-186`
- `nextStandardPacket` は `while (windows.next(true))` で、`.key_release` などの返り値を読み飛ばしながら `next` を呼び直します。
- `next` を呼ぶたびに32レコードの予算が新しくなるため、1パケットあたりの上限は32になりません。
- 押下中のキーの解放（キーアップや、フォーカス喪失時の `releaseNext`）は最大256件あります。そのため上限は 256×32 程度になります。有限ではあるものの、「通知が大量に来ても32レコードの上限は破られない」という主張は、ここでは成り立ちません。
- `nextByte`（`:206`）も同じ構造です。
- 対策例：外側のループに合計の上限を設けるか、標準モードでは `next` の中で解放イベントを `continue` 扱いにして予算内で処理します。

## 問題が見つからなかった項目
- 1番目の項目（POSIX が `next()` を経由しない、GRAPHICS の restart が残る）
- 3番目の項目のうち、入力が確実にある場合だけ次のバイトを読む判定そのもの
- 4番目の項目（遅延した特殊イベントの扱い）
- 5番目の項目：`deferred` が上書きされる経路はありません。`read_fn` が呼ばれるのは `deferred == null` のときだけです（`standard_event.zig:135-160`）。
- 6番目の項目：`ready()` は Decoder を変更しません。

除外を指示された境界（stdin のみの待機 1078、peek 中でも除外マウスを捨てる、ネイティブの deferred を保持する）は扱っていません。
