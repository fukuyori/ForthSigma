レビューは完了しました。「Common採用なし・速度未確定」という結論を覆す問題はありませんが、文書を確定する前に直すべき記述が3点あります。Linux計時は未完了(`aa-1.json` と `aa-2-partial.json` まで、`aa-decision`・`compare-*`・`decision`・`complete` なし)で、計測値は読んでおらず推定もしていません。

## 重大指摘(文書確定前に修正を推奨)

**1. PGOの記述が対象targetを書いておらず、実際より広く読める**
- Cプローブ(`pgo-c-result.json`)は `x86_64-windows-gnu` だけで、Linux muslでは一度も試していません。LTOが通る唯一の候補がLinuxなので、「PGOはWindows GNUのCプローブのみ確認、Linux muslは未試行」と明記が必要です。
- 「Zig VM側のbuild-exeでは…unrecognized parameter」は不正確です。`zig-pgo-flag.json` の対象は最小プローブ `libc-lto-probe.zig` で、`-target`/`-mcpu` 指定なし、`-fno-emit-bin` 付きです。
- 確認できたのは「`zig build-exe` のCLIがこのフラグ名を受け付けない」ことだけです。VMソースやbuild API経由では試していないので、その範囲に書き直してください。
- 「全PGO手法が不可能ではない」という限定そのものは適切です。

**2. サイズ1%基準はfull LTOでも「Linuxのみ充足、Windowsは評価不能」**
- 基準は `docs/VM_PERFORMANCE_PLAN.md:179` で「Windows/Linux通常版で各1%以内」です。
- 文書はthinの超過しか触れておらず、fullが基準を満たしたように読めます。Windowsはリンク失敗で実行体がないため、fullも未判定と明記すべきです。
- 数値は検算済みで正しいです(full −3.286%、thin +1.138%、いずれも `strip=true`・Linux musl)。

**3. 冒頭の「回帰通過を確認」が範囲無限定で、テストへのLTO適用の証拠は間接的**
- 実施したのは `-Doptimize=fast` のみです。`test-linux-full.py` は流用元CLIスクリプトの `['debug','fast']` を `['full']` に置き換えています。冒頭文は「Linux musl・fast・WSL実行の範囲で」と限定してください。
- `candidate-linux-full-tests.log` にコンパイルコマンド行はなく、`-flto` は直接確認できません。確認できた証拠は次の3つです。
  - `unit_tests.lto`/`host_tests.lto` を追加したbuild.zig差分。
  - 両テストの `test_zcu.o` 先頭が `4243c0de`(bitcode)。
  - 同じビルドで生成された `sigma` がSHA f149…(CLI 9件すべて一致)。
- これはZigコンパイル単位がbitcodeで出たことを示すだけです。Cオブジェクト(core-math、`fma_for_tests.c`)と最終リンクのLTO化は直接示していません。「適用した」ではなく「設定し、ZCUオブジェクトのbitcode化で確認した」とするのが正確です。
- テスト結果自体は記載どおりです(core 1,011成功/5skip、host 63成功/1skip)。親コマンドのexit 1も、失敗コマンドがCLI 9件+テスト2件の計11件でELF起動不能と整合します。

## 適切と確認できた点

- **build API設定と実際の対応**:`default` は `exe.lto = null`、`none` は `.none` で、SHA一致を2 target・このtoolchainに限定した記述は妥当です。full/thinはSHA・サイズが変わっており、設定は実際に効いています。
- **CPU baseline**:全ビルドとプローブが `-Dcpu=baseline`/`-mcpu baseline`/`-march=baseline` で、native等の指定はありません。配布スクリプトの記述も `build-release.sh:84-89`、`build-release.ps1:52-58` と一致します。`-march=x86-64` の誤りを別ログに分けた扱いも適切です。
- **Windows失敗の限定**:本体full/thinは各58エラー、float=falseでも同種、最小Zig+libcとヘッダーなしCは各54エラーで、LTOなしはexit 0です。「原因未特定・Windows全般や別toolchainは断定しない」は証拠の範囲内です。
- **screenの凍結**:`script-freeze.json` と `start.json` のハッシュが一致し、両実行体のSHAを起動時にassertしています。判定式(両群とも10%以上短縮かつ2δ超)とA/A未達時の再試行なし停止は、protocolと文書に一致します。

## 任意事項

- **再現性の限界の追記**:global cacheのほか、ソースディレクトリの絶対パスとcwdも同一です。global cacheにはmusl CRTやcompiler-rtのビルド済み成果物も入り得るので、再ビルドされたのはプロジェクト側だけの可能性があります。`fresh-local-cache` が事前に空だったかの記録もありません。見出しは「同一環境での再ビルド一致」程度が無難です。
- **exe本体のLTO証拠**:本体ビルドにはbitcodeヘッダーの記録がなく、根拠はサイズとSHAの変化だけです。compiler helpには `-flto`/`-fno-lto` しかなく、full/thinの区別はbuild API側の確認に依存する旨を一言添えるとよいです。
- **screenの順序バランス**:`run.py` の `(i+index)%2` と奇数標本数(5と7)により、群内の先行回数が3:2、4:3に偏ります。群2で反転するので全体では相殺されますが、群ごとに判定するため注記の価値があります。
- **screenの外乱記録**:「build/回帰/profileと重ねない」はスクリプトで強制も記録もされておらず、WSLからWindowsホスト側の負荷は見えません。CPU0固定は割り込みの影響を受けやすい点も限界です。
- **screenの終了状態**:A/A未達時は `stop.json` を書いてexit 0、checksumのassert失敗時はpartialだけが残ります。結果を追記するときは `complete.json` と `decision.json` の存在で完了を判定してください。
- **配置差の交絡**:候補は1実行体・1条件なので、LTOの効果とコード配置の偶然を分離できません。`VM_PERFORMANCE_PLAN.md:97` の「配置差を性能改善と断定しない」を、速度節の結果追記時に明示するとよいです。
- **Windowsの表記**:未試行は `x86_64-windows-msvc` とlld以外のリンカである、と具体名を入れると限定がより明確になります。

なお、このセッションにはRead/Grep/Globしかなく、プランファイルの作成はできないため、報告のみとしています。