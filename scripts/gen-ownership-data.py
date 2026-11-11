#!/usr/bin/env python3
"""gen-ownership-data.py: write docs/_data/ownership.json from the real compiler.

docs/one-owner.md is the third scrolling explainer. It follows one binary tree (depth 4:
16 leaves and 15 nodes, 31 cells) through ordinary functional code and shows what having
one owner buys: in-place reuse with no allocation, a copy the moment a second holder
appears, two halves rewritten on two tasks with no lock; then the same fact as a type
(`linear`, `affine`); then the contract that keeps it (`@[no_alloc]`). Every count,
excerpt and compiler message on it comes from docs/_data/ownership.json, which this script
writes; nothing on the page is typed in by hand.

    scripts/gen-ownership-data.py                 regenerate the data file
    scripts/gen-ownership-data.py --check         exit 1 if a fresh run would differ
    scripts/gen-ownership-data.py --check-inputs  exit 1 if a fixture, a pinned source
                                                  file or this script changed since the
                                                  data was generated (needs no compiler;
                                                  doc-lint Check H runs this)

The compiler is $MARCH_BIN or _build/default/bin/main.exe. No forge is needed.

What it does, each compiler run in its own fresh directory under a private HOME:

  1. for the four tree programs (owned, shared, vault, parallel) under
     docs/assets/explainer/ownership/programs/: runs `march --why-copies`, then compiles
     with `--rc-trace` and runs the binary with MARCH_TRACE_GC=1, and folds the runtime's
     trace/gc/gc.jsonl into allocations and increments per function, the way
     scripts/gc-trace-report.py folds it;
  2. runs `march --check` on the five linear/affine programs and records the diagnostic,
     its exit code, and which excerpt lines bind and use the tracked value;
  3. runs `march --compile` on the five contract programs (and the trace on the one whose
     caller keeps the old tree), and `--compile --report-contracts` on the owned program
     for the no_alloc candidate hint;
  4. pins the phrases of specs/lang/memory-model.md and specs/lang/linear-types.md the
     page quotes, and the alloc_bound design and todo it points at.

The recursion warnings the tree functions raise (`[non_tail_recursion]`) and clang's
target-triple warning are stripped from every quoted output.
"""
import datetime
import difflib
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "docs" / "_data" / "ownership.json"
FIXTURES = ROOT / "docs" / "assets" / "explainer" / "ownership"
PROGRAMS = FIXTURES / "programs"

_spec = importlib.util.spec_from_file_location("gen_explainer_data", ROOT / "scripts" / "gen-explainer-data.py")
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)


# ── the tree ───────────────────────────────────────────────────────────────────

DEPTH = 4   # `build(4, 1)` in the tree programs
TREE = {"depth": DEPTH, "leaves": 2 ** DEPTH, "nodes": 2 ** DEPTH - 1, "cells": 2 ** (DEPTH + 1) - 1}

RUNS = ["owned", "shared", "vault", "parallel"]
LINEAR = {"ok": "linear_ok", "twice": "linear_twice", "never": "linear_never",
          "affine_ok": "affine_ok", "affine_twice": "affine_twice"}
CONTRACTS = {"pinned": "contract_pinned", "bare": "contract_bare", "transient": "contract_transient",
             "boxed": "contract_boxed", "caller": "contract_caller"}

# The functions of each program a card shows.
EXCERPTS = {
    "owned": ["inc_leaves", "main"], "shared": ["main"], "vault": ["main"], "parallel": ["inc_parallel"],
    "linear_ok": ["inc_leaves", "main"], "linear_twice": ["main"], "linear_never": ["main"],
    "affine_ok": ["maybe_sum"], "affine_twice": ["twice"],
    "contract_pinned": ["inc_leaves"], "contract_bare": ["describe", "width_bare"],
    "contract_transient": ["width"], "contract_boxed": ["forward", "record"], "contract_caller": ["main"],
}


# ── excerpts ───────────────────────────────────────────────────────────────────

