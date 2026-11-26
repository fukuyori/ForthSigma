#!/usr/bin/env python3
"""1057 saved-entry adapter. Standard library only; smoke is never timing evidence."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time
import uuid
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
CONFIGS = {
    'M0': {}, 'M1': {'graphics': False}, 'M2': {'audio': False},
    'M3': {'extension': False}, 'M4': {'audio': False, 'graphics': False},
    'M5': {'audio': False, 'extension': False},
    'M6': {'graphics': False, 'extension': False},
    'M7': {'audio': False, 'graphics': False, 'extension': False},
    'M8': {'files': False}, 'M9': {'files': False, 'debug': False},
    'M10': dict(audio=False, graphics=False, files=False, debug=False, float=False, image=False, x11=False),
    'M11': dict(audio=False, debug=False, x11=False),
}
MANUAL = {
    'MNL-01a': ('path', 'n を1回押し、要求世代と採用世代、古い結果に戻らないことを確認。終了は q。'),
    'MNL-01b': ('search', 'a/b の切替を確認。失敗 f は別の案内で実行。終了は q。'),
    'MNL-01b-f': ('search', '有効な画像が出た後 f を1回押し、画像の保持を確認。終了は q。'),
    'MNL-02': ('audible', '既知の短い合成音を聴き、n を1回押して音の乱れと画面応答を確認。終了は q。'),
    'MNL-03a': ('normal', '待機中に端末で Ctrl+C を1回押し、捕捉と端末・音声の状態を確認。'),
    'MNL-03b': ('cancel', 'c で取消し後、n で再投入し、新しい結果と画面・音声・入力の継続を確認。終了は q。'),
    'MNL-04': ('bye', 'q を1回押し、窓の消滅と音の停止を別々に確認。'),
    'MNL-05': ('normal', '窓の閉じるボタンを1回押し、待機解除と端末復旧を確認。'),
}

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

TTY = load('integration_tty', ROOT / 'tests/scripts/manual-acceptance-tty.py')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(path, text):
    path.write_text(text, encoding='utf-8', newline='\n')

def save(path, value):
    write(path, json.dumps(value, ensure_ascii=False, indent=2) + '\n')

def command(argv, directory, name, **kw):
    result = subprocess.run([str(v) for v in argv], cwd=ROOT, capture_output=True, timeout=600, **kw)
    (directory / (name + '.stdout')).write_bytes(result.stdout)
    (directory / (name + '.stderr')).write_bytes(result.stderr)
    save(directory / (name + '.json'), dict(argv=[str(v) for v in argv], status=result.returncode))
    if result.returncode:
        raise RuntimeError('%s: status %s; see %s' % (name, result.returncode, directory))
    return result

def text(path):
    return (ROOT / path).read_text(encoding='utf-8')

def source(config, directory, baseline, frames, measurement=False, backend='native'):
    options = CONFIGS[config]
    a, g, e, f = (options.get(k, True) for k in ('audio', 'graphics', 'extension', 'files'))
    f = f and e
    chunks = ['DECIMAL\n', '%d CONSTANT IA-NATIVE %d CONSTANT IA-TK\n' % (-int(backend=='native'),-int(backend=='tk'))]
    chunks += ['%d CONSTANT IA-%s\n' % (-int(value), key) for key, value in zip('AGEF', (a,g,e,f))]
    chunks += ['0 VALUE NV-BASELINE\n%d CONSTANT NV-FRAME-LIMIT\n' % frames,
               'DEFER IA-IMPORT DEFER IA-RESAVE DEFER IA-CHILD-ARGS\n', text('examples/integration/core.fs')]
    if g:
        chunks += ['REQUIRE-GRAPHICS ALSO GRAPHICS\n']
    if e:
        chunks += [text('examples/task-path-worker.fs'), text('examples/task-search-worker.fs'), text('examples/task-console.fs')]
        ext = text('examples/integration/extension.fs')
        first, rest = ext.split(': IA-REQUEST', 1)
        chunks += [first, ': NV-NUM >R >R 0 <# #S #> R> R> TEXT ;\n' if g else '']
        if g:
            native = text('examples/task-native-common.fs')
            chunks += [native[native.index(': NV-HEADER'):native.index(': NV-SHOW')]]
        requests = text('examples/integration/requests.fs')
        if not g:
            requests = requests[:requests.index(': NP-BOARD')] + requests[requests.index('CREATE TS-INPUT'):requests.index(': NS-BOARD')]
        chunks += [requests, ': IA-REQUEST' + rest]
    if a:
        chunks += [text('examples/pcm-synth.fs'), text('examples/integration/audio.fs')]
    if g:
        chunks += [text('examples/integration/graphics.fs')]
    if f:
        chunks += [text('examples/integration/pipe.fs')]
    if measurement:
        chunks += [text('examples/integration/measurement.fs')]
    chunks += [text('examples/integration/loop.fs')]
    child = directory / 'provider.py'
    write(child, 'import subprocess,sys\np=subprocess.Popen([sys.executable,"-c","import sys;sys.stdin.buffer.read()"],stdin=subprocess.PIPE)\n'
          'print("SEQ:1",flush=True)\nprint("SEQ:2",file=sys.stderr,flush=True)\nsys.stdin.buffer.read()\np.stdin.close()\np.wait(timeout=3)\n')
    extra = directory / 'append.sigma'
    resave = directory / ('resaved.exe' if os.name == 'nt' else 'resaved')
    chunks += [': IA-IMPORT-RUN S" LOAD-DICTIONARY %s" EVALUATE ;\n\' IA-IMPORT-RUN IS IA-IMPORT\n' % extra.as_posix(),
               ': IA-RESAVE-RUN S" SAVESYS %s" EVALUATE ;\n\' IA-RESAVE-RUN IS IA-RESAVE\n' % resave.as_posix()]
    if f:
        chunks += [': IA-CHILD-SETUP S" %s" IA-PROC-ARG S" %s" IA-PROC-ARG ;\n\' IA-CHILD-SETUP IS IA-CHILD-ARGS\n' % (Path(sys.executable).as_posix(), child.as_posix())]
    return '\n'.join(chunks)

def create_app(binary, config, directory, args):
    app = directory / ('sigma.exe' if os.name == 'nt' else 'sigma')
    body = source(config, directory, args.baseline, 0 if args.manual else args.frames, bool(args.measure), args.backend)
    definitions = directory / 'definitions.fs'
    write(definitions, body)
    # CLI file loading works independently of the FILES vocabulary. No INCLUDED
    # remains in generated definitions, including in files=false configurations.
    command([binary, definitions, '-e', "' IA-ENTRY APP-ENTRY! SAVESYS " + app.as_posix() + ' BYE'], directory, 'save')
    extra = directory / 'append.sigma'
    command([binary, '-e', ': IA-IMPORTED 73 ; : IA-IMPORT-ENTRY ." UNEXPECTED-APP-DISPATCH" ; '
             "' IA-IMPORT-ENTRY APP-ENTRY! SAVE " + extra.as_posix() + ' BYE'], directory, 'append-image')
    return app


def paint_records(output):
    # ConPTY may move the cursor instead of emitting a newline between writes.
    # Extract delimited protocol objects, preserving all raw bytes separately.
    return [json.loads(v) for v in re.findall(r'PAINTTRACE\s+(\{[^{}]*\})',output,re.S)]

def paint_text(output):
    return ''.join('PAINTTRACE '+json.dumps(v,separators=(',',':'))+'\n' for v in paint_records(output))

def execute(app, argv, directory, timeout, action=None, expected=0):
    session = TTY.Terminal(directory, timeout)
    record = dict(argv=[str(app), *argv], expected=expected, status='unverified', stdout_stderr='merged by ConPTY/PTY; output.bin preserves original terminal bytes')
    try:
        session.launch_argv(record['argv'])
        if action:
            action(session)
        recovery = session.finish(interrupted=expected != 0)
        output = session.text[session.start:]
        record.update(status='pass' if recovery['exit_code'] == expected else 'fail', recovery=recovery,
                      exit_code=recovery['exit_code'])
        if recovery['exit_code'] != expected:
            record['reason'] = 'unexpected exit status'
    except TTY.CollectionMissing as exc:
        output = session.text[getattr(session, 'start', 0):]
        record.update(status='unverified', reason=str(exc))
    except Exception as exc:
        output = session.text[getattr(session, 'start', 0):]
        record.update(status='fail', reason=str(exc))
    finally:
        session.close()
        record['forced_cleanup'] = session.forced_cleanup
        if session.collection_errors and record['status']=='pass':record.update(status='unverified',reason='native process/thread collection incomplete')
        if platform.system()=='Darwin' and record['status']=='pass':record.update(status='unverified',reason='native lifetime tracing required beyond macOS child polling')
        if session.forced_cleanup:
            record.update(status='fail', reason='owned workload required forced cleanup')
    write(directory / 'paint.log', paint_text(output))
    record['output_sha256'] = digest(directory / 'output.bin')
    record['evidence'] = str(directory.relative_to(ROOT))
    record['output'] = output
    save(directory / 'result.json', record)
    return record

def inspect(record, tokens=()):
    if record['status'] != 'pass':
        return False
    missing = [v for v in tokens if v not in record['output']]
    if missing:
        record.update(status='fail', reason='missing endpoints: ' + repr(missing))
        return False
    return True

def run_configuration(config, directory, args):
    directory.mkdir()
    options = CONFIGS[config]
    a,g,e,f = (options.get(k, True) for k in ('audio','graphics','extension','files'))
    binary = args.binary
    if binary is None:
        prefix = directory / 'build'
        argv = ['zig', 'build', '-Doptimize=ReleaseFast', '-Dtask-acceptance=true', '--prefix', str(prefix)]
        argv += ['-D%s=false' % k for k,v in options.items() if not v]
        command(argv, directory, 'build')
        binary = prefix / 'bin' / ('sigma.exe' if os.name == 'nt' else 'sigma')
    binary = binary.resolve(strict=True)
    ledger = [dict(ia='IA-%02d' % n, os=platform.system(), configuration=config, backend=args.backend,
                   status='unverified', automated_result='unverified', reason='additional evidence required', human_reply=None, limitations=[],
                   method='saved-entry integration', next_procedure='native full run / manual observation', evidence=[])
              for n in range(1,19)]
    def verdict(n, records, tokens=(), reason='saved-entry automatic endpoints and terminal/ownership checks'):
        good = [inspect(r,tokens) for r in records]
        ledger[n-1].update(status=('pass' if all(good) else ('fail' if any(r['status']=='fail' for r in records) else 'unverified')), reason=reason,
                           evidence=[r['evidence'] for r in records])
        ledger[n-1]['automated_result']=ledger[n-1]['status']
    def na(n, reason):
        ledger[n-1].update(status='N/A', automated_result='N/A', reason=reason, next_procedure=None)
    metadata = dict(binary=str(binary), binary_sha256=digest(binary), options=options)
    save(directory/'binary.json', metadata)
    if config == 'M10':
        result = command([binary,'-e','[DEFINED] SAVESYS . [DEFINED] APP-ENTRY! . BYE'],directory,'image-boundary')
        ledger[12].update(status='pass' if result.stdout.split() == [b'0',b'0'] else 'fail', reason='image exclusion boundary')
        for n in range(1,13): na(n,'image=false: no saved fixture')
        return ledger
    app = args.saved_app.resolve(strict=True) if args.saved_app else create_app(binary,config,directory,args)
    metadata.update(app=str(app), app_sha256=digest(app), definitions_sha256=digest(app.parent/'definitions.fs'))
    save(directory/'binary.json',metadata)
    if args.measure:
        return measure(app, directory, args, ledger, metadata)
    cases = {}
    def case(name, mode, action=None, expected=0, tokens=()):
        r=execute(app,mode,directory/name,args.timeout,action,expected)
        inspect(r,tokens);cases[name]=r
        save(directory/name/'result.json',r)
        print(config,name,r['status'],r.get('reason',''),flush=True)
        return r
    def ready(t): t.expect('IA-READY',t.start)
    def request_keys(keys):
        def action(t):
            ready(t)
            t.expect('result generation=1 ', t.start)
            for key in keys:
                offset=len(t.text);t.send(key)
                t.expect('result generation=|NATIVE-FAILED|IA-CANCEL resubmitted',offset)
        return action
    if args.manual:
        mode, guide=MANUAL[args.manual]
        print('%s\n実行体: %s\nOS/backend: %s / %s\n音声経路: %s\n引数: %s\n対象: 新しい保存アプリの窓と端末\n%s' %
              (args.manual,app,platform.system(),args.backend,args.audio_route,mode,guide),flush=True)
        def manual(t):
            ready(t)
            print('端末キーはこのコンソールに1行ずつ入力（ctrl-c は文字列 Ctrl+C）。done で回答へ。',flush=True)
            while not t.exited():
                key=input('キー> ')
                if key=='done':break
                if key=='Ctrl+C':t.send('\x03')
                else:t.send(key)
            if not t.exited(): t.send('q')
        result=case('manual',[mode],manual,0)
        save(directory/'human-reply.json',dict(unit=args.manual,reply=input('観察結果> '),result=result['evidence'],raw_sha256=result['output_sha256']))
        return ledger
    normal=case('normal',['normal','','a b','日本語','-e'],tokens=('IA-ENTRY runs=1','IA-READY','IA-END'))
    verdict(1,[normal],('IA-ENTRY runs=1','IA-READY','IA-FRESH no inherited runtime ownership'))
    if normal['output'].count('IA-ENTRY runs=1')!=1:ledger[0].update(status='fail',automated_result='fail',reason='entry did not run exactly once')
    bypass=case('bypass',['--sigma','--no-app','--','-e','4242 . CR BYE'],tokens=('4242',))
    empty=case('empty-arguments',[],lambda t:(ready(t),t.send('q')) if e or g else ready(t),tokens=('IA-ENTRY runs=1','IA-END'))
    verdict(2,[normal,empty,bypass])
    if not all(v in normal['output'] for v in ('IA-ARG 0 ','IA-ARG 3 a b','IA-ARG 9 日本語','IA-ARG 2 -e')):ledger[1].update(status='fail',automated_result='fail',reason='current argv byte lengths/content differ')
    if 'IA-ENTRY runs=' in bypass['output']: ledger[1].update(status='fail',reason='diagnostic bypass dispatched entry')
    stages=['input'] if e else []
    stages += ['window'] if g else []
    stages += ['pcm'] if a else []
    stages += ['task'] if e else []
    stages += ['pipe'] if e and f else []
    faults=[]
    for stage in stages:
        faults.append(case('fault-'+stage,['fault-'+stage],expected=1,tokens=('IA-CLEAN error=-4100',)))
        faults.append(case('recover-'+stage,['normal'],lambda t:(ready(t),t.send('q')) if e or g else ready(t),tokens=('IA-FRESH no inherited runtime ownership','IA-END')))
    fresh=case('fresh',['normal'],tokens=('IA-END',))
    if faults: verdict(3,[*faults,fresh])
    else:na(3,'no staged runtime resource groups')
    if e:
        auto=case('requests',['path'],request_keys('nfn'),tokens=('NATIVE-FAILED','result generation=4'))
        search=case('search',['search'],request_keys('bfa'),tokens=('NATIVE-FAILED','result generation=4'))
        cancel=case('cancel',['cancel'],request_keys('cn'),tokens=('IA-CANCEL requested','IA-CANCEL terminal','IA-CANCEL released','IA-CANCEL resubmitted'))
        verdict(8,[cancel])
        for record,example in [(auto,'path'),(search,'search')]:
            try:
                requested=1
                for item in re.finditer(r'NATIVE-INPUT generation=(\d+)|result generation=(\d+)',record['output']):
                    if item[1]:requested=int(item[1])
                    elif int(item[2])!=requested:raise AssertionError('stale result %s while requested=%s' % (item[2],requested))
                TTY.generations(record['output'])
                if 'NATIVE-FAILED retained=2' not in record['output']:raise AssertionError('failure did not retain generation 2')
            except AssertionError as exc:record.update(status='fail',reason=str(exc))
        save(directory/'requests/result.json',auto)
        save(directory/'search/result.json',search)
        if config=='M0':verdict(5,[auto,search])
        else:na(5,'IA-05 is specified for M0')
        verdict(4,[normal],('IA-WAIT events=',))
        events=[int(v) for v in re.findall(r'IA-EVENT seq=(\d+)', normal['output'])]
        totals=re.findall(r'IA-RECONCILE produced=(\d+) processed=(\d+) discarded=(\d+) pending=(\d+)',normal['output'])
        reconciled=(len(totals)==1 and events==list(range(1,len(events)+1)) and
                    int(totals[0][0])==len(events) and int(totals[0][0])==sum(map(int,totals[0][1:])))
        providers=('result generation=' in normal['output'] and 'IA-WAIT events=' in normal['output'])
        if f:
            # Python text pipes translate LF to CRLF on Windows only. These are
            # pipe byte totals, before the PTY's separate output translation.
            pipe_bytes=len(('SEQ:1'+os.linesep).encode('ascii'))
            providers=providers and 'SEQ:1' in normal['output'] and 'SEQ:2' in normal['output'] and ('stdout=%d stderr=%d' % (pipe_bytes,pipe_bytes)) in normal['output']
        ledger[3].update(status='unverified' if reconciled and providers else 'fail',automated_result='pass' if reconciled and providers else 'fail',
                         reason='readiness sequence/disposition and provider totals reconciled; human close is separate',
                         reconciliation=dict(events=len(events),totals=totals),limitations=['Readiness notifications are counted, not pipe bytes or task queue records.'])
    else:
        na(4,'no public composite wait without EXTENSION');na(5,'IA-05 is specified for M0');na(8,'EXTENSION excluded')
    exits=[case('exit-'+m,[m],expected=code,tokens=('IA-EXIT live '+m.upper(),)) for m,code in [('bye',0),('quit',1),('throw',1)]]
    verdict(9,[normal,*exits])
    append=case('append',['append'],tokens=('IA-APPEND preserved entry/resources; no dispatch','IA-END'))
    verdict(11,[append])
    if 'UNEXPECTED-APP-DISPATCH' in append['output']:ledger[10].update(status='fail',reason='append dispatched source entry')
    resaved=case('resave',['resave'],tokens=('IA-RESAVED',))
    second=directory/('resaved.exe' if os.name=='nt' else 'resaved')
    if second.exists():
        restored=execute(second,['normal'],directory/'restored',args.timeout)
        inspect(restored,('IA-ENTRY runs=1','IA-END'))
        verdict(10,[resaved,restored])
    else:verdict(10,[resaved],('IA-RESAVED',))
    verdict(12,[normal,fresh],('IA-END',))
    probe=('REQUIRE-AUDIO ALSO AUDIO ' if a else '')+'[DEFINED] PCM-OPEN . '
    probe+=('REQUIRE-GRAPHICS ALSO GRAPHICS ' if g else '')+'[DEFINED] GFX-INIT . '
    probe+=('REQUIRE-EXTENSION ALSO EXTENSION ' if e else '')+'[DEFINED] TASK-CANCEL . [DEFINED] OPEN-FILE . CR BYE'
    boundary=command([binary,'-e',probe],directory,'saved-configuration-boundary')
    if boundary.stdout.split()!=[str(-int(v)).encode() for v in (a,g,e,f)]:
        ledger[11].update(status='fail',automated_result='fail',reason='declared build does not match group boundary probe')
    if config=='M9':verdict(13,[cancel,normal])
    elif config=='M11':ledger[12].update(status='unverified',reason='Tk/terminal capability observations required on Linux')
    else:na(13,'M9/M10/M11 boundary only')
    if g and args.backend != 'native' and e:
        inspect(normal, ('IA-BUDGET deadline reached',))
        verdict(7, [normal, empty, auto, search],
                ('IA-FRAME-WAIT rejected no-capability; deadline/input fallback', 'IA-END'),
                reason='unsupported frame wait rejected; deadline and input termination completed with task results')
    elif not g:
        verdict(7, [normal], ('IA-END',), reason='graphics-excluded path progresses without frame wait')
    else:
        ledger[6].update(reason='native backend requires separate unsupported-backend observation' if args.backend == 'native'
                        else 'no composite capability probe without EXTENSION')
    if config!='M0':na(6,'IA-06 is specified for M0')
    else:ledger[5].update(reason='functional/smoke collection only; PAINTTRACE and PCM counters retained; no numerical timing verdict')
    for n in (14,15,16,17,18):ledger[n-1]['reason']='shared document / three-OS aggregate review required'
    save(directory/'cases.json',cases)
    return ledger


def measure(app, directory, args, ledger, metadata):
    """Reuse 1405 result-driven scheduling and frame-number baseline replay."""
    class Session(TTY.Terminal):
        @property
        def text(self):
            raw=super().text
            return re.sub(r'(?<!\n)(PAINTTRACE\s+\{)',r'\n\1',raw)
        def launch(self, sigma, source):
            self.launch_argv([str(app), 'measure-' + args.measure] + (['baseline',baseline_script] if args.baseline else []))
    class Runner(TTY.Runner):
        def end(self, terminal, interrupted=False):
            start = terminal.start
            recovery = terminal.finish(interrupted)
            return dict(recovery=recovery, output_before_exit=terminal.text[start:])
    runner = Runner.__new__(Runner)
    runner.root = directory
    runner.args = SimpleNamespace(native_frame_limit=args.frames,native_baseline=args.baseline,
                                  native_baseline_schedule=args.load_schedule,sigma=app)
    baseline_script = None
    if args.baseline:
        document=json.loads(args.load_schedule.read_text(encoding='utf-8'))
        candidate=next(c for c in document['results']['AC-25']['cases'] if c['name']=='native-'+args.measure)
        rendered=candidate.get('render_schedule',[])
        if len(rendered)!=args.frames-1:raise ValueError('load render schedule missing')
        transitions=[]
        previous=None
        for row in rendered:
            pair=(row['generation'],row['requested'])
            if pair!=previous:
                transitions.append('DUP %d >= IF %d IA-RENDER-GEN ! %d IA-RENDER-REQ ! THEN' % (row['frame'],*pair))
                previous=pair
        replay=directory/'render-replay.fs'
        write(replay,': IA-REPLAY-APPLY IA-FRAME @ 1+\n'+'\n'.join(transitions)+"\nDROP ;\n' IA-REPLAY-APPLY IS IA-REPLAY\n")
        baseline_script='S" '+replay.as_posix()+'" INCLUDED'
    terminal = Session(directory/'measurement', args.timeout)
    result = dict(status='unverified',native_baseline=args.baseline)
    try:
        result.update(runner.native(terminal,args.measure))
        output = result['output_before_exit']
        result['render_schedule']=[dict(frame=int(f),generation=int(g),requested=int(r)) for f,g,r in
                                   re.findall(r'IA-RENDER frame=(\d+) generation=(\d+) requested=(\d+)',output)]
        if len(result['render_schedule'])!=args.frames-1:raise AssertionError('render schedule incomplete')
        if args.baseline and result['render_schedule']!=candidate['render_schedule']:raise AssertionError('rendered content schedule differs')
        starts = re.findall(r'PCM-START underruns=(\d+)',output)
        ends = re.findall(r'PCM-END underruns=(\d+) start=(\d+) valid=(-?\d+) accepted=(\d+)',output)
        if len(starts)!=1 or len(ends)!=1 or ends[0][2]!='-1' or starts[0]!=ends[0][1]:
            raise AssertionError('PCM measurement interval endpoints missing or inconsistent')
        result['pcm'] = dict(start=int(starts[0]),end=int(ends[0][0]),delta=int(ends[0][0])-int(starts[0]),
                             accepted=int(ends[0][3]),format='48000 mono s16LE',block=512,capacity=4096)
        log=directory/'paint.log'
        write(log,paint_text(output))
        paint=load('integration_paint',ROOT/'tests/scripts/run-acceptance.py')
        result['paint']=paint.paint_summary(log,'smoke' if args.smoke else 'measure',baseline=args.baseline)
        result['status']='format-only' if args.smoke else 'unverified'
        result['reason']='Smoke is not timing evidence; pair rendering/PCM supply equality and the fixed two-pair/80% rule require review.'
    except Exception as exc:
        result.update(status='failed',reason=str(exc))
    finally:
        terminal.close()
        result['forced_cleanup']=terminal.forced_cleanup
        result['collection_errors']=terminal.collection_errors
        if terminal.forced_cleanup:result.update(status='failed',reason='owned workload required forced cleanup')
    # Same schema consumed by 1405's baseline scheduler.
    result.update(name='native-'+args.measure,app_sha256=metadata['app_sha256'],binary_sha256=metadata['binary_sha256'])
    save(directory/'results.json',dict(results={'AC-25':{'cases':[result]}}))
    ledger[5].update(status='fail' if result['status']=='failed' else 'unverified',reason=result['reason'],
                     evidence=[str((directory/'results.json').relative_to(ROOT))])
    return ledger

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--configs',nargs='+',choices=CONFIGS,default=['M0'])
    p.add_argument('--saved-app',type=Path,help='reuse the identical load saved executable for a baseline')
    p.add_argument('--binary',type=Path,help='existing acceptance build for exactly one configuration')
    p.add_argument('--smoke',action='store_true')
    p.add_argument('--functional',action='store_true',help='functional run without a timing verdict')
    p.add_argument('--frames',type=int,default=None)
    p.add_argument('--baseline',action='store_true')
    p.add_argument('--measure',choices=['path','search'],help='paired PAINTTRACE collection; Claude runs after confirmation')
    p.add_argument('--load-schedule',type=Path)
    p.add_argument('--confirmed')
    p.add_argument('--manual',choices=MANUAL)
    p.add_argument('--timeout',type=float,default=45)
    p.add_argument('--backend',choices=['native','tk','terminal'],default='native')
    p.add_argument('--audio-route',default='system default (unverified)')
    p.add_argument('--output',type=Path,default=ROOT/'.work/integration-acceptance')
    p.add_argument('--plan',type=Path,default=ROOT/'docs/INTEGRATION_ACCEPTANCE_PLAN_1057.ja.md')
    p.add_argument('--plan-sha256')
    args=p.parse_args()
    if args.baseline and args.load_schedule:
        load_meta=json.loads((args.load_schedule.parent/'binary.json').read_text(encoding='utf-8'))
        args.saved_app=Path(load_meta['app'])
        args.binary=Path(load_meta['binary'])
        if digest(args.saved_app)!=load_meta['app_sha256'] or digest(args.binary)!=load_meta['binary_sha256']:p.error('load artifact hash mismatch')
    if args.binary and len(args.configs)!=1:p.error('--binary requires exactly one configuration')
    if args.smoke and os.environ.get('SIGMA_ACCEPTANCE_SMOKE')!='1':p.error('smoke requires SIGMA_ACCEPTANCE_SMOKE=1')
    if args.plan.resolve()!=ROOT/'docs/INTEGRATION_ACCEPTANCE_PLAN_1057.ja.md':p.error('actual Japanese 1057 plan required')
    if args.plan_sha256 and args.plan_sha256!=digest(args.plan):p.error('plan hash mismatch')
    if args.baseline and (not args.measure or not args.load_schedule):p.error('baseline requires --measure and --load-schedule')
    if args.measure and args.backend!='native':p.error('IA-06 PAINTTRACE requires native backend')
    if args.measure and args.configs!=['M0']:p.error('IA-06 requires M0')
    if args.measure and not args.smoke and (not args.confirmed or not args.plan_sha256):p.error('formal collection requires --confirmed and --plan-sha256')
    if args.measure and not args.smoke and os.environ.get('SIGMA_ACCEPTANCE_SMOKE')=='1':p.error('formal collection cannot inherit smoke environment')
    if not args.smoke and not args.functional and not args.manual and not args.measure:p.error('formal timing is not enabled; this adapter currently accepts --smoke or one --manual unit')
    if 'M11' in args.configs and platform.system()!='Linux':p.error('M11 is Linux only')
    args.frames=args.frames or (240 if args.smoke else 1200)
    if args.measure and not args.smoke and args.frames!=1200:p.error('formal collection fixes 1200 frames')
    if args.frames<1:p.error('--frames must be positive')
    root=args.output.resolve()/ (time.strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8])
    root.mkdir(parents=True)
    # The adapter owns an ANSI-decoded PTY, independent of its invoking shell.
    # Noninteractive runners commonly export TERM=dumb (or omit it); inheriting
    # that disables TERM-MODE! even though the test PTY supports its sequences.
    inherited_term=os.environ.get('TERM')
    if os.name!='nt' and inherited_term in (None, '', 'dumb'):
        os.environ['TERM']='xterm-256color'
    manifest=dict(run_id=root.name,created=TTY.utc(),os=platform.platform(),python=sys.version,
                  smoke=args.smoke,argv=sys.argv,backend=args.backend,audio_route=args.audio_route,
                  terminal_environment=dict(inherited=inherited_term,effective=os.environ.get('TERM')),
                  head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                  plan_sha256=digest(args.plan),english_plan_sha256=digest(ROOT/'docs/INTEGRATION_ACCEPTANCE_PLAN_1057.md'),
                  sources={str(v.relative_to(ROOT)):digest(v) for v in [Path(__file__).resolve(),ROOT/'tests/scripts/manual-acceptance-tty.py',ROOT/'examples/task-path-worker.fs',ROOT/'examples/task-search-worker.fs',ROOT/'examples/task-console.fs',ROOT/'examples/task-native-common.fs',ROOT/'examples/pcm-synth.fs',ROOT/'src/main.zig',ROOT/'src/tests/task_reap_test.zig',*sorted((ROOT/'examples/integration').glob('*.fs'))]},confirmed=args.confirmed)
    save(root/'manifest.json',manifest)
    command(['git','diff','--binary'],root,'working-tree')
    command(['zig','version'],root,'zig-version')
    results=[]
    for config in args.configs:
        try:
            current=argparse.Namespace(**vars(args))
            if config=='M11' and current.backend=='native':current.backend='terminal'
            results+=run_configuration(config,root/config,current)
        except Exception as exc:
            save(root/(config+'-error.json'),dict(error=str(exc)))
            print(config,'ERROR',exc,flush=True)
            results += [dict(ia='IA-%02d'%n,configuration=config,os=platform.system(),backend=args.backend,status='unverified',reason=str(exc),human_reply=None,evidence=[]) for n in range(1,19)]
    for row in results:row.update(run_id=root.name,tested_revision=manifest['head'],recording_revision=manifest['head'],smoke=args.smoke,devices=args.audio_route)
    save(root/'ledger.json',results)
    print(root,flush=True)
    return int(any(r['status']=='fail' for r in results) or any(root.glob('*-error.json')))

if __name__=='__main__':sys.exit(main())
