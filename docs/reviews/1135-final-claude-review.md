レモン、最終レビューの結果です。ファイルを読んだだけで、コマンド・テスト・git・tque CLI は実行していません。そのため、テストの結果、tque の現在の状態、git の状態は未確認です。

## 結論
- **High:** なし
- **Medium:** なし。M1〜M4 はすべて解消していました。

## M1〜M4 の照合
- **M1:** 解消。`verify-nes-apu.py:184` で、出力の SHA256 を `c63131af…d94755` に固定して照合しています。docstring の「four-channel」も消えています（`verify-nes-apu.py:2`）。
- **M2:** 解消。`verify-nes-dmc.py:31` の最後の場面は `(5,0,0x4010)` で、rate を 15 から 0 に変えています。`verify-nes-dmc.py:46` の手計算の期待値 `26/213/0/213/0` も合っています。cycle 2 で 26 を読み込み、偶数 cycle の 4〜54 の 26 回の clock で 0 になり、cycle 56 で 213 を読み込みます。
- **M3:** 解消。
  - `tasks-review.json`: 1139 は「先行照合…最終採否は別工程」です。1140 の depends_on は 1132/1136/1137/1138/1139 で、blocked は true です。999 は effective 21 です。
  - 同じ内容が `EMULATOR_CORE_PLAN.md:98-100`、`CORE_EXTENSION_PLAN.md:200`、`HANDOFF.md:7` に入っています。7枝で 21% になること、不足が見つかったら子タスクと 1140 の依存を追加すること、分母が増えると表示が下がる場合があることも書かれています。
  - `HANDOFF.md:13,17` の 25%/6枝 は、`HANDOFF.md:7` で「1140追加前の履歴」と明示されています。
- **M4:** 解消。`NES_DMC_FORTH.md:54` に、1134 の全 process 時間と直接比べないことが書かれています。fast_dac_8khz の測定区間に enqueue と領域回収が入ることも書かれています。この点は benchmark の scope（`verify-nes-dmc.py:116`）にもあります。結果欄は、指示どおり書き込み待ちとして扱いました。

## Low 項目の照合
- 折り返しの手計算試験（`verify-nes-dmc.py:47`）と、remaining>0 のときに再有効化しても再開しない試験（`verify-nes-dmc.py:48`）が入っています。後者の期待値 `32/49153` は、cycle 1 で取り込んだ後の値と合っています。
- 重複していた `import time` は削除済みです。
- LUT の最大値は、report の `pulse_max`、`tnd_max`、`maximum_sum` に記録されます（`verify-nes-dmc.py:59`）。

## 任意の文言修正（Low、直さなくても動作に影響なし）
1. `NES_DMC_FORTH.md:3` の「対象一覧1139」を「先行照合1139」にすると、tque の題名と揃います。
2. `verify-nes-dmc.py:49` の case 名に、追加した rate 保持・折り返し・再開しない試験が入っていません。report に残す名前で区別したい場合は、例えば `hand-delta-parity-silent-irq-rate-retain-wrap-no-restart` に変えます。

ハードウェア DMA とネイティブ実装は範囲外のままとし、今回は扱っていません。
