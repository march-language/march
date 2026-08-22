# Floats in an erased slot: the case-merge box and the destructured field box are owned now (fixed 2026-08-22)

Closes `specs/todos/2026-08-21-boxed-option-float-cells-never-freed.md` (this
file is its `git mv`). Landed together with, but rooted differently from,
`specs/progress/2026-08-22-task-handle-and-ok-wrapper-leak.md` — see "Was there
one shared root?" below.

Probe: `test/native/erased_float_slot_leak_probe.march` (in `@runtest`,
threshold `< 1000`).

## What leaked

A `Float` never fits an erased (uniform-ptr) slot as itself: the uniform
representation is a `march_alloc_float` box, and every such box needs an owner.
Two places in `lib/tir/llvm_case.ml` created or inherited one and named none.

### 1. The case merge — 20,000 of the filed 30,000

Every arm coerces its value into the ptr-typed `result_slot`, so a `"double"`
arm allocates a fresh box on the way in. The merge already knew how to
unbox-and-free that box — but only when EVERY arm reaching it was `"double"`,
and the comment on `arm_result_tys` claimed "arms that don't reach merge …
contribute nothing" while only the `unreachable` default was actually excluded.
The match-compilation fallback default (`Lower_state.nonexhaustive_panic`,
`panic_("non-exhaustive pattern match")`) is emitted as an ordinary arm whose
`@march_panic_ext` call is *declared* to return ptr. That `"ptr"` spoiled the
all-double proof for **every** Float-armed match on a boxed ADT — including the
filed `match opt do Some(x) -> x; None -> 1.0 end` — even though the arm
diverges and never reaches the merge at runtime.

New `arm_diverges` recognises exactly the four primitives that call
`@march_panic`/`@march_panic_ext` and never return (`panic`, `panic_`, `todo_`,
`unreachable_` — the same names `llvm_emit`'s `is_known_fn` table lists) and
keeps them out of the arm-type list. Precision matters in one direction only: a
false positive would unbox-and-free a ptr another arm legitimately produced,
i.e. a use-after-free. A user-written `panic("…")` routed through a March
prelude wrapper is deliberately NOT recognised — its callee is an ordinary
March fn — and keeps the pre-existing leak: the safe direction.

### 2. The destructured field — 10,000 of the filed 30,000

`Some(x)` on an `Option(Float)`: the ctor's declared field is generic, so the
slot holds the box. The branch bound the BOX and let the body unbox it, which
left the cell's reference with no successor — the binder is a Float,
`Rc_types.needs_rc TFloat` is false, so Perceus emits no drop for it, and the
cell's own free is shallow.

The binder is now the raw `double`, which is exactly what
`Llvm_toplevel.emit_fn`'s apply-wrapper prologue already does for a Float
parameter arriving through this same ABI. Copying the double out is what makes
the release sound: the binder then aliases nothing. The box is released on the
`march_decrc_freed` **unique** path — the path on which the cell was actually
freed, which is the proof that no other holder exists. On the shared path
(RC > 1 after the dec) the cell survives and still owns the box, so nothing is
released and — unlike an ordinary heap field — nothing is dup'd either.

FBIP whole-cell reuse (`EReuse` on the scrutinee) is exempt: there the field
keeps its old ptr binding, because a raw-double binder would make any
reconstruction re-box and store a FRESH box into the reused cell, orphaning the
one already in the slot — a new leak traded for the fixed one. That path keeps
its pre-existing behaviour, which is the safe direction and the same
conservatism the reuse counterpart of the leading-dec path already applies.

### 3. The niche merge — found while probing, same defect, never had the fix

`Repr.Niche`'s merge (an outer `Option` whose payload is a heap pointer, e.g.
`Option(Option(Float))`) had no arm-type bookkeeping at all, so it always
handed the caller the live box. It now shares `arm_diverges` and the same
unbox-and-free. Nothing in the tree covered it before.

## The filing's decomposition was wrong; the total was right

The filing read 30,000 as "10000×2 Some allocations + 10000×1 None cells, i.e.
everything on this path leaks", and concluded the outer cell's drop must be
missing. It is not: the outer cells were always freed. The real split is
20,000 merge boxes (one per iteration, from BOTH arms) + 10,000 `Some` field
boxes. The `None` half leaks only its merge box, which is why the arithmetic
coincidentally matched.

