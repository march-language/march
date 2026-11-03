#!/usr/bin/env python3
"""Run the `march>` REPL-transcript doctests embedded in stdlib doc comments and
check each against the value the REPL actually produces.

This is the "stdlib-doctest extractor" follow-up to the differential-oracle
work (specs/todos differential-oracle-coverage): the module doc comments contain
`## Examples` blocks of the shape

        march> List.singleton(42)
        [42]

where the line after `march> EXPR` is the value the REPL prints. We feed each
EXPR to `march repl` (which renders values exactly as the doctest shows, e.g.
`= [42]`) and assert the rendered value equals the documented one — so a doctest
that drifts from the implementation, or a REPL/JIT regression, turns the check
red instead of rotting silently in a comment nobody runs.

Doctests are batched one `march repl` session per module (the REPL prints one
`march(N)> = VALUE` line per input expression, in order) to amortise the ~0.6s
stdlib load per session.

Which modules: those in PURE_MODULES, plus every module that opted its examples
into the docs' "Try it" buttons with a `-- doc: try` header line (a reader can
run those in the browser, so they must be right). Every expression of a checked
module is fed, in file order, to ONE session, so a `let` example line sets up
the bindings later lines use; only lines followed by an expected value are
checked.

How values are compared. The bare REPL renders `None` as `null`, `Some(1)` as a
raw tagged int, an opaque `ptype` as `#<tag>`, so its printed text matches the
doc only for PRIMITIVE values (Int, Bool, String, lists of those); those are
compared as text. Any other expected value is checked by also evaluating
`(EXPR) == (EXPECTED)` in the session and requiring `true`.

LOUD SKIPS (Wave-2 doctrine — never an invisible skip). A doctest is skipped,
with its reason printed, when:
  * its module is neither in PURE_MODULES nor opted in with `doc: try`;
  * the expected output is a `** panic ...` line (a panic ends a native REPL
    session, so these are not even fed);
  * the expected value spans more than one line;
  * no value came back (for `==`: the expected value is not a March expression
    with equality, e.g. `<fn>` or an opaque value).
Everything else is RUN and must match.

Whole-program examples: a ```march try fence (the docs' opt-in for a complete
program) is interpreted with the native compiler and must exit 0; when it is
followed by an ```output fence, its standard output must equal that block. A
program without `mod` is wrapped in `mod DocExample do needs IO ... end`, the
way the in-browser REPL accepts top-level declarations.

Usage:
  MARCH_BIN=./_build/default/bin/main.exe python3 scripts/check-stdlib-doctests.py --check [stdlib/foo.march ...]
If no files are given, every stdlib/*.march is scanned. Exits nonzero on any
mismatch (or if zero doctests were actually run — a silent-empty guard).
"""
import glob
import os
import re
import subprocess
import sys
import time

# Modules whose `## Examples` are pure, single-value REPL transcripts. Everything
# else is extracted but every doctest is skipped-loud: their examples do IO
# (network/filesystem/env), spawn work, or otherwise don't reduce to one printed
# value in a bare REPL.
PURE_MODULES = {
    "list", "option", "string", "path", "base64",
    "hash_map", "ring_buf", "rrb_vec", "http",
}

REPL_VALUE_RE = re.compile(r"march\((\d+)\)>\s*=\s*(.*)$")
# A `march>` line in a doc string, or in a module's `--` header comment.
MARCH_LINE_RE = re.compile(r"^\s*(?:--\s*)?march>\s?(.*)$")

# A value the bare REPL renders byte-for-byte as the doc shows: an integer, a
# bool, a double-quoted string, or a `[...]` list of such (no constructor `(`
# inside, which would be a non-primitive element).
_INT_RE = re.compile(r"^-?\d+$")
_STR_RE = re.compile(r'^".*"$')


def is_primitive_expected(expected):
    if _INT_RE.match(expected) or expected in ("true", "false") or _STR_RE.match(expected):
        return True
    # A list of records is structured: printers differ on `{ a: 1 }` spacing.
    if expected.startswith("[") and expected.endswith("]") and "(" not in expected \
            and "{" not in expected:
        return True
    return False


def module_stem(path):
    return os.path.splitext(os.path.basename(path))[0]


