# Antigravity（agy）によるVM改善計画レビュー

2026-11-15、agy CLI 1.5.9で実施。以下はレビュー報告の本文を保存したもので、リンクのみ閲覧用に変換した。未確認の仮説や採用しない提言も含む。[指摘の採否と反映](VM_PERFORMANCE_REVIEW.md#antigravityagyレビューの採否)を参照する。モデル名はCLIの結果に明示されていない。

実際のツール履歴はread_file 14回、13ファイル。原文の「計10ファイル」とは異なるため、実履歴を採用する。コマンド・編集・再測定はレビューエージェントへ依頼せず、ツール履歴にもない。

---

# ForthSigma VM実行速度改善計画 設計レビュー報告

[VM_PERFORMANCE_PLAN.md](VM_PERFORMANCE_PLAN.md)、[VM_PERFORMANCE_REVIEW.md](VM_PERFORMANCE_REVIEW.md)、[GFORTH_VM_REFERENCE.md](GFORTH_VM_REFERENCE.md) および関連するSigma実装・Gforth参照ソース（固定版 `c479e1eec66dd57a2441c3020177267ba70d3bdc`）を照合し、設計レビューを実施しました。

全体として、現行の改訂計画は「測定の揺らぎと生成コードの分離確認を先行させる点」「`Running` の外側書戻しを不要と整理した点」「Gforthの機械語ディスパッチや生スタック構造を安易に持ち込まない点」において非常に堅実に構成されています。その上で、実装着手前に詰めておくべき境界条件と検証設計の不足点を以下に報告します。

---

## 1. 優先度別の指摘事項（文書位置・実装根拠つき）

### 【優先度：高】P1. 案Aの「追加実験（一時Runningへの値渡し）」における `returnToCaller` の成功時スタック溢れと状態復元の順序
- **対象文書位置**: [VM_PERFORMANCE_PLAN.md](VM_PERFORMANCE_PLAN.md#L74-L76)（案A：局所変更の実験設計）
- **実装根拠**: [src/forth.zig](../src/forth.zig#L1678-L1691)（`returnToCaller`）、[src/forth.zig](../src/forth.zig#L1808-L1815)（`runOperations` の例外捕捉ループ）、[src/tests/catch_test.zig](../src/tests/catch_test.zig#L163-L173)
- **内容**:
  計画74行目では、追加実験として「ヘルパーが必要な境界だけ一時Runningへ値を渡し、通常復帰・エラーの両方で必要な状態をループ内へ反映する案」が記載されています。
  ここで [src/forth.zig](../src/forth.zig#L1678-L1691) の `returnToCaller` に注目すると、CATCH対象のワードが正常終了した際、以下の順で処理が行われます：
  1. `self.frame_depth -= 1; running.* = self.frames[self.frame_depth];`（CATCH呼出し元の `Running` を復元）
  2. `self.catch_depth -= 1;`（このCATCH継続を消費）
  3. `try self.push(0);`（成功コード `0` をデータスタックに積む）

  もしステップ3の `try self.push(0)` が `error.StackOverflow` で失敗した場合（[catch_test.zig](../src/tests/catch_test.zig#L163-L173) の `"a successful CATCH without room for zero throws to its caller"` のケース）、このCATCH自体は既にステップ2で解除済みであり、エラーは**外側のCATCHまたはトップレベル**へ伝播します。
  - 外側に別のCATCHがある場合は `resumeCatch` が外側のフレームで上書きします。
  - しかし**外側にCATCHがない場合**、ループを抜けて [src/forth.zig](../src/forth.zig#L1779) の `recordBacktrace(self.failed_pc, loop_frames, entry_call_depth)` が呼ばれます。このとき `self.frame_depth` は既にデクリメントされているため、`failed_pc` がステップ1で復元された「CATCH呼出し元の `running.pc`」を指していないと、CATCH呼出し元のフレームがバックトレースから1段欠落します。
  - したがって、`returnToCaller` はインライン展開のままローカル `running` を直接更新させるか、一時コピーを使うなら `errdefer` で `failed_pc` を記録する**前**に必ず一時 `Running` をローカル `running` へ書き戻す順序を厳守する必要があります（計画76行目に順序への言及はありますが、この「CATCH成功時の `push(0)` 失敗＋外側CATCHなし時のバックトレース整合性」が具体的な必須条件になります）。

### 【優先度：中】P2. 案Aで `runOperationsLoop` が `Running` を値受け取りする場合の、CATCH連続捕捉・BYE巻き戻し時の引数渡し経路
- **対象文書位置**: [VM_PERFORMANCE_PLAN.md](VM_PERFORMANCE_PLAN.md#L66-L70)
- **実装根拠**: [src/forth.zig](../src/forth.zig#L1800-L1819)（`runOperations`）、[src/forth.zig](../src/forth.zig#L1829-L1834)（`runOperationsLoop` 内の `self.halted` 分岐）
- **内容**:
  計画66〜70行目にある通り、通常終了・`QUIT`・`StepLimit` では外側の `running` を再利用せず、例外捕捉時は外側の `resumeCatch(&running)` が `self.frames[caught.frame_depth]` から全フィールド（`pc`, `end_pc`, `defining_word`, `locals_frame`）を復元して次の `runOperationsLoop` へ渡すため、「通常の退出時書戻しは不要」という判断は**実装と完全に一致しており正確**です。
  実装時に1点だけ注意が必要なのは、以下の2経路の接続です：
  1. `runOperations` 側の捕捉ループ（[forth.zig](../src/forth.zig#L1808-L1816)）では、`resumeCatch(&outer_running)` で更新した `outer_running`（および `checkWatches(self, outer_running.pc -| 1)`）を、次のイテレーションの `runOperationsLoop(counted, outer_running, ...)` へ値渡しで引き継ぐこと。
  2. `runOperationsLoop` 内部の `if (self.halted)`（[forth.zig](../src/forth.zig#L1829-L1834)）で呼ばれる `resumeCatch(&local_running)` で `try self.push(0)` が失敗した場合、直後に外側の `catch |err|` へ出て外側のCATCH（あれば）に捕捉されるため、内側でローカルの `local_running` を更新するだけで問題なく繋がりますが、`resumeCatch` 自体は外側（`&outer_running`）と内側（`&local_running`）の双方から `*Running` を受け取れるシグネチャのまま維持するのが最小変更になります。

### 【優先度：中】P3. 案A0（`halted` 検査移動）における「例外フォーマッター内での `halted` 一時退避・復元」と「CATCH内BYEの非停止セマンティクス」
- **対象文書位置**: [VM_PERFORMANCE_PLAN.md](VM_PERFORMANCE_PLAN.md#L80-L85)（案A0：halted検査の配置）
- **実装根拠**: [src/forth.zig](../src/forth.zig#L1829-L1834)、[src/tests/catch_test.zig](../src/tests/catch_test.zig#L151-L161)
- **内容**:
  計画83〜84行目で、`f1140c7` 直前にも `while (!self.halted)` が存在したことを踏まえ、A0を条件付きの別実験に分離した判断は適切です。
  もしA0を検討する場合、単に「`BYE` 等で `self.halted = true` になった瞬間にループを抜ける」と変えてしまうと、既存のCATCH＋BYEの挙動と食い違う点があります。
  現行の [src/forth.zig](../src/forth.zig#L1829-L1834) では、`self.halted` が真のとき：
  - `self.catch_depth != entry_catches` であれば、**即座にreturnせず**、`_ = self.resumeCatch(running); try self.push(0); continue;` を実行します。
  - そして次のループ先頭で再び `if (self.halted)` に入り、`catch_depth == entry_catches` になるまで1段ずつCATCH継続を剥がして各段で `0` をプッシュし（もし途中でスタックが溢れれば `-3` を外側のCATCHへ投げ）、最後にreturnします（[catch_test.zig](../src/tests/catch_test.zig#L151-L161)）。
  したがって、A0でループ先頭から `self.halted` 検査を移動する場合、移動先の各境界（`BYE`、動的呼出し、ホストコールバック復帰等）は単なる `return` ではなく、この「`entry_catches` までCATCH継続を順次 `resumeCatch` + `push(0)` で巻き戻す処理」へ合流する必要があります。この点からも、A0は生成コード上で明確なボトルネック証拠が出ない限り見送る（または後回しにする）という現行計画の優先順位が妥当です。

### 【優先度：低】P4. 案Bの条件整理と、そもそも `f1140c7` で整数演算・LOOPが遅くなった原因仮説（H1/H2）の切り分け
- **対象文書位置**: [VM_PERFORMANCE_PLAN.md](VM_PERFORMANCE_PLAN.md#L38-L42), [L86-L100](VM_PERFORMANCE_PLAN.md#L86-L100)
- **実装根拠**: [src/forth.zig](../src/forth.zig#L1822-L2072)、[docs/measurements/2026-11-15-vm-diagnosis.json](measurements/2026-11-15-vm-diagnosis.json#L67-L731)
- **内容**:
  計画86〜100行目における案Bの設計制約（偽の `RuntimeError` を使わない、`ran` の扱い、deferred CATCHの `call_depth` 補正、`handed` と `backtrace_suppression`、`entry_frames` / `entry_catches` によるホスト再入境界の保護）は、現行の `enterCatch` / `wordInLoop` / `runOperations` の実装構造を正確に網羅しています。
  一点補足すると、測定データ（[2026-11-15-vm-diagnosis.json](measurements/2026-11-15-vm-diagnosis.json)）では、`f1140c7` の前後で「整数演算 (+59.0%)」「LOOP (+37.9%)」が悪化する一方、「定数・変数 (-15.7%)」は**高速化**し、「スタック操作 (-1.3%)」「浮動小数点 (-2.7%)」はほぼ不変です。
  もし `running: *Running` のポインター間接参照（H1）だけが主因であれば、すべての命令で毎ディスパッチ `running.pc` を読み書きするため、スタック操作や定数・変数も同様に遅くなるはずです。科目によって明暗が分かれていることは、H2（`runOperations` と `runOperationsLoop` の関数分割、`builtinInLoop` / `wordInLoop` の導入、あるいは巨大 `switch` ループ内のレジスター割り当て・基本ブロック配置・ジャンプテーブル生成の変化）の寄与が大きい可能性を示唆しています。

---

## 2. Gforth参照の妥当性と、Sigmaへ参考にする点・移植してはいけない点の整理

[GFORTH_VM_REFERENCE.md](GFORTH_VM_REFERENCE.md) および [.work/gforth-vm-reference/](https://github.com/forthy42/gforth/tree/c479e1eec66dd57a2441c3020177267ba70d3bdc) の4ファイル（`engine.c`, `threaded.h`, `prim-500-620.txt`, `except.fs`）を照合しました。

### 理解の妥当性
文書内のGforth実装に対する理解は**正確**であり、GPLコードの不転用方針およびアーキテクチャ差の切り分けも適切です。

### Gforthから設計原理として参考にできる点
1. **通常ディスパッチのホット状態と、例外境界で保存するコールド状態の明確な分離**:
   - Gforthの [`prim-500-620.txt`](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/prim#L564-L585) では、通常命令は局所の `ip`, `sp`, `rp`, `fp`, `lp` だけを動かし、例外境界である `(try)` / `uncatch` / `fast-throw` だけが `SPs->handler` を介して6セルの退避フレーム（`a_recovery`, `a_sp`, `c_op`, `f_fp`, `c_lp`, `a_oldhandler`）を保存・復元します。
   - Sigmaにおいても、通常の算術命令や `LOOP` が「CATCH継続の存在」を意識しないようにし、状態遷移（`enterCatch`, `resumeCatch`, および `returnToCaller` の `catch_depth != 0` 分岐）だけにコストを局所化する設計指針はそのまま有効です。
2. **コールドパスの分離によるメインループのレジスター圧軽減**:
   - Gforthはプリミティブと高水準ワード（[`except.fs`](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/except.fs#L79-L85) の `catch` 定義）を分離し、各プリミティブのコード片を小さく保っています。Sigmaの `runOperationsLoop` のような単一 `switch` ループでは、ループ内の1箇所でも複雑なヘルパー呼出しや多数の変数生存区間があると、LLVMのレジスターアロケータがループ全体の `self` や `running`（または `pc`）をスタックへスピルさせることがあるため、コールドパスを `noinline`（`@call(.never_inline, ...)` または `@branchHint(.cold)`）で外へ出す設計が参考になります。

### Sigmaへ移植してはいけない方式・状態配置（計画の区別は適切）
1. **リターンスタック（`rp`）への例外フレーム直接埋め込み**:
   - Gforthは `(try)` でリターンスタック上に `rp-6` のフレームを直接積みますが、Sigmaはデータスタック・リターンスタック・ループスタック・呼出し枠（`frames`）・CATCH枠（`catches`）を型付きスライスで分離し、深さ検査とイメージ保存の安全性を保っています。これをGforth流の生スタック混在に変えてはいけません。
2. **`sp` / `fp` / `TOS` の無条件レジスターキャッシュ（[`engine.c`](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/engine/engine.c#L530-L561), [L646-L658](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/engine/engine.c#L646-L658)）**:
   - Sigmaでは各プリミティブ（`word_modules[...].execute(self, hot)`）が `*State` 経由で `self.push` / `self.pop` を行い、途中で容量検査やエラー送出、ホストコールバック再入を行います。`sp` や `TOS` をローカルキャッシュする案（計画の案C）を見送ったのは極めて妥当です。
3. **Computed Goto（[`threaded.h`](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/engine/threaded.h#L109-L126) の `goto *real_ca`）やダイレクトスレッディング**:
   - Sigmaの `Op` 配列・`SEE`・イメージ再配置・デバッグ機構と根本から衝突するため、対象外とする判断は正しいです。

---

## 3. 仮説としての改善案・第0段階での追加確認ポイント

現在の第0段階〜案Aの計画を補強するため、以下の視点を第0段階の逆アセンブル調査および独立実験の仮説として追加することを提案します。

1. **仮説H1a（`pc` / `end_pc` のスカラ分解とローカル保持）**:
   - `Running`（`CallFrame`）は `pc: u16`, `end_pc: u16`, `defining_word: ?u16`, `locals_frame: Cell`（計16バイト）の構造体です。
   - 案Aで `var running: Running` をローカル変数にしても、`builtinInLoop` や `wordInLoop` へ `&running` のアドレスを渡した時点で、LLVMのSROA（Scalar Replacement of Aggregates）が阻害され、`running` 全体がホストスタックフレーム上のメモリーに配置されて `running.pc += 1` がメモリー読み書きのまま残る可能性があります（計画72行目の懸念通り）。
   - 第0段階の逆アセンブルでこれが確認された場合、計画74行目の「一時Runningへの値渡し」または「呼出し・復帰・CATCH・ローカル変数の分岐以外ではアドレスを取らせない」ことで、`running.pc` と `running.end_pc` がCPUレジスターに載るかを1ステップで確認できます。
2. **仮説H2a（`builtinInLoop` / `wordInLoop` のインライン展開によるループ肥大化の抑制）**:
   - `f1140c7` で追加された `builtinInLoop`（2箇所から呼出し）と `wordInLoop`（5箇所から呼出し）は `inline` 指定がありませんが、`ReleaseFast`（`-Doptimize=fast`）ではコンパイラー判断で `runOperationsLoop` 内にインライン展開されている可能性があります。
   - 特に `wordInLoop` とその中の `enterCatch` は `CatchContext.init(self)`（多数の `State` フィールド読取り）を含んでおり、これが `runOperationsLoop` の5箇所に展開されると、ホットな算術・ループ命令の周辺でレジスター圧やコード配置が悪化する原因になり得ます。
   - もし第0段階の逆アセンブルで `enterCatch` や `wordInLoop` が `runOperationsLoop` 内に展開されていた場合、これらに `@call(.never_inline, ...)`（またはコールドヒント）を付けるだけで、案Bのような複雑なループ退出プロトコルを導入せずにH2の悪化分を解消できる可能性があります。

---

## 4. 検証項目と採否基準への提言

### 追加・明確化すべき検証ケース
計画114行目で既存テスト（`catch_test.zig`, `p09a_test.zig`）との重複を避けて追加候補が挙げられていますが、特に以下の2点は案Aの境界条件として有効です：
1. **「CATCH成功時の `0` プッシュでスタック溢れ（`-3`）」かつ「外側にCATCHがない場合」のバックトレース検証**:
   - 前述のP1の通り、`catch_test.zig:163` は外側に `OUTER` の `CATCH` があるケースを検証しています。これに加え、外側に `CATCH` がない状態で `INNER` の `CATCH` が成功時 `push(0)` で `-3`（StackOverflow）になった際、`report` が出力する `BACKTRACE:` に `INNER` の呼出し位置が正しく記録されるかを確認するテスト。
2. **例外フォーマッター（`EXCEPTIONS`）実行中に `BYE` または再 `THROW` が起きた場合の `halted` / `backtrace_suppression` 状態検証**:
   - `p09a_test.zig:170, 209` でフォーマッター内の `THROW` と `CATCH` は検証されていますが、フォーマッター内で `BYE` が呼ばれた場合や `CATCH-NOBT` が絡んだ場合の復帰後の状態確認（計画114行目に記載の候補の具体化）。

### 性能・サイズの採否基準（暫定基準）への提言
計画116〜133行目の採否基準は統計的な過信を避けた実務的な設計になっていますが、運用上の曖昧さを防ぐため以下の3点を提言します：

1. **「最低限の改善（整数演算とLOOP各10%以上短縮、Bは15%以上）」の解釈**:
   - 現在版（`current`）の測定値では、直前版（`before-catch`）に対して以下の悪化が生じています：
     - **整数演算**: `141.268 ms` → `227.773 ms`（**+61.2%**、直後版比で+59.0%。逆算すると直前版水準への完全回復は約 **-38.0%** の時間短縮）
     - **LOOP**: `118.719 ms` → `163.663 ms`（**+37.9%**。完全回復は約 **-27.5%** の時間短縮）
     - **入れ子呼出し**: `301.264 ms` → `408.364 ms`（**+35.6%**。完全回復は約 **-26.2%** の時間短縮）
   - したがって、現在版から10%〜15%の短縮は「`f1140c7` による悪化分の約3〜5割を取り戻す最低ライン」として妥当な設定です。
   - **提言**: 例えば「整数演算が20%改善したが、LOOPは8%の改善にとどまった（他項目の悪化はなし）」という場合に不採用として破棄するのは惜しいため、**「整数演算とLOOPの双方が `2δ_i` を超えて改善し、一方または両方が10%（Bは15%）以上短縮、かつもう一方も5%以上短縮（または悪化なし）」**のように、片方だけ大きく効いた場合の扱いを決めておくと判断に迷いません。また、同じく+35%悪化している「入れ子呼出し（`calls`）」への効果も主要観察項目に含めることを推奨します。
2. **A/A校正における `δ_i` の算出式（分母）の明確化**:
   - 計画58行目の「2系列で観測したA1/A2の中央値差の絶対値の最大（%）」について、`|median(A1) - median(A2)| / min(median(A1), median(A2)) * 100`（または平均値を分母）のどちらで `%` に換算するかを固定しておくと、スクリプト化時にブレません。
   - 参考までに、[2026-11-15-vm-diagnosis.json](measurements/2026-11-15-vm-diagnosis.json) の `current` 5試行の `(max - min) / median` を見ると、`loops` は約1.0%、`stacks` は約1.1%、`float` は約1.1%と安定している一方、`plus-loop` は約5.2%（93.59ms〜98.61ms）、`arithmetic` は約2.2%（227.14ms〜232.05ms）のレンジがあります。最終判定の1億反復・7回測定では中央値はさらに安定するはずですが、`plus-loop` 等はウォームアップやCPU周波数変動の影響を受けやすいため、`δ_i <= 2%` のゲートは有効に機能します。
3. **「異なる生成コードの配置差（コードアライメント効果）」への対処**:
   - 計画58行目・62行目で既に触れられていますが、`runOperationsLoop` の変更で無関係なカーネル（例：`variables` や `float`）が `max(3%, 2δ_i)` をわずかに超えて変動した場合、それが「論理的な処理増」なのか「関数配置・ループ先頭アライメントの変化」なのかを、第0段階の非countedループ命令数比較で切り分けられるようにしておくと安全です。

---

## 5. 今回読んだ範囲と未確認の範囲

### 確認した範囲（計10ファイル読取り）
- **計画・レビュー・測定文書**:
  - [docs/VM_PERFORMANCE_PLAN.md](VM_PERFORMANCE_PLAN.md)（全143行）
  - [docs/VM_PERFORMANCE_REVIEW.md](VM_PERFORMANCE_REVIEW.md)（全70行）
  - [docs/GFORTH_VM_REFERENCE.md](GFORTH_VM_REFERENCE.md)（全26行）
  - [docs/measurements/2026-11-15-vm-diagnosis.json](measurements/2026-11-15-vm-diagnosis.json)（1〜800行：ビルド条件、`history_comparison` 全8カーネル、`feature_comparison` の構造）
- **Sigma実装・テストコード**:
  - [src/forth.zig](../src/forth.zig#L1550-L2080)（`Running`, `CatchContinuation`, `enterCatch`, `builtinInLoop`, `wordInLoop`, `resumeCatch`, `returnToCaller`, `recordBacktrace`, `traceRunning`, `executeOperations`, `runOperations`, `runOperationsLoop`）
  - [src/core/words_system.zig](../src/core/words_system.zig#L80-L150)（`CatchContext`, `init`, `handleError`, `.bye`）
  - [src/core/error_reporting.zig](../src/core/error_reporting.zig#L1-L321)（全文：`report`, `showBacktrace`, `restoreCatchFrame` 等）
  - [src/tests/catch_test.zig](../src/tests/catch_test.zig#L1-L329)（全文）
  - [src/tests/p09a_test.zig](../src/tests/p09a_test.zig#L1-L242)（全文）
- **Gforth固定版参照ファイル（`c479e1eec66dd57a2441c3020177267ba70d3bdc`）**:
  - [.work/gforth-vm-reference/engine.c](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/engine/engine.c#L515-L676)
  - [.work/gforth-vm-reference/threaded.h](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/engine/threaded.h#L85-L135)
  - [.work/gforth-vm-reference/prim-500-620.txt](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/prim#L500-L620)
  - [.work/gforth-vm-reference/except.fs](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/except.fs#L30-L90)

### 未確認の範囲（今回のレビュー制約により未実施）
- ビルド・テストの実行、ベンチマークの再計測、および逆アセンブル生成コード（`00d234b`, `f1140c7`, `50e661e`）の実バイナリー比較。
- `00d234b` 時点の旧ソースファイルの直接読取り（レビュー文書・計画文書および現行ソースとの整合確認のみ）。
- [src/forth.zig](../src/forth.zig) の上記範囲外（`executeWord` や外側のインタープリター本体）、および `words_debug.zig` / `exception_registry.zig` / イメージ保存実装の内部詳細。
