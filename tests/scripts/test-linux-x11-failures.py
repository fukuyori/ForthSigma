#!/usr/bin/env python3
"""Exercise explicit native X11 setup rejection, EOF and a stalled server.
Build Sigma with -Dx11=true. Set SIGMA_TEST_BINARY to select another binary.
No desktop connection is used; this test owns a temporary local X11 socket.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
SIGMA = os.environ.get('SIGMA_TEST_BINARY', str(ROOT / 'zig-out/bin/sigma'))
SOURCE = 'REQUIRE-GRAPHICS ALSO GRAPHICS 2 2 GFX-INIT DISPLAY-WINDOW : T [\'] SHOW CATCH . ; T BYE'
results = {}
for mode in ('reject', 'eof', 'stall'):
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    path = None
    for number in range(200, 240):
        candidate = f'/tmp/.X11-unix/X{number}'
        try:
            server.bind(candidate)
            path = candidate
            break
        except OSError:
            continue
    if path is None:
        server.close()
        raise RuntimeError('No free local X11 test socket')
    server.listen(1)
    server.settimeout(8)
    finish = threading.Event()
    errors = []

    def serve():
        try:
            client, _ = server.accept()
            with client:
                if mode == 'eof':
                    return
                client.settimeout(2)
                client.recv(320)
                if mode == 'reject':
                    client.sendall(b'\0\0\x0b\0\0\0\0\0')
                else:
                    finish.wait(8)
        except Exception as error:
            errors.append(str(error))

    worker = threading.Thread(target=serve, daemon=True)
    worker.start()
    try:
        environment = dict(os.environ, DISPLAY=f':{number}', XAUTHORITY='/tmp/sigma-test-absent-authority', XMODIFIERS='@im=none')
        started = time.monotonic()
        process = subprocess.run([SIGMA, '-e', SOURCE], env=environment, capture_output=True, text=True, timeout=8)
        elapsed = time.monotonic() - started
        assert process.returncode == 0, (mode, process.stdout, process.stderr)
        assert process.stdout.strip() == '-265', (mode, process.stdout, process.stderr)
        assert elapsed < 6, (mode, elapsed)
        if mode == 'stall':
            assert elapsed >= 4.5, elapsed
        results[mode] = {'caught': -265, 'seconds': round(elapsed, 3)}
    finally:
        finish.set()
        worker.join(2)
        server.close()
        Path(path).unlink()
    assert not errors, errors
print(json.dumps(results, indent=2))
