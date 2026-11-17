# task869 再々レビュー（読取り専用）

**結論:** 採否（3候補とも本体不採用）と数値を覆す欠陥はありません。M1〜M5・L1〜L6の対応は実物と概ね整合しています。ただし文書の正確さについて中2件・低4件の修正が残ります。

本レビューはRead/Grep/Globのみです。ビルド・テスト・SHA再計算は一切再実行しておらず、以下の「確認」はすべて保存済みsource・log・JSON同士の照合です。

## 残る指摘

### 中

**N1. 基準側の追補は Windows Debug 1構成だけなのに、両OS・全構成で通したと読める**
- 該当: `docs/VM_THREE_CANDIDATES_REVIEW_RESPONSE.md:7,17,33`、`docs/VM_THREE_CANDIDATES_RESULTS.md:38,63`
- 証拠:
  - `.work/three-candidates-20261116/fusion-post-review.py:6` のjobは `fusion-baseline` が `windows-debug` の1件、残り10件は候補です。
  - `fusion-post-review-results.json:2-16` も基準は1行だけです。
  - VALUEも同じ形です（`value-followup.py:6`、`value-followup-results.json:2-16`）。
- 修正: 「基準はWindows GNU Debugの1構成、候補は両OS×5構成」と明記してください。基準と候補の同一動作を実行で確かめた範囲はWindows Debugに限られます。
- 補足: 「baseline CPU」（`-Dcpu=baseline`）と基準版が紛らわしいので、語を分けてください。

**N2. タスク状態の記述が古い（#862/#872/#873/#874は完了・原因未特定で打切り済み）**
- `docs/VM_THREE_CANDIDATES_RESULTS.md:65`: 「#862の対照診断設計は別の残作業である」
- `docs/VM_THREE_CANDIDATES_REVIEW_RESPONSE.md:39`: 「CPU0 API/ETW残差の原因調査（#862）…は別の残作業」
- `.work/three-candidates-20261116/document.py:52`: 上記RESULTSの文の生成元です。ここを直さないと再生成で戻ります。測定JSONの `scripts` にも同じ文が入っています。
- `docs/VM_WINDOWS_TIMING_FOLLOWUP.md:115`: 「#862…別の残作業として維持する」
- `docs/VM_ADDITIONAL_MEASURES_SELECTION.md:3`: 「現在の未完了は#862…#869、#870、#871」
- `docs/VM_WINDOWS_ETW_CONTROL_PLAN.md:3`: 冒頭の「新規取得・原因特定はまだ行っていない」に当時の記述という注記がありません（同書 `:77` で#873へ引継ぎ済み）。
- `docs/VM_WINDOWS_ETW_ANALYSIS.md:5`: 「取得はまだ行っていない」も同様です（`:3` に後続結果はあります）。
- `docs/VM_PERFORMANCE_PLAN.md:228`: ETW取得後の追記で止まり、#873/#874の結果へのリンクがありません。
- 修正: 各所を「#862/#872/#873/#874は完了、原因未特定で打切り」とし、`docs/VM_WINDOWS_ETW_CONDITION_INVESTIGATION.md` へリンクしてください。
- あわせて確認が必要な点:
  - 「再々レビューは実施していない」（RESULTS `:65`、RESPONSE `:33`）は、本レビューの記録時に更新が必要です。
  - #870は、RESPONSE `:39` の「別の残作業」と `docs/VM_PARTIAL_ADOPTION_EVALUATION_PLAN.md:26`（判断待ちで維持）・`:43`（認めない場合は閉じる）のどちらが現状か、文書からは判定できません。実際のタスク状態に合わせてください。

### 低

