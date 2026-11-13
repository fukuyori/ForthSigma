# P02 数値演算・数値入出力の実装記録

2026-11-13。管理タスクは545、子557（P02a）、558（P02b）、559（P02c）。対象語と完了条件は[実装フェーズ](GFORTH_WORD_PHASES.md)、比較元は[P00仕様](GFORTH_P00_SPEC.md)と保存済みケースに従う。

## 整数演算（32語）

符号付き除算のF系は床関数、S系は0方向への切捨て。剰余と商を返す語は剰余を先、商を上へ置く。乗除算は積を128ビットで保持する。ゼロ除算は既存Sigma同様-10、セルの商が表現できなければ-11。MOD系でも商の範囲を検査する。

U系は64ビットの符号なしセルを扱う。UD/MODは符号なし128ビットを割り、剰余セルと二倍長商を返す。DU/MODは符号付き128ビットを符号なしセルで床除算し、**符号なし剰余、符号付きセル商**を返す。比較元のスタック表記の型名だけで判断せず、負数も実測した。

利用者の「おすすめで」により次を確定した。

- ARSHIFTは算術右シフト。シフト数を符号なしとして扱い、64以上は符号埋め（0または-1）。
- DLSHIFT/DRSHIFTは128ビットの論理シフト。128以上は0。DARSHIFTは算術シフトで、128以上は符号埋め。
- DROL/DRORは128ビット回転、回転数mod 128。
- WROL/WRORは下位16ビット、LROL/LRORは下位32ビットを回転。上位を0にし、回転数は各幅で剰余を取る。負数の生セルも符号なしの回転数として扱う。

指定GforthではARSHIFTの64以上が折り返す。二倍長シフトは0や64以上の境界、狭幅回転は範囲外の回転数や入力上位ビットで、文書上の意味と異なる結果がある。Sigmaは上の確定仕様を採用し、Gforthとの共通比較とSigma固有の境界検証を分けた。例：指定Gforthの`1. 128 DLSHIFT`は2^64、Sigmaは0。指定Gforthの`-8 64 ARSHIFT`は-8、Sigmaは-1。

CTZは0で64、LOG2は0で-1。POW2?は1ビットだけ立つ値で真=-1。>POW2は切上げた2の累乗を返し、入力0または64ビットを超える結果は0。MUXはマスクの1ビットで第1入力、0ビットで第2入力を選ぶ。

## 浮動小数点（16語）

f64と独立Fスタックを使用する。INF/INFINITY、-INF/-INFINITY、NAN、1/F、F2*、F2/、FCOPYSIGNはIEEEの無限大・NaN・符号付き0を扱う。NaNペイロードの一致は要求しない。

F*+はr1+r2*r3を1回だけ丸める融合積和。別々の乗算・加算との差が出る`-1 + (1+2^-27)*(1-2^-27) = -2^-54`を回帰検証する。Gforthの全環境との最終ビット一致は要求しない。

F~ABSは`abs(r1-r2) < r3`、F~RELは`abs(r1-r2) < r3*(abs(r1)+abs(r2))`という厳密な不等号。比較元の説明にある`abs(r1+r2)`とは異なるが、指定ビルドの逆符号入力で確認し、既存F~の相対誤差と同じ意味にした。

V*は内積、FAXPYは要素順にy=a*x+yを更新する。ストライドは符号付きのバイト数で、負数・0を許す。要素数0はアドレスを参照せず、V*は+0を返す。両ベクトルの全範囲を端点と128ビット算術で事前検査し、範囲外時にFAXPYを部分書込みしない。重複する領域は逐次処理の順序で参照する。これらの配列演算は融合丸めを要求しない。

## 変換・表示・乱数（17語）

