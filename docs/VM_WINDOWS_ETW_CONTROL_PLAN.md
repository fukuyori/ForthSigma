# Windows API/ETW残差の対照診断計画（#862）

2026-11-16。#862の成果物は対照診断の設計である。設計時点では本書の計画による新規取得は未実施だった。その後#873の取得と#874の追加解析を完了し、[原因未特定で打切り](VM_WINDOWS_ETW_CONDITION_INVESTIGATION.md)。以下の未実施表記は各節作成時点の記録である。

## 根拠と問い

[既存解析](VM_WINDOWS_ETW_ANALYSIS.md)では、同じREADY/DONE区間でもAPI−ETW（DPC/ISR控除後）が約−427～+97ms残った。対象はCPU0固定、基準Sigmaとnative各3回、単一ETWセッションだった。取得時のclock情報は直接保存されていなかった。

[CPU2での後続評価](VM_THREE_CANDIDATES_RESULTS.md)ではA/A校正が成立したが、CPU0との同時対照ではなく、ETW残差の原因を説明しない。

次に確かめるのは、残差の再現性、CPU間の差、観測器の負担、ETW記録の有無による記述統計の差である。API・ETWのどちらを正解と認定する実験でもない。

## 固定する入力と比較条件

- 採用済みWindows基準実行体SHA256 `379d6c6c069b9c3072da22fa6cea8b7deff77c5ed78ef9bbd070f92a724337bf`、既存native実行体、benchmark helper、WPR profileを再利用する。native等のハッシュは既存記録と照合し、新driver・観測器・入力・環境情報のハッシュを取得前に凍結する。不一致なら取得を開始しない。
- Sigmaは既存セルlocalカーネル、N=1,238,709,678。nativeは既存volatile加算、N=38,400,000,000。期待値は両者とも7*N。Nを今回の結果に合わせて調整しない。異なる命令列なので両者の速度比を求めない。
- CPUはgroup0のlogical CPU0とCPU2。事前に利用可能性を確認し、runnerと継承した子processのaffinity、primary threadのgroup/maskを保存する。CPU2を利用できなければ別CPUへ自動置換しない。
- 観測器はminimal/fullの2条件。minimalはprocess/thread時間と各照会のraw QPC bracket、PID/TID、READY/DONE/EXITを記録する。affinity/priorityは計時区間の外でも検査する。fullはminimalと同じ必須記録に加え、既存のcycles・thread一覧・context counter・per-CPU counterを取得する。観測APIの失敗値を検査し、エラーを0に置換しない。
- ETW off/onの2条件。onは既存のCSwitch/ProcessThread/ReadyThread/ThreadPriority/CpuConfig/DPC/Interrupt profile。offにはETW残差という値を作らず、CPU・wall・観測所要時間だけを比較する。
- process kernel+userを主指標として維持する。priority、電源、timer resolution、常駐サービスなどのOS設定は変更しない。build/test/他profileを計時と並行しない。

## 実行順と回数

2群を一度だけ取得する。各群にETW off/on各1ブロックを設け、群1はoff→on、群2はon→offとする。onはブロックごとに別の一意sessionを使う。ブロック内の8条件は、CPU×観測器×プログラムの直積である。

群1の順序は `0/minimal/Sigma, 2/full/native, 0/full/native, 2/minimal/Sigma, 2/minimal/native, 0/full/Sigma, 2/full/Sigma, 0/minimal/native`。群2は逆順。各ブロックでこの順にwarmupを1巡し、次に同じ順序を3巡して記録対象とする。warmupも保存し解析対象の印を分ける。

計128実行（記録対象96、warmup32）、ETW sessionは2本。時系列・ブロック位置による交絡は残るので、群間差を因果効果と呼ばない。失敗標本を補充したり、安定するまで繰り返したりしない。

## 時計と境界

driver開始時と各ブロック前後にPythonのversion、`get_clock_info('perf_counter')`、QueryPerformanceFrequency、raw QueryPerformanceCounterを保存する。raw QPC→perf_counter_ns→raw QPCのbracketを複数回記録し、同一原点と換算の整合性を直接検査する。整合しなければUTC近似で同一区間一致を主張しない。

GetProcessTimesとGetThreadTimesをそれぞれraw QPCの前後で挟む。ETL headerのclock type/frequencyを検査し、RAW_TIMESTAMPのCSwitchを読む。開始・終了のAPI bracket両端の組合せからscheduler時間の最小・最大を求める。境界sliceにDPC/ISRが一部重なる場合は全slice分を比例配分せず、生イベントで重複区間を切り取る。これができなければ控除後残差の判定は未確定とする。

APIの観測刻み、照会bracket、ETW換算・丸めの幅は別々に報告する。APIの刻みをscheduler quantumや精度保証と呼ばない。cyclesも時間・命令数へ換算しない。

## 集計と判断

各条件・各群の3標本について全生値、CPU/wall/観測所要時間の中央値と範囲/中央値を示す。ETW onでは切替slice、DPC/ISR、その控除後、APIとの差の絶対msとAPIに対する比を保存する。CPU0/2、minimal/full、off/onの差を群別に示し、標本を混ぜて好都合な群だけ選ばない。

診断としての成功は、全checksum・必須API・affinity検査が通り、記録停止を確認し、lost events/buffers=0、全CPUのCSwitch old/new連鎖と対象PID/TIDの対応、時計・境界の検査が成立して、比較表を作れることである。残差が消えたことは成功の必須条件ではない。

