#!/usr/bin/env python3
"""Probe local XIM server discovery/transport, encoding and preedit-capable IC.

Uses only Python's standard library and the sibling X11 wire probe. This does
not claim physical IME acceptance or COMMIT/preedit correctness.
"""
import json
import os
import struct
import time
from linux_x11_probe import Connection, pad


def main():
    conn = Connection(os.environ.get('DISPLAY', ''))
    window = None
    try:
        servers = conn.atom(b'XIM_SERVERS')
        header, data = conn.reply(conn.request(20, body=struct.pack('<IIIII', conn.root, servers, 4, 0, 1024)))
        if header[1] != 32:
            raise RuntimeError('No XIM_SERVERS property')
        candidates = []
        modifier = os.environ.get('XMODIFIERS', '').removeprefix('@im=')
        for i in range(0, len(data), 4):
            atom = struct.unpack_from('<I', data, i)[0]
            h, n = conn.reply(conn.request(17, body=struct.pack('<I', atom)))
            name = n[:struct.unpack_from('<H', h, 8)[0]].decode('ascii')
            h, _ = conn.reply(conn.request(23, body=struct.pack('<I', atom)))
            owner = struct.unpack_from('<I', h, 8)[0]
            if owner:
                candidates.append((name == '@server=' + modifier, name, owner))
        if not candidates:
            raise RuntimeError('No live XIM selection owner')
        _, server_name, owner = sorted(candidates, reverse=True)[0]
        window = conn.resource()
        conn.request(1, conn.depth, struct.pack('<IIhhHHHHII', window, conn.root, 0, 0, 1, 1, 0, 1, conn.visual, 0))
        xconnect, protocol = conn.atom(b'_XIM_XCONNECT'), conn.atom(b'_XIM_PROTOCOL')
        more = conn.atom(b'_XIM_MOREDATA')
        prop = conn.atom(b'_client_sigma_probe')

        def cm(target, atom, fmt, payload):
            event = struct.pack('<BBHII', 33, fmt, 0, target, atom) + payload.ljust(20, b'\0')
            conn.request(25, body=struct.pack('<II', target, 0) + event)

        cm(owner, xconnect, 32, struct.pack('<5I', window, 0, 0, 0, 0))
        event = conn.wait_event(33, window)
        if struct.unpack_from('<I', event, 8)[0] != xconnect or event[1] != 32:
            raise RuntimeError('Unexpected XIM transport handshake')
        peer, major, minor, boundary = struct.unpack_from('<4I', event, 12)
        if major != 0:
            raise RuntimeError(f'Probe supports only XIM transport major 0, got {major}.{minor}')

        def send(opcode, body=b''):
            conn.deadline = time.monotonic() + 5
            packet = struct.pack('<BBH', opcode, 0, len(pad(body)) // 4) + pad(body)
            if len(packet) <= 20:
                cm(peer, protocol, 8, packet)
            elif minor in (1, 2) and (minor == 1 or len(packet) < boundary):
                for start in range(0, len(packet), 20):
                    cm(peer, more if start + 20 < len(packet) else protocol, 8, packet[start:start + 20])
            else:
                conn.request(18, 2, struct.pack('<IIIB3xI', peer, prop, 31, 8, len(packet)) + packet)
                cm(peer, protocol, 32, struct.pack('<II', len(packet), prop))

        notices = []
        def receive(expected):
            buffered = bytearray()
            while True:
                event = conn.wait_event(33, window)
                atom = struct.unpack_from('<I', event, 8)[0]
                if atom not in (protocol, more):
                    raise RuntimeError('Unexpected XIM event atom')
                if event[1] == 8:
                    buffered.extend(event[12:32])
                    if atom == more:
                        if len(buffered) > 1024 * 1024:
                            raise ValueError('XIM packet exceeds probe bound')
                        continue
                elif event[1] == 32:
                    length, atom = struct.unpack_from('<II', event, 12)
                    if length > 1024 * 1024:
                        raise ValueError('XIM property exceeds probe bound')
                    h, b = conn.reply(conn.request(20, 1, struct.pack('<IIIII', window, atom, 31, 0, (length + 3) // 4)))
                    if h[1] != 8 or struct.unpack_from('<I', h, 12)[0] != 0:
                        raise ValueError('Invalid XIM property reply')
                    buffered.extend(b[:length])
                else:
                    raise RuntimeError('Unexpected XIM event format')
                if len(buffered) < 4:
                    raise ValueError('Short XIM packet')
                opcode, _, units = struct.unpack_from('<BBH', buffered)
                length = units * 4
                if len(buffered) < 4 + length:
                    raise ValueError('Truncated XIM packet')
                body = bytes(buffered[4:4 + length]);buffered.clear()
                if opcode == 20:
                    raise RuntimeError('XIM server returned ERROR')
                if expected is None:
                    return opcode, body
                if opcode == expected:
                    return body
                notices.append(opcode)
                if len(notices) > 128:
                    raise ValueError('Too many XIM notices')

        send(1, struct.pack('<BBHHH', 108, 0, 0, 0, 0))
        connect_reply = receive(2)
        locale = b'ja_JP.UTF-8'
        send(30, bytes([len(locale)]) + locale)
        opened = receive(31)
        imid, im_length = struct.unpack_from('<HH', opened)
        ic_length = struct.unpack_from('<H', opened, 4 + im_length)[0]
        attrs = {}
        offset, end = 8 + im_length, 8 + im_length + ic_length
        while offset < end:
            aid, kind, length = struct.unpack_from('<HHH', opened, offset)
            name = opened[offset + 6:offset + 6 + length].decode('ascii')
            attrs[name] = (aid, kind)
            offset += 4 + (2 + length + 3) // 4 * 4
        names = [b'UTF8_STRING', b'COMPOUND_TEXT']
        encoding = b''.join(bytes([len(n)]) + n for n in names)
        send(38, struct.pack('<HH', imid, len(encoding)) + pad(encoding) + bytes(4))
        enc = receive(39)
        _, category, index = struct.unpack_from('<HHh', enc)
        encoding_name = names[index].decode() if category == 0 and 0 <= index < len(names) else 'fallback'
        def attribute(name, value):
            aid, _ = attrs[name]
            return struct.pack('<HH', aid, len(value)) + pad(value)
        style = 0x0002 | 0x0400  # XIMPreeditCallbacks | XIMStatusNothing
        values = attribute('inputStyle', struct.pack('<I', style)) + attribute('clientWindow', struct.pack('<I', window)) + attribute('focusWindow', struct.pack('<I', window))
        send(50, struct.pack('<HH', imid, len(values)) + values)
        created = receive(51)
        got_imid, icid = struct.unpack_from('<HH', created)
        if got_imid != imid or icid == 0:
            raise ValueError('Invalid IC response')
        send(58, struct.pack('<HH', imid, icid))
        # Synthetic forward/COMMIT round trip in this private IC. The desktop's
        # selected input method determines whether this is ASCII or preedit text.
        keymap_header, keymap_data = conn.reply(conn.request(101, body=bytes([8, 248, 0, 0])))
        columns = keymap_header[1]
        committed, preedits = [], []
        for symbol in (ord('a'), 0xff0d):
            code = next(i + 8 for i in range(248) if struct.unpack_from('<I', keymap_data, i * columns * 4)[0] == symbol)
            for kind in (2, 3):
                event = struct.pack('<BBHIIIIhhhhHBB', kind, code, 0, 0, conn.root, window, 0, 0, 0, 0, 0, 0, 1, 0)
                send(60, struct.pack('<4H', imid, icid, 3, 0) + event)
                for _ in range(64):
                    opcode, body = receive(None)
                    if opcode == 62:
                        break
                    if opcode == 37:
                        continue
                    if opcode == 73:
                        send(74, struct.pack('<HHi', imid, icid, 1024))
                    elif opcode == 75:
                        flags, length = struct.unpack_from('<IH', body, 16)
                        if not flags & 1:
                            preedits.append(body[22:22 + length].decode('utf-8'))
                    elif opcode == 76:
                        send(77, body[:8])
                    elif opcode == 63:
                        flags = struct.unpack_from('<H', body, 4)[0]
                        if flags & 2:
                            offset = 12 if flags & 6 == 6 else 6
                            length = struct.unpack_from('<H', body, offset)[0]
                            committed.append(body[offset + 2:offset + 2 + length].decode('utf-8'))
                        if flags & 1:
                            send(62, struct.pack('<HH', imid, icid));break
                    elif opcode == 60:
                        if struct.unpack_from('<H', body, 4)[0] & 1:
                            send(62, struct.pack('<HH', imid, icid));break
                    elif opcode == 61:
                        send(62, struct.pack('<HH', imid, icid))
                else:
                    raise RuntimeError('XIM forward exchange did not terminate')
        send(59, struct.pack('<HH', imid, icid))
        send(52, struct.pack('<HH', imid, icid));receive(53)
        send(32, struct.pack('<HH', imid, 0));receive(33)
        send(3);receive(4)
        print(json.dumps(dict(server=server_name, transport=[major, minor], protocol=list(struct.unpack('<HH', connect_reply)), encoding=encoding_name, preedit_callback_ic='created/destroyed', notices=notices, synthetic_commit=committed, synthetic_preedit=preedits, physical_ime='not tested'), indent=2))
    finally:
        conn.sock.close()


if __name__ == '__main__':
    main()
