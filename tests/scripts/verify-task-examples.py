#!/usr/bin/env python3
"""Untimed public task examples and pipe/terminal/file integration (1380).

Run from the repository root: python tests/scripts/verify-task-examples.py
--sigma zig-out/bin/sigma.exe. Timeouts are hang guards, never acceptance data.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import threading


class Session:
    def __init__(self, sigma, source):
        self.child = subprocess.Popen(
            [sigma, source], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.messages = queue.Queue()
        self.output = bytearray()
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()

    def read(self):
        while block := self.child.stdout.read(1):
            self.messages.put(block)
        self.messages.put(None)

    def expect(self, marker):
        target = marker.encode()
        while target not in self.output:
            block = self.messages.get(timeout=120)
            if block is None:
                raise AssertionError(f"missing {marker!r}: {self.output.decode(errors='replace')}")
            self.output.extend(block)

    def send(self, value):
        self.child.stdin.write(value.encode())
        self.child.stdin.flush()

    def finish(self):
        self.child.wait(timeout=120)
        self.reader.join(timeout=5)
        assert not self.reader.is_alive(), "reader did not finish"
        while not self.messages.empty():
            if (block := self.messages.get_nowait()) is not None:
                self.output.extend(block)
        assert self.child.returncode == 0, self.output.decode(errors="replace")
        return self.output.decode(errors="replace")

    def close(self):
        if self.child.poll() is None:
            self.child.kill()
            self.child.wait()
        self.reader.join(timeout=5)
        self.child.stdin.close()
        self.child.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sigma", type=Path, default=Path("zig-out/bin/sigma.exe" if os.name == "nt" else "zig-out/bin/sigma"))
    args = parser.parse_args()
    sigma = str(args.sigma.resolve(strict=True))
    work = Path(".work/1380")
    work.mkdir(parents=True, exist_ok=True)
    passed = []
    result = subprocess.run([sigma, "tests/scripts/check-task-examples.fs"],
                            capture_output=True, timeout=120)
    (work / "algorithms.log").write_bytes(result.stdout + result.stderr)
    assert result.returncode == 0 and b"task examples passed" in result.stdout, (
        result.stdout + result.stderr).decode(errors="replace")
    passed.append("public-worker-algorithms-and-generation")
    chunk_data = bytes(range(256)) * 512 + bytes(range(7))
    chunk_path = work / "chunks.bin"
    chunk_path.write_bytes(chunk_data)
    checksum_source = work / "checksum-chunks.fs"
    checksum_source.write_text(
        Path("examples/task-checksum.fs").read_text().replace(
            'S" LICENSE"', f'S" {chunk_path.as_posix()}"'), encoding="utf-8")
    # Deterministic caller-side backpressure: generation 4 is refused twice,
    # then the real API receives the unchanged latest input on a later turn.
    retry_source = work / "path-full-retry.fs"
    console = Path("examples/task-console.fs").read_text(encoding="utf-8")
    console = console.replace("  TASK-SUBMIT DUP", "  TE-SUBMIT DUP")
    console = console.replace(": TC-TRY-SUBMIT", """VARIABLE TE-REFUSALS
: TE-SUBMIT ( snapshot name u input u profile stream -- id ior )
  TC-GEN @ 4 = TE-REFUSALS @ 2 < AND IF
    1 TE-REFUSALS +! 2DROP 2DROP 2DROP DROP 0 TASK-E-FULL
  ELSE TASK-SUBMIT THEN ;
: TC-TRY-SUBMIT""")
    retry_source.write_text(Path("examples/task-path.fs").read_text(encoding="utf-8").replace(
        'S" examples/task-console.fs" INCLUDED', console), encoding="utf-8")
    diagnostic_retry = work / "diagnostic-full-retry.fs"
    diagnostic = Path("tests/scripts/diagnose-task-path.fs").read_text(encoding="utf-8")
    diagnostic = diagnostic.replace("7 TASK-SUBMIT", "7 TD-SUBMIT")
    diagnostic = diagnostic.replace(": TD-TRY", """VARIABLE TD-REFUSALS
: TD-SUBMIT
  TC-GEN @ 4 = TD-REFUSALS @ 2 < AND IF
    1 TD-REFUSALS +! 2DROP 2DROP 2DROP DROP 0 TASK-E-FULL
  ELSE TASK-SUBMIT THEN ;
: TD-TRY""")
    diagnostic_retry.write_text(diagnostic, encoding="utf-8")
    # The public API test covers real queue expiry and its diagnostic. Here
    # force a latest terminal failure once to verify the example re-submits it.
    expired_source = work / "path-expired-retry.fs"
    expired_console = Path("examples/task-console.fs").read_text(encoding="utf-8")
    expired_console = expired_console.replace("0 TASK-WAIT THROW", "0 TE-WAIT THROW")
    expired_console = expired_console.replace(": TC-POLL", """VARIABLE TE-FAILURES
: TE-WAIT
  TASK-WAIT DUP 0= TE-FAILURES @ 0= AND IF
    DROP DROP DROP TASK-FAILED 0 0 1 TE-FAILURES !
    ." latest terminal failure injected" CR
  THEN ;
