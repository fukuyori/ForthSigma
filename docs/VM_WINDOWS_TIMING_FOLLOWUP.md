# Windows計時変動の追加診断（#855）

最新状況：管理者実行によるETW6標本の取得・停止確認と、生QPCによるREADY/DONE区間の照合まで完了した。以下のAccessDenied・管理者取得未実行はそれ以前の記録。[取得後の解析結果](VM_WINDOWS_ETW_ANALYSIS.md)。候補比較・採用の保留は維持する。

2026-11-16。セル型local試作のWindows校正未達を受け、保存済み標本の照合と、基準版だけの追加観測を行う。一次CPU指標・2%校正上限・OS設定は変更しない。以下は最初の診断標本を得る前に固定した範囲である。結果・採否は実行後に追記する。

## 保存済みlocal A/Aの再集計（#856）

| 群 | CPU時間A/A差 | 経過時間A/A差 |
| --- | ---: | ---: |
| 1 | 5.167959% | 1.873130% |
| 2 | 1.980198% | 1.014638% |

20測定標本と4warmupのCPU値をkernel+user照会差から再計算して一致。CPU値は全24実行で15.625msの倍数だが、この粒度だけで最大約5.2%差を説明したとは扱わない。CPU/wallの20標本の相関は-0.105で、CPU変化が経過時間へそのまま反映する関係はこの範囲では確認できなかった。小標本・同一セッションの観察で、相関から原因を特定しない。

先後差は正負が混在し、後に実行した方が一貫して遅い偏りはなかった。kernel/userの別々の中央値を足してCPU中央値と呼ばない。今回の保存ログには主thread/cycles/ホストCPU活動がないため、過去の別カーネルでの「process/主thread一致」を今回へ流用しない。

## 基準版の短長診断計画（#857）

採用済みWindows strip実行体SHA379d…を固定し、同じlocalカーネルでN=1,238,709,678と4倍の4,954,838,712を実行する。前者は前回pilotで約6秒、後者は約24秒を狙う。今回の結果を見てNを調整しない。過去の2R@短長診断で長条件の相対範囲が小さかったことと、今回localが実例で多いことを根拠に選んだ。長くすれば安定するとは未確認。

2群・各条件3標本、群/条件ごとにwarmup1回を除外。短長を交互にし群2で反転、計16実行を一度だけ行う。標本とwarmupは全保存。CPU0 runner、子processのaffinity/priority/groupも取得する。候補版を使わず、build/test/profileと計時を重ねない。

追加観測はREADY/DONE/EXIT境界のprocess/主thread kernel+user、process/thread cycles、thread集合、affinity/priority、psutil7.2.2のper-CPU user/system/idle/interrupt/dpc、context counters、各APIと観測全体の経過時間。まずPython processで観測APIの対照確認を行った。psutilのWindows context実装ではinvoluntaryが0で返るため、その0を非自発切替がない証拠にしない。cyclesを経過時間やretired instructionsへ変換しない。

各APIは順に取得するため境界は完全に同時ではない。observerのコストがwallにも混ざり得るので、開始/終了QPC相当のperf_counter時刻とAPI所要時間を残す。CPU会計・per-CPU counterは同じOSが提供する値で、独立した物理精度の検証ではない。計測設定やCPU周波数/優先度を変更せず、測定値を都合よく補正しない。

## 診断後の判断条件

すべての照会・checksumが成功し、processと主thread CPU差が観測された15.625msの1刻み以内、子affinityがCPU0を維持し、長条件のCPU範囲/中央値が両群で2%以内なら、別計画による**一度の約24秒A/A校正**を検討する根拠とする。この条件は今回の3標本を校正合格と呼ぶものではなく、採用条件の変更でもない。別途、所定の5標本×2群等で校正しなければ候補比較へ進まない。

条件が揃わなければ採用保留を維持し、何が未確定かを記録する。同じ6秒条件のA/Aを再試行しない。主指標をwall/cyclesへ置き換えて過去の未達を通過扱いにもしない。診断・判断・レビュー後に#855を閉じ、速度改善計画全体は未完了として管理する。

