#!/usr/bin/env python3
"""Compare native and Tk palette/dither rendering on an owned authenticated Xvfb.
Build with -Dx11=true; set SIGMA_TEST_BINARY and optionally SIGMA_TEST_XVFB.
Missing Xvfb/wish exits 77. This test creates windows and changes their geometry.
It does not change the keymap, compositor scale, or the user's display settings.
"""
import json
import os
from pathlib import Path
import hashlib
import struct
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'experiments'))
from linux_x11_probe import Connection
from linux_x11_test_support import OwnedXvfb, SigmaSession, binary_identity, require_linux

require_linux()

SIGMA = os.environ.get('SIGMA_TEST_BINARY', str(ROOT / 'zig-out/bin/sigma'))
connection = None
mask = 0
ansi = {0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd,
        0x00cdcd, 0xe5e5e5, 0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00,
        0x5c5cff, 0xff00ff, 0x00ffff, 0xffffff}
levels = (0, 95, 135, 175, 215, 255)
xterm = {r << 16 | g << 8 | b for r in levels for g in levels for b in levels}
xterm.update(v << 16 | v << 8 | v for v in range(8, 239, 10))
pixels = []
for y in range(8):
    for x in range(12):
        pixels.append((0, 0xffffff, 0xff0000, 0x00ff00)[x] if x < 4 else
                      ((x * 23 + y * 19) % 256 << 16 |
                       (x * 11 + y * 29) % 256 << 8 | (x * 37 + y * 7) % 256))


def children(window):
    _, data = connection.reply(connection.request(15, body=struct.pack('<I', window)))
    return struct.unpack('<' + 'I' * (len(data) // 4), data)


def property_bytes(window, atom):
    header, data = connection.reply(connection.request(20, body=struct.pack('<IIIII', window, atom, 31, 0, 256)))
    return data[:struct.unpack_from('<I', header, 16)[0]]


def matching_windows(native, deadline=None):
    connection.deadline = time.monotonic() + 5 if deadline is None else deadline
    todo = list(children(connection.root))
    matches = []
    while todo:
        window = todo.pop()
        try:
            if property_bytes(window, 39) == b'FORTH/Sigma graphics':
                is_native = property_bytes(window, 67).startswith(b'sigma\0Sigma\0')
                if is_native == native:
                    matches.append(window)
            todo.extend(children(window))
        except RuntimeError as error:
            if 'error code=3 ' not in str(error):
                raise  # A previous Tk window may disappear after QueryTree.
    return matches


def read_pixels(window, width, height):
    _, data = connection.reply(connection.request(73, 2, struct.pack('<IhhHHI', window, 0, 0, width, height, 0xffffffff)))
    bits, padding = connection.formats[connection.depth]
    stride = ((width * bits + padding - 1) // padding) * padding // 8
    order = 'little' if connection.byte_order == 0 else 'big'
    return [int.from_bytes(data[y * stride + x * bits // 8:y * stride + (x + 1) * bits // 8], order) & mask
            for y in range(height) for x in range(width)]


def settled_pixels(window, width, height):
    previous = None
    until = time.monotonic() + 5
    # Both backends scale by an integer in these two geometries. The white
    # source pixel at (1,0) stays white in every tested palette/dither mode.
    zoom = min(width // 12, height // 8)
    left = (width - 12 * zoom) // 2
    white_index = zoom // 2 * width + left + zoom + zoom // 2
    while time.monotonic() < until:
        connection.deadline = time.monotonic() + 5
        current = read_pixels(window, width, height)
        if current == previous and current[white_index] == mask:
            return current
        previous = current
        time.sleep(.05)
    raise AssertionError('window pixels did not settle')


def snapshot(native, colors, dither):
    mode = 'DISPLAY-WINDOW' if native else 'DISPLAY-TK'
    setup = ' '.join(f'{i % 12} {i // 12} ${value:06X} GFX-PSET' for i, value in enumerate(pixels))
    source = (f'REQUIRE-GRAPHICS ALSO GRAPHICS 12 8 GFX-INIT {setup} '
              f'96 64 WINDOW-SIZE {colors} DISPLAY-COLORS {"TRUE" if dither else "FALSE"} DITHER {mode} '
              'SHOW ." READY" CR KEY DROP BYE')
    assert not matching_windows(native), 'previous matching window survived'
    with SigmaSession(SIGMA, source, server.environment()) as session:
        assert session.line().strip() == b'READY', (mode, session.errors())
        matches = matching_windows(native)
        assert len(matches) == 1, (mode, 'expected exactly one window', matches)
        window = matches[0]
        initial = settled_pixels(window, 96, 64)
        connection.request(12, body=struct.pack('<IH2xII', window, 12, 128, 80))
        connection.sync()
        resized = settled_pixels(window, 128, 80)
        session.send()
        session.finish()
        # Check normal Sigma cleanup before the session's emergency killpg.
        until = time.monotonic() + 5
        while matching_windows(native, deadline=until):
            if time.monotonic() >= until:
                raise AssertionError('window survived normal Sigma exit')
            time.sleep(.01)
    return initial, resized



def digest(image):
    return hashlib.sha256(b''.join(pixel.to_bytes(4, 'little') for pixel in image)).hexdigest()


with OwnedXvfb() as server:
    identity = binary_identity(SIGMA)
    version = server.wish_version()
    connection = Connection(os.environ['DISPLAY'])
    try:
        assert connection.depth == 24 and tuple(connection.visual_info[1:]) == (0xff0000, 0xff00, 0xff), 'RGB888 depth24 required'
        mask = connection.visual_info[1] | connection.visual_info[2] | connection.visual_info[3]
        results = []
        native_images = {}
        for colors in (0, 2, 16, 256):
            for dither in (False, True):
                reference = snapshot(False, colors, dither)
                native = snapshot(True, colors, dither)
                assert native == reference, ('native differs from Tk', colors, dither)
                initial, resized = native
                if colors:
                    allowed = {0, 0xffffff} if colors == 2 else ansi if colors == 16 else xterm
                    assert set(initial) <= allowed, (colors, 'color outside palette')
                    minimum = 2 if colors == 2 else 8 if colors == 16 else 17
                    assert len(set(initial)) >= minimum, (colors, 'palette collapsed')
                else:
                    expected = [pixels[(y // 8) * 12 + x // 8] for y in range(64) for x in range(96)]
                    assert initial == expected, 'full-color pixels differ from source'
                assert all(resized[y * 128 + x] == 0 for y in range(80) for x in (0, 1, 2, 3, 124, 125, 126, 127)), 'letterbox not black'
                native_images[colors, dither] = initial
                results.append({'colors': colors, 'dither': dither, 'native_matches_tk': True,
                                'initial_pixels': len(initial), 'resized_pixels': len(resized),
                                'initial_sha256': digest(initial), 'resized_sha256': digest(resized),
                                'unique_colors': len(set(initial)), 'black_letterbox': True})
        for colors in (2, 16, 256):
            assert native_images[colors, False] != native_images[colors, True], ('dither had no effect', colors)
        assert native_images[0, False] == native_images[0, True], 'dither changed full-color output'
        assert binary_identity(SIGMA) == identity, 'binary changed during test'
        print(json.dumps({'binary': identity, 'wish_version': version, 'server': 'owned authenticated Xvfb depth24',
                          'cases': results, 'scope': 'integer zoom 8x/10x and horizontal letterbox only; odd, shrink and physical scaling not accepted here'}, indent=2))
    finally:
        connection.sock.close()
