#!/usr/bin/env python3
"""Compile-time benchmark: clean vs incremental, March's CAS/BLAKE3 cache.

    python3 bench/compile_time.py [path/to/march] [prog.march]

Compile time is the complaint heard most often about statically-compiled
languages, so it belongs next to the runtime numbers. March content-addresses
each compiled definition (BLAKE3 over the def plus the compiler and runtime
digests), so a rebuild after an edit recompiles only the changed definition and
its dependents and links the rest from cache.

Two measurements, both on the same program:

  clean        cold cache (`.march/cas` removed) — the whole program compiled,
               dominated by clang lowering every definition.
  incremental  one integer literal changed, cache warm — the realistic
               edit-rebuild loop.

Prints its own provenance so a pasted result is traceable. Restores the source
it edits.
"""
import pathlib
import re
import shutil
import statistics
import subprocess
import sys
import time

MARCH = sys.argv[1] if len(sys.argv) > 1 else "./_build/default/bin/main.exe"
PROG = sys.argv[2] if len(sys.argv) > 2 else "bench/dataframe_bench.march"
OUT = "/tmp/march_compile_time_out"


def med_min(ts):
    ts = sorted(ts)
    return statistics.median(ts), ts[0]


def compile_once():
    t0 = time.perf_counter()
    subprocess.run([MARCH, "--compile", "--opt", "2", PROG, "-o", OUT],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return (time.perf_counter() - t0) * 1000


def cpu_info():
    p = pathlib.Path("/proc/cpuinfo")
    if p.exists():
        for line in p.read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    try:
        return subprocess.check_output(
            ["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
    except Exception:
        return "unknown"


def main():
    src_path = pathlib.Path(PROG)
    orig = src_path.read_text()
    lines = orig.count("\n") + 1

    print(f"program : {PROG} ({lines} lines)")
    print(f"cpu     : {cpu_info()}")

    clean = []
    for _ in range(3):
        shutil.rmtree(".march/cas", ignore_errors=True)
        clean.append(compile_once())
    cm, cl = med_min(clean)

    compile_once()  # warm the cache
    incr = []
    try:
        for i in range(5):
            src = src_path.read_text()
            new, k = re.subn(r"\b100\b", str(101 + (i % 2)), src, count=1)
            if k == 0:  # no `100` literal — flip any two-digit literal instead
                new, k = re.subn(r"\b(\d\d)\b",
                                 lambda m: str(int(m.group(1)) ^ 1), src, count=1)
            src_path.write_text(new)
            incr.append(compile_once())
    finally:
        src_path.write_text(orig)
    im, il = med_min(incr)

    print(f"clean       (cold CAS)         median {cm:6.0f} ms   min {cl:6.0f}")
    print(f"incremental (1 literal edited) median {im:6.0f} ms   min {il:6.0f}")
    if im > 0:
        print(f"speedup     {cm / im:.0f}x")


if __name__ == "__main__":
    main()
