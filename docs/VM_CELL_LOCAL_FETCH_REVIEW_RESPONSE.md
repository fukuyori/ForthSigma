# セル型local読込み試作のレビュー対応（#854）

2026-11-16。[初回レビュー](VM_CELL_LOCAL_FETCH_CLAUDE_REVIEW.md)と[追補レビュー](VM_CELL_LOCAL_FETCH_CLAUDE_FOLLOWUP.md)を保存した。追補の結論は「残るブロッカーなし」、初回Medium1件・Low4件は対応済み。レビューはRead/Grep/Globのみで行い、編集・コマンド実行は依頼していない。実行結果は別途こちらで確認した。

| 指摘 | 対応・検証 |
| --- | --- |
| Medium-1：他型fallbackの境界不足 | char/XT/double/floatのkindとoffsetを明示する288条件を追加。charの末端1byte/7byte成功とcell失敗の違い、double空き1でlowだけ積む既存挙動、float満杯/無効addressの優先、data/float/return・frame・pending・失敗PCを確認。no-floatではchar/XT/doubleの216条件 |
| Low-1：Linuxの命令順が未保存 | 両OS・両loop実体のcell分岐と本体を保存。後続の共有分岐先も抜粋へ追記。symbols版についての観測で、strip版との命令列同一性は証明していない |
| Low-2：test/symbolsと凍結strip版の区別 | 両OSの凍結baseline/candidate計4実行で、通常入力から入れ子CATCH内のlocal読込みを満杯にし、-3・DEPTH0・後続local結果7・DEPTH0を確認。合成した無効addressはunit testに限定 |
| Low-3：baselineの構成が少ない | 補強後にbaseline/candidate双方のWindows Debug/fastとLinux fastを実行。candidateのno-float/no-debug/minimalも再実行。Linux Debugの補強後テストは未再実行と明示 |
| Low-4：未使用slot・入れ子CATCH | cell失敗時の未使用slotを検査。typed fallbackでもprefixと残余slotを確認。通常入力の入れ子CATCHでlocal読込みを失敗させ、locals/frame/call/catch復元と後続処理を検証 |

追加した4test宣言は、cell48条件・frameなし2条件・typed288条件・入れ子CATCH2条件を含む（feature/countingによる独立性の限界あり）。no-debugではcounted指定の反復も同じ非counted経路となり、failed_pc検査は行わない。

追補9構成はすべて所定の検証を通過した。Windowsは成功したbuild testにcached host等を含み、要約のテスト合計が構成間で異なる。例えばWindows fastはbaseline1,074/1,084、candidate1,015/1,020と表示されるが、candidateのhost64件がcachedで集計外となるため。coreは双方1,015成功/5skip。Linux fastは両側のcore ELFが1,015成功/5skip、host ELFが63成功/1skip、exit0。Linux親コマンドのexit1は保持した。Windowsの成功ログが要約のみの箇所では、各新testの非skipをソースと宣言数から判断しており、全件の名前付きログがあるとは扱わない。

補強は初回CPU計時完了後に行った。runtimeの差分・凍結6実行体・元のroot入力が変わっていないことをSHAで確認した。計時完了UTCと最初の追補logの作成UTCも測定JSONへ保存したが、ファイル時刻は独立した実行履歴/ホスト負荷の証明ではない。追補review後の追加は共有後続コードの生抜粋と記録の整理で、この追加抜粋自体の再レビューはしていない。

初回レビューの「投機ロードなし」は、生成命令で検査より前に明示的ロードがない、という範囲に限定して読む。ハードウェアの投機実行がないことを静的コードから証明したものではない。doubleのlen-8（第1セルのみ有効）は任意追加の注記として残し、helper不変・他境界/部分pushの検証で今回の範囲を閉じた。

追補レビューは校正未達と候補比較なしの記録も確認した。A/A原因は未特定で、レビュー通過を速度改善の証明にしない。**採否は保留、本体未反映。** [試作結果](VM_CELL_LOCAL_FETCH_EXPERIMENT.md)、[全検証記録](measurements/2026-11-16-cell-local-fetch-validation.json)、[全CPU記録](measurements/2026-11-16-cell-local-fetch-performance.json)。
