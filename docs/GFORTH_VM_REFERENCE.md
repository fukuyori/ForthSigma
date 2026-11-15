# Gforth実装から参照するVM設計

2026-11-15。Sigmaの[速度改善計画](VM_PERFORMANCE_PLAN.md)の補足。参照はGforthの固定コミット`c479e1eec66dd57a2441c3020177267ba70d3bdc`。速度比較に使用したインストール済みGforth 1.0.2と同一のビルド・ソース版だとは扱わない。

## 確認したソース

| ファイル | 読んだ範囲と確認内容 | Sigmaでの使い方 |
| --- | --- | --- |
| [engine/engine.c](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/engine/engine.c#L516) | gforth_engine内でip、sp、fp、lpなどを局所変数として宣言し、registerや対象依存マクロを用いる。構成によってTOSキャッシュも使う | Running局所保持案の比較材料。Zigでも同じレジスター割当てになる、という証明にはしない |
| [engine/threaded.h](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/engine/threaded.h#L100) | 構成別のディスパッチを定義し、読んだ経路には計算されたラベルへのジャンプとNEXTがある | 毎命令の共通コストと呼出し境界を調査する材料。Sigmaへcomputed gotoやスレッディング方式を移植する提案ではない |
| [prim 500〜620行](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/prim#L564) | (try)がVMのスタック位置などを保存し、uncatchが旧ハンドラーを戻す。fast-throwは保存したVM状態と継続先を復元する | 例外境界で保存・復元する状態を明確にする。SigmaのCatchContinuation・CatchContextとの対応を検証する |
| [except.fs](https://github.com/forthy42/gforth/blob/c479e1eec66dd57a2441c3020177267ba70d3bdc/except.fs#L70) | 高水準CATCHがTRY・EXECUTE・UNCATCHなどで構成される。バックトレースや抑制は関連語で扱う | 通常命令の経路と例外処理の責任を分ける考え方を参照する。TRY構文の追加はしない |

固定版はGitHubのファイル取得で確認し、取得時のblob SHA・参照範囲を`.work/gforth-vm-reference/manifest.json`へ保存した。原文は同フォルダー内だけに置き、Sigmaのsrcへコピーしていない。GPL-3.0-or-later表記を確認しており、コードやマクロの転用は行わない。

## 計画へ反映する点

1. **実行状態の所有者を明確にする。** 実行中はループ内の値を正とし、例外・動的呼出し・ホスト再入の各境界で何を保存し、何を復元するかを表にする。Gforthの変数宣言だけを根拠に、Sigmaのポインター共有が遅いと断定しない。
2. **例外フレームはVM状態として維持する。** Sigmaのホスト再帰回避と、設定した呼出し上限からの回復を残す。Gforthの生のリターンスタック配置や機械語番地をSigmaの論理メモリーへ持ち込まない。
3. **生成コードで境界を検証する。** 局所状態が実際にレジスターへ保持されるか、ヘルパー呼出し前後で退避が増えるか、通常ディスパッチに何が残るかを調べる。Cのregister指定やcomputed gotoの効果を、Zigのswitchへそのまま当てはめない。
4. **スタック全体のキャッシュは別の大規模変更。** sp/fpやTOSまで局所化すると、Sigmaの容量検査、公開State、コールバック、例外時の部分スタック効果への対応が増える。今回のRunningだけを対象とする案と混ぜない。
5. **性能比から実装原因を逆算しない。** Gforth-fastとの差にはエンジン・生成処理・コンパイラー・対象設定などの違いがある。各手法の寄与を測らずに「この方式で10倍になる」とはしない。
6. **まれな処理の配置は生成コードで判断する。** agyは、例外用ヘルパーが複数の分岐へ過剰にインライン展開されていないかを調べ、問題がある場合だけ非インライン化やcoldヒントを個別に試す案を提言した。計画のA2へ追加した。Gforthの分割がSigmaにも同じ効果を与えるという実測ではなく、coldヒントと非インライン化も別の指定として扱う。
7. **例外語の前提差を維持する。** 参照したGforthのfast-throwプリミティブは非0と有効なハンドラーを前提にする。一方、Sigmaのwords_diagnostics.zigは0を何もしない入力とし、非0をRuntimeErrorとして既存の伝播・未捕捉報告へ渡す。Gforthの内部プリミティブを写してSigmaの検査や振る舞いを削らない。

## 今回の範囲

これは静的な参照調査であり、Gforthのビルド設定の完全再現や、変更候補の生成コード・速度の確認ではない。SigmaのOpKind・Builtin ID・保存形式・既存機能を維持する方針も変えない。具体的な改善効果は、現在版と候補版の同条件測定で判定する。
