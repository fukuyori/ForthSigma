# 640 Mac実機受け入れ（1111）

未実施。aarch64-macosのクロスコンパイルはMacでの実行合格ではない。
Mac上のcheckoutで、OS・機種・Zig版・対象commitと未コミット差分を記録してから実行する。

```sh
zig version
zig build test --summary all
zig build
python3 scripts/make-grapheme-table.py --check
python3 tests/scripts/verify-graphemes.py --sigma zig-out/bin/sigma
zig build test -Dextension=false --summary all
zig build test -Dgraphics=false -Daudio=false -Dfiles=false --summary all
```

期待：通常単体の公式853ケース、UTF-8境界・異常系、前方の先読み制限、長い結合列、
GB9c/GB11の交差、画像復元、除外時の辞書・HELP・実行拒否が成功する。
公開語の独立照合は853ケース・3,096項目で成功する。表示幅の変更は対象外。
試験ログをMac側の.work/640-mac等へ保存し、本文記録へ結果と除外を転記する。
成功後に1111と640のタイトル・親子関係を再照合し、全子の完了を確かめて完了にする。
パッケージ作成・コミット・タグ・pushはこの受け入れ手順に含めない。
