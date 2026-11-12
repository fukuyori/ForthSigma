#!/usr/bin/env python3
"""EKEY host regressions. Run: python3 scripts/verify-ekey.py zig-out/bin/sigma"""
import os
import subprocess
import sys
import time

exe = sys.argv[1] if len(sys.argv) > 1 else "zig-out/bin/sigma"
# An open empty pipe must not hold EKEY? until the writer closes it.
p = subprocess.Popen([exe, "-e", "EKEY? . BYE"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
try:
    p.wait(timeout=2)
    assert p.stdout.read() == b"0 "
finally:
    p.stdin.close()
    if p.poll() is None:
        p.kill()
    p.wait()

for program, data, expected in [
    ("EKEY . KEY . BYE", b"\x1b[99~", b"27 91 "),
    ("EKEY . EKEY . BYE", "日é".encode(), b"26085 233 "),
    ("EKEY? . KEY . BYE", b"A", b"-1 65 "),
    ("EKEY . BYE", b"\x03", b"3 "),
]:
    result = subprocess.run([exe, "-e", program], input=data, stdout=subprocess.PIPE, timeout=3, check=True)
    assert result.stdout == expected, (program, result.stdout)

if os.name == "posix":
    import pty
    for program, data, expected in [
        ("EKEY . BYE", b"\x1b", b"27 "),
        ("KEY . EKEY . BYE", "Aé\n".encode(), b"65 233 "),
        ("300 MS EKEY? . EKEY . BYE", b"A", b"-1 65 "),
        ("\' EKEY CATCH . BYE", b"\x03", b"-28 "),
        ("EKEY? DROP 300 MS \' EKEY? CATCH . BYE", b"\x03", b"-28 "),
        ("EKEY . PAD 16 ACCEPT PAD SWAP TYPE BYE", b"\x1b[xyz\n", b"27 [xyz"),
        ("EKEY . KEY . BYE", b"Aq\n", b"65 113 "),
    ]:
        master, slave = pty.openpty()
        p = subprocess.Popen([exe, "-e", program], stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        os.close(slave)
        try:
            time.sleep(0.15)
            start = time.monotonic()
            os.write(master, data)
            out, err = p.communicate(timeout=3)
            elapsed = time.monotonic() - start
            assert p.returncode == 0 and out == expected, (program, out, err)
            if data == b"\x1b":
                assert 0.035 <= elapsed < 0.5, elapsed
        finally:
            os.close(master)
            if p.poll() is None:
                p.kill()
            p.wait()
    # Exercise ACCEPT with both streams attached to a terminal, enabling line editing.
    import errno
    import select
    master, slave = pty.openpty()
    program = 'EKEY DROP PAD 16 ACCEPT PAD SWAP S" [xyz" COMPARE . BYE'
    p = subprocess.Popen([exe, "--max-steps", "100000", "-e", program], stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    captured = b""
    try:
        time.sleep(0.15)
        os.write(master, b"\x1b[xyz\n")
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    chunk = os.read(master, 4096)
                except OSError as error:
                    if error.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                captured += chunk
            if p.poll() is not None:
                break
        p.wait(timeout=1)
        assert p.returncode == 0 and captured.endswith(b"\r\n0 "), captured
    finally:
        os.close(master)
        if p.poll() is None:
            p.kill()
        p.wait()
print("EKEY pipe checks passed; " + ("POSIX PTY checks passed" if os.name == "posix" else "PTY checks skipped"))
