#!/usr/bin/env python3
"""gen-authority-data.py: write docs/_data/authority.json from the real compiler and forge.

docs/deploy-authority.md is the second scrolling explainer. It follows one dependency
update to examples/lab_app past every check between a pull request and a running node.
Every count, excerpt and tool message on it comes from docs/_data/authority.json, which
this script writes; nothing on the page is typed in by hand.

    scripts/gen-authority-data.py                 regenerate the data file
    scripts/gen-authority-data.py --check         exit 1 if a fresh run would differ
    scripts/gen-authority-data.py --check-inputs  exit 1 if the lab app or a fixture changed
                                                  since the data was generated (needs no
                                                  compiler; doc-lint Check H runs this)

The compiler is $MARCH_BIN or _build/default/bin/main.exe; forge is $FORGE_BIN or
_build/default/forge/bin/main.exe.

What it does, in a scratch directory under a private HOME:

  1. reads every module's declared capabilities from `march --emit-core-ast`;
  2. runs `march --check` on each wrong program in docs/assets/explainer/authority/programs/;
  3. copies the lab app, gives the copy one dependency (the `gauge` fixture, version 1.0),
     and replaces the one line of `Probe` that formats the health reading with a call to
     it. examples/lab_app itself has no dependency and is not changed;
  4. records the dependency's capabilities, exports the topology, generates the firewall;
  5. swaps in gauge 1.1, which opens a socket, and runs each check that notices:
     `forge deps`, the pools' derived capabilities, `forge deploy hot`, and `forge build`
     on a variant whose topology writes the work pool's capabilities down.

One thing is seeded rather than measured. `forge deploy hot` compares a pool's
capabilities with the record a completed deploy leaves in .forge/deploy/<env>/derived.json.
The script deploys nothing, so it writes that record itself, from the export in step 4.
"""
import datetime
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "docs" / "_data" / "authority.json"
LAB = ROOT / "examples" / "lab_app"
FIXTURES = ROOT / "docs" / "assets" / "explainer" / "authority"
ENV = "lab"
DEP = "gauge"

_spec = importlib.util.spec_from_file_location("gen_explainer_data", ROOT / "scripts" / "gen-explainer-data.py")
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)


# ── what a module may reach ────────────────────────────────────────────────────

# Capabilities that reach past the process: files, the network, other processes, C code,
# or the root capability, which is all of them.
OUTSIDE = ("IO.FileSystem", "IO.FileRead", "IO.FileWrite", "IO.Network", "IO.NetConnect",
           "IO.NetListen", "IO.WebSocket", "IO.Database", "IO.Process", "IO.Foreign")
CLASSES = ["none", "inside", "outside"]


def reach_class(needs):
    """"none": declares nothing. "outside": can reach a file, the network, a process or
    C code. "inside": anything else: the console, the clock, tasks, shared state, or a
    proof capability such as Session.Live, which carries no IO authority of its own (the
    page says "the process they run in, or a session they are handed")."""
    if not needs:
        return "none"
    for n in needs:
        if n == "IO" or any(n == o or n.startswith(o + ".") for o in OUTSIDE):
            return "outside"
    return "inside"


def source_modules(path):
    """The modules a source file declares, by `mod Name do`."""
    return re.findall(r"^\s*mod\s+(\w+)\s+do\s*$", Path(path).read_text(), flags=re.M)


def module_facts(module_caps, own_names):
    """One entry per module the program links, grouped by what it can reach."""
    mods = [{"name": m["module"], "needs": list(m.get("needs") or []),
             "cls": reach_class(m.get("needs") or []), "own": m["module"] in own_names}
            for m in module_caps]
    mods.sort(key=lambda m: (CLASSES.index(m["cls"]), m["name"]))
    return {"total": len(mods),
            "classes": {c: sum(1 for m in mods if m["cls"] == c) for c in CLASSES},
            "list": mods,
            "own": [m for m in mods if m["own"]]}


# ── the topology ───────────────────────────────────────────────────────────────

def file_lines(path):
    """A file without its comments and blank lines."""
    return [l.rstrip() for l in Path(path).read_text().splitlines()
            if l.strip() and not l.strip().startswith("#")]


