# Unicode書記素境界（640）詳細設計

2026-11-20。Unicode 18.0.0 / UAX #29 revision 49を使用し、既存の表示幅15.1.0は変更しない（レモン了承済み）。

## 採用仕様

レビュー状態：再認証後のClaude Codeレビューは完了。レモンの指示で前方検査を探索に必要な範囲へ限定する案を採用。[原文](reviews/640-design-claude-review.md)、[評価・採否](reviews/640-review-response.md)。tqueは仕様1108→実装1109→Windows/Linux1110、実装1109→Mac実機1111へ分割済み。

EXTENSIONへ次の2語を追加する。結果はUTF-8バイト数であり、コードポイント数や表示列数ではない。

| 語 | スタック | 意味 |
| --- | --- | --- |
| X-GRAPHEME | ( c-addr u -- u1 ) | 渡した文字列の最初の拡張書記素クラスタのバイト数 |
| X-GRAPHEME-LAST | ( c-addr u -- u1 ) | 渡した文字列の最後の拡張書記素クラスタのバイト数 |

文字列全体を独立したtextとして扱い、両端を境界とする。途中から切り出した文字列は元のtextと同じ境界になる保証がない。前後の探索で元のtextとの位置関係を暗黙に補わない。末尾側にも先頭と全長を渡す。空なら0。前方は返ったバイト数だけ進み、後方は全長から返ったバイト数を引くことで反復できる。

領域と長さはmemoryAddressで全範囲を検査し、不正領域・負の長さは既存の-9。UTF-8は前方では先頭クラスタと境界判定用の次の1コードポイントまで検査する。それより後ろは復号せず、そこにある不正列は後続の探索時に報告する。末尾では入力全体を検査する。検査範囲内の不正UTF-8（過長、surrogate、範囲外、不完全列を含む）は-24をTHROWし、成功するまでスタックを変更しない。-24は不正なスカラー値・符号化引数として既存のInvalidNumberを使用し、専用例外は増やさない。従来のXCHAR語の寛容な復号は変えない。

## アルゴリズム

[UAX #29 revision 49](https://www.unicode.org/reports/tr29/tr29-49.html)のdefault extended grapheme cluster、GB1〜GB999を実装する。地域・言語別tailoringと正規化はしない。特に18.0.0のGB9cはLinker Extend* × Consonantであり、旧版の規則を流用しない。

3属性を1バイトに詰めた疎な統合区間表を生成し、1回の二分探索で引く。走査中は前のGCB、RIの奇偶、Extended_Pictographic GCB=Extend*とZWJの状態、InCB Linker InCB=Extend*の状態を保持する。再帰・ヒープ確保なし、追加領域O(1)。表サイズをR、探索する先頭クラスタのバイト長をk、入力長をnとして、前方はO((k+1) log R)、全クラスタの前方反復はO(n log R)。末尾探索は先頭から1回でO(n log R)。末尾を繰り返し削除すると総計O(n² log R)になり得ることをHELPへ明記する。

末尾の後方参照案は初期実装では採用せず、前文脈を保持する順走査を共有する。ASCII/Hangul特例も入れず、生成表を規則どおり保持する。

GB9cの状態はInCB=Linkerで立て、InCB=Extendで保持し、その他で解除する。次のInCB=Consonantとの境界を抑止する。GB11の状態はExtended_Pictographicで立て、GCB=Extendで保持し、GCB=ZWJで直後状態へ移る。次のExtended_Pictographicとの境界を抑止する。CR/LF/ControlのGB3〜5を先に適用する。U+200DはInCB=ExtendだがU+200Cは異なるため、2種類のExtendを混用しない。

幅・単語境界・タブ列・端末描画・既存の行編集は変更しない。OSサービス不要。extension=falseで公開語と実行入口を除外する。Builtinを末尾追加し、既存の画像ABI署名機構に従って古い画像を拒否する。Stateフィールド・保存画像の資源は追加しない。

## データ・ライセンス・再生成

公式の固定URL https://www.unicode.org/Public/18.0.0/ucd/ 以下のauxiliary/GraphemeBreakProperty.txt、emoji/emoji-data.txt、DerivedCoreProperties.txt、auxiliary/GraphemeBreakTest.txtをtests/data/unicode-18.0.0へ保存する。Unicode License v3を同梱しTHIRD_PARTY_NOTICESへ追記。生成器は入力の版とSHA256を記録し、ネットワークなしで再生成できるようにする。組込み表だけ製品へ含め、公式試験データは試験時に使用する。

18.0.0紹介ページには草稿注記が残るが、採用対象は承認済みと明記する固定改訂49と18.0.0データ。可変latest URLを生成に使用しない。

## 検証・完了条件

GraphemeBreakTestの全行を前方・末尾で照合する。UTF-8の全異常形式、空・NUL・CRLF、国旗の奇偶、ZWJ、インド系結合、長い結合列、スタック不足・領域外・失敗時スタック、機能除外、保存画像を試験する。Windows/Linuxで実行し、Macはクロスコンパイルと実機受け入れを区別する。英日HELP・全語参照・生成再現性・文書チェックを確認する。

着手前回帰：HEAD 8f4a968でWindows通常23/23 step成功（core/runtimeはキャッシュ、host143成功12除外）。afac042のPOSIX修正を含むLinux native16ケースと公開語5ケース成功。ログは.work/640/linux-{native,words}.json。
