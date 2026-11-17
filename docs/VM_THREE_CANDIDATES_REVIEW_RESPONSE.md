# 3候補のレビュー対応と採否

2026-11-16 後続：利用者が部分採用基準の変更を承認し、[#875/#876の実例評価](VM_PARTIAL_ADOPTION_RESULTS.md)を実施した。pinball資産生成・logicは通過したが、短いwaterworks logicの計時で停止。追加採用は保留、#870は#877の計時入力設計が残る。以下の判断待ちという表記は当時の記録である。

2026-11-16。[途中レビュー](VM_THREE_CANDIDATES_CLAUDE_REVIEW.md)と[最終技術レビュー](VM_THREE_CANDIDATES_FINAL_REVIEW.md)を受けて対応した。レビューは読取り専用で、実行検証の独立再実施ではない。

## 途中レビューへの対応

- VALUEの読み書き順・outer_pc・failed_pc・frame状態に重大指摘はなかった。入れ子InvalidAddress、compiled呼出し3段のbacktrace、CATCH復元を基準・候補の同じテストへ追加し、基準版はWindows GNU Debugの1構成、候補版はWindows GNU/Linux musl各5構成で確認した。CPU生成設定は各構成ともbaseline。基準・候補の動作比較を実行した追補範囲はWindows Debugに限る。
- VALUE開始前にlocal completeの確認、ビルド結果の固定SHA照合、worker失敗をinfrastructure_errorとして終了記録する処理を追加した。localの開始済みdriverは変更していない。VALUEの予備条件名をdedicatedへ訂正した。
- Windowsも別のシンボル付き生成物でPDB source lineと逆アセンブルを対応づけた。readCellの負値・範囲検査、容量検査、load/store、outer_pc更新を両loopで確認した。静的な観察に限定する。
- 隣接pairのケース別回数・隣接PC数・偏り、分類の限界を計画へ追加した。callは語自身のkindでありsynonym/deferの解決先ではない。inline標識と通常callは同じcall_colonキーで、PC隣接は同じframe・融合安全性の保証ではない。
- literal→bit_andはN依存のmask/wrap/DEPTHを24実行、counted profileの総operation数を4実行で確認した。計時kernelの定数7だけではNやANDの実行回数を検証しないと明記した。外れ側を含む既存12対照も再計数した。

## 最終技術レビューへの対応

| 指摘 | 対応・確認範囲 |
| --- | --- |
| M1 残り1セルを踏まないfixture | smallストレージは1024。4095/4096の丸めをやめ、実際のlen−1/lenを明示。基準・候補に同じfixtureを追補。基準版はWindows GNU Debugのみ、候補版は両OS各5構成で通過 |
| M2 計時前検証の機械的強制不足 | 今回のLinux補完3構成は全ELF exit0で、保存時刻がFUSION start以前だったことを照合。準備器にも3構成・ELF exitと主要置換のpostconditionを追加。開始済みcontroller/worker/protocolは凍結したまま。globalな他process検出を実装したとは扱わない。準備器の追加assertは開始済みguardより後にあり、この作業領域で実行した検証ではない。 |
| M3 BYE・再入・compiled CATCH | 同じループのCATCH失敗→resume→次のpair、pair後BYE、出力callback内のpair実行と戻り時のscope復元を追加。keep_counting=false/trueを設定した候補の両OS各5構成を追補。ただしcounted経路を選ぶのはdebug有効構成だけで、debug無効・最小構成は両設定とも非counted経路 |
| M4 外れ側の正味負担 | pair出発側からliteral総数53,693,908〜53,693,917、一致17,956,448を記録。単独kernelの差分を仮に線形適用した増加側の算術例も掲載。ただし差分はkernel全体・周辺コード生成を含むため、実例の正味Irの実測や信頼できる予測にはできない。候補のCPU採否は別の実測で判断した |
| M5 FUSION現状 | 最終のCPU比較・未strip命令計数の区別、補完実行、採否を結果へ反映。Windows専用予備条件未達、本体未反映 |
| L1 未測定範囲 | local/VALUEは標準1条件未達、33条件未測定。FUSIONは標準34条件すべて未測定。専用短縮だけで部分採用を確定しない |
| L2 Windows会計刻み | 今回の全Windows CPU値が15.625msの倍数と照合。標準整数の小差は0〜数刻みで、高精度の効果や時計の正しさと扱わない |
| L3 監査範囲 | helper/worker/controller/protocol・各結果metadataのSHA、順序、配列、CPU照会差、中央値からA/Aと比較・最終statusを再計算。logとCallgrind等の最終更新時刻が各計時区間内にないことも記録。mtimeだけでprocessの開始終了・他の背景負荷を独立証明しない |
| L4 古いprotocol説明 | 元の凍結protocolは改変せず、annotationsにFUSION固有の定数7・N未検証・実行順を記録。workerの期待値自体は7で正しく比較されている |
| L5 Windows先読み生成 | 計時後に同じruntime SHAからシンボル版を別作成し、PDB行2050付近の語末/次tag比較、AND、ループ復帰を確認。Windows命令数やstrip版とのbyte一致を証明したとは扱わない |
| L6 Linux子affinity | 親のsched_setaffinity継承であり、子自体の直接照会ではないことを維持 |

## 実行順の相違と限界

最終レビューはFUSIONの基準A/A開始後に届いた。M1〜M3は計時前の追補を勧める指摘だったが、runtimeの修正は不要で、同じ候補の試験追加で確認できると判断した。進行中の計時にbuild/test/profileを重ねず、計時を取り直して標本を選び直すこともせず、全計時後に追補を行った。当初の事前検証に不足があったことと、この順序を明記する。追補で候補のruntime修正が必要になった場合は、元の速度結果を修正後候補へ流用しない方針だった。

追補は基準・候補で同一のtest source bytesを確認し、基準版はWindows GNU Debugの1構成、候補版はWindows GNU/Linux musl各5構成で通過した。成功済みhost等のcache再利用はlogに残した。root runtime、各候補runtimeと計時実行体のSHAは変わっていない。追補後の[再々レビュー](VM_THREE_CANDIDATES_REREVIEW.md)を#869で実施した。再計時はしていない。現在の再ハッシュ照合を実施して値と生成scriptをJSONに保存したが、追補期間全体の連続的な不変証明ではない。

## 採否

localは専用約11〜18%短縮、VALUEは専用約42〜45%短縮を観測した。ただし標準整数の10%目標に届かず、残り33条件も未評価なので、本体へ追加採用しない。literal→bit_andはLinux専用約17%短縮に対しWindows専用約1〜2%増加となり、両OS予備条件未達で本体へ採用しない。命令数や局所の短縮から、通常版全体の改善を作ったとは結論しない。

[全結果](VM_THREE_CANDIDATES_RESULTS.md)と[全標本・script・検証・監査](measurements/2026-11-16-three-candidates.json)。この3候補の評価範囲を完了し、CPU0 API/ETW残差は#862/#872/#873/#874を完了し、[原因未特定で打切り](VM_WINDOWS_ETW_CONDITION_INVESTIGATION.md)。部分採用は[#870の評価案](VM_PARTIAL_ADOPTION_EVALUATION_PLAN.md)を作成済みで、基準変更の判断と追加評価は未実施のため未完了とする。


## #869 再々レビューの補正と限界

| 指摘 | 対応 |
| --- | --- |
| N1 追補の基準版構成 | 基準版Windows Debugのみと、候補版両OS各5構成を分けて訂正 |
| N2 古いタスク状態 | ETW関連4件の完了・打切りと#869実施を記録。#870は評価案作成済み・基準判断と追加評価は未実施 |
| N3 ハッシュ再照合の証拠 | 現在の実ファイルからroot runtime・候補最終bytes・計時実行体を再ハッシュし、値・UTC・生成sourceを保存 |
| N4 保存scriptの履歴 | 実行後編集・追加assert未実行・fixture差替え手順未保存を明記。旧fusion-frozenを注記付きで保存し、旧文書生成器の再実行を拒否 |
| N5 countedの範囲 | debug有効構成だけと限定 |
| N6 再入の確認範囲 | callback到達・scope復元までとし、内側pair結果の積極検証は未実施と明記 |

中2件・低4件の指摘へ対応し、採否・数値は維持した。基準版の追補実行はWindows Debugの1構成だけであり、候補版の両OS各5構成と区別する。基準と候補の同一test bytesを確認したことは、基準版の両OS全構成の実行を意味しない。

`build-fusion.py`と`prepare-fusion-performance.py`は実行後に編集された保存版であり、追加assertを実行済みとは扱わない。追補時のテスト差替え手順は未保存で、最終bytes・SHAと実行ログが確認範囲である。旧`fusion-frozen.json`のtests SHAは初回版を指し、最終fixtureのSHAとは異なる。旧凍結記録は改変せず、注記付きで測定JSONへ収録した。

再入テストはcallbackへの到達・エラーなし・scope復元を確認したが、内側のstack中立なpair結果を積極的に照合していない。内側pairの意味を独立検証したとは主張しない。counted経路の確認はdebug有効構成だけで、debug無効・最小構成はkeep_counting両値とも非counted経路である。

現在の再ハッシュ照合はroot runtime・各候補の最終source・計時実行体が保存値と一致することを確認した。値・UTC・生成scriptは測定JSONの`rereview869.hash_audit`へ保存した。過去の全時点の不変性を証明するものではない。文書の検証範囲を補正した対応であり、runtime・fixtureは変更せず、新しいビルド・テスト・計時は行っていない。
