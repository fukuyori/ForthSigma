# レビュー結果: `verify-windows-vsync-unavailable.py` / `windows_display_test_support.py`

High に当たる指摘はありません。Medium が 4 件、Low が 4 件です。コードを読んで静的に確認しただけで、実行はしていません。

DwmFlush が使えて S_OK が返る現在の Windows 11 環境では、`kind='available'` になり `not-applicable` / exit 2 で止まります。そのため、この構成だけで誤って pass になる経路はありません。

## Medium

**M1. 成功コードが失敗として扱われる（`verify-windows-vsync-unavailable.py:60`）**
- `all(row['hresult'] != 0 ...)` で判定しているため、S_FALSE (1) のような正の成功 HRESULT もエラー扱いになります。
- 要件は「エラーを返す」なので、`< 0`（FAILED）で判定し、3 回すべてが負の場合だけ `hresult-failure` にしてください。

**M2. system32 の実 DLL であることを検証していない（`:33`, `:35`, `:76`）**
- `provider='system32/dwmapi.dll'` と `function_injection=False` は固定値で、測定結果ではありません。
- 子プロセスは `sys.executable script --probe-child` を隔離なしで起動しています（`:81`）。そのため `PYTHONPATH` や site/sitecustomize で `ctypes`/`json` を差し替えたモックでも、`hresult-failure` を出せてしまいます。
- 修正案:
  - `GetModuleFileNameW(dwm._handle)` の結果を `GetSystemDirectoryW()\dwmapi.dll` と比較し、一致しなければ失敗にする。その実パスをレポートに記録する。
  - 子プロセスを `-E -s`（または `-I`）で起動する。`-I` を使う場合、probe はサポートモジュールを import しない構成にする必要があります。
  - 親プロセス側の `sys.flags` も記録する。

**M3. 「missing」の判定範囲が広すぎる（`:36-38`）**
- `OSError` であれば winerror の値に関係なく `library-unavailable` になります。アクセス拒否 (5) や DLL 初期化失敗 (1114) なども、DLL が無い場合と同じ扱いです。
- winerror 126（ERROR_MOD_NOT_FOUND）だけを unavailable とし、それ以外は failed か別の status に分けてください。
- `:96` も `!= 'available'` で Sigma 実行へ進む否定判定になっています。`library-unavailable` / `function-unavailable` / `hresult-failure` の許可リスト方式にしてください。

**M4. Sigma が未改変であることを pass 条件にしていない（`:76`, `:104`）**
- `binary_identity` は hash を記録するだけで、期待値（正規ビルドの hash）との照合はしていません。
- そのため、`WAIT 0 n` を 8 行出力するだけのスタブを `--sigma` に指定しても pass します（ただし M1〜M3 の条件を満たす環境に限ります）。
- 修正案:
  - 期待 hash を引数で必須にし、不一致なら failed にする。
  - hash は実行の直前と直後の 2 回取って比較する（取得から実行までの TOCTOU 対策）。

## Low（必要な修正のみ）

- **L1** (`:83`, `:123-126`): `assign_job` が失敗すると子プロセスは job に入らないため、`TerminateJobObject` では終了しません。この場合、`wait(timeout=5)` が TimeoutExpired になり、元の例外を上書きします。`invoke` と同じように、`poll() is None` なら `child.kill()` してから wait してください。
- **L2** (`:100-103`): `VSYNC-WAIT` がスタックに余分な値を残しても検出できません。ループ後に `DEPTH .` を出力し、0 であることを確認してください。
- **L3** (`support:122`, `:124`): `TerminateJobObject` の戻り値を確認していません。少なくとも失敗したことは記録してください。
- **L4** (`:130-135`): cleanup が例外を投げたとき、`pass` のままレポートが書かれ、exit は非 0 になるという不整合が起こりえます。cleanup が失敗した場合は、書き込む前に status を `failed` に変更してください。

## 問題なしと判断した点

- **ctypes の構造体定義**: `BasicLimits`、`ExtendedLimits`、`Accounting` のフィールド構成、情報クラス 9 と 1、`OpenProcess` のアクセス権 0x101、DwmFlush の `c_long` 戻り値型。
- **ゲートとタイムアウト**: stdin の gate、3 秒と 30 秒のタイムアウト、0〜500ms の待ち時間の上限、0 との一致判定。
- **status の保存**: `open('x')` による既存証跡の保護、タイムアウト時と not-applicable 時に pass にならないこと。
