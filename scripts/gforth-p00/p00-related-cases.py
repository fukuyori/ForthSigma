from p00_runner import run
from pathlib import Path
import tempfile
with tempfile.TemporaryDirectory(dir=Path('.work/gforth-audit').resolve()) as td:
 d=Path(td);csvfile=d/'data.csv';csvfile.write_text('a,b\n')
 q=lambda p:'S" '+str(p)+'"'
 c=[]
 def a(w,s,e):c.append((w,s,e))
 a('OPEN-DIR',q(d/'missing')+' OPEN-DIR . DROP','-514')
 a('FILE>PATH','VARIABLE PP PP OFF '+q(d)+' PP ALSO-PATH : BAD S" missing" PP FILE>PATH 2DROP ; \' BAD CATCH .','-514')
 a('OPEN-PATH-FILE','VARIABLE PP PP OFF '+q(d)+' PP ALSO-PATH S" missing" PP OPEN-PATH-FILE .','-514')
 a('READ-CSV','REQUIRE csv.fs : FIELD . . TYPE SPACE ; '+q(csvfile)+' \' FIELD READ-CSV','1 0 a 1 1 b')
 a('READ-CSV-throw','REQUIRE csv.fs : FIELD 2DROP 2DROP -99 THROW ; : BAD '+q(csvfile)+' [\'] FIELD READ-CSV ; \' BAD CATCH .','-99')
 f=d/'evaluate.fb';f.write_bytes(b' '*1024+b'BLK @ . S" BLK @ ." EVALUATE BLK @ .'.ljust(1024,b' '))
 a('EVALUATE','USE '+str(f)+' 1 LOAD BLK @ .','1 0 1 0')
 f=d/'refill.fb';f.write_bytes(b' '*1024+b'REFILL'.ljust(1024,b' ')+b'. BLK @ . SOURCE NIP .'.ljust(1024,b' '))
 a('REFILL','USE '+str(f)+' 1 LOAD','-1 2 1024')
 f=d/'save.fb';f.write_bytes(b' '*1024+b'S'.ljust(1024,b' '))
 a('SAVE-INPUT',': S SAVE-INPUT RESTORE-INPUT . ; USE '+str(f)+' 1 LOAD','0')
 a('RESTORE-INPUT',': S SAVE-INPUT RESTORE-INPUT . ; USE '+str(f)+' 1 LOAD','0')
 f=d/'comment.fb';f.write_bytes(b' '*1024+(b'111 . \\ ignored').ljust(64,b' ')+b'222 .'.ljust(960,b' '))
 a('\\','USE '+str(f)+' 1 LOAD','111 222')
 run('Related',c)
