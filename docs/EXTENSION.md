# ForthSigma Extension Manual

Japanese version: [EXTENSION.ja.md](EXTENSION.ja.md). This English version is the primary one.

This guide is for writing Forth programs that use terminals, files, child processes and background calculations. Each chapter starts with the basic use, gives a runnable example, then explains the details. Use the [word reference](WORD_REFERENCE.md) for individual contracts and the [user manual](USER_MANUAL.md) for the language and command line.

Save each Forth code block as a separate UTF-8 `.fs` file and run it from the repository root with `zig-out/bin/sigma.exe path/to/example.fs` on Windows. Use `zig-out/bin/sigma` on POSIX. The examples use the full build, decimal numbers and separate processes; `EXEC-LIMITED` also needs debug support. If the executable is absent, build it with `zig build`. Examples that use files expect the repository root as the working directory. Temporary example files use `.work/1457/`; create that directory first. No example opens a graphics window or audio device.

## 1. Loading the vocabulary and common rules

`REQUIRE-EXTENSION` loads the vocabulary once. `ALSO EXTENSION` adds it to the search order; `PREVIOUS` removes that search-order entry. Loading does not itself select the vocabulary. Put the loader at the top level, outside colon definitions.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
HOST-OS TYPE CR
PREVIOUS
BYE
```

On Windows this prints `windows`. `HOST-OS ( -- c-addr u )` reports the compilation target family: `windows`, `linux` (including WSL and Android), `macos`, or `unknown`. Treat unfamiliar future values as unknown. The returned text is borrowed and read-only until the next call or dictionary restore; copy it to keep it.

Extension selection is independent of graphics and audio. `-Dextension=false` removes the loader and vocabulary (the loader then gives unknown word, -13). `-Ddebug=false` removes `EXEC-LIMITED`, but not task control. `-Dfiles=false` removes ordinary file words and leaves file-dependent extension operations unavailable; memory-only path compaction and grapheme operations do not need files. `-Dgraphics=false` makes combined paint waits unavailable; `-Daudio=false` removes PCM facilities. `-Dimage=false` removes the saved-application words. `-Dhelp=false` removes HELP, not the extension APIs.

An `ior` of zero means the API call succeeded. It does not mean that a process exited successfully, a task succeeded, or a wait found a condition. Read the other outputs. `THROW` consumes zero harmlessly and raises a nonzero error; use it when the program should stop on failure. Errors requiring recovery should be inspected first, especially partial I/O counts and short-buffer results. Memory/stack validation and missing host capabilities may THROW directly, so an API returning `ior` can still throw. The precise distinction is word-specific. `CATCH` does not close resources or undo side effects for you.

For relative waits in this guide, `ms=0` polls, a negative value waits without an overall deadline, and a positive value uses one monotonic deadline. Timeout and EOF have different outputs. A ready indication does not reserve bytes or capacity. Terminal Ctrl+C in supported wait scopes throws -28; a byte 3 read from a file or pipe is data. See chapters 6 and 9 for interrupt limits and error handling.

### Words in this chapter

[`HOST-OS`](WORD_REFERENCE.md#w-455854454e53494f4e3a484f53542d4f53).

Related words in other groups: [`REQUIRE-EXTENSION`](WORD_REFERENCE.md#w-53796e7461783a524551554952452d455854454e53494f4e).

## 2. Terminal display and standard events

Use `TERM-MODE!` to replace the terminal presentation request, and `TERM-MODE@` to read accepted requests. Use `EKEY-WAIT` for complete standard input events, rather than repeatedly reading partial escape sequences yourself. This small example only resets presentation and queries geometry, so it also runs with redirected output.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
0 TERM-MODE! THROW
TERM-MODE@ . COLS . ROWS . CR
PREVIOUS
BYE
```

With redirected output the result is `0 80 24`. `COLS` and `ROWS` share `FORM`'s output-target rules: geometry if available, otherwise 80 columns and 24 rows; output capture uses the largest positive cell for columns and 1 row.

Combine request bits with `OR`: `TERM-ALT-SCREEN`=1, `TERM-PASTE`=2, `TERM-HIDE-CURSOR`=4, `TERM-MOUSE`=8. For example, the mask for an alternate screen with a hidden cursor is `TERM-ALT-SCREEN TERM-HIDE-CURSOR OR`. A successful mask replaces all previous bits. Restore explicitly with `0 TERM-MODE! THROW`, including your error path. The accepted mask describes requests, not terminal acknowledgment. Mouse and paste reporting apply only while raw input is active. Windows ignores the paste request. Standard output must be a suitable terminal for nonzero requests; captured Forth output does not capture these terminal controls.

The following event example reads a selected file, avoiding an interactive wait. It creates and deletes a small file; EOF is a complete event with a true flag.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
S" .work/1457/event.dat" W/O CREATE-FILE THROW CONSTANT EF
S" A" EF WRITE-FILE THROW
EF CLOSE-FILE THROW
: EVENTS
  0 EKEY-WAIT THROW SWAP . . CR
  0 EKEY-WAIT THROW DROP K-EOF = . CR ;
