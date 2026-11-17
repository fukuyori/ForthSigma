# 部分採用評価の中断記録

2026-11-17 最新結果：[#881の継続評価](VM_PARTIAL_ADOPTION_LOCAL_STANDARD_RESULTS.md)を停止条件まで完了し、#870を終了した。VALUEは未測定38条件を残して評価を終了。セル型localは実例18条件と標準16条件で悪化上限を通過したが、Windows catch-nested-256が上限5%を超え、標準17条件は未比較。両候補とも追加採用は保留、製品VMは採用済み基準版のまま。以下は各時点の履歴である。

2026-11-16、利用者の指示で中断。今回のcontroller・WSL worker・実行中の子を停止し、生データを保持した。製品VMは変更していない。

- #877：反復入力134件と計時手順20件の検証を完了。
- #878 VALUE：Windows waterworks資産生成のA/A最大δ2.030%で上限2%未達、固定計画どおり終了。後続と標準34条件は未測定。
- #879 local：Linux waterworks renderの比較第2系列を中断。baseline/candidate各6/7標本を保存したが、系列完了の判定には使わない。以後のklondike render・資産生成2件・標準34条件は未実施。

再開時は`.work/partial-adoption-resume-20261116`の凍結protocol・results・local/interruption.json・partial JSONを確認する。中断系列への追記や、元のstart guardを解除した無記録の再実行はしない。中断した条件をどう扱うかを先に記録し、別の再開protocolを固定する。#879と#870は未完了のまま。コミット・プッシュはしていない。

[中断時の記録](measurements/2026-11-16-partial-adoption-interruption.json)。

## 2026-11-17 再開

利用者の再開指示を受け、入力・実行体・旧証拠のSHA一致と旧processの停止を確認した。中断したLinux waterworks renderはN=198を維持し、旧第1系列と途中の第2系列を混ぜず、新しいA/A各5標本×2系列と比較各7標本×2系列で条件全体を再取得する。旧データは保持する。他の完了条件は履歴として参照し、同時期の再計測とは扱わない。

新しい作業領域は`.work/partial-adoption-continue-20261117`。この条件の後はklondike render→残る資産生成2件→標準34条件へ進む。最初の未達で停止する規則を維持する。VALUEは校正未達の正式結果を維持し、再試行しない。

[再開方針・凍結protocol・最終source](measurements/2026-11-17-partial-adoption-resume.json)。
