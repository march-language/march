# Floor division and constant-divisor lowering

**Status:** design, nothing implemented. **Filed:** 2026-10-29.
**Source idea:** Ben Joffe, "Fast Signed 64-bit Floor Division by Constants" (benjoffe.com/fast-floordiv, 2026;
reference at github.com/benjoffe/fastdiv, `algorithms/benjoffe.hpp`).
**Reading status:** the article, its Annexure A proof and the reference solver were read through a
fetch-and-summarize tool, not as raw files. The solver is excerpted below; Phase 3 starts by reading the
actual `.hpp` and the proof directly.

## Why

Three facts about the current tree drive this:

1. **Every Int division is an out-of-line call.** `/` and `%` lower to `march_checked_div_op` /
   `march_checked_mod_op`; `int_div`, `int_mod`, `int_div_euclid`, `int_mod_euclid` lower to
   `march_checked_idiv` / `imod` / `ediv` / `emod` (all in `runtime/march_runtime.c`). LLVM never sees
   a constant divisor, so even `x / 86400` gets no multiply-by-reciprocal lowering. The helpers exist
   only to trap on a zero divisor, which a nonzero literal cannot be.
2. **There is no public floor division.** `stdlib/datetime.march` carries a private `floor_div`
   (`q = int_div(a,b); r = a - q*b; if r < 0 do q - 1 else q`). That is correct for `b > 0` only:
   `floor_div(7, -2)` gives `-3`, but the floor is `-4`. Its callers all divide by positive constants
   (86400), which is the exact case the article optimizes.
3. **Int is 63-bit** (`[-2^62, 2^62)`, lazily normalized from i64; see `Llvm_ctx.emit_wrap_int63`). The
   article's 64-bit algorithm is valid on the full i64 range, so it covers ours. Whether the smaller
   domain lets us use simpler constants than the article is an open question, not a claim.

## Phases

Each phase lands on its own and is useful without the next.

### Phase 1: inline nonzero-literal divisors

When the divisor atom is `ALit (LitInt n)` with `n` not in `{0, -1}`, emit inline LLVM instead of the
helper call:

| Source | Emitted |
|---|---|
| `a / n`, `int_div(a, n)` | `sdiv i64 a, n` |
| `a % n`, `int_mod(a, n)` | `srem i64 a, n` |
| `int_div_euclid(a, n)` | `q = sdiv`, `r = srem`, then `q - (r<0)` for `n>0`, `q + (r<0)` for `n<0` (as `select`) |
| `int_mod_euclid(a, n)` | `r = srem`, then `r + (r<0 ? abs n : 0)` |

Why exclude `0`: the helper stays as the trap path, so its message and behavior are untouched.
Why exclude `-1`: `sdiv` by `-1` overflows for `INT64_MIN`. The 63-bit range makes that unreachable
only if the operand is already normalized at that point, which I have not verified. Leaving `-1` on the
helper costs nothing.

Sites (the arm exists twice in `llvm_emit.ml`, once in the general `EApp` path and once in the second
call-emission path; keep them in step or factor one function):
- `emit_int_arith` in `lib/tir/llvm_emit_arith.ml` (the `/` and `%` arm)
- the `Int_mod | Int_div | Int_mod_euclid | Int_div_euclid` arms in `lib/tir/llvm_emit.ml`

**Checked 2026-10-29: the literal does survive to codegen.** `x / 86400` stays `/(x, 86400)` through
`tir-defun`; a `let d = 86400 in int_div_euclid(x, d)` is rewritten by `tir-opt-1-cprop` so the call
takes the literal. In emitted LLVM, a tail-recursive `f(x / 86400 - 1, acc + x % 86400)` produced
`call i64 @march_checked_div_op(i64 %w6314, i64 86400)` and the same for `mod_op`, so the divisor
reaches the emitter as a literal and the helper call is still emitted. No literal-forwarding step is
needed. (The existing parity test that hides the divisor behind a variable is still the right control
for comparing the literal and variable paths.)

**Interpreter, JIT, JS:** interpreter unchanged. JIT shares `llvm_emit`, so it changes with it (verify
by running `test_jit`). `js_emit` is unaffected: JS arithmetic does not go through these helpers.

Optional follow-up in the same phase: `purity.ml` currently treats these ops as trapping. A nonzero
literal divisor cannot trap, so the call could be marked pure and CSE'd/hoisted. Separate commit,
only if the benchmark shows it matters.

### Phase 2: `int_div_floor` / `int_mod_floor`

Public builtins named to match `int_div_euclid` / `int_mod_euclid`. The request was for "`floor_div`";
I kept the `int_` prefix because a bare `floor_div` is a name user programs commonly define, and a
module-level fn shadowing a builtin hits the known typecheck/runtime split (see memory). If you want the
short name anyway, it is an alias in the prelude (`fn floor_div(a, b) do int_div_floor(a, b) end`), not a
second builtin.

