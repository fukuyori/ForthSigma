# 2R@ 局所試作レビュー結果

試作の実装に続行を止める問題はありませんでした。ただし文書の組合せ数が誤っており（256 ではなく 128）、これは修正が必要です。確認は Read/Grep/Glob のみで行い、変更・テスト実行・リポジトリ外アクセスはしていません。

## 重大指摘

**1. テストの組合せ数は 128 通りで、文書の「256 通り」は誤り**
`core_words_test.zig:1003-1007` のループは counted 2 × compiled 2 × pending 2 × ret_depth 4 × space 4 = 128 です。さらに direct 経路は `executeBuiltin` を直接呼ぶため `keep_counting` が効かず、direct×counted の 32 通りは実質重複です（独立なのは 96 通り）。`docs/VM_STACK_CHECK_INVESTIGATION.md:29` の訂正が必要です。

**2. 基準バイナリの出所が記録上つながっていない**（記録の不備で、計数の信頼性自体は高い）
- 基準バイナリは `.work/rot3-20261116/baseline-symbols` の流用で、逆アセンブルのパスも `rot3-20261116\baseline\src` です。
- `build-test.py` は `stack-check-20261116/baseline` の Linux ビルドをしていません。
- JSON の `source_manifest.baseline` がどのツリーのハッシュかは明記がなく、rot3 側ツリーとの同一性を示す記録もありません。
- 私が確認できた範囲では、rot3 baseline の 2R@ 節は同一です。`words_stack.zig` と `forth.zig` のハッシュは過去の測定記録にある採用版の値と一致します。関数アドレス `0x1175160` と他関数の計数も両版で一致します。
- rot3 ツリー全体が同一かどうかは未確認です。JSON に rot3 baseline のソースハッシュか、流用の旨を追記してください。

## 実装の確認結果（問題なし）

- **安全性**: 先頭の 2 検査で `return_depth >= 2` と空き 2 以上が確定するため、`base`・`base+1` への格納と `return_depth-2`・`-1` の読み出しは範囲内です。
- **エラー優先**: ReturnStackUnderflow → StackOverflow の順は両版同一で、生成コードでも `0x1e` → `0x1f` の順です。pending 出力エラーの優先は `executeBuiltin`（`forth.zig:2219`）側にあり、試作の影響を受けません。
- **途中状態**: 基準版でも先頭検査の後は push が失敗しないため、部分 push 状態はどちらにもありません。失敗時は両版とも無書き込みです。
- **Storage 不変条件**:
  - 差が出るのは、1 回目の格納が `data_depth`・`data_stack.len`・`ptr` 自体を書き換える場合だけです。
  - `Storage.allocate` は data/return を別々に確保し、State は別オブジェクトなので、その別名は生じません。
  - `allocate` 以外の Storage 構築経路は src 内に見当たりません。テストがスライスを縮める例（`p01b_test.zig:60`）も同じ確保の部分です。
  - `data_depth > len` の不正状態では両版とも同じ挙動です。

## 生成コードと計数の主張

| 主張 | 確認結果 |
| --- | --- |
| 2R@ の Ir 30→26 | 逆アセンブルの手計数と一致 |
| Dw 5→4 | 一致 |
| Dr 14→12 | 試作版 12 は一致。基準版は `add [mem],1` の読みを数えると 15 になり、Callgrind が modify を書き込み側だけで数えるなら 14 で整合（その扱いは未確認） |
| 全体 546→542 | JSON の合算と一致 |
| DNEGATE 160 で不変 | 30+81+22+27 で一致 |
| 後続の容量分岐が消えた | 試作版の分岐は先頭の `jbe`/`jb` のみ |
| DNEGATE の popDouble は検査 1 回、pushDouble の容量検査は残存 | 逆アセンブルどおり |
| Windows Debug 両版 21/21、core 1012 成功/5 skip | ログと一致。host は cached 表示 |
| 初回の型エラーは両版同一のテスト側の問題 | 失敗ログと一致 |

## 任意事項

- **最適化ビルドでの境界確認がない**: 境界テストは Windows Debug のみです。変更が効く fast ビルドで試作版が実行されたのは Callgrind カーネルだけで、検証は合計値と DEPTH=0 です。#833 の範囲と理解していますが、採用判断の前提として明記すると安全です。
- **失敗 PC の検査条件**: `failed_pc`・backtrace の検査は `debug_enabled` のときだけです（`core_words_test.zig:1037`）。Debug テストでこのオプションが有効かは確認していません。
- **テストの補強候補**:
  - 失敗時に `data_stack[depth..]` が無書き込みであること（space=1 の場合）。
  - `interpretLine` のトップレベル経路と CATCH 経由。
- **追加の削減余地**: 試作版は 1 回目の格納後に `return_depth` と両スタックの ptr を再ロードしています。2 セルを先にローカルへ読めば減る可能性がありますが、別試作として扱うのが妥当です。
- **docs 側 JSON の情報不足**: カーネル定義と呼出し回数（各 builtin 1 回/反復）は `.work` 内の `*-code.json` にしかありません。docs 側に入れると `.work` なしで検証できます。