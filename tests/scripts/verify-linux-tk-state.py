#!/usr/bin/env python3
"""Owned Tk window state transitions on a Linux X11/XWayland desktop.
Synthetic ICCCM/EWMH close/minimize/restore requests; no physical button/IME claim.
"""
import argparse
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time
from linux_x11_test_support import SigmaSession, binary_identity, require_linux, stop_process_group

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'experiments'))
from linux_x11_probe import Connection
require_linux()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma')
parser.add_argument('--no-native', action='store_true')
args = parser.parse_args()
FIELDS = ('open focused minimized closes tcl native_open native_focused native_minimized native_closes held').split()


def tcl(script):
    assert '"' not in script
    return 'S" ' + script + '" TCL-EVAL 2DROP '


def snapshot(session, name):
    fields = session.line().split()
    assert fields[:2] == [b'STATE', name.encode()], fields
    values = list(map(int, fields[2:]))
    assert len(values) == len(FIELDS), values
    return dict(zip(FIELDS, values))


def window_id(session):
    line = session.line().split()
    assert line[0] == b'WINDOW', line
    window = int(line[1], 0)
    connection.deadline = time.monotonic() + 5
    protocols = connection.atom(b'WM_PROTOCOLS')
    delete = connection.atom(b'WM_DELETE_WINDOW')
    while window != connection.root:
        _, body = connection.reply(connection.request(20, body=struct.pack('<IIIII', window, protocols, 4, 0, 32)))
        if delete in struct.unpack('<' + 'I' * (len(body) // 4), body):
            return window
        header, _ = connection.reply(connection.request(15, body=struct.pack('<I', window)))
        window = struct.unpack_from('<I', header, 12)[0]
    raise AssertionError('Tk WM protocol window not found')


connection = Connection(os.environ['DISPLAY'])


def message(window, atom, value, direct=False):
    connection.deadline = time.monotonic() + 5
    event = struct.pack('<BBHII5I', 33, 32, 0, window, connection.atom(atom), value, 0, 0, 0, 0)
    target, mask = (window, 0) if direct else (connection.root, (1 << 19) | (1 << 20))
    connection.request(25, body=struct.pack('<II', target, mask) + event)
    connection.sync()
    time.sleep(.2)


rows = []
try:
    with tempfile.TemporaryDirectory(prefix='sigma-tk-state-') as directory:
        app = Path(directory) / 'tk-state-app'
        steps = [
            ('shown', '4 2 GFX-INIT 128 80 WINDOW-SIZE SHOW', None),
            ('focused', tcl('focus -force .sigma; update'), None),
            ('other-focus', tcl('toplevel .accept_other; entry .accept_other.e; pack .accept_other.e; update; focus -force .accept_other.e; update'), None),
            ('ime-focus', tcl('destroy .accept_other; sigma_ime 1 0 0 10; focus -force .sigma_ime; update'), None),
            ('held', tcl('event generate .sigma_ime <KeyPress> -keysym a -keycode 38; update'), None),
            ('minimized', '', 'minimize'),
            ('restored', '', 'restore'),
            ('closed', '', 'close'),
            ('reopened', 'SHOW', None),
            ('closed-again', '', 'close'),
            ('stopped', 'TCL-STOP', None),
            ('restart', 'SHOW', None),
            ('third-close', '', 'close'),
            ('full-event-queue', 'SHOW ' + tcl('for {set i 0} {$i < 80} {incr i} {sigma_event queued}; sigma_window_close_request'), None),
        ]
        steps += [('fullscreen', 'TRUE FULLSCREEN SHOW', None),
                  ('fullscreen-closed', '', 'close'),
                  ('fullscreen-reopened', 'SHOW', None),
                  ('normal', 'FALSE FULLSCREEN', None),
                  ('final-close', '', 'close')]
        if not args.no_native:
            steps += [('native-selected', 'DISPLAY-WINDOW SHOW 2000 WINDOW-PAINT-WAIT DROP', None),
                      ('tk-selected', 'DISPLAY-TK', None)]
        steps += [('saved', f"' ACCEPT-APP APP-ENTRY! SAVESYS {app}", None)]
        source = '''REQUIRE-GRAPHICS ALSO GRAPHICS DISPLAY-TK
: ACCEPT-REPORT WINDOW-OPEN? . WINDOW-FOCUSED? . WINDOW-MINIMIZED? . WINDOW-CLOSES .
GFX-TCL? . GFX-WINDOW-FLAGS >R >R >R . R> . R> . R> . [CHAR] a KEY-HELD? . ;
: ACCEPT-APP DISPLAY-TK ." STATE fresh " ACCEPT-REPORT CR ;
." STATE before " ACCEPT-REPORT CR
'''
        for name, action, _ in steps:
            source += f'KEY DROP {action} 300 MS ." STATE {name} " ACCEPT-REPORT CR\n'
            if name in ('shown', 'reopened', 'restart', 'fullscreen-reopened'):
                source += 'S" winfo id ." TCL-EVAL ." WINDOW " TYPE CR\n'
            if name in ('fullscreen', 'fullscreen-reopened', 'normal'):
                source += '." FULLSCREEN " FULLSCREEN? . CR\n'
        source += 'KEY DROP BYE'
        with SigmaSession(str(args.sigma.resolve()), source, os.environ.copy()) as session:
            before = snapshot(session, 'before')
            assert all(value == 0 for value in before.values()), before
            rows.append(dict(phase='before', state=before))
            window = None
            for name, _, operation in steps:
                if operation == 'minimize':
                    message(window, b'WM_CHANGE_STATE', 3)
                elif operation == 'restore':
                    message(window, b'_NET_ACTIVE_WINDOW', 2)
                elif operation == 'close':
                    message(window, b'WM_PROTOCOLS', connection.atom(b'WM_DELETE_WINDOW'), direct=True)
                session.send()
                state = snapshot(session, name)
                rows.append(dict(phase=name, state=state))
                if name in ('shown', 'reopened', 'restart', 'fullscreen-reopened'):
                    window = window_id(session)
                if name in ('shown', 'focused', 'ime-focus', 'held', 'restored', 'reopened', 'restart', 'fullscreen', 'fullscreen-reopened', 'normal'):
                    assert state['open'] == -1 and state['minimized'] == 0, (name, state)
                if name in ('focused', 'ime-focus'):
                    assert state['focused'] == -1, (name, state)
                if name == 'other-focus':
                    assert state['open'] == -1 and state['focused'] == 0, state
                if name == 'held':
                    assert state['held'] == -1, state
                if name == 'minimized':
                    assert state['open'] == state['minimized'] == -1 and state['focused'] == state['held'] == 0, state
                counts = {'closed': 1, 'reopened': 1, 'closed-again': 2, 'stopped': 2,
                          'restart': 2, 'third-close': 3, 'full-event-queue': 4, 'fullscreen': 4, 'fullscreen-closed': 5, 'fullscreen-reopened': 5, 'normal': 5, 'final-close': 6, 'tk-selected': 6, 'saved': 6}
                if name in counts:
                    assert state['closes'] == counts[name], (name, state)
                if name in ('closed', 'closed-again', 'third-close', 'full-event-queue', 'fullscreen-closed', 'final-close', 'tk-selected', 'saved', 'stopped'):
                    assert state['open'] == state['focused'] == state['minimized'] == state['held'] == 0, (name, state)
                if name in ('fullscreen', 'fullscreen-reopened', 'normal'):
                    flag = session.line().split()
                    assert flag == [b'FULLSCREEN', b'0' if name == 'normal' else b'-1'], flag
                if name == 'stopped':
                    assert state['tcl'] == 0, state
                if name == 'native-selected':
                    assert state['open'] == state['native_open'] == -1 and state['closes'] == state['native_closes'] == 0, state
            session.send()
            session.finish()
            assert not (session.buffer + session.process.stdout.read()).strip()
            assert not session.errors(), session.errors()
        process = subprocess.Popen([str(app)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        try:
            stdout, stderr = process.communicate(input=b'', timeout=15)
            assert process.returncode == 0 and not stderr, (stdout, stderr)
            fields = stdout.split()
            assert fields[:2] == [b'STATE', b'fresh'] and list(map(int, fields[2:])) == [0] * len(FIELDS), stdout
        finally:
            stop_process_group(process)
        print(json.dumps(dict(status='pass', binary=binary_identity(args.sigma), phases=rows,
                              saved_app=binary_identity(app), fresh_stdout=stdout.decode()), indent=2))
finally:
    connection.sock.close()
