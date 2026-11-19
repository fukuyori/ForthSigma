# 646 詳細設計レビュー原文

2026-11-20。固定コピーの読み取り専用レビュー。

# 646 設計レビュー（`.work/646/design-review/design.md`）

レモン、確認が終わりました。今回は Read/Grep/Glob による読み取りだけで、ファイルの変更やコマンドの実行はしていません。Gforth 1.0.2 の実際の動きは、今回は確かめていません（未確認）。

## High

**H1. 既存の `normalize` は 1024 バイトまでしか扱えず、非公開で、FPATH 探索も同じ関数を使っている**
- `src/core/paths.zig:114` で `capacity = string_buffer_count * string_buffer_size` = 4×256 = 1024 と決まっています。`normalize` の `Buffer.append` は、これを超えると `StringTooLong`（-18）を返します。一方、設計では「長いパスを確認」と書いていますが、COMPACT の入力長の上限も、上限を超えたときの扱いも決めていません。
- `starts`/`parents` は `[capacity]` の配列で、スタック上に置かれます。上限を上げると、スタックの消費もそれに比例して増えます。
- `fn normalize` は `pub` ではありません（`paths.zig:133`）。また `candidate()`（`paths.zig:176`）が OPEN-PATH-FILE / FILE>PATH の中で使っています。COMPACT を Gforth に合わせるために `normalize` を変えると、**FPATH 探索の結果も同時に変わります**。
- **決める値**:
  - (a) COMPACT の上限をなくす（元の領域の中で処理し、出力が入力より長くならないことを利用する）か、1024 のままにするか。1024 のままなら、超えたときの THROW コード（-18 か）。
  - (b) 共有する関数を変えたとき、FPATH の結果も変わってよいか。変わってよいなら、FPATH の回帰テストも検証項目に加える。

**H2. SYNC の「最後の方向が read なら未配送の書込みはない」という前提を、既存のコードは保証していない**
- `FileSlot` が持つ方向の情報は `last_read` だけです（`main.zig:422`）。書込み側の印はありません。
- 読込み側（`main.zig:827`, `:1113`, `LineSource.get` `:754`）は、書込みのあとに fflush/fseek をせずに `last_read = true` にしています。「write → read → SYNC」の順で呼ぶと、C ライブラリが書込みバッファを掃き出したかどうかに左右されます。※C 標準ではこの順序は未定義動作で、UCRT と glibc で動きが違う可能性があると推測されます。
- **決める値**:
  - (a) 読込み側でも、書込み直後なら `prepareFileWrite` と対称に fseek/fflush する。
  - (b) または SYNC で、`last_read` のときに `seek64(file,0,SEEK_CUR)` を使う。この場合 `input.length` の保留と `eof` は FileSlot 側が持っているので、変わらないことを確認する。
  - どちらにしても、「write→read→SYNC のあと、別のハンドルから内容を読む」試験を加える。

**H3. SYNC の拒否条件の評価順序と ior の値が決まっていない**
- 標準ストリームの ID は `openedFile()` で null になります（`main.zig:461`）。そのため、素直に書くと EBADF になり、設計の EINVAL と合いません。
- Linux では `fopen(dir,"rb")` が成功するので、「read-only のディレクトリ」が fileid として存在します。この場合、EINVAL と EACCES のどちらを先に返すかが決まっていません。
- 種類の判定に `native_pipe` だけを使うと、キャラクタデバイス（`/dev/null`、Windows の `NUL`/`CON`）を見逃します。`sigma_file_is_pipe`（`src/host_file_kind.c:6`）は FIFO とソケットしか判定しません。
- **決める値（提案する順序）**:
  1. 標準 ID なら EINVAL
  2. 範囲外または閉じた ID なら EBADF
  3. `pipe`/`native_pipe`/`proc_owner≠0` なら EINVAL
  4. その時点で fstat `S_ISREG` を確認する。Windows では `GetFileType==FILE_TYPE_DISK` かつディレクトリ属性でないことを確認する。通らなければ EINVAL
  5. `access==.read_only` なら EACCES
- 種類の判定は、`host_file_kind.c` に関数を足して行うことを推奨します。

**H4. REALPATH の callback が Forth メモリへ直接書くと、「失敗時は buffer 無変更」と registry の整合が崩れる**
- 設計の「callback の長さを再検査」という記述は、callback が `[]u8` を通じて Forth メモリへ直接書くことを想定しているように読めます。
- Windows では UTF-16 から UTF-8 への変換の途中で、孤立サロゲートによる失敗（`wide_c.errno_illegal_sequence`=42、`main.zig:46`）が起こり得ます。途中まで書いた後に失敗すると、buffer は変わっているのに `registry.written` が呼ばれない状態になります。
- **決める値**: callback はホスト側の確保領域へ結果を書き、長さだけを返す。core が capacity を比べてから `copyMemory` する。この方式なら、入力と出力が重なっても安全です。

## Medium

**M1. -21 は既存の慣例と異なる**
- files が無いときは `fileOps()` が `HostUnavailable` を返し、これは -21 になります。
- しかし、optional callback が欠けている場合、既存のコードは `error.FileUnavailable` = **-263** を返しています（`directories.zig:19,49,86`、`defs.zig:1193`）。
- -21 にするなら、それが意図的であることを設計に明記してください。

