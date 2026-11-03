#!/usr/bin/env python3
"""Generate the stdlib sources the in-browser March reads.

Writes, into OUT_DIR (default docs/assets/):

  march_stdlib.js        window.marchStdlib[file] = source, for the files loaded at
                         startup: the interpreter REPL's CORE set (js/march_browser.ml)
                         plus the extra files the Tetris live compiler reads
                         (js/march_browser_compile.ml's browser_stdlib_files).
  march_stdlib_index.js  window.marchModuleIndex = {core, modules}: every stdlib module
                         with its file, the modules it references, and why it cannot
                         run in a browser (null if it can). The interpreter REPL uses it
                         to load modules on demand (marchModulesNeeded).
  stdlib/<file>.js       one per stdlib file, same assignment form, fetched on demand.

Design: specs/2026-10-14-browser-repl-modules-design.md.

Run from the project (worktree) root:  python3 scripts/gen-browser-stdlib.py [OUT_DIR]
scripts/build-browser-repl.sh passes a staging directory.
"""
import json
import os
import re
import sys

ROOT = os.getcwd()
STDLIB = os.path.join(ROOT, "stdlib")

# Loaded when the REPL starts, in this order (prelude first). Everything else loads
# on first use. Kept to what the REPL loaded before on-demand loading existed, minus
# random.march (it needs 63-bit Int; see UNAVAILABLE), so startup cost is unchanged.
CORE = [
    "prelude.march", "option.march", "result.march", "list.march",
    "task.march",
    "hamt.march", "map.march", "math.march", "string.march", "sort.march",
    "seq.march", "set.march", "array.march", "tuple.march", "char.march",
    "range.march", "enum.march", "json.march",
    "http.march", "http_transport.march", "http_client.march",
    "crypto.march", "deque.march", "vector_clock.march", "merkle.march",
    "crdt.march", "consistent_hash.march", "vault.march",
]

# Read at startup by the Tetris live compiler (js/march_browser_compile.ml), which
# loads its own fixed list from march_stdlib.js.
COMPILE_EXTRA = ["dom.march", "hash_map.march", "bytes.march", "random.march"]

# Modules that cannot work in a browser, and why. Whole-module only: a module that is
# mostly pure but has a few native helpers (Seq, Csv, Env, System) stays loadable and
# those helpers fail when called. Naming one of these in REPL input gives
# "<Module> isn't available in the browser REPL: <reason>" instead of evaluating.
FS = "it needs a file system"
NET = "it needs network sockets"
PROC = "it needs operating-system processes"
CLUSTER = "it needs the cluster runtime"
WIDE = "it needs 63-bit integers (the browser REPL's Int is 32-bit)"
UNAVAILABLE = {
    "File": FS, "Dir": FS,
    "Socket": NET, "Tls": NET, "HttpServer": NET, "WebSocket": NET,
    "ChannelSocket": NET, "ClusterConn": NET, "NetKernel": NET,
    "Process": PROC, "Signal": PROC,
    "Cluster": CLUSTER, "ClusterNode": CLUSTER, "ClusterAuth": CLUSTER,
    "ClusterLoad": CLUSTER, "SessionNode": CLUSTER, "Topology": CLUSTER,
    "Node": CLUSTER, "NodeCall": CLUSTER, "NodeRpc": CLUSTER, "NodeSend": CLUSTER,
    "RemoteCall": CLUSTER, "DistLink": CLUSTER, "DistSupervisor": CLUSTER,
    "Swim": CLUSTER, "SwimDriver": CLUSTER, "Membership": CLUSTER,
    "GlobalRegistry": CLUSTER, "PeerRegistry": CLUSTER, "PeerReader": CLUSTER,
    "Handshake": CLUSTER, "WorkDispatch": CLUSTER,
    # Each of these has an Int literal or arithmetic past 2^31 (DataFrame's FNV
    # offset, Random's 32-bit masks), so it fails to parse or misbehaves at 32 bits.
    "DataFrame": WIDE, "Msgpack": WIDE, "NetFrame": WIDE, "NodeQueue": WIDE,
    "Random": WIDE,
}

MOD_RE = re.compile(r"^(\s*)mod ([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*) do\s*$")
REF_RE = re.compile(r"\b([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)\.[A-Za-z_]")


def modules_in(src):
    """Every module a file declares, nested ones qualified (`mod A do mod B do` -> A.B)."""
    out, stack = [], []  # stack of (indent, qualified name)
    for line in src.splitlines():
        m = MOD_RE.match(line)
        if not m:
            continue
        indent = len(m.group(1))
        while stack and stack[-1][0] >= indent:
            stack.pop()
        name = ".".join([q for _, q in stack[-1:]] + [m.group(2)]) if stack else m.group(2)
        stack.append((indent, name))
        out.append(name)
    return out


def strip_comments(src):
    return "\n".join(line.split("--", 1)[0] for line in src.splitlines())


def resolve(ref, known):
    """Longest dotted prefix of `ref` that names a known module (Js.Dom.X -> Js.Dom)."""
    parts = ref.split(".")
    for n in range(len(parts), 0, -1):
        cand = ".".join(parts[:n])
        if cand in known:
            return cand
    return None


def js_assign(name, src):
    return "window.marchStdlib[%s] = %s;" % (json.dumps(name), json.dumps(src))


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "assets")
    files = sorted(f for f in os.listdir(STDLIB) if f.endswith(".march"))
    sources = {f: open(os.path.join(STDLIB, f), encoding="utf-8").read() for f in files}

    for f in CORE + COMPILE_EXTRA:
        if f not in sources:
            sys.exit("gen-browser-stdlib: %s is listed but stdlib/%s does not exist" % (f, f))

    file_of = {}
    for f in files:
        for mod in modules_in(sources[f]):
            file_of.setdefault(mod, f)
    missing = sorted(set(UNAVAILABLE) - set(file_of))
    if missing:
        sys.exit("gen-browser-stdlib: UNAVAILABLE names unknown modules: %s" % ", ".join(missing))

    modules = {}
    for mod, f in sorted(file_of.items()):
        refs = {resolve(r, file_of) for r in REF_RE.findall(strip_comments(sources[f]))}
        uses = sorted(r for r in refs if r and file_of[r] != f)
        modules[mod] = {"file": f, "uses": uses, "unavailable": UNAVAILABLE.get(mod)}
    index = {"core": CORE, "modules": modules}

    os.makedirs(os.path.join(out_dir, "stdlib"), exist_ok=True)
    startup = CORE + [f for f in COMPILE_EXTRA if f not in CORE]
    with open(os.path.join(out_dir, "march_stdlib.js"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(["window.marchStdlib = window.marchStdlib || {};"]
                           + [js_assign(f, sources[f]) for f in startup]) + "\n")
    with open(os.path.join(out_dir, "march_stdlib_index.js"), "w", encoding="utf-8") as fh:
        fh.write("window.marchModuleIndex = %s;\n" % json.dumps(index, indent=1, sort_keys=True))
    for f in files:
        with open(os.path.join(out_dir, "stdlib", f[:-len(".march")] + ".js"), "w",
                  encoding="utf-8") as fh:
            fh.write("window.marchStdlib = window.marchStdlib || {};\n"
                     + js_assign(f, sources[f]) + "\n")
    print("wrote %d startup files, %d modules indexed, %d per-file sources to %s"
          % (len(startup), len(modules), len(files), out_dir))


if __name__ == "__main__":
    main()
