レモン、静的レビューが終わりました。結果を報告します。

# task998 PCM内部コンポーネント レビュー（`src/core/sound_stream.zig` / `src/tests/pcm_stream_test.zig`）

**確認の範囲**
- 読んだもの: 上の2ファイル、`src/core/sound_engine.zig` の `Ring` と `Engine.render`、`docs/PCM_STREAM_DESIGN_PROPOSAL.md` の該当行。
- このセッションでは Bash を使っていないので、テストは実行していません。テストの結果は**未確認**です。下の内容はすべてコードを読んだうえでの指摘です。
- `src/forth_test.zig:96` で `tests/pcm_stream_test.zig` が import されていることは確認しました。

## High

なし。SPSC のメモリ順序、ringの寿命、u32 の wrap、デコード、bounded copy について、データ競合や解放後アクセスにつながる箇所は見つかりませんでした（根拠は後半に書きます）。

## Medium 1: ダウンサンプル時、WRITEのタイミングで出力位置が永久にずれ、underrunとしても数えられない

**場所:** `sound_stream.zig:67-69`

```zig
const consumed: u32 = @intCast(@min(advance, available));
self.head.store(head +% consumed, .release);
if (advance > available) self.phase = 0;
```

`advance > available` のとき、まだ届いていない分の進みを捨てています。そのあと producer がフレームを追加すると、本来は読み飛ばすはずのフレームが再生されます。無音は出ないので、underrun にも数えられません。

**手でたどった例（192000→48000、比は4:1）:**
- 全部を先に書いた場合、出力は f0, f4, f8 になります。
- f0..f4 を書いて2回 sample し、そのあと f5..f8 を書いた場合:
  - sample2 は f4 を出し、advance=4、available=1 なので head=5、phase=0 になります。
  - sample3 は **f5** を出します（正しくは f8）。
- これ以降、入力1フレーム分ずれたままになります。

設計案（29行）には「WRITE分割で結果が変わらないことを試験する」とあり、この挙動はそれに反します。

**修正案:** 未着の分を、consumer だけが持つ値として次回に繰り越します。underrun になったら、phase と一緒に繰り越し分も捨てます。

```zig
    // Consumer-only: input frames the rational clock has passed before they arrived.
    skip: u64 = 0,

    pub fn sample(self: *Stream) Frame {
        var head = self.head.raw;
        var available = self.tail.load(.acquire) -% head;
        if (self.skip != 0) {
            const dropped: u32 = @intCast(@min(self.skip, available));
            head +%= dropped;
            available -= dropped;
            self.skip -= dropped;
            self.head.store(head, .release);
        }
        if (available == 0) {
            if (!self.starving) {
                const value = self.underruns.raw;
                self.underruns.store(value +| 1, .release);
            }
            self.starving = true;
            self.phase = 0;
            self.skip = 0;
            return .{ .left = 0, .right = 0 };
        }
        self.starving = false;
        const result = self.frames[head % self.frames.len];
        self.phase += self.input_rate;
        const advance = self.phase / self.output_rate;
        self.phase %= self.output_rate;
        const consumed: u32 = @intCast(@min(advance, available));
        self.head.store(head +% consumed, .release);
        self.skip = advance - consumed;
        return result;
    }
```

- 既存テストとの関係（手でたどった結果）:
  - 63行のテストは、sample2 の後に skip=3 が残ります。sample3 は available=0 で underrun になるので、無音0 が返り、テストは通ります。
  - 42行のテストは advance が available を超えないので、影響を受けません。
- 追加するテスト: 上の例で、3回目の sample が `f8` になることを確かめ、`underruns == 0` も確かめます。f5 だけを足した場合は、無音になって underrun が1増えることも確かめます。

## Medium 2: 後で別の publish をすると `Control.completed` が二度と true にならない（ringが解放されないまま残る）

**場所:** `sound_stream.zig:101-103`

```zig
return serial != 0 and self.acknowledged.load(.acquire) == serial;
```

**起きる流れ（設計案22行の CLOSE timeout→busy→所有権を保持、という流れ）:**
1. CLOSE が timeout します。
2. consumer が遅れて ack します。
3. 利用者が別の PCM-OPEN をします。`request == acknowledged` なので、`publish` は成功します。
4. `acknowledged` が新しい serial に進むので、`completed(close_serial)` はこの後ずっと false になります。

その結果、古い stream は解放できないまま残ります。解放後アクセスにはなりませんが、寿命の管理として誤りです。

**修正案:** serial は単調に増え、`next` が 0 になった後は `publish` がすべて拒否されます。このため、大小比較で正しく判定できます。

```zig
    pub fn completed(self: *const Control, serial: u64) bool {
        return serial != 0 and self.acknowledged.load(.acquire) >= serial;
    }
```

**追加するテスト:** 次の順に操作して、最後に `completed(closing)` が true であることを確かめます。

`publish(&s)` → `apply` → `closing = publish(null)` → `apply` → `publish(&s2)` → `completed(closing)`

## 問題なしと判断した項目

- **SPSC:**
  - `tail` は producer だけが書き、`head` は consumer だけが書きます。
  - producer はフレームを書いてから `tail` を release で store し、consumer は acquire で読みます。
  - consumer はフレームを読んでから `head` を release で store し、producer の `queued()` は acquire で読みます。これで、上書きより先に読み終わることが保証されます。
  - この構成は `sound_engine.Ring` と同じです。
- **保持中のフレーム:** advance=0 のあいだ head は進まないので、出力中のフレームが上書きされることはありません。`queued()` に保持中のフレームが含まれることも、設計案19行と一致します。
- **u32 wrap:** `frames.len` は 65536 以下の2の冪なので、2^32 を割り切ります。このため `(tail +% i) % len` で位置が飛ぶことはありません。`queued`/`free` も、`tail - head ≤ len` が成り立つ限り正しい値になります。
- **phase のオーバーフロー:** phase は output_rate 未満、input_rate は 192000 以下なので、u64 に収まります。
- **デコード:** `readInt(i16, bytes[at..][0..2], .little)` はアラインメントに依存しません。符号付きの値もテスト（63行）で検証されています。
- **bounded copy:** 乗算のオーバーフローを検査しています。`requested` の全バイトを先に検査します。コピーするのは `fit ≤ free ≤ len` 個までで、入力の参照は関数から返った後に残りません。
- **Control:**
  - `pending` は、`request == acknowledged` を acquire で確認した後にだけ書かれます。consumer が `pending` を読むのは `request` を acquire した後で、`acknowledged` を release する前です。したがって `pending` へのアクセスは競合しません。
  - serial の上限については、最大値を detach 専用に残す設計になっています。u64 なので、実際に使い切ることはないと判断しました。

## Low（参考）

- `output` の上限が検査されていません（`init` は 0 だけを拒否）。Medium 1 の修正を入れれば、どの値でも正しく動きます。ただ、host は 48000 固定なので、`8000..192000` に制限しておくほうが安全です。
- 並行ストレステスト（77行）は 48000:48000 だけです。non-unity 比（44100→48000 など）で、取りこぼしや重複がないことを並行状態で確かめるテストはありません。

テストの実行が必要であれば、PowerShell から `zig build test` を実行した結果で確認します。修正は、レモンから指示を受けてから行います。
