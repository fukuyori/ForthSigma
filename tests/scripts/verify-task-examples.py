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
    # Independent Python oracle: overlaps, truncation, chunk edges and 256-byte
    # patterns. Native SCAN/SKIP calls are exercised beyond one 64 KiB chunk.
    search_cases = [
        (b"aba", b"ababa"), (b"aaa", b"aaaaaa"), (b"abc", b"ab"),
        (b"a", b""), (b"a", b"a" * 131073),
        (b"b", b"a" * 131073), (b"a", b"ab" * 1200),
        (b"ab", b"x" * 65535 + b"abab" + b"x" * 65535 + b"ab"),
        (b"a" * 256, b"a" * 66000),
        (b"a" * 255 + b"b", b"x" * 65535 + b"a" * 255 + b"b"),
        (bytes([0]), bytes([0]) * 65537),
        (b"ab", b"a" * 66000),
    ]
    lines = ['S" examples/task-search-worker.fs" INCLUDED',
             'VARIABLE SS VARIABLE SJ CREATE SI 140000 ALLOT CREATE SO 8032 ALLOT',
             ': CHECK 0= IF -4095 THROW THEN ;',
             'TASK-SNAPSHOT THROW SS !']
    for pattern, text in search_cases:
        data = pattern + text
        offsets = [i for i in range(len(text)-len(pattern)+1) if text.startswith(pattern, i)]
        lines += ['1 SI !', f'{len(pattern)} SI CELL+ !']
        # Encode constant runs compactly without native calls exceeding 64 KiB.
        start = 0
        while start < len(data):
            end = start + 1
            while end < len(data) and data[end] == data[start] and end-start < 65536:
                end += 1
            lines.append(f'SI {16+start} + {end-start} {data[start]} FILL')
            start = end
        lines += [f'SS @ S" TS-SEARCH" SI {16+len(data)} TASK-T1 7 TASK-SUBMIT THROW SJ !',
                  'SJ @ -1 TASK-WAIT THROW DROP TASK-SUCCEEDED = CHECK',
                  'SJ @ SO 8032 TASK-RESULT THROW TASK-SUCCEEDED = CHECK',
                  f'{32+min(1000,len(offsets))*8} = CHECK',
                  'SO @ 1 = CHECK', f'SO CELL+ @ {len(offsets)} = CHECK',
                  f'SO 16 + @ {min(1000,len(offsets))} = CHECK',
                  f'SO 24 + @ {(-1 if len(offsets)>1000 else 0)} = CHECK']
        lines += [f'SO {32+i*8} + @ {offset} = CHECK' for i, offset in enumerate(offsets[:1000])]
        lines.append('SJ @ TASK-RELEASE THROW')
    lines += ['SS @ TASK-SNAPSHOT-RELEASE THROW', '." search oracle passed" CR BYE']
    oracle = work / "search-oracle.fs"
    oracle.write_text("\n".join(lines) + "\n", encoding="utf-8")
    result = subprocess.run([sigma, str(oracle)], capture_output=True, timeout=120)
    (work / "search-oracle.log").write_bytes(result.stdout + result.stderr)
    assert result.returncode == 0 and b"search oracle passed" in result.stdout, (result.stdout + result.stderr).decode(errors="replace")
    passed.append("search-python-oracle-12-cases-all-stored-offsets")
    # Independent Python oracle for G1: the same neighbour order (left, right,
    # up, down) and first-visit parents, so every vertex of the path must match.
    def path_oracle(data):
        # Same checks and order as TP-SEARCH, from the raw input bytes.
        if len(data) < 32:
            return b""
        cell = lambda i: int.from_bytes(data[i*8:i*8+8], "little", signed=True)
        result = bytearray(data[0:8] + bytes(8))
        width = cell(1)
        if not 64 <= width <= 256:
            return bytes(result)
        n = width * width
        if n + 32 != len(data):
            return bytes(result)
        start, goal, board = cell(2), cell(3), data[32:]
        if not (0 <= start < n and 0 <= goal < n) or board[start] or board[goal]:
            return bytes(result)
        parent = [-1] * n
        parent[start] = start
        queue, head = [start], 0
        while head < len(queue) and parent[goal] == -1:
            v = queue[head]; head += 1
            for ok, nb in ((v % width > 0, v - 1), (v % width < width - 1, v + 1),
                           (v >= width, v - width), (v + width < n, v + width)):
                if ok and board[nb] == 0 and parent[nb] == -1:
                    parent[nb] = v; queue.append(nb)
        if parent[goal] == -1:
            return bytes(result)
        path, v = [goal], goal
        while v != start:
            v = parent[v]; path.append(v)
        result[8:16] = len(path).to_bytes(8, "little")
        return bytes(result) + b"".join(p.to_bytes(4, "little") for p in path)
    def path_input(width, start, goal, board, generation=7):
        cells = (generation, width, start, goal)
        return b"".join(c.to_bytes(8, "little", signed=True) for c in cells) + board
    def random_board(width, density, seed, keep, walls=(1,)):
        state, board = seed, bytearray(width * width)
        for i in range(len(board)):
            state = (state * 1103515245 + 12345) & 0x7fffffff
            board[i] = (walls[(state >> 10) % len(walls)] if state % 1000 < density else 0)
        for i in keep:
            board[i] = 0
        return bytes(board)
    def wall_board(width):
        board = bytearray(width * width)
        for row in range(width):
            board[row * width + width // 2] = 1
        return bytes(board)
    def snake_board(width):
        board = bytearray(width * width)
        for row in range(1, width, 2):
            for col in range(width):
                board[row * width + col] = 1
            board[row * width + (width - 1 if row % 4 == 1 else 0)] = 0
        return bytes(board)
    mixed = (1, 2, 3, 4, 5, 6, 128, 255)
    open64 = bytes(4096)
    path_cases = [
        path_input(64, 0, 4095, open64), path_input(256, 0, 65535, bytes(65536)),
        path_input(256, 0, 65535, wall_board(256)), path_input(256, 0, 65280, snake_board(256)),
        path_input(100, 0, 9999, random_board(100, 370, 1, (0, 9999))),
        path_input(256, 0, 65535, random_board(256, 300, 2, (0, 65535))),
        path_input(64, 2080, 1000, random_board(64, 250, 3, (2080, 1000))),
        path_input(64, 777, 777, random_board(64, 200, 5, (777,))),
        path_input(200, 39999, 0, random_board(200, 450, 4, (0, 39999))),
        path_input(256, 65535, 0, random_board(256, 200, 6, (0, 65535))),
        # Wall bytes other than 1 (including the grid codes 2..6) must still block.
        path_input(128, 0, 16383, random_board(128, 330, 7, (0, 16383), mixed)),
        path_input(128, 0, 16383, random_board(128, 600, 8, (0, 16383), mixed)),
        path_input(64, 0, 4095, bytes([0] + [0] * 31 + [6] * 64 + [0] * 4000)),
        # Odd widths with paths along every edge.
        path_input(65, 64, 4160, random_board(65, 150, 9, (64, 4160))),
        path_input(255, 0, 65024, bytes(65025)), path_input(255, 254, 65024, bytes(65025)),
        # Invalid inputs, checked in TP-SEARCH order.
        path_input(64, 0, 4095, bytes(4095) + bytes([1])),
        path_input(64, 0, 4095, bytes([2]) + bytes(4095)),
        path_input(64, 5, 5, bytes(5) + bytes([255]) + bytes(4090)),
        path_input(64, -1, 4095, open64), path_input(64, 0, -1, open64),
        path_input(64, 4096, 0, open64), path_input(64, 0, 4096, open64),
        path_input(63, 0, 3968, bytes(63 * 63)), path_input(257, 0, 66048, open64),
        path_input(64, 0, 4095, open64)[:31],
        path_input(64, 0, 4095, open64)[:-1], path_input(64, 0, 4095, open64) + bytes(1),
    ]
    lines = ['S" examples/task-path-worker.fs" INCLUDED',
             'VARIABLE PS VARIABLE PJ VARIABLE PF',
             'CREATE PI 66600 ALLOT CREATE PO 262160 ALLOT CREATE PE 262160 ALLOT',
             ': CHECK 0= IF -4095 THROW THEN ;',
             ': LOADF ( addr u c-addr cu -- ) R/O BIN OPEN-FILE THROW PF ! PF @ READ-FILE THROW DROP PF @ CLOSE-FILE THROW ;',
             'TASK-SNAPSHOT THROW PS !']
    reachable = 0
    for index, data in enumerate(path_cases):
        expected = path_oracle(data)
        reachable += int.from_bytes(expected[8:16], "little") > 0
        (work / f"path-{index}.in").write_bytes(data)
        (work / f"path-{index}.expected").write_bytes(expected)
        lines += [f'PI {len(data)} S" {(work / f"path-{index}.in").as_posix()}" LOADF',
                  f'PE {len(expected)} S" {(work / f"path-{index}.expected").as_posix()}" LOADF',
                  f'PS @ S" TP-SEARCH" PI {len(data)} TASK-G1 7 TASK-SUBMIT THROW PJ !',
                  'PJ @ -1 TASK-WAIT THROW DROP TASK-SUCCEEDED = CHECK',
                  'PJ @ PO 262160 TASK-RESULT THROW TASK-SUCCEEDED = CHECK',
                  f'{len(expected)} = CHECK',
                  f'PO {len(expected)} PE {len(expected)} COMPARE 0= CHECK',
                  'PJ @ TASK-RELEASE THROW']
    assert reachable >= 10, reachable
    lines += ['PS @ TASK-SNAPSHOT-RELEASE THROW', '." path oracle passed" CR BYE']
    oracle = work / "path-oracle.fs"
    oracle.write_text("\n".join(lines) + "\n", encoding="utf-8")
    result = subprocess.run([sigma, str(oracle)], capture_output=True, timeout=120)
    (work / "path-oracle.log").write_bytes(result.stdout + result.stderr)
    assert result.returncode == 0 and b"path oracle passed" in result.stdout, (result.stdout + result.stderr).decode(errors="replace")
    passed.append(f"path-python-oracle-{len(path_cases)}-cases-every-vertex")
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
