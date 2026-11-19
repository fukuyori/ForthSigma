# 638 ファイル対応の工程再検討原文

2026-11-19、読み取り専用。実行結果や採否とは区別する。

## 依頼

```text
Follow-up design decision needed from implementation review items1/8. Evaluate restricting NEW EKEY-WAIT to standard stdin (including redirected stdin), returning HostUnavailable before consuming input for non-stdin INFILE-EXECUTE. Existing EKEY/EKEY? in a selected file continue to use the legacy path unchanged (byte readiness, UTF8, literal ESC). INFILE-EXECUTE still saves/restores outer standard decoder but cannot create a new decoder backlog in inner selected files. Reasons: arbitrary FileOps.unread only guarantees1byte, and preserving split UTF8 over scope exit for pipes needs persistent per-handle buffering across KEY-FILE/READ-FILE/position/close/reused file IDs. That belongs to639 nonblocking I/O/multi-source wait;638 task title/API plan focuses standard keyboard and already defers multi-source waiting to639. Alternative implementing that generic file cache now expands638 substantially. Is stdin-only EKEY-WAIT a coherent concrete638 boundary, preserving all existing file behavior? Identify contradictions with docs/ASYNC_CORE_PLAN.md task638 and whether a smaller lossless alternative exists. No file changes/commands. Japanese concise recommendation, no user questions.
```

## 原文

## 結論

stdin専用の `EKEY-WAIT` は、638の範囲として筋が通っています。既存のファイル入力の動作もすべて保てるので、この案を推奨します。ただし、`docs/EVENT_QUEUE_DESIGN.md` に書き換えが必要な箇所が3つあり、決めておくべき点が2つあります。

根拠として読んだのは `docs/ASYNC_CORE_PLAN.md`（40・88〜113行）と `docs/EVENT_QUEUE_DESIGN.md` の全体です。実装コードは読んでおらず、未確認です。

## 638の範囲と合っているか

- `ASYNC_CORE_PLAN.md:40` では、638は標準キーボードのイベントを扱う項目です。「複数の入力源の待機」は後回しと明記され、`KEY-FILE`/`KEY?-FILE` の非ブロッキング化は639に入っています。
- `ASYNC_CORE_PLAN.md:102` の「途中列を保留して次の呼出しへ持ち越す」は、stdin のデコーダについての記述と読めます。
- 選択中のファイルで期限付きの待機をするには、ファイルごとの読み取り可能判定と、ファイルハンドルごとに続く保留バッファが要ります。これはどちらも639の機能に当たります。

このため、計画書との間に矛盾はありません。

## 詳細設計で書き換えが必要な箇所

1. **35行「EKEY-WAITのみ対象iorを戻り値で返す」**：選択中のファイルでも `EKEY-WAIT` が動く前提の書き方です。「戻り値で返す ior は標準入力（リダイレクトを含む）の読み取りエラーに限る。ファイルを選択中は入力を読む前に拒否する」と書き換えます。`EKEY`/`EKEY?` は従来の経路のままという記述は残します。
2. **37行「独立状態を使い」**：内側のファイル用に新しいデコーダを使う意味に読めます。「外側の標準デコーダの状態を退避・復元するだけで、内側のファイルでは保留を作らない」に変えます。
3. **11行の例外の一覧**：`HostUnavailable` をどの値に対応させるかが書かれていません。`-21`（機能不在）として THROW することを推奨します。15行の「新しいホスト口がないときは -21」とも揃います。戻り値の ior にすると、その位置は「対象の読み取りエラー」を表すので、意味が混ざってしまいます。

## 決めておくべき点

- **「標準入力」の判定方法**：`INFILE-EXECUTE` に stdin のファイルIDを渡した場合の扱いです。ファイルIDの値ではなく入力源そのもので判定し、標準入力なら許可して外側のデコーダを共有する、と明記してください。37行の「同じ入力源の入れ子は共有する」と揃えるためです。
- **拒否するタイミング**：入力源の判定を最初に行い、入力も保留も一切触らずに THROW します。結果3セル分のスタックの余地を確認するのは、そのあとです。試験には「拒否したあと、`KEY-FILE`/`READ-FILE` で同じバイトが読める」ことを入れてください。

## もっと小さく、入力を失わない方法はあるか

候補を検討しましたが、どれも推奨しません。

- **選択中のファイルでは `ms<0`（無期限）だけ許可し、それ以外は -21 にする**
  - 期限切れが起きないので、途中のバイトが残ることはありません。
  - ただし、動作は既存の `EKEY` に ior を返す機能を足しただけです。割込みで途中の UTF-8 を失う点も既存の `EKEY` と同じで、新しく入力を守れるわけではありません。
  - 引数の値によって使えたり使えなかったりする仕様は分かりにくく、利点も小さいため見送るのがよいと考えます。
- **通常ファイルだけ許可する**
  - 通常ファイルは期限切れにならないので、読んだ位置を戻せば損失は出ません。
  - しかし、パイプと見分けるには639で作る判定が必要になります。
- **スコープを抜けるときに保留を捨てる、または THROW する**
  - 入力を失うか、既存の動作を変えてしまうため採れません。

## 推奨

stdin 専用で確定し、上の3か所を書き換えるのがよいと考えます。選択中のファイルでの `EKEY-WAIT` は、639の後続タスクとして tque に登録しておくことを推奨します。今回はファイル変更なしの指示なので、登録はしていません。
