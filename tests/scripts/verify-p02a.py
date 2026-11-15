#!/usr/bin/env python3
"""P02a integer boundary matrix and recorded cases; optional local Gforth comparison."""
import argparse
import csv
import json
import pathlib
import subprocess
parser = argparse.ArgumentParser()
parser.add_argument("sigma", nargs="?", default="zig-out/bin/sigma")
parser.add_argument("--gforth-build", type=pathlib.Path)
parser.add_argument("--report", type=pathlib.Path)
args = parser.parse_args()
names = [r["name"] for r in csv.DictReader(open("docs/gforth-p00-spec-cases.tsv"), delimiter="\t") if r["unit"] == "P02a"]
cases = []
for r in csv.DictReader(open("docs/gforth-p00-runtime-cases.tsv"), delimiter="\t"):
    if r["word"] in names and r["case_id"].startswith("P02a:"):
        cases.append((r["case_id"], r["input"], r["expected"].split()))
recorded = len(cases)
MASK = (1 << 64) - 1
def cell(x):
    x &= MASK
    return x if x < 1 << 63 else x - (1 << 64)
def cells(x):
    return f"{cell(x)} {cell(x >> 64)}"
def add(name, operands, expected, outputs=1):
    k = len(cases)
    printing = " ".join(["."] * outputs)
    expected = [str(cell(x)) for x in reversed(expected)]
    cases.append((f"boundary:{name}:{k}", f"{operands} {name} {printing}", expected))
    cases.append((f"compiled:{name}:{k}", f": P02A{k} {name} ; {operands} P02A{k} {printing}", expected))
values = [0, 1, 2, 3, (1 << 63)-1, 1 << 63, MASK]
for a in values:
    for n in [0,1,15,16,17,31,32,33,63,64,65,127,128,129,-1]:
        for name,width,left in [("WROL",16,True),("WROR",16,False),("LROL",32,True),("LROR",32,False)]:
            # Gforth's out-of-range narrow rotation behavior is not its documented operation.
            # Only compare valid-width operands/counts here; Sigma-specific boundaries are checked separately.
            if a >= (1 << width) or not 0 <= n < width: continue
            mask=(1 << width)-1; x=a & mask; shift=n % width
            result=((x << shift) | (x >> ((-shift) % width))) if left else ((x >> shift) | (x << ((-shift) % width)))
            add(name, f"{cell(a)} {n}", [result & mask])
    add("CTZ", str(cell(a)), [64 if a==0 else (a & -a).bit_length()-1])
    add("LOG2", str(cell(a)), [a.bit_length()-1])
    add("POW2?",str(cell(a)),[-int(a!=0 and a & (a-1)==0)])
    add(">POW2",str(cell(a)),[0 if a==0 else 1 << (a-1).bit_length()])
for a in [0,1,(1<<64)-1,1<<64,(1<<127)-1,1<<127,(1<<128)-1]:
    for n in [0,1,63,64,65,127,128,129,255,-1]:
        shift=n%128; mask=(1<<128)-1
        for name,left in [("DROL",True),("DROR",False)]:
            result=(((a<<shift)|(a>>((-shift)%128))) if left else ((a>>shift)|(a<<((-shift)%128)))) & mask
            add(name,f"{cells(a)} {n}",[result,result>>64],2)
for a in [-(1<<63),-17,-1,0,1,17,(1<<63)-1]:
    for b in [-7,-1,1,3,(1<<63)-1]:
        if a==-(1<<63) and b==-1: continue
        for floor in [True,False]:
            q=a//b if floor else (abs(a)//abs(b))*(-1 if (a<0)!=(b<0) else 1)
            r=a-q*b; suffix="F" if floor else "S"
            for name,output in [("/"+suffix,[q]),("MOD"+suffix,[r]),("/MOD"+suffix,[r,q])]:
                add(name,f"{a} {b}",output,len(output))
        for factor in [-3,0,2]:
            for floor in [True,False]:
                p=a*factor; q=p//b if floor else (abs(p)//abs(b))*(-1 if (p<0)!=(b<0) else 1)
                if not -(1<<63)<=q<(1<<63):continue
                r=p-q*b; suffix="F" if floor else "S"
                add("*/"+suffix,f"{a} {factor} {b}",[q])
                add("*/MOD"+suffix,f"{a} {factor} {b}",[r,q],2)
