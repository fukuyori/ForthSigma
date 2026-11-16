# 追補レビュー: セル型 `local_fetch` 直接化（#850 試作）

**結論: 残るブロッカーはありません。** 初回の Medium-1 と Low-1〜4 はすべて対応済みです。新テストの期待値に誤りや空虚な検査はなく、runtime の差分も 1 行のままです。`followup-results.json` は現時点で 9 構成すべて完了しています。

## 初回指摘の対応状況

| 指摘 | 判定 | 根拠 |
| --- | --- | --- |
| Medium-1 他型 fallback の境界 | 解消 | `fallback-tests.zig:2-76`。char/xt/double/float × counted × pending × data 空き 0/1/2 × float 空き 0/1 × アドレス 3 点で 288 通り（no-float は 216）。 |
| Low-1 Linux の命令順 | 解消 | `cell-paths.json` に両 OS・両ループ実体の本体と分岐元を記録。 |
| Low-2 凍結実行体での確認 | 解消 | `frozen-errors.json` の 4 件。SHA は `build-results.json` と `performance/protocol.json` の凍結値に一致。 |
| Low-3 baseline の実行範囲 | 解消 | baseline を windows-debug / windows-fast / linux-fast で実行。 |
| Low-4 上位 slot と入れ子 CATCH | 解消 | `boundary-tests.zig:49`、`fallback-tests.zig:78-95`。 |

## 新テストの期待値

ソース（`local_variables.zig:132-139`、`forth.zig:2353-2363, 2387-2391, 2408-2412, 2420-2424`）と照合しました。

- **char:** `len-1` と `len-7` で成功し、`len` で InvalidAddress。cell 経路へ誤って流れると `len-1` と `len-7` が失敗するので、分岐条件の退行を検出できます。
- **xt:** cell と同じ境界と優先順位。挙動が同じなので経路の識別はできませんが、これは性質上のものです。
- **double:** 空き 1 のとき low（0x11223344）だけ積んで StackOverflow、depth は +1。`pushDouble` の実挙動どおりです。
- **float:** data スタックは空き 0 でも不変。float 満杯で FloatStackOverflow、無効アドレスが優先。
- **上位 slot 検査:** 事前に全 slot を -37 で埋めてから、失敗後に `data_depth` 以上を検査しています。空き 0 の StackOverflow では対象が 0 個ですが、空き 1/2 の無効アドレスで実質的に検査されます。
- **入れ子 CATCH:** CATCH が xt を取った後は深さ 0 で、ループがちょうど STACK-CELLS 個を積むため、最初に溢れるのは `x` の `local_fetch` です。-3、深さ、`locals_top`、frame/call/catch 深さ、後続の `10 3 LOCAL-NEXT` → 7 はいずれも正しい期待値です。
- **kind と offset の反映:** 同じ定義でアドレスと kind だけを変えて成否が分かれるので、operand の書換えが実際に効いていることをテスト自身が示しています。

## 区別して読むべき点

- **合成 operand と通常入力:** 無効アドレスと、cell 用定義に kind ビットを立てた operand は、テストでの書換えでしか作れません。通常入力で確認できたのは、容量超過（-3）とその後の復帰だけです。
- **凍結実行体で未確認の経路:** InvalidAddress 経路は、strip 済み凍結実行体では動的に確認していません（`frozen-errors.json` の scope にも明記されています）。
- **テスト binary と凍結実行体:** 境界テストは `zig build test` の binary、命令列は symbols 版の実行体です。strip 済み実行体とバイト一致する保証はありません。
- **静的アセンブリの限界:** 観測できたのは命令配置だけです。4 実体とも、範囲検査 3 分岐 → 容量検査 → ロード → ストアの順でした。ハードウェアの投機実行がないことは示せません。

## 実行結果

- **両側で確認できた構成:** windows-debug（両側 1015 合格 / 5 skip / 計 1020）、windows-fast、linux-fast。
- **Linux:** 親コマンドは exit 1（ホストが ELF を実行できないため）、ELF 直接実行は exit 0。新旧 4 テストは両側とも名前付きで OK です（`followup-*-linux-fast-elf-1.log:528-531`）。
- **candidate のみ:** no-float、no-debug、minimal は exit 0。linux-debug は追補では再実行していないので、新 fallback テストはその構成で未実行です。
- **テスト同一性:** `followup-test-hashes.json` で両コピーの `core_words_test.zig` が同一ハッシュです。
- **runtime 不変:** `candidate/src/forth.zig:2177` は `runtime.patch` と一致し、baseline 側は旧形のままです。ソースのハッシュ再計算は私の側ではできていません。

## 軽微な注記（いずれもブロッカーではありません）

- **windows-fast の集計差:** baseline は 1074/1084、candidate は 1015/1020 と表示されます。candidate 側は小さい方のテスト（64 件）が cached で集計外になっただけで、本体は両側とも 1015 合格 / 5 skip / 計 1020 です。記録に一言あると誤読を防げます。
- **名前での実行確認:** Windows と機能無効構成のログは要約行のみです。新テストに skip 経路はないので実行されたと判断できますが、これはソースからの推論です。
- **`cell-paths.json` の抜粋範囲:** 最初の `jmp` で切れるため、depth 加算が見えるのは Linux の 1 実体だけです。エラー分岐先も含まれず、Windows 共有分岐先のエラーコードは静的に未追跡のままです。どちらが counted 側かのラベルもありません。
- **double の未検査点:** `len-8`（high は読めて low が範囲外）はありません。helper は不変なので任意の追加です。
- **計画書の記述:** `docs/VM_CELL_LOCAL_FETCH_PLAN.md:3,59` の「試作はまだ」「未着手」は現状と合っていません。採否記録の際に更新してください。

## 計時

- **記録の一致:** `performance/results.json` は `calibration_unresolved`、`comparisons` は空です。Windows local の A/A は δ=5.168% と 1.980%、最小中央値 6.046875 秒で、計画の「最大 δ 2% 以内」を満たしていません。
- **打切りの妥当性:** 候補 A/B、Linux 校正、標準 34 条件に進まなかったのは事前計画どおりです。
- **判定の読み方:** 「採用保留」であって、遅くなったことを観測した不採用ではありません。速度向上も示されていません。
- **未確認:** 追補テストが計時完了後に実行されたかどうかは、成果物からは確認していません。A/A 変動の原因も評価していません。