def excerpt_lines(source, names):
    """The named functions' source: each `fn NAME(` (with any `@[...]` attribute line
    directly above it) down to the `end` at the same indent, without that indent (the
    module's), one blank line between functions. Returns [(1-based source line or None
    for a separator, text)], in the order of `names`."""
    lines = source.splitlines()
    out = []
    for name in names:
        first = next(i for i, l in enumerate(lines)
                     if re.match(rf"\s*(p?fn)\s+{re.escape(name)}\s*\(", l))
        indent = len(lines[first]) - len(lines[first].lstrip())
        last = next(i for i in range(first + 1, len(lines))
                    if lines[i].strip() == "end" and len(lines[i]) - len(lines[i].lstrip()) == indent)
        start = first
        while start > 0 and lines[start - 1].strip().startswith("@["):
            start -= 1
        if out:
            out.append((None, ""))
        out.extend((i + 1, lines[i][indent:]) for i in range(start, last + 1))
    return out


def excerpt(source, names):
    return "\n".join(text for _, text in excerpt_lines(source, names)) + "\n"


def excerpt_line_of(lines, source_line):
    """The 1-based excerpt line that shows `source_line`, or None."""
    for n, (src, _) in enumerate(lines, 1):
        if src == source_line:
            return n
    return None


# ── diagnostics ────────────────────────────────────────────────────────────────

NOISE = re.compile(r"^(warning: overriding the module target triple.*|\d+ warnings? generated\.|compiled \S+)$", re.M)


def strip_warnings(text):
    """The compiler's output without the `-- WARNING: RECURSION` blocks the tree
    functions raise, clang's target-triple warning, and the `compiled ...` line; blocks
    separated by one blank line."""
    text = NOISE.sub("", text)
    blocks = [b for b in re.split(r"(?m)^(?=-- )", text) if not b.startswith("-- WARNING: RECURSION")]
    kept = "".join(blocks)
    kept = re.sub(r"\n{3,}", "\n\n", kept).strip("\n")
    return kept + "\n" if kept else ""


def points_at(output):
    """The source line a diagnostic's first `N |` gutter names, or None."""
    m = re.search(r"(?m)^\s*(\d+) \|", output)
    return int(m.group(1)) if m else None


def slug_of(output):
    m = re.search(r"\[([a-z_]+)\]\s*$", output, re.M)
    return m.group(1) if m else None


def reason_of(output):
    """The indented reason line under a contract message (`  In \\`f\\`: ...`)."""
    m = re.search(r"(?m)^  (\S.*)$", output)
    return m.group(1).strip() if m else None


# ── the trace ──────────────────────────────────────────────────────────────────

def fold_trace(lines, sites):
    """A MARCH_TRACE_GC=1 trace folded per site, as scripts/gc-trace-report.py's summary
    does: {site label: {"alloc": n, "inc": n, "dec": n, "free": n}}, labels sorted. A
    label is `<fn>#<ordinal>:<runtime callee>`; an unattributed event is `runtime`."""
    per = {}
    kinds = {"alloc": "alloc", "inc_ref": "inc", "dec_ref": "dec", "free": "free"}
    for line in lines:
        line = line.strip()
        if not line:
            continue
        ev = json.loads(line)
        kind = kinds.get(ev.get("event"))
        if kind is None:
            continue
        sid = ev.get("site", -1)
        label = sites[sid] if 0 <= sid < len(sites) else ("runtime" if sid < 0 else f"site#{sid}")
        row = per.setdefault(label, {"alloc": 0, "inc": 0, "dec": 0, "free": 0})
        row[kind] += 1
    return dict(sorted(per.items()))


SITE = re.compile(r"^(.*)#(\d+):(\w+)$")


def site_parts(label):
    """`inc_leaves#3:march_alloc` -> ("inc_leaves", "march_alloc"); the compiled entry
    point `march_main` is `main`."""
    m = SITE.match(label)
    if not m:
        return label, None
    fn = m.group(1)
    return ("main" if fn == "march_main" else fn), m.group(3)


