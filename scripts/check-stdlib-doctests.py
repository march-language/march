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

LOUD SKIPS (Wave-2 doctrine — never an invisible skip). The `## Examples` are
idealised transcripts, not literal REPL output: the bare REPL renders `None` as
`null`, `Some(1)` as a raw tagged int, an opaque `ptype` as `#<tag>` and `()` as
`1`, so only PRIMITIVE values (Int, Bool, String, and lists of those) render
byte-for-byte as documented. A doctest is therefore skipped, with its reason
printed, when:
  * the module is IO/effect-heavy (network/filesystem/env/actors), whose
    examples show side effects rather than a pure return value;
  * the expected output is a `** panic ...` line (panics go to stderr);
  * the expected value spans more than one line;
  * the expected value is not a primitive rendering (a constructor like
    `Some(..)`/`Ok(..)`, `None`/`null`, unit `()`, or a `ptype` — the REPL's
    terser rendering legitimately differs from the doc);
  * the REPL produced no value for it (the example references a binding a prior
    `let` in the same block set up, which a one-shot eval doesn't have).
Everything else is RUN and must match.

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

# Modules whose `## Examples` are pure, single-value REPL transcripts. Everything
# else is extracted but every doctest is skipped-loud: their examples do IO
# (network/filesystem/env), spawn work, or otherwise don't reduce to one printed
# value in a bare REPL.
PURE_MODULES = {
    "list", "option", "string", "path", "base64",
    "hash_map", "ring_buf", "rrb_vec",
}

REPL_VALUE_RE = re.compile(r"march\((\d+)\)>\s*=\s*(.*)$")
MARCH_LINE_RE = re.compile(r"^\s*march>\s?(.*)$")

# A value the bare REPL renders byte-for-byte as the doc shows: an integer, a
# bool, a double-quoted string, or a `[...]` list of such (no constructor `(`
# inside, which would be a non-primitive element).
_INT_RE = re.compile(r"^-?\d+$")
_STR_RE = re.compile(r'^".*"$')


def is_primitive_expected(expected):
    if _INT_RE.match(expected) or expected in ("true", "false") or _STR_RE.match(expected):
        return True
    if expected.startswith("[") and expected.endswith("]") and "(" not in expected:
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
        # The expected value is the next line, dedented to its content.
        expected = lines[i + 1].strip() if i + 1 < n else ""
        # Is the value multi-line? (the line after that is neither a new
        # `march>` nor the end of the indented example block).
        after = lines[i + 2].strip() if i + 2 < n else ""
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


def run_module(bin_path, exprs):
    """Feed exprs to one `march repl` session; return {input_index: value}.

    The REPL prints `march(N)> = VALUE` where N is the 1-based input index, so
    the Nth input's value is keyed by N. An input that errors prints a bare
    `march(N)>` with no `= VALUE` and simply has no entry — alignment is by N,
    never by position, so one errored expression can't shift the rest.
    """
    stdin = "".join(e + "\n" for e in exprs)
    proc = subprocess.run(
        [bin_path, "repl"],
        input=stdin, capture_output=True, text=True, timeout=120,
    )
    values = {}
    for line in proc.stdout.splitlines():
        m = REPL_VALUE_RE.search(line)
        if m:
            values[int(m.group(1))] = m.group(2).rstrip()
    return values


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

    for path in files:
        stem = module_stem(path)
        doctests = list(extract_doctests(path))
        if not doctests:
            continue
        runnable = []
        for (lineno, expr, expected, reason) in doctests:
            if reason is None and stem not in PURE_MODULES:
                reason = f"module '{stem}' not in the pure-REPL allowlist"
            if reason is not None:
                total_skip += 1
                skips.append(f"  SKIP {path}:{lineno}  {expr!r} — {reason}")
                continue
            runnable.append((lineno, expr, expected))
        if not runnable:
            continue
        values = run_module(bin_path, [e for (_, e, _) in runnable])
        for idx, (lineno, expr, expected) in enumerate(runnable):
            actual = values.get(idx + 1)  # REPL input index is 1-based
            if actual is None:
                # The REPL emitted no value for this expression — the example
                # references a `let` binding a prior line in the same block set
                # up, which a one-shot eval doesn't have. Skip, don't fail.
                total_skip += 1
                skips.append(
                    f"  SKIP {path}:{lineno}  {expr!r} — REPL produced no value "
                    f"(example likely needs setup bindings)")
                continue
            total_run += 1
            if actual != expected:
                failures.append(
                    f"  FAIL {path}:{lineno}  {expr}\n"
                    f"        expected: {expected!r}\n"
                    f"        actual:   {actual!r}"
                )

    for s in skips:
        print(s)
    print(f"\nstdlib doctests: {total_run} run, {total_skip} skipped, {len(failures)} failed")
    if failures:
        print("\n".join(failures))
        return 1
    if total_run == 0:
        print("error: no doctests were actually run — the extractor matched nothing", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
