# タスク制御01-B2：Writerと共有状態の監査

作成日：2026-11-23。対象：タスク1350（1048配下）。静的ソース監査であり、ワーカー実装・並行実行試験の合格を示す文書ではない。

## 1. 根拠と判定の範囲

設計の根拠は `docs/TASK_CONTROL_DETAILED_PLAN.md` 2・5〜13節、`docs/TASK_CONTROL_PLAN.md`、`docs/CORE_EXTENSION_DETAILED_DESIGN.md` 11節、`docs/CORE_EXTENSION_WORKER_STATE_AUDIT.md`、`docs/CORE_EXTENSION_REVIEW_RESPONSE.md`、`docs/CORE_EXTENSION_DESIGN_DECISIONS.md` である。独立VMの採用と最終許可集合は未決である。本書は最小許可集合の候補である算術・比較・分岐・ループ・スタック・検査付きワーカー内論理メモリを前提とする条件付き監査である（`docs/TASK_CONTROL_DETAILED_PLAN.md:136`、`docs/CORE_EXTENSION_DETAILED_DESIGN.md:781`、`docs/CORE_EXTENSION_DETAILED_DESIGN.md:802`）。

「到達しない」は上記候補だけを静的・動的に制限し、Stateをコピーせず、専用Writerを構築した場合の設計判定である。現在の辞書全体から到達不能という意味ではない。1351の語・Op別許可集合との突合せ、および1053の再帰監査・試験が必要である。所有スレッド欄はホスト側の管理主体と補助スレッド・OS callbackの区別を示す。全変数のロック規約を証明したものではない。

## 2. Writerの全73フィールド

73件を宣言から再計数した。設定欄は実装済みの事実ではなく、ワーカーWriterの構築案である。context以外のoptional 70件はnull、contextとwrite_fnは専用設定、standard_interruptsはfalseとする。contextはnull許容型であるが、既定値がないため明示設定が必要である。write_fnとstandard_interruptsの2件はnull不可である。通常ホストの配線は `src/main.zig:3752` であり、このWriterをコピーしてcallbackを一部差し替える方式は採らない。

