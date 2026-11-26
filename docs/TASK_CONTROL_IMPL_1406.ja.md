# tque 1406：Linux X11描画のまとめ送り

2026-11-26。[英語版](TASK_CONTROL_IMPL_1406.md)も参照。第1段階の計測端点を保ち、第2段階でLinuxの描画送信とmailbox待機を変更した。計画ファイル、tque、Gitの状態を変更するコマンドは実行していない。

## 第1段階の証拠と原因

Claudeがサンドボックス外のXWaylandで測定した。G1、226フレーム、窓480×360。今回提示された証拠の場所は `.work/1406/native-before`。

| 区間 | 中央値 (ms) | p95 (ms) |
|---|---:|---:|
| request → take | 1.0 | 2.0 |
| take → draw-begin | 0.02 | 0.03 |
| draw-begin → draw-end | 13.4 | 14.0 |
| draw-end → roundtrip | 0.06 | 0.06 |
| roundtrip → complete | 0.0005 | 0.0006 |

T1も同じ傾向で、drawは約13.5 msだった。主因はWindow.drawで、行ごとのPutImage、ヘッダーと本体の別書き込み、行ごとのready()、画素の各成分のchannel()変換があった。次の要因はrun()で新しい絵を取る前の2 msのsleep。サーバー往復後の完了処理はごく短かった。

第1段階ではtake、draw-begin、draw-end、roundtrip端点を追加した。`tests/scripts/paint-breakdown.py`は完了に対応する最後の描画試行を結び、端点の欠落を報告し、smoke記録を除外する。`run-acceptance.py`は既存の端点検証の前に未知のeventを無視する。

## 実装

`src/host_window_linux.zig`でPutImageのヘッダーと複数行を連続したバッファに格納し、一度のsendに渡す。Connection.sendの部分書き込み・送信詰まり処理を使い、要求ごとにsequenceを一つ進める。要求はsetupのmaximum-request-length×4、ローカルバッファ64 KiB、8行の範囲内に制限する。BIG-REQUESTSは使わない。要求末尾の4バイト境界への詰めと、各行の画素形式の詰めを区別する。幅2048画素を超える窓では横方向に分割し、拡大行の生成は1行に1回のまま。

各行の生成後に単調時計のミリ秒値を調べ、tickが進んでいたらその行で要求を区切る。もう一つの上限は8行。要求の間でイベントを順に処理し、stop・redraw・窓破棄で途中終了する。確認間の変換処理は約1 msと従来の最大1行分に抑えるが、スケジューリングと送信詰まりの時間には実時間の保証がない。入力・Expose・closeの実際の応答は実機確認が必要。

対応するTrueColor visualのうち、32bpp、マスク0xff0000/0xff00/0xff、サーバーと自分のバイト順が一致する場合は、native u32を直接格納する。上位バイトは従来と同じく0にする。他の形式はchannel()とバイト順変換を使う。各成分の全256値と、alphaを含むグレースケールで両経路のバイト列を比較する試験を追加した。逆のバイト順と16bppで高速経路を選ばないことも確かめる。

新しい絵の公開とstopで、非ブロッキング・close-on-execのpipeからpollを起こす。Xのfdも同時に待つ。pipeの登録・通知・破棄はmailboxのロックで保護し、再利用されたfdへの書き込みを防ぐ。pipeが満杯なら通知は既に残っている。登録前に届いた絵は最初の待機前に取り出す。`src/host_x11.h`には_GNU_SOURCEなしのlibc変換でも使えるようLinuxのpipe2宣言を追加した。モード変更・IME処理の確認周期を維持するためpollのタイムアウトは2 msとし、絵とX入力はその期限を待たずに起こす。

window_layoutによる行生成、fit/smoothの動作、最小化中の完了延期、サーバー往復、WINDOW-FRAMES/WINDOW-PAINT-WAITの公開処理は既存のものを使う。

## 検証と実機での追試

指定のキャッシュディレクトリで、`zig build test`は371件成功・36件skip・2件失敗だった。失敗は同一のhost_x11 oversized-reply/GenericEventソケット試験が2つの試験バイナリで出たもの（sendの期待値32、実際-1）。`zig build runtime-test`は184件成功・17件skip・同じ1件の失敗。追加したTrueColorのバイト一致試験は成功した。acceptanceビルドと `python3 tests/scripts/test-acceptance-paint.py` は成功。`python3 scripts/check-docs.py` と `git diff --check` も成功した。日本語word-referenceの説明を確認し、まとめ送りと通知待機で語の意味が変わらないため、`python3 scripts/word-reference.py --record-reviewed-sources` で翻訳元の指紋を更新した。

