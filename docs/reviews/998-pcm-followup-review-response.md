# PCM998残件：Claudeレビューの評価と対応（2026-11-20）

[初回原文](998-pcm-followup-claude-review.md)と[修正後原文](998-pcm-followup-final-claude-review.md)を保存する。レビューはRead/Glob/Grepだけで実施し、実行結果とは区別する。今回はPCM基盤の変更ではなく、除外検査と実聴用スクリプト・記録の追加。

| 指摘 | 判断と対応 |
| --- | --- |
| H1 22050Hzに32768frameは不正 | 採用。初回レビュー中に無音実行でも-24を確認し16384へ修正。両OSのcase2成功 |
| H2 Ctrl+CがPython親も中断する | 採用。case8実行中だけ親にcaught no-op SIGINT handlerを置き、終了後に復元。SIG_IGNの子継承は避ける。stdoutを表示しながら記録する |
| M1 全量空き待ちと波形の位相飛び | 採用。4800frame=55周期のblockと4800frame分の空き待ちへ変更。途中でqueueを空にする契約にしない |
| M2 drain後に終了してしまう | 採用。case6は1秒、ほかは250ms保持。engine drainとdevice再生位置を区別する |
| M3 PCM2語だけの確認 | 全7組14語へ拡張。無効版ではAUDIOが利用不能で現在検索順から見つからないことを示し、バイナリ内の全コード除去まで証明するとは記述しない |
| L1 無音の混合は実聴でない | 採用。無音case3ではMMLを送らず、case4のSFXも振幅0。audible混合は実聴待ちと明記 |
| L2 discard表示・underrun・再開の説明 | DISCARDEDを実行時に照合しUNDERRUNSをJSONへ数値記録。再開は先頭からの再生とする |
| L3/L4 cleanup失敗の優先、-528共有 | 本体例外を優先する既存の契約を維持。cleanup失敗は成功として扱わずprocess終了時のhost回収へ進む。期限エラー等の-528共有はこの補助スクリプトの制限 |
| L5 case8出力未記録 | teeしたstdoutをJSON保存し、CATCH=-28/CLOSE=0/helloと終了codeを照合する |
| L6 パスの制限 | quote/改行を拒否、SAVESYS確認は空白なしのcheckoutを要求し、曖昧に解釈しない |
| L7 辞書容量 | 両OSの全caseと保存アプリを実行して確認。case2の264600byte配列も成功 |

修正後の再レビューは対象5点にHigh/Mediumなし。残るLowはCtrl+Cを押すタイミングと出力flush。READY後に1回だけ押す手順を記載した。Windowsの専用非表示console全体へのCTRL_C_EVENT、Linuxの専用process group全体へのSIGINTを実際に送り、親Pythonの継続・Sigmaの-28/close0・CLOSE表示後の合成hello入力・JSON保存まで確認した。両OSでCLOSE行はhello投入前に観測できたが、全端末での物理入力・実聴を確認した意味ではない。

1159/1160は元の保存済み実行体16構成と新実行体4構成で成功し完了。実聴1148/1149は未完了。Linux現環境はAUDIO?=0で、システム変更はしていない。[手順と検証範囲](../PCM_LISTENING_ACCEPTANCE.md)。
