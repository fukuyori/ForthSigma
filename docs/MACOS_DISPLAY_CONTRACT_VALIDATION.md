# macOSの表示支援・共通受け入れ（1335）

2026-11-23、macOS 27.2.1（arm64）、Homebrewのwish（Tcl/Tk 9.1.0）、Zig 0.17.1。`4835696`の実行体と、同じソースの`-Dgraphics=false`の実行体。SHA-256はJSONに記録している。

`python3 tests/scripts/verify-macos-display-contract.py --no-graphics <graphicsなしのsigma> --output docs/measurements/2026-11-23-macos-display-contract.json`

[結果](measurements/2026-11-23-macos-display-contract.json)。Linuxの`verify-linux-display-contract.py`をmacOSへ移した（プロセスグループで所有する`macos_display_test_support.py`を使う）。6群がすべて成功した。

| 群 | 確かめたこと |
| --- | --- |
| 端末 | `DISPLAY-TERMINAL`で`SHOW`しても、ネイティブのウィンドウもwishも起動しない。状態はすべて0、`WINDOW-DISPLAY`は-1 |
| Tkの対応表 | `DISPLAY-TK`で、選んだだけではwishを起動せず、`SHOW`でTkが開く。macOSではTkの`WINDOW-PIXELS`と`WINDOW-IMAGE-RECT`は0（1288）。フレームは0 0・偽、`VSYNC-WAIT`は偽 |
| エラー | 存在しないディスプレイ番号と`3 WINDOW-FIT`は-24、画面への`GFX-ALPHA-PSET`は-278、不正な`GFX-RGB`は-9。スタックは残らない |
| 表示先の切替え | ネイティブで64×40を開くと64 40・描いた数1 1・待ちは真。端末へ切り替えてもネイティブのウィンドウは開いたまま答える。Tkを選ぶとTkについて答え（フレームは0）、ネイティブの値は流用しない。`GFX-WINDOW-CLOSE`でネイティブだけが閉じ、Tkは開いたまま |
| 保存アプリ | 表示中に`SAVESYS`した実行体を新しく起動すると、ウィンドウ・表示一覧・回数は持ち越されず0。辞書の変数（`IMAGE-MODE` 4、`IMAGE-ALPHA` 127、`IMAGE-SMOOTH`真）は保存値 |
| graphicsなしのビルド | `REQUIRE-GRAPHICS`は-270、`GRAPHICS`と表示の語は定義されていない。通常のビルドでは同じ語がすべて定義されている（正の対照） |

LinuxのX11なしビルドの群は、macOSに対応するビルドがないので除いた。`WINDOW-DISPLAY`はこのスクリプトでは`DISPLAYS`を呼ぶ前なので-1（文書のとおり）。所属画面の値は1259の確認で見ている。

Tclからの合成操作と、プログラムからの操作だけで、物理ボタンや画面への実提示は確認していない。macOS固有の個別確認は、ディスプレイ情報1259、大きさと回数1266、置き方1286、補間1320、状態1297、閉じる要求の保留1328、フレーム1302、Tk（[MACOS_TK_DISPLAY_VALIDATION.md](MACOS_TK_DISPLAY_VALIDATION.md)）を参照。
