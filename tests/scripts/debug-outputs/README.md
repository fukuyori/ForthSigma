# Outputs of the debugging features on each system

Japanese version: [README.ja.md](README.ja.md).

This folder keeps what `tests/scripts/verify-debug-outputs.py` recorded on each system,
so that the output of the debugging features (see [docs/DEBUGGING.md](../../../docs/DEBUGGING.md))
can be compared between systems line by line. It was made for tque #890: comparing the
output on macOS with the output on Windows directly.

| File | System |
|---|---|
| `macos.json` | macOS 27.2, Apple silicon (arm64), FORTH/Sigma 0.11.0 |
| `windows.json` | Windows (to be recorded) |

## What is recorded

The script runs 27 cases, each in a new folder in the system's temporary folder, with the
same program (`prog.fs` of docs/DEBUGGING.md) and inputs on every system, so the outputs
hold no absolute paths. For each case it keeps:

- the arguments and the standard input it gave,
- the exit code,
- the standard output and the standard error, as they came (decoded as UTF-8),
- the files the case writes: `fmt.fs` after `--format`, and `run.jsonl` of `--debug-log`.

The cases are the examples of docs/DEBUGGING.md (the backtrace, `--max-steps`, `--trace`,
`~~` and `~~BT`, `DBG` with the keys from a pipe, `WATCH`, `--profile`, `--coverage`,
`--lint`, `--format-check`, `--debug-log`) and the features without one (`--max-steps=N`,
`--trace-limit`, `~~1BT` and `ONCE`, `~~VALUE` and `~~VARIABLE`, the `DBG` keys `n`, `u`,
`d`, and `s`, `BREAK:` and `BREAK"`, `UNWATCH`, `.COVER-RAW`, the four kinds of `--lint`
findings, `--format`, `--format-indent`, and `--`). The list is `CASES` in the script.

## Recording on a system

From the root of the repository, with a release build:

```sh
zig build -Doptimize=fast
python3 tests/scripts/verify-debug-outputs.py --sigma zig-out/bin/sigma --out tests/scripts/debug-outputs/macos.json
```

On Windows:

```powershell
zig build -Doptimize=fast
python tests/scripts/verify-debug-outputs.py --sigma zig-out/bin/sigma.exe --out tests/scripts/debug-outputs/windows.json
```

The file records the system, the processor, and the first line of the banner (the
version). Commit the file so that the other system can compare with it.

## Comparing two systems

```sh
python3 tests/scripts/verify-debug-outputs.py --compare tests/scripts/debug-outputs/macos.json tests/scripts/debug-outputs/windows.json
```

For each case of the first file, the case of the same name in the second file is
compared: the exit code, the standard output, the standard error, and the files. Before
comparing, CR LF is taken as LF, since Windows ends lines with CR LF; nothing else is
changed. Each case is reported as one line:

- `[same]` — everything is the same.
- `[differs]` — followed by what differs (`exit 1 / 0`, `stdout`, `stderr`, `file fmt.fs`)
  and, for the standard output and error, each line that differs: the line number, then
  the line of the first file and the line of the second, quoted.
- `[missing]` — the second file has no case of that name.

The last line counts the cases and those that differ. The exit status is 0 when none
differ and 1 otherwise.

Every difference is to be explained before the check is done: it is either a bug, or a
difference of the systems that is meant (record it in docs/DECISIONS.md). Both files
should come from the same commit; compare the version lines at the top of the report.
