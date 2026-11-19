#!/usr/bin/env python3
"""Real delayed-pipe acceptance for selected-file EKEY-WAIT (1078)."""
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def run(sigma):
    results = []
    with tempfile.TemporaryDirectory(prefix="file-wait-", dir=ROOT / ".work") as directory:
        work = Path(directory)
        producer = work / "producer.py"
        producer.write_text(
            "import sys,time\n"
            "sys.stdout.buffer.write(bytes([0xe3]));sys.stdout.buffer.flush()\n"
            "time.sleep(1.2)\n"
            "sys.stdout.buffer.write(b'' if sys.argv[1]=='eof' else bytes([0x81,0x82,66]));sys.stdout.buffer.flush()\n"
        )
        # Forth S\" has no shell quoting escape; this fixture requires plain paths.
        if any(c.isspace() or c == '"' for c in str(producer) + sys.executable):
            raise RuntimeError("Fixture paths must contain no whitespace or quotes")
        prelude = 'REQUIRE-EXTENSION ALSO EXTENSION DECIMAL\n'
        timeout = ': FIRST 500 EKEY-WAIT ." FIRST " . . . CR ;\n\' FIRST P INFILE-EXECUTE\n'
        cases = [
            ("resume", "resume", timeout +
             ': SECOND 2000 EKEY-WAIT ." SECOND " . . . CR EKEY ." TAIL " . CR ;\n'
             "' SECOND P INFILE-EXECUTE\n", ["FIRST 0 0 0", "SECOND 0 -1 12354", "TAIL 66"]),
            ("byte-after-scope", "resume", timeout +
             'P KEY-FILE ." BYTE " . CR PAD 3 P READ-FILE THROW ." COUNT " . CR\n'
             'PAD C@ . PAD 1+ C@ . PAD 2 + C@ . CR\n', ["FIRST 0 0 0", "BYTE 227", "COUNT 3", "129 130 66"]),
            ("partial-eof", "eof", timeout +
             ': LAST 2000 EKEY-WAIT ." LAST " . . . CR 0 EKEY-WAIT ." EOF " . . . CR ;\n'
             "' LAST P INFILE-EXECUTE\n", ["FIRST 0 0 0", "LAST 0 -1 65533", "EOF 0 -1 2147483681"]),
            ("throw-and-failed-seek", "resume",
             ': FIRST 500 EKEY-WAIT 2DROP DROP -99 THROW ;\n'
             ": WRAPPED ['] FIRST P INFILE-EXECUTE ; ' WRAPPED CATCH .\n"
             '0 0 P REPOSITION-FILE ." SEEK " 0<> . CR\n'
             'P KEY-FILE ." PREFIX " . CR PAD 3 P READ-FILE THROW DROP\n', ["-99", "SEEK -1", "PREFIX 227"]),
        ]
        for name, mode, body, expected in cases:
            command = f"{sys.executable} {producer} {mode}"
            program = prelude + f'S" {command}" R/O OPEN-PIPE THROW CONSTANT P\n' + body
            program += 'P CLOSE-PIPE THROW DROP ." FINISHED" CR BYE\n'
            source = work / f"{name}.fs"
            source.write_text(program)
            result = subprocess.run([str(sigma.resolve()), str(source)], cwd=ROOT,
                                    stdin=subprocess.DEVNULL, capture_output=True, timeout=15)
            stdout = result.stdout.decode("utf-8", "replace")
            stderr = result.stderr.decode("utf-8", "replace")
            if result.returncode or stderr or "FINISHED" not in stdout or any(x not in stdout for x in expected):
                raise AssertionError((name, result.returncode, stdout, stderr, expected))
            results.append({"case": name, "stdout": stdout, "exit_code": result.returncode})
    return {"platform": sys.platform, "kind": "real-delayed-pipe", "cases": results}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sigma", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    report = run(arguments.sigma)
    if arguments.output:
        arguments.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False))
