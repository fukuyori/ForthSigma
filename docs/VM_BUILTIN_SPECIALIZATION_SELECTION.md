# 組込み語呼出し特殊化の選定（2026-11-16）

**最終状態：生成コード・回帰・画像プローブは確認済み。専用ケースの校正未達により候補の速度は未測定、採用保留。本体未反映。**

現行のcompiled -ROTはbuiltinInLoop→executeBuiltin→std.mem.rotateを通る。前のLinux非counted計数では各1回/反復だった。一方ROTはprimitiveタグから直接進む。この差は候補の根拠だが、新しい試作の削減やWindows速度を保証するものではない。

OpKindに単純にminus_rotを追加する案は選ばない。image_encoderはprimitiveを保存時call_builtinへ正規化するが、image_format.layoutSignatureはOpKindのexecution-onlyを含む全enum名・値をhash入力とする。末尾追加でも署名入力が変わり、保存互換性に無影響とは仮定できない。

call_builtinの既存id範囲検査・outer_pc更新を維持し、既存Builtin.minus_rotだけ既存State.executeBuiltinを@call(.always_inline,...)で定数引数とともに呼ぶ。ほかの語は元のRunning境界・builtinInLoopへ進む。既存のstd.mem.rotateを維持し、固定3セル化やalign64の試作は混ぜない。

executeBuiltinは語を実行してresultを保持→checkOutputError→try result→coverage判定の順である。module.executeを直接tryしてから出力エラーを確認するとエラー優先が変わるため、共通処理を手動複製せず既存関数をinlineする。現在のstartsBlock(minus_rot)はfalseだが、フックを手動で省略する設計にはしない。

**※仮説：定数引数と強制inlineにより2段のヘルパーを減らせる可能性がある。** 実際のcall数・コードサイズ・速度は生成物で検証する。std.mem.rotateまでinline化されてデータ移動が変わる場合は「2呼出しだけを除いた対照」とは呼ばない。

OpKind/Builtin・Word/Op・compileCall対応は変更しない。保存署名に新しい入力を足さない設計だが、SAVE/LOAD双方向とSEEは実際に検証する。pending出力エラーとunderflowの優先、failed_pc、counted/非counted、順序・prefix・満杯・構成別両OSも確認する。

専用-ROTカーネルを対象効果のために含め、全17項目/OSで他経路の追加分岐や配置の影響を確認する。CPU一次指標・既定上限を維持し、校正未達を通過扱いにしない。標準の整数演算・LOOP10%以上に届かず対象語だけ改善する場合は部分改善と分けて判断し、新しい合格率は今回独自に設けない。

親826、生成物827、回帰828、測定829、レビュー830をautoで登録した。候補791〜793・804は826の後へ依存を追加し、一案ずつ進める。[根拠・ソースハッシュ・タスク](measurements/2026-11-16-builtin-specialization-selection.json)。コミット・タグ・プッシュ・リリースは行っていない。


## 単独試作と生成コードの結果

#827で既存call_builtin内の-ROTだけを特殊化した。両OSのfast/baseline CPU・シンボル付きビルドは成功。新しいタグ、手書きrotate、align(64)は追加していない。defs・words_stack・image_format・image_encoderは基準とバイト単位で同じである。

Linux Callgrindの100/200反復差分で、-ROTはbuiltinInLoop→executeBuiltin→rotateの3呼出しから、rotate1呼出しへ変わった。カーネル全体は194→131命令、読込み52→31、書込み31→12。rotate自身の自己計数は両版ともIr56/Dr8/Dw7で、少なくともこの入力のrotate処理が消えたり別のデータ移動へ置き換わった結果とは扱わない。ROT対照132命令、既存スタック対照326命令は変わらなかった。ただし両対照はprimitive経路であり、新しい比較を通る-ROT以外のcall_builtin語への影響は確認していない。再評価にはその対照を追加する。これらはLinux非countedの計数で、Windows・countedや実時間へ一般化しない。

基準と候補へ同じ新テスト3件を入れ、Windows Debugは各1,073成功・10skip。順序・prefix・全容量・underflowに加え、pending出力エラーとunderflowが同時ならerror.Thrown/-123が先になること、失敗PC・バックトレース・深さの復元をcompiled/両ループで確認した。新テストは本体へ取り込んでいない。

