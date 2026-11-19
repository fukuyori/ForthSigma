# Unicode 18.0.0の書記素データ

640で使うUnicode公式データです。出典URLとSHA256はmanifest.jsonに記録しています。
可変のlatestではなく18.0.0に固定し、Unicode License v3の全文をLICENSE.txtに同梱しています。
書記素境界はUAX #29改訂49、既存の表示幅は独立した15.1.0を使います。

GraphemeBreakPropertyはGCB、emoji-dataはExtended_Pictographic、
DerivedCorePropertiesはInCB、GraphemeBreakTestは公式適合試験を提供します。
`python scripts/make-grapheme-table.py --check`で製品表の再現性と入力ハッシュを、
`python tests/scripts/verify-graphemes.py --sigma PATH`で公開語と全公式ケースの一致を確認できます。
`zig build test`も公式ケースを照合します。公式データは製品実行体に埋め込みません。
