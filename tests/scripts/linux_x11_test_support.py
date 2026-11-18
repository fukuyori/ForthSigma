"""Private authenticated Xvfb and bounded Sigma output for Linux integration tests."""
import hashlib
import json
import os
from pathlib import Path
import secrets
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time


def skip(reason):
    print(json.dumps({'skipped': reason}))
    raise SystemExit(77)


def require_linux():
    if sys.platform != 'linux':
        skip('Linux is required')


def binary_identity(binary):
    path = Path(binary).resolve()
    data = path.read_bytes()
    return {'path': str(path), 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}


def stop_process_group(process, timeout=3):
    """Stop only a child started with start_new_session=True, including its helpers."""
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=timeout)
    # A failed Sigma might have exited before its wish. Its private session's
    # remaining process group must not survive the test's error path.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


class SigmaSession:
    def __init__(self, binary, source, env):
        self.stderr = tempfile.TemporaryFile()
        self.buffer = b''
        try:
            self.process = subprocess.Popen([binary, '-e', source], env=env,
                                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=self.stderr, bufsize=0, start_new_session=True)
        except BaseException:
            self.stderr.close()
            raise

    def line(self, timeout=7):
        until = time.monotonic() + timeout
        while b'\n' not in self.buffer:
            remaining = until - time.monotonic()
            if remaining <= 0 or not select.select([self.process.stdout], [], [], max(0, remaining))[0]:
                raise TimeoutError('Sigma output line deadline')
            data = os.read(self.process.stdout.fileno(), 4096)
            if not data:
                raise AssertionError(('Sigma stdout ended before a complete line', self.errors()))
            self.buffer += data
            if len(self.buffer) > 1024 * 1024:
                raise AssertionError('Sigma output line too large')
        line, self.buffer = self.buffer.split(b'\n', 1)
        return line.rstrip(b'\r')

    def errors(self):
        self.stderr.seek(0)
        return self.stderr.read(65536).decode('utf-8', 'replace')

    def send(self, byte=b'x'):
        self.process.stdin.write(byte)
        self.process.stdin.flush()

    def finish(self, timeout=5):
        if not self.process.stdin.closed:
            self.process.stdin.close()
        self.process.wait(timeout=timeout)
        assert self.process.returncode == 0, self.errors()

    def close(self):
        try:
            stop_process_group(self.process)
        finally:
            self.process.stdout.close()
            if not self.process.stdin.closed:
                self.process.stdin.close()
            self.stderr.close()

    def __enter__(self):
        return self

    def __exit__(self, *unused):
        self.close()


class OwnedXvfb:
    """Let Xvfb allocate its display atomically, and use a private MIT cookie."""
    def __init__(self):
        require_linux()
        self.executable = os.environ.get('SIGMA_TEST_XVFB') or shutil.which('Xvfb')
        self.wish = shutil.which('wish')
        if not self.executable or not self.wish:
            skip('Xvfb and wish are required')
        self.folder = tempfile.TemporaryDirectory(prefix='sigma-x11-test-')
        self.server_auth = Path(self.folder.name) / 'server.auth'
        self.client_auth = Path(self.folder.name) / 'client.auth'
        self.cookie = secrets.token_bytes(16)
        self._write_auth(self.server_auth, b'')
        self.log = open(Path(self.folder.name) / 'xvfb.log', 'w+b')
        self.process = None
        self.number = None
        self.previous_env = {}

    def _write_auth(self, path, number):
        def field(data):
            return struct.pack('>H', len(data)) + data
        # Xvfb loads the server's cookie regardless of display/address fields.
        # Xlib clients get a separate entry with the exact allocated number.
        data = struct.pack('>H', 65535) + field(b'') + field(number) + field(b'MIT-MAGIC-COOKIE-1') + field(self.cookie)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'wb') as out:
            out.write(data)

    def start(self):
        assert self.process is None
        reading, writing = os.pipe()
        command = [self.executable]
        if self.number is not None:
            command.append(f':{self.number}')
        command += ['-screen', '0', '1280x720x24', '-nolisten', 'tcp',
                    '-auth', str(self.server_auth), '-displayfd', str(writing)]
        try:
            self.process = subprocess.Popen(command, pass_fds=(writing,), stdout=self.log,
                                            stderr=self.log, start_new_session=True)
        except BaseException:
            os.close(reading)
            os.close(writing)
            raise
        os.close(writing)
        try:
            if not select.select([reading], [], [], 5)[0]:
                raise TimeoutError('private Xvfb startup')
            value = os.read(reading, 128).strip()
            assert value.isdigit() and self.process.poll() is None, 'private Xvfb failed before ready'
            actual = int(value)
            if self.number is None:
                self.number = actual
                self._write_auth(self.client_auth, str(actual).encode())
            else:
                assert actual == self.number, 'Xvfb restarted on another display'
        except BaseException:
            self.stop()
            raise
        finally:
            os.close(reading)

    def stop(self):
        if self.process is not None:
            child, self.process = self.process, None
            stop_process_group(child)

    def environment(self, **overrides):
        result = dict(os.environ, DISPLAY=f':{self.number}', WAYLAND_DISPLAY='',
                      XMODIFIERS='@im=none', XAUTHORITY=str(self.client_auth), SIGMA_WISH=self.wish)
        result.update(overrides)
        return result

    def wish_version(self):
        result = subprocess.run([self.wish], env=self.environment(),
                                input='wm withdraw .\nputs "Tcl:[info patchlevel] Tk:[package require Tk]"\nexit\n',
                                capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, result.stderr
        return result.stdout.strip()

    def __enter__(self):
        try:
            self.start()
            for name in ('DISPLAY', 'XAUTHORITY'):
                self.previous_env[name] = os.environ.get(name)
            os.environ['DISPLAY'] = f':{self.number}'
            os.environ['XAUTHORITY'] = str(self.client_auth)
            return self
        except BaseException:
            self.close()
            raise

    def close(self):
        try:
            self.stop()
        finally:
            self.log.close()
            self.folder.cleanup()
            for name, old in self.previous_env.items():
                if old is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = old

    def __exit__(self, *unused):
        self.close()
