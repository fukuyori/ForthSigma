#!/usr/bin/env python3
"""Run the P00 reference cases from the repository root; writes the recorded TSV."""
import csv,subprocess,sys
from pathlib import Path
here=Path(__file__).resolve().parent
scripts=['basic','standard','integer','memory','float','string','compiler','dictionary','host','debug','failure','event','related','assignment']
for name in scripts:
 subprocess.run([sys.executable,str(here/('p00-'+name+'-cases.py'))],check=True)
rows=list(csv.DictReader(open('docs/gforth-p00-runtime-cases.tsv'),delimiter='\t'))
expected=list(csv.DictReader(open('docs/gforth-p00-spec-cases.tsv'),delimiter='\t'))
assert len(rows)==470,'Unexpected reference case count; update the documented count deliberately.'
assert all(r['pass']=='True' for r in rows),'Reference cases failed; inspect recorded actual values.'
covered={r['word'] for r in rows}
assert all(r['name'] in covered for r in expected),'Missing a per-word reference case.'
assert len({r['case_id'] for r in rows})==len(rows),'Duplicate case IDs.'
print(f'{len(rows)} reference cases passed; all {len(expected)} inventory names covered.')
