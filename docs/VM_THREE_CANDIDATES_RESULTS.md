# 速度改善3候補の評価結果（#863）

2026-11-16 後続：利用者が部分採用基準の変更を承認し、[#875/#876の実例評価](VM_PARTIAL_ADOPTION_RESULTS.md)を実施した。pinball資産生成・logicは通過したが、短いwaterworks logicの計時で停止。追加採用は保留、#870は#877の計時入力設計が残る。以下の判断待ちという表記は当時の記録である。

2026-11-16。各候補を採用済み基準から独立して評価した。組合せの速度・安全性を検証したという意味ではない。追加採用はなく、rootのVMと既存実行体は維持した。専用ケースの改善がなかったという結論ではない。

| 単独案 | Windows専用CPU変化率（2系列） | Linux専用CPU変化率（2系列） | 採否 |
| --- | ---: | ---: | --- |
| cell local_fetch | −11.026% / −11.735% | −17.959% / −18.470% | 標準整数目標未達・本体未反映 |
| VALUE経路分離 | −42.424% / −42.523% | −43.104% / −44.549% | 標準整数目標未達・本体未反映 |
| literal→bit_and先読み | ＋1.882% / ＋1.344% | −17.431% / −17.454% | Windows専用予備条件未達・本体未反映 |

負数は短縮、正数は増加。特定のCPU2・入力・環境での観測で、アプリ全体の短縮率ではない。Windows CPU値は15.625ms刻みで観測され、6秒の約0.26%に相当する。標準整数での0〜数刻みの差を高精度の効果と扱わない。A/Aは信頼区間や精度保証ではない。

## セル型local取得の再評価（#864）

- windows/local A/A最大δ1.023%、最小中央値6109.375ms。通過=True。
- linux/local A/A最大δ0.239%、最小中央値6451.439ms。通過=True。
- windows/arithmetic A/A最大δ1.047%、最小中央値5968.750ms。通過=True。
- windows/local CPU変化率：-11.026% / -11.735%。
- linux/local CPU変化率：-17.959% / -18.470%。
- windows/arithmetic CPU変化率：+0.257% / +0.783%。

状態：`standard_primary_target_unmet`。CPU2はCPU0と別の事前固定条件であり、過去の未達を取り消していない。Windowsの生存中子affinity[2]とCPU照会差を照合した。Linuxは親のaffinity継承で、子そのものの照会はしていない。
専用localケースの効果を標準整数演算・LOOPの10%短縮へ読み替えない。標準34条件のうちWindows整数1条件を測って未達、残り33条件は未測定。局所改善の部分採用についても、残りの性能条件を通過したとは判断しない。

## VALUE呼出し（#865）

単独変更は.call内の.valueだけ。outer_pc更新とreadCell→pushの順を維持し、synonym/defer/EXECUTE経由等は既存経路を残した。Linuxの対象kernelはIr201→124、deferred-colonは217→218、ほかの10対照は同数。未strip版の計数であり、strip実行体のCPU時間とは区別する。
Windowsサイズは基準と同一1,809,408bytes、Linuxは1,891,456→1,891,632bytes（+176bytes、約0.0093%）。
初回のWindows debug/fastは各1,072成功/10skip、debug無効1,005/77skip、float無効1,007/49skip、最小591/462skip。Linux Debug/fastはcore1,013成功/5skip、host63成功/1skip。cross親のELF直接起動失敗を保持し、WSLで実行した。CLI18件は補完であり、VALUEそのものの検証ではない。両OS標準16組・辞書12実行・実例9組の出力一致は限定した状態確認であり、全画面の一致ではない。
- windows/value A/A最大δ0.701%、最小中央値6671.875ms、通過=True。
- linux/value A/A最大δ0.869%、最小中央値5853.492ms、通過=True。
- windows/arithmetic A/A最大δ0.265%、最小中央値5890.625ms、通過=True。
- windows/value CPU変化率：-42.424% / -42.523%。
- linux/value CPU変化率：-43.104% / -44.549%。
- windows/arithmetic CPU変化率：+0.265% / +0.000%。
状態：`standard_primary_target_unmet`。専用の約42〜45%短縮は部分効果であり、標準整数の10%目標を満たしていない。標準34条件のうちWindows整数1条件を測って未達、残り33条件は未測定。本体への追加採用は行わない。

VALUE追補では、基準・候補に同じ入れ子InvalidAddress/CATCH/3段backtraceテストを追加した。CPU設定をbaselineに固定し、基準版はWindows GNU Debugのみ、候補版はWindows GNU/Linux musl各5構成（Debug/fast・debug無効・float無効・最小）で確認した。Windows debug/fastは追加後1,073成功/10skip、Linux coreは1,014成功/5skip、host63成功/1skip。その他の構成・cache再利用の有無は各logのsummaryをJSONへ保存した。Linux親CLIの直接起動失敗と、WSLのELF実行成功は区別する。
WindowsはPDBのsource lineから両loopのVALUE成功経路を対応づけ、outer_pc更新、負値/範囲/容量検査、memory load、stack storeを確認した。選択した成功block内にhelper callはなかった。未strip版の静的な観察で、strip計時実行体とのbyte一致や全経路の動的観測とは主張しない。

## 隣接命令（#867・#868）

9ケース×2回の総operation数・pair・stdoutが一致した。合計544,675,224 operation。literal→bit_andは17,956,448回。資産生成へ偏る入力であり、一般的な時間比や期待改善率ではない。profile用plain_callsを外す変更は作業コピーだけ。rootの通常profile仕様は維持した。
[選定理由と単独試作計画](VM_ADJACENT_PAIR_PLAN.md)。保存形式・code列を変えない非counted実行時先読みを単独試作した。local/VALUEの全計時終了後にビルド・検証した。
対象kernelのLinux Irは87→78。一方、先読みが外れるliteral対照87→95、colon-call111→119、deferred-colon217→225等の増分もあり、対象の削減だけで採用しない。Windowsサイズは1,809,408→1,808,896bytes、Linuxは1,891,456→1,891,536bytesで、各1%以内。
元のliteral/AND本体を順に実行し、元のcode列とcounted側を維持した。深さ0のANDは、右operandのliteralをpopしてから左operand不足を返す。最初の基準試験でテスト側の期待値1が実際の0と違うことを検出し、integer_math.zigの2回pop順に合わせて期待値と計画文を修正した。runtimeをこの期待に合わせて変えたものではない。fixture構文の初回失敗と合わせてlogを保存した。
通常のN依存mask/wrap/DEPTH24実行、counted profile4実行、両OS標準16組、辞書12実行、実例9組の出力確認が通過した。Windows構成別とLinux Debug/fastのcore/host、Linux CLI18件も確認した。これらは全入力・全画面やCPU精度の保証ではない。
- windows/fusion A/A最大δ0.271%、最小中央値5765.625ms、通過=True。
- linux/fusion A/A最大δ0.582%、最小中央値5932.407ms、通過=True。
- windows/fusion CPU変化率：+1.882% / +1.344%。
- linux/fusion CPU変化率：-17.431% / -17.454%。
状態：`dedicated_screen_unmet`。

FUSIONのIrはLinux未strip版の命令計数で、CPU時間ではない。CPU比較は上記の両OS専用ケースを実測し、Windowsで予備条件未達のため標準34条件はすべて未測定。Windowsでも別のシンボル付き生成物をPDB行情報と対応づけ、語末/次tagの比較とAND処理を含む先読みblockを確認した。これは静的観察であり、Windowsの実行命令数やstrip計時版とのbyte一致ではない。
literal総数はpairから53,693,908〜53,693,917回、一致17,956,448回で、不一致も多い。外れ側を含む注意と仮定付き算術例を[選定計画](VM_ADJACENT_PAIR_PLAN.md#literal全体と外れ側の注意)へ記録した。kernel差分を実例全体へ線形に足し引きすることは実測や信頼できる予測ではない。
最終レビューは基準A/A開始後に届いた。初回fixtureはsmall容量1024を4096と取り違えて残り1セルを未検証だったため、len−1/lenへ修正し、compiled CATCHのresume・pair後BYE・出力callback再入の2テストも追加した。候補runtimeと計時実行体は変更せず、追補試験は全CPU計時終了後に実施する順序とした。これは当初の事前検証不足であり、追補前に全境界を確認済みだったとは主張しない。
全計時はwarmup込み448実行＋baseline pilot6実行。全群配列・CPU照会差・SHA・中央値・A/Aと比較・終了理由を再計算した。filesystemのlog最終更新時刻も照合したが、これだけでprocess開始/終了や他の背景負荷を独立証明したものではない。

[事前計画](VM_THREE_CANDIDATES_PLAN.md)、[途中レビュー](VM_THREE_CANDIDATES_CLAUDE_REVIEW.md)、[固定入力・全標本・検証・script](measurements/2026-11-16-three-candidates.json)。

## 最終追補と判断

計時終了後の追補は、基準・候補の同一テストで容量len−1/len、compiled CATCH復帰、BYE、出力callback再入まで確認した。CPU設定をbaselineに固定し、基準版はWindows GNU Debugの1構成、候補版はWindows GNU/Linux musl各5構成で通過した。Linux ELFはWSLで実行し、CLI18件は別に補完した。成功済みhost等のbuild cache再利用もlogに残す。runtime source SHAと計時実行体は変更せず、追補後の再計時はしていない。
localとVALUEは対象ケースの短縮を確認したが、標準目標に届かず、残り33条件を通過したとは扱えない。literal/ANDはWindows専用予備条件で未達となり標準34条件は未測定。この3試作を本体へ追加採用しない。部分改善として再提案する場合も、未評価の性能条件と採用方針の判断が残る。
[最終技術レビュー](VM_THREE_CANDIDATES_FINAL_REVIEW.md)と[指摘への対応](VM_THREE_CANDIDATES_REVIEW_RESPONSE.md)。最終追補後の[再々レビュー](VM_THREE_CANDIDATES_REREVIEW.md)を#869で実施し、検証範囲・生成手順の記録を補正した。#864/#865/#867/#868の評価と#866の記録・レビュー対応を完了する。CPU0のAPI/ETW残差の原因は未特定で、#862/#872/#873/#874は完了して[残差調査を打切り](VM_WINDOWS_ETW_CONDITION_INVESTIGATION.md)。部分採用は[#870の評価案](VM_PARTIAL_ADOPTION_EVALUATION_PLAN.md)の判断・追加評価が残る。


## #869 再々レビューの補正と限界

中2件・低4件の指摘へ対応し、採否・数値は維持した。基準版の追補実行はWindows Debugの1構成だけであり、候補版の両OS各5構成と区別する。基準と候補の同一test bytesを確認したことは、基準版の両OS全構成の実行を意味しない。

`build-fusion.py`と`prepare-fusion-performance.py`は実行後に編集された保存版であり、追加assertを実行済みとは扱わない。追補時のテスト差替え手順は未保存で、最終bytes・SHAと実行ログが確認範囲である。旧`fusion-frozen.json`のtests SHAは初回版を指し、最終fixtureのSHAとは異なる。旧凍結記録は改変せず、注記付きで測定JSONへ収録した。

再入テストはcallbackへの到達・エラーなし・scope復元を確認したが、内側のstack中立なpair結果を積極的に照合していない。内側pairの意味を独立検証したとは主張しない。counted経路の確認はdebug有効構成だけで、debug無効・最小構成はkeep_counting両値とも非counted経路である。

現在の再ハッシュ照合はroot runtime・各候補の最終source・計時実行体が保存値と一致することを確認した。値・UTC・生成scriptは測定JSONの`rereview869.hash_audit`へ保存した。過去の全時点の不変性を証明するものではない。文書の検証範囲を補正した対応であり、runtime・fixtureは変更せず、新しいビルド・テスト・計時は行っていない。
