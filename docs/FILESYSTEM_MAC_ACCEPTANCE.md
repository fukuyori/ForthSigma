# 646 Mac実機受け入れ（1116）

未実施。Mac向けクロスコンパイルを実機合格と扱わない。
640の書記素Mac1111とは別のタスク。Macの機種・OS・Zig版・Git状態を記録する。

```sh
zig version
zig build test --summary all
zig build
python3 tests/scripts/verify-filesystem.py --sigma zig-out/bin/sigma --output .work/646/mac-public.json
zig build test -Dextension=false --summary all
zig build test -Dfiles=false -Dgraphics=false -Daudio=false --summary all
python3 scripts/check-docs.py
```

確認内容：Gforth参照1,010例、長いCOMPACT、実パスのsymlink・短buffer・cap0・alias、
metadataの秒/nsと通常ファイル限定、SYNCの方向切替・位置/保留入力・EOF・readonly/pipe/device拒否。
公開語scriptは作業用のファイルを.work/646配下へ作り、所有するファイルだけを後始末する。
負時刻の設定がOS/ファイルシステムで丸められた場合は、statで観測した実際の値を記録し、
負時刻を検証できた扱いにしない。Macの同期はfsyncでありF_FULLFSYNCではない。

結果を実装記録へ転記し、1116の現在のタイトルと親子関係を再照合して完了にする。
646全体は全子の完了後に完了にする。コミット・タグ・push・配布物作成はこの手順に含めない。
