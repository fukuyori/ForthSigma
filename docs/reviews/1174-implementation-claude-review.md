# task1174 実装レビュー（読み取りのみ）

レモン、指定された5ファイルを読み、照合に必要な `examples/pcm-synth-play.fs`、`scripts/snes-tables.py`、`examples/snes-gauss.fs` の冒頭も読みました。編集・実行・ネットワークアクセスはしていません。テストは実行していないので、通過するかは未確認です。

**結論:** High はありません。仕様と実装は、算術と順序のどちらも一致しています。Medium は2件で、どちらも検証の独立性と網羅の問題です。

## 仕様どおりと確認した項目
- **ENV は更新前の値で出力（決定事項）**
  - `snes-dsp-audio.fs:114-116` は次の順で処理しています。
    1. 更新前の ENV から value を作る
    2. ENVX/OUTX を publish する
    3. `SD-ENV-STEP` を呼ぶ
    4. pitch を加えて consume する
  - 非ループの END で ENV を 0 にするのは consume の中（`:65`）なので、同じ frame の ENVX は更新前の値のままです。`:51` の宣言どおりです。
  - mode 境界の判定は、release 以外では毎 frame 行っています（`:95`→`:69-72`）。
- **Gaussian**
  - `:96-104` の各項の対応は、oldest×g[255-i]、older×g[511-i]、old×g[256+i]、new×g[i] です。i=(phase>>4)&255 です。
  - 3項を足した後に S16 で wrap し、4項目を足して飽和させ、最後に ASR 1 しています。出力は -16384..16383 の範囲です。
  - BRR の `SD-SAT SD-S15`（`:46`）は、+7FFF を -1 に、-8000 を 0 にします。宣言どおりです。
- **pitch と END フラグ**
  - pitch の上位バイトは `63 AND` で 14bit にしています（`:117`）。
  - PMON は v>0 のときだけ掛かり、floor の後で 0..16383 に clamp します。factor は 0 以上なので、下限側は実質的に使われません。
  - consume は phase≥4096 の間ループします（`:122`）。header は nib=0 のときに latch します。16個目の値を履歴に入れた後で、次の順に処理します。
    1. ENDX を set する
    2. その時点の DIR/SRCN から loop addr を読む
    3. LOOP=0 なら ENV0/release にする
  - ARAM のアクセスはすべて `65535 AND` で wrap します。
- **KON の delay**
  - START で delay=5 にし、f..f+4 は無音です。f+4 に最初の BRR 値を取り込み、delay 中は pitch/PMON/ENV を止めます。
  - KOFF の後に KON があれば KON が優先され、soft reset も同じ扱いです（`:160-163`）。
- **echo**
  - EDL は offset が 0 のときに latch し、max(4, n×2048) を使います（`:135`）。
  - 読み込みは `SD-S16` の後に ASR 1 しています。FIR のタップは (EHI+I+1)&7 で、FIR0 が最古、FIR7 が最新です。
  - FIR は先頭7項を wrap し、最終項を足して飽和させます。
  - MVOL/EVOL/EFB の各積は floor(/128) の後に S16 で wrap します。
  - 書き込みは飽和させてから `-2 AND` しています。左右とも 16bit で wrap します。
  - mute（FLG bit6）は出力だけを 0 にし、ECEN（bit5）は書き込みだけを止めます。
- **queue と時刻**
  - 検査の順序は次のとおりで、すべて変更前に行うので原子的です（`:182-199`）。
    1. reg/addr
    2. value/target
    3. 過去の tick
    4. 容量（-528）
    5. 末尾の tick 順（-24）
  - 回収は、未処理件数が1024件未満のときに MOVE で行います。末尾 tick の比較が消費済みのエントリを指しても、その tick は CYCLE 以下なので、誤って error になることはありません。
  - 即時操作の後に同じ tick で追加した予定は、次の TO/RUN/RENDER の冒頭で `at SD-RAW-TO`（0 frame）として適用されます。RENDER 0 と SAMPLE は flush しません。
