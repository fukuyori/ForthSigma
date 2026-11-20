#!/usr/bin/env python3
"""Check the isolated blocked-audio child exits with status 1 and retained storage."""
import argparse,hashlib,json,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('probe',type=Path);args=p.parse_args()
probe=args.probe.resolve();rows=[]
for _ in range(3):
    begin=time.perf_counter()
    result=subprocess.run([str(probe)],input=b'',capture_output=True,timeout=5)
    elapsed=time.perf_counter()-begin
    assert result.returncode==1,(result.returncode,result.stdout,result.stderr)
    assert result.stdout.splitlines()==[b'blocked consumer retained; hard exit 1'] and not result.stderr,(result.stdout,result.stderr)
    rows.append({'exit_code':result.returncode,'stdout':result.stdout.decode(),'stderr':result.stderr.decode(),'elapsed_seconds':elapsed})
print(json.dumps({'probe':str(probe),'sha256':hashlib.sha256(probe.read_bytes()).hexdigest(),'runs':rows},indent=2))
