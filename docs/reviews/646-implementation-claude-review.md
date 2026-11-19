# 646 実装レビュー原文

2026-11-20。固定コピーを読み取りのみで確認。実行試験はロクが別途行う。

# 646 実装レビュー(凍結版 `.work/646/implementation-review`)

レモン、凍結ファイルを Read/Grep だけで確認しました。コマンドもテストも実行していないため、テスト結果はすべて「未確認」です。main.zig は FileSlot、LineSource、fileRead、prepareFileRead/Write、fileSync、fileKey、event probe の範囲だけを読みました。

**High はありません。** Medium が3件、Low が4件です。

## 問題がなかった項目

- **prepareFileRead の方向修正**: C の読み取り4経路(LineSource:755、fileRead:832、fileKey:1149、event probe:1734)はすべて prepareFileRead を通ります。それ以外の `getc`/`fread` は画像の読み込み専用ストリームだけです。
  - `access == .read_write` かつ `!last_read` のときだけ fflush し、成功した場合だけ `last_read` を立てます。
  - そのため「最後の操作が入力」の状態で fflush する未定義動作は生じません。ZZ→NUL の原因(書込み後に flush も位置付けもせず読み取ること)への対処として正しいです。
- **SYNC**: 拒否の順序は設計どおりで、標準ID → EBADF → pipe/proc → regular判定 → readonly の順に、fflush より前に判定しています。
  - `last_read` のときは `seek64(0,SEEK_CUR)` だけを行い、`input` と `eof` には触れません。
  - 失敗しても fileid を閉じません。
  - Windows の worker は `GetFileType==3`(pipe)だけで起動するため、通常ファイルが worker の対象外という前提(M7)とも一致します。
- **コア**:
  - スタックの容量と全メモリ範囲を、ホストを呼ぶ前に検査しています。
  - `release` は `defer` なので、HostFailed の経路でも必ず解放されます。
  - `registry.written` は実際に書いたバイト数だけを通知しています。
  - REALPATH はホスト側で名前をスタックバッファへ複製してから OS に渡すため、入力と出力が重なっても安全です。
- **COMPACT**: `compactInto` の出力長が入力長を超えないことを確認しました。部分文字列の書込み位置がその部分の入力位置を超えないので、scratch に入力長ぶん確保すれば足ります。
- **mtime**:
  - `ticks/1e7 - 11644473600` と `(ticks%1e7)*100` は、FILETIME が符号なしなので floor 分解と同じ結果になり、u32 にも収まります。
  - POSIX の `tv_nsec` は正規化済みです。
- **UTF-8**: `MB_ERR_INVALID_CHARS` は、既存の `wide_c.from`(`utf8ToUtf16Le`、厳格)と同じく不正な列を拒否します。
- **ネイティブの確保と解放**: Windows realpath の realloc ループ、エラー時の `free(result)`、CloseHandle のエラー合成に漏れはありません。

## Medium

### M1. Windows: 明示 namespace の拒否に抜け道がある(`\??\` と予約デバイス名)

`wide_name`(native.c:35-51)が拒否するのは `\\.\`、ドライブ以外の `\\?\`、UNC の pipe share だけです。

- **`\??\` 接頭辞**: Win32 のパス変換は `\??\` をそのまま NT パスとして通します(※既知の挙動に基づく推測です。実機では未確認)。`/??/pipe/x` は `/`→`\` 変換で `\??\pipe\x` になり、CreateFileW が名前付きパイプへクライアント接続する可能性があります。
- **予約デバイス名**: `COM1`、`CONIN$`、`NUL` などは明示 namespace ではないため、そのまま CreateFileW で開かれます。METADATA の `GetFileType` による拒否は open の後です。シリアルポートは開いただけで制御線が変化するなどの副作用があります(※推測です)。

修正案(`wide_name` 内):
1. `wcsncmp(p, L"\\??\\", 4) == 0` なら EINVAL。
2. `GetFullPathNameW(p, ...)` の結果が `\\.\` で始まるなら EINVAL。予約名は `\\.\COM1` に展開されます。展開するかどうかは OS の版に従うので、Windows 11 の規則変更にも追従します。判定だけに使い、open には元の `p` を渡します。

テストへ追加するもの: `S" /??/pipe/sigma-x"` と `S" COM1"` に対して REALPATH と METADATA を呼び、EINVAL が返り、open が起きないこと。

### M2. H2・設計で約束した回帰テストが不足している

`verify-filesystem.py` の SYNC のケースは、READ-FILE の経路(66行)と write→READ-FILE→SYNC(69行)だけです。69行も最終ファイルの内容だけを見ていて、読んだバイトと位置は検査していません。追加案は次の3つです。

1. **保留入力**: 内容 `a\rbc` のファイルで READ-LINE を行うと、CR の先読みで `b` が decoder に入ります。続けて SYNC → FILE-POSITION(2 になること)→ READ-FILE で `bc` が返ること。
2. **EOF の保持**: 末尾まで READ-FILE → SYNC → READ-FILE が 0 と ior=0 を返すこと。
3. **4経路**: write の直後に READ-LINE、KEY-FILE、event probe の経路でそれぞれ読み、読んだ値と内容に NUL が混入しないこと。69行には、読んだ 1 バイトが `a` であることと、SYNC 後の位置が 3 であることの検査も足します。

### M3. 全語参照とマニュアルに4語がない

- `docs/WORD_REFERENCE(.ja).md` と `USER_MANUAL(.ja).md` を Grep しても、4語は 0 件でした。
- 一方、`help_text.zig`、`translations.ja.tsv`、`usage-overrides.json` には入っています。
- 設計の「検証」節は英日のマニュアルと全語参照の更新を求めています。
- `scripts/word-reference.py` による再生成が未実行と推測されます(生成手順は未確認)。

## Low

- **L1 COMPACT の heap 依存**: ALLOCATE の heap を使うため、heap が枯渇・断片化していると -257 になります(HELP には記載済み)。Gforth は失敗しません。上で確認した「書込み位置 ≦ 読取り位置」の性質を使えば、`@memcpy` を `std.mem.copyForwards` に替えるだけで元の領域内で整理でき、heap も -257 も不要になります。設計で採用済みの方式なので、変えるかどうかの判断はレモンに委ねます。
- **L2 長すぎる名前の ior**: 4096 バイト以上の名前に対して `nameBytes` は EINVAL を返しますが、既存の OPEN-FILE は ENAMETOOLONG を返します。ENAMETOOLONG の値は OS ごとに違うため、長さの判定を C 側へ移すのが簡単です。
- **L3 Windows エラーの対応**: `ERROR_INVALID_DRIVE`(15)、`ERROR_BAD_NETPATH`(53)、`ERROR_BAD_NET_NAME`(67)が EIO になります。存在しないドライブ・共有に対しては ENOENT にする案です(UCRT の対応表は未確認)。
- **L4 `last_read` が立つ範囲**: prepareFileRead は write_only のスロットでも `last_read=true` にします。そのため SYNC が fflush ではなく seek の経路を通ります。ISO C では fseek が未書込みの出力を書き出すので結果は正しいですが、意図をはっきりさせるため、`access == .write_only` のときは `last_read` を立てない案です。

## 対応の優先順

1. M1 の `\??\` と予約名の拒否、そのテスト
2. M2 の回帰テスト追加(コードの修正は不要と見込みます)
3. M3 の文書再生成
4. L1〜L4 はレモンの判断で

凍結ディレクトリの `result.json` は空でした。この指摘をそこへ書き込むかどうかは、レモンの指示を待ちます。