def toml_excerpt(path):
    """A TOML file without its comments, one blank line between its tables."""
    out = []
    for l in file_lines(path):
        if l.startswith("[") and out:
            out.append("")
        out.append(l)
    return out


def firewall_rules(ufw_text):
    """`forge topology gen ufw` output -> {host: [{"from": host, "port": n}]}, the
    host-to-host rules only (ssh is open to anyone)."""
    out, host = {}, None
    for line in ufw_text.splitlines():
        m = re.match(r"# ==> ufw-(.+)\.sh <==", line)
        if m:
            host = m.group(1)
            out[host] = []
            continue
        m = re.match(r"ufw allow from (\S+) to any port (\d+) proto tcp", line)
        if m and host:
            out[host].append({"from": m.group(1), "port": int(m.group(2))})
    return out


def topology_facts(export, ufw_text):
    """Pools, hosts, roles and ports from `forge topology export --json`, and the
    firewall forge generates from the same file."""
    control_label = export["control"]["candidates"]
    pools = []
    for p in export["pools"]:
        d = export["derived"][p["name"]]
        pools.append({"name": p["name"], "serves": p["serves"], "initiates": d["initiates"],
                      "caps": d["caps"], "caps_source": d["source"],
                      "hosts": [{"name": h["host"].split("@")[-1], "labels": h["labels"]} for h in p["hosts"]]})
    rules = firewall_rules(ufw_text)
    cluster, control = export["cluster_port"], export["control"]["port"]
    return {
        "pools": pools,
        "roles": [{"name": r["name"], "role": r["role"], "capacity": r["capacity"], "place": r["place"]}
                  for r in export["roles"]],
        "cluster_port": cluster, "control_port": control,
        "control_hosts": [h["name"] for p in pools for h in p["hosts"] if control_label in h["labels"]],
        "firewall": rules,
        "cluster_rules": sum(1 for rs in rules.values() for r in rs if r["port"] == cluster),
        "control_rules": sum(1 for rs in rules.values() for r in rs if r["port"] == control),
    }


def pool_caps(export):
    return {name: d["caps"] for name, d in export["derived"].items()}


def added_caps(before, after):
    return {pool: [c for c in caps if c not in (before.get(pool) or [])] for pool, caps in after.items()}


# Lines the docs state in prose. If the phrase is gone the page must not go on quoting it.
PINNED = [
    {"key": "node_refusal", "file": "docs/hot-code-reload.md",
     "value": "FAILED Server.handle: ERR cap_policy IO.FileWrite — deploy rejected by node capability policy"},
    {"key": "policy_from_caps", "file": "docs/topology.md",
     "value": "from the pool's written `caps`, else the compiler's derived ones"},
    {"key": "sandbox_patched", "file": "specs/lang/capability-threat-model.md",
     "value": "the OS sandbox installed at startup still applies to patched code"},
]


def pinned_facts(root):
    out = {}
    for e in PINNED:
        path = Path(root) / e["file"]
        if not path.exists() or e["value"] not in path.read_text():
            sys.exit(f"gen-authority-data: {e['file']} no longer says {e['value']!r}; "
                     "check what the page claims and update PINNED")
        out[e["key"]] = e["value"]
    return out


# Chosen for legibility, and stated on the page as such.
SIM = {"seed": 20261106, "sessions_per_s": 2.2, "leg_s": 0.55, "suspect_s": 3}


# ── inputs ─────────────────────────────────────────────────────────────────────

def input_files(root):
    root = Path(root)
    lab = root / "examples" / "lab_app"
    fixtures = root / "docs" / "assets" / "explainer" / "authority"
    return ([lab / "src" / "lab_app.march", lab / "topology.toml", lab / "topology.lab.toml", lab / "forge.toml"]
            + sorted(p for p in fixtures.rglob("*") if p.is_file()))


def inputs_sha256(root):
    h = hashlib.sha256()
    for f in input_files(root):
        h.update(str(f.relative_to(root)).encode() + b"\0" + f.read_bytes() + b"\0")
    return h.hexdigest()


def check_inputs(data_path, root):
    data = json.loads(Path(data_path).read_text())
    return data.get("generated", {}).get("inputs_sha256") == inputs_sha256(root)


