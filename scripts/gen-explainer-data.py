#!/usr/bin/env python3
"""gen-explainer-data.py: write docs/_data/explainer.json from the real compiler.

docs/protocol-to-cluster.md is a hand-written page that follows examples/lab_app from its
`protocol Order` to a running cluster. Every number, code excerpt and diagnostic on it
comes from docs/_data/explainer.json, which this script writes: Jekyll renders the values
into the page (`site.data.explainer`), and the page's scripts read the same data. Nothing
on the page is typed in by hand, so a compiler change shows up as a diff of the data file.

    scripts/gen-explainer-data.py                 regenerate the data file
    scripts/gen-explainer-data.py --check         exit 1 if a fresh run would differ
    scripts/gen-explainer-data.py --check-inputs  exit 1 if the lab app, its topology or a
                                                  wrong program changed since the data was
                                                  generated (needs no compiler; doc-lint
                                                  Check H runs this)

The compiler is $MARCH_BIN, or _build/default/bin/main.exe. Every compiler run happens in
a fresh directory under a private HOME, so no cache shapes the output.

Design: specs/2026-11-05-distributed-explainer-design.md.
"""
import datetime
import difflib
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "docs" / "_data" / "explainer.json"
LAB_APP = ROOT / "examples" / "lab_app" / "src" / "lab_app.march"
PROTOCOL = "Order"


# ── the Order facts ────────────────────────────────────────────────────────────

def order_source(path):
    """The lines of `protocol Order`, from `@[endpoints]` to its closing `end`, with the
    common leading indent removed."""
    lines = Path(path).read_text().splitlines()
    head = next(i for i, l in enumerate(lines) if l.strip() == f"protocol {PROTOCOL} do")
    start = head - 1 if lines[head - 1].strip() == "@[endpoints]" else head
    indent = len(lines[head]) - len(lines[head].lstrip())
    end = next(i for i in range(head + 1, len(lines))
               if lines[i].strip() == "end" and len(lines[i]) - len(lines[i].lstrip()) == indent)
    return [l[indent:] for l in lines[start:end + 1]]


def _tags(steps, seen):
    """Message tags in first-appearance order."""
    for s in steps:
        if isinstance(s, str):
            continue
        if "msg" in s:
            if s["msg"]["tag"] not in seen:
                seen.append(s["msg"]["tag"])
        elif "loop" in s:
            _tags(s["loop"], seen)
        elif "choose" in s:
            for b in s["choose"]["branches"]:
                _tags(b["steps"], seen)
    return seen


def _name(decl):
    n = decl.get("name")
    return n.get("txt") if isinstance(n, dict) else n


def _state_types(module):
    """A role module's conversation states: its always-linear types named `S_…`, in
    declaration order. (Its other always-linear type, `Parked_<Role>`, is the token for a
    session parked inside an actor.)"""
    return [_name(x) for x in module["decls"]
            if x["kind"] == "DAlwaysLinearType" and (_name(x) or "").startswith("S_")]


def _step_label(state_type):
    """`S_send_Want` -> "send Want"; `S_offer_have_out` -> "offer have/out"; `S_end` -> "end"."""
    parts = state_type.split("_")[1:]
    if parts == ["end"]:
        return "end"
    verb, rest = parts[0], parts[1:]
    return verb + " " + ("/".join(rest) if verb in ("choose", "offer") else "_".join(rest))


def strips(core_ast):
    """Each role's steps in order, read off the state types the compiler generated for it:
    the strip a card draws beside the code is the role's linear types, one per step."""
    out = {}
    for d in core_ast["module"]["decls"]:
        if d.get("kind") == "DMod" and d["name"]["txt"].startswith(PROTOCOL + "_"):
            states = _state_types(d)
            if states:
                out[d["name"]["txt"][len(PROTOCOL) + 1:]] = [_step_label(t) for t in states]
    return out


def excerpts(lab_app_path):
    """Lines of the lab app the page quotes."""
    lines = Path(lab_app_path).read_text().splitlines()
    stock = next(l.strip() for l in lines if l.strip().startswith("fn stock("))
    # The Ledger actor's head: the comment block above it, down to its `init` line.
    actor = next(i for i, l in enumerate(lines) if l.strip() == "actor LedgerActor do")
    first = actor
    while first > 0 and lines[first - 1].strip().startswith("--"):
        first -= 1
    last = next(i for i in range(actor, len(lines)) if lines[i].strip().startswith("init("))
    indent = len(lines[actor]) - len(lines[actor].lstrip())
    return {"stock_signature": stock[:-3] if stock.endswith(" do") else stock,
            "ledger_actor": "\n".join(l[indent:] for l in lines[first:last + 1]) + "\n"}


