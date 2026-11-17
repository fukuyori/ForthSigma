# 3候補の最終技術レビュー（Claude Code）

2026-11-16。読取り専用、exit0。FUSION基準A/A開始後に受領した、追補前のレビュー。指摘後の変更と実行順は対応文書を参照。

# 最終技術レビュー所見(#863 / #867・#868)

**結論:** FUSION差分に意味論上の欠陥は見つかりませんでした。ただしCPU計時を始める前に直すべき点が3件(M1〜M3)、結果文書の正直さに関する点が2件(M4・M5)残っています。local/VALUEの「未達・root不採用」という結論は、凍結済みスクリプトと `results.json` に整合しています。

## 確認できた事項(指摘なし)

- **PC・例外境界**(`fusion/src/forth.zig:2048-2055`)
  - push失敗時の `failed_pc` はliteral+1、AND失敗時はAND+1で、`errdefer`(`:1840`)がループ局所の `pc` を読むため基準と同じです。
  - `pc < end_pc` の検査で語末を越えません。ANDへの直接分岐は従来の `inline else` 経路に残ります。
  - `counted` はcomptime引数なので、trace/profile/WATCH/step/StepLimitの命令境界は不変です。
- **省かれる境界検査**
  - 融合で飛ばされるのはループ先頭の `halted` 検査1回だけです。`halted = true` は `words_system.zig:150`(同期的なBYE)のみで、literalのpushでは立たないため観測差はありません。
- **深さ0の訂正**
  - `src/core/integer_math.zig:19-20` は `b`(literal)をpopしてから `a` で失敗します。深さ0・`data_stack[0]==255` の期待値と計画文(`VM_ADJACENT_PAIR_PLAN.md:20`)は実装と一致し、runtime側は変えていません。
- **除外ビルド**
  - `isExcludedBuiltin(.bit_and)` の場合もpush、pc前進、`InvalidExecutionToken` の順で、基準の2命令実行と同じです。
- **計時スクリプトの置換**
  - `prepare-fusion-performance.py` の `.replace` 対象は、現行の `value/run.py`・`worker.py` にすべて実在します。
  - 置換後は20ケース、標準34条件、期待値7、WSL側workerパスが整合します。
- **数値の一致**
  - 両 `results.json` は文書の数値と一致します。状態は両方とも `standard_primary_target_unmet`(windows/arithmetic)、`not_adopted: true` です。
- **VALUE追補**
  - `value-followup-results.json` はWindows 5構成がparent_exit 0、Linux 5構成がparent_exit 1かつELF 2本ともexit 0で、文書30行目と整合します。
  - `selected_blocks` の3番目のブロックはstack storeと深さ加算のみでcallがなく、「静的観察に限る」という記述は妥当です。

## 残る指摘

### 中

**M1. 容量境界テストが実際には境界を踏んでいない**(`fusion-tests.zig:4,8`)
- `createMachine` は `.small`(data_stack=1024、`memory_map.zig:64`)を使うため、4095と4096はどちらも1024に丸められ、同じ満杯ケースを2回実行しています。
- 「literalのpushでちょうど満杯になり、ANDが成功する」深さ(len−1)は未検証です。
- 対処: `machine.data_stack.len - 1` と `len` を明示的に使ってください。

**M2. 計時開始の条件が機械的に強制されていない**(`prepare-fusion-performance.py:5-6`)
- 確認しているのは `fusion-test-results.json` と `fusion-correctness.json` の存在だけです。
- Linuxのdebug無効・float無効・最小構成の補足結果(`fusion-followup-results.json`)の存在と、ELFのexit 0は検査していません。「ビルド・テスト完了まで計時しない」は手順頼みです。
- 現時点の同ファイルには3構成ともELF exit 0が記録されていますが、各logのsummary件数は範囲外で未確認です。
- 対処: `start.json` を作る前に、followupの3構成と全 `elf_tests[].exit==0` をassertしてください。置換が効かなかった場合に黙って進まないよう、各 `.replace` に `assert old in s` も加えてください。

