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
markers is hand-written prose and is left alone. That prose includes an
`<a id="..."></a>` line before each example's `### ` heading: the language chapters
link to it, and scripts/gen-lang-docs.py reads the `[code]` tags in each example's output
to list the example on docs/errors/<code>.md. So after this script changes an example's
output, run scripts/gen-lang-docs.py too (doc-lint Check F fails until you do).

A marker may name another way to run its example, after the name:

    <!-- error-tour: <name> run=test -->

runs `march test` on it (with MARCH_PROP_SEED=42, so a property's report is stable)
instead of `march --check`, and the ```text block holds the failure reports it prints:
each `FAIL: "<test>"` line and the report under it, de-indented, without the progress
dots or the summary line. The program must compile and its tests must fail. Such an
example is run-time output, so the error playground (which only checks) does not list it.

Each program is checked from its own fresh directory under a private HOME, as
`<name without its NN- prefix>.march`, so the header line names a file a reader can
recognise and no cache under the repo or ~/.cache/march shapes the output. The
refinement examples need z3 on PATH.

Usage:
  scripts/gen-error-tour.py            rewrite docs/error-messages.md in place
  scripts/gen-error-tour.py --check    exit 1 if the page differs from what this
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
PAGE = os.path.join(ROOT, "docs", "error-messages.md")
SRC_DIR = os.path.join(ROOT, "docs", "assets", "error-tour")
MARKER = re.compile(r"(<!-- error-tour: ([\w-]+)(?: run=(test))? -->\n)(.*?)(<!-- /error-tour -->)", re.S)


def failure_reports(out):
    """The `FAIL: "<test>"` blocks of a `march test` run, de-indented (the
    same extraction as test/run_test_reports.ml)."""
    lines, blocks, i = out.split("\n"), [], 0
    while i < len(lines):
        line = lines[i]
        if line.strip().startswith('FAIL: "'):
            k = len(line) - len(line.lstrip(" "))
            body, i = [line.strip()], i + 1
            while i < len(lines) and (lines[i] == "" or
                                      len(lines[i]) - len(lines[i].lstrip(" ")) > k):
                body.append(lines[i][k + 2:])
                i += 1
            while body and body[-1] == "":
                body.pop()
            blocks.append("\n".join(body))
        else:
            i += 1
    return "\n\n".join(blocks)


def check_output(march_bin, name, home, run=None):
    src = os.path.join(SRC_DIR, name + ".march")
    if not os.path.exists(src):
        sys.exit(f"error: {PAGE} names example `{name}`, but {src} does not exist")
    shown = re.sub(r"^\d+-", "", name) + ".march"
    work = tempfile.mkdtemp(prefix="error-tour-")
    try:
        shutil.copy(src, os.path.join(work, shown))
        env = dict(os.environ, HOME=home)
        if run == "test":
            env["MARCH_PROP_SEED"] = "42"
            cmd = [march_bin, "test", shown]
        else:
            cmd = [march_bin, "--check", shown]
        proc = subprocess.run(cmd, cwd=work, env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    finally:
        shutil.rmtree(work)
    with open(src) as f:
        program = f.read()
    output = proc.stdout
    if run == "test":
        output = failure_reports(output)
        if not output:
            sys.exit(f"error: example `{name}` (run=test) printed no failing test:\n{proc.stdout}")
    return program, output.rstrip() + "\n"


def render(page, march_bin):
    home = tempfile.mkdtemp(prefix="error-tour-home-")
    try:
        def fill(m):
            program, output = check_output(march_bin, m.group(2), home, m.group(3))
            return (m.group(1) + "```march\n" + program + "```\n\n"
                    + "```text\n" + output + "```\n" + m.group(5))
        return MARKER.sub(fill, page)
    finally:
        shutil.rmtree(home)


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
    new = render(page, march_bin)
    if check:
        if new != page:
            print(f"{os.path.relpath(PAGE, ROOT)} is stale: run scripts/gen-error-tour.py")
            sys.exit(1)
        return
    if new != page:
        with open(PAGE, "w") as f:
            f.write(new)
        print(f"wrote {os.path.relpath(PAGE, ROOT)}")


if __name__ == "__main__":
    main()
