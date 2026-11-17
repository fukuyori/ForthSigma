# VM速度改善の引き継ぎ

更新日：2026-11-17

## 現在の結論

- 製品VMに採用済みの改善は、PC/endPCの局所保持と、単純なdata wordの早期`.call`経路。これらはcommit `7b1295f`で採用され、通常34条件はWindows・Linuxで通過済み。
- 追加候補のVALUE経路とセル型localは、独立した比較実験まで実施した。今回の部分採用基準で一部の実例改善は確認したが、追加採用は保留。VALUEは未測定条件を残して評価を終了し、セル型localは標準条件の比較でWindows catch-nested-256が悪化上限を超えた。
- 製品VM・候補sourceは今回変更していない。最新の追補評価は停止条件どおり終了し、製品ビルド・追加テストも行っていない。
- 直近の評価結果と生データは[追補結果](VM_PARTIAL_ADOPTION_FOLLOWUP_RESULTS.md)、各測定段階の履歴は[部分採用評価の中断記録](VM_PARTIAL_ADOPTION_HANDOFF.md)を参照。

## 直近の測定結果

- local候補：実例9ケースの両OSと標準整数演算2条件を比較。Windows LOOPのA/A最大δが2.191781%となり、上限2%を超えたため、候補比較に入る前に停止した。標準32条件は未評価。
- VALUE候補：実例7ケースの両OSを比較。Windows waterworks資産生成のA/A最大δが2.030457%となり、上限2%を超えたところで停止した。実例残り2ケースと標準34条件は未評価。
- 両候補ともpinball資産生成の短縮は観測したが、全回帰条件の確認が終わっていないので追加採用条件を満たしたとは扱わない。整数演算・LOOP各10%短縮の従来目標も達成扱いにしない。
- 比較条件、中央値、校正値、打切り位置、監査結果は追補結果の表と測定JSONに記録済み。A/Aのδは計測揺らぎの確認値であり、時計精度や信頼区間ではない。

## 次に行う作業

#880の判断は[継続方針](VM_PARTIAL_ADOPTION_CONTINUATION_PLAN.md)に記録した。VALUEは採用保留のまま評価を終了し、セル型localは標準32条件の評価を新しい手順で続ける。新しい手順では、校正未達の条件を保留にして次へ進み、一巡後に同じN・CPU・標本数・上限で1回だけ再校正する。悪化上限と「全条件通過」の採用条件は変えていない。

この手順による計時（#881）は終了した。[結果](VM_PARTIAL_ADOPTION_LOCAL_STANDARD_RESULTS.md)：標準15条件を比較し、14条件は悪化上限を通過したが、Windows catch-nested-256が系列1で+9.770%となり上限5%を超えたため、停止規則どおり終了した。未比較は17条件。セル型localの追加採用も保留である。`.work/partial-adoption-local-standard-20261117`のprotocolは実行済みなので、再実行しない。

利用者の判断により、両候補とも採用保留として#870を終了した。速度改善（#786）配下で残るのは、成果のコミット・プッシュ（#871）である。catch-nested-256などを別の手順で調べ直す場合は、新しいタスクとして方針と条件を先に記録する。

## 参照資料とデータ

- [速度改善計画](VM_PERFORMANCE_PLAN.md)：全体の経緯、採用済み変更、候補の優先順位。
- [部分採用評価計画](VM_PARTIAL_ADOPTION_EVALUATION_PLAN.md)：承認済み評価基準。
- [短い実例の計時設計](VM_SHORT_WORKLOAD_TIMING_PLAN.md)：反復入力と検証範囲。
- [追補結果](VM_PARTIAL_ADOPTION_FOLLOWUP_RESULTS.md)：#878/#879の最終集計、未測定条件、監査上の限界。
- [継続方針](VM_PARTIAL_ADOPTION_CONTINUATION_PLAN.md)：#880の判断、校正未達の生標本、localの新しい手順と凍結protocol。
- [local標準条件の結果](VM_PARTIAL_ADOPTION_LOCAL_STANDARD_RESULTS.md)：#881の比較結果、停止条件の標本、未比較17条件、監査。
- `docs/measurements/2026-11-17-partial-adoption-followup-results.json`：条件別の集計・監査source。
- `docs/measurements/2026-11-17-partial-adoption-followup-raw.json.gz`：各段階の生標本と凍結source。
- 実行用候補・fixture・cacheは`.work`配下。製品sourceと混同しない。

## Gitと公開状態

今回の調査資料・測定データには未コミット差分がある。現時点でこの引き継ぎ作成に伴うcommit/pushは行っていない。`examples/boing.fs`と`scripts/__pycache__/`も作業ツリーに見えるため、後で公開する場合は内容と所有範囲を確認し、速度改善資料だけを選別する。tque #871にはcommit/push作業が登録されているが、登録だけでは実行許可として扱わない。利用者から明示的な依頼があった場合に、直前のGit・remote状態を確認して実施する。

## 引き継ぎ時の注意

- tque番号は振り直されることがある。作業開始時に#786/#870と配下タスクの現在のタイトル・親子関係・状態を再確認する。
- 追加候補は同一試験で組み合わせていない。独立候補間の効果を足し合わせない。
- 過去系列と再開後系列は混合しない。停止済み評価を同条件で無記録に再試行しない。
- 原因が記録で特定できない揺らぎを、OS/API・周波数・背景負荷のせいと断定しない。
- Claude Codeの3候補レビューと追レビューは完了し、指摘・制約は[レビュー対応記録](VM_THREE_CANDIDATES_REVIEW_RESPONSE.md)と[再レビュー](VM_THREE_CANDIDATES_REREVIEW.md)に反映済み。
