# localアクセスとcall内訳の調査（#847）

2026-11-16 後続結果：[CPU2でのlocal再評価・VALUE試作・隣接先読みの評価](VM_THREE_CANDIDATES_RESULTS.md)を完了した。専用ケースの短縮と標準目標未達を記録し、本体への追加採用はない。以下は本資料の調査・試作時点の記録であり、後続の比較未実施という現在状態を表さない。

2026-11-16。採用版の実装・両OSのシンボル付き生成物・Linux命令計数・実例9ケースを照合した。**次の統合判断へ残す局所案は、セル型localの経路分離とVALUE呼出しの経路分離。いずれも効果未確認の仮説で、まだ試作・本体反映していない。** 先に#848で資産生成の内訳を確認し、#849で一案を選定する。

## localの実装と生成コード

localのoperandは下位32bitのoffsetと上位のLocalKind。VMはlocals_frame!=0を確認してaddressを計算し、fetchLocal/storeLocalへ渡す。関数はcell/xt、double、float、charを分岐し、readCell/writeCell等を呼ぶ。XT:の名前参照はlocal_executeとなるので通常のlocal_fetchと同一視しない。型付きの変数参照はlocal_addressにもなる。

Linuxの非counted経路にはfetchLocal/storeLocalへの通常呼出しが残った。セル読込みでは型選択、アドレス範囲、data容量、読込み・pushを確認。WindowsでもfetchLocal（460 bytes）とstoreLocal（567 bytes）の関数、および各2箇所のcallを確認した。Windows fetchの入口に型による間接jump、セル側に負値・範囲・data容量の検査がある。call site数は静的な箇所数であり、Windows実行中の回数や時間を測った値ではない。

使ったのは過去の採用版シンボル付き生成物。全tracked runtime sourceとbuild.zigが現在のrootとSHA一致した。snapshotのcore_words_test.zigだけには実験用ROTテストの差分がある。テストソースを含め全ファイル同一とは言わない。シンボル付き実行体はstrip済み本体とbyte同一ではなく、今回新たに両者の全関数同一性を証明していない。Linux SHAはaf54…、Windowsシンボル付き実行体/PDBとrootのSHAも測定JSONへ記録した。

## Linuxの対照計数

12ケースを各100/200反復で実行し、Callgrindの差を100で割った。非counted runOperationsの範囲を収集。全ケースで期待値とDEPTH=0、exit0を確認し、Callgrind実行の出力も一致した。Irは実行命令数で、時間やCPU cycleではない。各カーネルはLOOP・operand・算術・呼出し等を含み、異なる語の速度順位には使わない。

| 対照 | カーネルIr/反復 | 関数自身Ir/反復・実呼出し |
| --- | ---: | --- |
| literal 7加算 | 87 | local helperなし |
| cell local読込み | 129 | fetchLocal 28、1回 |
| cell local書込み | 135 | storeLocal 38、1回 |
| char local読込み | 123 | fetchLocal 22、1回 |
| double local読込み | 247 | fetchLocal 44、1回 |
| float local読込み | 129 | fetchLocal 26、1回 |
| XT local実行 | 353 | wordInLoop 1回、そこからexecuteWord 1回 |
| CONSTANT呼出し | 104 | wordInLoopなし |
| CREATEされたデータ語 | 150 | wordInLoopなし |
| 短いcolon呼出し | 111 | この対照はinline marker、frameを作る通常colon一般の値ではない |
| DEFER→colon | 217 | wordInLoopなし、VM内のcolon経路 |
| VALUE呼出し | 201 | wordInLoop 1回、そこからexecuteWord 1回 |

readCell/writeCellの安全検査自体が不要との結論は出していない。cell localとliteralの差42命令全体を、関数呼出しだけの負担や削減可能量と数えない。100/200差は一定setupを除く計数であり、一般的な定常性や誤差上限の証明ではない。

## 実例の型・call分類

前回の作業用計測版に、各compiled PCのlocal型とcall先の分類出力を追加した。通常6ケース＋資産生成3ケースで各2回、全PC回数・分類・stdoutが再現した。従来の基準版出力とも一致。これは最終dictionaryのkindによる分類で、任意のプログラムが実行中に語を変更/破棄した場合の履歴を復元する方法ではない。profile有効でcountedを通るため、通常実行の時間は表さない。

全9ケースのlocal_fetch/local_storeはcellで、他型・local_execute/local_addressはこの範囲の実行0。型の全般的不使用とは扱わない。通常6ケースのcallは主にconstant/variable/created。RENDERにはbuiltinへのcallも含む。call_colonはframeを作る呼出しとinline markerを区別できた。例えばklondike-logicはcolon-frame 279,724回、inline-marker 24,508回。pinball-bakeのcallにはvalue 9,464,534回、builtin 4,880,942回が含まれた。全callを同一のヘルパー呼出し数と扱う集計は不適切だった。

分類出力の対照として、上記12ケースをWindowsのroot/シンボル版/分類計測版で実行し、36実行の期待値・DEPTH0を確認した。cell/char/double/float fetch、XT execute、cell storeの分類数が各100回で一致。typed localの初期storeも分類された。CONSTANTは本体100回＋反復数constant1回、colon対照はinline-marker100回、DEFER/VALUEは各100回と区別できた。任意プログラムの全分類やnative内部呼出しを検証したものではない。

## 局所案と判断

1. **セル型localの経路分離を予備案へ。** ※仮説です。VMの既存分岐内でcellだけを先に処理すれば型分岐・helper呼出しを減らせる可能性がある。readCell/push、pop/writeCell等の順序と例外・登録通知は維持し、他型は既存fallbackを残す。readLocalを無検査にする案、local領域の安全性を仮定して範囲検査を外す案は選ばない。コード増・配置・countedの悪化は未確認。
2. **VALUEの呼出し経路分離を予備案へ。** ※仮説です。ソースの既存.value処理はreadCell→pushで、現行.callの早期データ語経路には含まれずwordInLoopへ進む。検査・失敗PC・容量・TO更新を維持した局所分離が可能か調べる価値がある。pinball-bakeの高頻度に限定した根拠であり、全ゲームや標準整数/LOOPへの効果は未確認。fvalue/two_valueまで一括拡張しない。

どちらも次の実装に確定せず、#848のVM/native内訳と併せて#849で比較する。既存の画像/SEE・保存形式・typed local・ADDR/TO/+TO・再帰/入れ子・再入・例外失敗順・counted/非counted・両OSとサイズの検証が必要。意味同等でも速度の基準未達なら採用しない。広範囲のinline強制や新命令を同時導入しない。

#847は上記の生成コード・計数・候補有無の判断を記録して完了する。観測用buildは10/10成功、unit suite・Claude Codeレビュー・性能比較は今回は未実施。本体は変更していない。

初回のLinux対照はNという既存名との重複警告により出力検査で停止した。専用constant名へ直して計数を実行した。source snapshot全同一の照合もテスト差分で停止し、runtimeとtestを区別して記録した。Windows対照の件数表示は初期11ケース時の33を追加後に残していたため、保存された12ケース/36実行へ報告値だけ訂正した。各初回失敗・報告訂正を製品の失敗や速度標本には数えない。

[ソース照合・両OS逆アセンブル・Linux全計数・分類結果・入力script](measurements/2026-11-16-local-call-investigation.json)。
