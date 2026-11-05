#!/usr/bin/env python3
"""gen-explainer-data.py: write docs/_data/explainer.json from the real compiler.

docs/protocol-to-cluster.md is a hand-written page that follows examples/lab_app from its
`protocol Order` to a running cluster. Every number, code excerpt and diagnostic on it
comes from docs/_data/explainer.json, which this script writes: Jekyll renders the values
into the page (`site.data.explainer`), and the page's scripts read the same data. Nothing
on the page is typed in by hand, so a compiler change shows up as a diff of the data file.

    scripts/gen-explainer-data.py                 regenerate the data file
    scripts/gen-explainer-data.py --check         exit 1 if a fresh run would differ
    scripts/gen-explainer-data.py --check-inputs  exit 1 if examples/lab_app changed since
                                                  the data was generated (needs no compiler;
                                                  doc-lint Check H runs this)

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
                            "functions": kinds.count("DFn")})
    cur = protocol_record["current"]
    return {
        "modules": modules,
        "linear_states": sum(m["linear_states"] for m in modules),
        "functions": sum(m["functions"] for m in modules),
        "fingerprint": cur["fingerprint"],
        "roles": cur["roles"],
        "tags": _tags(cur["steps"], []),
    }


# ── inputs ─────────────────────────────────────────────────────────────────────

def lab_app_sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def check_inputs(data_path, lab_app_path):
    """True when the data file was generated from the lab app as it is now."""
    data = json.loads(Path(data_path).read_text())
    return data.get("generated", {}).get("lab_app_sha256") == lab_app_sha256(lab_app_path)


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


# ── the data file ──────────────────────────────────────────────────────────────

def build(march):
    core, record = compiler_outputs(march)
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                            capture_output=True, text=True).stdout.strip()
    order = {"source": order_source(LAB_APP)}
    order.update(order_facts(core, record))
    return {
        "generated": {"commit": commit, "date": datetime.date.today().isoformat(),
                      "lab_app_sha256": lab_app_sha256(LAB_APP)},
        "order": order,
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
        if not DATA.exists() or not check_inputs(DATA, LAB_APP):
            print("explainer data is stale: examples/lab_app changed; run scripts/gen-explainer-data.py")
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
