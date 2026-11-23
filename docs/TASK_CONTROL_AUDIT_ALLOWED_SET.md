# タスク制御01-B3：初期許可集合とOpの監査案

作成日：2026-11-23。対象：1048配下1351。状態：ソース静的監査と提案である。方式採用・実装・実機検証の完了を示すものではない。

## 1. 根拠と範囲

根拠は `docs/TASK_CONTROL_DETAILED_PLAN.md`（特に2・5〜13節）、`docs/TASK_CONTROL_PLAN.md`、`docs/CORE_EXTENSION_DETAILED_DESIGN.md` 11節、`docs/CORE_EXTENSION_WORKER_STATE_AUDIT.md`、`docs/CORE_EXTENSION_REVIEW_RESPONSE.md`、`docs/CORE_EXTENSION_DESIGN_DECISIONS.md` である。詳細計画5節の計算用途、7.2節の最適化後検査、12.2節の到達先監査、レビュー再確認F01を具体化する。

許可判定は提案である。新規StorageとState.init、専有State、専用Writer、不変辞書、入力と結果のコピー、worker専用取消し経路が成立することを前提とする。現行VMがこの制限を強制しているという意味ではない。builtinは `defs.Builtin` 識別子を正とし、Forth名は登録表から併記する。別名は最終実装へ解決して検査する。

本作業の書込み対象は本書のみである。src・tque・gitを変更せず、ビルド・試験・速度や時間の測定を行っていない。行番号は作成時点のものであり、更新時は再照合する。

## 2. 到達先と共通条件

State欄は語本体と確認した補助経路のフィールド集合であり、配列内部を含める。拒否対象の未追跡箇所は未追跡と明記する。Writer・モジュール変数の「到達しない」は語本体と以下の補助経路に限る。実行ループのcounted経路を含む無条件の非到達を意味しない。モジュールのconst、関数内のvarは共有可変変数と区別する。

| 記号 | 到達先の根拠と条件 |
|---|---|
| A | `words_arithmetic.execute`（`src/core/words_arithmetic.zig:33`）と `integer_math.binary`（`src/core/integer_math.zig:18`）は整数・倍長演算を行う。`popDouble/pushDouble`（`src/forth.zig:2437`, `src/forth.zig:2444`）もdata_stack/data_depthへ還元され、Writerやモジュール可変変数は使わない。 |
| S | `words_stack.execute`（`src/core/words_stack.zig:19`）、`peek/pop/push`（`src/forth.zig:2467`, `src/forth.zig:2472`, `src/forth.zig:2478`）はスタックと深さだけを使う。戻りデータスタックとVMの呼出しフレームは別である。 |
| M | `memoryAddress`（`src/forth.zig:2511`）はmemory.len内かだけを検査する。権限領域の検査ではない。読取り・書込み領域、上限、負の長さをworker側で追加検査する条件である。`memoryRange`（`src/forth.zig:2520`）は負の長さを0としており、ABIの負長拒否とは別契約である。 |
| W | セル書込みは `writeCell`（`src/forth.zig:2546`）から `address_registry.written`（`src/core/address_registry.zig:109`）へ、MOVE類は `address_registry.copy`（`src/core/address_registry.zig:178`）へ進む。addressesのrecords/count/memory_order/memory_count/index_dirty/stable_writesを専有する必要がある。再分類の `classify/storageValid`（`src/core/address_registry.zig:43`, `src/core/address_registry.zig:70`）からdata_here/sizes/memoryと `heapTop/blockSize/blockUsed`（`src/core/heap_memory.zig:15`, `src/core/heap_memory.zig:20`, `src/core/heap_memory.zig:26`）へ到達する。この経路にWriter・モジュール可変変数の参照はない。 |
| L | `loopFrame`（`src/forth.zig:2505`）はloop_stack/loop_depthを読む。拡張ループ `enter/finish`（`src/core/words_loops.zig:84`, `src/core/words_loops.zig:138`）もdata/loopスタックで完結する。memory_up/downループ自体はメモリを読み書きせず数値アドレスを進める。 |
| F | 本案はprimitiveにある基本8語だけを追加候補とする。`words_float.execute`（`src/core/words_float.zig:67`）、`fpeek/fpop/fpush`（`src/forth.zig:2488`, `src/forth.zig:2493`, `src/forth.zig:2499`）のfloat_stack/float_depthに限る。その他の数学関数や表示は追加監査前に許可しない。 |
| C | コンパイル時の構文builtinをworker実行時に許すことと、事前に生成された分岐・ループOpを許すことは別である。`words_compiling.execute`（`src/core/words_compiling.zig:62`）、`words_loops.execute`（`src/core/words_loops.zig:33`）の構文は初期ランタイム集合から外す。拒否語の全State・Writer到達先を本書では再帰監査していない。 |
| H | 予約・ヒープAPIは初期案から除外する。`reserveData`（`src/forth.zig:2560`）、`heapAllocate`（`src/core/heap_memory.zig:50`）等の管理状態、破損ヘッダ、走査中の取消しを別途確認する必要がある。論理ヒープをOSのALLOCATEと断定しない。 |
| O | 出力語は除外する。`State.write`（`src/forth.zig:525`）以降の全callbackとfallbackの監査は別成果物と結合する。callbackのnullを許可検査の代用にしない。State.writeはcapture_sink、capture_target、output_fileへの分岐を先に選び、通常経路だけがwriter.writeへ進む（`src/forth.zig:525`）。 |
| X | 動的実行・例外は初期試作で拒否する。4・5節の迂回経路も同時に拒否する。 |

共通ラッパーを別記する。`State.executeBuiltin`（`src/forth.zig:2299`）は所有モジュールへdispatchした後、`checkOutputError`（`src/forth.zig:2292`）を呼ぶ。output_errorを読み消去しthrowCodeへ進み得る。debugのコンパイル時coverageも条件付きで動く（`src/forth.zig:2316`）。以下の表はこの共通部分を重複記載しない。workerを非コンパイル状態、step_limit=0、追跡・profile・watch・stepper・keep_counting無効、execution_control.active=false、出力エラー状態初期化済みとする案である。primitive直接実行はこのラッパーを通らない（`src/forth.zig:2117`）。実行ループの全debug状態・共通エラー記録まで含むState再帰監査の完了ではない。

counted経路は`defs.debug_enabled`かつstep_limit、tracing、profile、keep_counting、execution_control.activeのいずれかが有効な場合に選ばれる（`src/forth.zig:1877`）。watch単独は選択条件ではない。activeはexecution.depthを検査する（`src/core/execution_control.zig:19`）。countedでは各Opでchargeを呼び（`src/forth.zig:1974`）、予算切れのStepLimitと、execution.depthが非0の場合のwriter.execution_ops.pollへの到達・操作表欠如時のHostUnavailableがあり得る（`src/core/execution_control.zig:26`, `src/core/execution_control.zig:51`）。profile更新と条件付きwords_debug.stepも各Opで動く（`src/forth.zig:1975`, `src/forth.zig:1976`）。従って許可語も共通経路からWriterへ到達し得る。

