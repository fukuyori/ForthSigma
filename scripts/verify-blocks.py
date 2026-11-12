#!/usr/bin/env python3
"""Native block integration checks, including EOF and SAVESYS termination."""
import pathlib
import subprocess
import sys
import tempfile

exe = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "zig-out/bin/sigma").resolve()
with tempfile.TemporaryDirectory(dir=pathlib.Path(".zig-cache"), prefix="verify-blocks-") as name:
    work = pathlib.Path(name).resolve()

    def run(program, binary=exe):
        result = subprocess.run([str(binary), "--max-steps", "100000", "-e", program], cwd=work,
                                input=b"", stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        assert result.returncode == 0, (program, result.stdout, result.stderr)
        return result.stdout

    for value, ending in [(65, "BYE"), (66, "")]:
        run(f"1 BLOCK {value} SWAP C! UPDATE {ending}")
        data = (work / "blocks.fb").read_bytes()
        assert len(data) == 2048 and data[1024] == value

    # Match Gforth: writing beyond EOF leaves filesystem-zeroed holes.
    (work / "blocks.fb").unlink()
    run("3 BLOCK DROP UPDATE FLUSH BYE")
    assert (work / "blocks.fb").read_bytes()[1024:2048] == b"\x00" * 1024
    assert run(": BAD 1 LOAD ; ' BAD CATCH . BYE") == b"-13 "

    data = [b"", b"BLK @ . SOURCE-ID . SOURCE NIP . 2 LOAD 11 .", b"22 .",
            b"7 . \\ ignored 999".ljust(64) + b"8 .", b"-99 THROW", b"NEXT", b"66 ."]
    (work / "blocks.fb").write_bytes(b"".join(x.ljust(1024, b" ") for x in data))
    result = run(": NEXT REFILL DROP ; 1 LOAD BLK @ . 3 LOAD : BAD 4 LOAD ; ' BAD CATCH . BLK @ . 5 LOAD BYE")
    assert result == b"1 2 1024 22 11 0 7 8 -99 0 66 ", result
    assert run(": KEPT 42 ; SAVE words.sigma LOAD-DICTIONARY words.sigma KEPT . BYE").endswith(b"42 ")

    block_file = work / "blocks.fb"
    if sys.platform != "win32":
        block_file.chmod(0o400)
        try:
            assert run("2 LOAD BYE") == b"22 "
        finally:
            block_file.chmod(0o600)

    saved = work / ("saved.exe" if sys.platform == "win32" else "saved")
    run(f": DIRTY 1 BLOCK 68 SWAP C! UPDATE ; SAVESYS {saved.name} BYE")
    run("DIRTY", saved)
    assert (work / "blocks.fb").read_bytes()[1024] == 68
print("Block integration passed: BYE, EOF, input restoration, dictionary load, SAVESYS EOF")
