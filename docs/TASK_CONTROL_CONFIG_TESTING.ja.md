# タスク制御の構成試験

英語版を主とする：[TASK_CONTROL_CONFIG_TESTING.md](TASK_CONTROL_CONFIG_TESTING.md)。

対象は[構成計画](TASK_CONTROL_CONFIG_MATRIX.md)のC00〜C16である。Zig 0.17.1とPython 3を使い、リポジトリのルートから実行する。機能試験であり、速度・経過時間を測定しない。パッケージの作成とシステムへのインストールは行わない。

## Windows（PowerShell）

```powershell
python tests/scripts/verify-task-public-matrix.py --fresh-cache
```

## Linux x86_64（Linuxの機械上で実行する）

1381の変更を含む同じソースを用意する。書込み可能な作業ツリーと、プロジェクトのビルド手順に従いZig 0.17.1とPython 3をあらかじめ用意する。スクリプトは依存物をダウンロードしない。

```sh
zig version  # 0.17.1を確認する
python3 --version
uname -sm   # Linux x86_64を確認する
mkdir -p .work
python3 tests/scripts/verify-task-public-matrix.py --fresh-cache > .work/task-public-linux.log 2>&1
printf '%s\n' "$?"  # 直前の終了コードを確認する。0が必要である
cat .work/task-public-linux.log
cat .work/task-public-matrix/results.json
```

`--fresh-cache`は呼出しごとに新しい`.work/fresh-*/`内の`.zig-global-cache`と`.zig-cache`を使う。全構成が初めは空の両キャッシュを共有し、実行中の依存物の再利用はあり得る。buildログには`--summary all`を残す。省略時は作業ツリーのキャッシュを使う。成果物と構成別ログは`.work/task-public-matrix/`へ出力する。毎回開始時に`results.json`を`[]`へ戻す。`--configs`で再実行すると以前の行は残らず、選択した完了行だけになる。選択したログは上書きし、他のログには以前の記録が残り得るため、OS別の作業ツリーを使うか先に記録を退避する。JSONに残るのは完了した構成であり、中断・失敗を全構成成功とは扱わない。`commands.json`は実行コマンド・終了コードとログの対応である。標準エラーとプロセス終了コードも保存する。

一部の構成だけを再実行する例である。

```sh
python3 tests/scripts/verify-task-public-matrix.py --configs C08 C11 C12 C16
```

各構成で`zig build test`、実行体build、runtime試験の配置・直接実行、公開58語の有無、debug語の有無を確認する。EXTENSION有効時はForthによる投入・結果・解放・無限ループ取消しと、その後のメイン計算を確認する。files/graphics除外時は能力なしの拒否も確認する。DBGはdebug、EXEC-LIMITEDはdebugとextensionの両方に従う。後者が有効な場合は予算を別途確認する。runtime直接実行のログにより、buildキャッシュに隠れた実行とskipを区別する。

本試験は実窓・音声機器の受け入れ試験ではない。Linuxではデスクトップ・TTY・backendの条件を別途記録する。C16はX11を除くが、成功してもframebuffer等の実画面対応を証明しない。任意試験のskipを実機成功としない。端末入力、音、描画、終了の実機結合と、期限・遅延目標の確認は別の受け入れ作業である。

## クロスコンパイルだけを行う

WindowsのPowerShellからmacOS向け全構成をコンパイルする例である。

```powershell
python tests/scripts/verify-task-public-matrix.py --build-only --target aarch64-macos
```

実行体、core/host/runtime試験実行体と既存のfreestanding境界をコンパイルする。出力先は`.work/task-public-matrix/aarch64-macos/`である。対象OSの実行体は起動しない。macOS実機確認は1383の範囲である。`--target`には`--build-only`が必須である。

E=0の検査は既定検索順の`[DEFINED]`だけである。隠れたbuiltinや検索順から届かないbuiltin、TASK固有HELP項目、保存イメージのbuiltin・直接Op除外は未確認である。有効なkind=2と対応backendのkind=5の受理は、I/O注入・合成描画状態を使う既存の制御されたruntime試験で確認する。ネイティブ窓なしの描画待機には、Linux C16を含めNO-CAPABILITYを要求する。実機受け入れは別である。

各JSON行にはplatform/OS、arch、Zig/Pythonの版、DISPLAY/WAYLAND_DISPLAY/TERM、プロセスのTTY状態、キャッシュパス、runtime成功・skip・失敗件数を記録する。

実測した成否と未実施項目は[1381報告書](TASK_CONTROL_IMPL_1381.md)に記載する。
