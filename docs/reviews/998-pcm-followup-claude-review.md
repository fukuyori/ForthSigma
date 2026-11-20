レビューした結果、High 2件、Medium 3件、Low 7件の指摘がありました。中心は High の2件で、case 2 は必ず失敗し、case 8 は Ctrl+C の手順が成り立ちません。ファイルの編集・実行はしていません。

## High

**H1. case 2 は `PCM-OPEN` で必ず -24 になります(バグ)**
- 場所: `tests/scripts/pcm-listen.py:57`(`OPEN-PCM` は `{rate} {channels} 32768 PCM-OPEN`)と `:36`(case 2 の rate は 22050)。
- 原因: `src/core/sound_stream.zig:13` の `validCapacity` は `capacity <= hz` を要求します。22050Hz では 32768 は大きすぎて、`words_pcm.zig:44-45` で `InvalidNumber` になります。silent でも audible でも case 2 は動きません。
- 対処: capacity を rate から決めます。22050Hz なら 16384 にします(2のべき乗で、`<= hz` と `*25 >= hz` を満たします)。

**H2. case 8 の Ctrl+C が Python 親プロセスにも届き、手順と記録が壊れます(バグ)**
- 場所: `pcm-listen.py:122-125`。
- 原因: 待機中、Sigma は Ctrl+C を通常どおり処理する状態にします。Windows では `SetConsoleMode(mode|1)`(`src/host_wait.zig:93`)、POSIX では `ISIG=true`(`:128`)です。このため Ctrl+C の CTRL_C_EVENT / SIGINT は、同じコンソール(フォアグラウンドのプロセスグループ)にいる `python` にも届きます。
- POSIX での影響: `subprocess.run` に KeyboardInterrupt が上がり、`Popen.wait` が約0.25秒待ったあと子を kill します。そのため「hello を入力する」段階に進めません。
- Windows での影響: `WaitForSingleObject` は割り込まれないので、子は最後まで動き、子の終了後に KeyboardInterrupt が上がると推測されます(※推測です)。
- 共通の影響: どちらでも `--record` の JSON は書かれず、Python は異常終了します。
- 対処: case 8 の実行中だけ親で SIGINT を無視し、終了後に戻します。ただし POSIX では `SIG_IGN` が exec 後の子に引き継がれ、待機の外での Sigma の Ctrl+C 処理(`src/main.zig:2205` 付近)に影響しうる点は未確認です。

## Medium

**M1. case 8 の音が「continuous」になりません(バグ)**
- 場所: `pcm-listen.py:86` の `BEGIN 0 OFFSET ! 4096 SEND 32768 -1 P @ PCM-WAIT 2DROP AGAIN`。
- 原因1: capacity と同じ 32768 フレームを待つのは「キューが空になるまで待つ」ことです(`words_pcm.zig:146`)。毎回キューが空になってから補充するため、約85msごとに underrun が起きやすくなります。
- 原因2: 毎回 `OFFSET` を 0 に戻していて、4096 フレームは 550Hz の 46.93 周期です。周期の途中で位相が飛ぶので、約11.7Hz のクリックが加わります。
- 対処: 待つ量を小さくします(例: 4096)。データは周期の整数倍にするか、`OFFSET` を続けて進めます。
- `-1` の timeout は無期限の意味で正しく使われています(`runtime_base.zig:28`)。

**M2. case 6 は case 1 と同じ処理で、「完了後の無音」を確かめる区間がありません(制約)**
- 場所: `pcm-listen.py:89` と `:100`。
- 内容: `DRAINED` の直後に `REPORT` から `BYE` に進むので、無音の区間は生まれません。マニュアル(`docs/GRAPHICS_AND_SOUND.md:571`)では、drain はエンジンが消費し終えたことを意味し、デバイスの再生位置ではありません。プロセス終了で末尾が切れても区別できません。
- 対処: `DRAIN` の後に、たとえば `1000 MS` の保持を入れます。

**M3. `verify-pcm-exclusion.py` が確認しているのは `PCM-OPEN` と `SND-PCM-OPEN` の2語だけです(制約)**
- 場所: `verify-pcm-exclusion.py:20-26`。
- 内容: 文書(`GRAPHICS_AND_SOUND.md:575`)は「7組をすべて除外」と書いていますが、残りの6組とほかの `SND-` 語は確認していません。
- `FIND-NAME` は現在の検索順序だけを探します。そのため disabled 版では、検索順序の外の wordlist に語が残っていても見つかりません。この試験で示せるのは「AUDIO が使えず、語が見えない」ことまでで、ビルドから外れていることまでは示せません。
- 期待値自体は正しいです:
  - disabled の `-275`(`words_audio.zig:68`、`defs.zig:1213`)。
  - 解釈時に token を照合する経路(`forth.zig:1315`)と、`EVALUATE` を使って CATCH の中で実行するやり方。

## Low

- **L1(制約)** silent の case 3 では `PLAY` を省くので(`pcm-listen.py:88`)、case 1 と同じ内容になり、MML との混合経路は通りません。case 4 も振幅0の SFX で、混合した結果が無音であることしか確かめられません。
- **L2(バグ寄り)** case 5 は `DISCARDED` を出力しますが、`:137` では確認していません。`UNDERRUNS=` も全ケースで判定していません。説明文の「resume」(`:23`)も実際には先頭からの再生です(`TONE` が `OFFSET` を 0 にします、`:69`)。
- **L3(制約)** `RUN`(`:91`)は、`BODY` と `CLEANUP` の両方が失敗すると `CLEANUP` 側のエラーを捨てます。`CLOSE` が -528 で終わると `P` は残りますが、プロセスはその後終わるので実害は小さいです。`CLEANUP` と `RUN` のスタックの扱いは、成功・失敗のどちらの経路でも正しいです。
- **L4(制約)** タイムアウトと「待ち切れなかった」をどちらも `-528` で THROW しています(`:64`, `:66`, `:84`)。`-528` は busy と同じ番号なので、区別できません。
- **L5(制約)** case 8 は stdout を記録しません(`:125`)。Ctrl+C が `PCM-WAIT` の中で受け取られたか(`CATCH=-28`)を、JSON から確かめられません。`SEND` 内の `PCM-WRITE` の最中に押したときの挙動は未確認です。
- **L6(制約)** パスを `S" ..."` や `SAVESYS <name>` にそのまま埋め込んでいます(`:53`, `:79`, `:94`)。空白や `"` を含むパスでは壊れます。現状の ROOT では問題ありません。
- **L7(未確認)** `CREATE BUF` は最大 264,600 バイトです(case 2)。辞書の空きが足りるかは確認していません。

## 確認できた点(問題なし)

- silent が既定であることは守られています:
  - `--audible` がなければ振幅は 0(`:39`, `:76`)、MML は省略(`:88`)。
  - ただし silent でも実デバイスは開きます。開くときのポップ音の有無は未確認です。
- 全ケースのスタックの扱いが正しいことを確認しました:
  - `SEND` の部分書き込みのループと `+!` の順序。
  - `CLEANUP ( -- ior )`。
  - case 8 の `ACCEPT DUP . CR LINE SWAP TYPE`。
  - `triangle()` の値域(±amplitude)。
- audible の事前確認(`AUDIO?` が `-1`、`:118-120`)は妥当です。
- `verify-pcm-exclusion.py` の enabled 側の期待値 `['0','-1','-1','0']` はスタックの効果どおりです。ただし `REQUIRE-AUDIO` を読み込むだけでデバイスが開くかどうかは未確認です。
