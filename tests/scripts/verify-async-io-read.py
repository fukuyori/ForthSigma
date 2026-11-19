#!/usr/bin/env python3
"""Real pipe/stdio acceptance of WAIT-FILES and READ-AVAILABLE; no physical keys."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def run(sigma):
    reports = []
    with tempfile.TemporaryDirectory(prefix="async-read-", dir=ROOT / ".work") as directory:
        work = Path(directory)
        producer = work / "producer.py"
        producer.write_text("import sys,time\ntime.sleep(float(sys.argv[1]))\nsys.stdout.buffer.write(sys.argv[2].encode());sys.stdout.buffer.flush()\n")
        assert not any(c.isspace() or c == '"' for c in str(producer) + sys.executable)

        def invoke(name, body, expected, input_bytes=None):
            source = work / f"{name}.fs"
            source.write_text("REQUIRE-EXTENSION ALSO EXTENSION DECIMAL\n" + body + "\nBYE\n")
            result = subprocess.run([str(sigma.resolve()), str(source)], cwd=ROOT,
                                    input=input_bytes, capture_output=True, timeout=12)
            text = result.stdout.decode("utf-8", "replace")
            error = result.stderr.decode("utf-8", "replace")
            if result.returncode or error or any(token not in text for token in expected):
                raise AssertionError((name, result.returncode, text, error, expected))
            reports.append({"case": name, "stdout": text, "exit_code": 0})

        def command(delay, data):
            return f"{sys.executable} {producer} {delay} {data}"

        invoke("two-pipes", f'''
S" {command(.8, 'S')}" R/O OPEN-PIPE THROW CONSTANT A
S" {command(.1, 'F')}" R/O OPEN-PIPE THROW CONSTANT B
CREATE IDS A , B ,
IDS 2 0 WAIT-FILES ." POLL " . . CR
IDS 2 1500 WAIT-FILES ." FIRST " . . CR
PAD 8 B READ-AVAILABLE THROW DROP ." FIRST-COUNT " . CR
PAD C@ ." FIRST-BYTE " . CR
B KEY-FILE ." FIRST-EOF " . CR
IDS 2 0 WAIT-FILES ." EOF-READY " . . CR
IDS 1 2000 WAIT-FILES ." SECOND " . . CR
A KEY-FILE ." SECOND-BYTE " . CR
B CLOSE-PIPE THROW DROP A CLOSE-PIPE THROW DROP
''', ["POLL 0 -1", "FIRST 0 1", "FIRST-COUNT 1", "FIRST-BYTE 70", "FIRST-EOF -1", "EOF-READY 0 1", "SECOND 0 0", "SECOND-BYTE 83"])
        invoke("immediate-poll", f'''S" {command(0, 'Q')}" R/O OPEN-PIPE THROW CONSTANT POLLPIPE
CREATE POLLIDS POLLPIPE , 250 MS
POLLIDS 1 0 WAIT-FILES ." READY " . . CR
PAD 1 POLLPIPE READ-AVAILABLE THROW DROP ." COUNT " . CR
PAD C@ ." BYTE " . CR POLLPIPE CLOSE-PIPE THROW DROP
''', ["READY 0 0", "COUNT 1", "BYTE 81"])

        invoke("legacy-to-worker", f'''
S" {command(0, 'ABC')}" R/O OPEN-PIPE THROW CONSTANT P
P KEY-FILE ." BEFORE " . CR
CREATE IDS P ,
IDS 1 1000 WAIT-FILES THROW ." READY " . CR
PAD 8 P READ-AVAILABLE THROW DROP ." COUNT " . CR
PAD C@ . PAD 1+ C@ . CR
P KEY-FILE ." EOF " . CR P CLOSE-PIPE THROW DROP
''', ["BEFORE 65", "READY 0", "COUNT 2", "66 67", "EOF -1"])
        invoke("invalid-after-ready", f'''
S" {command(0, 'X')}" R/O OPEN-PIPE THROW CONSTANT P
CREATE IDS P , -99 ,
IDS 2 0 WAIT-FILES ." INVALID " . . CR
P KEY-FILE ." KEPT " . CR P CLOSE-PIPE THROW DROP
''', ["INVALID -521 1", "KEPT 88"])
        invoke("stdin-prefetch", '''
EKEY? ." PEEK " . CR
CREATE IDS STDIN , IDS 1 1000 WAIT-FILES ." STDIN " . . CR
PAD 8 STDIN READ-AVAILABLE THROW DROP ." COUNT " . CR
PAD C@ ." BYTE " . CR EKEY ." AFTER " . CR
PAD 8 STDIN READ-AVAILABLE ." EOF-END " . . . CR
''', ["PEEK -1", "STDIN 0 0", "COUNT 1", "BYTE 65", "AFTER 2147483681", "EOF-END 0 -1 0"], b"A")
    return {"platform": sys.platform, "cases": reports}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sigma", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = run(args.sigma)
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))
