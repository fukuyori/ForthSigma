# 652 EXEC-LIMITED 実装レビュー

レモン、指摘は3件です。Read/Grep/Glob による静的レビューのみで、ビルドとテストは実行していません（テスト結果は未確認です）。

## 1. 【高】Ctrl+C の元位置の計算が、未完成のシーケンスが前にあるとずれる

**場所**
- `src/main.zig:3302` の `consumed = initial + replay.bytes - shadow.length - 1`
- 関連: `src/core/standard_event.zig:178`、`src/host_input.zig:191`

**原因**
- decoder の `read` が中断を返す経路は2つあります。
  - 136行: 3がバッファの先頭にある場合。3を consume するので、上の式で正しく計算できます。
  - 178行: source から3を読んだ直後に返る場合。3はバッファに入らず、その前に読んだ未完成のバイト（ESC、`ESC [`、UTF-8 の先頭バイト）が `shadow.length` に残ります。
- 178行の経路では、3の位置は `initial + replay.bytes - 1` です。ところが式は、さらに `shadow.length` 分だけ前のバイトを指します。
- read の時点のバッファには、必ず未完成の列だけが残っています（完成した列は read の前に event として返るため）。

**再現手順（POSIX、raw の端末）**
1. EKEY を一度使った後など、端末が raw の状態で `: SPIN BEGIN AGAIN ; ' SPIN 0 EXEC-LIMITED` を実行します。
2. 実行中に Esc を押し、次に Ctrl+C を押します。
   - 前の poll では、ESC だけが queue に入ります（候補なし）。
   - 次の poll の view は `[ESC, 3]` になります。clone の `escape_at` は今の時刻なので、ESC は未完成のまま残ります。続いて3を読んで178行で中断します。
   - 計算結果は `consumed = 0+2-1-1 = 0` で、origin は `.queued 0`、つまり ESC を指します。
3. 結果
   - Debug/ReleaseSafe では、`host_input.zig:191` の assert で panic します。
   - Windows の record の経路では、ESC の record に cancelled が付いて ESC が消えます。Ctrl+C の record は残るので、次の poll でもう一度中断します。CATCH で続行したプログラムには2回目の -28 が届き、キーを使う側でも同じ3がまた Ctrl+C として扱われます。これは「文字を捨てない」に反します。
   - Alt+Ctrl+C を ESC 0x03 で送る端末でも同じことが起きます。

**最小修正**
- `ExecutionReplay` に `last_three: bool` を追加します。
- `read()` の先頭で false にし、byte packet を返すときに `packet.value == 3` を設定します（`.restart` の packet では false のままです）。
- 計算式を次のように変えます。

```zig
const total = initial + replay.bytes;
const consumed = if (replay.last_three) total - 1 else total - shadow.length - 1;
```

  - paste 中に読み込まれてバッファに入った3は、136行で中断として扱われる前に必ず次の read が入ります。このため、フラグで2つの経路を区別できます。
- 試験として、`"\x1b\x03"`、`"\x1b[\x03"`、`"a\x1b\x03z"` で3だけが消え、ESC などは残ることを追加してください。

## 2. 【中】EXEC の終了時に検出した中断が捨てられる

**場所**
- `src/host_wait.zig:284`（入れ子の end での `takeInterrupt`）
- `src/core/execution_control.zig:87-88`

**原因**
- `finishing == UserInterrupt` で、`failure` が自分の -280 以外の場合（通常の THROW、外側の入口の StepLimit）、88行は failure だけを返します。
- 中断印は `endExecution`/`endInput` の swap で既に消費されているので、Ctrl+C が失われます。
- 一方で、自分の -280 のとき（89行）は UserInterrupt が優先されており、扱いが揃っていません。

**再現手順**
1. fake host で `end` が UserInterrupt を返すようにし、`: BAD -123 THROW ; ' BAD 10 EXEC-LIMITED` を実行します。結果は Thrown だけになります。
2. 実機では、次のどちらかで起きます。
   - poll 間隔（最大1023 op）の間に SIGINT が届き、その間に通常の THROW が起きる場合。
   - 入れ子で、外側の予算が尽きると同時に Ctrl+C が来る場合。内側の end（284行）が中断印を取り、StepLimit を返します。外側は -280 にするので、中断が消えます。

**最小修正**
- `host_wait.zig:284` を削除します。入れ子の end では中断印を残し、外側の poll または end に検出させます。深さ0の場合は、`endInput` の301行が既に検出しています。
- `execution_control.zig:88` を次のように変えます。

```zig
if (failure) |err| if (!own_limit) return if (finishing != null and err != error.StepLimit and err != error.Quit) finishing.? else err;
```

  - 通常の THROW より -28 を優先します。CLI の StepLimit と Quit はそのまま優先します。
  - この優先順位は設計書に書かれていないので、採用した場合は優先順位を設計書へ追記してください。

## 3. 【低】replay の作業領域が大きく、解決できない3があると poll のたびに作り直す

**場所:** `src/main.zig:3245-3248`、`src/main.zig:3277`

**内容**
- `ExecutionReplay` は5120要素の配列を3つ持ち、`@splat(null)` で初期化しています。
- ※推測（概算）です。Packet が約56B、`?ExecutionOrigin` が約24B とすると、1回の呼出しで約530KB をスタックに確保して初期化します。
- poll は、EVALUATE/CATCH/EXEC の Zig 再帰が深い位置から呼ばれます。
- bracketed paste 内の3のように、中断にならない3が queue に残ると、`candidate()` は真のままです。そのため、1024 op ごとにこの初期化と再生を繰り返します。正しさの問題ではなく、性能の問題です。

**最小修正**
- 上限を実際の最大値に合わせて約400にします（core の保留 34、deferred、unread、utf8 4、view 320）。またはモジュールの static に置きます。
- 必要であれば、前回の view と同じ内容なら再生を省きます。

## 確認して問題が見つからなかった点

| 確認項目 | 確認した内容 |
|---|---|
| 外側の owner の巻き戻し | 内側は復元せずに `depth=index` で返り、外側で -280 になります |
| CLI 優先、同時に尽きた場合の順序 | CLI → 外側 → 内側の順です |
| CATCH との関係 | 通常の CATCH と compiled catch（`forth.zig:1847`）は StepLimit を通過させます |
| 明示の `-280 THROW` | clearStop の後に StepLimit として外へ出ます |
| 失敗後に残る stop | 新しい StepLimit は毎回 stop を設定し直すので、悪影響はありません |
| ネイティブの後始末 | slurp の errdefer、csv の defer、openInPath、mkdir、endSourceFile。-28/HostFailed が増えても漏れはありません |
| POSIX の cooked 入力 | 20ms の poll と中断確認があるので、SA_RESTART でも止まりません |
| NS/audio | 入れ子のときは pollExecution に切り替わります |
| Broker | 排他です |
| Windows の surrogate | cancelled で high を切ります。view と next() は同じ判断をします |
| 予約の上限 | Windows: queued + 4×records + 32 ≤ 256。view も 320 以内です |
| leave 時の文字保持 | 保持されます |
| 再生の順序 | core の保留 → deferred → lookahead/unread → utf8 → host の順で、`sourceRead`/`terminalStandardEvent` と一致します |
| 画像 | appendImage と encode に影響しないこと（テストあり）。LOAD は別の State を経由した append です |
| debug=false でのビルド除外 | `debug_builtins` と Empty 型で除外されます |
| State 監査表 | `execution` の行は追加済みです（`CORE_EXTENSION_WORKER_STATE_AUDIT.md:111`） |