# ── running the tools ──────────────────────────────────────────────────────────

def forge_bin():
    exe = os.environ.get("FORGE_BIN") or str(ROOT / "_build" / "default" / "forge" / "bin" / "main.exe")
    if not Path(exe).exists():
        sys.exit(f"gen-authority-data: no forge at {exe}; run `dune build --root . forge/bin/main.exe` or set FORGE_BIN")
    return exe


class Workspace:
    """A scratch directory with `march` and `forge` on PATH (forge runs the compiler by
    name) and a private HOME, so no cache or key of the caller's shapes an output."""

    def __init__(self, directory, march, forge):
        self.dir = Path(directory)
        (self.dir / "bin").mkdir()
        (self.dir / "home").mkdir()
        for name, exe in (("march", march), ("forge", forge)):
            script = self.dir / "bin" / name
            script.write_text(f'#!/bin/sh\nexec "{exe}" "$@"\n')
            script.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.dir / "home"),
                        PATH=str(self.dir / "bin") + os.pathsep + os.environ.get("PATH", ""))
        for k in ("MARCH_LIB_PATH", "MARCH_BIN", "FORGE_BIN"):
            self.env.pop(k, None)

    def run(self, args, cwd, lib_path=None):
        """(exit code, stdout + stderr with this workspace's paths removed)."""
        env = dict(self.env, MARCH_LIB_PATH=str(lib_path)) if lib_path else self.env
        p = subprocess.run(args, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=600)
        return p.returncode, self.scrub(p.stdout + p.stderr)

    def scrub(self, text):
        real = os.path.realpath(self.dir)
        for prefix in sorted({str(self.dir), real}, key=len, reverse=True):
            text = text.replace(prefix + "/app/", "").replace(prefix + "/", "")
        return text


def must(rc, out, what, want=0):
    if rc != want:
        sys.exit(f"gen-authority-data: {what} exited {rc}, expected {want}:\n{out}")
    return out


# The one line of the lab app the dependency replaces: Probe formatting its reading.
PROBE_LINE = ('      let line = "live " ++ int_to_string(live_allocs()) ++ "\\nat " ++ '
              'int_to_string(unix_time_ms()) ++ "\\n"\n')
PROBE_CALL = "      let line = Gauge.line(live_allocs(), unix_time_ms())\n"


def use_dependency(app):
    src = app / "src" / "lab_app.march"
    text = src.read_text()
    if PROBE_LINE not in text:
        sys.exit("gen-authority-data: Probe no longer formats its reading on the line this script replaces; "
                 "update PROBE_LINE")
    src.write_text(text.replace(PROBE_LINE, PROBE_CALL))


def put_dependency(ws, version):
    dst = ws.dir / DEP
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(FIXTURES / f"{DEP}-{version}", dst)
    return (dst / "src" / f"{DEP}.march").read_text()


def export_topology(ws, app):
    rc, out = ws.run(["forge", "topology", "export", "--json", "--env", ENV], app)
    start = out.find("{")
    if rc != 0 or start < 0:
        sys.exit(f"gen-authority-data: forge topology export failed:\n{out}")
    export = json.loads(out[start:])
    for pool, d in export["derived"].items():
        if d.get("source") != "compiler" or d.get("caps") is None:
            sys.exit(f"gen-authority-data: pool {pool}'s capabilities were not derived by the compiler:\n{out[:start]}")
    return export


def lock_body(path):
    return "\n".join(file_lines(path)) + "\n"


def module_caps(ws, source, lib_path=None):
    rc, out = ws.run(["march", "--emit-core-ast", str(source)], Path(source).parent, lib_path)
    start = out.find("{")
    if rc != 0 or start < 0:
        sys.exit(f"gen-authority-data: --emit-core-ast failed:\n{out}")
    # diagnostics (hints) follow the JSON on stderr; the object is the first line group
    return json.JSONDecoder().raw_decode(out[start:])[0]["module_caps"]


def code_only(source):
    """A source file without its leading comment lines."""
    lines = source.splitlines()
    while lines and (lines[0].startswith("--") or not lines[0].strip()):
        lines.pop(0)
    return "\n".join(lines).rstrip("\n") + "\n"


