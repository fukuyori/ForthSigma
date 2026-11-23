"""Helpers for the macOS display scripts: run Sigma in its own process group.

The macOS counterpart of windows_display_test_support.py. Sigma, its AppKit window
child, and wish are started in a new session, so that the whole group is stopped at
the end and no helper outlives a script.
"""
import hashlib
import os
from pathlib import Path
import queue
import signal
import subprocess
import sys
import tempfile
import threading
import time

if sys.platform != 'darwin':
    print('skip: macOS only')
    sys.exit(0)


def binary_identity(binary):
    path = Path(binary).resolve()
    data = path.read_bytes()
    return dict(path=str(path), sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))


def _group_alive(pgid):
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def stop_group(process, timeout=3):
    """Stop the process group of a child started with start_new_session=True."""
    if process is None:
        return
    pgid = process.pid
    for sig in (signal.SIGTERM, signal.SIGKILL):
        if not _group_alive(pgid):
            break
        try:
            os.killpg(pgid, sig)
        except ProcessLookupError:
            break
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline and _group_alive(pgid):
            if process.poll() is None:
                try:
                    process.wait(timeout=.05)
                except subprocess.TimeoutExpired:
                    pass
            else:
                time.sleep(.05)
    if process.poll() is None:
        process.wait(timeout=5)


def assert_group_gone(process, timeout=5):
    """After a normal end, no helper (the AppKit child, wish) is left in the group."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not _group_alive(process.pid):
            return
        time.sleep(.05)
    raise AssertionError('helpers of Sigma are still running')


def invoke(binary, source=None, cwd=None, timeout=60):
    arguments = [str(Path(binary).resolve())]
    if source is not None:
        arguments += ['-e', 'KEY DROP ' + source]
    process = subprocess.Popen(arguments, cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    try:
        stdout, stderr = process.communicate(input=b'\n', timeout=timeout)
        output = stdout.decode('utf-8', 'replace')
        assert process.returncode == 0 and not stderr, (process.returncode, output, stderr)
        assert 'BACKTRACE:' not in output and 'STACK UNDER FLOW' not in output, output
        assert_group_gone(process)
        return output
    finally:
        stop_group(process)


def run(binary, source, cwd=None):
    return invoke(binary, source, cwd)


class SigmaSession:
    """Line protocol with a deadline, process-group ownership and an initial KEY gate."""
    def __init__(self, binary, source, cwd=None):
        self.process = None
        self.stderr = tempfile.TemporaryFile()
        self.lines = queue.Queue()
        try:
            self.process = subprocess.Popen([str(Path(binary).resolve()), '-e', 'KEY DROP ' + source], cwd=cwd,
                                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.stderr,
                                            start_new_session=True)

            def read_lines():
                try:
                    for line in iter(self.process.stdout.readline, b''):
                        self.lines.put(line.rstrip(b'\r\n'))
                finally:
                    self.lines.put(None)
            self.reader = threading.Thread(target=read_lines, daemon=True)
            self.reader.start()
            self.send()
        except BaseException:
            self.close()
            raise

    def send(self):
        self.process.stdin.write(b'\n')
        self.process.stdin.flush()

    def line(self, timeout=7):
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty:
            raise TimeoutError('Sigma stdout line deadline') from None
        if line is None:
            raise AssertionError(('Unexpected Sigma EOF', self.errors()))
        return line

    def errors(self):
        self.stderr.seek(0)
        return self.stderr.read()

    def finish(self):
        assert self.process.wait(timeout=10) == 0, self.errors()
        self.reader.join(timeout=5)
        assert not self.reader.is_alive()
        trailing = []
        while not self.lines.empty():
            item = self.lines.get_nowait()
            if item is not None:
                trailing.append(item)
        assert not trailing and not self.errors(), (trailing, self.errors())
        assert_group_gone(self.process)

    def close(self):
        if self.process is not None:
            stop_group(self.process)
            if hasattr(self, 'reader'):
                self.reader.join(timeout=5)
            for stream in (self.process.stdin, self.process.stdout):
                if stream:
                    stream.close()
        self.stderr.close()

    def __enter__(self):
        return self

    def __exit__(self, *unused):
        self.close()
