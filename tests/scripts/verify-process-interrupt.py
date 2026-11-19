#!/usr/bin/env python3
"""Interrupt an owned PROC-WAIT without implicitly terminating its child."""
import argparse
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]


def run(sigma):
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        handler_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.DWORD)
        protect_helper = handler_type(lambda event: 1)
        kernel.SetConsoleCtrlHandler.argtypes = [handler_type, wintypes.BOOL]
        kernel.GenerateConsoleCtrlEvent.argtypes = [wintypes.DWORD, wintypes.DWORD]
        assert kernel.SetConsoleCtrlHandler(protect_helper, 1)
        console = open("CONIN$", "rb", buffering=0)
    else:
        console = subprocess.DEVNULL
    try:
        with tempfile.TemporaryDirectory(prefix="process-interrupt-", dir=ROOT / ".work") as directory:
            work = Path(directory)
            producer = work / "producer.py"
            producer.write_text("import time\ntime.sleep(30)\n")
            assert '"' not in str(producer) + sys.executable
            source = work / "interrupt.fs"
            source.write_text(
                'REQUIRE-EXTENSION ALSO EXTENSION DECIMAL\n'
                'PROC-NEW THROW CONSTANT P\n'
                f'S" {sys.executable}" P PROC-ARG THROW S" {producer}" P PROC-ARG THROW\n'
                '2 0 P PROC-IO THROW 2 1 P PROC-IO THROW 2 2 P PROC-IO THROW P PROC-START THROW\n'
                ': WAIT P -1 PROC-WAIT ;\n'
                '." READY" CR STDOUT FLUSH-FILE THROW \' WAIT CATCH .\n'
                'P PROC-STATUS THROW ." CHILD " . . CR\n'
                'P PROC-KILL THROW P 3000 PROC-WAIT THROW 2DROP P PROC-FREE THROW ." FINISHED" CR BYE\n'
            )
            child = subprocess.Popen([str(sigma.resolve()), str(source)], cwd=ROOT,
                                     stdin=console, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            lines = queue.Queue()
            threading.Thread(target=lambda: lines.put(child.stdout.readline()), daemon=True).start()
            try:
                ready = lines.get(timeout=8)
                assert b"READY" in ready, ready
                time.sleep(.1)
                if os.name == "nt":
                    assert kernel.GenerateConsoleCtrlEvent(0, 0)
                else:
                    child.send_signal(signal.SIGINT)
                out, err = child.communicate(timeout=8)
                assert child.returncode == 0 and b"-28 CHILD 0 1" in out and b"FINISHED" in out and not err, (child.returncode, out, err)
                return {"platform": sys.platform, "case": "proc-wait-interrupt-keeps-child-running", "stdout": (ready + out).decode(), "exit_code": 0}
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()
    finally:
        if os.name == "nt":
            console.close()
            kernel.SetConsoleCtrlHandler(protect_helper, 0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sigma", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--console-child", action="store_true")
    args = parser.parse_args()
    if os.name == "nt" and not args.console_child:
        startup = subprocess.STARTUPINFO()
        startup.dwFlags = subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
        command = [sys.executable, __file__, "--sigma", str(args.sigma.resolve()), "--console-child"]
        if args.output:
            command += ["--output", str(args.output.resolve())]
        result = subprocess.run(command, creationflags=subprocess.CREATE_NEW_CONSOLE, startupinfo=startup, timeout=20, capture_output=True)
        sys.stdout.buffer.write(result.stdout)
        sys.stderr.buffer.write(result.stderr)
        raise SystemExit(result.returncode)
    report = run(args.sigma)
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))