for a in values:
    for b in [1,3,1<<63,MASK]:
        for name,out in [("U/",[a//b]),("UMOD",[a%b]),("U/MOD",[a%b,a//b])]:
            add(name,f"{cell(a)} {cell(b)}",out,len(out))
        for f in [0,1,3,MASK]:
            q,r=divmod(a*f,b)
            if q<=MASK:
                add("U*/",f"{cell(a)} {cell(f)} {cell(b)}",[q])
                add("U*/MOD",f"{cell(a)} {cell(f)} {cell(b)}",[r,q],2)
for a in [0,1,(1<<64)-1,1<<64,(1<<127)-1,1<<127,(1<<128)-1]:
    for b in [1,3,1<<63,MASK]:
        q,r=divmod(a,b)
        add("UD/MOD",f"{cells(a)} {cell(b)}",[r,q,q>>64],3)
        signed=a if a<(1<<127) else a-(1<<128)
        q,r=divmod(signed,b)
        if -(1<<63)<=q<(1<<63):add("DU/MOD",f"{cells(a)} {cell(b)}",[r,q],2)
for a in values:
    for b in values:
        for mask in [0,1,1<<63,MASK]:
            add("MUX",f"{cell(a)} {cell(b)} {cell(mask)}",[(a&mask)|(b&(~mask&MASK))])

# Compare shifts only inside their documented width. Out-of-width policy differs from Gforth.
for width in [64,128]:
    for signed in [-(1<<(width-1)),-8,-1,0,1,(1<<(width-1))-1]:
        for n in ([0,1,31,63] if width==64 else [1,31,63]):
            add("ARSHIFT" if width==64 else "DARSHIFT",f"{signed if width==64 else cells(signed)} {n}",
                [signed>>n] if width==64 else [signed>>n,(signed>>n)>>64],1 if width==64 else 2)
            if width==128:
                bits=signed&((1<<128)-1)
                for name,result in [("DLSHIFT",(bits<<n)&((1<<128)-1)),("DRSHIFT",bits>>n)]:
                    add(name,f"{cells(bits)} {n}",[result,result>>64],2)

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
# Confirm the explicitly selected Sigma policy outside Gforth's reliable domain.
shared_count = len(cases)
for a in values:
    for n in [16,17,32,33,64,65,128,-1]:
        for name,width,left in [("WROL",16,True),("WROR",16,False),("LROL",32,True),("LROR",32,False)]:
            mask=(1<<width)-1; x=a&mask; shift=n%width
            result=(((x<<shift)|(x>>((-shift)%width))) if left else ((x>>shift)|(x<<((-shift)%width))))&mask
            add(name,f"{cell(a)} {n}",[result])
for width in [64,128]:
    for a in [-8,0,8]:
        for n in ([width,width+1,256,-1] if width==64 else [0,64,65,127,128,129,256,-1]):
            op=f"{a if width==64 else cells(a)} {n}"
            result=(a >> min(n & MASK,width-1))
            add("ARSHIFT" if width==64 else "DARSHIFT",op,[result] if width==64 else [result,result>>64],1 if width==64 else 2)
            if width==128:
                bits=a&((1<<128)-1)
                left=(bits<<n)&((1<<128)-1) if 0<=n<128 else 0
                right=bits>>n if 0<=n<128 else 0
                add("DLSHIFT",op,[left,left>>64],2);add("DRSHIFT",op,[right,right>>64],2)
# Zero division consistently throws -10 in Sigma, unlike some Gforth primitives.
for name in ["/F","/S","/MODF","/MODS","MODF","MODS","*/F","*/S","*/MODF","*/MODS","U/","UMOD","U/MOD","U*/","U*/MOD","DU/MOD","UD/MOD"]:
    operands="1 2 0" if "*" in name else "1. 0" if name in ["DU/MOD","UD/MOD"] else "1 0"
    k=len(cases)
    cases.append((f"sigma-zero:{name}",f": P02ERR{k} {operands} {name} ; ' P02ERR{k} CATCH .",["-10"]))
for case in cases[shared_count:]:
    result=subprocess.run(commands["sigma"]+[case[1]+" DEPTH . BYE"],capture_output=True,text=True,timeout=10,input="")
    assert result.returncode==0 and result.stdout.split()==case[2]+["0"],(case,result.stdout,result.stderr)
report = {"words": len(names), "recorded_cases": recorded, "boundary_and_compiled_cases": len(cases) - recorded, "total_cases": len(cases), "gforth_shared_cases": shared_count, "sigma_policy_cases": len(cases)-shared_count, "batches": len(batches), "checked": list(commands), "pass": True}
if args.report:
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report))
