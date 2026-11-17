# Windows ETWによるCPU時間の照合（#861）

2026-11-16後続結果：#873でCPU0/2・観測器minimal/full・ETW off/onの128実行を取得し、2本のtraceを照合した。[対照診断結果](VM_WINDOWS_ETW_CONTROL_RESULTS.md)。CPU2の今回の条件別変動幅は小さいがAPI/ETW残差は残り、原因は未特定である。

2026-11-16追補：#862の[対照診断設計](VM_WINDOWS_ETW_CONTROL_PLAN.md)を作成した。CPU0/2、観測器minimal/full、ETW off/onを2群で比較する。設計時点では取得はまだ行っていなかった。その後の取得・打切り判断は冒頭の後続結果に記録した。#862と後続の実装・事前検証#872は、速度改善の親#786配下で管理する。本文中の「121配下」は登録当時の記録である。

2026-11-16。利用者が管理者PowerShellから専用driverを実行し、基準Sigma3回・native対照3回の取得に成功した。先のAccessDeniedはこの実行で解消した。新しい速度比較・校正ではなく、計時変動の診断である。

## 取得と整合性

- 専用instance `SigmaTiming2bdcbacfad`、44.9769444秒。6標本のchecksumは7*N。stop exit0、cleanup_confirmed=true。ETLは55,312,384bytes、SHA256 `a5d55b65cb1ec469993102a7ae0db4a363db3f68f765d9c393281ec01dd56fbf`。
- xperfの報告はLost Events=0、Lost Buffers=0。CSwitch723,767件の全CPU old/new thread連鎖に不一致は0。対象primary TIDをprocess/thread開始・終了イベントと対応づけた。対象の全sliceはCPU0、切替時のpriorityは8/9/10だった。API境界のpriority値0は動的priorityが常に固定という意味ではなかった。
- xperfは44.493519秒のSysConfig Logical Disks（type0x0c/version2）1件にInvalid Event警告を出した。全対象thread終了後の構成イベントであり、CSwitchイベントの警告ではない。CSVにはInvalidEvent行がなかったが、これで全イベントの妥当性が証明されたとは扱わない。rundownには機器・サービス等の情報も含まれるため、ETLと全CSVは.workだけに保持する。
- 自作parserの各sliceをxperf出力と照合し、整数マイクロ秒への丸めによるstart差は最大1us。thread別のDPC/ISR控除後合計はxperf標準cswitch集計との差が最大13usだった。独立した計測器との一致ではなく、同じETLを使った集計照合である。

## 同じthreadの全生存期間で比較

APIはEXIT時に取得した主threadのkernel+user累積値。ETWは同じTIDの切替slice合計で、xperf標準`cswitch -thread`と`-exc_dpcisr`を使う。READY/DONE間のCPU値とは境界が異なるため、表では全生存期間どうしを比較した。thread終了イベントから最後のswitch-outまで14〜125usあり、終了処理を含むsliceの境界差は残る。

単位はms。差はAPI−ETW控除後。

| 実行順 | 対象 | API主thread累積 | ETW切替slice | DPC/ISR控除分 | ETW控除後 | 差 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | sigma | 5796.875 | 6512.496 | 298.897 | 6213.599 | -416.724 |
| 2 | native | 7500.000 | 7852.111 | 370.041 | 7482.070 | +17.930 |
| 3 | native | 7375.000 | 7838.019 | 359.113 | 7478.906 | -103.906 |
| 4 | sigma | 6125.000 | 6614.009 | 437.932 | 6176.077 | -51.077 |
| 5 | sigma | 6031.250 | 6726.435 | 550.356 | 6176.079 | -144.829 |
| 6 | native | 7593.750 | 8131.751 | 648.675 | 7483.076 | +110.674 |

ETWの切替sliceは、そのthreadが選択されていた時間の集計であり、DPC/ISRの実行が入り得る。控除分は298.897〜648.675msだった。一方、控除後もAPIとの差は−416.724〜+110.674ms残り、符号も一定でない。観測されたDPC/ISR時間を引くだけではAPIとの一致は得られなかった。

3回ずつの全生存期間の範囲/中央値は、SigmaがAPI5.440%・ETW控除後0.608%、nativeがAPI2.917%・ETW控除後0.056%だった（正確な再計算値はJSON）。これは少数標本の記述統計であり、2%校正の合格、代替指標の採用、ETWの絶対精度の証明には使わない。異なる命令列と反復数なのでSigma/native速度比も出さない。

## 結論と次の切分け

