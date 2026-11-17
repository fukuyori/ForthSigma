#!/usr/bin/env python3
"""Drive the SDK-header-free AppKit child probe through pipes with a 5 s deadline."""

from __future__ import annotations

import select
import subprocess
import sys
import time
import struct


def main() -> int:
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} command [arguments ...]", file=sys.stderr)
        return 2

    deadline = time.monotonic() + 5.0
    process = subprocess.Popen(
        sys.argv[1:], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, bufsize=1,
    )

    def read_line() -> str:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([process.stdout], [], [], remaining)[0]:
            raise TimeoutError("child did not answer within the 5 s deadline")
        line = process.stdout.readline()
        if not line:
            detail = process.stderr.read()
            raise RuntimeError(f"child closed its protocol pipe; stderr={detail!r}")
        return line.rstrip("\n")

    try:
        process.stdin.write("HELLO 1\n")
        process.stdin.flush()
        ready = read_line()
        if ready != "READY 1":
            raise RuntimeError(f"unexpected startup response: {ready!r}")
        process.stdin.write("FRAME 17 2 2 0 0\n")
        process.stdin.flush()
        frame_ready = read_line()
        if frame_ready != "FRAME-READY 17":
            raise RuntimeError(f"unexpected frame allocation response: {frame_ready!r}")
        process.stdin.buffer.write(struct.pack("<4I", 0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFFFF))
        process.stdin.buffer.flush()
        frame = read_line()
        if frame != "FRAME-ACCEPTED 17":
            raise RuntimeError(f"unexpected frame response: {frame!r}")
        process.stdin.write("QUIT\n")
        process.stdin.flush()
        responses = set()
        while "EXIT 0" not in responses:
            responses.add(read_line())
        if not {"QUIT-ACCEPTED", "CLOSED", "EXIT 0"}.issubset(responses):
            raise RuntimeError(f"unexpected shutdown responses: {responses!r}")
        process.stdin.close()
        process.wait(timeout=max(0.01, deadline - time.monotonic()))
        if process.returncode != 0:
            raise RuntimeError(f"child exited with status {process.returncode}")
        print("READY 1, FRAME-ACCEPTED 17, CLOSED, EXIT 0 (within 5 s)")
        return 0
    except Exception as error:
        process.terminate()
        try:
            process.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        print(f"AppKit probe failed: {error}", file=sys.stderr)
        if process.stderr:
            detail = process.stderr.read()
            if detail:
                print(detail, file=sys.stderr, end="")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
