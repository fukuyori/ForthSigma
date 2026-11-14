#!/usr/bin/env python3
"""Native POSIX shell/editor integration without an external reference runtime."""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--sigma', type=Path, required=True)
p.add_argument('--output', type=Path, default=Path('.work/posix-native/report.json'))
a = p.parse_args()
if os.name != 'posix':
    p.error('POSIX required')
sigma = str(a.sigma.resolve(strict=True))
root = a.output.parent.resolve()
root.mkdir(parents=True, exist_ok=True)
passed = []

def run(name, code, expected, env=None, status=0, binary=None):
    r = subprocess.run([binary or sigma, '--max-steps', '100000', '-e', code],
                       input=b'', capture_output=True, timeout=20, cwd=root, env=env)
    assert (r.returncode, r.stdout) == (status, expected), (name, r.returncode, r.stdout, r.stderr)
    passed.append(name)

run('shell-binary-status', ': BYTES BOUNDS ?DO I C@ . LOOP ; S" printf \'A\\000B\\n\'; exit 3" SH-GET BYTES $? . BYE', b'65 0 66 10 768 ')
run('shell-empty', 'S" true" SH-GET NIP . $? . BYE', b'0 0 ')
run('pipe-input-restoration', 'S" printf AB" R/O OPEN-PIPE THROW CONSTANT P : R KEY . KEY . ; \' R P INFILE-EXECUTE INFILE-ID STDIN = . P CLOSE-PIPE . . BYE', b'65 66 -1 0 0 ')
run('pipe-output', 'S" cat > written.txt" W/O OPEN-PIPE THROW CONSTANT P : R S" 日本語" TYPE ; \' R P OUTFILE-EXECUTE P CLOSE-PIPE . . BYE', b'0 0 ')
assert (root / 'written.txt').read_bytes() == '日本語'.encode()
source = root / "日本語 source'$(echo BAD).fs"
source.write_text(': EDIT-NATIVE 11 ;\n: EDIT-USE EDIT-NATIVE ;\n')
stub = root / 'record editor.py'
log = root / 'editor.json'
stub.write_text('import json,os,pathlib,stat,sys\np=pathlib.Path(sys.argv[-1]); pathlib.Path(os.environ["EDITOR_LOG"]).write_text(json.dumps({"line":sys.argv[-2],"path":str(p),"text":p.read_text(),"mode":stat.S_IMODE(p.stat().st_mode)})); sys.exit(int(os.environ.get("EDITOR_EXIT", "0")))\n')
# DrvFs without metadata does not preserve POSIX mode 0600. Use the Linux
# temporary filesystem when checking the permissions of inspection reports.
temporary = tempfile.TemporaryDirectory(prefix='sigma-verify-', dir='/tmp')
env = dict(os.environ, EDITOR=shlex.join([sys.executable, str(stub)]), EDITOR_LOG=str(log), TMPDIR=temporary.name)
include = f'S" {source}" INCLUDED '
run('editor-file', include + 'EDIT EDIT-NATIVE BYE', b'', env)
call = json.loads(log.read_text())
assert call['path'] == str(source) and call['line'] == '+1', call
run('editor-report', include + 'WHEREG EDIT-NATIVE BYE', b'', env)
call = json.loads(log.read_text())
assert 'EDIT-USE' in call['text'] and call['mode'] & 0o077 == 0 and not Path(call['path']).exists(), call
run('editor-failure-cleanup', include + 'WHEREG EDIT-NATIVE BYE', b'HOST FUNCTION ERROR !\n', dict(env, EDITOR_EXIT='7'), 1)
assert not Path(json.loads(log.read_text())['path']).exists()
run('editor-save', include + 'SAVE editor.sigma SAVESYS editor-program BYE', b'')
run('editor-load', 'LOAD-DICTIONARY editor.sigma EDIT EDIT-NATIVE BYE', b'', env)
run('editor-saved-system', 'EDIT EDIT-NATIVE BYE', b'', env, binary=str(root / 'editor-program'))
temporary.cleanup()
a.output.write_text(json.dumps({'platform': sys.platform, 'passed': passed}, indent=2) + '\n')
print(f'{len(passed)} POSIX native checks passed')
