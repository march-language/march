---
layout: docs
title: Memory Model
nav_order: 6.7
permalink: /docs/memory-model/
---

# Memory Model — How FBIP Works

March's headline promise is **functional code that runs in place**: you write
pure transformations over immutable data, and the compiler turns them into
mutation when it can prove no one will notice. There is no tracing garbage
collector, no stop-the-world pause, and — in the common "transform and return"
case — no allocation at all. This page explains the mechanism end to end.

The two ingredients are **Perceus reference counting** (deterministic, compiled
in) and **FBIP — Functional But In-Place** (the reuse optimization that rides on
top of it). The same uniqueness property that makes FBIP work also makes
*parallel* FBIP lock-free.

---

## Perceus: deterministic reference counting

Every heap value carries a small reference count (RC). The classic problem with
reference counting is throughput: naively, every time a value is passed,
returned, or bound, you pay an increment, and every time a reference dies you pay
a decrement. **Perceus** eliminates almost all of that cost with a compile-time
dataflow analysis that inserts `inc` and `dec` operations *precisely* at the
points where ownership actually changes — and then fuses, cancels, and elides
them:

- A function that receives a value and immediately returns a transformed version
  often needs **no increment at all** — the caller's reference is transferred.
- An `inc` followed by a `dec` on the same path provably cancels, and both are
  removed.
- What survives is only the genuinely uncertain residue.

The result is *deterministic* memory management. Because the `dec` that frees a
value is **emitted by the compiler at that value's last use**, deallocation
happens at a known program point:

