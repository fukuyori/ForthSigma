# 読込みと段階別経過時間の診断（#836・途中結果）

2026-11-16。Windows用の作業用コピーに観測処理を追加し、[12ケースの命令計数](VM_WORKLOAD_PHASE_PROFILE.md)と同じ入力を実行した。本体・配布設定は未変更。計測版は通常fast、baseline CPU、strip=true、通常機能。profile/countingは有効にしていない。

## 観測方法

引数境界にreset/reportを置き、QueryPerformanceCounterで段階全体の経過tickを取得した。同じ区間のGetProcessTimesによるuser+kernel CPU時間も保存。fileOpen/fileClose/fileReadLine/filePositionを薄いwrapperで囲み、それぞれの呼出し数と経過tickを加算した。read_lineの返したpayload長も合計した。ファイル操作の前後で時計を読む処理自体の負担が入り、wrapperがコード配置に影響する可能性もある。本体の未計測実行時間とは区別する。

各ケース5標本、全標本保存、warmup除外・再試行なし。CPU affinity未固定、OS cacheは消していない。通常の採用判定に使う5秒以上/A/A校正は行わず、診断用の短い測定とした。速度改善率や候補の採用判断に使わない。build完了後に逐次実行し、buildと計時は重ねていない。

## 結果

各列は個別に求めた中央値（ms）。読込みはファイル引数のincludeFileから定義処理が終わるまで。資産生成等の入力範囲は前回資料と同じで、実際のINIT-GAME全体ではない。

| 実例 | 読込み・定義全体 | ファイルcallback合計 | 資産生成 | 開始状態生成 | 追加キー操作 |
| --- | ---: | ---: | ---: | ---: | ---: |
| pinball | 2.214 | 1.123 | 762.184 | 0.171 | 0.019 |
| waterworks | 2.030 | 0.999 | 245.501 | 0.023 | 0.181 |
| klondike | 2.326 | 1.147 | 463.720 | 0.084 | 1.766 |

資産生成のCPU時間中央値は順に750.000/250.000/453.125ms。短い残り9ケースのCPU中央値は全て0であり、CPU負担が0という意味ではない。観測されたCPU時計の粒度で短区間の差を判断できなかった。壁時計とCPU時計は別なので、相互に引き算しない。

読込み中のcallback呼出し数は、open/close各1、read_line/positionがpinball各1,355、waterworks各1,050、klondike各1,355。行payloadは47,837/35,529/47,539 bytesで、全15標本が元ファイルの改行を除いたbyte数と一致した。read_line/positionは物理行数+EOFの1回と一致。資産生成・開始状態生成・追加キー操作の測定区間では、対象4callbackの呼出しは全標本0だった。

これはCRTを含むファイルcallbackの時間であり、物理ディスク待ち時間ではない。各callbackの合計を引いた残余には解釈、コンパイル、VM、埋込みgraphicsの定義、バッファ処理、引数処理、観測負担などが混在する。「純粋なコンパイル時間」や「I/O以外の全CPU時間」とは呼ばない。中央値同士を引いた値と、各標本の残余中央値も同一とは限らない。

今回の範囲では、資産生成が読込み段階より長い経過時間として観測された。初期化頻度や表示・音声を含む実利用全体の時間比を示すものではない。資産生成のVM処理とnative描画処理の内訳も未分離で、これだけでVM最適化の候補順位は確定しない。

## 検証と残件

計測版buildは10/10ステップ成功。12ケースの各1回の基準版出力確認と、計測版60実行のexit0/stdout一致を確認した。基準版のSHAは採用済み379d…を維持。callback数とpayloadも各5標本で一致。空区間の全callback0、既知のCRLF/空行を含む3行ファイルでopen/close各1、read_line/position各4とpayload一致を確認した。既存回帰suiteとClaude Codeレビューは今回は未実施で、観測用コピーを製品へ採用するものではない。

準備scriptの初回はPythonの既定cp932によるmain.zig読込みで失敗した。UTF-8 modeで再実行してbuildを完了した。VMの失敗・測定標本には数えない。

#836の初回調査の結論と省略経路は以下へ追記する。#806の順位確定はまだ行わない。

## 実際の初期化と省略経路（#846）

実際のINIT-GAMEも、基準版各1回と計測版各5回を別に実行した。NO-SOUND、NO-AUTORUNは維持し、pinballのみBUILD-WALLSを区間前に実行した。INIT-GAME内のNOW・ランダムなdealは固定せず、出力の全状態同一性ではなくDONE=false、data深さ0、pinball/waterworksのtitle mode、klondikeのD-SRC/HOVER=-1を全18実行で確認した。経過時間中央値はpinball 0.0046ms、waterworks 0.0021ms、klondike 0.0814ms。対象4callbackは全15計測で0。極短時間のため効果判断には使わない。

省略した処理をソースと照合した。

| 経路 | 確認した実装と調査範囲 |
| --- | --- |
| 資産生成 | 各BAKE-ALLは画像・文字等を生成し、内部でGFX-INITも呼ぶ。単なるソースコンパイルではない。native描画を含む内訳は未分離 |
| 音声 | 各実例はHAS-SOUNDの条件でSAMPLE/SFX/PLAYを使う。NO-SOUND下ではMAKE-SOUNDSは空、EFFECT/JINGLEも代替定義になる。今回の時間に音声生成・再生は含まれない |
| 入力 | KEY!へ渡した値の処理は実行したが、INKEY/KEY-HELD?/MOUSE/MOUSE-EVENTのpolling・実イベントやdrag/dropの全操作は未測定 |
| 表示と待機 | 各ゲームloopの16 FRAMEを省略。graphics.fsのFRAMEは待機後SHOWを呼ぶので、headless RENDERと表示付きframe時間は異なる |
| コンパイル・I/O | ファイルcallbackを分離観測したが、残余はコンパイル専用ではない。embedded graphicsはホストread_lineを通らず、直接解釈/native処理もcompiled命令計数から漏れる |

今回の限定入力に対する初回調査として#836/#805を完了する。全実利用性能の測定完了という意味ではない。次の#806では、BAKE-ALLのVM/native内訳の観測を追加候補に含め、call/local_fetch等の頻度と併せて比較する。コンパイル内部の細分化と表示/音声/マウスは未測定項目として残し、必要性を順位比較で判断する。約2msの読込みの細分化や極短時間の初期化特殊化を、現段階で次の実装に選ばない。

[全60標本・コマンド・script・差分・build・対照確認](measurements/2026-11-16-workload-native-diagnostic.json)。