def order_facts(core_ast, protocol_record):
    """What the compiler generated for the protocol: one entry per `Order_*` module with
    its linear state types and functions, the totals, and the protocol's fingerprint,
    roles and message tags."""
    modules = []
    for d in core_ast["module"]["decls"]:
        if d.get("kind") == "DMod" and d["name"]["txt"].startswith(PROTOCOL + "_"):
            kinds = [x["kind"] for x in d["decls"]]
            modules.append({"name": d["name"]["txt"],
                            "linear_states": kinds.count("DAlwaysLinearType"),
                            "states": _state_types(d),
                            "functions": kinds.count("DFn")})
    cur = protocol_record["current"]
    return {
        "modules": modules,
        "linear_states": sum(m["linear_states"] for m in modules),
        "conversation_states": sum(len(m["states"]) for m in modules),
        "functions": sum(m["functions"] for m in modules),
        "fingerprint": cur["fingerprint"],
        "roles": cur["roles"],
        "tags": _tags(cur["steps"], []),
    }


# ── the state map ──────────────────────────────────────────────────────────────
#
# Chapter 1 draws one cell for every combination of the roles' positions and lights the
# cells the protocol can actually reach. A role's positions are the states of its local
# view (its projection); reachability is asynchronous, as the runtime is: a role may have
# sent before its peer has received. A message in flight does not get a cell of its own.

def project(steps, role):
    """One role's local view of the protocol, as an automaton:
    {"start": 0, "edges": {state: [(("send"|"recv", peer, tag), next_state)]}, "final": {states}}.
    States are numbered in first-visit order from the start."""
    parent = {}

    def find(x):
        while parent.get(x, x) != x:
            x = parent[x]
        return x

    counter = [0]
    raw = []   # (from_state, action, to_state), before states are merged

    def fresh():
        counter[0] += 1
        return counter[0]

    def walk(seq, cur, exits):
        """Walk `seq` from state `cur`; return the state after it, or None when control
        never falls out of the end (a `stop`, or a loop nothing leaves)."""
        for s in seq:
            if cur is None:
                return None
            if s == "stop":
                exits.append(cur)
                return None
            if "msg" in s:
                m = s["msg"]
                if m["from"] == role or m["to"] == role:
                    action = ("send", m["to"], m["tag"]) if m["from"] == role else ("recv", m["from"], m["tag"])
                    nxt = fresh()
                    raw.append((cur, action, nxt))
                    cur = nxt
            elif "choose" in s:
                ends = [walk(b["steps"], cur, exits) for b in s["choose"]["branches"]]
                live = [e for e in ends if e is not None]
                for e in live[1:]:
                    parent[find(e)] = find(live[0])
                cur = live[0] if live else None
            elif "loop" in s:
                loop_exits = []
                end = walk(s["loop"], cur, loop_exits)
                if end is not None:
                    parent[find(end)] = find(cur)      # the body's end is the loop's entry
                for e in loop_exits[1:]:
                    parent[find(e)] = find(loop_exits[0])
                cur = loop_exits[0] if loop_exits else None
        return cur

    top_exits = []
    last = walk(steps, 0, top_exits)
    finals = {find(x) for x in ([last] if last is not None else []) + top_exits}

    merged = {}
    for a, action, b in raw:
        edge = (action, find(b))
        if edge not in merged.setdefault(find(a), []):
            merged[find(a)].append(edge)

    number, order = {find(0): 0}, [find(0)]
    for s in order:                                   # first-visit order
        for _, t in merged.get(s, []):
            if t not in number:
                number[t] = len(number)
                order.append(t)
    return {"start": 0,
            "edges": {number[s]: [(a, number[t]) for a, t in es] for s, es in merged.items() if s in number},
            "final": {number[f] for f in finals if f in number}}


def _automaton_size(a):
    states = {a["start"]} | set(a["edges"]) | a["final"]
    for es in a["edges"].values():
        states |= {t for _, t in es}
    return len(states)


MAX_QUEUE = 8


