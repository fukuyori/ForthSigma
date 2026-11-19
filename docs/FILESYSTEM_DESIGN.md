# 646 ファイルシステム拡張の詳細設計

2026-11-20。レモンの指示でOS同期を含める。[着手確認](FILESYSTEM_SCOPE.md)。
[設計レビュー](reviews/646-design-claude-review.md)を受け、[評価・採否](reviews/646-review-response.md)の具体化を採用する。640のMac実機1111と今回のMac実機1116は別に残す。

## 公開API

すべてEXTENSION。COMPACT-FILENAMEはホスト不要。他の3語はfiles有効かつoptional
FileOps callbackが必要で、欠ける場合は-21をTHROWし引数を保持する。

| 語 | スタック | 意味 |
| --- | --- | --- |
| COMPACT-FILENAME | ( c-addr u -- c-addr u2 ) | Gforthと同じ文字列だけの整理を元の領域へ書く |
| FILE>REALPATH | ( name u buffer capacity -- needed ior ) | リンクをたどった既存パスをバッファへコピーする |
| FILE-METADATA | ( name u -- ud-size mtime-sec mtime-nsec ior ) | 通常ファイルのサイズと最終更新時刻を同じ照会で取得 |
| SYNC-FILE | ( fileid -- ior ) | 書込み可能な通常ファイルのCバッファとOSへの同期を要求 |

