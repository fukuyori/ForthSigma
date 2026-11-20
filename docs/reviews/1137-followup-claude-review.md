レビュー結果をまとめます。コマンド、テスト、書き込み、ネットワークアクセスはどれも行っていません。指定の5ファイルを読んだうえで、判定に必要な `examples/paula.fs:9,35-60,121` も読みました。以下はコードを読んで判断したもので、実行結果ではありません。

## 結論
- **High：なし**
- **Medium：1件**。Low2 の一部「ブロック先頭で volume に戻る」は、今の fixture では確かめられていません。

## Medium：both attach の手計算ケースで block 再開を区別できない
`verify-paula-stream.py:28` は LEN=4（偶数）です。

- 交互の位相（field 10）は1 word ごとに切り替わります（`paula.fs:45`）。4 word で一巡するので、次ブロックの先頭は reset がなくても volume 側になります。
- そのため `PA-RELOAD` の `0 SWAP 10 PA!`（`paula.fs:35`）を消しても、5つの境界はすべて同じ値 `64 65536 1 / 64 123 0 / 32 123 1 / 32 124 0 / 64 124 1` になります。
- 区別するには LEN を奇数にします。例えば LEN=3 なら、tick 739 で新ブロックの word0 が来ます。
  - reset がある場合：64 が volume に入る
  - reset がない場合：64 が period に入り、123 に丸められて `PA-PER-CLAMPS` が増える
- 次の2か所は、この確認が済んだと読める書き方です。
  - `PAULA_FORTH.md:68`「次blockでvolumeへ戻る5境界」
  - `1137-review-response.md:31`「block再開の5境界」

word 列 64/123/32/124 の交互適用と、tick 1/247/493/739/985 の値は、コードと手計算で一致しています。

## Low1：対応済み
- **mock の条件：** `PCM-OPEN` は 48000/2/4096 以外で -24 を THROW します。
- **受理量：** `PCM-WRITE` は 5 → 0 → 残り全部（507）を受理します（`ENDCASE` 既定節の `frames SWAP` も正しい）。
- **期待値の内訳：** 期待値 `0 3 2 1 0 0 20 20 0 -1 512` を手で追い、すべて正しいと判断しました。
  - 残り 0
  - write 3回、wait 2回（5受理後と0受理後）、close 1回、handle 0
  - offset 0/20/20
  - 2048 byte の COMPARE が一致
  - コピーした出力が非ゼロ
  - `PS-FRAMES` 512
- **2 byte/frame への退行：** offset が 10 になり、COMPARE も外れるので検出できます。
- **cleanup の各ケース：** timeout、close 再試行、本体エラーの優先（close 失敗／close の THROW）、cleanup の THROW の伝播、open 失敗で close しない、drain 失敗で close する。期待値は `paula-play.fs:24-30` の CATCH と優先順位の処理に合っています。
- 各ケースは別の process で動くので、状態は持ち越されません。

## Low3：対応済み
- `PAULA_FORTH.md:31`：奇数・範囲外の read が -24 になることを明記
- `PAULA_FORTH.md:33,51`：VOL bit6 優先の規則を明記

## そのほかの記述
- 既存の実装レビュー（High/Medium なし）の判断は変わりません。上の Medium は追加 fixture にあるもので、本体コードの欠陥ではありません。
- `PAULA_FORTH.md:9` では、Agnus の slot・pipeline・実機互換は対象外と宣言されたままです。
- Mac の確認 1147 は未完了で、それが済むまで親 1137 も完了にしない書き方が `PAULA_FORTH.md:3`、`:64` と `1137-review-response.md:3` に残っています。
