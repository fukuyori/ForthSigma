"""Deterministic public-ABI fixtures, shared by smoke and measured runs."""
from pathlib import Path


def generate(root, out, turns=1):
    out.mkdir(parents=True, exist_ok=True)
    common = """REQUIRE-EXTENSION ALSO EXTENSION
VARIABLE AS VARIABLE AJ CREATE AR 524288 ALLOT
CREATE ATURN 4 , 0 , 0 , 0 , 0 , CREATE AEVENT 32 ALLOT
: ATICK ATURN 1 AEVENT 1 0 TASK-WAIT-MANY THROW 2DROP ;
\\ Preserve the supply interval while servicing reclamation every main turn.
: APACE 1000 * UTIME DROP + BEGIN ATICK
  DUP UTIME DROP > WHILE 1 MS REPEAT DROP ;
: AP AJ @ TASK-STATE THROW 2DROP DROP ;
: AW BEGIN AP DUP 3 < WHILE DROP 1 MS REPEAT DROP ;
: ARCHECK TASK-SUCCEEDED <> IF -1 THROW THEN ." RESULT-BYTES=" DUP . ." RESULT-COUNT=" AR CELL+ @ . CR DROP ;
: AC AJ @ TASK-CANCEL THROW AW AP TASK-CANCELLED <> IF -1 THROW THEN AJ @ TASK-RELEASE THROW ;
: AF AS @ TASK-SNAPSHOT-RELEASE THROW BYE ;
"""
    paths = {}
    def put(name, source):
        path = out / (name + '.fs')
        path.write_text(source, encoding='utf-8')
        paths[name] = path
    for shape in ('open', 'wall', 'snake'):
        # Rows alternate direction; blocked odd rows leave alternating end gaps.
        board = '' if shape == 'open' else (
            '0 BEGIN DUP 256 < WHILE 1 AI 32 + 2 PICK 256 * + 128 + C! 1+ REPEAT DROP' if shape == 'wall' else
            '1 BEGIN DUP 256 < WHILE 0 BEGIN DUP 256 < WHILE 1 AI 32 + 3 PICK 256 * + 2 PICK + C! 1+ REPEAT DROP DUP 4 MOD 1 = IF 255 ELSE 0 THEN 0 AI 32 + 3 PICK 256 * + ROT + C! 2 + REPEAT DROP')
        goal = 65280 if shape == 'snake' else 65535
        put('G1-' + shape, 'S" tests/task/task-path-worker.fs" INCLUDED\n' + common + """
CREATE AI 65568 ALLOT
: INIT AI 65568 0 FILL 1 AI ! 256 AI 8 + ! 0 AI 16 + ! 65535 AI 24 + !
""" + board + f' {goal} AI 24 + ! ' + """ ;
: RUN INIT TASK-SNAPSHOT THROW AS !
""" + f'{turns} ' + """0 DO AS @ S" TP-SEARCH" AI 65568 TASK-G1 7 TASK-SUBMIT THROW AJ ! AW
AJ @ AR 524288 TASK-RESULT THROW ARCHECK AJ @ TASK-RELEASE THROW LOOP ;
RUN AF
""")
    put('G2', 'S" tests/task/task-map-worker.fs" INCLUDED\n' + common + """
CREATE AI 24 ALLOT 1 AI ! 256 AI 8 + ! 0 AI 16 + !
: RUN TASK-SNAPSHOT THROW AS !
""" + f'{turns} ' + """0 DO AS @ S" TM-GENERATE" AI 24 TASK-G2 7 TASK-SUBMIT THROW AJ ! AW
AJ @ AR 524288 TASK-RESULT THROW ARCHECK AJ @ TASK-RELEASE THROW LOOP ; RUN AF
""")
    put('T1', 'S" tests/task/task-search-worker.fs" INCLUDED\n' + common + """
CREATE AI 1048593 ALLOT
: INIT 16 0 DO AI 17 + I 65536 * + 65536 97 FILL LOOP
1 AI ! 1 AI 8 + ! 97 AI 16 + C! ;
: RUN INIT TASK-SNAPSHOT THROW AS !
""" + f'{turns} ' + """0 DO AS @ S" TS-SEARCH" AI 1048593 TASK-T1 7 TASK-SUBMIT THROW AJ ! AW
AJ @ AR 524288 TASK-RESULT THROW ARCHECK AJ @ TASK-RELEASE THROW LOOP ; RUN AF
""")
    put('cancel', common + """
: AB 2DROP BEGIN AGAIN ;
: RUN TASK-SNAPSHOT THROW AS ! AS @ S" AB" S" x" TASK-G1 7 TASK-SUBMIT THROW AJ !
BEGIN AP DUP 3 < WHILE DROP REPEAT DROP AP TASK-CANCELLED <> IF -1 THROW THEN AJ @ TASK-RELEASE THROW ; RUN AF
""")
    put('queued', common + """
VARIABLE AK : AB 2DROP BEGIN AGAIN ;
: RUN TASK-SNAPSHOT THROW AS ! AS @ S" AB" S" x" TASK-I1 7 TASK-SUBMIT THROW AK !
BEGIN AK @ TASK-STATE THROW 2DROP DROP 2 = UNTIL
AS @ S" AB" S" y" TASK-I1 8 TASK-SUBMIT THROW AJ ! AC
AK @ AJ ! AC ; RUN AF
""")
    put('snapshot', common + """
CREATE AI 3000000 ALLOT VARIABLE AS2 VARIABLE AS3
: RUN TASK-SNAPSHOT THROW AS ! 1 ALLOT TASK-SNAPSHOT THROW AS2 !
1 ALLOT TASK-SNAPSHOT THROW AS3 ! AS2 @ TASK-SNAPSHOT-RELEASE THROW
AS3 @ TASK-SNAPSHOT-RELEASE THROW ; RUN AF
""")
    put('I1', 'S" tests/task/task-checksum-worker.fs" INCLUDED\n' + common + """
: AB 2DROP BEGIN AGAIN ; VARIABLE BLOCKER
CREATE AI 65552 ALLOT CREATE IDS 5 CELLS ALLOT VARIABLE AN VARIABLE AX VARIABLE LEFT
: INIT 65536 0 DO I 255 AND AI 16 + I + C! LOOP 1 AI ! IDS 5 CELLS 0 FILL ;
: FEED
5 0 DO IDS I CELLS + @ DUP IF
  TASK-STATE THROW 2DROP DROP 3 >= IF
    IDS I CELLS + @ AR 524288 TASK-RESULT THROW ARCHECK
    IDS I CELLS + @ TASK-RELEASE THROW 0 IDS I CELLS + ! THEN
ELSE DROP THEN
IDS I CELLS + @ 0= LEFT @ 0> AND IF
  AN @ 1+ AI 8 + ! AS @ S" TI-CHECKSUM" AI 65552 TASK-I1 I TASK-SUBMIT
  DUP TASK-E-FULL = IF 2DROP ELSE THROW IDS I CELLS + ! 1 AN +! -1 LEFT +! THEN
THEN LOOP ;
: RUN INIT TASK-SNAPSHOT THROW AS !
AS @ S" AB" S" x" TASK-I1 99 TASK-SUBMIT THROW BLOCKER !
BEGIN BLOCKER @ TASK-STATE THROW 2DROP DROP 2 = UNTIL
""" + str(max(5, turns)) + """ LEFT ! FEED BLOCKER @ TASK-CANCEL THROW BLOCKER @ TASK-RELEASE THROW
BEGIN FEED 0 AX ! 5 0 DO IDS I CELLS + @ AX @ OR AX ! LOOP
LEFT @ AX @ OR 0= UNTIL ; RUN AF
""")
    put('response', common + """
VARIABLE AI : AB 2DROP BEGIN AGAIN ;
: RUN TASK-SNAPSHOT THROW AS ! AS @ S" AB" S" x" TASK-I1 7 TASK-SUBMIT THROW AJ !
." INPUT-READY" CR
BEGIN AP DROP EKEY? IF EKEY DUP AI ! ." INPUT-APPLIED=" AI @ . CR 113 = ELSE 0 THEN UNTIL AC ; RUN AF
""")
    for native, body in {
        'fill': 'ABUF 65536 97 FILL',
        'move': 'ABUF ABUF 32768 + 32768 MOVE',
        'compare': 'ABUF 32768 ABUF 32768 + 32768 COMPARE DROP',
        'search': 'ABUF 65535 ABUF 65535 + 1 SEARCH 2DROP DROP',
        'roll': '0 BEGIN DUP 8192 < WHILE DUP 1+ REPEAT DROP 8191 ROLL 0 BEGIN DUP 8192 < WHILE NIP 1+ REPEAT DROP',
    }.items():
        initialization = 'CREATE ABUF 65536 ALLOT ABUF 65536 97 FILL'
        if native == 'search': initialization += ' 98 ABUF 65535 + C!'
        put('native-'+native, common + initialization + '\n: AB 2DROP BEGIN ' + body + ' AGAIN ;\n' +
            ': RUN TASK-SNAPSHOT THROW AS ! AS @ S" AB" S" x" TASK-I1 7 TASK-SUBMIT THROW AJ ! AW AP TASK-CANCELLED <> IF -1 THROW THEN AJ @ TASK-RELEASE THROW ; RUN AF\n')
    checks = {
        'G1-open': 'AR CELL+ @ 511 <> IF -1 THROW THEN',
        'G1-wall': 'AR CELL+ @ 0<> IF -1 THROW THEN',
        'G1-snake': 'AR CELL+ @ 32896 <> IF -1 THROW THEN',
        'G2': 'AR CELL+ @ 256 <> AR 16 + C@ 255 <> OR AR 17 + C@ 1 <> OR IF -1 THROW THEN',
        'T1': 'AR CELL+ @ 1048576 <> AR 16 + @ 1000 <> OR AR 24 + @ 0= OR IF -1 THROW THEN 1000 0 DO AR 32 + I CELLS + @ I <> IF -1 THROW THEN LOOP',
        'I1': 'AR 16 + @ 8355840 <> IF -1 THROW THEN',
    }
    for name, check in checks.items():
        paths[name].write_text(paths[name].read_text().replace('TASK-RESULT THROW ARCHECK', 'TASK-RESULT THROW ARCHECK '+check))
    for name in ['G1-open', 'G1-wall', 'G1-snake', 'G2', 'T1', 'I1', 'snapshot']:
        source = paths[name].read_text().split(': RUN', 1)[0]
        if ': INIT' in source: source += '\nINIT\n'
        put('baseline-'+name, source + 'TASK-SNAPSHOT THROW AS ! ." BASELINE-READY" CR EKEY DROP AF\n')
    if turns > 1:
        for name in ['G1-open', 'G1-wall', 'G1-snake', 'G2', 'T1']:
            path = paths[name]
            pace = 1000 if name == 'G2' else 100
            text = path.read_text().replace('THROW LOOP ;', 'THROW EKEY? IF EKEY 113 = IF LEAVE THEN THEN '+str(pace)+' APACE LOOP ;')
            path.write_text(text)
        path = paths['I1']
        text = path.read_text().replace('LEFT @ AX @ OR 0= UNTIL', '50 APACE EKEY? IF EKEY 113 = ELSE 0 THEN LEFT @ AX @ OR 0= OR UNTIL 5 0 DO IDS I CELLS + @ DUP IF TASK-RELEASE THROW ELSE DROP THEN LOOP')
        path.write_text(text)
    return paths

