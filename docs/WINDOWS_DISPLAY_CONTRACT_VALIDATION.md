# Windowsの表示支援・共通受け入れ（1334）

2026-11-23。基準ソースは`d29bdbe`、Windows / Zig 0.17.1。
Linuxの1333をWindows向けに移し、1326のTk close制御を含む作業ツリーで再実行した。HEADだけでは未コミットの変更を特定できないため、JSONにworking_treeと実行体のSHA-256も記録した。
[実行結果と実行体のSHA-256](measurements/2026-11-23-windows-display-contract.json)。

## 実行方法と結果

PowerShellで次を実行した。ビルド、テスト、結合確認はすべて終了コード0。

```powershell
zig build -Doptimize=ReleaseFast
zig build -Doptimize=ReleaseFast -Dgraphics=false --prefix .work/1334/no-graphics
zig build test
zig build test -Dgraphics=false
python tests/scripts/verify-windows-display-contract.py --no-graphics .work/1334/no-graphics/bin/sigma.exe --output docs/measurements/2026-11-23-windows-display-contract.json
```

スクリプトは自身が起動したSigmaを専用のWindows jobへ割り当ててから、
最初の`KEY`へ入力を送り実行を始める。保存アプリの起動語にも同じ待ちを置く。
成功時はjob内のActiveProcessesが0になることも期限付きで検査する。失敗・30秒の期限切れは所有jobを終了回収する。KILL_ON_JOB_CLOSEも設定し、Pythonの強制終了時にもjobを閉じて子を終了させる。
保存アプリは一時フォルダーで作成・起動し、その後削除する。

| 確認 | 結果 |
| --- | --- |
| 端末 | SHOWと情報取得でnativeやwishを起動しない。サイズ・状態・フレームは0、所属画面は-1。VSYNCは別のホスト機能で、この環境では真。 |
| Tk単独 | 選択だけではwishを起動しない。SHOW後はopen、物理サイズ160×100、画像領域160×80で中央配置。DISPLAYS後は所属画面を取得できる。nativeのサイズ・フレーム・変更回数は0。 |
| 共通エラー | 不正な画面番号とWINDOW-FITは-24、画面へのアルファ書込みは-278、範囲外メモリのGFX-RGBは-9。スタックへの残りなし。 |
| バックエンド切替え | native→端末→Tkでnativeの基本語から画像番号1/1とサイズ160×100を保持していることを照合。Tkの公開語のフレーム情報は0/0・待ち偽。Tkだけ200×120へ変更し、画像領域200×100とnativeとのサイズ差をassert。最後は基本語GFX-WINDOW-CLOSEでnativeだけを閉じる。公開のWINDOW-CLOSEがTkを閉じる経路は別の17段階で確認（下記）。 |
| 保存アプリ | 実際のSAVESYS実行体を新規起動。ウィンドウ・wish・表示一覧・フレーム・変更回数を持ち越さない。辞書内のIMAGE-MODE/ALPHA/SMOOTHは4/127/真を保持。 |
| graphics除外 | 通常版で対象11語の存在を正の対照として確認。除外版ではGRAPHICSと対象語は未定義、REQUIRE-GRAPHICSは-270。 |
| 待ちの基本語と端末のエラー | 端末のFULLSCREENは-21、GFX-FRAME-WAITの範囲外は-24。 |
| 小窓 | 指定64×40と実際のクライアント領域を別々に記録。Windowsの最小幅補正を区別。 |
| 公開の待ち語 | WINDOW-PAINT-WAITは範囲外を0〜60000へ丸め、ウィンドウなしでは偽。スタックへの残りなし。 |

小さいウィンドウではWindowsが幅を広げるため、指定64×40に対して実サイズ120×40となった。
Tk単独は物理サイズ160×100と倍率1を前提としてassertし、取得した倍率の分子・分母も記録する。これは異なる倍率の受け入れではない。Windowsのx11オプションはLinux専用なので、no-x11に相当する構成試験はない。

## 完了の範囲と残件

1334は上記の共通条件の確認として完了。1037・1047全体の完了ではない。
実行中の辞書復元時に現在のfit/smooth/keep-open・表示一覧を保持して画像・clipを消す境界は、
既存の`graphics_test.zig`の回帰テストを今回Windowsで実行した結果による。

TkのWINDOW-FRAMESと待ちは、1300の修正で明示的に未対応の0/0・偽を返す。native併用中も混同しないことを再実行した。
1326のTk close制御と1295の操作行列は、[追加検証](WINDOWS_TK_DISPLAY_VALIDATION.md)で確認した。

物理ボタン・IME・画面の接続変更・DPI差・画面への実提示・速度は今回確認していない。
表示先選択1039、macOS共通受け入れ1335などの既存タスクも保持する。

Claude Codeの初回と作業中の追加レビューへの対応は[レビュー対応](reviews/2026-11-23-windows-display-response.md)を参照。初回は8項目で、レビュー後に小窓の根拠を加えた最終版は9項目。
