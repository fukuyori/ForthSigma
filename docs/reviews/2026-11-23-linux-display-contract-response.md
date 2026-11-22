# Linux共通受け入れのレビュー対応（2026-11-23）

[Opus 5.5レビュー原文](2026-11-23-linux-display-contract-opus55.md)。今回の変更は検証と文書であり、実行時コードや公開APIは変更していない。

| 指摘 | 対応 |
| --- | --- |
| graphics除外の存在確認は、未ロードの通常ビルドでも通る | REQUIRE-GRAPHICSの-270とGRAPHICSの不在を追加。同じ語の一覧が通常ビルドのロード後に存在することも対照として検査 |
| Tkへの切替後のサイズはnativeのサイズではない | GFX-WINDOW-STATEのnative幅・高さを別フィールドで取得し、Tkの値と独立に照合 |
| 保存アプリだけstdoutのエラー検出が弱い | 全実行を共通invokeへ集約。BACKTRACE/STACK UNDER FLOWの検査と、timeout時を含め所有プロセスグループの回収を共通化 |
| Tk行の未確認フィールドとno-X11のエラー | native専用のfocused/minimized/closes、native幅高さ、WINDOW-CLOSE後のwish継続を追加。DISPLAY-WINDOW/-21、強制SHOW/-265、端末のFULLSCREEN/-21も検査 |
| 新しいマシンが実際の起動時復元の関数を使っていない | restoreFreshImageへ変更。ただし新しいStateが既定の実行時設定を持つことの検査であり、既存Stateの設定をリセットするとの主張はしない |
| 外部の偽状態を比べるだけでは弱い | 復元中にwindow state/fit/smooth/closeコールバックが呼ばれないことをそれぞれの呼出し回数で検査 |
| monitor-movesの接続期限が起動中に切れる可能性 | raw_monitorsとfind_windowの開始時にそれぞれ単調時計で5秒の期限を設定 |
| monitor-moves終了時のstdoutエラーを見逃す | finish後に未消費のstdoutとstderrが空であることを検査 |

再確認では初回の指摘はすべて解消との回答だった。追加の2件（期限と終了時の出力）は上表のとおり対応し、実機で再実行した。固定待ちと倍率1の前提は現在の実機確認の制限として維持する。物理倍率変更・接続切断・Windows/macOSの共通受け入れは1334〜1336に残す。

SAVESYSケースの主張は「実機で保存した実行体を新たに起動したときのホスト資源・表示キャッシュの不在、および辞書変数の保持」に限定する。fit/smooth/keep-openなどの非直列化はZigの新しいStateへの復元テストで、実行中復元は偽ホストのコールバックとStateで別に確認する。未検証のほかのruntimeフィールドの全網羅とは扱わない。
