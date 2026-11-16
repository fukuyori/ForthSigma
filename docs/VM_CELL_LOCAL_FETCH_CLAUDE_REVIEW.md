# レビュー結果: セル型 `local_fetch` 直接化（#850 試作）

**結論: 安全性に関するブロッカーはありません。** 変更は意味的に baseline と等価で、境界テストは cell 経路については非空虚です。ただし他型 fallback の境界確認が計画に対して不足しています（Medium 1件）。速度・採否条件（計画 手順5〜7）は評価対象外で、未検証です。

## 検証済みの事実

| 観点 | 結果 | 根拠 |
| --- | --- | --- |
| 差分範囲 | 1行のみ。root は未変更 | `runtime.patch:7-8`、root `src/forth.zig:2177` は旧形のまま |
| 凍結 | baseline-windows の SHA が root 実行体と一致 | `frozen-runtime.json:7` と `build-results.json:17` |
| サイズ | Windows 同一バイト数、Linux +192 (0.0101%) | `build-results.json:54,91-92` |
| cell の意味 | `fetchLocal` の `.cell, .xt` 枝と同一式 | `src/core/local_variables.zig:134`、`candidate/src/forth.zig:2177` |
| エラー優先 (ソース) | `readCell` の InvalidAddress が `push` の StackOverflow より先 | `candidate/src/forth.zig:2387-2391, 2420-2425, 2450-2453` |
| エラー優先 (Windows 生成コード) | 両ループ実体とも、範囲検査 → 容量検査 → ロード → ストア → depth 加算の順。検査前の投機ロードなし | `windows-disassembly.txt:62129-62143, 61981`（非counted）、`69729-69741`（counted） |
| pending 出力 | local 経路は新旧とも `checkOutputError` を呼ばず、`output_error` を消費しない | `candidate/src/forth.zig:2170-2194, 2201-2206` |
| 失敗 PC | `pc` は加算済みで、同一関数内の `try` から同じ `errdefer` に入る | `candidate/src/forth.zig:1840-1842, 1879` |
| frame / locals 復元 | `executeOperations` の `defer` が担い、opcode に依存しない | `candidate/src/forth.zig:1762-1769` |
| frame なし | `locals_frame == 0` の検査は分岐より前で不変 | `candidate/src/forth.zig:2171` |
| counted / 非counted | `counted` は comptime で、両実体に同じ変更が入る | `candidate/src/forth.zig:1783-1784`、逆アセンブル上の2箇所 |
| XT fallback | XT 種別の `local_fetch` は実在し（POSTPONE、`+TO`）、candidate でも `fetchLocal` へ流れる | `candidate/src/core/quotations.zig:157-158`、`definers.zig:278` |
| テスト同一性 | 追記後の `core_words_test.zig` は両側で同一ハッシュ | `test-source-hashes.json` |
| テスト実行 | Windows 4構成と minimal は exit 0。Linux は親コマンド exit 1 だが ELF 直接実行は exit 0 で、境界テスト2件が OK | `test-results.json`、`candidate-linux-debug-elf-1.log:529-530`、`candidate-linux-fast-elf-1.log:528-529` |

境界テスト1は 2×2×3×4=48 通りで、無効アドレスと満杯の重複、空き0/1/2、末端セル、prefix 保持、return/float スタック、`locals_top`、frame/call/catch 深さ、pending、失敗 PC を絶対値で検査しています。operand の kind ビットは 0 のままなので、candidate では確実に直接経路を通ります。

## 指摘事項

### Medium-1: 他型 fallback の境界テストがない（検証済みの不足）

- **場所:** `boundary-tests.zig` 全体。計画は `docs/VM_CELL_LOCAL_FETCH_PLAN.md:35` で「他型 fallback の float/data/return stack も確認する」としています。
- **問題:** 追加テストは cell 種別だけです。既存テストは正常系のみです（`locals_test.zig:38-39`、`core_words_test.zig:954`、`p07b_test.zig:69`）。
- **特に char:** char の slot は cell 幅で確保され（`local_variables.zig:42`）、frame はゼロ初期化されます（`forth.zig:2166`）。そのため char を誤って cell 経路で読んでも、正常系では同じ値になり検出できません。差が出るのはメモリー末端だけです。
- **現状の評価:** 現行コードの `kind == .cell` に誤りはなく、実害は確認していません。ただし分岐条件の退行を検出する手段がありません。
- **依頼:** 同じ operand 書換え方式で、kind ビットを設定したケースを両コピーに追加してください。
  - char: `memory.len-1` で成功し、`memory.len` で InvalidAddress。cell との識別点は `memory.len-7`（char は成功、cell は失敗）。
  - xt: cell と同じ境界と優先順位。
  - float: data スタック不変。float スタック満杯で FloatStackOverflow、無効アドレスが優先。
  - double: 空き0/1/2。`pushDouble` は空き1で low だけ積んで失敗するので、baseline の挙動をそのまま期待値にする。

