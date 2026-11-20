# SNES Windows/Linux測定準備

[計画レビュー原文](1175-1176-plan-claude-review.md)はHigh/Mediumなし。レビューは読み取りのみで実行していない。6負荷各16384frame、既定では計時せず全PCM/266state/queue2/fullARAMを照合する。`--measure` は開始確認への返答後だけ使い、7回の別process・順序回転で測定する。

検査を補強し、warmup後RESET/SETUPしたARAM全64KiBも計時前に書き出して初期期待値と照合する。出力A5/前状態と全ARAM確認を計時区間外で行い、dense8kHzの2件（reg/所有RAM byte）の生成・enqueue・空compactionをWORKへ含める。元のLowに対し、-O実行は入口で拒否し、round_timing_flagsで未計時round0を区別するようにした。

wallはNTIMEなので時刻補正の影響を受け、CPUTIME2回とD+も含む。CPU時間は参考値で粒度未校正。7round/6負荷なので回転1が2回となり完全均等ではない。compaction時に未処理データMOVEは生じない。Forth sourceは最後のroundを保存し、timedの7回は同じ文である。計時文はまだ実行しておらず、実行時の長さ/state/PCM/ARAM assertで不正な値を保存しない構成。

初回準備時点では速度値/採否/生成音の実聴は未実施で、1175/1176を完了とはしない。LinuxはWSL2で、物理Linux/Macへ外挿しない。開始前に確認するというレモンの指示に従い、この時点では計時開始の返答待ちだった。

Windows/Linuxの既定検証は両方成功。6負荷の全PCM/state/ARAMと初期ARAM/RESET/A5を照合し、timing_enabled=false、全timing配列空、中央値nullを確認した。-Oの実行拒否も確認済み。追加の計時はしていない。

## 初回測定と採否

レモンのＯＫ後にWindows→WSL/Linuxで各6負荷16384frame×7回を実行。全PCM/266state/queue2/fullARAMと前状態/ARAM reset/A5が全回一致。12組の中央値/実時間比を再計算して保存した。最重のfilter3/maxpitchは0.425/0.503倍、Windows echoは0.983倍なので、初回版では全負荷の実時間採用に不足する。

## Forth側の等価置換候補

[候補レビュー原文](1175-1176-arshift-claude-review.md)は、使用中のshiftでARSHIFTとの同値性を確認し、本体移行前の評価を推奨している。原文の表のH/Mは同値性/効果の判定欄の表記で、不具合High/Mediumの列挙ではない。速度改善の大きさや全負荷が1倍を超えるかは未確認である。

SD-ASRだけを既存ARSHIFTへのaliasにし、native/ABI/APIは変更していない。内部で使うshift1/4/5/6/7/10/11について旧helper/候補/独立Pythonの境界115vectorを両OSで照合。候補は1344vectorを含む8構成×20モデル群、6構成×19RAM群も通過した。全6負荷の計時なし検証でPCM/ARAM hash・266state・queueが初回版と一致し、初期ARAM/前状態/A5も照合。oracle mathのASTとharness不変、native332source/8binary現物hash不変も確認した。

[全記録](../measurements/2026-11-20-snes-dsp-os-acceptance.json)は旧sourceと初回7値を保存し、候補source/結果を別に記録する。候補の速度は未測定で、開始確認を新たに取り、その返答後に測定する。1175/1176/1177と親1173は未完了。今回コミット/プッシュは行っていない。

## ARSHIFT候補の測定後

新たな開始確認へのＯＫ後、Windows→WSL/Linuxの順で各6負荷×7回を測定し、全PCM/state/queue/ARAM照合も成功。全負荷で改善したが、filter3/maxpitchは0.496/0.556倍で実時間に不足した。全負荷のForth採用を保留し、既定方針に従ってnativeフレームkernelの1183を1173直下に登録。1175/1176/1177は1183を待つ依存を追加した。Mac確認を含め未完了のまま進める。

## OS実聴の準備

[試聴準備レビュー](1175-1176-listening-plan-claude-review.md)はHighなし、Medium3件。included全ファイルとhelper自身のLFハッシュを保存/照合し、同じ実行体・全ソースの無音実装置試験合格を--playの前提にし、段階表示を逐次teeする修正を行った。--check-readyは音を出さず条件だけ確認する。両OSで全PCM/state/ARAMの独立preflight、同じfixtureのFALSE実装置送出、readiness確認が成功した。生成音の実聴と物理Ctrl+Cは未実施。修正後の機能確認はこちらで実行した結果で、Claudeが再判定したという意味ではない。