process/primary APIの区間CPU差は6回とも0だった。主threadへの他thread CPU混入や移動先CPUの見落としを示す記録はない。一方、スケジューラー由来の時間とAPI累積時間に差が残る。**差の発生を観測したが、OS/APIの不具合、周波数、特定driverを原因と断定する根拠はない。** ETWの記録負担も含む単一セッションである。

以下は生QPC照合前の判断である。READY/DONE区間とETWの厳密な対応はこの時点では未完了。現在の補助集計はobserver UTCをtrace UTCに合わせた近似で、時計調整・API照会の前後差を排除していない。今回の主表はこの近似に依存しない全生存期間の照合とした。

この時点で次の作業とした記録済みETLの生QPC timestampとobserverのperf_counterの照合は、以下で実施済みである。計画は、同じREADY/DONE境界でスケジューラー区間を集計する。既存記録から確定できなければ、QPC境界markerを含む専用診断を先に設計し、再取得の目的・成功条件を固定する。原因を仮定したVM修正や主指標の変更は行わず、候補比較・採用は引き続き保留する。

[全6標本・導出値・解析script・取得情報](measurements/2026-11-16-windows-etw-analysis.json)。rootのVM・benchmark helper・配布設定は変更していない。#861の取得と全生存期間照合を完了し、生QPCによる区間照合も続けて実施した（下記）。


## 続けて実施した生QPCによるREADY/DONE区間照合

追加の記録は行わず、Windows OpenTraceW/ProcessTrace APIのRAW_TIMESTAMPモードで同じETLのCSwitchを読み直した。専用C補助プログラムは.work内だけに作成し、ProcessTrace/CloseTraceともexit0、723,767件を抽出した。clock typeは1（QPC）、frequencyは10,000,000。解析環境のPython perf_counterがQueryPerformanceCounter実装であることを確認した。取得時processのclock infoと原点は直接記録していない。取得時との原点一致は、先のUTC近似窓とのgross差が6行とも16〜33usだったことによる間接確認であり、直接の証明ではない。

全CSwitchのpayload先頭8byteから得たnew/old TIDとCPUが、xperfの723,767行とすべて一致した。生QPCから換算した時刻とxperf時刻のoffset幅は1us以内。各CPUの直前switchからtargetのswitch-outまでを積算し、observerのprocess_query_end_nsで同じREADY/DONE区間に切りそろえた。UTCによる時計合わせをこの表には使っていない。

DPC/ISRはxperfのslice別控除値を利用する。境界で一部だけ重なるsliceは6実行とも0件だった。下表のETW範囲は、sliceごとの整数us丸めに各±1us、API照会の両境界bracket合計を加えた保守的な幅であり、信頼区間やETW全体の精度保証ではない。APIの全生存期間・区間値はすべて15.625ms刻みで観測され、この幅にAPIの量子化は含めていない。行2の差は観測刻み未満で、sub-ms精度のAPI差を示すものではない。

| 実行順 | 対象 | API process区間CPU ms | ETW区間・DPC/ISR控除後 ms | API−ETW ms |
| --- | --- | ---: | ---: | ---: |
| 1 | sigma | 5781.250 | 6207.768〜6208.882 | -427.632〜-426.518 |
| 2 | native | 7484.375 | 7478.655〜7480.077 | +4.298〜+5.720 |
| 3 | native | 7375.000 | 7475.928〜7477.276 | -102.276〜-100.928 |
| 4 | sigma | 6125.000 | 6170.966〜6172.161 | -47.161〜-45.966 |
| 5 | sigma | 6031.250 | 6170.919〜6172.199 | -140.949〜-139.669 |
| 6 | native | 7578.125 | 7480.007〜7481.433 | +96.692〜+98.118 |

表のAPI区間CPUはprocessの値で、primary threadとの差は6回とも0だった。同じREADY/DONE区間でも、API−ETWの差はSigma最初が約−427ms、native最後が約+97msとなり、全生存期間の境界違いだけでは解消しなかった。DPC/ISRを引いた後の差が残ることを、記録済みデータの別の境界でも確認した。**APIまたはETWのどちらかを正解と認定したものではなく、会計方式・仮想化・周波数・driver等の原因は引き続き未特定である。**

次の調査対象は、同じ区間・同じ時計で残ったAPI/スケジューラー時間の差である。CPU0のDPC/ISRは観測できたが、その負担と残差が同じ原因であるとは断定しない。新たな環境変更・指標変更・候補比較を始める前に、対照条件と成功条件を別途固定する。


[Claude Codeレビュー](VM_WINDOWS_ETW_CLAUDE_REVIEW.md)と[指摘反映・残作業](VM_WINDOWS_ETW_REVIEW_RESPONSE.md)。#861と#855の診断範囲は完了。残差の原因をさらに切り分ける対照診断の設計を#862として121配下・autoで登録した。
