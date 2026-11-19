#!/usr/bin/env python3
"""Owned real-pipe write acceptance; exercises backpressure, copied data and drain."""
import argparse,json,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def run(sigma):
    reports=[]
    with tempfile.TemporaryDirectory(prefix='async-write-',dir=ROOT/'.work') as directory:
        work=Path(directory); sink=work/'sink.py'; data=work/'received.bin'
        sink.write_text('import sys,time\ntime.sleep(.8)\nwith open(sys.argv[1],"wb") as f:\n while True:\n  b=sys.stdin.buffer.read(8192)\n  if not b: break\n  f.write(b)\n')
        producer=work/'producer.py';producer.write_text('import sys,time\ntime.sleep(.2)\nsys.stdout.buffer.write(b"R");sys.stdout.buffer.flush()\n')
        def invoke(name,body):
            source=work/(name+'.fs');source.write_text('REQUIRE-EXTENSION ALSO EXTENSION DECIMAL\n'+body+'\nBYE\n')
            result=subprocess.run([str(sigma.resolve()),str(source)],cwd=ROOT,capture_output=True,timeout=15)
            out=result.stdout.decode('utf-8','replace');err=result.stderr.decode('utf-8','replace')
            assert result.returncode==0 and not err,(name,result.returncode,out,err)
            reports.append({'case':name,'stdout':out});return out
        out=invoke('backpressure',f'''
S" {sys.executable} {sink} {data}" W/O OPEN-PIPE THROW CONSTANT PIPEOUT
S" {sys.executable} {producer}" R/O OPEN-PIPE THROW CONSTANT PIPEIN
CREATE READIDS PIPEIN ,
CREATE IDS PIPEOUT , CREATE DATA 65536 ALLOT DATA 65536 65 FILL
VARIABLE TOTAL
: SEND 8 0 DO DATA 65536 PIPEOUT WRITE-AVAILABLE THROW TOTAL +! LOOP ; SEND
IDS 1 20 WAIT-WRITABLE ." FULL " . . CR
READIDS 1 2000 WAIT-FILES THROW DROP
PAD 1 PIPEIN READ-AVAILABLE THROW DROP DROP PAD C@ ." PARALLEL " . CR
PIPEIN CLOSE-PIPE THROW DROP
DATA 65536 66 FILL
IDS 1 3000 WAIT-WRITABLE ." READY " . . CR
PIPEOUT FLUSH-FILE THROW
DATA 1 PIPEOUT WRITE-FILE THROW
PIPEOUT CLOSE-PIPE THROW DROP
." TOTAL " TOTAL @ . CR
''')
        assert 'FULL 0 -1' in out and 'READY 0 0' in out and 'PARALLEL 82' in out,out
        count=int(out.split('TOTAL ')[1].split()[0]);received=data.read_bytes()
        assert count>0 and received==b'A'*count+b'B',(count,len(received),received[:5],received[-5:])
        out=invoke('stdout-order','S" OLD" TYPE S" NEW" STDOUT WRITE-AVAILABLE THROW DROP STDOUT FLUSH-FILE THROW')
        assert out=='OLDNEW',out
        exiting=work/'exit.py';exiting.write_text('import time\ntime.sleep(.1)\n')
        out=invoke('broken-pipe',f'''S" {sys.executable} {exiting}" W/O OPEN-PIPE THROW CONSTANT PIPEOUT
300 MS
PAD 1 PIPEOUT WRITE-AVAILABLE ." FIRST " . . CR
PIPEOUT FLUSH-FILE ." FLUSH " . CR
PAD 1 PIPEOUT WRITE-AVAILABLE ." AGAIN " . . CR
PIPEOUT CLOSE-PIPE ." CLOSE " . . CR
''')
        assert 'AGAIN -544 0' in out,out
        if sys.platform=='win32': assert 'FLUSH -544' in out and 'CLOSE -544' in out,out

        source=work/'stderr.fs'
        source.write_text('''REQUIRE-EXTENSION ALSO EXTENSION DECIMAL
CREATE DATA 131072 ALLOT DATA 131072 69 FILL
DATA 65536 STDERR WRITE-AVAILABLE THROW . CR
DATA 131072 STDERR WRITE-FILE THROW STDERR FLUSH-FILE THROW BYE
''')
        result=subprocess.run([str(sigma.resolve()),str(source)],cwd=ROOT,capture_output=True,timeout=12)
        accepted=int(result.stdout.strip());assert result.returncode==0 and result.stderr==b'E'*(accepted+131072),(result.returncode,accepted,len(result.stderr))
        reports.append({'case':'stderr-queue-and-legacy','accepted':accepted,'stderr_bytes':len(result.stderr)})
        source.write_text('REQUIRE-EXTENSION ALSO EXTENSION S" OUT" STDOUT WRITE-AVAILABLE THROW DROP S" ERR" STDERR WRITE-FILE THROW BYE')
        result=subprocess.run([str(sigma.resolve()),str(source)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=12)
        assert result.returncode==0 and result.stdout==b'OUTERR',(result.returncode,result.stdout)
        reports.append({'case':'shared-stdout-stderr-order','stdout':result.stdout.decode()})
    return {'platform':sys.platform,'cases':reports}
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--sigma',required=True,type=Path);p.add_argument('--output',type=Path);a=p.parse_args();r=run(a.sigma)
    if a.output:a.output.write_text(json.dumps(r,indent=2)+'\n')
    print(json.dumps(r))
