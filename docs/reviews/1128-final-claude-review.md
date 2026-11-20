# task1128 最終レビュー（Read/Grep のみ）

**結論：新しい High・Medium の欠陥は見つかりませんでした。** ビルドとテストは実行していないので、テストが通るかどうかは確認していません。ここに書いたのは、コードを読んで判断した結果です。

## 前回のレビューで不足していたテストの確認

| 項目 | 判定 | 根拠 |
|---|---|---|
| detach 要求中の STOP の timeout | 足りている | `pcm_words_test.zig:298-321`：`render` を 1 回呼んで OPEN の ack だけを進めます。`audio_wait_samples=0` で STOP すると `0 0` が返り、phase は stopping のままです。この間の WRITE は `-534` になります。そのあと ack が届くと STOP は `-1 0` を返し、CLOSE は stopped からそのまま commit します（`owned` の中の `refresh` で stopped に移ります） |
| ack 前の UNDERRUNS | 足りている（注記あり） | `pcm_words_test.zig:323-337`：古い値 99 を入れておいても `0 0` が返ります。`words_pcm.zig:79` の「ack 未完了かつ detach 前なら 0」の分岐を直接確かめています。consumer が実際に underrun を起こす経路は通っていませんが、その件数は `Stream.init` が 0 に戻すので、この分岐を確かめる目的には足りています |
| host 再起動後の ID と storage | 足りている | `host_audio.zig:1163-1178`：silent モードで start、open、shutdown の順に進め、storage の長さが 0 になること、再起動後の ID が前より大きいことを確認しています。ID は `freeStorage` で `next_pcm_id` に退避され（`:201`）、`start` で戻されます（`:112`）。rollback の経路でも `Engine.init` の直後に退避するので、ID は前の値を引き継ぎます |
| 実際の native scope | 足りている | `main.zig:4782-4845`：fake でない `executionBegin/Poll` と、`host_wait` の実際の depth 管理を使っています。`Fake.step` は guard が外れていると `.host_failed` を返すので、呼出し全体が 1 つの scope に入っていることを確かめられます。入れ子の場合は次の順に進みます。内側の `finish` が `std.c.raise(.INT)` を送ってから `endExecution` で depth を 2 から 1 に下げ、`endInput` は depth が 0 でないので中断を消費しません（`host_wait.zig:298`）。CLOSE は `0` を返し、外側の `endExecution` が `UserInterrupt` を返します。Windows では中断を送らず、入れ子の depth の対応だけを確認します |
| OPEN の前に待機の能力を確認 | 足りている | `words_pcm.zig:46`：`audio_scope_ops`、`standard_clock`、`audio_wait_fn` のどれか 1 つでも欠けていれば、`engineOf` と session に触る前に THROW します。スタックは元のまま残ります。テストは `pcm_words_test.zig:280-296` で、storage が空のときに `-524` が返り、handle は 0、phase は free であることも確認しています |

## その他の確認事項

- **host の確保と解放**：起動時の確保に失敗した場合、storage は `&.{}` になり、OPEN は `-524` を返します。shutdown が join に成功し、`cleanup_ok` も真の場合に限って `freeStorage` を呼びます。失敗したときは storage を保持し、再起動もしません（`host_audio.zig:143-153, 190-197`）。問題ありません。
- **raw 入力を失わないこと**：audio の待機は `.read_input` を返しても何もしません（`words_pcm.zig:155`）。入力の保持は `executionRawPoll`（`main.zig:3334`）が受け持ちます。今回の native テストは `input_is_terminal=false` で動かしており、raw 入力の経路は通りません。raw 入力を再生する既存のテストが PCM でもそのまま当てはまるかは**未確認**です。
- **enum の登録と除外**：7 語は `Builtin` の末尾に追加されています（`defs.zig:1164-1170`）。`definitions` と `library_words` でも末尾に追加されています。`words_audio.words` に含まれるので、audio=false のビルドでは `audio_builtins` から除外されます（`defs.zig:65,76`）。help は 14 件、ja.tsv も 14 件で、件数は合っています。語ごとの内容の照合は**未確認**です。
- **image の復元**：`restore`/`restoreFresh` は prepare の前に `-528` を返します（`image_restore.zig:13,21`）。前回から変わっていません。

## Low（テストの注記）

1. native テストは depth が 0 に戻ったことを `inputGuardActive()` で確かめています。`execution_depth` そのものは見ていません。ただ、depth が合っていなければ `endExecution` が `HostFailed` を返すので、実際には検出されます。
2. host 再起動のテストは `Session.open` を直接呼んでおり、Forth の語（State の handle）を通る経路ではありません。再起動の前に CLOSE もしていません。storage の寿命と ID を確かめる目的には足ります。
3. 前回の Low 2 件（古い handle があると復元が拒否される件、State を破棄したときに session が残る件）は変わっていません。

## 実機の作業とフィクスチャの区別

- **フィクスチャで確認している範囲**：上に挙げたテストはすべてフィクスチャです。`pcm_words_test` は fake の clock、scope、`render` を使います。`host_audio` は silent モードで、デバイスを開きません。`main.zig` の native テストは、OS の signal とコンソールの handler は実物ですが、audio は `Engine.render` を直接呼ぶ fake で、デバイスはありません。
- **実機での作業が必要な範囲（テストでは確かめられません）**：
  - 実際のデバイス（Windows の waveOut、Linux の ALSA/pipe、macOS の CoreAudio）での再生と、聞いて分かるほどの underrun
  - Windows の端末で実際に Ctrl+C を押して、PCM-WAIT、STOP、CLOSE を中断すること
  - raw モードの端末で待機している間のキー入力が失われないこと

修正が必要な High・Medium の欠陥はありません。