| # | フィールド（宣言位置） | ワーカー設定案 | null時の分類・挙動 | コアの参照位置 |
|---|---|---|---|---|
| 1 | `execution_ops` (`src/core/host_interface.zig:187`) | null | エラー：debug有効時のEXEC-LIMITEDのbegin/pollはHostUnavailable。debug無効時はInvalidExecutionTokenである（`src/core/execution_control.zig:60`）。メインの信号scopeを借用しない。取消し専用経路は別途設計する | `src/core/execution_control.zig:51`、`src/core/execution_control.zig:67` |
| 2 | `audio_scope_ops` (`src/core/host_interface.zig:189`) | null | エラー：PCMのscope開始前にHostUnavailable | `src/core/words_pcm.zig:46`、`src/core/words_pcm.zig:121` |
| 3 | `process_ops` (`src/core/host_interface.zig:190`) | null | エラー：PROCESS語はHostUnavailable | `src/core/words_process.zig:20` |
| 4 | `physical_key_ops` (`src/core/host_interface.zig:191`) | null | 既定値／無操作：SCANの可否・保持は偽、イベントなし、resyncは空bitmap。復元時resetも呼ばない | `src/core/image_restore.zig:104`、`src/core/words_graphics.zig:97`、`src/core/words_graphics.zig:103`、`src/core/words_graphics.zig:110`、`src/core/words_graphics.zig:121` |
| 5 | `gamepad_ops` (`src/core/host_interface.zig:192`) | null | 既定値：POLLは空snapshotにして-1、MAPは0。既存snapshotへの問い合わせはState内を読む | `src/core/gamepad.zig:30`、`src/core/gamepad.zig:82` |
| 6 | `context` (`src/core/host_interface.zig:193`) | 設定：専用context | null許容型であるがcallbackの契約次第である。設定案はワーカー専用出力contextであり、メインのHostを渡さない | `src/core/host_interface.zig:387`、`src/forth.zig:486` |
| 7 | `write_fn` (`src/core/host_interface.zig:194`) | 設定：専用上限付き出力 | null不可。必須関数ポインターである。上限付きワーカー専用出力へ設定する案である。void戻り値なので超過をcontextへ記録しタスク失敗へ変換する経路が必要である | `src/core/host_interface.zig:387` |
| 8 | `log_fn` (`src/core/host_interface.zig:196`) | null | 何もしない：debugログを出さない | `src/core/debug_log.zig:37`、`src/core/debug_log.zig:63` |
| 9 | `read_fn` (`src/core/host_interface.zig:197`) | null | 既定値／エラー：input_redirect.lineはnull。ACCEPT等は入力先がなくInputUnavailable。リダイレクト済みならfile_ops経由の入力は別経路である | `src/core/input_redirect.zig:104`、`src/core/words_input.zig:47` |
| 10 | `load_fn` (`src/core/host_interface.zig:198`) | null | エラー：LOAD/SAVE/SAVESYSの対応callback取得時にFileUnavailable | `src/core/words_system.zig:208` |
| 11 | `save_fn` (`src/core/host_interface.zig:199`) | null | エラー：LOAD/SAVE/SAVESYSの対応callback取得時にFileUnavailable | `src/core/words_system.zig:214` |
| 12 | `savesys_fn` (`src/core/host_interface.zig:200`) | null | エラー：LOAD/SAVE/SAVESYSの対応callback取得時にFileUnavailable | `src/core/words_system.zig:220` |
| 13 | `key_fn` (`src/core/host_interface.zig:201`) | null | エラー／既定値：KEY・XKEYはInputUnavailable。legacy EKEYはEOF、pollはイベントなし。非リダイレクトの行読取りでStateに保留バイトがある場合はHostUnavailableとなる。ACCEPTもread_fnが設定されていればこの経路へ進む | `src/core/event_input.zig:33`、`src/core/input_redirect.zig:77`、`src/core/input_redirect.zig:78`、`src/core/words_input.zig:47`、`src/core/words_input.zig:49`、`src/core/words_terminal.zig:24`、`src/core/words_xchar.zig:139` |
| 14 | `key_ior_fn` (`src/core/host_interface.zig:203`) | null | フォールバック：KEYはkey_fnへ落ちる。両方nullならInputUnavailable。片方だけnullでは入力の遮断にならない | `src/core/words_terminal.zig:23` |
| 15 | `monotonic_ms_fn` (`src/core/host_interface.zig:205`) | null | フォールバック：legacy EKEYのESC継続待ちが各回50ms指定になる。OS時計の直接取得はしないがevent_key_fn等へ到達する | `src/core/event_input.zig:83` |
| 16 | `event_key_fn` (`src/core/host_interface.zig:207`) | null | フォールバック：legacy EKEYはkey_ready_fn/key_fn/input_error_fnへ進む。両入力callbackをnullにしてもStateのpendingは読む | `src/core/event_input.zig:26` |
| 17 | `standard_event_fn` (`src/core/host_interface.zig:210`) | null | フォールバック：EKEY/EKEY?はlegacy入力へ。modernの直接呼出しはHostUnavailable。UNREADはunread_fnまたはState.pending_keyへ | `src/core/event_input.zig:56`、`src/core/event_input.zig:72`、`src/core/event_input.zig:150`、`src/core/event_input.zig:160`、`src/core/event_input.zig:170` |
| 18 | `standard_clock` (`src/core/host_interface.zig:211`) | null | エラー：modernとPCM scopeはHostUnavailable。legacy EKEYのmonotonic_ms_fnとは別である | `src/core/event_input.zig:161`、`src/core/words_pcm.zig:46`、`src/core/words_pcm.zig:122` |
| 19 | `standard_interrupts` (`src/core/host_interface.zig:212`) | false | boolでnull不可。falseを設定する案である。modernの割込み解釈を無効にするだけで入力禁止を意味しない | `src/core/event_input.zig:164` |
| 20 | `buffered_key_fn` (`src/core/host_interface.zig:215`) | null | フォールバック：pending_standard_event、event_key_fn、legacy keyへ進む。ホスト保持バイトを先取りしない | `src/core/event_input.zig:19`、`src/core/event_input.zig:47` |
| 21 | `key_ready_fn` (`src/core/host_interface.zig:216`) | null | 既定値：legacy pollはイベントなし。redirect.readyはStateのpendingだけでも真になる | `src/core/event_input.zig:28`、`src/core/input_redirect.zig:69` |
| 22 | `unread_fn` (`src/core/host_interface.zig:221`) | null | フォールバック：legacyはState.pending_event_bytes/pending_keyへ戻す。checked版がある場合はそちらを優先する | `src/core/event_input.zig:48`、`src/core/event_input.zig:189`、`src/core/event_input.zig:239` |
| 23 | `unread_byte_fn` (`src/core/host_interface.zig:223`) | null | フォールバック／エラー：beforeStdinBytesはunread_fnへ。beforeFileReadでlegacyバイトの押戻しが必要ならHostUnavailable。両方nullではdecoder保持を残す場合がある | `src/core/event_input.zig:170`、`src/core/event_input.zig:180`、`src/core/event_input.zig:218` |
| 24 | `sleep_fn` (`src/core/host_interface.zig:224`) | null | エラー：対応する待機・時刻・環境・errno・SYSTEM・エディター語はHostUnavailable | `src/core/words_system.zig:227` |
| 25 | `sleep_ns_fn` (`src/core/host_interface.zig:226`) | null | エラー：対応する待機・時刻・環境・errno・SYSTEM・エディター語はHostUnavailable | `src/core/nanosecond_wait.zig:10` |
| 26 | `utime_fn` (`src/core/host_interface.zig:228`) | null | エラー：対応する待機・時刻・環境・errno・SYSTEM・エディター語はHostUnavailable。State.initは時計を呼ばず乱数seedの既定値を維持し、graphics入力の時刻取得はnullを返す | `src/forth.zig:486`、`src/core/graphics_input.zig:459`、`src/core/words_system.zig:246` |
| 27 | `ntime_fn` (`src/core/host_interface.zig:230`) | null | エラー：対応する待機・時刻・環境・errno・SYSTEM・エディター語はHostUnavailable | `src/core/words_system.zig:234` |
| 28 | `cputime_fn` (`src/core/host_interface.zig:232`) | null | エラー：対応する待機・時刻・環境・errno・SYSTEM・エディター語はHostUnavailable | `src/core/words_system.zig:240` |
| 29 | `local_time_fn` (`src/core/host_interface.zig:233`) | null | エラー：対応する待機・時刻・環境・errno・SYSTEM・エディター語はHostUnavailable | `src/core/words_memory.zig:151` |
| 30 | `zoned_time_fn` (`src/core/host_interface.zig:235`) | null | エラー：対応する待機・時刻・環境・errno・SYSTEM・エディター語はHostUnavailable | `src/core/zoned_time.zig:9` |
| 31 | `getenv_fn` (`src/core/host_interface.zig:237`) | null | エラー：対応する待機・時刻・環境・errno・SYSTEM・エディター語はHostUnavailable | `src/core/paths.zig:243`、`src/core/words_system.zig:251` |
| 32 | `errno_fn` (`src/core/host_interface.zig:239`) | null | エラー：対応する待機・時刻・環境・errno・SYSTEM・エディター語はHostUnavailable | `src/core/words_diagnostics.zig:34` |
| 33 | `system_fn` (`src/core/host_interface.zig:241`) | null | エラー：対応する待機・時刻・環境・errno・SYSTEM・エディター語はHostUnavailable | `src/core/shell_line.zig:7`、`src/core/words_system.zig:271` |
| 34 | `editor_fn` (`src/core/host_interface.zig:243`) | null | エラー：対応する待機・時刻・環境・errno・SYSTEM・エディター語はHostUnavailable | `src/core/source_editor.zig:50`、`src/core/source_editor.zig:63` |
| 35 | `file_ops` (`src/core/host_interface.zig:244`) | null | エラー：State.fileOpsはHostUnavailable。例外として診断のstderr出力は通常Writer出力へフォールバックする。内部の.?利用もあるため語の禁止検査を省けない | `src/forth.zig:2407`、`src/core/graphics_font.zig:235`、`src/core/graphics_font.zig:282`、`src/core/words_graphics.zig:680`、`src/core/words_tools.zig:273` |
| 36 | `framebuffer_fn` (`src/core/host_interface.zig:249`) | null | エラー：GFX-INIT／画像確保・decodeはHostUnavailable。Stateに既にある画素を使う描画語までは禁止しない | `src/core/words_graphics.zig:132` |
| 37 | `image_alloc_fn` (`src/core/host_interface.zig:253`) | null | エラー：GFX-INIT／画像確保・decodeはHostUnavailable。Stateに既にある画素を使う描画語までは禁止しない | `src/core/graphics_decode.zig:30`、`src/core/graphics_decode.zig:206`、`src/core/graphics_images.zig:289` |
| 38 | `image_free_fn` (`src/core/host_interface.zig:255`) | null | エラー／無操作：新規画像確保はHostUnavailable。releaseAllはcallbackなしでもスロットを空にするため、非空なら解放漏れになる | `src/core/graphics_decode.zig:31`、`src/core/graphics_decode.zig:207`、`src/core/graphics_images.zig:290`、`src/core/graphics_images.zig:318` |
| 39 | `terminal_size_fn` (`src/core/host_interface.zig:258`) | null | フォールバック：FORM/COLS/ROWSと端末描画は80列24行（captureでは別規則）。出力はWriterへ続く | `src/core/graphics_terminal.zig:26`、`src/core/words_terminal.zig:85` |
| 40 | `terminal_mode_set_fn` (`src/core/host_interface.zig:260`) | null | 既定エラー値：モード設定のiorは-21。mask不正は-24 | `src/core/words_extension.zig:95` |
| 41 | `terminal_mode_get_fn` (`src/core/host_interface.zig:261`) | null | エラー／フォールバック：問合せはHostUnavailable。設定成功後の確認値は要求maskに代用する | `src/core/words_extension.zig:97`、`src/core/words_extension.zig:106` |
| 42 | `input_error_fn` (`src/core/host_interface.zig:263`) | null | 何もしない：legacy callback後のlatched error検査を省略する。入力自体は禁止しない | `src/core/event_input.zig:30`、`src/core/event_input.zig:35`、`src/core/event_input.zig:179`、`src/core/event_input.zig:197`、`src/core/event_input.zig:206` |
| 43 | `terminal_utf8_fn` (`src/core/host_interface.zig:268`) | null | 何もしない：UTF-8出力前後のホスト切替を省く。端末描画のWriter出力は続く | `src/core/graphics_terminal.zig:177` |
| 44 | `display_budget_fn` (`src/core/host_interface.zig:271`) | null | 何もしない：自動バックエンド探索のホスト共通期限scopeを省く。window/Tk探索は続く | `src/core/words_graphics.zig:501` |
| 45 | `window_fn` (`src/core/host_interface.zig:278`) | null | エラー／フォールバック：明示window表示はHostUnavailable、可否は偽。autoTryはdesktopならTclへ、最後は端末方式1へ落ちる | `src/core/words_graphics.zig:284`、`src/core/words_graphics.zig:289`、`src/core/words_graphics.zig:504` |
| 46 | `ime_preedit_fn` (`src/core/host_interface.zig:282`) | null | 既定値：未確定文字列の長さ0 | `src/core/words_graphics.zig:318` |
| 47 | `ime_caret_fn` (`src/core/host_interface.zig:285`) | null | 何もしない：caret通知なし | `src/core/words_graphics.zig:476` |
| 48 | `window_fullscreen_fn` (`src/core/host_interface.zig:290`) | null | 既定動作：State.gfx_fullscreenの設定・照会だけを行う | `src/core/words_graphics.zig:327`、`src/core/words_graphics.zig:331` |
| 49 | `window_cursor_fn` (`src/core/host_interface.zig:292`) | null | 何もしない：Stateのcursor設定は行うがホスト通知しない | `src/core/words_graphics.zig:469` |
| 50 | `displays_fn` (`src/core/host_interface.zig:296`) | null | 既定値：再取得時は空のdisplay snapshotを返す。再取得しない問合せは既存のState snapshotを読む | `src/core/words_graphics.zig:338` |
| 51 | `window_display_fn` (`src/core/host_interface.zig:301`) | null | 既定値：-1 | `src/core/words_graphics.zig:357` |
| 52 | `window_state_fn` (`src/core/host_interface.zig:304`) | null | 既定値：空WindowState。flags/矩形/世代等は0または偽 | `src/core/words_graphics.zig:367`、`src/core/words_graphics.zig:380`、`src/core/words_graphics.zig:428`、`src/core/words_graphics.zig:441`、`src/core/words_graphics.zig:448` |
| 53 | `window_size_fn` (`src/core/host_interface.zig:309`) | null | 既定値：外部windowの寸法0 0 | `src/core/words_graphics.zig:223` |
| 54 | `window_minimized_fn` (`src/core/host_interface.zig:311`) | null | 何もしない：Tclの表示状態判定にnative最小化情報を反映しない | `src/core/tcl.zig:449` |
| 55 | `window_fit_fn` (`src/core/host_interface.zig:315`) | null | 何もしない：State側の設定は残すがホストへ適用しない | `src/core/words_graphics.zig:403` |
| 56 | `window_place_fn` (`src/core/host_interface.zig:322`) | null | 何もしない：State側の設定は残すがホストへ適用しない | `src/core/words_graphics.zig:395` |
| 57 | `window_close_fn` (`src/core/host_interface.zig:328`) | null | フォールバック／無操作：keep-open/closeの通知なし。closesはwindow_state_fnがあればそこから取得、なければ0 | `src/core/words_graphics.zig:408`、`src/core/words_graphics.zig:418`、`src/core/words_graphics.zig:426` |
| 58 | `window_smooth_fn` (`src/core/host_interface.zig:331`) | null | 何もしない：State側の設定は残すがホストへ適用しない | `src/core/words_graphics.zig:436` |
| 59 | `window_wait_fn` (`src/core/host_interface.zig:338`) | null | 既定値：描画待機・VSYNC待機は0。同期OS待機へは落ちない | `src/core/words_graphics.zig:457`、`src/core/words_graphics.zig:463` |
| 60 | `input_fn` (`src/core/host_interface.zig:343`) | null | graphics_input.readPendingはinput_fnの取得位置で戻る。その前にstandard_inputのpaste/escape_atを変更し、graphics有効時はTclをpollする。input_fn=nullだけではこれらを遮断しない | `src/core/graphics_input.zig:467`、`src/core/graphics_input.zig:471`、`src/core/graphics_input.zig:472` |
| 61 | `mouse_fn` (`src/core/host_interface.zig:346`) | null | 何もしない：Stateのmouse設定とinput_error_fn検査は続く | `src/core/graphics_input.zig:581` |
| 62 | `cursor_fn` (`src/core/host_interface.zig:349`) | null | 既定動作：端末画像のtop行位置をホストへ問い合わせず不明のままにする | `src/core/graphics_terminal.zig:75` |
| 63 | `font_buffer_fn` (`src/core/host_interface.zig:353`) | null | エラー：BDF読込みはどちらかがnullならHostUnavailable。既存font.bufferは復元で解放されない | `src/core/graphics_font.zig:210`、`src/core/graphics_font.zig:244` |
| 64 | `font_free_fn` (`src/core/host_interface.zig:355`) | null | エラー：BDF読込みはどちらかがnullならHostUnavailable。既存font.bufferは復元で解放されない | `src/core/graphics_font.zig:210`、`src/core/graphics_font.zig:245`、`src/core/graphics_font.zig:258` |
| 65 | `process_start_fn` (`src/core/host_interface.zig:359`) | null | エラー：Tclの起動・送信・受信はHostUnavailable。送受信の失敗をlost処理へ変換する箇所がある | `src/core/tcl.zig:146` |
| 66 | `process_write_fn` (`src/core/host_interface.zig:361`) | null | エラー：Tclの起動・送信・受信はHostUnavailable。送受信の失敗をlost処理へ変換する箇所がある | `src/core/tcl.zig:173` |
| 67 | `process_read_fn` (`src/core/host_interface.zig:365`) | null | エラー：Tclの起動・送信・受信はHostUnavailable。送受信の失敗をlost処理へ変換する箇所がある | `src/core/tcl.zig:181` |
| 68 | `process_stop_fn` (`src/core/host_interface.zig:368`) | null | 既定動作：Tcl停止はホスト停止済み(true)として処理する。子プロセスを実際に停止する保証はない | `src/core/tcl.zig:160` |
| 69 | `system_font_fn` (`src/core/host_interface.zig:371`) | null | エラー：system font選択はHostUnavailable | `src/core/graphics_font.zig:195` |
| 70 | `system_glyph_fn` (`src/core/host_interface.zig:375`) | null | 既定値：system glyphなし、GLYPH-LOADは-1 | `src/core/graphics_font.zig:146` |
| 71 | `audio_fn` (`src/core/host_interface.zig:379`) | null | エラー：音engine取得・PCMはHostUnavailable。既存のState内音設定は別に存在する | `src/core/words_audio.zig:326`、`src/core/words_pcm.zig:13`、`src/core/words_pcm.zig:17` |
| 72 | `audio_device_fn` (`src/core/host_interface.zig:381`) | null | 既定値：音デバイス可否は0 | `src/core/words_audio.zig:318` |
| 73 | `audio_wait_fn` (`src/core/host_interface.zig:384`) | null | エラー：音の待機はHostUnavailable、PCMもscope開始前に拒否する | `src/core/words_audio.zig:906`、`src/core/words_pcm.zig:46`、`src/core/words_pcm.zig:123` |

