# タスク1353：最小隔離の試作・レビュー修正

作成日：2026-11-23。これは1357の方式判断へ渡す試作であり、採用ではない。
根拠文書はTASK_CONTROL_DETAILED_PLAN（2・5〜9.1・12.2節）、TASK_CONTROL_AUDIT_REENTRY、TASK_CONTROL_AUDIT_SHARED_STATE、TASK_CONTROL_AUDIT_ALLOWED_SET、TASK_CONTROL_ACCEPTANCE、TASK_CONTROL_METHOD_COMPARISONである。

## 暫定条件と変更ファイル

G1の判断事項への仮置きとして、動的実行（EXECUTE・.execute・.local_execute・DEFER・DOES>・CATCH/THROW）を拒否し、ワーカーではcounted経路を選ばず、PADを許可集合から外す。これは確定仕様ではない（`src/task_worker_probe.zig:45`、`:83`、`:130`）。

| ファイル | 要点 |
|---|---|
| src/task_worker_probe.zig | 新規State/Storage、専用Writer、静的到達検査、入力と結果のコピーを行う試験用ハーネスである。今回、呼出しOpの解釈・残留状態・循環・ループ語・出力上限を修正した（同`:7`、`:26`、`:58`、`:130`、`:155`）。 |
| src/tests/task_worker_probe_test.zig | 既存6試験を修正し5試験を追加した。合計11試験である（同`:9`、`:197`以降）。 |
| src/forth_test.zig | 前回の試作で追加した試験importである（同`:4`）。今回の修正では変更していない。 |
| docs/TASK_CONTROL_PROTO_1353.md | 本報告である。 |

src/forth.zigとbuild.zigは変更していない。試作のimportは試験ルートに限る（`src/forth_test.zig:4`）。通常ビルドのメイン実行経路へ変更を加えていない。生成コードの比較は未確認である。コミット・ブランチ作成・push・tque更新は行っていない。開始時から存在した他の文書差分は今回の修正成果に含めない。

## 設計上の選択とレビューへの対応

9件ともソースに照らして妥当と判断した。誤りとして退けた指摘はない。

1. VMのcall_builtinはbuiltin_countの範囲内の識別子からbuiltinフィールドを実行し、非インラインcall_colonはcolonを前提とする（`src/forth.zig:2101`、`:1978`）。検査器も両者を分離し、前者は範囲と実際のbuiltin、後者はcolon種別を検査する。インラインも元語のcolon種別を要求する保守的な選択である（`src/task_worker_probe.zig:97`、`:101`）。variable・constant・synonymを指す不一致Opを手で注入し、さらにkindをconstantへ変えたbuiltin語の禁止builtinフィールドも検査する（`src/tests/task_worker_probe_test.zig:197`）。
2. halted時にVMは入口を実行せず戻る（`src/forth.zig:1939`）。halted、loop/catch/frame/call深さ、capture_sink/target、output_file、report_capturingをDirtyVmとして拒否する（`src/task_worker_probe.zig:130`）。各フィールドとhalted状態の実スレッドJobを試験し、失敗・結果長0・データ深さ0を要求する（`src/tests/task_worker_probe_test.zig:231`）。
3. executeWordはsynonym先を再帰実行する（`src/forth.zig:1549`）。訪問済み集合だけでは循環を拒否できないため、enqueue前にsynonym辺のみを語数上限でたどる。範囲外と循環をInvalidCodeとし、通常のcolon再帰はこの検査では拒否しない（`src/task_worker_probe.zig:58`）。非循環・自己循環・2語循環を試験する（`src/tests/task_worker_probe_test.zig:197`）。
4. DOと同様、loop・plus_loop・I・Jを1360まで許可から外す。BEGIN/UNTILの有限計算は引き続き試験する（`src/task_worker_probe.zig:45`、`:112`、`src/tests/task_worker_probe_test.zig:165`、`:266`）。
5. Bufferの実効上限をmin(limit, 配列長)とし、残量は飽和減算で求める。limit=100で80バイトと追加文字列を書き、64バイトとoverflowを要求する（`src/task_worker_probe.zig:15`、`src/tests/task_worker_probe_test.zig:284`）。
6. failureの強制unwrapをoptional anyerrorの比較へ変更した。nullもpanicではなく期待値不一致になる（`src/tests/task_worker_probe_test.zig:86`、`:110`、`:160`）。
7. スレッド試験が示すのは隔離である。開始の待合せ後に処理する構造では、メインとワーカーのForth実行の重なりまでは証明していない。試験名も隔離の確認に合わせた。重なりは未確認である（`src/tests/task_worker_probe_test.zig:9`）。
8. システム領域の先頭0と末尾data_start-1を長さ0でも拒否し、addr=dataLimit・長さ0は成功とする。65バイト入力とHERE=dataLimit-1への2バイト入力をInputTooLargeにする試験を追加した（`src/tests/task_worker_probe_test.zig:293`）。
9. キャッシュログはgitの無視対象であり、保存成果物として残らない。必要な結果は本書へ転記する（`.gitignore:1`）。入力上限はresult.len（64バイト）に結び付いており独立した設定ではない（`src/task_worker_probe.zig:179`）。BEGIN AGAINはvalidateを通ることを試験したが実行していない（`src/tests/task_worker_probe_test.zig:266`）。Jobに取消し・期限はなくexecuteWordの帰還を待つため、この入口を実行するとjoinが戻らない。検査器は停止性を証明しない（`src/task_worker_probe.zig:168`、`:192`）。

