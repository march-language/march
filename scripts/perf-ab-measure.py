#!/usr/bin/env python3
"""Measurement core of scripts/perf-ab.sh: same-box, interleaved A/B timing.

Takes pairs of already-compiled benchmark binaries (one per compiler) and
reports, per benchmark, the median wall time of each arm, the ratio B/A, a
bootstrap 95% confidence interval for that ratio, and a verdict. It also
compares the runtime's MARCH_STRING_STATS allocation counters, which are
exact and do not move with machine load.

Design: specs/2026-10-30-perf-ab-runner-design.md. The rules it encodes were
each learned from a measurement that lied (specs/benchmarks.md):

  * Absolute milliseconds are never compared to anything recorded earlier.
    Only the two arms, measured in the same minute on the same box, are.
  * The arms are INTERLEAVED and the order alternates (A,B then B,A), so a
    load spike or thermal drift lands on both, and neither arm always pays
    the second-slot or first-slot cost.
  * Every binary is run untimed first. The first exec of a freshly written
    binary on macOS costs 300-600 ms of code-signing/page-in work that has
    nothing to do with the program.
  * Outputs are compared between arms. A candidate that got faster by
    computing something else is not faster.
  * Instrumentation never shares a run with a timing: the counter pass is a
    separate, untimed run.

Usage (normally invoked by scripts/perf-ab.sh):
  perf-ab-measure.py --runs N --threshold PCT --out-md F --out-json F \
      NAME:BIN_A:BIN_B [NAME:BIN_A:BIN_B ...]
Exit status: 0 nothing outside noise in the slow direction, 1 a regression
(timing or counter), 2 the comparison itself is invalid (a run failed, the
outputs differ).
"""

import argparse
import json
import os
import platform
import random
import re
import statistics
import subprocess
import sys
import time

# Counters read from the MARCH_STRING_STATS=1 dump (runtime/march_runtime.c,
# str_stats_dump). GATED counters are deterministic for a single-threaded
# benchmark, so an increase is a real change in the work done, not noise.
# peak_live_bytes is reported but not gated: it is a high-water mark sampled
# with relaxed atomics, so it can wobble by an object under the scheduler.
#
# The value is the absolute slack allowed. Object counts get none. Byte
# counters get a few bytes, because a benchmark that prints its own timing
# ("ms=88" one run, "ms=100" the next) allocates and copies one more byte
# when the number gains a digit: the A/A self-test caught json_stream doing
# exactly that. 64 bytes is a handful of printed numbers, and far below any
# change the string-ABI work could make.
GATED = {"allocs": 0, "obj_allocs": 0, "live_objs": 0, "obj_alloc_bytes": 0,
         "alloc_bytes": 64, "copy_bytes": 64}
REPORTED = list(GATED) + ["peak_live_bytes"]

# Wall-clock numbers some benchmarks print about themselves ("time: 2 ms",
# "ms=326", "TIME_MS 10.1"). Masked before the two arms' outputs are compared,
# so only the computed values have to agree.
# Horizontal whitespace only: a `\s*` would let "checksum=280000\nms=88" mask
# the checksum together with the timing.
TIMING_RE = re.compile(r"ms=\d+(\.\d+)?|TIME_MS[ \t]+\d+(\.\d+)?|\d+(\.\d+)?[ \t]*(ms|us|µs)\b")


def mask(out):
    return TIMING_RE.sub("<T>", out)