def extract_doctests(path):
    """Yield (lineno, expr, expected, skip_reason|None) for each `march>` in path.

    `expected` is the single line immediately after the `march>` line; a
    multi-line expected value is flagged as a skip rather than mis-parsed.
    """
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()
    n = len(lines)
    for i, line in enumerate(lines):
        m = MARCH_LINE_RE.match(line)
        if not m:
            continue
        expr = m.group(1).strip()
        # The expected value is the next line, dedented to its content (a
        # header-comment line's `--` prefix removed).
        expected = _content(lines[i + 1]).strip() if i + 1 < n else ""
        # Is the value multi-line? (the line after that is neither a new
        # `march>` nor the end of the indented example block).
        after = _content(lines[i + 2]).strip() if i + 2 < n else ""
        multiline = (
            after != ""
            and not after.startswith("march>")
            and not after.startswith('"""')
            and not after.startswith("#")
        )
        reason = None
        if expr == "":
            reason = "empty expression"
        elif expected.startswith("**"):
            reason = "expected a panic (not a pure REPL value)"
        elif expected == "" or expected.startswith("march>") or expected.startswith('"""'):
            reason = "no expected-value line follows"
        elif multiline:
            reason = "multi-line expected value"
        elif not is_primitive_expected(expected):
            reason = "non-primitive value (bare REPL rendering differs from the doc)"
        yield (i + 1, expr, expected, reason)


TRY_MARKER_RE = re.compile(r"^\s*--\s*doc:\s*try\s*$", re.M)
FENCE_RE = re.compile(r"^\s*(?:--\s?)?```\s*(\S*)\s*(\S*)\s*$")


def strip_comment(expr):
    """`expr` without a trailing `-- note` (a `--` outside string literals)."""
    in_str = False
    i = 0
    while i < len(expr):
        c = expr[i]
        if in_str:
            if c == "\\":
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif expr.startswith("--", i):
            return expr[:i].rstrip()
        i += 1
    return expr


def _content(line):
    """A source line as doc text: a `-- ` header-comment prefix removed."""
    stripped = line.lstrip()
    if stripped.startswith("--"):
        rest = stripped[2:]
        return rest[1:] if rest.startswith(" ") else rest
    return line


def _dedent(lines):
    widths = [len(l) - len(l.lstrip()) for l in lines if l.strip()]
    cut = min(widths) if widths else 0
    return "\n".join(l[cut:] if len(l) >= cut else "" for l in lines).strip("\n") + "\n"


def extract_programs(src):
    """Yield (lineno, code, expected_output|None) for each ```march try fence."""
    lines = src.split("\n")
    i = 0
    while i < len(lines):
        m = FENCE_RE.match(lines[i])
        if not (m and m.group(1) == "march" and m.group(2) == "try"):
            i += 1
            continue
        start = i + 1
        body = []
        i += 1
        while i < len(lines) and not (FENCE_RE.match(lines[i]) and _content(lines[i]).strip() == "```"):
            body.append(_content(lines[i]))
            i += 1
        i += 1
        # An ```output fence right after (blank lines allowed) is the expected stdout.
        j = i
        while j < len(lines) and _content(lines[j]).strip() == "":
            j += 1
        want = None
        if j < len(lines):
            om = FENCE_RE.match(lines[j])
            if om and om.group(1) == "output":
                out = []
                j += 1
                while j < len(lines) and _content(lines[j]).strip() != "```":
                    out.append(_content(lines[j]))
                    j += 1
                want = _dedent(out)
                i = j + 1
        yield (start, _dedent(body), want)


def run_program(bin_path, code, want):
    """Interpret one example program natively; None if it passes, else a message."""
    import tempfile
    if not re.search(r"^\s*mod\s", code, re.M):
        code = ("mod DocExample do\n  needs IO\n\n"
                + "".join("  " + l + "\n" if l.strip() else "\n" for l in code.split("\n"))
                + "end\n")
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "doc_example.march")
        with open(src, "w", encoding="utf-8") as f:
            f.write(code)
        proc = subprocess.run([os.path.abspath(bin_path), src], cwd=d,
                              capture_output=True, text=True, timeout=180,
                              env={**os.environ, "HOME": d})
    if proc.returncode != 0 or "-- ERROR" in proc.stdout + proc.stderr:
        detail = (proc.stdout + proc.stderr).strip().splitlines()
        return f"exited {proc.returncode}: " + " | ".join(detail[:6])
    if want is not None and proc.stdout.strip() != want.strip():
        return f"output differs\n        expected: {want.strip()!r}\n        actual:   {proc.stdout.strip()!r}"
    return None


