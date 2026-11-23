# Windows共通受け入れ追加レビュー

Claude Code読み取り専用。変更作業中の追加照合で、最終状態の承認とは区別する。

# 1334 再レビュー（Windows表示支援の共通受け入れ）

レモン、Read/Glob/Grep だけで照合しました。スクリプト・ビルド・テストは実行していないので、実行結果はすべて未確認です。git の状態は今回コマンドで確認していません。根拠はセッション開始時のスナップショットだけです。tque の状態も未確認です。

前回のレビュー（`docs/reviews/2026-11-23-windows-display-claude-review.md`）の指摘は、現行の版にほぼそのまま残っています。それに加えて、**測定した実行体と現在の作業ツリーが食い違っている**問題を新たに見つけたので、High とします。

## High

**H1. 記録した結果が、現在のソースの動作と合わない**
- 場所:
  - `src/graphics/graphics.fs:367`（作業ツリーで変更中）
  - `tests/scripts/verify-windows-display-contract.py:85-94`
  - `docs/WINDOWS_DISPLAY_CONTRACT_VALIDATION.md:3-4,29,47`
  - `docs/HANDOFF.md:5`
  - `docs/CORE_EXTENSION_DETAILED_DESIGN.md:678`
- 内容:
  - 作業ツリーの `graphics.fs:367` は、Tk 表示中の `WINDOW-CLOSE` を `2 GFX-TK-WINDOW-CLOSE` へ渡します。これは `tcl.zig:421` → `sigma_tk.tcl:96-101` の `wm withdraw .` で、Tk のウィンドウを閉じます。
  - 一方 JSON の switching の rows[3] は `native_open 0`・`open -1`・`tcl -1` で、「native が閉じて Tk は開いたまま」という旧来の動作です。スクリプトの 93-94 行も、この旧来の動作を期待値にしています。
- 実行体の状況（Grep で確認）:
  - 現在の `zig-out/bin/sigma.exe` には `2 GFX-TK-WINDOW-CLOSE DROP ELSE GFX-WINDOW-CLOSE` の文字列があります。
  - 同じパスの SHA-256 は、2つの記録で異なります。display-contract は `c0d1…`、`2026-11-23-windows-tk-state.json` は `9b3e…` です。
- 推測できること（※推測です）:
  - 1334 の測定に使った実行体は、この変更より前のソースからビルドされています。
  - 今のツリーで再実行すると、93 行（`rows[3]['native_open'] == 0`）と 94 行（`open == -1`）で失敗する見込みです。
  - 測定時のツリーが `d29bdbe` そのものだったかどうかは、記録からは判別できません。
- 文書の問題:
  - 「アプリケーションの実装は変更せず」（`WINDOWS_DISPLAY_CONTRACT_VALIDATION.md:4`、`HANDOFF.md:5`）は、現在のツリーには当てはまりません。
  - 「WINDOW-CLOSEはnativeを閉じ、Tkは開いたまま」（同 29 行）と、設計書 678 行の「WINDOW-CLOSE…はnative専用」は、作業中の実装（`graphics.fs:367`）と食い違います。`graphics.fs:364-365` の説明文も「host's own window を閉じる」のままです。
- 修正案（どちらにするかはレモンの判断です）:
  - (a) 1334 の文書・スクリプト・JSON は、作業中の 1326 系の変更とは別のコミットにする。そのうえで「測定は旧来の WINDOW-CLOSE 経路の実行体による」と明記する。
  - (b) 1326 の変更を取り込んだ後で、rows[3] の期待値を「Tk が閉じて native は開いたまま」に改める。再実行して JSON を作り直す。
  - どちらの場合も、`source_revision` の横に `git status --porcelain` の結果、またはツリーが dirty かどうかを JSON に入れ、ビルドしたツリーと結び付ける。

## Medium

**M1. Tk への切替えを判別できていない（前回 M1 のまま）**
- 場所: スクリプト 92 行、文書 29 行
- 内容: native と Tk が同じ 160×100 なので、rows[2] の大きさがどちら由来でも pass します。assert しているのは `tcl == -1` だけです。
- 再現条件: `WINDOW-PIXELS`（`graphics.fs:335-337`）が Tk 選択中も native を返す実装に戻っても、検出できません。
- 修正案: Tk 側だけ別の大きさにして `width != native_width` を assert する。または、文書の記述を「GFX-TCL?が真になる」まで弱める。