def block(source, opener):
    """The block that starts on the first line beginning (after its indent) with
    `opener`, down to the `end` at the same indent, without that indent."""
    lines = source.splitlines()
    first = next(i for i, l in enumerate(lines) if l.strip().startswith(opener))
    indent = len(lines[first]) - len(lines[first].lstrip())
    last = next(i for i in range(first + 1, len(lines))
                if lines[i].strip() == "end" and len(lines[i]) - len(lines[i].lstrip()) == indent)
    return "\n".join(l[indent:] for l in lines[first:last + 1]) + "\n"


def module_head(source, name):
    """`mod NAME do` and the `needs` lines under it, without their indent."""
    lines = source.splitlines()
    first = next(i for i, l in enumerate(lines) if l.strip() == f"mod {name} do")
    indent = len(lines[first]) - len(lines[first].lstrip())
    out = [lines[first][indent:]]
    for l in lines[first + 1:]:
        if not l.strip().startswith("needs "):
            break
        out.append(l[indent:])
    return "\n".join(out) + "\n"


# The part of each wrong program a card shows.
PROGRAM_SHOWS = {"undeclared": "fn report", "ceiling": "fn main"}


def run_programs(ws):
    out = {}
    for path in sorted((FIXTURES / "programs").glob("*.march")):
        d = ws.dir / ("program-" + path.stem)
        d.mkdir()
        (d / path.name).write_text(path.read_text())
        rc, text = ws.run(["march", "--check", path.name], d)
        text = text.rstrip() + "\n"
        out[path.stem] = {"output": text, "exit": rc, "headline": base.headline(text),
                          "shown": block(path.read_text(), PROGRAM_SHOWS[path.stem])}
        if rc == 0:
            sys.exit(f"gen-authority-data: {path.name} is meant to be rejected and was accepted")
    return out


def dependency_story(ws):
    """Steps 3 to 5 of the module comment."""
    app = ws.dir / "app"
    shutil.copytree(LAB, app)
    v1 = put_dependency(ws, "1.0")
    must(*ws.run(["forge", "add", DEP, "--path", f"../{DEP}"], app), "forge add")
    use_dependency(app)
    must(*ws.run(["forge", "audit", "--record"], app), "forge audit --record")
    lock_before = lock_body(app / "forge.caps.lock")
    caps_v1 = module_caps(ws, app / "src" / "lab_app.march", ws.dir / DEP / "src")
    before = export_topology(ws, app)
    ufw = must(*ws.run(["forge", "topology", "gen", "ufw", "--env", ENV], app), "forge topology gen ufw")

    v2 = put_dependency(ws, "1.1")
    refused_rc, refused = ws.run(["forge", "deps"], app)
    if refused_rc == 0 or "now ALSO needs" not in refused:
        sys.exit(f"gen-authority-data: forge deps did not refuse the update:\n{refused}")
    must(*ws.run(["forge", "deps", "--accept-caps"], app), "forge deps --accept-caps")
    lock_after = lock_body(app / "forge.caps.lock")
    caps_v2 = module_caps(ws, app / "src" / "lab_app.march", ws.dir / DEP / "src")
    after = export_topology(ws, app)

    # A variant whose topology writes the work pool's capabilities down, as they were
    # before the update: there the compiler itself refuses the build.
    written = ws.dir / "written" / "app"
    written.parent.mkdir()
    shutil.copytree(app, written, ignore=shutil.ignore_patterns(".forge", ".march"))
    shutil.copytree(ws.dir / DEP, written.parent / DEP)
    topo = written / "topology.toml"
    anchor = 'start  = "LabApp.Work.start"\n'
    if anchor not in topo.read_text():
        sys.exit("gen-authority-data: the work pool's `start` line moved; update the anchor")
    caps_line = "caps   = [" + ", ".join(f'"{c}"' for c in pool_caps(before)["work"]) + "]"
    topo.write_text(topo.read_text().replace(anchor, anchor + caps_line + "\n"))
    wrc, wout = ws.run(["forge", "build"], written)
    werr = [l.split(": ", 1)[1] if ".forge/topology.json: " in l else l
            for l in wout.splitlines() if "error: topology:" in l]
    if wrc == 0 or not werr:
        sys.exit(f"gen-authority-data: a pool with written caps accepted the update:\n{wout}")

    # The record a completed deploy leaves, seeded from the export before the update.
    record = app / ".forge" / "deploy" / ENV / "derived.json"
    record.parent.mkdir(parents=True)
    record.write_text(json.dumps({p: {"caps": d["caps"], "initiates": d["initiates"]}
                                  for p, d in before["derived"].items()}))
    hot_rc, hot = ws.run(["forge", "deploy", "hot", "--env", ENV], app)
    if hot_rc == 0 or "would widen pool" not in hot:
        sys.exit(f"gen-authority-data: forge deploy hot did not stop at the widening:\n{hot}")
    grant = [c for caps in added_caps(pool_caps(before), pool_caps(after)).values() for c in caps]
    grant = sorted(set(grant))
    flags = [a for c in grant for a in ("--grant-cap", c)]
    _, granted = ws.run(["forge", "deploy", "hot", "--env", ENV] + flags, app)
    granted_lines = [l.strip() for l in granted.splitlines() if l.strip().startswith("granted widening:")]
    if not granted_lines or "would widen pool" in granted:
        sys.exit(f"gen-authority-data: --grant-cap did not pass the widening gate:\n{granted}")

    def dep_needs(caps):
        return next((m.get("needs") or [] for m in caps if m["module"] == "Gauge"), None)

    return {
        "dep": {
            "name": DEP,
            "v1": {"version": "1.0", "code": code_only(v1), "needs": dep_needs(caps_v1)},
            "v2": {"version": "1.1", "code": code_only(v2), "needs": dep_needs(caps_v2)},
            "call": PROBE_CALL.strip(), "lock_before": lock_before,
            "refused": {"output": refused, "exit": refused_rc},
            "lock_after": lock_after,
        },
        "topology": topology_facts(before, ufw),
        "widening": {
            "before": pool_caps(before), "after": pool_caps(after),
            "added": added_caps(pool_caps(before), pool_caps(after)),
            "refusal": {"output": hot, "exit": hot_rc},
            "grant_flags": " ".join(flags), "granted": granted_lines,
            "written": {"caps_line": caps_line.replace("caps   =", "caps ="), "output": "\n".join(werr) + "\n", "exit": wrc},
        },
    }


