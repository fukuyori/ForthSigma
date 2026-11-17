# 短い実例の反復計時入力（#877）

2026-11-17 最新結果：[#881の継続評価](VM_PARTIAL_ADOPTION_LOCAL_STANDARD_RESULTS.md)を停止条件まで完了し、#870を終了した。VALUEは未測定38条件を残して評価を終了。セル型localは実例18条件と標準16条件で悪化上限を通過したが、Windows catch-nested-256が上限5%を超え、標準17条件は未比較。両候補とも追加採用は保留、製品VMは採用済み基準版のまま。以下は各時点の履歴である。

2026-11-16。[初回部分採用評価](VM_PARTIAL_ADOPTION_RESULTS.md)でWindows waterworks logicの単回CPU差が非正となったため、別の計時入力を設計・検証した。過去のfresh-process条件を再試行したものではなく、新しい反復条件である。採用基準とprocess CPUという主指標は維持する。

## 反復する入力

waterworks logic、klondike logic、pinball/waterworks/klondike renderの5ケースを、同じprocess内で繰り返す。画像を確保する資産生成はこの方式へ変更せず、従来のfresh-process合算を維持する。

`REQUIRE-GRAPHICS`を先に完了し、その後の`HERE`からゲーム読込み・決定的な初期化・WORKLOAD定義後の`HERE`までの論理データ領域を保存する。各反復の前に別領域の保存bytesを`MOVE`で復元する。`src/core/memory_map.zig`でデータ領域と入力・heap・localsの領域が分かれていることを確認した。VM全体の状態を巻き戻す仕組みではない。

renderでは各反復前に`SCREEN DRAW-TO W H GFX-INIT`も行い、画面を初期化する。BAKE済み画像は反復間で保持する。画面初期化・データ復元・WORKLOAD・状態checksumは計時に含め、ファイル読込み・資産生成・定義のコンパイル・初期snapshot作成はREADY前に終える。

各回で初回fresh入力と同じ状態checksumを検査し、不一致ならTHROWして停止する。反復回数をlocalに数えて結果として返し、Python側の独立期待値Nと照合する。最初はカウンターをデータスタックへ置いてDEPTH checksumを変えてしまう不備を検出したため、localへ修正して全検証を行った。ゲームやVMを期待値へ合わせて修正したものではない。

復元の所要時間を差し引かない。この結果は「初期状態復元を含む600tick等の処理」の比較であり、過去のfresh-child単回処理との絶対時間・短縮率を直接比較しない。

## 事前検証

- 両OS×基準/VALUE/localの3実行体で、反復ごとの選択状態checksum、ゲーム論理領域全bytesのhash、HERE、DEPTH=0を確認した。
- waterworks/klondike logicはN=1/2/7/20、renderはN=1/2/7で確認。実際の計時ループもN=11で検査した。
- waterworksは復元を省いた負対照を両OSの基準版で実行し、2回目に状態checksumが変わることを検出した。
- renderは最終frame全体をPPMへ保存し、反復数間・基準/候補間でSHA256が一致した。これは最終frameの一致で、全中間frame・実ウィンドウの視覚的受入れ試験ではない。
- klondikeはCARD-BUF/BASE-BUFが別heapにあるため、その終了時hashも反復間で照合した。論理領域の復元がheapやnative host状態も復元するとは扱わない。

以上134件の検証記録と、両OS×両候補×5入力の20件のREADY/DONE手順確認を保存した。候補・helper・ゲーム入力は従来の凍結SHAと一致する。新しいVM buildや配布実行体の置換はしていない。

## 固定する校正条件と再開順

baseline-only pilotの初期Nはwaterworks logic=1000、klondike logic=100、各render=10（両OS共通）。pilotのprocess CPUから約6秒となるNを一度固定する。今回の候補側事前確認の値をNの選択へ使わない。

その後はA1/A2各5標本×2系列、全arm中央値5秒以上・最大δ2%以下を条件とする。通過後だけ各7標本×2系列を比較し、各armのwarmup1回を除外・保存、先後交替・系列2反転を維持する。CPU2固定、子の生存中affinity直接確認、OS設定を変更しない。最初の未成立条件で停止し、N/CPU/標本数の探索や同条件再試行はしない。

順序はVALUE→local。候補ごとにwaterworks logic→klondike logic→pinball render→waterworks render→klondike render→waterworks資産生成→klondike資産生成、各ケースWindows→Linux、その後に標準34条件（整数→LOOP→残り通常項目→CATCH系、各Windows→Linux）とする。

既に通過したpinball資産生成・logicの両OS比較は、旧resultsのSHAと同じ実行体を確認して参照する。今回同時期に再測定したとは主張せず、異なる計時方式や時刻の結果を足して全体の短縮率を作らない。必須実例の改善基準・その他の悪化上限・サイズ・安全性の条件は承認済み内容を維持する。

## 計時開始ガード

新controller/worker/protocol、入力・反復検証・手順確認記録を`ready.json`へ凍結する。controllerは全SHAを照合し、記録が揃わなければ開始しない。Pythonの最適化実行も拒否する。`--preflight`は実例を起動せず照合のみ行う。

両候補のpreflight成功と、凍結ハッシュを不一致にした負対照で開始前に拒否することを確認した。負対照後は元の記録bytesを復元した。新protocolのstart.jsonが未作成であることも確認した時点で#877の入力設計・事前検証を完了した。実測は後続評価タスクで扱う。

[入力・全検証記録・最終script・凍結protocol](measurements/2026-11-16-short-workload-timing-validation.json)。作業領域は`.work/partial-adoption-resume-20261116`、PPM画像等の大きな検証出力はそこだけに保持する。
