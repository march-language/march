#!/usr/bin/env python3
"""Fold a MARCH_TRACE_GC=1 trace into per-object histories.

    scripts/gc-trace-report.py [DIR|gc.jsonl] [--top N] [--site PATTERN]
                               [--addr HEX] [--all]

Reads trace/gc/gc.jsonl (and trace/gc/sites.json when the program was built
with `march --rc-trace`, which names each event's "site" field) and prints:

  1. every object still live at the last event: its type tag, allocation
     site, and its full inc/dec history with the site and resulting count of
     each step (a cell the runtime made immortal, a string literal's shared
     cell, is counted apart and never listed as live);
  2. every object whose count went negative or that was freed twice;
  3. a per-site summary: allocs, incs, decs and frees by site, and the net
     (+allocs +incs -decs -frees), which is the number of references a site
     took and nothing released.

A site reads "<fn>#<ordinal>:<runtime callee>": the compiled function, the
position of the call among its runtime calls, and what it called; every
event that call made (a builtin's internal allocations included) carries
it.  Without --rc-trace every site reads -1, shown as "runtime": the
histories are still complete, only unattributed.  An address the allocator reuses after
a free starts a new object (a new generation), so histories never run
together.  A site id the table does not cover (a hot patch loaded on top of
the main program registers its own table) prints as "site#N".

Exit status is 1 when any object is live or any history is inconsistent, so
a test can use it as a leak gate; --all prints every object, live or not.

Workflow (CLAUDE.md "Leak hunting"):
    march --rc-trace --compile -o prog prog.march
    MARCH_TRACE_GC=1 ./prog
    scripts/gc-trace-report.py trace/gc
For a live process, `kill -USR2 PID` flushes the file first (USR1 if
MARCH_PREEMPT_SIGNAL moved the scheduler's tick onto USR2).
"""
import argparse
import json
import os
import re
import sys
from collections import defaultdict

TAG_NAMES = {
    -1: "String", -2: "Resource", -3: "Float", -7: "Task",
}


def tag_name(tag):
    if tag in TAG_NAMES:
        return TAG_NAMES[tag]
    if tag >= 0:
        return f"ctor#{tag}"
    return f"tag{tag}"


class Obj:
    __slots__ = ("addr", "gen", "tag", "alloc_site", "size", "events",
                 "rc", "freed", "double_free", "negative", "first_ts", "immortal")

    def __init__(self, addr, gen, first_ts):
        self.addr = addr
        self.gen = gen
        self.tag = None
        self.alloc_site = None
        self.size = 0
        self.events = []        # (event, site, rc, ts)
        self.rc = None
        self.freed = False
        self.double_free = False
        self.negative = False
        self.first_ts = first_ts
        self.immortal = False


