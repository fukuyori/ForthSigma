レモン、静的に読んだ結果を報告します（Read/Grep/Glob のみで、テストは実行していないため結果は未確認です）。

## 結論
今回の修正範囲に、高・中の具体的な欠陥は見つかりませんでした。

## 入れ子で外側の予算が尽き、中断が保留されている場合
外側の end で -28 になります。コード上の流れは次のとおりです。

1. 内側の entry は、外側の stop による `StepLimit` を受けます。`own_limit` は false です。
2. 内側の `endExecution` は `endInput()` だけを呼びます（`src/host_wait.zig:285`）。`input_depth` がまだ 0 ではないので 298行で戻り、中断印は残ります。そのまま `StepLimit` を返します（`execution_control.zig:92`）。
3. 外側では `own_limit` が true になります。深さ 0 の `endInput` が 302行で印を swap して `UserInterrupt` を返します。92行は `own_limit` なので飛ばされ、93行で `UserInterrupt` を返します。

## H1（Ctrl+C の位置のずれ）
- `ExecutionReplay.read` は呼ばれるたびに `last_three` を false にし、byte packet のときだけ `value == 3` を設定しています（`src/main.zig:3264-3268`）。`.restart` やマウスの packet では false のままです。
- `src/core/standard_event.zig` の `read` を確認しました。3 を読んだ同じ呼出しの中で、`read_fn` を挟まずに 136行（バッファ先頭の 3）へ進むのは、paste が解除されたときだけです。paste の解除は、終了マーカーが完成した時点の parse で起きます。マーカーの後ろのバイトを先に読むことはないので、この経路で区別を誤る場合は見つかりませんでした。
- 計算式（3311行）が負に回り込むこともありません。3 がもとのバッファにある場合は `consumed < initial` になり、印を付けずに戻ります。
- origin は、`byte_origins` によってバイト単位で対応しています。
- 作業領域は static の `undefined` になり、`@splat` による初期化はなくなりました。

## H2・debug=false での除外
- 入れ子の end は印を消費しなくなりました。`host_wait.zig:512` のテストで確認されています。
- `enabled_definitions` を `group` が使い、`definitions` はそのまま残っています。

## 低（参考）
- `enabled_definitions` は「EXEC-LIMITED が最後の要素である」ことを前提に `len - 1` で切っています。comptime の assert がないので、順序が変わると別の語が除外されます。
- この経路を通しで確かめるテストがありません。`execution_control_test.zig` の Fake は、入れ子でも end のたびに中断を返します。そのため「外側の予算が尽き、内側は印を残し、外側が -28」の組合せは、今の Fake では表せません。
- 入れ子で内側が自分の予算で止まり（自分の -280）、同時に中断が保留されている場合、内側は -280 を返します。中断は、外側の次の poll（最大 1023 op 後）か外側の end で届きます。中断は失われませんが、届くのが遅れます。