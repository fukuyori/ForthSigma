# 課題1401: 埋め込みテキストの再現性

## 埋め込み対象

`git grep -n "@embedFile"` で洗い出した。文書中の言及は埋め込み呼び出しではない。匿名インポート名の実体は `build.zig` の `addEmbeddedTexts` と試験モジュールの設定で確認した。画像の名前は `src/tests/images/expected.zig` と試験内の文字列から決まる。

| 埋め込み元 | 対象ファイル | 処理 |
|---|---|---|
| `src/core/words_audio.zig` | `src/audio/audio.fs` | CR除去 |
| `src/core/words_extension.zig` | `src/extension/extension.fs` | CR除去 |
| `src/core/words_game.zig` | `src/graphics/game.fs` | CR除去 |
| `src/core/words_graphics.zig` | `src/graphics/graphics.fs`, `src/graphics/graphics_float.fs` | 連結前にCR除去 |
| `src/core/words_gui.zig` | `src/graphics/gui.fs` | CR除去 |
| `src/core/tcl.zig` | `src/graphics/sigma_tk.tcl` | CR除去 |
| `src/core/words_help.zig` | `LICENSE`, `THIRD_PARTY_NOTICES.md` | 既存のCR除去を共通関数へ移動 |
| `src/main.zig` (two sites) | `VERSION` | CR除去後に既存の末尾空白除去 |
| `src/tests/audio_test.zig` | `include/chip-sound.fs`, `include/msx-sound.fs`, `include/st-sound.fs`, `include/nes-sound.fs`, `include/c64-sound.fs`, `include/scc-sound.fs`, `include/amiga-sound.fs`, `include/chips.fs` | CR除去 |
| `src/tests/filesystem_test.zig` | `tests/data/compact-filename.json` | CR除去 |
| `src/tests/grapheme_test.zig` | `tests/data/unicode-18.0.0/GraphemeBreakTest.txt` | CR除去 |
| `src/tests/load_image_test.zig` | `src/tests/images/` 下記一覧のファイル | 元のバイト列を維持 |

画像ファイル一覧（`src/tests/images/` からの相対名）: `argb32_v5.bmp`, `core8.bmp`, `gray.pgm`, `gray1.png`, `gray16.png`, `gray2.png`, `gray2_adam7.png`, `gray4.png`, `gray8.png`, `gray_trns.png`, `la16.png`, `la8.png`, `mono1.bmp`, `pal4.bmp`, `pal4.png`, `pal8.bmp`, `pal8.png`, `plain.ppm`, `plain15.pgm`, `rgb.ppm`, `rgb16.png`, `rgb16.ppm`, `rgb24.bmp`, `rgb555.bmp`, `rgb565.bmp`, `rgb8.png`, `rgb8_adam7.png`, `rgb_trns.png`, `rgba16.png`, `rgba8.png`, `topdown24.bmp`, `xrgb32.bmp`。

## 採用した方法

案bを採用し、`src/core/embedded_text.zig` でcomptimeにCRを除去する。2回の走査で必要な長さを数え、その長さの定数配列へコピーする。文字列の連続結合を避け、実行時の処理は増やさない。LF入力、UTF-8、末尾改行がない入力のバイト列は維持する。既存のライセンス正規化もこの共通関数に移した。画像フィクスチャはバイナリとして扱い、テキスト形式のPPM/PGMも試験入力のバイト列を維持する。`VERSION` も2か所とも正規化してから既存の末尾空白除去を行う。`.rdata` を調べた結果、末尾の除去だけでは元のLF/CRLFを含む配列が残ることを確認したため、この入力も正規化した。

autocrlfによる取り出し方だけでなく、直接CRLFに変換された入力にも対応でき、再チェックアウトを必要としないため、この方式を選んだ。`.gitattributes` は変更せず、測定データと受入計画の `-text` 設定も維持した。ライセンスの表示内容と利用条件は変更しない。

`src/core/source_input.zig` の `readEmbeddedLine` はLFで分割し、行末にCRがあれば除去する。CRは必須ではないので、正規化後は既存のLF読み取り経路を通る。TclにもLF入力と同じスクリプトのバイト列を渡す。

## 再現性の検証

環境はWindows x86_64、Zig 0.17.1。複製元のHEADは `792cf26a154cc2fed786ffb9d265c4c2d07cc63d`。証拠は `.work/1401/` に保存した（ローカルの成果物であり、バージョン管理対象外）。

全ビルドで使用したPowerShellの環境設定:

```powershell
$env:ZIG_GLOBAL_CACHE_DIR="$PWD/.work/codex-cache/global"
$env:ZIG_LOCAL_CACHE_DIR="$PWD/.work/codex-cache/local"
python .work/1401/reproduce.py
```

`git archive HEAD` の `head.tar` を `lf/` と `crlf/` へ独立して展開した。スクリプトでライセンス、VERSION、試験テキストを含む全テキスト埋め込み対象をLFまたはCRLFに変換し、画像のバイト列は維持した。対象入力について、CR除去とCRLFからLFへの置換が等しいこともassertで確認する。各複製を変更前の状態でビルドし、実装ファイルだけを上書きして再ビルドする。4回とも引数は `zig build -Doptimize=ReleaseFast -Ddebug=false -Dstrip=true`。PEセクション表のPointerToRawDataとSizeOfRawDataから `.text` の生バイト列を切り出し、整列用のパディングを含めてSHA-256を計算する。ビルドログ、取り出したセクション、`hashes.json` を保存した。元の作業ツリーへのcheckoutやインデックスの変更は行わない。

| 状態 | 改行 | `.text` SHA-256 |
|---|---|---|
| 変更前 | LF | `c929f33f2e6c3a376ea838f7a147d8e601d46b6548eec8eace3f280500b97848` |
| 変更前 | CRLF | `f08e94fdbd68c41fd3d78119942dc6317f11313e1b7a1dcfe3c820278eea3cca` |
| 変更後 | LF | `9702ed2043e5ec74ab0f0508283b4573e7bca7bcd1c334a9d0d2081806012510` |
| 変更後 | CRLF | `9702ed2043e5ec74ab0f0508283b4573e7bca7bcd1c334a9d0d2081806012510` |

変更前は不一致、変更後は一致した。全セクションの生サイズは1,532,928バイト。実装ファイルのSHA-256を固定して両複製に適用し、検証終了時にも作業ツリーの実装と一致することを確認した。20テキスト対象のLF内容のSHA-256も `lf-content-sha256.json` に保存した。

## 試験結果

以下はすべて終了コード0で通過した。

- `zig test src/core/embedded_text.zig`（1試験）
- `zig build test`
- `zig build runtime-test`
- `python scripts/check-docs.py`（findings: 0）
- `git diff --check`

実装の変更を検出する文書検査に合わせ、語の定義・説明を変更していないことを確認したうえで `python scripts/word-reference.py --record-reviewed-sources` により `docs/word-reference/translation-sources.json` を更新した。生成済みリファレンス本文に差分はない。

共通関数の試験では、空入力、LF維持、CRLF、単独CR、UTF-8、末尾LFなしを確認する。LFを読めることは読み取り実装で確認し、通常のコア試験でライブラリ読み込みと埋め込みソースの移動も検証する。

## 未確認事項

比較で確認する範囲は、上記Windowsビルド設定の `.text` の一致。PE全体の一致、異なるツールチェーン、他OS、全機能オプションの組み合わせは確認対象にしていない。Tcl/Tkの対話的なGUI確認は実施していない。今後追加する埋め込みテキストも明示的に共通関数を通し、バイナリは元のバイト列を維持する必要がある。
