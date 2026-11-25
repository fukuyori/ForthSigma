# tque 1396：待ち滞留の計測端点

2026-11-25、ロク。開始点 main c4931ac。本測定は行っていない。

同じタスク行に submitted（既存の Service.submit 開始）、input_copied（所有入力コピー完了）、enqueued（キュー登録後、ロック解放前）、acquired（同じロック内でのワーカー受取り、期限・取消し確認前）を記録する。acquired は atomic で受け渡す。通常ビルドでは comptime の計測条件、空の Storage、定数を返す now() によって除く。命令ごとの確認は加えていない。

runner は enqueued→acquired を用途別に集計し、G1=50ms、G2/T1=100ms、I1=200ms と既存の80%規則を適用する。根拠は利用条件3節。I1の先行blockerは従来の投入→公開と同じ条件で除外する。キューから取り除いた未実行タスクは滞留0として数えない。それ以外の端点欠落・不正は欠測とする。smoke は項目の型と名前だけを確認し、時間統計を計算しない。submitted は公開語の引数検査を含む全体の開始ではなく、従来どおり内部 submit の開始である。

Snapshot の独立した「投入可能」端点は未実装。利用条件6節は取得開始→投入可能100msを定めるが、成立条件を定義していない。STATE_MACHINE 3節はキュー受理を定め、PUBLIC_API_PROPOSAL 3〜4節はSnapshot取得と入口検査・入力コピーを伴う投入を分けている。Snapshot ID登録、投入受理、ワーカー復元のいずれかを推測で選ばない。snapshot_main_ns はAPIの所要時間だけである。端点の実装には利用者による成立条件の決定が必要であり、D07全体を照合できたとはしない。

計画をv6 / macOS v4へ改訂し、1396の理由、新指標、未確定の区間を記した。回数・追加回数・供給間隔は変更していない。固定SHA-256：

- Windows/Linux: c45a98503ee4939ddd2518377ee721e70656b38af5ebc4a9d3af61de083e4dcb
- macOS: 515804545d987b0c80326b48314340d212e531a528e6b30d2963ece5c6141c27

検証は zig build test、debug=falseのtest、runtime-test、計測用ビルド、例題17群、hold、output、文書検査、変更したZig 3ファイルのfmt確認が成功。日本語のTASK-SUBMIT/SNAPSHOTの説明は引き続き正しく、公開仕様を変えていないことを確認して翻訳元指紋を更新した。

Windows smokeの証跡は .work/acceptance/20261125T115104Z-0cf0769c/results.json。端点形式10件で4用途の指標名を確認し、全件valid、時間統計なし。最初の直接指定smokeはnative-probe条件で拒否され、runner管理のビルドで成功した。最初のholdは既存通常実行体を参照して失敗し、計測用ビルド後に成功した。キャッシュのAccessDeniedは、ZIG_GLOBAL_CACHE_DIRとZIG_LOCAL_CACHE_DIRの両方をリポジトリ内へ指定して解消した。

通常ビルドの.text比較は下記へ記録する。tque照会は外部保存先lockへのAccessDeniedで失敗した。tque更新、commit・branch・tag・pushは行っていない。指定の手動受け入れ3ファイルは編集していない。

以下はClaude用の未実行の本測定コマンド。時間の測定は必ずレモンに確認してから行い、CONFIRMATION_REFERENCEを実際の確認参照へ置き換える。計画の環境情報を記録する。workloadsは既定の指示どおり独立2回とし、旧標本と混ぜない。Snapshotの未確定区間はこれらのコマンドでも判定できない。回数は計画とrunnerの既定値を維持する。

Windows (PowerShell, repository root):
```powershell
python tests/scripts/run-acceptance.py --mode measure --only workloads snapshot --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN.md --plan-sha256 c45a98503ee4939ddd2518377ee721e70656b38af5ebc4a9d3af61de083e4dcb --confirmed CONFIRMATION_REFERENCE
```
Linux (repository root):
```sh
python3 tests/scripts/run-acceptance.py --mode measure --only workloads snapshot --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN.md --plan-sha256 c45a98503ee4939ddd2518377ee721e70656b38af5ebc4a9d3af61de083e4dcb --confirmed CONFIRMATION_REFERENCE
```
macOS (native arm64, ~/source/zig/ForthSigma):
```sh
python3 tests/scripts/run-acceptance.py --mode measure --only workloads snapshot --plan docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md --plan-sha256 515804545d987b0c80326b48314340d212e531a528e6b30d2963ece5c6141c27 --confirmed CONFIRMATION_REFERENCE
```

Final Git inspection also shows changes to protected manual files and new 1395/wait fixtures during the session. This work did not edit or revert them. They remain outside the 1396 implementation.

Normal .text: same build directory, identical ReleaseFast/debug=false/strip=true/task-acceptance=false arguments, HEAD archive before/after the three Zig changes. Raw PE .text sizes [1532928, 1532928], SHA-256 ['955e53b3e44a95130d83f768441e815a60dad1bf064967988316c536794c5016', '955e53b3e44a95130d83f768441e815a60dad1bf064967988316c536794c5016'], equal=True. Evidence: .work/1396-release-text.json. Default Debug and different-directory comparisons also differed. No timing measurement was used.


## Snapshot の「投入可能」の定義（利用者の決定 2026-11-25、A）

レモンの決定により、`TASK-SNAPSHOT` が ID を返した時点を「投入可能」とする。現在の実装は取得をメイン上で最後まで行ってから ID を返し（`src/host_task_api.zig:214`）、返った ID はその時点で `TASK-SUBMIT` に渡せる。したがって「取得開始→投入可能」は既存の `snapshot_main_ns` と同じ区間になり、新しい端点は加えない。D07 の100msは、`snapshot_main_ns`（目安50ms）で照合する。これまでの最大は Windows 13.2ms・Linux 16.5ms・Mac 32.2ms（[1382報告書](TASK_CONTROL_IMPL_1382.md) の80%規則の節）。取得の一部を ID の返却の後に行う作りへ変える場合は、改めて独立の端点を加える。
