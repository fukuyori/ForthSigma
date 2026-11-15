# PC分離実装のClaude Codeレビュー（2026-11-15）

Claude Codeによる静的レビュー。応答モデル: claude-fable-5-2。Read／Grep／Globのみ、25回のツール呼出し。コマンド実行・編集・再測定は依頼していない。依頼文・応答・対象ハッシュ・監査記録は`.work/claude-pc-implementation-review-20261115/`に保存した。

以下は受領した原文。レビュー後の対応は[対応記録](VM_PC_SCALAR_REVIEW_RESPONSE.md)を参照する。指摘箇所の行番号はレビュー時点のもの。

---

# PC・終端PC分離版 `runOperationsLoop` レビュー

## A. 結論

**現行実装に、基準版と意味が変わる箇所は見つかりませんでした。** 採用を覆す指摘はなく、指摘は保守性・テスト不足・文書の4件（中2、低2）です。

ただしこれはソースと差分の静的読解による結論で、ビルド・実行・測定はしていません。「同一」と言えるのは、下記の経路を1つずつ追って反例を作れなかったという意味です。

確認した経路と根拠：

- **PC の値域**：`max_code = 65535`（`src/core/memory_map.zig:25`）で `end_pc ≤ 65535`。命令取得時は `pc < end_pc` なので `pc + 1 ≤ 65535` となり、`src/forth.zig:1876` の u16 変換は基準の `running.pc += 1` と同じ条件でしか失敗しません。
- **分岐・ループ・LEAVE**：すべて基準と同じ u16 変換を通してから usize へ広げています（`src/forth.zig:2051-2098`）。
- **残存する `running.pc` / `running.end_pc` の読取り**：ループ内は `1965-1966` と `1994-1995` のみで、どちらも直前に `running` を代入した直後です。古い値を読む箇所はありません。
- **フレーム格納・呼出し・復帰**：`frames[]` への格納（`1962`、`1991`）と `traceRunning` への引渡しはすべて `frameWithLoopPCs` 経由です。ENTER/LEAVE イベントの順序も基準と同じです。
- **DOES>**：`does_code_start` は加算後の PC で基準と同値です（`2122`）。`defining_word` は PC と無関係のフィールドです。
- **locals**：`locals_frame` は `running` 本体に残り、境界で往復コピーされます。`returnToCaller` は実体化した側の値を読みます（`1680`）。
- **値渡し化した駆動側**：`runOperations` の `running` は、ループ失敗後に必ず `resumeCatch(&running)` で上書きされてから再投入されます（`1808`）。古い値を使う経路はありません。
- **defer / errdefer の順序**：内側ブロックの `defer`（PC 反映）が関数レベルの `errdefer`（`failed_pc` 記録、`1837-1839`）より先に走ります。成功用 0 の push 失敗は、復帰側（`1688`）も BYE 側（`1854`）も復元後の PC が記録されます。
- **CATCH / DEFER / SYNONYM / EXECUTE**：`enterCatch` と `wordInLoop` は、`running.*` を書き換えた後にエラーを返す経路がありません（`1618-1626`、`1649-1657`）。
- **再入**：`executeWord` 経由の内側ループは独自の局所変数を持ち、外側の状態には `frames` と `outer_pc` 以外で触れません。
- **StepLimit / Quit**：PC 加算後に返る点も、駆動側の扱いも基準と同じです。

破棄済み案A（値渡し版・境界コピー版）の問題は、現行実装には持ち込んでいません。

## B. 指摘

### B-1（中・保守性）局所 `running` の PC フィールドが境界間で古いまま残る

- **場所**：`src/forth.zig:1834-1836` と、11箇所の境界ブロック（`1845-1853` ほか）。
- **再現条件**：現行コードでは発生しません。将来ループ内に `running.pc` や `running.end_pc` を直接読む、あるいは `running` をそのまま `frames[]` やヘルパーへ渡すコードを足した場合です。
- **影響**：コンパイルは通り、古い PC が黙って使われます。復帰先や `failed_pc`、バックトレースが壊れます。
- **対応案**：ループ内の局所を PC を含まない形（`defining_word` と `locals_frame` だけ）にして、誤読を型で防ぐのが確実です。生成コードが変わるので再測定が要ります。最小限なら `1834` 付近に「`running.pc` / `end_pc` は境界以外で無効」と明記します。

### B-2（中・テスト）`failed_pc` を直接検証しているのは2経路だけ