**M3. 計画に列挙した検証項目の一部に、専用テストの証跡がない**(`VM_ADJACENT_PAIR_PLAN.md:22`)
- BYEと再入は `fusion-tests.zig` に専用テストがありません。
- CATCHは `' FUSION-STEP CATCH`(interpreter起点)だけです。同じループ内で `resumeCatch` を通る、コンパイル済み語の中のCATCHは融合失敗では未検証です。
- 対処: `: T ['] FUSION-STEP CATCH ;` 型のテストを追加するか、結果文書で「未実施」と明記してください。

**M4. 外れ側の費用が、選定に使った実例で正味評価されていない**(結果37行目、計画7-14行目)
- 一致で−9 Ir、不一致のliteralで+8 Irです。
- 実例ではliteral→bit_andが17.96M回に対し、literal→rshiftだけで11.82M回、local_fetch→literalは26.30M回あります。
- 不一致のliteralが約2,020万回を超えると、正味のIrは増加します。literalの総実行回数が文書にないため、判定できません。
- 対処: 既存のpair集計からliteral総数を出し、正味のIr見積りを追記してください。
- 推定(定義は未読): worker.pyのarithmetic検算式(a=3、c=7、&65535)からすると、標準arithmeticは一致1・不一致2で正味悪化側になり得ます。専用kernelは一致100%の最良例です。

**M5. FUSIONの現状が結果文書に明記されていない**(結果33-39行目)
- VALUE節にある「未strip版の計数であり、CPU時間と区別する」に相当する注記が、FUSION節にありません。
- 追記すべき内容:
  - CPU時間は未測定で、Ir 87→78は時間ではないこと。
  - Linuxのdebug無効・float無効・最小構成は補足として実行中または未反映であること。
  - 採否は未判定であること。

### 低

**L1. 未測定数と部分効果の扱いが明記されていない**(結果14-15行目、28行目)
- localとVALUEそれぞれに「標準34条件のうち、測定は1条件(windows/arithmetic)で未達、残り33条件は未測定」と書いてください。
- VALUE節には「専用の−42〜−44%は部分効果であり、不採用」の一文がありません。local節の15行目に相当する記述です。

**L2. Windows CPU時間の量子化に注記がない**
- 中央値が15.625msの倍数で、6秒に対して約0.26%です。arithmeticの+0.265%/+0.000%とA/A δ 0.265%は、0〜1 tickの差です。
- 結論には影響しませんが、分解能の注記を足してください。

**L3. `audit-performance.py` の検査範囲が狭い**
- `benchmark-runtime.py` のsha照合がありません。
- 各結果の `script_sha256`・`protocol_sha256` を `start.json` と照合していません。
- 監査した群から較正δ、判定、statusを再計算していません(`results.json` を転記しているだけです)。
- 計時と重ならなかったことの裏付け(ビルド・テストlogの時刻と `start.json` の比較)がありません。

**L4. FUSION用protocolの説明文が古い**
- `scope` と `checksums` がVALUE版のまま残ります。
- 期待値7は `expected_origin: independent formula` と記録されますが、Nに依存しません。「反復回数は検証しない定数」と明記してください。

**L5. Windowsで融合経路が生成・実行された証跡がない**
- あるのはサイズ差(−512 bytes)だけです。Irの根拠はLinuxの未strip版に限られます。
- VALUEと同様にPDBで対応を取るか、未確認と明記してください。

**L6. Linuxの子プロセスaffinityは継承のみで、直接照会していない**
- 開示済みで、追加の対応は不要です。

## 採否の整理

- **local、VALUE:** 専用ケースには効果がありますが、標準arithmeticの10%目標が未達です。33条件は未測定で、rootには不採用です。緩めた基準での採用は支持しません。
- **FUSION:** 未判定です。M1〜M3を直し、M4の正味見積りを出してから計時に進むことを勧めます。
