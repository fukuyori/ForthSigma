# セル型local読込みの単独実験計画（#849）

2026-11-16。**現在は第1試作・回帰・レビュー対応を完了し、Windows校正未達により採用保留。本体未反映。** [試作結果と採否](VM_CELL_LOCAL_FETCH_EXPERIMENT.md)を参照。以下は#847/#848を統合してセル型local_fetchを第一候補、VALUEを予備へ選んだ際の実験計画である。

## 選定理由

| 比較点 | セル型local_fetch | VALUE呼出し |
| --- | --- | --- |
| 実利用の根拠 | 通常6ケースと資産生成3ケースの全てで実行。観測したlocal_fetchは全てcell | pinball-bakeで9,464,534回。他の観測8ケースにはcall/valueなし |
| 生成コードの根拠 | LinuxはfetchLocalを1回/反復、セル経路の自己Ir28。Windowsにも関数callと型分岐が残る | Linux対照はwordInLoop→executeWordを1回/反復。ソースのcall fallbackと一致 |
| 単独変更の形 | local_fetchでcellだけreadCell→pushを直接実行、他型は旧helper | .callの.valueだけreadCell→pushへ分離する案 |
| 維持すべき状態 | locals_frame、address計算、readCell後pushの順序、失敗PC・frame、counted/非counted | 左記のmemory/stackに加え、word id、outer_pc・Runningのboundary引渡し、synonym/defer等との関係を照合する必要 |
| 変更範囲・検証費用 | fetchだけならstore/通知/TO等の実装を変えずに切り分け可能 | 既存の採用済みdata経路へ追加するため、過去の大きなコード配置変化や失敗PCの検証も必要 |
| 今回の判断 | **第一候補。読込みだけの単独試作へ** | 予備。第一候補の結果後に独立した着手判断 |

「より速くなる」と確認済みの順序ではなく、使用範囲と小規模な切り分けのしやすさで選んだ。#848のnative割合は時計追加で攪乱されているため、local案の改善率を逆算していない。cell-fetch対照129命令とliteral87命令の差42命令を丸ごと削減できるとも扱わない。標準整数演算/LOOPへの効果は未確認。

## 変更を一つに限定する

作業用コピーのsrc/forth.zigで既存local処理のlocal_fetch枝だけを次の意味へ変える。

```text
既存のlocals_frame検査、address計算、LocalKind読出しは維持
local_fetch:
    kind == cellなら push(readCell(address))
    それ以外は fetchLocal(address, kind)
```

readCellはアドレス範囲と読込み、pushはdata容量を検査する。その順を維持する。fetchLocal本体、local_store、local_address、local_execute、frameの確保/解放、typed localの形式、opcode、画像形式を変えない。XT:参照をcell扱いにせず、fvalue/two_value/VALUE経路、インライン指定、関数アライン、CPU設定を混ぜない。無検査ロードや安全検査の移動も行わない。

## 検証の順序と打切り

1. **基準と候補を凍結する。** rootのGit状態・runtime source・toolchain・target/CPU/最適化・実行体SHAを記録し、同じ入力からbaseline/candidateの別コピーを用意する。root実行体は上書きしない。両OSで通常fast/CPU baselineを固定。候補の差分が上記一箇所であることを確認する。
2. **生成コードと命令計数。** #847のcell-fetch対照を再利用し、Linux100/200反復差でhelper callと全体/自己命令を照合、両OSの対応するコードも確認する。char/double/float/XT/セルstoreの対照は変更外の確認に使う。cell-fetchに削減がなければ時間比較へ進まず打切り。メモリー容量・State/CallFrame・追加割当ては増やさず、両OS実行体各1%増以内を確認する。
3. **意味の同等性。** 既存のtyped local、ADDR/TO/+TO、再帰・入れ子・shadowing、CATCH/THROW/BYE・frame復元のテストを確認する。不足する境界だけbaseline/candidate双方へ同じテストを追加する。local frameなし、末端/範囲外address、data空き0/1、prefix保持、無効addressとdata満杯の重複、pending出力エラー、compiled失敗PC、keep_countingを含め、例外優先と失敗後状態を比較する。テスト用に不正operandを構成する場合は通常コンパイル入力と区別する。他型fallbackのfloat/data/return stackも確認する。
4. **構成別回帰と辞書互換。** 両OSのDebug/fastと既存の機能無効構成の回帰・CLIを実施する。Windowsのcross Linux親コマンドの失敗と生成ELFの実行成功は分けて記録。SEE・SAVE/LOAD-DICTIONARY双方向読込みでlocalを持つ定義の動作を確認する。SAVESYS/installerを作る計画ではない。
5. **対象ケースのCPU予備比較。** 次の定義で、起動/コンパイルを除いたREADY/DONE間の子process CPU時間を測る。Nの検査値は7*N。literal対照の生成コード計数は行うが、対象の効果へ混ぜない。

