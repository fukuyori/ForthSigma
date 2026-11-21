# バージョン更新チェックリスト

製品バージョンの基準値はルートの `VERSION` ファイルです。`build.zig` はこの値を実行ファイルに埋め込み、起動時の表示（`FORTH/Sigma 版番号  MIT License`）に使います。`scripts/build-installer.ps1` はこの値を読み、Inno Setupの製品情報と出力名へ渡します。`scripts/build-zip.ps1` と `scripts/build-zip.sh` も、ZIPの名前にこの値を使います。配布物の版番号を別の値に変える引数はありません（実行ファイルの版番号と食い違わないようにするため）。

## 更新対象ファイル

- `VERSION`: 製品バージョンの基準値。
- `README.md`、`README.ja.md`: 起動時の表示とリリースタグの例。
- `docs/USER_MANUAL.md`、`docs/USER_MANUAL.ja.md`: 起動時の表示例と、ログの例の `start` の行（`"version"`）。
- `docs/DEBUGGING.md`、`docs/DEBUGGING.ja.md`: 起動時の表示例と、ログの例の `start` の行（`"version"`）。
- `src/core/debug_log.zig`: 先頭のコメントにあるログの例の `start` の行。
- `CHANGELOG.md`: その版の見出し（`## [版番号] - 日付`）と、末尾のリンク。
- `docs/DEVELOPMENT_SCHEDULE.md`: 今回の版番号更新と変更内容の記録。
- `docs/HANDOFF.md`: 現在の版番号と更新状況。過去の検証対象の版番号は保持する。

過去の変更履歴や実測値に付けた版番号は、その時点の記録として残す。`build.zig`、インストーラー、リリーススクリプトは `VERSION` を参照するため、固定の版番号を追加しない。

- `docs/SIZE_SPEED_MEASUREMENT.md`: 測定対象の版番号。過去の実測記録として保持し、バージョン更新時には書き換えない。
- `docs/measurements/2026-11-17-size-speed.json`: 上の測定の生データに記録した測定対象の版番号。過去の実測記録として保持し、バージョン更新時には書き換えない。
- `tests/scripts/debug-outputs/macos.json`、`tests/scripts/debug-outputs/windows.json`、`tests/scripts/debug-outputs/linux.json`: 各OSで記録したデバッグ機能の出力。起動時の表示とログの `start` の行に、記録したときの版番号が入っている。記録として保持し、バージョン更新時には書き換えない。記録し直すときは、3つを同じコミットのビルドで記録する。
- `tests/scripts/debug-outputs/README.md`、`tests/scripts/debug-outputs/README.ja.md`: 上の3つを記録したときのOSと版番号の表。記録し直したときだけ、表の版番号を合わせる。

- `docs/measurements/2026-11-20-size-speed.json`: 測定当時の版番号を含む履歴。過去の測定値なので、将来の版へ書き換えない。
- `docs/measurements/2026-11-20-snes-dsp-native.json`: SNES DSPの本体計算の測定で保存した`check-docs.py`の出力に、測定当時の版番号が入っている。過去の測定記録なので、将来の版へ書き換えない。

## リリース時

- [ ] `VERSION` の値を公開する版番号へ更新する。
- [ ] `python scripts/check-docs.py` を実行し、`findings: 0` を確かめる。前のタグの後に加えた組み込み語（HELP と互換性の一覧）とオプション（利用者マニュアルと変更履歴）、すべての組み込み語（利用者マニュアルの本文と「登録済みワード一覧」）、英語版と日本語版の構成、版番号を書いている箇所を、ソースと照合する。
- [ ] 利用者マニュアルの「登録済みワード一覧」の語数を、`sigma -e "WORDS BYE"` が示す語の数と合わせる。「未実装の機能」に、実装した語が残っていないことを確かめる。
- [ ] 機能を除くビルドのオプション（`-Ddebug=false` など）の説明、試験のファイルの一覧、表の行の名前のように、仲間を列挙している文を検索して読み直す（スクリプトは見ない）。除いた版の説明は、その版をビルドして実行で確かめる。
- [ ] 公開する版番号とタグ名を決める。タグ作成・pushは別途明示された場合だけ行う。
- [ ] `scripts/build-installer.ps1` で作ったインストーラー名と製品情報を確認する。
- [ ] 署名付き配布物を作る場合は `CODESIGN_CERT` を確認し、`scripts/build-installer.ps1 -Sign` を使う。署名にはタイムスタンプが付く（既定のサーバーは `http://timestamp.digicert.com`、`CODESIGN_TIMESTAMP_URL` で変更できる）。署名した実行ファイルの `Get-AuthenticodeSignature` で `TimeStamperCertificate` があることを確かめる。
- [ ] 公開前にREADME、変更履歴、互換性情報に版固有の変更があれば反映する。
- [ ] `v` に `VERSION` の値を付けたタグ（例: `v0.1.0`）を作ってプッシュする。タグのプッシュで GitHub Actions の Release が動く。手動起動（Actions > Release > Run workflow）もでき、各OSのZIPは実行の成果物（artifact）から取る。タグで起動したときは、タグと `VERSION` が違うとビルドは失敗する。
- [ ] VERSIONと一致するタグの全ジョブ成功後、CIがGitHub Releaseを作り、Linux x86_64向けの2つのZIPとSHA256ファイルを公開する。ほかの対象向けZIPはActionsのartifactに残る。Windows版2つ（`sigma-版番号-windows-x86_64.zip` と浮動小数点の語を除いた `sigma-版番号-windows-x86_64-nofloat.zip`）は、`scripts/build-zip.ps1 -Sign` で作った署名付きのZIPを添付する（CIの成果物のWindows版は署名なし）。`build-zip.ps1` も `VERSION` の値を使い、`-Version` で上書きできる。
- [ ] macOS では `scripts/sign-and-notarize-macos.sh` で、署名と公証を済ませたユニバーサルの PKG（`dist/pkg/sigma-版番号-macos-universal.pkg`）を作り、リリースに加える。このスクリプトも `VERSION` の値を使い、`--version` で上書きできる。最後に Gatekeeper の確認（`spctl`）で `Notarized Developer ID` と出ることを確かめる。
- [ ] 更新後のソースと生成物の版番号が一致することを確認する（引数なしで起動したときの1行目を含む）。

## バージョン情報を新しいファイルへ追加した場合

- [ ] 本チェックリストを更新し、追加した固定バージョン箇所を列挙する。
- [ ] `VERSION`、`README.md`、`installer/sigma.iss`、リリースビルドスクリプトとの値の受け渡しを確認する。
