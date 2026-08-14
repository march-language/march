# SIMD closeouts, Task 3: pin mutual-TCO vector correctness

**Filed/closed:** 2026-08-13, third of a 3-task closeout plan for the SIMD
vector-types feature (`.superpowers/sdd/2026-08-12-simd-closeouts/`). Tasks 1
and 2 fixed a real bug each (vector arg-box leak; interpreter fma rounding
parity). Task 3 is a **pin**, not a fix: there is no bug here to close, only a
correctness invariant worth locking down against regression.

## Background

`lib/tir/llvm_tco.ml` combines a MUTUAL-recursion group (functions that
tail-call each other, not just themselves) into one dispatcher function with
a shared parameter-slot layout. A vector-typed parameter threaded through
that group keeps a uniform boxed `ptr` slot — the group boxes/unboxes the
vector on every call — unlike a SELF-tail-recursive function (`emit_fn`'s
path), which promotes a vector parameter to a native `<N x T>` register slot
(see `test/native/simd_leak_probe.march`, Task 1's fixture, and the fix it
pins).

This asymmetry is deliberate: extending native vector-slot residency to
mutual-recursion groups is real but unscoped work, tracked as "no todo" —
wontfix-until-demand — in `docs/simd-vectorization.md`'s "Known limits". It
is NOT something this closeout changes. What Task 3 adds is a fixture proving
the boxed path is still numerically correct, so a future person touching
`llvm_tco.ml`'s parameter-slot logic gets a red test instead of a silent
miscompile if they break it.

## What was added

- `test/native/simd_mutual_tco.march` — `even_step`/`odd_step` mutually
  tail-call each other threading a `Simd.F32x4` accumulator over a 16-lane
  `NativeArray.make_f32` source. BOTH steps add a freshly loaded 4-lane
  chunk; the symmetry is load-bearing, see "The vacuous first cut" below.
  `main` requires `Cap(IO.Console)` per the current strict capability rule.
  Verified interpreted first (`dune exec march --`) — prints `32.` — then
  `.expected` was produced from that run.
- `test/dune` — a compile-run-diff rule pair for `simd_mutual_tco`, modeled
  on `simd_vector_core`'s (compile once, run once, diff stdout against
  `.expected`; no RSS assertion needed here, this is a correctness pin, not
  a leak guard), PLUS an IR-shape rule pair `simd_mutual_tco_llvm_check`
  modeled on `simd_nested_closure_acc`'s: it re-emits with `--emit-llvm`,
  scopes an `awk` window to the `@__mutco_*` combined dispatcher's own
  `define`, and asserts the conjunction `mutco >= 1 && boxed >= 2 &&
  vadd >= 1` — a dispatcher exists at all, both accumulator slots are the
  uniform boxed `alloca ptr`, and the vector arithmetic survived (so a
  DCE'd body can't satisfy the first two vacuously).
- `lib/tir/llvm_tco.ml` — the mutual-TCO boxed-slot comment now cites this
  fixture and this file by path instead of only gesturing at
  docs/simd-vectorization.md.

## Verification

- `dune exec march -- test/native/simd_mutual_tco.march` → `32.` (interpreted)
- Compiled binary via the `test/dune` diff rule reproduces `32.` byte-for-byte
  (asserted every `dune build @test/runtest`).
- `simd_mutual_tco_llvm_check` observes `mutco=3 boxed=2 vadd=2` — the
  emitted dispatcher is
  `define double @__mutco_even_step_odd_step__(i64 %__tag__.arg, ...)` with
  `%even_step__acc.addr = alloca ptr` and `%odd_step__acc.addr = alloca ptr`,
  i.e. exactly the boxed mutual-group slots this file claims to pin.
- Manual trace: `a` is 16 lanes of `2.0`. The walk visits `i = 0, 4, 8, 12`
  (even, odd, even, odd) and adds one 4-lane chunk of `[2,2,2,2]` at each, so
  `acc` ends at `[8,8,8,8]` and `sum_f32x4` gives `32.0`. Matches.
- Falsification cycle run on the shape rule (see below), both directions.

## The vacuous first cut — and why the shape rule is mandatory

The first version of this fixture **did not exercise the mutual-TCO path at
all**, and its output diff could not tell. `odd_step` originally multiplied
the accumulator by `splat_f32x4(1.0)` instead of loading from the array. That
made it *pure*, hence an inline candidate in `lib/tir/inline.ml`; `even_step`
was not a candidate because `Simd.load_f32x4` reads memory. And
`direct_candidate_calls` only walks edges BETWEEN candidates, so the SCC
exclusion in `recursive_candidate_names` never saw the even↔odd cycle. The
inliner folded `odd_step` into `even_step`, collapsing mutual recursion into
SELF-recursion: the emitted IR was `define double @even_step` with
`%acc.addr = alloca <4 x float>` — the NATIVE-slot path that
`simd_leak_probe` already pins — with no `__mutco_*` symbol and no
`mutual_loop` block. `odd_step` was not emitted at all.

Note the trap: this is not specific to the inline *threshold*. Any change
that makes a step inlinable (purity, size, or a smarter SCC pass) collapses
the fixture, and the program keeps printing a plausible number. **Output
equality can never distinguish the two lowerings**, which is precisely how
this shipped green. Hence the IR-shape rule is part of the pin, not an
optional extra.

Falsification cycle (both directions actually run, not reasoned about):

| state | fixture | shape rule | counts |
|---|---|---|---|
| fixed | both steps load from `a` | GREEN | `mutco=3 boxed=2 vadd=2` |
| sabotaged | `odd_step` back to the pure `mul_f32x4(acc, splat(1.0))` | **RED** | `mutco=0 boxed=0 vadd=0` |
| restored | both steps load from `a` | GREEN | `mutco=3 boxed=2 vadd=2` |

The sabotage run was done twice. The first left `.expected` at `32.`, so the
diff rule went red too — which proves nothing about the shape rule's
independent value. The second set `.expected` to the sabotaged program's own
output (`16.`), making the **diff rule green while the shape rule stayed
red** (`test/dune`, the `simd_mutual_tco_llvm_check` assertion, `found
mutco=0 boxed=0 vadd=0`). That is the direct demonstration that the shape
assertion — and only the shape assertion — catches the collapse.

## Pointers

- `test/native/simd_mutual_tco.march`, `test/native/simd_mutual_tco.expected`
- `test/dune` (search `simd_mutual_tco` — four rules: compile/run,
  diff, `--emit-llvm` shape extraction, shape assertion)
- `lib/tir/inline.ml` (`run`, `recursive_candidate_names`,
  `direct_candidate_calls`) — the pass whose candidate-set scoping made the
  first cut vacuous
- `lib/tir/llvm_tco.ml` (the mutual-TCO param-slot alloca comment)
- Sibling closeouts: `specs/progress/2026-08-11-simd-tco-entry-box-leak.md`
  (Task 1), `specs/progress/2026-08-13-simd-fma-rounding-parity.md` (Task 2)
