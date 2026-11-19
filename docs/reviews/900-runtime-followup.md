<!-- Claude Code, 2026-11-19, session 3aef4c04-a62e-4e4d-9321-315ab058fd03. Fixed recovery snapshot; original response follows. -->

レモン、再確認の結果です。編集、Git 操作、テストの実行、外部アクセスはしていません。固定コピーのコードを読んで判断しています。指摘1の根拠を確かめるため、リポジトリの `src/host_input.zig` と `src/host_resize.zig` も読みました。

## 前回の指摘の状況(コード上で確認。ビルド・試験・OS での動作は未確認)
- **1【高】end 失敗後の所有**: 対応がコードにあります。
  - `native_scope` と `recovery_broker` はプロセスが持っています(`host_wait.zig:146-147`)。
  - 次の待機で `beginNative` が、終了時に main の defer(`main.zig:2103`)が recover します。
  - `installed`/`console`/`terminal` によって、復元は何度呼んでも安全です。
  - 復元の失敗を中断より先に報告します(`host_wait.zig:213-214`)。
  - begin の巻き戻しが失敗した場合は `failed_scope` に残します(`host_signal_broker.zig:32-34`)。
  - ただし新しい問題が1件あります(下の1)。
- **2 exit 経路**: `flushOutput`、`utf8_console.finish`、`resize_scope.end` を明示的に呼んでいます(`main.zig:2108-2110`)。`resize_scope.end` は sigaction を戻すだけで、Storage には触れません。
- **3 台帳のコピー**: `bound_address` の照合でコピーを拒否しています。`tables` の減算は `closed` によって一度だけです。
- **4 phase**: atomic(acquire/release)になっています。
- **5 waitTaken**: HostFailed 等で即座に返ります。`audio_test.zig:253-269` で「待機が毎回失敗する」場合を試験しています。
- **6 pending**: `swap(false, .acq_rel)` に変わり、EAGAIN と書き込み失敗の試験(POSIX)が追加されています。
- **7 2回目の deinit**: close に失敗しても `.closed` に移り、エラーは一度だけ返ります。
- **8 試験の後片付け**: host_runtime と host_wait は直っています。`host_wake.zig:164,181,210` には `catch unreachable` が残っていますが、Wake の deinit が失敗するのは close が失敗した場合だけです。

## 未解決の現在の欠陥

### 1.【中】保留した復元が、古い端末状態で上書きする(終了時を含む)
- **根拠**:
  - 終了時の defer の順序では、`host_input.leave()`(`main.zig:2124`)が先に動き、そのあとで `recover()`(`main.zig:2103`)が動きます。
  - POSIX の `Scope.end`(`host_wait.zig:91-100`)は、NS 開始時に保存した termios をそのまま書き戻します。Windows も同様で、保存した console mode を書き戻します(`:43-44`)。
- **失敗する条件**:
  1. raw モード(INKEY 等)の最中に NS を実行する。
  2. 終了時に `tcsetattr`/`SetConsoleMode` が一度失敗し、所有が保留される。
  3. Forth の終了時に `host_input.leave` が端末を cooked モードに戻す。
  4. そのあとの recover が成功し、raw の設定を書き戻す。

  結果として、プロセスが終わった後も端末は raw・echo なしのまま残ります。
- 終了時以外でも同じことが起きます。所有を保留している間に `host_input.enter` が NS 用に変えた状態(ISIG が有効、QUIT/SUSP が無効)を「元の状態」として保存すると、その後の復元が食い違います。
- 復元の失敗が実際にどの程度起きるかは未確認です。
- **修正案**: 終了時は `host_input.leave` より前に recover します。端末の状態が NS 以外で変わったときは、保留中の端末の復元を破棄する規則を決めます。

### 2.【低】`recovery_broker` が、破棄された Runtime を指したまま残りうる
- **根拠**: `host_wait.zig:147,164,170`。`Runtime.deinit` は ResourceBusy を返すだけで、recover しません。
- **失敗する条件**: 保留が残った状態で、main 以外の利用者(試験の途中失敗など)が Runtime を捨てると、次の `beginNative` がスタックの解放済み領域を参照します(未定義動作)。
- main は exit するので、今は実害がありません。「保留中の Runtime は破棄しない」と契約に明記することを勧めます。

### 3.【低】Windows でハンドラーの削除失敗を保留している間、Ctrl+C が効かない
- **根拠**: `onControl` は CTRL_C で 1 を返します(`host_wait.zig:22-25`)。
- **失敗する条件**: 削除の失敗を保留している間は、NS の外の cooked モードでも Ctrl+C が吸収されます。そのため、`utf8_console` のハンドラー(0 を返して既定の終了処理に進む)まで届かず、プログラムが終わりません。
- ハンドラーが呼ばれる順序と削除が失敗する条件は、Microsoft の資料で確認していません(※推測)。

### 4.【低】試験で通っていない経路
次の3点は試験がありません。
- 中断と復元の失敗が重なったときに、復元の失敗が優先されること(`waitUsing`)
- main の終了時の recover と exit の経路
- 実際の NativeScope で、begin の途中から巻き戻すこと

OS の失敗を注入する手段がないため、Windows と POSIX の部分的な復元は未試験です(未確認)。

## 未確認
- ビルドとテストの結果(実行していません)
- POSIX 試験(`host_wake.zig:221`)の実際の通過
- 実際の端末・コンソールで `tcsetattr`/`SetConsoleMode`/`SetConsoleCtrlHandler` が失敗したときの挙動
