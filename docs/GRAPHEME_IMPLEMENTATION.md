# Unicode書記素境界640の実装・検証記録

2026-11-20。基点main `8f4a968`、Zig 0.17.1、Windows/PowerShellとWSL Linux。
変更は未コミット。[採用設計](GRAPHEME_DESIGN.md)、[レビュー評価](reviews/640-review-response.md)。

## 実装

- EXTENSIONの`X-GRAPHEME ( c-addr u -- u1 )`と`X-GRAPHEME-LAST ( c-addr u -- u1 )`。
  結果は先頭・末尾のdefault extended grapheme clusterのUTF-8バイト数。空なら0。
- Unicode 18.0.0 / UAX #29 revision 49。表示幅は従来の15.1.0を維持する。
- 前方は先頭クラスタと次の1コードポイントだけを厳密に復号する（レモンの選択）。
  `ab FF`は前方1、末尾は不正UTF-8。`a FF`は先読みの不正として前方も失敗する。
- 末尾は元の先頭と全長を渡して全文を1回走査する。追加領域O(1)、再帰・確保なし。
  前方反復はO(n log R)、末尾の反復削除はO(n² log R)になり得る。
- 領域全体はmemoryAddressで先に検査。不正符号化は-24、不正領域・負の長さは-9。
  エラーまでpeekだけを使い、引数を保持する。既存XCHAR復号は変更していない。
- GCB、Extended_Pictographic、InCBを統合区間表へ生成。GB9cのInCB=Extendと
  GB11のGCB=Extendを分けて保持。Unicode18のLinker始まりの規則を使う。
- `-Dextension=false`で登録・HELP・実行口を除外。State追加なし、OSサービス不要。
  Builtin末尾追加により画像ABI署名が変わり、以前の画像はソースから再作成する。

## 確認結果

| 対象 | 結果 |
| --- | --- |
| Windows通常 | 23/23 step成功、core1082成功・9除外、host143成功・12除外。runtimeは先行成功のキャッシュ |
| Linux musl/WSL | core1082成功・9除外、host148成功・14除外、runtime15成功 |
| Windows extension除外 | 23/23 step成功、core1066成功・25除外。公開語の実行拒否・HELPと辞書の除外を試験 |
| graphics/audio/files除外 | 13/13 step成功、core715成功・375除外、host133成功・18除外（公式データの通常試験への追加前の記録） |
| 公開語の公式適合 | Windows通常、Linux、Windows fastの3構成とも853ケース・3,096項目成功 |
| 通常単体の公式適合 | 全853行を両端から照合する1試験を`zig build test`へ追加。公式データはcore試験だけに埋込み |
| UTF-8・stack・memory | 過長、surrogate、範囲外、不完全列、不正継続、スカラー境界、空、NUL、CRLF、領域外・stack不足と失敗時の引数保持が成功 |
| 規則・画像 | 長い結合列、GB9c/GB11の属性交差、全公式RI/ZWJケース、公開語を含む定義の画像保存・復元が成功 |
| Mac向け | aarch64-macos、graphics/audio/float除外でcore/host/runtime 14/14 stepコンパイル成功。Mac実機は未実施 |
| OS非依存性 | Windows通常testに含むCortex-M0+ freestandingコンパイル成功 |
| 文書・実辞書 | 全語1797項目、HELP1583項目、標準キー35個、文書例28件、独立使用例393件を照合して成功 |
| 生成再現性 | 固定入力5ファイルのSHAと生成表一致。check-docsからも検査し指摘0件 |

着手前にはMacのprocess修正を含むWindows通常23/23 step、Linux native16ケース
（rollback・資源数6→6）、公開PROC語5ケースを確認した。

最終補強の全辞書走査・公式パーサー上限検査については、再試験ログを正本とする。
ローカル証跡は`.work/640/`の`windows-final-tests.log`、`excluded-final-tests.log`、
`linux-final-core.log`、`linux-host.log`、`linux-runtime.log`、
`{windows,linux,fast}-graphemes.json`、`macos-compile.log`、`reference.log`、`docs-final.log`。
ホスト部に変更がない再実行では既存キャッシュを使う。除外を成功件数に含めない。

## データと再現

`tests/data/unicode-18.0.0/manifest.json`が公式固定URLとSHAの正本。
`.gitattributes`で入力txtのバイト列を保ち、Gitの改行変換でSHAが変わるのを防ぐ。
生成器の`--check`は入力全件（公式試験とライセンスを含む）を検査する。
製品には`src/core/grapheme_data.zig`だけを含め、公式fixtureは含めない。

```powershell
python scripts/make-grapheme-table.py --check
zig build test --summary all
zig build
python tests/scripts/verify-graphemes.py --sigma zig-out/bin/sigma.exe
python scripts/word-reference.py --check --sigma zig-out/bin/sigma.exe
python scripts/check-docs.py
```

## 残作業

Mac実機1111は[受け入れ手順](GRAPHEME_MAC_ACCEPTANCE.md)に残す。
クロスコンパイルやWindows/Linuxでの成功で640全体を完了にしない。
クラスタ表示幅・単語境界・既存端末行編集への組込みは今回の実装範囲に含めていない。
コミット・タグ・push・配布物作成は行っていない。
