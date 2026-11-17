# セル型local読込みの単独試作結果（#850）

2026-11-16 後続結果：[CPU2でのlocal再評価・VALUE試作・隣接先読みの評価](VM_THREE_CANDIDATES_RESULTS.md)を完了した。専用ケースの短縮と標準目標未達を記録し、本体への追加採用はない。以下は本資料の調査・試作時点の記録であり、後続の比較未実施という現在状態を表さない。

2026-11-16。**第1試作は採用保留。セル読込みの命令数は減ったが、WindowsのA/A校正差5.168%が上限2%を超えたため、候補版のCPU時間比較は行わなかった。速度改善・悪化はいずれも未判定で、本体は採用済み版を維持する。** 以下に試作・検証・レビュー対応と未測定範囲を記録する。

## 変更と生成物（#851）

作業用コピーだけでsrc/forth.zigのlocal_fetch枝を変更した。

```zig
.local_fetch => if (kind == .cell) try self.push(try self.readCell(address)) else try self.fetchLocal(address, kind),
```

locals_frameの検査、address/kindの計算、readCell→pushの意味と例外順、他型fallback、local_store、VALUE、opcode/画像形式は変更していない。State/CallFrameの定義・容量・割当て方針にも変更はない。root source・build.zig・配布設定は未変更。

rootのtracked入力からbaseline/candidateを別コピーへ凍結し、fast/baseline CPU/通常機能で両OSをビルド。baselineのstrip版SHAはWindows379d…、Linux bdb6…を再現した。両OSの候補symbols版も別に生成した。単独差分と入力SHA・全コマンドをJSONへ保存した。

| 対象 | baseline | candidate | サイズ差 |
| --- | ---: | ---: | ---: |
| Windows GNU strip | 1,809,408 bytes | 1,809,408 bytes | 0% |
| Linux musl strip | 1,891,456 bytes | 1,891,648 bytes | +0.01015% |

Linux symbols版のCallgrind100/200反復差で、セル読込みカーネルはIr129→108、Dr36→30、Dw12→10。baseline計数は#847の同じ採用runtimeのsymbols版結果を再利用し、現在のstrip baselineを新たにprofileした値ではない。fetchLocalへの呼出しが反復ごと1回から0になった。命令数・参照数でありCPU時間ではない。charはIr123→127、double247→250、float129→132と追加分岐の増加がある。セルstore、XT実行、CONSTANT/CREATE/colon/DEFER/VALUE等の他対照は今回のIrが同じだった。12対照でbaseline/candidateの期待値・DEPTH0・exit0を確認した。

WindowsはPDBで両loop実体とfallback helperを識別し、cell用の分岐先を逆アセンブルで確認。Linuxも両loop実体の分岐選択とcell本体を記録した。確認したcell経路では範囲検査・data容量検査の後にロード/ストアが並ぶ。これは生成命令の配置についての観測で、CPUの投機実行を否定する証明ではない。symbols版・test版・凍結strip版をbyte同一とは扱わない。

## 回帰と辞書・実例（#852）

初回は両コピーへ同じ境界テスト2件を追加し、48条件のcell address/空き容量/counting/pending出力と、frameなしの2条件を確認した。無効addressと満杯の重複ではInvalidAddressが優先し、pending出力エラーはこのlocal経路では消費されない。prefix・return/float・frame/call/catch・locals_top・compiled失敗PCを検査した。不正operandで作る条件は通常入力による操作と区別する。

両側Windows Debugと、候補のWindows fast/no-debug/no-float/minimal、Linux Debug/fastの回帰が通過。Windows通常の初回build testは21/21ステップ成功、1,072成功/10skip（追加2testを含む、cached host等を含むbuild結果）。LinuxのWindows親コマンドはELFとCLIを実行できずexit1のまま保存し、生成されたcore/host ELF2本をWSLで直接実行してexit0、CLI9条件×Debug/fastの18件を補完した。親コマンドを成功と書き換えていない。

