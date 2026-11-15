#!/usr/bin/env python3
"""Windows native integration contracts; no Gforth comparison or console claim."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import datetime
import shutil

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--sigma', type=Path, default=Path('zig-out/bin/sigma.exe'))
a = p.parse_args()
if os.name != 'nt':
    p.error('Windows required')
sigma = str(a.sigma.resolve(strict=True))
root = Path('.work/windows-native').resolve()
root.mkdir(parents=True, exist_ok=True)
passed = []

def run(name, source, expected, data=b'', env=None, binary=None, status=0):
    r = subprocess.run([binary or sigma, '--max-steps', '100000', '-e', source],
                       cwd=root, input=data, capture_output=True, timeout=30, env=env)
    assert (r.returncode, r.stdout) == (status, expected), (name, r.returncode, r.stdout, r.stderr, expected)
    passed.append(name)

child = root / 'pipe-child.py'
child.write_text('import sys\nif sys.argv[1]=="read":\n sys.stdout.buffer.write(b"A\\x00B\\n"); sys.stdout.flush(); sys.exit(3)\nelse:\n open(sys.argv[2],"wb").write(sys.stdin.buffer.read())\n', encoding='utf-8')
command = subprocess.list2cmdline([sys.executable, str(child), 'read'])
run('pipe-read-binary-status', f': BYTES BOUNDS ?DO I C@ . LOOP ; S\" {command}\" R/O BIN OPEN-PIPE THROW CONSTANT P P SLURP-FID OVER >R BYTES R> FREE THROW P CLOSE-PIPE . . BYE', b'65 0 66 10 0 3 ')
target = root / 'written.bin'
command = subprocess.list2cmdline([sys.executable, str(child), 'write', str(target)])
run('pipe-write-unicode', f'S\" {command}\" W/O BIN OPEN-PIPE THROW CONSTANT P S\" 日本語\" P WRITE-FILE THROW P FLUSH-FILE THROW P CLOSE-PIPE . . BYE', b'0 0 ')
assert target.read_bytes() == '日本語'.encode()
run('pipe-invalid-mode', 'S" exit 0" R/W OPEN-PIPE . . BYE', b'-534 0 ')
run('shell-output-status', ': BYTES BOUNDS ?DO I C@ . LOOP ; S" echo ABC& exit /b 3" SH-GET BYTES $? . BYE', b'65 66 67 13 10 3 ')
run('shell-empty', 'S" exit /b 0" SH-GET NIP . $? . BYE', b'0 0 ')
run('input-throw-restores', ': R KEY DROP -123 THROW ; : RUN [\'] R STDIN INFILE-EXECUTE ; \' RUN CATCH . INFILE-ID STDIN = . KEY . BYE', b'-123 -1 66 ', b'AB')
run('output-throw-restores', 'S" out.txt" W/O CREATE-FILE THROW CONSTANT F : R 65 EMIT -123 THROW ; : RUN [\'] R F OUTFILE-EXECUTE ; \' RUN CATCH . OUTFILE-ID STDOUT = . F CLOSE-FILE THROW BYE', b'-123 -1 ')
assert (root / 'out.txt').read_bytes() == b'A'
run('marker-redefinition', ': KEPT 7 ; MARKER M : KEPT 8 ; KEPT . M KEPT . BYE', b'WARNING: SAME NAME WORD EXISTS\r\n8 7 ')
run('dictionary-save-load', ': KEPT 42 ; SAVE words.sigma LOAD-DICTIONARY words.sigma KEPT . BYE', b'42 ')
run('saved-system-create', ': KEPT 42 ; SAVESYS saved.exe BYE', b'')
run('saved-system-run', 'KEPT . BYE', b'42 ', binary=str(root / 'saved.exe'))
entries = root / '日本語 directory'
entries.mkdir(exist_ok=True)
for name in ['alpha', '日本語 file', 'a space']:
    (entries / name).write_text('x', encoding='utf-8')
directory_source = f'S" {entries}" OPEN-DIR THROW CONSTANT D : LIST-DIR BEGIN PAD 1024 D READ-DIR THROW WHILE PAD SWAP TYPE CR REPEAT DROP ; LIST-DIR D CLOSE-DIR THROW BYE'
r = subprocess.run([sigma, '-e', directory_source], input=b'', capture_output=True, timeout=20)
assert r.returncode == 0 and set(r.stdout.decode().splitlines()) == {'.', '..', 'alpha', '日本語 file', 'a space'}, (r.stdout, r.stderr)
passed.append('directory-unicode-enumeration')
for stamp in [0, 1704067200, 2147483648]:
    local = datetime.datetime.fromtimestamp(stamp)
    expected = f'{local.year} {local.month} {local.day} {local.hour} {local.minute} {local.second} '.encode()
    run(f'timezone-{stamp}', f'{stamp}. >TIME&DATE&TZ 2DROP 2DROP . . . . . . BYE', expected)

# Exercise a quoted executable path as well as a quoted script/source argument.
editor = root / 'editor space'
editor.mkdir(exist_ok=True)
editor_python = editor / 'python.exe'
shutil.copy2(sys.executable, editor_python)
python_dll = Path(sys.executable).with_name(f'python{sys.version_info.major}{sys.version_info.minor}.dll')
shutil.copy2(python_dll, editor / python_dll.name)
stub = editor / 'record.py'
log = editor / 'calls.json'
stub.write_text('import json,os,pathlib,sys\np=pathlib.Path(sys.argv[-1]); pathlib.Path(sys.argv[1]).write_text(json.dumps({"line":sys.argv[-2],"path":str(p),"text":p.read_text(encoding="utf-8")})); sys.exit(int(os.environ.get("SIGMA_EDITOR_EXIT", "0")))\n', encoding='utf-8')
env = dict(os.environ, PYTHONHOME=sys.base_prefix, EDITOR='"' + str(editor_python) + '" ' + subprocess.list2cmdline([str(stub), str(log)]))
source = root / '日本語 source & argument.fs'
source.write_text(': EDIT-NATIVE 11 ;\n: EDIT-USE EDIT-NATIVE ;\n', encoding='utf-8')
include = f'S" {source}" INCLUDED '
run('editor-file', include + 'EDIT EDIT-NATIVE BYE', b'', env=env)
call = json.loads(log.read_text())
assert call['line'] == '+1' and call['path'] == str(source), call
run('editor-report', include + 'WHEREG EDIT-NATIVE BYE', b'', env=env)
call = json.loads(log.read_text())
assert 'EDIT-USE' in call['text'] and not Path(call['path']).exists(), call
run('editor-failure-cleanup', include + 'WHEREG EDIT-NATIVE BYE', b'HOST FUNCTION ERROR !\r\n', env=dict(env, SIGMA_EDITOR_EXIT='7'), status=1)
assert not Path(json.loads(log.read_text())['path']).exists()
run('editor-missing', include + 'EDIT EDIT-NATIVE BYE', b'HOST FUNCTION UNAVAILABLE !\r\n', env=dict(env, EDITOR=' '), status=1)
run('editor-save', include + 'SAVE editor.sigma SAVESYS editor.exe BYE', b'')
run('editor-load', 'LOAD-DICTIONARY editor.sigma EDIT EDIT-NATIVE BYE', b'', env=env)
run('editor-saved-system', 'EDIT EDIT-NATIVE BYE', b'', env=env, binary=str(root / 'editor.exe'))
# Escapes must remain input bytes when stdin is redirected, without history,
# interactive editing or echo. Test both a pipe and an actual redirected file.
input_bytes = b'\x1b[A\x1b[D\x1b[H\x1b[F\x1b[3~\xc3\xa9\r\n'
expected = b''.join(str(byte).encode() + b' ' for byte in input_bytes)
input_source = f': READ-BYTES {len(input_bytes)} 0 DO KEY . LOOP ; READ-BYTES BYE'
run('redirected-pipe-no-editor', input_source, expected, input_bytes)
redirected = root / 'redirected-input.bin'
redirected.write_bytes(input_bytes)
with redirected.open('rb') as stdin:
    r = subprocess.run([sigma, '-e', input_source], stdin=stdin, capture_output=True, timeout=20)
assert (r.returncode, r.stdout) == (0, expected), (r.returncode, r.stdout, r.stderr)
passed.append('redirected-file-no-editor')
report = {'platform': sys.platform, 'passed': passed,
          'excluded': ['interactive console keys/resize/Ctrl+C', 'terminal SHOW rendering', 'Gforth comparison', 'Linux/macOS']}
(root / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, indent=2))