def trace_facts(per_site, named=("build", "inc_leaves", "main")):
    """Allocations and increments per function. `allocs[fn]` counts the `march_alloc`
    cells a named function allocated; `tasks` the task handles `march_task_spawn_thunk`
    made; `plumbing` the cells every other function allocated (list cells, chunks,
    closures); `total` every allocation event in the trace, strings included."""
    allocs = {fn: 0 for fn in named}
    incs = {fn: 0 for fn in named}
    tasks = plumbing = total = 0
    for label, row in per_site.items():
        fn, callee = site_parts(label)
        total += row["alloc"]
        if fn in named:
            incs[fn] += row["inc"]
        if callee == "march_task_spawn_thunk":
            tasks += row["alloc"]
        elif callee == "march_alloc":
            if fn in named:
                allocs[fn] += row["alloc"]
            else:
                plumbing += row["alloc"]
    allocs.update({"tasks": tasks, "plumbing": plumbing, "total": total})
    return {"allocs": allocs, "incs": incs}


# ── the tracked value ──────────────────────────────────────────────────────────

BINDER = re.compile(r"\b(linear|affine)\s+let\s+t\b|\b(linear|affine)\s+t\s*:|\bt\s*:\s*(linear|affine)\b")
USE = re.compile(r"\bt\b")


def token_lines(text):
    """Where the tracked value `t` lives in an excerpt: ("linear"|"affine", the 1-based
    line that binds it, the lines after it that use it, one entry per use)."""
    lines = text.splitlines()
    binder = kind = None
    for n, l in enumerate(lines, 1):
        m = BINDER.search(l)
        if m:
            binder, kind = n, next(g for g in m.groups() if g)
    if binder is None:
        sys.exit("gen-ownership-data: no linear or affine binding of `t` in:\n" + text)
    uses = [n for n, l in enumerate(lines, 1) if n > binder for _ in USE.findall(l)]
    return kind, binder, uses


# ── pinned prose ───────────────────────────────────────────────────────────────

# Claims the page quotes. Each is an exact phrase (whitespace folded) that must still be
# in the file; if it is gone the page must not go on quoting it.
PINNED = [
    {"name": "strongest", "file": "specs/lang/memory-model.md",
     "phrase": "A `linear` value is the *strongest* FBIP case"},
    {"name": "fallback", "file": "specs/lang/memory-model.md",
     "phrase": "the fallback is automatic and always correct"},
    {"name": "disjoint", "file": "specs/lang/memory-model.md",
     "phrase": "Uniqueness *is* the disjointness proof"},
    {"name": "erased", "file": "specs/lang/linear-types.md",
     "phrase": "linearity is **compile-time-erased**"},
    {"name": "endpoint", "file": "specs/lang/linear-types.md",
     "phrase": "An endpoint is tracked as affine plus"},
]
ALLOC_BOUND = {"todo": "specs/todos/2026-11-04-alloc-bound-contract.md",
               "design": "specs/2026-11-04-alloc-bound-design.md"}
ALLOC_BOUND_PHRASE = "`@[alloc_bound(N)]`"


def _folded(text):
    return re.sub(r"\s+", " ", text)


def pinned_facts(root):
    root = Path(root)
    out = {}
    for e in PINNED:
        path = root / e["file"]
        if not path.exists() or _folded(e["phrase"]) not in _folded(path.read_text()):
            sys.exit(f"gen-ownership-data: {e['file']} no longer says {e['phrase']!r}; "
                     "check what the page claims and update PINNED")
        out[e["name"]] = dict(e)
    for key, rel in ALLOC_BOUND.items():
        path = root / rel
        if not path.exists():
            sys.exit(f"gen-ownership-data: {rel} is gone; the page points at the alloc_bound {key}")
    if ALLOC_BOUND_PHRASE not in (root / ALLOC_BOUND["todo"]).read_text():
        sys.exit(f"gen-ownership-data: {ALLOC_BOUND['todo']} no longer mentions {ALLOC_BOUND_PHRASE}")
    out["alloc_bound"] = dict(ALLOC_BOUND)
    return out


# Chosen for legibility, and stated on the page as such.
SIM = {"seed": 20261106, "visit_s": 0.12, "hold_s": 0.35}


# ── inputs ─────────────────────────────────────────────────────────────────────

def input_files(root):
    """The fixtures, the prose the pinned phrases live in, and this script.

    Only the `.march` fixtures count: compiling one in place leaves a gitignored `.ll`
    beside it, and a sha that swept those in would match only the machine that made it.
    """
    root = Path(root)
    return (sorted((root / "docs" / "assets" / "explainer" / "ownership").rglob("*.march"))
            + sorted({root / e["file"] for e in PINNED} | {root / p for p in ALLOC_BOUND.values()})
            + [root / "scripts" / "gen-ownership-data.py"])


