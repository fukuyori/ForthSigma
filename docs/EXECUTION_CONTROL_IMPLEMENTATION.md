# 652 実行制御の実装・検証

2026-11-20。基点main `8f4a968`、Windows PowerShell / Zig 0.17.1 / WSL Linux。
640/646の差分を保持して実装。Mac実機1122は2026-11-20に合格（下記「Mac実機受け入れ」）。

## 実装

- EXTENSIONかつdebugで`EXEC-LIMITED ( i*x xt u -- j*x ior )`を公開。最大16段。0は無制限の中断確認、正常0、自分の予算切れ-280。
- CLIと入口予算を分離し、外側全部へ課金する。CLI→外側→内側の順で枯渇を判定。通常CATCHはStepLimitを通し、所有入口だけが深さを復元する。明示-280 THROWの従来挙動を維持。
- 通常VM loop(false)の本体には確認を追加せず、counted・有効入口中の解釈token・native checkWorkBlockへ共通chargeを接続。予算がない場合の短い経路を追加。
- hostのExecutionOpsはoptional。interrupt-only signal所有を入れ子で共有し、NS/audio/input待機と共存。POSIXのEXEC最初の所有はSA_RESTART。復元失敗を最優先し、その後はcallee例外、pending割込み、正常/入口iorの順。
- POSIXはbyte queue、Windowsは未デコードINPUT_RECORD ringに保持。pollはmode変更や標準/GFX変換を行わない。copyしたstandard decoderで再生し、sourceタグから中断の3だけを除く。Windows cancelled markerでsurrogateの誤結合を防ぐ。
- bounded queueの満杯時は後ろのCtrl+Cを検出できない場合がある。pasteの3を保持し、cookedへの移行でも読取り済み文字を保持する。
- 大きな再生作業領域はprocess-owned static、使用部分だけ上書き。modern decoderのsource実行中はprobeをskipする。
- 新しいState.executionは170番目の直下フィールド。予算はencode対象外でappend/LOAD後も有効。新BuiltinでABI署名が変わるため旧画像はソースから作り直す。

## レビューと回帰

[採用設計](EXECUTION_CONTROL_DESIGN.md)、[採否](reviews/652-review-response.md)、[設計原文](reviews/652-design-claude-review.md)、[実装原文](reviews/652-implementation-claude-review.md)、[限定再レビュー](reviews/652-followup-claude-review.md)。ClaudeはRead/Glob/Grepのみで、実行試験はロクが担当。

実装レビューH1で、sourceが未完成ESCの後に3を返す場合の位置計算誤りを修正。source直後とbuffer先頭の中断を区別した。ESC/CSI/部分UTF-8の回帰と実console/PTYでESC保持を確認。M2でinner endが中断印を消費する処理を除き、outer予算切れ＋inner endの印がouter endで-28となるコア/host通し試験を追加。限定再レビューでは対象修正に高・中の具体的欠陥なし。

debugなしでは登録表からEXEC-LIMITEDを除外し、HELP用全表は維持する。除外構成で見つかったHELP/画像復元の4失敗を修正・再試験した。通常THROWより-28を優先するレビュー案は採用済みの例外優先順位と異なるため不採用とし、順序をテストに固定。

## 検証ログ

`.work/652/`へコンパイル・core/host・公開語・console/PTY・性能・文書照合のログを保存。最終集計は以下へ追記する。

- 入口の内外予算、CLIと明示-280 THROW、通常例外、host begin/end失敗、深さ復元、解釈loop、native FAXPYの部分更新、画像保存除外/append、LOAD後の継続制限を確認する。
- Windows private consoleはF1/日本語/貼付け/未完成ESC、Raw→KEYのBackspace、Raw→READ-FILEのUTF-8、Cooked Ctrl+C/KEY、NS、満杯70文字を保持したOS割込みを確認する。利用者のconsoleへは入力しない。
- Unix PTYはRaw文字・paste・ESC・UTF-8、Cooked SIGINT/KEY、NS、端末mode復元を確認する。WSLの結果をMac実機の合格としない。

20msは目標であって保証ではない。時間上限・全native/OS処理の強制中断・副作用の巻戻し・スケジューリング・中断位置からの継続は実装していない。[Mac実機手順](EXECUTION_CONTROL_MAC_ACCEPTANCE.md)。

## 最終集計

| 構成 | core | host |
| --- | --- | --- |
| Windows debug/full | 1093成功・10除外・失敗0 | 148成功・12除外・失敗0 |
| Linux musl/WSL、graphics/audioなし | 938成功・165除外・失敗0 | 138成功・15除外・失敗0 |
| Windows debugなし | 1021成功・82除外・失敗0 | 147成功・13除外・失敗0 |
| Windows extensionなし | 1069成功・34除外・失敗0 | 147成功・13除外・失敗0 |

Mac aarch64/graphics・audioなしのクロスコンパイルとは別に、Mac実機で下記1122を実施した。Windows ReleaseFastの公開語/独立console試験も成功。実辞書1802項目、HELP1588項目、文書例28件・個別実行例398件を照合し欠落なし。check-docs指摘0、git diff --check成功。

