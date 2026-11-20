# task1169 実装レビュー（読み取りのみ）

**結論：High はありません。Medium は 4 件で、どれも Forth の動作の誤りではなく、検査の抜けか仕様の未確定です。**

指定された 5 ファイルに加え、`examples/zx-ay-levels.fs`、`scripts/zx-ay-levels.py`、`examples/pcm-synth-play.fs` の関係部分を読みました。ファイルの編集・実行・ネットワークアクセスはしていません。そのため、テストが通るかどうかは**未確認**です。

## 確認して問題がなかった点

- **overflow**
  - `ZX-RAW-RUN`（zx-spectrum-audio.fs:65）と `ZX-RUN`（:114）は、`MAX−CYCLE` と比べるので加算が溢れません。
  - fast 経路では、clock を 16 で割った商と余りを分けて計算しています（:70-71）。
  - `ZX-MAX-FRAMES`（:139-141）は `(MAX−cycle)·48000 + 47999 − frac` を double で求め、cpu で割っています。これは「f フレーム後の累積 tick ＝ floor((frac+f·cpu)/48000) ≤ 残り」の条件と正確に一致します。
  - `ZX-STREAM` の `blocks > max/512` の判定（play.fs:14）も、`blocks·512 ≤ max` と同じ条件です。
- **予定の時刻と順序**
  - 予定の追加は、範囲・時刻・model・容量・逆順をすべて判定してから compact と追加を行います（:100-105）。
  - 適用済みの末尾 entry の tick は現在の cycle 以下なので、逆順判定に使っても誤判定になりません。
  - `ZX-TO`（:106-112）は、予定の tick まで PSG を進めてから書き込みます。即時の操作（`ZX-WRITE`、`ZX-IN`、`ZX-AY@`）は、先に `ZX-TO` で予定を flush してから行います。これは文書 :21 の「PSG step→予定→即時→標本」と一致します。
  - CYCLE が進む経路は `ZX-RAW-TO` だけで、その前に必ず予定を flush するので、過去の時刻の予定が残ることはありません。
- **AY の 16 段 envelope**
  - 32 状態（各 EP）を `>>1` するので、1 level は 2EP step です（:36-40, :133）。
  - hold の終わりの値（0-3/9 → 0、4-7/F → 0、B/D → 15）も 16 段の定義と一致します。
  - `ZX-STEP-LIMIT` の noise の式 `2k−1+half`（:45）と、`ZX-ADVANCE-STEPS` の `(steps+1−half)/2`（:53）は、Python の 1 step ずつ計算する oracle と同じ結果になります。
  - period を短くした場合（count ≥ 新しい period）は、`1 MAX` によって次の step で切り替わります。
- **一部の bit だけを見る port 復号**
  - `C002h` で mask し、`C000h` なら select、`8000h` なら data、A0=0 なら ULA です（:81-82, :90-93）。文書 :17 と一致します。
  - 偶数 alias（例：FFFC）でも 1 件の予定の中で ULA と AY の両方に書くので、設計レビュー M2 の通りです。
- **入力 error の原子性**：`ZX-IN` は port・時刻・未対応をすべて判定してから `ZX-TO` を呼びます（:127-129）。

## Medium

**M1. 時刻上限の事前検査のテストが弱い**（verify:166）
- 判定は `[-1]==42`（buffer が変わっていないこと）だけです。CATCH の値が -24 であることも、SNAP の前後で state が同じことも確認していません。
- 上限ちょうどで成功する境界（near-MAX で `OUT 1 ZX-RENDER` が通ること）も検査していません。
- そのため、`ZX-MAX-FRAMES` が常に 0 を返すような off-by-one があっても、このテストは通ります。

**M2. error の優先順位が API ごとに違い、文書にも定められていない**
- `ZX-AY!` で reg15 を指定すると、時刻の判定より先に -21 になります（`ZX-CHECK-REG` :76 → `ZX-CHECK` :80）。
- 48K で `ZX-AY!`/`ZX-INPUT!`/`ZX-AY@` を呼ぶと、過去 tick の -24 が -21 より先です（:80）。`ZX-IN` も同じ順です（:127-128）。
- queue が満杯で逆順の tick を渡すと、-24 ではなく -528 になります（:101 が :102 より先）。
- 設計レビュー M1 は「範囲→model→過去 tick→満杯」の順を提案しましたが、文書 :19 は error の番号を挙げているだけで順序を書いていません。
- 1 つの呼び出しで複数の条件に当たる場合にどの番号を返すかが決まっていないので、仕様を決める必要があります。

**M3. 宣言した復号規則のうち、検査されていないものがある**
- select が 15 または上位 nibble 非0 のときに data 書き込みを無視する規則（:93）を、どのテストも検査していません。PORTS のテストは常に select=8 です（verify:110）。
- 上位 nibble 非0 の select（例：0x1E）での IN → 255 は検査していません。検査しているのは select=15 だけです（verify:147）。
- 48K での `ZX-IN` → -21 と `ZX-INPUT!` → -21 も、error 表（verify:158）に入っていません。この表の IN の行は mode1 だけです。

**M4. 文書が「検証する」と書いている period0／短縮を、直接検査していない**（文書 :46）
- envelope のテストは EP=1 だけです（verify:128）。EP=0→1 と R12（上位 byte）は検査していません。
- PCM のテスト（verify:137-138）には、tone と noise の period 0 も、tone と noise の period 短縮もありません。この PCM テストで扱う短縮は、envelope の 100→1 だけです。

## Low

- **L1.** `ZX-STREAM` の事前検査（play.fs:13-14）と出力経路は、verifier が play.fs を読み込まないため検査されていません（verify:101 は hash の記録だけです）。
- **L2.** `ZX-RESET` が `ZX-SLOW` を FALSE に戻します（:23）。文書の表（:31, :38）にはこの動作が書かれていません。
- **L3.** reset 後に R13 を一度も書かずに amplitude の bit4 を立てると、envelope の level は 15（最大）のまま固定されます（:21-22, :29）。Python も同じ動作なので不一致ではありませんが、モデルの宣言として文書に書かれていません。

## バグではなく、宣言されたモデルの限界

次の点は文書に明記されているので、バグとしては扱いません。

- 理想の 3dB 表、`floor(合計/6)` の混合、DC/alias/click が残ること
- AY の復号で A0 を見ないこと、偶数 alias で ULA と AY の両方に書くこと
- BFFD の read・ULA の read・偶数 alias の IN → -21
- R15/portB → -21、select が 15 または上位 nibble 非0 → readFF
- portA が low 優先の AND
- noise の tap0 xor3/seed1、R13 を書くたびの再始動、PSG の共有 divider
- `ZX-TO` などで飛ばした区間の PCM を作らないこと、fraction を持ち越すこと
- -9 のときだけ state が巻き戻らないこと（文書 :25）
- fast 経路の 1 回の処理量が noise の period で決まること（性能の性質であり、正しさの問題ではありません）

## 未確認

- 実機の 128K で、FFFD/BFFD の復号（A0 を見ないこと）と BFFD の read が合っているか。原典の PDF を今回は開いていません。設計レビューでも未確認のままです。
- テストが実際に通るかどうか（実行していません）。