## native対照への追加計画（#859）

短長16実行が完了し、localの長条件のCPU範囲/中央値は2.379%・3.626%で再校正検討条件未達だった。生存中の必須観測は取得でき、process/主thread CPUは一致、子affinityはCPU0だった。観測器だけでVM固有性は分けられないため、**VMを使わないnative対照を新たに追加する。以下はnativeの最初のpilot前の計画である。** 元の短長protocol/scriptは変更しない。

自作の短いCでvolatileなlocal=7とresultを使い、n回result+=localを行う。Zig cc、Windows GNU、CPU baseline、-O2で作成し、100反復のREADY/DONE・検査値700を事前確認した。volatileのループがある生成コードも記録する。製品コードや他実装の移植ではない。

同じ観測器・CPU0・短長順序・各3標本×2群とwarmupを使う。native-only100M pilotから約6秒のNを一度だけ固定し、長は4Nとする。計16実行＋pilotを保持し再試行しない。期待値7*Nは独立計算。コンパイル・対照の小テストは計時前に終える。

READY/DONEの生存中必須情報と、EXITの終了済process補助情報の取得不可は分けて記録する。元計画の「すべての照会成功」はEXIT情報までの意味が曖昧だったが、今回の再開不可は長条件の範囲比未達だけでも決まっており、数値条件を緩めていない。native対照ではこの取得範囲を開始前に明示する。

nativeでもCPU/wall/cyclesの変動差が出るかを観察する。出てもOS/APIの不具合と断定せず、出なくてもSigma固有と断定しない。異なる命令列・反復数の実行なので速度を直接比較せず、native対照の安定性をSigma候補の校正に流用しない。

## スケジューラー記録の利用確認（#860）

native16実行も完了したが、nativeのCPU範囲比にも短2.521%/5.198%、長1.534%/2.707%の変動が出た。Sigma固有の原因に絞る根拠がないため、次にWPR/xperfの取得可否を確認する。以下はETW開始前の計画である。

default WPRと今回の一意instanceに記録なしを読取り確認した。他のnamed instanceすべてを列挙したものではなく、他sessionを停止・変更しない。インストール済みWPRのexportしたprofileとtool helpを参照し、CSwitch/ProcessThread/ReadyThread/ThreadPriority/CpuConfig/DPC/Interruptだけの最小profile（256KB×64buffer）を作成し、profiledetailsで検証した。ネットワーク/File/Registry/stackのproviderは追加しない。特権が必要で起動できなければエラーを保持し、昇格や既存sessionの停止を行わない。

専用の一意なinstanceを作り、基準Sigmaとnative対照を3回ずつ、短条件の固定Nで1session内に記録する。これは計時比較ではなく、スケジューラーを追う別のプロファイル実行である。出力は.workspace内の.workに限定し、終了時には自分のinstanceだけstop、失敗時も同じinstanceだけcancelする。元のCPU校正・診断をこのETW実行で通過扱いにはしない。既存記録があれば開始しない。

取得できれば主threadのlifetime CPUとcontext-switch区間、DPC/ISR等の観測を照合する。trace欠落・境界の違いを確認せず一致/不一致の原因を断定しない。ETLと全イベントdumpは.workに保持し、追跡する成果物は対象の数値・手順・ハッシュ等に限る。priority/電源等の永続設定は変えない。

## 短長診断の結果

各セルは、warmupを除いた3標本の範囲/中央値。A1/A2校正のδではなく、信頼区間でもない。cyclesはQueryProcessCycleTimeの差で、経過時間やretired instructionsと同一視しない。