def explore(steps, roles):
    """Every cell the protocol can reach, in the order a breadth-first run of the roles
    first visits them. Exits if a queue grows past MAX_QUEUE (the protocol is not bounded)."""
    autos = [project(steps, r) for r in roles]
    start = (tuple(a["start"] for a in autos), ())
    seen, frontier, cells = {start}, [start], []
    while frontier:
        nxt = []
        for states, queues in frontier:
            if list(states) not in cells:
                cells.append(list(states))
            q = dict(queues)
            for i, role in enumerate(roles):
                for (kind, peer, tag), target in autos[i]["edges"].get(states[i], []):
                    q2 = dict(q)
                    if kind == "send":
                        q2[(role, peer)] = q.get((role, peer), ()) + (tag,)
                        if len(q2[(role, peer)]) > MAX_QUEUE:
                            sys.exit(f"gen-explainer-data: {role} -> {peer} queue passes {MAX_QUEUE}: the protocol is not bounded")
                    else:
                        waiting = q.get((peer, role), ())
                        if not waiting or waiting[0] != tag:
                            continue
                        q2[(peer, role)] = waiting[1:]
                    new_states = states[:i] + (target,) + states[i + 1:]
                    config = (new_states, tuple(sorted((k, v) for k, v in q2.items() if v)))
                    if config not in seen:
                        seen.add(config)
                        nxt.append(config)
        frontier = nxt
    return {r: _automaton_size(a) for r, a in zip(roles, autos)}, cells


def reachable(steps, roles):
    """(states per role, the reachable cells sorted)."""
    axes, cells = explore(steps, roles)
    return axes, sorted(cells)


def state_map(steps, roles):
    axes, path = explore(steps, roles)
    total = 1
    for n in axes.values():
        total *= n
    return {"roles": list(roles), "axes": axes, "cells": total, "reachable": sorted(path), "path": path}


# ── timings, topology and the simulations' parameters ──────────────────────────

def _host(entry):
    h = entry["host"] if isinstance(entry, dict) else entry
    return h.split("@")[-1]


def topology_facts(toml_path, overlay_path):
    """Who runs what in the lab: the ingress host, the hosts that offer Stock, the hosts
    labelled `books` (one of which holds the Ledger), and the two roles' capacities."""
    import tomllib   # Python 3.11+; imported here so `--check-inputs` runs on older ones
    base = tomllib.loads(Path(toml_path).read_text())
    overlay = tomllib.loads(Path(overlay_path).read_text())
    roles = base["roles"]
    stock_pool = next(name for name, pool in base["pool"].items()
                      if f"{PROTOCOL}.Stock" in pool.get("serves", []))
    work = overlay["pool"][stock_pool]["hosts"]
    return {
        "ingress": _host(overlay["pool"]["ingress"]["hosts"][0]),
        "stock_hosts": [_host(h) for h in work],
        "books_hosts": [_host(h) for h in work if isinstance(h, dict) and "books" in h.get("labels", [])],
        "stock_capacity": roles[f"{PROTOCOL}.Stock"]["capacity"],
        "ledger_capacity": roles[f"{PROTOCOL}.Ledger"]["capacity"],
    }


# Values the docs state in prose. Each entry names the file and the exact phrase that
# states the value; if the phrase is gone, the value may have changed, and the generator
# refuses to carry the old number onto the page.
#
# These are the CLUSTER runtime's numbers. The lab app runs on cluster nodes, where the
# node itself (SWIM) is the only failure detector. The direct runner's session heartbeat
# (a ping every second, failure after 10 s of silence) does not apply there and is
# deliberately not here.
PINNED = [
    {"key": "swim_probe_s", "value": 1, "file": "specs/lang/clustering.md",
     "must_contain": "SWIM probes every 1 s"},
    {"key": "swim_ack_ms", "value": 500, "file": "specs/lang/clustering.md",
     "must_contain": "waits 500 ms for an ack"},
    {"key": "suspect_s", "value": 3, "file": "specs/lang/clustering.md",
     "must_contain": "3 s for a suspect to refute"},
    {"key": "settle_s", "value": 15, "file": "docs/topology.md",
     "must_contain": "`MARCH_PLACEMENT_SETTLE_MS` (default 15000)"},
]


