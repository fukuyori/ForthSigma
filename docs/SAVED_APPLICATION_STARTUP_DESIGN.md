# 保存アプリの起動基盤：1067 詳細設計案

2026-11-20。基点main d9e88f2。1067の設計対象であり、1068/1069の実装・受け入れを完了したものではない。既存の測定文書の差分を保持する。

## 公開APIと登録

本体のimage語群（image=true）にAPP-ENTRY! `( xt -- )`、APP-ENTRY@ `( -- xt flag )`、APP-ENTRY-OFF `( -- )`を追加する。audio/graphics/extension/debug/filesに依存しない。image=falseでは3語を辞書・HELPから除く。

初版の登録対象は、完成したcolon定義（:NONAMEも含む）だけ。wordIdで範囲を検査し、kind==colon、compile_only=false、定義中のwordでないこと、code範囲が有効なことを確認する。builtin、DEFER、SYNONYM、CREATE/DOES、forward、vocabularyは-261 InvalidExecutionToken。これらを使うアプリは`: MAIN HOOK ;`のようなcolon wrapperを登録できる。入口の実行効果は`( -- )`。setter/clearはセルに重なる旧address registryのslot記録を明示的に取り除く。registry.writtenは通常書込みの通知であり削除ではないため、それだけに頼らない。setterは全検査成功後にpopし、不正xtでは既存設定と引数を保持。定義の途中の登録は-259 InvalidDefinitionとする。

wordIdは数値0も有効なので0で解除しない。未登録のqueryは`0 false`、登録済みは`xt true`。clearは独立語。@で破損した登録を検出したら-261として値を返さない。

新しい非公開system cell 0x0dd0（host_os_buffer_address+8からtimezone_buffer_address 0x0e00の間）にword-id+1を保存する。0は未登録、登録値の範囲はbuiltin_count+1..word_count。システム領域のコンパイル時非重複検査を増やす。このセルはアドレス型rootではなく専用のword-token root。範囲1..word_count、対象colonと完全性を保存・復元で検査する。セルに重なるaddress registry recordは不正として拒否。State直下への永続フィールド追加はしない。

State.dropWordsFromへ解除を置き、FORGET/MARKER/語群rollback/定義・quotation中断で登録wordを削除する前にrootを0へ戻す。HEREの変更だけでwordを削除する経路とは区別する。MARKERに設定のsnapshotは足さず、削除先への参照を失効させる。新wordが同じIDを再利用しても復活しない。登録対象が残る後続word削除では設定を保つ。同名再定義は登録を変えない。登録後にCOMPILE-ONLY等で属性が変わる場合もあるため、query・保存/append元・restore preflight・起動直前で共通の対象検査を行う。アプリ実行中の削除制約は既存VMに従い、起動hostは開始時のIDを一度取得する。

## 保存・完全復元・追加読込み

SAVEとSAVESYSは登録を保存する。SIGIMG45/46/47のsystem memory領域に既存の方式で保持し、headerサイズやtyped address relocation形式は増やさない。新BuiltinによりABI署名が変わり旧ABI画像は従来どおり拒否する。登録rootがある画像のword IDは完全復元では既存のIDを保つため数値の再配置はない。共通preflightでrootを検査し、失敗時は辞書・設定・OS資源を変更しない。

LOAD-DICTIONARY/appendImageは辞書を追加するだけで、source側のAPP登録は常に引き継がない。target側の登録を未登録も含め保持する。source登録の構造検査は行う。source側の登録先word自体は通常どおり再配置して追加し、必要なら追加後のwordを明示的に登録する。設定の暗黙な置換や起動は行わない。full restore、append、SAVESYSプロセス起動を別の操作としてテストする。

root検査の共通関数をimage_graph.collect、image_restore_plan.prepare、append preflightへ置く。apply後に失敗し得る検査を追加しない。copy-on-saveのイメージ用領域でruntime-only入力/資源を除く既存規則は維持する。

## 実行体末尾情報とfail closed（比較レビューでB案を採用）

SIGEND01の20byte footerを維持する。SIGEND02やAPP bitを増やさず、画像内の非公開rootを唯一の登録情報にする。[比較レビュー](reviews/1067-metadata-claude-review.md)。元案は[レビュー用原案](reviews/1067-design-proposal.md)に保存した。

host_saved_image.readはAbsent / Present(owned bytes) / Failedを区別する。実行体の読取り権限を起動要件とし、open/seek/ftellできない場合はFailed。file sizeが20以上なら末尾20byteを読み、footer先頭（end-20..end-12）のSIGEND01を調べる。markerなしはAbsent、読み取り失敗はFailed。marker確認後はbase_len/image_len/20の加算overflow、baseとimageの範囲・file endとの一致、確保/読取り失敗をすべてエラーとする。marker自体が失われた任意の破損を、通常実行体と識別できる保証はしない。