詳細計画9.1の手順5（`docs/TASK_CONTROL_DETAILED_PLAN.md:267`）に従い、workerでcountedを選ばない規則とするか、debug機能および専用execution_opsとそのcontextを監査して許すかを決める必要がある。前記の無効化は初期案の前提であり、worker専用取消し経路をdebug予算へ代用するものではない。

## 3. builtin別の提案

「許可」にも2節の専有・取消し等の共通条件が付く。「条件付許可」はM/Wの追加領域検査を必須とする。**表にないbuiltinはすべて不許可**である。I/O・UI・音・SYSTEM・同期待機・辞書変更・タスク投入等を未監査のまま許可しない。各行の実装欄はexecute関数定義と分岐のfile:lineである。

表は312行でありBuiltin総数ではない。`defs.Builtin`（`src/core/defs.zig:82`）の総数は1112である。許可172件と条件付許可30件の計202件を候補集合とした補集合は910件（1112−202）であり、表内の不許可110件と未掲載800件を含む。条件未成立の30件も拒否する場合は940件（1112−172）となる。集計コマンドは付録Aに示す。

### words_arithmetic

| builtin / Forth名 | 実装関数 / 分岐 | 到達State | Writer callback | モジュール変数 | 判定・根拠 |
|---|---|---|---|---|---|
| `add` / + | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `sub` / - | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `mul` / * | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `div` / / | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `mod` / MOD | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `max` / MAX | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `min` / MIN | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `equal` / = | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `not_equal` / <> | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `less` / < | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `greater` / > | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `less_equal` / <= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `greater_equal` / >= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `bit_and` / AND | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `bit_or` / OR | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `bit_xor` / XOR | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `bit_nand` / NAND | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `bit_nor` / NOR | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `lshift` / LSHIFT | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `rshift` / RSHIFT | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `div_mod` / /MOD | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:152` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `swap_bytes` / SWAB | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:225` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `negate` / MINUS | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:226` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `abs` / ABS | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:227` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `one_plus` / 1+ | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:231` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `one_minus` / 1- | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:232` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `two_star` / 2* | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:233` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `two_slash` / 2/ | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:234` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `logical_not` / NOT | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:235` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `zero_equal` / 0= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:235` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `zero_less` / 0< | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:236` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `zero_greater` / 0> | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:237` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `zero_greater_equal` / 0>= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:239` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `under_plus` / UNDER+ | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:241` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `zero_not_equal` / 0<> | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:247` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `bit_complement` / COM | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:248` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `true_value` / TRUE | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:249` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `false_value` / FALSE | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:250` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `s_to_d` / S>D | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:251` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_to_s` / D>S | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:252` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_add` / D+ | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:255` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_sub` / D- | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:255` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_negate` / DNEGATE | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:260` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_abs` / DABS | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:261` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_zero_equal` / D0= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:265` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_zero_less` / D0< | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:266` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_equal` / D= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:271` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_less` / D< | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:271` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `within` / WITHIN | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:284` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `u_less` / U< | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `u_greater` / U> | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `star_slash` / */ | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:160` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `star_slash_mod` / */MOD | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:160` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `m_star` / M* | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:168` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `um_star` / UM* | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:173` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `um_slash_mod` / UM/MOD | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:178` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `fm_slash_mod` / FM/MOD | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:219` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `sm_slash_rem` / SM/REM | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:219` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_two_star` / D2* | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:187` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_two_slash` / D2/ | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:188` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_max` / DMAX | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:189` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_min` / DMIN | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:189` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `m_plus` / M+ | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:194` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `du_less` / DU< | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:208` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `m_star_slash` / M*/ | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:200` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `rol` / ROL | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `ror` / ROR | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `arshift` / ARSHIFT | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:35` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `darshift` / DARSHIFT | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:40` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `dlshift` / DLSHIFT | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:40` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `drshift` / DRSHIFT | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:40` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `star_slash_f` / */F | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:54` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `star_slash_mod_f` / */MODF | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:54` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `star_slash_mod_s` / */MODS | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:54` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `star_slash_s` / */S | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:54` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `slash_f` / /F | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:54` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `slash_mod_f` / /MODF | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:54` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `slash_mod_s` / /MODS | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:54` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `slash_s` / /S | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:54` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `to_pow2` / >POW2 | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:118` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `ctz` / CTZ | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:118` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `drol` / DROL | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:141` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `dror` / DROR | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:141` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `du_slash_mod` / DU/MOD | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:103` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `log2` / LOG2 | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:118` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `lrol` / LROL | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:129` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `lror` / LROR | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:129` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `mod_f` / MODF | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:54` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `mod_s` / MODS | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:54` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `mux` / MUX | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:112` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `pow2_query` / POW2? | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:118` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `u_star_slash` / U*/ | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:75` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `u_star_slash_mod` / U*/MOD | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:75` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `u_slash` / U/ | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:75` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `u_slash_mod` / U/MOD | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:75` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `ud_slash_mod` / UD/MOD | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:75` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `u_mod` / UMOD | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:75` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `wrol` / WROL | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:129` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `wror` / WROR | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:129` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `zero_less_equal` / 0<= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:238` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_zero_less_equal` / D0<= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:267` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_zero_not_equal` / D0<> | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:268` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_zero_greater` / D0> | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:269` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_zero_greater_equal` / D0>= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:270` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_less_equal` / D<= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:271` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_not_equal` / D<> | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:271` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_greater` / D> | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:271` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `d_greater_equal` / D>= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:271` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `du_less_equal` / DU<= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:208` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `du_greater` / DU> | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:208` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `du_greater_equal` / DU>= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:208` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `u_less_equal` / U<= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `u_greater_equal` / U>= | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `u_max` / UMAX | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |
| `u_min` / UMIN | `execute` (`src/core/words_arithmetic.zig:33`), `src/core/words_arithmetic.zig:151` | data_stack, data_depth | 到達しない | 到達しない | 許可：整数・倍長演算のみ（A） |

### words_stack

| builtin / Forth名 | 実装関数 / 分岐 | 到達State | Writer callback | モジュール変数 | 判定・根拠 |
|---|---|---|---|---|---|
| `drop` / DROP | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:21` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `dup` / DUP | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:22` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `swap` / SWAP | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:23` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `over` / OVER | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:27` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `rot` / ROT | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:28` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `minus_rot` / -ROT | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:28` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `nip` / NIP | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:33` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `tuck` / TUCK | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:38` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `pick` / PICK | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:44` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `roll` / ROLL | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:49` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `two_dup` / 2DUP | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:56` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `two_drop` / 2DROP | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:62` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `two_swap` / 2SWAP | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:66` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `two_over` / 2OVER | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:70` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `depth` / DEPTH | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:101` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `to_r` / >R | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:102` | data_stack, data_depth, return_stack, return_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `from_r` / R> | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:108` | data_stack, data_depth, return_stack, return_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `r_fetch` / R@ | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:113` | data_stack, data_depth, return_stack, return_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `two_to_r` / 2>R | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:160` | data_stack, data_depth, return_stack, return_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `two_r_from` / 2R> | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:169` | data_stack, data_depth, return_stack, return_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `two_r_fetch` / 2R@ | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:118` | data_stack, data_depth, return_stack, return_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `question_dup` / ?DUP | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:156` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `two_rot` / 2ROT | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:125` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `n_to_r` / N>R | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:135` | data_stack, data_depth, return_stack, return_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `n_r_from` / NR> | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:145` | data_stack, data_depth, return_stack, return_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `two_nip` / 2NIP | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:76` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `two_r_drop` / 2RDROP | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:96` | data_stack, data_depth, return_stack, return_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `two_tuck` / 2TUCK | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:83` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `fourth` / FOURTH | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:95` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `r_drop` / RDROP | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:96` | data_stack, data_depth, return_stack, return_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |
| `third` / THIRD | `execute` (`src/core/words_stack.zig:19`), `src/core/words_stack.zig:94` | data_stack, data_depth | 到達しない | 到達しない | 許可：専有スタックのみ（S） |

### words_memory

| builtin / Forth名 | 実装関数 / 分岐 | 到達State | Writer callback | モジュール変数 | 判定・根拠 |
|---|---|---|---|---|---|
| `blank` / BL | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:30` | data_stack, data_depth | 到達しない | 到達しない | 許可：定数または数値アドレス演算のみ（A） |
| `cell` / CELL | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:31` | data_stack, data_depth | 到達しない | 到達しない | 許可：定数または数値アドレス演算のみ（A） |
| `cells` / CELLS | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:32` | data_stack, data_depth | 到達しない | 到達しない | 許可：定数または数値アドレス演算のみ（A） |
| `cell_plus` / CELL+ | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:33` | data_stack, data_depth | 到達しない | 到達しない | 許可：定数または数値アドレス演算のみ（A） |
| `cell_minus` / CELL- | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:34` | data_stack, data_depth | 到達しない | 到達しない | 許可：定数または数値アドレス演算のみ（A） |
| `aligned` / ALIGNED | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:35` | data_stack, data_depth | 到達しない | 到達しない | 許可：定数または数値アドレス演算のみ（A） |
| `fetch` / @ | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:39` | data_stack, data_depth, memory | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `store` / ! | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:43` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `cfetch` / C@ | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:48` | data_stack, data_depth, memory | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `cstore` / C! | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:52` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `add_store` / +! | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:58` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `inc_store` / 1+! | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:63` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `dec_store` / 1-! | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:63` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `zero_store` / OSET | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:68` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `off` / OFF | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:68` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `on` / ON | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:69` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `question` / ? | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:70` | data_stack, data_depth, memory, writer, output_error, output_count, capture_sink, capture_target, capture_failed, output_file, report_capturing, report_text, report_len等 | State.write経由（O） | 出力callback依存・未追跡 | 不許可：出力を含む（O） |
| `array_fetch` / A@ | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:75` | data_stack, data_depth, memory | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `array_store` / A! | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:79` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `erase` / ERASE | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:84` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `fill` / FILL | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:84` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `move` / MOVE | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:94` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `cmove` / CMOVE | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:94` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `here` / HERE | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:118` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 不許可：予約・ヒープ・データ空間管理は初期集合から除外（H） |
| `allot` / ALLOT | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:158` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 不許可：予約・ヒープ・データ空間管理は初期集合から除外（H） |
| `comma` / , | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:159` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 不許可：予約・ヒープ・データ空間管理は初期集合から除外（H） |
| `c_comma` / C, | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:172` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 不許可：予約・ヒープ・データ空間管理は初期集合から除外（H） |
| `two_fetch` / 2@ | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:179` | data_stack, data_depth, memory | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `two_store` / 2! | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:180` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `count` / COUNT | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:184` | data_stack, data_depth, memory | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `pad` / PAD | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:190` | data_stack, data_depth | 到達しない | 到達しない | 許可：定数返却のみ。system内のためPADへの書込みは現案では失敗する（5節末） |
| `place` / PLACE | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:191` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `compare` / COMPARE | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:207` | data_stack, data_depth, memory | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `search` / SEARCH | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:216` | data_stack, data_depth, memory | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `slash_string` / /STRING | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:233` | data_stack, data_depth | 到達しない | 到達しない | 許可：定数または数値アドレス演算のみ（A） |
| `minus_trailing` / -TRAILING | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:241` | data_stack, data_depth, memory | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `char_plus` / CHAR+ | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:250` | data_stack, data_depth | 到達しない | 到達しない | 許可：定数または数値アドレス演算のみ（A） |
| `chars` / CHARS | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:251` | data_stack, data_depth | 到達しない | 到達しない | 許可：定数または数値アドレス演算のみ（A） |
| `bounds` / BOUNDS | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:252` | data_stack, data_depth | 到達しない | 到達しない | 許可：定数または数値アドレス演算のみ（A） |
| `blank_fill` / BLANK | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:84` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `cmove_up` / CMOVE> | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:106` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `scan` / SCAN | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:260` | data_stack, data_depth, memory | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `skip` / SKIP | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:260` | data_stack, data_depth, memory | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `str_equal` / STR= | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:270` | data_stack, data_depth, memory | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `string_prefix_query` / STRING-PREFIX? | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:270` | data_stack, data_depth, memory | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `plus_place` / +PLACE | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:276` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 条件付許可：領域検査を追加する条件（M/W） |
| `align_here` / ALIGN | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:119` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 不許可：予約・ヒープ・データ空間管理は初期集合から除外（H） |
| `unused` / UNUSED | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:157` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 不許可：予約・ヒープ・データ空間管理は初期集合から除外（H） |
| `dump` / DUMP | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:125` | data_stack, data_depth, memory, writer, output_error, output_count, capture_sink, capture_target, capture_failed, output_file, report_capturing, report_text, report_len等 | State.write経由（O） | 出力callback依存・未追跡 | 不許可：出力を含む（O） |
| `time_and_date` / TIME&DATE | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:150` | data_stack, data_depth, writer | local_time_fn, context | ホストcallback依存・未追跡 | 不許可：ホスト時計を使う |
| `allocate` / ALLOCATE | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:290` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 不許可：予約・ヒープ・データ空間管理は初期集合から除外（H） |
| `free` / FREE | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:296` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 不許可：予約・ヒープ・データ空間管理は初期集合から除外（H） |
| `resize` / RESIZE | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:300` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 不許可：予約・ヒープ・データ空間管理は初期集合から除外（H） |
| `two_comma` / 2, | `execute` (`src/core/words_memory.zig:28`), `src/core/words_memory.zig:165` | data_stack, data_depth, memory, addresses内部全体, data_here, sizes | 到達しない | 到達しない | 不許可：予約・ヒープ・データ空間管理は初期集合から除外（H） |