def pinned_facts(root):
    """The timings the page shows: the pinned values above, plus the drain deadlines read
    from the lab app's topology."""
    root = Path(root)
    out = {}
    for e in PINNED:
        path = root / e["file"]
        if not path.exists() or e["must_contain"] not in path.read_text():
            sys.exit(f"gen-explainer-data: pinned fact {e['key']} = {e['value']}: "
                     f"{e['file']} no longer says {e['must_contain']!r}; check the value and update PINNED")
        out[e["key"]] = e["value"]
    import tomllib
    drain = tomllib.loads((root / "examples/lab_app/topology.toml").read_text())["drain"]
    out["drain_soft_ms"] = drain["soft_ms"]
    out["drain_hard_ms"] = drain["hard_ms"]
    return out


LAB_NOTE = "specs/progress/2026-10-05-multi-host-lab.md"


def lab_run(root):
    """The one recorded run of the multi-host lab, read from its progress note. The lab
    runs on demand, not in CI, so the page states when the number was measured, and that
    the scenario it comes from did not pass: the Ledger moved in 1 s, but the returning
    host took the role back at once and sessions stopped (bugs since fixed, and guarded
    by the two-node scenario `topology_rejoin`)."""
    path = Path(root) / LAB_NOTE
    text = path.read_text() if path.exists() else ""
    for phrase in ("## Results (2026-10-05, main at 53d66f068",
                   "XFAIL failover: the Ledger moved lab-4 -> lab-3 in 1 s with no session failed"):
        if phrase not in text:
            sys.exit(f"gen-explainer-data: {LAB_NOTE} no longer says {phrase!r}; "
                     "check the lab's recorded results and update lab_run")
    return {"date": "2026-10-05", "commit": "53d66f068", "failover_s": 1,
            "failover_result": "expected-fail", "source": LAB_NOTE}


# Chosen for legibility, not measured, and stated on the page as such: the lab's own
# traffic is one session every one to two seconds, at which the cluster view would be
# nearly empty and no node could ever be full.
SIM = {"seed": 20261105, "load_per_s": 14, "session_s": [1.2, 2.8], "restart_s": 1,
       # one actor and its mailbox: arrivals keep pace with handling, so a short queue stays visible
       "mailbox": {"arrival_s": 0.45, "service_s": 0.45, "migrate_s": 1.2, "backlog": 7,
                   "parked": 12, "restart_s": 2.5}}


# ── inputs ─────────────────────────────────────────────────────────────────────

def input_files(root):
    """Every file the data is read from, apart from the compiler itself and the prose
    the pinned facts quote: the lab app, its topology, and the wrong programs."""
    root = Path(root)
    lab = root / "examples" / "lab_app"
    return ([lab / "src" / "lab_app.march", lab / "topology.toml", lab / "topology.lab.toml"]
            + sorted((root / "docs" / "assets" / "explainer" / "programs").glob("*.march")))


def inputs_sha256(root):
    h = hashlib.sha256()
    for f in input_files(root):
        h.update(str(f.relative_to(root)).encode() + b"\0" + f.read_bytes() + b"\0")
    return h.hexdigest()


def check_inputs(data_path, root):
    """True when the data file was generated from the inputs as they are now."""
    data = json.loads(Path(data_path).read_text())
    return data.get("generated", {}).get("inputs_sha256") == inputs_sha256(root)


# ── running the compiler ───────────────────────────────────────────────────────

def march_bin():
    exe = os.environ.get("MARCH_BIN") or str(ROOT / "_build" / "default" / "bin" / "main.exe")
    if not Path(exe).exists():
        sys.exit(f"gen-explainer-data: no compiler at {exe}; run `dune build --root . bin/main.exe` or set MARCH_BIN")
    return exe


