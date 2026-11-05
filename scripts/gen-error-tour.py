#!/usr/bin/env python3
"""gen-error-tour.py: fill docs/error-messages.md's examples from the real compiler.

docs/error-messages.md is a hand-written tour of March's diagnostics. Each example on
it is a program in docs/assets/error-tour/<name>.march (the error playground on the
same page loads the same files) and the output `march --check` prints for it. The
page marks each example's place with

    <!-- error-tour: <name> -->
    ...
    <!-- /error-tour -->

and this script rewrites what lies between the two markers: a ```march block with the
program and a ```text block with what `march --check` prints, so the page shows what
the compiler says today rather than what someone once pasted. Everything outside the
markers is hand-written prose and is left alone.

It also writes docs/assets/error-tour/examples.json, {name: {file, source, output}} for
every example on the page. The error playground shows an example's output from it the
moment the example is picked, without loading the 2 MB compiler, and runs the
compiler only once the program has been edited.

Each program is checked from its own fresh directory under a private HOME, as
`<name without its NN- prefix>.march`, so the header line names a file a reader can
recognise and no cache under the repo or ~/.cache/march shapes the output. The
refinement examples need z3 on PATH.

Usage:
  scripts/gen-error-tour.py            rewrite docs/error-messages.md and
                                       examples.json in place
  scripts/gen-error-tour.py --check    exit 1 if either differs from what this
                                       script would write
  MARCH_BIN=path                       compiler to run (default
                                       _build/default/bin/main.exe; build it first
                                       with `dune build --root . bin/main.exe`)
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
import json

PAGE = os.path.join(ROOT, "docs", "error-messages.md")
SRC_DIR = os.path.join(ROOT, "docs", "assets", "error-tour")
INDEX = os.path.join(SRC_DIR, "examples.json")
MARKER = re.compile(r"(<!-- error-tour: ([\w-]+) -->\n)(.*?)(<!-- /error-tour -->)", re.S)


def check_output(march_bin, name, home):
    src = os.path.join(SRC_DIR, name + ".march")
    if not os.path.exists(src):
        sys.exit(f"error: {PAGE} names example `{name}`, but {src} does not exist")
    shown = re.sub(r"^\d+-", "", name) + ".march"
    work = tempfile.mkdtemp(prefix="error-tour-")
    try:
        shutil.copy(src, os.path.join(work, shown))
        env = dict(os.environ, HOME=home)
        proc = subprocess.run([march_bin, "--check", shown], cwd=work, env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    finally:
        shutil.rmtree(work)
    with open(src) as f:
        program = f.read()
    return shown, program, proc.stdout.rstrip() + "\n"


def render(page, march_bin):
    """Return (new page text, examples.json text)."""
    home = tempfile.mkdtemp(prefix="error-tour-home-")
    examples = {}
    try:
        def fill(m):
            name = m.group(2)
            shown, program, output = check_output(march_bin, name, home)
            examples[name] = {"file": shown, "source": program, "output": output}
            return (m.group(1) + "```march\n" + program + "```\n\n"
                    + "```text\n" + output + "```\n" + m.group(4))
        new = MARKER.sub(fill, page)
    finally:
        shutil.rmtree(home)
    return new, json.dumps(examples, indent=1, sort_keys=True) + "\n"


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        return None


def main():
    check = sys.argv[1:] == ["--check"]
    if sys.argv[1:] not in ([], ["--check"]):
        sys.exit("usage: scripts/gen-error-tour.py [--check]")
    march_bin = os.environ.get("MARCH_BIN",
                               os.path.join(ROOT, "_build", "default", "bin", "main.exe"))
    if not os.access(march_bin, os.X_OK):
        sys.exit(f"error: no compiler at {march_bin}; run `dune build --root . bin/main.exe`")
    with open(PAGE) as f:
        page = f.read()
    new, index = render(page, march_bin)
    outputs = [(PAGE, page, new), (INDEX, read(INDEX), index)]
    stale = [path for path, old, want in outputs if old != want]
    if check:
        for path in stale:
            print(f"{os.path.relpath(path, ROOT)} is stale: run scripts/gen-error-tour.py")
        sys.exit(1 if stale else 0)
    for path, old, want in outputs:
        if old != want:
            with open(path, "w") as f:
                f.write(want)
            print(f"wrote {os.path.relpath(path, ROOT)}")


if __name__ == "__main__":
    main()