### 2.1 nullでも別経路へ進む重要箇所

| 語・処理 | nullからの遷移と到達先 | 初期ワーカーでの扱い |
|---|---|---|
| EKEY/EKEY?、KEY/XKEY、UNREAD | standard_event_fnなし→legacy→event_key_fn/key_fn/key_ready_fn/unread_fn等。standard_event_fnとclockがあるmodernでは共有modern_depthを更新する（`src/core/event_input.zig:16`、`src/core/event_input.zig:56`、`src/core/event_input.zig:154`）。リダイレクトはfile_opsへ進む | 入力語すべて禁止。あるcallbackのnullだけで遮断しない |
| 自動表示・SHOW系 | window_fnなし→desktop指定ならTcl→端末方式。Tclはprocess_start/write/read等を経てhost_processのプロセス共有状態へ、端末はWriter出力へ進む（`src/core/words_graphics.zig:500`、`src/core/tcl.zig:146`、`src/core/graphics_terminal.zig:178`） | UI禁止。window_fn=nullだけでは禁止できない。専用write_fnも必須 |
| FORM/COLS/ROWS、端末画像出力 | terminal_size_fnなしでも80×24で続行する（`src/core/words_terminal.zig:78`、`src/core/graphics_terminal.zig:31`）。terminal_utf8_fnなしでもWriter出力する | 初期許可に含めない |
| 診断stderr | file_opsなしでも通常出力へ落ちる（`src/core/words_tools.zig:273`）。write_fnがメイン用なら共有output_bufferへ届く（`src/main.zig:3055`、`src/main.zig:3752`） | 診断も専用出力へ限定 |
| WINDOW-CLOSES | window_close_fnなしでもwindow_state_fnへ進む（`src/core/words_graphics.zig:426`） | 両方null、UI語も禁止 |
| パスのhome展開 | FileOps.user_homeがないとgetenv_fnへ進む（`src/core/paths.zig:240`）。OS環境を直接禁止したつもりでも別callbackから到達し得る | file_ops/getenv_fnともnull、ファイル語禁止 |

全optionalがnullなら、上記のフォールバックからメインのホストcallbackへ自動的に接続する実装ではない。ただし必須write_fn/contextをメインから借用すると出力経由で到達する。Stateの既存画素・font・Tcl・capture_sink等への直接アクセスもcallbackのnullでは取り除けないため、専用Stateの初期化が必要である（`src/forth.zig:483`、`src/core/graphics_images.zig:329`）。

## 3. モジュール直下の変数：16ファイル255宣言行

従来の「16ファイル255行」は行頭にある `var` / `pub var` の宣言行を数えた値であり、ソースの総行数ではない。今回の同じ条件での再計数も16ファイル255件で一致した。`src/tests`、`test_`で始まる試験注入変数、`host_line.zig`の`sunk`を除外した。コンテナ内変数はこの255件に含まれないため、3.2で別に列挙する。

| ファイル | 宣言行数 |
|---|---|
| `src/core/event_input.zig` | 1 |
| `src/host_audio.zig` | 10 |
| `src/host_directories.zig` | 2 |
| `src/host_display_budget.zig` | 1 |
| `src/host_display_macos.zig` | 3 |
| `src/host_evdev.zig` | 6 |
| `src/host_gamepad.zig` | 3 |
| `src/host_input.zig` | 17 |
| `src/host_process.zig` | 2 |
| `src/host_resize.zig` | 1 |
| `src/host_runtime.zig` | 1 |
| `src/host_signal_broker.zig` | 2 |
| `src/host_wait.zig` | 10 |
| `src/host_window_linux.zig` | 37 |
| `src/host_window_macos.zig` | 128 |
| `src/main.zig` | 31 |
| 合計 | 255 |

### 3.1 変数ごとの所有・アクセス・到達判定

各行の「否（条件付き）」は1節の初期候補を強制した場合である。ホストの起動・終了・資源管理による直接アクセスは存続する。ワーカーがそれを呼んでよいことを意味しない。宣言と同一ファイル内の主な参照を付記する。

