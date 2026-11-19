#!/usr/bin/env python3
"""Run PROC words through Sigma with explicitly owned Python fixture children."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(sigma):
    reports = []
    with tempfile.TemporaryDirectory(prefix="proc-words-", dir=ROOT / ".work") as directory:
        work = Path(directory)
        child = work / "child.py"
        child.write_text(
            "import os,sys,time\n"
            "if sys.argv[1]=='sleep':time.sleep(30)\n"
            "elif sys.argv[1]=='bulk':\n"
            " sys.stdout.buffer.write(b'O'*200000);sys.stdout.buffer.flush()\n"
            " sys.stderr.buffer.write(b'E'*200000);sys.stderr.buffer.flush()\n"
            " data=sys.stdin.buffer.read();sys.stdout.buffer.write(data);sys.stdout.buffer.flush()\n"
            "else:\n"
            " data=sys.stdin.buffer.read();sys.stdout.buffer.write(data.upper());sys.stdout.buffer.flush()\n"
            " sys.stderr.buffer.write(b'ERR');sys.stderr.buffer.flush()\n",
            encoding="utf-8",
        )
        assert '"' not in str(child) + sys.executable

        def invoke(name, body, expected):
            source = work / (name + ".fs")
            source.write_text("REQUIRE-EXTENSION ALSO EXTENSION DECIMAL\n" + body + "\nBYE\n", encoding="utf-8")
            result = subprocess.run([str(sigma.resolve()), str(source)], cwd=ROOT,
                                    input=b"", capture_output=True, timeout=12)
            output = result.stdout.decode("utf-8", "replace")
            error = result.stderr.decode("utf-8", "replace")
            assert result.returncode == 0 and not error, (name, result.returncode, output, error)
            assert all(token in output for token in expected), (name, output, expected)
            reports.append({"case": name, "stdout": output, "exit_code": result.returncode})

        def setup(mode):
            return f'''PROC-NEW THROW CONSTANT P
: PARG P PROC-ARG THROW ;
S" {sys.executable}" PARG S" {child}" PARG S" {mode}" PARG
'''

        invoke("exchange-half-close-status", setup("echo") + '''
P PROC-START THROW
P PROC-STDIN THROW CONSTANT PIN
S" abc" PIN WRITE-FILE THROW PIN CLOSE-FILE THROW
P PROC-STDOUT THROW CONSTANT POUT
PAD 3 POUT READ-FILE THROW ." COUNT " . CR PAD 3 TYPE CR
P PROC-STDERR THROW CONSTANT PERR
PAD 3 PERR READ-FILE THROW DROP PAD 3 TYPE CR
P 3000 PROC-WAIT THROW ." EXIT " . . CR
P PROC-STATUS THROW ." AGAIN " . . CR
P PROC-FREE THROW
P PROC-STATUS ." STALE " . 2DROP CR
''', ["COUNT 3", "ABC", "ERR", "EXIT 0 2", "AGAIN 0 2", "STALE -521"])

        invoke("timeout-busy-kill", setup("sleep") + '''
2 0 P PROC-IO THROW 2 1 P PROC-IO THROW 2 2 P PROC-IO THROW
P PROC-START THROW
P 0 PROC-WAIT THROW ." POLL " . . CR
P 5 PROC-WAIT THROW ." TIMEOUT " . . CR
P PROC-STDOUT THROW ." NULL " . CR
P PROC-FREE ." BUSY " . CR
P PROC-KILL THROW P 3000 PROC-WAIT THROW ." KILLED " . . CR
P PROC-FREE THROW
''', ["POLL 0 1", "TIMEOUT 0 1", "NULL 0", "BUSY -528",
      "KILLED 137 2" if sys.platform == "win32" else "KILLED 9 3"])

        invoke("cooperative-three-stream-bulk", setup("bulk") + '''
P PROC-START THROW
P PROC-STDIN THROW CONSTANT PIN
P PROC-STDOUT THROW CONSTANT POUT
P PROC-STDERR THROW CONSTANT PERR
CREATE SEND-BYTES 1024 ALLOT SEND-BYTES 1024 73 FILL
VARIABLE SENT VARIABLE GOT-OUT VARIABLE GOT-ERR
VARIABLE CLOSED-IN VARIABLE END-OUT VARIABLE END-ERR
: SEND-CHUNK
  SENT @ 131072 < IF SEND-BYTES 131072 SENT @ - 1024 MIN PIN WRITE-AVAILABLE THROW SENT +! THEN
  SENT @ 131072 = CLOSED-IN @ 0= AND GOT-OUT @ 200000 >= AND GOT-ERR @ 200000 >= AND IF PIN CLOSE-FILE THROW -1 CLOSED-IN ! THEN ;
: RECEIVE-OUT PAD 8192 POUT READ-AVAILABLE THROW END-OUT !
  DUP 0 ?DO PAD I + C@ GOT-OUT @ I + 200000 < IF 79 ELSE 73 THEN <> ABORT" stdout data" LOOP GOT-OUT +! ;
: RECEIVE-ERR PAD 8192 PERR READ-AVAILABLE THROW END-ERR !
  DUP 0 ?DO PAD I + C@ 69 <> ABORT" stderr data" LOOP GOT-ERR +! ;
: TRANSFER BEGIN SEND-CHUNK RECEIVE-OUT RECEIVE-ERR END-OUT @ END-ERR @ AND UNTIL ;
TRANSFER
SENT @ ." SENT " . CR GOT-OUT @ ." OUT " . CR GOT-ERR @ ." ERR " . CR
P 3000 PROC-WAIT THROW ." EXIT " . . CR P PROC-FREE THROW
''', ["SENT 131072", "OUT 331072", "ERR 200000", "EXIT 0 2"])

        invoke("missing-executable-retains-config", '''
PROC-NEW THROW CONSTANT P
S" sigma-no-such-executable-643" P PROC-ARG THROW
P PROC-START ." MISSING " . CR
P PROC-STATUS THROW ." CONFIG " . . CR
P PROC-FREE THROW
''', ["MISSING -514", "CONFIG 0 0"])
    return {"platform": sys.platform, "cases": reports}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sigma", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = run(args.sigma)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result))
