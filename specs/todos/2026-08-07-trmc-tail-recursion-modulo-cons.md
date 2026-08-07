# TRMC: tail-recursion-modulo-cons

**Filed:** 2026-08-07
**Priority:** P2 — a real constant-factor win on every list producer, and it
removes a warning that currently exports work to users. Not urgent; not blocked.

Taken from Lorenzen & Leijen, *Reference Counting with Frame Limited Reuse*
(ICFP'22) §2.4.1. See `specs/todos/2026-08-07-drop-guided-reuse-coverage.md` for
the sibling item from the same paper (measured, and declined).

> "With TRMC, such function can make its tail call inside any tail-position
> *expression* consisting of just constructors and non-allocating total
> expressions. […] This is done by pre-allocating the `Cons` node ahead of the
> recursive call with a *hole* in the tail field, which is later assigned by the
> recursive call."

March has plain TCO (`lib/tir/llvm_tco.ml`) and no TRMC — `grep -ri trmc lib/`
is empty. Instead, `lib/typecheck/typecheck.ml:12055` **warns** and tells the
user to hand-write an accumulator.

## What this is actually worth (measured 2026-08-07)

The naive pitch — "O(n) stack becomes O(1)" — is not the win here, because the
stdlib has already paid that cost by hand. `List.map`, `filter`, `filter_map`,
`append`, `flat_map` and `range` are all written as accumulator + `reverse`
(`stdlib/list.march:230` for `map`), which is exactly what the warning pushes
people into.

Nor is the win allocation. Compiling a `List.map` probe and reading the
post-Perceus TIR (`MARCH_DUMP_TXT=tir-perceus`) shows FBIP **already fires in
both loops**:

```
fn go$apply$4133($clo, lst : List(Int), acc : List(Int)) : List(Int) =
  ...
  Cons($f298, $f299) -> ...
    let $t296 : Int = call_ptr f(h) in
    let $t297 : List(Int) = reuse lst as List.Cons($t296, acc) in   <-- reuse
    call_ptr go(t, $t297)

fn go$apply$3589($clo, lst : List(Int), acc : List(Int)) : List(Int) =   -- reverse
  ...
    let $t280 : List(Int) = reuse lst as List.Cons(h, acc) in            <-- reuse
    call_ptr go(t, $t280)
```

So on a unique list `List.map` is already ~0 net allocations. **The cost is that
it traverses twice** — once to build reversed, once to `reverse`.

**The win is halving the traversal count** on every list producer: a ~2x
constant factor on `map`/`filter`/`filter_map`/`append`/`flat_map`/`range`, plus
letting user code be written in the natural style and still get the reuse.

### Consequence for staging

The compiler feature alone buys nothing for the stdlib — those functions are
*already* tail-recursive, so TRMC has nothing to transform. Collecting the win
requires a **second, separate work item**: rewriting the stdlib producers back
into the natural non-accumulator form. That rewrite is behaviour-preserving and
easy to verify, but it must be planned, or Phase 1–4 ship and nothing gets
faster.

## Design

### The lever: we do not need to emit a loop

`Llvm_tco` already turns a self tail call into a loop. TRMC only has to *produce
a tail-recursive function*; codegen comes free. That is what keeps this tractable.

### Shape

    fn map(f, xs) = match xs { Nil -> Nil; Cons(x,xx) -> Cons(f x, map(f,xx)) }

becomes a destination-passing helper whose recursive call **is** a tail call:

    fn map(f, xs) = match xs {
      Nil -> Nil
      Cons(x,xx) -> let c = Cons(f x, HOLE) in map_dps(f, xx, &c.1); c }

    fn map_dps(f, xs, dst) = match xs {          -- self-tail-recursive
      Nil -> dst := Nil
      Cons(x,xx) -> let c = Cons(f x, HOLE) in dst := c; map_dps(f, xx, &c.1) }

### Eligibility

A self-recursive function where every recursive call is either in tail position
or is an **argument of a data-constructor application in tail position**, with
the path from the constructor to the call consisting only of constructors and
non-allocating total expressions.

### New TIR nodes

Two, and this is the bulk of the mechanical cost:

- `EAllocHole of ty * atom list * int` — allocate a constructor with field `i`
  uninitialized.
- `ESetField of atom * int * atom` — write into a hole. `Llvm_data.emit_store_field`
  already exists and is already used for in-place mutation on the actor-struct
  `EReuse` path, so the codegen side is close to free.

A new `Tir.expr` constructor ripples to every pass that matches exhaustively.
From the `EReuse` audit that is: `dce`, `cprop`, `escape`, `inline`,
`join_points`, `fusion`, `defun`, `cap_attrib`, `beta_adt`, `simplify`,
`known_call`, `drop`, `borrow`, `perceus` (+ `_liveness`, `_elide`, `_fbip`,
`_scrut`), `js_emit`, `llvm_emit`, `pp` — call it ~18 files, mostly one-line
arms. This is the same tax Route B carried in the reuse-coverage item; here it
buys something.

### Pipeline placement

**Post-lower, pre-mono.** Recursion must still be syntactically visible: by
`tir-perceus` the stdlib's inner `go` is a closure invoked via `call_ptr`
(see the dump above — `Known_call` does *not* devirtualize it), so a late pass
would not recognise self-recursion at all. Running before mono also means one
transformation per source function rather than per monomorphic instantiation.

Perceus then sees an ordinary tail-recursive function and inserts RC normally.

## RC hazards — the part to get right

1. **Deep-drop of an unfilled hole.** `march_decrc` just `free()`s and does not
   walk children, but `Drop.run` synthesizes deep-drop functions that *do*. A
   deep-drop reaching a cell with an unfilled hole reads that field. Mitigating
   fact: `march_alloc` returns **zeroed** memory and `IS_HEAP_PTR(0)` is false,
   so a hole reads as a no-op for RC. **Verify this holds on every path** (panic
   unwinding, early return, the `$jp_clo` default arms) before relying on it.
2. **Ownership transfer at the hole write.** `dst := c` moves the local's
   reference into the parent with no incref. Perceus must not also drop `c`.
   This is the classic destination-passing RC subtlety and the most likely
   source of a double-free.
3. **`dst` is an interior pointer.** It points *into* a heap cell and must never
   be RC'd itself. `Rc_types.needs_rc` and `Escape` both have to treat it as a
   raw `TPtr`. The cell it points into stays alive because the parent holds it.
4. **Interaction with `join_points`.** Default arms become `$jp_clo` closures,
   which starved FBIP once before (see `perceus_fbip.ml`'s `try_fbip_sink` RC-op
   case). The TRMC matcher must see through the same shape.

## Staging

| Phase | Work | Rough size |
|---|---|---|
| 1 | ~~Eligibility analysis + reporting, no transformation.~~ **DONE 2026-08-07** — see below | small |
| 2 | ~~`EAllocHole` / `ESetField` + codegen + the pass arms~~ **DONE 2026-08-07** | medium |
| 3 | The DPS transformation itself | medium |
| 4 | Perceus/Drop/Escape integration — the four hazards above | **the real work** |
| 5 | Downgrade/remove the `typecheck.ml:12055` warning for now-eligible functions | small |
| 6 | *Separate item:* rewrite stdlib producers into natural style to collect the win | small, high value |

Phase 1 is worth doing on its own — it is cheap and it either justifies or kills
phases 2–5 the same way the instrumentation killed the reuse-coverage item.

## Phase 1 results (landed 2026-08-07)

`lib/tir/trmc.ml` — analysis only, no transformation, no effect on emitted code.
Runs post-lower from `bin/main.ml`; reports to stderr under `MARCH_TRMC_REPORT=1`.
Unit tests in `test/test_trmc.ml` (7 cases, wired into `run_codegen`).

Over the full stdlib link closure:

| verdict | count |
|---|---:|
| **eligible** (all self-calls transformable) | **19** |
| **mixed** (partially — see below) | 1 |
| non-trmc | 72 |
| already-tail | 542 |

All 19 eligible sites are `List.Cons@1` — the hole is always the list tail. The
eligible set is the expected shape: `Sort.insert_sorted`, `Tuple.zip`,
`ConsistentHash.ring_insert`, `Merkle.pair_up`, `PubSub.list_remove_first`,
`Presence.list_remove_meta`, several `list_append`/`list_concat` helpers.

`OrderedMap.tree_map` is the sole **mixed** case and it is the paper's §2.4
shape: `Node(tree_map(l), k, v, tree_map(r))`. Only one call can own the hole,
so the analysis assigns it to the one that runs last (`Tree.Node@3`) and reports
the other as a real recursive call that survives. Partially transformable —
worth having, but it does not become a loop.

### Two classifier corrections found while validating

Both were caught by checking the output against known-good source rather than
trusting the first number, and both are recorded as tests:

1. **Branching recursion was over-counted.** The first version reported *both*
   calls in `Node(self(l), .., self(r))` as transformable. Only the last one on
   a path can be the destination. Fixed by requiring the continuation to contain
   no further self-call.
2. **Join points were misread as value computations — the larger error.**
   `lower_match` hoists a match's fall-through into `ELetRec([jp], ..)` bound to
   a `$jp_clo` variable, and a join-point body is the match's *continuation*, so
   it inherits tail position. Treating it as a let RHS reported `List.last`'s
   plain tail call as unreachable. Fixing it moved **43 functions** out of
   `non-trmc` into `already-tail` (115 → 72) and added one eligible.

   The fix keys on `fn_kind = FnJoinPoint`, not a `$jp` name prefix.
   **Approximation carried into Phase 2:** it assumes every call site of a join
   point is itself in tail position. That holds for `lower_match`'s fall-through
   join points but is not checked. Phase 2 must verify per call site rather than
   inherit.

## Measured: natural style is 1.8x SLOWER today (2026-08-07)

Before betting Phase 2 on Phase 6, I measured the two styles directly. Same
work (20k-element list, 2000 successive maps, list threaded so it stays unique),
compiled `--opt 2`, alternating runs:

| style | traversals | time | peak RSS |
|---|---:|---:|---:|
| natural (`Cons(h+1, nmap(t))`) | 1 | ~0.30s | 4.3 MB |
| accumulator + `reverse` (today's stdlib) | 2 | ~0.17s | 3.4 MB |

**The one-traversal version is 1.8x slower and uses 28% more memory.** The
mechanism is the paper's §2.6 frame-limitedness example, reproduced exactly —
post-Perceus TIR for the natural version:

```
let $t28942 : List(Int) = nmap(t) in
reuse xs as List.Cons($t28941, $t28942)
```

The reuse token `xs` is live *across* the recursive call, so the function holds
one cell per stack frame:

> "Here, `r` is live during the recursive call and so reuse analysis can hold on
> to as many `Cons` cells as either the list is long or the stack allows."

This is the good news about our reuse — it is frame-limited exactly as the paper
proves drop-guided reuse to be — but it means the natural style pays O(n)
retained cells on top of O(n) stack.

### Two consequences

1. **Phase 6 must not land before phases 2–5.** Rewriting the stdlib producers
   into natural style *without* TRMC is a measured 1.8x regression, not a win.
   The current accumulator+`reverse` style is not a workaround for a compiler
   weakness — today it is genuinely the faster code.
2. **It sharpens the estimate of what TRMC buys.** TRMC collapses the O(n)
   frames to O(1), which removes *both* the stack and the retained tokens while
   keeping the single traversal. The accumulator version spends ~0.085s per
   traversal; a TRMC'd single traversal should land near that, i.e. roughly
   **1.5–2x faster than today's stdlib**. Treat this as an estimate, not a
   measurement: it cannot be measured without the transformation, because March
   has no source-level way to express the hole.

## Phase 2 results (landed 2026-08-07)

`EAllocHole of ty * atom list * int` and `ESetField of atom * int * atom` added
to `Tir.expr`, with arms in **22 files**. Nothing constructs them yet — Phase 3
does — so they are exercised from hand-built TIR in `test/test_trmc.ml`.

Emitted IR for `alloc_hole List.Cons(42, _) hole=1` then a fill:

```
%hp1  = call ptr @march_alloc(i64 32)      ; 2-field cell
%fp3  = getelementptr i8, ptr %hp1, i64 16
store i64 42, ptr %fp3                      ; field 0
                                            ; offset 24 NOT stored — the hole
%fp8  = getelementptr i8, ptr %ld6, i64 24
store ptr %ld7, ptr %fp8                    ; ESetField fills it
```

Gated by two tests: the module passes the same LLVM verifier the native-fixture
gate uses, and the hole's slot is stored **exactly once** — by the fill, never
by the allocation. The second test is the one that matters: without it,
`EAllocHole` could quietly become "EAlloc with a null argument", which would
still verify and still run while invalidating Phase 3's ownership reasoning.

**Runtime behaviour is NOT yet proven end-to-end.** No program can construct
these nodes until Phase 3, so nothing has executed a hole-fill. That is Phase
3's gate, not this one.

### Decisions made while implementing

- **No interior-pointer ("destination") value in the IR.** The TRMC helper will
  pass the OBJECT and bake the field index into the specialized helper. Sound
  because every iteration of a single-constructor TRMC loop writes the same
  field of a freshly allocated cell. This removes hazard #3 (interior pointers
  needing a new unowned-pointer notion in `Rc_types`/`Escape`) entirely.
- **Hazard #1 confirmed at the allocator.** `march_alloc` is a `calloc`
  (`march_runtime.c`), so a hole reads as 0 and `IS_HEAP_PTR(0)` is false — an
  RC op or deep-drop reaching an unfilled hole is a no-op, not a wild
  dereference. Phase 3 still has to confirm this on panic/early-return paths.
- **Perceus `ESetField` case is written for hazard #2**: ownership MOVES into
  the object, so no IncRC is emitted for the stored value and it stays in the
  live-before set rather than being treated as a last use.
- **`ESetField` stores through a `ptr` slot.** Correct because the hole is by
  construction the recursive field, which is the ADT's own Boxed
  representation. Phase 3 must not select a hole over an unboxed Int/Float
  field without revisiting that store — noted in the code.
- **Repr guard mirrors `EStackAlloc`**: `EAllocHole` of a Newtype-/Niche-repr
  type fails loudly rather than building a boxed cell that consumers decode as
  erased.
- **CAS fingerprint includes the hole index** (tags `0x53`/`0x54`). Two
  allocations differing only in which field is left unwritten are different
  programs; omitting the index would let the cache serve one for the other.
  The change is purely additive, so existing artifact hashes are unaffected.

Full suite green: compiler 797, eval 256, codegen 555, stdlib 833.

## Phase 3 prototype (2026-08-07) — measured, then set aside. NOT in the tree.

A working destination-passing rewrite was built and benchmarked to answer "is
this actually an improvement?" **It is not, yet**, so it was deliberately NOT
landed — the code is not in this repo. The measurements below are the reason
phases 4A/4B exist and are worth keeping even though the prototype is gone.

`Trmc.transform_module` built `f$dps(params, dst)` from an `Eligible` function
with exactly one modulo-cons site; v1 refused intervening lets between the call
and the `EAlloc`, which removes the effect-reordering hazard entirely.

Output is **correct** on both benchmarks. Measured against the same 20k/2000
workload:

| variant | time | peak RSS |
|---|---:|---:|
| natural, TRMC **off** | ~0.29s | 4.37 MB |
| natural, TRMC **on** | ~1.00s | **3.44 MB** |
| accumulator + `reverse` | ~0.17s | 3.41 MB |

**The memory prediction held**: peak RSS drops to accumulator levels, because
the retained reuse tokens are gone. **The time is 3.5x WORSE.** Two causes, both
visible in the post-Perceus TIR and both squarely Phase 4 work:

### A. FBIP reuse is destroyed

Before: `reuse xs as List.Cons($t28941, $t28942)` — zero allocations on a
unique list. After:

```
dec_rc xs;
let $trmc52 : List.Cons = alloc_hole List.Cons($t28941, _) in
```

`Perceus_fbip.same_arity` only pairs a scrutinee drop with an `EAlloc`, never an
`EAllocHole`, so every iteration now allocates. That is n allocations per
traversal where there were 0 — the dominant cost.

This is the paper's "TRMC interacts well with reuse analysis" claim, and it does
**not** come for free: the reuse analysis has to learn to produce a
reuse-with-hole (`reuse xs as Cons(h, _)`). That is the single highest-value
next step.

### B. A post-call drop breaks the tail call

```
$dst.1 <- $trmc52;
nmap$dps(t, $trmc52);
dec_rc $trmc52          <-- should not exist
```

The cell was moved into `$dst`, then passed as the recursive call's destination.
Perceus's `ESetField` case correctly declines to treat the STORE as a last use,
but the subsequent use-as-argument is still the last one, so a post-call drop
lands anyway. Consequences:

1. The recursive call is no longer in tail position, so `Llvm_tco` cannot make
   it a loop — **the O(n) stack is still there**. TRMC's whole point is missed.
2. It is a drop of a cell the parent now owns through its field.

Fix direction: `$dst`-role parameters must be borrowed at the call site, and a
value moved by `ESetField` must be excluded from post-call drops for the rest of
its scope — not just at the store.

### What is NOT established

Cause B is read off the TIR, not demonstrated as a crash. **ASAN is unusable
here**: `MARCH_SANITIZE=1` hangs on this program with TRMC *off* as well, so the
hang is a pre-existing property of that build in this environment and proves
nothing about TRMC. Any future memory-safety claim about this transformation
needs a working sanitizer path first.

### Verdict

The structural transformation is sound and the memory result confirms the
model; the time result is gated on (A) and (B), both Phase 4 work. The
prototype was reverted rather than landed gated — see below for what replaced
it as coverage.

### What the prototype DID establish about Phase 2

Phase 2's own tests go straight from hand-built TIR to `emit_module`, skipping
every intermediate pass — so the `EAllocHole`/`ESetField` arms in ~20 files
(mono, defun, perceus, escape, dce, cprop, inline, ...) were written but
unexercised. The prototype was the first thing to push hole-bearing TIR through
the whole pipeline at `--opt 2`, and it produced correct programs. That is real
validation of those arms.

Since the prototype is not in the tree, that coverage is now provided directly
by `test/test_trmc.ml`'s `trmc-pipeline` group, which runs a hole-bearing module
through `mono -> defun -> perceus -> escape` and asserts:

- both nodes survive intact;
- the resulting IR still passes the LLVM verifier;
- **no drop is emitted for the value moved into the hole** — pinning the
  ownership-move rule that Phase 4B depends on. Verified non-vacuous: the
  stored variable is still present under its own name post-pipeline, and the
  pass chain demonstrably ran (Perceus inserted RC ops into an RC-free fixture).

### One open question for the IR surface

Fixing (A) means expressing "reuse this cell, write field 0, leave field 1 a
hole". That cannot be built from the current nodes: `EReuse (a, ty, args)`
demands every field, and unlike a fresh `calloc`'d cell a REUSED cell's hole
slot holds a stale live pointer, so it must be explicitly cleared rather than
left alone. The likely shape is `EReuse` gaining a hole index, mirroring
`EAllocHole` — a small amendment to the IR surface that will land after this
one.

### Verdict on phases 2–5

19 functions, all one constructor shape, plus one partial. That is a real but
narrow set, and the payoff on those 19 is only collected together with Phase 6.

The measurement above is what should decide it. TRMC is not a marginal
constant-factor tweak: it is the thing that makes the natural style viable at
all. Today natural style is 1.8x slower, so the whole idiom is effectively
unavailable — which is why the stdlib is written the way it is, and why the
compiler emits a warning steering users the same way. Estimated 1.5–2x on list
producers *plus* unlocking the idiom is a stronger case than the bare count of
19 suggested.

Recommend proceeding to Phase 2, with Phase 6 explicitly gated behind it.

## Verification

- 16 perceus TIR goldens will churn; regenerate deliberately and read the diff.
- `bench/list_ops.march` (HOF/closures) and `bench/tree_transform.march` (FBIP).
  Compiled, `--opt 2` — interpreted runs are useless here.
- A new map/filter-heavy benchmark: the existing set does not isolate the
  two-traversal cost this targets.
- ASAN sweep. Hazards 1–3 are all use-after-free or double-free shaped, and this
  area's bugs are historically compiled-only and sometimes flaky — one clean run
  proves nothing.
- Full suite including Slow.

## Open questions

- Do we TRMC through *multiple* constructor layers (the paper's `Node(B, ...)`
  rebalancing case, §2.4), or only a single constructor? Single first.
- Mutual TRMC? `Llvm_tco` has a mutual-TCO group emitter; out of scope for v1.
- Does the hole-write need to be atomic for actor-shared values? v1 should refuse
  TRMC on any type that can cross an actor boundary rather than answer this.
