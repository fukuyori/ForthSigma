# レビュー結果：-ROT特殊化（#790/#826〜830）

候補コードに欠陥は見つからず、測定停止と採用保留の判断も妥当です。ただし文書に、根拠より強く読める記述が2点あります（下記「重大」）。確認は Read/Grep/Glob のみで、再実行・変更はしていません。

## 重点項目の判定

| 項目 | 判定 | 根拠 |
|---|---|---|
| エラー優先 | 問題なし | `candidate/src/forth.zig:2015` は既存 `executeBuiltin` をそのまま inline しており、実行→`checkOutputError`→`try result`→coverage の順（`:2214-2227`）が保たれる。新テストは pending -123 と underflow の同時発生で `error.Thrown` が先になることを両ループで検査している。 |
| PC | 問題なし | 範囲検査と `outer_pc` 更新は分岐の前に残っている（`:2011-2012`）。-ROT 経路は `boundary_running` を作らないが、基準でも `builtinInLoop` が frame を書き換えるのは CATCH だけ（`:1630`）なので、`pc`/`end_pc`/`failed_pc` は同じ値になる。 |
| 計数（counted ループ） | 問題なし | `ran`・step 上限・profile・stepper はすべて switch の前（`:1878-1885`）で、差分の外にある。 |
| 計数（Callgrind） | 数値は一致 | 自己計数の合算で 194 = 81+22+35+56、131 = 75+56 を再計算で確認。Dr 52→31、Dw 31→12、rotate 自己計数 56/8/7 も記録どおり。 |
| 画像互換性 | プローブ範囲内で妥当 | 差分は `forth.zig` の1箇所だけ。`layoutSignature` は OpKind/Builtin の全名・値を hash する（`image_format.zig:436-439`）ので、タグを追加しない設計理由は正しい。4回の LOAD と SEE 一致も記録どおり。 |
| 測定停止 | 妥当 | 中央値と差を再計算し、3.5398% / 2.9586%、最小中央値 5,281,250 µs で一致。`run.py:15` の停止条件は `protocol.json` と同じ。 |
| 候補未計測 | 裏付けあり | `commands.json` は pilot・aa×2 のみ。子プロセス25個はすべて基準の sha `379d…`。`compare-*`・`target-result.json`・`complete.json` は存在しない。 |
| 採用保留 | 妥当 | 「遅い候補と判断したものでもない」「命令数から速度を推定しない」の記述は根拠の範囲内。 |

反復数 349,090,910 と checksum 231 / 312 も式どおりです。

## 重大な修正事項

**1. Linux回帰を「完了した」とする記述は根拠を超えている（文書34行目、PLAN.md 3行目）**

- `candidate-linux-{debug,fast}-tests.log:56` は「9/21 steps succeeded (11 failed)」。
- `validate.py:16` が WSL で再実行するのは `test` という名前の ELF 2本だけ。
- 残り9ステップは `sigma` 本体の CLI 実行（STDIN READ-LINE、XKEY/ACCEPT、引数ファイル、`--evaluate` など）で、候補の Linux 版では Debug/fast とも実行されていない。
- 1,014/5 と 63/1 は実測どおり。
- 修正案：「Linuxは単体テストELF 2本のみWSLで確認。CLI実行9ステップ×2構成は未実行」と明記し、PLAN.md の「構成別両OS回帰…まで完了」も同じ範囲に限定する。

**2. Callgrind の対照は、分岐が追加された経路を通っていない（文書26行目）**

- 候補は `call_builtin` 全体に `target_builtin == .minus_rot` の比較を足している。
- ROT 対照と stacks 対照は primitive タグだけで動く。両版とも `builtinInLoop` への呼出しエッジが0。
- したがって「132・326命令は変わらなかった」が示すのは primitive 経路の非変化だけ。-ROT 以外の `call_builtin` 語への影響は命令数でも未確認。
- 修正案：その範囲を文書に明記し、再評価の事前計画に「-ROT 以外の call_builtin 語」の対照を入れる。

## 任意事項

- **冒頭の太字が古い。** 「生成コード確認へ進む。本体未反映・速度未測定」のままなので、最終状態（校正未達・候補未計測・採用保留）に更新するとよい。
- **画像確認とCallgrindは凍結版と別の実行体で行われている。**
  - 画像確認の候補は `windows/bin/sigma.exe`（strip=false、2,057,216 bytes）で、凍結候補 `dc417e…`（1,810,944 bytes）ではない。
  - 基準は `.work/rot3-20261116` 側の実行体（sha は `379d…` で一致）。
  - Callgrind も両版ともシンボル付き版。
  - 文書に一文あると誤読を防げる。
- **保存画像のハッシュは異なる。** 2画像は同じ 87,303 bytes だが sha256 が違う。SAVE のパス名（baseline/candidate）が画像に入るためと推測するが、未確認。「バイト同一ではない、原因未特定」と書くのが安全。
- **`root_runtime_unchanged: true` の根拠が記録にない。** `worker.py:10` が照合する `frozen-sources.json` は候補コピーの5ファイルだけ。本体ソースは git 状態から未変更と分かるが、本体 Windows 実行体のハッシュ照合は記録されていない。
- **`image_format.zig`・`image_encoder.zig` の同一性は記録からは確認できなかった。** `frozen-sources.json` にこの2ファイルの候補側ハッシュがなく、「バイト単位で同じ」は未照合（`defs`・`words_stack` は一致）。
- **40行目「追加処理の負担も含む」は不正確。** thread/cycle の読取りと Toolhelp スナップショットは親プロセス側で動き、子は KEY 待ち。子の `GetProcessTimes` 差分には直接入らない。
- **校正データの観察事項を再評価の条件整備に使える。** いずれも候補の評価ではない。
  - 系列1は kernel 時間が約1.08〜1.44秒、系列2は約0.17〜0.39秒と大きく違う。
  - wall が CPU より約0.1〜0.7秒長い。
  - pilot からの見込み6秒に対し、実測は約5.3〜5.5秒。
  - 「独立2系列」は約0.2秒間隔の連続実行。
- **Windows の生成コードは未確認。** 3呼出し→1呼出しは Linux の計数のみで、文書もそう限定している。
- **`run.py`・`worker.py` のハッシュが記録にない。** `start.json` は protocol の sha だけなので、次回はスクリプトも凍結するとよい。
- **テストの補強候補。** CATCH 内の -ROT 失敗、step 上限・WATCH・profile 併用時の -ROT は個別テストがない（該当コードは差分の外）。