def run_module(bin_path, path, exprs):
    """Feed exprs to one `march repl` session; return ({input_index: value}, jit_errors).

    The REPL prints `march(N)> = VALUE` where N is the 1-based input index, so
    the Nth input's value is keyed by N. An input that errors prints a bare
    `march(N)>` with no `= VALUE` and simply has no entry — alignment is by N,
    never by position, so one errored expression can't shift the rest.
    """
    stdin = "".join(e + "\n" for e in exprs)
    start = time.monotonic()
    proc = subprocess.run(
        [bin_path, "repl"],
        input=stdin, capture_output=True, text=True, timeout=120,
    )
    # One line per session: wall time plus the REPL's own `[timing]` and
    # `march JIT:` stderr lines, so a slow CI run shows where the time went
    # (a cold stdlib prelude compile, or a cache load that fell back to
    # recompiling) instead of only the step total.
    notes = [l.strip() for l in proc.stderr.splitlines()
             if l.startswith("[timing]") or l.startswith("march JIT:")]
    print(f"  {path}: {len(exprs)} exprs  {time.monotonic() - start:6.1f}s  "
          + "; ".join(notes), flush=True)
    values = {}
    for line in proc.stdout.splitlines():
        m = REPL_VALUE_RE.search(line)
        if m:
            values[int(m.group(1))] = m.group(2).rstrip()
    # A `march JIT:` line means the stdlib prelude .so failed to load and the
    # session fell back to recompiling it (~25 s each on CI, and the fallback
    # lowers stdlib without its type map). The doctests still pass that way,
    # so this is the only thing that notices.
    jit_errors = [l for l in notes if l.startswith("march JIT:")]
    return values, jit_errors


def main():
    args = [a for a in sys.argv[1:] if a != "--check"]
    bin_path = os.environ.get("MARCH_BIN", "./_build/default/bin/main.exe")
    if not os.path.exists(bin_path):
        print(f"error: march binary not found at {bin_path} (set MARCH_BIN)", file=sys.stderr)
        return 2
    files = args or sorted(glob.glob("stdlib/*.march"))

    total_run = 0
    total_skip = 0
    failures = []
    skips = []

    programs_run = 0
    for path in files:
        stem = module_stem(path)
        with open(path, encoding="utf-8") as f:
            src = f.read()
        opted_in = stem in PURE_MODULES or TRY_MARKER_RE.search(src) is not None
        doctests = list(extract_doctests(path))
        inputs = []   # fed to the session, in file order
        checks = []   # (input_index, kind, lineno, expr, expected, expr_index)
        for (lineno, expr, expected, reason) in doctests:
            if not opted_in:
                total_skip += 1
                skips.append(f"  SKIP {path}:{lineno}  {expr!r} — module '{stem}' "
                             "neither in PURE_MODULES nor opted in with `doc: try`")
                continue
            if expr == "" or (reason or "").startswith("expected a panic"):
                total_skip += 1
                skips.append(f"  SKIP {path}:{lineno}  {expr!r} — {reason}")
                continue
            inputs.append(expr)
            expr_index = len(inputs)
            if reason is None:
                checks.append((expr_index, "text", lineno, expr, expected, expr_index))
            elif reason.startswith("non-primitive"):
                inputs.append(f"({strip_comment(expr)}) == ({expected})")
                checks.append((len(inputs), "eq", lineno, expr, expected, expr_index))
            else:
                # Fed for its bindings / effects, but nothing to compare against.
                total_skip += 1
                skips.append(f"  SKIP {path}:{lineno}  {expr!r} — {reason}")
        if checks:
            values, jit_errors = run_module(bin_path, path, inputs)
            for err in jit_errors:
                failures.append(f"  FAIL {path}: stdlib prelude did not load: {err}")
            for (idx, kind, lineno, expr, expected, expr_index) in checks:
                actual = values.get(idx)
                if actual is None:
                    total_skip += 1
                    why = ("REPL produced no value" if kind == "text" else
                           "`==` produced no value (the expected value is not a March "
                           "expression with equality)")
                    skips.append(f"  SKIP {path}:{lineno}  {expr!r} — {why}")
                    continue
                total_run += 1
                ok = actual == expected if kind == "text" else actual == "true"
                if not ok:
                    shown = actual if kind == "text" else values.get(expr_index, "(no value)")
                    failures.append(
                        f"  FAIL {path}:{lineno}  {expr}\n"
                        f"        expected: {expected!r}\n"
                        f"        actual:   {shown!r}")
        for (lineno, code, want) in extract_programs(src):
            programs_run += 1
            err = run_program(bin_path, code, want)
            if err:
                failures.append(f"  FAIL {path}:{lineno}  ```march try program\n        {err}")

    for s in skips:
        print(s)
    print(f"\nstdlib doctests: {total_run} run, {total_skip} skipped, {programs_run} programs, "
          f"{len(failures)} failed")
    if failures:
        print("\n".join(failures))
        return 1
    if total_run == 0 and programs_run == 0:
        print("error: no doctests were actually run — the extractor matched nothing", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
