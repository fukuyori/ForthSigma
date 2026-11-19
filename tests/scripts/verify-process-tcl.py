#!/usr/bin/env python3
"""Check shared registry Tcl reservation, protocol restart and script cleanup."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def wait_gone(pid, timeout=5):
    import time
    deadline = time.monotonic() + timeout
    while True:
        try:
            os.kill(int(pid), 0)
        except ProcessLookupError:
            return
        assert time.monotonic() < deadline, ("process still exists", pid)
        time.sleep(.01)


def run(sigma, fixture):
    with tempfile.TemporaryDirectory(prefix="tcl-process-", dir=ROOT / ".work") as directory:
        work = Path(directory)
        log = work / "children.txt"
        env = dict(os.environ, SIGMA_PROCESS_FIXTURE_LOG=str(log))
        source = work / "tcl.fs"
        source.write_text(f'''REQUIRE-EXTENSION ALSO EXTENSION
REQUIRE-GRAPHICS ALSO GRAPHICS
: RESERVE 64 0 DO PROC-NEW THROW LOOP ;
: RELEASE 64 0 DO PROC-FREE THROW LOOP ;
RESERVE
S" {fixture.resolve()}" TCL-PROGRAM
S" first" TCL TCL-STOP
S" second" TCL TCL-STOP
S" third" TCL
RELEASE
." TCL-REGISTRY-PASS" CR BYE
''', encoding="utf-8")
        result = subprocess.run([str(sigma.resolve()), str(source)], cwd=ROOT, env=env,
                                input=b"", capture_output=True, timeout=15)
        output = result.stdout.decode("utf-8", "replace")
        error = result.stderr.decode("utf-8", "replace")
        assert result.returncode == 0 and not error and "TCL-REGISTRY-PASS" in output, (result.returncode, output, error)
        children = [line.split("|", 1) for line in log.read_text().splitlines()]
        assert len(children) == 3, children
        for pid, script in children:
            assert not Path(script).exists(), ("script retained", script)
            if os.name == "nt":
                import ctypes
                api = ctypes.WinDLL("kernel32", use_last_error=True)
                api.OpenProcess.restype = ctypes.c_void_p
                api.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
                api.CloseHandle.argtypes = [ctypes.c_void_p]
                handle = api.OpenProcess(0x100000, False, int(pid))
                if handle:
                    try:
                        assert api.WaitForSingleObject(handle, 0) == 0, ("child still running", pid)
                    finally:
                        api.CloseHandle(handle)
            elif sys.platform == "linux":
                assert not Path("/proc/" + pid).exists(), ("child not reaped", pid)
            else:
                try:
                    os.kill(int(pid), 0)
                except ProcessLookupError:
                    pass
                else:
                    raise AssertionError(("child still exists", pid))
        # Exit must kill retained Tcl descendants before relinquishing its Job/PGID.
        log.unlink()
        env["SIGMA_PROCESS_FIXTURE_DESCENDANT"] = "1"
        source.write_text(f'REQUIRE-GRAPHICS ALSO GRAPHICS S" {fixture.resolve()}" TCL-PROGRAM S" child" TCL BYE\n', encoding="utf-8")
        if sys.platform == "linux":
            import ctypes
            libc = ctypes.CDLL(None, use_errno=True)
            saved = ctypes.c_int()
            assert libc.prctl(37, ctypes.byref(saved), 0, 0, 0) == 0
            assert libc.prctl(36, 1, 0, 0, 0) == 0
        try:
            result = subprocess.run([str(sigma.resolve()), str(source)], cwd=ROOT, env=env,
                                    input=b"", capture_output=True, timeout=8)
            assert result.returncode == 0 and not result.stderr, (result.returncode, result.stdout, result.stderr)
            records = [line.split("|", 1) for line in log.read_text().splitlines()]
            descendants = [int(value) for key, value in records if key == "descendant"]
            assert len(descendants) == 1, records
            for pid in descendants:
                if os.name == "nt":
                    handle = api.OpenProcess(0x100000, False, pid)
                    if handle:
                        try: assert api.WaitForSingleObject(handle, 0) == 0, ("Tcl descendant still running", pid)
                        finally: api.CloseHandle(handle)
                elif sys.platform == "linux":
                    waited, status = os.waitpid(pid, 0)
                    assert waited == pid and os.WIFSIGNALED(status) and os.WTERMSIG(status) == 9, status
                else:
                    wait_gone(pid)
            for key, value in records:
                if key != "descendant": assert not Path(value).exists(), value
        finally:
            if sys.platform == "linux": assert libc.prctl(36, saved.value, 0, 0, 0) == 0
        return {"case": "private-tcl-reservation-restart-and-exit", "children": len(children), "scripts_removed": True, "exit_kills_descendants": True, "stdout": output}


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