```forth
: BENCH-RUN { | x -- }
  7 TO x 0 BENCH-ITERATIONS 0 DO x + LOOP ;
```

baseline-only 100M pilotで約6秒のNを決め、その後は固定。OSごとにCPU0を固定し、A/A各5標本×2群、各armのwarmup1回を除外。両群の最小中央値5秒以上・最大δ2%以内を確認する。群内の先行順を交互にし、群2で反転。両OSで校正できた場合だけ、各7標本×2群の候補比較へ進む。全標本・時刻・順序・checksum・CPU照会を残す。校正失敗時は候補を測らず保留し、同一条件の無根拠な再試行をしない。

専用localケースは両群で2δを超えてCPU時間が減ることを、標準比較へ進む予備条件とする。これは新しい本体採用条件ではなく、10%という標準整数/LOOP目標をlocalへ適用した判定でもない。予備条件未達なら後続時間比較を打切り、未測定範囲を記録する。A/A差は信頼区間やA/B中のドリフト上限ではなく、2群も独立環境ではない。

6. **予備通過後の評価。** 通常8項目・CATCH9項目を両OSで既存条件に従って比較する。標準整数演算/LOOP各10%以上かつ2δ超、通常項目の悪化上限、CATCH各目標、実行体各1%以内、メモリー/意味の維持を変更しない。実例の資産生成3ケースと通常6ケースの出力も確認する。実例時間を比較するなら専用の事前計画と校正を用意し、#848の診断時間をbaselineへ流用しない。build/test/profileと計時は重ねない。
7. **レビューと採否。** 差分・境界テスト・生成コード・全標本をレビューへ渡して指摘を反映し、必要な再検証をする。標準目標未達なら「標準条件通過」と扱わず、local/実例のみの部分改善として別の採否判断に残す。安全性・サイズ・通常項目の上限を満たせない案は不採用。rootへ反映する場合も基準からの差分を再確認し、コミット/プッシュは別途の明示依頼に従う。

## 見送ったときの次手

VALUE案を自動試作しない。#847/#848の根拠を使い、VALUEの境界・失敗状態・scopeを再確認して独立計画を作る。両案が局所的に成立しない、又は効果根拠を得られない場合は、予備の隣接命令頻度調査へ進むかを判断する。命令融合・VM複製・全状態cache/JITへ自動的に拡張しない。

根拠：[local/call調査](VM_LOCAL_CALL_INVESTIGATION.md)、[native画像処理の観測](VM_BAKE_NATIVE_ATTRIBUTION.md)、[全候補比較](VM_CANDIDATE_REPRIORITIZATION.md)、[標準採用条件を適用した記録](VM_ALL_VALIDATION.md)。

## tqueへの反映

親121配下に単独実験#850を登録し、#849の選定へ依存させた。子タスクは#851（試作・生成コード・計数・サイズ）→#852（同等性・回帰・辞書）→#853（校正・時間比較）→#854（レビュー・採否）。すべて進捗auto。登録時点では未着手だったが、現在は第1試作の打切りと採用保留の記録まで完了した。全速度改善計画や従来の保留候補を完了・削除したものではない。

## 計時前の詳細化

試作・回帰後、最初のCPU pilotを走らせる前に次の順序と打切りを固定する。専用localケースはWindows→LinuxのA/Aを先に行い、最初の校正未達で後続の計時を止める。両OS通過時だけ両OSのlocal候補比較を行い、専用予備条件未達なら標準比較へ進まない。

標準34条件の順序はWindows整数演算→Windows LOOP→Linux整数演算→Linux LOOP→残るWindows通常/CATCH→残るLinux通常/CATCHとする。最初の校正未達、主目標10%かつ2δ超の未達、又は他項目の非通過で後続を打ち切る。2系列とも悪化上限超過と、片系列のみ超過は区別して記録し、後者も未解決として採用しない。この詳細化はCPU結果を見る前の事前計画であり、全34条件を測らなかった場合は残件を明示する。部分改善のみを見て未測定項目を通過扱いにはしない。
