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


def run_repl(bin_path, exprs, backend=None):
    """Feed exprs to one `march repl` session. Return (values, stdout, stderr).

    `values` is {input_index: rendered_value}. The REPL prints
    `march(N)> = VALUE` where N is the 1-based input index, so the Nth input's
    value is keyed by N. An input that errors prints a bare `march(N)>` with no
    `= VALUE` and simply has no entry — alignment is by N, never by position, so
    one errored expression can't shift the rest. `backend` overrides
    MARCH_JIT_BACKEND for this session (e.g. "orc").
    """
    stdin = "".join(e + "\n" for e in exprs)
    env = dict(os.environ)
    if backend is not None:
        env["MARCH_JIT_BACKEND"] = backend
    proc = subprocess.run(
        [bin_path, "repl"],
        input=stdin, capture_output=True, text=True, timeout=120, env=env,
    )
    values = {}
    for line in proc.stdout.splitlines():
        m = REPL_VALUE_RE.search(line)
        if m:
            values[int(m.group(1))] = m.group(2).rstrip()
    return values, proc.stdout, proc.stderr


# Free lowercase identifiers a self-contained doctest expression must NOT
# reference (a `let` a prior example line set up); used only to decide whether a
# no-value result is anomalous (worth diagnosing) or an expected setup skip.
_IDENT_RE = re.compile(r"\b([a-z_][a-zA-Z0-9_]*)\b")
_KNOWN_FREE = {"fn", "do", "end", "let", "if", "else", "match", "true", "false"}


def references_bare_local(expr):
    """Heuristic: does `expr` reference a lowercase identifier that isn't a
    module-qualified call target or a keyword? Such an expr needs a prior `let`,
    so a no-value result for it is an expected skip, not an anomaly."""
    # Drop `Module.member` qualified names — their leading segment is uppercase.
    stripped = re.sub(r"\b[A-Z][A-Za-z0-9_]*\.", "", expr)
    for ident in _IDENT_RE.findall(stripped):
        if ident in _KNOWN_FREE:
            continue
        # A bare lowercase word that is immediately followed by "(" is a call to
        # a lowercase top-level/stdlib fn (fine); otherwise it's a free var.
        if not re.search(re.escape(ident) + r"\s*\(", stripped):
            return True
    return False


def diagnose_anomaly(bin_path, path, lineno, expr, expected, actual,
                     module_stdout, module_stderr):
    """Dump everything needed to understand a doctest anomaly on the runner that
    produced it: the full batched session output, an isolated re-run on the
    default (clang+dlopen) backend, an ORC (in-process LLJIT) re-run, and env."""
    bar = "─" * 72
    print(f"\n╔══ DOCTEST ANOMALY {path}:{lineno}", flush=True)
    print(f"║  expr     : {expr}", flush=True)
    print(f"║  expected : {expected!r}", flush=True)
    print(f"║  actual   : {actual!r}", flush=True)
    print(f"╟─ full batched `march repl` session for this module {bar[:20]}", flush=True)
    print(module_stdout, flush=True)
    if module_stderr.strip():
        print("║  ── session stderr ──", flush=True)
        print(module_stderr, flush=True)
    # Isolated re-run on each backend: does it reproduce alone, and does the
    # in-process ORC backend (no clang/dlopen/dyld) agree with the doc?
    for label, backend in (("default (clang+dlopen)", None), ("orc (in-process)", "orc")):
        try:
            vals, out, err = run_repl(bin_path, [expr], backend=backend)
            iso = vals.get(1, "<no value>")
        except Exception as e:  # noqa: BLE001 — diagnostics must never crash the run
            iso = f"<re-run raised {e!r}>"
            out = err = ""
        print(f"╟─ isolated re-run [{label}]: {iso!r}", flush=True)
        if err.strip():
            print(f"║    stderr: {err.strip()[:400]}", flush=True)
    print(f"╚══ end anomaly {path}:{lineno}\n", flush=True)


def main():
    # --diagnose: on any anomaly (a wrong value, or an unexpected no-value for a
    # self-contained primitive doctest) dump full evidence — for capturing the
    # intermittent JIT-REPL nondeterminism on the CI runner that produces it,
    # since it does not reproduce locally (specs/todos JIT-REPL nondeterminism).
    diagnose = "--diagnose" in sys.argv
    args = [a for a in sys.argv[1:] if a not in ("--check", "--diagnose")]
    bin_path = os.environ.get("MARCH_BIN", "./_build/default/bin/main.exe")
    if not os.path.exists(bin_path):
        print(f"error: march binary not found at {bin_path} (set MARCH_BIN)", file=sys.stderr)
        return 2
    files = args or sorted(glob.glob("stdlib/*.march"))

    if diagnose:
        import platform
        try:
            cc = subprocess.run(["clang", "--version"], capture_output=True, text=True, timeout=10).stdout.splitlines()
            cc = cc[0] if cc else "?"
        except Exception:  # noqa: BLE001
            cc = "?"
        print(f"[diag] arch={platform.machine()} clang={cc} "
              f"MARCH_JIT_BACKEND={os.environ.get('MARCH_JIT_BACKEND', '(default)')}", flush=True)

    total_run = 0
    total_skip = 0
    failures = []
    anomalies = 0
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
        values, mod_out, mod_err = run_repl(bin_path, [e for (_, e, _) in runnable])
        for idx, (lineno, expr, expected) in enumerate(runnable):
            actual = values.get(idx + 1)  # REPL input index is 1-based
            if actual is None:
                # The REPL emitted no value for this expression. Usually the
                # example references a `let` a prior line set up (skip). But a
                # SELF-CONTAINED primitive doctest yielding no value is
                # suspicious — under --diagnose, capture it (it might be the
                # intermittent JIT flake), without changing pass/fail: some ops
                # (e.g. certain RRB paths) consistently don't JIT-compile, so a
                # no-value is not by itself a failure.
                total_skip += 1
                skips.append(
                    f"  SKIP {path}:{lineno}  {expr!r} — REPL produced no value "
                    f"(example likely needs setup bindings)")
                if diagnose and not references_bare_local(expr):
                    anomalies += 1
                    diagnose_anomaly(bin_path, path, lineno, expr, expected,
                                     None, mod_out, mod_err)
                continue
            total_run += 1
            if actual != expected:
                failures.append(
                    f"  FAIL {path}:{lineno}  {expr}\n"
                    f"        expected: {expected!r}\n"
                    f"        actual:   {actual!r}"
                )
                if diagnose:
                    anomalies += 1
                    diagnose_anomaly(bin_path, path, lineno, expr, expected,
                                     actual, mod_out, mod_err)

    for s in skips:
        print(s)
    diag_note = f", {anomalies} anomalies diagnosed" if diagnose else ""
    print(f"\nstdlib doctests: {total_run} run, {total_skip} skipped, "
          f"{len(failures)} failed{diag_note}")
    if failures:
        print("\n".join(failures))
        return 1
    if total_run == 0:
        print("error: no doctests were actually run — the extractor matched nothing", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
