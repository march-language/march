# Differential Oracle Expansion — Design Spec

**Date:** 2026-07-04
**Status:** Design — not yet scheduled
**Author:** deep-review program follow-up (see `specs/analysis/2026-07-01-pipeline-deep-review.md` §8)
**Motivating evidence:** the campaign's largest recurring bug class.

---

## 1. Problem

March has **two implementations of its own semantics**: the tree-walking
interpreter (`lib/eval/eval.ml`, ~9,000 lines) and the compiled backend
(`lib/tir/*` → LLVM IR → `runtime/*.c`). They are written and maintained
independently, share no executable spec, and **drift**. Every drift is a bug
that is invisible until a specific program happens to exercise the diverged
path — and because the interpreter is the day-to-day development path, the
compiled-only bug typically ships and is found by a user (or a doc review)
months later.

The deep-review campaign fixed a long list of these, and the pattern is
unmistakable — every one is "compiled-only crash/wrong-output, interpreter
correct":

| Bug | Fixed | How it was found |
|---|---|---|
| `println([1,2,3])` compiled never worked (mono empty-substitution) | `ffe6fba8` | investigating the "sort_by crash" |
| Toml `get_str` corruption (4 RC/codegen bugs) | `exciting-burnell` cluster | user hit it in `forge.toml` parsing |
| Dual-position owned+borrowed double-consume (UAF, exit 134) | `a5dad194` | manual RC review |
| FBIP `same_arity` type-param vs field-count (heap overflow) | `a5dad194` | manual RC review |
| Double-`dec_rc` scrutinee re-matched in sibling arm (exit 134) | `20d1d144` | **TIR snapshot audit** |
| `EUpdate` on erased record OOB write | `0d1a829e` | code review |
| Record-update on missing field: compiled panics, interpreter fabricates | filed (open) | B5 fix follow-up |
| Derived `compare`/`hash`/`eq` SIGSEGV on Newtype-repr variants | filed (open) | **Wave 4 doc claim-verification** |

Two of these were caught by instruments the campaign *built* (the snapshot
audit, the doc claim-verification) rather than by a user — which is the whole
point. The differential oracle (`test/test_properties.ml`) is the right
instrument to catch the *rest* automatically, but today it is under-powered:
its generators cover a narrow slice of the language, and its comparison logic
skips several failure modes that are exactly where these bugs live.

## 2. What exists today

`test/test_properties.ml` (~1,494 lines) uses QCheck2. Its heart is
`oracle_check src` (~line 706):

1. Run `src` through the interpreter (`bin/main.exe <file>`). Nonzero → **skip**
   (generated program may legitimately error).
2. Compile (`bin/main.exe --compile <file> -o bin`). Nonzero → **skip**
   ("generator hit an unimplemented feature").
3. Run the compiled binary. `rc_run >= 128` (signal-killed) → **FAILURE** (the
   W2.0 fix, `a5dad194` — this is what makes crash-shaped RC bugs surface).
   Clean nonzero → **skip**. Output mismatch → **FAILURE**.

There are ~30 string generators (`gen_arith_module`, `gen_adt_module`,
`gen_closure_module`, `gen_recursive_module`, `gen_tuple_module`,
`gen_list_module`, `gen_nested_match_module`, …) unioned into
`gen_well_typed_module`, plus TIR-atom generators for pass-level properties.

**The gaps that let the campaign's bugs through:**

- **Generator coverage.** None of the ~30 generators produce: `println` of a
  generic container (the println-of-list bug), derived-method *calls*
  (`compare`/`hash`/`eq` by name — the Newtype crash), record *updates* on
  possibly-absent fields, `Newtype`/niche-represented single-field variants,
  values flowing through erased (`TVar`) positions, a variable passed at two
  argument positions with different borrow modes, or dead multi-type-param ADT
  bindings before an allocation. Every open/recent bug lives in a shape the
  generator can't emit.
- **Comparison surface.** The oracle compares **stdout only**, at `--compile`
  with **no optimization level**, on a **single run**. It therefore cannot see:
  optimizer-only miscompiles (`--opt 2` differs from `--opt 0`); non-crashing
  wrong-*behavior* that doesn't reach stdout (a leak, a wrong RC count that
  doesn't corrupt output); or exit-code divergence where both are nonzero.
- **The "compile-fail = skip" hole.** Step 2 treats a compiler failure as
  "unimplemented feature" and skips. But a compiler that *crashes* (segfaults,
  `Failure`, assertion) while compiling a well-typed program is a compiler bug,
  not an unimplemented feature — indistinguishable today from a graceful
  "not supported" and silently skipped. This is a vacuous-green of the exact
  class Wave 2 spent a whole task killing elsewhere.
