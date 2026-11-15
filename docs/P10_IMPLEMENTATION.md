# P10 実施記録

更新日：2026-11-15。tque 742の実施済み作業と残件を記録する。追加確認749〜751も実行・記録を完了した。

## 追加確認の結果（749〜751）

Windows・WSLとも通常構成37件、8種類の単独機能除外構成の統合268件、通常版→機能除外版のイメージ読込7件がすべて成功した。各OS合計312件。全JSONの`complete: true`を確認。通常版の最終ビルドはWindows・Linux用とも成功し、Linux実行体はWSLで検証した。除外版の単体テスト・ビルドは前回成功分を使用し、今回は追加ケースを再実行した。

| 除外機能 | Windows統合成功件数 | WSL統合成功件数 |
| --- | ---: | ---: |
| float | 36 | 36 |
| files | 30 | 30 |
| help | 37 | 37 |
| tools | 37 | 37 |
| image | 24 | 24 |
| graphics | 34 | 34 |
| audio | 34 | 34 |
| debug | 36 | 36 |

再実行結果は`.work/p10-refresh.log`、更新済みの両OSの`matrix.json`と構成別`no-*-integration.json`、`windows-default.json`・`linux-default.json`、両OSの`cross-build.json`に記録。最終ビルドログは`.work/p10-windows-final-build.log`と`.work/p10-linux-final-build.log`。HELP・英日マニュアル・互換性一覧の閉じたパイプのエラー説明を揃え、`DECISIONS.md`へ検証範囲を記載した。文書チェックは`.work/p10-docs-final.log`で指摘0件、`git diff --check`も成功。保存画像のSIGIMG45/46/47の検証は描画・音声デバイスの実機動作確認を意味しない。機能除外は単独8構成であり、複数同時除外の全256構成ではない。

## 追加確認前の実施記録

- `scripts/verify-p10.py`を作成し、マクロ・無名定義・検索順・型付き参照・例外・FORGET/MARKER・保存/復元・破損イメージ拒否を組み合わせて検証した。Windows通常構成は37件成功、WSL通常構成は追加前の25件成功。証跡は`.work/p10/windows-default.json`、`.work/p10/linux-default.json`。両方とも`complete: true`を確認した。
- `scripts/verify-feature-matrix.py`を作成し、以下の8種類の単独機能除外構成で、Windowsのビルド・単体テスト、Linux用ビルドとWSL上の単体テスト、各構成の統合テストが成功した。Linuxのテスト実行体はWindowsでクロスコンパイルし、WSL上で実行した。Linux版Zigでのビルドランナー実行を意味しない。

| 除外機能 | Windows統合成功件数 | WSL統合成功件数 |
| --- | ---: | ---: |
| float | 30 | 30 |
| files | 24 | 24 |
| help | 31 | 31 |
| tools | 31 | 31 |
| image | 24 | 24 |
| graphics | 31 | 31 |
| audio | 31 | 31 |
| debug | 30 | 36 |

上表は追加確認前の成功件数。単体テスト・ビルドの証跡は各OSフォルダーの`no-*-tests.log`、`no-*-build.log`。WSL実行ログは`no-*-native-test-0.log`と`no-*-native-test-1.log`。統合JSONとmatrixは今回の再実行結果へ更新済みであり、現在の件数は冒頭の追加確認結果を参照する。

- `scripts/verify-p10-cross-build.py`を作成し、Windows通常版の保存イメージを7種類の機能除外版へ読み込む検証が7件成功した。float除外版では保存済みの浮動小数点語を実行すると-261になり、除外機能の実行を拒否した。証跡は`.work/p10/windows/cross-build.json`。image除外版には読込機能がないため対象外。
- 英日マニュアルの登録語索引、互換性一覧の不足、古い未実装表記、日本語のP07/P08表を修正した。`scripts/check-docs.py`はMarkdownのエスケープされた縦棒を扱い、追加語だけでなく組込み950語を確認するよう変更した。`python scripts/check-docs.py`は指摘0件。証跡は`.work/p10-docs.log`。
- HELPのBROKEN-PIPE-ERROR説明にWindows CRTでEINVALになる場合を明記した。

主な実行方法：`python scripts/verify-feature-matrix.py --platform windows`、同`--platform linux`。通常構成は`python scripts/verify-p10.py --sigma <実行体> --output <JSON>`、構成間読込は`python scripts/verify-p10-cross-build.py --default <通常版> --matrix <除外構成フォルダー>`。

## macOS実機での確認（2026-11-15、tque #752）

macOS arm64・Zig 0.17.1で通常版・単独機能除外8構成のビルド・単体テスト・P10統合と構成間保存読込が成功した。通常37件＋除外268件＋構成間7件＝312件。通常単体は1062成功・7 skip。ランタイム13件、文書チェック指摘0件、実行時辞書と使用例の照合も成功した。[環境・件数・証跡・再実行方法](MACOS_P10_VALIDATION.md)を参照する。マトリックスの実行には`--platform macos`を使用する。

Windows・WSL・Linuxネイティブ・macOSのP10確認が揃った。tque 752・742・553・542を子から順に完了とし、542配下全件のdone・auto100%をコマンドで再照会した。単独機能除外8構成という検証範囲を維持し、全256構成や表示・音声デバイスの実動作確認とは区別する。

## Linuxネイティブでの追加確認（2026-11-15、tque #754）

Windows経由のWSL確認とは別に、Linux版Zigのビルドランナーから通常版・8単独機能除外構成のビルド・単体テストと、P10統合・構成間保存読込の計312件が成功した。追加の境界482件・PTY/FIFO24件・POSIX統合10件・ランタイム13件と文書チェックも成功した。[環境・証跡・結果](LINUX_P10_VALIDATION.md)を参照。macOS実機の#752とは別管理とする。