**M2. 画面倍率と実サイズの根拠を記録していない（前回 M2 のまま）**
- 場所: スクリプト 65-68 行・91 行、文書 35-36 行
- 内容:
  - `width >= 160` と緩くしながら、`view_width == 160`・`view_height == 80` は固定値です。width が 160 を超えると view も変わるので、緩めた意味がありません。67 行は 66 行と重複しています。
  - 文書 35 行の「64×40 → 120×40」は、JSON にもスクリプトにも根拠がありません。
- 修正案:
  - `WINDOW-DISPLAY` と `DISPLAY-SCALE` を JSON に残す。
  - 64×40 を、実サイズを記録する case として加える。
  - Tk の大きさは `== 160/100` に揃える。

## Low

1. **成功時の終了漏れを検出できない**（`windows_display_test_support.py:57-58`）
   - 成功時も `TerminateJobObject` で強制終了するので、BYE の後に wish が残っても検出できません。
   - 修正案: 終了させる前に `QueryInformationJobObject(JobObjectBasicAccountingInformation)` で ActiveProcesses を読み、0 であることを assert する。
2. **失敗時の回収の穴**（同 38 行・58-62 行）
   - `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` を設定していないので、Python 自体が強制終了されると sigma と wish が残ります。
   - `TerminateJobObject` の戻り値を見ていません。
   - finally 内の `process.wait(timeout=5)` が TimeoutExpired を投げると、元の例外が隠れます。
   - `process._handle` は非公開の属性です。
3. **保存アプリの行数を確認していない**（スクリプト 104 行・108 行）: `states(...)[0]` だけを使っています。`len == 1` を assert すべきです。
4. **VSYNC の期待値が緩い**（同 45 行）: `0/-1` の両方を許しています。文書 26 行は「この環境では真」と書いているので、記録した値に合わせて固定するか、文書を合わせます。
5. **保存アプリの fit・clip を直接確かめていない**（同 99-103 行）
   - 新規起動したアプリで fit/clip が持ち越されないことは、`graphics_test.zig` に依存しています。これは文書 41-42 行に書かれているとおりです。
   - 改善案: ACCEPT-MAIN で SHOW したあと、`WINDOW-IMAGE-RECT` の y が 10（aspect に戻っている）であることを確かめる。
6. **Linux の no-x11 に当たる case がない理由が書かれていない**
   - Windows には、ウィンドウを外すビルド条件がありません（`build.zig:17` の x11 は Linux 専用）。そのため -265 の経路は確かめられません。
   - 文書にこの理由を一行足すとよいです。
7. **1要素だけのループ**（スクリプト 51 行）: Linux 版の名残です。害はありません。
8. **設計書に古い記述が残っている**（`CORE_EXTENSION_DETAILED_DESIGN.md:688`）: 「Windows共通受け入れ1334…を残し」が 660 行の完了記述と食い違ったままです。

## 照合して問題なしとしたもの

- **KEY ゲート**
  - パイプからの入力では、KEY はデータか EOF が来るまで待ちます（`main.zig:1896-1901`）。
  - `\n` は `AssignProcessToJobObject` の後の `communicate` で送られます（support 49-52 行）。
  - wish は `CREATE_SUSPENDED` で起動され、`CREATE_BREAKAWAY_FROM_JOB` は付いていません。継承するハンドルも HANDLE_LIST で限定されています（`host_process_native.c:161,171`）。そのため wish はテスト側の job に入り、stdout パイプも漏れません。
  - Popen から Assign までの間に子プロセスを作る経路は見つかりませんでした。保存アプリも、起動語の中の KEY で同じように待ちます。
- **公開の待ち語の範囲丸め**: `WINDOW-PAINT-WAIT` は丸めたうえで呼びます（`graphics.fs:437`）。範囲外の値に対しては、`words_graphics.zig:443` が -24 を投げます。丸めが無ければ -24 になるので、偽陽性ではありません。
- **4つの状態語の対応表**: `graphics.fs:350-357` の Tk/native の振り分けと、tk-table の期待値は一致しています。WINDOW-CLOSE だけは H1 のとおり作業中の実装と食い違います。
- **項目数**: 「8項目」（設計書 660 行）は、スクリプトの case 数と一致します。
- **1334 を完了とした判断**: 範囲の切り方（1300・1303・1304・1295・1326・DPI・実提示を残件にする）は妥当です。ただし、H1 を解消するまでは、記録がどのソースに対応するかを示せません。