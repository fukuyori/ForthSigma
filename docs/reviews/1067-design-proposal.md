# 保存アプリの起動基盤：1067 詳細設計案

2026-11-20。基点main d9e88f2。1067の設計対象であり、1068/1069の実装・受け入れを完了したものではない。既存の測定文書の差分を保持する。

## 公開APIと登録

本体のimage語群（image=true）にAPP-ENTRY! `( xt -- )`、APP-ENTRY@ `( -- xt flag )`、APP-ENTRY-OFF `( -- )`を追加する。audio/graphics/extension/debug/filesに依存しない。image=falseでは3語を辞書・HELPから除く。

初版の登録対象は、完成したcolon定義（:NONAMEも含む）だけ。wordIdで範囲を検査し、kind==colon、compile_only=false、定義中のwordでないこと、code範囲が有効なことを確認する。builtin、DEFER、SYNONYM、CREATE/DOES、forward、vocabularyは-261 InvalidExecutionToken。これらを使うアプリは`: MAIN HOOK ;`のようなcolon wrapperを登録できる。入口の実行効果は`( -- )`。setterは全検査成功後にpopし、不正xtでは既存設定と引数を保持。定義の途中の登録は-259 InvalidDefinitionとする。

wordIdは数値0も有効なので0で解除しない。未登録のqueryは`0 false`、登録済みは`xt true`。clearは独立語。@で破損した登録を検出したら-261として値を返さない。

新しい非公開system cell 0x0dd0（host_os_buffer_address+8からtimezone_buffer_address 0x0e00の間）にword-id+1を保存する。0は未登録。システム領域のコンパイル時非重複検査を増やす。このセルはアドレス型rootではなく専用のword-token root。範囲1..word_count、対象colonと完全性を保存・復元で検査する。セルに重なるaddress registry recordは不正として拒否。State直下への永続フィールド追加はしない。

FORGET/MARKER/HERE巻戻し等で登録wordを削除する前にrootを0へ戻す。新wordが同じIDを再利用しても復活しない。登録対象が残る後続word削除では設定を保つ。同名再定義はIDを変えない限り登録を変えない。アプリ実行中の削除制約は既存VMに従い、起動hostは開始時のIDを一度取得する。

## 保存・完全復元・追加読込み

SAVEとSAVESYSは登録を保存する。SIGIMG45/46/47のsystem memory領域に既存の方式で保持し、headerサイズやtyped address relocation形式は増やさない。新BuiltinによりABI署名が変わり旧ABI画像は従来どおり拒否する。登録rootがある画像のword IDは完全復元では既存のIDを保つため数値の再配置はない。新しいpreflightでrootを検査し、失敗時は辞書・設定・OS資源を変更しない。

LOAD-DICTIONARY/appendImageは辞書を追加するだけで、source側のAPP登録は常に引き継がない。target側の登録を未登録も含め保持する。source登録の構造検査は行う。source側の登録先word自体は通常どおり再配置して追加し、必要なら追加後のwordを明示的に登録する。設定の暗黙な置換や起動は行わない。full restore、append、SAVESYSプロセス起動を別の操作としてテストする。

root検査の共通関数をimage_graph.collect、image_restore_plan.prepare、append preflightへ置く。apply後に失敗し得る検査を追加しない。copy-on-saveのイメージ用領域でruntime-only入力/資源を除く既存規則は維持する。

## 実行体末尾情報とfail closed

main.readEmbeddedImageの現在の戻り値はnullに「埋込みなし」「読取り・確保・footer不正」を混同する。Absent / Present(owned bytes, flags, base length) / Failedを区別するreaderへ変える。実行体そのものを読めない場合はFailed（status1）。正しいmarkerを持たない通常実行体の末尾はAbsent。

新SAVESYSは24byte footer SIGEND02を書く。offset0..8 magic、8..12 image_len u32、12..20 base_len u64、20..24 flags u32。bit0はAPP登録あり、他bitは0。加算のoverflow、サイズ/配置、image CRC/ABI、flagと復元rootの一致を必須検査する。flags=0とroot登録の不一致もエラー。markerが見つかった後の読取り/確保/範囲/CRC/復元失敗はstderrの固定診断とstatus1で終了し、REPLやファイル引数へ落ちない。

旧20byte SIGEND01 footerはレイアウトを読むため認識するが、APPフラグなしとして扱う。画像ABIの互換性検査は維持する。SIGEND01でrootが登録されている新ABI画像なら不一致として拒否する。新SAVESYSの再保存は両footerのbase_lenを検査して古い画像/footerを切り離し、多重appendを防ぐ。実行体の任意の壊れ方すべてをmarkerなしと区別できる保証はしない。

footerのAPP bitは、復元前にCLI grammarを選ぶための情報であり、単独では信用しない。image rootと照合するまで入口を呼ばない。footerが壊れている場合は正常Sigmaとして続行しない。--formatの通常実行体での従来早期処理は残すが、saved footerがある実行体は少なくともfooter/画像preflightを先に通す。破損画像は--no-appでも復元しない。

## アプリ引数とホストオプション