S" .work/1457/event.dat" R/O OPEN-FILE THROW CONSTANT INPUT-F
' EVENTS INPUT-F INFILE-EXECUTE
INPUT-F CLOSE-FILE THROW
S" .work/1457/event.dat" DELETE-FILE THROW
PREVIOUS
BYE
```

This prints `65 -1` and `-1`: character A and then EOF. `EKEY-WAIT ( ms -- event flag ior )` returns `0 false 0` on timeout and `K-EOF true 0` on EOF. Partial UTF-8 and escape input survives timeouts. Files decode UTF-8 but retain literal ESC and byte 3. `INFILE-EXECUTE ( xt fileid -- )` borrows the selected file; close it explicitly after return.

After consuming `K-MOUSE`, call `EKEY-MOUSE ( -- column row buttons wheel )`. Coordinates start at zero; button bits are left=1, right=2, middle=4; wheel up is 1 and down is -1. `EKEY?` peeks without changing this metadata. `K-PASTE-BEGIN` and `K-PASTE-END` delimit bracketed paste on supporting input; pasted control bytes remain text. Switching to byte or GRAPHICS input ends paste interpretation. Do not read the same input through two consumers expecting duplicate events.

### Words in this chapter

[`TERM-MODE!`](WORD_REFERENCE.md#w-455854454e53494f4e3a5445524d2d4d4f444521), [`TERM-MODE@`](WORD_REFERENCE.md#w-455854454e53494f4e3a5445524d2d4d4f444540), [`COLS`](WORD_REFERENCE.md#w-455854454e53494f4e3a434f4c53), [`ROWS`](WORD_REFERENCE.md#w-455854454e53494f4e3a524f5753), [`EKEY-WAIT`](WORD_REFERENCE.md#w-455854454e53494f4e3a454b45592d57414954), [`EKEY-MOUSE`](WORD_REFERENCE.md#w-455854454e53494f4e3a454b45592d4d4f555345), [`TERM-ALT-SCREEN`](WORD_REFERENCE.md#w-455854454e53494f4e3a5445524d2d414c542d53435245454e), [`TERM-PASTE`](WORD_REFERENCE.md#w-455854454e53494f4e3a5445524d2d5041535445), [`TERM-HIDE-CURSOR`](WORD_REFERENCE.md#w-455854454e53494f4e3a5445524d2d484944452d435552534f52), [`TERM-MOUSE`](WORD_REFERENCE.md#w-455854454e53494f4e3a5445524d2d4d4f555345), [`K-MOUSE`](WORD_REFERENCE.md#w-455854454e53494f4e3a4b2d4d4f555345), [`K-PASTE-BEGIN`](WORD_REFERENCE.md#w-455854454e53494f4e3a4b2d50415354452d424547494e), [`K-PASTE-END`](WORD_REFERENCE.md#w-455854454e53494f4e3a4b2d50415354452d454e44).

Related words in other groups: [`EKEY`](WORD_REFERENCE.md#w-464f5254483a454b4559), [`EKEY?`](WORD_REFERENCE.md#w-464f5254483a454b45593f), [`K-EOF`](WORD_REFERENCE.md#w-454b4559533a4b2d454f46), [`INFILE-EXECUTE`](WORD_REFERENCE.md#w-464f5254483a494e46494c452d45584543555445).

## 3. Nonblocking file I/O

Wait for readiness, transfer the available part, and keep the remaining bytes for a later turn. Keep EOF separate from a temporarily empty input. The example uses a regular file so no external producer is needed.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
CREATE IDS 1 CELLS ALLOT
CREATE BUF 16 ALLOT
S" .work/1457/io.dat" W/O CREATE-FILE THROW CONSTANT WF
WF IDS !
IDS 1 0 WAIT-WRITABLE THROW . CR
S" hello" WF WRITE-AVAILABLE THROW . CR
WF FLUSH-FILE THROW WF CLOSE-FILE THROW
S" .work/1457/io.dat" R/O OPEN-FILE THROW CONSTANT RF
RF IDS !
IDS 1 0 WAIT-FILES THROW . CR
BUF 16 RF READ-AVAILABLE THROW DROP BUF SWAP TYPE CR
RF CLOSE-FILE THROW
S" .work/1457/io.dat" DELETE-FILE THROW
PREVIOUS
BYE
```

It prints `0`, `5`, `0`, and `hello`. The arrays contain file IDs as cells, not OS handles. `WAIT-FILES` and `WAIT-WRITABLE` take `( addr n ms -- index ior )`, with 1–64 entries and a zero-based result. All entries are validated before waiting. EOF or an I/O error also makes a target ready; timeout returns `-1 0`. A bad target can return its index and an error, even when an earlier entry is ready.

`READ-AVAILABLE ( addr capacity fid -- count eof? ior )` returns immediately with currently available bytes. `count=0`, false EOF and zero ior means try later, not end of input. A partial count may accompany an error: preserve/process those bytes before recovery. A zero-capacity read validates the request but does not consume input or advance EOF observation. Ordinary reads and event reads share the file's pending bytes.

`WRITE-AVAILABLE ( addr length fid -- accepted ior )` copies accepted bytes before returning. Advance the source by that count and retry the remainder only when writable. Acceptance does not prove delivery. On Windows, queued delivery can fail later; the error remains until close. `FLUSH-FILE` and close wait for delivery and can therefore block. An interrupted Windows close returns -516 and retains the ID and queue for retry. POSIX writes report their direct result and do not use that Windows delivery queue.

The new four words throw -28 on terminal interruption. Windows synchronous duplex pipes, and stdin shared with stdout/stderr as the same pipe object, are rejected by these APIs with EINVAL (-534); ordinary file and older event operations keep their own contracts. See [the I/O design](ASYNC_IO_DESIGN.md) for these limits.

### Words in this chapter

