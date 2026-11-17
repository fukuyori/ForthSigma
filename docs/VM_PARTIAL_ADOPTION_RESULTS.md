# VALUE・セル型localの部分採用評価結果（#875・#876）

2026-11-17 最新結果：[#881の継続評価](VM_PARTIAL_ADOPTION_LOCAL_STANDARD_RESULTS.md)を停止条件まで完了し、#870を終了した。VALUEは未測定38条件を残して評価を終了。セル型localは実例18条件と標準16条件で悪化上限を通過したが、Windows catch-nested-256が上限5%を超え、標準17条件は未比較。両候補とも追加採用は保留、製品VMは採用済み基準版のまま。以下は各時点の履歴である。

2026-11-16。利用者の承認により、[部分採用基準](VM_PARTIAL_ADOPTION_EVALUATION_PLAN.md)を適用した。両候補ともpinball資産生成で必須改善基準を通過し、pinball logicの悪化検査も通過した。**短いwaterworks logicの計時で停止したため、追加採用は保留。製品VMと配布実行体は変更していない。**

## 実例で得られた結果

数値は基準版に対するCPU変化率、2系列の中央値から算出。負数は短縮。資産生成では両OSの両系列で`max(3%, 2δ_i)`を超える短縮を必須とした。今回のδでは上限・閾値はいずれも3%だった。

| 単独候補・実例 | Windows | Linux | 判断 |
| --- | ---: | ---: | --- |
| VALUE・pinball資産生成 | −3.421% / −4.961% | −6.768% / −7.535% | 必須改善基準通過 |
| local・pinball資産生成 | −9.769% / −8.312% | −12.015% / −12.141% | 必須改善基準通過 |
| VALUE・pinball logic | 0.000% / −1.411% | −1.103% / −1.016% | 悪化上限通過 |
| local・pinball logic | −7.713% / −8.800% | −8.632% / −8.700% | 悪化上限通過 |

対象の入力・CPU2・環境で得た部分効果である。資産生成だけの短縮をアプリ全体や操作全体の短縮とは扱わない。候補は独立した単独案であり、両者を組み合わせた効果は未評価。

## 入力と時計の検証範囲

既存9実例を両OSの基準版・VALUE版・local版で実行し、出力・状態checksum・DEPTH=0が54件すべて一致した。資産生成のchecksumにはDEPTH、画面寸法、8×8点のpixel値も含めた。ただし全画像・全状態の独立oracleや実画面の視覚的受入れ試験ではなく、baseline参照との限定した一致確認である。READY/DONEを使う計時手順も両候補・両OSの4件で事前確認した。

画像poolと辞書の確保を引き継がないよう、各実例1回ごとに新しい子processを使い、読み込み・準備・コンパイルをREADY前に終えた。実例処理とchecksumのCPU差を子ごとに取り、固定したN個を合算した。1個の連続kernelを5秒測ったわけではなく、起動・終了の全費用も含まない。Windowsの離散的なCPU値を合算しても量子化誤差の相殺や物理精度は保証されない。

各条件のbaseline-only pilotでNを一度固定し、A1/A2各5標本×2系列、各arm中央値5秒以上・最大δ2%以下の校正後だけ、各7標本×2系列の候補比較を行った。warmupは各arm・各系列1回ずつ除外して保存した。Windowsに加え、Linuxでも今回の生存中子affinity[2]を各CPU照会時に直接検査した。従来の3候補評価でLinux子affinityを継承のみとしていた記録を書き換えるものではない。

| 候補 | OS・実例 | A/A最大δ | 最小arm中央値 |
| --- | --- | ---: | ---: |
| VALUE | Windows資産生成 | 0.262% | 5.969s |
| VALUE | Linux資産生成 | 0.096% | 6.069s |
| VALUE | Windows logic | 0.717% | 8.719s |
| VALUE | Linux logic | 0.301% | 5.923s |
| local | Windows資産生成 | 0.000% | 5.969s |
| local | Linux資産生成 | 0.726% | 6.070s |
| local | Windows logic | 0.267% | 5.844s |
| local | Linux logic | 0.237% | 5.870s |

## 停止した条件と残る未測定

両候補とも、次のWindows waterworks logicのbaseline-only pilotでhelperが`measurement too short; increase --iterations`を返し、controllerは`infrastructure_error`として終了した。これは候補版の性能悪化・checksum不一致・VM例外による停止ではなく、比較前の計時条件未成立である。元のstatusは改変せず保存した。

VALUE側の失敗時生CPU照会値は保存されておらず、helperの非正CPU区間の拒否までが確認範囲である。VALUE終了後、localの計時を始める前に失敗照会保存を追加した。localの失敗記録ではREADY/DONEともkernel=0・user=0、区間差0nsを確認した。EXITではkernelが15.625msとなったが、これだけで更新遅延や精度の原因を証明しない。子affinityは3照会とも[2]だった。

Nの再調整・同条件再試行・CPU変更・wall/cyclesへの指標変更は行っていない。未測定は各候補につき残り7実例×両OSと標準34条件、計48の比較条件である。失敗したWindows waterworks logicもこの未測定範囲に含める。旧評価のWindows整数1条件を今回の新protocolで測ったことにはしない。

## 回帰・サイズ・監査

計時前に最終候補のソースと実行体を過去の凍結記録と照合し、計時終了後にもroot runtime・入力・worker・controller・protocol・実行体を再照合した。新しいruntime・境界fixtureの修正やビルドは行っていない。既存の回帰記録は[#869の補正済み確認範囲](VM_THREE_CANDIDATES_REVIEW_RESPONSE.md)を参照し、追補の基準版はWindows Debugのみ、候補版は両OS各5構成という区別も維持する。

Windows実行体は両候補とも基準1,809,408bytesと同一。Linuxは基準1,891,456bytesに対してVALUE1,891,632bytes（+0.0093%）、local1,891,648bytes（+0.0102%）で、各1%上限以内。ただしサイズ通過は未測定の性能条件を補わない。

各候補224batch（warmup込み）を再監査し、子CPU差の合計、checksum合計、両OSの生CPU照会差と子affinity、先後順、中央値、A/A・比較判定を再計算した。成功pilot計8件を含む保存済み子実行は合計35,568件。失敗pilotは各候補1件を別記録とし、この成功件数に混ぜていない。状態確認54件と事前handshake4件も計時標本数に混ぜない。

## 判断と次の作業

#875/#876の固定計画による評価を終了し、実例効果と計時未成立を記録した。専用kernelだけでなく、pinball資産生成・logicでの部分短縮は確認できた。一方、全実例と標準項目の悪化上限を確認していないため、本体へ追加採用しない。#870全体は未完了である。

次は#870配下・autoの#877で、短い実例を有効なprocess CPU区間で評価する入力を設計する。例えば状態初期化の同値性を検証した同一process内反復を検討できるが、まだ実装・検証しておらず、fresh-process合算とは別の計時条件になる。新しい入力・期待値・校正条件を先に固定し、今回の停止条件を通過したことにはしない。採用基準や主指標を緩めて解決しない。

[集計・監査source・凍結ハッシュ](measurements/2026-11-16-partial-adoption-results.json)と[全生標本・子CPU照会・protocol・入力・worker sourceの圧縮JSON](measurements/2026-11-16-partial-adoption-raw.json.gz)を保存した。CLI生成器・過去候補の記録と同じく、作業用scriptは`.work/partial-adoption-20261116`にあり、復元可能なsourceを測定JSONへ収録している。