host_saved_image.inspect(bytes)はheapにimage_format.Workspaceを確保してformat.parse（CRC/ABI/構造検証）を行い、system cellと対象colonと重複relocationをcore/app_entryの共通検査で確認する。型のあるViewを外へ返さず、m/lとentryの値だけを返してWorkspaceを解放する。サイズを推定値で固定せず@sizeOfで確保する。word/codeのfeature検査も既存のimage_featuresで行えるため、この段階で実施する。image=falseで非zeroのAPP rootはInvalidImageとして拒否する。未登録の画像を扱う既存の内部restore能力は別に維持する。

ここまでをhost option解析より前に行う。rootの有無でAPP/legacy grammarを選び、現在のStateに対するbuiltin table/容量/typed relocation等はその後のrestore preflightで検査する。二度parseするがViewを共有するための画像codec全体の改造は行わない。余分な検証費用は1069で小/大画像の起動時間として記録する。

full restoreの失敗は既存診断とstatus1で終了し、REPLやファイル引数へ落とさない。復元後rootとinspectのentryも一致検査する。saved実行体の--format/--lint/--no-appも、完全な復元検査を迂回しない。したがって一部のhost optionエラーはbuiltin一致エラーより先に報告され得るが、Forth引数実行・APP起動・整形書込みは完全な検査の後だけ。

SAVESYSの再保存は従来と同じfooter版を使い、markerがある場合はbase_len/image_len/endを検証してから古い画像/footerを剥がす。不正なfooterをbase_lenだけ信用して切り離さない。新BuiltinによるABI変更と、footer版の維持は別の話で、旧ABI画像を許可するものではない。

## アプリ引数とホストオプション

APP登録ありのSAVESYS実行体では、既定ですべてのargv[1..]をアプリへ渡す。-m/-l/-d/-e/--format/--trace/--/日本語/空文字/空白入りも保持し、自動的にForthソースやファイルとして実行しない。ARGC/ARGV/ARG/NEXT-ARG/SHIFT-ARGSの既存契約を利用し、argv[0]は現在起動した実行体の名前。過去の引数は引き継がない。

アプリ起動時のSigma側オプションは、最初の引数が専用sentinel `--sigma`のときだけ有効。形式は`app --sigma HOST-OPTIONS -- APP-ARGS...`。sentinelと区切りを除いた残りをアプリへ渡す。HOST-OPTIONS末尾の--は、APP-ARGSがない場合だけ省略できる。認めるものは既存のサイズ/スタック設定、--max-steps/--trace/--trace-limit/--profile/--coverage/--debug-log、--lint/--format/--format-check/--format-indent、および新しい--no-app。unknown host optionはstatus1で、アプリへ流さない。debug専用オプションはdebug=falseで拒否する。

APP実行体の--sigma内の-m/-lは、0指定も含め明示指定として拒否する。従来のno-entry grammarの0指定は現行parseStartOptionsに従い無視する。保存されたm/lのlayoutを使い、data/return/float stackのサイズは既存許可・容量検査に従う。既存通常版の自動起動なしでsentinelを使わなければ、parseStartOptionsと通常のファイル/-e/REPLの挙動は変えない。通常版でも明示した--sigma prefixは同じhost grammarで認識する。

`--sigma --no-app -- -e '...'`は登録を解除せずそのプロセスだけ入口を回避し、後ろを従来のファイル/-e/REPLへ渡す。`--sigma -- --sigma`で、最初のアプリ引数としてliteral --sigmaを渡せる。--no-appはdebugに依存させない。

--format/--format-checkは--no-app必須として、root!=0のAPP実行体では--no-appを必須として復元と登録検査の後、sourceを実行せずファイルを整形して終了する。--lintも--no-app必須とし、従来の検査モードへ進む。これにより診断用オプションが意図せずアプリを実行したり、APP引数を整形対象にしたりしない。

## 起動順と終了（全体レビューを反映）

0 Mac内部child専用プロトコルは現行どおり最優先。1 argvを既存方式で保持し実行体パスを取得。2 footer/inspect（CRC・ABI・構造/root/feature）を検査。3 APP又はlegacy grammarでhost optionを解析し保存layoutでサイズを決める。Absentでformatなら従来どおりStateなしで早期処理。4 Storage/Runtime/State/hostと既存deferを準備。5 復元前にstep_limit、tracing、trace_limit、plain_calls、cover_blocksを設定する。6 Presentなら完全復元・inspect結果とrootを照合する。format以外のlog/lint/profileとdeferは現行どおり復元前に準備し、復元失敗も記録できるようにする。7 formatなら完全復元検査の後ここで処理してreturn（log/lint/profileを作らない）。8 現在の引数を新vectorからsetArgumentsする。9 APPかつno-appでなければresetSteps、root再検査、executeWordを一度だけ呼ぶ。他は従来の引数loop/REPL。

plain_callsを画像復元後へ遅らせると短い定義が特殊化されtrace/profile/coverageが見えなくなるため、設定時点を維持する。復元失敗でも既存deferが動くよう、cleanupは必ず復元前に用意する。

