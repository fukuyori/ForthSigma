# タスク1355：W1の通常ビルド影響の比較

作成日：2026-11-23。日本語の静的生成コード比較報告である。

## 1. 結論と対象

**plain実体の命令列は不変ではない。** Windows x86_64とLinux x86_64のReleaseFast／ReleaseSmallの4組とも、アドレス・シンボル名の差を除いてもrunOperationsのplain実体に差がある。runOperationsLoopは独立関数として残らず、その本体はrunOperationsへインライン化されている。入口のworker判定以外に、Stateの配置変更、plainにも残る取消しエラーの回復除外、レジスタ割当てと命令配置の変化がある。

一方、worker側のCancellation読取り・1024 Op確認処理は別実体にある。plain側にworkerの定期確認処理が追加されたという結果ではない。通常経路全体の追加処理が「入口1読取りだけ」であるとはいえない。

基準は `D:/tmp/forthz-base`、試作は `D:/tmp/forthz-1352` である。両方のHEADは `35523f676836134c4fbaed19e3d01d2a23ec2a92` であり、試作の未コミットW1変更を比較した。基準の開始時・終了時の `git status --short` は空である。試作の既存変更・未追跡ファイルはそのまま保持した。ソース、tque、Gitの参照・インデックスを変更せず、コミット・タグ・pushを行っていない。

速度、実行時間、ベンチマークは測定していない。命令数は静的逆アセンブルの行数であり、実行回数や速度ではない。機能試験・実行体の起動も本タスクでは行っていない。

## 2. 条件、ツール、実行コマンド

- Zig 0.17.1：`C:/Users/n_fuk/AppData/Local/Microsoft/WinGet/Links/zig.exe`。
- LLVM objdump／pdbutil 22.1.8：`C:/Program Files/LLVM/bin`。
- Windows GNU objdump：GNU Binutils 2.47.20260726。PEに関数シンボルが見えないことの確認に使用した。
- WSL UbuntuのGNU objdump：GNU Binutils for Ubuntu 2.46、x86_64。
- Python 3.14.3：抽出・サイズ集計・テキスト差分・SHA-256の補助に使用した。
- targetは明示的に `x86_64-windows`／`x86_64-linux` とした。同じtarget内のCPU条件はZigのbaselineである。WindowsのホストCPU固有機能へ最適化するnative設定ではない。
- `-Doptimize=fast` はReleaseFast、`small` はReleaseSmallである。両者とも `-Ddebug=false -Dstrip=false` とした。
- 語群float、files、help、tools、image、graphics、x11、audio、extensionはすべてbuild.zigの既定値trueである。その他の容量設定も既定値でそろえた。両build.zigのSHA-256は `99863ea3298a40159762109d7e135149fb73c42719e8a413d6d47472fffc9982` で一致した。
- Windows上の同じZigでLinux向けもクロスビルドした。WSL内で別版Zigを使ったビルドではない。WSLのfileはELF64 x86-64、statically linked、with debug_info、not strippedと判定した。

PowerShellで、各ツリーをカレントディレクトリとして次を実行した。ビルド8件はすべて終了コード0、失敗出力なしである。global/local cacheも指定ツリー内に閉じた。

