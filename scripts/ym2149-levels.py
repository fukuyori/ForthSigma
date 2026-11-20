from pathlib import Path
from decimal import Decimal,localcontext,ROUND_FLOOR
with localcontext() as c:
 c.prec=70
 values=[0]+[int((Decimal(32767)*Decimal(10)**(Decimal('-1.5')*(31-i)/20)).to_integral_value(rounding=ROUND_FLOOR)) for i in range(1,32)]
s='\\ Original ideal1.5dB YM2149 model levels; not measured chip DAC data.\nCREATE YM-LEVELS\n'+'\n'.join(' '.join(str(v)+' ,' for v in values[i:i+8]) for i in range(0,32,8))+'\n'
import argparse
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
target=Path(__file__).resolve().parents[1]/'examples/ym2149-levels.fs'
if args.check:assert target.read_text(encoding='utf-8')==s,'Level table is stale'
else:target.write_text(s,encoding='utf-8',newline='\n')
print('32 ideal levels reproduced.')