**M2. 負の長さの扱いが既存のファイル語と異なる**
- `memoryRange` は負の u を空文字列として扱います（`forth.zig:2467-2472`）。
- 設計の「負の長さは -9」は、DELETE-FILE などの既存語と動きが違います。
- capacity=0 のときに buffer アドレスを検査するかどうかも決めてください。`memoryAddress(addr,0)` は、addr がメモリ長以下なら通ります。

**M3. SYNC の read-only を EACCES にするか、EBADF にするか**
- 既存の `fileIoCheck` は、方向が違う場合に EBADF を返します（`main.zig:1179`）。
- POSIX の fsync は EACCES を返しません。EACCES にするなら、その理由を記録しておくことを推奨します。

**M4. Windows の REALPATH の出力は、既存の `absolute()` で絶対パスと判定されない**
- `paths.zig:128` が絶対パスとみなすのは、`/`、`~`、`./`、2 文字目が `:` のものだけです。
- このため `\\?\C:\...` や `\\?\UNC\...` を OPEN-PATH-FILE や REQUIRED に渡すと、FPATH が前に付けられてしまいます。
- **決める値**: 次のどちらかにする。
  - `VOLUME_NAME_DOS` で得た `\\?\X:\` は `X:\` に戻す。
  - `absolute()` が `\\` で始まる形も絶対パスとして扱うようにする。
- また、出力が 4095 バイトを超えると、そのパスを OPEN-FILE で開けません（`cPath`、`main.zig:1006`）。この制約も明記してください。

**M5. Windows で開くときのフラグと値**
- CreateFileW の引数を、次のように具体的に書いてください。
  - アクセス権: `0`（または `FILE_READ_ATTRIBUTES`）
  - 共有モード: `FILE_SHARE_READ|WRITE|DELETE`
  - フラグ: `OPEN_EXISTING`、`FILE_FLAG_BACKUP_SEMANTICS`
- `BACKUP_SEMANTICS` を付けないと、ディレクトリを開いたときに ACCESS_DENIED になります。その結果、METADATA は EINVAL ではなく EACCES を返し、REALPATH はディレクトリを扱えません。
- `\\.\pipe\...` を開くと、名前付きパイプのサーバーに接続するという副作用があります。これを拒否するか、許すかを決めてください。
- GetFinalPathNameByHandleW は、バッファが足りないと必要な長さを返します。そのため、2 回呼び出す形にする必要があります。
- GetLastError から errno への対応は、既存の表（`main.zig:1034` の 2/3→ENOENT、5/32→EACCES、それ以外→EIO）と共通にすることを推奨します。

**M6. METADATA の時刻**
- FILETIME の変換は「(t − 116444736000000000) を floor で割る」と式で書いてください。
- FILETIME=0（ファイルシステムが値を記録していない場合）をどう扱うか決めてください。
- POSIX 側は、Linux の `st_mtim` と macOS の `st_mtimespec` の違いを C の層で吸収すると書いてください。

**M7. SYNC と非同期の writer/reader worker**
- 現在、worker を使うのは GetFileType==3（パイプ）のときだけです（`main.zig:1231`, `:1455`）。
- このため、H3 のとおり種類を先に拒否すれば、`finishWriter` を呼ばなくても安全です。この前提を設計に一文で書いておくと、今後 worker の適用範囲が広がったときの事故を防げます。

**M8. SYNC は FileSlot に依存するので、配置先を明確にする**
- `FileSlot` は main.zig の非公開の構造体です。
- そのため、SYNC の callback 本体は main.zig に置くことになります。`host_filesystem.zig` に置く場合は、slot を調べる関数を公開する必要があります。設計の「担当分け」にこのことを書いてください。
- macOS の `fsync` はストレージ媒体への書込みまでは保証しません（`F_FULLFSYNC` を使わないため）。保証範囲の文書に、この点を書き加えてください。

## COMPACT について

- `normalize` は、末尾の `.`/`..` をそのまま残します。`/..` は `/..` のまま、`./` は空文字列になります（`paths.zig:142-155`）。
- この結果が Gforth 1.0.2 と同じかどうかは**未確認**です。18 例の照合には、少なくとも次の例を含めてください。
  - `""` `"/"` `"//"` `"./"` `"/.."` `"/../a"` `"a/.."` `"a/b/."` `"../a"` `"a//b/"`
- Gforth の GPL のコードを移植せず、既存の normalize を共有する方針そのものには問題ありません。

## 確認したもの

- `paths.zig` 全体
- `host_interface.zig` の FileOps
- `main.zig` の次の部分
  - FileSlot
  - open/close/write/flush/resize
  - `prepareFileWrite`
  - read 系で `last_read` を設定する箇所
  - `fileIoCheck`
  - `managedReader`/`managedWriter`/`ensureWriter`
  - proc の slot
- `host_file_kind.c`
- `defs.zig` のエラーコード表
- `directories.zig` の、optional callback が欠けたときの処理

`host_file_reader.zig` の中身は、ほとんど読んでいません（未確認）。