| 変数 | 宣言 | 所有・アクセス主体 | アクセス経路 | 初期許可集合からの到達 | 主な同一ファイル参照 |
|---|---|---|---|---|---|
| `modern_depth` | `src/core/event_input.zig:154` | メイン入力を扱うホストスレッドに限定する必要がある。非atomic共有値 | 直接：modernから更新、mainのexecutionRawPollから読取り | 否（入力禁止・modernのcallback/clockなし・両操作口にメインのExecutionOpsを渡さないことが条件）。詳細は4節 | `src/core/event_input.zig:162`、`src/core/event_input.zig:163` |
| `engine` | `src/host_audio.zig:37` | ホストproducerと音consumerの共有Engine。ワーカーへ借用しない | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:101`、`src/host_audio.zig:110` |
| `next_pcm_id` | `src/host_audio.zig:38` | ホストPCMセッション管理 | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:111`、`src/host_audio.zig:200` |
| `state` | `src/host_audio.zig:39` | ホスト音起動・停止管理 | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:95`、`src/host_audio.zig:98` |
| `device_open` | `src/host_audio.zig:40` | 音backendがatomic印を更新し、ホストが照会する | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:115`、`src/host_audio.zig:116` |
| `stop_requested` | `src/host_audio.zig:41` | ホストがatomicで停止要求を書き、音consumerが読む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:106`、`src/host_audio.zig:165` |
| `thread_exited` | `src/host_audio.zig:42` | 音consumerがatomicで終了を通知し、ホストが読む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:57`、`src/host_audio.zig:64` |
| `cleanup_ok` | `src/host_audio.zig:43` | 音consumerの後始末結果をatomicでホストへ通知する | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:55`、`src/host_audio.zig:62` |
| `terminal_cleanup_failure` | `src/host_audio.zig:44` | ホスト音終了管理 | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:109`、`src/host_audio.zig:147` |
| `windows_thread` | `src/host_audio.zig:45` | ホストによる音スレッドhandle管理 | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:169`、`src/host_audio.zig:179` |
| `posix_handle` | `src/host_audio.zig:46` | ホストによる音スレッドhandle管理 | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:169`、`src/host_audio.zig:182` |
| `slots` | `src/host_directories.zig:12` | ホストディレクトリ管理 | file_opsのdirectory callback経由 | 否（file_opsなし・ファイル禁止） | `src/host_directories.zig:24`、`src/host_directories.zig:48` |
| `next_id` | `src/host_directories.zig:14` | ホストディレクトリ管理 | file_opsのdirectory callback経由 | 否（file_opsなし・ファイル禁止） | `src/host_directories.zig:51`、`src/host_directories.zig:84` |
| `until` | `src/host_display_budget.zig:9` | ホスト表示管理。初期表示探索で共有する表示予算の期限 | display_budget_fnのscopeで設定し、active/deadline/expired/remaining/cleanupDeadlineから参照 | 否（UI禁止） | `src/host_display_budget.zig:19`、`src/host_display_budget.zig:23`、`src/host_display_budget.zig:28`、`src/host_display_budget.zig:32`、`src/host_display_budget.zig:36`、`src/host_display_budget.zig:40` |
| `executable_path` | `src/host_display_macos.zig:58` | ホスト表示管理。macOSプローブ子との起動情報を含む | display_budget_fn/displays_fn/window表示経由＋起動情報設定は直接 | 否（UI禁止） | `src/host_display_macos.zig:63`、`src/host_display_macos.zig:237` |
| `environment` | `src/host_display_macos.zig:59` | ホスト表示管理。macOSプローブ子との起動情報を含む | display_budget_fn/displays_fn/window表示経由＋起動情報設定は直接 | 否（UI禁止） | `src/host_display_macos.zig:64`、`src/host_display_macos.zig:239` |
| `parent_ready` | `src/host_display_macos.zig:60` | ホスト表示管理。macOSプローブ子との起動情報を含む | display_budget_fn/displays_fn/window表示経由＋起動情報設定は直接 | 否（UI禁止） | `src/host_display_macos.zig:65`、`src/host_display_macos.zig:72` |
| `slots` | `src/host_evdev.zig:15` | ホストgamepad管理 | gamepad_ops経由。evdevはホストbackendから直接 | 否（UI・機器入力禁止） | `src/host_evdev.zig:69`、`src/host_evdev.zig:78` |
| `next_id` | `src/host_evdev.zig:16` | ホストgamepad管理 | gamepad_ops経由。evdevはホストbackendから直接 | 否（UI・機器入力禁止） | `src/host_evdev.zig:113`、`src/host_evdev.zig:114` |
| `next_scan` | `src/host_evdev.zig:17` | ホストgamepad管理 | gamepad_ops経由。evdevはホストbackendから直接 | 否（UI・機器入力禁止） | `src/host_evdev.zig:70`、`src/host_evdev.zig:185` |
| `denied` | `src/host_evdev.zig:18` | ホストgamepad管理 | gamepad_ops経由。evdevはホストbackendから直接 | 否（UI・機器入力禁止） | `src/host_evdev.zig:73`、`src/host_evdev.zig:101` |
| `denied_once` | `src/host_evdev.zig:19` | ホストgamepad管理 | gamepad_ops経由。evdevはホストbackendから直接 | 否（UI・機器入力禁止） | `src/host_evdev.zig:86`、`src/host_evdev.zig:90` |
| `directory_present` | `src/host_evdev.zig:20` | ホストgamepad管理 | gamepad_ops経由。evdevはホストbackendから直接 | 否（UI・機器入力禁止） | `src/host_evdev.zig:74`、`src/host_evdev.zig:202` |
| `library` | `src/host_gamepad.zig:77` | ホストgamepad管理 | gamepad_ops経由。evdevはホストbackendから直接 | 否（UI・機器入力禁止） | `src/host_gamepad.zig:85`、`src/host_gamepad.zig:100` |
| `api` | `src/host_gamepad.zig:78` | ホストgamepad管理 | gamepad_ops経由。evdevはホストbackendから直接 | 否（UI・機器入力禁止） | `src/host_gamepad.zig:88`、`src/host_gamepad.zig:93` |
| `opened` | `src/host_gamepad.zig:79` | ホストgamepad管理 | gamepad_ops経由。evdevはホストbackendから直接 | 否（UI・機器入力禁止） | `src/host_gamepad.zig:111`、`src/host_gamepad.zig:168` |
| `input_is_terminal` | `src/host_input.zig:20` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:40`、`src/host_input.zig:43` |
| `output_is_terminal` | `src/host_input.zig:21` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:303` |
| `flush_output` | `src/host_input.zig:23` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:108`、`src/host_input.zig:304` |
| `before_mode_change` | `src/host_input.zig:26` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:38`、`src/host_input.zig:41` |
| `mode_generation` | `src/host_input.zig:30` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:32`、`src/host_input.zig:183` |
| `raw` | `src/host_input.zig:65` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:37`、`src/host_input.zig:39` |
| `standard_keyboard` | `src/host_input.zig:66` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:232`、`src/host_input.zig:264` |
| `modes` | `src/host_input.zig:68` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:81`、`src/host_input.zig:82` |
| `presentation_changed` | `src/host_input.zig:69` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:109` |
| `presentation_error` | `src/host_input.zig:70` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:72`、`src/host_input.zig:73` |
| `restarted` | `src/host_input.zig:128` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:207`、`src/host_input.zig:208` |
| `standard_seen_generation` | `src/host_input.zig:129` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:183`、`src/host_input.zig:234` |
| `queued` | `src/host_input.zig:133` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:138`、`src/host_input.zig:139` |
| `queued_head` | `src/host_input.zig:134` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:139`、`src/host_input.zig:184` |
| `queued_len` | `src/host_input.zig:135` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:138`、`src/host_input.zig:139` |
| `execution_captured` | `src/host_input.zig:144` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:171`、`src/host_input.zig:324` |
| `cursor_unanswered` | `src/host_input.zig:311` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:87`、`src/host_input.zig:298` |
| `shared` | `src/host_process.zig:32` | ホストTcl/プロセス管理 | process_start/write/read/stop callback経由＋回収処理から直接 | 否（Tcl・プロセス禁止） | `src/host_process.zig:35`、`src/host_process.zig:57` |
| `shared_id` | `src/host_process.zig:33` | ホストTcl/プロセス管理 | process_start/write/read/stop callback経由＋回収処理から直接 | 否（Tcl・プロセス禁止） | `src/host_process.zig:38`、`src/host_process.zig:48` |
| `pending` | `src/host_resize.zig:5` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_resize.zig:7`、`src/host_resize.zig:10` |
| `identities` | `src/host_runtime.zig:21` | ホストスレッド。Runtime生成時のID発行 | 直接：Runtime.init/initWith。Writer callbackではない | 否（TaskManagerがホスト側で作成する必要がある） | `src/host_runtime.zig:35`、`src/host_runtime.zig:40` |
| `process_owner` | `src/host_signal_broker.zig:7` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_signal_broker.zig:26`、`src/host_signal_broker.zig:37` |
| `fallback` | `src/host_signal_broker.zig:68` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:289`、`src/host_wait.zig:301`、`src/host_wait.zig:350`、`src/host_wait.zig:380` |
| `active` | `src/host_wait.zig:13` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:360`、`src/host_wait.zig:361` |
| `interrupted` | `src/host_wait.zig:14` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:78`、`src/host_wait.zig:110` |
| `accepting_interrupts` | `src/host_wait.zig:15` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:72`、`src/host_wait.zig:77` |
| `native_scope` | `src/host_wait.zig:221` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:239` |
| `recovery_broker` | `src/host_wait.zig:222` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:225`、`src/host_wait.zig:227` |
| `input_depth` | `src/host_wait.zig:255` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:288`、`src/host_wait.zig:289` |
| `input_ticket` | `src/host_wait.zig:256` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:289`、`src/host_wait.zig:299` |
| `execution_depth` | `src/host_wait.zig:257` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:240`、`src/host_wait.zig:262` |
| `execution_machine` | `src/host_wait.zig:258` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:262`、`src/host_wait.zig:266` |
| `execution_poll` | `src/host_wait.zig:259` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:267`、`src/host_wait.zig:274` |
| `physical_state` | `src/host_window_linux.zig:5` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:9`、`src/host_window_linux.zig:98` |
| `guard` | `src/host_window_linux.zig:22` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:242`、`src/host_window_linux.zig:245` |
| `stop` | `src/host_window_linux.zig:23` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:289`、`src/host_window_linux.zig:310` |
| `running` | `src/host_window_linux.zig:24` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:278`、`src/host_window_linux.zig:289` |
| `abandoned` | `src/host_window_linux.zig:26` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:278`、`src/host_window_linux.zig:311` |
| `thread` | `src/host_window_linux.zig:27` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:299`、`src/host_window_linux.zig:301` |
| `status` | `src/host_window_linux.zig:28` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:300`、`src/host_window_linux.zig:302` |
| `start_deadline` | `src/host_window_linux.zig:29` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:314`、`src/host_window_linux.zig:343` |
| `mailbox` | `src/host_window_linux.zig:30` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:253`、`src/host_window_linux.zig:254` |
| `keys` | `src/host_window_linux.zig:31` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:378`、`src/host_window_linux.zig:384` |
| `key_head` | `src/host_window_linux.zig:32` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:378`、`src/host_window_linux.zig:384` |
| `key_count` | `src/host_window_linux.zig:33` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:377`、`src/host_window_linux.zig:385` |
| `down` | `src/host_window_linux.zig:34` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:97`、`src/host_window_linux.zig:260` |
| `told` | `src/host_window_linux.zig:35` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:379`、`src/host_window_linux.zig:380` |
| `mouse_queue` | `src/host_window_linux.zig:36` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:397`、`src/host_window_linux.zig:398` |
| `mouse_head` | `src/host_window_linux.zig:37` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:397`、`src/host_window_linux.zig:398` |
| `mouse_count` | `src/host_window_linux.zig:38` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:396`、`src/host_window_linux.zig:399` |
| `mouse_latest` | `src/host_window_linux.zig:39` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:99`、`src/host_window_linux.zig:261` |
| `mouse_dirty` | `src/host_window_linux.zig:40` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:100`、`src/host_window_linux.zig:262` |
| `preedit` | `src/host_window_linux.zig:41` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:75`、`src/host_window_linux.zig:76` |
| `preedit_len` | `src/host_window_linux.zig:42` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:74`、`src/host_window_linux.zig:75` |
| `caret` | `src/host_window_linux.zig:44` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:82`、`src/host_window_linux.zig:83` |
| `caret_dirty` | `src/host_window_linux.zig:45` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:84`、`src/host_window_linux.zig:642` |
| `fullscreen_wanted` | `src/host_window_linux.zig:48` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:56`、`src/host_window_linux.zig:57` |
| `fullscreen_dirty` | `src/host_window_linux.zig:49` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:58`、`src/host_window_linux.zig:750` |
| `cursor_visible` | `src/host_window_linux.zig:50` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:66`、`src/host_window_linux.zig:67` |
| `cursor_dirty` | `src/host_window_linux.zig:51` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:68`、`src/host_window_linux.zig:753` |
| `shared` | `src/host_window_linux.zig:108` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:131`、`src/host_window_linux.zig:160` |
| `shared_origin` | `src/host_window_linux.zig:109` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:226`、`src/host_window_linux.zig:1311` |
| `shared_image` | `src/host_window_linux.zig:113` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:215`、`src/host_window_linux.zig:238` |
| `fit_mode` | `src/host_window_linux.zig:117` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:198`、`src/host_window_linux.zig:215` |
| `smooth_on` | `src/host_window_linux.zig:118` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:206`、`src/host_window_linux.zig:1434` |
| `layout_dirty` | `src/host_window_linux.zig:119` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:199`、`src/host_window_linux.zig:207` |
| `keep_open` | `src/host_window_linux.zig:124` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:132`、`src/host_window_linux.zig:154` |
| `close_unseen` | `src/host_window_linux.zig:125` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:132`、`src/host_window_linux.zig:133` |
| `place_monitor` | `src/host_window_linux.zig:183` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:190`、`src/host_window_linux.zig:752` |
| `place_dirty` | `src/host_window_linux.zig:184` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_linux.zig:191`、`src/host_window_linux.zig:752` |
| `physical_state` | `src/host_window_macos.zig:13` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:24`、`src/host_window_macos.zig:544` |
| `physical_receiver` | `src/host_window_macos.zig:14` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:19`、`src/host_window_macos.zig:21` |
| `send_size_to_id` | `src/host_window_macos.zig:80` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1457`、`src/host_window_macos.zig:2339` |
| `send_image_hot_spot` | `src/host_window_macos.zig:81` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1458`、`src/host_window_macos.zig:2340` |
| `send_rect_cursor` | `src/host_window_macos.zig:82` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1473`、`src/host_window_macos.zig:2341` |
| `did_draw` | `src/host_window_macos.zig:103` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1072`、`src/host_window_macos.zig:2454` |
| `did_close` | `src/host_window_macos.zig:104` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1479`、`src/host_window_macos.zig:1496` |
| `active_app` | `src/host_window_macos.zig:105` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1367`、`src/host_window_macos.zig:1482` |
| `stdout_lock` | `src/host_window_macos.zig:106` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1800`、`src/host_window_macos.zig:1801` |
| `active_view` | `src/host_window_macos.zig:107` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1073`、`src/host_window_macos.zig:1412` |
| `active_window` | `src/host_window_macos.zig:108` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1342`、`src/host_window_macos.zig:1411` |
| `selector_register` | `src/host_window_macos.zig:109` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1074`、`src/host_window_macos.zig:1077` |
| `send_void1` | `src/host_window_macos.zig:110` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1348`、`src/host_window_macos.zig:1372` |
| `send_id1` | `src/host_window_macos.zig:111` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1368`、`src/host_window_macos.zig:1402` |
| `send_bool1` | `src/host_window_macos.zig:112` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1367`、`src/host_window_macos.zig:2054` |
| `send_bool0` | `src/host_window_macos.zig:113` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1896`、`src/host_window_macos.zig:1897` |
| `send_id_index` | `src/host_window_macos.zig:114` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1383`、`src/host_window_macos.zig:2317` |
| `send_range0` | `src/host_window_macos.zig:115` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:2301` |
| `send_usize0` | `src/host_window_macos.zig:116` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1334`、`src/host_window_macos.zig:1381` |
| `send_keycode` | `src/host_window_macos.zig:117` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1626`、`src/host_window_macos.zig:1690` |
| `send_utf8` | `src/host_window_macos.zig:118` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1404`、`src/host_window_macos.zig:1572` |
| `send_is_kind` | `src/host_window_macos.zig:119` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1554`、`src/host_window_macos.zig:1655` |
| `current_hardware_key` | `src/host_window_macos.zig:120` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1648`、`src/host_window_macos.zig:1650` |
| `send_double0` | `src/host_window_macos.zig:121` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1729`、`src/host_window_macos.zig:2319` |
| `send_point0` | `src/host_window_macos.zig:122` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1936`、`src/host_window_macos.zig:2325` |
| `send_point0_stret` | `src/host_window_macos.zig:123` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1933`、`src/host_window_macos.zig:2321` |
| `send_point_from_view` | `src/host_window_macos.zig:124` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1945`、`src/host_window_macos.zig:2326` |
| `send_point_transform` | `src/host_window_macos.zig:125` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1954`、`src/host_window_macos.zig:2327` |
| `send_point_from_view_stret` | `src/host_window_macos.zig:126` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1942`、`src/host_window_macos.zig:2322` |
| `send_point_transform_stret` | `src/host_window_macos.zig:127` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1951`、`src/host_window_macos.zig:2323` |
| `send_other_event` | `src/host_window_macos.zig:128` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:2033`、`src/host_window_macos.zig:2336` |
| `post_event` | `src/host_window_macos.zig:129` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:2034`、`src/host_window_macos.zig:2343` |
| `dispatch_async` | `src/host_window_macos.zig:130` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:2108`、`src/host_window_macos.zig:2358` |
| `dispatch_after` | `src/host_window_macos.zig:133` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1355`、`src/host_window_macos.zig:2359` |
| `dispatch_time` | `src/host_window_macos.zig:134` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1355`、`src/host_window_macos.zig:2360` |
| `main_queue` | `src/host_window_macos.zig:135` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1357`、`src/host_window_macos.zig:2108` |
| `rect_fill` | `src/host_window_macos.zig:136` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1079`、`src/host_window_macos.zig:2344` |
| `executable_path` | `src/host_window_macos.zig:137` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:470`、`src/host_window_macos.zig:905` |
| `environment` | `src/host_window_macos.zig:138` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:471`、`src/host_window_macos.zig:907` |
| `parent_ready` | `src/host_window_macos.zig:139` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:472`、`src/host_window_macos.zig:856` |
| `child_process` | `src/host_window_macos.zig:140` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:19`、`src/host_window_macos.zig:271` |
| `display_request_sequence` | `src/host_window_macos.zig:141` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:308`、`src/host_window_macos.zig:309` |
| `display_response_sequence` | `src/host_window_macos.zig:142` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:311`、`src/host_window_macos.zig:316` |
| `display_response_id` | `src/host_window_macos.zig:143` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:322`、`src/host_window_macos.zig:323` |
| `window_was_ready` | `src/host_window_macos.zig:144` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:496`、`src/host_window_macos.zig:956` |
| `frame_sequence` | `src/host_window_macos.zig:145` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:555`、`src/host_window_macos.zig:557` |
| `child_said_closed` | `src/host_window_macos.zig:147` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:498`、`src/host_window_macos.zig:517` |
| `held_keys` | `src/host_window_macos.zig:149` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:548`、`src/host_window_macos.zig:748` |
| `queued_buttons` | `src/host_window_macos.zig:151` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:737`、`src/host_window_macos.zig:742` |
| `input_queue` | `src/host_window_macos.zig:152` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:631`、`src/host_window_macos.zig:632` |
| `input_head` | `src/host_window_macos.zig:153` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:631`、`src/host_window_macos.zig:632` |
| `input_count` | `src/host_window_macos.zig:154` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:630`、`src/host_window_macos.zig:633` |
| `input_line` | `src/host_window_macos.zig:155` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:620`、`src/host_window_macos.zig:622` |
| `window_size` | `src/host_window_macos.zig:158` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:333`、`src/host_window_macos.zig:334` |
| `parent_fit` | `src/host_window_macos.zig:162` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:344`、`src/host_window_macos.zig:399` |
| `parent_smooth` | `src/host_window_macos.zig:163` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:390`、`src/host_window_macos.zig:946` |
| `parent_place` | `src/host_window_macos.zig:166` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:378`、`src/host_window_macos.zig:937` |
| `parent_keep_open` | `src/host_window_macos.zig:169` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:357`、`src/host_window_macos.zig:358` |
| `close_pending` | `src/host_window_macos.zig:170` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:358`、`src/host_window_macos.zig:362` |
| `frames_shown` | `src/host_window_macos.zig:175` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:340`、`src/host_window_macos.zig:580` |
| `frames_painted` | `src/host_window_macos.zig:176` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:341`、`src/host_window_macos.zig:589` |
| `last_accepted_sequence` | `src/host_window_macos.zig:177` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:581`、`src/host_window_macos.zig:586` |
| `shown_image` | `src/host_window_macos.zig:178` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:343`、`src/host_window_macos.zig:344` |
| `input_line_used` | `src/host_window_macos.zig:179` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:546`、`src/host_window_macos.zig:620` |
| `preedit_buffer` | `src/host_window_macos.zig:180` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:258`、`src/host_window_macos.zig:787` |
| `preedit_length` | `src/host_window_macos.zig:181` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:257`、`src/host_window_macos.zig:547` |
| `ime_caret` | `src/host_window_macos.zig:182` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:294`、`src/host_window_macos.zig:295` |
| `fullscreen_wanted` | `src/host_window_macos.zig:185` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:269`、`src/host_window_macos.zig:270` |
| `cursor_visible` | `src/host_window_macos.zig:186` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:280`、`src/host_window_macos.zig:281` |
| `fullscreen_desired` | `src/host_window_macos.zig:190` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1300`、`src/host_window_macos.zig:1301` |
| `fullscreen_transitioning` | `src/host_window_macos.zig:191` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:208`、`src/host_window_macos.zig:1283` |
| `transition_by_sigma` | `src/host_window_macos.zig:194` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1282`、`src/host_window_macos.zig:1287` |
| `asked_during_transition` | `src/host_window_macos.zig:197` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1282`、`src/host_window_macos.zig:1287` |
| `pending_place` | `src/host_window_macos.zig:201` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1343`、`src/host_window_macos.zig:1361` |
| `place_after_exit` | `src/host_window_macos.zig:203` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1347`、`src/host_window_macos.zig:1353` |
| `child_cursor_visible` | `src/host_window_macos.zig:211` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1448`、`src/host_window_macos.zig:1472` |
| `blank_cursor` | `src/host_window_macos.zig:212` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1456`、`src/host_window_macos.zig:1467` |
| `pressed_keys` | `src/host_window_macos.zig:213` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1627`、`src/host_window_macos.zig:1640` |
| `mouse_buttons` | `src/host_window_macos.zig:214` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1758`、`src/host_window_macos.zig:1761` |
| `sent_buttons` | `src/host_window_macos.zig:216` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1769`、`src/host_window_macos.zig:1770` |
| `wheel_remainder` | `src/host_window_macos.zig:217` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1729`、`src/host_window_macos.zig:1731` |
| `last_mouse_x` | `src/host_window_macos.zig:218` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1754`、`src/host_window_macos.zig:1755` |
| `last_mouse_y` | `src/host_window_macos.zig:219` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1754`、`src/host_window_macos.zig:1756` |
| `last_mouse_event_ns` | `src/host_window_macos.zig:220` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1761`、`src/host_window_macos.zig:1762` |
| `frame_pixels` | `src/host_window_macos.zig:221` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1080`、`src/host_window_macos.zig:1082` |
| `frame_width` | `src/host_window_macos.zig:222` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1081`、`src/host_window_macos.zig:1082` |
| `frame_height` | `src/host_window_macos.zig:223` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1081`、`src/host_window_macos.zig:1082` |
| `last_frame_size` | `src/host_window_macos.zig:224` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:2047`、`src/host_window_macos.zig:2048` |
| `last_requested_size` | `src/host_window_macos.zig:225` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1414`、`src/host_window_macos.zig:1417` |
| `child_fit` | `src/host_window_macos.zig:228` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1081`、`src/host_window_macos.zig:1596` |
| `child_smooth` | `src/host_window_macos.zig:232` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1258`、`src/host_window_macos.zig:2070` |
| `child_frame_sequence` | `src/host_window_macos.zig:235` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1085`、`src/host_window_macos.zig:1086` |
| `child_painted_sequence` | `src/host_window_macos.zig:236` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1085`、`src/host_window_macos.zig:1086` |
| `child_keep_open` | `src/host_window_macos.zig:240` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1919`、`src/host_window_macos.zig:2168` |
| `child_close_unseen` | `src/host_window_macos.zig:241` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1919`、`src/host_window_macos.zig:1920` |
| `smoother` | `src/host_window_macos.zig:242` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1258` |
| `send_size1` | `src/host_window_macos.zig:243` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1416`、`src/host_window_macos.zig:2303` |
| `send_size_return` | `src/host_window_macos.zig:244` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1185`、`src/host_window_macos.zig:2313` |
| `send_size_stret` | `src/host_window_macos.zig:245` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1182`、`src/host_window_macos.zig:2308` |
| `send_rect0` | `src/host_window_macos.zig:246` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1145`、`src/host_window_macos.zig:2310` |
| `send_rect_stret` | `src/host_window_macos.zig:247` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1142`、`src/host_window_macos.zig:2305` |
| `send_rect1` | `src/host_window_macos.zig:248` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1155`、`src/host_window_macos.zig:1175` |
| `send_rect1_stret` | `src/host_window_macos.zig:249` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1152`、`src/host_window_macos.zig:1172` |
| `send_rect_to_view` | `src/host_window_macos.zig:250` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1165`、`src/host_window_macos.zig:2312` |
| `send_rect_to_view_stret` | `src/host_window_macos.zig:251` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1162`、`src/host_window_macos.zig:2307` |
| `send_set_frame` | `src/host_window_macos.zig:252` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1391`、`src/host_window_macos.zig:1433` |
| `marked_text` | `src/host_window_macos.zig:253` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1532`、`src/host_window_macos.zig:1533` |
| `marked_selection` | `src/host_window_macos.zig:254` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1535`、`src/host_window_macos.zig:1549` |
| `cg_provider` | `src/host_window_macos.zig:1194` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1262`、`src/host_window_macos.zig:2347` |
| `cg_color_space` | `src/host_window_macos.zig:1195` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1264`、`src/host_window_macos.zig:2348` |
| `cg_image` | `src/host_window_macos.zig:1196` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1267`、`src/host_window_macos.zig:2349` |
| `cg_draw` | `src/host_window_macos.zig:1197` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1270`、`src/host_window_macos.zig:2350` |
| `cg_interpolation` | `src/host_window_macos.zig:1198` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1269`、`src/host_window_macos.zig:2351` |
| `cg_release` | `src/host_window_macos.zig:1199` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1268`、`src/host_window_macos.zig:2352` |
| `cg_provider_release` | `src/host_window_macos.zig:1200` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1263`、`src/host_window_macos.zig:2355` |
| `cg_color_release` | `src/host_window_macos.zig:1201` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1265`、`src/host_window_macos.zig:2354` |
| `send_id0_global` | `src/host_window_macos.zig:1202` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1260`、`src/host_window_macos.zig:1261` |
| `send_string_from_utf8` | `src/host_window_macos.zig:1203` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1401`、`src/host_window_macos.zig:2330` |
| `objc_get_class` | `src/host_window_macos.zig:1273` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1076`、`src/host_window_macos.zig:1259` |
| `send_color` | `src/host_window_macos.zig:1274` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1077`、`src/host_window_macos.zig:2335` |
| `send_void0` | `src/host_window_macos.zig:1275` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1078`、`src/host_window_macos.zig:1464` |
| `kept_input` | `src/host_window_macos.zig:1779` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1787`、`src/host_window_macos.zig:1788` |
| `kept_input_length` | `src/host_window_macos.zig:1780` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1784`、`src/host_window_macos.zig:1787` |
| `physical_sender` | `src/host_window_macos.zig:1813` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1837`、`src/host_window_macos.zig:1838` |
| `physical_guard` | `src/host_window_macos.zig:1814` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1835`、`src/host_window_macos.zig:1836` |
| `physical_sync_requested` | `src/host_window_macos.zig:1815` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1837`、`src/host_window_macos.zig:2144` |
| `send_super_event` | `src/host_window_macos.zig:1818` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1868`、`src/host_window_macos.zig:2370` |
| `application_superclass` | `src/host_window_macos.zig:1819` | ホストwindow管理＋UI/入力処理。macOSには親子プロセス双方の変数がある | window/IME/physical/input callback経由＋UIイベント・子通信の直接操作 | 否（入力・UI禁止） | `src/host_window_macos.zig:1867`、`src/host_window_macos.zig:2369` |
| `saved_output_code_page` | `src/main.zig:189` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:198`、`src/main.zig:200` |
| `file_wake` | `src/main.zig:407` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:1164`、`src/main.zig:1166` |
| `stdin_reader` | `src/main.zig:408` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:1158`、`src/main.zig:1293` |
| `stdout_writer` | `src/main.zig:409` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:1152`、`src/main.zig:1502` |
| `stderr_writer` | `src/main.zig:410` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:1155`、`src/main.zig:1503` |
| `output_ior` | `src/main.zig:411` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:908`、`src/main.zig:996` |
| `output_nonblocking` | `src/main.zig:412` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:998`、`src/main.zig:1597` |
| `closing_all_files` | `src/main.zig:413` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:706`、`src/main.zig:727` |
| `deferred_packets` | `src/main.zig:414` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:1403`、`src/main.zig:1409` |
| `deferred_head` | `src/main.zig:415` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:1409`、`src/main.zig:3253` |
| `deferred_length` | `src/main.zig:416` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:1403`、`src/main.zig:1409` |
| `file_slots` | `src/main.zig:429` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:437`、`src/main.zig:438` |
| `stdin_eof` | `src/main.zig:430` | ホストI/O管理＋stdin/stdout/stderrのI/O補助処理 | file_ops/入力/write_fn経由＋ホスト初期化・回収から直接 | 否（専用出力・入力/ファイル禁止） | `src/main.zig:1201`、`src/main.zig:1215` |
| `processes` | `src/main.zig:1982` | ホストプロセス・音の回収管理 | process_ops/audio関連callback経由＋終了処理から直接 | 否（プロセス・音禁止） | `src/main.zig:1946`、`src/main.zig:1952` |
| `next_process_id` | `src/main.zig:1983` | ホストプロセス・音の回収管理 | process_ops/audio関連callback経由＋終了処理から直接 | 否（プロセス・音禁止） | `src/main.zig:2033`、`src/main.zig:2105` |
| `process_cleanup_error` | `src/main.zig:1984` | ホストプロセス・音の回収管理 | process_ops/audio関連callback経由＋終了処理から直接 | 否（プロセス・音禁止） | `src/main.zig:2111`、`src/main.zig:3609` |
| `audio_cleanup_failed` | `src/main.zig:1985` | ホストプロセス・音の回収管理 | process_ops/audio関連callback経由＋終了処理から直接 | 否（プロセス・音禁止） | `src/main.zig:3610`、`src/main.zig:3617` |
| `lint_findings` | `src/main.zig:2565` | ホスト診断管理 | log_fn・lint/CLI診断経由 | 否（log_fnなし、診断は専用context） | `src/main.zig:3622`、`src/main.zig:3817` |
| `debug_log_file` | `src/main.zig:2568` | ホスト診断管理 | log_fn・lint/CLI診断経由 | 否（log_fnなし、診断は専用context） | `src/main.zig:2573`、`src/main.zig:3794` |
| `output_buffer` | `src/main.zig:3055` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:1583`、`src/main.zig:1585` |
| `output_used` | `src/main.zig:3056` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:994`、`src/main.zig:997` |
| `output_is_terminal` | `src/main.zig:3058` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:172`、`src/main.zig:195` |
| `output_cursor` | `src/main.zig:3060` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:390`、`src/main.zig:681` |
| `stderr_shares_output` | `src/main.zig:3061` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:2953`、`src/main.zig:2956` |
| `lookahead` | `src/main.zig:3134` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:3139`、`src/main.zig:3142` |
| `unread_bytes` | `src/main.zig:3135` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:3142`、`src/main.zig:3294` |
| `unread_count` | `src/main.zig:3136` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:3140`、`src/main.zig:3141` |
| `execution_replay_workspace` | `src/main.zig:3391` | プロセス所有・ホストスレッド専用のreplay作業領域 | execution_ops/audio_scope_opsのbeginがexecutionRawPollを登録し、pollから参照・更新する。変数への参照はexecutionRawPoll内のみ | 否（両操作口にメインのExecutionOpsを渡さない） | `src/main.zig:3344`、`src/main.zig:3350`、`src/main.zig:3353`、`src/host_wait.zig:267`、`src/host_wait.zig:274`、`src/main.zig:3397`、`src/main.zig:3752` |
| `input_failure` | `src/main.zig:3439` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:2268`、`src/main.zig:2351` |
| `line_editing` | `src/main.zig:3526` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:3539`、`src/main.zig:3557` |
| `line_history` | `src/main.zig:3527` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:3944` |

### 3.2 255件に含まれないコンテナ内の共有変数

コンテナの `var` はインスタンスフィールドではなく、Stateごとの所有にならない。行頭検索だけを全共有状態監査の完了条件にできない。以下は宣言範囲をソース照合して抽出した追加表である。関数ローカル・comptimeで計算したローカル・テスト専用変数は含めない。externの環境変数はOS/Cの借用状態として分ける。

| 変数 | 宣言 | 所有・アクセス主体 | アクセス経路 | 初期許可集合からの到達 | 主な同一ファイル参照 |
|---|---|---|---|---|---|
| `windows.device` | `src/host_audio.zig:383` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:408`、`src/host_audio.zig:413` |
| `windows.event` | `src/host_audio.zig:384` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:81`、`src/host_audio.zig:395` |
| `windows.samples` | `src/host_audio.zig:385` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:410`、`src/host_audio.zig:440` |
| `windows.headers` | `src/host_audio.zig:386` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:410`、`src/host_audio.zig:424` |
| `windows.prepared` | `src/host_audio.zig:387` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:411`、`src/host_audio.zig:414` |
| `linux.backend` | `src/host_audio.zig:497` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:127`、`src/host_audio.zig:132` |
| `linux.pulse` | `src/host_audio.zig:504` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:497`、`src/host_audio.zig:533` |
| `linux.pulse_write` | `src/host_audio.zig:505` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:556`、`src/host_audio.zig:759` |
| `linux.pulse_free` | `src/host_audio.zig:507` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:557`、`src/host_audio.zig:594` |
| `linux.pulse_lib` | `src/host_audio.zig:508` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:562`、`src/host_audio.zig:651` |
| `linux.pcm` | `src/host_audio.zig:515` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:113`、`src/host_audio.zig:133` |
| `linux.alsa_write` | `src/host_audio.zig:516` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:134`、`src/host_audio.zig:574` |
| `linux.alsa_recover` | `src/host_audio.zig:517` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:136`、`src/host_audio.zig:575` |
| `linux.alsa_drop` | `src/host_audio.zig:521` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:137`、`src/host_audio.zig:576` |
| `linux.alsa_close` | `src/host_audio.zig:522` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:138`、`src/host_audio.zig:577` |
| `linux.alsa_wait` | `src/host_audio.zig:523` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:135`、`src/host_audio.zig:578` |
| `linux.alsa_lib` | `src/host_audio.zig:524` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:582`、`src/host_audio.zig:655` |
| `linux.pipe_fd` | `src/host_audio.zig:527` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:607`、`src/host_audio.zig:608` |
| `linux.pipe_pid` | `src/host_audio.zig:528` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:611`、`src/host_audio.zig:615` |
| `macos.queue` | `src/host_audio.zig:838` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:900`、`src/host_audio.zig:909` |
| `macos.buffers` | `src/host_audio.zig:839` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:907`、`src/host_audio.zig:935` |
| `macos.enqueue` | `src/host_audio.zig:840` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:883`、`src/host_audio.zig:923` |
| `macos.start_queue` | `src/host_audio.zig:841` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:884`、`src/host_audio.zig:940` |
| `macos.stop_queue` | `src/host_audio.zig:842` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:885`、`src/host_audio.zig:946` |
| `macos.dispose_queue` | `src/host_audio.zig:843` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:886`、`src/host_audio.zig:947` |
| `macos.framework_lib` | `src/host_audio.zig:844` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:901`、`src/host_audio.zig:953` |
| `macos.failed` | `src/host_audio.zig:846` | ホスト音管理＋音consumer/OS音callback。atomic印を介するものを含む | audio_fn/audio_device_fn/audio_wait_fn経由＋起動終了の直接操作 | 否（音禁止） | `src/host_audio.zig:39`、`src/host_audio.zig:98` |
| `win32.optional` | `src/host_display.zig:115` | ホスト表示管理 | displays_fn/window callback経由 | 否（UI禁止） | `src/host_display.zig:135` |
| `win32.optional_loaded` | `src/host_display.zig:116` | ホスト表示管理 | displays_fn/window callback経由 | 否（UI禁止） | `src/host_display.zig:135` |
| `gdi.dc` | `src/host_font.zig:105` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `gdi.bits` | `src/host_font.zig:106` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `gdi.font` | `src/host_font.zig:107` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.loaded` | `src/host_font.zig:217` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.ok` | `src/host_font.zig:218` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.string_create` | `src/host_font.zig:219` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.release` | `src/host_font.zig:220` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.compare` | `src/host_font.zig:221` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.array_count` | `src/host_font.zig:222` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.array_at` | `src/host_font.zig:223` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.create_font` | `src/host_font.zig:224` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.copy_postscript_name` | `src/host_font.zig:225` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.copy_family_name` | `src/host_font.zig:226` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.copy_full_name` | `src/host_font.zig:227` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.copy_localized_name` | `src/host_font.zig:228` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.ascent_of` | `src/host_font.zig:229` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.descent_of` | `src/host_font.zig:230` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.glyphs_for` | `src/host_font.zig:231` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.advances_for` | `src/host_font.zig:232` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.draw_glyphs` | `src/host_font.zig:233` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.family_names` | `src/host_font.zig:234` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.family_key` | `src/host_font.zig:235` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.full_key` | `src/host_font.zig:236` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.context` | `src/host_font.zig:237` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.pixels` | `src/host_font.zig:238` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.font` | `src/host_font.zig:240` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.ascent` | `src/host_font.zig:242` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `coretext.line_height` | `src/host_font.zig:243` | ホストfont管理（OS別backend） | system_font_fn/system_glyph_fn経由 | 否（UI禁止） | `src/core/graphics_font.zig:146`、`src/core/graphics_font.zig:195` |
| `posix.saved` | `src/host_input.zig:383` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:386`、`src/host_input.zig:387` |
| `windows.input` | `src/host_input.zig:515` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:37`、`src/host_input.zig:535` |
| `windows.saved_mode` | `src/host_input.zig:516` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:610`、`src/host_input.zig:613` |
| `windows.raw_mode` | `src/host_input.zig:517` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:613`、`src/host_input.zig:614` |
| `windows.pending` | `src/host_input.zig:519` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:37`、`src/host_input.zig:553` |
| `windows.pending_len` | `src/host_input.zig:520` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:553`、`src/host_input.zig:629` |
| `windows.high_surrogate` | `src/host_input.zig:521` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:554`、`src/host_input.zig:635` |
| `windows.down` | `src/host_input.zig:526` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:596`、`src/host_input.zig:597` |
| `windows.releasing` | `src/host_input.zig:527` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:637`、`src/host_input.zig:688` |
| `windows.after` | `src/host_input.zig:528` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:145`、`src/host_input.zig:198` |
| `windows.records` | `src/host_input.zig:531` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:196`、`src/host_input.zig:536` |
| `windows.record_head` | `src/host_input.zig:532` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:196`、`src/host_input.zig:543` |
| `windows.record_len` | `src/host_input.zig:533` | ホスト入力・端末管理 | 入力/端末/待機callback経由＋ホストmode管理から直接 | 否（入力・端末禁止） | `src/host_input.zig:536`、`src/host_input.zig:543` |
| `posix.saved` | `src/host_line.zig:541` | ホスト行編集 | read_fn/terminalReadから行編集、直接mode保存 | 否（入力禁止） | `src/host_line.zig:544` |
| `windows.to_program` | `src/host_process.zig:157` | ホストTcl/プロセス管理 | process_start/write/read/stop callback経由＋回収処理から直接 | 否（Tcl・プロセス禁止） | `src/host_process.zig:40`、`src/host_process.zig:43` |
| `windows.from_program` | `src/host_process.zig:158` | ホストTcl/プロセス管理 | process_start/write/read/stop callback経由＋回収処理から直接 | 否（Tcl・プロセス禁止） | `src/host_process.zig:41`、`src/host_process.zig:44` |
| `windows.script_name` | `src/host_process.zig:160` | ホストTcl/プロセス管理 | process_start/write/read/stop callback経由＋回収処理から直接 | 否（Tcl・プロセス禁止） | `src/host_process.zig:172`、`src/host_process.zig:173` |
| `posix.to_program` | `src/host_process.zig:404` | ホストTcl/プロセス管理 | process_start/write/read/stop callback経由＋回収処理から直接 | 否（Tcl・プロセス禁止） | `src/host_process.zig:40`、`src/host_process.zig:43` |
| `posix.from_program` | `src/host_process.zig:405` | ホストTcl/プロセス管理 | process_start/write/read/stop callback経由＋回収処理から直接 | 否（Tcl・プロセス禁止） | `src/host_process.zig:41`、`src/host_process.zig:44` |
| `posix.script_name` | `src/host_process.zig:407` | ホストTcl/プロセス管理 | process_start/write/read/stop callback経由＋回収処理から直接 | 否（Tcl・プロセス禁止） | `src/host_process.zig:160`、`src/host_process.zig:172` |
| `win.read_lock` | `src/host_wait.zig:27` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:31`、`src/host_wait.zig:34` |
| `win.read_thread` | `src/host_wait.zig:28` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:40`、`src/host_wait.zig:49` |
| `win.read_generation` | `src/host_wait.zig:29` | ホスト待機・scope管理＋OS信号/console通知。atomic印を含む | execution/audio scope・sleep・入力callback経由＋signal/resize処理から直接 | 否（ホストscopeを渡さず待機・入力禁止） | `src/host_wait.zig:44`、`src/host_wait.zig:48` |
| `win32.physical_state` | `src/host_window.zig:192` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.dpi` | `src/host_window.zig:320` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.dpi_loaded` | `src/host_window.zig:321` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.lock` | `src/host_window.zig:400` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.pixels` | `src/host_window.zig:401` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.width` | `src/host_window.zig:402` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.height` | `src/host_window.zig:403` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.requested` | `src/host_window.zig:405` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.window` | `src/host_window.zig:406` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.update_pending` | `src/host_window.zig:409` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.resize_pending` | `src/host_window.zig:411` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.keys` | `src/host_window.zig:416` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.key_head` | `src/host_window.zig:417` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.key_count` | `src/host_window.zig:418` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.high_surrogate` | `src/host_window.zig:419` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.interrupt_pending` | `src/host_window.zig:421` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.fullscreen_wanted` | `src/host_window.zig:424` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.fullscreen_on` | `src/host_window.zig:425` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.windowed_place` | `src/host_window.zig:426` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.windowed_dpi` | `src/host_window.zig:427` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.cursor_visible` | `src/host_window.zig:429` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.ime_caret` | `src/host_window.zig:433` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.ime_generation` | `src/host_window.zig:436` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.preedit` | `src/host_window.zig:437` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.preedit_len` | `src/host_window.zig:438` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.down` | `src/host_window.zig:444` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.told` | `src/host_window.zig:445` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.mouse_x` | `src/host_window.zig:446` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.mouse_y` | `src/host_window.zig:447` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.mouse_buttons` | `src/host_window.zig:448` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.mouse_changed` | `src/host_window.zig:449` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.mouse_queue` | `src/host_window.zig:454` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.mouse_head` | `src/host_window.zig:455` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.mouse_count` | `src/host_window.zig:456` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.queued_buttons` | `src/host_window.zig:457` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.wheel_rest` | `src/host_window.zig:458` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.client_size` | `src/host_window.zig:464` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.window_monitor` | `src/host_window.zig:465` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.window_changes` | `src/host_window.zig:466` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.window_focused` | `src/host_window.zig:470` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.window_minimized` | `src/host_window.zig:471` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.user_closes` | `src/host_window.zig:472` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.keep_open` | `src/host_window.zig:480` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.close_unseen` | `src/host_window.zig:481` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.thread` | `src/host_window.zig:593` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.class_registered` | `src/host_window.zig:594` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.broken` | `src/host_window.zig:596` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.start_timeout_ms` | `src/host_window.zig:598` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.started` | `src/host_window.zig:600` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.start` | `src/host_window.zig:608` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.frames_shown` | `src/host_window.zig:770` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.frames_painted` | `src/host_window.zig:771` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.painted_event` | `src/host_window.zig:772` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.Vsync.flush` | `src/host_window.zig:826` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.Vsync.loaded` | `src/host_window.zig:827` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.Vsync.request` | `src/host_window.zig:828` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.Vsync.done` | `src/host_window.zig:829` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.Vsync.worker` | `src/host_window.zig:830` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.Vsync.busy` | `src/host_window.zig:832` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.Vsync.result` | `src/host_window.zig:833` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.fit_mode` | `src/host_window.zig:960` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.place_monitor` | `src/host_window.zig:979` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.place_device` | `src/host_window.zig:980` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.restore_place_pending` | `src/host_window.zig:982` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.restore_size` | `src/host_window.zig:983` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.restore_dpi` | `src/host_window.zig:984` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.smooth_on` | `src/host_window.zig:1108` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.smooth` | `src/host_window.zig:1111` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.band` | `src/host_window.zig:1131` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.band_columns` | `src/host_window.zig:1132` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.band_failed` | `src/host_window.zig:1135` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `win32.mouse_client` | `src/host_window.zig:1169` | ホストwindow管理＋UIスレッド。Vsyncは専用補助スレッド | window/physical/IME/input callback経由＋イベントから直接 | 否（UI・入力禁止） | `src/host_window.zig:610`、`src/host_window.zig:825` |
| `utf8_console.read_input` | `src/main.zig:2166` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:2169`、`src/main.zig:2171` |
| `utf8_console.read_cancelled` | `src/main.zig:2167` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:2173`、`src/main.zig:2281` |
| `utf8_console.active` | `src/main.zig:2178` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:195`、`src/main.zig:1293` |
| `utf8_console.saved_output` | `src/main.zig:2179` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:2201`、`src/main.zig:2213` |
| `utf8_console.saved_input` | `src/main.zig:2180` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:2202`、`src/main.zig:2214` |
| `utf8_console.input` | `src/main.zig:2182` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:425`、`src/main.zig:438` |
| `utf8_console.bytes` | `src/main.zig:2188` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:52`、`src/main.zig:53` |
| `utf8_console.start` | `src/main.zig:2189` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:1304`、`src/main.zig:1530` |
| `utf8_console.end` | `src/main.zig:2190` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:717`、`src/main.zig:934` |
| `utf8_console.high_surrogate` | `src/main.zig:2191` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:2327`、`src/main.zig:2331` |
| `utf8_console.ended` | `src/main.zig:2192` | ホスト出力・入力・行編集管理 | write_fn/入力/read_fn/端末callback経由＋CLIから直接 | 否（専用出力・入力禁止） | `src/main.zig:1779`、`src/main.zig:1797` |

追加表は163宣言行・9ファイルである。直下表との和集合は418宣言行・20ファイルである。これは上記抽出条件の件数であり、Cライブラリ内部・OS内部の全状態数ではない。`src/host_audio.zig:479` の `linux.environ` はextern宣言であり、この合計には含めない。プロセス環境への参照なのでワーカーへ許可しない。

## 4. modern_depthの詳細

`modern_depth` は `pub var usize = 0` のプロセス内共有変数であり、State内のdecoderとは異なる（`src/core/event_input.zig:154`）。宣言・増加・defer減少・ホスト参照の4箇所を確認した（`src/core/event_input.zig:154`、`src/core/event_input.zig:162`、`src/core/event_input.zig:163`、`src/main.zig:3394`）。atomicまたはthreadlocalの宣言ではない。

`modern` は最初に入力リダイレクトを判定し、選択されていればFileOps.event_waitへ直接戻る。この分岐はdepthを更新しない。標準入力の場合はstandard_event_fnとstandard_clockの両方が必要であり、片方がなければ更新前にHostUnavailableで戻る。両方があればdepthを増やしてstandard.readを呼び、エラー経路を含めdeferで減らす（`src/core/event_input.zig:155`）。EKEY/EKEY?はstandard_event_fnの有無でmodernまたはlegacyへ分岐する（`src/core/event_input.zig:56`、`src/core/event_input.zig:72`）。

読取り側はexecution_ops/audio_scope_opsのpollから動く。両操作口には同じexecution_host_opsが設定され、そのbeginがhost_wait.beginExecutionへexecutionRawPollを渡してexecution_pollに登録し、pollがpollExecutionを通じて呼び出す（`src/main.zig:3344`、`src/main.zig:3350`、`src/main.zig:3353`、`src/main.zig:3752`、`src/host_wait.zig:267`、`src/host_wait.zig:274`）。

ホストのexecutionRawPollはcaptureExecutionの後、この値が0でなければdecoderのreplay検査を中断する。目的はsource callback実行中のdecoder再検査を避けることである。replay workspaceもプロセス所有・ホストスレッド専用と明記されている（`src/main.zig:3390`）。この値はワーカーの取消し深さや、すべてのVMの安全性を示す値ではない。

※推測：複数スレッドでmodernを許すと、非atomicの増減とホストの読取りが競合し、他VMのdepthがメインのreplayを抑止し得る。並行再現は未確認である。Stateのdecoderを別確保しただけではこの共有変数は分離されない。

初期案では入力語の静的・動的拒否に加え、standard_event_fn/standard_clock/file_opsをnullにするため、ワーカーからこの増減へ進ませない。読取り側の遮断には、execution_opsとaudio_scope_opsのどちらにもメインのExecutionOpsを渡さないことが必要である。入力callbackの遮断だけではpoll経由の共有値の読取りを防げない（`src/main.zig:3394`、`src/main.zig:3752`）。これは条件付きの遮断案であり、1351の実装単位での証明は未完了である。将来入力を許す場合はStateまたはホスト所有の入力scopeへdepthを移す設計判断が必要であり、atomic化だけでは「別VMのdepthがメインのreplayを抑止する」という意味の混同を解消しない。

## 5. image_restore.applyの後始末とStorage

restore/restoreFreshはどちらもPCM所有中（audio_pcm_handle != 0）を-528で拒否し、preflight.prepare成功後に同じapplyを呼ぶ。差はmemory_is_freshのみであり、後始末callbackを省略するフラグではない（`src/core/image_restore.zig:12`、`src/core/image_restore.zig:20`、`src/core/image_restore.zig:25`）。

| 処理 | 新規Storage＋State.init＋専用Writer | 再利用Storage／Stateの注意 | 根拠 |
|---|---|---|---|
| input・guard・アドレス登録・watchの無効化 | 専用Stateの値だけを更新する | wrap_guardを共有・借用したStateでは外部のGuardを変更し得る。停止確認後に専用Stateを再構築する必要がある | `src/core/image_restore.zig:26`、`src/core/words_value_extensions.zig:27` |
| sh_get_result=null | 旧論理ヒープへの参照を捨てる。新規Stateは空である | 古いアドレスを復元後にfreeしないための処理である。captureや他の非永続状態全体の初期化ではない | `src/core/image_restore.zig:34` |
| wordlist再構成、specialize、inline復元、debug情報更新 | 自身の辞書・コードを再構成する | 復元後に許可検査する。復元前の入口だけを検査して完了にしない | `src/core/image_restore.zig:78`、`src/core/image_restore.zig:84`、`src/core/image_restore.zig:86` |
| clearImage | 空画素のまま、builtin fontへ切り替える。ホストcallbackはない | framebufferを解放せず参照を捨てる。fontもkindをbuiltinにするだけでfont.bufferをfreeしない。再利用前に所有者が回収する必要がある | `src/core/image_restore.zig:103`、`src/core/words_graphics.zig:587`、`src/core/graphics_font.zig:78` |
| physical_key_ops.reset | nullなので呼ばれない。Storageの新旧とは無関係である | 非nullなら必ずcontextへresetする。メインのTrackerを借用するとメイン入力を変更するため不適合 | `src/core/image_restore.zig:104` |
| graphics_images.releaseAll | 全スロット空のためimage_free_fnを呼ばない | 非空slotごとにimage_free_fnを呼ぶ。nullなら画素解放なしで参照を消すため漏れる。専用所有の正しい解放callbackならメイン干渉は避けられるが、初期null Writerのまま非空を持つ状態は許容しない | `src/core/image_restore.zig:105`、`src/core/graphics_images.zig:317`、`src/core/graphics_images.zig:329` |
| tcl.forgetHeap | graphics有効時だけ呼ぶ。空のState内Tcl参照を捨てるのでホストTcl操作はない | result/error/event/partialの論理ヒープ参照を捨て、未読メッセージのskipを残す。partialがUならStateのTkキーを忘れる。process_stopを呼ばず、実行中のTcl子は停止しない | `src/core/image_restore.zig:106`、`src/core/tcl.zig:85`、`src/core/tcl.zig:96` |
| memory_is_fresh=true | Storageの論理メモリがゼロ済みなら保存範囲のコピーでよい | 使用済みメモリでrestoreFreshすると保存対象外に旧データが残る。State.initだけではStorage全域を消去しない | `src/core/image_restore.zig:51`、`src/forth.zig:483` |
| memory_is_fresh=false | 通常restoreでも復元可能である | block buffer領域は意図的に消去せず保持する。restoreだけでタスク間を完全初期化したとはいえない | `src/core/image_restore.zig:50`、`src/core/image_restore.zig:52` |

### 5.1 評価

新規Storageでは、ゼロ済み論理メモリ、State.init、専用Writer、空の画像・font・Tcl、audio_pcm_handle=0、借用Guardなしという条件で、列挙した後始末からメイン資源を操作する経路はないと静的に判断する。Storage.allocateのalready_zeroはallocatorがゼロを保証する場合の指定であり、任意allocatorにtrueを渡してよいという意味ではない（`src/forth.zig:159`、`src/forth.zig:177`）。並行実行試験は未確認である。

再利用Storageと再利用Stateは分けて扱う。Storageだけ再利用しState.initをやり直しても、事前の資源回収を省くと旧Stateのホスト資源を失う。Stateも使い回してrestoreだけ行う場合、画像のrelease、Tclのpartial処理、block buffer保持、font buffer保持、復元で触れない実行時設定が残る。restoreFreshを再利用にそのまま使用する案は不適合である。通常restoreへの切替だけで再利用の隔離が成立するとも判定しない。

提案は、停止・結果コピー完了後に専用資源を回収し、Storageの論理メモリ全域をゼロにし、State.initを行ってからrestoreFreshする基準手順である。全スロット・font・Tcl・block状態が空であることを確認する。再利用を省略初期化で最適化する場合は、全State項目を対象に1053/1362で別途判断・試験する。本書はその実装を行っていない。

## 6. 未確認事項と判断が必要な事項

- 未確認：1351の最終許可語・specialize/inline後のOpと、本表の到達条件との全件突合せ。初期候補は確定仕様ではない。
- 未確認：成功・失敗・取消し後の反復再利用、メインの画像・物理キー・Tcl・入力・出力を保持した並行試験。速度・時間の測定は行っていない。
- 未確認：C/OS内部のプロセス共有状態、全変数のロック規約・memory orderingの証明。atomic変数があることだけをワーカー許可の根拠にしない。
- 判断事項：専用write_fnの超過記録と失敗への変換、取消し専用経路とexecution_opsの役割分担。メインのExecutionOpsを流用しない。
- 判断事項：初期版を新規Storage限定にするか、全域消去・State再初期化付きの再利用まで含めるか。画像・font・Tcl等を将来許す場合の回収責任。
- 判断事項：modern_depthを入力禁止で隔離する初期案と、将来State/ホストscopeへ移す案。入力を許す前に選択が必要である。

## 付録A. 実際に使用した計数方法

PowerShellからPythonを実行した。作業用スクリプトファイルは作成していない。以下は今回実行した抽出条件を再実行できる形にしたものである。

```powershell
$env:PYTHONUTF8=1
@'
from pathlib import Path
import re, collections
s = Path('src/core/host_interface.zig').read_text()
fields = re.findall(r'^    (\w+):', s[s.index('pub const Writer'):], re.M)
print('Writer:', len(fields), 'unique:', len(set(fields)))
counts = collections.Counter()
for p in Path('src').rglob('*.zig'):
    if 'tests' in p.parts: continue
    for line in p.read_text().splitlines():
        m = re.match(r'^(?:pub )?var (\w+)', line)
        if not m or m[1].startswith('test_'): continue
        if p.name == 'host_line.zig' and m[1] == 'sunk': continue
        counts[p.as_posix()] += 1
