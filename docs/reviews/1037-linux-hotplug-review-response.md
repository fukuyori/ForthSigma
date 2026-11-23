# Linux物理抜き差し記録：Claude Codeレビューへの対応

2026-11-23。物理操作を待つ記録機構について、Claude Code CLIへ固定スナップショットを渡して3回の静的レビューを依頼した。Read/Grep/Globだけを許可し、Claudeは実行・編集をしていない。[初回](1037-linux-hotplug-claude-review.md)、[再確認](1037-linux-hotplug-claude-followup.md)、[最終確認](1037-linux-hotplug-claude-final.md)。

| 指摘 | 対応 |
|---|---|
| M1：無応答も操作待ちに分類される | AwaitingHardwareを専用例外とし、ハード待ちとソフト状態待ちを分離。SigmaとX11のTimeoutErrorはfail |
| M2：再接続後の観測が短い | 10秒の保持を追加。最後にも3回連続で一致を求める |
| M3：-1をPythonの負の添字として扱う | 有効添字と元の主画面名で判定 |
| M4：作業領域の変数を交差面積で上書き | intersectionsへ分離し、生の作業領域の証跡を保持 |
| M5：DRMだけでケーブルと断定できない | EDID消失も要求し、電源断・特権操作との区別の限界を記録。物理合格には事後の操作者申告が必要 |
| M6：0 DOでゼロ件を扱えない | ?DOへ変更 |
| R1：早期の再接続等を製品の失敗と誤分類 | ハード前提が崩れたソフト待ちの期限切れはincompleteへ |
| R2：一度の非同期更新で誤失敗 | X11単独の所属画面も毎回保存し、単発の不一致を許容。3回続く不一致をfail、ハード変更をincompleteとする |
| R3：事前フラグが操作後の申告ではない | フラグを廃止。元の記録はobserved-awaiting-operator-confirmationのまま保存。完了記録への事後の申告を、元JSONのSHA-256とともに別ファイルへ排他的作成 |

最終確認ではR1・R2の解消、R3の実装の解消と、中程度以上の実バグなしという判定だった。追加の否定テストとしてpreflightの確認拒否を足し、さらに`-O`/`PYTHONOPTIMIZE`でassertが無効な場合は明示的に実行を拒否するようにした。この小さな補強は最終レビュー後の変更である。

[記録機構の6ケース](../measurements/2026-11-23-linux-hotplug-recorder-checks.json)は成功。事前の表示、操作なしのincomplete、意図的なSigma無応答のfailと回収、preflightの確認拒否、未完了の確認拒否、最適化モードでの確認拒否を区別して検証した。

実際の物理操作は一度も観測されていない。合格する物理記録や操作者申告を人工的に作ってはいない。1336・1345と親1037の進捗・未完了状態は維持する。次は[実施手順](../LINUX_DISPLAY_HOTPLUG_VALIDATION.md)に沿った実際のケーブル操作が必要である。
