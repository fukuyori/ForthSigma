# task1169 設計レビュー：ZX Spectrum 48K beeper／128K beeper+AY

読み取りのみで行いました。編集・実行・ネットワークアクセスはしていません。

読んだもの:
- `docs/ZX_SPECTRUM_AUDIO_FORTH.md`
- `examples/ym2149.fs`（envelope・noise・mixer・level の部分だけ）
- `.work/1169/zx128-5.png` と `zx128-19.png`（128K manual の scan）

この2ページにはAYのport復号の記述がありませんでした。そのため、FFFD/BFFD の復号条件が原典と合っているかは**未確認**です。`ay.pdf` と `sound_psg.zig` は読んでいません。

## High

**H1. AY clock が整数になりません**
- 128Kでは AY clock = 3546895/2 = 1773447.5Hz です。
- 文書にある「全周期はAY clock/(256EP)」を、手計算やPythonで整数の Hz として計算すると切り捨ての誤差が出ます。
- 対応: 検証の期待値はすべて CPU tick で書きます。
  - tone の半周期 = 16·TP tick
  - noise の更新 = 32·NP tick
  - envelope の 1 level = 32·EP tick
  - envelope の全周期 = 512·EP tick
- Hz を書くときは有理数の形（3546895/(32·TP) など）だけにする、と文書に追記します。

**H2. PSG step の境界がどの tick か決まっていません**
- 対応: RESET の時刻を tick 0 とし、PSG step は tick = 16k（k≥1）に到達した時点で1回進む、と宣言します。
- 16 で割った余りは state として持ちます。ZX-TO や ZX-OUT で端数の tick に飛んでも、余りは維持します。
- この決め方がないと、slow/fast や分割実行の結果を照合する基準になりません。

**H3. select が無効なときの IN で、文書の中に矛盾があります**
- OUT/IN の節は「15/上位nibble非0は readFF」と書いています。
- 一方、IN の節は「未対応を FF の実機仕様と捏造しない（-21）」と書いています。
- 対応: 次の2つに分けて明記します。
  - port が未対応 → -21
  - FFFD は対応 port だが、select が R15 または上位 nibble 非0 → FF を返す（モデルの宣言）
- 上位 nibble で deselect する理由として AY の chip address mask を挙げるなら、`ay.pdf` で確認してから記載します。現時点では**未確認**です。

## Medium

**M1. 入力 error の判定順が決まっていません**
- 複数の error が同時に該当すると、どの番号を返すかで検証の結果が変わります。
- 対応: 次の順で判定すると決め、全組み合わせを検査します。
  1. stack 値の範囲（byte / port 0..65535 / reg）→ -24
  2. model に対する未対応 → -21
  3. tick が過去 → -24
  4. queue が満杯 → -528
- どの error でも、時刻・queue・state を変更する前に返します。

**M2. ULA と AY の両方に当たる偶数 alias の予定（例: FFFC）**
- 対応: queue には1件（target = 16+port）だけ入れます。適用時に ULA と AY へ同じ tick で書き込みます。
- 2件に分けると、適用の途中で queue 満杯になるなど、片方だけが書かれた状態が生じ得ます。
- 適用時の select を使う規則は、この1件の中で ULA → AY select/data の順に処理します。

**M3. 現在 tick と同じ tick の予定を、即時操作の後に追加した場合**
- 「予定→即時」という順序規則と矛盾します。
- 対応: 「同じ tick では、PSG step の後、書き込みは呼び出し順に適用する。予定は ZX-RUN 0 / ZX-IN / ZX-AY@ の flush 時点で適用する」に統一します。
- 現在 tick と同じ tick の EVENT は許可し、適用は次の flush とします。

**M4. RENDER の fraction の扱いと overflow 判定**
- 対応:
  - fraction は RESET だけが 0 にします。ZX-TO / ZX-RUN / ZX-OUT では変えません。
  - 必要な tick 数は q = frames/48000、r = frames mod 48000 として、q·clock + (r·clock + frac)/48000 で求めます。
  - overflow は q > (MAX−now)/clock を先に検査し、続いて残りを比較します。
- clock は 3546895 以下（22bit）なので、r·clock は 64bit に収まります。

**M5. 出力 memory が不正なとき（-9）は state が途中まで進んだままになります**
- 他の error は原子的なのに、ここだけ例外です。
- 対応: 書き込み先が有効かを事前に検査できるなら、前に検査します。できない場合は今の宣言を残し、Windows/Linux/Mac の受入でこの経路を検査しない理由を文書に書きます。

## Low

**L1. 32状態の envelope を >>1 で出す方式は、16段 AY と同じ結果になります**
- `YM-ENV-START` は state 31・count 0 から始めるので、各 level がちょうど 2EP の幅で並びます。
- hold の終わりの値（shape 0B/0D → 15、4-7 → 0）も16段の定義と一致します。
- EP=0→1（1 level = 2 step）は、モデルの宣言として明記するだけで足ります。

**L2. 混合の上限は 16383+4096 = 20479 で、s16 の範囲に収まります**
- 次の点を文書で固定します。
  - 合計してから1回だけ floor(÷6) する（channel ごとに割らない）
  - mixer の出力は (tone OR tone無効) AND (noise OR noise無効)
  - 単極なので、両方無効のときは音量どおりの DC になる
- Python の検証も同じ floor の規則にします。

**L3. 7FFD（paging）は音源の範囲外です**
- 128K の A15=0・A1=0・A0=0 の port は ULA にだけ作用する、という記述で十分です。
- paging を含まないことを一文で明記しておきます。

## 実装の具体案（Forth が先）

1. `examples/zx-spectrum.fs` を新しく作ります。`ym2149.fs` は INCLUDE しません。
   - 理由: `YM-REGS` は R15 まで書き込むことと、`YM-LEVELS` が32段であることが ZX の宣言と合わないためです。
   - 32状態の envelope と tone/noise の step のアルゴリズムは YM と同じものにしますが、変数は `ZX-` の名前で独立させます。
2. AY の register は書き込み時に mask します（R1/3/5 &15、R6 &31、R8-10 &31、R13 &15）。読み出しも mask 後の値を返します。R13 は同じ値を書いても envelope を再始動します。
3. channel の level は「amplitude bit4 が立っていれば env-state>>1、立っていなければ amplitude&15」とし、`ZX-AY-LEVELS` の16 cell を引きます。
4. 時刻の state は次の4つです: `ZX-TICK`、`ZX-PSG-PHASE`（0..15）、`ZX-FRAC`（0..47999）、`ZX-MODEL`。48K では `ZX-PSG-PHASE` を進めません。
5. 独立 Python は、16段 envelope（level ごとに 2EP の count）と tick 単位の期待値で書きます。Forth と共通の表や関数は使いません。
6. OS ごとの作業は分けたままにします。1169 で行うのは Forth と Python の照合までです。Windows 1170 / Linux 1171 / Mac 1172 の測定と実聴は別作業です。速度の測定は、レモンが開始を確認してから行います。
