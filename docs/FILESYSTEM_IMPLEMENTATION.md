# 646 ファイルシステム拡張の実装・検証記録

2026-11-20。基点main `8f4a968`、Zig0.17.1、Windows PowerShell / WSL Linux。
640の差分を保持して作業した。双方とも未コミット。[採用設計](FILESYSTEM_DESIGN.md)、
[レビュー評価](reviews/646-review-response.md)、[Mac実機](FILESYSTEM_MAC_ACCEPTANCE.md)。

## 実装範囲

EXTENSIONへCOMPACT-FILENAME、FILE>REALPATH、FILE-METADATA、SYNC-FILEを追加した。
スタックと失敗契約は採用設計および英日HELP・マニュアルを正本とする。

- COMPACTは既存の字句整理を共通compactIntoへ分け、入力長ぶんのprivate heapで計算してから
  元の領域へ反映する。1024バイト制限は公開語に追加しない。FPATH内部の従来Buffer上限は維持。
  Gforth GPLコードを移植せず、既存算法と実測出力を照合した。heap不足時は-257で無変更。
- 実パスはホストが全結果を確保して返し、コアがcap比較後にコピーして同じ呼出し内に解放する。
  入出力alias・短buffer・エラーを扱い、失敗時に出力を変更しない。新しいcallbackとreleaseは対で必要。
- metadataは通常fileのサイズ（ud）とUnix符号付き秒/ns。Windows FILETIMEをfloor等価式で分解。
  POSIX statのlayoutとMacのst_mtimespec差はC側へ置く。OSの実精度や後続操作との原子性は保証しない。
- SYNCはmainの既存FileSlotを使う。標準→無効/closed→pipe/proc→非regular→readonlyの順で検査し、
  C/OS同期より前に非通常を拒否する。失敗でもfileidを閉じない。MacはfsyncでF_FULLFSYNCではない。
- Windowsのdevice/NT接頭辞・UNC pipe share・OSが予約名と解釈するパスをopen前に拒否する。
  支持するextended pathはdrive/UNCで、Volume GUID形式はEINVAL。入力上限4095バイトは維持する。
- 新Builtin末尾追加で画像ABI署名が変わる。新Stateフィールドや保存画像のOS資源は追加していない。
  古い画像はソースから再作成する。通常VMループへ確認を追加していない。

## 実行で発見した方向切替の問題

Windowsで`changed`へ`ZZ`を書き、1バイト読取り後にSYNCすると、期待した`ZZanged`ではなく
`ZZ\0nged`になることを再現した。SYNC時の位置操作だけでは書込み→読取りのC契約を満たせなかった。
prepareFileReadでupdate streamの出力を入力前にflushし、LineSource、READ-FILE、KEY-FILE、
filePollByteの4経路へ接続した。write-onlyで失敗した読取りはlast_readとして記録しない。
SYNC時の位置操作は保留入力とslot EOFを保つ。試験は読んだbyte、位置、内容を照合し直した。

## 確認結果

| 対象 | 結果 |
| --- | --- |
| Windows通常 | 23/23 step成功。最新回はcore/runtimeが先行成功のキャッシュ、host144成功・12除外 |
| Linux musl/WSL | core1085成功・10除外、host149成功・14除外、runtime15成功 |
| Windows extension除外 | 23/23 step成功、core1067成功・28除外、host144成功・12除外 |
| Windows files/graphics/audio除外 | 13/13 step成功、core718成功・377除外、host134成功・18除外。COMPACTはホストなしで成功 |
| 公開語の結合 | Windows通常・Windows fast・Linuxの各9ケース群。COMPACT1,010例、8,003バイト、cap0/不足/alias、metadata、同期の方向/拒否、リンクを含む |
| Native資源の反復 | Windows1,000反復でhandle126→126、Linux1,000反復でfd5→5。実パス・metadata・失敗経路を反復 |
| open前拒否 | 試験shared library限定のcounterで5名×2APIの10呼出しがopen前にEINVAL。通常fileでcounterが1増える陽性対照も成功 |
| mtime | Windowsは設定値1700000000秒+123456700ns、負時刻-1秒+900000000nsを照合。WSL作業領域は実statでns=0、負時刻設定後も0。Linuxの負時刻実機合格とは扱わない |
| SYNCの入力 | CR先読みの保留byte、論理位置、EOF後の再読を単体と公開語で確認。write→4入力経路→SYNCでNULが混入しない |
| core契約・画像 | callback不足・負長・stack容量不足で呼出し前に失敗し引数保持。短buffer/alias/OS失敗時解放、最大u64サイズ、符号付き秒、画像のcompiled語復元が成功 |
| 既存process回帰 | Windows公開PROC4件、Linux5件成功。大量3streamの送受信も維持 |
| Macクロス | aarch64-macos、graphics/audio/float除外でcore/host/runtime14/14 stepコンパイル成功。Mac実機は下記1116で合格 |
| 文書 | 全語1801・HELP1587、文書例28件・独立使用例397件、標準キー35件を実辞書と照合。check-docs指摘0件 |

