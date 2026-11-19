# テストと検証のスクリプト

リポジトリのルートから実行します。`test-*`は回帰テスト、`verify-*`は統合・比較の
確認、`probe-*`は参考結果の収集です。`gforth-p00/`にはP00のGforth参照テストが
あります。必要な参照ビルドはそのREADMEを確認してください。各スクリプトの
OS・参照実行環境の条件も満たす必要があります。

実行例:

```sh
python3 tests/scripts/test-word-reference.py --sigma zig-out/bin/sigma
python3 tests/scripts/test-line-editor.py --sigma zig-out/bin/sigma
python3 tests/scripts/verify-p10.py --sigma zig-out/bin/sigma --output .work/p10/report.json
python3 tests/scripts/verify-feature-matrix.py --platform macos
python3 tests/scripts/verify-debug-outputs.py --sigma zig-out/bin/sigma --out tests/scripts/debug-outputs/windows.json
python3 tests/scripts/verify-debug-outputs.py --compare tests/scripts/debug-outputs/macos.json tests/scripts/debug-outputs/windows.json
```

ビルド・配布・データ生成・文書生成・ベンチマークのコマンドは`scripts/`にあります。
`check-docs.py`、`word-reference.py`、その補助の`word_reference_examples.py`、
`benchmark-runtime.py`も同じです。`test-benchmark-runtime.py`にはLinuxの
プロセスCPU時計APIが必要です。

`debug-outputs/`には各OSで`verify-debug-outputs.py`が記録した結果があり、
`--compare`で比較できます。

`check-ime.fs`は合否を自動判定しない手動確認です。`GUI-FIELD`を表示し、IMEで
入力した日本語とそのバイト列を出力します。実行方法はファイル冒頭にあります。

`check-window.fs`もSigma自身のウィンドウの手動確認です。マウスの押下・解放・
ホイールを出力し、入力待ちや計算中の移動・リサイズ・閉じる操作を確認できます。
実行方法はファイル冒頭にあります。

`check-fullscreen.fs`は`FULLSCREEN`と`MOUSE-CURSOR`の手動確認です。ウィンドウが
フルスクリーンで開き、キーで解除・再びフルスクリーン・カーソルの表示切替を試せます。
キーと見る点はファイル冒頭にあります。

`check-auto-size.fs`は`WINDOW-SIZE 0 0`の手動確認です。3つの画像を順に表示し、
ウィンドウが画面の作業領域に収まることを確かめます。見る点はファイル冒頭にあります。

過去の測定JSONと外部レビュー原文には、記録当時のパスを残しています。
現在の実行コマンドは`tests/scripts/`を使います。

Linuxの実験用X11バックエンドは`zig build -Dx11=true`でビルドします。
`test-linux-native-window.py`は画素・黒余白・キー・閉じて再表示を確認し、
`SIGMA_TEST_RESIZE=1`でリサイズの再描画も確認します。private Xvfbだけで、
`SIGMA_TEST_REMAP=1`によるキーマップ変更と、`test-linux-xim-fixture.py`による
preeditの差分・Unicode確定・IMの生存確認を試せます。この2つは
`SIGMA_TEST_PRIVATE_XSERVER=1`が必要で、利用者のデスクトップには適用しません。
`SIGMA_TEST_CLOSE_AFTER=6`は初回作成期限の後に閉じて再表示する確認です。
`test-linux-x11-failures.py`は自分専用の一時ソケットで接続拒否・切断・無応答を確認します。
実行ファイルは`SIGMA_TEST_BINARY`で選べます。

`test-linux-display-budget.py`は実験用Linuxビルドで、自動探索全体の5秒期限、
PNG送信の詰まり、無応答・停止した子、少量ずつ続く応答、回収、再試行、失敗後の
明示的Tcl実行を確認します。一時的なwish代替プログラムと専用ローカルソケットを
使い、デスクトップには接続しません。プロセス起動とスケジューリングを含む
受け入れ許容値は5.25秒です。

`check-window-keys.fs`は特殊キー・リピート・フォーカス喪失の手動確認用に、
キーコードとAの押下状態を記録します。stdinを`/dev/null`にして端末入力を除外します。
Escapeで終了し、窓のCtrl+Cはキー読込と押下状態読込の両方で捕捉します。繰り返しの
コードとVM処理時刻は利用者の操作報告と照合します。手順はファイル先頭を参照してください。

`test-linux-window-colors.py`はフルカラー/2/16/256色とディザリングの8設定で、
整数倍率のリサイズ前後のnativeとTkの画素を比較します。
`test-linux-auto-display.py`は自動選択、選択済み表示先の切断、明示指定の失敗、
`DISPLAY-AUTO`での復帰を確認します。両方とも認証付きdepth24の専用Xvfbを起動し、
利用者のDISPLAYには接続しません。XvfbがPATHにない場合は`SIGMA_TEST_XVFB`、
実験用Linux実行ファイルには`SIGMA_TEST_BINARY`を指定します。Xvfb/wishがなければ
成功扱いにはせず、終了コード77でskipと報告します。
`test-linux-x11-support.py`は共通ヘルパーの途中行の期限、stderrの詰まり防止、
プロセスグループ回収、X11認証、skipの終了状態を確認します。

`check-window-display.fs`は色・リサイズ・画面間移動の手動確認です。色帯・灰色階調・
4つのクリック対象を表示し、0/2/6/5で色数、Dでディザリングを切り替えます。
デスクトップの表示設定は変更しません。手順はファイル先頭を参照してください。

### 子プロセス管理（643）

`verify-process-words.py --sigma PATH`は公開PROC語とFILE/AVAILABLEによる3ストリームの
大量入出力を確認します。`verify-process-interrupt.py --sigma PATH`は無期限待機の中断と
子プロセスの生存を確認します。Windowsの中断試験は専用の非表示consoleを作り、
その中だけにCtrl+Cを送ります。

制御したfixtureは`zig cc tests/process_wish_fixture.c -o .work/643/wish-fixture.exe`で作成し、
`verify-process-capacity.py --sigma PATH --fixture PATH`で64実プロセスと上限超過・再利用を、
`verify-process-tcl.py --sigma PATH --fixture PATH`でTcl内部予約枠・再起動・script削除・
終了時の子孫回収を確認します。Linux用fixtureは
`zig cc -target x86_64-linux-musl`で作成し、WSL内でLinux版Sigmaと実行します。
fixtureは実Tcl/TkやGUI表示の代用ではありません。

native C単体は`zig cc -shared -DSIGMA_PROC_TESTING src/host_process_native.c -o .work/643/process-native.dll`
と`verify-process-native.py --library PATH`で確認します。LinuxのPython ctypesにはGNU共有libraryを
使います。Linuxの子孫試験は専用helperのsubreaper設定を一時変更し、自分で起動した子孫を回収して
元へ戻します。製品Sigmaではsubreaperを設定しません。

各scriptの`--output PATH`でJSONの結果を保存できます。OS単体・公開語・Tcl protocol・実GUIを区別し、
Macのクロスコンパイルを実機確認の代わりにしません。
