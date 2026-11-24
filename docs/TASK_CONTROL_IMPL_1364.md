# タスク1364：タスク台帳とハンドル

更新日：2026-11-24。対象は1048配下の1364である。

## 変更ファイルと要点

- src/core/task_ledger.zig：ホスト専用の台帳である。ResourceTableとHandleを使用する。既定は16件、同時実行1枠である。Ledger(capacity)で台帳件数、LedgerWithConcurrency(capacity, workers)で同時実行数もコンパイル時設定できる。workers=0はコンパイルエラーである。
- src/tests/task_ledger_test.zig：台帳単体の11試験である。識別子検査、状態遷移、参照保持、所有者終了、実行枠、混在状態の上限を検査する。
- docs/TASK_CONTROL_IMPL_1364.md：本報告書である。

初回実装ではsrc/runtime_test.zigに試験importを1行追加した。辞書・UIと独立した共有runtime試験へ含めるためである。今回のレビュー修正で変更したのは上記3ファイルだけであり、既存ファイルの追加変更はない。作業開始時から存在した他タスクの変更・未追跡ファイルは保持した。

通常実行器、State、回復経路、forth.zig、既存ResourceTableは今回変更していない。通常経路の変化はなく、命令ごとの定期取消し確認も追加していない。公開Forth語、スタック効果、数値エラー値は追加・確定していない。コミット・タグ・ブランチ作成・push・tque変更、作業ツリー外の変更、速度・時間の測定は行っていない。第三者コード・ライブラリは追加していない。

## 設計上の選択と理由

根拠はTASK_CONTROL_STATE_MACHINE.mdの2〜6節、TASK_CONTROL_USAGE_CONDITIONS.mdの4節・10節の利用者決定、TASK_CONTROL_WAIT_REGISTRATION.mdの参照契約である。

- registerはcreatedの非公開予約、publishはキュー予約成立後のqueued公開を表す。台帳件数にはcreated・queued・running・RELEASE済み内部記録・未回収終端をすべて含める。
- RELEASEは外部IDを無効化し、未終端ならcancel_requestedをラッチする。内部参照や実行側参照を落とさず、終端を捏造しない。lookup/inspectは値コピーを返す。
- finishはrunningから各終端、または取消し要求済みqueuedからcancelledだけを受理する。同じ終端の再報告はfalse、矛盾する報告はConflictingTerminalである。要求後の正常帰還もsucceededにできる。
- execution_refはfinishでは落とさない。物理的な帰還・joinまたは同等の所有権引渡し確認後にexecutionStoppedで落とす。内部参照はretain/dropで管理する。collectは外部・実行側・内部参照が残る間はReferencesRemain、参照0でもqueued/runningならInvalidTransitionで拒否する。createdだけは予約のロールバックとして回収できる。実資源の後始末は呼出し側の責務である。
- endOwnerは全所有記録を対象に外部無効化と未終端の要求ラッチを行う。終端・参照は維持する。終了ownerへの新規受理停止はホストの契約であり、終了ownerの墓標は追加しない。
- ResourceTableの識別子検査→種別→所有者の順を維持する。registerはowner=0、識別子枯渇、満杯の順に拒否する。公開エラーの数値は定めない。

台帳はホストスレッド専用であり、workerへ台帳ポインタを渡さない。ロックやOSスレッド検査は追加していない。

## レビュー指摘への対応

1. 指摘どおり、従来のfinishは要求なしのqueued→cancelledを通していた。cancel_requestedがfalseならInvalidTransitionで拒否するよう修正し、試験した。待ち期限超過は次項の別APIで扱う。
2. startでexecution_refを持つ記録数を数え、設定枠数以上ならWorkerOccupiedとする。終端確定後もexecutionStoppedまでは枠を保持する。既定1枠と明示2枠を試験した。停止未確認の記録がある場合は設定枠数によらず新規実行を止める従来の保守的な扱いを維持した。
3. registerからworker占有検査を除き、停止未確認中でも投入を受け付ける。実行開始だけを拒否し、待ち期限超過で終端にできることを試験した。
4. tableをtable_for_testingへ改名し、直接操作が試験専用であることをコメントでも示した。Zigのフィールドアクセスを隠蔽するものではない。直接操作は最大serial、別種注入、参照0のrunningという通常APIでは作れない異常状態の回収拒否検査に使用する。
5. endOwner後のregisterはホスト契約であり、変更していない。
6. createdへのfinish、queued→succeeded/failed、queued以外へのstart、publish二重呼出し、RELEASE済みで参照0のqueued/runningのcollect、execution_refなしのmarkStopUnconfirmedの拒否を試験した。16件構成でcreated・queued・running・RELEASE済みrunning・未回収終端を混ぜ、すべて上限へ数えられることも試験した。2件のrunningを同時に含む混在試験には明示2枠を使い、既定1枠の契約と区別した。

指摘を誤りと判断して退けた項目はない。

## 1366の期限切れとの接続

D:/tmp/forthz-1366/src/core/task_queue.zigを読み取り確認した。Queue.expireは待ち項目を排他的に除去し、Result.kind=failed、reason=queue_expiredとして封印する。時計取得失敗時のfailWaitingはfailed / clock_failedを使う。

この2種類を受ける専用内部API failQueued(id, owner, reason)を追加した。ホストが排他的除去と失敗封印を確認した後、queued→failedを行う。通常finishからqueued→failedは許可しない。同じfailedの再報告はfalse、異なる終端との競合はConflictingTerminalである。理由enumは入口の区別に使用し、台帳に保存しない。診断の保持・公開は結果管理層の責務である。排他的除去の証明自体を台帳が検査するものではない。両理由、重複・競合、不正な元状態を試験した。

1366のQueue.submit自身はunresponsive時にWorkerUnresponsiveを返す。台帳側は投入を受け付けるが、結合時にはキュー側との契約整合が必要である。本作業では1366を変更していない。

## 試験と実行結果

Windows PowerShellから、ZIG_GLOBAL_CACHE_DIRをworktree内の.zig-global-cacheに設定して実行した。作業ツリー外の設定は変更していない。

- zig build test：成功、終了コード0。
- zig build runtime-test：成功、終了コード0。台帳11試験を含む。
- zig build test -Ddebug=false：成功、終了コード0。
- zig fmt --check src/core/task_ledger.zig src/tests/task_ledger_test.zig：成功、終了コード0。
- git diff --check：成功、終了コード0。既存src/runtime_test.zigの改行変換予告は出た。

台帳は辞書・build_options・語群に依存しない共有runtime試験から検査するため、追加の語群除外構成は実行していない。

## 未確認事項と利用者の判断が必要な事項

worker・キュー・結果所有・実VM・Snapshot・待機登録との結合は未確認である。キュー取得の排他性、結果・診断の封印と公開、取消しトークンへの転送・起床、所有者の新規受理停止、実資源解放は後続管理層で結合検証する必要がある。今回の全体試験成功を、それらの結合完了の証拠とはしない。

速度・時間条件、実利用の応答、追加128 MiB予算は測定しておらず、達成を主張しない。方式の確定・公開、公開語・公開エラー値、VM再利用は引き続き保留である。本修正だけを理由とする新たな利用者判断事項はない。
