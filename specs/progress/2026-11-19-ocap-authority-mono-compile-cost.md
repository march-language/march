# Every compiled program monomorphizes `stdlib/authority.march` and then drops it (2026-11-19)

Found during ocap phase 4 (PR A, since `bad07beec`, Authority's run-time policy in
March). Every `--compile` now monomorphizes about 100 `stdlib/authority.march`
functions that are removed before LLVM emission: on
`test/snapshots/src/trmc_modulo_cons.march` the tir-mono function count went from 37
to 144, while the emitted module has 14 defines and none of them from `Authority`.
On native, the launch and the checks run the C policy (`runtime/march_authority.c`,
`Auth_native`), so `launch_init`'s March body is dead there.

The compile-time delta is not measured yet: both arms of a comparison against
origin/main already carry `bad07beec`, so it needs a build of `bad07beec^`
(or a switch that skips the March policy) timed on a hello world and on a
mid-size program, with a private HOME so the CAS does not answer.

What to do: measure it as above; if it matters, make the March policy
unreachable on native when `Auth_native.applicable` holds (so mono never sees
it), and check with `scripts/ir-oracle.sh` that emitted IR does not move.

## Measured 2026-11-24: about 70 ms per compile, roughly 3% of a small program's compile

I built compilers from `git archive` of `bad07beec^` and `bad07beec` and timed them alternately
(before, after, before, …) to cancel machine load. Each arm had its own private `HOME` and cwd,
with one warm-up compile per program. Every timed compile appended a different unreachable
`pfn probe_<n>()`, so the source-level cache missed. The command was `--compile --opt 2
--timings`. The measure is the `cas-hash` stamp, which covers the front end and the
whole-program TIR passes, the work this todo is about. Five rounds per cell; medians:

| program | `bad07beec^` | `bad07beec` | delta | typecheck delta |
|---|---|---|---|---|
| hello world (`needs IO.Console`) | 2.209 s | 2.281 s | **+72 ms (+3.3%)** | +41 ms |
| `bench/tree_transform.march` | 2.219 s | 2.289 s | **+70 ms (+3.2%)** | +35 ms |

The spread within each cell was 20–40 ms, apart from one outlier per "before" column. Function
counts are the same on both programs: +94–96 at `lower`, about +100 at `mono` and `defun`, and
+46 that survive to `perceus` (hello: 5 → 51) before `opt` removes them. A mid-size program
pays the same absolute cost, since the policy doesn't depend on the program. On topology's
15.7 s leaf edit (`specs/plans/incremental-codegen-cas-baseline-3.md`) that's under 0.5%. A third
program, `bench/dataframe_bench.march`, dropped out because its trailing `end -- mod …` defeated
the probe injection.

**Caveats.** `authority.march` was 1 117 lines at `bad07beec` and is 1 345 on `main` (p5 and p6),
so today's cost is probably somewhat higher. I didn't measure it, because `main` has no switch
that removes the policy. The load average was high (~20 on 14 cores), but alternating the arms
and the tight spreads make the delta credible. Absolute times are inflated.

**Verdict.** The fix above is still cheap and correct, but the payoff is small. The larger cost
it sits inside is that every program carries the whole stdlib through lowering, mono, fusion and
defun (~6 200 functions at `lower`, ~7 100 at `mono`) and prunes it only at Perceus. On hello
world that is about 1.1 s of the 2.2 s. A smaller cost: `typecheck` alone is ~1.15 s on hello
world at `bad07beec^`, against a ~0.39 s front end for the small corpus in baseline 2
(2026-10-07). Part of that is load, but the growth predates `bad07beec`. Both are bigger targets
than this item.

## 2026-11-25: the pre-mono prune removes the policy before mono

`Dce_pre_mono` (`specs/progress/2026-11-24-pre-mono-dce.md`) drops every function the roots
cannot reach before Mono, so Mono, Fusion and Defun no longer see the unreachable part of
`stdlib/authority.march` (hello world: 66 functions into Mono, was 6,340). What is left of this
item is the part a native program does reach: `Authority.check` and what it calls are still
lowered, monomorphized and emitted, and `launch_init`'s March body stays reachable although
the C policy runs instead. Typechecking and lowering `authority.march` are unchanged (the
"typecheck delta" column above). Making the March policy unreachable on native when
`Auth_native.applicable` holds is still open; the remaining payoff has not been re-measured.

## 2026-11-25, re-measured: under 1 ms is left in the TIR passes

Measured on `8816b1020` (hello world and `bench/tree_transform.march`, private `HOME`, a
different unreachable `pfn` per run). Load was 7 to 24, so only paired deltas are meaningful.

| stage | functions (hello) | from `Authority` |
|---|---|---|
| lower | 6,351 | 113 |
| mono, fusion, defun | 48 | 3 |
| perceus | 5 | 1 |
| emitted | 8 defines | 0 |

- The three survivors are `Authority.check`, `describe` and `limit_text`. `check` is live code:
  `println` calls it (`stdlib/prelude.march`). `describe` and `limit_text` are kept because the
  prune keeps every `Show` impl (`Mono.implicit_callees`), including `impl Show(CapError)`.
  That same edge keeps about 40 of the 48 functions.
- **Correction to the note above:** `launch_init` is not reachable on native.
  `Auth_native.retarget` rewrites the injected call to `cap_rt_launch_init` before the prune.
- Mono through defun takes about 1 ms for all 48 functions.
- What Authority still costs is typechecking and lowering `stdlib/authority.march` itself.
  Stubbing the bodies the C policy replaces (1,451 lines to 934, and to 614 with `mock_for`
  stubbed too, which breaks mocks) saved 10 to 40 ms of CPU on about 2.1 s. The per-stage
  typecheck delta was not resolvable at that load.
- With the prune off (`--opt 0`, hot reload, JS), 160 Authority functions still reach mono.

**Options.** (A) Close this item. (B) Keep a `Show` impl only for a type the program can
reach: about 50 to 100 lines in `Mono.implicit_callees` / `Dce_pre_mono`, under 1 ms saved,
not specific to Authority. (C) Keep the March policy out of the native front end: split the
matcher and parser into a module loaded only by the interpreter and JS, plus a C twin for
`mock_for`. About 600 lines of March moved and 150 of C, two stdlib shapes and two tcenv
caches, for 10 to 40 ms (1 to 2%).

The larger target this points at is the front end: `typecheck` is about 0.74 s of the 1.14 s
a hello world takes to reach `cas-hash` (one run at load 3).

## Closed 2026-11-25

Closed with option A: the pre-mono prune removed the cost this item was filed for, and the
10 to 40 ms left in the front end is not worth splitting the policy module for.
