# 639 設計レビュー原文

# 639 設計レビュー：Windows の reader/writer と公開契約の確定案

読んだもの：`docs/ASYNC_IO_DESIGN.md`、`docs/ASYNC_CORE_PLAN.md` の §3・進める順序・決定事項、`docs/FILE_INPUT_WAIT_DESIGN.md`、`src/main.zig`（`fileOpenMode` から `fileEventWait` までと `rawStandardInputByte`、`redirectedInputReady`）、`src/host_wait.zig`、`src/host_wake.zig`、`src/host_process.zig`（`writeProgram` と `Watch`）。ファイルは変更していません。ビルドもテストも実行していません。

## 1. 採用案の要旨

- **Windows の reader thread は維持します。** 待つ操作が始まったときに slot ごとに起動し、ホストが持つ受信 queue に書き込みます。待機は既存の `host_wake.Wake` を1つ共有して行います。WaitForMultipleObjects の64個上限は、この共有で回避します。
- **WRITE-AVAILABLE は「ホスト送信 queue が受け入れたバイト数」を返します。** 渡されたデータは呼出し中に複製し、戻った後は利用者のメモリを参照しません。後から起きた書込みエラーは sticky として保持します。overlapped pipe への作り替えは採りません。

## 2. 読取り worker の寿命

### slot の状態

slot は `direct → reader → closed` の順に一方向にだけ進みます。状態は host 側の静的配列に置き、State やイメージには入れません。

- `direct`：現在の CRT 経路そのものです。既存の語の動作は変わりません。
- `reader` へ移る契機は次の2つだけです。
  - そのファイル ID を含む `WAIT-FILES`
  - ms が0でない `EKEY-WAIT`
- 移行の前提：Windows の pipe stream は `_IONBF` で開いており、非 stdin では ungetc を使いません（main.zig:603-613、642-647）。このため CRT の内部に未読のバイトは残らないと判断しています。すでに EOF を観測した slot では thread を起動しません。
- 受信 queue は64KiB で、移行時に heap から確保します。確保や thread 生成に失敗したら、何も消費せずに ior を返します。

### reader thread の処理

1. queue が満杯なら、`space_event` か `stop` を待ちます（逆圧）。
2. `in_io=true` にしてから ReadFile を呼びます。CRT は通さず、`_get_osfhandle` で得た OS handle から直接読みます。
3. 結果ごとの扱い：
   - データあり：queue に追加し、`Wake.notify` を呼びます。
   - 109（BROKEN_PIPE）：sticky EOF にして notify し、終了します。
   - その他のエラー：sticky ior にして notify し、終了します。
   - 995（ABORTED）：`stop` なら終了します。`stop` でなければもう一度読みます。
4. Wake は合図にすぎず、状態の正本は slot 側です。待つ側は20ms以下に区切って待ち、そのたびに全 slot を走査し直します。そのため notify が失われても、遅れは20ms以下で済みます。

### 既存 FILE 語の経路（reader 状態）

- 読む順序はどの語でも同じで、**Decoder → queue → sticky EOF/ior** です。main thread は OS handle を読みません。
- `KEY?-FILE` / `FILE-EOF?` は queue の状態だけを見ます。
- `KEY-FILE` / `READ-FILE` / `READ-LINE` は queue を待ちます。待機は beginInput の範囲で行うので、Ctrl+C で -28 になります。
- `READ-FILE` が保証するのは1078と同じ Decoder prefix のトランザクションまでです。同じ呼出しの中で queue から取り出した分は、ior や -28 のときに失われます。現行の fread も同じで、要求長は queue の容量を超えうるためです。

### 停止（CLOSE-PIPE、全回収、stdin の一時停止）

```
stop=true; SetEvent(space_event)
until WaitForSingleObject(thread,0)==0:
    lock; if in_io: CancelSynchronousIo(thread); unlock
    WaitForSingleObject(thread,10)
CloseHandle(thread); queue破棄; その後に _pclose / fclose
```

- 10msごとの再試行は、host_process.zig `Watch` と host_wait.zig `cancelConsoleRead` と同じ形の、停止時だけの再試行です。定常の待機を poll で行うものではありません。
- slot は join が終わった後でしか空かないので、ID を再利用しても前の thread の影響を受けないことが構造上保証されます。

### stdin

- 端末（コンソール）は既存の host_input のままです。WAIT-FILES ではコンソール handle と Wake の event を一緒に待ちます。文字でない入力 record は既存の queue に残し、ready には数えません。
- リダイレクトされた pipe の stdin は、上と同じ契機で遅延起動します。
- `SYSTEM` / `OPEN-PIPE` / Tcl の起動前には、stdin reader を停止して join します。停止の時点で受け取っていたバイトは queue に残すので失いません。子プロセスと stdin を奪い合わないためです。stdin reader は、次に待つ操作が来たときに再び起動します。

### READ-AVAILABLE

