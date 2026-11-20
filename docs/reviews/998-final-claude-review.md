レモン、`src/core/sound_stream.zig` と `src/tests/pcm_stream_test.zig` を読んでレビューしました。指示どおりテストやコマンドは実行していないので、テスト結果は**未確認**です。

## 結論
- **High: なし**
- **Medium: なし**

## 確認した項目

**draining(意図した drain の空出力を数えない仕組み)**
- フラグは producer 側が持ち、release で書き込みます。consumer は `sample()` の中で acquire で読みます(85行)。
- フラグが立っている間に出力が空になっても、`underruns` も `starving` も増やさず、`phase` と `skip` だけを0に戻します。
- `begin()`(61-67行)と `discard()`(68-72行)は `draining` を戻しません。begin で戻さないという要件どおりです。
- 取り消しでフラグが下りた後は、`started && !starving` の状態なので、次に空になった時点でまた underrun として数えます。
- 304行のテストは underrun が1になることを期待しており、この動きと合っています。295-299行のテストも、最後のフレームを使い終えた後の空8回が0件になることを確認しています。

**u32 化と Cortex-M0+**
- 複数のスレッドから触る値はすべて32bit以下の atomic で、使っているのは load と store だけです(`head`、`tail`、`underruns`、`draining`、`request`、`acknowledged`)。fetchAdd などの読み書き一体の操作はありません。
- `underruns` は consumer だけが書き、`+| 1` で上限に張り付くので、一周して0に戻ることはありません。
- `phase` と `skip` は u64 のままですが、consumer しか触らない普通の変数なので、64bit atomic は要りません。
- テストの `@as(u64, ...)` と u32 の値の比較は、型が広がる方向なので問題にならないと推測されます。※推測です。コンパイルでは確かめていません。

**serial が一周しないこと**
- `next == maxInt` のときは、stream を付けた publish を `IdentityExhausted` で拒否し、null(detach)だけを通します。
- その後は `next = 0` になり、以後の publish はすべて拒否されます(129-130行)。
- 133-136行のテストでこの流れを確認しています。

**`completed` の比較**
- `completed` は `acknowledged >= serial` で判定します(137行)。serial は単調に増えて一周しないので、この比較は成り立ちます。0 は false になります。

**読み飛ばし(skip)の扱い**
- 前の回に読み飛ばせなかった分は、次の回の最初に、届いている分だけ落とします。それでもフレームが足りなければ、`phase` と `skip` を0に戻します。
- `phase` は毎回出力レートで割った余りに戻すので、上限を超えません。
- 169-178行のテスト(WRITE の区切りをまたぐ読み飛ばし)の期待値と合っています。

**寿命とメモリ順序**
- `apply` は render の最初で1回だけ呼ばれます(`sound_engine.zig:386`)。前の stream を discard し、次の stream を begin してから ack を release で書きます。
- `pending` は、producer が ack を acquire で確認した後にだけ書き換えます。
- `discard` が producer の書き込みと同時に起きても、head は前にしか進まないので、producer が書く場所と重なりません。

## 1128(公開語の実装)で守る必要がある順序
欠陥ではありませんが、`draining` を下ろすのは producer の責任になります。そのため、公開語の側で次の順序を守る必要があります。
- drain が成功した後は、detach の `completed` を確認するまで `draining` を下ろさない。先に下ろすと、detach が適用されるまでの間の空出力を underrun として数えます。
- 同じ stream を再び OPEN するときは、publish より前に `draining` を下ろす。下ろし忘れると、次の再生で underrun が数えられないままになります。

## 未確認
- テスト全体(実行していません)。
- `begin` が `draining` を戻さないことを直接確かめるテストはありません。コードではそう動くことを確認しています。
- `pcm_stream_test.zig:216` の期待値。初期化直後の PSG の出力がちょうど0であることが前提で、前回のレビューから確かめていません。
