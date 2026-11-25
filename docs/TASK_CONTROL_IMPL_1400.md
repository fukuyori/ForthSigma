# AC-28: task exclusion checks (1400)

The core suite now inspects the complete dictionary, filtered HELP metadata and
encoded dictionary images independently of the search order. See the
[configuration matrix](TASK_CONTROL_CONFIG_MATRIX.md#ac-28構成別の検査1400)
for configuration expectations. The Japanese counterpart is
[TASK_CONTROL_IMPL_1400.ja.md](TASK_CONTROL_IMPL_1400.ja.md).

`src/tests/task_exclusion_test.zig` checks all 58 public task words, every
`task_` builtin tag (including future internal tags), and the absence of a
task-specific OpKind. An extension-disabled dictionary has no task builtin
entries, including nameless entries. Builtin enum tags remain common to builds;
this test does not require removing wire identifiers or shared host services.

Filtered HELP metadata has 58 task entries with extension enabled and zero
otherwise. This filtering is independent of help=false. With help=false the
HELP entry point is absent; the test explicitly imports the metadata, so its
presence in the test executable does not establish its presence in the product.

For extension-disabled builds, the real image encoder output is parsed and
checked for task names/builtin entries and excluded direct builtin operations.
Each task builtin is then injected separately as an added builtin word and as a
direct `.builtin` operation, encoded with a valid checksum, and rejected by
restore with InvalidImage. Re-encoding the destination before and after rejection
must produce identical bytes. These tests do not rely on rejection of an unrelated
extension builtin or on a bad checksum.

The configuration runner also uses the public SAVE and LOAD-DICTIONARY words.
An extension-enabled producer loads EXTENSION and compiles references to all 58
task words before SAVE. Each extension-disabled consumer saves its own dictionary
and rejects that producer image with -264, executes a pre-existing definition,
and successfully defines and executes another word after rejection. A second
extension-enabled producer image saved without loading EXTENSION is accepted;
both the existing word and the imported word must execute. Feature configuration
alone does not make a base-only image incompatible.

For source failures, each of the 58 task words is compiled in a new definition
on an extension-disabled VM. After UnknownWord and normal error-report recovery,
the existing word count, code count and HERE must match their earlier values;
the failed definition is absent and both existing and subsequent definitions run.
This is error recovery, not a promise to roll back successful earlier source
definitions or arbitrary side effects.

## Validation

Windows AMD64, Zig 0.17.1, Python 3.14.3, 2026-11-25. The final observed HEAD
was `d3d0d66`; work started at `f33eb57`. No commit, branch or push was performed.
Zig's global cache was set to the checkout-local `.zig-global-cache` because the
default cache was not writable in this environment.

| Command | Result |
|---|---|
| `zig build test` | Passed |
| `zig build test -Ddebug=false` | Passed |
| `zig build -Dextension=false test` | Passed |
| `zig build runtime-test` | Passed |
| `python tests/scripts/verify-task-public-matrix.py` | C00–C17: all 18 configurations passed; all 155 commands succeeded |
| `python scripts/check-docs.py` | Passed, findings: 0 |
| `zig fmt --check src/forth_test.zig src/tests/task_exclusion_test.zig` | Passed |

The seven extension-disabled configurations C00/C02/C04/C06/C12/C13/C17 all
produced `-264 42 9` for foreign task-image rejection and `0 42 77` for the
base-only image acceptance check. Core tests also verified byte-identical
dictionary encodings after each isolated builtin/direct-Op rejection.
Logs are in `.work/ac28-*.log` (the final matrix run is
`.work/ac28-matrix-final.log`); configuration logs, commands and results are in
`.work/task-public-matrix/`. Japanese word-reference source fingerprints were
refreshed after confirming that only tests changed and no word descriptions
required translation changes. Linux and macOS execution of these new checks is
delegated to Claude and remains unperformed here.

`tque show 1400` was attempted but could not open its storage lock (Access denied).
No tque files were accessed directly and no completion flag was set.

TaskManager code retention, ordinary-loop machine code, performance and the
128 MiB measurements are outside these tests. The generated-code comparison
remains tracked under 1390. No new image compatibility policy was introduced.
