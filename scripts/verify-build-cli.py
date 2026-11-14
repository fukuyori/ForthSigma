#!/usr/bin/env python3
"""Run the build.zig CLI contracts in the executable's actual OS environment."""
import argparse
import json
import os
from pathlib import Path
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--sigma', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
sigma = str(a.sigma.resolve(strict=True))
newline = b'\r\n' if os.name == 'nt' else b'\n'
cases = [
    ('pipe-bytes', ['-e', ': T PAD 9 STDIN READ-FILE . DUP . 0 DO PAD I + C@ . LOOP ; T BYE'], b'A\r\nB\x1aC\x00\xff', b'0 8 65 13 10 66 26 67 0 255 ', 0),
    ('pipe-lines', ['-e', 'PAD 20 STDIN READ-LINE . . PAD SWAP TYPE PAD 20 STDIN READ-LINE . . PAD SWAP TYPE BYE'], b'ab\r\ncd\n', b'0 -1 ab0 -1 cd', 0),
    ('argument-file', ['src/tests/argument_file.fs', '-e', '. BYE'], b'', b'ARG-FILE5 ', 0),
    ('argument-stack', ['-e', '7', '--evaluate', '. BYE'], b'', b'7 ', 0),
    ('argument-missing', ['-e'], b'', b'-e: OPTION REQUIRES AN ARGUMENT !' + newline, 1),
    ('xkey-accept', ['-e', 'XKEY . PAD 10 ACCEPT PAD SWAP TYPE SPACE KEY . BYE'], b'\xe6A\nrest\n', b'65533 A 114 ', 0),
    ('xkey-read-line', ['-e', 'XKEY . PAD 10 STDIN READ-LINE . . PAD SWAP TYPE BYE'], b'\xe6Ab\ncd\n', b'65533 0 -1 Ab', 0),
    ('xkey-inkey', ['-e', 'REQUIRE-GRAPHICS ALSO GRAPHICS XKEY . INKEY . INKEY . BYE'], b'\xe6AB', b'65533 65 -1 ', 0),
    ('argument-no-file', ['sigma-no-such-file.fs', '-e', 'BYE'], b'', None, 1),
]
results = []
for name, args, data, expected, status in cases:
    r = subprocess.run([sigma, *args], input=data, capture_output=True, timeout=20)
    assert r.returncode == status and (expected is None or r.stdout == expected), (name, r.returncode, r.stdout, r.stderr, expected)
    results.append({'case': name, 'exit': r.returncode, 'stdout_hex': r.stdout.hex()})
report = {'complete': True, 'platform': os.name, 'cases': results}
if os.name == 'posix':
    import resource
    report['stack_limit_bytes'] = resource.getrlimit(resource.RLIMIT_STACK)
a.output.parent.mkdir(parents=True, exist_ok=True)
a.output.write_text(json.dumps(report, indent=2) + '\n')
print(f'{len(results)} build CLI cases passed')
