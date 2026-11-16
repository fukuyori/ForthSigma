# ビルド最適化調査レビューへの対応

[Read/Grep/Globのみのレビュー原文](VM_BUILD_OPTIMIZATION_CLAUDE_REVIEW.md)を保存。レビュー時点の「共通採用なし・速度未確定」を覆す問題はなかった。

1. PGOのCプローブはWindows GNUだけ、Linux muslは未試行と訂正。build-exe確認もtarget/cpu未指定の最小Zig＋引数解析であり、VMソース/build APIのPGO試験ではないと明記した。全PGO不可とは扱わない。
2. サイズ基準はLinux fullのみ充足し、Windows fullは実行体がなく評価不能と明記した。thinのLinux＋1.138%は1%上限超過。
3. 回帰はLinux musl/fast/WSLだけと限定。unit/hostへのfull設定、ZCU bitcodeヘッダー、本体SHAの証拠と、Cオブジェクト・最終リンクフラグが直接未記録という限界を明記した。

cacheパスの事前空状態未記録、同一絶対パス/cwd/global cache、奇数標本数による群内順序の偏り、ホスト側外乱未記録、配置差未分離、MSVC/別リンカ未試行を追記した。CPU0が割込みに特に弱いとの原因説明は未検証のため採用していない。

レビュー後に計時のdecision/completeを確認し、両群とも2.58〜2.68%短縮だが10%目標未達と記録。残る項目は未測定。数値はレビューの対象ではなく、保存標本から再集計したものとして区別する。本体・配布設定の変更はしていない。
