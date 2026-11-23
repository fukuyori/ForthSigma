# Windows共通受け入れ Claude Codeレビュー

Claude Code model_usage_since_last_result: claude-opus-5-5。読み取り専用。初回の変更に対するレビュー。

# 1334 レビュー結果（Windows表示支援の共通受け入れ）

レモン、Read/Grepだけで照合しました。スクリプト・ビルド・テストは実行していないので、実行結果はすべて未確認です。tqueで1334が完了になっているかも未確認です。

**重大な問題（High）はありません。** 1334を「共通条件の確認として完了」とした判断は、文書に書かれた範囲と残件（1300・1303・1304・1295・1326・DPI・実提示）に照らして妥当です。ただし、文書の一部が assert の確認範囲より強い主張になっています。

## High
なし。

## Medium

**M1. Tkへの切替えを、記録の主張どおりには確認できていない**
- 場所: `tests/scripts/verify-windows-display-contract.py:135-147`、`docs/WINDOWS_DISPLAY_CONTRACT_VALIDATION.md:29`
- 内容: `graphics.fs:335-337` で、Tk表示中の `WINDOW-PIXELS` はTkのウィンドウの大きさを返します。ところがnativeもTkも同じ `160 100 WINDOW-SIZE` なので、rows[2] の width/height/x/y はどちらから来た値でも 160/100/0/10 になります。
- assert しているのは `rows[2]['tcl'] == -1` だけです。focused（JSONでは0から-1に変化）や大きさの出どころは確認していません。
- 再現条件: `WINDOW-PIXELS` が Tk 選択中も誤って `GFX-WINDOW-STATE`（native）を返す実装に戻っても、この case は pass します。
- 修正案（どちらか）:
  - Tk側だけ別の大きさにする（例: `S" wm geometry . 200x120" TCL-EVAL` の後に照会）。そのうえで `rows[2]['width'] != rows[2]['native_width']` を assert する。
  - 文書29行の「Tk選択時の状態はTkへ切り替わる」を「GFX-TCL?が真になる」まで弱める。

**M2. 画面倍率を記録・前提にしていない**
- 場所: スクリプト `118-121`・`144`、JSON全体
- 内容: この機械には倍率の違う画面があります（`CORE_EXTENSION_DETAILED_DESIGN.md:659`）。それでも `view_width == 160` や `[160,100,0,10,160,80]` を固定値で assert しています。ウィンドウが開いた画面の `DISPLAY-SCALE` は JSON にありません。
- 再現条件: 主画面を100%以外の倍率にして実行すると、Tkの物理ピクセルやWindowsの最小幅補正で期待値から外れる可能性があります（※推測です）。外れた場合、それが実装の不具合か倍率の差かを記録から判別できません。
- 文書35行の「指定64×40に対して実サイズ120×40」も、JSON にもスクリプトにも根拠が残っていません。
- 修正案:
  - `WINDOW-DISPLAY` と `DISPLAY-SCALE` を出力して JSON に保存し、倍率1以外では skip または失敗理由を明示する。
  - 64×40 のケースを、実サイズを記録する case として加える。

## Low

1. **失敗時の回収の範囲**（`verify-windows-display-contract.py:55,75`）
   - job に `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` を設定していません。Python 自体が強制終了されると、sigma と wish が残ります。
   - 文書20-21行の「成功・失敗・期限切れ」の3経路は finally で回収されるので、記述自体は正しいです。
   - 修正案: `SetInformationJobObject` で KILL_ON_JOB_CLOSE を設定する。
2. **成功時の終了漏れを検出できない**（同 `75`）
   - 成功した場合も `TerminateJobObject` で強制終了するので、BYE の後に wish が残っても気づけません。
   - 修正案: `communicate` の後、`QueryInformationJobObject(JobObjectBasicAccountingInformation)` で ActiveProcesses を読んで記録・assert する。
   - 強制終了したときは `%TEMP%\sigma-tk-<pid>-*.tcl`（`host_process.zig:164-171`）が残る可能性があります（※推測です）。
3. **KEYゲートは成立している**
   - パイプ入力の場合、KEY は `main.zig:1896-1921` でデータか EOF が来るまで待ちます。`\n` は AssignProcessToJobObject の後に送られます。
   - wish は `host_process_native.c:171` で `CREATE_BREAKAWAY_FROM_JOB` を付けずに起動されるので、テスト側の job から抜けません。
   - 競合が残るのは Popen から Assign までの間ですが、この間に sigma が子プロセスを作る処理は見つかりませんでした。
   - 改善案: `process._handle`（非公開の属性）への依存をやめ、`OpenProcess(pid)` で handle を取る。
4. **Tk単独の大きさの assert が文書より緩い**（同 `118-119`）
   - `width >= 160` と緩くしながら、`view_width == 160` は固定値です。文書27行は「物理サイズ160×100」と書いています。
   - width が160より大きければ view も変わるので、`width == 160 and height == 100` に揃えるのが一貫します。
5. **VSYNC の期待値が緩い**（同 `98`）
   - `absent()` は vsync の `0/-1` を両方許します。文書26行は「この環境では真」です。
   - 修正案: 記録値として JSON に残す、または期待値を -1 に固定する。
6. **保存アプリの state 行数を確認していない**（同 `157,161`）
   - `states(...)[0]` だけで、行数を確認していません。他の case と同じく `len == 1` を assert すべきです。
7. **Tk の表示待ちが固定300ms**（同 `111,138`）
   - 遅い環境では Tk が map される前に照会して width 0 になり、偽陰性になり得ます。偽陽性にはなりません。Linux版も同じです。
8. **記録の再現性**（同 `188`）
   - `source_revision` に dirty の有無がありません。binaries が HEAD からビルドされたことも確認していません。
   - 修正案: `git status --porcelain` の結果を JSON に入れる。
9. **ループの残骸**（同 `104`）
   - `for ... in [(args.sigma, 'full')]` は Linux版の名残で、1要素だけのループです。害はありません。
10. **設計書に古い記述が残っている**（`docs/CORE_EXTENSION_DETAILED_DESIGN.md:688`）
    - 「Windows共通受け入れ1334…を残し」とあり、660行の完了記述と食い違います。現状を書く文書なので、688行から1334を外すのが適切です。
    - `LINUX_NATIVE_VALIDATION.md:366` は1333時点の記録なので、そのままで問題ありません。

## 照合して問題なしとしたもの
- **公開の待ち語の範囲丸め**（`184-186`）: `WINDOW-PAINT-WAIT` は `0 MAX 60000 MIN GFX-FRAME-WAIT` です（`graphics.fs:437`）。直前の case で `GFX-FRAME-WAIT` がウィンドウなしでも -24 を投げることを確認しているので、丸めが無ければ -24 になります。偽陽性ではありません。
- **Tk/native/terminal の対応表**: `graphics.fs:322-367` の振り分け（4つの状態語と PIXELS・IMAGE-RECT・DISPLAY は Tk へ、CHANGES・FRAMES・CLOSE・PAINT-WAIT は native）と、各 case の期待値は一致しています。
- **保存アプリの初期化**: `absent(fresh)` で全項目が0・-1であることと、ライブラリ変数が4/127/-1であることを assert しています。fit・smooth・keep-open・clip を直列化しないことは `graphics_test.zig` に依存しており、文書41-42行にもそう書かれています。
- **graphics除外**: 正の対照と負の対照の両方があり、Linux版と同等です。