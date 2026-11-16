# Windows計時診断レビューへの対応

2026-11-16。[初回レビュー](VM_WINDOWS_TIMING_FOLLOWUP_CLAUDE_REVIEW.md)を受け、以下を反映した。

| 指摘 | 対応 |
| --- | --- |
| M1 特権実行のWPR探索 | SystemDirectory APIから絶対パスを取得。PATHや作業ディレクトリから探索しない |
| M2 assertによる入力確認 | 管理者driverのassertを明示的な例外へ置換。psutil版・入力ハッシュを確認。`python -O --preflight`相当の検査が成功 |
| M3 後始末の確認 | 専用instanceのstop/cancel終了値と最終statusを保存。停止未確認は失敗とし手動cancelを表示。開始もtry/finallyの範囲へ移動 |
| M4 context counterの意味 | Windows実装を確認し、全threadのContextSwitches合計として説明。自発・非自発分類には使わない |
| L1 host時間の二重計上 | total=user+system+idleへ補正。interrupt/dpcを再加算しない。元の標本は保持して再集計 |
| L2 thread観測範囲 | 両端共通IDの差分だけ。新規・終了・一時的threadの履歴を含まないと明記 |
| L3 量子とpriority | 15.625msは観測刻みとして表記。priority API失敗値の確認不足は観測器の制限として明記 |
| L4 native判定 | 事前条件のない2%合否fieldを削除。記述統計として保持 |
| L5–L8 手順・事前確認 | 生存中/終了後の取得範囲、WhatIfの限界、強制終了時の復旧を明記。wrapperのLeaf/driverハッシュ確認と専用preflightを追加。旧生成器は構文確認だけに変更 |

後始末の4分岐（stop成功、stop失敗後cancel成功、stop成功後も記録状態でcancel、停止未確認）をオフラインの模擬応答で検査した。すべて専用instanceを指定し、期待する停止確認結果になった。模擬検査は実WPRの取得・停止の成功を示さない。

凍結した観測器・32標本・実行順・反復数を保持したまま再集計し、CPU中央値・範囲と再開不可の判断が変わらないことを照合した。root VM、benchmark helper、基準実行体のSHAも一致した。runtime変更がないため追加のビルド・回帰試験は行っていない。

残る実作業は#861の管理者ETW取得と解析。現在はWindowsのAccessDeniedで取得できておらず、原因は未特定、候補比較と採用は保留である。[現在の結果と実行手順](VM_WINDOWS_TIMING_FOLLOWUP.md)。


## 再レビューへの最終対応

| 指摘 | 状態・確認 |
| --- | --- |
| H1 driverハッシュ再確認 | 対応済み。実ファイルのread_bytesから再計算。旧LF文字列による生成処理を実行不可にし、実バイト照合を含むPowerShell -WhatIfを再実行・exit0。出力をadmin-validation.jsonへ保存し、統合JSONも再生成 |
| M5 開始失敗の上書き | 対応済み。start_failedを保持し、開始失敗時はstopを省きstatusを確認。0x80070005の模擬応答で状態保持とstop/cancelなしを検証 |
| L11 未検証経路 | 一部対応。開始失敗ケースを追加。WPR起動のOSErrorはexit=-1の記録として返し、後続の停止確認へ進める。実WPR・強制終了の後始末は未検証 |
| L12 実行環境 | 一部対応。wrapperはPython -E -Pを指定し環境変数とscriptディレクトリの探索優先を抑制。利用者書込み領域を管理者実行する信頼境界は残り、ハッシュで解消したとは扱わない |
| L13 個人パス・実行ポリシー | ローカル再現のため現在の絶対パスとPIDを保持。ETLは公開していない。本ターンはcommit/pushなし。実行ポリシーの拒否は観測されていないため設定変更や回避手順は追加しない |
| L14 記録整理 | 対応済み。初回と再レビューの対象時点を明記し、対応表を追加。既存scripts/__pycache__は成果物に含めない |

再レビュー後の最終補正は上記の模擬ケース、最適化preflight、wrapper -WhatIfで検証した。最終補正後のClaude Code再々レビューおよび管理者実取得は行っていない。原因と採否の結論は不変。
