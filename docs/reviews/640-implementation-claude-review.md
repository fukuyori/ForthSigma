# 640 実装レビュー原文

2026-11-20。固定コピーに対する読み取り専用レビュー。実行試験は別途ロクが実施。

# タスク640 実装レビュー結果

**結論：高・中の不具合は見つかりませんでした。** 中程度の指摘が2件あり、どちらも試験の自動化と文書の問題です。境界判定、スタック処理、メモリ検査、生成器、画像の扱いは、採用設計と UAX #29 rev49 に合っています。

この確認は Read/Glob/Grep だけで行いました。ビルドと試験は私は実行していないため、853ケース／3096チェック成功という結果は未確認です。

## 正しいと確認した点

- **GB9c**
  - `grapheme.zig:42` は、InCB=Linker で状態を立て、InCB=Extend で保持し、それ以外で解除します。設計どおりです。
  - 公式試験の `GraphemeBreakTest.txt:179`、`:659`、`:879` では、直前に子音のない `094D × 0915`、`1CF5 × 0915`、`11A3A × 11A0B` も結合しています。18.0.0 の GB9c が「Linker Extend* × Consonant」であることはこの試験データで裏付けられ、実装もそれに合っています。
  - U+200D は InCB=Extend、U+200C は InCB=None として表から引かれます。2種類の Extend は混ざっていません。
- **GB11**
  - `consume` は、`pictographic_zwj` を更新前の `pictographic_extend` から計算します。
  - ZWJ が2つ続くと状態が切れます。拡張絵文字が GCB=Extend の文字や InCB=Linker の文字を挟んで続く場合も、状態は正しく保持されます。
- **RI**：`ri_odd` は直前が RI かどうかだけで奇偶を切り替えます。RI と RI の間に Extend を挟む場合と、RI が3つ続く場合を確認しました。
- **規則の順序**：GB3、GB4/5 の後に GB6〜9b、GB9c、GB11、GB12/13 の順で判定しています。抑止する規則どうしは順序を入れ替えても結果が変わらず、GB4/5 が先に判定されることも守られています。
- **前方探索の範囲**：前方では、境界を見つけた時点で、すでに復号した先読み1コードポイントを使ってすぐ返ります。それより後ろのバイトは復号しません。`"ab\xFF"` の試験もこの動作を固定しています。
- **スタック**
  - `requireDepth`、`peek`、`memoryAddress`、`size` がすべて成功してから、スタックを1つ減らします。
  - 負の長さは `std.math.cast` で -9 になります。
- **画像**：`Builtin` は末尾に追加されています。`layoutSignature` は `Builtin` の名前と値を署名に含めるため、古い画像は自動的に拒否されます。
- **生成器**
  - 生成前に、入力すべての SHA256 と版を検査します。
  - InCB と GCB の値名を固定リストの `index` で引くため、未知の値があれば生成が止まります。
  - 18.0.0 の InCB の値は Linker、Consonant、Extend の3種だけです（`DerivedCoreProperties.txt:13323/13352/13437`）。

## 中程度の指摘

**M1. 公式適合試験が通常の試験経路に入っていない**
- 現状：`GraphemeBreakTest` の照合は `tests/scripts/verify-graphemes.py` を手で実行したときだけ行われます。`build.zig`、`forth_test.zig`、`check-docs.py` からは呼ばれていません。`make-grapheme-table.py --check` も同じ状況です。
- 影響：
  - 表や状態遷移を変えて回帰しても、`zig build test` では検出できません。
  - Zig の単体試験には、国旗の奇偶と絵文字の ZWJ 列の試験がありません。
- 修正案：
  1. `build.zig` で試験モジュールに `addAnonymousImport("grapheme_break_test", .{ .root_source_file = b.path("tests/data/unicode-18.0.0/GraphemeBreakTest.txt") })` を追加します。
  2. `grapheme_test.zig` でそのファイルを `@embedFile` で取り込み、全行を `grapheme.size(…, false/true)` で照合する試験を追加します。製品バイナリには含まれません。
  3. 公開語を通す試験としては `verify-graphemes.py` を残します。
  4. `scripts/check-docs.py` の検査に `make-grapheme-table.py --check` を加えます。

**M2. 文書が実装に追いついていない**
- `tests/data/unicode-18.0.0/README.md:11-12` に「A table generator and executable conformance tests have not yet been implemented.」と書かれていますが、生成器も試験もすでにあり、記述が事実と異なります。この README には日本語版もありません。
- `tests/scripts/README.md` と `README.ja.md` に `verify-graphemes.py` の説明がありません。
- 修正案：
  - データ README の該当文を、生成器 `scripts/make-grapheme-table.py [--check]` と照合スクリプト `tests/scripts/verify-graphemes.py --sigma PATH` の使い方に書き換え、`README.ja.md` も作ります。
  - 両方の tests/scripts README に、実行例を1行ずつ追加します。

## 低（参考）

- `verify-graphemes.py` は `GraphemeBreakTest.txt` の SHA256 を manifest と照合していません。生成器と同じ検査を、先頭に3行ほどで追加できます。
- 不正 UTF-8 の試験は、長さが不足する列（`\xE2x`、`\xE2\x82`）だけです。長さは足りていて継続バイトが不正な列（例：`\xE2\x28\xA1`、`\xF0\x9F\x98x`）が含まれていません。
- 機能を除外したビルドの試験では、`executeBuiltin` と HELP は確認していますが、辞書で語が見つからないことは確認していません。
- 生成された `grapheme_data.zig` の先頭には、入力の SHA256 が書かれていません（記録は manifest にあります）。設計の「生成器は入力の版とSHA256を記録」を manifest の記録で満たすと判断してよければ、対応は不要です。

レビューのみのため、tque への登録は行っていません。M1 と M2 の修正や登録を進める場合は指示してください。
