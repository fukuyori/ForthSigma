#!/usr/bin/env python3
"""Initial experimental Linux native/Tk search: one 5 s budget including cleanup.
Build with -Dx11=true; SIGMA_TEST_BINARY overrides the executable. No desktop used.
Temporary fake wish programs exercise blocked pipes, trickling output and recovery.
"""
import json
import os
from pathlib import Path
import signal
import select
import socket
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
SIGMA = os.environ.get('SIGMA_TEST_BINARY', str(ROOT / 'zig-out/bin/sigma'))
FAKE = r'''#!/usr/bin/env python3
import os, signal, sys, time
with open(os.environ['SIGMA_TEST_PID_LOG'], 'a') as f:
    f.write(str(os.getpid()) + '\n')
signal.signal(signal.SIGTERM, signal.SIG_IGN)
mode = os.environ['SIGMA_TEST_WISH_MODE']
if mode == 'blocked':
    while True: time.sleep(1)
if mode == 'stopped':
    os.kill(os.getpid(), signal.SIGSTOP)
if mode == 'trickle':
    while True:
        os.write(1, b'E 0 0\n')
        time.sleep(.04)
if mode == 'partial':
    os.write(1, b'R 0 999999\n')
    while True:
        os.write(1, b'a')
        time.sleep(.04)
while True:
    header = sys.stdin.buffer.readline()
    if not header: break
    left = int(header)
    while left:
        data = sys.stdin.buffer.read(min(left, 4096))
        if not data: sys.exit(0)
        left -= len(data)
    if mode == 'normal':
        os.write(1, b'R 0 0\n')
'''
results = {}
with tempfile.TemporaryDirectory(prefix='sigma-budget-') as folder:
    program = Path(folder) / 'wish-fixture'
    program.write_text(FAKE)
    program.chmod(0o700)
    pid_log = Path(folder) / 'children'
    env = dict(os.environ, DISPLAY=':19999', WAYLAND_DISPLAY='', XMODIFIERS='@im=none',
               SIGMA_WISH=str(program), SIGMA_TEST_PID_LOG=str(pid_log),
               XAUTHORITY=str(Path(folder) / 'absent-authority'))

    def run(name, mode, size=2, source=None, display=None, lower=4.5, upper=5.25):
        pid_log.write_text('')
        case_env = dict(env, SIGMA_TEST_WISH_MODE=mode)
        if display is not None: case_env['DISPLAY'] = display
        command = source or f'REQUIRE-GRAPHICS ALSO GRAPHICS {size} {size} GFX-INIT TRUE GFX-AUTO-TRY . BYE'
        # KEY flushes the search result and holds Sigma alive until Python has
        # inspected its children. This avoids timing a short sampling window.
        command = command.removesuffix(' BYE') + ' CR KEY DROP BYE'
        started = time.monotonic()
        child = subprocess.Popen([SIGMA, '-e', command], env=case_env, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        reaped = set()
        try:
            ready, _, _ = select.select([child.stdout], [], [], upper + 3)
            if not ready: raise TimeoutError(name)
            checkpoint = child.stdout.readline()
            elapsed = time.monotonic() - started
            assert child.poll() is None, (name, checkpoint)
            for line in pid_log.read_text().splitlines():
                pid = int(line)
                if not Path(f'/proc/{pid}').exists(): reaped.add(pid)
            rest, stderr = child.communicate(input='x', timeout=3)
            stdout = checkpoint + rest
        finally:
            if child.poll() is None: child.kill(); child.wait()
        assert child.returncode == 0, (name, stdout, stderr)
        assert lower <= elapsed <= upper, (name, elapsed, stdout, stderr)
        assert stdout.strip() == ('3' if mode == 'normal' else '1'), (name, stdout, stderr)
        pids = [int(line) for line in pid_log.read_text().splitlines()]
        assert pids, (name, 'wish was never attempted')
        for pid in pids:
            assert not Path(f'/proc/{pid}').exists(), (name, 'child not reaped', pid)
        if mode != 'normal':
            expected = len(pids) - (1 if name == 'explicit_tcl_after_timeout' else 0)
            assert len(reaped) >= expected, (name, 'failed child not reaped while Sigma alive', pids, reaped)
        results[name] = dict(seconds=round(elapsed, 3), mode=int(stdout.strip()), children_gone=len(pids), children_reaped_while_parent_running=len(reaped))

    run('silent_response', 'silent')
    run('blocked_large_write', 'blocked', size=4096)
    run('stopped_child', 'stopped')
    run('event_trickle', 'trickle')
    run('partial_reply_trickle', 'partial')
    run('healthy_tk', 'normal', lower=0, upper=2)
    # A timed-out automatic attempt must clear its deadline before explicit TCL.
    normal = Path(folder) / 'normal-wish'
    normal.write_text(FAKE.replace("mode = os.environ['SIGMA_TEST_WISH_MODE']", "mode = 'normal'"))
    normal.chmod(0o700)
    recovery = ('REQUIRE-GRAPHICS ALSO GRAPHICS 2 2 GFX-INIT TRUE GFX-AUTO-TRY DROP '
                f'S" {normal}" TCL-PROGRAM S" x" TCL 1 . BYE')
    run('explicit_tcl_after_timeout', 'silent', source=recovery)
    retry = ('REQUIRE-GRAPHICS ALSO GRAPHICS 2 2 GFX-INIT '
             'TRUE GFX-AUTO-TRY DROP DISPLAY-AUTO TRUE GFX-AUTO-TRY . BYE')
    run('fresh_search_after_display_auto', 'silent', source=retry, lower=9.5, upper=10.5)

    if not os.path.isdir('/tmp/.X11-unix') or not os.access('/tmp/.X11-unix', os.W_OK):
        results['native_socket_cases'] = {'skipped': 'local X11 socket directory is unavailable'}
    else:
        # Native stalls for its 2 s allocation; Tk receives only the shared remainder.
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        path = None
        for number in range(200, 240):
            candidate = Path(f'/tmp/.X11-unix/X{number}')
            try:
                server.bind(str(candidate)); path = candidate; break
            except OSError: pass
        if path is None: raise RuntimeError('no unused X11 test socket')
        server.listen(1)
        server.settimeout(8)
        finish = threading.Event()
        errors = []
        def serve():
            try:
                client, _ = server.accept()
                with client:
                    client.recv(320)
                    finish.wait(8)
            except Exception as exc: errors.append(str(exc))
        worker = threading.Thread(target=serve, daemon=True)
        worker.start()
        try:
            run('native_and_tk_share_budget', 'silent', display=f':{number}')
        finally:
            finish.set(); worker.join(2); server.close(); path.unlink()
        assert not errors, errors

        # First native attempt times out; count the next accept to prove it retries.
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(path)); server.listen(2); server.settimeout(4)
        accepted = []
        errors = []
        def retry_server():
            try:
                for attempt in range(2):
                    client, _ = server.accept(); accepted.append(attempt)
                    with client:
                        client.settimeout(3)
                        client.recv(320)
                        if attempt == 0:
                            while client.recv(320): pass
                        else:
                            client.sendall(b'\0\0\x0b\0\0\0\0\0')
            except Exception as exc: errors.append(str(exc))
        worker = threading.Thread(target=retry_server, daemon=True); worker.start()
        try:
            run('native_timeout_then_native_retry', 'normal', display=f':{number}', source=retry, lower=1.8, upper=3.5)
        finally:
            worker.join(4); server.close(); path.unlink()
        assert not errors, errors
        assert len(accepted) == 2, accepted
print(json.dumps(results, indent=2))
