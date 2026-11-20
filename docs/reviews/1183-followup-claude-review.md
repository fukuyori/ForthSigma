レビューが終わりました。結論として、**M1 はほぼ解消しています**。High（具体的な不具合）は見つかりませんでした。ただし、テスト名が示す内容を実際には確かめていない箇所が残っています。

ファイルを読んだだけで、テスト・ビルド・ハッシュ計算・git は実行していません。下の「一致」「合格」は、記録 JSON の内容と、コードを読んで判断したものです。

## M1 の判定：ほぼ解消（feedback だけ未解消）

- **BRR**（`verify-snes-dsp-audio.py:214-217`）：`SD-RUN` は `SD-FRAMES-XT` を経由して `SNES-FRAMES` を呼ぶので、Zig の `brr` まで届いています。256×16×3 の期待値の並び順も合っています。
- **ENV**（`:218-220`）：pitch は 0、FLG は 32 です。このため、1フレームにつき `envelope(0)` がちょうど1回、frame 1 から N の順に呼ばれ、Python の期待値と同じ条件になっています。
- **Gauss**（`:221-229`）：PCM と OUTX を通じて比べています。
- **FIR**（`:230-232`）：EDL=0 なので、エコーのアドレスは常に 0 です。そのため 8 タップのインパルスを正しく判別できます。
- **検証失敗・重なり・クロック上限・StepLimit**：`snes_dsp_test.zig` が Zig から直接確かめています。
- **feedback**：下の Medium 1 のとおり、まだ確かめられていません。

## High
なし。Zig の `step`／`echo`／`valid`／`commit` と Forth 版 `SD-STEP` を突き合わせ、前回の照合結果から変わっていないことを確認しました。

## Medium

**1. feedback と書き込み禁止の検証が効いていない**（`verify-snes-dsp-audio.py:233-238`）
- `SNAP` は ARAM を出力しません。ここでは `m.state()` だけを比べています。
- 手計算すると、flag=0 のときに書き戻される値は ch0 が `0x8000`、ch1 が `0` です。どちらも初期値と同じです。
- そのため、ARAM を比べたとしても、書き込み（flag 0）と書き込み禁止（flag 32）を区別できません。
- テスト名は「feedback…write-disable」ですが、ネイティブ版で実際に確かめているのは mute と EVOL の折り返しだけです。
- feedback の折り返し（`signed16(fir*efb>>7)`）と MVOL の折り返しは、補助語のテスト（`:250-253`）でしか直接確かめていません。
- 2048 フレームの各シナリオでこの境界を通るかどうかは、coverage に印がないため**未確認**です。
- 対応案：初期 ARAM を書き戻し値と違う値にして、`SD-ARAM` を比べます。

**2. no-audio 構成で 1183 のネイティブ版を検証した記録が見つからない**
- `.work/1183/verify-matrix.py` が回しているのは `''`、`-no-debug`、`-no-float` だけです。no-audio のバイナリはビルドされていますが、検証の対象に入っていません。
- 設計書（`SNES_DSP_NATIVE_DESIGN.md:27`）は feature-disabled の検証を要求しています。
- 探したのは `.work/1183` の py と log、`SNES_DSP_AUDIO_FORTH.md` だけです。ほかの場所の記録は**未確認**です。

## Low

1. **no-float 構成で EXEC-LIMITED のテストが飛ばされている**
   - `verify-matrix.py:8` は、`kind` が空でなければ `--no-debug` を付けます。そのため no-float でも EXEC-LIMITED を実行しません。
   - `windows-no-float-extra-native.json` を読み、この case がないことを確認しました。
2. **Gauss テストの「oldENV-publish」が判別できていない**
   - ENV=2047 で mode=3 なので、更新後は 2039 になります。`>>4` するとどちらも 127 です。
3. **ネイティブ版が実際に動いたことを確かめていない**
   - SAVESYS テスト（`verify-snes-dsp-native.py:37-41`）は、Forth 版で動いても同じ結果になります。保存したイメージの中で `SD-FRAMES-XT @ 0<>` を確かめていません。
   - `verify-snes-dsp-audio.py --native` にも同じ確認がありません。
4. **Zig テストに足りない境界がある**
   - バッファがちょうど隣接している場合に受け付けるかどうかを確かめていません。
   - ARAM が 65535 から 0 へ折り返すときに、1 バイトずつ registry へ通知されるかどうかを確かめていません。
   - globals の不正値のテストは、対象のセルだけを比べています。メモリ全体が変わっていないかは見ていません。
5. **前回の L2（registry 通知）は解消済み**
   - `reg_writes` と `ram_writes` で、実際に書き込んだ箇所だけを通知しています。
   - 設計書 `:33`、`:39` にも明記されています。
6. **前回の L1（性能）はそのまま**
   - `commit` は今も、毎フレーム 138 セルすべてを書き戻しています。

## ハッシュとソースの記録

- **前回の L3 は解消しています。** `verify-snes-dsp-audio.py:316` は、`--native` のときにネイティブ関連の 5 ファイルを記録します。`windows-model-native.json` にも実際に記録されていました。
- **新しい抜け（Low）：** `verify-snes-dsp-native.py:42` の記録対象に、次のファイルが入っていません。
  - `tests/scripts/verify-snes-dsp-audio.py`（期待値を作る `Model`、`demo`、`DUMP` を import している本体）
  - `scripts/snes-gauss-data.json`
  - `examples/snes-gauss.fs`
- **ハッシュの一致は未確認です。** 記録の値（`sound_snes_dsp.zig` = `1fbe02bf…` ほか）が今のファイルと一致するかは、計算していないため確認できていません。
  - `docs/word-reference/translation-sources.json:106` の値は、記録と同じ `1fbe02bf…` でした。

`.work/1183/final-claude-review.md` は空のファイルでした。

ご依頼は読み取りのみだったため、Medium 1、2 の tque への登録はしていません。