| プログラム | 群 | 条件 | CPU中央値ms | CPU範囲比 | wall範囲比 | cycles範囲比 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Sigma | 1 | 短 | 6,203.125 | 8.060% | 0.193% | 0.138% |
| Sigma | 1 | 長 | 24,296.875 | 2.379% | 0.201% | 0.168% |
| Sigma | 2 | 短 | 6,187.500 | 2.778% | 2.646% | 0.107% |
| Sigma | 2 | 長 | 24,562.500 | 3.626% | 0.206% | 0.114% |
| native | 1 | 短 | 7,437.500 | 2.521% | 1.886% | 0.031% |
| native | 1 | 長 | 29,546.875 | 1.534% | 0.799% | 0.018% |
| native | 2 | 短 | 7,515.625 | 5.198% | 1.822% | 0.043% |
| native | 2 | 長 | 30,015.625 | 2.707% | 2.382% | 0.060% |

SigmaのCPU範囲比は長でも両群2%超となり、事前の再校正検討条件を満たさなかった。同じ条件での再試行・候補比較はしていない。nativeにも変動があり、SigmaのVM固有の原因には絞れなかった。同じ原因が両者へ働いた、又はOS/APIの不具合という証明ではない。

nativeの100M pilotはCPU15.625msと観測された一刻みだけだった。固定Nは短38,400,000,000・長153,600,000,000となり、wall中央値は約7.9〜8.2秒/32.1〜32.3秒で、狙った約6/24秒とは異なった。粗いpilotによる反復数推定の限界として記録し、結果を見てNを直したりpilotをやり直したりしていない。Nと命令列が違うのでSigmaとの速度比は出さない。Cの生成コードには4回展開されたvolatile読込み・加算・格納のループを確認した。

Sigma16実行・native16実行＋native pilot1を保持し、checksumはすべて7*N。processと主threadのCPU差は計32診断実行で0、全READY/DONEで子affinity[0]・主thread group0/mask1を確認。取得したpriority値はprocess32/thread0で一定だったが、実効的な動的priorityや周波数の全変化を観測したものではない。両境界に共通して存在した他threadのCPU増分は0で、processへの他thread CPU混入を説明する根拠は得られなかった。新規・終了threadと、境界間だけ生存するthreadはこの差分集計に含まれない。

補助観測の最大所要時間はSigma42.189ms、native41.675ms。特にthread一覧取得が最大34.979ms、context counterが10.038ms。wallには観測負担も入るため補正して採用指標へ使わない。process CPU照会自体は最大0.163ms。DONE以後EXITまでのCPU増分は各実行0〜15.625msで、通常の終了処理を含む値。これだけで会計更新遅延の有無・精度を証明しない。

host per-CPU配列index0のbusy比は32実行とも1.0だった。レビュー後の集計ではWindowsのtotalをuser+system+idle、busyをuser+systemとして計算した。interrupt/dpcはsystemに含まれるため再加算しない。修正前の全field合計は二重計上を含んでいた。CPU0のidle増分は0で、修正後も比は1.0だった。これは対象以外の負担がない証拠でも、独立した物理CPU利用率でもない。対象CPUの周波数やschedulerの全履歴はなく、背景負荷・DPC/ISR等を原因として断定しない。

EXITでは終了済processのthread一覧等が取得できず、NoSuchProcessを原記録に保持した。生存中READY/DONEの必須fieldは取得できた。元の「全照会成功」の範囲の曖昧さを後続計画で明確化したが、Sigmaの長条件の範囲比未達は変わらず、これを理由に条件を通過扱いにはしていない。

## ETW開始結果と残る作業

最小profileの検証は成功したが、専用instanceの開始は**Access is denied、HRESULT 0x80070005**で拒否された。現在のprocessはIsUserAnAdmin=false。開始失敗後にも自分のinstanceが記録中でないことを確認し、他instanceのstop/cancelや自動昇格はしていない。ETLもprofiled workloadも取得していない。Windows側のアクセス拒否を記録している。

現状の結論は、**変動原因は未特定、セル型local候補の速度比較は未再開、採用保留を維持**。root VM・benchmark script・配布設定は変更していない。原因を仮定したVM修正や指標のすり替えは行わない。