基準がSAVEした画像を候補で、候補がSAVEした画像を基準でLOAD-DICTIONARYし、両方で1 2 3を-ROTして2 1 3 0を出すことを確認した。両自己roundtripも含め4load実行が成功、SEE出力も同一だった。このプローブの互換性確認であり、任意の全画像に対する保証とはしない。SAVESYS実行体やインストーラーは作成していない。

[生成物・呼出し・テスト・双方向画像の根拠](measurements/2026-11-16-builtin-minus-rot-generation.json)を保存した。専用カーネルは最終3セルを100×底＋10×中央＋上端で検査し、DEPTH=0と後続42も照合している。なおbuild.pyの成功printにコピー元のalignment-controlという文字列が残るが、実際のソース・差分・コマンドは本試作のものである。実行したスクリプトを後から偽装して書き換えず、記録へ注記した。

#828の構成別・両OS回帰は完了した。Windows fastは1,073成功/10skip、no-debugは1,006/77、no-floatは1,008/49、minimalは592/462。Linux Debug/fastは各core 1,014/5、host 63/1。Linuxクロス実行の親コマンドはexit 1だが、生成された2 ELFをWSLで実行し各exit 0を確認した。freestandingもコンパイルした。Windowsサイズは1,809,408→1,810,944 bytes、Linuxは1,891,456→1,893,072 bytesで、各約0.09%増、1%上限内。[検証記録](measurements/2026-11-16-builtin-minus-rot-validation.json)。

## 専用ケースの校正と保留判断

Windows専用-ROTカーネルの基準版だけのpilotから349,090,910反復を固定した。独立2系列、各A1/A2でwarmup 1回を除き5標本、順序を交互にして測定した。最小中央値は5,281.250 msで5秒条件を満たしたが、最大A/A差は3.539823%で2%上限を超えた。全標本を保存し、同じ計画内での再試行は行っていない。[校正データ・プロトコル](measurements/2026-11-16-builtin-minus-rot-target.json)。

このため候補版は計測していない。Linux専用ケースと両OS各17標準項目も未測定。命令数削減や回帰通過から速度改善を推定せず、採用を保留する。遅い候補と判断したものでもない。一次指標はREADY/DONE間のGetProcessTimesのkernel+user差。補助のthread/cycle読取りを含むログ付きプロトコルであり、追加APIは親プロセス側で実行され、子のCPU値に直接加算されるわけではない。ただし観測が実行環境へ及ぼす影響は未評価。A/A差は信頼区間や全変動の上限ではない。

試作と追加テストは.work内だけに保持し、本体ソース・本体Windows実行体は採用済みPC分離＋データ語経路分離版のままである。性能を確認できる測定条件の整備後、独立した事前計画で再評価する余地を残す。


## Claude Codeレビュー対応

[レビュー原文](VM_BUILTIN_MINUS_ROT_CLAUDE_REVIEW.md)で指摘されたLinux CLI未実行9項目を、build.zigの入出力・終了値条件に従いDebug/fastの生成済みELFで追加確認した。18実行すべて成功。[CLI補完記録](measurements/2026-11-16-builtin-minus-rot-linux-cli.json)。元のクロス実行失敗ログは保持し、最初から全試験が成功していたとは扱わない。

画像プローブとCallgrindはシンボル付き実行体であり、時間計測用のstrip版とは別である。保存画像2個は同じサイズだがバイト同一ではなく、ハッシュ差の原因は未特定。全画像互換性の保証はしていない。

本体と実行体の最終ハッシュ、defs・words_stack・image_format・image_encoderの基準/候補同一性、計時スクリプトの現時点ハッシュを[追加根拠](measurements/2026-11-16-builtin-minus-rot-review-evidence.json)へ記録した。スクリプトのハッシュは事後記録で、実行前凍結の証明ではない。[指摘への回答](VM_BUILTIN_MINUS_ROT_REVIEW_RESPONSE.md)。

再評価では非-ROTのcall_builtin対照、CATCH内失敗、step/WATCH/profile併用も補強候補とする。系列ごとのkernel時間差とwall/CPU差は観察事項であり原因は未特定。独立2系列は別々の標本群であるが、約0.2秒間隔の連続実行で、環境の独立性を保証しない。

第1評価 #826〜830は打切り・保留判断まで記録して完了。速度改善の実証や本体反映の完了ではない。再評価条件の整備はautoの #831へ残し、次の優先調査 #791は[スタック検査調査](VM_STACK_CHECK_INVESTIGATION.md)へ整理した。
