# 652 実行制御の詳細設計

2026-11-20。640/646のMac実機は残す。[着手確認](EXECUTION_CONTROL_SCOPE.md)。
レモンは、文字を捨てず、Raw入力キュー満杯時は後ろのCtrl+Cを検出できない場合がある制約を了承した。
[レビュー原文](reviews/652-design-claude-review.md)と[採否](reviews/652-review-response.md)を照合し、以下を採用設計として実装する。

## APIと予算

`EXEC-LIMITED ( i*x xt u -- j*x ior )`をEXTENSIONへ追加し、extensionかつdebugで公開する。
uはセルの符号なしビット値、0は上限なし・中断確認のみ。正常終了0、入口予算切れ-280。
実行開始前にstack深さ、xt、最大16段の入口深さ、hostのbegin/poll/end能力を検査する。
入力の検査失敗は引数を保持してTHROW。実行中の普通のTHROWと-28は外へ伝え、CLI StepLimitも外へ伝える。

入口ごとの予算をCLIのstep_limit/steps_leftから分離し、内部に尽きた入口のindexを記録する。
CLIが尽きた場合はownerなし。StepLimitは既存どおり通常CATCHを通り抜け、ownerが一致した入口だけが-280へ変える。
外側の予算が先に尽きた場合、内側でior化せず、その外側まで戻す。同時はCLI→外側→内側を優先する。
予算を消費できることを全段で先に検査し、その後で全段を1ずつ減らす。0の入口は減らさない。

単位は入口のxt dispatch1、compiled operation1、有効EXEC中の解釈token1、既存native checkWorkBlock1（呼出し元はおおむね256反復単位）。
CPU命令数・文字数・時間ではない。呼出し先のnative処理が自動的にすべて中断可能になるわけではなく、
安全な確認点まで戻る必要がある。OS呼出しはpreemptしない。追加の大転送等も共通hookを利用する方針。

予算切れはxt/uを除いた入口のCATCH相当の深さへ復元し、-280を積む。内容の復元は保証しない。
データ/return/float/control/loop/解釈loopと未完定義・quote等はrestoreCatchFrameへ合わせる。
実行frame/call/locals/catchはexecuteOperationsの既存deferと入口の保存値で戻す。
trace/profile/backtrace抑制はCatchContextの共通復元処理へ合わせる。
メモリ・辞書・ファイル・描画・音等の副作用は自動で取り消さない。中断位置からの継続再開はない。

## 通常ループとの分離

通常runOperationsLoop(false)の本体へ確認や分岐を追加しない。入口で有効なbudget depthがあればcountedを選ぶ。
counted側の既存CLI消費点を共通chargeへ置換し、nativeのcheckWorkBlockも同じchargeへ接続する。
debug=falseでは新wordを除外し、予算用Stateフィールドは空の型として構築する。
native既存hookには有効予算の判定が増えるため、通常native処理も費用を別に測る。
確認間隔は256/1024/4096候補を実VMで比較して確定する。20msは目標で保証しない。

## Hostの信号所有と入れ子待機

Writerへoptional ExecutionOps(begin(State),poll(State),end(State))を1組で加える。
hostなしの埋込みは-21。テストでは明示的なfake hostを与える。コアはOSサービスを呼ばない。
host_waitの既存interrupt-only beginInput/endInputを、外側EXECの寿命中に1回保持する。
EXECがsignalの最初の所有者ならPOSIX SA_RESTARTを使う。
同じVMの内側EXECは参照深さを増やし、別VMへの再入は拒否する。
端末のISIG/PROCESSED_INPUTを計算のために有効化しない。cooked入力のOS SIGINTとRawのbyte3を別に確認する。

EXEC内のNS/audio/input waitは、外側のinterrupt-only scopeをborrowして同じhandlerを使う。
NSの時計と期限は既存Runtimeから使うが、二重にnative handlerを置かない。
RawのNS/audio待機は区切りで同じpollを呼び、計算中に保持した入力へ追記する。EXEC外の待機契約は維持する。
中断印は1度の検出で消費し、CATCH後に同じ印で繰り返し中断しない。復元失敗はHostFailedを優先して報告し、
既存Brokerのprocess-owned scopeとrecoverへ保持する。戻ったVMのポインターを復元待ちに残さない。
SYSTEM等が端末modeを変えても、interrupt-only scopeは古いmodeを再適用しない。

## Raw入力の保持案

POSIXはhost_input.queuedへbyteを保持し、Windowsは未デコードINPUT_RECORD ringへ保持する。
pollからenter/nextStandardPacketやconsole mode変更は呼ばない。通常のconsumerが取り出すときに、
Windowsのkey release/focus/mouseを従来どおりデコードする。読み取り済みの文字はcookedへの移行時も保持する。
Windowsは最大64レコードかつ最悪UTF-8展開後256byte以内、POSIXは256byteの既存queueを使い、
DSRの32byte分を予約する。満杯なら新しいOS入力を読まない。

背景pollは実際のdecoderやmouse/paste状態をcommitしない。standard.Decoderのcopyと、現在のcore pendingと
host queueのreadonly replay sourceを使い、既存standard.readを0待機で進めてCtrl+Cを調べる。
source直後の中断では最新byte、buffer先頭の中断では供給byte数とcloneの残bytes数から元位置を求め、sourceタグからそのbyteだけを元queueから除く。Windowsの削除箇所はcancelled markerとし、surrogateをまたいで結合しない。
先行する普通の文字・ESC・UTF-8・mouse等は残り、EKEY?/EKEYでのmetadata更新時点も変えない。
bracketed paste中のbyte3は既存parserと同じく通常入力として保持する。
満杯なら新しく読まないため、その後ろのCtrl+Cは検出できない場合がある（了承済み）。
mode変更・byte APIへの切替・partial escape・貼付け境界・selected-file入力との接続はレビューと試験で確かめる。

replayの作業領域はprocess-owned staticとし、host threadからだけ使う。modern decoder実行中は再生しない。
通常THROWと同時にendで中断が届いた場合も、callee例外を優先する。入れ子endでは印を消費しない。内側自身の予算切れと中断が重なった場合、内側は-280を返し、外側の次pollまたはendで-28となる。

## State・画像・検証

予算stack・owner・poll counterはプロセス内だけで、画像へ保存しない。restore/appendがactiveな予算を
無効化して制限を回避しないことを調べる。State監査表へ新しい内部フィールドを追加する。
Builtin末尾追加によりABI署名は変化し、旧画像はソースから再生成する。

テスト：0/境界/大u、内側/外側/CLIの先行・同時、CATCH/THROW/NO-BT、SYNONYM/EXECUTE/DEFER、
native hook、locals/return/float/frame/quote/compiledの復元、host不足、失敗したbegin/endと復元再試行。
入力は文字保持、UTF-8/ESC、paste byte3、mouse commit、full queue後の保留、KEY/FILE/GRAPHICS切替。
Windows独立console/pipeとLinux PTY/SIGINTでNS/audio/入力との入れ子、終了・mode復元を確認する。
通常・countedの速度を別に測り、debug/extension除外、画像、文書・実辞書を確認する。
Macはcross compileと実機を区別し、実機は別タスクへ残す。
