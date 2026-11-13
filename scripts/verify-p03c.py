#!/usr/bin/env python3
"""Compare buffer/owned-memory runtime behavior with the designated Gforth build."""
import argparse, json, pathlib, subprocess
p=argparse.ArgumentParser()
p.add_argument('sigma', nargs='?', default='zig-out/bin/sigma')
p.add_argument('--gforth-build', type=pathlib.Path, required=True)
p.add_argument('--report', type=pathlib.Path)
a=p.parse_args()
cases=[('layout','BUFFER% . .',['24','8']),('init','CREATE B 24 ALLOT B INIT-BUFFER B @ B CELL+ @ OR B 2 CELLS + @ OR .',['0']),('free','2VARIABLE V 8 ALLOCATE THROW 8 V 2! V FREE-MEM-VAR V 2@ OR .',['0']),('null-free','2VARIABLE V 0 7 V 2! V FREE-MEM-VAR V 2@ . .',['7','0'])]
for n in [0,1,3,7,8,9,31,64]:
    cases.append((f'copy-{n}',f'CREATE S {max(n,1)} ALLOT S {n} 65 FILL S {n} SAVE-MEM OVER >R S {n} COMPARE . R> FREE THROW',['0']))
    for extra in [0,1,7,16]:
        cases.append((f'extend-{n}-{extra}',f'{n} ALLOCATE THROW DUP {n} 65 FILL {n} {extra} EXTEND-MEM DUP {n+extra} = . DROP OVER OVER {n} + = . NIP FREE THROW',['-1','-1']))
for first in [0,1,8,31]:
    for second in [0,1,8,64]:
        cases.append((f'adjust-{first}-{second}',f'CREATE B 24 ALLOT B INIT-BUFFER {first} B ADJUST-BUFFER {second} B ADJUST-BUFFER B @ {second} = . B 2 CELLS + @ {max(first,second)} = . B FREE-MEM-VAR',['-1','-1']))
build=a.gforth_build.resolve()
commands={'sigma':[str(pathlib.Path(a.sigma).resolve()),'--max-steps','100000','-e'], 'gforth':[str(build/'gforth-ditc'),'-p',str(build)+':~+','-i',str(build/'gforth.fi'),'-e']}
for name,source,expected in cases:
    for runtime,command in commands.items():
        r=subprocess.run(command+[source+' DEPTH . BYE'],text=True,capture_output=True,input='',timeout=15)
        assert r.returncode==0 and r.stdout.split()==expected+['0'],(name,runtime,r.returncode,r.stdout,r.stderr)
report={'words':6,'cases':len(cases),'checked':list(commands),'pass':True}
if a.report:
    a.report.parent.mkdir(parents=True,exist_ok=True)
    a.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
