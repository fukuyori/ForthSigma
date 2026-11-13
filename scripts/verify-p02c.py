#!/usr/bin/env python3
"""P02c conversion/output fixtures and range/reproducibility tests; optional local Gforth."""
import argparse,csv,json,pathlib,subprocess,math,struct
parser=argparse.ArgumentParser()
parser.add_argument('sigma',nargs='?',default='zig-out/bin/sigma')
parser.add_argument('--gforth-build',type=pathlib.Path)
parser.add_argument('--report',type=pathlib.Path)
args=parser.parse_args()
names=[r['name'] for r in csv.DictReader(open('docs/gforth-p00-spec-cases.tsv'),delimiter='\t') if r['unit']=='P02c']
commands={'sigma':[str(pathlib.Path(args.sigma).resolve()),'--max-steps','100000','-e']}
if args.gforth_build:
    b=args.gforth_build.resolve()
    commands['gforth']=[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']
cases=[]
for r in csv.DictReader(open('docs/gforth-p00-runtime-cases.tsv'),delimiter='\t'):
    if r['word'] in names and r['case_id'].startswith('P02bc:') and '>STRING-EXECUTE' not in r['input']:
        expected=r['expected'].split()
        if r['stdin']=='LF*1000':expected=expected[:-2]
        cases.append((r['input'],expected))
recorded=len(cases)
def add(source,out):cases.append((source,[str(v) for v in out]))
for seed in [0,1,-1,-(1<<63)]:
    add(f'{seed} SEED! RND RND {seed} SEED! RND ROT = . RND = .',[-1,-1])
    for bound in [0,1,2,100,(1<<63)-1]:
        add(f'{seed} SEED! {bound} RANDOM '+('0= .' if bound==0 else f'DUP 0>= SWAP {bound} < AND .'),[-1])
for text,sep,expected in [('1,5',44,1.5),(' -1.25 ',46,None),('',46,0),('   ',44,0),('1E2',46,100),('1.5',44,None),('bad',46,None),('1E5',69,1.5),('1-5',45,1.5),('125',50,1.5),('1 5',32,1.5)]:
    source=f'S" {text}" {sep} >FLOAT1 .'
    if expected is not None:source+=f' {expected}e F= .'
    add(source,[0] if expected is None else [-1,-1])
for text,number,places in [('123',123,-1),('1.25',125,2),('1.2.3',123,1),('-1.5',-15,1),('12.',12,0)]:
    add(f'S" {text}" S>NUMBER? . 2DROP DPL @ .',[-1,places])
for number in [0,1,12,-1,-(1<<63),(1<<63)-1]:
    add(f'{number} DEC. BASE @ .',[number,10])
    if number>=0:add(f'{number} 24 DEC.R SPACE BASE @ .',[number,10])
    add(f'{number} H. BASE @ .',[f'${number&((1<<64)-1):X}',10])
for lo,hi in [(0,0),(1,0),(-1,0),(0,1),(-1,-1),(0,-(1<<63))]:
    value=(lo&((1<<64)-1))+((hi&((1<<64)-1))<<64)
    add(f'{lo} {hi} UD. BASE @ .',[value,10])
    add(f'{lo} {hi} 45 UD.R SPACE BASE @ .',[value,10])
add(": IBASE BASE @ -99 THROW ; : OBASE ['] IBASE 2 BASE-EXECUTE ; : RBASE ['] OBASE 16 BASE-EXECUTE ; ' RBASE CATCH . BASE @ .",[-99,10])
add(": IBASE -99 THROW ; : CBASE ['] IBASE CATCH BASE @ ; ' CBASE 16 BASE-EXECUTE SWAP . . BASE @ .",[-99,16,10])

for source,out in cases:
    for name,cmd in commands.items():
        r=subprocess.run(cmd+[source+' DEPTH . BYE'],input='',text=True,capture_output=True,timeout=15)
        assert r.returncode==0 and r.stdout.split()==out+['0'],(name,source,out,r.stdout,r.stderr)
# The original four output probes require deferred >STRING-EXECUTE. Capture host output instead.
float_cases=0
for word in ['E.','E.EXACT','E.P','FP.']:
    for value in ['0e','-0e','1e','-1.25e','0.1e','1e30','1e-30']:
        source=f'{value} '+('17 ' if word=='E.P' else '')+word+' BYE'
        for name,cmd in commands.items():
            r=subprocess.run(cmd+[source],input='',text=True,capture_output=True,timeout=15)
            assert r.returncode==0,(name,source,r.stderr)
            text=r.stdout.strip()
            if word=='FP.':
                scales={p:10.0**(-30+i*3) for i,p in enumerate('qryzafpnum kMGTPEZYRQ')}
                last=text[-1:]
                if last in scales and last!=' ':parsed=float(text[:-1])*scales[last]
                else:parsed=float(text)
            else:
                if text.endswith('e'):text+='0'
                parsed=float(text)
            expected=float(value+'0' if value.endswith('e') else value)
            assert parsed==expected and (parsed!=0 or math.copysign(1,parsed)==math.copysign(1,expected)),(name,source,text,parsed,expected)
        float_cases+=1
# Check precision/layout spelling, including rounding across an exponent boundary.
layout_cases=0
for value,digits,expected in [('999.9e',3,'1e3'),('1000e',3,'1000e'),('1234e',3,'1234e'),('0.00001e',3,'.00001e'),('0.000001e',3,'1e-6'),('0e',3,'0e')]:
    for name,cmd in commands.items():
        r=subprocess.run(cmd+[f"{value} {digits} E.P BYE"],input='',text=True,capture_output=True,timeout=15)
        assert r.returncode==0 and r.stdout==expected,(name,value,digits,r.stdout,r.stderr)
    layout_cases+=1
# DEC.R follows the documented unsigned contract, selected by the user.
policy_cases=0
for value in [-1,-(1<<63)]:
    source=f"{value} 24 DEC.R SPACE BASE @ . DEPTH . BYE"
    r=subprocess.run(commands['sigma']+[source],input='',text=True,capture_output=True,timeout=15)
    assert r.returncode==0 and r.stdout.split()==[str(value&((1<<64)-1)),'10','0'],(source,r.stdout,r.stderr)
    policy_cases+=1
report={'sigma_policy_cases':policy_cases,'words':len(names),'recorded_cases':recorded,'conversion_and_boundary_cases':len(cases)-recorded,'output_capture_cases':float_cases,'precision_layout_cases':layout_cases,'total_cases':len(cases)+float_cases+policy_cases+layout_cases,'checked':list(commands),'pass':True}
if args.report:
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
