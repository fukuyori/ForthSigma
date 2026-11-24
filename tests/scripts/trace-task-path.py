#!/usr/bin/env python3
"""06-H stage capture. Default checks format only; --analyze reads an existing log.
Run from the repository root with a -Dtask-trace=true sigma.
No elapsed-time acceptance check. Session timeouts are hang guards only.
"""
import argparse
import os
from pathlib import Path
import re
import runpy
import subprocess

STAGES = "api_entry request token_before token_after acquired vm_start restored prepared forth_return detected runner_return sealed published observed host_stopped deadline_check deadline".split()

SETUP_STAGES = "snapshot_retained state_reserved state_chunk state_allocated allocation_chunk memory_allocated data_allocated return_allocated float_allocated loops_allocated frames_allocated catches_allocated zero_chunk storage_zeroed storage_allocated state_initialized_chunk initialized plan_allocated restore_validated restore_applied restored plan_released fresh_checked resolved grants_ready permissions_checked input_ready prepared".split()

def records(text):
    rows = []
    target = None
    for line in text.splitlines():
        if line.startswith("cancel-after-stage="):
            target = line.split("=", 1)[1]
        if "TASKTRACE token=" not in line:
            continue
        fields = dict(re.findall(r"(\w+)=([^\s]+)", line))
        if not all(stage in fields for stage in STAGES):
            raise AssertionError("incomplete TASKTRACE record")
        for stage in set(STAGES + SETUP_STAGES):
            fields[stage] = int(fields.get(stage, 0))
        fields["executing"] = int(fields.get("executing", 0))
        fields["cancel_after_stage"] = target
        rows.append(fields)
    if not rows:
        raise AssertionError("no TASKTRACE records: enable -Dtask-trace=true")
    return rows

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sigma", type=Path, default=Path("zig-out/bin/sigma.exe" if os.name == "nt" else "zig-out/bin/sigma"))
    parser.add_argument("--log", type=Path, default=Path(".work/06h/task-path-trace.log"))
    parser.add_argument("--cancel-stages", action="store_true", help="trace-only long-running job; cancel after each setup stage and inside execution")
    parser.add_argument("--analyze", type=Path, help="read a captured log; do not launch sigma")
    args = parser.parse_args()
    if args.analyze:
        for row in records(args.analyze.read_text(encoding="utf-8", errors="replace")):
            print(f"token={row['token']} event={row['event']} cancel_after_stage={row['cancel_after_stage']}")
            if row["token_after"]:
                candidates = [(row[stage], stage) for stage in SETUP_STAGES + ["vm_start", "executing"]
                              if row.get(stage, 0) and row[stage] <= row["token_after"]]
                if candidates:
                    print(f"  last-stage-before-token: {max(candidates)[1]}")
            present = [stage for stage in ["vm_start"] + SETUP_STAGES if row[stage]]
            setup_pairs = list(zip(present, present[1:]))
            for start, end in setup_pairs + [("api_entry", "request"), ("request", "token_before"), ("token_after", "detected"), ("detected", "forth_return"), ("forth_return", "runner_return"), ("runner_return", "sealed"), ("sealed", "published"), ("published", "observed"), ("observed", "host_stopped")]:
                if row[start] and row[end]:
                    print(f"  {start}->{end}: {row[end] - row[start]} ns")
        return
    if args.cancel_stages:
        stages = ["vm_start", "snapshot_retained", "state_reserved", "state_allocated", "memory_allocated",
                  "data_allocated", "return_allocated", "float_allocated", "loops_allocated",
                  "frames_allocated", "catches_allocated", "storage_zeroed", "storage_allocated",
                  "initialized", "plan_allocated", "restore_validated", "restore_applied",
                  "restored", "plan_released", "fresh_checked", "resolved", "grants_ready",
                  "permissions_checked", "input_ready", "executing"]
        args.log.parent.mkdir(parents=True, exist_ok=True)
        with args.log.open("wb") as log:
            for stage in stages:
                env = dict(os.environ, SIGMA_TASK_TRACE_CANCEL_AT=stage)
                run = subprocess.run([str(args.sigma.resolve(strict=True)), "tests/scripts/trace-task-cancel.fs"],
                                     env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
                log.write(f"cancel-after-stage={stage}\n".encode() + run.stdout)
                log.flush()
                assert run.returncode == 0, run.stdout.decode(errors="replace")
                rows = records(run.stdout.decode(errors="replace"))
                assert any(row.get(stage, 0) and row["token_after"] >= row[stage] and row["detected"]
                           for row in rows), f"target stage not reached before cancellation: {stage}"
                assert b"trace-terminal=5 " in run.stdout, run.stdout.decode(errors="replace")
        print(f"Cancellation stage captures saved: {args.log}")
        return
    session_type = runpy.run_path(str(Path(__file__).with_name("verify-task-examples.py")))["Session"]
    session = session_type(str(args.sigma.resolve(strict=True)), "tests/scripts/diagnose-task-path.fs")
    try:
        session.expect("G1 diagnostic:")
        session.send("nnn")
        session.expect("result generation=4 ")
        session.send("dq")
        output = session.finish()
    finally:
        session.close()
        args.log.parent.mkdir(parents=True, exist_ok=True)
        args.log.write_bytes(session.output)
    rows = records(output)
    assert any(row["event"] == "observed" for row in rows)
    print(f"Trace format OK: {len(rows)} records; log: {args.log}")

if __name__ == "__main__":
    main()
