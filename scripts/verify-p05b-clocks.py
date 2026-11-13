#!/usr/bin/env python3
"""Check common clock contracts; live timestamps/counters are not equal-value oracles."""
import argparse, pathlib, subprocess, time, json, os
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True);a=p.parse_args()
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path('zig-out/bin/sigma').resolve()),'--max-steps','30000000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
source={
 'units':'NTIME D. CPUTIME D. D. DEPTH . BYE',
 'sleep':'2VARIABLE U0 2VARIABLE S0 CPUTIME S0 2! U0 2! 100 MS CPUTIME S0 2@ D- D. U0 2@ D- D. DEPTH . BYE',
 'busy':': BUSY 0 1000000 0 DO I + LOOP DROP ; 2VARIABLE U0 2VARIABLE S0 CPUTIME S0 2! U0 2! BUSY CPUTIME S0 2@ D- D. U0 2@ D- D. DEPTH . BYE',
 'child':'''2VARIABLE U0 2VARIABLE S0 CPUTIME S0 2! U0 2! S" python3 -c 'sum(i*i for i in range(5000000))'" SYSTEM $? . CPUTIME S0 2@ D- D. U0 2@ D- D. DEPTH . BYE'''
}
results=[]
for case,code in source.items():
 for runtime,cmd in commands.items():
  wall_before=time.time_ns();start=time.monotonic_ns()
  r=subprocess.run(cmd+[code],input='',capture_output=True,text=True,timeout=30)
  elapsed=time.monotonic_ns()-start;wall_after=time.time_ns()
  assert r.returncode==0,(case,runtime,r.returncode,r.stdout,r.stderr)
  values=list(map(int,r.stdout.split()));assert values[-1]==0,(case,runtime,values)
  if case=='units':
   stamp,system,user,_=values
   assert wall_before-5_000_000<=stamp<=wall_after+5_000_000,(runtime,stamp,wall_before,wall_after)
   assert system>=0 and user>=0
   assert system+user<elapsed//1000*max(1,os.cpu_count() or 1)+500_000,(runtime,values,elapsed)
  else:
   if case=='child':
    status=values.pop(0);assert status==0,(runtime,status,r.stderr)
   system,user,_=values;assert system>=0 and user>=0,(case,runtime,values)
   if case=='sleep':assert system+user<80_000,(case,runtime,values)
   if case=='busy':assert system+user>0,(case,runtime,values)
   if case=='child':assert system+user<elapsed//1000*0.8,(case,runtime,values,elapsed)
  results.append({'case':case,'runtime':runtime,'values':values,'elapsed_ns':elapsed})
report={'words':2,'common_contract_cases':len(source),'runtime_checks':len(results),'exact_value_comparison':False,'results':results,'pass':True}
root=pathlib.Path('.work/p05b-clocks-check');root.mkdir(parents=True,exist_ok=True);(root/'comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'words':2,'common_contract_cases':len(source),'runtime_checks':len(results),'pass':True}))
