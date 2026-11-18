#!/usr/bin/env python3
"""Automatic display selection and loss/retry on an owned authenticated Xvfb.
Build -Dx11=true; SIGMA_TEST_BINARY and SIGMA_TEST_XVFB override executable paths.
Missing Xvfb/wish exits 77. Never connects to the user's display server.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import time
from linux_x11_test_support import OwnedXvfb, SigmaSession, binary_identity, require_linux

require_linux()
ROOT = Path(__file__).resolve().parents[2]
SIGMA = os.environ.get('SIGMA_TEST_BINARY', str(ROOT / 'zig-out/bin/sigma'))
UNAVAILABLE = 'sigma-invalid-display'


def select_mode(name, display, wayland, expected):
    source = ('REQUIRE-GRAPHICS ALSO GRAPHICS 2 2 GFX-INIT '
              'SHOW CR ." RESULT " GFX-AUTO-DISPLAY . CR BYE')
    started = time.monotonic()
    with SigmaSession(SIGMA, source, server.environment(DISPLAY=display, WAYLAND_DISPLAY=wayland)) as session:
        found = next_result(session)
        assert found == [expected], (name, found)
        session.finish()
    return {'case': name, 'mode': expected, 'seconds': round(time.monotonic() - started, 3)}


def next_result(session):
    until = time.monotonic() + 7
    while time.monotonic() < until:
        line = session.line(max(0, until - time.monotonic()))
        found = re.search(rb'RESULT (-?\d+) (\d+)', line)
        if found:
            return [int(value) for value in found.groups()]
        found = re.fullmatch(rb'RESULT (\d+)\s*', line)
        if found:
            return [int(found[1])]
    raise TimeoutError('Sigma result')


with OwnedXvfb() as server:
    identity = binary_identity(SIGMA)
    version = server.wish_version()
    matrix = [
        select_mode('native_available', f':{server.number}', '', 2),
        select_mode('native_unsupported_tk_available', f'unix/:{server.number}', '', 3),
        select_mode('headless', '', '', 1),
        select_mode('wayland_hint_without_x11', '', 'sigma-test-no-wayland', 1),
        select_mode('malformed_display', UNAVAILABLE, '', 1),
    ]
    source = ('REQUIRE-GRAPHICS ALSO GRAPHICS 2 2 GFX-INIT DISPLAY-WINDOW '
              ': T [\'] SHOW CATCH CR ." RESULT " . CR ; T BYE')
    with SigmaSession(SIGMA, source, server.environment(DISPLAY=UNAVAILABLE)) as session:
        line = session.line()
        while b'RESULT ' not in line:
            line = session.line()
        assert line.strip() == b'RESULT -265', line
        session.finish()

    source = ('REQUIRE-GRAPHICS ALSO GRAPHICS 2 2 GFX-INIT '
              ': RUN BEGIN [\'] SHOW CATCH CR ." RESULT " . GFX-AUTO-DISPLAY . CR '
              'KEY DUP [CHAR] a = IF DISPLAY-AUTO THEN [CHAR] q = UNTIL ; RUN BYE')
    with SigmaSession(SIGMA, source, server.environment()) as session:
        sequence = [next_result(session)]
        assert sequence[-1] == [0, 2], sequence
        server.stop()
        # SHOW may return from its ready mailbox before the owner observes EOF.
        # Poll the public behaviour instead of sleeping for an assumed interval.
        observations = []
        until = time.monotonic() + 5
        while True:
            session.send()
            value = next_result(session)
            observations.append(value)
            if value == [-265, 3]:
                sequence.append(value)
                break
            assert value == [0, 2] and time.monotonic() < until, observations
            time.sleep(.01)
        # States 3/1 after an error are pending candidates for the NEXT SHOW,
        # not assertions that Tk or the terminal already displayed this frame.
        for expected in ([-265, 1], [0, 1]):
            session.send()
            sequence.append(next_result(session))
            assert sequence[-1] == expected, sequence
        server.start()
        session.send(b'a')
        sequence.append(next_result(session))
        assert sequence[-1] == [0, 2], sequence
        session.send(b'q')
        session.finish()
    assert binary_identity(SIGMA) == identity, 'binary changed during test'
    print(json.dumps({'binary': identity, 'wish_version': version, 'authenticated_xvfb': True,
                      'selection_matrix': matrix, 'explicit_unavailable_error': -265,
                      'native_loss_observations': observations,
                      'selected_backend_loss_and_retry': sequence,
                      'scope': 'owned Xvfb; Wayland is only an environment hint, not a real connection'}, indent=2))
