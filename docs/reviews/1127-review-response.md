# 1127 音声ホスト寿命：レビュー評価と判断

2026-11-20、基点416caf9。Claude CodeへRead/Glob/Grepのみで依頼した。[初回](1127-claude-review.md)、[再レビュー](1127-followup-claude-review.md)、[最終指摘](1127-final-claude-review.md)、[close再試行の確認](1127-close-retry-claude-review.md)。実行検証は[実装記録](../PCM_HOST_LIFETIME_IMPLEMENTATION.md)に分ける。

## 初回の指摘

- M1採用：shutdownのstop要求直後にfailedへ移し、時計の取得・期限計算・join失敗でrunningへ戻さない。遅れた終了の後に明示shutdownが成功したときだけidleへ戻す。時計故障試験を追加。
- M2は保守的な寿命管理として採用：deviceを所有threadで解放し、動的libraryは成功join後にVM threadでunload。thread作成前のrollbackはVM threadで両方を解放する。TLS内部の実害を確認した指摘ではなく、レビューも仮説として記載したもの。
- M3採用：音声workerが残る失敗時は、通常deferとflush後にPOSIXの_exit/Windowsの自プロセスTerminateProcessでstatus1へ進み、libc/DLL終了処理へ残ったworkerを渡さない。別ビルドの阻害consumerプロセスで検証する。任意driverの全障害に対する停止時間保証とはしない。
- M4採用：waveOutOpen、AudioQueueNewOutput、ALSA openはlocal出力先で受け、成功後にglobalへ移す。
- L1採用：診断をaudio shutdown incompleteとし、実際には解放済みのstartup rollbackにもshared storage retainedと表示しない。
- L2採用：pipe2(O_CLOEXEC)を使い、0..2へ割り当たったfdをF_DUPFD_CLOEXECで3以上へ移す。writerだけをnonblockingにし、child stdinの読み方は変えない。
- L3採用：POSIXの専用音声workerは同期fault以外のsignalをblockする。親のsignal maskを変更しない。Mac AudioQueueのframework内部threadまでこの操作で管理したとは扱わない。

## 再レビューの指摘

- N1採用：runtime deinit/signal復旧に失敗したfatal deferにもaudio失敗時のhard exitを入れ、通常libc.exitへ落ちる経路を塞ぐ。
- N2採用：thread作成前のrollbackが再試行で本当に完了した場合はcleanup_okを戻す。ただしstateはfailedで保持し、shutdown成功まで再startしない。ALSA closeがerrorを返してhandleを消費した場合はterminal failureとして残し、nullになったhandleを成功と取り違えない。
- N3：型の異なるextern宣言によるcompile問題はWindows/Linux/Mac cross compileで観測しなかった。重複を減らす提案は採用し、worker entryのstd.cによるmask操作へ統一した。
- N4：末尾の明示importと実行ログの試験名が既に存在したため、試験が未実行という指摘は該当しない。見通しのため既存のmain test blockへimportを統合した。
- 終了済みworkerをstartとaudio waitで検出し、消費側がいないEngineを返したり、空き待ちを続けたりしないよう補完した。

## 最終の指摘

workerの最初のcloseが失敗しdeferの再試行で回収できた場合も、cleanup_okが失敗のまま残る点を修正した。成功した再試行かつterminal failureなしのときだけ戻す。初回レビューの保守的な「失敗を保持」から、回収完了を確認できた一時的失敗だけを成功へ戻す判断へ整理した。永続的失敗と同期signal mask設定の失敗は成功扱いにしない。

1回だけのclose故障を差し替え、ALSA fixtureがcloseされpoolが空になりshutdown成功することを照合した。限定再レビューは対象に高・中の指摘なし。静的レビューと実行結果を混同しない。
