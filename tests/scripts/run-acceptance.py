#!/usr/bin/env python3
"""1382 native acceptance preparation. Default mode never measures elapsed time.

Run from PowerShell on Windows, or Python 3 on Linux/macOS.
Formal measurement is deliberately a separate, explicitly confirmed invocation.
"""
import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import runpy
import shutil
import struct
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
AUTO = {
    "fmt": ["zig", "fmt", "--check"],
    "test": ["zig", "build", "test", "--summary", "all"],
    "runtime": ["zig", "build", "runtime-test", "--summary", "all"],
    "plain": ["zig", "build", "test", "-Ddebug=false", "--summary", "all"],
    "docs": [sys.executable, "scripts/check-docs.py"],
    "matrix": [sys.executable, "tests/scripts/verify-task-public-matrix.py", "--fresh-cache"],
}
PROBES = ["memory", "snapshot", "workloads", "reclaim", "response"]
MEASURE = ["cancel", "startup", "size", "events", "paint", *PROBES]
PENDING = {
    "normal": "cross-platform A/A'/B workload and disassembly capture is not implemented",
}
LIMITS = {
    "G1_enqueue_acquired_ns": 50_000_000, "G2_enqueue_acquired_ns": 100_000_000,
    "T1_enqueue_acquired_ns": 100_000_000, "I1_enqueue_acquired_ns": 200_000_000,
    "request_stop_ns": 10_000_000, "request_reclaim_ns": 100_000_000,
    "queued_cancel_publish_ns": 10_000_000, "management_turn_ns": 1_000_000,
    "input_state_ns": 16_670_000, "input_screen_ns": 33_340_000,
    "input_terminal_ns": 50_000_000, "snapshot_main_ns": 50_000_000,
    "snapshot_image_bytes": 4*1024*1024, "queue_waiting": 4, "publish_reclaim_ns": 100_000_000,
    "G1_submit_publish_ns": 100_000_000, "G2_submit_publish_ns": 500_000_000,
    "T1_submit_publish_ns": 200_000_000, "I1_submit_publish_ns": 250_000_000,
    "task_reserved_bytes": 128*1024*1024, "task_committed_bytes": 128*1024*1024,
    "task_resident_bytes": None, "process_reserved_bytes": None,
    "process_committed_bytes": None, "process_resident_bytes": None,
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def stats(values, limit=None):
    values = sorted(values)
    if not values:
        return {"n": 0, "status": "unmeasured"}
    n = len(values)
    return dict(n=n, median=(values[(n-1)//2] + values[n//2])/2,
                p95=values[math.ceil(n*.95)-1], maximum=values[-1],
                limit=limit, exceedances=sum(v > limit for v in values) if limit is not None else None)


def text_section(path):
    """Return logical and file-backed .text bytes for native PE/ELF/Mach-O artifacts."""
    data = Path(path).read_bytes()
    if data[:4] in (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"):
        raise ValueError("fat Mach-O binaries are not supported; supply thin arm64")
    # ABI offsets: Apple mach-o/loader.h, mach_header_64 / segment_command_64 / section_64.
    # https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h
    if data[:4] == b"\xcf\xfa\xed\xfe":
        if len(data) < 32:
            raise ValueError("truncated Mach-O header")
        cpu, = struct.unpack_from("<I", data, 4)
        count, commands_size = struct.unpack_from("<II", data, 16)
        if cpu != 0x0100000c:
            raise ValueError("Mach-O requires arm64")
        end = 32 + commands_size
        if end > len(data):
            raise ValueError("truncated Mach-O commands")
        offset = 32
        found = None
        for _ in range(count):
            if offset + 8 > end:
                raise ValueError("truncated Mach-O command")
            command, size = struct.unpack_from("<II", data, offset)
            if size < 8 or size % 8 or offset + size > end:
                raise ValueError("invalid Mach-O command size")
            if command == 0x19:  # LC_SEGMENT_64; mach-o/loader.h
                if size < 72:
                    raise ValueError("truncated segment_command_64")
                sections, = struct.unpack_from("<I", data, offset + 64)
                if 72 + sections * 80 > size:
                    raise ValueError("truncated section_64 array")
                for i in range(sections):
                    at = offset + 72 + i * 80
                    name = data[at:at+16].rstrip(b"\0")
                    segment = data[at+16:at+32].rstrip(b"\0")
                    if name == b"__text" and segment == b"__TEXT":
                        length, file_offset = struct.unpack_from("<QI", data, at+40)
                        flags, = struct.unpack_from("<I", data, at+64)
                        if flags & 0xff in (1, 0xc, 0x12) or file_offset + length > len(data):
                            raise ValueError("__TEXT,__text is not file backed or is truncated")
                        if found is not None:
                            raise ValueError("duplicate __TEXT,__text")
                        found = dict(format="Mach-O64-arm64", logical_bytes=length, file_bytes=length)
            offset += size
        if offset != end:
            raise ValueError("Mach-O command count/size mismatch")
        if found is None:
            raise ValueError("missing __TEXT,__text")
        return found
    if data[:2] == b"MZ":
        pe = struct.unpack_from("<I", data, 0x3c)[0]
        if data[pe:pe+4] != b"PE\0\0":
            raise ValueError("bad PE signature")
        count = struct.unpack_from("<H", data, pe+6)[0]
        optional = struct.unpack_from("<H", data, pe+20)[0]
        for i in range(count):
            section = pe+24+optional+i*40
            if data[section:section+8].rstrip(b"\0") == b".text":
                return dict(format="PE", logical_bytes=struct.unpack_from("<I", data, section+8)[0],
                            file_bytes=struct.unpack_from("<I", data, section+16)[0])
    elif data[:4] == b"\x7fELF":
        endian = {1: "<", 2: ">"}[data[5]]
        wide = data[4] == 2
        if data[4] not in [1, 2]:
            raise ValueError("unknown ELF class")
        offset = struct.unpack_from(endian+("Q" if wide else "I"), data, 40 if wide else 32)[0]
        stride, count, strings = struct.unpack_from(endian+"HHH", data, 58 if wide else 46)
        if not count or strings == 0xffff:
            raise ValueError("extended ELF section numbering is not supported")
        def section_value(index, wide_offset, narrow_offset):
            return struct.unpack_from(endian+("Q" if wide else "I"), data,
                                      offset+index*stride+(wide_offset if wide else narrow_offset))[0]
        names_offset = section_value(strings, 24, 16)
        names_size = section_value(strings, 32, 20)
        names = data[names_offset:names_offset+names_size]
        for i in range(count):
            name = struct.unpack_from(endian+"I", data, offset+i*stride)[0]
            if names[name:].split(b"\0", 1)[0] == b".text":
                size = section_value(i, 32, 20)
                return dict(format="ELF", logical_bytes=size, file_bytes=size)
    raise ValueError("no supported .text section; preserve artifact for static review")


def acceptance_plan(explicit=None, platform_name=None):
    return (explicit or ROOT / ('docs/TASK_CONTROL_ACCEPTANCE_PLAN_MACOS.md'
            if (platform_name or sys.platform) == 'darwin' else 'docs/TASK_CONTROL_ACCEPTANCE_PLAN.md')).resolve()


def memory_metrics(platform_name=None):
    return (['process_virtual_bytes', 'process_phys_footprint_bytes', 'process_resident_bytes']
            if (platform_name or sys.platform) == 'darwin' else
            ['process_reserved_bytes', 'process_committed_bytes', 'process_resident_bytes'])


def memory_budget(metric):
    return 128*1024*1024 if metric in ('process_reserved_bytes', 'process_committed_bytes', 'process_phys_footprint_bytes') else None


def paint_summary(path, mode):
    """Import only. Never launches a window or begins a timing run."""
    rows = []
    for line in Path(path).read_text(encoding='utf-8', errors='replace').splitlines():
        if line.startswith('PAINTTRACE '):
            rows.append(json.loads(line[len('PAINTTRACE '):]))
    if not rows:
        raise ValueError('no PAINTTRACE records in paint log')
    missing = []
    if any(r.get('lost_events', 0) for r in rows):
        missing.append('paint ring overflow')
    events = [r for r in rows if 'event' in r]
    allowed = {'request', 'complete', 'wait-register', 'wait-painted', 'input', 'terminal', 'draw-generation'}
    for row in events:
        if row['event'] not in allowed or any(type(row.get(k)) is not int or row[k] < 0 for k in ('frame', 'detail', 'at')) or type(row.get('smoke')) is not bool:
            raise ValueError('invalid PAINTTRACE event')
    if mode == 'smoke':
        return dict(status='format-only', events=len(events), missing=missing,
                    timing='no differences or thresholds calculated in smoke')
    if any(r.get('smoke', True) or type(r.get('at')) is not int or r['at'] <= 0 for r in events):
        raise ValueError('paint measurement requires non-smoke positive monotonic endpoints')
    requests, completed, registered, waited, inputs, terminals = {}, {}, {}, {}, {}, {}
    tables = {'request': requests, 'complete': completed, 'wait-register': registered,
              'wait-painted': waited, 'input': inputs}
    for row in sorted(events, key=lambda r: r['at']):
        kind, frame = row['event'], row['frame']
        if kind in tables:
            if frame in tables[kind]:
                raise ValueError('duplicate paint endpoint: %s/%s' % (kind, frame))
            tables[kind][frame] = row['at']
        elif kind == 'terminal':
            terminals.setdefault(frame, []).append(row)
    values = {k: [] for k in ('paint_request_complete_ns', 'paint_wait_ns', 'input_screen_ns', 'input_terminal_ns')}
    deadlines = []
    frames = sorted(requests)
    # Frame 1 opens the window: retain its raw endpoints, exclude it from steady cadence.
    steady = frames[1:]
    if not steady:
        missing.append('no steady frames')
    for frame in frames:
        if frame not in completed:
            missing.append('frame %d not drawn (never infer completion from a later painted-through number)' % frame)
            continue
        elapsed = completed[frame] - requests[frame]
        if elapsed < 0:
            raise ValueError('paint completion precedes request')
        values['paint_request_complete_ns'].append(elapsed)
        if frame in steady:
            deadline = requests[steady[0]] + (frame - steady[0] + 1) * 1_000_000_000 // 60
            deadlines.append(dict(frame=frame, deadline=deadline, complete=completed[frame], exceeded=completed[frame] > deadline))
        if frame not in registered or frame not in waited:
            missing.append('frame %d missing kind=5 endpoints' % frame)
        elif waited[frame] < registered[frame]:
            raise ValueError('PAINTED precedes wait registration')
        else:
            values['paint_wait_ns'].append(waited[frame] - registered[frame])
    for generation, start in inputs.items():
        candidates = [r for r in terminals.get(generation, []) if r['at'] >= start and r['detail'] in completed and completed[r['detail']] >= start]
        if not candidates:
            missing.append('generation %d has no matching input-to-drawn state' % generation)
            continue
        row = min(candidates, key=lambda r: r['at'])
        values['input_screen_ns'].append(completed[row['detail']] - start)
        values['input_terminal_ns'].append(row['at'] - start)
    if not inputs:
        missing.append('no input endpoints')
    return dict(status='imported-unverified', missing=missing,
                statistics={k: stats(v, LIMITS.get(k)) for k, v in values.items()},
                frames=deadlines, frame_deadline_exceedances=sum(r['exceeded'] for r in deadlines),
                limitation='Host input acquisition through backend drawing completion / terminal writer completion. OS/compositor/panel emission and human visual/audible observations are not measured.')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--mode", choices=["auto", "smoke", "measure"], default="auto")
    p.add_argument("--only", nargs="+", help="test runtime plain docs matrix examples trace cancel startup size events")
    p.add_argument("--list", action="store_true", help="list runnable groups and manual-only ACs without executing")
    p.add_argument("--confirmed", help="operator confirmation reference; required for every formal measurement")
    p.add_argument("--sigma", type=Path)
    p.add_argument("--build-manifest", type=Path, help="external binary build commands/configuration and hashes")
    p.add_argument("--baseline-build-manifest", type=Path, help="A source/archive/toolchain/build provenance, copied into evidence")
    p.add_argument("--baseline", type=Path, help="same-configuration A executable for startup/size")
    p.add_argument("--paint-log", type=Path, help="existing single-process native PAINTTRACE log; import only")
    p.add_argument("--paint-baseline-log", type=Path, help="same rendering/input/cadence without task load")
    p.add_argument("--events", type=Path, help="JSONL from separately instrumented real backend; see plan")
    p.add_argument("--plan", type=Path, help="frozen plan; defaults to macOS plan on Darwin")
    p.add_argument("--plan-sha256", help="expected frozen plan SHA-256 (required in measure mode)")
    p.add_argument("--probe-stages", nargs="+", help="only named stages for a flagged item extension")
    p.add_argument("--probe-cases", nargs="+", help="explicit normal probe cases; recorded as a partial run")
    p.add_argument("--repetitions", type=int, help="formal cancel default 100, startup default 100")
    a = p.parse_args()
    if a.list:
        print("auto: " + " ".join([*AUTO, "examples", "trace"]))
        print("smoke/measure: " + " ".join(MEASURE))
        print("blocked measurement groups: " + " ".join(PENDING))
        print("auto aliases: AC-01..AC-26 AC-28; aliases run covering suites, not isolated tests")
        print("AC-29: static A/B/A' collection is pending")
        print("manual subcases: AC-02 AC-05 AC-18 AC-20 AC-24 AC-25; AC-27 belongs to 1383")
        return 0
    if a.mode == "measure" and not a.plan_sha256:
        p.error("measurement requires --plan-sha256 of the reviewed plan")
    if a.mode == "measure" and not a.confirmed:
        p.error("formal measurement requires the operator's prior confirmation (--confirmed reference)")
    if a.mode == "measure" and not a.only:
        p.error("formal measurement requires explicit --only groups; no implicit full acceptance run")
    if a.repetitions is not None and a.repetitions < 1:
        p.error("repetitions must be positive")
    selected = a.only or (list(AUTO) + ["examples"] if a.mode == "auto" else ["cancel"])
    if a.mode == "auto":
        expanded = []
        for item in selected:
            if item.startswith("AC-"):
                try:
                    number = int(item[3:])
                except ValueError:
                    p.error("invalid AC ID: " + item)
                if number not in [*range(1, 27), 28, 29]:
                    p.error("AC ID is outside Windows/Linux scope: " + item)
                aliases = (["examples", "runtime"] if number in [2, 5, 18, 20, 24, 25] else
                           ["matrix"] if number == 26 else ["docs", "matrix"] if number == 28 else
                           [] if number == 29 else ["test", "runtime", "plain"])
                if not aliases:
                    p.error("AC-29 needs external static A/B/A' artifacts; see plan")
                expanded.extend(aliases)
            else:
                expanded.append(item)
        selected = list(dict.fromkeys(expanded))
    allowed = list(AUTO) + ["examples", "trace"] if a.mode == "auto" else [*MEASURE, *PENDING]
    if any(name not in allowed for name in selected):
        p.error(f"{a.mode} allows: {', '.join(allowed)}")
    if any(n in selected for n in ["cancel", "trace"]) and any(n in selected for n in ["startup", "size", "examples", *PROBES]):
        p.error("diagnostic and normal-build cases require separate invocations")
    if a.mode == "measure" and a.sigma and not a.build_manifest:
        p.error("external measured binary requires --build-manifest")
    os.chdir(ROOT)
    out = ROOT / ".work/acceptance" / (datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8])
    out.mkdir(parents=True)
    os.environ["ZIG_GLOBAL_CACHE_DIR"] = str(ROOT / ".work/acceptance-cache/global")
    report = dict(mode=a.mode, confirmation=a.confirmed, argv=sys.argv, results=[],
                  requested_items=a.only, expanded_items=selected, acceptance_verdict="not-evaluated",
                  environment=dict(platform=platform.platform(), machine=platform.machine(),
                  processor=platform.processor(), python=sys.version, cpu_count=os.cpu_count(),
                  parent_clock=vars(time.get_clock_info("perf_counter")),
                  cwd=str(ROOT), env={k: os.environ.get(k) for k in ["TERM", "DISPLAY", "WAYLAND_DISPLAY", "ZIG_GLOBAL_CACHE_DIR"]},
                  tty={k: v.isatty() for k, v in [("stdin", sys.stdin), ("stdout", sys.stdout), ("stderr", sys.stderr)]}))
    def save():
        (out / "results.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    def command(name, argv, env=None):
        entry = dict(item=name, command=list(map(str, argv)), log=name+".log", status="running")
        report["results"].append(entry)
        save()
        try:
            with (out / entry["log"]).open("wb") as log:
                r = subprocess.run(list(map(str, argv)), stdout=log, stderr=subprocess.STDOUT, env=env, timeout=7200)
        except Exception as exc:
            entry.update(status="failed", error=str(exc))
            save()
            raise
        entry.update(exit_code=r.returncode, status="passed" if r.returncode == 0 else "failed")
        save()
        if r.returncode:
            raise RuntimeError(f"{name}: exit {r.returncode}; see {out / entry['log']}")
    try:
        for key, cmd in [("head", ["git", "rev-parse", "HEAD"]), ("git_status", ["git", "status", "--short"]), ("zig", ["zig", "version"])]:
            report["environment"][key] = subprocess.check_output(cmd).decode(errors="replace").strip()
        report["source_manifest"] = {s: sha(ROOT/s) for s in subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard"]).decode().splitlines() if (ROOT/s).is_file()}
        report["runner_sha256"] = sha(__file__)
        zig_path = shutil.which("zig")
        report["environment"]["zig_executable"] = zig_path
        report["environment"]["zig_sha256"] = sha(zig_path)
        if sys.platform == "darwin" and platform.machine() != "arm64":
            raise ValueError("macOS acceptance requires native arm64, without Rosetta")
        if report["environment"]["zig"] != "0.17.1":
            raise ValueError("acceptance requires Zig 0.17.1")
        plan = acceptance_plan(a.plan)
        plan_bytes = plan.read_bytes()
        report["plan_sha256"] = hashlib.sha256(plan_bytes).hexdigest()
        (out / plan.name).write_bytes(plan_bytes)
        if a.plan_sha256 and a.plan_sha256.lower() != report["plan_sha256"]:
            raise ValueError("frozen plan SHA-256 mismatch: no measurement started")
        report["sampling_protocol"] = "reduced counts; not Usage Conditions section 8 prescribed starting counts; macOS requires prior count confirmation"
        report["plan_path"] = str(plan)
        if not report["environment"]["parent_clock"]["monotonic"]:
            raise ValueError("perf_counter must be monotonic")
        report["fixed_counts"] = dict(cancellation_attempts_per_phase=100, representative_native_operations=5,
            native_phases=3, interaction_seconds=600, interaction_repeats=1, memory_repeats=3,
            snapshot_processes=100, snapshot_generations=3, startup_warmup=5, startup_trials=100)
        if a.baseline_build_manifest:
            shutil.copyfile(a.baseline_build_manifest, out / "baseline-build-manifest.txt")
            report["baseline_build_manifest_sha256"] = sha(a.baseline_build_manifest)
        if a.build_manifest:
            shutil.copyfile(a.build_manifest, out / "external-build-manifest.json")
        sigma = a.sigma.resolve() if a.sigma else None
        needs_sigma = any(n in selected for n in ["examples", "trace", "cancel", "startup", "size", *PROBES])
        workload_only = set(selected) == {"workloads"}
        workload_flags = ["-Dtask-native-probe=false"]
        if needs_sigma and sigma is None:
            trace = "cancel" in selected or "trace" in selected
            prefix = out / ("trace-build" if trace else "normal-build")
            command("build", ["zig", "build", "-Doptimize=ReleaseFast", "-Ddebug=false", "-Dstrip=true", f"-Dtask-trace={str(trace).lower()}", f"-Dtask-acceptance={str(any(n in selected for n in PROBES if n != 'response')).lower()}", *(workload_flags if workload_only else []), "--prefix", prefix, "-j2"])
            sigma = prefix / "bin" / ("sigma.exe" if os.name == "nt" else "sigma")
        if sigma:
            if sys.platform == "darwin":
                text_section(sigma)  # Reject fat/wrong-architecture artifacts before execution.
            report["binary"] = dict(path=str(sigma), sha256=sha(sigma),
                                    configuration="external: operator must supply build provenance" if a.sigma else "ReleaseFast debug=false strip=true task-trace="+str("cancel" in selected or "trace" in selected)+" task-acceptance="+str(any(n in selected for n in PROBES if n != "response")))
        workload_sigma = sigma
        if "workloads" in selected and not workload_only and not a.sigma:
            prefix = out / "workloads-build"
            command("workloads-build", ["zig", "build", "-Doptimize=ReleaseFast", "-Ddebug=false", "-Dstrip=true",
                    "-Dtask-trace=false", "-Dtask-acceptance=true", *workload_flags, "--prefix", prefix, "-j2"])
            workload_sigma = prefix / "bin" / ("sigma.exe" if os.name == "nt" else "sigma")
        if "workloads" in selected:
            report["workloads_binary"] = dict(path=str(workload_sigma), sha256=sha(workload_sigma))
        response_sigma = sigma
        if "response" in selected and len(selected) > 1:
            if a.sigma:
                raise ValueError("response requires a separate proven normal build invocation")
            prefix = out / "response-build"
            command("response-build", ["zig", "build", "-Doptimize=ReleaseFast", "-Ddebug=false", "-Dstrip=true", "-Dtask-trace=false", "-Dtask-acceptance=false", "--prefix", prefix, "-j2"])
            response_sigma = prefix / "bin" / ("sigma.exe" if os.name == "nt" else "sigma")
        report["response_binary"] = dict(path=str(response_sigma), sha256=sha(response_sigma)) if "response" in selected else None
        save()
        for name in selected:
            print(f"{name}: running; evidence {out}", flush=True)
            if name in PENDING:
                report["results"].append(dict(item=name, status="blocked", reason=PENDING[name]))
                save()
                raise RuntimeError(PENDING[name])
            elif name in PROBES:
                report.setdefault("probe_sources", {}).update({str(path.relative_to(ROOT)): sha(path) for path in
                    [ROOT / "tests/scripts/acceptance-probes.py", ROOT / "tests/scripts/acceptance-fixtures.py", ROOT / "src/core/task_acceptance.zig"]})
                fixtures = runpy.run_path(str(ROOT / "tests/scripts/acceptance-fixtures.py"))["generate"](ROOT, out / "fixtures" / name, 1_000_000_000 if a.mode == "measure" and name == "workloads" else 1)
                if name == "memory":
                    path = fixtures["snapshot"]
                    path.write_text(path.read_text().replace('AS2 @ TASK-SNAPSHOT-RELEASE', '." ACCEPTANCE-MEMORY-HOLD" CR EKEY DROP AS2 @ TASK-SNAPSHOT-RELEASE'))
                driver = runpy.run_path(str(ROOT / "tests/scripts/acceptance-probes.py"))["run"]
                report.setdefault("fixture_manifest", {})[name] = {k: dict(path=str(v), sha256=sha(v)) for k, v in fixtures.items()}
                stages = "vm_start snapshot_retained state_reserved state_allocated memory_allocated data_allocated return_allocated float_allocated loops_allocated frames_allocated catches_allocated storage_zeroed storage_allocated initialized plan_allocated restore_validated restore_applied restored plan_released fresh_checked resolved grants_ready permissions_checked input_ready executing".split()
                cases = ([("cancel", stage) for stage in stages] + [("queued", None)] + [("native-"+native, phase) for native in ["fill", "move", "compare", "search", "roll"] for phase in ["native_before", "native_running", "native_after"]] if name == "reclaim" else
                         [("snapshot", None)] if name == "snapshot" else
                         [("response", None)] if name == "response" else
                         [(case, None) for case in ["G1-open", "G1-wall", "G1-snake", "G2", "T1", "I1"] + (["snapshot"] if name == "memory" else [])])
                if a.probe_cases:
                    cases = [(case, stage) for case, stage in cases if case in a.probe_cases]
                    if not cases: raise ValueError("no matching probe cases")
                if a.probe_stages:
                    cases = [(case, stage) for case, stage in cases if stage in a.probe_stages]
                    if not cases: raise ValueError("no matching probe stages")
                reps = (a.repetitions or 1) if a.mode == "smoke" else (a.repetitions or (100 if name in ["reclaim", "snapshot"] else 3 if name == "memory" else 1))
                entry = dict(item=name, status="running", trials=[], reduced_protocol=True, requested_repetitions=reps,
                             duration_seconds=600 if a.mode == "measure" and name in ["workloads", "response"] else None,
                             rule="not Usage Conditions section 8 prescribed counts; maximum >80% requires extension")
                report["results"].append(entry)
                save()
                grouped = {}
                stage_text = (ROOT / "src/core/task_trace.zig").read_text().split("pub const Stage = enum {", 1)[1].split("};", 1)[0]
                stage_names = [x.strip() for x in stage_text.split(',') if x.strip()]
                entry["phase_observations"] = []
                fixture_hashes = {case: sha(fixtures[case]) for case, _ in cases}
                event_file = (out / (name+".jsonl")).open("a", encoding="utf-8")
                for case, stage in cases:
                    for trial in range(reps):
                        raw = out / f"{name}-{case}-{stage or 'none'}-{trial:04d}"
                        if name == "response":
                            result = runpy.run_path(str(ROOT / "tests/scripts/acceptance-probes.py"))["response"](response_sigma, fixtures[case], raw, a.mode == "smoke")
                        else:
                            baseline = None
                            if name == "memory":
                                baseline = driver(sigma, fixtures["baseline-"+case], raw.with_name(raw.name+"-baseline"), a.mode == "smoke", memory_hold=True)
                            result = driver(workload_sigma if name == "workloads" else sigma, fixtures[case], raw, a.mode == "smoke", stage, case[7:] if case.startswith("native-") else None,
                                        600 if a.mode == "measure" and name == "workloads" else None, memory_hold=name == "memory", buffer_output=name == "workloads" and os.name == "nt")
                        if name == "workloads" and not any(row.get("native_probe") is False for row in result["events"]):
                            raise ValueError("workloads requires -Dtask-native-probe=false")
                        if result.get("phase_missed"):
                            entry.setdefault("missing", []).append(dict(case=case, stage=stage, trial=trial, reason="hold or native observation missing within 6s"))
                        if result.get("timed_out"):
                            entry.setdefault("missing", []).append(dict(case=case, stage=stage, trial=trial, reason="120s hang guard; endpoints missing", raw=raw.name))
                        if name == "memory" and a.mode == "measure":
                            if result["os_sample_errors"] or baseline["os_sample_errors"]:
                                entry.setdefault("missing", []).append(dict(case=case, trial=trial, reason="OS sample errors; see raw JSON"))
                            if not result["memory_checkpoints"] or not baseline["memory_checkpoints"] or len(result["memory_checkpoints"]) != result["expected_memory_checkpoints"] or len(baseline["memory_checkpoints"]) != baseline["expected_memory_checkpoints"]:
                                entry.setdefault("missing", []).append(dict(case=case, trial=trial, reason="acknowledged memory checkpoint missing"))
                            budgets = {}
                            for metric in memory_metrics():
                                b = [x[metric] for x in baseline["memory_checkpoints"][-1:]]
                                v = [x[metric] for x in result["os_samples"]]
                                if not b or not v:
                                    entry.setdefault("missing", []).append(dict(case=case, trial=trial, metric=metric, reason="OS sample missing"))
                                if b and v:
                                    delta = max(v)-max(b)
                                    budgets[metric] = dict(baseline_peak=max(b), loaded_peak=max(v), delta=delta,
                                        budget=memory_budget(metric),
                                        extend_required=memory_budget(metric) is not None and delta > .8*memory_budget(metric))
                            entry.setdefault("memory", []).append(dict(case=case, trial=trial, sampled_only=True, checkpoint_samples=len(result["memory_checkpoints"]), limitation="held checkpoints cover retained VM/result, not all transient allocation peaks", values=budgets))
                        entry["trials"].append(dict(case=case, stage=stage, trial=trial,
                                                   wall_seconds=result["trial_wall_seconds"], raw=raw.name))
                        if name == "snapshot" and not any(r.get("metric") == "snapshot_image_bytes" for r in result["events"]):
                            entry.setdefault("missing", []).append(dict(case=case, trial=trial, reason="snapshot endpoints absent"))
                        for row in result["events"]:
                            if "task" not in row: continue
                            if name == "workloads":
                                metric = case.split('-')[0]+"_enqueue_acquired_ns"
                                if metric in LIMITS and (not metric.startswith("I1_") or row.get("input_bytes") == 65552):
                                    fields = ["submitted", "input_copied", "enqueued", "acquired"]
                                    valid = all(type(row.get(field)) is int for field in fields)
                                    entry.setdefault("endpoint_formats", []).append(dict(case=case, trial=trial,
                                        metric=metric, fields=fields, valid=valid, smoke=a.mode == "smoke"))
                                    if not valid:
                                        entry.setdefault("missing", []).append(dict(case=case, trial=trial,
                                            metric=metric, reason="submission endpoint fields absent or invalid"))
                            if case == "queued" and row.get("queued"):
                                entry["phase_observations"].append(dict(case=case, target="queued", actual="queued",
                                    trial=trial, phase_ok=row["request_stage"] == 0, method="queue-removal"))
                            if not stage: continue
                            actual = stage_names[row["request_stage"]]
                            held = row.get("hold_stage") == stage_names.index(stage)
                            phase_ok = held and actual == stage and not row.get("hold_timeout", True) and not result.get("phase_missed")
                            entry["phase_observations"].append(dict(case=case, target=stage, actual=actual,
                                trial=trial, phase_ok=phase_ok, held=held,
                                method="guarded-native-entry-full-call" if stage == "native_running" else "token-hold"))
                            if not phase_ok:
                                entry.setdefault("missing", []).append(dict(case=case, stage=stage, trial=trial,
                                    reason="hold timeout or target/request phase mismatch"))
                        if a.mode == "measure":
                            if name != "response" and not any("task" in r for r in result["events"]) and name != "snapshot":
                                entry.setdefault("missing", []).append(dict(case=case, stage=stage, trial=trial, reason="task row absent"))
                            for row in result["events"]:
                                values = {}
                                if row.get("metric") == "input_state_ns":
                                    values[row["metric"]] = row["value"]
                                elif "value" in row:
                                    if row["metric"] in LIMITS: values[row["metric"]] = row["value"]
                                elif "lost_events" in row:
                                    entry.setdefault("missing", []).append(dict(case=case, stage=stage, trial=trial, reason="event buffer overflow", lost_events=row["lost_events"]))
                                elif "metric" in row:
                                    if name == "memory": continue
                                    if row["metric"] in LIMITS and not (row["end"] >= row["start"] > 0):
                                        entry.setdefault("missing", []).append(dict(case=case, trial=trial, metric=row["metric"], reason="clock endpoint invalid"))
                                    if row["metric"] in LIMITS and row["end"] >= row["start"] > 0:
                                        values[row["metric"]] = row["end"] - row["start"]
                                elif "task" in row:
                                    if name == "memory": continue
                                    phase_ok = not stage or (row.get("hold_stage") == stage_names.index(stage)
                                        and row["request_stage"] == stage_names.index(stage) and not row.get("hold_timeout", True))
                                    for endpoint in ["stopped", "published", "reclaimed"]:
                                        if endpoint == "stopped" and row.get("queued"): continue
                                        if not row.get(endpoint):
                                            entry.setdefault("missing", []).append(dict(case=case, stage=stage, trial=trial, endpoint=endpoint, reason="task endpoint absent or zero"))
                                    for metric, start, end in [
                                        ("request_stop_ns", "requested", "stopped"),
                                        ("request_reclaim_ns", "requested", "reclaimed"),
                                        ("publish_reclaim_ns", "published", "reclaimed"),
                                        ("queued_cancel_publish_ns", "requested", "published"),
                                        (case.split('-')[0]+"_enqueue_acquired_ns", "enqueued", "acquired"),
                                        (case.split('-')[0]+"_submit_publish_ns", "submitted", "published")]:
                                        if start == "requested" and name != "reclaim": continue
                                        if metric == "request_stop_ns" and row.get("queued"): continue
                                        if stage and not phase_ok and metric in ["request_stop_ns", "request_reclaim_ns"]:
                                            entry.setdefault("missing", []).append(dict(case=case, stage=stage, trial=trial, metric=metric, reason="hold timeout or target/request phase mismatch"))
                                            continue
                                        if metric == "queued_cancel_publish_ns" and not row["queued"]: continue
                                        if end == "acquired" and row.get("queued"): continue
                                        if metric in ["I1_submit_publish_ns", "I1_enqueue_acquired_ns"] and row.get("input_bytes") != 65552: continue
                                        if metric in LIMITS and row.get(end, 0) >= row.get(start, 0) > 0:
                                            values[metric] = row[end]-row[start]
                                        elif metric in LIMITS:
                                            entry.setdefault("missing", []).append(dict(case=case, stage=stage, trial=trial, metric=metric, reason=f"invalid or missing endpoints: {start}={row.get(start)}, {end}={row.get(end)}"))
                                for metric, value in values.items():
                                    grouped.setdefault((case, stage, metric), []).append(value)
                                    event_file.write(json.dumps(dict(case=case, stage=stage, metric=metric, trial=trial, value=value,
                                            unit="ns" if metric.endswith("_ns") else "count" if metric == "queue_waiting" else "bytes", build="normal" if name == "response" else "normal-path-probe", fixture_sha256=fixture_hashes[case]))+"\n")
                        save()
                event_file.close()
                if name == "reclaim":
                    entry["phase_complete"] = all(row["phase_ok"] for row in entry["phase_observations"])
                    entry["phase_missing_count"] = sum(not row["phase_ok"] for row in entry["phase_observations"])
                if name == "reclaim":
                    expected = len(cases) * reps
                    if len(entry["phase_observations"]) != expected:
                        entry["phase_complete"] = False
                        entry.setdefault("missing", []).append(dict(reason="phase rows absent", expected=expected,
                            observed=len(entry["phase_observations"])))
                entry.update(status="format-only" if a.mode == "smoke" else "incomplete" if entry.get("phase_missing_count") or entry.get("missing") else "recorded",
                    statistics=[dict(case=k[0], stage=k[1], metric=k[2], **stats(v, LIMITS[k[2]]),
                        extend_required=LIMITS[k[2]] is not None and max(v) > .8*LIMITS[k[2]]) for k,v in grouped.items()])
            elif name in AUTO:
                if name == "fmt":
                    changed = subprocess.check_output(["git", "diff", "--name-only", "HEAD", "--", "*.zig"]).decode().splitlines()
                    changed += subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "--", "*.zig"]).decode().splitlines()
                    AUTO["fmt"] = ["zig", "fmt", "--check", *sorted({s for s in changed if (ROOT/s).is_file()})]
                try:
                    command(name, AUTO[name])
                finally:
                    if name == "matrix" and (ROOT / ".work/task-public-matrix").exists():
                        binaries = {str(path.relative_to(ROOT)): dict(bytes=path.stat().st_size, sha256=sha(path))
                                    for path in (ROOT / ".work/task-public-matrix").rglob("*")
                                    if path.is_file() and path.name in ["sigma", "sigma.exe", "test", "test.exe"]}
                        (out / "matrix-binaries.json").write_text(json.dumps(binaries, indent=2)+"\n", encoding="utf-8")
                        shutil.copytree(ROOT / ".work/task-public-matrix", out / "matrix-raw",
                                        ignore=shutil.ignore_patterns("*.exe", "*.pdb", "*.o", "*.obj", "sigma", "test"))
            elif name == "examples":
                command(name, [sys.executable, "tests/scripts/verify-task-examples.py", "--sigma", sigma])
                shutil.copytree(ROOT / ".work/1380", out / "examples-raw")
            elif name == "trace":
                command(name, [sys.executable, "tests/scripts/trace-task-path.py", "--sigma", sigma, "--log", out / "trace-raw.log"])
            elif name == "cancel":
                # A short smoke executes each existing 06-H phase once, without computing deltas.
                reps = (a.repetitions or 1) if a.mode == "smoke" else (a.repetitions or 100)
                parser = runpy.run_path(str(ROOT / "tests/scripts/trace-task-path.py"))["records"]
                groups = {}
                for i in range(reps):
                    raw = out / f"cancel-{i:04d}.raw.log"
                    command(f"cancel-{i:04d}", [sys.executable, "tests/scripts/trace-task-path.py", "--sigma", sigma, "--cancel-stages", "--log", raw])
                    rows = parser(raw.read_text(encoding="utf-8", errors="replace"))
                    with (out / "cancel.jsonl").open("a", encoding="utf-8") as f:
                        for row in rows:
                            f.write(json.dumps(dict(trial=i, build="diagnostic", **row)) + "\n")
                    if a.mode == "measure":
                        # One process per stage in the raw log. Merge supplemental
                        # events instead of counting deadline/observed as extra trials.
                        merged = {}
                        for row in rows:
                            target = row["cancel_after_stage"]
                            dst = merged.setdefault(target, {})
                            for field, value in row.items():
                                if isinstance(value, int) and value:
                                    dst[field] = value
                        for stage, row in merged.items():
                            for end in ["detected", "forth_return", "runner_return", "sealed", "published", "observed", "host_stopped"]:
                                start = row.get("api_entry", 0)
                                value = row.get(end, 0)
                                group = groups.setdefault((stage, end), dict(values=[], missing=0))
                                if start and value >= start:
                                    group["values"].append(value-start)
                                else:
                                    group["missing"] += 1
                report["results"].append(dict(item="cancel-summary", status="format-only" if a.mode == "smoke" else "diagnostic-only", repetitions=reps,
                    statistics=[dict(stage=k[0], interval="api_entry->"+k[1], unit="ns", missing=v["missing"], **stats(v["values"], 10_000_000 if k[1] in ["detected", "forth_return", "runner_return"] else None)) for k,v in groups.items()],
                    limitation="Not a normal-build D07 verdict; no exact join/reference-release timestamp"))
            elif name in ["startup", "size"]:
                if not a.baseline:
                    raise ValueError("--baseline required for paired A/B comparison")
                baseline = a.baseline.resolve(strict=True)
                if sys.platform == "darwin":
                    text_section(baseline)
                report["baseline"] = dict(path=str(baseline), sha256=sha(baseline))
                if name == "size":
                    report["results"].append(dict(item=name, A=baseline.stat().st_size, B=sigma.stat().st_size,
                        text_A=text_section(baseline), text_B=text_section(sigma),
                        status="recorded", limitation="disassembly and D01 still require static review"))
                else:
                    fixture = out / "ready.fs"
                    fixture.write_text('." ACCEPTANCE-READY" CR BYE\n', encoding="utf-8")
                    report["startup_fixture"] = dict(path=str(fixture), sha256=sha(fixture))
                    save()
                    values = {"A": [], "B": []}
                    for i in range((2 if a.mode == "smoke" else (a.repetitions or 100)) + 5):
                        for variant in (["A", "B"] if i % 2 == 0 else ["B", "A"]):
                            exe = baseline if variant == "A" else sigma
                            wall_start = time.perf_counter()
                            start = time.perf_counter_ns() if a.mode == "measure" else None
                            child = subprocess.Popen([str(exe), str(fixture)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                            try:
                                # Session's background reader gives the ready marker a bounded wait.
                                import queue
                                import threading
                                received = queue.Queue()
                                def read_ready():
                                    received.put(child.stdout.readline())
                                reader = threading.Thread(target=read_ready, daemon=True)
                                reader.start()
                                line = received.get(timeout=120)
                                elapsed = time.perf_counter_ns()-start if start is not None else None
                                reader.join()
                                tail, err = child.communicate(timeout=120)
                            except Exception:
                                child.kill()
                                child.communicate()
                                raise
                            if child.returncode or b"ACCEPTANCE-READY" not in line:
                                raise RuntimeError(f"startup marker missing: {line+tail+err!r}")
                            sample = dict(trial=i, variant=variant, warmup=i<5, ready_ns=elapsed, trial_wall_seconds=time.perf_counter()-wall_start,
                                          command=[str(exe), str(fixture)], exit_code=child.returncode,
                                          stdout=(line+tail).decode(errors="replace"), stderr=err.decode(errors="replace"))
                            with (out / "startup.jsonl").open("a", encoding="utf-8") as f:
                                f.write(json.dumps(sample)+"\n")
                            if i >= 5 and elapsed is not None:
                                values[variant].append(elapsed)
                    report["results"].append(dict(item=name, status="recorded" if a.mode == "measure" else "format-only", statistics={k: stats(v) for k,v in values.items()}, limitation="parent receipt includes pipe/scheduling latency; review separately from internal readiness"))
            elif name == "paint":
                if not a.paint_log:
                    raise ValueError('--paint-log required; runner never starts native measurement')
                shutil.copyfile(a.paint_log, out / 'paint.log')
                entry = dict(item=name, **paint_summary(a.paint_log, a.mode))
                if a.paint_baseline_log:
                    shutil.copyfile(a.paint_baseline_log, out / 'paint-baseline.log')
                    baseline = paint_summary(a.paint_baseline_log, a.mode)
                    entry['baseline'] = baseline
                    if a.mode != 'smoke':
                        entry['additional_frame_deadline_exceedances'] = max(0, entry['frame_deadline_exceedances'] - baseline['frame_deadline_exceedances'])
                        entry['endpoint_counts_match'] = (not entry['missing'] and not baseline['missing'] and
                            len(entry['frames']) == len(baseline['frames']) and baseline['frame_deadline_exceedances'] == 0)
                        entry['comparison_eligible'] = False
                        entry['comparison_review'] = 'Claude must verify equal source/build/backend/refresh/input/rendering load and duration; raw logs alone do not establish these conditions'
                else:
                    entry['baseline_missing'] = 'rerun same rendering/input at 60Hz without tasks; no D07 added-frame verdict'
                report['results'].append(entry)
                save()
            elif name == "events":
                if not a.events:
                    raise ValueError("--events required: backend probe not implemented by this runner")
                shutil.copyfile(a.events, out / "events.jsonl")
                groups = {}
                seen = set()
                for line in a.events.read_text(encoding="utf-8").splitlines():
                    row = json.loads(line)
                    for field in ["case", "metric", "trial", "value", "unit", "build", "fixture_sha256"]:
                        if field not in row:
                            raise ValueError(f"missing event field: {field}")
                    if type(row["value"]) not in (float, int) or not math.isfinite(row["value"]) or row["value"] < 0:
                        raise ValueError("invalid sample")
                    if type(row["trial"]) is not int or row["trial"] < 0:
                        raise ValueError("trial must be a nonnegative integer")
                    if not isinstance(row["fixture_sha256"], str) or not re.fullmatch("[0-9a-f]{64}", row["fixture_sha256"]):
                        raise ValueError("fixture_sha256 must be a SHA-256 hex digest")
                    if a.mode == "measure" and row["build"] not in ["normal", "diagnostic"]:
                        raise ValueError("formal event build must be normal or diagnostic")
                    key = (row["case"], row["metric"], row["unit"], row["build"], row["fixture_sha256"])
                    if row["metric"] not in LIMITS:
                        raise ValueError("unknown metric: " + row["metric"])
                    unit = "ns" if row["metric"].endswith("_ns") else "count" if row["metric"] == "queue_waiting" else "bytes"
                    if row["unit"] != unit:
                        raise ValueError("metric unit mismatch")
                    identity = (*key, row["trial"])
                    if identity in seen:
                        raise ValueError("duplicate trial/metric")
                    seen.add(identity)
                    groups.setdefault(key, []).append(row["value"])
                report["results"].append(dict(item=name, status="format-only" if a.mode == "smoke" else "imported-unverified",
                    statistics=[] if a.mode == "smoke" else [dict(group=k, **stats(v, LIMITS[k[1]])) for k,v in groups.items()]))
    except Exception as exc:
        report["error"] = str(exc)
        save()
        print(str(exc), file=sys.stderr)
        return 1
    if sha(plan) != report.get("plan_sha256"):
        report["error"] = "plan changed during run"
        save()
        return 1
    save()
    print(out / "results.json")
    if a.mode == "smoke" and any(r.get("phase_complete") is False for r in report["results"]):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
