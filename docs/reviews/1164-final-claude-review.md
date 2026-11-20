指定の5ファイルを読んで確認しました。コードの編集、スクリプトの実行、ネットワークへのアクセスはしていません。

## 結論：High と Medium は残っていません

前回 Medium とした4点は、どれも解消されたと判断します。

- **pending の pattern payload が残った状態での compaction**：`C8-QUEUE` は、payload を `C8-TEMP` にコピーし終えてから `C8-COMPACT` を呼び、そのあとで entry に書き込みます（`examples/chip8-audio.fs:54-58`）。512件を pending のまま compaction させ、全PCMと状態を照合するテストがあります（`verify-chip8-audio.py:155-167`）。
- **同一 tick で queued と immediate が重なる場合**：`C8-TO` は `at <= tick` の event を先に適用し、そのあとで immediate を書きます（`chip8-audio.fs:61-76`）。timer と pattern の両方で、このテストがあります（`verify-chip8-audio.py:99-100, 118-120`）。
- **active 中に timer 境界を多数またぐときの phase**：`count` は1回あたり800000以下に抑えられています。step の最大値はおよそ5.6e6なので、積は2^63を超えません。250境界を一度に進めて closed-form と照合するテストもあります（`verify-chip8-audio.py:173-177`）。
- **stream テスト**：callback ケースが11件あり、その中にオーバーフローを open より前で拒否するケース（`stream-overflow-before-open`）と、使用中の handle を横取りしないケースがあります。`C8-STREAM` のチェック順は、blocks が負かどうか → handle → overflow の順です（`chip8-audio-play.fs:13-14`）。

## 残っている Low（参考）

1. **`C8-RENDER` の途中で失敗した場合**：出力先アドレスが不正だと、`1000 C8-RUN` まで進んだあとの格納で失敗するため、状態が1フレーム分だけ進んで残ります。テストはこの動作を仕様として固定しています（`verify-chip8-audio.py:197`、期待値 `[-9, 1000]`）。他の API は失敗しても状態が変わらないので、この例外的な動作がドキュメントに書かれているかは確認していません（未確認）。
2. **pitch テーブルの照合方法**：テストの期待値は double の計算から作り、生成スクリプトは Decimal（精度80桁）で計算しています。両者で floor の結果が食い違えば、テストは失敗として表に出ます。気づかないまま通ってしまう問題ではありません。

`scripts/chip8-pitches.py --check` は assert を使わずに `SystemExit` で失敗を返します。`read_text` は改行を変換するので、CRLF でチェックアウトした環境でもそのまま比較できます。
