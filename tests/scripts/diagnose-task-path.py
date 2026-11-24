#!/usr/bin/env python3
"""Send nnn after the G1 banner and capture public diagnostics (no benchmark).

Run from the repository root. --keep-old retains superseded public IDs for
inspection; default preserves release-after-submit. Observation time is only
a diagnostic/hang guard and is not reported as a performance result.
"""
import argparse
import os
from pathlib import Path
import runpy
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sigma", type=Path, default=Path(
        "zig-out/bin/sigma.exe" if os.name == "nt" else "zig-out/bin/sigma"))
    parser.add_argument("--keep-old", action="store_true")
    parser.add_argument("--observe-seconds", type=float, default=20)
    args = parser.parse_args()
    if args.observe_seconds <= 0:
        parser.error("--observe-seconds must be positive")
    session_type = runpy.run_path(str(Path(__file__).with_name(
        "verify-task-examples.py")))["Session"]
    work = Path(".work/1380")
    work.mkdir(parents=True, exist_ok=True)
    source = Path("tests/scripts/diagnose-task-path.fs")
    mode = "retained" if args.keep_old else "released"
    if args.keep_old:
        original = source.read_text(encoding="utf-8")
        source = work / "diagnose-task-path-retained.fs"
        source.write_text(original.replace("0 CONSTANT TD-KEEP-OLD",
                                           "-1 CONSTANT TD-KEEP-OLD"), encoding="utf-8")
    session = session_type(str(args.sigma.resolve(strict=True)), str(source))
    timer = None
    try:
        session.expect("G1 diagnostic:")
        session.send("nnn")
        timer = threading.Timer(args.observe_seconds, session.send, args=("dq",))
        timer.start()
        output = session.finish()
        print(output, end="")
    finally:
        if timer is not None:
            timer.cancel()
            timer.join()
        session.close()
        log = work / f"diagnose-task-path-{mode}.log"
        log.write_bytes(session.output)
        print(f"\nlog: {log}")


if __name__ == "__main__":
    main()
