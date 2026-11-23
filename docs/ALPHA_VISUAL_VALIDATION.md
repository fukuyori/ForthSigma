# Windowsでの煙と輪郭のアルファ合成確認（1310）

2026-11-23。既存のIMAGE-KEEP-ALPHA、MODE-SOURCE-OVER、PUT-IMAGEを使い、アプリケーション実装は追加変更していない。
[描画結果](measurements/2026-11-23-windows-alpha-visual.png)、[画素照合と実行体SHA-256](measurements/2026-11-23-windows-alpha-visual.json)。

```powershell
python tests/scripts/verify-alpha-visual.py
```

スクリプトが自作のRGBA PNGを2枚生成する。煙は3つの半径の違う雲の密度、
輪郭は幅4画素でアルファが変化する円。完全透明部分には意図的にマゼンタのRGBを入れる。
Windows版Sigmaでalphaを保持して読み込み、640×320の不透明な市松模様へ合成する。
煙は3枚をずらして重ね、円は別の2か所へ置く。

SigmaのPPMから読んだ614,400バイトのRGBは、Pythonで独立に計算した
`(src*a + dst*(255-a) + 127) // 255`の全画素と一致した。
これは不透明背景へのsource-overの検証で、透明な描画先の合成全般を検証したものではない。
PNGの生成結果も画像として確認し、煙の重なり、市松模様が透ける部分、円の柔らかな輪郭があり、
完全透明部分のマゼンタが縁へ漏れていないことを確認した。

この記録はWindows版のファイル描画結果の照合と生成画像の確認であり、
モニターの色管理・校正やnative/Tkウィンドウの実提示の受け入れではない。
アルファ付きPNG保存、拡大時の補間、アルファ付き図形語の要否は1309の判断として残る。
