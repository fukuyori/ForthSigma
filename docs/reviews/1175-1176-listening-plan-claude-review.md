# SNES OS 試聴準備のレビュー（読み取りのみ）

実行・変更・計測はしていません。根拠はファイルの読み取りだけです。

**結論：High はありません。Medium が3件、Low が5件あります。** 依頼された検証項目は、コード上ではすべて満たしています。

## High
なし。

## Medium

**M1. `--play` の前提チェックが、`acceptance-common.fs` とバイナリしか固定していない**
- `acceptance.py:18` が照合しているのは、preflight の `binary_sha256` と `common_sha256_lf` だけです。
- `acceptance-common.fs` が `INCLUDED` で読み込む次のファイルは照合されていません。
  - `tests/audio/snes-dsp-audio-play.fs`（ゼロ埋めの FILL、SD-STREAM）
  - `examples/snes-dsp-audio.fs`
  - `examples/snes-dsp-native-backend.fs`
  - `tests/audio/pcm-synth-play.fs`（PS-SAFE-CLEANUP）
  - `tests/audio/pcm-synth.fs`、`examples/snes-gauss.fs`
- `acceptance.py:38` の再生コード自体も照合されていません。
- このため、preflight の後でこれらが変わっても、証明をやり直さずに `--play` が通ります。
- 対応案：これらのファイルと `acceptance.py` を LF 正規化して SHA を取り、preflight に記録し、`--play` で照合する。

**M2. `--play` が、ゼロ出力でのデバイス実行の合格を前提にしていない**
- アンダーランとフレーム数を実デバイスで確かめるのはゼロ出力の実行だけです。しかし `--play` は `{os}-stereo-silent.json` を確認しません。
- 現状は次のとおりです。
  - `windows-stereo-silent.json`：exit 0、`underruns=0 frames=98304` が2回、`DEPTH=0`。
  - `linux-stereo-silent.json`：`.work/1175-1176` に存在しません。Linux のゼロ出力実行は未確認です。
- 対応案：`--play` の条件に、同じバイナリ・同じソースのハッシュで exit 0 の silent JSON があることを加える。

**M3. 試聴者が、どちらの音が鳴っているかをリアルタイムで見られない**
- `acceptance.py:39` は `capture_output=True` で起動しています。そのため `LEFT LOW` / `RIGHT HIGH` の表示はプロセス終了後にまとめて出ます。Forth 側の `STDOUT FLUSH-FILE` は試聴者には効きません。
- 左右・高低を人が判定する手順としては弱いです。
- 対応案：stdout を逐次表示しながら記録する。または Python 側で事前に「低音・左 → 高音・右」と表示する。

## Low

- **L1. 実際にストリームへ送った PCM は捕捉していません。** 同一であることは次の理由で成り立ちます。
  - SD-RENDER は1フレームごとに `32 SD-RUN` を呼ぶので、8×512 の先行送出と 184×512 に分けても、98304 フレームを一度に描画しても結果は同じです。
  - SD-NOTE は SD-DEMO-SETUP 経由で SD-RESET を呼ぶので、2音目も初期状態から始まります。SD-FRAMES-XT はリセットされず、native のままです。
- **L2. 音量の上限と、低音・高音の周波数を直接確かめるチェックがありません。**
  - ピッチ 451 / 901 は、BRR の16サンプルのループで約 220Hz / 440Hz に相当します（※計算による推定）。
  - ピークは約 ±1024（約 -30dBFS）と推定されます（※推測です）。
  - 現在の照合は、オラクルとの完全一致と、使わない側のチャンネルがゼロであることだけです。
- **L3. `timeout=30` を超えると、`TimeoutExpired` のためレポートが書かれません。**
- **L4. preflight の `no_device_output: true` は固定値です。** ただしコード上は正しい内容です。
  - `--verify` の経路は PCM-OPEN を呼びません。
  - SNES-FRAMES は音声エンジンを取得しません（`src/core/words_audio.zig:84`、`src/core/words_snes_dsp.zig:1`）。
  - `pcm-synth.fs` と `snes-gauss.fs` には PLAY・PCM-OPEN・SND- がありません。
- **L5. `--play` 時に、preflight の `tests` の内容を見直していません。** preflight はすべての assert を通った後にだけ書き出されるので、手で編集されない限り問題はありません。

## 確認できた点（問題なし）

- **フィクスチャ**
  - Forth の `SD-NOTE`（`acceptance-common.fs:3-7`）と Python の `note()`（`acceptance.py:8-11`）は、書き込むレジスタと値、その順序が同じです。
  - `demo()` と `SD-DEMO-SETUP` も、ARAM・レジスタ・ボイスループが一致しています。
  - 鳴らすのは KON=1 のボイス0だけです。左の音は 451/16/0、右の音は 901/0/16 です。
  - EVOL L/R=0、EON=0、FLG=32 なので、エコーは出力されず、ARAM にも書き込みません。
- **フレーム数**
  - 192×512 = 98304 フレーム、32000Hz、ステレオ（4バイト/フレーム）です。
  - SD-PRIME 16384 バイト = 8×512×4、SD-BUFFER 2048 バイト = 512×4 で一致しています。
- **preflight**
  - PCM 393216 バイト全体、SNAP の 266 値と event count・index・DEPTH（`+[0,0,0]`）、ARAM 65536 バイトを完全に照合しています。
  - 使う側のチャンネルが0以外を含み、使わない側がすべて0であることも確認しています。
  - Windows と Linux の preflight で、PCM のハッシュが一致しています。
- **後始末**
  - SD-STREAM の `CATCH → PS-SAFE-CLEANUP → 本体のエラーを優先` は PS-STREAM と同じ構造です。
  - 本体でエラーが起きても PCM-CLOSE（破棄）が走ります。
- **アンダーランとフレーム数**
  - PCM-STOP（モード1、1000ms）の後に PCM-UNDERRUNS を読みます。
  - SD-ACCEPT-DONE は、handle=0、underruns=0、frames=98304 のどれかが外れると THROW します。
  - Python 側も、正規表現で2回一致すること、`DEPTH=0`、stderr が空、exit 0 を確認しています。
- **`--play` 以外で音が出ないこと**
  - `--verify` はデバイスを開きません。
  - フラグなしの実行は、描画したうえでゼロ埋めした PCM だけを送ります。
  - `--play` と `--verify` は同時に指定できません。
  - 試聴結果は `pending` で記録され、人が判断します。

対応するなら、M1（ハッシュで固定する範囲を広げる）、M2（ゼロ出力での実行合格を前提にする）、M3（表示をリアルタイムにする）の順をお勧めします。