- >FLOAT1は指定された1バイト文字を小数点とする。空／空白だけの文字列は0。変換成功時だけFスタックへ値を置く。失敗時のフラグは0。cは任意の1バイトで、数字・符号・e/E・空白を指定した場合もその文字を小数点として扱う（指定Gforthと比較済み）。
- BASE-EXECUTEは2〜36の基数でxtを実行し、正常終了・THROWの双方で元のBASEへ戻す。
- CONVERTは先頭の1バイトを飛ばし、BASEの数字を符号なし二倍長へ累積し、最初の未変換文字のアドレスを返す。累積は128ビットで折り返し、メモリー範囲は検査する。
- DPLは論理アドレス0x0d50。整数変換の最後の小数点から後ろの文字数、単セルや失敗では-1。新VMでは-1。通常の数値リテラルやS>NUMBER?でも更新する。
- DEC.は符号付き10進。DEC.Rは**符号なし**10進右寄せ。指定Gforthは負の生セルを符号付きで表示するが、利用者の「おすすめで」により文書上の符号なし契約を採用した。
- H./HEX.は符号なし16進を$接頭辞付きで表示。DEC.、DEC.R、H./HEX.はBASEを変更しない。
- UD./UD.RはBASEで符号なし二倍長を表示。右寄せは末尾空白なし、それ以外の整数表示は末尾空白あり。
- E.は元のf64へ戻る最少の有効桁数を選ぶ。E.EXACTは完全な十進値、E.Pは指定の有効桁数（1〜1000、範囲外-11）を使い、丸め前の値で指数を避けられる場合に1桁追加する。例えば999.9eを3桁で表示すると1e3、1000eは1000eとなり、指定Gforthと一致する。eマーカーを付け、末尾空白は付けない。E.EXACTは最小サブノーマル値も含めて確認する。
- FP.はPRECISIONを使う工学表記とSI接頭辞（10^-30〜10^30、microはASCII u）。範囲外はE指数。NaN・無限大も含め末尾空白あり。
- SEED!はVMごとの64ビット乱数状態を設定する。RNDは次の生セル、RANDOMは符号なし上限未満を返し、上限0では0。同じ種の列を再現するがGforthの列との一致は要求しない。Sigmaでは64ビットLCG（乗数6364136223846793005、加数1442695040888963407）と、上限との積の上位64ビットを使用する。暗号用途の乱数ではない。新VMの種はホストのUnix epochマイクロ秒の下位64ビット、時刻の取得口がない／失敗する場合は0（P00確定仕様）。乱数状態は辞書イメージへ保存しない。RNDはLCGの生状態なので下位ビットは弱く、最下位ビットは交互に反転する。範囲を選ぶ用途はRNDの下位ビットをマスクせずRANDOMを使う。

## 検証結果

通常構成と全機能群無効構成のzig build testが成功。src/tests/p02a_test.zig、p02b_test.zig、p02c_test.zigをルートテストから取り込み、辞書イメージの復元・追加後の新語実行も確認した。

|検証|ケース数|範囲|
|---|---:|---|
|P02a|3,521|Gforth共通2,888、Sigma境界方針633|
|P02b|259|基本16、IEEE・比較・ストライド等243。FAXPYの負・0ストライドと重複も比較|
|P02c|119|基本13、変換等70、表示捕捉28、E.P表記6、SigmaのDEC.R方針2|
|計|3,899|意図した比較元との差も含む。全件のGforth一致を意味しない|

初回コミットc3cde8aをpush後、Claude Code Sonnetへ読取専用レビューを依頼し、P2 1件・P3 8件を修正／比較実測／文書化した。[レビュー記録](P02_REVIEW.md)を参照。再レビューは全件解消・新たな具体的問題なし。tque 545/557/558/559は完了・auto、レビュー対応は614。Windows/Linux確認は607へ分離。

## 検証と再実行

```sh
ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache" zig build test --cache-dir .zig-cache
ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache" zig build test \
  -Dfloat=false -Dgraphics=false -Daudio=false -Dfiles=false \
  -Dimage=false -Dhelp=false -Dtools=false -Ddebug=false --cache-dir .zig-cache
ZIG_GLOBAL_CACHE_DIR="$PWD/.zig-global-cache" zig build --cache-dir .zig-cache
python3 scripts/verify-p02a.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build --report .work/p02a-check/results.json
python3 scripts/verify-p02b.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build --report .work/p02b-check/results.json
python3 scripts/verify-p02c.py zig-out/bin/sigma --gforth-build .work/gforth-audit/gforth-build --report .work/p02c-check/results.json
```

--gforth-buildなしではSigmaのみ検証する。P02cの元の表示4ケースは未実装の>STRING-EXECUTEを使うため、ホスト側で出力を捕捉するケースに置き換えた。E系の表記全体のバイト一致ではなく、値と符号付き0の復元を検証する。Zigの回帰ではF*+の融合丸め、E.EXACTの完全な値、入力不足、範囲外時の非部分書込みも確認する。

比較元はP00と同じ作業用Gforth 1.0.1 arm64。コードの転用はしていない。ログ／JSONはGit管理外の.zig-cacheと.workへ保存する。Windows/Linuxの確認は利用者の指示によりここでは実施せず、別環境の確認へ引き継ぐ。版番号変更・パッケージ作成は行わない。

## レビューで明確化した制限

V*/FAXPYとDEC.R/UD.Rの長いネイティブループは、debug有効構成の--max-stepsに256回以下の処理を1単位として計上する。直接呼出しでも有効で、StepLimit（-280）は既存仕様どおりCATCHで捕捉できない。通常のコンパイル済み実行ループは変更していない。既定値0では無制限で、debug無効構成にはステップ制限がない。中断前の計算／書込み／出力は巻き戻さない。これは範囲検査失敗時に部分書込みしない保証とは別である。既存.R等のループには今回変更を加えていない。

HEX等の基数では、E.やDEC.を数値リテラルとして書いていたコードが新しい語に解決される。数値は$E.、$DEC.のように接頭辞を付ける。既存サンプルのRND/RANDOM再定義は従来どおりその定義が優先されるが、組込語と同名のため再定義警告・lintのREDEFINEDが出る場合がある。