各98304frame/約3.072秒、左低音→500ms間隔→右高音。反対channel全ゼロとPCM peak<=2048を確認。タイムアウトでもowned childだけを回収し失敗記録を保存する。Windowsの経路はwaveOut/WAVE_MAPPER既定で、装置一覧を実際の選択endpointと断定しない。[準備全ソース/ログ](../measurements/2026-11-20-snes-dsp-os-acceptance.json)のlistening_preparation。物理中断のhelperも準備し、RAM模擬THROWのcleanup/replayは両OSで成功したが、物理合格に数えない。

## Windows左音が聞こえなかった報告の切り分け

[raw同一周波数テストのレビュー](1175-channel-reference-claude-review.md)はfixture自体のHigh/Mediumなし。証拠/解釈のMedium2件に対し、RAM captureに試聴と同じ現物binary・全included source・mock helperのハッシュを加えて再確認した。RAM内配置の証拠に限り、Zig transport/OS/実装置を通った証拠とはしない。raw440Hzを左→右→両側各2秒で比較し、結果を得る前に元の原因を断定しない。無音実装置は3段階ともhandle0/underrun0/64000frame、S-DSP frame0/stack0/code0。実音の再生は開始確認待ち。

## Windows物理Ctrl+Cの準備

[中断準備レビュー](1175-1176-interrupt-plan-claude-review.md)はHighなし・Medium1件（両側toneとRAM中断検証を--playの前提にしていない）。両toneの全PCM/state/ARAM・source/binary hashと、RAM検査のbinary/本番source hashの一致を起動条件にした。模擬検証ではreplayを1blockへ縮める変換を明記し、実際の192blockの音は別の全PCM検査で確認する。--check-readyは成功、音は出していない。Lowの親deadlineは45秒、物理中断時のaccepted-frame表示、実Python.exe解決も追加した。PowerShellはparser確認済みで、可視窓の起動と実際のCtrl+Cの挙動は未実施。修正確認はこちらの実行結果で、Claudeの再判定と区別する。

## Windows最終受け入れ

[最終レビュー原文](1175-windows-final-claude-review.md)はHigh0/Medium3。M1の最新statusと歴史的な準備statusの混在を修正し、ユーザー返答追記の更新時刻/記録主体とactual-run snapshotの範囲を記録した。M2は試験後既定出力CABLE Input、後段物理機器未同定という制限を明記。M3は元の連続試験を再合格させたとは言わず、右初回/左単独再試験・raw参照・物理中断再再生の各確認を区別した。初回未合格と原因未特定を残す。

これらの制限を明記して宣言Windows範囲を閉じられるというレビュー評価に従い1175完了。Linux1176/Mac1177と親1173は未完了。物理はCATCH=-28/handle0/accepted81856、低音replay98304/underrun0/stack0/code0/userＯＫ、残留Sigmaなし。actual supervisor snapshotsのLF hashはこちらで再計算して照合した（Claudeは計算していない）。後のLinux tone proofファイル選択変更前に保存したWindows実行版と、現在helperを混同しない。

## Linux最終レビューの反映

[初回](1176-linux-final-claude-review.md)はHigh1/Medium3。[追レビュー](1176-linux-followup-claude-review.md)でH1/M1/M3解消、M2の最新状態更新を完了時に行う条件でblocking High/Mediumなし。H1は記録補助のTextIOWrapper.readlineとPOSIX communicateの混用で先読み行が欠けることをLinuxで切り出して再現し、Windowsでは欠けない差も保存。ファイル全量回収方式へ変えた無音の機能再試験で全ラベル/前後AUDIO?=-1/PCM統計を確認し、pacatをSigmaの子PIDとして記録した。元のログ/helperを残し、速度の再測定はしていない。

M1は実Linuxlauncherのprelaunch/postrun/snapshot hash一致とtool起動pathを補い、元の誤ったWindowslauncher manifestは注記付きで保存。今後のhelperもOS別launcherへ修正。M2はtop-level/preparation/process/cleanupの最新statusを一括更新し、過去のtasks_snapshotは時点を明記。M3は既存1139監査と同形の1171受け入れに従うWSL/PulseAudio範囲と、physical Linux/direct ALSAを主張しない条件を明記した。

source snapshotとhelper SHA、Linuxlauncher各hashはこちらで実際に再計算して照合した。追レビューが計算したという意味ではない。owned sleepのみをPID/cmdlineで確認して終了し、controller退出、Sigma/pacat残留なし。1176完了、Mac1177と親1173は未完了auto80%。現在のunit validationはWindows native実行で、LinuxCLI検証と区別した。
