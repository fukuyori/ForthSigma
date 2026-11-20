# 1170/1171 最終レビューへの追加確認

ファイルを読んで確認しただけで、編集・実行・ネットワーク接続はしていません。

## 結論
- High：なし
- Medium：なし。前回の Medium 3件はすべて解消しています。

## Medium 3件の確認

**M1. 古い「待ち」の記述と矛盾する経過の記述：解消**
- `docs/ZX_SPECTRUM_AUDIO_FORTH.md` から、前回指摘した古い文はなくなっています。
  - 「物理再試験待ち」
  - 「原因特定・修正と再確認は未実施」
  - 「物理Ctrl+C後…は未確認」
- 次の3か所が同じ現在状態を示しています。
  - 仕様書の冒頭「最新の受け入れ状況」（7行目）
  - 仕様書の表（96–97行目）
  - 仕様書の「採否と残る作業」（112行目）
- 現在状態は「Windows1170完了、Linux1171は最終記録/レビュー中」です。
- 試行ごとの経過は JSON に残す、と11行目で分けています。

**M2. 物理試行2回のうち成功1回、成功例は試験用に非可聴の周期を変えたもの：解消**
- 仕様書：
  - 97行目に「物理試行2回のうち、試験設定を変えた2回目で成功」とあります。
  - 104行目に、toneB/C を 4095、noise を 31 に変えたこと、R7=62 なので toneA は変わらないこと、元の重い設定で成功したとは扱わないことが書かれています。
- review-response：
  - 21行目に、再開の了承、r2 の結果、レモンのＯＫ、成功1回/2回が追記されています。
  - 27行目に、M1〜M3 への対応内容が書かれています。
- JSON：
  - `linux_interrupt_retry`（9641–9654行）は exit 0、CATCH=-28/handle0、REPLAY-OK underrun0、DEPTH0 で、レモンのＯＫも入っています。
  - `linux_physical_attempt_summary`（9655–9662行）は attempts 2、successful_attempts 1 で、成功時の設定が Linux 専用の試験設定であることが書かれています。
  - 両方の binary hash は、初回失敗の記録と同じ `28b12e5b…` です。

**M3. 捕捉はタイミング次第、初回失敗時の cleanup は未確認、診断は物理受け入れではない：解消**
- 捕捉がタイミング次第であること：
  - 仕様書104行目に書かれています。
  - JSON の 8396行目の status と、`signal_scope_limit` にも書かれています。
- 初回失敗時の cleanup が未確認であること：
  - 仕様書100行目に「明示的cleanupが行われたとは主張しない」とあります。
  - JSON の `original_profile` と 8396行目にも同じ趣旨が書かれています。
- 診断が物理受け入れではないこと：
  - 仕様書102行目と review-response 19行目に書かれています。
  - JSON では `diagnostic_is_not_physical_acceptance: true`、`physical_acceptance: false`（9637行）、`linux_signal_diagnostic.scope` が該当します。

**タスクの状態**
- 1171 は「最終記録/レビュー中」で、JSON 冒頭の status（8行目）とも一致しています。
- `tasks_snapshot` では 1168/1171/1172 がすべて todo、1168 は effective 50 です。
- Mac1172 と親1168 は未完了とする記述で、どのファイルもそろっています。

## Low（対応は任意）
- `linux_interrupt_first_failed.human_listening_result` が `"pending"`（9499行）のままです。失敗した回なので、この後に実聴は行われません。「pending」だと実聴待ちと読めるため、「not applicable（failed run）」のような値のほうが誤解がないと考えます。
- JSON の準備段階の記録に、当時の状態のまま次の記述が残っています。
  - `"Prepared, not launched"`（9487行、9639行）
  - Windows 48K の `"fix replay still pending"`（8394行）
  - 試行ごとの記録として残すという方針どおりですが、記録時点の状態であることがキー名などで分かれば、読み違いを防げます。
- 仕様書104行目の「初回と同じtoneA-only設定の実聴PCM」は、どの PCM と照合したかが分かりにくい表現です。JSON の `comparison_reference` を見ると、照合先は Windows 128K 準備時の profile です。

## 残る制約（指摘ではありません）
- Linux は WSL2/RDPSink での確認で、物理 Linux や ALSA 直結は未確認です。
- 待機区間の外で Ctrl+C を押すと、プロセスが終了し得ます。native 側の捕捉範囲は変えていません。この件が tque に登録されているかは未確認です。
- 元の重い設定では、物理 Ctrl+C の成功は得られていません。
- 中断したストリームの underrun は調べていません。
- 初回送出の修正で解消したのは、今回再現した供給不足だけです。任意のホスト負荷で欠落しないことは保証しません。
- r2 の実施時刻は記録されていません。残っているのは結果を記録した時刻（`outcome_recorded_at`）だけです。
- Linux1171 は最終レビュー待ちです。Mac1172 と親1168 は未完了のままです。
