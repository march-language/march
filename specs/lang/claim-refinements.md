---
layout: docs
title: "Claim: Refinement Types"
nav_order: 20.5
permalink: /docs/claim-refinements/
---

> Part of the March Language Reference; see [specs/lang/index.md](index.md).

# Claim: Refinement Types

This is one of the four claims March 1.0 makes and treats any break of as a bug. The others
are [deploys]({{ site.baseurl }}/docs/claim-deploys/),
[capabilities]({{ site.baseurl }}/docs/claim-capabilities/) and
[performance]({{ site.baseurl }}/docs/claim-performance/). The feature itself is described
on [Refinement Types]({{ site.baseurl }}/docs/refinement-types/).

## The guarantee

By default the refinement checker reports a violation only when it can show one, with a
concrete input that breaks the contract, so it never rejects correct code; when it stays
silent, that does **not** mean the contract was proved. A module that declares
`cap verified` asks for more: every refinement obligation in that module must be proved by
the z3 solver, or explicitly accepted by an `@[assume]` (a function's return contract is
taken without proof) or `@[trusted]` (an unproved obligation inside the function is
accepted), and anything else fails the build with the reason it couldn't be proved. So a
`cap verified` module is **verified modulo the listed assumptions**: its `@[assume]` and
`@[trusted]` annotations, the standard library's own assumed contracts, and the trusted
base below. (Decided 2026-10-30: user code may use `@[assume]`, and `cap verified` must
list every assumption it relies on.)

## Assumptions

These make up the trusted base. If one is false, a "proved" contract may not hold.

- **z3 is present and correct.** Today z3 is found through `MARCH_Z3` or the first `z3` on
  `PATH` (`lib/refine/solver.ml`). It is not shipped with March and its version is not
  pinned. Without z3, ordinary modules get no refinement checking at all and no warning; a
  `cap verified` module fails the build, but the error says "solver-undecided", not "z3
  is missing". Bundling a pinned z3 in every release archive was decided on 2026-09-29 and
  is not built yet.
- **Each solver query finishes within 3 seconds.** The timeout is wall-clock time, so a
  heavily loaded machine can turn a proof into "undecided" and a `cap verified` build red.
- **Cached results came from a working z3.** The build cache does not record which z3, or
  whether any, produced a cached result.
- **`Int` arithmetic does not overflow.** The solver treats integers as unbounded. At run
  time an `Int` is 63-bit and **wraps** on overflow
  ([Int width and overflow]({{ site.baseurl }}/docs/types/#int-width-and-overflow)). So a
  proof about `i + len <= n` can hold in the solver and fail at run time for values whose
  sum wraps. **This is changing:** making overflow stop the program instead of wrapping was
  decided on 2026-09-29 and is being implemented. Once it lands, a program that would
  overflow stops at that point, and this assumption becomes "the program has not stopped
  on overflow"; this page will be updated with it.
- **Callers satisfy the contracts the checker skipped.** A function's body assumes its own
  parameter contracts. A caller in a module that is not `cap verified` may have had that
  obligation skipped, and nothing is checked at run time, so a proof inside the callee
  depends on its callers.
- **`@[assume]` contracts are true.** The standard library's assumed contracts (for example
  `Set` and `Map`, which hold only for a comparator that is a strict total order) each have
  a run-time property test. Yours are your responsibility.
- **The encoding and the measures are correct.** A `@[measure]` that is not total and pure
  is rejected at compile time, but the translation to the solver is trusted.
- **Refinements are erased.** A refined type compiles to its plain type; nothing is checked
  at run time.

## Not claimed

- **Completeness.** Many correct programs can't be proved; the checker skips what it can't
  translate and says why (`--refine-report`).
- **Anything outside `cap verified`.** There, silence is not a proof.
- **Refinements in an `interface` method signature.** They are not enforced: a warning
  outside `cap verified`, an error inside it.
- **Termination**, unless you ask for it with `--termination-report`.
- **A list of each assumption, today.** `--refine-report` counts `@[assume]` and
  `@[trusted]` uses (the `trusted` column) but does not name them one by one; listing them
  in `--refine-audit` and `forge audit` is **planned**.

## Gate

**Runs in CI today:**

- The z3-backed refinement suite (`test (ubuntu, refinecheck)`, Linux only; macOS skips it
  because its answers don't depend on the OS).
- The refinement obligation coverage ratchet in the `conformance` job: a drop in proved
  obligations, or a rise in skipped ones, fails the build.
- The measure soundness check is a compile error, so it runs on every build.

**Planned, not built:**

- A **must-reject soundness corpus** (overflow, skipped callers, interface signatures,
  higher-order code), separate from the coverage ratchet.
- A **determinism job** that runs the refinement suite on a deliberately starved CPU and
  requires identical results, after the solver moves from a wall-clock timeout to a
  resource limit.
- A **pinned z3** in CI on every platform (CI uses whatever z3 its package manager
  provides today, which differs between Linux and macOS).