### words_compiling

| builtin / Forth名 | 実装関数 / 分岐 | 到達State | Writer callback | モジュール変数 | 判定・根拠 |
|---|---|---|---|---|---|
| `define_aconstant` / ACONSTANT | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_avariable` / AVARIABLE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `builds` / <BUILDS | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:64` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `immediate` / IMMEDIATE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:71` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `execute` / EXECUTE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:75` | 実行先依存 | 実行先依存 | 実行先依存 | 不許可：任意xtへの再入（X） |
| `index` / I | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:76` | data_stack, data_depth, loop_stack, loop_depth | 到達しない | 到達しない | 許可：既存ループの参照・終了（L） |
| `index_2` / J | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:77` | data_stack, data_depth, loop_stack, loop_depth | 到達しない | 到達しない | 許可：既存ループの参照・終了（L） |
| `index_3` / K | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:78` | data_stack, data_depth, loop_stack, loop_depth | 到達しない | 到達しない | 許可：既存ループの参照・終了（L） |
| `leave` / LEAVE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:79` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `unloop` / UNLOOP | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:80` | data_stack, data_depth, loop_stack, loop_depth | 到達しない | 到達しない | 許可：呼出し単位のループ深さ境界を必須とする終了操作（L、4節） |
| `compile_if` / IF | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:84` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_else` / ELSE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:85` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_ahead` / AHEAD | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:86` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_then` / THEN | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:87` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_begin` / BEGIN | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:88` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_end` / END | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:89` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_again` / AGAIN | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:90` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_while` / WHILE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:91` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_repeat` / REPEAT | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:92` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_do` / DO | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:93` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_q_do` / ?DO | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:94` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_loop` / LOOP | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:95` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_plus_loop` / +LOOP | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:96` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_does` / DOES> | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:97` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_case` / CASE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:98` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_of` / OF | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:99` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_endof` / ENDOF | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:100` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_endcase` / ENDCASE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:101` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_exit` / EXIT | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:102` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_recurse` / RECURSE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:118` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `question_exit` / ?EXIT | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:107` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `question_leave` / ?LEAVE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:107` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_question_of` / ?OF | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:115` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_contof` / CONTOF | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:116` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `compile_next_case` / NEXT-CASE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:117` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_colon` / : | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_variable` / VARIABLE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_fvariable` / FVARIABLE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_constant` / CONSTANT | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_value` / VALUE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_two_variable` / 2VARIABLE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_two_constant` / 2CONSTANT | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_fconstant` / FCONSTANT | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_fvalue` / FVALUE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_two_value` / 2VALUE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_buffer` / BUFFER: | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `define_array` / ARRAY | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:122` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `end_definition` / ; | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:123` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `tick` / ' | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:124` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `to_body` / >BODY | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:128` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `literal` / LITERAL | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:130` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `fliteral` / FLITERAL | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:134` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `sliteral` / SLITERAL | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:220` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `two_literal` / 2LITERAL | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:213` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `state` / STATE | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:230` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_if` / [IF] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:231` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_else` / [ELSE] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:234` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_then` / [THEN] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:235` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_defined` / [DEFINED] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:236` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_undefined` / [UNDEFINED] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:236` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `cs_pick` / CS-PICK | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:197` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `cs_roll` / CS-ROLL | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:197` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_ifdef` / [IFDEF] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:139` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_ifundef` / [IFUNDEF] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:139` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_do` / [DO] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:146` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_q_do` / [?DO] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:146` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_loop` / [LOOP] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:154` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_plus_loop` / [+LOOP] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:154` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_i` / [I] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:162` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_begin` / [BEGIN] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:178` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_until` / [UNTIL] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:179` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_again` / [AGAIN] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:184` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_while` / [WHILE] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:188` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_repeat` / [REPEAT] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:184` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_for` / [FOR] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:171` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |
| `bracket_next` / [NEXT] | `execute` (`src/core/words_compiling.zig:62`), `src/core/words_compiling.zig:172` | 未追跡（拒否対象） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：コンパイル・定義・入力解釈等は初期集合外（C） |

