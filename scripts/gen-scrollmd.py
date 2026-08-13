#!/usr/bin/env python3
"""Generate runnable Scroll notebooks (.scrollmd) from opted-in docs pages.

A docs page opts in with `scrollmd: true` in its Jekyll front-matter. Because a
.scrollmd file is just Markdown with fenced ```march code cells — which is what
our docs already are — conversion is mostly a transform. See
specs/2026-06-23-scrollmd-doc-downloads-design.md for the full design.

Two modes:

  --emit  (default)   Convert each opted-in page to docs/downloads/<slug>.scrollmd.
                      Pure Python; no March toolchain needed (runs in the Pages job).

  --check             Verify each opted-in notebook compiles THE WAY SCROLL RUNS IT:
                      tokenize cells exactly as Scroll's parse_cells does, assemble
                      the `mod NotebookRunner do … fn main() … end end` program that
                      Scroll's generate_runner produces, and run `march --check` on
                      it. Needs a compiler: set MARCH_BIN (default "march"); it may
                      be a multi-word command, e.g. MARCH_BIN="dune exec --root . march --".

Usage:
  scripts/gen-scrollmd.py --emit  [--out docs/downloads] [docs ...]
  scripts/gen-scrollmd.py --check [docs ...]
If no paths are given, scans docs/ for pages with `scrollmd: true`.
"""

import os
import re
import sys
import shlex
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DOCS = REPO / "docs"
SITE = "https://march-lang.org"

SKIP_MARKER = re.compile(r"^\s*<!--\s*scroll:skip\s*-->\s*$")
RUN_MARKER = re.compile(r"^\s*<!--\s*scroll:run\s+(.*?)\s*-->\s*$")
FENCE_MARCH = "```march"
FENCE_STATIC = "```march-static"


# ── Front-matter ──────────────────────────────────────────────────────────────

def split_front_matter(text):
    """Return (meta: dict, body: str). Flat `key: value` front-matter only."""
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    fm = text[3:end].strip("\n")
    body = text[end + 4:].lstrip("\n")
    meta = {}
    for line in fm.splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip().strip('"').strip("'")
    return meta, body


def is_opted_in(meta):
    return str(meta.get("scrollmd", "")).lower() == "true"


# ── Link rewriting (permalink-relative → absolute) ─────────────────────────────

def rewrite_links(body, permalink):
    body = body.replace("{{ site.baseurl }}", SITE).replace("{{site.baseurl}}", SITE)
    page_url = SITE + permalink
    base = permalink if permalink.endswith("/") else permalink.rsplit("/", 1)[0] + "/"

    def fix(m):
        text, target = m.group(1), m.group(2).strip()
        if target.startswith(("http://", "https://", "mailto:")):
            return m.group(0)
        if target.startswith("#"):
            return f"[{text}]({page_url}{target})"
        if target.startswith("/"):
            return f"[{text}]({SITE}{target})"
        # bare-relative: resolve against the page's permalink directory
        rel = target[:-3] + "/" if target.endswith(".md") else target
        parts = (base + rel).split("/")
        stack = []
        for p in parts:
            if p == "..":
                if stack:
                    stack.pop()
            elif p not in ("", "."):
                stack.append(p)
        resolved = "/" + "/".join(stack)
        if rel.endswith("/") and not resolved.endswith("/"):
            resolved += "/"
        return f"[{text}]({SITE}{resolved})"

    return re.sub(r"\[([^\]]*)\]\(([^)]+)\)", fix, body)


# ── Header cell ────────────────────────────────────────────────────────────────

def header_cell(slug, permalink, version):
    ver = f"Generated for March {version}." if version else "Generated from the current docs."
    page_url = SITE + permalink
    return (
        f"> **Generated from the [March docs]({page_url}).**\n"
        "> Runnable [Scroll](https://github.com/march-language/scroll) notebook. To use it:\n"
        ">\n"
        "> 1. Install Scroll once: `forge install scroll@https://github.com/march-language/scroll`\n"
        f"> 2. Run it: `forge scroll.serve {slug}.scrollmd`\n"
        "> 3. **Shift+Enter** runs a cell. Cells share state top-to-bottom, and running a\n"
        ">    cell re-runs the ones above it — keep cells side-effect-free or idempotent.\n"
        ">\n"
        f"> {ver} Blocks shown for reference only won't run. This runs March on your\n"
        "> machine — it's the same code shown on the docs page.\n"
    )


# ── Emit ────────────────────────────────────────────────────────────────────────

def emit(body, slug, permalink, version):
    body = rewrite_links(body, permalink)
    out, pending_skip = [], False
    for line in body.splitlines():
        if SKIP_MARKER.match(line):
            pending_skip = True
            continue
        run = RUN_MARKER.match(line)
        if run:
            out += ["```march", run.group(1), "```"]
            continue
        if pending_skip and line.strip() == FENCE_MARCH:
            out.append(FENCE_STATIC)
            pending_skip = False
            continue
        out.append(line)
    return header_cell(slug, permalink, version) + "\n" + "\n".join(out).strip() + "\n"


# ── Cell tokenizer (mirrors Scroll's Cells.parse_cells) ────────────────────────