```powershell
# $root は D:/tmp/forthz-base または D:/tmp/forthz-1352
$env:ZIG_GLOBAL_CACHE_DIR = "$root/.zig-cache/1355-global"
$env:ZIG_LOCAL_CACHE_DIR = "$root/.zig-cache/1355-local"
zig build -Dtarget=x86_64-windows -Doptimize=fast -Ddebug=false -Dstrip=false --prefix zig-out/1355/windows-fast --summary failures
foreach ($cfg in @(@('windows','small'),@('linux','fast'),@('linux','small'))) {
    zig build "-Dtarget=x86_64-$($cfg[0])" "-Doptimize=$($cfg[1])" -Ddebug=false -Dstrip=false --prefix "zig-out/1355/$($cfg[0])-$($cfg[1])" --summary failures
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

調査コマンドは以下である。`$exe`、`$pdb`、`$start`、`$end` は後掲の対象実体の値である。PEの開始アドレスはPDBのsection 0001の10進offsetに `0x140001000` を加え、終了アドレスはcode sizeを加えた値である。

```powershell
zig version
llvm-objdump --version
objdump --version
wsl --list --quiet
wsl -d Ubuntu -- sh -lc 'command -v objdump; objdump --version | head -1; uname -m'
llvm-objdump --syms $exe
objdump -t $exe
llvm-pdbutil dump -publics $pdb
llvm-pdbutil dump -symbols $pdb
llvm-pdbutil dump -types $pdb
llvm-objdump -t $exe
llvm-objdump -h $exe
llvm-objdump -d --no-show-raw-insn --x86-asm-syntax=intel --start-address=$start --stop-address=$end $exe
llvm-objdump -d --no-show-raw-insn --x86-asm-syntax=intel --source --line-numbers --start-address=$start --stop-address=$end $exe
wsl -d Ubuntu -- objdump -h -d -Mintel /mnt/d/tmp/forthz-1352/zig-out/1355/linux-fast/bin/sigma
wsl -d Ubuntu -- file /mnt/d/tmp/forthz-1352/zig-out/1355/linux-fast/bin/sigma
```

WSL objdumpは両ツリーのlinux-fast／linux-smallすべてに実行した。PEのpublics／EXEシンボルだけでは対象を取得できず、PDBのS_LPROC32を使用した。`llvm-dwarfdump` はPATH上に存在せず、LinuxではELFシンボルとLLVMのソース行付き逆アセンブルを代替とした。

集計・抽出スクリプトと生の証拠は、許可された比較用出力先 `zig-out/1355/analysis/` に置いた。再実行順は以下である。これは計測ハーネスではない。

```powershell
python zig-out/1355/analysis/analyze.py
python zig-out/1355/analysis/compare.py
python zig-out/1355/analysis/evidence.py
python zig-out/1355/analysis/pe.py
python zig-out/1355/analysis/extra.py
python zig-out/1355/analysis/shape.py
```

## 3. 実行体・セクションのバイト数

すべて単位はbyte、差はW1−基準である。strip=falseのWindowsではデバッグ情報は別PDB、LinuxではELF内にある。そのためOS間の全体サイズを直接比較しない。

| target / optimize | 基準の実行体全体 | W1の実行体全体 | 差 |
|---|---:|---:|---:|
| windows-fast | 2,447,360 | 2,461,184 | +13,824 |
| windows-small | 1,908,224 | 1,918,464 | +10,240 |
| linux-fast | 10,330,664 | 10,408,264 | +77,600 |
| linux-small | 7,133,424 | 7,195,096 | +61,672 |

### 3.1 Windows PE

VirtualSize（配置先の内容長）とSizeOfRawData（ファイル上の512 byte整列済み領域長）を分ける。LLVM -hはPEの.dataなどでraw側を表示するため、PE section headerの両値も直接読んだ。.dataのVirtualSizeにはゼロ初期化領域が含まれる。EXE全体にはヘッダー・整列も含む。PDBはEXEサイズに含めない。

| optimize | section | Virtual 基準 | Virtual W1 | 差 | Raw 基準 | Raw W1 | 差 |
|---|---|---:|---:|---:|---:|---:|---:|
| windows-fast | .text | 1,429,334 | 1,442,502 | +13,168 | 1,429,504 | 1,442,816 | +13,312 |
| windows-fast | .rdata | 974,568 | 975,264 | +696 | 974,848 | 975,360 | +512 |
| windows-fast | .buildid | 90 | 90 | +0 | 512 | 512 | +0 |
| windows-fast | .data | 904,600 | 904,600 | +0 | 1,024 | 1,024 | +0 |
| windows-fast | .pdata | 25,332 | 25,392 | +60 | 25,600 | 25,600 | +0 |
| windows-fast | .tls | 16 | 16 | +0 | 512 | 512 | +0 |
| windows-fast | .reloc | 14,088 | 14,096 | +8 | 14,336 | 14,336 | +0 |
| windows-small | .text | 912,358 | 921,830 | +9,472 | 912,384 | 922,112 | +9,728 |
| windows-small | .rdata | 954,204 | 954,800 | +596 | 954,368 | 954,880 | +512 |
| windows-small | .buildid | 90 | 90 | +0 | 512 | 512 | +0 |
| windows-small | .data | 904,600 | 904,600 | +0 | 1,024 | 1,024 | +0 |
| windows-small | .pdata | 23,904 | 23,976 | +72 | 24,064 | 24,064 | +0 |
| windows-small | .tls | 16 | 16 | +0 | 512 | 512 | +0 |
| windows-small | .reloc | 14,164 | 14,168 | +4 | 14,336 | 14,336 | +0 |

PDBのファイルサイズは次のとおりである。パス・型・行情報などを含むため、通常経路の命令量とは区別する。

| optimize | 基準PDB | W1 PDB | 差 |
|---|---:|---:|---:|
| windows-fast | 6,639,616 | 6,680,576 | +40,960 |
| windows-small | 5,021,696 | 5,050,368 | +28,672 |

### 3.2 Linux ELF

LLVM -hのsection sizeを示す。.bss、.tbss、.relro_paddingはNOBITS/BSSであり、値全体がファイル内に格納されるわけではない。DEBUG・シンボル・文字列表も省略せず示す。ELFヘッダー・プログラムヘッダー・セクションヘッダー・整列は全体サイズにのみ含む。

| optimize | section | 基準 | W1 | 差 |
|---|---|---:|---:|---:|
| linux-fast | .rodata | 1,028,784 | 1,029,968 | +1,184 |
| linux-fast | .eh_frame_hdr | 14,948 | 14,988 | +40 |
| linux-fast | .eh_frame | 82,856 | 82,556 | -300 |
| linux-fast | .text | 1,282,131 | 1,295,187 | +13,056 |
| linux-fast | .tbss | 262,148 | 262,148 | +0 |
| linux-fast | .got | 0 | 0 | +0 |
| linux-fast | .relro_padding | 3,240 | 1,544 | -1,696 |
| linux-fast | .data | 4,400 | 4,400 | +0 |
| linux-fast | .bss | 1,373,472 | 1,373,472 | +0 |
| linux-fast | .debug_loc | 3,331,248 | 3,358,964 | +27,716 |
| linux-fast | .debug_abbrev | 76,692 | 76,692 | +0 |
| linux-fast | .debug_info | 1,789,878 | 1,806,405 | +16,527 |
| linux-fast | .debug_str | 405,192 | 406,225 | +1,033 |
| linux-fast | .comment | 40 | 40 | +0 |
| linux-fast | .debug_line | 1,126,035 | 1,133,925 | +7,890 |
| linux-fast | .debug_ranges | 555,888 | 564,352 | +8,464 |
| linux-fast | .debug_pubnames | 131,759 | 131,947 | +188 |
| linux-fast | .debug_pubtypes | 181,600 | 183,084 | +1,484 |
| linux-fast | .debug_aranges | 240 | 240 | +0 |
| linux-fast | .symtab | 183,576 | 183,720 | +144 |
| linux-fast | .shstrtab | 232 | 232 | +0 |
| linux-fast | .strtab | 133,099 | 133,269 | +170 |
| linux-small | .rodata | 1,008,816 | 1,009,744 | +928 |
| linux-small | .eh_frame_hdr | 13,692 | 13,740 | +48 |
| linux-small | .eh_frame | 67,836 | 68,112 | +276 |
| linux-small | .text | 818,069 | 827,765 | +9,696 |
| linux-small | .tbss | 262,148 | 262,148 | +0 |
| linux-small | .got | 0 | 0 | +0 |
| linux-small | .relro_padding | 3,832 | 1,080 | -2,752 |
| linux-small | .data | 4,408 | 4,408 | +0 |
| linux-small | .bss | 1,373,472 | 1,373,472 | +0 |
| linux-small | .debug_loc | 1,919,053 | 1,943,562 | +24,509 |
| linux-small | .debug_abbrev | 76,426 | 76,426 | +0 |
| linux-small | .debug_info | 1,245,142 | 1,257,247 | +12,105 |
| linux-small | .debug_str | 404,370 | 405,403 | +1,033 |
| linux-small | .comment | 40 | 40 | +0 |
| linux-small | .debug_line | 757,236 | 763,894 | +6,658 |
| linux-small | .debug_ranges | 193,600 | 197,984 | +4,384 |
| linux-small | .debug_pubnames | 130,748 | 130,936 | +188 |
| linux-small | .debug_pubtypes | 183,211 | 184,695 | +1,484 |
| linux-small | .debug_aranges | 240 | 240 | +0 |
| linux-small | .symtab | 182,520 | 182,688 | +168 |
| linux-small | .shstrtab | 232 | 232 | +0 |
| linux-small | .strtab | 125,719 | 125,916 | +197 |

## 4. 実体の識別と関数サイズ

debug=falseなのでcounted=trueの選択はコンパイル時に除かれる。W1のworker印null側の呼出し先をplainと特定した。関数番号だけから意味を推定していない。WindowsのW1は `__func_134` がplain、`__func_133` がworker、基準は `__func_133` のみである。LinuxのW1は `__func_170` がplain、`__func_169` がworker、基準は `__func_169` のみである。Linuxのシンボルには `forth.State.` が付く。

ReleaseSmallのexecuteOperationsではnull側のcallがこれを直接示す。ReleaseFastではexecuteOperationsがexecuteWordにインライン化されており、そこから同じnull側callを確認した。runOperationsLoopは4組すべてで独立シンボルがない。WindowsではPDBにrunOperationsLoopのinlineeレコードがあり、Linuxではソース行付き逆アセンブルがループ本体をrunOperations内に対応付ける。PDBもStateのsizeofもstrip=falseのデバッグ情報から得た値である。したがってloopだけの独立バイト数は算出せず、runOperations全体を比較する。

次表は開始アドレス、code size／ELF symbol size、静的命令行数である。W1のworker実体は通常経路の比較値へ混ぜていない。サイズにプロローグ・エピローグ・回復経路とNOPを含む。

| 構成 | 実体 | 基準 address | W1 address | 基準 byte | W1 byte | 差 | 基準 命令行 | W1 命令行 |
|---|---|---|---|---:|---:|---:|---:|---:|
| windows-fast | executeWord | 0x140041710 | 0x140041730 | 2,515 | 2,729 | +214 | 549 | 591 |
| windows-fast | executeOperations | inline | inline | — | — | — | — | — |
| windows-fast | runOperations plain | 0x1400420f0 | 0x1400421e0 | 11,295 | 10,051 | -1,244 | 2,157 | 1,906 |
| windows-fast | executeBuiltin | 0x14004b430 | 0x14004e910 | 21,033 | 21,033 | +0 | 4,433 | 4,433 |
| windows-small | executeWord | 0x14003876c | 0x14003877d | 1,323 | 1,510 | +187 | 329 | 357 |
| windows-small | executeOperations | 0x140038c97 | 0x140038d63 | 86 | 116 | +30 | 25 | 33 |
| windows-small | runOperations plain | 0x140038ced | 0x140038dd7 | 8,675 | 7,995 | -680 | 1,768 | 1,604 |
| windows-small | executeBuiltin | 0x14003e5bc | 0x140040a17 | 119,323 | 119,331 | +8 | 24,425 | 24,427 |
| linux-fast | executeWord | 0x115add0 | 0x115b190 | 2,474 | 2,596 | +122 | 538 | 565 |
| linux-fast | executeOperations | inline | inline | — | — | — | — | — |
| linux-fast | runOperations plain | 0x115b780 | 0x115bbc0 | 10,865 | 11,051 | +186 | 2,177 | 2,202 |
| linux-fast | executeBuiltin | 0x1164650 | 0x1167dd0 | 21,157 | 21,157 | +0 | 4,429 | 4,429 |
| linux-small | executeWord | 0x1146415 | 0x1146903 | 1,280 | 1,437 | +157 | 313 | 348 |
| linux-small | executeOperations | 0x1146915 | 0x1146ea0 | 86 | 115 | +29 | 25 | 33 |
| linux-small | runOperations plain | 0x114696b | 0x1146f13 | 8,172 | 8,032 | -140 | 1,728 | 1,693 |
| linux-small | executeBuiltin | 0x114bdd2 | 0x114e7e5 | 118,434 | 118,434 | +0 | 24,741 | 24,742 |

W1 workerのサイズはWindows fast 12,781、small 8,528、Linux fast 11,270、small 8,266 byteである。これは専用実体の存在を示す値であり、全体増分をworker単独のサイズだけで説明するものではない。

## 5. 命令列差分と原因

### 5.1 比較方法とアドレス差の扱い

`analysis/<tree>-<config>/` に対象ごとの生の `.asm`、ソース行付き `.source.asm`、補助的な `.norm`、`symbols.txt`、`sections.txt`、Windowsの `types.txt` を保存した。`<config>-<function>.diff` は正規化後のunified diffである。Windows PDBの型情報にはStateフィールドのoffsetが記録されている。

正規化では命令先頭のアドレス・表示用の `<symbol+offset>` を除き、直接分岐を関数内相対位置または呼出し先名へ置換し、RIP相対データ参照の変位をDATAとした。plain／workerの呼出し先は別名に保った。Stateの参照offset、スタックoffset、レジスタ名、通常の即値は残す。関数内の命令追加によるLOCAL位置の変化、外部関数の番号、未解決ADDR、ジャンプテーブルアドレスには表示上の差が残り得るため、diff行数を実変更の個数とは扱わない。DATA置換だけで参照データの内容一致も証明しない。

さらにshape.pyではWindows executeBuiltinの即値・変位をすべて隠した補助比較をした。これは配置差とopcode/レジスタ/順序の差を分ける診断であり、不変の証明には用いない。raw逆アセンブルとソース対応を根拠として以下を記す。

### 5.2 executeOperations：通常入口にも分岐が残る

Windows ReleaseSmallの抜粋である。W1のnull側がplainへ進む。基準はこのcmp/条件分岐なしで単一実体をcallする。

```asm
; W1 executeOperations
140038d8a: cmp  qword ptr [rcx + 0x463d80], 0x0 ; worker_cancellation
140038d95: je   0x140038da8
140038da1: call 0x14003e6cf                     ; worker
140038da6: jmp  0x140038db7
140038da8: lea  r9, [rbp - 0x8]
140038dac: mov  dword ptr [r9], eax
140038daf: mov  rcx, rsi
140038db2: call 0x140038dd7                     ; plain
```

Linux ReleaseSmallでも `[rdi + 0x463d80]` のcmp、null側から `0x1146f13`（plain）、非null側から `0x114c5a9`（worker）をcallする。ReleaseFastでは独立関数がなくなっても、この判定がexecuteWord内に残る。Linux fastの `0x115b328` のcmp、`0x115b330` のje、`0x115b33b` のworker callとnull側plain callが例である。したがって独立シンボルの消失を追加判定の消失とは扱わない。

### 5.3 executeWord：別の追加判定と拒否処理

`src/forth.zig:1555` の `if (self.worker_cancellation != null) try self.checkWorkerWord(id);` に対応する追加読取り・分岐がある。Windows fastの抜粋を示す。

```asm
140041757: mov  r14, qword ptr [rcx + 0x463d80]
; 語の取得
1400417a6: test r14, r14
1400417a9: je   0x14004181a ; nullなら拒否処理を飛ばす
; synonym走査、kind/has_does検査、checkWorkerBuiltin呼出し
```

これはexecuteOperationsの入口判定とは別の判定である。通常の解釈実行・nativeからの再入に通るexecuteWordにも影響する。追加拒否処理は非null側にあり、plainで毎回拒否集合を走査するという意味ではない。Linuxも同じソース行にtest/jeと拒否処理が対応する。サイズ差にはこの追加だけでなく、inline化されたexecuteOperations、配置・レジスタ割当ての差も含む。

### 5.4 State配置：同じ名前のフィールドでも変位が異なる

Windows fastのPDB LF_MEMBERによる値である。これはリンク先の移動やシンボルの改名ではなく、実際のメモリ参照オペランドの変更である。

| Stateフィールド | 基準offset | W1 offset |
|---|---:|---:|
| words | 0x163dd8 | 0xfd0 |
| code | 0x16e8 | 0x301aa8 |
| data_depth | 0x1031b0 | 0x4033c0 |
| backtrace_suppression | 0x1484b0 | 0x4486a0 |
| frame_depth | 0x163b40 | 0x463d58 |
| catch_depth | 0x163b58 | 0x463d70 |
| worker_cancellation | なし | 0x463d80 |
| halted | 0x550b44 | 0x550b4c |

基準とW1のStateは通常の `struct` であり、PDBで異なる配置を実際に確認した。単に全フィールドへ8 byteを足した配置ではない。State全体のsizeofは両方6,777,936 byteで一致しているが、内部配置は一致しない。配置を変えたコンパイラ内部の決定過程までは確認していない。

例えばWindows fast executeBuiltinは両方21,033 byte／4,433命令行だが、次が異なる。

```diff
-cmp byte ptr [rsi + 0x163940], 0x1
+cmp byte ptr [rsi + 0x463b40], 0x1
-mov rax, qword ptr [rsi + 0x163938]
+mov rax, qword ptr [rsi + 0x463b38]
-mov qword ptr [rsi + 0x463db8], rax
+mov qword ptr [rsi + 0x463dc0], rax
```

即値・変位を隠したWindows fast executeBuiltinのopcode/レジスタ/命令順の列は一致した。しかし上記の変位は隠してはいけない実際の差であるため、命令列不変とは結論しない。Linux fast executeBuiltinもサイズ・命令行数は一致するが、State変位を含む正規化比較では異なる。

### 5.5 plain runOperations／インラインループ：回復経路と割当ての差

plainとworkerは別実体であるが、plain全体の命令列は基準と異なる。Windows fastの冒頭には次の実変更がある。

```diff
-sub rsp, 0x228
+sub rsp, 0x238
-mov rax, qword ptr [rcx + 0x163b58]
-mov qword ptr [rbp + 0x100], rax
+mov r11, qword ptr [rcx + 0x463d70]
 ; catch深さの保持先がスタック中心からr11を使う割当てへ変わる
