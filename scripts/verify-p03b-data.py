#!/usr/bin/env python3
"""P03b raw-placement subset; typed address relocation remains a separate stage."""
import argparse,csv,json,pathlib,subprocess,re
parser=argparse.ArgumentParser()
parser.add_argument("sigma",nargs="?",default="zig-out/bin/sigma")
parser.add_argument("--gforth-build",type=pathlib.Path)
parser.add_argument("--report",type=pathlib.Path)
args=parser.parse_args()
names=['->HERE','2FIELD:','L,','LFIELD:','MAXALIGN','MEM,','SAVE-MEM-DICT','W,','WFIELD:','X,','XD,','XFIELD:']
cases=[]
for row in csv.DictReader(open('docs/gforth-p00-runtime-cases.tsv'),delimiter='\t'):
    if row['word'] not in names or row['case_id'].startswith('Boundary:'):continue
    source=re.sub(r'\bF\b',f"P03BF{len(cases)}",row['input'])
    extra=2 if row['stdin']=='LF*1000' else 1
    cases.append((row['case_id'],source,row['expected'].split()[:-extra]))
recorded=len(cases)
def cell(v):
    v&=(1<<64)-1
    return v if v<1<<63 else v-(1<<64)
for value in [0,1,255,256,65535,65536,(1<<31)-1,1<<31,(1<<32)-1,1<<32,(1<<63)-1,1<<63,(1<<64)-1]:
    for name,fetch,width in [('W,','W@',2),('L,','L@',4),('X,','X@',8),('XD,','XD@',8)]:
        for offset in [0,1,3,7]:
            k=len(cases);definition=f': P03BC{k} {name} ; '
            operand=f'{cell(value)} 123' if name=='XD,' else str(cell(value))
            source=f'{definition}{offset} ALLOT HERE {operand} P03BC{k} {fetch} '
            if name=='XD,':source+='D>S '
            source+='. '
            expected=cell(value&((1<<(width*8))-1))
            cases.append((f'comma:{k}',source,[str(expected)]))
for offset in [0,1,2,3,7,8,9,15,16,17,63,64]:
    for name,size,alignment in [('WFIELD:',2,2),('LFIELD:',4,4),('XFIELD:',8,8),('2FIELD:',16,8)]:
        k=len(cases);aligned=(offset+alignment-1)&-alignment
        source=f'{offset} {name} BF{k} . 100 BF{k} .'
        cases.append((f'field:{k}',source,[str(aligned+size),str(100+aligned)]))
for count in [0,1,2,3,7,8,15,16]:
    for word in ['MEM,','SAVE-MEM-DICT']:
        k=len(cases);buf=f'CP{k}'
        source=f'CREATE {buf} 32 ALLOT {buf} 32 65 FILL '
        if word=='MEM,':source+=f'HERE {buf} {count} MEM, {count} '
        else:source+=f'{buf} {count} SAVE-MEM-DICT '
        source+=f'{buf} {count} COMPARE .'
        cases.append((f'copy:{k}',source,['0']))
# Restore HERE only within a newly created raw buffer; do not reclaim named definitions.
for shift in [0,1,3,7]:
    k=len(cases);buf=f'OV{k}'
    source=f'CREATE {buf} 64 ALLOT {buf} 64 65 FILL {buf} {shift} + ->HERE {buf} 16 MEM, {buf} 16 + {shift} + HERE = .'
    cases.append((f'overlap:{k}',source,['-1']))
commands = {"sigma": [str(pathlib.Path(args.sigma).resolve()), "--max-steps", "100000", "-e"]}
if args.gforth_build:
    build = args.gforth_build.resolve()
    commands["gforth"] = [str(build / "gforth-ditc"), "-p", str(build) + ":~+", "-i", str(build / "gforth.fi"), "-e"]
batches = []
batch = []
size = 0
for case in cases:
    if size + len(case[1]) > 2500 and batch:
        batches.append(batch)
        batch, size = [], 0
    batch.append(case)
    size += len(case[1]) + 1
if batch: batches.append(batch)
for batch in batches:
    program = " ".join(case[1] for case in batch) + " DEPTH . BYE"
    expected = [value for case in batch for value in case[2]] + ["0"]
    for name, command in commands.items():
        result = subprocess.run(command + [program], capture_output=True, text=True, timeout=15, input="")
        assert result.returncode == 0 and result.stdout.split() == expected, (name, [c[0] for c in batch], result.stdout, result.stderr)
report = {"words": len(names), "recorded_cases": recorded, "boundary_and_compiled_cases": len(cases) - recorded, "total_cases": len(cases), "batches": len(batches), "checked": list(commands), "pass": True}
if args.report:
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report))
