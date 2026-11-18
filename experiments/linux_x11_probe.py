#!/usr/bin/env python3
"""X11 wire-protocol feasibility probe; no X11 Python package or shared library.

Only local DISPLAY=:N[.screen] and unix:N[.screen] are accepted. Authentication
comes from XAUTHORITY or ~/.Xauthority. Cookies are never printed. Each protocol
operation has a five-second deadline, including intervening events. This is a
probe, not Sigma's window backend. Run on the desktop with Python 3.
"""

import argparse
import json
import os
from pathlib import Path
import re
import socket
import struct
import time


def pad(data):
    return data + bytes(-len(data) % 4)


def auth(display):
    path = Path(os.environ.get("XAUTHORITY") or str(Path.home() / ".Xauthority"))
    try:
        data = path.read_bytes()
    except FileNotFoundError:
        return b"", b""
    pos = 0
    best = None
    while pos < len(data):
        if pos + 2 > len(data):
            raise ValueError("truncated Xauthority family")
        family = struct.unpack_from(">H", data, pos)[0]
        pos += 2
        fields = []
        for _ in range(4):
            if pos + 2 > len(data):
                raise ValueError("truncated Xauthority length")
            length = struct.unpack_from(">H", data, pos)[0]
            pos += 2
            if pos + length > len(data):
                raise ValueError("truncated Xauthority field")
            fields.append(data[pos:pos + length])
            pos += length
        address, number, name, cookie = fields
        if (family == 65535 or family == 256 and address == socket.gethostname().encode()) and number in (b"", str(display).encode()) and name == b"MIT-MAGIC-COOKIE-1":
            if best is None or family == 256 and not best[0]:
                best = (family == 256, name, cookie)
    return best[1:] if best else (b"", b"")


