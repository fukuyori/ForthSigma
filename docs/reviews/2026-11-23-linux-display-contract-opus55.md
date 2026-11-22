# Linux共通受け入れのOpus 5.5レビュー（2026-11-23）

Claude Code CLIに`--model claude-opus-5-5 --tools Read,Grep,Glob`を指定。両応答のmodelUsageも`claude-opus-5-5`。読み取り専用で依頼し、実行検証はCodexが担当した。

## 初回

所見は 3 件です（Medium 1、Low 2）。加えて、カバレッジの不足と未検証のエッジケースがあります。読み取りのみのレビューで、テストは実行していません。

## 確認できた所見

**[Medium] `verify-linux-display-contract.py:121-126` の no-graphics ケースが判別になっていない**
- `REQUIRE-GRAPHICS ALSO GRAPHICS` を付けずに素の `[DEFINED] DISPLAYS .` などを実行しています。
- これらのワードは REQUIRE-GRAPHICS で読み込まれ、GRAPHICS 語彙に入ります（`verify-p10.py:45-49` と同じ前提です）。そのため **full ビルドでもすべて 0 になり、このケースは必ず通ります**。
- 誤って full バイナリを `--no-graphics` に渡しても、そのまま pass が出ます。
- 修正案: 既存の契約に合わせて `: TRY-W S" REQUIRE-GRAPHICS" EVALUATE ; ' TRY-W CATCH . [DEFINED] GRAPHICS .` が `-270 0` になることを確認する。比較用に、full 側で同じ名前の一覧が `REQUIRE-GRAPHICS ALSO GRAPHICS` の後に -1 になることも確認するとよいです。

**[Low] `verify-linux-display-contract.py:94-96` の主張とアサーションの対象がずれている**
- `rows[2]`（DISPLAY-TK に切り替えた後）では、`(TK-SHOWN?)` が真になります。このとき `WINDOW-PIXELS` と `WINDOW-IMAGE-RECT` が返すのは Tk ウィンドウの値です（`graphics.fs:335-337, 415`）。
- つまり `width==64 and height==40` は、native ウィンドウのサイズが保たれたことを示していません。両方とも 64x40 なので偶然一致しています。
- 一方 `open`/`shown`/`painted`/`paint_wait` は native の値なので、ケース名「keeps-native-window-and-counts」の根拠になるのはこちらだけです。
- 修正案: 主張から外すか、`rows[2]` の width/height は Tk の値として意図を明記する。

**[Low] `verify-linux-display-contract.py:112-114` で保存アプリだけ出力チェックが弱い**
- `run()` が行っている `'STACK UNDER FLOW'` のチェックが、保存アプリの実行では抜けています。

## Zig テスト（`graphics_test.zig:3279-3332`）

アサーションは正しく、分離（`FakeWindow.state` の defer リセット、`growing=false`）も問題ありません。ただし、どれだけ証明しているかには限界があります。

- **[Low] fresh 側（3321-3331）は `restoreImage` を使っている**
  - SAVESYS アプリが起動時に通るのは `restoreFreshImage`（`main.zig:3829`）です。fresh 側はこの経路を通っていません（違いは `image_restore.zig:51` の memset の有無だけです）。
  - また fresh マシンでは fit/smooth/keep-open/displays を一度も設定していません。そのため 3324-3329 は、イメージがこれらを運ばないことの回帰ガードにはなります。しかし restore のリセット処理は検証していません。
  - テスト名の「new machine」はこの範囲だと明記しておくとよいです。
- **[Low] 3308 の `expectEqualDeep(host_before, FakeWindow.state)` はほぼ自明**
  - `growing=false` の `tell` は状態を変えず、restore は `window_state_fn` を呼びません。そのため常に成り立ちます。
  - ホスト状態の保持を示すなら、`FakeWindow.asked` の不変に加えて、`window_fit_fn`/`window_smooth_fn`/`window_close_fn` のフェイクが restore 中に呼ばれないことを確認する方が意味があります。
- 3319 の `expectError` の後に `data_depth = 0` がありませんが、無害です。

## カバレッジの不足（tque 1047 の範囲内、実害は未確認）

- **no-x11 のエラー契約**: `DISPLAY-WINDOW` → -21 と、`(DISPLAY)=2` での `SHOW` → -265（`graphics.fs:264, 486`）が未テストです。また `DISPLAY-TERMINAL TRUE FULLSCREEN` → -21 は Zig 単体テストにしかありません。
- **Tk 行（67-75）**: `focused`/`minimized`/`closes` が未アサートです。`rows[3]`（WINDOW-CLOSE 後）でも Tk が生きていること（`tcl==-1`）を確認していません。
- **SAVESYS ケース（102-119）**: before 行で fit/smooth/keep-open/CLIP! を設定していますが、Forth 側に問い合わせるワードがないため、fresh 側で観測していません。Python ケースが示しているのは、ホストウィンドウ・表示キャッシュの不在とライブラリ変数の保持だけです。
- **in-place restore で未カバーのランタイム状態**: `gfx_window_size`、`gfx_auto_display`、`gfx_fullscreen`、`gfx_cursor_visible`、`gfx_color_mode`、フォント（`clearImage` が組み込みに戻す）が未カバーです。
  - 特に、`(DISPLAY)` は image 側の値で上書きされますが、`gfx_auto_display` はターゲット側に残ります。この組み合わせは未テストです。