| | Tracing GC (e.g. OCaml's minor/major) | Perceus RC |
|---|---|---|
| When memory is freed | Later, when a collection runs | At the value's last use, in line |
| Pause | Stop-the-world (or concurrent barriers) | None — no scan ever happens |
| Write barriers | On every pointer store | None (immutable-by-default has no stores) |
| Predictability | Depends on heap pressure | Compile-time, per-value |

No scan. No pause. No write barriers. Freeing is just a `dec` the compiler
already wrote into the code.

---

## Uniqueness = RC 1

The key fact Perceus exploits at runtime is simple: **when a value's last use
sees RC == 1, that value is uniquely owned.** No other reference exists, so
nothing else can ever observe it again. Its memory is about to become garbage.

If, *at that same point*, the program is allocating a new value **of the same
shape** (same constructor arity / size class), the runtime skips the allocator
entirely and **reuses the dying value's memory for the new one**. One uniqueness
check replaces an allocator round-trip — and the new value lands at the same
address, so it stays hot in cache.

This is the whole trick. FBIP is just this rule applied to constructor rewrites.

---

## FBIP: a worked before/after

Here is the canonical example — incrementing every leaf of a binary tree:

```march
ptype Tree = Leaf(Int) | Node(Tree, Tree)

pfn inc_leaves(t : Tree) : Tree do
  match t do
  Leaf(n)    -> Leaf(n + 1)
  Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))
  end
end
```

Read functionally, this allocates a brand-new tree: every `Leaf(n + 1)` and
every `Node(...)` is a fresh constructor. A naive implementation would allocate
a full second tree and then free the first.

**What the compiler actually emits.** When `inc_leaves` owns `t` uniquely (the
caller transferred its only reference), Perceus knows that the moment the `match`
scrutinizes a `Node(l, r)`, that `Node` cell is dying — its RC is 1 and its last
use is right here. The rebuild `Node(inc_leaves(l), inc_leaves(r))` has the
*same shape* as the cell being matched, so instead of allocating, the compiler
**reuses the matched cell in place**:

```text
before  (functional reading):           after  (what runs):

  match Node(l, r):                        match cell @0x40 = Node(l, r):
    allocate a NEW Node                      reuse cell @0x40
    fill it with (l', r')                    overwrite its two fields with (l', r')
    free the old Node                        (no alloc, no free — same address)
```

Conceptually the optimized form is `reuse t as Node(l', r')`: the `Node(l, r)`
you matched and the `Node(...)` you build are the *same heap cell*, with its
fields rewritten. Across the whole tree, a transform that looks like it allocates
N nodes allocates **zero** after the first pass — it walks the existing tree and
overwrites it.

**Why this is safe.** Immutability is what makes the rewrite invisible. Because
no other reference to the old `Node` can exist (RC == 1) *and* March values are
immutable (no aliased reference could have stashed a pointer into the old cell to
observe later), there is no observer to fool. The language semantics say "old
value gone, new value fresh"; the runtime says "same bytes, rewritten." Both
agree because no one else is looking.

> This is why `tree_transform` (the FBIP benchmark) runs roughly 15× faster than
> the equivalent C that allocates and frees a fresh tree each pass, and several
> times faster than OCaml's tracing GC: it does no allocator work at all in
> steady state.

---

## When reuse fires vs. falls back

Reuse fires when, at a constructor expression, the compiler can pair it with a
**uniquely-owned dying value of matching shape**. It falls back to a normal
allocation when it can't:

| Situation | Outcome |
|---|---|
| Matched value is uniquely owned (RC == 1) and the rebuild matches its shape | **Reuse in place** — no allocation |
| Matched value is **shared** (RC > 1 — someone else still holds it) | **Allocate fresh**, leave the shared value untouched |
| No same-shape value is dying at this allocation point | **Allocate fresh** |

The crucial property: **the fallback is automatic and always correct.** If a
value is shared, mutating it in place *would* be observable — so Perceus simply
doesn't. It allocates a new value and decrements the shared one's count. You
never get a wrong answer from a missed reuse; you only get an allocation. A
fallback is a performance characteristic, **never a bug**.

This is also why you can reason about reuse locally: sharing a value (keeping the
old binding around, storing it in two places) is exactly what *disables* reuse at
that site, and the compiler quietly does the safe thing.

---

## Writing allocation-free code

You don't write reuse directives — the compiler decides. But you can *see* its
decisions and steer them. The [LSP]({{ site.baseurl }}/docs/lsp/) reports, as
inlay hints and per-function code lenses:

- `♻ in-place` — FBIP fired: this value was reused without allocating.
- `⧉ copied` — a value had to be copied (it was shared, so reuse couldn't fire).
- `⚡ stack-allocated` — the value never reached the heap at all.

**The practical loop:**

1. Turn on performance annotations (`march.inlayHints.performanceAnnotations`).
2. Scan a hot function. `♻` and `⚡` are good. A `⧉ copied` *inside a hot loop*
   is a refactor target — that's an allocation you can probably remove.
3. Rewrite so the value you transform is **consumed**, not aliased.

**The rules that keep reuse firing:**

- **Consume the value you transform.** Destructure it and rebuild from the
  pieces; don't read the original again afterward.
- **Don't reuse the old binding after rebuilding.** A second use of the old value
  pushes its RC above 1 at the rebuild point — reuse can't fire.
- **Keep the constructor shape and arity matched.** Reuse needs the dying cell
  and the new cell to be the same size class.

Here is a `⧉`-triggering anti-pattern next to its `♻` fix:

```march
ptype Box = Box(Int, Int)

-- ⧉ copied: `b` is read AGAIN after the new Box is built, so the old Box is
-- still live (RC > 1) at the rebuild point. The compiler must allocate a copy.
pfn bump_copied(b : Box) : (Box, Int) do
  match b do
  Box(x, y) ->
    let updated = Box(x + 1, y)
    let old_x   = match b do Box(ox, _) -> ox end   -- second use of `b`
    (updated, old_x)
  end
end

-- ♻ in-place: `b` is consumed exactly once. Nothing else references the old
-- Box, so its cell is rewritten in place — zero allocation.
pfn bump_reused(b : Box) : Box do
  match b do
  Box(x, y) -> Box(x + 1, y)
  end
end
```

If `bump_copied` genuinely needs the old field, read it *before* you rebuild
(bind `x` in the same `match`, then return it) rather than matching `b` a second
time — that collapses the two uses into one and reuse fires again.

---

## Parallel FBIP needs no locks

The uniqueness that powers FBIP also makes it **lock-free across cores**.

Consider summing or transforming the two children of a tree in parallel:

```march
Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))
```

`l` and `r` are **disjoint subtrees**. When the parent `Node` is uniquely owned,
each child is uniquely owned within its own branch — RC == 1 in its own context.
Hand `l` to one core and `r` to another and each rewrites its subtree in place
with **nothing to synchronize**: there is no shared cell two cores could both
touch, so there's no lock, no atomic RC traffic, no contention. Uniqueness *is*
the disjointness proof.

This is exactly the property the `parallel` benchmark relies on: sibling subtrees
have independent RC chains, so in-place reuse stays correct on both sides with no
locking. The same idea scales to actor message passing — see the
[parallelism]({{ site.baseurl }}/docs/parallelism/) guide, and
[linear types]({{ site.baseurl }}/docs/linear-types/) for the ownership-transfer
("zero-copy send") case where a `linear` value is *guaranteed* RC == 1.

---

## Where this sits in the bigger picture

FBIP is one layer of a stratified memory model. The others reinforce it:

- **`linear` / `affine` values** have statically known lifetimes — the compiler
  inserts `free` at the last use with zero RC bookkeeping (see
  [linear types]({{ site.baseurl }}/docs/linear-types/)). A `linear` value is
  the *strongest* FBIP case: RC == 1 by construction.
- **Immutable-by-default** means pointer fields are never written after
  construction, which is what eliminates write barriers — and what makes in-place
  reuse unobservable.
- **Whole-program monomorphization and defunctionalization** make types concrete
  and remove heap-allocated closures, so escape analysis can stack-allocate the
  many values that never outlive their call (`⚡ stack-allocated`).

The net effect: most values never touch the heap, the ones that do are usually
reused rather than reallocated, and the residual frees are deterministic `dec`
operations the compiler already wrote — not a collector you have to wait for.

---

## Next Steps

- [Linear Types]({{ site.baseurl }}/docs/linear-types/) — ownership that
  guarantees RC == 1, and zero-copy actor sends.
- [Safety by Construction]({{ site.baseurl }}/docs/safety-by-construction/) —
  how the safety layers stack on one function.
- [Parallelism]({{ site.baseurl }}/docs/parallelism/) — the scheduler that runs
  disjoint, uniquely-owned subtrees across cores.
- [LSP & Editors]({{ site.baseurl }}/docs/lsp/) — turning on the `♻ / ⧉ / ⚡`
  performance hints.