[`WAIT-FILES`](WORD_REFERENCE.md#w-455854454e53494f4e3a574149542d46494c4553), [`READ-AVAILABLE`](WORD_REFERENCE.md#w-455854454e53494f4e3a524541442d415641494c41424c45), [`WRITE-AVAILABLE`](WORD_REFERENCE.md#w-455854454e53494f4e3a57524954452d415641494c41424c45), [`WAIT-WRITABLE`](WORD_REFERENCE.md#w-455854454e53494f4e3a574149542d5752495441424c45).

Related words in other groups: [`OPEN-FILE`](WORD_REFERENCE.md#w-464f5254483a4f50454e2d46494c45), [`CLOSE-FILE`](WORD_REFERENCE.md#w-464f5254483a434c4f53452d46494c45), [`FLUSH-FILE`](WORD_REFERENCE.md#w-464f5254483a464c5553482d46494c45).

## 4. Child processes and pipes

Use `PROC-*` when you need separate stdin, stdout and stderr, explicit arguments, or cancellation. Create a configuration, copy arguments into it, start it, drain output, observe completion, then free it. `PROC-START` does not invoke a shell. This Windows example invokes Windows PowerShell explicitly and produces only a short line, so waiting before reading cannot fill its output pipe.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
PROC-NEW THROW CONSTANT P
S" powershell.exe" P PROC-ARG THROW
S" -NoProfile" P PROC-ARG THROW
S" -NonInteractive" P PROC-ARG THROW
S" -Command" P PROC-ARG THROW
S" Write-Output child-ok" P PROC-ARG THROW
P PROC-START THROW
P PROC-STDIN THROW CLOSE-FILE THROW
P -1 PROC-WAIT THROW . . CR
CREATE CHILD-BUF 64 ALLOT
CHILD-BUF 64 P PROC-STDOUT THROW READ-AVAILABLE THROW
DROP CHILD-BUF SWAP TYPE
P PROC-FREE THROW
PREVIOUS
BYE
```

It prints exit code `0`, state `2`, and `child-ok`. The corresponding POSIX shell arguments are `/bin/sh`, `-c`, `printf child-ok`. The following configuration-only example checks both argument lists without needing either OS's shell to run. On POSIX, use the second list in the preceding example in place of the five Windows arguments.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
PROC-NEW THROW CONSTANT WIN-P
S" powershell.exe" WIN-P PROC-ARG THROW
S" -NoProfile" WIN-P PROC-ARG THROW
S" -NonInteractive" WIN-P PROC-ARG THROW
S" -Command" WIN-P PROC-ARG THROW
S" Write-Output child-ok" WIN-P PROC-ARG THROW
WIN-P PROC-FREE THROW
PROC-NEW THROW CONSTANT POSIX-P
S" /bin/sh" POSIX-P PROC-ARG THROW
S" -c" POSIX-P PROC-ARG THROW
S" printf child-ok" POSIX-P PROC-ARG THROW
POSIX-P PROC-FREE THROW
." configurations-ok" CR
PREVIOUS
BYE
```

This prints `configurations-ok`. The first `PROC-ARG` is the executable name; later calls append arguments, including empty ones. `PROC-CWD` sets the child's directory (empty inherits at startup). `PROC-ENV` applies edits in order: `NAME=VALUE` sets, `NAME` removes, `NAME=` sets an empty value. Configuration is copied and may only be changed before startup. Limits are 64 process records, 128 arguments, 128 environment edits and 64 KiB of configuration strings including NUL terminators. Windows `.bat`/`.cmd` files require explicit `cmd.exe`; quoting and shell metacharacters are not interpreted by the direct process API.

`PROC-IO ( mode which proc -- ior )` selects stream 0/1/2 (stdin/stdout/stderr). Mode 0 creates a pipe (the default for all three), 1 inherits, 2 uses the null device, and 3 merges stderr into stdout (stderr only). The three stream getters return ordinary file IDs, or zero when not piped/when merged. Close a PROC stream with `CLOSE-FILE`; closing stdin sends EOF but does not join the child. Drain both stdout and stderr while the child runs when output may be large. Waiting for termination first can deadlock on full pipes.

`PROC-STATUS` and `PROC-WAIT` return `( state code ior )`: state 0=configuring, 1=running, 2=exited, 3=POSIX signal. A wait timeout leaves state 1; status can be read repeatedly. Exit status and pipe EOF are independent; descendants may keep a pipe open. Windows retains unsigned 32-bit exit codes in state 2; POSIX state 3 reports the actual signal number.

`PROC-TERM` requests group termination without waiting: POSIX SIGTERM, Windows Job termination with code 143. `PROC-KILL` uses SIGKILL or Windows code 137. If needed, explicitly TERM, wait for a chosen grace period, then KILL and wait again. `PROC-FREE` rejects a running root with EBUSY; it discards unread/undelivered pipe data when freeing a terminal record. Cleanup failure retains ownership for retry. Ctrl+C or an ordinary Forth exception does not kill the child. Process IDs and file IDs are owned resources; copying their numeric values does not copy ownership.

For a simple one-way shell command, use the core file words `OPEN-PIPE` and `CLOSE-PIPE`. They are available without selecting EXTENSION when files support is enabled. This command is accepted by both Windows and POSIX shells:

```forth
S" echo pipe-ok" R/O OPEN-PIPE THROW CONSTANT SH-PIPE
CREATE SH-BUF 64 ALLOT
SH-BUF 64 SH-PIPE READ-LINE THROW DROP
SH-BUF SWAP TYPE CR
SH-PIPE CLOSE-PIPE THROW . CR
BYE
```

It prints `pipe-ok` and status `0`. `OPEN-PIPE ( addr u fam -- fid ior )` accepts R/O or W/O, not R/W; `BIN` is allowed. Close these IDs with `CLOSE-PIPE ( fid -- status ior )`, which waits for the shell and does not update `$?`. Do not interchange CLOSE-FILE and CLOSE-PIPE. `BROKEN-PIPE-ERROR` is -544, but Windows CRT may return EINVAL (-534) on a closed pipe. Pipe commands share terminal state; use SYSTEM/SH for foreground interactive commands. See [process management](PROCESS_MANAGEMENT_DESIGN.md) and [one-way pipes](USER_MANUAL.md#one-way-shell-pipes-p06b).

### Words in this chapter

[`PROC-NEW`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d4e4557), [`PROC-ARG`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d415247), [`PROC-CWD`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d435744), [`PROC-ENV`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d454e56), [`PROC-IO`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d494f), [`PROC-START`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d5354415254), [`PROC-STDIN`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d535444494e), [`PROC-STDOUT`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d5354444f5554), [`PROC-STDERR`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d535444455252), [`PROC-STATUS`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d535441545553), [`PROC-WAIT`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d57414954), [`PROC-TERM`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d5445524d), [`PROC-KILL`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d4b494c4c), [`PROC-FREE`](WORD_REFERENCE.md#w-455854454e53494f4e3a50524f432d46524545).

Related words in other groups: [`OPEN-PIPE`](WORD_REFERENCE.md#w-464f5254483a4f50454e2d50495045), [`CLOSE-PIPE`](WORD_REFERENCE.md#w-464f5254483a434c4f53452d50495045), [`BROKEN-PIPE-ERROR`](WORD_REFERENCE.md#w-464f5254483a42524f4b454e2d504950452d4552524f52).

## 5. Filesystem paths and Unicode text

Choose lexical path editing for text, OS resolution for an existing path, metadata for a regular file, and synchronization for a writable file. They solve different problems. This example edits a path and examines VERSION without modifying it.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
S" a/../b" COMPACT-FILENAME TYPE CR
CREATE PATH-BUF 8192 ALLOT
S" VERSION" PATH-BUF 8192 FILE>REALPATH THROW 0> . CR
S" VERSION" FILE-METADATA THROW 2DROP 0. D> . CR
PREVIOUS
BYE
```

It prints `b`, `-1`, `-1`: a compacted path, a nonempty resolved path, and a positive file size. `COMPACT-FILENAME` changes the supplied bytes in place and retains the address. Only `/` separates components, even on Windows; a terminal `.` or `..` is retained. It does not resolve links or check existence. Compaction can change the meaning of paths involving links; do not use it as a substitute for OS resolution.

`FILE>REALPATH ( name u buffer capacity -- needed ior )` follows links to an existing path and copies bytes without NUL. Capacity zero queries the required length; insufficient capacity returns needed and ERANGE (-546) without changing the destination. Other errors return zero and ior. Input/output may overlap. Windows returns UTF-8 extended paths with backslashes, POSIX native path bytes. Input is limited to 4095 bytes; no tilde expansion or FPATH search occurs.

`FILE-METADATA ( name u -- ud-size mtime-sec mtime-nsec ior )` follows links to a regular file. Size uses two cells; time is signed Unix UTC seconds plus nanoseconds 0–999999999. Actual precision depends on the filesystem. On failure all four numeric outputs are zero. A metadata query is not an atomic promise about a later read or a guarantee of detecting all changes.

Use `SYNC-FILE` when you explicitly need OS synchronization of a writable regular file. This separate example creates, synchronizes and deletes its own file:

```forth
REQUIRE-EXTENSION ALSO EXTENSION
S" .work/1457/sync.dat" R/W CREATE-FILE THROW CONSTANT SF
S" saved" SF WRITE-FILE THROW
SF SYNC-FILE THROW
SF CLOSE-FILE THROW
S" .work/1457/sync.dat" DELETE-FILE THROW
." sync-ok" CR
PREVIOUS
BYE
```

This prints `sync-ok`. SYNC-FILE flushes C buffering and requests fsync on POSIX or FlushFileBuffers on Windows. It retains the file handle on OS error and preserves logical position, pending input and EOF on success. It rejects standard streams, pipes, nonregular files and read-only handles. The operation may block without cancellation. It does not guarantee rename/parent-directory persistence or survival of arbitrary power loss. macOS uses fsync rather than F_FULLFSYNC.

### Grapheme boundaries

For text editing, `X-GRAPHEME` and `X-GRAPHEME-LAST` return the UTF-8 byte length of the first or last default extended grapheme cluster. They do not return terminal columns.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
S" abc" 2DUP X-GRAPHEME /STRING TYPE CR
S" abc" X-GRAPHEME-LAST . CR
PREVIOUS
BYE
```

This prints `bc` and `1`. Both return zero for an empty slice. The rules are Unicode 18.0.0 / UAX #29 revision 49; display-width tables are separate (15.1.0). Forward scanning checks the first cluster and one lookahead scalar; the last-cluster query validates the entire slice. Invalid UTF-8 throws -24, invalid memory -9, with arguments preserved. Pass the original address and whole length for a last-cluster query. Repeated backward deletion can take quadratic time. There is no normalization or locale tailoring. See [filesystem design](FILESYSTEM_DESIGN.md) and [grapheme design](GRAPHEME_DESIGN.md).

### Words in this chapter

[`COMPACT-FILENAME`](WORD_REFERENCE.md#w-455854454e53494f4e3a434f4d504143542d46494c454e414d45), [`FILE>REALPATH`](WORD_REFERENCE.md#w-455854454e53494f4e3a46494c453e5245414c50415448), [`FILE-METADATA`](WORD_REFERENCE.md#w-455854454e53494f4e3a46494c452d4d45544144415441), [`SYNC-FILE`](WORD_REFERENCE.md#w-455854454e53494f4e3a53594e432d46494c45), [`X-GRAPHEME`](WORD_REFERENCE.md#w-455854454e53494f4e3a582d4752415048454d45), [`X-GRAPHEME-LAST`](WORD_REFERENCE.md#w-455854454e53494f4e3a582d4752415048454d452d4c415354).

## 6. Execution budgets and interruption

`EXEC-LIMITED` runs a definition with a cooperative work budget. It is useful for bounding a calculation in the calling VM; it is not a background task or a way to resume an interrupted definition. It needs both extension and debug support.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
: SMALL 42 ;
' SMALL 100 EXEC-LIMITED . . CR
: SPIN BEGIN AGAIN ;
' SPIN 100 EXEC-LIMITED -280 = . CR
PREVIOUS
BYE
```

It prints `0 42` and `-1`. The stack effect is `( i*x xt u -- j*x ior )`. Zero budget means unlimited execution with interrupt checks. Normal completion returns zero; exhaustion belonging to this entry returns -280. Compare that value before using THROW: throwing it has the existing fatal StepLimit behavior, rather than an ordinary recoverable exception.

Units count entry dispatch, compiled operations, interpreted tokens inside the active entry and native work checkpoints. They are not milliseconds or CPU instructions. Up to 16 entries nest; all enclosing finite budgets are charged. Exhaustion of an outer entry unwinds to that owner. CLI step exhaustion, ordinary THROW and terminal interruption (-28) propagate outward.

Exhaustion restores entry stack depths after removing xt/u, but not prior values or side effects in memory, files, graphics or sound. Native/OS operations without checkpoints cannot be preempted. Input mode is not changed merely for computation. Earlier raw input is retained, but if the bounded input queue fills, Ctrl+C behind it may go undetected. A 20 ms design target is not a response-time guarantee. See [execution control](EXECUTION_CONTROL_DESIGN.md).

### Words in this chapter

[`EXEC-LIMITED`](WORD_REFERENCE.md#w-455854454e53494f4e3a455845432d4c494d49544544).

## 7. Tasks and combined waits

A task runs an admitted Forth calculation in a fresh, isolated worker VM. Define its entry before capturing an immutable dictionary snapshot. Submit its name and copied input bytes; copy the result back later. Here a VM is a separate Forth execution environment with its own memory and stacks. The main VM owns input, graphics, audio and OS resources. Task APIs must be called from the main thread.

### Submit, inspect, copy and release

This entry leaves its input unchanged as the result. It has the required worker stack effect `( input-addr input-u -- result-addr result-u )`.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
: ECHO-BYTES ;
CREATE RESULT-BUF 32 ALLOT
TASK-SNAPSHOT THROW CONSTANT SNAP
SNAP S" ECHO-BYTES" S" task-ok" TASK-I1 0 TASK-SUBMIT THROW CONSTANT JOB
JOB -1 TASK-WAIT THROW DROP TASK-SUCCEEDED = . CR
JOB TASK-STATE THROW 2DROP DROP TASK-SUCCEEDED = . CR
JOB RESULT-BUF 32 TASK-RESULT THROW DROP RESULT-BUF SWAP TYPE CR
JOB 0 RESULT-BUF 32 TASK-DIAGNOSTIC THROW . . CR
JOB TASK-RELEASE THROW
SNAP TASK-SNAPSHOT-RELEASE THROW
PREVIOUS
BYE
```

It prints `-1`, `-1`, `task-ok`, and `0 0`. The API shapes are:

| Word | Stack effect | Use |
| --- | --- | --- |
| TASK-SNAPSHOT | `( -- snap ior )` | Capture a dictionary version after defining the entry. |
| TASK-SUBMIT | `( snap name-addr name-u input-addr input-u profile stream -- task ior )` | Copy input and admit work. |
| TASK-STATE | `( task -- state requested result-u diag-u ior )` | Inspect state and cancellation request separately. |
| TASK-WAIT | `( task ms -- state wait-flags ior )` | Wait for termination without consuming results. |
| TASK-RESULT | `( task addr capacity -- needed state ior )` | Copy retained success bytes, without NUL. |
| TASK-DIAGNOSTIC | `( task which addr capacity -- needed code ior )` | Copy a UTF-8 diagnostic, without NUL. |
| TASK-CANCEL | `( task -- ior )` | Request cancellation without joining. |
| TASK-RELEASE | `( task -- ior )` | Consume the external ID; cancel pending work. |
| TASK-SNAPSHOT-RELEASE | `( snap -- ior )` | Consume the snapshot ID separately. |

States are `TASK-QUEUED`=1, `TASK-RUNNING`=2, `TASK-SUCCEEDED`=3, `TASK-FAILED`=4, `TASK-CANCELLED`=5. A cancellation request does not establish state 5; normal completion may win. Querying a failed or cancelled task can return ior=0. An empty success is still state 3. Results and diagnostics are non-consuming: copy repeatedly before release. Pending results return TASK-E-NOT-READY; insufficient capacity returns TASK-E-SHORT with needed/state (or needed/code) and leaves the destination unchanged. A zero-capacity result query can determine size. Diagnostic selectors are 0=primary, 1=secondary, 2=Writer, 3=reaping. An absent diagnostic is length/code 0/0; a cancellation diagnostic may have code zero. Each diagnostic is limited to 16 KiB, with 1 MiB total diagnostic storage.

Task and snapshot IDs are positive opaque cells, process-local and not reused. DUP is not retain. Releasing one invalidates every numeric copy. Snapshot release does not stop admitted tasks: they retain their version. TASK-RELEASE does not join or prove physical termination. After an accepted release even a host-error report can leave the external ID invalid; do not retry blindly with that ID. Keep calling task APIs on each main-loop turn so worker handback and reclamation advance. MS, EKEY? and drawing do not service task reclamation. A zero-deadline clock-only TASK-WAIT-MANY call (below) can service it without a live task ID.

For cancellation, request it explicitly and then wait for the terminal state. This calculation has no normal return, so a successful cancellation can be observed without racing a normal result.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
: WORK-FOREVER BEGIN AGAIN ;
TASK-SNAPSHOT THROW CONSTANT CANCEL-SNAP
CANCEL-SNAP S" WORK-FOREVER" S" x" TASK-I1 0 TASK-SUBMIT THROW CONSTANT CANCEL-JOB
CANCEL-JOB TASK-CANCEL THROW
CANCEL-JOB -1 TASK-WAIT THROW DROP TASK-CANCELLED = . CR
CANCEL-JOB TASK-RELEASE THROW
CANCEL-SNAP TASK-SNAPSHOT-RELEASE THROW
PREVIOUS
BYE
```

It prints `-1`. Applications that must keep processing UI should poll or use a combined wait instead of this unbounded single-task wait.

### Limits, snapshots and worker permissions

The current limits are one worker, a waiting queue of four, a ledger of 16 tasks, at most three snapshot versions of 4 MiB each, 16 MiB of shared input/result copies, and 128 MiB of additional task allocations. Capture a snapshot at load time and reuse it. Adding definitions later does not add them to an old snapshot. FORGET, MARKER, complete restore and dictionary append invalidate the structure for new submissions (TASK-E-STALE); obtain a fresh version. Ordinary variable changes leave old snapshots usable, with their old captured values. Work already admitted retains its version.

| Profile | Value | Maximum input | Maximum result | Queue residence |
| --- | --- | --- | --- | --- |
| TASK-G1 | 0 | 128 KiB | 512 KiB | 50 ms |
| TASK-G2 | 1 | 128 KiB | 128 KiB | 100 ms |
| TASK-T1 | 2 | 2 MiB | 64 KiB | 100 ms |
| TASK-I1 | 3 | 128 KiB | 4 KiB | 200 ms |

These queue deadlines differ from the caller's wait timeout. G1/G2 game work and T1 TUI work use the latest request for a stream; accepted replacement can cancel older work and suppress stale results. I1 uses bounded FIFO/backpressure. Use a stable nonnegative stream number for each independent flow. Failed admission preserves existing work; handle FULL/LIMIT rather than resubmitting in a tight loop. The utilization and response figures in [usage conditions](TASK_CONTROL_USAGE_CONDITIONS.md) are evaluation conditions, not guaranteed frame rates or stop times.

Workers receive copied bytes, not main-VM addresses, execution tokens or live resources. Reachable words and optimized operations are checked. Do not use file/terminal/graphics/audio operations, compilation, SYSTEM, nested task submission, dynamic EXECUTE/CATCH/THROW or unsupported loop forms in an entry. Use admitted arithmetic, memory, stack and branch operations; an empty colon definition as above is a valid identity entry. Check the word reference's worker classification, including every helper reached by the entry. A main-thread word existing in the snapshot does not make it worker-safe. Entry ABI violations fail the task with a diagnostic rather than returning an unchecked pointer.

### Waiting for several kinds of completion

`TASK-WAIT-MANY ( targets count events capacity ms -- n wait-flags ior )` takes aligned arrays. A target is five cells: `kind id arg0 arg1 tag`; an event is four cells: `index tag reason detail`. Allocate using TASK-WAIT-TARGET-CELLS and TASK-WAIT-EVENT-CELLS. Count is 1–64; capacity counts event records, not bytes, and must be at least count. Arrays must not overlap. The tag is your own identifying cell.

The following clock-only poll is also suitable for servicing reclamation on every main-loop turn after all external task IDs have been released.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
CREATE TARGET TASK-WAIT-TARGET-CELLS CELLS ALLOT
CREATE EVENT TASK-WAIT-EVENT-CELLS CELLS ALLOT
TASK-WAIT-CLOCK TARGET !
0 TARGET CELL+ !
0 TARGET 2 CELLS + !
0 TARGET 3 CELLS + !
77 TARGET 4 CELLS + !
TARGET 1 EVENT 1 0 TASK-WAIT-MANY THROW DROP . CR
EVENT CELL+ @ .
EVENT 2 CELLS + @ TASK-EVENT-DEADLINE AND 0<> . CR
PREVIOUS
BYE
```

It prints one event, tag `77`, and true (`-1`) for its deadline reason. An individual zero-duration clock is ready even when the overall call is a poll.

| Kind | id | arg0 | arg1 | Meaning |
| --- | --- | --- | --- | --- |
| TASK-WAIT-INPUT (1) | 0 | 0 | 0 | Current main input; readiness does not consume it. |
| TASK-WAIT-IO (2) | fileid | 1=read, 2=write | 0 | File or PROC/shell pipe readiness. |
| TASK-WAIT-TASK (3) | task | 0 | 0 | Terminal state or release, without consuming results. |
| TASK-WAIT-CLOCK (4) | 0 | relative ms, nonnegative | 0 | Per-target deadline, independent of the call timeout. |
| TASK-WAIT-PAINT (5) | 0 | shown from GFX-WINDOW-FRAMES | 0 | Registered native-window frame completion. |

Put several records in the same target array to wait for input, pipe readiness, task termination and a clock/paint target in one call. The returned set is in target-index order, one event per ready target, including duplicates. It does not consume input, reserve pipe capacity or remove task results. Read all returned records before choosing work. `reason` is a bitmask; test bits rather than comparing it to one constant. Reasons are INPUT=1, READABLE=2, WRITABLE=4, EOF=8, FAILURE=16, CLOSED=32, SUCCEEDED=64, FAILED=128, CANCELLED=256, RELEASED=512, DEADLINE=1024, PAINTED=2048 and CAPABILITY-LOST=4096 (each with prefix `TASK-EVENT-`). Source failure detail is a public diagnostic code.

The wait-flags EXPIRED=1, CANCELLED=2, INTERRUPTED=4 and HOST-FAILED=8 (prefix `TASK-WAIT-`) describe the waiter, not the target task. Ready events can coexist with overall expiration. Timeout has ior=0 and never cancels targets. A host failure returns TASK-E-HOST and may retain safely collected events. Real terminal Ctrl+C detaches registrations and throws -28, rather than merely setting the adapter interruption flag. Buffers are borrowed only during the call; registrations detach on every exit, including THROW.

For paint, use the one-cell shown counter from GFX-WINDOW-FRAMES for a submitted frame, not a guessed frame number. Only the host native window is supported (id=0); invalid/old-window targets return TASK-E-HANDLE. Tk, no native window and graphics exclusion return TASK-E-NO-CAPABILITY. Closing the window after registration gives RELEASED; PAINTED means backend completion, not proof of physical presentation. No window is opened by the examples here.

PCM is not a TASK-WAIT-MANY target kind. For an application that also streams audio, poll `PCM-WAIT ( frames ms pcm -- flag ior )` with ms=0 for free input slots, or inspect `PCM-QUEUED`, and bound the combined wait with a short clock/call deadline before checking PCM again. Free ring slots and an empty input ring are not audible playback completion. PCM-STOP has its own drain/discard contract. The PCM words require `REQUIRE-AUDIO ALSO AUDIO`; see [graphics and sound](GRAPHICS_AND_SOUND.md). Do not pass a PCM ID as a file or task ID.

See [the detailed task plan](TASK_CONTROL_DETAILED_PLAN.md) and [usage conditions](TASK_CONTROL_USAGE_CONDITIONS.md) for design context; the current registered contracts and HELP take precedence over older API proposals.

The next example combines a task and a clock. It first makes the task terminal so the ready set is deterministic: two records, in index order. A normal event loop may register the task while it is still pending and handle whichever records are ready.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
: COPY-INPUT ;
TASK-SNAPSHOT THROW CONSTANT MIX-SNAP
MIX-SNAP S" COPY-INPUT" S" x" TASK-I1 0 TASK-SUBMIT THROW CONSTANT MIX-JOB
MIX-JOB -1 TASK-WAIT THROW 2DROP
CREATE MIX-TARGETS 2 TASK-WAIT-TARGET-CELLS * CELLS ALLOT
CREATE MIX-EVENTS 2 TASK-WAIT-EVENT-CELLS * CELLS ALLOT
MIX-TARGETS 2 TASK-WAIT-TARGET-CELLS * CELLS ERASE
TASK-WAIT-TASK MIX-TARGETS !
MIX-JOB MIX-TARGETS CELL+ !
MIX-TARGETS TASK-WAIT-TARGET-CELLS CELLS + CONSTANT CLOCK-TARGET
TASK-WAIT-CLOCK CLOCK-TARGET !
MIX-TARGETS 2 MIX-EVENTS 2 0 TASK-WAIT-MANY THROW DROP . CR
MIX-EVENTS @ .
MIX-EVENTS TASK-WAIT-EVENT-CELLS CELLS + @ . CR
MIX-JOB TASK-RELEASE THROW
MIX-SNAP TASK-SNAPSHOT-RELEASE THROW
PREVIOUS
BYE
```

It prints `2` and indices `0 1`. Enlarge the arrays and add an INPUT record or an IO record with a pipe file ID using the layout above. Check each reason before consuming input or reading/writing a pipe.

### Words in this chapter

[`TASK-SNAPSHOT`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d534e415053484f54), [`TASK-SNAPSHOT-RELEASE`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d534e415053484f542d52454c45415345), [`TASK-SUBMIT`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d5355424d4954), [`TASK-STATE`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d5354415445), [`TASK-CANCEL`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d43414e43454c), [`TASK-WAIT`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d57414954), [`TASK-RESULT`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d524553554c54), [`TASK-DIAGNOSTIC`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d444941474e4f53544943), [`TASK-RELEASE`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d52454c45415345), [`TASK-WAIT-MANY`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d574149542d4d414e59), [`TASK-QUEUED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d515545554544), [`TASK-RUNNING`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d52554e4e494e47), [`TASK-SUCCEEDED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d535543434545444544), [`TASK-FAILED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4641494c4544), [`TASK-CANCELLED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d43414e43454c4c4544), [`TASK-G1`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4731), [`TASK-G2`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4732), [`TASK-T1`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d5431), [`TASK-I1`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4931), [`TASK-WAIT-TARGET-CELLS`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d574149542d5441524745542d43454c4c53), [`TASK-WAIT-EVENT-CELLS`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d574149542d4556454e542d43454c4c53), [`TASK-WAIT-INPUT`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d574149542d494e505554), [`TASK-WAIT-IO`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d574149542d494f), [`TASK-WAIT-TASK`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d574149542d5441534b), [`TASK-WAIT-CLOCK`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d574149542d434c4f434b), [`TASK-WAIT-PAINT`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d574149542d5041494e54), [`TASK-EVENT-INPUT`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d494e505554), [`TASK-EVENT-READABLE`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d5245414441424c45), [`TASK-EVENT-WRITABLE`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d5752495441424c45), [`TASK-EVENT-EOF`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d454f46), [`TASK-EVENT-FAILURE`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d4641494c555245), [`TASK-EVENT-CLOSED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d434c4f534544), [`TASK-EVENT-SUCCEEDED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d535543434545444544), [`TASK-EVENT-FAILED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d4641494c4544), [`TASK-EVENT-CANCELLED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d43414e43454c4c4544), [`TASK-EVENT-RELEASED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d52454c4541534544), [`TASK-EVENT-DEADLINE`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d444541444c494e45), [`TASK-EVENT-PAINTED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d5041494e544544), [`TASK-EVENT-CAPABILITY-LOST`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d4556454e542d4341504142494c4954592d4c4f5354), [`TASK-WAIT-EXPIRED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d574149542d45585049524544), [`TASK-WAIT-CANCELLED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d574149542d43414e43454c4c4544), [`TASK-WAIT-INTERRUPTED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d574149542d494e544552525550544544), [`TASK-WAIT-HOST-FAILED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d574149542d484f53542d4641494c4544).

Related words in other groups: [`PCM-WAIT`](WORD_REFERENCE.md#w-415544494f3a50434d2d57414954), [`PCM-QUEUED`](WORD_REFERENCE.md#w-415544494f3a50434d2d515545554544), [`PCM-STOP`](WORD_REFERENCE.md#w-415544494f3a50434d2d53544f50), [`GFX-WINDOW-FRAMES`](WORD_REFERENCE.md#w-47524150484943533a4746582d57494e444f572d4652414d4553).

## 8. Saved applications and runtime resources

Register a completed colon definition with `APP-ENTRY!`. SAVE preserves registration; an executable made with SAVESYS calls the entry once at startup. These are image-group words, not EXTENSION words. The following builds a small saved executable in the example directory.

```forth
: MAIN ." application started" CR ;
' MAIN APP-ENTRY!
APP-ENTRY@ NIP . CR
SAVESYS .work/1457/ext-app.exe
APP-ENTRY-OFF
APP-ENTRY@ . . CR
BYE
```

The builder prints `-1`, then `0 0`. Run `.work/1457/ext-app.exe` on Windows (on POSIX, `./.work/1457/ext-app.exe`; the suffix is just the chosen filename). It prints `application started` and exits without a REPL. Ordinary arguments are application data, not Forth files or source. Use the existing ARGC/ARGV/ARG/NEXT-ARG/SHIFT-ARGS facilities to read the current invocation's arguments. Normal return and BYE use common cleanup; QUIT and unhandled errors exit with status 1.

`APP-ENTRY@` returns xt/true or 0/false. `APP-ENTRY-OFF` clears registration for subsequent saves; it does not stop an already running entry. Only completed, non-compile-only colon definitions are accepted; wrap a builtin or DEFER in a colon definition. Invalid targets throw -261; registration while defining throws -259. Redefinition does not retarget registration; deleting its target clears it. LOAD-DICTIONARY imports definitions but preserves the receiving registration and does not autostart an entry.

For saved apps, only an initial `--sigma` enables host options. For example, `.work/1457/ext-app.exe --sigma --no-app -- -e "APP-ENTRY@ NIP . CR BYE"` bypasses startup for this process and prints true without clearing the stored registration. A literal first app argument `--sigma` is passed with `--sigma -- --sigma`. Saved executables reject host -m/-l; debug options need a debug build. Recognized corrupt embedded images fail rather than falling back to source execution, even with --no-app.

Save persistent Forth data and recreate runtime resources at application startup. Open files, pipe endpoints, process configurations/children, task IDs/snapshots, terminal requests, PCM streams and pending display operations are not portable saved resources. Saving an integer that once held an ID does not restore that resource. New processes start with terminal requests cleared. Complete restoration refuses active or unreclaimed task work without implicitly cancelling it; an open PCM stream also blocks full restore (-528). Do not assume a full restore and an appended LOAD have identical cleanup behavior. End tasks and continue task API calls until owned work can be reclaimed; drain/close streams, free processes and stop audio before operations that require idle resources. An old image ABI must be regenerated from source. No image operation is a checkpoint for live external activity.

See [saved-application design](SAVED_APPLICATION_STARTUP_DESIGN.md) and [saving the dictionary](USER_MANUAL.md#saving-the-dictionary-and-stand-alone-executables). SAVESYS needs a writable destination directory and rejects overwriting the running executable, final symlinks/reparse points and nonregular outputs. It publishes a complete temporary file by replacement; this is not a power-loss guarantee.

### Words in this chapter

No new EXTENSION words.

Related words in other groups: [`APP-ENTRY!`](WORD_REFERENCE.md#w-464f5254483a4150502d454e54525921), [`APP-ENTRY@`](WORD_REFERENCE.md#w-464f5254483a4150502d454e54525940), [`APP-ENTRY-OFF`](WORD_REFERENCE.md#w-464f5254483a4150502d454e5452592d4f4646), [`SAVE`](WORD_REFERENCE.md#w-464f5254483a53415645), [`SAVESYS`](WORD_REFERENCE.md#w-464f5254483a53415645535953), [`LOAD-DICTIONARY`](WORD_REFERENCE.md#w-464f5254483a4c4f41442d44494354494f4e415259), [`ARGC`](WORD_REFERENCE.md#w-464f5254483a41524743), [`ARGV`](WORD_REFERENCE.md#w-464f5254483a41524756), [`ARG`](WORD_REFERENCE.md#w-464f5254483a415247), [`NEXT-ARG`](WORD_REFERENCE.md#w-464f5254483a4e4558542d415247), [`SHIFT-ARGS`](WORD_REFERENCE.md#w-464f5254483a53484946542d41524753).

## 9. OS differences and troubleshooting

First distinguish an API error from a target failure or a timeout. Retain ownership until the word's contract says it was released. This example deliberately queries an invalid task ID and handles the returned ior without throwing it.

```forth
REQUIRE-EXTENSION ALSO EXTENSION
0 TASK-STATE TASK-E-HANDLE = . 2DROP 2DROP CR
PREVIOUS
BYE
```

It prints `-1`. Avoid treating all negative numbers as interchangeable. Common errors include:

| ior | Meaning and response |
| --- | --- |
| -9 | Invalid address/range; check byte capacities and cell-array allocation. Often thrown directly. |
| -13 | Unknown word; check loading, search order and excluded build features. |
| -21 | Host function unavailable; check files/debug/host capability rather than retrying forever. |
| -24 | Invalid number/encoding; check masks, counts, target fields and UTF-8. |
| -28 | Terminal interruption in a supported scope; arrange your own resource cleanup. |
| -257 | Internal temporary allocation failed; reduce retained work/data. |
| -265 | Host operation failed; preserve owned resources where required and report the failure. |
| -280 | EXEC-LIMITED's own budget exhausted; inspect before THROW. |
| -514 | ENOENT: path/executable not found. |
| -521 | EBADF: invalid/closed file or resource ID. |
| -525 | EACCES: access denied/read-only operation. |
| -528 | EBUSY: resource still active (for example PROC-FREE on a running child). |
| -534 | EINVAL: invalid argument or unsupported file/pipe kind. |
| -546 | ERANGE: FILE>REALPATH destination too short; allocate needed bytes and retry. |
| -544 | EPIPE: broken pipe; stop writing and inspect the child. Windows may instead return -534. |
| -516 | EINTR from older file/close paths; an interrupted Windows close keeps the ID for retry. |

Task-specific errors are named constants; they are values, not automatically thrown exceptions:

| Constant | Value | Meaning and response |
| --- | --- | --- |
| TASK-E-HANDLE | -300 | Invalid/old/wrong-owner or wrong-kind ID; do not reuse released copies. |
| TASK-E-FULL | -301 | Capacity/backpressure; process completions and release retained records. |
| TASK-E-STALE | -302 | Structurally invalidated snapshot for a new submission; capture again. |
| TASK-E-ENTRY | -303 | Name absent from the captured dictionary/search order. |
| TASK-E-DENIED | -304 | Forbidden worker operation or dependency; simplify the entry. |
| TASK-E-LIMIT | -305 | Byte/VM budget exceeded; reduce input, result or retained work. |
| TASK-E-NOT-READY | -306 | Result/diagnostic not yet available; wait or poll again. |
| TASK-E-SHORT | -307 | Destination too small; use needed, resize and retry, without a partial copy. |
| TASK-E-ABI | -308 | Invalid worker result stack, length or range; fix the entry ABI. |
| TASK-E-BUSY | -309 | Snapshot capture during incomplete compilation; finish defining first. |
| TASK-E-EXHAUSTED | -310 | ID/generation/reference space exhausted; no wraparound/reuse. |
| TASK-E-NO-CAPABILITY | -311 | Requested input/I/O/paint capability unavailable; choose a supported target. |
| TASK-E-HOST | -312 | Host wait/clock/cleanup failed; inspect retained events and diagnostics. |
| TASK-E-QUEUE-EXPIRED | -313 | Task failed in the queue; not the caller's wait timeout. |
| TASK-E-STOP-UNCONFIRMED | -314 | Physical stop unconfirmed; retain resources and continue reclamation. |

On Windows, choose the shell explicitly (the example uses Windows PowerShell); do not expect POSIX signals or paths. Windows TERM is Job termination, not a graceful POSIX SIGTERM. On POSIX, processes use a process group, but descendants can escape it; neither backend is a sandbox. File metadata precision and resolved-path spelling depend on the host. Terminal control depends on the actual terminal, while file-based event input is independent of terminal escape reporting.

If a loop is unresponsive, check for a blocking read/flush, waiting for a child before draining its pipes, a negative/unbounded timeout, unreleased task records, or lack of task API calls after RELEASE. Polling readiness never guarantees a later operation will still be ready. Do not infer audible PCM completion or physical frame presentation from buffer/paint readiness. Response targets in design documents are not OS scheduling guarantees.

### Coverage and evidence

The chapter inventories cover all 97 EXTENSION words: 90 names extracted from the `definitions` array in `src/core/words_extension.zig`, plus seven CONSTANT names from `src/extension/extension.fs`. Every name is checked against the EXTENSION section of WORD_REFERENCE; each belongs to one chapter inventory. TASK-E-* constants are listed here; other task constants are in chapter 7. The loader, core pipe words, image words and audio/graphics helpers are separately linked as related words and are not counted in 97.

The behavior follows source registration and [HELP](../src/core/help_text.zig), the [word reference](WORD_REFERENCE.md), the relevant [user manual](USER_MANUAL.md) sections and [compatibility notes](COMPATIBILITY.md). The [core detailed design](CORE_EXTENSION_DETAILED_DESIGN.md), [task plan](TASK_CONTROL_DETAILED_PLAN.md), [usage conditions](TASK_CONTROL_USAGE_CONDITIONS.md) and the per-chapter final designs supply context. Older proposal-only APIs are not documented as available words. In particular, there is no PCM kind in TASK-WAIT-MANY, no suspended-task continuation and no saved live OS resource guarantee.

All Forth blocks were run as separate files with the Windows executable. The saved executable was started separately and its --no-app bypass checked. The POSIX argument list was validated as configuration only; no POSIX child, live keyboard/mouse/paste session, graphics window, audio device, forced interrupt or cross-OS restore was exercised for this guide. The examples intentionally avoid needing those facilities.

### Words in this chapter

[`TASK-E-HANDLE`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d48414e444c45), [`TASK-E-FULL`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d46554c4c), [`TASK-E-STALE`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d5354414c45), [`TASK-E-ENTRY`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d454e545259), [`TASK-E-DENIED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d44454e494544), [`TASK-E-LIMIT`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d4c494d4954), [`TASK-E-NOT-READY`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d4e4f542d5245414459), [`TASK-E-SHORT`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d53484f5254), [`TASK-E-ABI`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d414249), [`TASK-E-BUSY`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d42555359), [`TASK-E-EXHAUSTED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d455848415553544544), [`TASK-E-NO-CAPABILITY`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d4e4f2d4341504142494c495459), [`TASK-E-HOST`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d484f5354), [`TASK-E-QUEUE-EXPIRED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d51554555452d45585049524544), [`TASK-E-STOP-UNCONFIRMED`](WORD_REFERENCE.md#w-455854454e53494f4e3a5441534b2d452d53544f502d554e434f4e4649524d4544).
