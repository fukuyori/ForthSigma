# 646 ファイルシステム拡張の着手確認

2026-11-20。レモンの「Macの確認は残して次へ」の指示で、640のMac実機1111を残し、
独立して開始可能な646へ進む。640の未コミット差分を保持し、コミット・タグ・pushはしない。

## 現在の確認結果

- tque646は親1002、先行1056、未着手0%・blocked=false。タイトルは
  COMPACT-FILENAME、実パス、更新時刻と大きさ、同期の語の要否。
- 既存FLUSH-FILE（src/main.zigのfileFlush）はCのfflush。OS同期とは分ける。
- RENAME-FILEは既存語を維持する。新しい置換語とOS変更監視は追加しない。
- 実パスの出力は既存詳細設計の「呼出し側バッファへコピー」を基準にする。
  語名、長さ不足、入力/出力重複、文字列形式、リンク切れ、競合は詳細設計で具体化する。
- 時刻とサイズを同じ照会で取得する語の名前、単位、符号、失敗時の結果を具体化する。
  同じ値だったことだけで変更なしと保証したり、単調時計と混同したりしない。

## Gforthとの動作照合

WSL上のGforth1.0.2 amd64で18例を実行した。ログと入力は
.work/646/{compact-probe.fs,gforth-compact.log}。Gforthのコードを転載・移植するのでなく、
振舞いを照合して既存のSigmaの正規化処理を公開する方針。ライセンスの異なるコードはコピーしない。

| 入力 | 出力 |
| --- | --- |
| 空 | 空 |
| `.` / `..` | そのまま |
| `./` | 空 |
| `a/.` / `a/..` | そのまま |
| `a/../` | 空 |
| `a/./b` | `a/b` |
| `/../../a` | そのまま |
| `//server/share/a/../b` | `/server/share/b` |
| `C:/a/../b` | `C:/b` |
| `a\b\..\c` | そのまま |

全18例で戻り値の先頭アドレスは元の先頭と一致した。文字列整理は実在確認や
リンク解決ではなく、OSの実パス取得と別の契約にする。

## 利用者へ確認する範囲

OS同期の語を追加するかは計画で明示的に未決のため、実装前に確認する。
提案は`SYNC-FILE ( fileid -- ior )`を追加し、通常ファイルについてCバッファの書出し後に
POSIX fsync / Windows FlushFileBuffersを要求する。既存FLUSH-FILEの意味は変更しない。
pipe・端末への同期は対象外として検査し、OS呼出しの失敗はiorで報告する。
この語単独でrename後の親ディレクトリや停電時の永続性を保証しない。

根拠：[FlushFileBuffers公式](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-flushfilebuffers)、
[Linux fsync](https://man7.org/linux/man-pages/man2/fsync.2.html)。
WindowsのFlushFileBuffersは書込み権限を要求し、pipeでは相手の読取りを待ち得る。
Linuxのファイル同期だけでは親ディレクトリの同期まで保証しない。

## 採否の確定と後続

レモンの「進めて」でSYNCを含める方針を確定した。
具体的なAPIと失敗契約は[採用設計](FILESYSTEM_DESIGN.md)、レビュー評価は
[646の評価・対応](reviews/646-review-response.md)を参照する。上の提案は着手時の記録。
