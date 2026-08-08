# macos-15 clang miscompile surfaced by the stdlib doctest checker (2026-08-08)

> **CORRECTED 2026-08-08 — this is NOT JIT-REPL nondeterminism.** The `--diagnose`
> CI soak (added on PR #224) captured decisive evidence: the failure is
> **100% DETERMINISTIC on the macos-15 runner** (6/6 soak runs identical:
> `76 run / 1 failed / 3 anomalies`), affects **BOTH** JIT backends — the default
> (clang+dlopen) AND in-process ORC both return the wrong value in isolation — and
> the emitted LLVM IR and the runtime C are both clean on inspection. It is a
> **clang-version-specific runtime miscompile**: the runner's Apple clang
> `1700.0.13.5` compiles `march_string_starts_with` (and some RRB paths) to the
> wrong result at the default runtime `-O2`, while a newer Apple clang
> (`1700.6.4.2`, local) does not — which is why it never reproduced across 52+
> local runs. Concretely `String.starts_with("/etc", "/")` returns `false`
> (only the match-SUCCEEDS case is wrong; `("etc","/")`/`("","/")` are correctly
> `false`). `test (macos-15)` stays green because no golden exercises this case —
> the doctest checker is what exposed a real, previously-undetected macOS bug.
>
> **Chase (chosen 2026-08-08): bisect the runtime -O on CI, then narrow.** Three
> advisory macOS-only CI probes (in the `conformance` job) pinned it:
>
> 1. **Runtime -O bisect** (`MARCH_RUNTIME_OPT=0|1|2|3`, added to `bin/main.ml`):
>    `String.starts_with("/etc","/") = false` at **every** level incl `-O0`. A
>    `-O0` miscompile of correct C rules out an optimization-triggered UB in our
>    code → NOT an -O2 miscompile.
> 2. **Standalone C probe**: `march_string_starts_with` compiled STANDALONE by the
>    runner's own clang (`-O0..-O3`) with hand-built structs returns `= 1`
>    (correct). So the isolated C function is fine on this clang → the miscompile
>    is in the MARCH-generated path (literal construction / prelude), not the C.
> 3. **March-level narrowing** (REPL ops on the runner):
>    - `byte_size("/etc") = 4` ✓ but **`byte_size("/") = 0`** ✗ (a 1-char literal
>      reads length 0 — `march_string_byte_length` returns `s ? s->len : 0`, so
>      the short literal's `march_string_lit_static` likely returned NULL/bad);
>    - `"/etc" == "/etc" = true` ✓;
>    - **every** `starts_with`/`ends_with` returns `false` (incl the empty-prefix
>      case, which must be `true`).
>
> 4. **Standalone lit_static probe**: compiling `march_string_alloc` +
>    `march_string_lit_static` (verbatim, incl. its atomic-CAS memoization) +
>    `byte_length` + `starts_with` STANDALONE with the runner's own clang, then
>    building `"/"`/`"/etc"` through `lit_static`, returns `len(/)=1`,
>    `len(/etc)=4`, `sw=1` — **all correct at every -O**. So the runtime C is NOT
>    miscompiled by this clang either.
>
> **Conclusion: LLVM 17.0.0 (Apple clang `1700.0.13.5`) miscompiles the March
> *generated* IR for the string-literal path**, not our C. It hits BOTH the
> clang-AOT fragment path AND the in-process LLJIT (ORC) path — the common factor
> is the emitted IR — so it is the shared LLVM 17.0.0 codegen. Most likely a false
> IR attribute the March backend emits (e.g. `nonnull`/`dereferenceable(N)` on a
> string/arg) that this LLVM exploits, or a genuine LLVM 17.0.0 codegen bug. A
> newer Apple clang (`1700.6.4.2`) compiles the identical IR correctly, which is
> why 52+ local runs and the `ubuntu` runner all pass. Not reproducible without
> that exact toolchain.
>
> **Resolution options** (needs a decision): (a) **pin/upgrade the macos runner's
> Xcode** to a known-good clang (e.g. select the image's newest Xcode in
> `.github/actions/march-setup`); fastest and robust, and correct if this is an
> Apple/LLVM 17.0.0 codegen bug — which the evidence favors. (b) **Harden the
> emitted IR**: dump the REPL fragment/prelude IR for the `"/"` literal + the
> `march_string_lit_static`/`string_starts_with` call sites and audit the
> attributes the March backend attaches (`nonnull`, `dereferenceable(N)`,
> `noalias`, poison flags); if one is over-promising, drop/correct it in
> `lib/tir/llvm_*` — this fixes it for every toolchain but needs CI cycles to
> confirm (no local repro). The doctest gate stays advisory until resolved.

---

## Original (superseded) framing

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