- **stream**
  - `SD-PRIME` の 16384 バイトは 8block×512frame×4 と一致し、`SD-BUFFER` の 2048 バイトも一致します。オフセットは `SENT*4` で計算しています。
  - 事前検査で MAX/512 を確認し、CATCH の後に `PS-SAFE-CLEANUP` を呼びます。本体のエラーを優先する扱いは `PS-STREAM` と同じです。
  - `pcm-synth.fs` に `SD-` の名前の衝突はありません。

## Medium

**M1. Gauss 表の検証が独立していない**
- `snes-gauss.fs` は、`snes-tables.py:7` が `scripts/snes-gauss-data.json` から生成したものです。verifier も同じ JSON を読んでいます（`verify-snes-dsp-audio.py:6`）。
- そのため、JSON に fullsnes からの転記誤りがあっても、Forth と Python は一致したまま通ります。
- 今ある検出手段は、JSON の hash（`:155`）、単調性、4係数の和 2047..2049 だけです。和を保ったまま隣同士の値がずれる誤りは検出できません。
- 設計レビューでは、Python 側を fullsnes から別に抽出することを推奨していましたが、まだ実装されていません。
- 対応案:
  - `source_html_sha256` が一致する保存済み HTML から再抽出して比較する。
  - または、資料から直接書き写した数点（端の値や中央付近）を手計算のベクトルとして固定する。

**M2. 統合テストで通っていない分岐がある**
- Python は Forth と同じ構造と式を写した実装です（`state()` の並びも同じです）。統合テストで実行されない分岐は、実質的に検証されていません。
- 次の分岐が未到達です。
  - **(a) 非ループの END による ENV0/release**
    - 全テストの header は 195（END+LOOP）だけです。
    - 手動テスト（`:191`）は 512 の header を書き換えていますが、header はすでに latch 済みなので、この分岐には入りません。
  - **(b) 1 frame での複数回の consume（pitch≥4096）**
    - demo の pitch は最大で 901+7×73=1412 です。voice7 に PMON が掛かっても、factor は最大 2047 なので約2822 にしかなりません。
    - PitchH の bit6-7 の mask と、PMON の上限 16383 にも届きません。
  - **(c) FIR**
    - FIR0..6 は常に 0 で、FIR7 が 64 から 7 に変わるだけです。
    - そのため、先頭7項の wrap、タップの順序、負の係数は統合テストに出てきません。
  - **(d) echo の ARAM の範囲**
    - ESA/offset の 16bit wrap は試されていません。
    - echo 領域は 0x4000–0x50FF で、BRR(0x200) や DIR(0x100) と重ならないので、計画（`:44`）にある「同ARAM競合」も試されていません。
  - **(e) その他**
    - 統合テストで ADSR を使っていません（demo は GAIN direct 48 だけです）。
    - DIV≠0 の状態から RENDER するケースがありません。
- 手計算のベクトルもありません。計画にある「手計算で照合」は、delay/ENDX/word wrap の3件だけです。次の項目は資料の値で固定されていません。
  - BRR の +7FFF→-1 と -8000→0
  - MVOL/EVOL/EFB の -128 での wrap
  - noise の最初の数値
- queue（-528、エラーの優先順位、回収、原子性）、MAX、-9、stream の部分送出と cleanup はまだ未検査です。レモンの言う「追加中」の範囲だと思いますが、未確認です。

## 明示している sample 境界の制約（実機互換の主張ではないもの）
次の項目は文書（`:13,33,35,37,38,40,53`）で宣言済みで、実装もそのとおりです。不具合としては扱いません。
- サブ frame の位相
- BRR を4値まとめて先読みすることと、ENDX の更新 slot
- rate counter の個別 offset
- garbage-boundary と、GAIN bent の内部値
- ESA の書き込み遅延と echo slot の競合
- 次の項目はモデル側の決定です。
  - PMON の上限
  - BRR の clip の扱い
  - MVOL/EVOL/EFB が overflow したときの扱い

## Low（参考）
- `SD-STREAM:32-33` のエラーの順序は、負数 -24 → 使用中 -528 → MAX -24 です。文書（`:55`）が定めているのは queue の順序だけなので、STREAM の順序も1行書くと Python 側と揃えやすくなります。

## 未確認
- テストが通るかどうか
- JSON と fullsnes の数値の照合
- 実機での挙動
