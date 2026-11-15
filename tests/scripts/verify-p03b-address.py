#!/usr/bin/env python3
"""P03b address word runtime compatibility; typed image relocation is verified by the Zig regression suite."""
import argparse,csv,json,pathlib,subprocess,re
parser=argparse.ArgumentParser()
parser.add_argument("sigma",nargs="?",default="zig-out/bin/sigma")
parser.add_argument("--gforth-build",type=pathlib.Path)
parser.add_argument("--report",type=pathlib.Path)
args=parser.parse_args()
names=['A,','ACONSTANT','AVARIABLE'];cases=[]
for row in csv.DictReader(open('docs/gforth-p00-runtime-cases.tsv'),delimiter='\t'):
    if row['word'] in names and not row['case_id'].startswith('Boundary:'):
        source=re.sub(r'\bA\b(?!,)',f"AP03{len(cases)}",row['input'])
        extra=2 if row['stdin']=='LF*1000' else 1
        cases.append((row['case_id'],source,row['expected'].split()[:-extra]))
recorded=len(cases)
for offset in [0,1,7,8,15,31]:
    for compiled in [False,True]:
        k=len(cases);target=f'TG{k}';var=f'AV{k}';name=f'AP{k}';array=f'AR{k}'
        source=f'CREATE {target} 32 ALLOT '
        if compiled:source+=f': DEF{k} ACONSTANT ; : VAR{k} AVARIABLE ; {target} {offset} + DEF{k} {name} VAR{k} {var} '
        else:source+=f'{target} {offset} + ACONSTANT {name} AVARIABLE {var} '
        source+=f'{name} {var} ! CREATE {array} {name} A, {var} @ {name} = . {array} @ {name} = .'
        cases.append((f'runtime:{k}',source,['-1','-1']))
for op in ['MOVE','CMOVE','CMOVE>']:
    k=len(cases)
    source=f'CREATE TG{k} 32 ALLOT CREATE R{k} TG{k} A, TG{k} 1+ A, 0 , 0 , R{k} R{k} 16 + 16 {op} R{k} 16 + @ TG{k} = . R{k} 24 + @ TG{k} 1+ = .'
    cases.append((f'copy:{k}',source,['-1','-1']))
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
