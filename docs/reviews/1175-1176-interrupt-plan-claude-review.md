レビューが終わりました(読み取りのみで、実行・編集・計測はしていません)。**High はなく、Medium が 1 件**です。

## Medium

**1. `--play` の前提条件に 2 つのプレフライト JSON が入っていない**

`interrupt.py` が `--play` の前に確認しているのは次の 4 つだけです。
- バイナリの sha
- `acceptance-common.fs` の sha
- `acceptance.py --check-ready`
- `AUDIO?`

```
 gate=subprocess.run([sys.executable,str(FOLDER/'acceptance.py'),a.os,'--check-ready'],capture_output=True,timeout=20)
```

`interrupt-tones-preflight.json` と `interrupt-ram-preflight.json` は、どこからも読まれていません。このため、次の問題があります。
- `--check-ready` が確認するのは左右片側だけの stereo fixture(`451 16 0` / `901 0 16`)です。本番で鳴らす両チャンネルの音 `901 16 16` / `451 16 16` は、tones プレフライトに不一致や欠落があっても再生されます。
- `interrupt-ram-preflight.json` には `binary_sha256` も生成ソースの sha もありません。今回生成される `windows-interrupt.fs` と同じ組み立てを検証した記録かどうかを、機械的に照合できません。RAM 版は最後が `1 TRUE SD-STREAM 512` で、本番は `192 … 98304` なので、本文も完全には一致しません。
- 出力の `{os}-interrupt.json` にも、これらのプレフライトへの参照がありません。

対応方法の案です。`--play` の前に tones プレフライトについて次を assert します。
- 2 件の `binary_sha256` が今回の sha と一致すること
- `source_sha256_lf` が `acceptance.source_hashes()` と一致すること
- `full_PCM_state_ARAM_match` が真であること

あわせて、RAM プレフライトに binary sha を記録し、それも照合します。

## 確認した結果、問題なしと判断した点

- **ファイル内エラー時**: `main.zig:3844-3851` で `return 1` になり、REPL には入りません。stdin を継承していても、入力待ちで止まることはありません。
- **Ctrl+C の経路**: `SD-SEND` の `PCM-WAIT THROW` で -28 になります。その後は `SD-STREAM-RUN CATCH`、`PS-SAFE-CLEANUP`、再 THROW を経て、`LONG CATCH` に届きます。処理順と後始末に問題はありません。
- **保護区間の外での Ctrl+C**: `host_wait.zig:77` は `accepting_interrupts` が偽なら 0 を返します。stdout がパイプなので `restoreOnSignal` も登録されず、既定の処理でプロセスが終了します。その場合は exit≠0 になり、`checks_passed` は false になるので、誤って合格になることはありません。scope の記述とも合っています。
- **30 秒で押されなかった場合**: `CATCH=0` になり、`CHECK` の `-528` で exit 1 になります。上限は 1875×512/32000 = 30.0 秒です。
- **信号の注入**: コード内に注入はありません。

## Low(参考)

- 親プロセスに締め切りがありません。`acceptance.py` には 30 秒の kill がありますが、`interrupt.py` の `proc.wait()` は無期限です。再生自体は Forth 側で上限がありますが、ホストが止まった場合は利用者がウィンドウを閉じる必要があります。
- 押したのが「約 1 秒」かどうかが記録に残りません。中断時点の `PS-FRAMES` を出力していないため、30 秒近くで押しても合格になります。
- 未確認の点が 2 つあります。
  - pwsh 上でネイティブコマンドを実行中に Ctrl+C を押したとき、pwsh が `python` を終了させないか。
  - `python` が `.bat` などのシム経由で起動されないか。シムだと「バッチ ジョブを終了しますか」の確認が出る可能性があります。

  どちらも実行して確かめていません。
