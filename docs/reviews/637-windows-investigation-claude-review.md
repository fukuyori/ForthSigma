# 637 Claude Code review: windows-investigation

2026-11-19。読み取り専用CLIレビュー。以下はレビュー原文であり、指摘の採否・実行確認とは区別する。

## 依頼

```text
Windows cooked input regression investigation. Read src/host_wait.zig and src/main.zig utf8_console and tests/scripts/verify-terminal-modes-windows.py. Read .work/637-review/readDataCooked.cpp if useful. We implemented temporary Ctrl+C handling to preserve terminal presentation. GenerateConsoleCtrlEvent triggers handler, CancelSynchronousIo (now experimental CancelIoEx) makes first ReadConsoleW return false with interrupted=true, Forth CATCH prints -28 NEXT. The subsequent ReadConsoleW hangs even after Q+CR via WriteConsoleInputW (queue drops to 0). Normal noninterrupt Q+CR works. Diagnose concrete code/test problems; propose minimal sound fix. Do not modify files. Consider concurrent handler teardown, actual control events vs generated, cooked read cancellation and test console state. Return concise Japanese findings.
```

## レビュー原文

# Windows cooked 入力の回帰調査（Ctrl+C 後に2回目の `ReadConsoleW` が戻らない件）

結論：原因はほぼ特定できたと考えていますが、確定させる実験はまだ実行していません。ファイルは変更していません。

## 主因：取り消した cooked read が conhost に残り、次の入力を先に食べる（※推測です。根拠は下記）

- `CancelIoEx`／`CancelSynchronousIo` で取り消せるのは、こちらのプロセス側の I/O だけです。conhost 側の待ち（cooked read の待機ブロック）は消えずに残ると考えられます。
- `readDataCooked.cpp:201-236` の `COOKED_READ_DATA::Notify` が読み取りを終える理由は、`CtrlC`／`CtrlBreak`／`ThreadDying`／`HandleClosing` の4つだけです。I/O 取り消しで終わる経路はこのファイル内にありません。
- その結果、次のように進んでいると考えられます。
  1. 2回目の `ReadConsoleW` が新しく待ちに入る。
  2. 注入した Q+CR を、キューの先頭に残っている古い cooked read が受け取る。入力キューが 0 になるという観測と合います。
  3. 古い read の返信先はもう取り消し済みなので、結果は捨てられる。
  4. 新しい read は次の行を待ち続けて、ハングする。

確認方法：`.work/637-review/windows-double-line-probe.py`（Q+CR を 0.5 秒あけて2回送るもの）を実行してください。2行目で `81` が返ればこの仮説で確定です。この probe の実行ログは見当たらなかったので、結果は未確認です。

## テストの問題：`GenerateConsoleCtrlEvent` は実際の Ctrl+C と経路が違う

- 実際に Ctrl+C キーを押した場合、入力モードが `0x1f7`（`ENABLE_PROCESSED_INPUT` を含む）なら、conhost の入力処理が `Notify(CtrlC)` を呼びます。cooked read は `STATUS_ALERTED` で conhost 自身が終わらせ、そのうえでハンドラも呼ばれます。つまり I/O を取り消す必要はありません。
- `GenerateConsoleCtrlEvent` はハンドラを呼ぶだけで、入力処理を通りません。cooked read は終わらないので、取り消しが必要になり、上の主因を自分で引き起こしています。
- つまりこのテストは、利用者がキーを押す場面とは別の状況を検証しています。
- `windows-key-interrupt.log` では、READY の後に NEXT が出ずにタイムアウトしています。ただ、どのような注入方法だったかは未確認です。`WriteConsoleInputW` で書き込んだ Ctrl+C のレコードが、この入力処理を通るかどうかも未確認です。

## 並行する終了処理について（ハングの原因ではないと判断）

- `onControl` はハンドラ用の別スレッドで動き、`cancelConsoleRead` は最長およそ 250 ms 繰り返します。`endConsoleRead` が `read_thread=null` にすれば止まり、次のスコープでは `read_generation` が変わるので止まります。ロックの下で比べているので、新しい読み取りを誤って取り消すことはないと読みました。
- ハンドラの実行中に `SetConsoleCtrlHandler(&onControl, 0)` で外すことは問題ありません。関数も状態も static なので、寿命の問題は起きません。
- ハンドラは登録の新しい順に呼ばれるので、`onControl` が先に呼ばれて 1 を返します。そのためスコープの中では `restoreOnSignal` は呼ばれず、これは意図どおりです。
- ただし `CancelIoEx(stdin, null)` は、そのハンドルに対するすべてのスレッドの I/O を取り消します。今は読み取りスレッドが1本なので実害はありませんが、範囲は広すぎます。

## 最小で健全な修正案

1. `host_wait.zig` の `onControl` から I/O の取り消しを外し、`interrupted` を立てるだけにする。`cancelConsoleRead`、`read_thread`、`read_generation` と、`main.zig` の `fill` から呼んでいる `beginConsoleRead`／`endConsoleRead` も不要になります。
   - 実際の Ctrl+C では、conhost が read を終わらせます。`ReadConsoleW` が 0 を返すか read 数 0 で戻った後、`inputInterrupted()` で -28 にする流れは今のコード（`main.zig:1167-1171`）のままで成り立ちます。
   - kernelbase がこのとき「成功、読み取り 0、`ERROR_OPERATION_ABORTED`」を返すかどうかは未確認です。修正時に `GetLastError` をログに出して確かめる必要があります。
2. テストは本物の入力経路を通るように変える。ConPTY（`CreatePseudoConsole`）の入力パイプに `\x03` を書く方法が、実際のキー入力に一番近いと考えます。`WriteConsoleInputW` に Ctrl+C のレコード（vk `0x43`、char `0x03`、`LEFT_CTRL_PRESSED`）を書く方法で入力処理を通るかは未確認なので、先に probe で確かめる必要があります。
3. 外部から生成された CTRL_C（`GenerateConsoleCtrlEvent`）では、cooked read を途中で止めない。次の行が入力された時点で -28 にする、という仕様にして文書に書く。cooked の待ちを安全に取り消す公開 API は見当たらないので、これが健全だと考えます。

先に確認していただきたい点が1つあります。3番の仕様（外部から生成された Ctrl+C では即座に中断しない）で問題ないでしょうか。問題なければ、double-line probe での確認から進めます。
