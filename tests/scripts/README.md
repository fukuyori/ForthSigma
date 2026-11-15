# Test and verification scripts

Run these scripts from the repository root. `test-*` contains regression tests,
`verify-*` contains integration and comparison checks, and `probe-*` collects
reference results. `gforth-p00/` contains the P00 Gforth reference suite; see its
README for the required reference build. Platform and reference-runtime
requirements still apply to individual scripts.

Examples:

```sh
python3 tests/scripts/test-word-reference.py --sigma zig-out/bin/sigma
python3 tests/scripts/test-line-editor.py --sigma zig-out/bin/sigma
python3 tests/scripts/verify-p10.py --sigma zig-out/bin/sigma --output .work/p10/report.json
python3 tests/scripts/verify-feature-matrix.py --platform macos
```

Build, distribution, data-generation, documentation-generation and benchmark
commands remain in `scripts/`, including `check-docs.py`, `word-reference.py`,
its `word_reference_examples.py` helper, and `benchmark-runtime.py`.
`test-benchmark-runtime.py` requires Linux's process CPU clock API.

Recorded measurement JSON and original external review transcripts preserve
paths as they were when recorded. Current commands use `tests/scripts/`.