- 同一区間残差の幅が0を含むか、観測されたAPIの一刻み以内か、それを超えるかを各標本で区別する。一刻み以内でも正確さが証明されたとはしない。
- CPU間または観測器間で、両群の中央値差の方向が揃い、かつ各条件の標本範囲が重ならない場合は、追加調査候補とする。原因の認定や統計的有意差とは扱わない。
- off/on差はETWの負担を含む条件差として報告する。offにはscheduler参照がないため、offで残差が消えたとは言わない。
- 差が不明瞭、群間で反転、または残差が持続する場合は、この計画で原因を識別できなかったと結論する。CPU0のDPC/ISRと残差の相関だけでdriver・OS・仮想化・周波数を原因と断定しない。

## 打切りと次の判断

入力不一致、必須API失敗、clock不整合、対象CPU逸脱、trace欠落、未解決のCSwitch連鎖、checksum不一致があれば、その取得を有効な対照比較として扱わない。自分のsessionだけを停止し、失敗記録を残して打ち切る。停止を確認できなければ所有instanceの手動cancel手順を表示する。他sessionを停止しない。既存記録が検出された場合も開始しない。

開始前の小入力によるAPI/境界/後始末検証は許容するが、本番128実行の試し取り・再試行にはしない。実行中の手順変更が必要なら本計画との差を先に記録して別判断とする。

2群終了後は結果をレビューし、識別できた条件差に限定して次の調査要否を決める。同じ取得を自動反復しない。この診断をA/A校正や候補採用の合格へ流用しない。残差の解消だけで候補を採用せず、性能評価の既定条件は維持する。

## 実施と成果物の分離

#862は本設計の記録まで。次工程は専用driver/観測器・解析器の実装と事前検証、続いて128実行の取得・集計である。管理者権限が必要なETW取得は、取得script完成後に実行環境の権限を確認する。現時点では新しい管理者実行手順はまだ作成していない。

ETL・全イベント・thread一覧などは`.work`だけに保持する。追跡する文書/JSONには対象の数値、固定条件、ハッシュ、失敗情報、検証範囲を保存し、raw trace全体を公開しない。

## #872 実装・事前検証（2026-11-16）

専用の[capture.py](../scripts/windows-etw-control/capture.py)、[観測器](../scripts/windows-etw-control/observer.py)、[解析器](../scripts/windows-etw-control/analyze.py)、[PowerShell wrapper](../scripts/windows-etw-control/capture.ps1)、[raw QPC decoder](../scripts/windows-etw-control/read-etw-qpc.c)を実装した。製品VMとbenchmark helperは変更していない。

`--prepare`は入力・script・本計画・環境を`.work/windows-etw-control-20261116/fixed.json`へ凍結し、既存manifestを上書きしない。`--preflight`と本番開始前後で凍結入力を照合する。小入力の`--smoke`は本番128実行と区別され、ETWを開始しない。

取得scriptは128実行を固定順で保存する。解析器は群別の生値・中央値・範囲とCPU/観測器/ETW条件差を出力する。境界sliceにDPC/ISRの部分重なりがある場合、slice合計から位置を推定せず、控除後残差を未確定にする。この場合、診断成功とは扱わず、生イベントによる追加解析が必要である。新規exportの警告も自動無視せず停止する。

検証した範囲はPython構文、wrapperの`-WhatIf`、CPU0/2×minimal/full×Sigma/nativeの小入力8条件、checksum、子affinity/group、API差分の再計算、観測時計の原点・換算検査である。小入力の時間は性能比較・校正の結果として使用しない。DONE後のaffinity/priority検査はprocess CPU区間の外だがwallには含まれ、観測所要時間へ別bracketを加算する。

新しくビルドしたdecoderで保存済みETLを再読込し、ProcessTrace/CloseTraceとも0、CSwitch723,767件、raw CSVのSHA256は既存と一致した。解析器もその全件のold/new連鎖・xperf対応・対象PID/TIDを確認し、6標本の残差区間は既存解析と重なった。非zero lost-events記録の拒否も確認した。これは保存済みtraceの再検証であり、新しいETW取得ではない。

WPR開始/停止失敗と既存記録を模擬し、失敗時は所有instanceだけにstop/cancelし、既存記録検出時はstart/stop/cancelしないことを確認した。実際の管理者権限による新driverの記録開始・停止・失敗処理はまだ未検証であり、模擬検証で代替できない。

本番開始を試みた結果、現在のprocessはadministrator=falseで、記録開始前に拒否された。ETW offの本番標本も未取得である。#872の実装・事前検証を完了し、実取得は#873に引き継ぐ。[検証記録](measurements/2026-11-16-windows-etw-control-validation.json)。

管理者PowerShellで、次を実行する。自動昇格はしない。

```powershell
pwsh -NoProfile -File 'D:\home\source\zig\forthz\scripts\windows-etw-control\capture.ps1'
```

通常の端末からWindows sudoを使う場合も、`.ps1`を直接起動せず`sudo pwsh -NoProfile -File 'D:\home\source\zig\forthz\scripts\windows-etw-control\capture.ps1'`とする。

完了後は新しい`.work/windows-etw-control-20261116/capture-*/capture.json`を確認し、同じfolderを解析器に渡す。

```powershell
python -X utf8 scripts/windows-etw-control/analyze.py '<取得folder>' --decoder .work/windows-etw-control-20261116/read-etw-qpc.exe
```

警告・欠落・境界未確定なら、その記録を保持して原因を確認する。本番の取り直しや条件変更を自動実行しない。
