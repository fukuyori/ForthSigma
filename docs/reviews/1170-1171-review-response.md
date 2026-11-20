# ZX Spectrum Windows/Linux受け入れのレビュー対応

## 測定計画と実施

[計画レビュー](1170-1171-plan-claude-review.md)はHigh/Mediumなし。既定は計時せず32768frame×6負荷の全PCM/39状態/queue2項目を照合する。レモンの開始確認へのＯＫ後だけ `--measure` でWindows→WSL/Linuxの順に7回の別process・順序回転・warmup/RESET/A5前状態確認後のWORKを計測した。

各回の全PCM/状態が一致。ロクが12組すべての中央値/実時間比、8binaryの現物サイズ/hashと332native sourceの現物hashを再確認した。[結果レビュー](1170-1171-results-claude-review.md)はHigh/Mediumなし。レビューは実行していない。[全値・ソース・来歴](../measurements/2026-11-20-zx-spectrum-os-acceptance.json)に保存した。NTIME時刻補正、CPUTIME粒度/2回の呼出し、dense compactionで未適用データMOVEがないこと、slow未測定を明記した。

## 初回送出の修正

Windows最初の実聴は確認されたがunderrun2。無音でも再現した。Windowsの初期8×480frame連続renderに対し、wrapper初回だけmin(blocks,8)×512frameを8192byte bufferへ合成して公開するよう修正。以後512frame、partial offset/timeout/CATCH/cleanup/error優先を維持した。1block/8blockだけの対照比較で対照underrun1/1/1、修正48K0/0/0・128K0/0/0。修正版の実聴もunderrun0。

[修正レビュー](1170-stream-prime-claude-review.md)はHigh/Mediumなし。6構成×19RAM検査で初回/継続のpartial/full/timeout/cleanup、短い/0block、時刻上限、一括PCMとの4096frame境界を照合した。native/core/速度ハーネスは不変で再計時していない。

## Linux初回失敗・診断・物理再試験

物理初回はREADYのみ、SIGINT exit=-2でCATCH/cleanup/再再生は未確認。source/JSONを保持した。[診断レビュー](1171-interrupt-diagnosis-claude-review.md)はNativeScope内だけSIGINTを捕捉する説明と非可聴回路の試験設定変更を妥当とし、物理捕捉の確実性は保証していない。正確な失敗命令位置は特定していない。

無音診断はSigCgt確認→SIGSTOPで固定→SIGINT/SIGCONT注入。捕捉なしでexit=-2、捕捉ありでCATCH=-28/handle0→replay underrun0/DEPTH0/code0。これはプログラム診断であり、物理受け入れではない。

レモンの再開了承後に物理2回目を実行した。Linux helperのみ非可聴B/C period4095、noise31に変更し、独立Pythonの各49152frame/全PCM/39状態を照合、元のtoneA-only実聴PCMともhash一致を確認した。2回目はCATCH=-28/handle0、replay underrun0/DEPTH0/code0となり、レモンが停止と低音再生をＯＫで確認した。物理試行2回のうち成功1回。元の重い設定で成功したとは扱わない。

nativeの捕捉範囲は変えておらず、待機外のCtrl+Cはプロセス終了し得る。初回はプロセス終了によるOSの資源回収で、明示的cleanupを確認していない。中断streamのunderrunも未照会。再試験成功後、残留Sigma/pacatなし、保持用owned sleep1800のcmdlineを確認して停止した。新結果はlinux-r2へ分け、元の失敗を上書きしていない。

## 最終レビューへの対応

[最終レビュー初回](1170-1171-final-claude-review.md)はHighなし、Medium3件。M1の古い未確認文は仕様書の結果節を現在状態に統合して除去。M2は再開了承・物理r2のstdout/exit0/実聴ＯＫ・成功1/2を本書とJSONに追記。M3は試験設定の変更、捕捉のタイミング依存、初回cleanup未確認を仕様書/JSON双方に明記した。

Lowの比較参照は元toneA-only高/低PCMの保存位置をJSONへ追加。r2の実施時刻は記録がなく推測せず、結果記録時刻とstderrがstdoutに合流していることを明記した。

## 現在状態と採否

Windows1170完了、Linux1171も実聴・物理r2成功と最終レビューを経て完了。Mac1172と親1168は未完了。宣言音源は測定範囲でForth維持とし、CPU/ROM全体・任意trace最悪時間・無欠落・Macへの外挿はしない。LinuxはWSL2/RDPSinkで、物理Linux/ALSA直結は未確認。レビューは読み取りのみで、実行/実聴はロクとレモンが別途確認したもの。今回コミット/プッシュは行っていない。

## 最終評価

[追確認レビュー原文](1170-1171-final-followup-claude-review.md)はHigh/Mediumなし、3件のMediumはすべて解消。Lowの失敗回のhuman pendingは結果JSON側でfailed/not applicableとし、準備snapshotは記録当時の状態と明記した。比較PCMの参照先も仕様書に記載した。原文レビューと元の失敗ファイルは改変していない。1170/1171完了、1172と親1168未完了auto75%。
