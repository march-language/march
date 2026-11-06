#!/usr/bin/env python3
"""gen-error-tour.py: fill docs/error-messages.md's examples from the real compiler.

docs/error-messages.md is a hand-written tour of March's diagnostics. Each example on
it is a program in docs/assets/error-tour/<name>.march (the error playground on the
same page loads the same files) and the output `march --check` prints for it. The
page marks each example's place with

    <!-- error-tour: <name> -->
    ...
    <!-- /error-tour -->

(or `<!-- error-tour: <name> --why-copies -->` for an example whose output comes from
that report instead of `--check`, `<!-- error-tour: <name> --run -->` for one that is
run, showing the run-time failure it prints, or `<!-- error-tour: <name> --test -->` for a
test module run with `march test` (seed fixed at 42), showing its failing tests' reports)
and this script rewrites what lies between the two markers: a ```march block with the
program and a ```text block with what `march --check` prints, so the page shows what
the compiler says today rather than what someone once pasted. Everything outside the
markers is hand-written prose and is left alone. That prose includes an
`<a id="..."></a>` line before each example's `### ` heading: the language chapters
link to it, and scripts/gen-lang-docs.py reads the `[code]` tags in each example's output
to list the example on docs/errors/<code>.md. So after this script changes an example's
output, run scripts/gen-lang-docs.py too (doc-lint Check F fails until you do).

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
MARKER = re.compile(r"(<!-- error-tour: ([\w-]+)((?: --[\w-]+)*) -->\n)(.*?)(<!-- /error-tour -->)", re.S)
# Flags an example's marker may name in place of the default `--check`, as in
# `<!-- error-tour: 35-copy-shared --why-copies -->`: reports that are not part of
# an ordinary check. The playground only checks, so such an example is not listed in it.
# `--run` is not a compiler flag: it means run the program (interpreted) and show what
# it prints on stderr, for the run-time failure reports. `--test` is not one either: it
# means run the test module with `march test` (MARCH_PROP_SEED=42, so a property's
# counterexample is fixed) and show its `FAIL:` reports.
ALLOWED_FLAGS = {"--why-copies", "--run", "--test"}


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


def check_output(march_bin, name, home, flags=()):
    src = os.path.join(SRC_DIR, name + ".march")
    if not os.path.exists(src):
        sys.exit(f"error: {PAGE} names example `{name}`, but {src} does not exist")
    shown = re.sub(r"^\d+-", "", name) + ".march"
    work = tempfile.mkdtemp(prefix="error-tour-")
    try:
        shutil.copy(src, os.path.join(work, shown))
        env = dict(os.environ, HOME=home)
        if "--test" in flags:
            env["MARCH_PROP_SEED"] = "42"
            proc = subprocess.run([march_bin, "test", shown], cwd=work, env=env,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            proc.stdout = failure_reports(proc.stdout)
        else:
            mode = [f for f in flags if f != "--run"] if flags else ["--check"]
            run = "--run" in flags
            proc = subprocess.run([march_bin, *mode, shown], cwd=work, env=env,
                                  stdout=subprocess.DEVNULL if run else subprocess.PIPE,
                                  stderr=subprocess.PIPE if run else subprocess.STDOUT, text=True)
            if run:
                proc.stdout = proc.stderr
    finally:
        shutil.rmtree(work)
    with open(src) as f:
        program = f.read()
    return program, proc.stdout.rstrip() + "\n"


def render(page, march_bin):
    home = tempfile.mkdtemp(prefix="error-tour-home-")
    try:
        def fill(m):
            flags = m.group(3).split()
            bad = [f for f in flags if f not in ALLOWED_FLAGS]
            if bad:
                sys.exit(f"error: {PAGE}: example `{m.group(2)}` names unknown flag(s) {bad}")
            program, output = check_output(march_bin, m.group(2), home, flags)
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
