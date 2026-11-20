"""Generate original integer Q32 bit steps from the XO-CHIP pitch formula."""
import argparse
from decimal import Decimal, localcontext, ROUND_FLOOR
from pathlib import Path

with localcontext() as ctx:
    ctx.prec = 80
    values = [int((Decimal(4000) * Decimal(2) ** (Decimal(p - 64) / 48)
                   * (1 << 32) / 48000000).to_integral_value(rounding=ROUND_FLOOR)) for p in range(256)]
content = '\\ Original XO-CHIP Q32 bit steps per declared48MHz tick; generated from formula.\nCREATE C8-PITCHES\n'
content += '\n'.join(' '.join(str(v) + ' ,' for v in values[i:i + 8]) for i in range(0, 256, 8)) + '\n'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
path = Path(__file__).resolve().parents[1] / 'include/chip8-pitches.fs'
if args.check:
    if path.read_text(encoding='utf-8') != content:
        raise SystemExit('Pitch table is stale')
else:
    path.write_text(content, encoding='utf-8', newline='\n')
print('256 pitch steps reproduced; default=' + str(values[64]))
