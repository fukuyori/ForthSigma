レモン、ご依頼どおり読むだけのレビューです。編集、実行、ネットワークへのアクセスはしていません。

**結論: High に当たるバグはありません。** 気になる点は、検証が足りない箇所(Medium 4件)と軽微な点(Low 4件)です。

## High
なし。ご指定の観点は、コードを読んだ範囲ですべて問題ありませんでした。

- **queue のコピーと原子性**: pattern は `C8-TEMP` へ先にコピーし、そのあとで回収と追加をします(`chip8-audio.fs:54-60`、`:75`)。
- **失敗時の挙動**: 不正入力の -24 と満杯の -528 は、状態を変える前に返ります。
- **時刻の境界**: 同じ tick では、timer の減算 → 予定 event → 即時 write の順に処理されます(`:35-40`、`:63-69`)。
- **Q32 のあふれ**: 最大になるのは pitch255 の step 約 5.64e6 に 800000 tick を掛けた約 4.5e12 で、2^39 を足しても 2^63 より十分小さいです。
- **pitch 表の式と phase の規則**: Octo の仕様、および今回採用した設計(同じ MODE なら phase を保つ、timer>0 で鳴らす)と合っています。
- **Forth の stack と cleanup**: `C8-STREAM` の `R> ?DUP IF SWAP DROP THROW THEN THROW` は、本体のエラーを優先して返します。cleanup は `PS-SAFE-CLEANUP` を使っているので、エラー時にも閉じます。

## Medium(検証が足りない箇所)
1. **pattern 予定を残したままの compaction を確かめていない**
   - 対象: `C8-COMPACT`(`chip8-audio.fs:44-47`)。
   - 満杯にするテスト(`verify-chip8-audio.py:162-166`)は timer event だけです。
   - dense テスト(`:140-148`)では、compaction の時点で未処理の予定が毎回 0 件です。
   - そのため、40byte の entry を移すときに 16byte の pattern が正しく移るかは確かめられていません。pattern 予定を数件残したまま compaction させ、PCM と状態を照合するテストが必要です。
2. **同じ tick で「予定 → 即時 write」の順になることを確かめていない**
   - 文書 `CHIP8_AUDIO_FORTH.md:15` でこの順序を宣言しています。
   - しかし `:97-98` と `:113` は、時刻が違うか、即時 write を先に行う形のテストです。
   - 例えば `2 T C8-TIMER-EVENT!` のあとに `5 T C8-TIMER!` を書き、5 になることを確かめるテストがありません。pattern でも同様です。
3. **timer>0 のまま複数周期を一度に進めたときの phase を model と照合していない**
   - 対象: `C8-RAW-RUN` が 800000 tick ごとに区切る処理(`chip8-audio.fs:35-41`)。
   - PCM の比較は、どれも 1000 tick ずつ進めています。
   - 長く進めるテストは `:150` の 123 tick だけで、`:102` の TIMERS は phase を見ていません。
   - pitch255 の XO で、半端な位置から数百万 tick を `C8-TO` で一度に進め、`C8-PHASE` を model と照合するケースが必要です。Q32 の余裕がどれだけあるかの実証にもなります。
4. **`C8-STREAM` を verifier が一度も実行していない**
   - `chip8-audio-play.fs` は hash を取るだけです(`:171`)。
   - 文書 `:44` の「無音の実 host と非ゼロ RAM fixture を区別する」という検証は、この verifier には入っていません。1165/1166 の実機確認とは別に、mono 送出と cleanup を確かめる手段が必要です。

## Low
1. **`C8-STREAM` に、ストリーム全体の時刻の事前検査がない**(`chip8-audio-play.fs:12-18`)
   - render 全体の事前検査は採用済みですが、`C8-STREAM` 全体には及んでいません。
   - `blocks*512*1000` が残りの時刻を超える場合、device を開いて途中まで送ったあとで -24 になります。`blocks*512` の積があふれるかどうかも検査していません。
2. **`C8-RENDER` の境界ちょうどで成功するケースのテストがない**
   - 上限ちょうどの frames(例: MAX-1500 から 1 frame)が成功するかどうかです。
   - 現状は 2 frames で失敗するケース(`:168`)だけです。
3. **`chip8-pitches.py --check` が `assert` に頼っている**(`:17`)
   - `python -O` で実行すると検査が無効になります。
   - 同じく `max_bit_rate_error_hz` も記録するだけで、上限を検査していません(`verify:91`)。
4. **`INCLUDED` の相対パスが、repo root から起動することを前提にしている**
   - 対象: `chip8-audio.fs:4`、`chip8-audio-play.fs:2-3`。
   - 文書や公開語の説明には、起動するディレクトリの条件が書かれていません。
