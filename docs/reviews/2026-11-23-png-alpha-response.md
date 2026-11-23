# アルファ付きPNG保存 レビュー対応

2026-11-23、Claude CodeへRead/Glob/Grepのみで依頼。[原文](2026-11-23-png-alpha-claude-review.md)。
レビューはHigh/Mediumなし。コード読解であり、実行検証はロクが担当した。

- GFX語一覧の欠落を追記し、screen保存の単体テストへ空スタックとIHDR type 6の確認を追加。
- ブロック境界は独立Python復号で確認。追加の64×255でrawがちょうど65,535のBFINALも照合し、128×128・最大幅16384×1で複数ブロックを確認した。大きいブロックのZigテストへの複製は行っていない。
- files=falseは実行体を別に作り、同じ5寸法で実際に保存・復号・再読込みが成功した。
- ABIはimage_format.zigのlayoutSignatureがBuiltinの全名・値を含み、decodeのvalidateHeaderが署名不一致をInvalidImageとすることをソースで確認。既存Builtin番号を末尾追加で維持しても、署名は変わる。
- 日本語単独のPNG_ALPHA_SAVE.mdは内部実装・検証記録として明示。利用者向けの説明・使用例は英日GRAPHICS_AND_SOUNDと全語リファレンスへ記載した。
- RGBA行バッファは65,537バイト。RGB/Tkの行バッファは従来の49,153バイトを保ち、画像全体の確保は増やしていない。

通常1373成功・25skip、graphics除外1201成功・193skip。全語と実辞書の照合、EKEYS35値、文書例28件・単独例426件、文書チェック指摘0。
[通常PNG結果](../measurements/2026-11-23-png-alpha-save.json)、[files除外結果](../measurements/2026-11-23-png-alpha-save-no-files.json)。
