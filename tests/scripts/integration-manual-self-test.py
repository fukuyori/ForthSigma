#!/usr/bin/env python3
"""Windows manual-adapter regression. No listening/visual acceptance is claimed."""
import ctypes
from ctypes import wintypes as W
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]


def run(unit, binary=None):
    argv = [sys.executable, '-u', 'tests/scripts/integration-acceptance.py',
            '--manual', unit, '--configs', 'M0']
    if binary: argv += ['--binary', str(binary)]
    child = subprocess.Popen(argv, cwd=ROOT, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             encoding='utf-8', errors='strict', env={**os.environ, 'PYTHONIOENCODING': 'utf-8'})
    chunks = queue.Queue()
    def read():
        while True:
            ch = child.stdout.read(1)
            chunks.put(ch)
            if not ch: return
    threading.Thread(target=read, daemon=True).start()
    output = ''
    def wait(token, start=0):
        nonlocal output
        deadline = time.monotonic() + 120
        while token not in output[start:]:
            if time.monotonic() >= deadline: raise AssertionError('timeout: '+token)
            try: ch = chunks.get(timeout=0.1)
            except queue.Empty: continue
            if not ch: raise AssertionError('unexpected EOF: '+output)
            output += ch
        return len(output)
    def send(value):
        child.stdin.write(value+'\n'); child.stdin.flush()
    try:
        wait('キー> ')
        if unit == 'MNL-03a':
            send('Ctrl+C'); wait('IA-CAUGHT interrupt; resources retained')
            send('n'); wait('NATIVE-INPUT generation=2'); wait('result generation=2')
            send('q')
        elif unit == 'MNL-03b':
            send('c'); wait('IA-CANCEL resubmitted'); wait('result generation=2')
            send('n'); wait('result generation=3'); send('q')
        elif unit == 'MNL-04':
            wait('PCM-START'); send('q'); wait('IA-EXIT live BYE')
        else:
            # Identify only this run's application from the absolute printed path.
            app = Path(re.search(r'実行体: (.+)\n', output)[1].strip())
            snapshots = json.loads((app.parent/'manual/processes.json').read_text(encoding='utf-8'))
            ids = {p['pid'] for s in snapshots for p in s['processes']
                   if Path(p['name']).name.lower() == 'sigma.exe'}
            user = ctypes.WinDLL('user32', use_last_error=True)
            user.PostMessageW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
            hits = []
            @ctypes.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
            def visit(hwnd, _):
                pid = W.DWORD()
                user.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
                if pid.value in ids and user.IsWindowVisible(hwnd):
                    if not user.PostMessageW(hwnd, 0x10, 0, 0): raise ctypes.WinError(ctypes.get_last_error())
                    hits.append(pid.value)
                return True
            user.EnumWindows(visit, 0)
            assert hits, 'owned visible window missing'
            wait('IA-END'); wait('保存アプリ終了。'); send('')
        wait('観察結果> ')
        send(''); wait('観察結果を入力してください。')
        send('自動試験。聴取・目視は未確認。')
        child.stdin.close()
        while True:
            ch = chunks.get(timeout=120)
            if not ch: break
            output += ch
        assert child.wait(timeout=10) == 0
        assert 'M0 manual pass' in output, output
        assert '[app] IA-END' in output or 'IA-EXIT live BYE' in output
        assert 'PAINTTRACE' not in output and 'PCM-SUPPLY' not in output
        app = Path(re.search(r'実行体: (.+)\n', output)[1].strip())
        (app.parent/'manual-console.txt').write_text(output, encoding='utf-8', newline='\n')
        result = json.loads((app.parent/'manual/result.json').read_text(encoding='utf-8'))
        assert result['status'] == 'pass', result
        assert not result['forced_cleanup']
        print(unit, 'PASS', app.parent, flush=True)
        for line in output.splitlines():
            if '[app]' in line: print(line.strip(), flush=True)
        return app.parent/'build/bin/sigma.exe' if binary is None else binary
    finally:
        if child.poll() is None:
            child.kill(); child.wait()


if __name__ == '__main__':
    if os.name != 'nt': raise SystemExit('Windows regression only; POSIX execution remains unverified')
    binary = None
    for unit in ('MNL-03a', 'MNL-03b', 'MNL-04', 'MNL-05'):
        binary = run(unit, binary)