def inputs_sha256(root):
    h = hashlib.sha256()
    for f in input_files(root):
        h.update(str(f.relative_to(root)).encode() + b"\0" + f.read_bytes() + b"\0")
    return h.hexdigest()


def check_inputs(data_path, root):
    data = json.loads(Path(data_path).read_text())
    return data.get("generated", {}).get("inputs_sha256") == inputs_sha256(root)


# ── running the compiler ───────────────────────────────────────────────────────

class Workspace:
    """A scratch directory with a private HOME, so no cache of the caller's shapes an
    output, and one fresh subdirectory per compiler run."""

    def __init__(self, directory, march):
        self.dir = Path(directory)
        self.march = march
        (self.dir / "home").mkdir()
        self.env = dict(os.environ, HOME=str(self.dir / "home"))
        for k in ("MARCH_LIB_PATH", "MARCH_BIN", "MARCH_TRACE_GC"):
            self.env.pop(k, None)
        self.n = 0

    def fresh(self, name):
        self.n += 1
        d = self.dir / f"{self.n:02d}-{name}"
        d.mkdir()
        (d / f"{name}.march").write_text((PROGRAMS / f"{name}.march").read_text())
        return d

    def run(self, args, cwd, env=None):
        """(exit code, stdout, stderr), each with this workspace's paths removed."""
        p = subprocess.run(args, cwd=cwd, env=dict(self.env, **(env or {})), stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=600)
        return p.returncode, self.scrub(p.stdout), self.scrub(p.stderr)

    def march_run(self, args, cwd):
        rc, out, err = self.run([self.march] + args, cwd)
        return rc, out + err

    def scrub(self, text):
        real = os.path.realpath(self.dir)
        for prefix in sorted({str(self.dir), real}, key=len, reverse=True):
            text = re.sub(re.escape(prefix) + r"/\d\d-[\w-]+/", "", text).replace(prefix + "/", "")
        return text


def must(rc, out, what, want=0):
    if rc != want:
        sys.exit(f"gen-ownership-data: {what} exited {rc}, expected {want}:\n{out}")
    return out


def trace(ws, name):
    """Compile `name` with the RC trace on, run it with MARCH_TRACE_GC=1 in its own
    directory, and fold the trace. Returns (the program's stdout, per-site counts)."""
    d = ws.fresh(name)
    rc, out = ws.march_run(["--rc-trace", "--compile", "-o", "bin", f"{name}.march"], d)
    must(rc, out, f"march --rc-trace --compile {name}.march")
    rc, stdout, stderr = ws.run([str(d / "bin")], d, {"MARCH_TRACE_GC": "1"})
    must(rc, stdout + stderr, f"./{name}")
    gc = d / "trace" / "gc"
    sites = json.loads((gc / "sites.json").read_text())
    per_site = fold_trace((gc / "gc.jsonl").read_text().splitlines(), sites)
    return stdout.strip(), per_site


def run_trees(ws):
    out = {}
    for name in RUNS:
        source = (PROGRAMS / f"{name}.march").read_text()
        d = ws.fresh(name)
        rc, text = ws.march_run(["--why-copies", f"{name}.march"], d)
        why = must(rc, text, f"march --why-copies {name}.march")
        why = strip_warnings(why)
        output, per_site = trace(ws, name)
        entry = {"excerpt": excerpt(source, EXCERPTS[name]), "why_copies": why, "exit": rc,
                 "headline": base.headline(why), "output": output}
        entry.update(trace_facts(per_site))
        out[name] = entry
    return out