COMPACTは`/`だけを区切りとし、空・末尾`.`/`..`・ルート超過をGforth1.0.2の
実行照合へ合わせる。末尾区切りを除いてできた`.`/`..`を改めて消さない。ドライブやUNCを
Windowsの実パスとして解釈しない。`\`とNULは通常バイト。文字列操作であり存在確認しない。
既存normalizeのアルゴリズムを共有し、Gforth GPLコードは移植しない。

REALPATHの入力と出力は重なってよい。先に入力をホスト専用領域へ複製してからOSへ渡す。
出力はNULなしのバイト列。capacity不足はneededに必要バイト数、ior=errnoIor(ERANGE)、
バッファ無変更。cap=0も必要長の照会に使える。他のOS失敗はneeded=0、buffer無変更。
Linux/macOSはrealpath、WindowsはCreateFileWとGetFinalPathNameByHandleW。
WindowsはAPIの`\\?\`形式とバックスラッシュを保持し、UTF-8へ変換する。
リンク切れや存在しない末尾は失敗。ディレクトリも可。空/NULを含む名前はEINVAL。
ホスト名入力上限は従来と同じ4095バイト、出力長はOS解決結果を使い追加の固定上限を置かない。
単なる絶対化や~展開、FPATH探索、字句的な..消去はしない。

METADATAはリンク先を取得し、通常ファイル以外はEINVAL。ud-sizeは非負バイト数を
標準FILE-SIZEと同じ2セルで返す。mtime-secは1970-01-01T00:00:00Zからの符号付き秒、
mtime-nsecは0..999999999。負時刻はfloor分解する（-0.1秒は-1秒と900000000ns）。
Windows FILETIMEの100nsをこの形へ換算し、POSIXはstatの秒とnsを使う。
分解能はファイルシステム次第で、返値の桁数を実精度とみなさない。失敗時は全数値0とior。
ファイルの変更を見落とさない保証、後続操作とのTOCTOU対策、ファイル識別子は含めない。

SYNCは既存のFileSlotを検査し、無効IDはEBADF、stdin/out/err・pipe・device・directoryはEINVAL、
read-onlyはEACCES。非通常ファイルはfflushより先に拒否し、pipeの配送待ちへ入らない。
既存入力の保留バイト・EOF・位置は変えない。最後の方向がreadなら、
seek64(file,0,SEEK_CUR)でCストリームを同期し、FileSlotのinput.length・EOFを保持する。writeならfflush成功後にPOSIX fsync/
Windows FlushFileBuffersを呼ぶ。失敗時もfileidと所有を保持する。
OS同期は同期的で期限・途中取消し保証なし。fileの同期だけでrenameや親directoryの永続性、
停電耐性を保証しない。FLUSH-FILEとRENAME-FILEは変更しない。

Windows結合試験でwrite→read後の同期にNULが混入することを再現したため、最後の方向の印だけで十分とは扱わない。update streamの読取り開始前にもprepareFileReadでfflushを成功させ、LineSource・READ-FILE・KEY-FILE・event probeの4経路で方向を整える。SYNC側のseekと併せて検証する。

SYNCの拒否順序は標準ID(EINVAL)、無効/closed(EBADF)、pipe/proc(EINVAL)、OSのregular判定(EINVAL等)、readonly(EACCES)。通常ファイルは既存workerの対象外であり、この前提を変更するときはSYNCも見直す。MacはfsyncでありF_FULLFSYNCではない。

Windowsの名前openはaccess=0、share=READ|WRITE|DELETE、OPEN_EXISTING、BACKUP_SEMANTICS。明示的なdevice namespaceとUNCのpipe shareはopen前に拒否する。解決後のUTF-8が4095バイトを超えて返ることはあるが、既存OPEN-FILEの入力上限は変えない。absolute判定はWindowsに限ってUNC/extended prefixを認識する。

Windowsの予約device名はGetFullPathNameWによるdevice形式への変換結果で、raw NT接頭辞は明示条件で、openより前に拒否する。extended pathはdrive/UNCだけを対応範囲とし、Volume GUID形式はEINVAL。OSごとの通常ファイル名解釈をこの範囲で保持する。

FILETIMEの変換はsec=t/10000000-11644473600、nsec=(t%10000000)*100で、epoch差をfloor分解するのと等価。FILETIME=0は1601年の値として返し、時刻未記録との区別は保証しない。Linux st_mtim、Mac st_mtimespecの差はC内で吸収する。

## コア・ホスト・失敗

全入力・出力領域・stack容量をホスト呼出し前に検査する。領域外や負の長さは-9、
stack不足は既存例外で引数保持。OS系の失敗はerrnoIorで返す。
COMPACTは入力長ぶんのprivate heapへ計算後にregistry通知とともにまとめて反映する。固定1024制限は追加しない。既存normalizeと共通の線形compactIntoを使い、FPATHも回帰する。
REALPATH callbackはホスト確保のowned bytesとiorを返し、必須の対になるrelease callbackで呼出し内に解放する。コアがcapを比較してからコピーし、成功したバイト数だけregistry.writtenを呼ぶ。直接Forthメモリへ書くcallbackは追加しない。
追加Builtinは末尾追加。State・保存画像へOS資源を追加しない。画像ABI署名は既存機構で変化する。

core/words_filesystem.zigはstack/メモリ検査とcallback接続、host_filesystem.zigは名前のC文字列化と
結果変換、host_filesystem_native.cはC stat layoutとWindows/POSIX APIを担当する。
既存FileOpsへoptional callback（実パス・その解放・metadata・sync）を追加し、mainの既存FileSlotでSYNCの所有・accessを検査する。
対応外OSはcallback未提供。ホスト専用確保・ハンドルは各呼出し内で必ず解放する。

## 検証

Gforth1.0.2との18例以上の差分照合、入力領域の変更・同じアドレス・末尾長・長いパスを確認。
REALPATHは日本語、相対、..、symlink/dangling、Windows junction/UNC形式の扱い、
空/NUL、buffer不足・cap0・alias・失敗時無変更を確認する。
METADATAは空ファイル・書込み後・既知mtime・負時刻の換算・大きなサイズ・symlink・非通常を確認。
SYNCはflush順序、通常fileの内容と位置/保留入力、readonly/closed/pipe拒否、失敗時所有保持を確認。
fake callbackで例外時のstackとメモリ、未提供・files/extension除外、画像保存・復元を試験。
Windows/Linux実行、代表的機能除外、Macクロスコンパイルを行い、Mac実機は別タスクへ残す。
英日HELP・マニュアル・全語参照・ライセンス・引継ぎを更新する。

## 公式資料

- [GetFinalPathNameByHandleW](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfinalpathnamebyhandlew)
- [GetFileInformationByHandle](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfileinformationbyhandle)
- [FlushFileBuffers](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-flushfilebuffers)
- [realpath](https://man7.org/linux/man-pages/man3/realpath.3.html)、[stat](https://man7.org/linux/man-pages/man2/stat.2.html)、[fsync](https://man7.org/linux/man-pages/man2/fsync.2.html)