- `direct` 状態では移行しません。PeekNamedPipe で読めるバイト数を調べ、その数以下を fread で読みます。1回だけの照会で、待ちません。
- `reader` 状態では queue だけから読みます。
- 不変条件：WAIT-FILES が ready と返した直後の READ-AVAILABLE は、1バイト以上、`eof?` が真、ior のいずれかを必ず返します。

## 3. 書込み

### 採用：ホスト送信 queue（64KiB、最初の非0 WRITE-AVAILABLE で writer thread を遅延起動）

- **count の意味（両 OS 共通）**：u2 は順序どおりの配送のために受け入れたバイト数です。相手が受け取ったことは意味しません。
  - POSIX：カーネルの pipe buffer が受け入れた数
  - Windows：ホスト送信 queue へ複製した数
- writer thread は同期の WriteFile を呼びます。109 / 232 を受けたら EPIPE（32）を sticky にし、未送信分を破棄して終了します。
- `WRITE-FILE`：送信 queue が空になるまで待ち（割込み可）、そのあとは既存の CRT 直接書込みを使います。writer は I/O 中でないので、同期 handle での直列化による詰まりは起きません。これで既存の「EPIPE はその語で返る」動作を保ちます。sticky エラーがあれば、書かずにそれを返します。
- `FLUSH-FILE`：queue が空になるのを待ってから fflush します。
- `CLOSE-PIPE`：queue が空になるのを待ちます。待機中に Ctrl+C が来たら、Cancel して未送信分を破棄し、close まで完了させてから THROW -28 します。半端に閉じた ID は残しません。返す ior の優先順位は次のとおりです。
  1. まだ利用者に報告していない sticky エラー
  2. `_pclose` のエラー
- writer の Cancel が効くことは、既存の `testWatch`（host_process.zig:302）が、CreatePipe で作った無名 pipe について示しています。

### 不採用：overlapped pipe への作り替え

- `_wpopen` の無名 pipe は overlapped にできません。作り替えるには、CreateNamedPipe と CreateProcess で cmd.exe の起動・引用符処理・`_pclose` の終了状態を作り直す必要があります。
- FILE_FLAG_OVERLAPPED を付けた handle は、OVERLAPPED 構造体を渡す I/O が前提です。そのため CRT の同期経路と共存できません。
- overlapped にしても、書込み中は所有したバッファが必要で、count の意味も「受け入れた数」のままです。契約は同じで、変更量だけが大きくなります。
- PIPE_NOWAIT は使いません。互換用の機能で、CRT の読取りにも影響します（※推測を含みます）。

## 4. 公開契約（確定案）

- `WAIT-FILES ( addr n ms -- index ior )`：ASYNC_IO_DESIGN の案どおりです。ready は「その ID の READ-AVAILABLE が1バイト以上、EOF、ior のいずれかを返せる」ことと定義します。ready の判定はデータを消費しません。
- `READ-AVAILABLE ( c-addr u fid -- u2 eof? ior )`：ホストが受け取り済みの分だけを返します。転送途中のデータは後で現れることがあります。
- `WRITE-AVAILABLE ( c-addr u fid -- u2 ior )`
  - u2 は受け入れた数です（上の定義）。
  - `0 0` は未準備です。
  - sticky エラーがあれば `0 ior` を返し、close まで持続します。
  - u=0 は検査だけを行い、sticky ior があればそれを返します。
  - ディスクのファイルは全量を書き込み、u2=u です。
- `WAIT-WRITABLE ( addr n ms -- index ior )`：ready は「u≥1 の WRITE-AVAILABLE が1以上か ior を返す」ことです。Windows で queue が空なら、すぐ ready になります。

## 5. 実装前に必要な試験（Windows）

- **G1**：silent child の `_wpopen` 読取り端で ReadFile が詰まっているとき、CancelSynchronousIo で 995 が返り、データを失わないこと。未確認です。WriteFile については既存の試験があります。
- **G2**：同期 handle で ReadFile が詰まっていると、同じ handle への WriteFile も止まること。読み書き両用の named pipe を制限する根拠になります。※推測です。
- **G3**：移行の時点で、`_IONBF` の CRT に未読のバイトが残っていないこと。

## 6. 利用者の判断が必要な点

1. **OPEN-FILE で開いた読み書き両用の named pipe**：reader thread を置くと、G2 の直列化で書込みが止まる見込みです（※推測です）。どちらにするかを決めていただく必要があります。
   - (a) 1078 と同じ PeekNamedPipe + 1ms の例外を残す。決定3と食い違います。
   - (b) WAIT-FILES / EKEY-WAIT は ior を返して対象外にする。

   クロの推奨は (b) ですが、1078 の EKEY-WAIT の動作が後退します。
2. **reader 状態の `READ-FILE` を Ctrl+C で止められるようにすること**：`direct` 状態（現行）との間で動作が変わります。止められるほうを推奨し、文書に明記します。

この2点以外は、上の案で決めて進められます。
