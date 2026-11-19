# 646 限定再レビュー原文

2026-11-20。固定コピーの読取り専用レビュー。

レモン、凍結ファイル（`.work/646/followup-review/` の8件）とレビュー文書2件を Read だけで確認しました。コマンドと試験は実行していないので、試験の結果は凍結された `windows-native.json` と `windows-device-name-probe.json` の記録だけが根拠です。`main.zig` と `build.zig` は凍結ファイルに含まれていないため、その部分は「未確認」と書いています。

**結論: High と Medium の残りはありません。** Low が4件あります。

## M1 予約デバイス名と NT 接頭辞

- **予約デバイス名**: `expanded_device`（native.c:42-62）は GetFullPathNameW の結果が `\\.\` で始まれば EINVAL を返します。判定にだけ使い、open には元の `p` を渡しています。
  - バッファの再確保ループ、エラー時の free、`count >= capacity` の判定に問題はありません。
  - probe の記録では、COM1・NUL・CONIN$ は `\\.\` 形式に変換され、`COM1.txt` と `folder/COM1` は通常のパスのままでした。どれを予約名とするかの判断を OS に任せる形になっています。
- **NT 接頭辞**: `/`→`\` の変換をした後に `\??\` と `\\.\` を拒否しています（native.c:69-71）。そのため `/??/pipe/...` も拒否されます。
  - probe では、`/??/pipe/sigma-probe` を GetFullPathNameW に渡すと `D:\??\pipe\...` になりました。GetFullPathNameW だけでは検出できない経路を、先に明示的に拒否しているので正しいです。
- **`\\?\` の扱い**: ドライブ形式と、pipe 以外の UNC だけを許可しています。GetFinalPathNameByHandleW の出力（`\\?\C:\`、`\\?\UNC\`）をそのまま入力に戻しても通ります。
- **open カウンター**: `open_attempts` を増やすのは、`wide_name` が成功した後の CreateFileW の直前だけです（native.c:86-89）。拒否された呼び出しはカウンターを増やしません。5名 × 2語 = 10回で、json の値 `10` と合っています。

## M2 読取り4経路の回帰試験

`verify-filesystem.py` の内容は次のとおりです。

- **書込み→READ-FILE**（79-81行）: 読んだ値（`97`）、SYNC 後の位置（`3`）、ファイルの最終内容（`ZZanged`）を検査しています。
- **書込みの後の READ-LINE / KEY-FILE / KEY?-FILE**（82-90行）: それぞれ、読んだ値、位置、内容が `Zbcdef\n` であること（NUL が混入しないこと）を検査しています。KEY?-FILE は、probe の後に SYNC を挟んでから KEY-FILE で値を読みます。
- **CR 先読みの保留入力と EOF**（91-93行）: `a\rbc` で READ-LINE → SYNC → 位置 `2` → READ-FILE で `bc`。続けて EOF まで読み、SYNC → `FILE-EOF?` が `-1` → 再読が `0` になることを検査しています。SYNC の seek が C の EOF 指示子を消しても、スロット側の eof が保たれていることを確認できる構成です。
- **未確認の点**: KEY?-FILE が実際に event probe の経路（前回レビューで main.zig:1734）を通るかは、main.zig が凍結ファイルにないため確認できていません。

## L2 / L3

- **L2**: `realpath` と `metadata` は、長さが4096以上のときに C の `sigma_fs_name_too_long()` を返します。試験は Python の `errno.ENAMETOOLONG` から ior を計算し、境界の4096バイトで検査しています（68-70行）。OS ごとの errno 値の違いに対応できます。
- **L3**: `ERROR_INVALID_DRIVE`、`ERROR_BAD_NETPATH`、`ERROR_BAD_NET_NAME` を ENOENT に対応づけました（native.c:24-25）。

## Low（任意の改善）

1. **カウンターの陽性対照がない**: 拒否するケースで「カウンターが増えない」ことは検査していますが、通常ファイルの `check()` で「カウンターが増える」ことは検査していません。カウンターが壊れていても試験が通ってしまうので、通常ファイルで1回以上増えることの assert を加えると、証明として成り立ちます。
2. **probe の範囲**: `folder/NUL`、`NUL.txt`、上付き数字の `COM¹` は probe に含まれていません。GetFullPathNameW と CreateFileW は同じ規則で変換するので結果は一致すると考えられますが、※推測です。記録に加える候補です。
3. **`\\?\Volume{GUID}\` 形式の拒否**: ドライブ文字でない `\\?\` をすべて拒否するので、正当なボリューム GUID のパスも EINVAL になります。安全側の仕様として扱うなら、文書に一言書いておく候補です。
4. **未確認の項目**: `SIGMA_FS_TESTING` が試験用の shared library だけで定義されていることは、build.zig が凍結ファイルにないため確認していません。また、`result.json` は空のままです。