- **It samples, it doesn't sweep.** The oracle only ever sees *generated*
  programs. The hundreds of hand-written `.march` fixtures under `test/`,
  `stdlib/`, `bench/`, and `examples/` — which exercise real, curated language
  shapes — are never run through the both-ways diff.

## 3. Goals

1. **Catch the compiled-only-divergence class in CI**, before a user does —
   for the shapes that keep breaking, not just the shapes that happen to be
   easy to generate.
2. **Make the oracle the refactor gate for `eval.ml`** (and any future
   interpreter work), the way byte-identical-IR was the gate for the Wave-3
   backend refactors. `eval.ml` has no IR to diff; a strong both-ways oracle
   is the only thing that can certify an interpreter refactor preserved
   behavior.
3. **Close the vacuous-green holes** in the oracle itself (compiler-crash vs
   unsupported; silent skip accounting).
4. Keep the suite fast enough to run per-commit for the sampled part, with a
   heavier full-corpus sweep gated to a slower CI lane.

Non-goals: deriving one implementation from the other (a worthy long-term
direction, out of scope); fuzzing the parser/typechecker for *rejection*
correctness (a separate effort); performance parity (the oracle checks
*behavior*, not speed).

## 4. Approach

### 4.1 Distinguish compiler-crash from unsupported-feature (prerequisite)

The step-2 "compile failed → skip" hole must close first, or expanded
generators will hide new compiler crashes as skips. Split the outcome:

- Compiler exits **0** → proceed to run.
- Compiler exits with a **clean, structured "unsupported"** signal → skip
  (counted). This requires the compiler to *have* such a signal — today a
  "not implemented" path and an internal `Failure`/segfault are
  indistinguishable by exit code. Introduce a distinct exit code (or a
  machine-readable stderr marker) for "typechecked but this construct isn't
  lowerable yet" so the oracle can tell "I don't support this" from "I crashed
  trying." Until that exists, treat **compiler signal-death (≥128) or an
  OCaml-backtrace on stderr** as a FAILURE (a compiler crash on a well-typed
  program is always a bug), and only a clean nonzero-with-no-backtrace as a
  skip. Count and report skips per the Wave-2 loud-skip doctrine.

### 4.2 Expand generators toward the failure shapes (the core work)

Add generators — biased toward where bugs concentrate — each unioned into
`gen_well_typed_module` and each with a one-line comment naming the bug class
it guards:

- **Generic-container output**: `println`/`to_string` of `List(a)`, `Option(a)`,
  tuples, nested containers (`[[1,2],[3]]`) — guards the println-of-list /
  interface-dispatch family.
- **Derived-method calls by name**: `derive Eq/Ord/Hash for T` then a call to
  `compare(x,y)`/`hash(x)`/`eq(x,y)` (not just the `==` operator) over each of:
  a single-field single-ctor variant (`Newtype` repr — the open SIGSEGV), a
  multi-field ctor (`Boxed`), a niche-shaped `Option`-like, and a record.
- **Record updates**: `{ base with f: v }` where `base` may be
  `record_from_list`-constructed (erased shape) and `f` may or may not exist —
  guards the EUpdate family and the interpreter/compiled missing-field
  divergence.
- **Borrow-mode-stressing calls**: a fn `f(a:own, b:borrow)` called `f(x, x)`
  with `x` dead-after — guards the dual-position class (`a5dad194`).
- **FBIP shapes**: a dead binding of a multi-type-param ADT (`Result(a,b)`)
  immediately before a same-arity allocation — guards `same_arity`.
- **Erased flows**: values passed through bare-`TVar` parameters (generic
  identity/HOF wrappers) then used concretely — the erased-repr family.
- **Deep/mutual recursion over heap data** long enough to force a scheduler
  yield and RC across a TCO back-edge — guards the B7/mutual-TCO family.

Each generator stays small and shrinkable (QCheck shrinking is what turns a
1000-line failing case into a 5-line repro — preserve it).

### 4.3 Widen the comparison surface

- **Optimization matrix.** Run the compiled path at `--opt 0` *and* `--opt 2`;
  diff each against the interpreter. An `--opt 2`-only divergence is an
  optimizer miscompile (the sort_by/cprop family) that `--compile`-default
  never sees.
