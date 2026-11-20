# 998 PCMレビューの評価・判断

2026-11-20。[設計レビュー原文](998-design-claude-review.md)、[内部リング原文](998-ring-claude-review.md)、[採用設計](../PCM_STREAM_DESIGN.md)。Claude CodeはRead/Glob/Grepだけで静的レビューし、実行確認はロクが担当。

## 設計レビュー

- H1採用：consumer領域をStateから分離しhost Engineの安定した有界領域へ置く。CLOSEでfreeせず、join成功後だけfree。Stateへ論理IDを置く場合もconsumerが参照しない。
- H2/H3採用：待機は相対ms・0poll・負数無期限。WAIT/STOP中断はTHROW -28。CLOSEの中断は既存close前例に合わせ-516でID保持。
- H4採用：backend別終了とopen失敗rollbackを1127へ分割。既存Pulse simpleを黙って削らない。blocked writeでのtimeoutは回収失敗として保持し、成功にしない。停止/driver呼出し全般の絶対上限は保証しない。公式APIは別途ソース照合記録にリンクした。
- H5採用：同一process内のstale拒否とcross-process一意性を区別し、後者は保証しない。
- M1〜M6/M8採用：容量40ms..1s、held frameをQUEUEDに含む、最初の入力前はunderrunにしない、不正値/範囲は事前THROW、consumerだけがheadを更新、装置なしsilentと位置の能力を明示。
- M5のOPENでack不要は、前streamがdetach ack済みの時だけ採用する。設定/書込みはconsumer非参照を確認して行い、新しいattachのpublish/ack自体は制御protocolとして保持する。
- **M7の完全復元applyでの自動abandonは採用しない。** 900の活動資源busy案と、apply前に検査する既存画像の構造を優先する。完全復元だけを変更前busy拒否し、明示CLOSE後に復元する。appendの共有prepareにbusy検査を混ぜない。
- 共通終了手順の「join後VM threadでOS解放」は一部変更する。driver解放自体が待ち得るので、原則backend threadが解放後にexitedを出し、VM threadは期限内に未完了を判定できるようにする。未停止なら保持して失敗終了する。

## 内部リングレビュー

Highなし、Medium2件を採用。

- M1：downsampleのadvanceが未着入力を越えたとき、skipを保持し次のsampleで消費する。WRITE分割だけで位置がずれる例を回帰試験にした。実際に無音となった場合だけphase/skipをresetする。
- M2：Controlのcompletedをack>=serialへ変更し、後続ack後も古い完了を保持する。serial0は常に未完了。最後のserialをdetachへ予約して枯渇時の取り外しを保つ。
- Lowのoutput rate上限を8000..192000へ制限。non-unityの並行ストレスは追加検証対象とし、現時点の並行試験はunity、非unityは決定的rate表で確認する。

レビューは公開API/host寿命を実装済みと評価したものではない。最終修正とEngine混合の限定再レビュー、実行結果は実装記録に分ける。


## 限定再レビューと全体テスト後の修正

[再レビュー原文](998-followup-claude-review.md)は初回M1/M2の修正・Engine混合・restore busy判断を確認し、Medium1件（drain尾部がunderrunになる）を指摘した。これを採用し、producer-ownedのatomic drainingを追加した。consumerは意図的なemptyを抑制し、drain取消し後のemptyは数える。beginがproducerのflagを上書きしないことを設計・試験に明記した。

既存の`zig build test`でthumb-freestanding-eabi/Cortex-M0+が64bit atomicを扱えないと判明した。内部Control serialとunderrun counterをu32へ変更し、折返さず枯渇拒否・最終detach予約・飽和を保った。phase/skipのu64整数演算はatomicでなく、そのまま使用できる。公開handleの世代IDは別のhost設計であり、内部serialの幅と混同しない。修正後の`zig build test`は成功した。

non-unityの実2thread試験（44100入力→48000出力）も追加し、低指摘の検証を補った。これは意図的なunderrunを挟まずpublicationを待つ連続性試験であり、実装装置の音切れ率や実時間性能の証明ではない。

[最終限定再レビュー](998-final-claude-review.md)は高・中の指摘なし。drain成功後のflag保持と、再OPEN publish前の解除を採用設計へ明記した。host/public APIは引き続き未実装。
