レモン、task998の読み取り専用レビューが終わりました。テストは実行していないので、結果は**未確認**です。

## 結論

- **High: なし**
- **Medium: 1件。** 今回のリング実装の不具合ではなく、採用設計の17行と内部リングの仕様が食い違っている点です。1128で公開語を実装する前に決めておく必要があります。

## Medium: drainの終わりがほぼ必ずunderrunとして数えられる

**設計の約束（`docs/PCM_STREAM_DESIGN.md:15,17`）**
- PCM-STOP mode1は、engineへ取り込み終わるまで待ってから停止要求を出します。
- PCM-UNDERRUNSは「stopped/drainedは数えない」と決めています。

**実装の動き（`src/core/sound_stream.zig:82-86`）**
- `sample()` は、`started && !starving` の状態で `available == 0` になると、無条件に `underruns` を1増やします。

**起きる流れ**
1. drainの最後のフレームは、使い終わるまで保持されます。使い終わった時点で `QUEUED` が0になります。
2. 同じrenderブロックの残りのsampleは空になり、ここでunderrunが1増えます。
3. 停止要求（detach）が `apply` されるのは次のrender境界です。この順番だと、増加はほぼ避けられません。

**producer側で後から1を引く方法は使えません。** consumerが空のsampleを出したのがdetachの前か後かを、producerは区別できないためです。

**対応案（1128で決めること）**
- `Stream` に、producerが書き込みconsumerが読むatomicの `draining` フラグを置きます。producerはdrainを始める前にreleaseで立てます。
- `sample()` はacquireで読み、立っていれば空を数えません。
- `begin()` でフラグを戻します。

この方法でよいか、レモンの判断をお願いします。

## 確認した項目（問題なし）

- **WRITEの区切りをまたぐ読み飛ばし（M1）:** `sample()` の75-81行で、未着のフレーム数 `skip` を次の回の最初に落とし、その後もフレームが足りなければ `phase` と `skip` を0に戻します（87-89行）。M1の手順を `pcm_stream_test.zig:169-178` でたどると、出力は f9（=f8位置）、`underruns == 0` になり、M1と一致します。63行のテストは無音とunderrunになり、設計の35行とも一致します。
- **`completed` の判定（M2）:** `>=` で比べています（133行）。serialは単調に増え、`next == 0` 以降はすべて拒否されます。180行のテストが、後から別のackが来てもtrueのままであることを確認しています。
- **最後のserialをdetach用に残す件:** `next == maxInt` のときは、stream付きのpublishを拒否し、nullのpublishだけを通します（125行）。そのため、どの順に操作しても最後のdetachはできます。
- **render境界でのreset/discard:** `apply` は `render` の最初で1回だけ呼ばれます（`sound_engine.zig:386`）。前のstreamは `discard`（head=tail、phase/skipを0）され、次のstreamは `begin` で状態を戻してから、ackをreleaseします。`begin` が触るのはconsumerの欄とatomicの `underruns` だけで、producerが使う `tail`/`frames` とは重なりません。
- **入力を借りない件:** `write` はすべてのバイトを先に検査し、コピー可能な分だけコピーします。関数から戻った後に入力への参照は残りません。
- **寿命とメモリ順序:**
  - フレームを書いてから `tail` をreleaseし、読んでから `head` をreleaseします。`free()` はheadをacquireで読みます。
  - `pending` は、ackをacquireで確認した後にだけ書かれます。
  - `discard` がproducerの書き込みと同時に起きても、headは単調にしか進まないので、重なりは起きません。
- **PCMなしの経路が以前と同じこと:** requestが0のとき、`apply` はacquireを1回読んで戻ります。`mix(x, 0)` は、`filtered` が返す [-32767, 32767] の値をそのまま返します。renderの関数は1つだけです。stop系のコマンドはPCMに触れません。
- **filtered後の飽和加算:** i32で加算し、[-32768, 32767] にclampします（106-108行）。filterとgainの後に加算しています。

## 設計だけの採用判断（未実装）

- **復元で適用・待機・abandonを足さないこと（29行）:** current StateがPCMを所有していれば、適用前に-528を返し、待機もabandonもしません。appendとLOADに対して無条件のbusy検査を足さない、と明記されています。CLOSEのtimeoutで所有権を保持するので、M2を直した `completed` と組み合わせて矛盾は見つかりませんでした。
- **hostが持つstorageと、exitedより前のbackend後始末（25, 45-47, 55行）:** 順番は「OS資源の解放→exited→join→storageの解放」です。期限を超えたときは所有権を保持し、未停止のthreadが残っている間は再startしません。macOSでは、Stop/Disposeが同期で成功した後にexitedを出します。consumerが参照しているものを先に解放する経路は見つかりませんでした。

## 未確認

- テスト全体（実行していません）。
- `pcm_stream_test.zig:216` の厳密な期待値。これは、初期化直後のPSG（音量レジスタが0）の出力がちょうど0であることを前提にしています。コードを読んだ範囲では0になると推測されますが、実行では確かめていません。
