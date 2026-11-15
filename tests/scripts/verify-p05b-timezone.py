#!/usr/bin/env python3
"""Compare calendar/DST with Gforth; actual offset/name with Python zoneinfo."""
import argparse,pathlib,subprocess,json,os,datetime,zoneinfo
p=argparse.ArgumentParser();p.add_argument('--gforth-build',type=pathlib.Path,required=True);a=p.parse_args()
b=a.gforth_build.resolve();commands={'sigma':[str(pathlib.Path('zig-out/bin/sigma').resolve()),'--max-steps','100000','-e'],'gforth':[str(b/'gforth-ditc'),'-p',str(b)+':~+','-i',str(b/'gforth.fi'),'-e']}
seconds=[-2208988800,-1,0,946684800,951782400,1704067200,1710053999,1710054000,1719792000,1730613599,1730613600,2147483647,2147483648,4102444800,32503680000]
zones=['UTC','Asia/Tokyo','America/New_York','Europe/London','Europe/Dublin','Asia/Kathmandu','Pacific/Chatham']
show=': SHOW >TIME&DATE&TZ DUP . 2DUP BOUNDS ?DO I C@ . LOOP 2DROP . . . . . . . . DEPTH . ; '
records=[];differences=0
for zone in zones:
 for stamp in seconds:
  results={}
  for runtime,cmd in commands.items():
   r=subprocess.run(cmd+[show+str(stamp)+'. SHOW BYE'],env={**os.environ,'TZ':zone},input='',capture_output=True,text=True,timeout=10)
   assert r.returncode==0,(runtime,zone,stamp,r.returncode,r.stdout,r.stderr)
   v=list(map(int,r.stdout.split()));n=v[0];name=bytes(v[1:1+n]).decode();rest=v[1+n:]
   assert len(rest)==9 and rest[-1]==0,(runtime,zone,stamp,v)
   results[runtime]={'calendar':list(reversed(rest[2:8])),'dst':rest[1],'offset':rest[0],'name':name}
  expected=datetime.datetime.fromtimestamp(stamp,zoneinfo.ZoneInfo(zone))
  fields=[expected.second,expected.minute,expected.hour,expected.day,expected.month,expected.year]
  dst=-1 if expected.dst() else 0
  for runtime,result in results.items():assert result['calendar']==fields and result['dst']==dst,(runtime,zone,stamp,result,fields,dst)
  actual=results['sigma'];assert actual['offset']==int(expected.utcoffset().total_seconds()) and actual['name']==expected.tzname(),(zone,stamp,actual,str(expected))
  if results['gforth']['offset']!=actual['offset'] or results['gforth']['name']!=actual['name']:differences+=1
  records.append({'zone':zone,'seconds':stamp,'sigma':actual,'gforth':results['gforth']})
# Bad native time_t and failed localtime conversions must throw instead of reading tm garbage.
for stamp in [2**80,-2**80,2**63-1,-2**63]:
 code=f': BAD {stamp}. >TIME&DATE&TZ ; \' BAD CATCH . DEPTH . BYE'
 r=subprocess.run(commands['sigma']+[code],env={**os.environ,'TZ':'UTC'},input='',capture_output=True,text=True,timeout=10)
 assert r.returncode==0 and r.stdout.split()==['-11','0'],(stamp,r.stdout,r.stderr)
report={'word':'>TIME&DATE&TZ','calendar_dst_comparisons':len(records),'actual_zone_oracle_checks':len(records),'reference_zone_differences':differences,'sigma_range_checks':4,'records':records,'pass':True}
root=pathlib.Path('.work/p05b-timezone-check');root.mkdir(parents=True,exist_ok=True);(root/'comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='records'}))