APPの推奨実行効果は`( -- )`だが、正常復帰/BYEでdata・float・return stackの残りを新たにエラーとはしない。既存のfinishBlocksによる未完定義・quote・postponing検査とdirty block保存を共通利用し、正常時はstatus0、finish/cleanup失敗はstatus1。QUITは従来の-e処理と同じく診断表示なしでstatus1、finishBlocksを通さず既存deferだけで後始末する。通常THROW/UserInterrupt/StepLimitも既存reportDiagnosticとstatus1。APP内CATCHによる処理は従来どおり。独自終了コード語や終了時Forth callbackは増やさない。

stderrへ専用診断を増やす案は採らず、初期化前の画像失敗は既存terminalWriteのINVALID IMAGE !、初期化後はreportDiagnostic(error.InvalidImage)を使う。option診断も既存のstdout経路と整合させる。reader自体はUIを持たずerrorを返す。

APP起動のために通常VMへpollやsignal scopeを追加しない。待機中の既存中断と、APPが明示的に使うEXEC-LIMITED（debug+extensionのみ）の協調的-28がhostへ戻る場合はstatus1と共通cleanup。checkpointのない計算中のCtrl+CやOS強制終了はOSの既定処理に従い、終了コードと後始末を保証しない。この2種類を受け入れでも区別する。1048の取消し専用VMループ・継続を先取りしない。

APPの登録変更/解除/LOADをしても、hostの一度だけのdispatchを再実行しない。argv0はexecutable_pathでなく現在渡されたargument_list[0]。上限はargv0込み256件、文字列領域内で各text.len+1が収まること。空文字と範囲外を区別し、超過はStringTooLongで入口を呼ばない。

## SAVESYS出力の失敗原子性

現行の出力先への直接fopen(wb)は、保存途中の失敗でfooterなしの実行体を残し得る。APPができていないのに保存先を通常版として実行できる状態を避けるため、1068では同じdirectoryへ排他的な一時ファイルを作り、base/画像/footerを書き、flush・close・既存の出力権限設定まで成功してから同一filesystemのatomic replaceで公開する。実行体と保存先をfile IDで比較し、相対指定・hardlinkでも自己上書きを拒否する。最終symlink/Windows reparse pointと非通常ファイルは拒否する。POSIXでは空の排他的fileをkernelのumask適用で作成して最終modeを取得し、書込み前に0600へ落とす。完全なfooterのflush後に同じfdへ最終modeを戻してcloseする。process-wide umaskは変更しない。途中失敗時は自分の一時ファイルを回収し、既存の出力先は変えない。先に既存先を削除して置換する実装は使わない。Windows/POSIXの実APIと権限・日本語path・既存出力先を1068で検証する。任意の電源断に対する永続性までは保証しない。

## 機能除外と予約引数

image=falseでは3語を除外し非zero rootの自動起動も拒否。files=falseでもARGC/ARGV/ARG/SHIFT-ARGSの現在契約を使える。audio/graphics/extensionは起動基盤の必須条件にしない。

debug=falseの--sigma prefixでは、既存サイズオプション（-d/-r/-fとlong名、保存実行体の-m/-lは拒否）、--no-app、区切り--だけを許す。trace/profile/coverage/log/max-stepsだけでなくformat/lint/format-indentもdebug依存で拒否する。

macOSの内部child予約引数を1件だけ渡す組合せは現行の私有プロトコルが先に処理するため、APP引数としてそのまま使えない。予約値は--sigma-internal-window-child-v1で、argv[1]がこれだけの場合。公開host optionとの混同なく文書へ記載する。

## 実装分割と受け入れ

1068はcore登録/root検査/削除、画像codec preflight/append方針、host reader/inspect/CLI/起動終了へ分ける。1069は実際の生成実行体を別プロセスで起動して出力/終了/資源を検査する。APIのコード実装前にこの1067をレビューして採用仕様を固定する。

必須ケース：登録0と無効/未完/DEFER等の拒否、query/clear/再定義/FORGET/MARKER/ID再利用、SAVE/full restore/LOAD(設定保持)/再保存、引数なし/空/空白/日本語/-e/-m/--format/--trace/--/literal --sigma、diagnostic no-app、unknown/missing host option、ABI/CRC/flag/length壊れ、APP一度だけ/正常/stack残り/未完定義/BYE/QUIT/THROW/Ctrl+C/cleanup失敗。audio/graphics/extensionの8通り、image/files/debug除外、Windows/Linux自動とMac実機を分ける。LOGO実装は試験前提にしない。

SAVESYSの置換後のmode/ACLは新しい生成実行体としてkernelのumask・directoryの継承規則で決まり、既存出力先の独自ACLをコピーする仕様にはしない。readonlyの既存先は拒否する。原子的な通常失敗の公開制御と、fsync/停電耐性の保証は別で、後者は今回追加しない。