APP登録ありのSAVESYS実行体では、既定ですべてのargv[1..]をアプリへ渡す。-m/-l/-d/-e/--format/--trace/--/日本語/空文字/空白入りも保持し、自動的にForthソースやファイルとして実行しない。ARGC/ARGV/ARG/NEXT-ARG/SHIFT-ARGSの既存契約を利用し、argv[0]は現在起動した実行体の名前。過去の引数は引き継がない。

アプリ起動時のSigma側オプションは、最初の引数が専用sentinel `--sigma`のときだけ有効。形式は`app --sigma HOST-OPTIONS -- APP-ARGS...`。sentinelと区切りを除いた残りをアプリへ渡す。HOST-OPTIONS末尾の--は、APP-ARGSがない場合だけ省略できる。認めるものは既存のサイズ/スタック設定、--max-steps/--trace/--trace-limit/--profile/--coverage/--debug-log、--lint/--format/--format-check/--format-indent、および新しい--no-app。unknown host optionはstatus1で、アプリへ流さない。debug専用オプションはdebug=falseで拒否する。

saved実行体の-m/-lは、--sigma内でも既存どおり拒否する。保存されたm/lのlayoutを使い、data/return/float stackのサイズは既存許可・容量検査に従う。既存通常版の自動起動なしでsentinelを使わなければ、parseStartOptionsと通常のファイル/-e/REPLの挙動は変えない。通常版でも明示した--sigma prefixは同じhost grammarで認識する。

`--sigma --no-app -- -e '...'`は登録を解除せずそのプロセスだけ入口を回避し、後ろを従来のファイル/-e/REPLへ渡す。`--sigma -- --sigma`で、最初のアプリ引数としてliteral --sigmaを渡せる。--no-appはdebugに依存させない。

--format/--format-checkは--no-app必須として、saved実行体では復元と登録検査の後、sourceを実行せずファイルを整形して終了する。--lintも--no-app必須とし、従来の検査モードへ進む。これにより診断用オプションが意図せずアプリを実行したり、APP引数を整形対象にしたりしない。

## 起動順と終了

0 Mac内部child専用プロトコルは現在どおり最優先。1 argvをUTF-8/WTF-8の既存方式で保持。2 実行体footerを調べ、APP grammar又はlegacy grammarを選ぶ。3 host optionを検査し、保存layoutに合わせStorage/State/Runtimeを準備。4 imageをpreflightし完全復元、root/flagを照合。5 現在の引数をsetArguments。6 hostの時計・I/O・debug/profile/log設定と既存cleanupを有効化。7 APP modeかつno-appでなければ保存したrootを一度だけexecuteWord。未登録又はno-appなら既存のargument loop/REPL。APP実行中にLOAD/clear/別の登録をしてもこの起動処理は繰り返さない。

APP開始時のdata/float/return/control/loop/call/frame/locals/quoteは既存restoreFresh後の空の状態。正常復帰時の公開contractは`( -- )`で、data/float/return/control/interpret-loop/quoteの残りがあればInvalidDefinitionを報告しstatus1。BYEがhaltedを立てた場合は既存契約を優先し、残stackの検査をせず正常終了。QUITはREPLへ戻さず正常終了として扱う。

通常復帰/BYE/QUITはdirty blockの保存を含む共通finishを行いstatus0、保存/後始末失敗ならstatus1。通常THROW/UserInterrupt/StepLimit/host初期化失敗は診断後status1。APPのCATCHが捕捉したエラーは既存契約どおりAPPが処理する。初版は独自の終了コードを返す語を追加しない。

APP自動起動のために通常VMへbudget/割込みpollを追加しない。中断は既存wait/入力語と、必要ならAPPが明示的に使うEXEC-LIMITEDの協調点に従う（後者はdebug+extensionのみ）。中断エラーがhostまで戻れば共通cleanupを実行する。OSの強制終了・checkpointのない計算・任意の外部プロセスの停止についてcleanupや20msを保証しない。1048のタスク制御・継続再開を先取りしない。

host資源は現在のrun/mainのdefer経路へ統一する。初期化済み資源だけを解放し、成功/THROW/BYE/QUIT/後始末失敗に同じ経路を使う。APP自身の明示的な後始末はAPPのCATCH等で行い、任意のForth callbackをhost終了時に自動呼出しする機能は増やさない。保存したOS handleやスレッド・継続は復活させない。

## 実装分割と受け入れ

1068はcore登録/root検査/削除、画像codec preflight/append方針、host reader/footer2/CLI/起動終了へ分ける。1069は実際の生成実行体を別プロセスで起動して出力/終了/資源を検査する。APIのコード実装前にこの1067をレビューして採用仕様を固定する。

必須ケース：登録0と無効/未完/DEFER等の拒否、query/clear/再定義/FORGET/MARKER/ID再利用、SAVE/full restore/LOAD(設定保持)/再保存、引数なし/空/空白/日本語/-e/-m/--format/--trace/--/literal --sigma、diagnostic no-app、unknown/missing host option、ABI/CRC/flag/length壊れ、APP一度だけ/正常/stack不整合/BYE/QUIT/THROW/Ctrl+C/cleanup失敗。audio/graphics/extensionの8通り、image/files/debug除外、Windows/Linux自動とMac実機を分ける。LOGO実装は試験前提にしない。
