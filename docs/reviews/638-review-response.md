# 638 レビューの評価と反映判断

2026-11-19。[設計](../EVENT_QUEUE_DESIGN.md)とレビュー原文を分けて記録する。

| 設計指摘 | 評価・判断 |
|---|---|
| 値3がホストで先に例外になる | 採用。新口は生バイトを渡し、coreがpaste外だけ-28にする。legacy口は維持 |
| 保留バイトがACCEPT/REFILL/KEY?/INKEYへ見えない | 採用。beforeBytesで行/byte APIへ渡し、GRAPHICSは先に生バイトを取り込む。hostの既存64バイトのunread上限を確認し、容量超過はassertではなくHostFailedを保留する |
| 完成したイベントよりdeadlineを優先する | 採用。既に手元にある完成イベントを返し、次のホスト呼出しの前に期限を判定する。切上げやOS待機による超過をゼロとは保証しない |
| paste中のGRAPHICS切替を-21とする | 採用。切替でpasteを解除し、GRAPHICSの従来規則に従う |
| peekとKEY互換 | 採用。生バイトから再計算し、paste/buttons/last_mouseの確定は消費時だけ。nativeの非文字イベントは標準側に保留 |
| mouse状態と修飾 | 採用。押下集合を独自追跡、修飾maskをOR、移動を公開、横wheelは消費。X10は対象外 |
| EKEYのiorは常に-265 | 一部のみ採用。実ソースでは選択ファイルのinput_redirect.byte/readyが元のiorをTHROWしているため、それを維持する。ネイティブは-265。EKEY-WAITは対象iorを返す |
| 選択ファイルとESC | 採用。ready/key/eofを使う専用アダプターでiorを保持し、ファイルはUTF-8以外のプロトコルを解釈しない |
| paste打切り | 採用。END/EOF/TERM-MODE!/再開始/入力源やAPIの切替で解除。無通信だけでは解除しない |
| 旧保留フィールドをまとめる | 機能上の必須条件ではないと評価。古い埋込みと既存試験の互換のため旧フィールドを保持し、新Sourceが先に消費する。新Decoderは一構造体で退避・初期化する |

設計レビューはコード実行をしていない。別途、差替え試験、POSIX PTY、Windows入力レコード、通常構成と機能除外、語参照の検査結果を実装記録へ残す。

## 実装レビューと工程の再検討

実装レビューで、選択ファイルへの複数バイトungetcと、scope退出時の先読み損失が指摘された。core内へ戻すだけでは、後のKEY-FILE/READ-FILEと位置・close・ID再利用を通じて保持できない。Claude Codeへ再度工程を照合するレビューを依頼し、638のEKEY-WAITをstdin専用に確定、639配下1078へファイルごとの期限待機を追加した。選択ファイルの既存EKEY/EKEY?は従来経路のまま。stdin IDは対象として許可し、非stdinは入力を消費せず-21。試験で拒否後のKEY-FILEが先頭Aを読み、外側DecoderがTHROW後も戻ることを確認する。

| 実装指摘 | 反映 |
|---|---|
| unread_fnなしのACCEPTが-21 | key_fnで保留接頭辞と続きの行をつなぐfallbackとCRLF試験を追加。両方ないホストは入力を保持して-21 |
| peekがEOFを消す | 消費までEOFを保持。一度だけEOFを通知する差替え入力で確認 |
| restartのbuttons残留とESC期限延長 | paste/buttonsを解除し、ESCの開始時刻を維持。差替え試験を追加 |
| SGR拡張ボタンの誤認 | code128以上を除外し、motionで押下bitを復旧。試験追加 |
| buffered_key_fnで値3を先にTHROW | 新sourceでこの口を使わず、ホストがlookaheadの生バイトを直接返す |
| peekで横wheelを消費 | 標準プロトコルの非公開通知として除外する方式を採用。KEYへ戻らないことも設計へ明記 |
| standardがGRAPHICSのrestartを奪う | standard側は別のmode_generation観測値で通知し、GRAPHICS用restartedフラグを消さない |