主な証拠：final-windows-{core,host}.log、final-linux-{core,host}.log、final-no-debug-{core,host}.log、final-no-extension-{core,host}.log、final-macos-compile.log、windows-fixed-{public,console}.json、linux-fixed-public.json、final-fast-{public,console}.json、final-docs.log、final-runtime-reference.log、timing-final.json。source-fingerprints.jsonにbuild.zig/srcの指紋を記録した。

## 確認間隔と費用

ReleaseFast、graphics/audioなし。プロセス全体のwall秒で1回warmup＋5回の中央値、固定順序、同時ビルドなし。通常/CLI/入口は1000万回のXOR loop、nativeは10万要素FAXPYを100回。プロセス起動・初期化も含み、特にnativeの短い値は誤差の影響を受ける。恒久的な性能や中断応答時間の保証ではない。古いtiming-current/candidatesは修正前の記録で、以下は修正後のtiming-finalを使う。

| 確認間隔 | 通常 | CLI counted | 無制限入口 | native通常 | native入口 |
| --- | --- | --- | --- | --- | --- |
| 変更前646 | 0.056933 | 0.068668 | 対象外 | 0.014566 | 対象外 |
| 256 | 0.053733 | 0.077390 | 0.164305 | 0.014168 | 0.021090 |
| 1024 | 0.052967 | 0.075520 | 0.150688 | 0.015521 | 0.022086 |
| 4096 | 0.054308 | 0.078595 | 0.146203 | 0.015844 | 0.021875 |

1024を採用した。256より入口loopの費用を抑え、4096より短い間隔で確認する。nativeは既存checkWorkBlockのたびにpollするため、この間隔だけで確認頻度は変わらない。通常loop本体へ処理は追加していない。一方でCLI countedとnative通常にも追加費用があり、CLI中央値は基準より約10%増えた。入口付き計算の費用も上表どおり明示する。CLIの入口なしには短い分岐を追加したが、測定上ゼロ費用とは扱わない。

実console/PTY試験のsecondsは中断からプロセス終了・保留入力読取り・50msのESC確定待ち等を含む。20ms以下の応答を実証する測定ではない。

## Mac実機受け入れ（1122）

2026-11-20、macOS 27.2.1（26B131）/ Apple M5 arm64 / Zig 0.17.1、対象commit `789420e`。
[実機手順](EXECUTION_CONTROL_MAC_ACCEPTANCE.md)の1〜5をすべて実施し、合格した。

| 手順 | 結果 |
| --- | --- |
| 1. ビルド・試験 | `zig build`成功。`zig build test`は23/23 step、1248成功・26除外・失敗0 |
| 2. `verify-execution-control.py` | 公開語7ケース（予算・入れ子・THROW・NS・LOAD後の制限）とPTY9ケース（Raw文字/ESC/未完成CSI/UTF-8、Raw→KEY・READ-FILE、paste中の3、Cooked SIGINT/KEY、NS）が成功。結果JSONは`.work/652-mac/verify.json` |
| 3. 実端末（利用者の操作） | Cooked/RawのCtrl+Cが-28でCATCHへ届き、a・日・↑（97 26085 2147483650）と貼付け71 bytesを保持。終了後の行入力はechoされ`got: hello`。TERM-PASTEを有効にしてx・0x03・yを貼り付けると、Terminal.appとWezTermでは`2147483683 120 3 121 2147483684`となり、3は中断にならず保持された |
| 4. 除外構成 | debugなしでEXEC-LIMITEDは辞書・HELPにない。extensionなしではREQUIRE-EXTENSION・EXEC-LIMITEDともない。debugなしでも画像の保存/復元後にEXTENSION語（FILE-METADATA・X-GRAPHEME）が動作 |
| 5. 待機の入れ子 | NS待機中のSIGINTで-28の後、EXEC-LIMITEDの再実行（-280・正常0）が成功。音声コマンドqueue満杯（16件）の待機中のSIGINTで-28、その後のPLAYも成功 |

GhosttyはTERM-PASTE中の0x03を空白（32）へ変換して送るため、貼付け中の3はSigmaへ届かない（端末の挙動。Sigmaは`120 32 121`を保持）。
初回実行では、手順2のPTY試験が端末mode不一致で失敗した。差はlflagの`PENDIN`だけだった。macOS/BSDのカーネルはICANONを戻すたびにこの状態ビットを立て、Sigmaを使わないPythonだけのraw→復元でも再現する。このため、比較から`PENDIN`を除くよう試験scriptを修正した（Linuxでは値は変わらない）。
ログ・source指紋・手動結果は`.work/652-mac/`（`verify.json`、`exclusion.txt`、`audio-wait.txt`、`manual-results.txt`、`source-fingerprints.json`）。20ms応答・OS呼出しの強制中断・継続再開は手順どおり対象外。