**Fast path for literal divisors in this phase.** The builtin's compiled lowering takes the Phase 1
inline form whenever the divisor is a nonzero literal, so `datetime`'s `floor_div(ts, 86400)` is
inlined `sdiv`/`srem` plus a one-instruction correction as soon as the builtin lands. The Phase 3
multiplier then replaces that inline form later.

**Semantics** (the contract all backends must agree on):

```
int_div_floor(a, b) = q - 1  if r != 0 and (r < 0) != (b < 0)   where q = a/b (truncating), r = a - q*b
                      q      otherwise
int_mod_floor(a, b) = a - int_div_floor(a, b) * b                 -- sign follows b, |r| < |b|
b = 0               -> panic "int_div_floor: division by zero" / "int_mod_floor: division by zero"
```

This is the real floor for every sign of `b`, which fixes the negative-divisor gap in
`datetime.march`'s helper. For positive `b` it equals `int_div_euclid`; they differ only for `b < 0`.
`-2^62 / -1` wraps to `-2^62` like the other quotients.

**Runtime names:** `march_checked_ifloordiv`, `march_checked_ifloormod`. Not `march_checked_fdiv`:
that is the existing *float* checked division.

**Sites**, following `.claude/skills/compiler-builtin/SKILL.md`. These builtins need a dedicated
emitter arm (for Phase 1/3 inlining), so they take a `Builtin_name.t` constructor, and the build then
fails until every exhaustive match is extended. Concretely, mirror every place `int_div_euclid` appears:

- `lib/typecheck/typecheck_builtins.ml`: `builtin_bindings`, `Int -> Int -> Int`
- `lib/eval/eval_builtins.ml`: interpreter impl, same panic text as the runtime
- `runtime/march_runtime.c`: the two helpers, beside `march_checked_ediv`
- `lib/tir/llvm_builtins.ml`: table row **and** `PDeclare` (both)
- `lib/tir/builtin_name.ml` / `.mli`: constructors, `to_string`, `all`
- `lib/tir/llvm_emit.ml`: `builtin_group`, and both call arms
- `lib/tir/alloc_contract.ml`: the two `named_builtin_*` matches
- `lib/tir/defun.ml` `builtin_names`, `lib/tir/policy_dce.ml`, `lib/tir/purity.ml`: name lists
- `lib/refinecheck/division_safety.ml`: `div_ops`, so a zero divisor is still a proof obligation
- `lib/tir/js_emit.ml` (two lists) and `runtime/march_runtime.mjs`, plus the two `test/*/march_runtime.mjs`
  copies if they are not generated
- Tests: `test_codegen.ml` `golden_preamble_*` (new `declare`), `test_builtin_compiled_lowering.ml`
  accounting, a parity test modeled on `test_compiled_int_div_euclid_parity` covering all four sign
  quadrants plus `b = ±1`, `a = ±2^62-ish` extremes, and divide-by-zero on both backends

Then migrate `datetime.march`: delete `floor_div`/`floor_mod`, call the builtins. Its tests must pass
unchanged for the positive-divisor cases. `Int` module / docs: `specs/lang/type-system.md` names the
division builtins; add the two, run `scripts/gen-lang-docs.py`, commit generated pages.

Without Phase 1/3, the compiled lowering is a helper call, same as `ediv`. Inline form for a literal
`n > 0` (the case that matters): `q = sdiv a, n; r = srem a, n; q + (r >> 63)`. For `n < 0` the
correction is `r > 0` instead of `r < 0`. Fold this into Phase 1's emitter helper.

### Phase 3: sign-selected multiplier for literal divisors (the article)

For literal `d` that is not `0`, `±1`, or a power of two (powers of two use `ashr`; for floor that is
exact with no fix-up), emit the article's sequence in IR using `i128`, which LLVM lowers to a single
high-multiply on both x86-64 and arm64:

```
m   = M + (x >>s 63)                 ; M for x >= 0, M-1 for x < 0
hi  = (sext x to i128) * (sext m to i128)
q   = trunc (hi >>s S) to i64        ; S = 64 + shift from the derivation
```

Example from the article: `d = 86400`, `M = (1<<79)/86400 + 1`, `S = 79`.

**Constant derivation** happens in OCaml at compile time and needs 128-bit arithmetic (the shift
ranges over `[W, 2W)`, so `2^S` is up to 127 bits). Check whether `zarith` is already a dependency; if
not, do the derivation with a small unsigned-128 helper rather than adding one for this.

**The reference solver** (`algorithms/benjoffe.hpp`, MIT, Copyright (c) 2026 Ben Joffe; any code we
port must keep that notice). What I read is a verbatim excerpt returned through a fetch tool, not the
file itself, so Phase 3 starts by reading the real file. As excerpted, with `W` the width,
`maxint = 2^(W-1)`, `dabs = |d|`, `neg = d < 0`:

```
top       = maxint + neg
boundUp   = top / dabs * dabs - 1
downMult  = maxint / dabs * dabs + 1
boundDown = downMult - (neg && downMult == maxint)
search(up):  for s in W .. 2W-1:
               two_s = 2^s ; rem = two_s mod dabs ; M = two_s / dabs + up
               err   = up ? dabs - rem : rem
               if two_s > (up ? boundUp : boundDown) * err && M < maxint: return (s, M)
```