: TC-POLL""")
    expired_source.write_text(Path("examples/task-path.fs").read_text(encoding="utf-8").replace(
        'S" examples/task-console.fs" INCLUDED', expired_console), encoding="utf-8")
    scenarios = [
        ("path-expired-retry", str(expired_source),
         [("result generation=1 ", "q")]),
        ("integration", "tests/scripts/check-task-console.fs",
         [("active", "r"), ("replaced", "c"), ("bye-active", "b")]),
        ("path", "examples/task-path.fs",
         [("result generation=1 ", "n"), ("result generation=2 ", "q")]),
        ("path-replace", "examples/task-path.fs",
         [("G1:", "nnn"), ("result generation=4 ", "q")]),
        ("path-full-retry", str(retry_source),
         [("G1:", "nnn"), ("result generation=4 ", "q")]),
        ("diagnostic-full-retry", str(diagnostic_retry),
         [("G1 diagnostic:", "nnn"), ("result generation=4 ", "q")]),
        ("search", "examples/task-search.fs",
         [("result generation=1 ", "b"), ("result generation=2 ", "a"),
          ("result generation=3 ", "q")]),
        ("search-replace", "examples/task-search.fs",
         [("T1:", "ba"), ("result generation=3 ", "q")]),
        ("checksum", "examples/task-checksum.fs", []),
        ("checksum-chunks", str(checksum_source), []),
    ]
    for name, source, steps in scenarios:
        session = Session(sigma, source)
        try:
            for marker, key in steps:
                session.expect(marker)
                session.send(key)
            text = session.finish()
            if name == "integration":
                for marker in ("frame=r", "frame=c", "frame=b", "cancelled", "released"):
                    assert marker in text, text
            else:
                assert "result generation=" in text, text
                generations = [int(n) for n in re.findall(r"result generation=(\d+)", text)]
                assert generations == sorted(generations), text
            if name == "path-expired-retry":
                assert text.count("latest terminal failure injected") == 1, text
                assert "failed/cancelled; previous display retained" in text, text
                assert "result generation=1 vertices=127 " in text, text
            if name == "path":
                assert "result generation=1 vertices=127 " in text, text
                assert "result generation=2 vertices=95 " in text, text
            if name == "path-replace":
                assert "result generation=4 vertices=95 " in text, text
            if name == "path-full-retry":
                assert text.count("submit deferred ior=-301") == 2, text
                assert "result generation=4 vertices=95 " in text, text
            if name == "diagnostic-full-retry":
                assert text.count("submit generation=4 ior=-301") == 2, text
                assert "requested-generation=4" in text, text
                assert "result generation=4 vertices=95 " in text, text
            if name == "search":
                assert "result generation=1 matches=1048576 stored=1000 truncated=-1 " in text, text
                assert "result generation=2 matches=0 stored=0 truncated=0 " in text, text
                assert "result generation=3 matches=1048576 stored=1000 truncated=-1 " in text, text
            if name == "search-replace":
                assert "result generation=3 matches=1048576 stored=1000 truncated=-1 " in text, text
            if name == "checksum":
                expected_sum = sum(Path("LICENSE").read_bytes()) & 0xffffffff
                assert f"chunk=1 checksum={expected_sum} " in text, text
            if name == "checksum-chunks":
                actual = [(int(n), int(total)) for n, total in re.findall(
                    r"chunk=(\d+)\s+checksum=(\d+)", text)]
                expected = [(i // 65536 + 1, sum(chunk_data[i:i + 65536]) & 0xffffffff)
                            for i in range(0, len(chunk_data), 65536)]
                assert actual == expected, (actual, expected)
            (work / f"{name}.log").write_text(text, encoding="utf-8")
            passed.append(name)
        finally:
            session.close()
    # Inject main-side failures after acquiring resources. CATCH must clean up
    # and preserve the original exception, rather than relying on BYE.
    failures = [
        ("checksum-read-error", "checksum", "READ-FILE THROW", "READ-FILE THROW -4095 THROW"),
        ("checksum-submit-error", "checksum", 'S" TI-CHECKSUM"', 'S" NO-SUCH-WORKER"'),
        ("path-wait-error", "path", "0 TASK-WAIT THROW", "0 TASK-WAIT THROW -4095 THROW"),
        ("search-result-error", "search", "262160 TASK-RESULT THROW", "262160 TASK-RESULT THROW -4095 THROW"),
    ]
    for name, example, before, after in failures:
        prefix = {"checksum": "TI", "path": "TP", "search": "TS"}[example]
        source = Path(f"examples/task-{example}.fs").read_text(encoding="utf-8")
        if example == "checksum":
            source = source.replace(before, after)
        else:
            console = Path("examples/task-console.fs").read_text(encoding="utf-8")
            source = source.replace('S" examples/task-console.fs" INCLUDED',
                                    console.replace(before, after))
        source = source.replace(f"{prefix}-MAIN BYE", f"""
: CHECK-CLEANUP
  ['] {prefix}-MAIN CATCH 0= IF -4094 THROW THEN
  TC-JOB @ TC-SNAP @ OR IF -4093 THROW THEN
""" + ("  TI-OPENED @ IF -4092 THROW THEN\n" if example == "checksum" else "") +
                                '." explicit cleanup passed" CR ; CHECK-CLEANUP BYE')
        script = work / f"{name}.fs"
        script.write_text(source, encoding="utf-8")
        result = subprocess.run([sigma, str(script)], capture_output=True, timeout=120)
        (work / f"{name}.log").write_bytes(result.stdout + result.stderr)
        assert result.returncode == 0 and b"explicit cleanup passed" in result.stdout, (
            result.stdout + result.stderr).decode(errors="replace")
        passed.append(name)
    (work / "results.json").write_text(json.dumps({"passed": passed}, indent=2) + "\n")
    print(f"{len(passed)} task example/integration groups passed")


if __name__ == "__main__":
    main()