- **Exit-code parity.** When both interpreter and compiled exit nonzero,
  compare the *codes* (a clean interpreter panic vs a compiled segfault on the
  same program is a divergence, currently skipped because both are nonzero).
- **RC-balance channel (optional, ride-along with §8.5).** When the runtime is
  built with the gc-trace hook, assert inc == dec + free per allocation on the
  compiled run — catches leaks and imbalances that don't corrupt stdout (the
  mutual-TCO leak class). This is the RC-balance harness from analysis-doc §8
  item 5; the oracle is its natural host.

### 4.4 Add the full-corpus sweep (a distinct mode)

Beyond generated programs, add a mode that enumerates **every deterministic,
self-contained `.march` program** under `test/`, `stdlib/` doctests, `bench/`,
and `examples/`, runs each through the both-ways diff (interpreter vs compiled
`--opt 2`), and reports divergences. These are curated, real language shapes —
higher signal per program than random generation. Exclude the known
nondeterministic set (actor races, wall-clock, RNG) via an explicit allowlist
so an exclusion is visible and reviewable (not a silent skip). This is the
"conformance mode" — slower, gated to a full-suite CI lane, but it would have
caught println-of-list and the derived-method crash from existing fixtures
without anyone writing a targeted test.

## 5. Phasing

- **Phase 1 — close the oracle's own holes** (§4.1): compiler-crash-vs-skip
  distinction, skip accounting. Small, unblocks everything.
- **Phase 2 — generator expansion** (§4.2): the highest-leverage bug-catching
  work; land generators in priority order (derived-method + generic-container
  first — they map to open bugs). Each new generator that reproduces an
  *already-known* open bug (Newtype SIGSEGV, missing-field record update) is
  landed with that bug marked `expected-fail`/`skip-with-reference` until its
  fix lands, so the oracle documents the bug without reddening CI.
- **Phase 3 — comparison surface** (§4.3): opt matrix + exit-code parity.
- **Phase 4 — full-corpus sweep** (§4.4): the conformance lane.
- **Phase 5 — wire as the `eval.ml` refactor gate**: document (in the
  compiler-rc skill and a testing doc) that an interpreter change must pass the
  oracle sweep with zero new divergences, mirroring the byte-identical-IR gate
  the backend refactors used.

## 6. Acceptance criteria

- The three currently-open compiled-only bugs (Newtype derived-method SIGSEGV;
  record-update missing-field divergence; and, once fixed, a regression guard
  for each) are each reproduced by a generator or corpus program in the oracle.
- A compiler crash (segfault/`Failure`) on a well-typed generated program fails
  the suite instead of skipping.
- The full-corpus sweep runs green on `main` at adoption time (any divergence
  it surfaces on day one is a real found bug — file it, don't suppress it).
- Skip counts are printed and bounded; a silent skip is impossible (Wave-2
  doctrine).
- Per-commit lane stays under a few minutes; the sweep lives in the slower lane.

## 7. Risks / open questions

- **Nondeterminism.** Any generator touching actors, time, RNG, hashing order,
  or float formatting can produce spurious diffs. Generators must stay in the
  deterministic subset; the corpus sweep needs the explicit nondeterministic
  allowlist. This is the main correctness risk for the oracle itself.
- **The "unsupported" signal (§4.1)** requires a small compiler change (a
  distinct exit code / stderr marker for typechecked-but-not-lowerable). Worth
  it — it also helps humans — but it is a real prerequisite, not free.
- **Cost of the opt matrix.** Compiling every generated program twice
  (`--opt 0` and `--opt 2`) roughly doubles oracle time; may need to sample the
  opt-2 arm at lower count than opt-0.
- **CAS cache interaction.** The oracle compiles many one-off programs; ensure
  it doesn't thrash or poison the shared CAS/JIT caches (see the companion spec
  `2026-07-04-concurrent-compiler-work-design.md` — the two efforts share the
  cache-isolation concern).
- **Shrinker quality.** The value of a found divergence is proportional to how
  small the shrunk repro is; complex generators shrink poorly. Keep each
  generator's grammar shallow.

## 8. Relationship to existing work

- Extends the W2.0 oracle fix (`a5dad194`) and the analysis-doc §8 items 1
  (oracle), 3 (generators), 5 (RC-balance harness).
- Complements the TIR snapshot infrastructure (W2.2): snapshots pin *IR shape*
  for a curated corpus; the oracle pins *observable behavior* over a random +
  full corpus. Different nets, both needed.
- Is the prerequisite gate for a future `eval.ml` restructure (the obvious next
  target of the Wave-3 pure-move method, which has no IR to diff).
