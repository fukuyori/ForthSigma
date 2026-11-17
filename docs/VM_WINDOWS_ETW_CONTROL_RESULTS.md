# Windows API/ETW残差の対照診断結果（#873）

追補：#874の[保存記録の追加解析](VM_WINDOWS_ETW_CONDITION_INVESTIGATION.md)を完了した。CPU0のDPC/ISR負担、full観測の負担、切替時priority、実行順を照合したが、残差の原因は未特定だった。この記録による残差調査は打切りとし、新規取得・同条件再試行は行っていない。以下の「次に調べる価値がある」は#873完了時点の判断である。

2026-11-16。[固定計画](VM_WINDOWS_ETW_CONTROL_PLAN.md)の128実行を取得し、2本のETLを解析した。**CPU2で今回の標本の変動幅は小さかったが、API/ETW残差は消えず、原因は未特定である。** VM実装・主指標・採用条件は変更していない。この取得は速度比較・A/A校正ではない。

## 取得・照合

利用者が管理者PowerShellで実行した`capture-20261116T101008-7e34a113`はstatus=complete、128実行（記録対象96、warmup32）。CPU0/2×minimal/full×Sigma/native×ETW off/onの各条件を2群で取得し、記録対象は条件・群ごとに3標本。入力ハッシュ、全checksum、READY/DONEの子affinity/group、標本数を再検査した。process/primary threadの区間CPU差は128実行とも0だった。

2つの所有WPR instanceはstop exit0、cleanup_confirmed=true。lost events/buffersは両traceとも0。group1のCSwitch3,596,321件、group2の3,372,888件で、全CPU old/new連鎖・raw payloadとxperfのCPU/TID対応を照合した。対象PID/TIDの開始・終了も対応し、対象sliceは指定CPUだけに存在した。clock type=QPC、frequency=10,000,000。取得時のQPC/perf_counter原点・換算bracketも保存した。

xperf dumperは両traceでSysConfig Logical Disks（GUID01853a65…、type0x0c/version2、MofLength112）の警告を1件ずつ出した。自動解析は警告時に停止し、ログを確認してから保存済みexportを解析した。警告は対象の最終switch-outよりgroup1で145,281us、group2で111,953us後だった。CSwitchの警告ではなく、対象期間後の構成イベントとして扱った。これは全イベントの妥当性を保証するものではない。新規取得・取り直しは行っていない。

同じAPI照会のraw QPC bracket両端を用いた4通りの境界でscheduler時間を計算し、sliceごとのDPC/ISR控除と整数us丸めの幅を加えた。境界sliceのDPC/ISR部分重なりにより配分が未確定となる標本は、warmupを含む64標本ともなかった。

## CPU時間の変動幅

各条件・各群の3標本に対する範囲/中央値を16条件分比較した集計。下表の最小/最大はその条件別統計の範囲で、全標本をまとめた変動幅ではない。

| CPU | 条件別の範囲/中央値の最小～最大 | 2%を超えた条件 |
| --- | ---: | ---: |
| CPU0 | 0.211～7.025% | 9/16 |
| CPU2 | 0.210～1.795% | 0/16 |

今回の固定条件ではCPU2に小さい変動幅を観測した。ただし、3標本の記述統計であり、所定の5標本×2群等のA/A校正を通過したという意味ではない。CPU0の変動原因が特定されたわけでもない。

## 同一区間のAPI−ETW残差

ETW onの記録対象はCPUごと24標本。下表は各標本の残差区間の下限最小～上限最大であり、信頼区間でも母集団の範囲でもない。

| CPU | API−ETW（DPC/ISR控除後）の残差区間の外側範囲 |
| --- | ---: |
| CPU0 | −555.957～+167.642ms |
| CPU2 | −110.597～+7.503ms |

この区間にはAPI照会bracketとETW集計の丸めを含めるが、API量子化やETW全体の精度保証は含めない。API値で観測された15.625ms刻みと同じ桁・それ以下の差からsub-ms精度を主張しない。CPU2にも一刻みを超える残差があるので、CPU移動だけで同一区間の不一致が解消したとは言えない。

minimalでも残差は残った。CPU0/minimalの外側範囲はSigma−231.191～+167.642ms、native−372.914～−58.016ms。CPU2/minimalはSigma−95.405～+1.052ms、native−110.597～−12.215ms。補助観測の削減だけで残差が一貫して消える結果ではなかった。

観測所要時間（READY/DONE合計とDONE後identity検査、記録対象）はminimalで約0.085～0.129ms、fullで約72.284～83.315msだった。fullの負担は明確に大きいが、その時間をCPU値やwallから差し引いていない。wallには観測負担が含まれる。

## 事前の条件差判定と解釈

「両群で中央値差の方向が揃い、各群の標本範囲が重ならない」という事前条件をCPU時間に適用すると、次が追加調査候補に該当した。これは因果認定や統計的有意差ではない。

| 条件の変更 | 固定する条件 | CPU中央値の差：群1 / 群2 |
| --- | --- | ---: |
| CPU0→CPU2 | ETW on、full、native | −46.875 / −156.250ms |
| CPU0→CPU2 | ETW on、full、Sigma | +328.125 / +109.375ms |
| minimal→full | ETW on、CPU0、native | +62.500 / +312.500ms |
| ETW off→on | CPU0、full、Sigma | −312.500 / −265.625ms |

CPU変更の差の方向はプログラムによって逆になり、ETW off/onにはブロック順・時刻の交絡も残る。ETW onでAPI値が小さい条件があっても、高速化やETW offでの残差の解消を示さない。offにはscheduler参照値がなく、残差そのものを比較できない。

## 判断と残作業

#873の固定取得・集計・記録を完了した。欠落、境界照合不能、checksum/affinity失敗を理由に取り直す状況ではなかった。一方、残差が持続し、条件差だけでは原因を識別できなかったため、同じ128実行を自動反復しない。

次に調べる価値があるのは、**保存済み128標本に対するCPU0×full×ETW条件の追加解析**である。上記4差分とDPC/ISR・priority・観測順の関係を群別に点検し、残差を説明できる記録があるか確認する。相関だけでdriver、OS、仮想化、周波数を原因と断定しない。記録から判断できなければ未特定として閉じ、別の取得が必要な場合は仮説と識別可能性を先に設計する。

候補の採用保留と既定の性能評価条件は維持する。今回の診断を校正合格へ流用せず、CPU2で行った候補評価の採否も変更しない。

[全条件の生値・派生値・警告検査・解析script・ハッシュ](measurements/2026-11-16-windows-etw-control-results.json)。ETL、全イベントCSV、host/thread一覧は`.work`に保持し、このJSONには公開しない。