イメージ復元は一時Decoderを初期化する設計を維持し、イベントを辞書から再現しない。ESC期限の加算と差分をcheckedにし、0ms時の無視通知の連続は64項目まで、Windowsのnativeフィルターも32レコードずつに制限した。EKEY/EKEY?も結果セルの余地を先に確認し、スタック満杯でイベントを失わないようにした。

## 最終・固定スナップショットレビューの反映

| 指摘 | 最終の判断と証拠 |
|---|---|
| POSIXでGRAPHICSのrestartを奪う | nextStandardPacketはqueued/readを直接読み、standard側の世代通知とGRAPHICSのフラグを分離。差替え試験と既存コンソール回帰 |
| stdin→file→stdinの入れ子 | stdin Decoderを一つ共有し、旧pending_key/bytes/eventもstdin用の一時キャッシュを通して出入りさせる。Decoderの先読みAB、旧pendingのXYZ/WINCH/Aを確認 |
| CR後の余分な待機と、次のACCEPTの文字損失 | 読める場合だけLFを調べ、typed入力の返却バイトはDecoder先頭へ戻す。CRLFとCR/nonLFの2行を確認 |
| KEY?でESC時刻を延ばす | KEY?は保留の照会だけとし、実際の転送・消費まで時刻を維持 |
| native通知がESCを分断する | 完成したnative通知を先に返して部分列を保持。WINCHを挟んだESC[とAが後でUPになる試験 |
| byte API後にnativeイベントが残る | 従来どおり標準側へ保持する設計を維持し、ACCEPT後に古い矢印が次のEKEYへ出る例も設計へ明記 |
| checked/void pushbackの失敗時に重複する | 新しいWriter.unread_byte_fnは「エラーなら未受理」の原子的操作。voidの旧口は受理を契約とし、受理分をcoreから外してから保留エラーを確認。両方を差替え試験で確認 |
| Decoderと旧pendingの順序 | Decoderを先頭に統一。checked転送は旧pending→Decoderの逆順で押し戻し、押し戻しなしはDecoderを先に読む。XKEY/行の返却もDecoder先頭に置く。XYZと不正UTF8のFF/Qを確認 |
| 失敗時にpasteが解除される | 原子的拒否では元の状態を保持し、転送成功または実際のbyte消費で解除 |
| Windowsフィルターの上限 | nextStandardPacket/nextByteの外側も32回まで。各native.nextの32レコード上限と合わせて有限にする。focus releaseの再帰を除去 |
| STDINのファイルAPIと先読み | KEY-FILE/READ-FILE/READ-LINE/SLURP/INCLUDE等で明示STDINのバイトを同じchecked口へ渡す。KEY?-FILE/FILE-EOF?もcoreの保留を参照。旧ホストの経路は維持 |

固定スナップショットレビューでEOFの順序の欠陥が見つかった。Windowsの実行体にESC[を渡し、EKEY?→KEY→EKEY→EKEYで`27 K-EOF 91`になることを再現した。typedホストのEOFをストリームの終端状態と定義し、押し戻したバイトの後にはホストがEOFを再通知する契約を採用した。成功した各バイトの転送でcoreのEOFキャッシュを解除し、拒否されたバイトは保持する。ESC[と途中UTF8の両方で、バイト→残り→EOFの順をWindows/Linuxの実行試験へ追加した。

EOF修正の評価レビューでは、このストリーム契約のもとで順序の欠陥が解消することを確認した（レビュー自身は実行していない）。core内だけのEOF先読みは引き続き消費まで保持する。raw端末のCtrl+D/Zを一度きりのEOFへ変換するAPIではない。

LinuxのSIGWINCH復元試験で、0とSA_RESTORERの差を確認した。実際に使用したZig同梱muslのsrc/signal/sigaction.cで、このABI用フラグをlibcが付加することを確認し、比較からそのビットだけを除外した。ハンドラー・マスク・その他のフラグは比較を維持する。ReleaseFastの符号付きbyte縮小は既存のunsigned経由の方法へそろえ、実行試験でUTF8を確認した。
