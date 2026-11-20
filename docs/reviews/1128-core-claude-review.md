# PCM 1128 実装レビュー結果（読取りのみ）

**結論：High と Medium に当たる実装上の欠陥は見つかりませんでした。** 確認は Read/Grep で行い、ビルドとテストは実行していません（未実行）。採用済みの方針（ms0/ready でも poll と scope を行う、attach ack が進んだ後は前の phase に戻さず書込みを続けられる、-587、256KiB を起動時に確保）は欠陥として扱っていません。

## 観点ごとの確認結果

| 観点 | 判定 | 根拠 |
|---|---|---|
| mailbox の上書き | 問題なし | `tryDetach` は前の request の ack を待ってから publish します（`sound_stream_session.zig:47`）。`publish` も ack 前は Busy を返します（`sound_stream.zig:126`） |
| 解放済み storage の再初期化 | 問題なし | `Stream.init` が transport を上書きするのは phase=free のときだけです。free になるのは `commitClose` からだけで、その経路は「detached かつ completed」（CLOSE が成功した場合と、refresh で stopped になった場合）に限られます。host 再起動時は `Engine.init` で Control ごと作り直されます |
| OPEN の ack 前に WRITE と UNDERRUNS | 問題なし | WRITE は opening でも書けます。UNDERRUNS は「ack 未完了かつ detach 前」なら 0 を返します（`words_pcm.zig:78`） |
| STOP drain の timeout と中断 | 問題なし | detach の publish 前に timeout や中断で抜けた場合だけ draining を false に戻します。publish 後は detached=true なので要求が残り、draining も保持されます（`words_pcm.zig:130`）。後の STOP は `tryDetach` の detached 分岐で ack を確認できます |
| CLOSE の再試行と遅れて届く ack | 問題なし | timeout は -528、中断は -516 を返し、どちらも phase=closing と ID を保持します。再度の CLOSE では `beginClose` が冪等で、`tryDetach` が completed を返した時点で commit します |
| scope 終了時の中断と handle 保持 | 問題なし | 待機の結果が成功でも、`ops.end` が UserInterrupt を返せば -516 になり、commit しません（`words_pcm.zig:104-111`）。host の失敗は中断より優先されます（`words_pcm.zig:131-135`）。試験は `pcm_words_test.zig:156-177` です |
| 全範囲の検査とスタックの原子性 | 問題なし | frames×ch×2 の overflow を検査し、`memoryAddress` で全 byte 範囲を検査してから copy します。frames=0 はメモリを参照しません。THROW の経路はすべて `result` より前にあります。QUEUED と UNDERRUNS は push する 1 枠を事前に確認しています |
| scope の構造 | 問題なし | 1 回の呼出し全体を 1 つの begin/end で覆い、3ms ごとに scope を外すことはしません。`audio_scope_ops` は audio ビルドなら debug/extension がなくても設定されます（`main.zig:3688`）。入れ子では同じ machine の depth を加算し、内側の end は中断を消費しません（`host_wait.zig:283`）。raw 入力は `executionRawPoll` で保持されます |
| 古い ID・他 State の ID | 問題なし | `owned` は handle の一致、owner の一致、phase≠free を照合し、一致しなければ handle を 0 に戻して -521 を返します |
| 完全復元と append | 問題なし | `restore` と `restoreFresh` は prepare の前に -528 を返します。prepare 自体は変更していません。`appendImage` と LOAD の一時 State は handle に触れません |
| host 再起動と storage の寿命 | 問題なし | `freeStorage` で next_id を `next_pcm_id` へ退避し、`start` で戻します。shutdown が失敗した場合は failed のまま storage を保持し、再起動しません |
| 登録 | 問題なし | enum の末尾に 7 語、`definitions` の末尾、`library_words`、英語 help 14 件、ja.tsv の 14 件（件数のみ照合） |

## Low（今は対応不要。tque に登録する候補）

1. **stale handle による復元拒否**：host が process 内で再起動した後、古い handle が残っていると、完全復元が -528 で拒否されます。現状 shutdown は終了時だけで、current State を完全復元する Forth 側の経路も見当たりません。`PCM-CLOSE` を呼べば -521 が返り、同時に handle も消えるので回復できます。直す場合は、`image_restore.restore`/`restoreFresh` の検査を「handle≠0 かつ session が一致する」に絞ります。
2. **State 破棄時の PCM の取り残し**：PCM を持つ State を CLOSE せずに破棄すると、session が取り残され、以後の OPEN は -528 になります。現在 writer を共有する別 State は LOAD の一時 State（`main.zig:2826`）だけで、これは PCM を持たないため、今は発生しません。worker VM の監査（1053）で、State の破棄時に CLOSE するか、audio を禁止するかを決めることを推奨します。

## Medium 相当の試験不足（実装の欠陥ではありません）

設計の完了条件に対して、`pcm_words_test.zig` で確認できなかった項目です。

- **STOP の要求保持**：detach の publish 後に STOP が timeout する場合です。期待値は false,0 で phase=stopping を保持し、WRITE は -534、後の STOP で -1,0 です。`audio_wait_samples` を、attach ack が届き detach ack が届かない値にして再現します。
- **ack 前の UNDERRUNS**：`audio_wait_samples=0` で OPEN し、consumer に underrun を起こさせても、UNDERRUNS が 0 を返すこと。
- **host 再起動後の ID**：`host_audio` の silent fixture で start→OPEN→CLOSE→shutdown→start と進め、次の ID が前の ID より大きいこと。
- **実 host の scope**：fake でない `execution_host_ops` を使った試験は見当たりませんでした。必要なのは depth が 0 に戻ること、入れ子で中断が外側に残ること、raw 入力が保持されることです。
- **未確認**：audio=false での語群除外と、HELP の英日全語照合が別の試験で網羅されているかは確認していません。

High と Medium に当たる実装の修正は不要と判断します。修正指示はありません。