```

ループ本体のOp取得にも、State.codeへの変位、取得先レジスタ、ブロック配置の差がある。基準の `lea r8,[rsi+0x16e8]`／`mov rdx,[r8+rcx]` に対し、W1では `lea rdx,[rsi+0x301aa8]`／`mov r15,[rdx+rcx]` となる。入口や末尾だけを除けば同一、という結果でもない。全4組でplainのサイズと命令行数が変わっている。

またW1の `src/forth.zig:1941` はworker comptime条件の外でTaskCancelledを回復対象から除外しており、plainにも生成される。Linux fastのソース対応付き抜粋で差を示す。

```asm
; 基準：Quit / StepLimit
115e020: cmp   r13w, 0x2f
115e025: je    0x115e1aa
115e02b: movzx eax, r13w
115e02f: cmp   eax, 0x4f
115e032: je    0x115e1aa
; W1 plain：Quit / StepLimit / TaskCancelled
115e1e0: movzx eax, di
115e1e3: add   eax, -0x2f
115e1e6: cmp   eax, 0x21
115e1e9: ja    0x115e1ff
115e1eb: movabs rcx, 0x300000001
115e1f5: bt    rcx, rax
115e1f9: jb    0x115e6ad
```

比較・bit testの列そのものが異なる。エラー判定の拡張はソース行と機械語を対応付けられる変更である。レジスタ割当て・命令スケジュール・ブロック配置の変化も観測できるが、その各差をState追加と回復条件変更のどちらが単独で引き起こしたかは切り分けていない。**推測：これらの変更が最適化の判断へ波及したと考えられる。** ソース改変による要因別再ビルドは許可範囲外であり実施していない。

workerのWindows fastには `[State+0x463d80]` からトークンを取得し、`movzx eax, byte ptr [rax]`、`mov r14d,0x400`、`test al,0x1` を行う列がある。plainの対応ループにはこのworker定期確認列・checkWorkerOp呼出しがないことを生の逆アセンブルとcomptime分離のソース対応で確認した。x86_64のacquire読取りは通常のloadにもなるため、lock命令がないことだけを分離の根拠にはしていない。

### 5.6 executeBuiltin ReleaseSmall：サイズ一致でも命令の差がある

Windows smallでは119,323→119,331 byte、Linux smallでは両方118,434 byteである。Linux smallの静的命令行数は24,741→24,742で、サイズ一致でも命令列は異なる。

Windows smallのTHROW逆引きループでは、基準の `lea r8,[rdx+0x10]` から始まる走査に対して、W1には次が入る。

```asm
1400561af: cmp rdx, 0x300
1400561b6: je  0x14005afc9
1400561bc: mov r8, rdx
1400561bf: add rdx, 0x10
1400561c3: cmp r8, 0x2f0
1400561ca: je  0x1400561af
```

`src/core/words_system.zig` の `if (entry[0] == error.TaskCancelled) continue;` と追加エラー表に対応する。executeBuiltin自体にworker印判定を置かなくても、インライン化された下位builtinの変更がこの実体へ入る。他にロード順序の入替え、`movdqu`→`movdqa` の差もWindows smallで観測した。後者はメモリ整列の扱いが変わった命令であるが、個々の最適化判断の原因は未特定である。Linux smallの差にもTHROW走査・オフセット・命令配置の変化が含まれる。すべてをシンボル名・アドレスだけの差と扱うことはできない。

## 6. 未確認事項と1357への判断材料

1. W1はworkerの定期確認処理をplainループから分離できているが、通常コードの機械語不変条件は満たしていない。追加入口分岐とexecuteWordの判定、plain回復処理、State参照変位、最適化後の命令配置までを判断対象とする必要がある。
2. 全体の.text増分にはworker実体と共有関数等も含む。plain実体が小さくなったWindowsの結果から速度改善や費用ゼロを主張しない。実行体増分から時間費用を推定もしない。
3. ReleaseFastとReleaseSmallの両方で不変でないことを確認したため、今回はReleaseSafeを追加していない。ReleaseSafe、strip=true、語群を絞った構成、別CPU、別ABI／Zig版は未確認である。
4. Linux向けはクロスビルドとWSLでの静的解析までである。WSL内での起動・機能・取消し・並行隔離の検証ではない。Windowsの機能再検証も本タスクの対象外である。
5. State追加とエラー集合／回復条件の要因別の寄与、コンパイラ内部の割当て決定、全関数・全データの意味的等価性は未確認である。正規化による一致だけで未検査データの同一性を証明しない。
6. 1357では「通常経路の命令列を維持する」ことを必須とするか、今回確認した変更範囲を許容するかを明示して判断する材料となる。W2/W3との優劣や採否、許容サイズ上限は本タスクだけで決定できない。速度・時間の判断は本報告の証拠に含めない。
7. 生成コード不変へ近づける検討対象は、State配置の影響、plainにも残るTaskCancelled回復除外、executeWordの実行時拒否、入口選択の位置である。これは次段の検討項目であり、本タスクでソースを修正した結果ではない。

## 7. 証拠の所在と作業境界

- ビルド：両ツリーの `zig-out/1355/{windows,linux}-{fast,small}/bin/`。
- 集約結果：試作ツリーの `zig-out/1355/analysis/results.json`、`pe-sizes.json`。
- 生逆アセンブル：`analysis/<tree>-<config>/*.asm`。Linuxは同じディレクトリの `wsl-objdump.txt` にGNU objdumpの全体出力もある。
- 個別差分：`analysis/<config>-<function>.diff`。関数番号の対応は4節による。
- ハッシュ：各構成の `sha256.txt`。ソースの終盤検査は `analysis/<tree>-source-hashes.json` に保存した。
- 本タスクの文書変更は本ファイルだけである。補助スクリプト・解析結果はすべて許可されたビルド出力先内に置いた。パッケージ・インストーラーは作成していない。

### 実行体のSHA-256

| 構成 | 基準 | W1 |
|---|---|---|
| windows-fast | `0f7dba0cebcc3c8b4cb8ebfa8effc69810abe3084187caedee8db7243497a491` | `91d4516b587aeb0a442587530c8bf469a4039038c5cc5c3597753b0550f5b19b` |
| windows-small | `0ecabfd79b8cc1eab73f03c459aa4dd6dca1604373916963147dd7a59ad90b95` | `d28700926e605a965bfa46d68dd4eb87dca27ceb312279c5a9d3e51e5deff163` |
| linux-fast | `8d5581e18d71780263838add8071a5c70597ef11c676e7c338bce451b252324b` | `616f2b047d49f08dd73ea9f28e085b5ddc218fd789aafe7192537cad6a25a187` |
| linux-small | `49698e018475c1f40b68cb466a5e45faf965791648eb8521cca1f9e99806f022` | `50c5525484a689f5af784ea6d973ec0e26997eea004403e2860338c62d023b5f` |