def run_linear(ws):
    out = {}
    for key, name in LINEAR.items():
        source = (PROGRAMS / f"{name}.march").read_text()
        lines = excerpt_lines(source, EXCERPTS[name])
        text = excerpt(source, EXCERPTS[name])
        d = ws.fresh(name)
        rc, output = ws.march_run(["--check", f"{name}.march"], d)
        output = strip_warnings(output)
        kind, binder, uses = token_lines(text)
        verdict = key.replace("affine_", "")
        entry = {"excerpt": text, "exit": rc, "kind": kind, "binder": binder, "uses": uses, "verdict": verdict}
        if verdict == "ok":
            must(rc, output, f"march --check {name}.march")
        else:
            must(rc, output, f"march --check {name}.march", want=1)
            entry.update({"output": output, "headline": base.headline(output), "slug": slug_of(output),
                          "at": excerpt_line_of(lines, points_at(output))})
            if entry["at"] is None:
                sys.exit(f"gen-ownership-data: the diagnostic for {name} points outside its excerpt:\n{output}")
        out[key] = entry
    return out


def candidate(ws):
    """The `no_alloc_candidate` hint `--report-contracts` prints for the owned program."""
    d = ws.fresh("owned")
    rc, text = ws.march_run(["--compile", "--report-contracts", "-o", "bin", "owned.march"], d)
    must(rc, text, "march --compile --report-contracts owned.march")
    hints = [json.loads(l) for l in text.splitlines() if l.startswith("{")]
    hint = next((h for h in hints if h.get("code") == "no_alloc_candidate" and "`inc_leaves`" in h["message"]), None)
    if hint is None:
        sys.exit(f"gen-ownership-data: --report-contracts named no no_alloc candidate for inc_leaves:\n{text}")
    return {"code": hint["code"], "message": hint["message"], "fix": hint["fix"]["text"]}


def run_contracts(ws):
    out = {"candidate": candidate(ws)}
    for key, name in CONTRACTS.items():
        source = (PROGRAMS / f"{name}.march").read_text()
        d = ws.fresh(name)
        rc, output = ws.march_run(["--compile", "-o", "bin", f"{name}.march"], d)
        output = strip_warnings(output)
        entry = {"excerpt": excerpt(source, EXCERPTS[name]), "exit": rc}
        if key in ("bare", "boxed"):
            must(rc, output, f"march --compile {name}.march", want=1)
            entry.update({"output": output, "headline": base.headline(output), "reason": reason_of(output)})
        else:
            must(rc, output, f"march --compile {name}.march")
        if key == "caller":
            _, per_site = trace(ws, name)
            facts = trace_facts(per_site)
            entry["allocs"] = {"inc_leaves": facts["allocs"]["inc_leaves"]}
            # The cells of the tree `main` builds, counted in its source: `main` also
            # allocates the console operation's `Ok(())` results (println returns
            # Result((), CapError)), so its allocation count is not the tree's size.
            entry["tree_cells"] = entry["excerpt"].count("Leaf(") + entry["excerpt"].count("Node(")
        out[key] = entry
    return out


# ── the data file ──────────────────────────────────────────────────────────────

def build(march):
    with tempfile.TemporaryDirectory() as d:
        ws = Workspace(d, march)
        rc, version = ws.march_run(["--version"], ws.dir)
        version = must(rc, version, "march --version").splitlines()[0].strip()
        runs = run_trees(ws)
        linear = run_linear(ws)
        contracts = run_contracts(ws)
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                            capture_output=True, text=True).stdout.strip()
    return {
        "generated": {"commit": commit, "date": datetime.date.today().isoformat(),
                      "compiler": version, "inputs_sha256": inputs_sha256(ROOT)},
        "tree": TREE,
        "runs": runs,
        "linear": linear,
        "contracts": contracts,
        "pinned": pinned_facts(ROOT),
        "sim": SIM,
    }


def main(argv):
    if "--check-inputs" in argv:
        if not DATA.exists() or not check_inputs(DATA, ROOT):
            print("ownership data is stale: docs/assets/explainer/ownership, a pinned spec file or "
                  "scripts/gen-ownership-data.py changed; run scripts/gen-ownership-data.py")
            return 1
        return 0
    data = build(base.march_bin())
    if "--check" in argv:
        old = base._comparable(json.loads(DATA.read_text())) if DATA.exists() else ""
        new = base._comparable(data)
        if old != new:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                                       "docs/_data/ownership.json", "regenerated"))
            print("ownership data differs from a fresh run; run scripts/gen-ownership-data.py")
            return 1
        return 0
    DATA.parent.mkdir(parents=True, exist_ok=True)
    DATA.write_text(base.render(data))
    print(f"wrote {DATA.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
