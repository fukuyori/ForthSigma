#!/usr/bin/env python3
"""Check that every register model in include/ has the common words (tque 1187; Apple II 1179).

Each model must define <P>-RESET ( -- ), <P>-WRITE ( value target tick -- ),
<P>-EVENT! ( value target tick -- ), <P>-READ ( target tick -- value ),
<P>-RUN ( clocks -- ) and <P>-RENDER ( addr frames -- ).  READ is compared
with the model's own specific read words, and EVENT! with WRITE.
"""
import argparse, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORDS = ['RESET', 'WRITE', 'EVENT!', 'READ', 'RUN', 'RENDER']
SELECT, DATA = 16746496, 16746498  # YM2149 Atari ST byte bus
MODELS = {
    'NA': ('include/nes-apu.fs', [
        ('1 16405 0 NA-WRITE 8 16387 0 NA-WRITE 16405 10 NA-READ . 10 NA-STATUS .', ['1', '1']),
        (': T 16384 10 NA-READ ; \' T CATCH .', ['-21']),
        (': T 16404 10 NA-READ ; \' T CATCH .', ['-24']),
        (': T 16405 -1 NA-READ ; \' T CATCH .', ['-24']),
        ('1 16405 0 NA-WRITE 8 16387 5 NA-EVENT! 16405 4 NA-READ . 16405 5 NA-READ .', ['0', '1'])]),
    'SI': ('include/sid.fs', [('54299 0 SI-READ .', ['0'])]),
    'PA': ('include/paula.fs', [('2 0 PA-READ .', ['0'])]),
    'YM': ('include/ym2149.fs', [
        ('7 18 0 YM-WRITE 33 19 0 YM-WRITE 7 1 YM-READ . 18 1 YM-READ . 16 19 1 YM-WRITE 7 1 YM-READ . 18 1 YM-READ .', ['33', '33', '16', '16']),
        (f'0 18 1 YM-EVENT! 9 19 2 YM-EVENT! YM-CYCLE @ . 0 1 YM-READ . 3 YM-TO 0 3 YM-READ . {SELECT} 3 YM-BUS@ .', ['0', '0', '9', '9']),
        ('5 16 0 YM-WRITE 0 17 0 YM-WRITE 14 1 YM-READ . 15 1 YM-READ .', ['5', '0'])]),
    'C8': ('include/chip8-audio.fs', [
        ('3 0 0 C8-WRITE 70 1 0 C8-WRITE 1 2 0 C8-WRITE 0 0 C8-READ . 1 0 C8-READ . 2 0 C8-READ . 0 C8-TIMER@ .', ['3', '70', '1', '3']),
        ('5 0 10 C8-EVENT! C8-CYCLE @ . 0 9 C8-READ . 0 10 C8-READ .', ['0', '0', '5']),
        (': T 3 0 C8-READ ; \' T CATCH .', ['-21']),
        (': T 4 0 C8-READ ; \' T CATCH .', ['-24'])]),
    'ZX': ('include/zx-spectrum-audio.fs', [
        ('1 ZX-MODEL! ZX-RESET 11 8 0 ZX-AY! 8 0 ZX-READ . 8 65533 0 ZX-OUT 65533 16 + 0 ZX-READ . 65533 0 ZX-IN .', ['11', '11', '11']),
        ('1 ZX-MODEL! ZX-RESET 7 8 10 ZX-EVENT! ZX-CYCLE @ . 8 9 ZX-READ . 8 10 ZX-READ .', ['0', '0', '7']),
        ('0 ZX-MODEL! ZX-RESET ZX-MODEL @ . ZX-CPU @ . 1 ZX-MODEL! ZX-RESET ZX-MODEL @ . ZX-CPU @ .', ['0', '3500000', '1', '3546895']),
        (': T 2 ZX-MODEL! ; \' T CATCH . ZX-MODEL @ .', ['-24', '0']),
        ('1 ZX-MODEL! ZX-RESET : T 15 0 ZX-READ ; \' T CATCH .', ['-21']),
        ('0 ZX-MODEL! ZX-RESET : T 8 0 ZX-READ ; \' T CATCH .', ['-21']),
        (': T 65552 0 ZX-READ ; \' T CATCH .', ['-24']),
        ('1 ZX-MODEL! ZX-RESET 10 ZX-RUN : T 15 9 ZX-READ ; \' T CATCH .', ['-24']),
        ('0 ZX-MODEL! ZX-RESET 1 ZX-MODEL! ZX-MODEL @ . ZX-CPU @ . : T 11 8 0 ZX-WRITE ; \' T CATCH . ZX-RESET ZX-MODEL @ . ZX-CPU @ .', ['0', '3500000', '-21', '1', '3546895'])]),
    'SD': ('include/snes-dsp-audio.fs', [
        ('99 12 0 SD-WRITE 77 128 4660 + 0 SD-WRITE 12 1 SD-READ . 12 1 SD-REG@ . 4660 128 + 1 SD-READ . 4660 1 SD-RAM@ .', ['99', '99', '77', '77']),
        ('42 200 5 SD-EVENT! SD-CYCLE @ . 200 4 SD-READ . 200 5 SD-READ .', ['0', '0', '42']),
        (': T 65664 0 SD-READ ; \' T CATCH .', ['-24'])]),
    'A2': ('include/apple2-audio.fs', [
        ('4 A2-CARD! A2-RESET 11 8 0 0 A2-AY! 65544 0 A2-READ . 8 0 0 A2-AY@ . 255 50179 0 A2-WRITE 50179 0 A2-READ .', ['11', '11', '255']),
        ('0 A2-CARD! A2-RESET 0 49200 10 A2-EVENT! 9 A2-TO A2-SPEAKER @ . 10 A2-TO A2-SPEAKER @ . 49200 10 A2-READ . A2-SPEAKER @ .', ['0', '1', '0', '0']),
        ('0 A2-CARD! A2-RESET 4 A2-CARD! A2-SLOT @ . : T 1 65536 0 A2-WRITE ; \' T CATCH . A2-RESET A2-SLOT @ .', ['0', '-21', '4']),
        (': T 8 A2-CARD! ; \' T CATCH . A2-SLOT @ .', ['-24', '0']),
        ('0 A2-CARD! A2-RESET : T 65536 0 A2-READ ; \' T CATCH .', ['-21']),
        ('4 A2-CARD! A2-RESET : T 50180 0 A2-READ ; \' T CATCH .', ['-21']),
        (': T 65568 0 A2-READ ; \' T CATCH .', ['-24']),
        ('10 A2-RUN : T 49200 9 A2-READ ; \' T CATCH .', ['-24'])]),
}

def run(binary, source, code):
    q = subprocess.run([str(binary)], cwd=ROOT, input=(f'S" {source}" REQUIRED\n' + code + ' DEPTH . BYE\n').encode(),
                       capture_output=True, timeout=60)
    out = q.stdout.decode(errors='replace').split()
    start = out.index('OK') + 1 if 'OK' in out else 0
    return out[start:-1] if out and out[-1] == 'OK' else out[start:]

def main():
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('sigma', type=Path)
    binary = p.parse_args().sigma.resolve(); failures = 0; count = 0
    for prefix, (source, cases) in MODELS.items():
        found = run(binary, source, ' '.join(f"' {prefix}-{w} 0<> ." for w in WORDS))
        count += 1
        if found != ['-1'] * len(WORDS) + ['0']:
            failures += 1; print(f'FAIL {prefix} words: {found}')
        for code, expected in cases:
            got = run(binary, source, code); count += 1
            if got != expected + ['0']:
                failures += 1; print(f'FAIL {prefix}: {code}\n  expected {expected + ["0"]}\n  got      {got}')
    print(f'{count - failures}/{count} passed'); return 1 if failures else 0

if __name__ == '__main__':
    sys.exit(main())
