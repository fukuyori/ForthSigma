#!/usr/bin/env python3
"""Public EXEC-LIMITED budgets and Unix PTY input/signal retention."""
import argparse, json, os, re, select, signal, subprocess, tempfile, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
PREFIX = 'REQUIRE-EXTENSION ALSO EXTENSION\n'
def run(sigma):
    reports=[]
    work=ROOT/'.work/652'; work.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=work,prefix='public-') as temp:
        source=Path(temp)/'check.fs'
        def invoke(code):
            source.write_text(PREFIX+code+'\nBYE\n',encoding='utf-8')
            result=subprocess.run([str(sigma),str(source)],capture_output=True,timeout=10)
            assert result.returncode==0 and not result.stderr.strip(),result
            return result.stdout.decode().split()
        assert invoke(': FOREVER BEGIN AGAIN ; 17 \' FOREVER 20 EXEC-LIMITED . .')==['-280','17']
        reports.append('finite-budget')
        assert invoke(': FOREVER BEGIN AGAIN ; : INNER [\'] FOREVER 0 EXEC-LIMITED 999 ; \' INNER 40 EXEC-LIMITED .')==['-280']
        reports.append('outer-budget-unwinds-inner')
        assert invoke(': SHORT 42 ; \' SHORT 0 EXEC-LIMITED . .')==['0','42']
        reports.append('unlimited-normal')
        assert invoke(': INNER 1 2 + ; : OUTER [\'] INNER 1 EXEC-LIMITED ; \' OUTER 100 EXEC-LIMITED . .')==['0','-280']
        reports.append('inner-budget-local')
        assert invoke(': BAD -123 THROW ; : RUN [\'] BAD 100 EXEC-LIMITED ; \' RUN CATCH .')==['-123']
        reports.append('ordinary-throw')
        assert invoke(': WAITING 1000000. NS ; \' WAITING 0 EXEC-LIMITED .')==['0']
        reports.append('nested-ns')
        image=Path(temp)/'execution.img'
        invoke(': IMAGE-VALUE 7 ; SAVE '+str(image))
        code=': LOADING S" LOAD-DICTIONARY '+str(image)+' [BEGIN] [AGAIN]" EVALUATE ; \' LOADING 200 EXEC-LIMITED . IMAGE-VALUE .'
        assert invoke(code)==['-280','7']
        reports.append('load-preserves-active-budget')

        if os.name!='nt':
            def terminal(name,raw,payload,reads=0,send_signal=False,operation="BEGIN AGAIN",reader="EKEY"):
                code=PREFIX+(': FOREVER ." READY" CR STDOUT FLUSH-FILE THROW '+operation+' ;\n')
                if raw: code+='EKEY? DROP\n'
                code+=': RUN [\'] FOREVER 0 EXEC-LIMITED DROP ;\n\' RUN CATCH . CR\n'
                code+=((reader+' . CR\n')*reads)+'BYE\n'
                source.write_text(code,encoding='utf-8')
                master,slave=os.openpty(); before=__import__('termios').tcgetattr(slave)
                proc=subprocess.Popen([str(sigma),str(source)],stdin=slave,stdout=slave,stderr=slave)
                data=b''
                def read_until(predicate,seconds=5):
                    nonlocal data
                    end=time.monotonic()+seconds
                    while not predicate():
                        assert time.monotonic()<end,(name,data,proc.poll())
                        ready,_,_=select.select([master],[],[],.05)
                        if ready:
                            try: block=os.read(master,8192)
                            except OSError: block=b''
                            data+=block
                        if proc.poll() is not None: break
                try:
                    read_until(lambda:b'READY' in data)
                    assert b'READY' in data,(name,data)
                    if payload: os.write(master,payload)
                    start=time.monotonic()
                    if send_signal: os.kill(proc.pid,signal.SIGINT)
                    read_until(lambda:proc.poll() is not None)
                    proc.wait(timeout=2)
                    assert proc.returncode==0 and b'-28' in data,(name,data,proc.returncode)
                    after=__import__('termios').tcgetattr(slave)
                    assert before==after,(name,'terminal mode not restored')
                    return data,time.monotonic()-start
                finally:
                    if proc.poll() is None: proc.kill(); proc.wait()
                    os.close(master);os.close(slave)
            data,latency=terminal('raw-retain',True,b'ab\x03',2)
            assert re.search(rb'-28\s+97\s+98',data),data
            reports.append({'raw-retain-seconds':latency})
            data,latency=terminal('escape-prefix',True,b'\x1b\x03',1)
            assert re.search(rb'-28\s+27',data),data
            reports.append('escape-prefix-retained')
            data,latency=terminal('incomplete-csi',True,b'\x1b[\x03',2)
            assert re.search(rb'-28\s+27\s+91',data),data
            reports.append('incomplete-csi-retained')
            data,latency=terminal('raw-to-key',True,b'a\x08b\x03',3,reader='KEY')
            assert re.search(rb'-28\s+97\s+8\s+98',data),data
            reports.append('raw-to-key-backspace')
            data,latency=terminal('raw-to-file',True,'日'.encode()+b'\x03',3,reader='PAD 1 STDIN READ-FILE THROW DROP PAD C@')
            assert re.search(rb'-28\s+230\s+151\s+165',data),data
            reports.append('raw-to-file-utf8')
            data,latency=terminal('paste',True,b'\x1b[200~\x03\x1b[201~\x03',3)
            assert b'3 ' in data,data
            reports.append({'paste-seconds':latency})
            data,latency=terminal('cooked-signal',False,b'',send_signal=True)
            reports.append({'cooked-signal-seconds':latency})
            data,latency=terminal('raw-ns',True,b'a\x03',1,operation='5000000000. NS')
            assert re.search(rb'-28\s+97',data),data
            reports.append({'raw-ns-seconds':latency})
            data,latency=terminal('cooked-key',False,b'',send_signal=True,operation='KEY DROP')
            reports.append({'cooked-key-seconds':latency})
    return reports
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('sigma',type=Path);args=parser.parse_args()
    print(json.dumps(run(args.sigma.resolve()),indent=2))