管理者向けに専用driverとPowerShell wrapperを作り、Python構文確認と-WhatIfを実行した。wrapperは管理者を確認し、自動昇格せず、実際のPythonパスを記録した環境JSONから選ぶ。freshなadmin-*配下へ出力し、依存関係と凍結実行体を開始前に確認する。ETW取得自体はまだ未検証である。

同じworkspaceの**管理者PowerShell**で次を実行する。

```powershell
& 'D:\home\source\zig\forthz\.work\windows-timing-followup-20261116\etw\capture-admin.ps1'
```

事前表示だけなら末尾へ`-WhatIf`を付ける。既存default/own WPR記録があれば開始せず、他sessionを止めない。baseline SHA379d…等が変わっていても開始しない。取得後は新しいadmin-*/capture.jsonとETLを同じworkspaceで解析する。ETLのschema/欠落/時間境界を確認してからCPU会計との照合へ進む。#861が未完了のため#855全体も未完了。#856/#857/#859/#860は照合・診断・利用可否確認として完了し、#858で現在の観測範囲と判断をレビューした。

[全標本・固定入力・解析script・API対照・WPR拒否記録・管理者手順](measurements/2026-11-16-windows-timing-followup.json)。この作業の結果で過去の校正未達を取り消していない。


## レビューによる補正と管理者実行の確認範囲

Windowsのpsutil context counterは、`voluntary`というfield名でも全threadのContextSwitches合計で、`involuntary`は0固定である。自発・非自発の分類には使わない。[psutil 7.2.2のWindows実装](https://github.com/giampaolo/psutil/blob/release-7.2.2/psutil/arch/windows/proc_info.c)と[CPU時間の実装](https://github.com/giampaolo/psutil/blob/release-7.2.2/psutil/arch/windows/cpu.c)で確認した。観測された15.625msの刻みはscheduler quantumと断定しない。priority APIの失敗値確認は凍結観測器にはなく、今回の取得値32/0を報告する範囲に留める。

元の32標本・凍結観測器・実行順は変更せず再集計した。補正前summaryは`.work/windows-timing-followup-20261116/etw/before-review/`に保存した。nativeの2%合否fieldは事前条件がないため削除し、範囲比を記述統計だけとして保持した。CPU中央値・範囲・再開不可の判断は変わらない。

管理者driverはSystemDirectory APIで得た絶対パスのWPRだけを起動する。入力ハッシュとpsutil版を明示的な例外で確認し、Python最適化時も確認を残す。wrapperもdriverハッシュとファイル種別を確認する。同じ書込み可能workspaceのハッシュは変更検出用であり、信頼の証明ではない。stop/cancelの終了値と最終statusを保存し、停止未確認なら失敗として専用instanceの手動cancelコマンドを表示する。強制終了・端末を閉じた場合は、開始時表示またはcapture.jsonの`manual_cancel`を管理者PowerShellで実行し、そのinstanceのstatusを確認する。他instanceは停止しない。

`python -O .work/windows-timing-followup-20261116/etw/capture-admin.py --preflight`は依存版・入力ハッシュ・System32 WPRの存在を記録せずに検査する。現在の結果は入力一致、psutil7.2.2、administrator=false。`-WhatIf`はwrapperのパス・driverハッシュと表示までを確認し、管理者判定・WPR開始・後始末の動作確認にはならない。実際の管理者記録と停止処理は未実行である。

[Claude Codeの初回レビュー](VM_WINDOWS_TIMING_FOLLOWUP_CLAUDE_REVIEW.md)と[指摘への対応・検証範囲](VM_WINDOWS_TIMING_FOLLOWUP_REVIEW_RESPONSE.md)を別に保持した。


2026-11-16 後続条件：別logical CPU2を事前固定し、local/VALUE/literal→bit_andの各基準A/A校正と専用比較を完了した。[結果](VM_THREE_CANDIDATES_RESULTS.md)。CPU2のA/A成立は、CPU0のAPI/ETW残差の原因や会計精度を解明したことを意味しない。#862/#872/#873/#874はその後完了し、[残差は原因未特定で打切り](VM_WINDOWS_ETW_CONDITION_INVESTIGATION.md)とした。