Both directions are searched. If only one passes it is used. If both pass, it picks round-down when
`up.S != W && down.S == W`, round-up when `up.S == W && down.S != W` on non-x86 only, otherwise
sign-selected with `S = max(up.S, down.S)` and `M = 2^S / dabs + !neg` (negated if `d < 0`). Runtime
sign-selected is `m = M + (x >> (W-1)); q = mulhi(x, m) >> shift`, with `M` held opaque so the compiler
does not rewrite it. The one-direction modes bias `x` by a compare first (`x < -1` for positive round-up,
`x > 1` for negative round-up, and unsigned-compare forms for round-down) and then use a single `M`.
If neither direction passes, the reference traps at compile time and says this never happens.

**What the proof establishes** (Annexure A, also read via a summary tool): with `N = W-1`, a rounding
works for positive `D` over the full signed range exactly when it works for unsigned `N`-bit input, using
`⌊x/D⌋ = -1 - ⌊(~x)/D⌋` for negative `x`. Round-down is excluded when `D` divides `2^N - 1` (7, 49, 73,
127, 337, 511, ...), and round-up is excluded for negative divisors when `|D|` divides `2^N + 1`. Sign-selected
works wherever both roundings work, and a rounding that works at some shift keeps working at larger shifts.
Powers of two are handled separately (shift). Because I have the proof only through a summary, our
tests do not rely on it: they check the derivation by brute force (below).

**Validity.** Never emit a multiplier whose validity was not established: the derivation returns `None`
rather than guess, and the emitter falls back to the Phase 1 inline fix-up form (`sdiv`/`srem` plus
correction, which LLVM still strength-reduces). We do not need the article's x86-vs-ARM mode preference
to be correct for the first cut: always use sign-selected when both roundings pass, else the one that
passes with its bias compare, and revisit once the benchmark shows what this machine prefers.

**Gate (decide with numbers, not belief).** Land Phase 3 only if the benchmark below shows a win over the
*Phase 1 fallback*, not over today's helper call. The helper call is the wrong baseline: Phase 1 already
takes most of that gain. The article's own x86 numbers are mixed (5-10% faster for most positive
divisors, slower for others, latency usually worse than Robison's), and its large win is on arm64.
If the margin is under noise on this machine, close Phase 3 as not worth the code and say so in
`specs/progress/`.

## Verification plan

- **Correctness of derived constants:** property test in OCaml over many divisors (all `|d|` up to 2000,
  `2^k ± 1`, the failing families above, `±(2^62 - 1)`) against a reference floor, with dividends at
  `0, ±1, ±d, ±(d-1), ±(d+1)`, `INT63_MIN/MAX`, plus random. A divisor list alone is not enough:
  also run the same derivation at 8-bit and 16-bit width exhaustively (every `x`, every `d`), since the
  algorithm is width-generic and that is the only place exhaustive checking is possible.
- **Compiled vs interpreted parity:** `.march` tests with literal and variable divisors side by side,
  all sign quadrants. The variable-divisor path is the oracle for the literal path.
- **IR oracles:** `scripts/ir-oracle.sh` will legitimately change for every program with a literal
  divisor. Do not use it to prove "no change"; review the diff and spot-check that only division sites
  moved. Per CLAUDE.md, first prove the oracle goes red on a deliberate perturbation.
  `scripts/determinism-oracle.sh` must stay green (the derivation is pure).
- **Snapshots / errors corpus:** `test/run_snapshots.exe` pins post-lower and post-Perceus TIR, which
  Phase 1 does not touch (it is an emitter change); Phase 2 may add nothing. Run both anyway.
- **Benchmark:** new `bench/int_div_const.march`: a hot loop over `x / 86400`, `x % 86400`,
  `int_div_floor(x, 86400)`, and a handful of other divisors including a power of two and a `7`-type
  failing divisor, with negative and positive `x`. Compile with `--opt 2`. Compare Phase 1, Phase 2, and
  Phase 3 builds against the pre-change compiler, interleaved (see the two-branch-control note in
  memory) and on a quiet machine. **Register it in `test/test_bench_gate.ml`** or the `bench-gate` job
  fails for everyone.
- **Stdlib:** `scripts/run-tests.sh` full, including `stdlib_march` for `datetime`.

## Bookkeeping

Per CLAUDE.md, in the same commits: `specs/todos/` entries (filed with this spec) move to
`specs/progress/` as each phase lands; `CHANGELOG.md` `[Unreleased]` gets an `### Added` bullet for the
two builtins and a `### Changed` bullet for constant-divisor speedups; no grammar change, so the
tree-sitter rules do not apply.

## Non-goals

- Unsigned or smaller-width division (Int is the only integer type here).
- Non-constant divisors. The runtime check plus hardware `idiv` stays.
- Changing `/` or `%` semantics: they stay truncating.
