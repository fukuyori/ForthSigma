レモン、レビュー結果です。今回はファイルを読んだだけで、コマンドもテストも実行していません。ビルドとテストの結果、tque の現在状態、git の状態は未確認です。tque は `.work/1132/tasks-resume.json` のスナップショットだけを見ました。`.work/1135/implementation-review.md` は空でした。1135 はまだ完了していません。

## High
実装・競合・スタック・数値で、High に当たる誤りは見つかりませんでした。

## Medium

**M1. 4声の1134出力との一致を、固定値で検査していない**（`verify-nes-apu.py:187`）
- 現在は Forth と Python を互いに比べているだけです。Python の `sample()` も今回変わったので、両方が同じようにずれた場合は試験を通ってしまいます。
- 修正:
  ```python
  assert hashlib.sha256(expected).hexdigest()=='c63131af04a7ac388810613e3425568cc4dce1b3f8334e3a1c392421c8d94755'
  ```
  を加えます。この値は1134の測定JSONにある値です。

**M2. rate を変えたつもりの場面で、rate が変わっていない**（`verify-nes-dmc.py:31`）
- `dmc()` は rate 15 で、その後の `(5,15,0x4010)` も rate 15 です。そのため「rate を変えても timer をリセットしない」動作を試していません。また、この動作の手計算の試験もありません。
- 修正1: その場面を `(5,0,0x4010)` に変えます。
- 修正2: 次の手計算の試験を加えます。
  ```python
  assert run('15 16400 0 NA-WRITE 0 16400 3 NA-WRITE 5 ND@ . 4 ND@ . 55 NA-TO 5 ND@ . 56 NA-TO 5 ND@ . DEPTH . BYE')==['26','213','0','213','0']
  ```
  期待値の根拠: cycle 2 の reload で timer は26になります。その後 APU clock 26回で0になり、cycle 56 で新しい period の213を読み込みます。

**M3. 999 の子タスク構成が文書の間で食い違っている**
- 1140 を書いているのは `NES_DMC_FORTH.md:3` だけです。`EMULATOR_CORE_PLAN.md:85-98`、`CORE_EXTENSION_PLAN.md:200`、`HANDOFF.md:5-7` には 1140 がありません。
- スナップショットでは、1139 の題名に「最終採否」が残り、`depends_on` も空のままです。
- 修正:
  - 1139 を「照合（監査）」だけにします。
  - 1140 を「最終採否」とし、depends_on を 1132/1136/1137/1138/1139 にします。
  - 「1139 で不足が見つかったら機種別の子タスクを登録し、均等平均の分母が増える」と明記します。
  - 7枝の場合、999 は (100+50)/7 ≈ 21% です。
  - `CORE_EXTENSION_PLAN.md:200` の「DMC1135未着手」を、今の状態に直します。

**M4. 設計レビュー Medium 7（測定の比較条件）が文書に入っていない**（`NES_DMC_FORTH.md:42-50`）
- 無音PCMの全 process 時間には、32768項目の表の初期化と、`DATA` による 32KB の Forth ループが入ります。
- 修正1: 「この値は1134の値と直接比べない」と書きます。
- 修正2: debug/graphics/extension を除いた構成で 256KiB の表を読み込めたかどうかを、結果の欄に記録します。結果が出るまでは「未確認」とします。

## Low
- **手計算の試験の追加を推奨:** 折り返しと「remaining>0 の間は再有効化しても再開しない」は、Python との比較でしか確かめていません。
  ```python
  assert run('15 16400 0 NA-WRITE 255 16402 0 NA-WRITE 4 16403 0 NA-WRITE 16 16405 0 NA-WRITE 27596 NA-TO 6 ND@ . 7 ND@ . 27597 NA-TO 6 ND@ . 7 ND@ . DEPTH . BYE')==['32768','1','32769','0','0']
  ```
  根拠: 取り込みは cycle 1、2回目以降は cycle 381+(k−2)×432 です。65回目は27597になります。
- `verify-nes-dmc.py:84` の `import time` は、3行目と重複しています。
- `verify-nes-apu.py:2` の docstring に「four-channel」が残っています。
- `fast_dac_8khz` の計測区間には、`DM-QUEUE-DAC` の enqueue 処理も入ります。benchmark の scope にそう書いてください。
- 1134のJSONの `source_snapshots_lf` について、保存した本文の LF 正規化 SHA256 が `820aae08…` と一致するかは未確認です。実行する側で照合してください。

## 照合して問題なかった項目
- **DMC の状態と rate 表:** ND の15項目、自前の32768byteのメモリ、`NA-MEM!` の事前検査と即時反映、RESET でメモリを保持すること。rate 表の index13=84 と、period=rate/2−1。
- **取り込み:** 次の CPU clock の先頭で、出力の clock より前に取り込み、DMA の待ちは扱わないこと。最後の取り込みでの loop と IRQ。FFFF→8000 の折り返し。
- **4015・4010・4011:** 4015 の書込みは DMC IRQ だけを消すこと。bit4=0 なら remaining=0、remaining=0 のときだけ再開すること。4010 で IRQ を無効にすると IRQ を消すこと。4011 は bit7 を無視すること。
- **出力:** 範囲外では変化しないこと（126+2 は126、1−2 は1）。clamp ではないことも、手計算の試験 `verify-nes-dmc.py:44` で確認しています。silent の間も shift と bits を進めること。
- **status と IRQ:** `NA-STATUS` の bit4/bit7 と、frame IRQ だけを消すこと。`NA-IRQ?` が frame|DMC を返すこと。
- **fast 版の分割:** `NA-DMC-NEXT` の (timer+1)×2−(cycle&1) は、APU clock の数と合っています。出力の clock は区間の終わりに1回だけです。バッファが空で remaining>0 のときは1 tick に分けるので、取り込みの時刻は reference 版と一致します。
- **合成の表:** `UM*`/`UM/MOD` のスタック順は正しいです。中間値の最大は約1.03e19 で、2^64 未満です。商は 32767 以下です。手計算の最大値は 8469+24297=32766 で、32768+31 項目すべてを Python の任意精度で照合しています。
- **試験:** 8kHz の DAC 試験で、予定表の領域回収（1024件を超える）と、出力の全byteの比較をしています。手計算の試験（cycle 434 で +2、IRQ の status 0/1）は、設計どおりです。
