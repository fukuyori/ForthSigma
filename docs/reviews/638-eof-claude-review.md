# 638 EOF修正の評価原文

2026-11-19、読み取り専用。レビュー時点の指摘であり、現状の未解決一覧ではない。実行結果と採否は638-review-response.mdおよび実装記録を参照。

## 依頼

```text
EOF correction choice from frozen-result.json: the typed Writer source EOF is a level stream condition; after any successful unread/pushback, the host reasserts EOF after its buffered bytes are drained (native ReadFile/read on closed pipe already does this; console rawCtrlD/Z arebytes, not one-shotEOF). PureDecoder still retains peekedEOF until EKEY consumption when no bytes moved. event_input.beforeStdinBytes nowclearscachedEOF on EACH successfully transferredbyte (evenpartialtransfer), beforeFileRead legacytransfer does same; rejectedbyte stayscore. Native reproduction beforefix inputESC[ with EKEY?DROP KEY EKEY EKEY yieldedESC EOF [; afterfix WindowsScript5cases includesESC [ EOF and truncatedUTF8->byte+replacement+EOF, bothpassed. StandardSTDIN KEY?-FILE/FILE-EOF? nowalso seelegacyqueuedbytes via hasStdinBytes. No source changes pending, Win/Linux/Mac/matrixrerunning. Read only event_input.zig relevant transfer funcs, host_interface contract, standard_event EOF, tests/scripts/verify-event-queue{,-windows}.py EOFcases. Check whether this corrects the actual EOForder defect under the stated valid stream-source contract. Do not broaden scope or modify/execute. Japanese concise, no userquestions.
```

## 原文

## 結論

あなたが示した有効なストリームソースの契約（`host_interface.zig:168`「EOF はストリームの状態であり、押し戻したバイトを読み切った後にホストが再び EOF を返す」）を前提とすれば、今回の修正で EOF の順序の不具合は解消しています。読んだ範囲では、新しい順序の逆転は見つかりませんでした。

## 根拠（読んだコード）

- **`event_input.zig:174-179`（`unread_byte_fn` 経路）**
  - `try callback(...)` が成功したときだけ、`length = at` と `eof = false` を実行します。
  - 押し戻しを拒否されたバイトは core に残り、`eof` も変わりません。
- **`event_input.zig:184-191`（従来の `unread_fn` 経路）**
  - 1 バイト渡すごとに `eof = false` にします。
- **`event_input.zig:213-223`（`beforeFileRead` の従来キュー）**
  - 同じく `push` が成功するたびに `eof = false` にします。
- **`standard_event.zig:155-159, 187`**
  - EOF を返すのは `length == 0 && eof` のときだけです。
  - 全バイトを押し戻すと core の `eof` は false になるので、core が EOF を先に返すことはなくなります。EOF はホストがバイトを読み切った後の `.eof`（行 187）から改めて来ます。
  - これで、修正前の `ESC EOF [` という順序の原因が取り除かれています。

## 部分転送時の順序

- 末尾のバイトから押し戻すので、失敗すると先頭側のバイトが core に残り、後ろ側はホストに渡ります。
- 読む順序は「core の残り → ホストの押し戻し分 → ホストが再び返す EOF」になり、元の並びと一致します。
- 1 バイトも渡らなかった場合は、core が「全バイト → EOF」を持ったままなので、これも正しい順序です。
- 従来キューを先に押し戻し、`standard_input` を後から押し戻すので、`standard_input` のバイトが前に来ます。EOF は最後に来るので、EOF の位置については問題ありません。

## バイトが 1 つもない状態で覗いた EOF

- `length == 0` のときは `beforeStdinBytes` が先頭で return するので、`eof` は残ります（行 168-171）。
- EKEY が 1 回だけ返して消費します（行 158）。ホスト側も同じ状態をずっと返すので、二重になっても観測される順序は崩れません。

## テストスクリプト

- `verify-event-queue{,-windows}.py:68/77` の 2 ケースを確認しました。
  - `27 91 2147483681` と `227 65533 2147483681` を期待しており、どちらも KEY → `beforeBytes` → `beforeFileRead` → 押し戻し、という経路を通ります。
  - 期待値は上の解析と一致します。
- `pipe-eof`（行 72-74/81-83）は、空の入力で EOF を返すことの確認です。

## 残る前提（今回の範囲外・未確認）

- **ホストの実装は読んでいません。** EOF を常に返し続ける（レベル型の）ソースだけに供給が限られているかは未確認です。
  - 根拠はホストの契約を書いたコメントと、Windows/Linux/Mac の実行結果だけです。その実行結果も私は再確認していないので未確認です。
  - ※推測です：POSIX の端末が canonical モードのまま stdin になる経路があると、Ctrl+D の EOF が 1 回限りになり、契約から外れます。raw モードだけで使われていれば該当しません。
- **押し戻しの拒否・部分転送は、上の 2 本のスクリプトでは検証されていません。** `event_queue_test.zig` にこのケースがあるかは未確認です。
