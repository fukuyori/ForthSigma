# Linux 1176 最終受け入れレビュー（読み取りのみ）

レモン、レビューが終わりました。結論として、**範囲を限った 1176 の完了処理に進むには、先に High 1 件と Medium 3 件を片付ける必要があります。** 何も実行・編集・測定せず、tque も操作していません。

読んだファイルは、`.work/1175-1176/linux-final-review-input.json`（全体）、`docs/measurements/2026-11-20-snes-dsp-os-acceptance.json`（status と tasks_snapshot の部分）、`docs/measurements/2026-11-20-snes-dsp-native.json`（platform 欄）、`.work/1175-1176/linux-device-checked-zero.{json,fs}`、`acceptance.py`（grep のみ）です。

## High

**H1. ゼロ出力の記録で、標準出力とソースが合っていません**
- `linux-device-checked-zero.fs` の 14 行目には `." LEFT LOW: about3seconds" CR` があります。
- しかし `linux-device-checked-zero.json` の stdout は `AUDIO?=-1 / handle=0… / RIGHT HIGH… / handle=0… / AUDIO?=-1 / DEPTH=0` です。`LEFT LOW` の行がありません。入力 JSON にも同じ内容が転記されています。
- この記録は「同じプロセスで AUDIO? の前後が -1」「RDPSink 経由で鳴った」という根拠に使われています。根拠の記録が、記載されたソースと食い違っている状態です。
- この実行は `acceptance.py` の通常の経路とは別のもの（CHECK-DEVICE 付き）でした。どの helper で実行し、どう出力を取り込んだかが記録にありません。行が欠けた理由は未確認です。
- 完了処理の前に、次のどちらかが必要です。
  - 実際に動いたソースと出力の取り込み方を特定し、記録を正しい内容にそろえる。
  - 再測定する。再測定にはレモンの承認が必要です。
- 補足：音の出る 2 回の試験（左低音→右高音、Ctrl+C 後の再再生）は、それぞれの stdout とレモンの OK で成立しています。H1 は、その経路を RDPSink と特定する根拠の正しさの問題です。

## Medium

**M1. 物理 Ctrl+C の実行記録に、Linux 用の起動スクリプトの hash が入っていません**
- `interrupt.py` は supervisor のハッシュ対象として `launch-windows-interrupt.ps1` を固定で書き込みます。そのため、1176 の実行記録（`supervisor_source_sha256_lf`、`actual_run_supervisor_sources`）にも Windows 用のスクリプトが載っています。
- Linux 用の `launch-linux-interrupt.ps1`（`86e1cb7e…`）は、準備段階の readiness 側にしか記録がありません。
- 実際にこのスクリプトで起動したことと、実行した時点の hash を、最終記録に明記する必要があります。

**M2. 古い状態の記述が残っています**（最終更新で直す予定の項目です）
以下は、完了処理で必ずそろえる必要があります。
- `preparation.status`：「physical Ctrl+C stop/replay pending」のまま
- `physical_interrupt_readiness.review_basis`：「Real WSL physical signal delivery is not yet tested」のまま
- `linux_acceptance.status`：「final review and owned keepalive cleanup pending」のまま
- 正式記録 `os-acceptance.json` の 8 行目：「Linux1176 … pending」のまま
- `tasks_snapshot`：1175 も 1176 も `todo` のまま。スナップショットとして残すなら、取得した時刻を明記するとよいです。

**M3. タスク名の「PulseAudio/ALSA」と、実際に確認した範囲がずれています**
- 確認できたのは、WSL2・Ubuntu 26.04.1・static musl → pacat → PulseAudio 17.0（WSLg）→ RDPSink の経路だけです。ALSA への直接出力も、物理 Linux 実機も確認していません。
- この範囲で 1176 を閉じるには、ALSA と実機を対象外とする判断を明記する必要があります。どちらも、別タスクに分けるか対象外とするかを、レモンが決めることになります。
- 記録の scope 欄には範囲が正しく書かれていますが、完了理由の中にも同じ文言を入れる必要があります。

## Low（完了の妨げにはならない注記）

- **pacat の sink input と sigma の対応**：sink input の記録（pacat PID 718）は、sigma の子プロセスであることを PID の親子関係で結び付けていません。実行中の pacat だった、という状況証拠にとどまります。
- **unit_validation の実行環境**：`zig build test` を Windows と Linux のどちらで実行したかが記録にありません。※推測です：native の実行なので、Windows ホストでの実行と思われます。Linux での検証として扱わない旨を書いておくとよいです。
- **重複した記録**：`generated_stereo_audible` と `preparation.stereo_audible` は同じ内容です。正式記録には 1 つだけ残すとよいです。
- **accepted-frames=155136 の注記**：約 4.8 秒分です。指示は「約 1 秒後に Ctrl+C」でしたが、バッファに先に積まれた分を含む値と思われます（※推測です）。判定には使っていないので、注記だけで足ります。

## 問題がないと確認できた点

- **Linux 4 構成のサイズ**：`linux`、`no-debug`、`no-float` は +14.9〜15.5KB、`no-audio` は −64B でした。各構成の検証数も記録されています。
- **速度測定**：6 ケースとも、native.json の platform 欄が `Linux-6.18.33.2-microsoft-standard-WSL2` になっています。WSL2 上での測定として区別されています。
- **左右の試聴**：左低音→右高音ともに handle=0、underruns=0、frames=98304、DEPTH=0、exit 0 で、レモンの OK が記録されています。
- **物理 Ctrl+C**：CATCH=-28 で handle=0、その後の低音の再再生も 98304 frames、underruns=0、DEPTH=0、exit 0、supervisor のタイムアウトなしで、レモンの OK があります。信号の注入は使っていません。
- **プロセスの残り**：確認後に sigma も pacat も残っていない、と記録されています。
- **Pulse の起動経過**：最初の接続拒否（原因は未確定）とソケットがない状態、その後の WSLg ログ（RDPSink への接続が 5.016s で成功）、準備完了の結果が、どれも記録に残っています。

## 完了処理の前にやること

1. H1 と M1〜M3 を片付ける。
2. 自分たちで起動した `sleep 1800` を、PID とコマンドラインで本人確認してから止める。止めた結果も記録する。
3. 状態の記述を最新にそろえる。

Mac 1177 と親タスク 1173 は、記録上は todo のままです。完了処理の後も未完了のまま残す方針に、問題はありません。