## 未検証のエッジケース（実害は確認していません）

- **`300 MS` の固定待ち（67, 91）**: 負荷が高いと Tk のマップが間に合わず、`WINDOW-PIXELS` が 0 になってフレークする可能性があります。
- **Tk 行の期待値 `[64, 40, 0, 4, 64, 32]`（73）**: スケール 1 を前提にしています。XWayland で HiDPI スケーリングが有効な環境では変わる可能性があります。
- **`timeout=25` で sigma が kill された場合**: 子プロセスの wish が残るかどうかは確認していません。

## 修正後の確認

**結論:** 前回指摘した点はすべて解消済みです。新しい `verify-linux-monitor-moves.py` に、低重大度の具体的な問題が 2 件残っています。確認は Read/Grep のみで行い、スクリプトとテストは実行していません。

## 前回指摘の解消確認
- **no-graphics**: `REQUIRE-GRAPHICS` を CATCH して -270 になること、`GRAPHICS` と各語が無いことを確認しています。フルビルドでの陽性対照もあります（`verify-linux-display-contract.py:128-136`）。
- **ネイティブの幅・高さ**: `GFX-WINDOW-STATE` から別に取り出して FIELDS に入れています。Tk のみの行では 0、ウィンドウ切替時は 64/40 であることを確認しています（`:80`, `:105`）。
- **共通の後始末**: `invoke` が全ケースでプロセスグループを停止しています。stdout の `BACKTRACE:` / `STACK UNDER FLOW` 検査は、SAVESYS で作ったアプリの実行にも適用されています（`:33-45`, `:121`）。
- **Tk のネイティブ専用フラグ**: open、focused、minimized、closes、shown、painted、changes、paint_wait、vsync、display、native の全項目を確認しています（`:80-81`）。
- **no-x11**: `DISPLAY-WINDOW` -21、強制 `SHOW` -265、端末での `FULLSCREEN` -21、DEPTH 0 を確認しています（`:137-144`）。
- **Zig テスト**: 新しいマシンは `restoreFreshImage` で作っています（`src/tests/graphics_test.zig:3335`）。restore の間に fake の state/fit/smooth/close コールバックが一度も呼ばれないこと（呼び出し回数 0）と、ホスト状態が変わらないことを確認しています（`:3306-3319`）。in-place restore 後もターゲット側の fit=2、smooth/keep-open=false、display id 22 が保たれ、画像・クリップは消え、ライブラリ変数はイメージの値になることも確認しています。
- **monitor-moves の基準点**: `display_randr.zig:118` の `place()` は RandR の並び順のまま、primary（無ければ先頭）を原点にします。スクリプトの正規化（`:76-79`）はこれと一致しています。`DISPLAY-RECT` が返すのは work 領域ではなく monitor の矩形なので、比較は正しいです。
- **monitor-moves の移動と判定**: EWMH の移動先は root 座標（primary 原点を足し戻した値）です。実際の位置は TranslateCoordinates で root 座標として取り、RandR の生の矩形と比べています。monitor の index と 64x40 のサイズを確認しています。monitor が変わったときの changes の増加も検査しており、これは `host_window_linux.zig:1152` の、monitor の変化を change として数える仕様と合っています。

## 残っている問題

### 1.【低〜中】X 接続の期限が更新されず、テストが不安定になりうる（`verify-linux-monitor-moves.py:27`, `:74`, `:80`）
- `Connection` の期限 `deadline` は、生成時（`experiments/linux_x11_probe.py:65`）に「生成から 5 秒」と決まります。
- 接続は Sigma を起動する前のモジュール読み込み時に作られます。その後 Sigma の起動、`SHOW`、最大 2000ms の `WINDOW-PAINT-WAIT`、MONITOR 行の出力を待ちます。
- その後に呼ぶ `raw_monitors()` と `find_window()` は期限を更新しません。`find_window()` はウィンドウツリー全体を GetProperty/QueryTree で辿ります。
- そのため、起動が遅い環境や窓の多いデスクトップでは `TimeoutError("X11 operation exceeded 5 seconds")` で誤って失敗します。
- **修正案:** `raw_monitors()` と `find_window()` の直前に、それぞれ `connection.deadline = time.monotonic() + 5` を入れる。

### 2.【低】終了時の実行時エラーを見逃す（`verify-linux-monitor-moves.py:106-107`）
- `SigmaSession.finish()` は returncode しか見ません（`linux_x11_test_support.py:88-92`）。
- contract 側のスクリプト自身のコメントにあるとおり、Sigma の実行時エラーは stdout に出て、終了コードは 0 のままになることがあります。
- このため、最後の `WINDOW-CLOSE BYE` でエラーが出ても PASS になります。
- **修正案:** `finish()` の後に stdout の残りとして `session.buffer` と残りの読み出しを取り、`BACKTRACE:` が無いことを確認する。あわせて stderr が空であること（`session.errors() == ''`）も確認する。

これ以外に、スコープ内で具体的に直すべき問題は見つかりませんでした。
