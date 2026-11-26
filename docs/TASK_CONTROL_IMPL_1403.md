# tque 1403: Windows PDB single-VM layout inspection

2026-11-26, Windows x86_64, Zig 0.17.1. Adds Windows symbol resolution to the layout variants in [1402](TASK_CONTROL_IMPL_1402.md). See the [Japanese report](TASK_CONTROL_IMPL_1403.ja.md).

## Implementation

On Windows [the runner](../tests/scripts/single-vm-ab.py) reads sigma.pdb beside the executable. `--pdbutil` overrides the tool; the default searches PATH, then uses `C:\Program Files\LLVM\bin\llvm-pdbutil.exe`. A missing tool or failed invocation stops execution. Full `dump --symbols --publics` output is retained in `*-pdb-symbols.txt`.

S_LPROC32/S_GPROC32 (including _ID variants) supply the section number, decimal offset and code size. PE32+ headers supply ImageBase and section VirtualAddress. The link-time virtual address is ImageBase + section VirtualAddress + offset; mod64 uses that address, before ASLR. layout.json records the PDB path/hash, tool/version, ImageBase and its mod64, SectionAlignment and its mod64, and all section VirtualAddresses and their mod64 values.

All instances of runOperations, runOperationsLoop, executeWordMode, executeBuiltin, executeWord and executeCompiled are recorded when standalone symbols exist. Inlining does not create an artificial standalone function. PDB addresses and code sizes delimit objdump instruction rows in `*-normal-functions.txt`, with function-name headings. Sizes come from PDB code size, not the distance to the next symbol. Missing all targets or an empty target disassembly range stops execution.

Nonbase layouts require the svab_layout_probe procedure record. S_PUB32 resolves svab_padding_begin/end; the existing validator sums contiguous decoded NOP byte widths. Missing/mismatched padding, non-NOPs or gaps stop execution. Records include the probe input section .text$a, whether it precedes all target functions, and whether it precedes the first Zig procedure in sigma_zcu.obj. The input section name comes from the generated C attribute. ELF/Mach-O symbol-resolution paths are unchanged.

## Execution and results

| Layout | B ordinary runOperations virtual address | Bytes | mod 64 | Probe virtual address | NOP bytes |
|---|---|---:|---:|---|---:|
| base | `0x140041190` | 9979 | 16 | — | — |
| tail64 | `0x140041190` | 9979 | 16 | 0x140193450 | 64 |
| hot16 | `0x140041190` | 9979 | 16 | 0x140193450 | 16 |
| hot32 | `0x140041190` | 9979 | 16 | 0x140193450 | 32 |

All four prepare/smoke pairs passed. Each smoke verified 45 processes (180 total); reused-build smoke verified another 45. B/B-copy .text matched byte-for-byte for every layout. All twelve nonbase probes matched 64/16/32 NOP bytes. ImageBase was 0x140000000 and SectionAlignment was 4096, both multiples of 64; every section VirtualAddress was also a multiple of 64. Every probe followed Zig code: B had its first Zig procedure at 0x14001e0f0 and probe at 0x140193450. B ordinary runOperations had the same address/mod64 across all four layouts. The comparison is retained in `.work/1403/layout-comparison.json`. Base/reuse symbol artifacts were refreshed with the final parser, recording artifact_refresh_script_sha256 in their manifests.

Reusing `.work/1391-prepared/builds.json` also matched the manual B runOperations__func_144 observation: section 0001, offset 262544, code size 9979 bytes; virtual address 0x140041190, mod64 16. Identify the ordinary instance by executeWordMode call sites and the worker=false path in src/forth.zig, rather than the anonymous number alone. The null-context branch in executeWord jumps to executeWordMode__func_141 (0x140040240), whose call at 0x14004059f targets runOperations__func_144. The disassembly is retained in reuse/B-normal-callsite.txt; objdump does not provide PDB source-line annotations here.

PowerShell set ZIG_GLOBAL_CACHE_DIR to `$PWD/.work/codex-cache/global` and ZIG_LOCAL_CACHE_DIR to `$PWD/.work/codex-cache/local`. Each layout ran `--mode prepare --layout <layout> --out .work/1403/<layout>`, followed by `--mode smoke --builds .work/1403/<layout>/builds.json --out .work/1403/<layout>-smoke`. Reused-build smoke artifacts are in `.work/1403/reuse`. manifest.json and builds.json retain the full commands.

## Limits and alternatives

The observed .text$a probe follows the Zig code; adding padding there does not establish a hot-function layout perturbation. Treat unchanged mod64 values as an ineffective layout experiment, not evidence of timing invariance. Hypothesis only: candidates for a copied-build experiment are an ordinary .text probe object explicitly linked before sigma_zcu.obj, or function-section generation combined with COFF symbol-order controls. Zig 0.17.1 support, linker applicability, probe retention and actual sub-64-byte movement are all unverified; neither candidate is implemented here. Verify final addresses before any measurement.

No --mode measure was run. Performance differences and timing acceptance remain unverified. Native ELF/Mach-O runs were not repeated. Product src/ and build.zig are unchanged; no tque or Git mutation was performed. Only copied build.zig files carry layout changes.

## Validation

`python -m py_compile tests/scripts/single-vm-ab.py`, `python scripts/check-docs.py` (findings: 0), and `git diff --check` passed. `.work/1403/verify.py` additionally confirmed that extracted function ranges start and end at the PDB address/code-size boundaries for every control.

Parser checks covered S_LPROC32/S_GPROC32, decimal offsets, PE address mapping, public-label aliases, missing labels, non-NOP instructions and instruction gaps. Results are in `.work/1403/parser-checks/results.json`. A real tail64 B negative check expecting 60 bytes stopped on 64 actual bytes. Another check suppressed the PDB procedure record and stopped on the missing probe. Diagnostics are in `.work/1403/negative-checks.json`; failure layout.json records remain in negative-mismatch / negative-missing-probe.
