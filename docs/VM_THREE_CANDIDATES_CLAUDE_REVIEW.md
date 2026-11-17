# 3候補の途中レビュー（Claude Code）

2026-11-16。VALUE単独試作・隣接計数・計時計画が対象。literal→bit_andは設計段階、local比較は実行中の時点の読取り専用レビュー。最終採否の独立検証ではない。

# レビュー結果（#863 / #865 / #867、読取りのみ）

**結論：VALUE分岐の意味・エラー状態は基準経路と一致しており、採用を妨げる重大（High）の指摘はありません。** 是正または記録を勧めるのは中5件・低6件です。計時結果の評価はしておらず、2%ゲートと採否規則の変更も提案しません。

## 確認できた点

- **VALUEの等価性**：基準は `else` → `wordInLoop` → `executeWord` → `push(readCell(word.value))` で、途中に通知・profile・frame操作はありません（`value/src/forth.zig:1634-1662`, `1445-1459`）。候補（`forth.zig:1957-1961`）は同じ `outer_pc` 代入と同じ評価順です。
  - 範囲検査（InvalidAddress）が容量検査（StackOverflow）より先で、`failed_pc` は同じerrdeferによりpc+1になります（`forth.zig:1840-1842`）。
  - synonym経由、DEFER→VALUE、EXECUTEは `word.kind` が `.value` にならないため従来経路のままです。TO/+TOは未変更です。
- **差分テスト**：同じ2テストが `baseline-tests` と `value` の両方の `core_words_test.zig:1001,1059` に入り、どちらもWindows debugで1072/1082通過です。
- **Callgrind**：VALUE呼出しは201→124、deferred-colonは217→218、他の10ケースは同数です（`generated-code.json`）。
- **計数器**：`countPair` はcountedループの `countOperation` 直後の1箇所だけです（`pairs/src/forth.zig:1884`）。`reset` は `pair_last` も消去し（`profiler.zig:79-88`）、`run-pairs.py:9` の「pair合計＝総数−1」で間接的に検証されています。
- **plain_calls**：rootは `trace or profile or coverage` のまま（`value/src/main.zig:2098`）、pairs作業コピーだけprofileを外しています（`pairs/src/main.zig:2098`）。文書の記述どおりです。
- **計時の凍結**：`start.json` による再実行拒否、worker起動ごとのbinary/worker/benchmarkハッシュ照合、AA（δ≤2%かつ中央値≥5秒）、両OS校正後のみ比較、2δ超の判定、`not_adopted: True` 固定は文書どおりです。local基準のWindowsハッシュは `frozen.json:305` と一致します（379d…）。

## 中

1. **literal→bit_and専用kernelの検査値が弱い**（`VM_ADJACENT_PAIR_PLAN.md:26`）
   - `7 … 65535 AND` の期待値7は、Nにも、ANDが実行されたかにも依存しません。両命令を飛ばす誤りでも7になります。
   - 既存workerの `expected()` はこのケースを持たず、基準出力との一致確認だけになります（`worker.py:22-31,45`）。
   - 対処：計時kernelは変えず、計時前の正当性確認として、N依存の結果・DEPTH・operation総数の基準一致を別に記録する。

2. **選定pairの偏りと隣接PC内訳が文書にない**（`VM_ADJACENT_PAIR_PLAN.md:7-14`）
   - literal→bit_andの17,956,448回のうち、資産生成3ケースが約1,549万回（約86%）、klondike-renderが約236万回です。logic 3ケースは合計約10万回です。
   - klondike-bakeの約679万回は合計からの差引きで、直接は読んでいません。
   - 確認した8ケースでは隣接PC数が回数と同数でした。表に列がありません。
   - 対処：選定理由の横にケース別回数と隣接PC数を追記する。頻度であり時間比ではない旨は記載済みです。

3. **先読みが外れる側の確認が計画にない**（`VM_ADJACENT_PAIR_PLAN.md:24`）
   - 棄却条件は対象kernelの命令削減だけです。全literalに入る次命令判定の増分（既存 `literal` ケースは87 Ir）を計時前に記録する項目がありません。
   - 対処：既存12ケースのCallgrind再計数を計時前の必須記録に加える。deferred-colonの+1のような配置変動もここで見えます。