The filing's item 3 — "who is meant to own `march_alloc_float`'s box once
`march_unbox_float` has read the double out" — is the question that turned out
to matter, and the answer is "whoever the cell handed it to, on the path where
the cell died".

## Measured

Darwin arm64, `--compile --opt 2`, `live_allocs()` delta, 20,000 iterations per
leg. Control = pristine `origin/main` 8897bb1a, built by file-copy swap of
`lib/tir/llvm_case.ml` + `lib/tir/llvm_emit.ml` (never `git stash` — shared
stash stack).

| leg | unfixed | fixed | shape |
|---|---:|---:|---|
| `boxed_leg` | 30,000 | 0 | `Option(Float)` — merge box + field box |
| `niche_leg` | 40,000 | 0 | `Option(Option(Float))` — niche merge |
| `mixed_leg` | 40,000 | 0 | `Cell(String, Float)` — heap AND Float field |
| `mixed_shared_leg` | 60,000 | 0 | double-free witness |
| `shared_leg` | 60,000 | 0 | double-free witness |
| `int_leg` | 0 | 0 | control: `Option(Int)` is niche, no boxes |
| **total** | **230,006** | **6** | |

The filed reduction itself: 30,000 → 0. Stdout is byte-identical between the
two builds, so every leg's arithmetic is unchanged.

The healthy figure is a small CONSTANT, not a rate — 6, and it does not move
with the iteration counts. Each defect scales linearly with them, so the
`< 1000` bound is orders of magnitude from both and falsifiable in both
directions (verified by running the assertion against both measured values).

## The trap this fix walked into, and how the witnesses caught it

Releasing the box at the *unbox* site is a use-after-free — the hazard
`specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md` records. The two
`*_shared` legs are the direct witnesses for the destructure half: they
destructure a still-live cell twice, so a release on the shared path hands the
second read freed memory.

It also bit for real, from an unexpected direction. `march_task_await`'s
`mk_ok` stores `task[3]`'s pointer into a fresh `Ok` cell **without taking a
reference for it**, and double-await is legal — so two `Ok` cells aliased one
box. Once the `Ok(v)` destructure started releasing erased-slot Float boxes,
the second `match task_await(t)` on one Float task read freed memory (measured:
the second await printed `0`, then SIGTRAP). Fixed at the source, in
`task_await`'s emit: the `"double"` arm now takes a `+1` so the `Ok` cell owns
its own reference. Only that arm — a ptr payload's `Ok(v)` destructure binds a
heap variable that Perceus drops, consuming `task[3]`'s one reference exactly as
before, and a `+1` there would convert today's balance into a per-await leak.
`task_lifetime_leak_probe.march`'s double-await leg pins it.

## Was there one shared root?

Partly. Items 1–3 here and the `task_await` `+1` are one root — *a heap value
crossing into an erased slot needs an owner named at the crossing* — and they
are fixed in one place each. The task-handle leak
(`specs/progress/2026-08-22-task-handle-and-ok-wrapper-leak.md`) is NOT the
same root: it is type-independent and is about a builtin not honouring a
calling convention Perceus already applied. The third filed item
(`specs/todos/2026-08-21-ecallptr-owned-arg-borrow-callee-leak.md`) is a third
root again — two sides of one ABI disagreeing — and is still open; see it for
why.

## Still open, deliberately

* A heap (non-Float) field extracted from a boxed generic ctor is not dropped
  either — `Cell(int_to_string(n), 0.5)` still leaks its `String` at
  1/iteration. Newly filed as
  `specs/todos/2026-08-22-boxed-ctor-heap-field-binder-not-dropped.md`;
  `mixed_leg` uses a string LITERAL precisely so that defect cannot
  contaminate this measurement.
* `task[3]`'s own reference to a Float payload box is still never released
  (the Task's free is shallow) — the unchanged remainder of
  `specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md`.

## Verification

* Probe RED 230,006 → GREEN 6; the filed reduction 30,000 → 0.
* Both `*_shared` double-free witnesses print identical sums on both builds.
* Full `dune build --root . @runtest` (includes this probe, the task probe,
  `native_float_box_abi_leak_probe`, the #313 acc probe, the SIMD and timer
  probes), `scripts/run-tests.sh`, TIR golden snapshots, sanitize sweep,
  `bench/list_ops.march` compiled — see the landing commit message.
