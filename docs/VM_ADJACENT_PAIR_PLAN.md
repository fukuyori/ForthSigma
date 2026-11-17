# 隣接命令の計数と単独試作の選定（#867）

2026-11-16。実例9ケースを各2回計数し、stdout、全operation数、全pair数が再現した。通常時のインライン方針を維持するため、作業コピーではprofileによるplain_calls指定だけを外した。rootのprofile仕様は変更していない。reset対照は5operation（literal/literal/add/drop/exit）、2回実行10operation、事前実行後resetで5operationを確認した。

計544,675,224 operationの内訳は資産生成3ケースの比重が大きく、利用者一般の平均を表さない。頻度はCPU時間比でも期待改善率でもない。

| pair | 全9ケースの回数 | operation総数に対する比 |
| --- | ---: | ---: |
| local_fetch → literal | 26,302,055 | 4.829% |
| local_store → local_fetch | 22,287,605 | 4.092% |
| literal → bit_and | 17,956,448 | 3.297% |
| local_fetch → local_fetch | 15,517,663 | 2.849% |
| literal → rshift | 11,819,618 | 2.170% |
| local_fetch → add | 11,753,743 | 2.158% |

## 単独試作へ進める案

**literal→bit_andの実行時先読みだけを選ぶ。** 頻度1位のlocal案と変更を混ぜず、frame/address計算・通知・型分岐を持たない小さなpairから検証する。※仮説です。dispatch1回を省ける可能性はあるが、literal一般の先読み負担・コード配置変化による悪化もあり得る。

新opcode、compiler、保存形式、元のcode列、SEEを変更しない。通常非countedループでliteralを既存pushした後、pc<end_pcかつ次がbit_andの場合だけ、次のpcを既存と同じ位置へ進め、既存bit_and本体を呼ぶ。literalでの容量不足が先、成功後にbit_andが深さ不足なら、先にliteralをpopしてから不足を返す既存の途中状態を維持する。失敗PCは失敗した命令の次を維持する。bit_andへ直接分岐で入る場合は従来の単独経路が残る。

countedは既存経路を維持し、trace/profile/WATCH/step/coverageの命令境界を省かない。literalとbit_and自身にはhost呼出しを追加しない。境界・データ/return/float stack・pending出力エラー・CATCH・BYE・StepLimit・再入・画像双方向読込みを確認する。

build/test/profileを計時に重ねない。現在のlocal/VALUE校正が終わってからビルドする。Linuxの対象kernel100/200差で命令削減がなければ棄却する。両OSサイズ増各1%以内、構成別回帰・辞書確認を先に行う。

専用CPU kernelは `: BENCH-RUN 7 BENCH-ITERATIONS 0 DO 65535 AND LOOP ;`、期待値7。CPU2、baseline100M pilot一度で約6秒Nを固定し、A/A5回×2群・中央値5秒以上・δ最大2%以内、未達で再試行なし。両OS通過後だけ7回×2群比較、2δ超の短縮を予備条件とする。予備通過時のみ既存標準34条件を同じ順序・判定で評価する。専用の改善だけで本体へ採用しない。

今回の対象は実行されたcompiled operationの隣接であり、nativeやinterpreterの全命令は含まない。PC隣接は融合の一般的安全性を証明しない。この試作はcodeを書き換えず、元の2命令の順序と例外境界を個別に検証することで判断する。


## 初回レビュー後の補足（計時前）

| ケース | literal→bit_and | 隣接PCで観測 | operation総数に対する比 |
| --- | ---: | ---: | ---: |
| pinball-logic | 67,840 | 67,840 | 0.318% |
| waterworks-logic | 1 | 1 | 0.000% |
| klondike-logic | 31,948 | 31,948 | 1.502% |
| pinball-render | 2,830 | 2,830 | 0.322% |
| waterworks-render | 120 | 120 | 0.031% |
| klondike-render | 2,363,121 | 2,363,121 | 9.658% |
| pinball-bake | 7,712,052 | 7,712,052 | 3.132% |
| waterworks-bake | 989,231 | 989,231 | 1.156% |
| klondike-bake | 6,789,305 | 6,789,305 | 4.165% |

資産生成3ケースの比重が大きいので、この合算を通常操作の一般的な効果と扱わない。隣接PC数はフレームや分岐をまたがない保証ではない。callは未解決の語種で、synonym/deferの解決先ではなく、call_colonのinline標識と通常callも同じキーに含む。入れ子実行ループとinterpreter/nativeによる観測の隙間をまたぐpairも含む。今回の有効入力を超えてFORGET後の不正id等を計数できるとは主張しない。

先読みが外れる側も含め、既存12対照をCallgrindで再計数する。専用kernelの期待値7だけでは反復実行やAND実行を保証しないため、別の非計時対照で `0から1+して65535 AND` をN=1/2/65535/65536/65537/100000回実行し、期待値N AND 65535とDEPTHを両版で照合する。countedのoperation総数も別に確認するが、counted側は先読みを使わないので通常経路の実行保証とは区別する。


## 最終レビュー後の追補順序

smallストレージのdata容量は1024であり、初回fixtureの4095/4096丸めでは残り1セルの条件を踏めていなかった。明示的にlen−1とlenへ修正し、compiled CATCHのresume、pair後のBYE、出力callbackからの再入でpairを実行する試験を追加する。これらの指摘はFUSIONの基準A/A開始後に届いた。候補runtime・計時実行体は変更せず、追補試験は全計時終了後に実行する。初回の事前検証不足と実行順を残し、計時をやり直して標本を選び直すことはしない。追補で意味差が見つかれば採用せず、その場合の既存計時は修正候補の効果へ流用しない。


## literal全体と外れ側の注意

literalを出発点とするpairの合計は53,693,908回。末尾1命令がliteralかをpairだけから確定しないため、literal総数は9ケース合算で53,693,908〜53,693,917回の範囲とする。一致は17,956,448回、不一致は少なくとも35,737,460回ある。

※仮説です。単独kernelの一致−9Ir、不一致＋8Irを出現ごとへ仮に線形適用すると、正味は＋124,291,648〜＋124,291,720Irという増加側の算術例になる。ただし各kernel差分はループ全体・レジスター割当て・周辺コードを含み、literal1回の固有費用ではない。別対照では命令数が減った例もあり、この式を実例の正味Irの実測や信頼できる予測、CPU時間へ換算してはならない。専用kernelは一致100%の有利な入力で、標準・実例への利益を代表しない。これを理由に採用基準を緩めず、実測の評価と分ける。

2026-11-16 実施後追記：上記の追補・N依存対照は実施済み。[最終結果と#869の確認範囲補正](VM_THREE_CANDIDATES_RESULTS.md)。再入試験はcallback到達とscope復元までで、内側のstack中立pairの結果は積極検証していない。