サンドボックスでは表示された窓を検証できない。既存のhost X11ソケット試験のsend=-1は環境上の制限であり、合格とは扱わない。

第1段階と同じfixture、入力周期、display、倍率、窓サイズを使う。新しい証拠ディレクトリで実行する。

```sh
export ZIG_GLOBAL_CACHE_DIR=$PWD/.work/codex-cache/global
export ZIG_LOCAL_CACHE_DIR=$PWD/.work/codex-cache/local
zig build -Dtask-acceptance=true --prefix .work/1406/acceptance-after
python3 tests/scripts/manual-acceptance-tty.py --sigma .work/1406/acceptance-after/bin/sigma --cases native --native-paint --output .work/1406/native-after
python3 tests/scripts/paint-breakdown.py .work/1406/native-after/native-path/output.txt .work/1406/native-after/native-search/output.txt
```

決定的な画素読み戻しには、専用Xvfbで `SIGMA_TEST_BINARY=$PWD/.work/1406/acceptance-after/bin/sigma python3 tests/scripts/test-linux-native-window.py` も実行し、`SIGMA_TEST_RESIZE=1`でも繰り返す。負荷中のExpose・close・入力・最小化と復帰・stopを確認する。manual runnerは機能と証拠を確認するためのもので、測定には第1段階の同じ長さの226フレームの手順を使う。可変長の出力を同条件の標本として扱わない。

## 第2段階の実測

Claudeがサンドボックス外のXWayland（DISPLAY=:0、デスクトップにログイン済み）で測定した。証拠はLinux機の `.work/1406/native-after`（G1 339フレーム、T1 29フレーム）と、1398の組の測定 `.work/1398/native-load4`・`native-baseline4`（各1,200フレーム）。

| 区間 | 直す前 中央値 (ms) | 直した後 中央値 (ms) | 直した後 p95 (ms) |
|---|---:|---:|---:|
| request → take | 1.00 | 0.04 | 0.04 |
| take → draw-begin | 0.02 | 0.02 | 0.03 |
| draw-begin → draw-end | 13.42 | 4.75 | 5.80 |
| draw-end → roundtrip | 0.06 | 0.06 | 0.08 |
| roundtrip → complete | 0.0005 | 0.0005 | 0.0007 |

要求→完了は約14.5 msから約4.8 msになった。1398の組の測定（計画v8）では、各フレームの1/60秒の期限の超過は負荷あり・基準とも0、入力→画面の最大はG1 23.1 ms・T1 23.7 ms（目安33.34 ms）。

実機の確認：通常ビルドで `test-linux-native-window.py`（画素の読み戻し、レターボックス、キーの押下と解放、WM_DELETEと開き直し、終了）と `verify-linux-window-restore.py`（最小化中の描画の保留と復帰、待ち中の閉じる要求）が成功した。`SIGMA_TEST_RESIZE=1` の大きさ変更の読み戻しは、実際の画面では変更前のビルドでも同じX11エラー（BadMatch、GetImage）で失敗し、1406の変更によるものではない。この試験は専用のXvfbを前提とする。2026-11-26にレモンがLinux機へXvfbを入れ、Claudeが `Xvfb :99` の上で `9e5e5c3` の通常ビルドを試験し、大きさ変更後の描き直しを含む全項目が合格した（tque 1409、`.work/1409-resize0.log`・`1409-resize1.log`）。
## 計画の改訂と固定（2026-11-26、利用者の決定 案1）

60 Hzのフレーム期限を、各フレームの要求→完了が1/60秒以内かで判定する形に改めた（計画の末尾「60Hz期限の判定の改訂」）。積み上げ方式の超過数は題材のループ周期の特性として残し、合否に使わない。基準の超過0は比較の条件にしない。以降の取り込みは次の固定値を `--plan-sha256` に渡す。

| 計画 | SHA-256 |
|---|---|
| Windows/Linux v8 | `377be53a251b59dd58bd4df16763691998f28f69001d6b17864ea529e125194c` |
| macOS v6 | `ae2fabd1f1f6a687d3e1ef87e5a6571942f7a0bae0b9cbf79f69a8e095b97889` |