#!/usr/bin/env python3
"""Independently decode RGBA saves, RGB compatibility, and alpha-preserving reloads."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import zlib
if not __debug__:
    raise SystemExit('Run without Python -O')
ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma', type=Path, default=ROOT / 'zig-out/bin/sigma.exe')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()

def decode(data):
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    at = 8; chunks = []; compressed = b''; header = None
    while at < len(data):
        length = struct.unpack_from('>I', data, at)[0]
        kind = data[at+4:at+8]; body = data[at+8:at+8+length]
        assert len(body) == length
        assert struct.unpack_from('>I', data, at+8+length)[0] == zlib.crc32(kind+body)
        chunks.append(kind)
        if kind == b'IHDR': header = struct.unpack('>IIBBBBB', body)
        if kind == b'IDAT': compressed += body
        at += length + 12
    assert at == len(data) and chunks == [b'IHDR', b'IDAT', b'IEND']
    width,height,depth,color,compression,filtering,interlace = header
    assert depth == 8 and color in (2,6) and compression == filtering == interlace == 0
    channels = 4 if color == 6 else 3
    decoder = zlib.decompressobj()
    raw = decoder.decompress(compressed) + decoder.flush()
    assert decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail
    assert len(raw) == height * (1 + channels * width)
    pixels = bytearray()
    for y in range(height):
        row = raw[y*(1+channels*width):(y+1)*(1+channels*width)]
        assert row[0] == 0
        pixels += row[1:]
    # Check actual stored-block boundaries independently of zlib's inflate.
    assert compressed[:2] == b'\x78\x01'
    pos = 2; blocks = 0
    while True:
        marker = compressed[pos]; size, inverse = struct.unpack_from('<HH', compressed, pos+1)
        assert marker in (0,1) and size ^ inverse == 65535
        pos += 5 + size; blocks += 1
        if marker == 1: break
    assert pos + 4 == len(compressed)
    return width,height,color,bytes(pixels),blocks

cases=[]
with tempfile.TemporaryDirectory(prefix='sigma-png-alpha-') as directory:
    folder = Path(directory)
    for width,height in [(1,1),(3,2),(64,255),(128,128),(16384,1)]:
        source=f'''REQUIRE-GRAPHICS ALSO GRAPHICS
{width} {height} GFX-INIT {width} {height} NEW-IMAGE CONSTANT IMG IMG DRAW-TO
: FILL-TEST {height} 0 DO {width} 0 DO
I 17 * 255 AND 16 LSHIFT J 29 * 255 AND 8 LSHIFT OR I J XOR 255 AND OR I J ROT GFX-PSET
I J I 37 * J 53 * + 255 AND GFX-ALPHA-PSET LOOP LOOP ;
FILL-TEST 0 0 1 1 CLIP! 2 DISPLAY-COLORS TRUE DITHER
S" alpha.png" SAVE-PNG-ALPHA S" primitive.png" GFX-SAVE-PNG-ALPHA THROW
S" rgb.png" SAVE-PNG
TRUE IMAGE-KEEP-ALPHA S" alpha.png" LOAD-IMAGE CONSTANT RELOADED
: VERIFY-RELOAD {height} 0 DO {width} 0 DO
RELOADED I J GFX-IMAGE-ALPHA@ I 37 * J 53 * + 255 AND <> IF -24 THROW THEN
RELOADED I J GFX-PIXEL IMG I J GFX-PIXEL <> IF -24 THROW THEN
LOOP LOOP ; VERIFY-RELOAD
SCREEN DRAW-TO S" screen.png" SAVE-PNG-ALPHA DEPTH . BYE'''
        result=subprocess.run([str(args.sigma.resolve()),'-e',source],cwd=folder,capture_output=True,timeout=35)
        assert result.returncode == 0 and not result.stderr and result.stdout.split() == [b'0'], (result.stdout,result.stderr)
        encoded=(folder/'alpha.png').read_bytes()
        assert encoded == (folder/'primitive.png').read_bytes()
        w,h,color,pixels,blocks=decode(encoded)
        expected=bytes(value for y in range(height) for x in range(width) for value in
                       [(x*17)&255,(y*29)&255,(x^y)&255,(x*37+y*53)&255])
        assert (w,h,color,pixels)==(width,height,6,expected)
        rw,rh,rc,rgb,_=decode((folder/'rgb.png').read_bytes())
        assert (rw,rh,rc,rgb)==(width,height,2,bytes(value for at,value in enumerate(expected) if at%4!=3))
        sw,sh,sc,screen,_=decode((folder/'screen.png').read_bytes())
        assert (sw,sh,sc)==(width,height,6) and screen==b'\0\0\0\xff'*(width*height)
        if width == 16384 or height == 128: assert blocks > 1
        if (width,height)==(64,255): assert blocks == 1
        cases.append(dict(width=width,height=height,rgba_bytes=len(encoded),stored_blocks=blocks,
                          pixel_sha256=hashlib.sha256(pixels).hexdigest(),
                          rgba_sha256=hashlib.sha256(encoded).hexdigest()))
report=dict(status='pass',binary=dict(path=str(args.sigma.resolve()),sha256=hashlib.sha256(args.sigma.read_bytes()).hexdigest()),
            cases=cases,checks=['chunk CRC','IHDR RGBA8','zlib Adler and stream boundary','stored blocks',
            'all RGBA pixels including zero-alpha RGB','public/primitive equality','RGB SAVE-PNG compatibility',
            'screen opaque','clip/display palette ignored','Sigma reload preserves RGB and alpha'])
args.output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('pass',len(cases),'dimensions')
