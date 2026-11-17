# 速度改善3候補の独立評価（#863）

2026-11-16。利用者の指示で、セル型local取得、VALUE呼出し、隣接命令の特殊化・融合の3件を進める。本体基準は7b1295fのruntimeで、現在HEADはf1d641c。試作と計測器は.workに分け、候補を混ぜない。採用には既存の安全性・両OS性能・サイズ条件を維持する。

## 実施範囲

1. セル型localは既存の単独試作・回帰・命令削減の記録を再照合する。計時条件の変更としてlogical CPU2を事前に一つだけ選ぶ。CPU0のETWでDPC/ISRとAPI残差を観測したことを別CPU対照の根拠とするが、CPU2なら正確・高速・安定とは仮定しない。一次指標はprocess CPUのまま、ETWやcyclesへ変更しない。
2. VALUEだけを既存.call dispatcher内でreadCell→pushへ分離する。outer_pc更新、範囲検査と容量検査の順序、failed_pc、例外・再入・TO更新を維持する。local/fvalue/two_value/synonym/defer/画像形式を変更しない。両OS生成コード・命令計数・境界・構成別回帰と辞書互換を確認する。
3. 基準版の作業コピーに隣接計数器を追加する。通常6ケースと資産生成3ケースを各2回観測し、stdout・総命令数・pairの再現性を確認する。観測対象は実行されたcompiled operationの列であり、native命令・CPU時間ではない。call/return/分岐をまたぐpairも区別せず数えるため、頻出pairだけで融合可能とは判断しない。隣接PCのpairを補助分類し、融合時には分岐流入・失敗位置・例外・SEE/保存形式の検証が別に必要と明記する。

## 計時の事前条件

全build/test/profileを終えてから計時する。CPU2は現在のprocess affinityに含まれることを確認する。rootと候補実行体・helper・scriptのハッシュを凍結し、子のCPU2 affinityを確認する。priority・電源・OSの永続設定を変更しない。

localは前回固定N=1,238,709,678を維持。VALUEは基準だけの100M pilotを一度行い、process CPUから約6秒となるNを一度固定する。pilotが0なら打切る。各対象ごとにA1/A2各5標本×2群、各armのwarmup1回、先後順交替・第2群反転を固定する。両群の全arm中央値5秒以上、最大δ2%以下を条件とする。未達ならその対象の候補を測らず、回数/N/CPUを探索しない。

両OSの校正成立後だけ各7標本×2群の専用候補比較に進む。校正成立はAPI精度や原因解明の証明ではない。local/VALUEの専用改善は2δ超を標準比較への予備条件とし、通常整数/LOOPの10%条件へ読み替えない。標準比較はWindows整数→Windows LOOP→Linux整数→Linux LOOP→残りの順で、既存の全34条件・各目標・悪化上限・サイズ各1%以内を維持する。最初の未達で止め、未測定範囲を残す。

## 打切り後も継続する範囲

local校正が失敗してもVALUEの単独試作・検証と隣接調査は進める。VALUE校正が失敗しても隣接調査は完了する。融合は頻度・安全性から具体案を選定する段階までとし、新opcodeを無根拠に追加しない。採用保留・不採用も各案の正式な結果として文書とtqueへ反映する。同じ失敗条件の再試行や主指標のすり替えはしない。

タスク：#864 local再評価、#865 VALUE、#867隣接頻度、#866レビューと採否。すべて#863配下・auto。#862の別CPU対照の設計もこの条件で具体化する。


## 途中レビュー後の明確化

VALUEの意味・失敗順に重大指摘はなかった。VALUE開始前にlocal complete.jsonを確認するguardと、ビルド結果の固定SHA照合、worker異常終了をinfrastructure_errorとして記録する処理を追加した。localの開始済みdriverは凍結したままとし、異常があれば基盤異常・未測定として別途記録する。これらは他processのbuild/test/profileを全て自動検出する仕組みではなく、本作業では実行順を制御する。Linux子affinityは親sched_setaffinityの継承に依存し、子自身の取得確認とは区別する。Windowsは生存中の子affinityを群の記録から確認する。

第三案は[隣接調査の結果とliteral→bit_andの単独試作計画](VM_ADJACENT_PAIR_PLAN.md)へ具体化した。#867の計数・選定は完了し、#868を#863配下に追加した。新opcodeやcode列の変更を伴わない先読み案を、全計時の完了後に独立して検証する。[途中レビュー](VM_THREE_CANDIDATES_CLAUDE_REVIEW.md)。
