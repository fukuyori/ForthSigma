#!/usr/bin/env python3
"""Create owned SAVESYS apps and verify actual startup/arguments/diagnostic behavior."""
import argparse, hashlib, json, os, shutil, struct, subprocess, tempfile, zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def run(sigma,debug=True,files=True):
    reports=[];work=ROOT/'.work/1069';work.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='public-',dir=work) as temp:
        folder=Path(temp)
        def invoke(binary,args,expected=0):
            p=subprocess.run([str(binary)]+args,cwd=folder,input=b'',capture_output=True,timeout=20)
            assert p.returncode==expected,(args,p.returncode,p.stdout,p.stderr)
            assert not p.stderr,(args,p.stderr)
            return p.stdout.decode('utf-8')
        def build(name,body,register=True):
            path=folder/(name+('.exe' if os.name=='nt' else ''))
            code=body+' '+("' MAIN APP-ENTRY! " if register else 'APP-ENTRY-OFF ')+f'SAVESYS {path.name} BYE'
            invoke(sigma,['-e',code]);assert path.exists()
            return path
        body='VARIABLE RUNS : MAIN 1 RUNS +! RUNS @ . CR SOURCE NIP . >IN @ . BLK @ . SOURCE-ID . CR ARGC @ 1 ?DO I ARG DUP . TYPE CR LOOP ;'
        if not files:body=body.replace('BLK @','0')
        app=build('app',body)
        values=['','a b','日本語','-e','--format','--trace','-m','--']
        output=invoke(app,values);lines=[s.strip() for s in output.splitlines()]
        assert lines[:2]==['1','0 0 0 0'],output
        assert lines[2:]==[(str(len(s.encode()))+' '+s).strip() for s in values],output
        assert [s.strip() for s in invoke(app,[]).splitlines()]==['1','0 0 0 0']
        reports.append('once-empty-source-current-argv-including-empty-space-unicode-options')
        assert invoke(app,['--sigma','--','--sigma']).splitlines()[-1].strip()=='7 --sigma'
        assert invoke(app,['--sigma','--no-app','--','-e','42 . BYE']).split()==['42']
        invoke(app,['--sigma','--unknown'],1)
        invoke(app,['--sigma','-m','0'],1)
        invoke(app,['x']*256,1);invoke(app,['x'*12000],1)
        reports.append('host-prefix-bypass-unknown-layout-and-capacity-errors')
        assert invoke(sigma,['-e','[DEFINED] OPEN-FILE . BYE']).split()==(['-1'] if files else ['0'])
        if debug:
            invoke(app,['--sigma','--format-check','--','owned.fs'],1)
            source=folder/'owned.fs';source.write_text(': EXAMPLE 42 ;\n',encoding='utf-8')
            invoke(app,['--sigma','--no-app','--format-check','--',source.name],0)
            log=folder/'profile.jsonl'
            invoke(app,['--sigma','--no-app','--debug-log',str(log),'--','-e','42 . BYE'])
            assert log.exists()
            reports.append('format-requires-no-app-and-debug-log')
        else:invoke(app,['--sigma','--trace'],1)
        for name,code,status in [('normal','1 2 3',0),('bye','1 2 BYE',0),('quit','QUIT',1),('throw','-123 THROW',1)]:
            sample=build(name,': MAIN '+code+' ;');invoke(sample,[],status)
            if status: assert invoke(sample,['--sigma','--no-app','--','-e','42 . BYE']).split()==['42']
        reports.append('normal-bye-quit-throw-and-recovery')
        legacy=build('legacy',': MAIN ." NOT-AUTO" ;',False)
        assert 'FORTH/Sigma' in invoke(legacy,[])
        assert invoke(legacy,['-e','42 . BYE']).split()==['42']
        reports.append('unregistered-legacy-behavior')
        unicode_app=build('保存アプリ',': MAIN 42 . ;')
        assert invoke(unicode_app,[]).split()==['42']
        reports.append('unicode-save-and-executable-path')
        readonly=folder/'readonly';readonly.write_bytes(b'OLD');readonly.chmod(0o444)
        try:
            if os.name=='nt' or not os.access(readonly,os.W_OK):
                invoke(app,['--sigma','--no-app','--','-e','SAVESYS readonly BYE'],1)
                assert readonly.read_bytes()==b'OLD'
                reports.append('readonly-existing-output-retained')
            else:reports.append({'readonly-test':'skipped','reason':'effective filesystem access remains writable'})
        finally:readonly.chmod(0o644)
        second=folder/('second.exe' if os.name=='nt' else 'second')
        invoke(app,['--sigma','--no-app','--','-e',f'SAVESYS {second.name} BYE'])
        a,b=app.read_bytes(),second.read_bytes()
        assert struct.unpack_from('<Q',a,len(a)-8)==struct.unpack_from('<Q',b,len(b)-8)
        assert invoke(second,[]).splitlines()[0].strip()=='1'
        reports.append('resave-does-not-append-another-base')
        original=hashlib.sha256(app.read_bytes()).hexdigest()
        invoke(app,['--sigma','--no-app','--','-e',f'SAVESYS {app.name} BYE'],1)
        assert hashlib.sha256(app.read_bytes()).hexdigest()==original
        alias=folder/('alias.exe' if os.name=='nt' else 'alias')
        os.link(app,alias)
        invoke(app,['--sigma','--no-app','--','-e',f'SAVESYS {alias.name} BYE'],1)
        assert hashlib.sha256(app.read_bytes()).hexdigest()==original
        reports.append('self-overwrite-relative-path-and-hardlink-rejected')
        link=folder/'link';target=folder/'target';target.write_bytes(b'OLD')
        try:os.symlink(target.name,link)
        except OSError as error:reports.append({'symlink-test':'skipped','reason':str(error)})
        else:
            invoke(app,['--sigma','--no-app','--','-e','SAVESYS link BYE'],1)
            assert link.is_symlink() and target.read_bytes()==b'OLD'
            reports.append('final-symlink-rejected')
        frame=app.read_bytes();base=struct.unpack_from('<Q',frame,len(frame)-8)[0];length=struct.unpack_from('<I',frame,len(frame)-12)[0]
        for kind in ['crc','abi','root','length']:
            data=bytearray(frame)
            if kind=='crc':data[base+120]^=1
            if kind=='abi':data[base+104]^=1
            if kind=='root':
                w,c,n=struct.unpack_from('<QQQ',data,base+48);struct.pack_into('<q',data,base+112+w+c+n+0xdd0,-1)
                struct.pack_into('<I',data,base+length-4,zlib.crc32(data[base:base+length-4]))
            if kind=='length':struct.pack_into('<I',data,len(data)-12,length+1)
            broken=folder/('broken-'+kind+('.exe' if os.name=='nt' else ''));broken.write_bytes(data);broken.chmod(app.stat().st_mode)
            text=invoke(broken,['-e','42 . BYE'],1);assert 'INVALID IMAGE' in text and 'FORTH/Sigma' not in text,text
        reports.append('corrupt-crc-abi-root-and-footer-fail-before-forth-arguments')
        if os.name!='nt':
            import select,signal,termios,time
            def interrupt_app(name,body,expected):
                sample=build(name,': MAIN '+body+' ;')
                master,slave=os.openpty();before=termios.tcgetattr(slave)
                env=dict(os.environ,TERM='xterm')
                child=subprocess.Popen([str(sample)],cwd=folder,stdin=slave,stdout=slave,stderr=slave,env=env)
                data=b''
                try:
                    deadline=time.monotonic()+5
                    while b'READY' not in data:
                        assert time.monotonic()<deadline,(name,data)
                        ready,_,_=select.select([master],[],[],.05)
                        if ready:data+=os.read(master,4096)
                    time.sleep(.05)
                    os.kill(child.pid,signal.SIGINT)
                    child.wait(timeout=5)
                    assert child.returncode==expected,(name,child.returncode,data)
                    if expected==1:
                        after=termios.tcgetattr(slave)
                        # PENDIN is kernel input state, as in verify-execution-control.py.
                        pendin=getattr(termios,'PENDIN',0)
                        before[3]&=~pendin;after[3]&=~pendin
                        assert after==before,(name,'terminal not restored')
                finally:
                    if child.poll() is None:child.kill();child.wait()
                    os.close(master);os.close(slave)
            flush='STDOUT FLUSH-FILE THROW ' if files else ''
            interrupt_app('waiting','." READY" CR '+flush+'5000000000. NS',1)
            interrupt_app('computing','." READY" CR '+flush+'BEGIN AGAIN',-signal.SIGINT)
            reports.append('pty-wait-cooperative-interrupt-and-compute-os-termination')
        assert not list(folder.glob('.sigma-save-*.tmp'))
        reports.append('no-owned-temporary-files-left')
    return reports
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('sigma',type=Path);p.add_argument('--no-debug',action='store_true');p.add_argument('--no-files',action='store_true');args=p.parse_args()
    print(json.dumps(run(args.sigma.resolve(),not args.no_debug,not args.no_files),ensure_ascii=False,indent=2))