class Connection:
    def __init__(self, display):
        match = re.fullmatch(r"(?:unix)?:([0-9]+)(?:\.([0-9]+))?", display)
        if not match:
            raise ValueError("probe accepts only local :N[.screen] or unix:N[.screen]")
        number, screen = int(match[1]), int(match[2] or 0)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.set_inheritable(False)
        self.display = display
        self.sequence = 0
        self.events = []
        self.deadline = time.monotonic() + 5
        try:
            self.sock.settimeout(5)
            self.sock.connect(f"/tmp/.X11-unix/X{number}")
            name, cookie = auth(number)
            self.send(struct.pack("<BBHHHHH", 108, 0, 11, 0, len(name), len(cookie), 0) + pad(name) + pad(cookie))
            header = self.read(8)
            body = self.read(struct.unpack_from("<H", header, 6)[0] * 4)
            if header[0] != 1:
                # Do not print the server's untrusted reason or any auth bytes.
                raise RuntimeError("X11 setup rejected")
            if len(body) < 32:
                raise ValueError("short X11 setup")
            self.base, self.mask = struct.unpack_from("<II", body, 4)
            vendor, self.max_request = struct.unpack_from("<HH", body, 16)
            roots, formats, self.byte_order = body[20:23]
            offset = 32 + (vendor + 3) // 4 * 4
            self.formats = {}
            for _ in range(formats):
                depth, bits, alignment = struct.unpack_from("BBB", body, offset)
                self.formats[depth] = bits, alignment
                offset += 8
            if screen >= roots:
                raise ValueError("DISPLAY screen does not exist")
            for index in range(roots):
                root, cmap, white, black = struct.unpack_from("<IIII", body, offset)
                visual = struct.unpack_from("<I", body, offset + 32)[0]
                depth, depths = body[offset + 38:offset + 40]
                offset += 40
                for _ in range(depths):
                    count = struct.unpack_from("<H", body, offset + 2)[0]
                    offset += 8
                    for _ in range(count):
                        vid, klass, _, _, red, green, blue, _ = struct.unpack_from("<IBBHIIII", body, offset)
                        if index == screen and vid == visual:
                            self.visual_info = klass, red, green, blue
                        offset += 24
                if index == screen:
                    self.root, self.visual, self.depth = root, visual, depth
            self.next_id = 1
        except BaseException:
            self.sock.close()
            raise

    def read(self, count):
        result = bytearray()
        while len(result) < count:
            self.sock.settimeout(max(0.001, self.deadline - time.monotonic()))
            if time.monotonic() >= self.deadline:
                raise TimeoutError("X11 operation exceeded 5 seconds")
            data = self.sock.recv(count - len(result))
            if not data:
                raise ConnectionError("X11 server disconnected")
            result.extend(data)
        return bytes(result)

    def send(self, data):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("X11 operation exceeded 5 seconds")
        self.sock.settimeout(remaining)
        self.sock.sendall(data)

    def request(self, opcode, detail=0, body=b""):
        data = pad(body)
        length = 1 + len(data) // 4
        if length > self.max_request:
            raise ValueError("request exceeds negotiated server limit")
        self.sequence += 1
        self.send(struct.pack("<BBH", opcode, detail, length) + data)
        return self.sequence & 65535

    def reply(self, sequence):
        while True:
            header = self.read(32)
            kind = header[0] & 127
            if kind == 0:
                raise RuntimeError(f"X11 error code={header[1]} request={header[10]} sequence={struct.unpack_from('<H', header, 2)[0]}")
            if kind == 1:
                length = struct.unpack_from("<I", header, 4)[0] * 4
                if length > 16 * 1024 * 1024:
                    raise ValueError("oversized X11 reply")
                body = self.read(length)
                if struct.unpack_from("<H", header, 2)[0] != sequence:
                    raise ValueError("unexpected X11 reply sequence")
                return header, body
            if kind == 35:  # GenericEvent carries an extra length.
                length = struct.unpack_from("<I", header, 4)[0] * 4
                if length > 1024 * 1024:
                    raise ValueError("oversized X11 event")
                self.read(length)
            self.events.append(header)
            if len(self.events) > 4096:
                raise ValueError("probe event queue exceeded its bound")

    def sync(self):
        self.reply(self.request(43))  # GetInputFocus: server processed prior requests.

    def wait_event(self, kind, window):
        while True:
            for i, event in enumerate(self.events):
                if event[0] & 127 == kind and struct.unpack_from("<I", event, 4 if kind in (12, 33) else 8)[0] == window:
                    return self.events.pop(i)
            event = self.read(32)
            if event[0] & 127 == 0:
                raise RuntimeError(f"X11 error code={event[1]} request={event[10]} sequence={struct.unpack_from('<H', event, 2)[0]}")
            if event[0] & 127 in (1, 35):
                raise RuntimeError("unexpected protocol packet while waiting for event")
            self.events.append(event)
            if len(self.events) > 4096:
                raise ValueError("probe event queue exceeded its bound")

    def resource(self):
        n = self.next_id * (self.mask & -self.mask)
        self.next_id += 1
        if n & ~self.mask:
            raise ValueError("probe resource ID space exhausted")
        return self.base | n

    def atom(self, name):
        header, _ = self.reply(self.request(16, body=struct.pack("<H2x", len(name)) + name))
        return struct.unpack_from("<I", header, 8)[0]

    def run(self):
        bits, alignment = self.formats[self.depth]
        klass, red, green, blue = self.visual_info
        if klass != 4 or bits not in (16, 24, 32) or alignment not in (8, 16, 32):
            raise ValueError("probe requires a TrueColor visual and 16/24/32-bit pixels")
        colors = (red, green, blue, red | green | blue)
        width, height = 257, 129  # At 16bpp/pad32 this exercises scanline padding.
        order = "little" if self.byte_order == 0 else "big"
        stride = ((width * bits + alignment - 1) // alignment) * alignment // 8
        row = lambda y: b"".join(colors[(y >= height // 2) * 2 + (x >= width // 2)].to_bytes(bits // 8, order) for x in range(width)) + bytes(stride - width * (bits // 8))
        pixels = b"".join(row(y) for y in range(height))
        delete = self.atom(b"WM_DELETE_WINDOW")
        protocols = self.atom(b"WM_PROTOCOLS")
        for _ in range(2):
            self.deadline = time.monotonic() + 5
            window, gc = self.resource(), self.resource()
            # Background pixel and event mask: Expose + StructureNotify.
            self.request(1, self.depth, struct.pack("<IIhhHHHHII", window, self.root, 0, 0, width, height, 0, 1, self.visual, (1 << 1) | (1 << 11)) + struct.pack("<II", 0, (1 << 15) | (1 << 17)))
            self.request(18, body=struct.pack("<IIIB3xI", window, protocols, 4, 32, 1) + struct.pack("<I", delete))
            title = b"FORTH/Sigma X11 protocol probe"
            self.request(18, body=struct.pack("<IIIB3xI", window, 39, 31, 8, len(title)) + title)
            self.request(55, body=struct.pack("<III", gc, window, 0))
            self.request(8, body=struct.pack("<I", window))
            self.sync()
            self.wait_event(19, window)  # MapNotify, after the window manager maps it.
            # Use a pixmap for deterministic readback even when the window is
            # covered/unmapped by the compositor. Copy the same pixels to the window.
            pixmap = self.resource()
            self.request(53, self.depth, struct.pack("<IIHH", pixmap, window, width, height))
            # Artificially cap requests to the core minimum, even when the server
            # allows more, so this small probe actually exercises request splitting.
            lines = max(1, (min(self.max_request * 4, 16384) - 24) // stride)
            for y in range(0, height, lines):
                n = min(lines, height - y)
                self.request(72, 2, struct.pack("<IIHHhhBB2x", pixmap, gc, width, n, 0, y, 0, self.depth) + pixels[y * stride:(y + n) * stride])
            self.request(62, body=struct.pack("<IIIhhhhHH", pixmap, window, gc, 0, 0, 0, 0, width, height))
            header, actual = self.reply(self.request(73, 2, struct.pack("<IhhHHI", pixmap, 0, 0, width, height, 0xffffffff)))
            if header[1] != self.depth:
                raise AssertionError("readback depth differs")
            # Unused bits and scanline padding are not meaningful on readback.
            for y in range(height):
                for x in range(width):
                    offset = y * stride + x * (bits // 8)
                    value = int.from_bytes(actual[offset:offset + bits // 8], order)
                    if value & (red | green | blue) != colors[(y >= height // 2) * 2 + (x >= width // 2)]:
                        raise AssertionError(f"pixel mismatch at {x},{y}")
            # ClearArea with exposures=True forces an Expose. Redraw retained pixels.
            self.request(61, 1, struct.pack("<IhhHH", window, 0, 0, 0, 0))
            self.sync()
            self.wait_event(12, window)
            self.request(62, body=struct.pack("<IIIhhhhHH", pixmap, window, gc, 0, 0, 0, 0, width, height))
            self.events.clear()  # Old configure events must not satisfy the resize check.
            self.request(12, body=struct.pack("<IH2xII", window, (1 << 2) | (1 << 3), width + 13, height + 7))
            while True:
                event = self.wait_event(22, window)
                if struct.unpack_from("<HH", event, 20) == (width + 13, height + 7):
                    break
            # Synthetic WM_DELETE_WINDOW exercises the receive/dispatch path;
            # a physical close-button click remains a separate acceptance check.
            event = struct.pack("<BBHII5I", 33, 32, 0, window, protocols, delete, 0, 0, 0, 0)
            self.request(25, body=struct.pack("<II", window, 0) + event)
            event = self.wait_event(33, window)
            if struct.unpack_from("<II", event, 8) != (protocols, delete):
                raise AssertionError("WM_DELETE_WINDOW payload differs")
            self.request(54, body=struct.pack("<I", pixmap))
            self.request(60, body=struct.pack("<I", gc))
            self.request(4, body=struct.pack("<I", window))
            self.sync()
        return dict(display=self.display, session=os.environ.get("XDG_SESSION_TYPE"), depth=self.depth, bits_per_pixel=bits, scanline_pad=alignment, max_request_bytes=self.max_request * 4, put_image_requests_per_frame=(height + lines - 1) // lines, pixel_readback="pass", expose_redraw="pass", resize_notify="pass", synthetic_wm_delete="pass", destroy_recreate="pass")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--display", default=os.environ.get("DISPLAY", ""))
    args = parser.parse_args()
    connection = Connection(args.display)
    try:
        print(json.dumps(connection.run(), indent=2))
    finally:
        connection.sock.close()


if __name__ == "__main__":
    main()
