#!/usr/bin/env python3
"""Runs the debugging features of sigma (the examples of docs/DEBUGGING.md and the
features without one) the same way on every system, and keeps what each run printed, so
that the results of two systems can be compared line by line (tque #890).

  python3 tests/scripts/verify-debug-outputs.py --sigma zig-out/bin/sigma \
      --out tests/scripts/debug-outputs/<system>.json
  python3 tests/scripts/verify-debug-outputs.py --compare \
      tests/scripts/debug-outputs/macos.json tests/scripts/debug-outputs/windows.json

The program and the inputs are made in a new folder in the system's temporary folder;
every command runs there, so the outputs hold no absolute paths. stdout and stderr are
kept as they came, decoded as UTF-8, with the exit code. --compare takes CR LF as LF.
"""
import argparse, json, pathlib, platform, shutil, subprocess, sys, tempfile

PROG = """: SQUARE ( n -- n ) DUP * ;
: SUMSQ ( a b -- n ) SQUARE SWAP SQUARE + ;
: AVERAGE ( sum n -- avg ) / ;
: REPORT ( a b n -- )
   >R SUMSQ R> AVERAGE . ;

\\ Not used by the examples above.
VARIABLE SCORE
: BUMP ( -- ) 1 SCORE +! ;
: SPIN ( -- ) BEGIN BUMP AGAIN ;
: TELL ( n -- ) DUP 0< IF DROP ." minus" ELSE 0= IF ." zero" THEN THEN ;
"""
FILES = {
    "prog.fs": PROG,
    "brk.fs": ": B1 1 BREAK: 2 + ;\nB1 . BYE\n",
    "brk2.fs": ': B2 1 BREAK" here" 2 + ;\n',
    "lint.fs": ": X ( a -- b c ) DUP ;\n: Y ( -- ) 1 IF 2 THEN ;\n: Z ( -- ) EXIT 3 ;\n: X 1 ;\nX Y Z\n",
    "fmt.fs": ": BAD\n1 IF\n2\n  THEN ;  \n",
}
# name, arguments, standard input (None: empty), files to keep after the run
CASES = [
    ("backtrace", ["prog.fs", "-e", "3 4 0 REPORT"], None, []),
    ("max-steps", ["--max-steps", "1000", "prog.fs", "-e", "SPIN"], None, []),
    ("max-steps=", ["--max-steps=1000", "prog.fs", "-e", "SPIN"], None, []),
    ("trace", ["--trace", "prog.fs", "-e", "3 4 5 REPORT BYE"], None, []),
    ("trace-limit", ["--trace", "--trace-limit", "3", "prog.fs", "-e", "3 4 5 REPORT BYE"], None, []),
    ("tilde", ["prog.fs", "-e", ": T 5 ~~ SQUARE ~~BT DROP ; : CALLER T ; CALLER BYE"], None, []),
    ("tilde-once", ["prog.fs", "-e", ': T 3 0 DO I ~~1BT ONCE ." once" THEN LOOP ; : C T ; C BYE'], None, []),
    ("tilde-value", ["-e", "3 ~~VALUE V 5 TO V ~~VARIABLE W 7 W ! W @ . BYE"], None, []),
    ("dbg-enter", ["prog.fs"], "3 4 DBG SUMSQ\n\n\n\n\n\n. BYE\n", []),
    ("dbg-n-u", ["prog.fs"], "3 4 5 DBG REPORT\n\nn\n\n\n\nu\n. BYE\n", []),
    ("dbg-d", ["prog.fs"], "3 4 5 DBG REPORT\nd\n BYE\n", []),
    ("dbg-s", ["prog.fs"], "3 4 5 DBG REPORT\ns\n.S BYE\n", []),
    ("break-colon", ["brk.fs"], None, []),
    ("break-quote", ["brk2.fs", "-e", "B2"], "\n\n\n. BYE\n", []),
    ("watch", ["prog.fs", "-e", "SCORE WATCH BUMP 7 SCORE ! BYE"], None, []),
    ("unwatch", ["prog.fs", "-e", "SCORE WATCH BUMP SCORE UNWATCH BUMP SCORE @ . BYE"], None, []),
    ("profile", ["--profile", "prog.fs", "-e", "3 4 5 REPORT BYE"], None, []),
    ("coverage", ["--coverage", "prog.fs", "-e", "3 4 5 REPORT -1 TELL CR COV% CR .COVERAGE BYE"], None, []),
    ("cover-raw", ["--coverage", "prog.fs", "-e", "-1 TELL .COVER-RAW BYE"], None, []),
    ("lint-prog", ["--lint", "prog.fs"], None, []),
    ("lint-findings", ["--lint", "lint.fs"], None, []),
    ("format-check-prog", ["--format-check", "prog.fs"], None, []),
    ("format-check-needs", ["--format-check", "fmt.fs"], None, []),
    ("format-indent-2", ["--format-check", "--format-indent", "2", "fmt.fs"], None, []),
    ("format", ["--format", "fmt.fs"], None, ["fmt.fs"]),
    ("debug-log", ["--debug-log", "run.jsonl", "--trace", "--profile", "prog.fs", "-e", "3 4 0 REPORT"], None, ["run.jsonl"]),
    ("end-of-options", ["--", "prog.fs", "-e", "3 4 5 REPORT BYE"], None, []),
]