追加の出力確認は通常8カーネル×2実行体×2OSの32実行、Windowsの通常6実例＋資産生成3実例×2実行体の18実行で一致。さらに資産生成3実例×2実行体の6実行で、RENDER後の全framebuffer2状態のhashを基準と比較し一致した。hash衝突の不存在や全資産/全状態の同一性を保証しない。時間比較ではない。各OSでlocal cell/double/XTを含む定義をbaseline/candidateからSAVEし、両者で相互LOAD-DICTIONARYする4SAVE/8LOAD、SEE出力の一致も確認した。画像SHAの同一性や他OS間互換を要求/実証したものではない。SAVESYS/installerは作っていない。

レビュー後の補強は次節と対応記録へ記載する。凍結CPU計測が終わった後にテストだけを補い、runtime差分・計時実行体は変更していない。

## CPU校正と採否（#853）

[計画](VM_CELL_LOCAL_FETCH_PLAN.md)を計時前に詳細化し、最初の校正未達で後続を止めること、両OSの専用校正通過時だけ候補比較へ進むこと、標準34条件にも主目標/悪化上限の打切りを置くことを凍結した。結果を見てしきい値や計時scriptを変更していない。

通常の非counted実行。CPU0、子processのREADY/DONE間CPU時間で起動/コンパイルを除き、境界I/Oを含む。baseline-onlyの100M pilotから**N=1,238,709,678**を固定し、検査値7*N=8,670,967,746を独立計算。A/Aは各arm5標本×2群、各arm/groupのwarmup1回を除外、先行順交互・群2で反転。全標本を保存した。build/test/profileと計時を重ねていない。

| 群 | A1中央値 | A2中央値 | A/A δ |
| --- | ---: | ---: | ---: |
| 1 | 6,359.375 ms | 6,046.875 ms | 5.167959% |
| 2 | 6,312.500 ms | 6,437.500 ms | 1.980198% |

最小中央値6,046.875msは5秒条件を通過したが、最大δ5.167959%は2%条件未達。予定どおり再試行せずに停止した。計20測定標本・4warmup・pilot1を保持。Windows CPU照会のkernel+user差から全24区間を再集計し、保存CPU値と中央値/δの一致を確認した。第1群の符号付きA2/A1変化-4.914005%と、絶対差/小さい中央値で定義するδ5.167959%を混同しない。

**候補のAB、Linuxの校正/AB、標準34条件、実例の時間比較は未実施。** 候補を実行していないという意味ではなく、回帰・出力・命令計数は実施したがCPU比較には進まなかった。校正差の原因は特定していない。δは信頼区間や後続計時の揺らぎ上限ではなく、群は独立環境ではない。事後A/A、ホスト負荷の記録もない。

## レビューと最終状態（#854）

[初回Claude Codeレビュー](VM_CELL_LOCAL_FETCH_CLAUDE_REVIEW.md)は安全性ブロッカーなし。他型fallbackの境界不足等の指摘に従い、typed operandのchar/XT/double/float、double空き1でlowだけ積んで失敗する既存挙動、float/data容量と例外優先、未使用slot、入れ子CATCH後の復帰を補強した。追補9構成を確認し、[追補レビュー](VM_CELL_LOCAL_FETCH_CLAUDE_FOLLOWUP.md)で初回のMedium1件・Low4件は対応済み、残るブロッカーなしとの結果を得た。検証の範囲は[対応記録](VM_CELL_LOCAL_FETCH_REVIEW_RESPONSE.md)を参照。

採否は**保留**。命令削減・サイズ条件・回帰結果だけで速度改善を認定せず、本体へ反映しない。#850はこの第1試作の検証と採否記録として完了し、全速度改善計画の完了とはしない。同一条件の無根拠な再計時や、VALUE案の自動試作は行わない。再開には計時安定性の新たな根拠等が必要で、VALUE案へ進む場合も独立した着手判断を行う。

[ビルド・生成コード・境界検証・全回帰・出力と辞書記録](measurements/2026-11-16-cell-local-fetch-validation.json)、[凍結入力・全CPU標本・再集計](measurements/2026-11-16-cell-local-fetch-performance.json)、[Linux CLI18件](measurements/2026-11-16-cell-local-fetch-linux-cli.json)。コミット/プッシュは今回行っていない。
