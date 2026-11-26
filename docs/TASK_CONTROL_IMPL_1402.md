# tque 1402: matched single-VM layout variants

2026-11-26, Linux x86_64, starting HEAD `333f8af`, Zig 0.17.1. This extends [1390](TASK_CONTROL_IMPL_1390.md) and [the runner](../tests/scripts/single-vm-ab.py). No timing measurement or acceptance verdict was performed. Product src/ and build.zig are unchanged; no tque or Git mutation was performed.

## Construction

`--layout base|tail64|hot16|hot32` selects fresh builds (prepare, or smoke without --builds). Base preserves the 1390 behavior: ordinary B builds at the repository root. Every other layout builds all four controls A/Aprime/B/B-copy in dedicated source copies. The A archive and Aprime's worker-entry-only patch remain as in 1390. Only copied build.zig files receive the additional layout change, recorded in each `<label>-layout.patch`; base records empty layout patches. Identical layout code is injected into all four controls.

The copied build uses `b.addWriteFiles()` to generate a tiny C function `svab_layout_probe`, with 16-byte alignment, inline NOPs and a return. It is not called by the measured workload. `forceUndefinedSymbol` roots it against linker GC, and disassembly must contain it on ELF/Mach-O; Windows now requires its PDB procedure record and decoded padding through 1403. `used` alone would not prevent linker GC. No product setting or source function is modified. Padding is specified in bytes: x86_64 uses one-byte NOPs; aarch64/arm64 (including Apple M5) uses four-byte NOPs, with bytes/4 instructions. C preprocessor checks reject unsupported architectures or byte counts not divisible by the instruction width during prepare. The return, compiler prologue/epilogue and alignment are outside the specified padding.

- `tail64`: 64 NOP bytes in ordinary `.text`; the original proposal's placement control.
- `hot16`: 16 NOP bytes in ELF `.text.hot`.
- `hot32`: 32 NOP bytes in ELF `.text.hot`.

ELF linker ordering places `.text.hot` before ordinary Zig function sections, so padding can move Zig code. A plain C `.text` input can land after it. Also, 64/256-byte increments alone need not change mod 64; 16/32-byte increments exercise different positions. The Linux verification below is the evidence for the adopted method, rather than assuming that adding bytes changes the hot code. In this Linux link, tail64 also precedes the Zig code: it moves B's ordinary runOperations by 128 bytes including other link-layout effects, leaving mod64 unchanged. Hot16 changes mod64, and the explicitly prioritized section plus sub-64-byte increments is retained as the useful perturbation. Reversing C-object order was therefore unnecessary for this implementation. On Mach-O the C section is `__TEXT,__text`; on COFF it is `.text$a`. Native Windows ordering and movement are recorded in [1403](TASK_CONTROL_IMPL_1403.md); Mach-O still requires native verification. No cross-platform movement guarantee is made.

## macOS placement and alternatives

On macOS arm64 (Apple M5), it is **unverified whether the C function in `__TEXT,__text` precedes Zig code**. Cross-compiling the C object verifies NOP bytes only, not final executable ordering or movement of ordinary runOperations. `hot16`/`hot32` are byte-count names; on Mach-O they do not select a special hot section. Claude will verify final linking and smoke on the Mac.