除外は成功件数に足さない。Windows junctionを所有するdirectoryで作って解決後に除去した。
Linux symlink/danglingとdeviceを確認した。実ネットワークUNC share、実serial device、
Volume GUID、停電・媒体障害による永続性は試験していない。明示的device拒否の試験で機器は開かない。

## 証跡と再現

ローカル`.work/646/`に以下を保存。別環境へ自動で移るログではない。

- windows-final-tests.log、excluded-final-tests.log、minimal-final-tests.log
- linux-{core,host,runtime}.log、macos-compile.log
- {windows,linux,fast}-public.json、{windows,linux}-native.json
- windows-device-name-probe.json、{windows,linux}-process.json
- reference-check.log、docs.log、各レビューの固定copy・依頼・JSON結果

```powershell
zig build test --summary all
zig build
python tests/scripts/verify-filesystem.py --sigma zig-out/bin/sigma.exe
zig cc -shared -DSIGMA_FS_TESTING src/host_filesystem_native.c -o .work/646/filesystem-native.dll
python tests/scripts/verify-filesystem-native.py --library .work/646/filesystem-native.dll
python scripts/word-reference.py --check --sigma zig-out/bin/sigma.exe
python scripts/check-docs.py
```

## Mac実機受け入れ（1116）

2026-11-20、macOS 27.2.1（26B131）/ Apple M5 arm64 / Zig 0.17.1、対象commit `789420e`（未コミット差分なし）。
[実機手順](FILESYSTEM_MAC_ACCEPTANCE.md)をMac上で実行し、すべて成功した。

| 確認 | 結果 |
| --- | --- |
| `zig build test`（通常） | 23/23 step、1248成功・26除外・失敗0 |
| `zig build test -Dextension=false` | 23/23 step、1208成功・51除外・失敗0 |
| `zig build test -Dfiles=false -Dgraphics=false -Daudio=false` | 13/13 step、855成功・399除外・失敗0 |
| 公開語（`verify-filesystem.py`） | 9ケース群成功。Gforth COMPACT 1,010例、1024超のCOMPACT、実パスのcap0/短buffer/alias、欠落directory、symlink・dangling・device、SYNCの方向切替・位置・readonly/closed、pipe拒否 |
| mtime | 設定値1700000000秒+123456700nsをそのまま観測。負時刻は要求-0.1秒に対しstatで-1秒+900000000nsを観測（APFSで丸めなし） |
| Native資源（`verify-filesystem-native.py`） | 1,000反復でfd 4→4 |
| 手動照合 | `/tmp`経由のsymlinkが`/private/tmp/...`の実パスへ解決。FILE-METADATAの大きさ・秒がstatと一致。directoryと`/dev/null`はEINVAL（-534） |
| 文書 | `word-reference.py --check`で全語1802・HELP1588・個別実行例398件成功、check-docs指摘0 |

Macの同期はfsyncでありF_FULLFSYNCではない（設計どおり）。ログ・JSON・source指紋は`.work/646/`の
`mac-public.json`、`mac-native.json`、`mac-manual.txt`、`test-*.txt`、`mac-source-fingerprints.json`。

## 状態と残作業

仕様1112・ホスト1113・コア/文書1114・Windows/Linux1115・Mac実機1116をすべて完了した。
配布物作成は行っていない。
