# CHIP-8音源1164：レビュー評価と対応（2026-11-20）

[設計原文](1164-design-claude-review.md)、[実装原文](1164-implementation-claude-review.md)、[最終原文](1164-final-claude-review.md)を分けて保存する。すべてRead/Glob/Grepのみ。実行検証と外部仕様照合はロクが別に実施した。

| 設計指摘 | 対応・判断 |
| --- | --- |
| H1 同じ境界でtimerを二重減算 | 採用。DIVを処理済み状態として保持し、tick0は処理済み。同時刻TO/RUN0で減らないことと、境界後のqueue追加を手計算で確認 |
| H2 render途中の時刻overflow | 採用。全framesの時刻範囲を除算で前検査し、overflowは状態/出力の変更前に返す。出力先memory不正による-9だけは途中の状態を戻さない例外として文書と負の試験で固定 |
| H3 pattern memory失敗の位置 | 採用。VMのMOVEから-9になることを実行確認。patternを作業bufferへコピー完了後に時刻進行/queue回収。満杯-528を不正pointer-9より先に返す順は明示した |
| M1 Q32積のoverflow | 採用。active時だけ最大800000tickずつ積を計算し、inactiveはmodによる位相進行だけ。pitch255の250境界進行を閉形式と照合 |
| M2 出力値・位相0 | 採用。classicのphase<2^31は+4096、以後-4096。XOはMSB-first、0/4096。既定zero patternは0 |
| M3 同じMODEの再設定 | 毎回resetする案は不採用。「値が変わる設定操作」でだけresetし、同じ値ならphase保持と明記して試験。実機命令の挙動とは主張しない |
| M4 queue layout/順序 | tick/kind/value各8byteと所有pattern16byteの40byte、kind0..3、pattern value0を明示。同tick追加順と予定→即時を検査 |
| M5 TIMER@の副作用 | tickまで進める読取りと公開表に明記。純粋SAMPLEとは分ける |
| Low 丸め/範囲/起動条件 | Q32誤差を数値記録し1step未満を検査。RCA本文とXO仕様を2026-11-20に照合。modern timer>0 gateで原機speaker特性を再現しないこと、rootからの起動を明示 |

実装レビューはHighなし、Mediumの検証不足4件を採用した。512件の未処理patternを残してcompactionし全PCM/状態を照合、timer/patternの予定→即時同tick、active250境界の位相を閉形式と照合、11件の非ゼロRAM送出/cleanup fixtureと両OSの無音実PCMを追加した。既存helperのpartial/full retry・一次例外優先・close再試行/ID保持も確認した。

Lowのstream全体の時刻前検査を採用し、overflowでOPEN前に返ることをfixtureで確認。RENDERの残り時刻ちょうどの成功と超過の原子性を追加した。生成表の--checkはassertに頼らず、python -Oでも実行確認した。

最終レビューはHigh/Mediumなし。残るLowの不正出力memoryによる部分進行は文書で明示済み。Decimal生成と独立doubleのfloor比較に不一致があれば失敗させ、8構成で一致した。[仕様・結果](../CHIP8_AUDIO_FORTH.md)、[全記録](../measurements/2026-11-20-chip8-audio.json)。1164の成功でWindows1165/Linux1166の実聴/性能測定やMac1167を代用しない。