### Low-1: Linux の命令順が成果物に残っていない

- **場所:** `generated-code.json` は Ir と call 数のみ、`windows-assembly.json` は fallback の call 箇所のみです。
- **問題:** 上記の Windows の命令順は、私が `windows-disassembly.txt` から読み取ったもので、成果物には記録されていません。Linux 側は逆アセンブルを確認できる成果物が見当たらず、検査→ロードの順は静的には未確認です（挙動は linux-fast の ELF テストで確認済み）。
- **依頼:** `candidate-linux-symbols` の cell 直接経路の抜粋（両ループ実体）と、Windows の該当行を記録に追加してください。

### Low-2: テスト binary と凍結実行体は別物

- **問題:** テストは `zig build test` の binary で、`-Dcpu=baseline -Dstrip=true` の凍結実行体ではありません。逆アセンブルも symbols 版です。インライン化や配置が同じである保証は成果物からは得られません。
- **問題（細部）:** Windows 直接経路の範囲外分岐（共有先 `0x14003fafc`）で、エラーコード用レジスタの値までは静的に追っていません。
- **依頼:** 両 OS の凍結 candidate 実行体で、通常入力から作れる失敗を1件 CLI で確認してください。例: data スタックを満杯にして `{ | x -- } x` を CATCH し、-3、深さ、後続の local 動作を見る。無効アドレスは通常入力では作れないので、テスト側の確認に留まると明記してください。

### Low-3: baseline のテスト実行は windows-debug のみ

- **場所:** `test.py:19-23`、`test-results.json`。
- **問題:** fast / Linux / no-debug では candidate だけを実行しています。期待値は絶対値なので等価性の主張は成り立ちますが、「両側で同一結果」と書けるのは windows-debug だけです。
- **依頼:** baseline も windows-fast と linux-fast で実行するか、記録上の表現を限定してください。

### Low-4: 失敗時の検査の細部

- **場所:** `boundary-tests.zig:48`。
- **問題:** 失敗時に検査するのは `[0..depth)` だけで、`depth` 以上の slot が -37 のままかは見ていません。
- **問題:** 失敗するのは frame 深さ0の最上位呼出しだけです。入れ子の colon 呼出し内や CATCH 下で `local_fetch` が失敗するケースはありません。復元機構は opcode 非依存で不変なので仮説的リスクです。
- **依頼:** 失敗時の上位 slot 検査を追加してください。余力があれば、入れ子＋CATCH で満杯になるケース（通常入力で構成可能）を1件追加してください。

### Info

- `-Ddebug=false` では counted の反復は非counted と同じ実体を通り、失敗 PC の検査も行われません（`forth.zig:1783`、`boundary-tests.zig:59,85`）。設計どおりで欠陥ではありません。
- no-debug / no-float / minimal の各ログは要約行しか確認できず、境界テストが skip されずに走ったことは名前では確認していません。
- `docs/VM_CELL_LOCAL_FETCH_PLAN.md:3,59` の「試作・追加 build はまだ行っていない」「未着手」は現状と合っていません。採否記録の際に更新してください。
- 不正な kind 値（5以上）の `@fromBackingInt`（`forth.zig:2174`）は baseline と同じ既存挙動で、今回の変更で悪化も改善もしていません（仮説的リスク）。

## 未評価の範囲

- 時間比較、A/A 校正、標準8項目、CATCH 9項目、実例ケース（計画 手順5〜6）。
- 採否判断。Ir の 129→108 と、他型の +3〜4 は命令数であって速度ではありません。
- SEE と SAVE/LOAD-DICTIONARY の往復（計画 手順4）。`smoke-images.json` は読んでいません。