- **場所**：`src/tests/catch_test.zig:176-218`（`failed_pc` の検証は `205`）。
- **内容**：検証されるのは復帰時の push 失敗と BYE 後の push 失敗です。「反映してから `failed_pc` を記録する」というコメントは9箇所の `wordInLoop` / `builtinInLoop` 境界にも付いていますが、そこを直接見るテストは確認できませんでした。
- **影響**：これらの境界から `defer` を外しても、ヘルパーが書換え後にエラーを返さない現状では結果が変わりません。つまりテストでは検出できず、将来ヘルパーが変わったときに初めて壊れます。
- **対応案**：D-2 のテスト追加。

### B-3（低・文書）計画文書に古い結論が残る

- **場所**：`docs/VM_PERFORMANCE_PLAN.md:174` と `:178`。
- **内容**：「通常VMの性能改善は達成していない」「速度改善の達成ではない」が、冒頭 `:3` の採用記載と並んでいます。`:17` に「以下は当時の計画」との断りはあるものの、末尾だけ読むと矛盾します。
- **関連**：`src/forth.zig:1822` のコメントが「Experiment:」のままです。
- **対応案**：`:174` と `:178` に「PC分離版の採用前の記述」と追記し、コードコメントを採用済みの表現へ直します。

### B-4（低・文書）最終測定の候補側のばらつきが本文にない

- **場所**：`docs/measurements/2026-11-15-vm-pc-scalars.json:2527-2539`、`docs/VM_PC_SCALAR_EXPERIMENT.md:29-40`。
- **内容**：整数演算・系列1の候補は中央値 738,396 µs に対し、7試行中2つが 900,327 と 822,485 です（範囲は中央値の約23%、基準は約0.9%）。計画 `:158` は各項目の最小・最大の記録を求めていますが、本文の表は中央値比だけです。
- **影響**：結論は変わりません。最悪の試行でも基準の最小値 1,126,315 µs より約20%速く、−34.61% は JSON から再計算して一致しました。
- **対応案**：本文に最小・最大か、この外れ値の存在を1行加えます。

### 文書の主張について（指摘なし、限界のみ）

- **Windows 速度**：`VM_PC_SCALAR_EXPERIMENT.md:3`、`:62`、`:124` で未測定と明記されており、過剰な主張はありません。計画の速度基準（`:151-154`）は OS を明示していないため、Linux のみでの採用は文言上は基準と矛盾しません。Windows で未達だった場合の扱いは決まっていません。
- **原因の主張**：命令数が増えたのに時間が減った点、`movd` 1命令を原因と断定しない点、A/A 校正が別ビルド間の配置差を含まない点は、いずれも文書自身が限定しています（`:61`、`:70`、`:89`）。
- **残る弱点**：約35%という値は、1組の実行体（基準1つ・候補1つ）の比較です。配置の偶然がどれだけ寄与しているかは分離されていません。

### 参考（回帰ではない、仮説）

fast ビルドで範囲外の分岐先を持つ命令を実行した場合、基準と現行で実際の挙動が異なる可能性があります。イメージ読込みは分岐先を範囲検査せず加算するだけです（`src/core/dictionary_image.zig:203-205`）。どちらも未定義動作で、安全検査付きビルドでは両方とも停止します。チェックサムを通る細工済みイメージが前提なので、PC分離の欠陥とは扱いません。fast ビルドの安全検査設定は未確認です。

## C. テスト・資料の限界

**現行テストが保証している範囲**（読んで確認したもの）：

| 対象 | テスト |
| --- | --- |
| 入れ子 CATCH と locals、DO ループの復元 | `catch_test.zig:127-139` |
| EXIT・DOES> 経由の CATCH 復帰 | `catch_test.zig:141-143` |
| SYNONYM・EXECUTE 経由の CATCH | `catch_test.zig:146-149` |
| BYE の巻戻し | `catch_test.zig:152-162` |
| 成功用 0 の容量不足（counted × BYE × 外側 CATCH の8通り、外側なしで `failed_pc` とバックトレース先頭） | `catch_test.zig:164-218` |
| ホスト出力からの再入（counted 両方） | `catch_test.zig:230-274` |
| QUIT・StepLimit の脱出 | `catch_test.zig:276-295` |
| CATCH 回復後の WATCH 位置 | `debug_words_test.zig:414-428` |
| CATCH 回復後の DBG 継続 | `debug_step_test.zig:44-56` |

**不足**：

