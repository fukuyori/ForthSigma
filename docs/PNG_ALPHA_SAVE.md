# アルファ付きPNG保存（1309）

本書は内部実装・検証記録。利用者向けの説明は英日GRAPHICS_AND_SOUNDと全語リファレンスに記載。

2026-11-23、利用者の追加指示により実装。既存のSAVE-PNGはRGBのまま、次の2語を追加した。

| 語 | スタック | 動作 |
| --- | --- | --- |
| SAVE-PNG-ALPHA | ( c-addr u -- ) | 描画先画像をRGBA8 PNGへ保存。ファイルエラーをTHROWする。 |
| GFX-SAVE-PNG-ALPHA | ( c-addr u -- ior ) | 同じ保存処理でiorを返す基本語。 |

描画先はDRAW-TOで選ぶ。CLIP!に関係なく画像全体を保存し、透明度0の画素も元のRGBを保持する。
straight RGBA8（PNG color type 6）であり、premultiplyや背景色への合成はしない。
画面を描画先にした場合は、すべての画素のアルファが255になる。
DISPLAY-COLORSやDITHERによる色数の変換は行わない。

従来のストリーミングPNG writerをRGB/RGBAでコンパイル時に分けた。RGB/Tk用の行バッファは従来のままで、
RGBA保存だけ4バイト/画素の行バッファを使う。画像全体の追加確保や外部ライブラリ追加はない。
フィルター0・非インターレース・stored deflateは従来と同じ。ファイルのopen/write/closeエラーの順序も共通処理。
-Dfiles=falseでも利用でき、-Dgraphics=falseでは語が存在しない。

```forth
REQUIRE-GRAPHICS ALSO GRAPHICS
2 2 NEW-IMAGE DRAW-TO
$336699 GFX-CLS 128 GFX-ALPHA-CLS
S" translucent.png" SAVE-PNG-ALPHA
```

例の画像は2×2の半透明青。不透明な画面へ戻すにはSCREEN DRAW-TOを使う。
読込みでアルファも保持するには、LOAD-IMAGEより前にTRUE IMAGE-KEEP-ALPHAを指定する。

## 検証

[通常版の結果と実行体SHA-256](measurements/2026-11-23-png-alpha-save.json)。

```powershell
zig build test --summary all
zig build -Doptimize=ReleaseFast
python tests/scripts/verify-png-alpha-save.py --output docs/measurements/2026-11-23-png-alpha-save.json
```

通常テスト1373成功・25skip。追加の回帰では透明度0/1/128/255、透明なマゼンタのRGB保持、
CLIP!と表示色設定の非適用、public/primitive一致、画面の不透明さ、open/write/closeのエラー順序を確認。
PythonのCRC32・zlibで独立に復号し、1×1、3×2、64×255、128×128、16384×1の全RGBA画素を期待値と照合した。
64×255はrawがちょうど65,535バイトで1ブロック、128×128と16384×1はブロックをまたぐ。Sigmaへ再読込みした全画素の色とアルファも一致。
同じ画像をSAVE-PNGで保存した場合はcolor type 2でRGBだけとなることを確認した。

Builtin追加で保存辞書ABIが変わるため、以前の保存アプリ・イメージは作り直す。
1309全体は未完了。拡大時の補間とアルファ付き描画語の要否は未決であり、今回の保存追加から推定しない。


-Dfiles=falseのReleaseFast実行体でも同じ5寸法が成功した。
[files除外の結果](measurements/2026-11-23-png-alpha-save-no-files.json)。
-Dgraphics=falseのテストは1201成功・193skip。実辞書の全語照合、EKEYS35値、文書例28件・単独使用例426件も成功し、文書チェックは指摘0。

[Claude Codeレビュー原文](reviews/2026-11-23-png-alpha-claude-review.md)はHigh/Mediumなし。
[対応記録](reviews/2026-11-23-png-alpha-response.md)を参照。