def load_sites(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return []


def fold(lines):
    """Replay the trace. Returns (objects in first-seen order, parse errors)."""
    live = {}            # addr -> Obj (current generation)
    objs = []
    gens = defaultdict(int)
    bad = 0
    for ln, line in enumerate(lines, 1):
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except ValueError:
            bad += 1
            continue
        kind = ev.get("event")
        addr = ev.get("addr")
        site = ev.get("site", -1)
        rc = ev.get("rc", 0)
        tag = ev.get("tag", 0)
        ts = ev.get("ts_ns", 0)
        if addr is None or kind is None:
            bad += 1
            continue
        o = live.get(addr)
        if kind == "alloc":
            # A fresh cell at an address: a new generation, whatever was there
            # before (if the trace missed its free, the old one stays as it
            # was, marked freed=False, and shows up as live).
            if o is not None and not o.freed:
                o.events.append(("reused", site, rc, ts))
            gens[addr] += 1
            o = Obj(addr, gens[addr], ts)
            o.tag = tag
            o.alloc_site = site
            o.size = ev.get("size", 0)
            o.rc = 1
            objs.append(o)
            live[addr] = o
            o.events.append(("alloc", site, 1, ts))
            continue
        if o is None or o.freed:
            # An op on something whose birth the trace never saw (allocated
            # before tracing resolved, an immortal literal cell, a cell a
            # runtime allocator created without a trace event): give it a
            # generation so the history is still shown.
            gens[addr] += 1
            o = Obj(addr, gens[addr], ts)
            o.tag = tag
            o.alloc_site = None
            objs.append(o)
            live[addr] = o
        if o.tag is None or (o.tag == 0 and tag != 0):
            o.tag = tag
        o.events.append((kind, site, rc, ts))
        if kind == "immortal":
            o.immortal = True
            o.rc = rc
        elif kind == "free":
            if o.freed:
                o.double_free = True
            o.freed = True
            o.rc = 0
        else:
            o.rc = rc
            if rc < 0:
                o.negative = True
    return objs, bad


def site_label(sites, sid):
    if sid is None:
        return "?"
    if sid < 0:
        return "runtime"
    if sid < len(sites):
        return sites[sid]
    return f"site#{sid}"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("path", nargs="?", default="trace/gc",
                    help="trace directory (holding gc.jsonl and sites.json) or the gc.jsonl file")
    ap.add_argument("--top", type=int, default=50,
                    help="print at most N live objects (default 50; 0 = all)")
    ap.add_argument("--site", metavar="PATTERN",
                    help="only objects whose history touches a site matching this regex")
    ap.add_argument("--addr", metavar="HEX",
                    help="only the object(s) at this address (every generation)")
    ap.add_argument("--all", action="store_true",
                    help="print every object's history, not only live/inconsistent ones")
    ap.add_argument("--no-summary", action="store_true", help="skip the per-site summary")
    args = ap.parse_args()

    path = args.path
    if os.path.isdir(path):
        jsonl = os.path.join(path, "gc.jsonl")
        sites_path = os.path.join(path, "sites.json")
    else:
        jsonl = path
        sites_path = os.path.join(os.path.dirname(path) or ".", "sites.json")
    try:
        with open(jsonl) as f:
            lines = f.readlines()
    except OSError as e:
        print(f"gc-trace-report: cannot read {jsonl}: {e}", file=sys.stderr)
        return 2
    sites = load_sites(sites_path)
    objs, bad = fold(lines)

    def lbl(sid):
        return site_label(sites, sid)

    def matches(o):
        if args.addr:
            want = args.addr.lower()
            if not want.startswith("0x"):
                want = "0x" + want
            if o.addr.lower() != want:
                return False
        if args.site:
            pat = re.compile(args.site)
            if not any(pat.search(lbl(s)) for (_, s, _, _) in o.events):
                return False
        return True

    objs = [o for o in objs if matches(o)]
    immortal = [o for o in objs if o.immortal and not o.freed]
    live = [o for o in objs if not o.freed and not o.immortal]
    broken = [o for o in objs if o.negative or o.double_free]

    print(f"trace: {jsonl}")
    print(f"events: {sum(1 for l in lines if l.strip())}  objects: {len(objs)}"
          f"  live at end: {len(live)}  immortal: {len(immortal)}  inconsistent: {len(broken)}"
          f"  sites: {len(sites) or 'none (built without --rc-trace)'}"
          + (f"  unparseable lines: {bad}" if bad else ""))

    def show(o, why):
        birth = (f"allocated at {lbl(o.alloc_site)}" if o.alloc_site is not None
                 else "allocated before tracing (no alloc event)")
        print(f"\n{why} {o.addr} gen {o.gen}  {tag_name(o.tag)}"
              f"{f' ({o.size} bytes)' if o.size else ''}  {birth}  final rc {o.rc}")
        for (kind, sid, rc, _ts) in o.events:
            print(f"    {kind:<8} rc={rc:<4} {lbl(sid)}")

    shown = objs if args.all else live
    limit = args.top if args.top > 0 else len(shown)
    if shown:
        print(f"\n== {'all objects' if args.all else 'live at last event'}"
              f" ({len(shown)}{f', showing {limit}' if limit < len(shown) else ''}) ==")
        for o in shown[:limit]:
            show(o, "LIVE" if not o.freed else "freed")
    if broken:
        print(f"\n== inconsistent histories ({len(broken)}) ==")
        for o in broken:
            show(o, "NEGATIVE" if o.negative else "DOUBLE-FREE")

    if not args.no_summary:
        per = defaultdict(lambda: [0, 0, 0, 0])   # alloc, inc, dec, free
        for o in objs:
            for (kind, sid, _rc, _ts) in o.events:
                row = per[sid]
                if kind == "alloc":
                    row[0] += 1
                elif kind == "inc_ref":
                    row[1] += 1
                elif kind == "dec_ref":
                    row[2] += 1
                elif kind == "free":
                    row[3] += 1
        print("\n== per-site summary (net = allocs + incs - decs - frees) ==")
        print(f"{'site':<48} {'alloc':>6} {'inc':>6} {'dec':>6} {'free':>6} {'net':>6}")
        rows = sorted(per.items(), key=lambda kv: (-(kv[1][0] + kv[1][1] - kv[1][2] - kv[1][3]), kv[0]))
        for sid, (a, i, d, f) in rows:
            print(f"{lbl(sid):<48} {a:>6} {i:>6} {d:>6} {f:>6} {a + i - d - f:>6}")

    return 1 if (live or broken) else 0


if __name__ == "__main__":
    sys.exit(main())
