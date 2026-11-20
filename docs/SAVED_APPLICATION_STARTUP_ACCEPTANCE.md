# 保存アプリ起動：1067 ソース照合と受け入れ条件

2026-11-20、基点d9e88f2。この文書は実装前のソース照合・基準動作・受け入れ条件を保存したもの。新APIの実装試験と完了範囲は[実装・検証記録](SAVED_APPLICATION_STARTUP_IMPLEMENTATION.md)を参照。以下の「現行」は実装前を指す。

## 現行ソースとの照合

| 対象 | 確認内容 | 設計・実装で接続する点 |
| --- | --- | --- |
| main.readEmbeddedImage | SIGEND01末尾20byteを読み、なしと各種失敗をnullへまとめる | absent/present/failureを分け、marker確認後の失敗で通常起動へ落とさない |
| main.run | parseStartOptions→format早期処理→embedded取得→layout→State/Runtime→restore→setArguments→通常引数loop | saved APP grammarとno-app診断、復元前の判断と復元後の一度だけのdispatch |
| main.loadDictionary | 別StateをrestoreFreshし、現在StateへappendImage | LOAD自体は実起動ではない。追加先のAPP設定保持をtyped appendと同じ方針にする |
| main.saveExecutableImage | 保存元の末尾footerを除いたbaseへ画像と20bytefooterを付ける | 新旧footerを検証して剥がし、従来footerの長さを検証し、画像内rootを唯一の登録情報にする |
| State.wordId | 0を含む0..word_count-1が有効 | queryのflagと独立clearを使う。APP対象colonの検査は別途行う |
| State.dropWordsFrom/forgetFrom | 辞書削除と再利用、型アドレスとdebug情報を無効化 | すべての削除経路を調べ、登録IDが範囲から消える前に解除する |
| string_values.define rollback | 失敗時にword_countを直接old_wordsへ戻す | callbackを呼ばない定義処理だが、直接count変更も監査する |
| image_format.layoutSignature | Builtin enumの名前と値もABI hashへ含む | APP新Builtinで旧ABI画像を拒否。旧footer認識と画像ABI互換を混同しない |
| image_encoder | system領域0..0x4000を保存 | 非公開APP cellはsystem領域へ保持し、専用word rootとして検査する |
| image_restore_plan/restore.apply | preflight後のapplyは失敗しない設計。stackを空にし完全復元 | APP rootの検査をpreflight側へ置き、実行はmain実起動だけに限定 |
| image_append_plan/selectGraph | FPATH以外のsystem relocationを保持する | APPセルへのaddress-type relocationは不正として拒否し、source APP設定を暗黙に取り込まない |
| words_system.setArguments | 最大256引数、文字列領域の事前容量検査。空文字は非zeroアドレス・長さ0で保存 | app modeでhost制御を除いた新しいargv vectorを作る。失敗時に入口を実行しない |
| words_system.argument/shiftArguments | argv0を保持し、範囲外は0 0、空文字は存在する引数 | 空文字を引数終端と混同しない |
| main.nextArgument | Forthメモリからコピーしてからshiftする | app modeではこのファイル/-e消費loopへ入らない |
| main.main/run/finishBlocks | process cleanup errorとlint結果でstatusを修正し、block保存やruntime復元を行う | APP終了も共通経路に合流し、後始末失敗が成功に隠れないようにする |

## 既存動作の実行確認

`.work/1067/baseline/probe.py`、同`results.json`。測定時のWindows/Linux通常版（source789420e、Zig本体ソースはd9e88f2と同じ）で、SAVESYSした実行体を別プロセスで起動した。

- 起動語なし・引数なしは従来のバナーとREPLへ進み、stdin EOFで正常終了した。
- `-e 'REPORT BYE'`の後ろの空文字、`a b`、日本語を保持し、ARGC=4、長さ0/3/9と内容を照合した。
- saved実行体の`-m 1M`はstatus1で保存layoutを保持する診断となった。サイズ単位は既存parseSizeによりMが大文字（小文字mはINVALID SIZE）。
- APP-ENTRY! / @ / -OFFは現行実行体に未登録だった。
- 生成実行体の末尾はSIGEND01で、base/image長を記録した。

この確認は新しいAPP自動起動、画像inspect、no-appを検証したものではない。

## 1069での受け入れ表（設計レビュー後に固定）

| 群 | 条件 | 確認する結果 |
| --- | --- | --- |
| API | 登録/照会/解除、未登録query、範囲外xt、0、builtin、DEFER、SYNONYM、未完colon | 保存設定と引数を壊さず仕様どおり受理/拒否。colon wrapperと完成NONAMEを含む |
| 寿命 | 同名再定義、後続だけのFORGET、登録先のFORGET/MARKER/quotation中断による削除、ID再利用 | 別wordへ偶然切り替わらず、削除後は未登録 |
| 保存 | SAVE/full restore/SAVESYS/再保存、登録変更/解除して保存 | IDと意味を保持。画像を二重appendしない |
| 追加 | 未登録/登録済みtargetへ登録済みsourceをLOAD、source/targetの破損 | target設定保持・勝手に起動しない・必要なwordの再配置・失敗原子性 |
| 引数 | なし、空文字、空白、日本語、-e/-m/--format/--trace/--、literal --sigma | argv0は現在の名前、host prefix以外はアプリへそのまま渡す。Forthとして自動実行しない |
| host prefix | --sigma、区切り、値不足、不明option、debug除外、-m/-l | 不正はアプリへ流さずstatus1。保存layoutを守る |
| 診断 | --no-app、format/lintの必要条件、登録語がTHROWする画像 | 実起動を回避し、設定自体は解除しない。診断処理とAPP dispatchを混ぜない |
| 破損 | footer marker/長さoverflow/範囲不一致、CRC/ABI、無効root | entry/argument loop/REPLへ落とさず失敗。no-appでも破損画像を実行しない |
| 終了 | 通常/stack不整合/BYE/QUIT/普通のTHROW/協調的-28/CLI StepLimit | statusと共通後始末が仕様と一致し、一度だけの入口呼出しを保つ |
| 保存失敗 | 既存先なし/あり、base/画像/footer/flush/close/replaceの故障 | 既存先を壊さず、一時ファイルを回収。不完全な出力を通常版として公開しない |
| 資源 | 初期化途中と実行途中の失敗、block保存失敗、runtime復元失敗 | 初期化済み資源の解放、エラー優先度、保存済みhandleを復活させない |
| 除外 | audio/graphics/extensionの8通り、image/files/debugの代表構成 | 起動基盤は語群に独立。image除外は新語とsaved起動を仕様どおり除外 |
| OS | Windows/Linux自動プロセス、macOS実プロセスと実端末 | cross compile、別プロセス、device/UIの結果を別に記録 |

実装1068、受け入れ1069では実行ファイル・source指紋・argv・stdout/stderr・status・残資源数を記録する。将来追加のPCM/フレーム提示/タスク資源との結合は最終1057の担当であり、1067の仕様設計を全後続実装待ちにしない。
