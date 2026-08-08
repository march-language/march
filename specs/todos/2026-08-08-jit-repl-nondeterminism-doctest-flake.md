# JIT REPL nondeterminism surfaced by the stdlib doctest checker (2026-08-08)

`scripts/check-stdlib-doctests.py` drives `march repl` (JIT-backed) and compares
each rendered value to the documented one. On CI it exposed an **intermittent,
runner-dependent** wrong result from the JIT REPL:

- `Path.is_absolute("/etc")` — whose body is literally
  `String.starts_with(path, "/")`, so it MUST be `true` on any platform —
  rendered `false` once on a `macos-15` GitHub runner, while rendering `true`
  5/5 in isolation locally and passing on the `ubuntu-24.04` runner in the same
  CI run.
- The checker's own run/skip split varied across macOS environments (80 run /
  87 skipped locally vs 76 / 91 on the macOS runner) — several doctests that
  produce a REPL value in one environment produce none in another, i.e. the JIT
  REPL emits different output for the same input program.

This is a **JIT-REPL determinism bug**, not a doctest-content bug (the doc value
is correct) and not a checker bug (alignment is by the REPL's `march(N)>` input
index, robust to a missing value). Because it can flake, the CI doctest step is
wired **advisory** (`continue-on-error: true`, `.github/workflows/ci.yml`,
`conformance` job) so a flake cannot redden CI. Make it a hard gate once the
JIT-REPL nondeterminism is root-caused and fixed.

Not reproduced locally so far (5/5 `true` for the specific expression). Likely
suspects to investigate: the stdlib precompile/JIT cache warm path
(`March_repl.Repl.maybe_precompile_stdlib` / `load_cached_tc_env`), any
order/hash-dependent codegen in the JIT, or a genuine intermittent miscompile of
`String.starts_with`. A first step is a soak: run the checker (or just the one
expression) hundreds of times per platform, and one-expr-per-session vs batched,
to localise whether it is per-expression JIT codegen or cross-expression REPL
state.
