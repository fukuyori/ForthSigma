# 1056 語群基盤と1036 OS判別

2026-11-19。1056・1036の採用仕様と実装。Windowsの12構成とLinuxの通常・extension除外で実行検証し、tque両項目は完了。Mac実機は1065に残す。設計レビュー原文と判断は別に残し、検証結果は実装記録へ追記する。

## 進行条件

利用者の「mac部分は残して、次に進めて」により、1056の先行条件を900全体から完了済み1064へ変更した。1065・1063・900は未完了のまま残す。Mac実機の完了を装わず、Windows/Linuxで次の基盤を開発する。1036は1056の基盤を使う最初の小さな語として同じ作業で検証する。

## 採用する公開契約

- `audio`・`graphics`・`extension`を独立したビルド選択とする。新しい`-Dextension`は既定trueとする。
- `REQUIRE-EXTENSION`を解釈時の入口とし、EXTENSION語彙へ組込み語と組込みForthライブラリを初回だけ登録する。ALSO EXTENSIONで利用し、PREVIOUSで元へ戻す。DLL等の動的ロードではない。
- 登録は既存のlibrary_loadingを使い、検索順・CURRENT・BASE・一度だけの定義名を維持する。今回追加した辞書部分の失敗を取り消し、再試行できる。前提語群は不要とする。
- 新しい公開時計・端末・イベント・Unicode・タスク管理・OS判別はextensionへ置く。新しいファイル機能にはfiles、実行制限652にはdebugも要求する。既存の標準語・既存グラフィックスや音の語は移動しない。
- 内部Runtime・時計・Wakeは本体の共有部品のまま。extensionの公開語を除いてもaudio/graphicsが利用できる。
- 最初の語`HOST-OS`は`( -- c-addr u )`で小文字ASCIIの`windows`・`linux`（WSL/Androidを含む）・`macos`、その他は`unknown`を返す。文字列は論理Forthメモリーへコピーし、ホストポインターはForthへ出さない。取得元は`builtin.os.tag`。環境変数や端末から推測せず、コンパイル対象のOS系列を返す。ホストのサービスやWriterの追加コールバックは不要。結果は次のHOST-OSかイメージ復元まで借用でき、書換え禁止。数値とOS定数の旧案を文字列へ具体化した。
- extension無効時のREQUIRE-EXTENSIONとHELPは通常の未定義語UnknownWord（-13）とする。有効時のみparser分岐を置き、無効時は利用者の同名定義を通常どおり呼べる。EXTENSIONとHOST-OSは登録しない。

## イメージと試験

Builtinを末尾追加してABI署名を更新する。旧イメージの互換維持は要件に追加しない。新magic/kindは増やさず、既存SIGIMG45/46/47の内容検査で除外を拒否する。Builtin enum追加によるABI更新と機能の有無の検査は別である。起動時の名前なし欄を除き、追加したbuiltin語と直接builtin Opに`defs.isExcludedBuiltin`を適用する。以前はaudio/graphicsを除いた実行体でも読めたイメージを、InvalidImage（-264）で読込み前に拒否する挙動変更になる。生のxtの整数値をデータとして保存しただけの場合は静的に判定できないため、実行時のInvalidExecutionToken防御も維持する。完全復元、Stateからの追加、バイト列からの追加のすべてで語群の認識と再読込みの冪等性を確認する。

Windowsでは3語群の8通りに加えfiles/debug除外とfloat/image/x11除外の代表構成を実行する。単体試験で失敗巻戻し・再試行・FORGET/MARKER・定義中の拒否・HELP・イメージ認識を確認する。異なるextension設定間ではイメージを実際に保存・読込みし、拒否後に既存辞書が使えることを確認する。Linux実行とMac向けコンパイルの結果はWindowsの結果と分ける。

## 実装上の配置

`extension_vocabulary_address=0x0dc0`、`host_os_buffer_address=0x0dc8`（8バイト）を使う。既存where-styleとtimezone領域の間に収まることをcomptimeで検査し、$TMPの0x0300帯を使用しない。借用文字列は毎回書き直し、イメージ内に残った別OSの値を返さない。image_addressはnullで、忘却後に語がなくなった場合に固有magicを維持する必要はない。

語群一覧は`src/core/library_groups.zig`へまとめ、State追加とバイト列追加の両経路が同じ一覧・配列長を使う。機能除外はdefsの共通表、組込みForthライブラリは同じextension条件で選び、HELPと全語リファレンスを登録表に照合する。公開時計の具体名やタスク方式、将来のfiles/debug条件の実装は各担当項目に残す。

[設計レビュー原文](reviews/1056-design.md)、[指摘の判断・対応](reviews/1056-response.md)。

イメージの機能検査は追加した組込み語と直接builtin Opを対象とする。起動時から予約されている基本辞書の欄への通常の呼出しは従来どおり読込みを許し、除外語の実行時にINVALID EXECUTION TOKENとなる。生のxtをデータとして保存する場合とは別の制約である。

HOST-OSは実行体の対象OS系列であり、Wine上のWindows版でもwindowsを返す。将来値が増える場合があるため、利用者は未知の文字列もunknownと同じく扱う。ライブラリ失敗の巻戻しは今回追加した辞書と検索設定の範囲であり、任意のForth実行のスタック・メモリー副作用を取り消すトランザクションではない。

wire codec（image_format）は機能構成に依存しない構造検査を維持する。実際の復元・バイト列追加はimage_restore_planからimage_featuresの共通検査を通し、State追加も同じ検査関数を使う。保存側で除外fixtureを構造的に扱えることと、読込み先で実行不可能な追加語を拒否することを分ける。

float除外では、例えばFLITERALやfloat局所変数の+TOが生成する直接builtin Opも事前拒否の対象となる。一方、F+等の予約欄への普通の呼出しは実行時拒否となる。SAVEはwire形式だけを確認し、機能による可否は実際の読込みで判定する。
