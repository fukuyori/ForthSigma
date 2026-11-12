from p00_runner import run
from pathlib import Path
import tempfile
with tempfile.TemporaryDirectory(dir=Path('.work/gforth-audit').resolve()) as td:
 f=Path(td)/'unicode';f.write_text('日',encoding='utf-8')
 setup='S" '+str(f)+'" R/O OPEN-FILE THROW DUP >R '
 c=[('EKEY','EKEY .','26085','日'),
 ('KEY',': READ-BYTE KEY . ; '+setup+'\' READ-BYTE SWAP INFILE-EXECUTE R> CLOSE-FILE THROW','230'),
 ('EKEY>CHAR','26085 EKEY>CHAR . .','0 26085'),
 ('EKEY>XCHAR','26085 EKEY>XCHAR . .','-1 26085'),
 ('EKEY>FKEY','K-UP K-SHIFT-MASK OR EKEY>FKEY . K-UP K-SHIFT-MASK OR = .','-1 -1')]
 run('InputEvents',c)
