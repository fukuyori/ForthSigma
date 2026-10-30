# バージョン更新チェックリスト

製品バージョンの基準値はルートの `VERSION` ファイルです。`build.zig` はこの値を実行ファイルに埋め込み、起動時の表示（`FORTH/Sigma 版番号  MIT License`）に使います。`scripts/build-installer.ps1` はこの値を読み、Inno Setupの製品情報と出力名へ渡します。`-Version MAJOR.MINOR.PATCH` を指定するとビルド時だけ上書きできます。

## リリース時

- [ ] `VERSION` の値を公開する版番号へ更新する。
- [ ] 公開する版番号とタグ名を決める。タグ作成・pushは別途明示された場合だけ行う。
- [ ] `scripts/build-installer.ps1` で作ったインストーラー名と製品情報を確認する。
- [ ] 署名付き配布物を作る場合は `CODESIGN_CERT` を確認し、`scripts/build-installer.ps1 -Sign` を使う。
- [ ] 公開前にREADME、変更履歴、互換性情報に版固有の変更があれば反映する。
- [ ] 更新後のソースと生成物の版番号が一致することを確認する（引数なしで起動したときの1行目を含む）。

## バージョン情報を新しいファイルへ追加した場合

- [ ] 本チェックリストを更新し、追加した固定バージョン箇所を列挙する。
- [ ] `VERSION`、`README.md`、`installer/sigma.iss`、リリースビルドスクリプトとの値の受け渡しを確認する。
