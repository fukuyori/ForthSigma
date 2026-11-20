#!/usr/bin/env python3
"""Reproduce numeric hardware lookup data; no audio and no external code."""
import argparse,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');args=p.parse_args()
v=json.loads((ROOT/'scripts/snes-gauss-data.json').read_text(encoding='utf-8'))['values']
if len(v)!=512 or any(type(x)!=int or not 0<=x<=1305 for x in v):raise SystemExit('Invalid Gauss dataset')
s='\\ Hardware numeric constants referenced from fullsnes; see scripts/snes-gauss-data.json.\nDECIMAL\nCREATE SD-GAUSS\n'
s+=''.join(' '.join(str(x)+' ,' for x in v[i:i+16])+'\n' for i in range(0,512,16))
outputs={ROOT/'include/snes-gauss.fs':s,
 ROOT/'src/core/snes_gauss.zig':'// Generated hardware numeric data; provenance: scripts/snes-gauss-data.json.\n'+'pub const values = [_]i64{\n'+''.join('    '+''.join(f'{x},'.ljust(6) for x in v[i:i+16]).rstrip()+'\n' for i in range(0,512,16))+'};\n'}
for f,text in outputs.items():
 if args.check:
  if f.read_text(encoding='utf-8')!=text:raise SystemExit(f'Gauss table differs: {f}')
 else:f.write_text(text,encoding='utf-8',newline='\n')
if args.check:print('512 Gaussian hardware constants reproduced in Forth and Zig')
