#!/usr/bin/env python3
"""Check Tk's physical size and image rectangle on a Linux X11/XWayland desktop.
Uses only its own Sigma/wish windows. SIGMA_TEST_BINARY overrides the binary.
WINDOW-FIT intentionally leaves Tk's integer scaling unchanged.
"""
import json
import os
from pathlib import Path
import struct
import sys

from linux_x11_test_support import SigmaSession, binary_identity, require_linux

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'experiments'))
from linux_x11_probe import Connection

require_linux()
binary = os.environ.get('SIGMA_TEST_BINARY', str(ROOT / 'zig-out/bin/sigma'))
source = '''REQUIRE-GRAPHICS ALSO GRAPHICS 160 100 GFX-INIT DISPLAY-TK
: ACCEPT-RECT WINDOW-IMAGE-RECT . . . . ;
VARIABLE ACCEPT-ID
." BEFORE " WINDOW-PIXELS . . ACCEPT-RECT CR
640 400 WINDOW-SIZE SHOW 300 MS
'''
for width, height in [(640, 400), (503, 307), (91, 61)]:
    source += f'S" wm geometry . {width}x{height}; update" TCL-EVAL 2DROP 300 MS SHOW 300 MS\n'
    for mode in range(3):
        source += f'''{mode} WINDOW-FIT
." ID " S" winfo id ." TCL-EVAL TYPE CR
." SIZE " WINDOW-PIXELS . . CR
." RECT " ACCEPT-RECT CR
." TK " S" sigma_view_rect" TCL-EVAL TYPE CR
KEY DROP
'''
source += '''." INVALID " 0 GFX-WINDOW-PIXELS . . -1 GFX-WINDOW-PIXELS . . 4294967296 GFX-WINDOW-PIXELS . . 4294967295 GFX-WINDOW-PIXELS . . CR
(TK-WINDOW-ID) ACCEPT-ID ! ." CLOSING " ACCEPT-ID @ . CR
S" wm withdraw .; update" TCL-EVAL 2DROP 300 MS ." HIDDEN " ACCEPT-RECT CR
ACCEPT-ID @ S" destroy ." TCL-EVAL 2DROP GFX-WINDOW-PIXELS ." CLOSED " . . CR BYE'''
connection = Connection(os.environ['DISPLAY'])
results = []
try:
    with SigmaSession(binary, source, os.environ.copy()) as session:
        assert session.line().split() == [b'BEFORE'] + [b'0'] * 6
        for width, height in [(640, 400), (503, 307), (91, 61)]:
            for mode in range(3):
                tag, value = session.line().split()
                assert tag == b'ID'
                window = int(value, 0)
                size = list(reversed(list(map(int, session.line().split()[1:]))))
                rect = list(reversed(list(map(int, session.line().split()[1:]))))
                tk = list(map(int, session.line().split()[1:]))
                header, _ = connection.reply(connection.request(14, body=struct.pack('<I', window)))
                actual = list(struct.unpack_from('<HH', header, 16))
                assert size == actual == [width, height], (size, actual, width, height)
                expected = [tk[i] * size[i % 2] // tk[4 + i % 2] for i in range(4)]
                assert rect == expected and rect[2] > 0 and rect[3] > 0, (rect, tk, expected)
                results.append(dict(requested=[width, height], fit=mode, pixels=size, rect=rect, tk=tk))
                session.send()
        assert session.line().split() == [b'INVALID'] + [b'0'] * 8
        assert session.line().split() == [b'CLOSING', str(window).encode()]
        hidden = session.line().split()
        assert hidden == [b'HIDDEN'] + [b'0'] * 4, hidden
        assert session.line().split() == [b'CLOSED'] + [b'0'] * 2
        session.finish()
    for offset in range(0, 9, 3):
        assert results[offset]['rect'] == results[offset + 1]['rect'] == results[offset + 2]['rect']
    print(json.dumps(dict(binary=binary_identity(binary), cases=results, status='pass'), indent=2))
finally:
    connection.sock.close()
