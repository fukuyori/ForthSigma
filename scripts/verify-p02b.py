#!/usr/bin/env python3
"""P02b basic and IEEE/strided-vector comparisons with optional local Gforth."""
import argparse,csv,json,pathlib,subprocess
parser=argparse.ArgumentParser()
parser.add_argument("sigma",nargs="?",default="zig-out/bin/sigma")
parser.add_argument("--gforth-build",type=pathlib.Path)
parser.add_argument("--report",type=pathlib.Path)
args=parser.parse_args()
names=[r["name"] for r in csv.DictReader(open("docs/gforth-p00-spec-cases.tsv"),delimiter="\t") if r["unit"]=="P02b"]
cases=[]
# P00 included LF probes for other deferred input words. Only use the isolated tested expression.
for r in csv.DictReader(open("docs/gforth-p00-runtime-cases.tsv"),delimiter="\t"):
    if r["word"] in names and r["case_id"].startswith("P02bc:"):
        expected=r["expected"].split()
        if r["stdin"]=="LF*1000":expected=expected[:-2]
        source=r["input"]
        if r["word"]=="FAXPY":
            import re
            source=re.sub(r"\bX\b","AX",source);source=re.sub(r"\bY\b","AY",source)
        cases.append((r["case_id"],source,expected))
recorded=len(cases)
def add(source,expected):cases.append((str(len(cases)),source,[str(v) for v in expected]))
for name in ["1/F","F2*","F2/"]:
    for value in ["0e","-0e","1e","-2e","INF","-INF"]:
        expected={"1/F": {"0e":"INF","-0e":"-INF","1e":"1e","-2e":"-0.5e","INF":"0e","-INF":"-0e"},"F2*":{"0e":"0e","-0e":"-0e","1e":"2e","-2e":"-4e","INF":"INF","-INF":"-INF"},"F2/":{"0e":"0e","-0e":"-0e","1e":"0.5e","-2e":"-1e","INF":"INF","-INF":"-INF"}}[name][value]
        for compiled in [False,True]:
            k=len(cases);call=f"P02B{k}" if compiled else name
            definition=f": {call} {name} ; " if compiled else ""
            add(f"{definition}{value} {call} {expected} 0e F~ .",[-1])
for name in ["F~ABS","F~REL"]:
    for a in [-2,0,1,2]:
        for b in [-2,0,1,2]:
            for tolerance in [-1,0,0.5,1,2]:
                bound=tolerance if name=="F~ABS" else tolerance*(abs(a)+abs(b))
                add(f"{a}e {b}e {tolerance}e {name} .",[-int(abs(a-b)<bound)])
for sign in ["0e","-0e","1e","-1e"]:
    target="-2e" if sign.startswith("-") else "2e"
    add(f"-2e {sign} FCOPYSIGN {target} 0e F~ .",[-1])
for count in [0,1,2,3]:
    k=len(cases)
    prefix=f"CREATE X{k} 1e F, 2e F, 3e F, CREATE Y{k} 4e F, 5e F, 6e F, "
    for sx,sy,offsetx,offsety in [(8,8,0,0),(-8,8,16,0),(0,8,0,0),(8,-8,0,16)]:
        xs=[1,2,3];ys=[4,5,6]
        expected=sum(xs[(offsetx+i*sx)//8]*ys[(offsety+i*sy)//8] for i in range(count))
        k=len(cases)
        prefix=f"CREATE X{k} 1e F, 2e F, 3e F, CREATE Y{k} 4e F, 5e F, 6e F, "
        add(prefix+f"X{k} {offsetx} + {sx} Y{k} {offsety} + {sy} {count} V* {expected}e F= .",[-1])
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