def run_march(march, args, cwd):
    """One compiler run from `cwd` under a private HOME. Returns (exit code, stdout, stderr)."""
    env = dict(os.environ, HOME=str(Path(cwd) / "home"))
    p = subprocess.run([march] + args, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                       capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def compiler_outputs(march):
    """The lab app's core AST and its protocol record, from two fresh compiler runs."""
    with tempfile.TemporaryDirectory() as d:
        rc, out, err = run_march(march, ["--emit-core-ast", str(LAB_APP)], d)
        if rc != 0:
            sys.exit(f"gen-explainer-data: --emit-core-ast failed:\n{err}")
        core = json.loads(out)
    with tempfile.TemporaryDirectory() as d:
        protos = Path(d) / "protos"
        protos.mkdir()
        rc, out, err = run_march(march, ["--check", "--emit-protocols", str(protos), str(LAB_APP)], d)
        if rc != 0:
            sys.exit(f"gen-explainer-data: --emit-protocols failed:\n{out}{err}")
        record = json.loads((protos / f"{PROTOCOL}.json").read_text())
    return core, record


# ── the wrong programs of chapter 1 ────────────────────────────────────────────

PROGRAMS = ROOT / "docs" / "assets" / "explainer" / "programs"

# Where each wrong program's role stands, on the state map, when it makes its wrong move
# (role order Shop, Stock, Ledger; positions are `project`'s state numbers). Each is a cell
# the protocol reaches: the map marks the point at which the compiler stops the program.
PROGRAM_CELLS = {
    "skip_step": [1, 1, 0],            # Stock has received Want and must choose
    "offer_misses_branch": [1, 3, 0],  # Stock has chosen `out`; Shop has no handler for it
    "send_out_of_turn": [0, 0, 0],     # nothing has happened yet; Ledger must wait
}


def headline(output):
    """The diagnostic's message line: the first non-empty line after the `-- KIND ---` header."""
    lines = [l for l in output.splitlines() if l.strip()]
    body = [l for l in lines if not l.startswith("-- ")]
    return body[0].strip() if body else ""


def role_body(source):
    """The part of a wrong program a card shows: what lies between the protocol and
    `fn main`, without its indent. The protocol itself is already on the page."""
    lines = source.splitlines()
    head = next(i for i, l in enumerate(lines) if l.strip() == f"protocol {PROTOCOL} do")
    indent = len(lines[head]) - len(lines[head].lstrip())
    end = next(i for i in range(head + 1, len(lines))
               if lines[i].strip() == "end" and len(lines[i]) - len(lines[i].lstrip()) == indent)
    stop = next(i for i in range(end + 1, len(lines)) if lines[i].strip().startswith("fn main"))
    body = [l[indent:] for l in lines[end + 1:stop]]
    return "\n".join(body).strip("\n") + "\n"


def run_programs(directory, march):
    """`march --check` on every program in `directory`, each from its own fresh directory
    under a private HOME, so the header names a bare file and no cache shapes the output."""
    out = {}
    for path in sorted(Path(directory).glob("*.march")):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / path.name).write_text(path.read_text())
            rc, stdout, stderr = run_march(march, ["--check", path.name], d)
        text = (stdout + stderr).rstrip() + "\n"
        out[path.stem] = {"source": path.read_text(), "output": text, "exit": rc,
                          "headline": headline(text), "cell": PROGRAM_CELLS.get(path.stem),
                          "body": role_body(path.read_text())}
    return out


# ── the data file ──────────────────────────────────────────────────────────────

def build(march):
    core, record = compiler_outputs(march)
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                            capture_output=True, text=True).stdout.strip()
    order = {"source": order_source(LAB_APP)}
    order.update(order_facts(core, record))
    order["strips"] = strips(core)
    return {
        "generated": {"commit": commit, "date": datetime.date.today().isoformat(),
                      "inputs_sha256": inputs_sha256(ROOT)},
        "order": order,
        "state_map": state_map(record["current"]["steps"], record["current"]["roles"]),
        "timings": pinned_facts(ROOT),
        "topology": topology_facts(ROOT / "examples/lab_app/topology.toml",
                                   ROOT / "examples/lab_app/topology.lab.toml"),
        "sim": SIM,
        "lab_run": lab_run(ROOT),
        "programs": run_programs(PROGRAMS, march),
        "excerpts": excerpts(LAB_APP),
    }


def render(data):
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def _comparable(data):
    """The data without the two fields that change on every run."""
    d = json.loads(json.dumps(data))
    d.get("generated", {}).pop("date", None)
    d.get("generated", {}).pop("commit", None)
    return render(d)


def main(argv):
    if "--check-inputs" in argv:
        if not DATA.exists() or not check_inputs(DATA, ROOT):
            print("explainer data is stale: examples/lab_app or docs/assets/explainer/programs changed; "
                  "run scripts/gen-explainer-data.py")
            return 1
        return 0
    data = build(march_bin())
    if "--check" in argv:
        old = _comparable(json.loads(DATA.read_text())) if DATA.exists() else ""
        new = _comparable(data)
        if old != new:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                                       "docs/_data/explainer.json", "regenerated"))
            print("explainer data differs from a fresh run; run scripts/gen-explainer-data.py")
            return 1
        return 0
    DATA.parent.mkdir(parents=True, exist_ok=True)
    DATA.write_text(render(data))
    print(f"wrote {DATA.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
