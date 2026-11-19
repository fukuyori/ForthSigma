<!-- Claude Code, 2026-11-19, session f355af48-5214-475e-84eb-35e540b3862b. Fixed terminal-recovery snapshot; original response follows. -->

レモン、確認が終わりました。編集・Git 操作・テスト実行・外部アクセスはしていません。固定コピー3件と、リポジトリの `src/host_signal_broker.zig` を読んで判断しています。

## 結論
今回の修正で、**重大・高・中の未解決の欠陥は見つかりませんでした**。前回の【中】1(保留した復元が古い端末状態を書き戻す)と【低】3(Windows で Ctrl+C が効かない)は、コードを読んだ範囲では解消しています。

### コードで確認した内容
- **終了時の順序**: `main.zig:2127-2132` の defer で、`recover()` を `host_input.leave()` より先に呼んでいます。この defer は、フックを戻す defer(`:2118`)より先に実行されます。そのため、`leave` の中でも `beforeInputModeChange` がもう一度 recover を試みます。
- **終了時の recover が失敗した場合**:
  - `leave` が raw から cooked に戻すときに `mode_generation` を進めます(`host_input.zig:181`)。
  - そのあと Runtime の defer(`main.zig:2103`)が recover をやり直します。このとき `NativeScope.end`(`host_wait.zig:134-136`)は、世代が違うので端末スナップショットを捨て、sigaction とハンドラーの復元だけをやり直します。
  - それでも失敗した場合は、メッセージを出して `exit(1)` で終わります。raw の設定を書き戻す経路はありません。
- **enter の基準状態**: `enter()` は、`before_mode_change()` が失敗すると、`saved.get()` / `GetConsoleMode` より前で false を返します(`host_input.zig:195`)。そのため、NS が一時的に変えたモード(ISIG 有効、QUIT/SUSP 無効)を元の状態として保存することはありません。recover が成功したときは、復元が済んでから基準状態を取得します。
- **世代を進める箇所**: raw と cooked の切り替えが実際に起きる `enter` と `leave` だけです。`begin` の途中の巻き戻しでは世代が同じなので、スナップショットは正しく使われます。begin の巻き戻しが失敗した場合も、`failed_scope` → `NativeScope.end` という同じ経路を通ります。
- **Windows の Ctrl+C**: `accepting_interrupts` は begin の前に true、end の前に false になります。`onControl` は、待機の外では 0 を返します(`host_wait.zig:24`)。そのため、ハンドラーの削除を保留している間も、Ctrl+C は後のハンドラー(`utf8_console` など)に届きます。

### 低い指摘(参考、修正は必須ではありません)
1. **新しい試験で回帰を検出できない場合がある**(`host_wait.zig:332-341`)
   - POSIX で標準入力が実際の端末のとき、スナップショットを捨てる処理が壊れても、全ゼロの termios に対する `tcsetattr` が成功することがあります。この場合、試験は通ったうえで、試験を実行した端末の設定まで壊れます。
   - 修正案: 試験の中で `input.input_is_terminal = false` にするだけでは防げません。fd 0 が端末なら試験を飛ばすか、捨てたことを `scope.?.terminal == null` などで直接確かめる形にすることを勧めます。
2. **POSIX で SIGINT が吸収される**
   - SIGINT ハンドラーの復元を保留している間は、`onSignal` が `accepting_interrupts` を見ていません。そのため、待機の外で Ctrl+C を押してもフラグが立つだけで、プログラムは終わりません。
   - これは前回の Windows の指摘3と同じ性質の問題で、今回の修正の対象外です。

## 区別して未確認の事項
- **設計上の指摘**: 上のとおり、コード上では解消しています。
- **実際の OS でのエラー注入**: 未検証です。`tcsetattr`、`SetConsoleMode`、`SetConsoleCtrlHandler`、`sigaction` が実際に失敗したときに、終了時の順序、世代による破棄、Ctrl+C を後のハンドラーに渡すことが期待どおり動くかは確かめていません。
- **ビルドとテストの結果**: 実行していないため未確認です。