4. **異常終了時の状態が記録されない**（`run.py:20`, `worker.py:17-19,42,55`）
   - workerの非0終了は制御側のassertで落ち、`complete.json` もstatusも残りません。`start.json` があるため再実行もできません。
   - 該当するのは、`NoSuchProcess` 以外のpsutil例外、Windowsの子affinity不一致（群の全標本後に判定）、pilotのCPU 0によるゼロ除算、WSL起動失敗です。
   - 対処：この場合は「基盤異常・未測定」として文書とtqueに正式記録し、再試行しない。VALUE側は未開始なので、開始前にこの扱いを明文化できます。

5. **重複実行の防止が宣言だけ**（`run.py:14` の `no_overlap`）
   - VALUE制御はlocalの `complete.json` を確認しません。build/test/profileの非重複も検出されません。
   - 対処：VALUE開始前にlocalの `complete.json` を目視確認して記録する。literal試作のbuildは両計時の完了後に行う（`VM_ADJACENT_PAIR_PLAN.md:24` と整合）。

## 低

6. **VALUE制御の表記がlocalのまま**：予備条件未達は `local_screen_unmet`、説明は `local_gate` で記録されます（`value/run.py:14,33`）。判定は同一です。開始前に直すか、結果の読替え注記を残してください。
7. **Linuxは子のaffinityを確認していない**：親の `sched_setaffinity` の継承に頼り、子ごとの確認はWindowsの先頭2回だけです（`worker.py:55`, `benchmark-runtime.py:52-57`）。`VM_THREE_CANDIDATES_PLAN.md:13` の「子のCPU2 affinityを確認」はLinuxでは親の値による推定です。
8. **VALUE候補ハッシュの突合せ**：`protocol.json` は開始時の実体を記録するだけです。開始後に候補が `build-results.json` の980c…/1b6f…、基準が379d…/bdb6…と一致するか確認してください。
9. **Callgrindは未strip版**：計数はff17…、計時は1b6f…です。Windowsの生成コード確認は見当たりません。「両OS生成コード確認」はLinux命令計数まで、と書くのが正確です。
10. **VALUEテストの未網羅**：
    - 失敗系はframe深さ0のみで、入れ子呼出し内やCATCH内でのInvalidAddress、backtrace内容の比較がありません。
    - Linuxはdebug/fastのみで、no-debug/no-float/minimalはWindowsのみです。
    - ELFテストは終了コードだけの記録です（`test-results.json:104-124`）。
    - 補完CLI 18件はVALUEを通りません（`missing-file` は終了コードのみ）。
11. **計数器の分類上の注意**（`profiler.zig:58-74`）：
    - `.call` は検証前の `op.value` で語種を引きます。FORGET後の古いidは誤分類になり得ます。
    - synonym/deferredは解決先でなく自身の種別で数えます。
    - `call_colon` はインライン標識と実呼出しが同じキーです。
    - `pair_last` は入れ子の実行ループをまたいで共有され、分岐先が次PCのpairも隣接PCに入ります。
    - `frozen.json:308` のpairsソースハッシュがplain_calls修正後のものかは確認できません。

## 想定される帰結

VALUEが専用の2δ条件を通っても、標準比較の最初はWindows整数の「10%以上短縮」です（`run.py:38-40`）。VALUEを含まないkernelなので、そこで `standard_primary_target_unmet` となり33条件が未測定で残る見込みです。これは規則どおりの停止で、悪化の証拠ではありません。「保留・未測定範囲あり」と記録するのが妥当です。

## このレビューの限界

- 実行・再計測はしていません。逆アセンブル、Callgrind生データ、計時標本は未読です。
- 辞書12確認、標準16組、ワークロード9組の出力一致は、成果物を特定できず未検証です。
- サイズ1%条件は基準のバイト数を読んでおらず未確認です（候補は1,809,408 / 1,891,632 bytes）。
- local計時は進行中で、読んだのは「Windows校正通過（δ1.02%、最小中央値6.11秒）」の記録だけです。