**N3. 「runtime・計時実行体のSHA不変」の根拠が、生成手順のない真偽値だけ**
- 該当: RESPONSE `:33`、RESULTS `:63`
- 証拠: `post-review-sequence-audit.json:2-6` は `runtime_unchanged: true` などの真偽値のみで、ハッシュ値も生成scriptも保存されていません。`overall-timing-totals.json`、`final-test-source-hashes.json`、`fusion-protocol-annotations.json:6` の `supplemental_linux_tests_preceded_start` も同様です。
- 記録同士で裏づけられた範囲:
  - 候補 `forth.zig` の `4a28cdb1…` は、`fusion-frozen.json:3`、測定JSON `:12686`、`:41686` で一致します。
  - 計時実行体の `fe016098…`／`86b1c94f…` は、`fusion-build-results.json:17,35` と `performance/fusion/protocol.json:156,158` で一致します。
  - 追補のコマンドは `fusion/` 内の `zig build test` で、計時実行体のある `fusion-windows/`・`fusion-linux/` を出力先にしていません。
  - 開始時のgit statusで `src/` に変更はありません。
- 裏づけられない範囲: 追補後に実行体を再ハッシュした記録です。`audit-performance.py:10-11` のassertは実行時点の照合ですが、追補との前後は記録されていません。
- 修正: 監査の生成手順と照合したハッシュ値を保存するか、「真偽値の自己申告で、再ハッシュの記録はない」と明記してください。

**N4. 保存scriptが実行時の内容ではなく、追加したassertは未実行**
- `build-fusion.py:12` は `fusion-boundary-followup.zig` を連結しますが、このファイルは最終レビュー後の追加です（`VM_THREE_CANDIDATES_FINAL_REVIEW.md:46`）。
- `fusion-frozen.json:4` の tests_sha `2b887295…` は、現行 `fusion-tests.zig` の `e00bd45e…`（`final-test-source-hashes.json:10`）と一致しません。scriptは `:8` で再実行を拒否するため、両treeのテストを差し替えた手順は記録にありません。
- `prepare-fusion-performance.py:7-9,12,25-28` の追加assertは、`:4` が `start.json` の存在で先に失敗するため、この作業領域では実行され得ません。RESPONSE `:18` の「postconditionを追加」は検証済みと読めます。
- `document.py:21` の reproduction_note は `build.py` にしか触れていません。
- `fusion-frozen.json` は測定JSONに含まれていません（`document.py:6` の一覧になし）。
- 修正: 「2本のscriptは実行後に編集した版で、追加assertは未実行」「テスト差替え手順は未保存で、最終bytesのSHAが正」と明記し、`fusion-frozen.json` を旧tests_shaの注記付きでJSONへ収録してください。

**N5. 「false/trueの両計数設定・全構成」は debug無効構成では成り立たない**
- 該当: RESPONSE `:19`
- 証拠: `fusion/src/forth.zig:1783` は、`defs.debug_enabled` が偽なら `keep_counting` に関係なく非countedループを選びます。debug無効・最小構成の2周は同じ経路です。
- 修正: 「counted側はdebug有効構成のみ」と限定してください。

**N6. 再入テストは、内側のpairが実行されたことを積極的には確認していない**
- 証拠: `fusion-boundary-followup.zig:52` の内側語は `511 255 AND DROP` でスタック中立です。合否は `failure == null` とscope値の一致（`:40-44`）だけで決まります。
- EMITからcallbackへ直接届く経路は今回未追跡です。既存の `fusion/src/tests/catch_test.zig:334` に同型の前例があることだけ確認しました。
- 修正: テストを直すなら再実行が要るので、今回は確認範囲の限界として文書に書けば足ります。
- あわせて: `docs/VM_ADJACENT_PAIR_PLAN.md:52` の「追加する／実行する」は実施済みなので、過去形にするか結果へのリンクを足してください。

## M1〜M5・L1〜L6 の照合結果

