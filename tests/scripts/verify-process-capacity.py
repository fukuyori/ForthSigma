#!/usr/bin/env python3
"""Start all 64 public processes with null stdio, then kill and reap all roots."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(sigma, fixture):
    with tempfile.TemporaryDirectory(prefix="proc-capacity-", dir=ROOT / ".work") as directory:
        source = Path(directory) / "capacity.fs"
        source.write_text(f'''REQUIRE-EXTENSION ALSO EXTENSION DECIMAL
CREATE PROCIDS 64 CELLS ALLOT
: SETUP >R
  S" {fixture.resolve()}" R@ PROC-ARG THROW
  S" --descendant" R@ PROC-ARG THROW
  2 0 R@ PROC-IO THROW 2 1 R@ PROC-IO THROW 2 2 R@ PROC-IO THROW
  R@ PROC-START THROW R> DROP ;
: STARTALL 64 0 DO PROC-NEW THROW DUP PROCIDS I CELLS + ! SETUP LOOP ;
: CHECKALL 64 0 DO PROCIDS I CELLS + @ PROC-STATUS THROW
  0 <> ABORT" code" 1 <> ABORT" state" LOOP ;
: KILLALL 64 0 DO PROCIDS I CELLS + @ PROC-KILL THROW LOOP ;
: FREEALL 64 0 DO PROCIDS I CELLS + @ DUP 3000 PROC-WAIT THROW 2DROP PROC-FREE THROW LOOP ;
STARTALL CHECKALL ." RUNNING64" CR
PROC-NEW ." FULL " . . CR
KILLALL FREEALL
PROC-NEW THROW DUP PROC-STATUS THROW ." REUSED " . . CR PROC-FREE THROW
BYE
''', encoding="utf-8")
        result = subprocess.run([str(sigma.resolve()), str(source)], cwd=ROOT,
                                input=b"", capture_output=True, timeout=25)
        output = result.stdout.decode("utf-8", "replace")
        error = result.stderr.decode("utf-8", "replace")
        assert result.returncode == 0 and not error, (result.returncode, output, error)
        assert all(token in output for token in ["RUNNING64", "FULL -536 0", "REUSED 0 0"]), output
        return {"case": "64-live-processes-overflow-and-reuse", "stdout": output}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sigma", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = run(args.sigma, args.fixture)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result))
