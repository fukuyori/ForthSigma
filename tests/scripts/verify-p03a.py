#!/usr/bin/env python3
"""P03a width, alignment, endian and sign matrices; optional local Gforth."""
import argparse,csv,json,pathlib,subprocess,re
parser=argparse.ArgumentParser()
parser.add_argument("sigma",nargs="?",default="zig-out/bin/sigma")
parser.add_argument("--gforth-build",type=pathlib.Path)
parser.add_argument("--report",type=pathlib.Path)
args=parser.parse_args()
names=[r["name"] for r in csv.DictReader(open("docs/gforth-p00-spec-cases.tsv"),delimiter="\t") if r["unit"]=="P03a"]
cases=[]
for row in csv.DictReader(open("docs/gforth-p00-runtime-cases.tsv"),delimiter="\t"):
    if row["word"] in names and row["case_id"].startswith("P03:"):
        source=re.sub(r"\bB\b",f"P03BUF{len(cases)}",row["input"])
        source=re.sub(r"\bV\b",f"P03VAR{len(cases)}",source)
        cases.append((row["case_id"],source,row["expected"].split()[:-1]))
recorded=len(cases)
MASK=(1<<64)-1
def cell(value):
    value &= MASK
    return value if value<1<<63 else value-(1<<64)
def add(name,operands,expected,outputs=1):
    k=len(cases); printing=' '.join(['.']*outputs)
    out=[str(cell(v)) for v in reversed(expected)]
    cases.append((f"boundary:{name}:{k}",f"{operands} {name} {printing}",out))
    cases.append((f"compiled:{name}:{k}",f": P03A{k} {name} ; {operands} P03A{k} {printing}",out))
values=[0,1,127,128,255,256,32767,32768,65535,65536,(1<<31)-1,1<<31,(1<<32)-1,1<<32,(1<<63)-1,1<<63,MASK]
for value in values:
    for n,w in [('C>S',8),('W>S',16),('L>S',32),('X>S',64)]:
        bits=value&((1<<w)-1); signed=bits if bits<1<<(w-1) else bits-(1<<w)
        add(n,str(cell(value)),[signed])
    add('XD>S',str(cell(value)),[value,-1 if value>=1<<63 else 0],2)
    for n,w in [('WBE',16),('LBE',32),('XBE',64)]:
        swapped=int.from_bytes((value&((1<<w)-1)).to_bytes(w//8,'little'),'big')
        add(n,str(cell(value)),[swapped])
    for n in ['WLE','LLE','XLE']:add(n,str(cell(value)),[value])
    swapped=int.from_bytes(value.to_bytes(8,'little'),'big')
    add('XDBE',f'{cell(value)} 0',[swapped,0],2)
    add('XDLE',f'{cell(value)} 0',[value,0],2)
    for n,size in [('CELL/',8),('FLOAT/',8),('DFLOAT/',8),('SFLOAT/',4)]:add(n,str(cell(value)),[cell(value)//size])
    add('CHAR-',str(cell(value)),[value-1])
    for alignment in [1,2,4,8,16,64,256,1<<63]:
        add('*ALIGNED',f'{cell(value)} {cell(alignment)}',[(value+alignment-1)&-alignment])
    for n,a in [('WALIGNED',2),('LALIGNED',4),('XALIGNED',8),('MAXALIGNED',8)]:add(n,str(cell(value)),[(value+a-1)&-a])
for value in values:
    for width,fetch,store in [(2,'W@','W!'),(4,'L@','L!'),(8,'X@','X!'),(8,'XD@','XD!')]:
        for offset in [0,1,3,7]:
            k=len(cases);buf=f'MEM{k}';mask=(1<<(width*8))-1
            operands=f'{cell(value)} 99' if width==8 and fetch=='XD@' else str(cell(value))
            source=f'CREATE {buf} 32 ALLOT {buf} 32 170 FILL {operands} {buf} {offset} + {store} {buf} {offset} + {fetch} '
            expected=[str(cell(value&mask))]
            if fetch=='XD@':source+='SWAP . . ';expected+=['0']
            else:source+='. '
            source+=f'{buf} {offset+width} + C@ .'
            cases.append((f'memory:{fetch}:{k}',source,expected+['170']))
for a in [-1,0,1,(1<<63)-1]:
    for index in [-2,-1,0,1,2]:add('TH',f'{a} {index}',[a+index*8])
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
