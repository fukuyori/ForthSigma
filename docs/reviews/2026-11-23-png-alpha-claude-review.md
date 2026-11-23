# アルファ付きPNG保存 Claude Codeレビュー

読み取り専用。実行検証はロクが担当。

# SAVE-PNG-ALPHA 読み取り専用レビュー

レモン、レビュー結果です。使ったのは Read/Grep/Glob だけで、ビルド・テスト・Python は実行していません。以下は**コードを読んだ結果**です。テスト1373成功・25skip、Python による4寸法の復号、Sigma への再読込みが成功したという点は、ロクの報告をそのまま引いています（私は再実行していないので未確認）。

## 結論：High・Medium はありません

ご指定の観点はすべて問題なしと判断しました。

| 観点 | 結果と根拠 |
|---|---|
| RGB 経路の互換 | `writePng` は `writePngPixels(..., false)` を呼ぶだけです（`src/core/words_graphics.zig:765-767`）。`alpha` はコンパイル時の定数なので、RGB 側は `channels=3`・IHDR type 2・行バッファ `1+3*max_side`・アルファ書込みなしで従来と同じです。Tk（`tcl.zig:585`）が使う `pngLength` と `max_message` も RGB 前提のまま変わっていません。 |
| RGBA の byte 順序 | R=`>>16`、G=`>>8`、B=下位8bit、A=`>>24` の順です（`:798-801`）。PNG type 6 の R,G,B,A 順と合っています。 |
| alpha 0 の RGB | 合成や premultiply をせず、下位24bit をそのまま書いています。ユニットテスト（`graphics_test.zig:1752`）で `$FF00FF`/α0 を確認済みです。 |
| パレット・clip が効かないこと | `.png_alpha` は `mode=null` を渡します（`:610`）。行は `canvas.pixels` の全幅・全高から読み、`clip` を参照していません。 |
| screen が不透明なこと | GFX-INIT が `opaque_alpha` で塗ります（`:140`）。描画は `color()` と `forcedAlpha()`（`graphics_images.zig:351-353`）で screen の α を 255 に固定し、`setAlpha`/`fillAlpha` は screen を拒否します（`:239`, `:248`）。保存側で特別な処理をしなくても α=255 になります。 |
| 最大幅と stored block | 最大の 16384×16384 RGBA で raw=1,073,758,208、blocks=16385、IDAT 長は約 1.0738e9 です。PNG の上限 2^31−1 にも `@intCast` の u32 にも収まります。BFINAL は `length == stream.left` で正しく決まり、LEN/NLEN と Adler-32 は既存の処理と同じです。 |
| サイズ計算・行バッファ | `row_size = 1+channels*width` と `raw = height*row_size` が、ブロック分割・IDAT 長と一致しています。行バッファは `1+4*16384` で全幅を収められます。 |
| エラー処理 | open の失敗は即座に ior を返します。書込みの失敗は最初の ior を保持し、以降の書込みは止めますが close は必ず実行し、返すのは書込み ior が優先です。PPM/BMP/PNG と同じ共通処理で、テスト（`:1758-1777`）でも確かめています。 |
| Builtin 登録と ABI | `defs.zig:1218`・`words`（`:30`）・`definitions`（`:67`）のいずれも末尾への追加なので、既存語の番号は変わりません。`graphics_builtins` に入るため、`-Dgraphics=false` では語が除かれます。 |

## Low（修正するなら）

1. **`src/graphics/graphics.fs` 冒頭の GFX 語一覧**（`:12-16`）に `GFX-SAVE-PNG-ALPHA ( c-addr u -- ior )` がありません。今回の対象範囲なので、16行目の後に1行足すのが妥当です。
2. **Zig のユニットテストが複数 block を通っていない**：2×2 は1ブロックで終わり、ブロックをまたぐ確認は Python スクリプトだけです。例えば 64×255（raw がちょうど 65535 で、1ブロック・BFINAL の境界）と 128×128 の RGBA を、既存の RGB テストと同じ CRC/LEN/Adler の検査で確かめるテストを追加すると、`zig build test` だけで回帰を検出できます。
3. **screen の保存テスト**（`graphics_test.zig:1754-1755`）は α の4バイトしか見ておらず、`expectStack(0)` と IHDR type 6 の確認がありません。2行足せば済みます。
4. **行バッファのスタック使用量**：RGBA では 65,537 B で、RGB より約16 KiB 増えます。呼ぶのはインタプリタのスレッドだけで、Tk 経路は RGB のままなので、実害は小さいと推測されます。

## 確認事項（レビューの範囲では未確認）

- `docs/PNG_ALPHA_SAVE.md` は日本語だけです。利用者向けの文書として扱うなら英語版と `.ja.md` の2本が必要です。検証記録の扱いでよいかを確認してください。
- 文書の「-Dfiles=false でも利用でき」：この語は `file_builtins` に入っていないので除外はされません。ただ、実行には `writer.file_ops` が要ります。files=false のビルドでホストが `file_ops` を渡しているか、このレビューでは確認していません。
- 文書の「Builtin 追加で保存辞書 ABI が変わる」：SIGIMG46 の読込みで、graphics 定義が1語増えた影響をどう扱うか（拒否するのか、再配置するのか）は読んでいません。

## レビューした範囲

`words_graphics.zig` の 30・67・263-273・565-811行、`defs.zig` の 1180-1219行、`help_text.zig` の 1157-1158・1174-1175行、`graphics.fs` の 1-68行、`graphics_test.zig` の 1675-1777行、`verify-png-alpha-save.py` の全体、`PNG_ALPHA_SAVE.md` の全体、`graphics_images.zig` の 1-300・336-473行です。files=false の実ホスト配線、SIGIMG46 の互換、他の docs 差分は範囲外としました。