- B-2 のとおり、ヘルパー境界での `failed_pc` は未検証です。
- コード領域の上端（`code_end = 65535`）で実行するテストは確認できませんでした。`p07a_test.zig:114` が `code_count` を上限近くに置くことだけ grep で見ています。
- DEFER 経由 CATCH の counted 側で、ENTER/LEAVE の順序を直接見る単体テストは確認していません（`catch_test.zig:72-125` は題名のみ確認）。
- `local_execute` 境界（`src/forth.zig:2167-2179`）を通るテストは探していません。
- DBG と WATCH のテストは文字列の有無と前後関係だけを見ており、表示される PC の値は固定していません。
- 文書の「基準照合44比較」「保存系16比較」は `.work` 内のスクリプトとログに依存し、私は中身を読んでいません。

**私が検証できなかった主張**：

- `src/forth.zig` と `forth-pc-scalars.zig` のバイト一致。grep で対象行の行番号と内容が一致することだけ確認しました。ハッシュは計算できません。
- 生成コードの記述（レジスター保持、`cmp rcx,r13`、バイト数・命令数）、Callgrind の計数、テスト件数、サイズ表。
- CATCH 9項目の率は JSON の `change_percent` と表が一致することを確認しました。元の試行値は読んでいません。
- 通常8項目のうち元の試行値まで読んだのは整数演算・系列1だけです。

## D. 必要な対応

コード修正が必須の欠陥はありません。優先順に：

1. **Windows の速度測定**（次工程）。通常8項目と CATCH 9項目を同じ手順で測り、未達だった場合に採用を維持するかどうかを先に決めておくことを勧めます。
2. **テスト追加**（B-2）。
   - 外側 CATCH なしで、DEFER 経由の組込み・`local_execute`・DOES> 付きワードの中でエラーを起こし、`failed_pc` とバックトレース先頭を検証する。
   - `code_end` が 65535 になるワードを実行し、復帰と分岐を確認する。
   - DEFER・SYNONYM 経由 CATCH の counted 側で、trace の ENTER/LEAVE の対応を検証する。
3. **古い PC フィールドの誤読防止**（B-1）。少なくともコメントで明記し、型で防ぐ変更をするなら再測定します。
4. **文書の整理**（B-3、B-4）。計画文書末尾の旧結論への注記、「Experiment:」コメントの更新、最小・最大の併記。
5. **任意**：約35%を PC 分離そのものの効果として一般化するなら、配置だけを変えた対照ビルドを Linux で1つ測ります。Windows の結果が独立した確認を兼ねます。

## E. 実際に読んだ範囲

読取りは約24回です。

**全文を読んだもの**

- `docs/VM_PC_SCALAR_EXPERIMENT.md`
- `.work/vm-pc-experiment/pc-scalars.patch`

**部分的に読んだもの**

- `src/forth.zig`：1440-2199 行（`executeWord`、`executeColon`、`CallFrame`、`enterCatch`、`builtinInLoop`、`wordInLoop`、`resumeCatch`、`returnToCaller`、`recordBacktrace`、`traceRunning`、`executeOperations`、`runOperations`、`frameWithLoopPCs`、`runOperationsLoop` 全体）。ほかは grep で `failed_pc`、`outer_pc`、`frames`、`max_code` の使用箇所。
- `src/tests/catch_test.zig`：120-299 行とテスト名一覧。
- `src/tests/debug_words_test.zig`：410-431 行とテスト名一覧。
- `src/tests/debug_step_test.zig`：40-59 行とテスト名一覧。
- `src/core/words_system.zig`：`CatchContext`（90-134）、BYE、旧 CATCH 本体付近（grep の前後行）。
- `src/core/dictionary_image.zig`：168-217 行。
- `docs/VM_PERFORMANCE_PLAN.md`：140-178 行と冒頭の grep 一致行。
- `docs/measurements/2026-11-15-vm-pc-scalars.json`：2465-2574 行、10640-10829 行、`change_percent` などのキーの grep。
- `.work/vm-pc-experiment/forth-pc-scalars.zig`：grep による対象行の照合のみ。

**未読**

- `.work/vm-pc-experiment/forth-baseline.zig`（基準側の内容は差分の削除行から把握）。
- `docs/VM_CATCH_COST_AND_BOUNDARIES.md`、案A関連の文書、その他の測定 JSON。
- `src/core/words_debug.zig`（`step`、`checkWatches`、`stepEnter` / `stepLeave`）、`words_loops.zig`、`inline_calls.zig`、`profiler.zig`。
- `.work` 内のアセンブリ、ログ、検証・測定スクリプト。
- `catch_test.zig` の 1-119 行と 300 行以降、debug 系テストの上記以外、`debug_log_test.zig` と `p07a_test.zig` の本文。
