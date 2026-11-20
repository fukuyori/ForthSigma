"""Generate the declared ideal16-level3dB AY table, not measured hardware data."""
from decimal import Decimal, localcontext, ROUND_FLOOR
from pathlib import Path
import argparse
with localcontext() as ctx:
    ctx.prec = 70
    values = [0] + [int((Decimal(32767) * Decimal(10) ** (Decimal(3) * (i - 15) / 20)).to_integral_value(rounding=ROUND_FLOOR)) for i in range(1, 16)]
text = '\\ Original ideal3dB AY model levels, not measured chip DAC data.\nCREATE ZX-LEVELS\n'
text += '\n'.join(' '.join(str(v) + ' ,' for v in values[i:i + 8]) for i in range(0, 16, 8)) + '\n'
p = argparse.ArgumentParser(); p.add_argument('--check', action='store_true'); args = p.parse_args()
target = Path(__file__).resolve().parents[1] / 'include/zx-ay-levels.fs'
if args.check:
    if target.read_text(encoding='utf-8') != text: raise SystemExit('AY level table is stale')
else: target.write_text(text, encoding='utf-8', newline='\n')
print('16 ideal AY levels reproduced')