# ── the data file ──────────────────────────────────────────────────────────────

def build(march, forge):
    with tempfile.TemporaryDirectory() as d:
        ws = Workspace(d, march, forge)
        own = set(source_modules(LAB / "src" / "lab_app.march"))
        probe = ws.dir / "probe"
        shutil.copytree(LAB, probe)
        modules = module_facts(module_caps(ws, probe / "src" / "lab_app.march"), own)
        programs = run_programs(ws)
        story = dependency_story(ws)
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                            capture_output=True, text=True).stdout.strip()
    data = {
        "generated": {"commit": commit, "date": datetime.date.today().isoformat(),
                      "inputs_sha256": inputs_sha256(ROOT)},
        "modules": modules,
        "programs": programs,
        "topology_file": toml_excerpt(LAB / "topology.toml"),
        "excerpts": {"probe": module_head((LAB / "src" / "lab_app.march").read_text(), "Probe")},
        "pinned": pinned_facts(ROOT),
        "sim": SIM,
    }
    data.update(story)
    return data


def main(argv):
    if "--check-inputs" in argv:
        if not DATA.exists() or not check_inputs(DATA, ROOT):
            print("authority data is stale: examples/lab_app or docs/assets/explainer/authority changed; "
                  "run scripts/gen-authority-data.py")
            return 1
        return 0
    data = build(base.march_bin(), forge_bin())
    if "--check" in argv:
        import difflib
        old = base._comparable(json.loads(DATA.read_text())) if DATA.exists() else ""
        new = base._comparable(data)
        if old != new:
            sys.stdout.writelines(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                                       "docs/_data/authority.json", "regenerated"))
            print("authority data differs from a fresh run; run scripts/gen-authority-data.py")
            return 1
        return 0
    DATA.parent.mkdir(parents=True, exist_ok=True)
    DATA.write_text(base.render(data))
    print(f"wrote {DATA.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