def parse_cells(content):
    """(kind, src) list. kind in {markdown, code, section}. Exact ```march only."""
    cells, buf, mode = [], [], "none"
    for raw in content.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        s = raw.strip()
        if mode == "code":
            if s == "```":
                cells.append(("code", "\n".join(buf)))
                buf, mode = [], "none"
            else:
                buf.append(raw)
        else:
            if s == FENCE_MARCH:
                if "\n".join(buf).strip():
                    cells.append(("markdown", "\n".join(buf).strip()))
                buf, mode = [], "code"
            elif s.startswith("<!-- section:") and s.endswith("-->"):
                if "\n".join(buf).strip():
                    cells.append(("markdown", "\n".join(buf).strip()))
                cells.append(("section", s[13:-3].strip()))
                buf = []
            else:
                buf.append(raw)
    if mode == "code":
        cells.append(("code", "\n".join(buf)))
    elif "\n".join(buf).strip():
        cells.append(("markdown", "\n".join(buf).strip()))
    return cells


def first_nonblank(src):
    for line in src.split("\n"):
        if line.strip():
            return line.strip()
    return ""


def build_runner(cells):
    """Assemble the program Scroll's generate_runner produces (for typecheck)."""
    mods, inlines = [], []
    for kind, src in cells:
        if kind != "code":
            continue
        if first_nonblank(src).startswith("mod "):
            mods.append(src)
        else:
            inlines.append(src)
    # `needs IO` rather than a narrower capability, deliberately. Since
    # 2026-08-06 an undeclared direct builtin call is an ERROR, and this
    # synthesized wrapper has to cover whatever the notebook's loose
    # expression cells call — which is arbitrary doc code, not a fixed set.
    # The root capability cannot under-declare; an unused-capability warning
    # does not fail the check.
    prog = ["mod NotebookRunner do", "  needs IO", ""]
    for m in mods:
        prog += [m, ""]
    # R1 stage D (2026-08-10): a program that performs IO must declare the
    # grant it runs under, so the synthesized `main` takes the root capability
    # matching the `needs IO` above. Same reasoning as that declaration — the
    # wrapper covers arbitrary doc code, so the root is the only grant that
    # cannot under-declare. `_`-prefixed because the cells never name it.
    prog.append("fn main(_cap_io : Cap(IO)) do")
    for c in inlines:
        for line in c.split("\n"):
            prog.append("  " + line if line.strip() else line)
    prog += ["  ()", "end", "", "end", ""]
    return "\n".join(prog)


# ── Discovery ────────────────────────────────────────────────────────────────────

def discover(paths):
    if paths:
        files = [Path(p).resolve() for p in paths]
    else:
        files = sorted(DOCS.rglob("*.md"))
    out = []
    for f in files:
        meta, body = split_front_matter(f.read_text())
        if is_opted_in(meta):
            out.append((f, meta, body))
    return out


def slug_of(meta):
    pl = meta.get("permalink", "").strip("/")
    pl = pl[len("docs/"):] if pl.startswith("docs/") else pl
    return pl.replace("/", "-") or "notebook"


def march_version():
    bin_cmd = os.environ.get("MARCH_BIN")
    if not bin_cmd:
        return ""
    try:
        r = subprocess.run(shlex.split(bin_cmd) + ["--version"],
                           capture_output=True, text=True, cwd=REPO, timeout=60)
        return r.stdout.strip().split()[-1] if r.returncode == 0 and r.stdout.strip() else ""
    except Exception:
        return ""


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]
    mode = "check" if "--check" in args else "emit"
    out_dir = DOCS / "downloads"
    if "--out" in args:
        out_dir = Path(args[args.index("--out") + 1]).resolve()
    paths = [a for a in args if not a.startswith("--")
             and a != (args[args.index("--out") + 1] if "--out" in args else None)]

    pages = discover(paths)
    if not pages:
        print("gen-scrollmd: no pages with `scrollmd: true` found.")
        return 0

    if mode == "emit":
        out_dir.mkdir(parents=True, exist_ok=True)
        version = march_version()
        for f, meta, body in pages:
            slug = slug_of(meta)
            (out_dir / f"{slug}.scrollmd").write_text(emit(body, slug, meta.get("permalink", "/"), version))
            print(f"  emitted {out_dir.relative_to(REPO) if out_dir.is_relative_to(REPO) else out_dir}/{slug}.scrollmd  (from {f.relative_to(REPO)})")
        return 0

    # check
    bin_cmd = shlex.split(os.environ.get("MARCH_BIN", "march"))
    failures = 0
    for f, meta, body in pages:
        slug = slug_of(meta)
        scrollmd = emit(body, slug, meta.get("permalink", "/"), "")
        cells = parse_cells(scrollmd)
        n_code = sum(1 for k, _ in cells if k == "code")
        prog = build_runner(cells)
        with tempfile.NamedTemporaryFile("w", suffix=f"_{slug}.march", delete=False, dir="/tmp") as tf:
            tf.write(prog)
            tmp = tf.name
        r = subprocess.run(bin_cmd + ["--check", tmp], capture_output=True, text=True, cwd=REPO)
        os.unlink(tmp)
        if r.returncode == 0:
            print(f"  ok    {slug}  ({n_code} runnable cells)")
        else:
            failures += 1
            print(f"  FAIL  {slug}  ({n_code} runnable cells)")
            msg = (r.stdout + r.stderr).strip().splitlines()
            for line in [l for l in msg if l.strip()][:8]:
                print(f"        {line}")
    if failures:
        print(f"\ngen-scrollmd --check: {failures} notebook(s) failed. "
              "A runnable cell must be a single `mod …` block OR expression/let "
              "statements — mark fragments with <!-- scroll:skip -->.")
        return 1
    print("\ngen-scrollmd --check: all notebooks compile.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