def run_once(binary, env=None):
    """Run [binary]; return (wall_ms, returncode, stdout, stderr).

    CPU time is taken around this call by ChildTimer."""
    start = time.perf_counter()
    proc = subprocess.Popen([binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env)
    out, err = proc.communicate()
    wall = (time.perf_counter() - start) * 1000.0
    return wall, proc.returncode, out.decode(errors="replace"), err.decode(errors="replace")


class ChildTimer:
    """Per-child user+sys CPU time via the RUSAGE_CHILDREN delta around each
    run. Exact because runs are strictly sequential: exactly one child
    terminates between two readings. On a loaded box CPU time is the less
    contaminated figure, so it is reported beside the wall time."""

    def __init__(self):
        import resource
        self.resource = resource
        self.last = self._read()

    def _read(self):
        r = self.resource.getrusage(self.resource.RUSAGE_CHILDREN)
        return (r.ru_utime + r.ru_stime) * 1000.0

    def lap(self):
        now = self._read()
        d = now - self.last
        self.last = now
        return d


def parse_stats(stderr):
    stats = {}
    for line in stderr.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "march_string_stats":
            try:
                stats[parts[1]] = int(parts[2])
            except ValueError:
                pass
    return stats


def bootstrap_ratio_ci(a, b, iters, rng):
    """95% percentile-bootstrap CI for median(b)/median(a).

    The arms are resampled independently. Medians, not means: one run that
    caught a load spike moves a mean arbitrarily far and a median not at
    all."""
    n_a, n_b = len(a), len(b)
    ratios = []
    for _ in range(iters):
        ma = statistics.median(a[rng.randrange(n_a)] for _ in range(n_a))
        mb = statistics.median(b[rng.randrange(n_b)] for _ in range(n_b))
        ratios.append(mb / ma if ma > 0 else float("inf"))
    ratios.sort()
    return ratios[int(0.025 * iters)], ratios[int(0.975 * iters) - 1]


def verdict(ratio, lo, hi, thr):
    """slower/faster only when BOTH the CI excludes 1.0 (the difference is
    real) AND the point estimate is beyond the threshold (it is big enough
    to matter). Either alone is not a finding: a tight CI on a 0.5% change is
    real but irrelevant, a 6% ratio with a CI straddling 1.0 is noise."""
    if lo > 1.0 and ratio > 1.0 + thr:
        return "slower"
    if hi < 1.0 and ratio < 1.0 - thr:
        return "faster"
    return "~"


def load1():
    try:
        return os.getloadavg()[0]
    except OSError:
        return float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=15)
    ap.add_argument("--warmup", type=int, default=2)
    ap.add_argument("--threshold", type=float, default=3.0, help="percent")
    ap.add_argument("--bootstrap", type=int, default=2000)
    ap.add_argument("--no-counter-gate", action="store_true")
    ap.add_argument("--metric", choices=["wall", "cpu"], default="cpu")
    ap.add_argument("--label-a", default="A")
    ap.add_argument("--label-b", default="B")
    ap.add_argument("--out-md")
    ap.add_argument("--out-json")
    ap.add_argument("pairs", nargs="+")
    args = ap.parse_args()
    thr = args.threshold / 100.0

    benches = []
    for p in args.pairs:
        name, a, b = p.split(":", 2)
        benches.append({"name": name, "bin": {"A": a, "B": b}})

    ncpu = os.cpu_count() or 1
    load_start = load1()
    invalid = []

    # Counter pass + output check: one untimed run per arm with the stats
    # dump on. It doubles as the first warmup run.
    for bch in benches:
        bch["stats"], outs = {}, {}
        for arm in ("A", "B"):
            env = dict(os.environ, MARCH_STRING_STATS="1")
            _, rc, out, err = run_once(bch["bin"][arm], env)
            if rc != 0:
                invalid.append(f"{bch['name']}: arm {arm} exited {rc}")
            bch["stats"][arm] = parse_stats(err)
            outs[arm] = mask(out)
        if outs["A"] != outs["B"]:
            invalid.append(f"{bch['name']}: outputs differ between arms")
            bch["output_differs"] = True

    # Warmup: untimed, absorbs first-exec cost and page cache.
    for _ in range(args.warmup):
        for bch in benches:
            for arm in ("A", "B"):
                run_once(bch["bin"][arm])

    timer = ChildTimer()
    for bch in benches:
        bch["wall"] = {"A": [], "B": []}
        bch["cpu"] = {"A": [], "B": []}
    for r in range(args.runs):
        for i, bch in enumerate(benches):
            order = ("A", "B") if (r + i) % 2 == 0 else ("B", "A")
            for arm in order:
                timer.lap()
                wall, rc, _, _ = run_once(bch["bin"][arm])
                cpu = timer.lap()
                if rc != 0:
                    invalid.append(f"{bch['name']}: arm {arm} exited {rc} on round {r}")
                bch["wall"][arm].append(wall)
                bch["cpu"][arm].append(cpu)
    load_end = load1()

    rng = random.Random(0x5EED)  # deterministic CIs for identical samples
    regressions = 0
    for bch in benches:
        for metric in ("wall", "cpu"):
            a, b = bch[metric]["A"], bch[metric]["B"]
            ma, mb = statistics.median(a), statistics.median(b)
            bch[metric + "_median_ms"] = {"A": ma, "B": mb}
            bch[metric + "_ratio"] = mb / ma if ma > 0 else float("inf")
            bch[metric + "_ci"] = bootstrap_ratio_ci(a, b, args.bootstrap, rng)
        bch["ratio"], bch["ci"] = bch[args.metric + "_ratio"], bch[args.metric + "_ci"]
        bch["verdict"] = verdict(bch["ratio"], *bch["ci"], thr)
        if bch["verdict"] == "slower":
            regressions += 1
        sa, sb = bch["stats"]["A"], bch["stats"]["B"]
        bch["counter_changes"] = {}
        for k in REPORTED:
            if k in sa and k in sb and sa[k] != sb[k]:
                bch["counter_changes"][k] = (sa[k], sb[k])
        bch["counter_regressed"] = [k for k, slack in GATED.items()
                                    if k in bch["counter_changes"]
                                    and bch["counter_changes"][k][1] > bch["counter_changes"][k][0] + slack]
        if bch["counter_regressed"] and not args.no_counter_gate:
            regressions += 1

    busy = load_start > ncpu / 2 or load_end > ncpu / 2
    lines = []
    lines.append(f"# perf A/B: {args.label_a} (A) vs {args.label_b} (B)\n")
    lines.append(f"Machine: {platform.system()} {platform.machine()}, {ncpu} cores. "
                 f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}. "
                 f"Load (1 min) {load_start:.2f} at start, {load_end:.2f} at end.")
    lines.append(f"{args.runs} interleaved rounds per arm after {args.warmup + 1} untimed "
                 f"warmup runs; compiled `--compile --opt 2`. A/B ms = median wall time; "
                 f"ratio = median(B)/median(A), with a bootstrap 95% CI, for wall and for "
                 f"user+sys CPU time. The verdict is on **{args.metric}** time and needs the "
                 f"CI to exclude 1.00 AND |ratio-1| > {args.threshold:g}%. Counters: "
                 f"MARCH_STRING_STATS, one untimed run per arm; ▲ = gated increase.\n")
    if busy:
        lines.append(f"> **WARNING: load average exceeded half the core count ({ncpu / 2:g}) "
                     f"during this run.** Both arms saw the same load, so the ratios still "
                     f"compare like with like, but expect wide wall-time CIs. CPU time is "
                     f"less affected; counters not at all.\n")
    lines.append("| benchmark | A ms | B ms | wall B/A [95% CI] | cpu B/A [95% CI] | verdict | counters |")
    lines.append("|---|---:|---:|---|---|---|---|")
    for bch in benches:
        if bch["counter_changes"]:
            cc = "; ".join(
                f"{k} {va:,}→{vb:,} ({(vb - va) / va * 100 if va else float('inf'):+.1f}%)"
                + (" ▲" if k in bch["counter_regressed"] else "")
                for k, (va, vb) in bch["counter_changes"].items())
        elif bch["stats"]["A"] and bch["stats"]["B"]:
            cc = "identical"
        else:
            cc = "n/a"
        v = bch["verdict"]
        if bch.get("output_differs"):
            v = "OUTPUT DIFFERS"
        elif v != "~":
            v = f"**{v}**"
        if bch["counter_regressed"] and not args.no_counter_gate:
            v = "**counters**" if v == "~" else v + " **counters**"
        wl, wh = bch["wall_ci"]
        cl, ch = bch["cpu_ci"]
        lines.append(f"| {bch['name']} | {bch['wall_median_ms']['A']:.1f} | {bch['wall_median_ms']['B']:.1f} "
                     f"| {bch['wall_ratio']:.3f} [{wl:.3f}, {wh:.3f}] "
                     f"| {bch['cpu_ratio']:.3f} [{cl:.3f}, {ch:.3f}] | {v} | {cc} |")
    lines.append("")
    if invalid:
        lines.append("**The comparison is INVALID:**\n")
        lines.extend(f"- {m}" for m in invalid)
        lines.append("")
    n_slow = sum(1 for b in benches if b["verdict"] == "slower")
    n_fast = sum(1 for b in benches if b["verdict"] == "faster")
    n_ctr = sum(1 for b in benches if b["counter_regressed"])
    lines.append(f"Summary: {n_slow} slower, {n_fast} faster, "
                 f"{len(benches) - n_slow - n_fast} within noise; "
                 f"{n_ctr} with an allocation-counter increase"
                 + (" (not gated)" if args.no_counter_gate else "") + ".")
    md = "\n".join(lines) + "\n"
    sys.stdout.write(md)
    if args.out_md:
        with open(args.out_md, "w") as f:
            f.write(md)
    if args.out_json:
        with open(args.out_json, "w") as f:
            json.dump({"label_a": args.label_a, "label_b": args.label_b,
                       "runs": args.runs, "threshold_pct": args.threshold,
                       "load_start": load_start, "load_end": load_end, "ncpu": ncpu,
                       "invalid": invalid, "benchmarks": benches}, f, indent=1)
    if invalid:
        return 2
    return 1 if regressions else 0


if __name__ == "__main__":
    sys.exit(main())
