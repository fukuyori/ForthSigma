#!/usr/bin/env python3
"""Render smoke/soft edges through Sigma and compare every pixel with independent source-over."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import zlib
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--sigma',type=Path,default=ROOT/'zig-out/bin/sigma.exe')
parser.add_argument('--output-dir',type=Path,default=ROOT/'.work/1037/alpha-visual')
args=parser.parse_args()
if not __debug__:
    raise SystemExit('Run without Python -O')
folder=args.output_dir.resolve(); folder.mkdir(parents=True,exist_ok=True)
def chunk(kind,data):
    return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
def png(w,h,pixels):
    raw=b''.join(b'\0'+bytes(v for p in pixels[y*w:(y+1)*w] for v in p) for y in range(h))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
size=128
smoke=[]; edge=[]
for y in range(size):
    for x in range(size):
        density=max(0, max(1-((x-cx)**2+(y-cy)**2)/(radius*radius) for cx,cy,radius in [(48,78,45),(72,64,36),(60,37,25)]))
        a=round(175*density)
        smoke.append((192,208,224,a) if a else (255,0,255,0))
        distance=math.hypot(x-63.5,y-63.5)
        a=round(255*max(0,min(1,(49-distance)/4)))
        edge.append((248,112,32,a) if a else (255,0,255,0))
for name,pixels in [('smoke',smoke),('edge',edge)]:
    (folder/(name+'.png')).write_bytes(png(size,size,pixels))
w,h=640,320
expected=[(48,48,48) if (x//16+y//16)%2 else (176,176,176) for y in range(h) for x in range(w)]
placements=[('smoke',24,120),('smoke',70,76),('smoke',120,24),('edge',356,40),('edge',444,132)]
for name,dx,dy in placements:
    pixels=smoke if name=='smoke' else edge
    for y in range(size):
        for x in range(size):
            *color,a=pixels[y*size+x]
            pos=(dy+y)*w+dx+x
            expected[pos]=tuple((c*a+d*(255-a)+127)//255 for c,d in zip(color,expected[pos]))
source='''REQUIRE-GRAPHICS ALSO GRAPHICS TRUE IMAGE-KEEP-ALPHA
640 320 GFX-INIT
: BACKDROP 320 0 DO 640 0 DO I 16 / J 16 / + 1 AND IF $303030 ELSE $B0B0B0 THEN I J ROT GFX-PSET LOOP LOOP ;
BACKDROP S" smoke.png" LOAD-IMAGE CONSTANT SMOKE S" edge.png" LOAD-IMAGE CONSTANT EDGE
MODE-SOURCE-OVER IMAGE-MODE
'''
for name,x,y in placements: source+=f'{name.upper()} {x} {y} PUT-IMAGE\n'
source+='S" result.ppm" SAVE-PPM S" result.png" SAVE-PNG DEPTH . BYE'
r=subprocess.run([str(args.sigma.resolve()),'-e',source],cwd=folder,capture_output=True,timeout=30)
assert r.returncode==0 and not r.stderr and r.stdout.split()==[b'0'],(r.stdout,r.stderr)
data=(folder/'result.ppm').read_bytes()
# Sigma emits P6 with one width/height line and no comments.
header,dimensions,maximum,rgb=data.split(b'\n',3)
assert (header,dimensions,maximum)==(b'P6',b'640 320',b'255'), data[:40]
reference=bytes(v for p in expected for v in p)
assert rgb==reference, sum(a!=b for a,b in zip(rgb,reference))
report=dict(status='pass',binary_sha256=hashlib.sha256(args.sigma.read_bytes()).hexdigest(),
            width=w,height=h,compared_rgb_bytes=len(reference),placements=placements,
            fixtures={name:hashlib.sha256((folder/(name+'.png')).read_bytes()).hexdigest() for name in ['smoke','edge']},
            output_png_sha256=hashlib.sha256((folder/'result.png').read_bytes()).hexdigest(),
            method='Independent per-channel straight-alpha source-over over an opaque checkerboard; zero-alpha RGB deliberately magenta')
(folder/'result.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('pass',len(reference),'RGB bytes')
