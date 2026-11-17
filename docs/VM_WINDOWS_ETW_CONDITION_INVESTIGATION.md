# 保存済みAPI/ETW対照診断の追加解析（#874）

2026-11-16。[#873の128実行](VM_WINDOWS_ETW_CONTROL_RESULTS.md)を再解析した。**CPU0のDPC/ISR負担はCPU2より大きかったが、控除後の残差を説明する原因は特定できなかった。今回の記録による切分けはここで終了する。** 新規取得・同条件再試行・製品VMの変更は行っていない。

## 解析範囲と検証

128実行のうちETW onの64標本（記録対象48、warmup16）について、保存済みraw QPCとxperf CSVを再読込した。offの64標本にはscheduler履歴がないため、DPC/ISRや実行中priorityの詳細集計は作らない。API境界priorityと観測APIの所要時間は全128標本の保存記録を利用した。

入力capture・raw CSV・event CSV・既存解析JSONのSHA256を前回記録と照合した。全6,969,209件のCSwitchについてCPU/TIDとold/new連鎖を再検査し、対象sliceをAPI照会終了のQPCで切りそろえた。DPC/ISR行はtimestamp・CPU・TIDで対応づけた。各標本のgross値と残差は、前回のAPI照会bracket・丸めを含む区間内に収まった。以下の単一値はこの境界での点集計であり、前回の幅を狭める主張ではない。

専用[解析script](../scripts/windows-etw-control/investigate.py)と[全派生値・元記録ハッシュ](measurements/2026-11-16-windows-etw-condition-investigation.json)を保存した。raw ETL/全CSV/hostとthread一覧は公開しない。

## DPC/ISRとAPI残差

ETW onの記録対象24標本/CPUで、対象threadのscheduler sliceに重なるDPC/ISR合計は次の範囲だった。

| CPU | DPC/ISR合計の最小～最大 |
| --- | ---: |
| CPU0 | 270.851～371.002ms |
| CPU2 | 2.713～6.667ms |

CPU0に大きい割込み負担が存在したことは確認できる。一方、以下の条件別算術平均の差では、DPC/ISR控除後のscheduler時間の差に比べ、APIとの差の変化が大きい。各セルはCPU0→CPU2の変更後−変更前。

| ETW on・full | 群 | API CPU差 | 控除後scheduler時間差 | 残差の差 |
| --- | ---: | ---: | ---: | ---: |
| Sigma | 1 | +281.250ms | −33.113ms | +314.363ms |
| Sigma | 2 | +239.583ms | −9.004ms | +248.587ms |
| native | 1 | −46.875ms | −33.749ms | −13.126ms |
| native | 2 | −156.250ms | −16.510ms | −139.740ms |

ここでは平均値の差を使い、`API差 = gross差 − DPC/ISR差 + 残差の差`の会計上の恒等式を検査した。これは原因の分解ではない。#873で選定に使った中央値とは統計量が異なり、中央値の代替や事前判断の変更には使わない。

大きなDPC/ISRを控除しても、Sigma/nativeのAPI差は同じ方向にならず、CPU2でも残差が残る。観測されたDPC/ISR時間をそのまま差し引く説明だけでは、APIとscheduler時間の一致は得られない。両者に共通する別の要因がある可能性も、この記録では検証できない。

## 観測器の負担

全128実行のうちfull観測64実行のREADY/DONE各照会（128境界）を集計すると、thread一覧の取得は平均31.952ms、context counterは平均6.315msだった。process CPU照会は平均0.026ms、最大1.384ms。これらは観測APIの経過時間であり、対象process CPUへの混入量ではない。

ETW on・CPU0でminimal→fullとした場合、API照会区間内の対象threadのoff-CPU時間は条件別平均の差で約36.474～38.652ms増えた。開始CPU照会後、対象threadがKEYで待つ間に補助情報を取得する手順と整合するが、全off-CPUの原因を分類したものではない。DONE後にも観測を行うため、wallの負担全体とは一致しない。

同じ条件変更でnativeのAPI CPU平均差は群1+57.292ms、群2+307.292ms、控除後scheduler平均差は−1.452ms、−13.418msだった。観測器に負担があることは確認したが、その所要時間をCPU値から差し引けば残差が解消するという根拠にはならない。minimalでも残差が残るため、full観測だけを唯一の原因とは認定しない。

## priorityと実行順

取得境界のAPI値は、全128実行でprocess priority class=32、thread priority=0だった。一方、ETWのswitch-in時には8/9/10、switch-out時にも8/9/10を観測した。APIの相対priority設定値と、ETWの実効priorityを同じ値として比較しない。

記録対象48標本では、switch-out時priority 8に対応するslice滞在時間の比率は各標本98.983～100.000%だった。これは切替時の値でsliceを分類したもので、実行中の全priority変化を観測したわけではない。sliceにはDPC/ISRも含まれる。この集計からpriority差を残差の原因とする根拠は得られなかった。

群・CPU・プログラムごとの記録対象6標本（minimal/full混在）について、残差とDPC量・取得順のPearson相関を記述統計として算出した。CPU0/Sigmaの残差−DPC相関は群1+0.560、群2−0.712、残差−取得順は群1−0.199、群2+0.703で方向が反転した。一貫した単純関係は確認できなかった。少数標本・観測方式混在・固定順の交絡があり、相関の有無から原因の存在・不在を証明しない。

## 結論と打切り

#874で予定した保存記録のDPC/ISR・priority・観測順による照合を完了した。CPU0の割込み負担とfull観測の負担は数値で分けられたが、API/ETW残差の原因を識別する記録は得られなかった。

この調査は**原因未特定として打ち切る**。同じ取得・集計を繰り返すタスクは追加しない。driver、OS会計、仮想化、周波数などを原因と断定せず、推測に基づくVM修正やOS設定変更へ進まない。

速度改善の候補評価には既定の主指標とA/A校正・採用条件を引き続き使う。今回の診断で校正合格や追加採用を宣言しない。将来この残差調査を再開する場合は、具体的な仮説と、既存記録にない何を測れば区別できるかを先に定めた別計画が必要である。
