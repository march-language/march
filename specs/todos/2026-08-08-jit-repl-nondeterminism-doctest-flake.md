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

## Investigation 2026-08-08 (systematic-debugging Phase 1)

**Not reproducible locally** across **52+ runs** of the full checker — warm (×10),
cold/fresh-`HOME` (×19, reproducing the CI cache scenario: first module cold-writes
the prelude `.so`+`.names`, later modules warm-restore), concurrent (×18, six
checkers sharing `~/.cache/march`), and ORC (×5). Every run: 80 run / 87 skip /
0 fail, `Path.is_absolute("/etc") = true`. Host: Apple clang 17.0.0,
arm64/darwin25.5.

**Localised to the JIT's clang+dlopen path.** The REPL evaluates a bare
expression through the JIT (`Repl_jit.run_expr`), NOT the interpreter
(`lib/repl/repl.ml`, the `Some jit when not actors_declared` branch). On macOS
the clang backend compiles each fragment to a `.so` with `-undefined
dynamic_lookup` and `dlopen`s it `RTLD_GLOBAL`, so undefined symbols resolve
against all loaded `.so`s in a **flat namespace**. `repl_jit.ml` itself documents
the hazard: a fragment's `go$apply$N` lambda UID colliding with a prelude
function's makes `partition_fns` treat it as an already-compiled extern and link
the **prelude's** implementation — a precise "wrong value" mechanism. The
prelude-`.so` cache write is atomic (temp+rename, `.names` before `.so`) and the
`Defun.lambda_counter` is restored from `.names` on cache-hit, so the guard holds
on every path tested here — hence the flake is either a low-rate event or
specific to the CI runner's clang/dyld.

**ORC backend is correct and deterministic** (`MARCH_JIT_BACKEND=orc`, in-process
LLJIT — no clang, no `dlopen`, no flat-namespace resolution): 5/5 checker runs
clean, `Path.is_absolute("/etc") = true`. So the bug is in the clang+dlopen path,
not lowering/codegen shared with ORC.

## Capturing it (chosen next step, 2026-08-08)

Since it only manifests on the CI runner, `scripts/check-stdlib-doctests.py` gained
a `--diagnose` mode and the `conformance` CI job now runs a 6× soak with it
(advisory). On any anomaly (a wrong value, or a self-contained-primitive
no-value) it dumps: the full batched `march repl` session (stdout+stderr), an
isolated re-run on BOTH the default (clang+dlopen) and ORC backends, and
arch/clang. When the flake recurs on macOS CI, that block will show whether it is
batch-context vs per-expression, and whether ORC disagrees with the default
backend (confirming the clang+dlopen path). Root-cause and fix once captured;
likely fixes if confirmed: unique per-fragment symbol prefixes so a fragment can
never resolve to a prelude symbol, a two-level namespace instead of flat, or
promoting ORC to the default REPL backend.
