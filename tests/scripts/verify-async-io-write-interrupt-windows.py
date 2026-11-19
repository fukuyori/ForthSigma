#!/usr/bin/env python3
"""Interrupt an owned queued writer close; retain the ID and retry the drain."""
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
        with tempfile.TemporaryDirectory(prefix="write-interrupt-", dir=ROOT / ".work") as directory:
            work = Path(directory)
            producer = work / "producer.py"
            producer.write_text("import sys,time,signal\nsignal.signal(signal.SIGINT,signal.SIG_IGN)\ntime.sleep(3)\nsys.stdin.buffer.read()\n")
            source = work / "interrupt.fs"
            source.write_text(
                'REQUIRE-EXTENSION ALSO EXTENSION DECIMAL\n'
                f'S" {sys.executable} {producer}" W/O OPEN-PIPE THROW CONSTANT P\n'
                'CREATE DATA 65536 ALLOT DATA 65536 65 FILL\n'
                'DATA 65536 P WRITE-AVAILABLE THROW DROP\n'
                '." READY" CR STDOUT FLUSH-FILE THROW\n'
                'P CLOSE-PIPE ." CLOSE " . . CR\n'
                'PAD 0 P WRITE-AVAILABLE ." STILL-OPEN " . . CR\n'
                'P FLUSH-FILE THROW P CLOSE-PIPE THROW DROP ." FINISHED" CR BYE\n'
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
                assert child.returncode == 0 and b"CLOSE -516 -1" in out and b"STILL-OPEN 0 0" in out and b"FINISHED" in out and not err, (child.returncode, out, err)
                return {"platform": sys.platform, "case": "queued-close-interrupt-retains-id-and-retries", "stdout": (ready + out).decode(), "exit_code": 0}
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