print(sorted(counts.items()))
print('module:', len(counts), sum(counts.values()))
'@ | python -
```

実行結果：Writer 73、unique 73。module 16ファイル255宣言行。ファイル別の内訳は3節に記載した。

追加コンテナ表は次の範囲を確認して、指定インデントにあるvarだけを抽出した。同じ行は二重計数しない。

```python
ranges = {'src/host_audio.zig': [(383, 387, 4, 'windows'), (497, 528, 4, 'linux'), (838, 846, 4, 'macos')], 'src/host_display.zig': [(115, 116, 4, 'win32')], 'src/host_font.zig': [(105, 107, 4, 'gdi'), (217, 243, 4, 'coretext')], 'src/host_input.zig': [(383, 383, 4, 'posix'), (515, 533, 4, 'windows')], 'src/host_line.zig': [(541, 541, 4, 'posix')], 'src/host_process.zig': [(157, 160, 4, 'windows'), (404, 407, 4, 'posix')], 'src/host_wait.zig': [(27, 29, 4, 'win')], 'src/host_window.zig': [(192, 1169, 4, 'win32'), (826, 834, 8, 'win32.Vsync')], 'src/main.zig': [(2166, 2192, 4, 'utf8_console')]}
extra = []
for p, groups in ranges.items():
    source = Path(p).read_text().splitlines()
    for first, last, indent, container in groups:
        for line in range(first, last + 1):
            m = re.match(r'^ {' + str(indent) + r'}var (\w+)', source[line-1])
            if m and not m[1].startswith('test_'):
                extra.append((p, line, container, m[1]))
assert len(extra) == len(set((p, line) for p, line, _, _ in extra))
print(len(extra), len(ranges))
```

実行結果：追加163宣言行・9ファイル。255件との和集合は418宣言行・20ファイルである。OS構成で排他的な宣言もソース上は別に数える。extern environは別枠1宣言である。

参照検索には `rg -n "writer\.[a-z_]+|modern_depth" src/core src/forth.zig src/main.zig`、`rg -n "^(pub )?var " src`、コンテナ宣言・各変数名の同一ファイル内検索を用いた。行番号は本監査時のソース位置であり、他作業でソースが変わった場合は再照合が必要である。

修正時のmodern_depth参照件数は、次のPowerShellコマンドで再確認した。結果は4行（宣言・増加・減少・ホスト読取り）である。

```powershell
@(rg -n "modern_depth" src/core/event_input.zig src/main.zig).Count
```