| 項目 | 判定 | 根拠 |
| --- | --- | --- |
| M1 len−1/len | 対応済み | `fusion-tests.zig:12-13` が `data_stack.len - 1` と `len` を使用。len−1は成功・深さ不変・先頭が `-37 & 255`（`:33-35`）、lenは `StackOverflow`・全セル不変・`failed_pc = pc+1`（`:30,36,45`）。push側の検査は `forth.zig:2396` |
| M2 計時前の強制 | 開示済み、N4あり | 事前3構成のELF exit 0は `fusion-followup-results.json` で確認。「start以前」の根拠は真偽値のみ |
| M3 CATCH／BYE／再入 | 対応済み、N5・N6あり | 下記 |
| M4 外れ側 | 対応済み | 53,693,908 − 17,956,448 = 35,737,460。35,737,460×8 − 17,956,448×9 = 124,291,648 で `fusion-frequency-cost-caution.json:76-80` と一致。仮定の算術例という限定も妥当 |
| M5 現状の明記 | 対応済み | RESULTS `:52,54`、`performance/fusion/results.json:31` が `dedicated_screen_unmet` |
| L1 未測定範囲 | 対応済み | RESULTS `:23,36,54,64` |
| L2 15.625ms刻み | 対応済み | `performance-audit.json:219,443,601` が全てtrue |
| L3 監査範囲 | 対応済み | `audit-performance.py:8-9,16,36-59` がSHA照合とstatus再計算を実施。mtimeの限界も明記（`:65`） |
| L4 protocol説明 | 対応済み | `fusion-protocol-annotations.json:4`。凍結protocol自体は古いままという開示どおり |
| L5 Windows生成 | 対応済み | 測定JSON `:12641-12687` に語末比較・tag比較（`cmpb $0x39`）・`andq`・ループ復帰。静的観察という限定も妥当 |
| L6 Linux affinity | 維持 | RESULTS `:22`、監査のscope文 |

M3の内訳:
- **compiled CATCH:** `: FUSION-CATCH ['] FUSION-BAD CATCH 511 255 AND ;` はループ内の `enterCatch`（`forth.zig:1630`）を通り、失敗後にdriverの `resumeCatch`（`:1808`）から同じループへ再入して次のpairを実行します。期待値 `{-4, 255}` は実装と整合します。
- **BYE:** pair直後のBYEで `halted` が立ち、後続の17はpushされません（`fusion-boundary-followup.zig:14-16`）。融合で省かれるのはliteralとANDの間の `halted` 検査だけです。`halted = true` は `words_system.zig:150` の同期BYEのみなので、この省略をテストで踏むことは構造上できません。
- **件数:** 追補後のcoreは全構成で2件増え、skipは不変です。Windowsは1014→1016、debug無効946→948、float無効949→951、最小540→542。Linux ELFは1016/5、948/73、951/44、542/453。

## 計時順序と総数

- 記録上のUTCは直列です。local 08:14:04〜08:31:16.257、VALUE 08:31:16.391〜08:47:43、FUSION 09:01:05〜09:12:45。
- FUSIONのビルド、事前補完、追補の各scriptには、先行計時の `complete.json` を要求するguardがあります（`build-fusion.py:4-6`、`fusion-post-review.py:4-5`）。
- 448実行は 168+168+112 と一致し（`performance-audit.json:176,400,570`）、pilot 6件を足して454です。localのpilotは固定Nのためarithmeticの1件だけです。
- `fusion-protocol-annotations.json` の作成時刻09:08:39はFUSION計時中ですが、文書の書込みであり、protocolの `no_overlap` が許す範囲です。
- processの開始・終了や背景負荷は記録がないので、判定していません。

## 残る検証上の限界

- 独立に再実行したテスト・ビルド・SHA計算はありません。
- 追補後の再計時はなく、候補と計時実行体の同一性は上記N3の範囲までです。
- local/VALUEは標準1条件が未達で残り33条件が未測定、FUSIONはWindows専用予備条件が未達で標準34条件が未測定です。本体VMは不変で、不採用という主張と記録は整合しています。
- VALUE入れ子テスト（`value-nested-tests.zig`）のbacktraceと `failed_pc` の検査はdebug有効構成のみです。
- Windowsの融合経路は静的観察のみです。
