# tque 1408：TASK-SUBMIT の遅延測定

[English](TASK_CONTROL_IMPL_1408.md)

受け入れビルド専用の計測で、同期する投入処理をsnapshot検索、admission、静的な入口検査、Task割り当て、名前のコピー、入力のコピーに分ける。既存の単調時計とバッファ付き `ACCEPTANCE` イベントを使い、通常ビルドでは計測コードをコンパイル時に除去する。

## 入口検査の前提とキャッシュ

`Snapshot` は作成後に `bytes` を変更せず、`inspectEntry` はその保存イメージからsearch order・case flags・辞書・コードを読み、入口名を解決して `inspectImage` を実行する。呼び出し元の `MemoryGate` は毎回同じ `admissionGate` で、contextを参照せず常に `false` を返す。`inspectImage` は機械の可変状態、時刻、ファイル、実行時の権限を読まない。よって、このsubmit経路の検査結果はSnapshotと入口名で決まる。

成功した結果だけをSnapshotごとに最大8名キャッシュする。名前はSnapshotのallocatorで複製し、最後の参照を解放するときにイメージとともに解放する。上限到達後の新しい名前と失敗した検査は保存しない。同じSnapshot・同じ名前の再検査ではparseと静的検査を省く。並行呼び出しもSnapshot内のロックで直列化する。

## 再現

```sh
export PATH=/opt/homebrew/bin:$PATH ZIG_GLOBAL_CACHE_DIR=$PWD/.work/codex-cache/global ZIG_LOCAL_CACHE_DIR=$PWD/.work/codex-cache/local
zig build -Dtask-acceptance=true --prefix .work/1399-submit/acceptance2
python3 tests/scripts/measure-task-submit.py .work/1399-submit/acceptance2/bin/sigma
```

runnerは `tests/task/task-native-search.fs` と同じ `TS-SEARCH` と1,048,593 bytesの引数で公開T1投入を反復する。窓は開かない。各段について1回目と2回目以降を分け、標本数、中央値、最大値をnsで表示する。

## 結果

macOS arm64 Apple M5で50回測定した。変更前は各段をまとめた中央値/最大値（ns）がsnapshot検索1,000/3,000、admission 1,000/4,000、入口検査17,162,500/19,737,000、Task割り当て3,000/4,000、名前コピー2,000/3,000、入力コピー173,500/221,000だった。

変更後は1回目/2回目以降の中央値（ns）が、snapshot検索0/0、admission 1,000/0、入口検査9,832,000/1,000、Task割り当て2,000/3,000、名前コピー2,000/2,000、入力コピー108,000/95,000だった。入口検査の1回目は9,832,000 ns、残る49回は中央値・最大とも1,000 ns。変更前後は別測定なので、非支配段の差を最適化効果とはみなさない。ネイティブ窓は開いていない。

## 検証

Snapshot試験で同名の2回目に検査回数が増えないこと、別名と別Snapshotでは増えること、失敗名は毎回 `EntryNotFound` になることを確認する。試験は `std.testing.allocator` を使い、Snapshot解放時のキャッシュ名リークを検出する。受け入れ・制限・エラー順序・所有解放と `storage_zeroed` の意味は変更していない。失敗結果はキャッシュしないため、拒否語は毎回同じ検査エラーになる。

実行コマンドは `zig build test`、`zig build runtime-test`、上記受け入れビルド、`python3 scripts/check-docs.py`、`git diff --check`。単語リファレンスのsource fingerprintは実装ファイル変更で変化したため、日本語説明に変更がないことを確認して再記録した。

## Claude のレビューと3 OSでの確認（2026-11-26、tque 1408）

キャッシュのキーに、検査の結果を変えうる設定（`test_host_probes`、`memory_gate` の検査の関数、`max_native_bytes`）を加えた。今の呼び出し元は `Service.submit` の1か所で設定は毎回同じだが、別の設定で呼ばれたときに結果を流用しないためである。設定が違えば検査し直すことを試験に加えた。

段ごとの時間（入口の検査、中央値）：

| OS | 1回目 | 2回目以降 | 入力のコピー（2回目以降） |
|---|---:|---:|---:|
| Windows | 4.6 ms | 0.002 ms | 0.21 ms |
| Linux | 5.7 ms | 0.004 ms | 0.73 ms |
| macOS | 12.5 ms | 0.001 ms | 0.10 ms |

ネイティブ窓（macOS、計画 macOS v6、`.work/1408/native-load1`〜`3`・`native-baseline1`）：入力→画面の最大は、直す前のT1の41.3 ms（3回中2回が目安33.34 msを超過）から、直した後はT1・G1とも16.7 ms以下（3回とも）になった。基準との組では、フレーム数1,200・入力数6が一致し、各フレームの期限の超過は負荷ありで0、タスクによる追加の超過も0だった。

試験：Windows・Linux・macOSで `zig build test`、`zig build runtime-test` が通った。