VMは別々のStorageとStateを新規確保し、値コピーによる複製は行わない。準備ソースは信頼する試験入力であり、検査後はワーカーがVMを専有する。専用Writerは必須write_fnとcontextのみ設定し、optionalのcallbackと操作表はnullである。結果はJob所有配列へコピーし、join後にVMを解放する（`src/task_worker_probe.zig:21`、`:26`、`:141`、`:155`、`src/tests/task_worker_probe_test.zig:9`、`:96`）。

許可したメモリ語の実行時検査は既存VMに依存する。この検査器は敵対コードの安全境界ではなく、全Opのoperand整合性や実行時の領域権限を証明しない。ワーカー内管理領域への書込み制限は未完成である（`src/task_worker_probe.zig:45`、`src/forth.zig:2511`、`docs/TASK_CONTROL_AUDIT_ALLOWED_SET.md:22`）。

## 試験と実行結果

既存試験は、2ワーカーとメインのメモリ・変数・Writer隔離、コピー結果の所有、ABIの深さ・長さ・範囲違反、診断超過、禁止語と展開後Opの拒否、有限BEGIN/UNTIL計算、確保バイト数を扱う（`src/tests/task_worker_probe_test.zig:9`、`:65`、`:96`、`:115`、`:165`、`:186`）。追加5試験の内容は上記1〜9に記載した。

実行環境はWindows/PowerShell、zig versionの実出力は0.17.1である。キャッシュ書込み先は作業ツリー内とした。速度・時間の測定は行っていない。ビルドツールが表示する所要時間は測定結果に用いない。

```powershell
$env:ZIG_GLOBAL_CACHE_DIR="$PWD\.zig-cache\global"
zig build test --summary all
zig build test -Ddebug=false --summary all
```

両構成とも終了コード0、23/23 steps succeededである。実出力の要約は次のとおりである。

| コマンド | Build Summaryとcore試験 |
|---|---|
| zig build test --summary all | 23/23 steps succeeded; 1205/1215 tests passed (10 skipped)。coreは1205 pass, 10 skipである。 |
| zig build test -Ddebug=false --summary all | 23/23 steps succeeded; 1133/1215 tests passed (82 skipped)。coreは1133 pass, 82 skipである。 |

host/runtime等はcachedであり、上記件数は今回実行されたcore試験の集計である。試作の11試験に失敗・スキップはない（`src/tests/task_worker_probe_test.zig:9`以降）。途中で追加試験のbuiltinWordの戻り値を配列添字に使った箇所に型不一致が出たため、u16への明示変換を加え、上記の両コマンドを再実行した（`src/tests/task_worker_probe_test.zig:216`）。

確保量の実出力は次のとおりである（`src/tests/task_worker_probe_test.zig:186`）。

```text
default:     1353 bytes State=7171424 memory=67174400 data=32768 return=32768 float=32768 loops=131072 frames=65536 catches=1540096
debug=false: 1353 bytes State=6777936 memory=67174400 data=32768 return=32768 float=32768 loops=131072 frames=65536 catches=1540096
```

Storage合計は69,009,408バイト、Stateとの算術合計は既定構成76,180,832バイト、debug=false構成75,787,344バイトである。成功時にもstderrのサイズ出力に続きfailed commandという行が表示されたが、両プロセスの終了コードは0であり、Build Summaryは全ステップ成功である。

確保量は試験の実出力から転記する。OSのページ丸め、allocator管理費、スレッドスタック、実コミット量、Snapshot、検査用作業配列を含まない（`src/tests/task_worker_probe_test.zig:186`）。

## 詳細計画4.1の停止条件との照合

| 条件 | 結果と未確認事項 |
|---|---|
| debug=falseの無限ループを取り消せない | 本ハーネスには取消しがない。BEGIN AGAINは検査を通る。停止・回収の成立を示しておらず、1352との結合が必要である（`src/task_worker_probe.zig:168`、`src/tests/task_worker_probe_test.zig:266`）。 |
| 再入・展開による検査回避 | 動的実行と禁止Opを拒否し、不一致呼出しOpと循環の検査漏れを補った。全operand・実行時領域・復元後コードとの結合は未確認である（`src/tests/task_worker_probe_test.zig:115`、`:165`、`:197`）。 |
| メイン資源への干渉 | 論理メモリ・変数・専用Writerの隔離を確認する試験がある。実行の重なりと全ホスト資源の実機隔離は未確認である（`src/tests/task_worker_probe_test.zig:9`）。 |
| 早期解放・再利用での残存 | 結果コピー後、join後にVMを解放する。コピー元変更後の結果所有を試験する。取消し後・プール再利用は未確認である（`src/tests/task_worker_probe_test.zig:9`）。 |
| 費用が利用条件を満たさない | バイト数のみ記録する。合格閾値は未決、時間測定は未実施であり、費用の合否は未確認である（`src/tests/task_worker_probe_test.zig:186`、`docs/TASK_CONTROL_DETAILED_PLAN.md:121`）。 |

## 1357へ渡す判断事項

動的実行拒否・PAD除外・counted不使用を初期版の条件とするか、DO系をいつ許可するかは未決である。入力上限を結果容量から独立させるか、公開エラーと診断上限をどう定めるかも判断が必要である（`src/task_worker_probe.zig:45`、`:130`、`:179`）。

取消しとの結合、Snapshot復元後の検査、実行時メモリ権限、成功・失敗・取消し後のVM再利用、全ホスト共有状態の再帰監査、生成コード、他OS実機は未確認である。今回の試作を方式採用や1053の本監査完了へ読み替えない。詳細計画4.1の停止条件を通過したとの結論も出さない（`docs/TASK_CONTROL_DETAILED_PLAN.md:121`、`docs/TASK_CONTROL_METHOD_COMPARISON.md:141`）。

第三者コードは取り込まず、既存コアとZig標準ライブラリを使用した（`src/task_worker_probe.zig:2`）。