def run(sigma, out):
    sigma = str(pathlib.Path(sigma).resolve())
    out = pathlib.Path(out).resolve()
    work = pathlib.Path(tempfile.mkdtemp(prefix="sigma-debug-outputs-"))
    results = []
    try:
        for name, argv, stdin, keep in CASES:
            for file in list(work.iterdir()):
                file.unlink()
            for file, text in FILES.items():
                (work / file).write_bytes(text.encode())
            r = subprocess.run([sigma] + argv, cwd=work, input=(stdin or "").encode(),
                               capture_output=True, timeout=30)
            kept = {f: (work / f).read_bytes().decode("utf-8", "replace") for f in keep if (work / f).exists()}
            results.append({"name": name, "args": argv, "stdin": stdin, "exit": r.returncode,
                            "stdout": r.stdout.decode("utf-8", "replace"),
                            "stderr": r.stderr.decode("utf-8", "replace"), "files": kept})
    finally:
        shutil.rmtree(work, ignore_errors=True)
    # Without arguments and with no input, sigma shows its banner and ends.
    banner = subprocess.run([sigma], capture_output=True, input=b"").stdout
    first = banner.decode("utf-8", "replace").splitlines()
    report = {"system": platform.system(), "release": platform.release(), "machine": platform.machine(),
              "sigma": first[0] if first else "", "cases": results}
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{len(results)} cases written to {out}")
    return 0

def lines(text):
    return text.replace("\r\n", "\n").split("\n")

def compare(first, second):
    a = json.loads(pathlib.Path(first).read_text(encoding="utf-8"))
    b = json.loads(pathlib.Path(second).read_text(encoding="utf-8"))
    print(f"{first}: {a['system']} {a['machine']} {a['sigma']}")
    print(f"{second}: {b['system']} {b['machine']} {b['sigma']}")
    cases = {c["name"]: c for c in b["cases"]}
    differ = 0
    for c in a["cases"]:
        d = cases.get(c["name"])
        if d is None:
            print(f"[missing] {c['name']}"); differ += 1; continue
        problems = []
        if c["exit"] != d["exit"]:
            problems.append(f"exit {c['exit']} / {d['exit']}")
        for part in ("stdout", "stderr"):
            if lines(c[part]) != lines(d[part]):
                problems.append(part)
        for file in sorted(set(c["files"]) | set(d["files"])):
            if lines(c["files"].get(file, "")) != lines(d["files"].get(file, "")):
                problems.append("file " + file)
        if problems:
            differ += 1
            print(f"[differs] {c['name']}: {', '.join(problems)}")
            for part in ("stdout", "stderr"):
                if part in problems:
                    x, y = lines(c[part]), lines(d[part])
                    for i in range(max(len(x), len(y))):
                        u = x[i] if i < len(x) else "<none>"
                        v = y[i] if i < len(y) else "<none>"
                        if u != v:
                            print(f"   {part} line {i + 1}:\n     {u!r}\n     {v!r}")
        else:
            print(f"[same]    {c['name']}")
    print(f"{len(a['cases'])} cases, {differ} differ")
    return 1 if differ else 0

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--sigma")
    p.add_argument("--out")
    p.add_argument("--compare", nargs=2, metavar=("FIRST", "SECOND"))
    args = p.parse_args()
    if args.compare:
        return compare(*args.compare)
    if not args.sigma or not args.out:
        p.error("--sigma and --out, or --compare")
    return run(args.sigma, args.out)

sys.exit(main())
