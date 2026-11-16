# BAKE-ALLのnative画像処理の観測（#848）

2026-11-16。Windows通常fast/baseline CPU/strip=trueの作業用コピーに観測を追加し、pinball・waterworks・klondikeのBAKE-ALLを調べた。**呼出し回数は前回のcompiled-PC分類と一致した。細粒度の時計追加による全体時間の変化も確認したため、観測値を本体の時間内訳や速度改善率として扱わない。本体コード・配布設定は未変更。**

## 範囲と対照

words_graphics.executeの外側だけを囲み、そこで呼ぶgraphics_images.execute等を含む区間をBuiltin別に記録した。子関数を別に足さず、入れ子の再入口は計数して重複区間を加算しない設計とした。今回の入れ子は全45標本で0。これは「全native処理」の計測ではなく、graphics moduleのexecutorが対象である。allocator、一般memory/stack、型や語のdispatch等は残余側へ入る。

同じ実行体で次の3方式を各5回、全標本保存・warmup除外なしで実行した。方式の順は0→1→2、1→2→0、2→0→1、0→2→1、2→1→0と変え、反復内の先頭を固定しなかった。完全な均衡・独立環境とは扱わない。affinity未固定、cache未消去、ホスト負荷未記録。build完了後に逐次実行し、他のbuild/test/profileと重ねていない。

- 方式0：引数境界の時計のみ。nativeごとの計数・時計なし。ただし観測版のwrapperと分岐は存在する。
- 方式1：nativeの回数のみ計数。
- 方式2：回数と外側executorの開始/終了QueryPerformanceCounterを計数。

区間はBAKE-ALLの引数境界。ファイル読込み・定義・チェック用の関数定義は前、reportを出して観測を止めた後にRENDERと全framebufferのチェックサムを計算した。NO-AUTORUN/NO-SOUND、表示/実入力/音声/FRAME待ちなし。QPCによる経過時間であり、process CPU時間ではない。5秒以上/A/A校正等の採用判定条件を満たす実験ではなく、診断に限定する。実行前に記録したprotocol/run.pyのSHAが実行後も一致することを確認した。

## 結果

msは標本ごとの値の中央値。割合は方式2の各標本でnative区間合計/全体を求めた値の中央値であり、個別の中央値同士の比とは限らない。

| 実例 | 方式0 全体ms | 方式1 全体ms | 方式2 全体ms | 方式2 native合計ms | 方式2 native割合 | native回数 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| pinball | 714.312 | 720.586 | 799.127 | 109.333 | 13.722% | 4,880,942 |
| waterworks | 223.357 | 224.003 | 256.672 | 39.635 | 15.445% | 1,779,250 |
| klondike | 426.566 | 419.002 | 438.697 | 17.186 | 3.930% | 720,157 |

方式2/方式1の全体中央値の差は順に+10.900%/+14.584%/+4.701%。方式1/0にも差があり、klondikeでは方式1の方が短かった。これらは観測方式と順序/負荷等が混ざった差で、時計の純粋な費用を確定した値ではない。差を引いて元のnative時間を推定する補正は行わない。方式0も本体とコード配置が異なるので、前回の約246〜762msとの違いを高速化とは扱わない。

native区間には開始/終了時計の一部負担とscheduling遅延が入り、区間外の時計呼出し・加算等は残余にも入る。短いPGET/PSET等は時計の粒度や観測負担に影響されるため、1回あたりの真の所要時間を出さない。方式2の残余中央値はpinball689.795ms、waterworks217.037ms、klondike421.636msで、**VMだけの時間ではない**。

| 実例 | 主なnative分類（方式2で得た個別区間合計の中央値） |
| --- | --- |
| pinball | PGET 3,277,909回/57.810ms、PSET 1,096,219回/18.371ms、GLYPH-LOAD 1,748回/13.100ms、HLINE 299,197回/7.444ms、CLS 135回/7.016ms |
| waterworks | PSET 1,270,036回/21.209ms、GLYPH-LOAD 989回/7.091ms、PGET 386,813回/6.781ms、IMAGE-NEW 204回/1.129ms、GLYPH-ALPHA 55,561回/0.982ms |
| klondike | PGET 645,376回/11.231ms、GLYPH-LOAD 366回/2.970ms、CLS 93回/1.222ms、HLINE 32,406回/0.740ms、GLYPH-ALPHA 20,713回/0.365ms |

分類数は15/15/12種類。表は上位5種類だけで、個別中央値の合計がnative全体中央値と同じになる保証はない。すべての分類・標本はJSONへ保存した。回数は方式1/2の各10標本で完全一致し、前回#847のBAKE-ALLで得たcall/builtin総数とも3ケース全て一致した。異なる観測処理のscope整合確認であり、計数の正しさを独立に証明したものではない。

## 出力と観測コードの検証

root各2回、観測版各15回で計51実行、exit0。各実例についてBAKE後に決定的な状態を作り、RENDER後の全framebufferを131倍加算の64bitチェックサムへ畳み込んだ。もう1操作後のRENDERでも同じ検査を行い、全方式・基準版でstdoutとDEPTH0が一致した。pinball/waterworksは選んだ1tick後も画像checksumが同じ、klondikeはdraw/flight後に異なるchecksumへ変わった。全資産・全状態の一致、hash衝突の不存在、全操作分岐の網羅を保証しない。表示受入でもない。

別の空区間/描画対照で、reset前のGFX-INITとreport後のGFX-PGETが計数されず、区間内のINIT/CLS/PSETだけ各1回になることを方式1/2で確認。方式0の計数0、画素456とDEPTH0もrootと一致した。過去の大きな計数だけに頼らずreset/report境界と画像操作の対照を追加した。

観測版buildは10/10成功。初回はZig reflectionの旧fields参照でコンパイルが失敗したため、リポジトリで使われているfield_namesへ修正した。初回script/logを保存し、計時前に成功を確認している。unit suite・Claude Codeレビューは今回は未実施。観測用コードを製品に採用するものではない。

## 判断と次の作業

#848は今回の範囲の観測・基準出力・攪乱・残余を記録して完了する。画像nativeの時間割合が本体でも上表と同じ、又は残余の全てがVMだとは結論しない。画像nativeだけを短縮したときの改善率や、local/VALUE案の予想効果も計算しない。

次の#849では、[local/call調査](VM_LOCAL_CALL_INVESTIGATION.md)のセル型local経路分離・VALUE経路分離を、共通する実例範囲・変更の安全性・検証費用で比較する。具体的な一案に絞れる場合だけ単独の試作計画を作る。今回の診断割合を根拠に新native命令や画像APIの一括変更へ進まない。資産生成のみの改善と標準整数演算/LOOP目標は分けて扱う。

[全標本・凍結protocol・script・観測差分・基準出力・対照確認](measurements/2026-11-16-bake-native-attribution.json)。