### words_loops

| builtin / Forth名 | 実装関数 / 分岐 | 到達State | Writer callback | モジュール変数 | 判定・根拠 |
|---|---|---|---|---|---|
| `positive_do` / +DO | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:35` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `unsigned_positive_do` / U+DO | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:35` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `negative_do` / -DO | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:35` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `unsigned_negative_do` / U-DO | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:35` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `inclusive_negative_do` / -[DO | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:35` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `unsigned_inclusive_negative_do` / U-[DO | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:35` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `negative_loop` / -LOOP | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:40` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `for_word` / FOR | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:35` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `next_word` / NEXT | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:40` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `memory_up_do` / MEM+DO | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:35` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `memory_down_do` / MEM-DO | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:35` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `array_to_mem` / ARRAY>MEM | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:56` | data_stack, data_depth | 到達しない | 到達しない | 許可：2セルの積を下側セルへ格納する数値計算。loopFrame参照なし（`src/core/words_loops.zig:56`） |
| `index_limit` / I' | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:62` | data_stack, data_depth, loop_stack, loop_depth | 到達しない | 到達しない | 許可：数値計算・既存ループ参照（L） |
| `delta_index` / DELTA-I | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:63` | data_stack, data_depth, loop_stack, loop_depth | 到達しない | 到達しない | 許可：数値計算・既存ループ参照（L） |
| `cs_drop` / CS-DROP | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:67` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `done` / DONE | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:51` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `question_dup_if` / ?DUP-IF | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:73` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |
| `question_dup_zero_if` / ?DUP-0=-IF | `execute` (`src/core/words_loops.zig:33`), `src/core/words_loops.zig:73` | compiling, defining, code, code_count, control_stack, control_depth, local_count（保守的上界） | 到達しない | 到達しない | 不許可：コンパイル時構文。生成後Opは別途判定（C） |

### words_float

| builtin / Forth名 | 実装関数 / 分岐 | 到達State | Writer callback | モジュール変数 | 判定・根拠 |
|---|---|---|---|---|---|
| `f_add` / F+ | `execute` (`src/core/words_float.zig:67`), `src/core/words_float.zig:203` | float_stack, float_depth | 到達しない | 到達しない | 許可：基本浮動小数演算とスタックのみ（F） |
| `f_sub` / F- | `execute` (`src/core/words_float.zig:67`), `src/core/words_float.zig:203` | float_stack, float_depth | 到達しない | 到達しない | 許可：基本浮動小数演算とスタックのみ（F） |
| `f_mul` / F* | `execute` (`src/core/words_float.zig:67`), `src/core/words_float.zig:203` | float_stack, float_depth | 到達しない | 到達しない | 許可：基本浮動小数演算とスタックのみ（F） |
| `f_div` / F/ | `execute` (`src/core/words_float.zig:67`), `src/core/words_float.zig:203` | float_stack, float_depth | 到達しない | 到達しない | 許可：基本浮動小数演算とスタックのみ（F） |
| `f_dup` / FDUP | `execute` (`src/core/words_float.zig:67`), `src/core/words_float.zig:162` | float_stack, float_depth | 到達しない | 到達しない | 許可：基本浮動小数演算とスタックのみ（F） |
| `f_drop` / FDROP | `execute` (`src/core/words_float.zig:67`), `src/core/words_float.zig:161` | float_stack, float_depth | 到達しない | 到達しない | 許可：基本浮動小数演算とスタックのみ（F） |
| `f_swap` / FSWAP | `execute` (`src/core/words_float.zig:67`), `src/core/words_float.zig:163` | float_stack, float_depth | 到達しない | 到達しない | 許可：基本浮動小数演算とスタックのみ（F） |
| `f_over` / FOVER | `execute` (`src/core/words_float.zig:67`), `src/core/words_float.zig:167` | float_stack, float_depth | 到達しない | 到達しない | 許可：基本浮動小数演算とスタックのみ（F） |

### words_system

| builtin / Forth名 | 実装関数 / 分岐 | 到達State | Writer callback | モジュール変数 | 判定・根拠 |
|---|---|---|---|---|---|
| `catch_word` / CATCH | `execute` (`src/core/words_system.zig:141`), `src/core/words_system.zig:287` | catches, catch_depth, throw_code等／実行先依存 | 実行先依存（THROW本体はなし） | 実行先依存（THROW本体はなし） | 不許可：例外・間接実行（X） |

| `throw` / THROW | `execute` (`src/core/words_system.zig:141`), `src/core/words_system.zig:275` | catches, catch_depth, throw_code等／実行先依存 | 実行先依存（THROW本体はなし） | 実行先依存（THROW本体はなし） | 不許可：例外・間接実行（X） |
| `perform` / PERFORM | `execute` (`src/core/words_system.zig:141`), `src/core/words_system.zig:268` | catches, catch_depth, throw_code等／実行先依存 | 実行先依存（THROW本体はなし） | 実行先依存（THROW本体はなし） | 不許可：例外・間接実行（X） |

### words_diagnostics

CATCH-NOBTの所属は`words_diagnostics.words`である（`src/core/words_diagnostics.zig:6`）。

| builtin / Forth名 | 実装関数 / 分岐 | 到達State | Writer callback | モジュール変数 | 判定・根拠 |
|---|---|---|---|---|---|
| `catch_nobt` / CATCH-NOBT | `execute` (`src/core/words_diagnostics.zig:7`), `src/core/words_diagnostics.zig:22` | catches, catch_depth, throw_code等／実行先依存 | 実行先依存（THROW本体はなし） | 実行先依存（THROW本体はなし） | 不許可：例外・間接実行（X） |

### words_defining

内部builtin compile_assign_isの表示名はdecompilerでPOSTPONE ISであり、通常登録された独立語名とは区別する（`src/core/decompiler.zig:234`, `src/core/word_semantics.zig:27`）。

| builtin / Forth名 | 実装関数 / 分岐 | 到達State | Writer callback | モジュール変数 | 判定・根拠 |
|---|---|---|---|---|---|
| `define_defer` / DEFER | `execute` (`src/core/words_defining.zig:29`), `src/core/words_defining.zig:45` | words, memory等（詳細未追跡） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：遅延実行先の生成・参照・変更（X） |
| `defer_store` / DEFER! | `execute` (`src/core/words_defining.zig:29`), `src/core/words_defining.zig:51` | words, memory等（詳細未追跡） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：遅延実行先の生成・参照・変更（X） |
| `defer_fetch` / DEFER@ | `execute` (`src/core/words_defining.zig:29`), `src/core/words_defining.zig:55` | words, memory等（詳細未追跡） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：遅延実行先の生成・参照・変更（X） |
| `defers` / DEFERS | `execute` (`src/core/words_defining.zig:29`), `src/core/words_defining.zig:57` | words, memory等（詳細未追跡） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：遅延実行先の生成・参照・変更（X） |
| `assign_is` / IS | `execute` (`src/core/words_defining.zig:29`), `src/core/words_defining.zig:31` | words, memory等（詳細未追跡） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：遅延実行先の生成・参照・変更（X） |
| `compile_assign_is` / POSTPONE IS（内部builtin） | `execute` (`src/core/words_defining.zig:29`), `src/core/words_defining.zig:31` | words, memory等（詳細未追跡） | 未追跡（実行前拒否） | 未追跡（実行前拒否） | 不許可：遅延実行先の生成・参照・変更（X） |

## 4. specialize・primitive・inline後のOp全種

`specializeCall`（`src/forth.zig:1453`）はcall/call_builtinを受け、builtinなら `builtinOpKind`（`src/core/defs.zig:1425`）により50種のprimitiveまたはcall_builtinへ変換する。callのcolon先はcall_colonになる。他のOpと不正operandはそのまま返すので、この関数自体は妥当性検査ではない。

`primitiveBuiltin`（`src/core/defs.zig:1420`）はOpを生成せず、primitiveタグと同名のBuiltinを返す。executeも含み、primitiveであることは許可を意味しない。実行ループではexecuteを専用分岐で扱い（`src/forth.zig:2075`）、他のprimitiveは所有モジュールへ直接渡す（`src/forth.zig:2117`）。

`inline_calls.body`（`src/core/inline_calls.zig:26`）は末尾exitを除いた本文を選び、executeを拒否する。他のprimitiveとliteral/float_literal/execution_token、既にinlineされたcall_colonを受け入れる。`compile`（`src/core/inline_calls.zig:47`）はpacked call_colonガードと本文のコピーを生成する。`restore`（`src/core/inline_calls.zig:74`）はcall後のbranchパディングを検証して展開を再構築する。許可検査はガードの元word IDだけでなくコピーされた本文も走査する。

以下はdefs.OpKind全89種である。「保存」はspecializeCallがそのまま返し得ること、「inline」は本文としてコピーまたはガードとして生成され得ることである。種別許可とは別にoperand、word kind、コード境界、分岐先の妥当性を常に検査する。

| OpKind | 生成・変換との関係 | 許可外の動作 / 初期判定 | Op種別単位での判定 | 実行根拠 |
|---|---|---|---|---|
| `call` (`src/core/defs.zig:1325`) | 保存 | あり：呼出し先依存。静的な許可先のみ | 不可：WordKind、SYNONYM、DEFER、DOES>を追跡 | `src/forth.zig:1978` |
| `compile_call` (`src/core/defs.zig:1326`) | 保存 | あり：コード生成。拒否 | 種類だけで拒否可 | `src/forth.zig:2122` |
| `builtin` (`src/core/defs.zig:1327`) | 保存 | あり：呼出し先依存。静的な許可先のみ | 不可：valueはBuiltin番号。妥当性と許可表を照合 | `src/forth.zig:2126` |
| `literal` (`src/core/defs.zig:1328`) | 保存 / inline | データを積むだけ：条件付許可 | 種類として可。文字列範囲とxtの出自を検査。xt生成は実行許可ではない | `src/forth.zig:2139` |
| `float_literal` (`src/core/defs.zig:1329`) | 保存 / inline | データを積むだけ：条件付許可 | 種類として可。文字列範囲とxtの出自を検査。xt生成は実行許可ではない | `src/forth.zig:2140` |
| `execution_token` (`src/core/defs.zig:1330`) | 保存 / inline | データを積むだけ：条件付許可 | 種類として可。文字列範囲とxtの出自を検査。xt生成は実行許可ではない | `src/forth.zig:2139` |
| `store_value` (`src/core/defs.zig:1331`) | 保存 | あり：WordKindで文字列VALUE等へ進む。拒否 | 不可：対象語型・アドレス・補助処理の監査が必要 | `src/forth.zig:2141` |
| `branch` (`src/core/defs.zig:1332`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2154` |
| `branch_zero` (`src/core/defs.zig:1333`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2155` |
| `do_loop` (`src/core/defs.zig:1334`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2158` |
| `q_do_loop` (`src/core/defs.zig:1335`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2158` |
| `loop` (`src/core/defs.zig:1336`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2180` |
| `plus_loop` (`src/core/defs.zig:1337`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2180` |
| `leave` (`src/core/defs.zig:1338`) | 保存 | 実行時行先：loop_stack最上位のexit_pcを使用 | 不可：静的operand検査では足りない。呼出し単位のループ深さ境界と実行時行先検査を必須とする | `src/forth.zig:2197` |
| `print_string` (`src/core/defs.zig:1339`) | 保存 | あり：Writer出力。拒否 | 種類だけで拒否可 | `src/forth.zig:2203` |
| `string_literal` (`src/core/defs.zig:1340`) | 保存 | データを積むだけ：条件付許可 | 種類として可。文字列範囲とxtの出自を検査。xt生成は実行許可ではない | `src/forth.zig:2217` |
| `counted_string` (`src/core/defs.zig:1341`) | 保存 | データを積むだけ：条件付許可 | 種類として可。文字列範囲とxtの出自を検査。xt生成は実行許可ではない | `src/forth.zig:2210` |
| `abort_string` (`src/core/defs.zig:1342`) | 保存 | あり：例外状態変更。拒否 | 種類だけで拒否可 | `src/forth.zig:2211` |
| `does` (`src/core/defs.zig:1343`) | 保存 | あり：辞書の動的実行先変更。拒否 | 種類だけで拒否可 | `src/forth.zig:2222` |
| `exit` (`src/core/defs.zig:1344`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2241` |
| `local_frame` (`src/core/defs.zig:1345`) | 保存 | ローカル操作：最小集合外として拒否 | 不可：locals_size/kind/offsetと領域を監査後に再判断 | `src/forth.zig:2253` |
| `local_store` (`src/core/defs.zig:1346`) | 保存 | ローカル操作：最小集合外として拒否 | 不可：locals_size/kind/offsetと領域を監査後に再判断 | `src/forth.zig:2253` |
| `local_fetch` (`src/core/defs.zig:1347`) | 保存 | ローカル操作：最小集合外として拒否 | 不可：locals_size/kind/offsetと領域を監査後に再判断 | `src/forth.zig:2253` |
| `local_address` (`src/core/defs.zig:1348`) | 保存 | ローカル操作：最小集合外として拒否 | 不可：locals_size/kind/offsetと領域を監査後に再判断 | `src/forth.zig:2253` |
| `local_execute` (`src/core/defs.zig:1349`) | 保存 | あり：ローカル中のxt実行。拒否 | 不可：実行先検査が必要 | `src/forth.zig:2280` |
| `add_value` (`src/core/defs.zig:1350`) | 保存 | あり：WordKindで文字列VALUE等へ進む。拒否 | 不可：対象語型・アドレス・補助処理の監査が必要 | `src/forth.zig:2153` |
| `positive_do` (`src/core/defs.zig:1351`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2172` |
| `unsigned_positive_do` (`src/core/defs.zig:1352`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2172` |
| `negative_do` (`src/core/defs.zig:1353`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2172` |
| `unsigned_negative_do` (`src/core/defs.zig:1354`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2172` |
| `inclusive_negative_do` (`src/core/defs.zig:1355`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2172` |
| `unsigned_inclusive_negative_do` (`src/core/defs.zig:1356`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2172` |
| `for_loop` (`src/core/defs.zig:1357`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2172` |
| `memory_up_do` (`src/core/defs.zig:1358`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2172` |
| `memory_down_do` (`src/core/defs.zig:1359`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2172` |
| `negative_loop` (`src/core/defs.zig:1360`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2175` |
| `next_loop` (`src/core/defs.zig:1361`) | 保存 | 単独で外部動作なし：許可候補 | 種類として可。分岐先、loop/frame状態と取消し境界を検査 | `src/forth.zig:2175` |
| `call_builtin` (`src/core/defs.zig:1362`) | specialize（非primitive） | あり：呼出し先依存。静的な許可先のみ | 不可：valueはword ID。words[id].builtinを照合 | `src/forth.zig:2101` |
| `call_colon` (`src/core/defs.zig:1363`) | specialize / inlineガード | あり：呼出し先依存。静的な許可先のみ | 不可：通常word IDとpacked guardを区別し本文走査 | `src/forth.zig:1978` |
| `dup` (`src/core/defs.zig:1364`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `drop` (`src/core/defs.zig:1365`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `swap` (`src/core/defs.zig:1366`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `over` (`src/core/defs.zig:1367`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `rot` (`src/core/defs.zig:1368`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `nip` (`src/core/defs.zig:1369`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `tuck` (`src/core/defs.zig:1370`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `two_dup` (`src/core/defs.zig:1371`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `two_drop` (`src/core/defs.zig:1372`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `add` (`src/core/defs.zig:1373`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `sub` (`src/core/defs.zig:1374`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `mul` (`src/core/defs.zig:1375`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `equal` (`src/core/defs.zig:1376`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `not_equal` (`src/core/defs.zig:1377`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `less` (`src/core/defs.zig:1378`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `greater` (`src/core/defs.zig:1379`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `zero_equal` (`src/core/defs.zig:1380`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `zero_less` (`src/core/defs.zig:1381`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `bit_and` (`src/core/defs.zig:1382`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `bit_or` (`src/core/defs.zig:1383`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `bit_xor` (`src/core/defs.zig:1384`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `bit_complement` (`src/core/defs.zig:1385`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `negate` (`src/core/defs.zig:1386`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `one_plus` (`src/core/defs.zig:1387`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `one_minus` (`src/core/defs.zig:1388`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `to_r` (`src/core/defs.zig:1389`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `from_r` (`src/core/defs.zig:1390`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `r_fetch` (`src/core/defs.zig:1391`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `fetch` (`src/core/defs.zig:1392`) | specialize / primitive対応 / inline | 固定builtin：条件付許可 | 不可：M/Wのアドレス・長さ検査が必要 | `src/forth.zig:2117` |
| `store` (`src/core/defs.zig:1393`) | specialize / primitive対応 / inline | 固定builtin：条件付許可 | 不可：M/Wのアドレス・長さ検査が必要 | `src/forth.zig:2117` |
| `cfetch` (`src/core/defs.zig:1394`) | specialize / primitive対応 / inline | 固定builtin：条件付許可 | 不可：M/Wのアドレス・長さ検査が必要 | `src/forth.zig:2117` |
| `cstore` (`src/core/defs.zig:1395`) | specialize / primitive対応 / inline | 固定builtin：条件付許可 | 不可：M/Wのアドレス・長さ検査が必要 | `src/forth.zig:2117` |
| `add_store` (`src/core/defs.zig:1396`) | specialize / primitive対応 / inline | 固定builtin：条件付許可 | 不可：M/Wのアドレス・長さ検査が必要 | `src/forth.zig:2117` |
| `index` (`src/core/defs.zig:1397`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `index_2` (`src/core/defs.zig:1398`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `cells` (`src/core/defs.zig:1399`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `cell_plus` (`src/core/defs.zig:1400`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `two_star` (`src/core/defs.zig:1401`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `two_slash` (`src/core/defs.zig:1402`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `lshift` (`src/core/defs.zig:1403`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `rshift` (`src/core/defs.zig:1404`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `f_add` (`src/core/defs.zig:1405`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `f_sub` (`src/core/defs.zig:1406`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `f_mul` (`src/core/defs.zig:1407`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `f_div` (`src/core/defs.zig:1408`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `f_dup` (`src/core/defs.zig:1409`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `f_drop` (`src/core/defs.zig:1410`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `f_swap` (`src/core/defs.zig:1411`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `f_over` (`src/core/defs.zig:1412`) | specialize / primitive対応 / inline | 固定builtin：許可 | 可：同名Builtinの3節判定へ還元 | `src/forth.zig:2117` |
| `execute` (`src/core/defs.zig:1413`) | specialize / primitive対応（inline除外） | 動的xt：不許可 | 不可：実行先を検査。初期は拒否 | `src/forth.zig:2075` |

LEAVEの行先はOpのoperandではなくloop_stack最上位のframe.exit_pcであり、pcだけを変更して現在のend_pcを変更しない（`src/forth.zig:2197`）。CallFrameはloop_depthを保存せず（`src/forth.zig:1640`）、frameWithLoopPCsもloop_depthを検査せず、フレームのコピーとpc/end_pcの更新だけである（`src/forth.zig:1918`）。EXITとreturnToCallerにもループ深さの復元・照合はない（`src/forth.zig:2241`, `src/forth.zig:1771`）。そのためDO内でEXITした後の残留フレーム、またはUNLOOPで露出した外側のフレーム（`src/core/words_compiling.zig:80`）をLEAVEが使うと、別定義のexit_pcへ現在のend_pcを保持したまま跳び得る。これはソース上の経路確認であり、実行試験は未実施である。

提案として、呼出し単位にloop_depthの下限とフレーム所有境界を保持し、UNLOOP・LEAVE・LOOP系による境界越えを拒否し、復帰時の残留ループを検査する必要がある。LEAVEでは所有するループのexit_pcと現在のコード範囲の整合も実行時に検査する。境界の実装・検証前はLEAVEとUNLOOPの許可候補を実許可へ移さない。

## 5. 動的実行・例外の迂回経路

| 経路 | 確認した動作と根拠 | 初期検査の提案 |
|---|---|---|
| EXECUTE | スタックxtをwordId/synonymTargetで解決し、colonは現在のループへ、それ以外はwordInLoopへ進む（`src/forth.zig:2075`）。builtin版はexecuteWordへ再入する（`src/core/words_compiling.zig:75`） | primitiveとbuiltinの両形式を拒否する |
| CATCH / CATCH-NOBT | 専用Opはない。builtin呼出しからbuiltinInLoopの特別処理（`src/forth.zig:1723`）またはCATCH-NOBTの実装（`src/core/words_diagnostics.zig:22`）からrunCatch（`src/core/words_system.zig:292`）がxtを実行する | builtin/call_builtin/callの解決後も拒否する |
| THROW | 専用Opはない。throw_codeを設定して失敗を返す（`src/core/words_system.zig:275`）。捕捉除外はrunOperations（`src/forth.zig:1898`）とCatchContext.handleError（`src/core/words_system.zig:121`）にある | 初期拒否。通常エラーの伝播と取消しを混同せず、将来許可時は専用取消し値の非捕捉を試験する |
| PERFORM | メモリからxtを読みexecuteWordを呼ぶ（`src/core/words_system.zig:268`） | EXECUTE禁止の迂回になるため拒否する |
| DEFER | callのdeferred分岐がword.valueのセルを読みcolonへ直接進む（`src/forth.zig:2006`）。executeWordにもdeferred分岐がある（`src/forth.zig:1567`） | 定義builtinだけでなく既存deferred WordKindへの呼出しを拒否する |
| DEFER!/IS/DEFERS | 定義・変更・取得処理はwords_defining.execute（`src/core/words_defining.zig:29`）、DEFER!はセルを書き換える（`src/core/words_defining.zig:51`） | 初期拒否。DEFERS等で既に直接呼出しへ解決された場合も最終実体を検査する |
| local_execute | ローカルからxtを読みwordInLoopへ進む（`src/forth.zig:2280`） | Op自体を拒否する |
| DOES> | does Opがwordsのdoes_code_start/end/has_doesを書き換える（`src/forth.zig:2222`）。has_doesを持つcreated/variableのcallは補助経路へ進む（`src/forth.zig:2032`） | doesとhas_doesを持つ語を拒否する。通常のアドレス返却語はworker領域へ再配置されていることを検査する |
| SYNONYM | synonymTargetが別の語を解決する（`src/forth.zig:1233`）。execute経路にも解決がある（`src/forth.zig:2076`） | 名前で許可せず、最終WordKind・Builtin・colon本文を検査する |

上表は全ネイティブ再入経路の完了表ではない。詳細計画2.1・12.2節のexecuteWord再入全箇所、Writer全フィールド、ホスト共有変数の担当成果物と結合する必要がある。本案の許可builtinには上表の動的再入を含めない。

論理memory内にも、system領域・入力領域に加え、ブロックバッファとソースのスナップショット、ヒープ、ローカル変数フレームが存在する（`src/core/memory_map.zig:34`）。これらはworkerの許可データ領域と同一視せず、領域外として検査対象に含める。!・MOVEの登録更新はclassify/heapContainsを通り、heapTop・ヒープヘッダーのsize/usedを読む（`src/core/address_registry.zig:43`, `src/core/address_registry.zig:54`）。heapTopはsystem内のheap_top_addressを読む（`src/core/heap_memory.zig:15`, `src/core/memory_map.zig:310`）。従ってユーザーデータの範囲だけでなく、補助処理が読む管理領域の専有・整合性も必要である。

PADは0x2000を積み（`src/core/words_memory.zig:190`, `src/core/memory_map.zig:321`）、system_end=0x4000より下のsystem領域である（`src/core/memory_map.zig:42`）。PAD自体は定数返却として許可候補に残すが、提案のsystem領域書込み拒否を適用するとPADへの書込みは失敗する。worker用PADへの再配置または限定的な権限付与は未決であり、現案でPADを作業バッファとして利用できるとはしない。

## 6. 許可検査器への提案

1. 復元・specialize・inline完了後に入口から実コードを走査する。再帰colonは訪問集合で循環を扱う。未知WordKind・不正operand・範囲外分岐は拒否する。
2. builtin/call_builtin/primitiveを同一Builtin許可表へ正規化する。call/call_colonは対象WordKindと実体を検査し、packed inlineガードを通常word IDとして扱わない。
3. inlineガードだけでなくコピー済み後続Opと分岐先も走査する。ガードは呼出し深さを保つものであり、許可証ではない（`src/forth.zig:1979`）。
4. メモリ操作では実行時にアドレス・幅・長さを検査する。system領域、ブロックバッファ・ソーススナップショット、ヒープ管理領域、ローカル変数フレームや実行先セルへ書ける状態を不変辞書とみなさない。ネイティブ走査中の取消しと操作上限が未成立なら、M/W候補を試作の実許可表へ入れない。
5. 静的検査後の辞書・コード・許可表の変更を認めず、動的実行先拒否の実行時防壁も設ける。null Writerだけに依存しない。
6. ビルド構成の除外検査（`src/forth.zig:2304`, `src/forth.zig:2119`）とタスク許可は別に扱い、未知builtin/Opは既定拒否とする。

## 7. 未確認事項と判断事項

未確認事項は次のとおりである。

- 許可検査器、追加メモリ領域検査、専用取消し経路は本作業で実装・実行していない。無限ループ停止、成功・失敗・取消し後の再利用、メイン・他workerへの非干渉は未確認である。
- Writer全callbackのfallback、ホスト共有状態、復元・破棄、共通エラー記録、counted経路（charge・execution_ops・stepperを含む）およびdebug/profile/watchの再帰監査は未完了である。拒否語の全到達先も未追跡である。
- snapshot再配置後の読取り専用領域・入力・静的データ・ブロックバッファ・ソーススナップショット・ヒープ管理領域・heap_top_address・ローカル変数フレーム・PADを含むsystem領域の権限区分と上限は未確定である。既存memoryAddressがこの分離を提供するとは扱わない。
- 基本8浮動小数語以外、ヒープAPI、ローカル、VALUE・文字列VALUE等の追加許可は未監査である。

判断が必要な事項は、呼出し単位のループ境界と復帰時検査の仕様、workerでのcounted経路の扱い、PADの権限または再配置、整数・スタック・制御Opだけで試作を始めるか、M/Wの領域検査を整えて同時に許可するか、基本8浮動小数語を含めるか、動的実行と例外を初期拒否とするかである。追加許可には個別の到達先監査と取消し・隔離の受入試験が必要である。本書だけで独立Forth VM方式を採用済みとはしない。

## 付録A. 実際に実行した件数集計

ソースの配列とenumを数えたコマンドである。Builtin総数も列挙から数えるが、全到達経路の数ではない。PowerShellから次のPythonを標準入力へ渡して実行した（先頭のhere-stringと末尾のパイプは省略する）。

```python
from pathlib import Path
import re
files=['words_arithmetic','words_stack','words_memory','words_compiling','words_loops']
def words(f):
 s=Path('src/core/'+f+'.zig').read_text(encoding='utf-8-sig'); a=re.search(r'pub const words\s*=.*?\{(.*?)\};',s,re.S).group(1); return re.findall(r'\.(\w+)',a)
for f in files: print(f,len(words(f)))
s=Path('src/core/defs.zig').read_text(encoding='utf-8-sig'); ops=re.findall(r'^\s+(\w+),',re.search(r'pub const OpKind = enum \{(.*?)\};',s,re.S).group(1),re.M)
print('OpKind',len(ops),'primitive',len(ops[ops.index('dup'):]))
builtins=re.findall(r'^\s+(\w+),',re.search(r'pub const Builtin = enum[^\{]*\{(.*?)\};',s,re.S).group(1),re.M)
print('Builtin total',len(builtins))
```

実行結果：

```text
words_arithmetic 115
words_stack 31
words_memory 54
words_compiling 76
words_loops 18
OpKind 89 primitive 50
Builtin total 1112
```

### 文書表の照合

次のPythonもPowerShellから実行した。builtin行の重複とOp全種の一致、OpKindの参照行そのものが該当メンバー宣言であることを照合する。その他の引用は本修正で対象箇所をソースと照合したが、このスクリプトで意味全体を証明するものではない。

```python
from pathlib import Path
import re
from collections import Counter
s=Path('docs/TASK_CONTROL_AUDIT_ALLOWED_SET.md').read_text(encoding='utf-8')
b=s.split('## 3.')[1].split('## 4.')[0]
r=re.findall(r'^\| `(\w+)` / .*? \| (許可|条件付許可|不許可)：',b,re.M)
assert len(r)==len(set(k for k,v in r))
print('builtin rows',len(r))
for decision in ['許可','条件付許可','不許可']:
 print(decision,sum(v==decision for k,v in r))
o=s.split('## 4.')[1].split('## 5.')[0]
a=re.findall(r'^\| `(\w+)` \(`src/core/defs.zig:',o,re.M)
d=Path('src/core/defs.zig').read_text(encoding='utf-8-sig')
e=re.findall(r'^\s+(\w+),',re.search(r'pub const OpKind = enum \{(.*?)\};',d,re.S).group(1),re.M)
assert a==e
print('OpKind exact match',len(a))
for name,num in re.findall(r'^\| `(\w+)` \(`src/core/defs.zig:(\d+)`',o,re.M):
 assert re.fullmatch(r'\s*'+re.escape(name)+r',\s*',d.splitlines()[int(num)-1]),(name,num)
print('OpKind reference names exact match',len(a))
builtins=re.findall(r'^\s+(\w+),',re.search(r'pub const Builtin = enum[^\{]*\{(.*?)\};',d,re.S).group(1),re.M)
assert set(k for k,v in r)<=set(builtins)
allowed=sum(v in ('許可','条件付許可') for k,v in r)
print('Builtin total',len(builtins),'allowed candidates',allowed,'default denied',len(builtins)-allowed)
print('strict allowed',sum(v=='許可' for k,v in r),'denied without conditional',len(builtins)-sum(v=='許可' for k,v in r))
```

実行結果：

```text
builtin rows 312
許可 172
条件付許可 30
不許可 110
OpKind exact match 89
OpKind reference names exact match 89
Builtin total 1112 allowed candidates 202 default denied 910
strict allowed 172 denied without conditional 940
```