If the probe follows Zig code, the researched first candidate is an `-order_file` placing `_svab_layout_probe` and the padding labels before the target symbols. LLVM documents symbol priorities within output sections and the subsection requirements for reordering ([SectionPriorities.h](https://llvm.googlesource.com/llvm-project.git/+/refs/tags/llvmorg-18.1.1/lld/MachO/SectionPriorities.h), [Mach-O subsection handling](https://lld.llvm.org/MachO/ld64-vs-lld.html)). Passing this through Zig 0.17.1, preserving the padding region and obtaining actual movement are unverified. Changing C-object/link input order is another unverified candidate. A separate earlier Mach-O section is a candidate for investigation, not an established solution: current [LLD section ordering](https://raw.githubusercontent.com/llvm/llvm-project/main/lld/MachO/OutputSegment.cpp) prioritizes `__text` ahead of other code sections, so simply renaming the section does not guarantee earlier placement. No suitable earlier section or working section-order override has been verified with Zig's Mach-O linker. These are alternatives to test in copied builds only; none is implemented here.

## Commands

Use Python 3.12+, Zig 0.17.1 and objdump; Mach-O also needs nm. Use a Mach-O-capable llvm-objdump on macOS. The following measure command is a proposal only: obtain an operator decision on iterations, counts, independent runs and extension rules before running it. Repeat it for every layout and independent run with a fresh output directory, preserving the preparation directory. Never pool layouts. See 1390 for timing scope, comparisons, and uncertainty rules.

```sh
export ZIG_GLOBAL_CACHE_DIR=$PWD/.work/codex-cache/global ZIG_LOCAL_CACHE_DIR=$PWD/.work/codex-cache/local
# macOS: add --objdump llvm-objdump to every invocation below.
for layout in base tail64 hot16 hot32; do
  python3 tests/scripts/single-vm-ab.py --mode prepare --layout "$layout" --out ".work/1402-r2/$layout"
  python3 tests/scripts/single-vm-ab.py --mode smoke --builds ".work/1402-r2/$layout/builds.json" --out ".work/1402-r2/$layout-smoke"
done
# Only after the operator fixes the plan and environment; use fresh run directories.
python3 tests/scripts/single-vm-ab.py --mode measure --builds .work/1402-r2/hot16/builds.json --out .work/1402-r2/hot16-run1 --rounds 100 --warmup 5 --iterations 10000000 --confirmed USER-DECISION-REF --environment 'CPU, power, background load, terminal: fill before run'
```

```powershell
$env:ZIG_GLOBAL_CACHE_DIR="$PWD/.work/codex-cache/global"
$env:ZIG_LOCAL_CACHE_DIR="$PWD/.work/codex-cache/local"
foreach ($layout in 'base','tail64','hot16','hot32') {
  python tests/scripts/single-vm-ab.py --mode prepare --layout $layout --out ".work/1402-r2/$layout"
  if ($LASTEXITCODE) { throw "prepare $layout failed" }
  python tests/scripts/single-vm-ab.py --mode smoke --builds ".work/1402-r2/$layout/builds.json" --out ".work/1402-r2/$layout-smoke"
  if ($LASTEXITCODE) { throw "smoke $layout failed" }
}
# Only after the operator fixes the plan and environment; use fresh run directories.
python tests/scripts/single-vm-ab.py --mode measure --builds .work/1402-r2/hot16/builds.json --out .work/1402-r2/hot16-run1 --rounds 100 --warmup 5 --iterations 10000000 --confirmed USER-DECISION-REF --environment 'CPU, power, background load, terminal: fill before run'
if ($LASTEXITCODE) { throw 'measure failed' }
```

## Reading layout records

`layout.json` is keyed by A/Aprime/B/B-copy. Each entry records `layout`, `symbols_status`, all matching `functions` (runOperations, runOperationsLoop, executeWordMode, executeBuiltin), and the probe's retention/address, `probe_bytes` (expected padding bytes), and `probe_actual_bytes` (disassembled padding bytes; null for base). Functions include full symbol name, integer/hex address, size in bytes, mod64, and size provenance. ELF uses objdump's symbol table. Mach-O falls back to ordered nm symbols and disassembly extent when symbol-table sizes are unavailable; this extent may include alignment padding and must not be compared as an exact source-function size. An absent standalone function can mean inlining; it is not proof of deletion. Full symbol tables and disassembly are retained beside the JSON.

In this Linux build, `executeWordMode__func_183` calls `runOperations__func_186` at the source line 1956 ordinary (counted=false, worker=false) branch; `B-normal-callsite.txt` in the hot16 preparation directory retains the line-annotated evidence. Identify ordinary runOperations through its call sites from worker=false executeWordMode / executeOperationsMode, not anonymous suffix numbers alone. Worker=true enters the other loop and performs cancellation checks. Keep all instantiations in the record. Addresses are link-time virtual addresses, not ASLR runtime addresses. `mod64` is address modulo 64. Require multiple values for B's ordinary runOperations across the prepared layouts before treating the experiment as a layout test.

Windows now resolves PDB symbols through llvm-pdbutil and PE headers; see [1403](TASK_CONTROL_IMPL_1403.md) for native verification and placement results. Missing target symbols, a missing nonbase probe, or missing/mismatched padding stop prepare/smoke on Windows as well as ELF/Mach-O. Symbol availability alone does not certify actual layout movement. The begin/end labels are rooted along with the function; their address interval must contain contiguous disassembled NOPs whose decoded byte widths sum to the expected size. Same-address aliases can be resolved through the symbol table. Every layout retains the existing exact B/B-copy .text comparison; matching hashes establish reproducibility, not speed invariance. Reusing --builds inherits its stored layout; a nonbase --layout together with --builds is rejected.

For subsequent approved measurements, compare each workload's B/A and B/Aprime separately against median +1% and p95 +2%. If the sign or inside/outside classification changes with layout or independent run, report inconclusive. Smoke verifies checksums only and cannot settle that question.

## Duration

※推測です: allow roughly 2–15 minutes per four-build prepare per layout and 8–60 minutes for all four layouts, depending on caches and host. Smoke has 45 short processes per layout (180 total); allow another 1–5 minutes in total as a hypothesis, not a performance result. The 1390 proposed measurement has 1,575 processes per independent run; assuming 0.1–2 seconds per process gives about 3–53 minutes/run, or 24–424 minutes for four layouts with two runs each, plus preparation. Linux/macOS/Windows share this hypothetical range because native timing costs were not measured. INTERPRET and machine load may exceed it.

## Linux verification

R2 rerun results (previous records remain in `.work/1402/`):

| Layout | B ordinary runOperations | Function bytes | mod 64 | B/B-copy .text bytes | NOP bytes expected/actual |
|---|---|---:|---:|---:|---:|
| base | `0x1141d90` | 11014 | 16 | 1387299 | — |
| tail64 | `0x1141e10` | 11014 | 16 | 1387379 | 64/64 |
| hot16 | `0x1141de0` | 11014 | 32 | 1387331 | 16/16 |
| hot32 | `0x1141df0` | 11014 | 48 | 1387347 | 32/32 |

All four prepares and final smoke runs passed. Each layout has 45 checksum-verified processes (180 total in final smoke runs) and byte-identical B/B-copy .text. All twelve nonbase probe instances survived GC and their disassembled padding matches the expected 64/16/32 bytes (64/16/32 NOP instructions on x86_64). B's ordinary runOperations has three distinct mod64 positions: 16, 32 and 48. The table is artifact evidence, not timing evidence. Preparation records are `.work/1402-r2/{base,tail64,hot16,hot32}/`; smoke records are the corresponding `*-smoke/` directories. Previous `.work/1402/` records are preserved. `.work/1402-r2/layout-comparison.json` records the checked cross-layout list.

Python byte compilation, `python3 scripts/check-docs.py` (findings: 0), and `git diff --check` passed. Padding parser checks reject non-NOPs and gaps and accept same-address symbol aliases; `.work/1402-r2/parser-checks.json` retains the results. A negative check against the Linux tail64 B binary deliberately expects 60 bytes: validation stops on 64 actual bytes and retains both values in `.work/1402-r2/mismatch-check/layout.json`. These are not native Mach-O/PE execution. Product src/ and build.zig have no diff.

## aarch64 object verification

On Linux, the exact generated C fragments were compiled with `zig cc -target aarch64-macos -c` and disassembled with `llvm-objdump-21 -d`. The objects are Mach-O arm64 in `__TEXT,__text`. `tail64`: 16 NOPs / 64 bytes; `hot16`: 4 NOPs / 16 bytes; `hot32`: 8 NOPs / 32 bytes. The address intervals and decoded instruction bytes agree with the expected values. An 18-byte negative check fails compilation because it is not divisible by four. Sources, objects, disassemblies, the negative-check diagnostic and `aarch64-check.json` are under `.work/1402-r2/`.

Native Windows execution and PDB extraction are recorded in [1403](TASK_CONTROL_IMPL_1403.md). Native macOS execution, final Mach-O probe ordering and ordinary runOperations movement, applicability of the fallback link-order methods and timing guideline sensitivity remain unverified. Claude will perform Mac verification. No --mode measure was executed. See the [Japanese report](TASK_CONTROL_IMPL_1402.ja.md).
