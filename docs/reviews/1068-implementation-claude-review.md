# task1068 保存アプリ起動：実装レビュー（読み取り専用）

レモン、読んだ範囲では High の不具合は見つかりませんでした。Medium は1件です。ほかに Low が4件あります。コマンドとテストは実行していません。

## Medium

**M1 POSIX の権限設定で umask を一時的に 0 にしている**
- 場所：`src/host_saved_image_native.c:92-93`（`sigma_saved_mode`）
- `umask(0); umask(mask);` の間は、プロセス全体の umask が 0 になります。この間にほかのスレッド（runtime・audio・process 管理）がファイルを作ったり子プロセスを起動したりすると、そのファイルや子プロセスは umask 0 で作られます。現在 `src` で `umask()` を呼ぶのはここだけです。`src/core/host_interface.zig:100-101` には「権限は作成時に適用し、後から chmod しない」という方針が書かれていますが、それにも反しています。
- 最小の修正：`sigma_saved_temp` の POSIX 側で `open(name, O_CREAT|O_EXCL|O_RDWR|O_CLOEXEC, 0777)` として作成し、権限の計算をカーネルの umask 適用に任せます。POSIX の `sigma_saved_mode` は何もしないようにするか、削除します。書込み中の一時ファイルを 0600 のままにしたい場合は、Linux なら `/proc/self/status` の `Umask:` を読み、`fchmod(fileno(stream), …)` を close の前に呼ぶ方法もあります。ただし macOS にはこの方法がないため、0777 で作成する案を勧めます。

## Low（参考）

- **L1 debug-log/lint/profile の作成位置が設計と違う**：`src/main.zig:3703-3750` は復元（`3752`）より前にあります。設計の起動順8では「復元後」です。format のときに作らない条件は守られています。復元失敗をログに残せる点では現行の順のほうが有用と考えます。コードと設計文書のどちらに合わせるかは、レモンの判断を仰ぎます。
- **L2 Windows のドライブ相対パス `C:out.exe`**：`host_saved_image_native.c:57-62` は `/` と `\` だけを区切りとして扱います。このため一時ファイルがカレントディレクトリに作られます。そこが別ボリュームだと MoveFileExW が失敗します。結果はエラーで、既存の出力先は変わりません。修正するなら、`_WIN32` のとき位置1の `:` も区切りに含めます。
- **L3 argv が空のとき、表示なしで status1**：`src/main.zig:3773`。通常の起動では発生しません。
- **L4 同じ行が3回ある**：`src/forth.zig:1172-1174` の `hidden_word` の行です。動作に影響はありません。1行に整理できます。

## 確認して問題がなかった点（観点別）

- **ID/root の寿命**：`app_entry.forget`（`app_entry.zig:62-65`）は、`raw > first`（id >= first）で解除します。FORGET/MARKER（`forth.zig:1151` を経由）、定義の中断（`error_reporting.zig:59,299`）、quotation の中断（`quotations.zig:35`）、語群の rollback（`library_loading.zig:139`）は、すべて `dropWordsFrom` を通ります。`string_values.zig:38` の rollback は直接 word_count を戻しますが、対象は直前に作った string value なので登録対象にはなりません。setter は全検査の後で pop し、重なる slot の記録も除いています。
- **型のある記録**：`imageEntry` の前に、`format.parse` が Word の enum と bool を検証しています（`image_format.zig:306-307`）。このため `bytesToValue` は安全です。重なる system relocation は、inspect・restore preflight・append（`validateState` と `collectForAppend`）の3か所で拒否されます。
- **preflight/append**：full restore は system 領域を丸ごと複製するので root も含まれます。検査はすべて apply の前です。State 経由の append（`dictionary_image.zig:97-`）と typed append（`image_append.zig`）は、どちらも 0x0dd0 に書かず、target 側の設定を保持します。
- **CLI**：`--sigma` の strict 解析では `next+1` の補正が正しく、`--` がなければ未知の option はエラーになります。debug=false では trace/format/lint も未知として扱われます。保存実行体での `-m`/`-l` は、prefix がある場合は0指定も拒否し、prefix がない従来の書き方では0指定を無視します。format/lint の `--no-app` 必須も守られています。
- **source context**：`runEntry`（`forth.zig:603-629`）は、blk・source・>IN・serial・token_start を退避して復帰します。エラー時は quotation を abort します。
- **debug 設定の順序**：step_limit・tracing・plain_calls・cover_blocks は復元前に設定されています。既存の defer も復元前に用意されています。
- **一時ファイルからの公開**：O_EXCL と O_CLOEXEC/_O_NOINHERIT を使っています。fclose を済ませてから公開し、失敗時は wide 版の `remove` で回収するので、日本語パスでも回収できます。自分自身へのエイリアスは file ID（Windows は volume と index、POSIX は dev と ino）で拒否し、最後の要素が symlink/reparse point なら拒否します。この検査は公開の直前にもう一度行います。旧 footer は長さが一致するか検査してから切り離します。
- **終了処理**：入口のエラーは reportDiagnostic のあと status1 になり、正常終了は finishBlocks を通ります。これは `-e` の経路と同じです。

テストの実行と結果の確認は、ロクの担当として未実施です。