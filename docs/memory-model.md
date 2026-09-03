---
layout: docs
title: Memory Model
nav_order: 5.8
permalink: /docs/memory-model/
---

# Memory Model: How FBIP Works

March's headline promise is **functional code that runs in place**: you write
pure transformations over immutable data (the style where you never mutate
anything, you just build new values from old ones) and the compiler turns
that into ordinary in-place mutation wherever it can prove no one will notice
the difference. There is no tracing garbage collector, no stop-the-world
collection, and, in the common "transform and return" case, no allocation at
all. This page explains the mechanism end to end, from first principles, so
you don't need a compilers background to follow it.

The claim to hold onto is **deterministic, not pauseless**. No collector scans
your heap and no pause stops your program at a moment it picks. But freeing is real
work that happens *inline*, and releasing a large structure costs time
proportional to its size; see
[drop cascades](#drop-cascades-freeing-is-work-you-scheduled) below. The
difference from a tracing GC is not that the work disappears; it is that you
choose when it happens, and it is the same every run.

The two ingredients are **[Perceus](https://www.microsoft.com/en-us/research/publication/perceus-garbage-free-reference-counting-with-reuse/)
reference counting** (deterministic, compiled in; the technique comes from
the 2021 paper *"Perceus: Garbage Free Reference Counting with Reuse"* by
Reinking, Xie, de Moura, and Leijen, if you want the formal treatment) and
**FBIP, Functional But In-Place** (the reuse optimization that builds on top
of it). The same uniqueness property that makes FBIP work also makes
*parallel* FBIP lock-free: no thread coordination needed.

---

## Perceus: deterministic reference counting

Every heap value includes a small **reference count (RC)**: a running count of how many
places in the program currently hold a pointer to it. The classic problem with
reference counting is throughput: naively, every time a value is passed,
returned, or bound, you pay an increment, and every time a reference dies you pay
a decrement, and those add up fast.

**Perceus** eliminates almost all of that cost. Instead of inserting an `inc`/`dec`
around every single use, the compiler traces, ahead of time, exactly where each
value is created and where it's used for the last time; then it inserts `inc`/`dec`
operations *only* at the points where ownership of a value actually changes, and
simplifies away as much of that as it can:

- A function that receives a value and immediately returns a transformed version
  often needs **no increment at all**: the caller's reference is transferred.
- An `inc` followed by a `dec` on the same path cancels (a fact the analysis
  can prove) and both are removed.
- What remains is only the truly uncertain residue.

The result is *deterministic* memory management. Because the `dec` that frees a
value is **emitted by the compiler at that value's last use**, deallocation
happens at a known program point:

| | Tracing GC (e.g. OCaml's minor/major) | Perceus RC |
|---|---|---|
| When memory is freed | Later, when a collection runs | At the value's last use, in line |
| Who chooses the moment | The collector | Your code's control flow |
| Cost of a free | Amortized into collection cycles | Paid inline, proportional to the data being released |
| Worst-case stall | A collection over live data you didn't choose | A drop cascade over a structure you did |
| Write barriers | On every pointer store | None (immutable-by-default has no stores) |
| Predictability | Depends on heap pressure | Compile-time, per-value, identical every run |

No scan, no write barriers, and no collector deciding when to interrupt you.
Freeing is just a `dec` the compiler already wrote into the code, which is
exactly why its cost lands where that `dec` is, and not somewhere convenient.

---

## Uniqueness = RC 1

The key fact Perceus exploits at runtime is simple: **when a value's last use
sees RC == 1, that value is uniquely owned.** No other reference exists, so
no part of the program can observe it again. Its memory is about to become garbage.

If, *at that same point*, the program is allocating a new value **of the same
shape** (same constructor arity / size class), the runtime skips the allocator
entirely and **reuses the dying value's memory for the new one**. One uniqueness
check replaces an allocator round-trip, and the new value lands at the same
address, so it stays hot in cache.

This is the whole trick. FBIP is just this rule applied to constructor rewrites.

---

## FBIP: a worked before/after

Here is the canonical example, incrementing every leaf of a binary tree:

```march
mod TreeDemo do
  ptype Tree = Leaf(Int) | Node(Tree, Tree)

  pfn inc_leaves(t : Tree) : Tree do
    match t do
    Leaf(n)    -> Leaf(n + 1)
    Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))
    end
  end

  pfn sum_leaves(t : Tree) : Int do
    match t do
    Leaf(n)    -> n
    Node(l, r) -> sum_leaves(l) + sum_leaves(r)
    end
  end

  -- A runnable entry point: build a small tree, increment every leaf, and
  -- fold it back to a number so the demo cell below can print a result.
  fn demo() : Int do
    let t = Node(Leaf(1), Node(Leaf(2), Leaf(3)))
    sum_leaves(inc_leaves(t))
  end
end
```

Read functionally, this allocates a brand-new tree: every `Leaf(n + 1)` and
every `Node(...)` is a fresh constructor. A naive implementation would allocate
a full second tree and then free the first.

**What the compiler actually emits.** When `inc_leaves` owns `t` uniquely (the
caller transferred its only reference), Perceus knows that the moment the `match`
scrutinizes a `Node(l, r)`, that `Node` cell is dying: its RC is 1 and its last
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
N nodes allocates **zero** after the first pass: it walks the existing tree and
overwrites it.

**Why this is safe.** Immutability is what makes the rewrite invisible. Because
no other reference to the old `Node` can exist (RC == 1) *and* March values are
immutable (no aliased reference could have stashed a pointer into the old cell to
observe later), there is no observer to fool. The language semantics say "old
value gone, new value fresh"; the runtime states "same bytes, rewritten." Both
agree because no one else is looking.

> This is why [`tree_transform`](https://github.com/march-language/march/blob/main/bench/tree_transform.march)
> (the FBIP benchmark) runs roughly 15× faster than the equivalent C that
> allocates and frees a fresh tree each pass, and several times faster than
> OCaml's tracing GC: it does no allocator work at all in steady state. See the
> [benchmark results](https://github.com/march-language/march/blob/main/bench/RESULTS.md)
> for the full numbers.

**Try it.** The `TreeDemo` module above is runnable: this cell builds the sample
tree `Node(Leaf(1), Node(Leaf(2), Leaf(3)))`, runs `inc_leaves`, and sums the
result. The leaves `1, 2, 3` become `2, 3, 4`, so the total is `9`:

```march
println("sum after inc_leaves: " ++ int_to_string(TreeDemo.demo()))
```

---

## When reuse fires vs. falls back

Reuse fires when, at a constructor expression, the compiler can pair it with a
**uniquely-owned dying value of matching shape**. It falls back to a normal
allocation when it can't:

| Situation | Outcome |
|---|---|
| Matched value is uniquely owned (RC == 1) and the rebuild matches its shape | **Reuse in place** (no allocation) |
| Matched value is **shared** (RC > 1; someone else still retains it) | **Allocate fresh**, leave the shared value untouched |
| No same-shape value is dying at this allocation point | **Allocate fresh** |

The crucial property: **the fallback is automatic and always correct.** If a
value is shared, mutating it in place *would* be observable, so Perceus simply
doesn't. It allocates a new value and decrements the shared one's count. You
never get a wrong answer from a missed reuse; you only get an allocation. A
fallback is a performance characteristic, **never a bug**.

This is also why you can reason about reuse locally: sharing a value (keeping the
old binding around, storing it in two places) is exactly what *disables* reuse at
that site, and the compiler does the safe thing with no visible sign.

---

## Writing allocation-free code

You don't write reuse directives; the compiler chooses. But you can *see* its
decisions and steer them. The [LSP]({{ site.baseurl }}/docs/lsp/) reports, as
inlay hints and per-function code lenses:

- `♻ in-place`: FBIP fired: this value was reused without allocating.
- `⧉ copied`: a value had to be copied (it was shared, so reuse couldn't fire).
- `⚡ stack-allocated`: the value never reached the heap at all.

**The practical loop:**

1. Turn on performance annotations (`march.inlayHints.performanceAnnotations`).
2. Scan a hot function. `♻` and `⚡` are good. A `⧉ copied` *inside a hot loop*
   is a refactor target: that's an allocation you can probably remove.
3. Rewrite so the value you transform is **consumed**, not aliased.

**The rules that keep reuse firing:**

- **Consume the value you transform.** Destructure it and rebuild from the
  pieces; don't read the original again afterward.
- **Don't reuse the old binding after rebuilding.** A second use of the old value
  pushes its RC above 1 at the rebuild point; reuse can't fire.
- **Keep the constructor shape and arity matched.** Reuse needs the dying cell
  and the new cell to be the same size class.

Here is a `⧉`-triggering anti-pattern next to its `♻` fix:

<!-- scroll:skip -->
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

**Pinning the result with a contract.** Once a hot function shows only `♻` and
`⚡`, you can make the compiler keep it that way:

<!-- scroll:skip -->
```march
@[no_alloc]
pfn bump_reused(b : Box) : Box do
  match b do
  Box(x, y) -> Box(x + 1, y)
  end
end
```

`@[no_alloc]` is checked on the compiled form, after reuse and stack promotion
have been decided, so the reusing version above passes and the `⧉ copied`
version does not. A later edit that reintroduces an allocation — here or in
anything the function calls — fails the build instead of silently regressing.
`@[no_alloc(warn)]` reports the same finding as a warning, and
`@[no_alloc(assume)]` marks a wrapper around an unknown closure or an `extern`
as trusted. `forge fix --contracts` adds the attribute to every function the
compiler has already verified. Two caveats worth knowing: a nullary
constructor of a variant that also has payload-carrying cases (`Nil` in
`List`) is a real heap cell today, so returning a fresh one fails the
contract, and a `Float` stored into a generic field is boxed, which counts.

If `bump_copied` truly needs the old field, read it *before* you rebuild
(bind `x` in the same `match`, then return it) rather than matching `b` a second
time; that collapses the two uses into one and reuse fires again.

---

## Parallel FBIP needs no locks

Normally, running code on two threads at once means you need locks or atomic
operations to stop them from corrupting the same memory at the same time; even
something as simple as two threads incrementing the same reference count needs
synchronization, or you can lose an update. The uniqueness that powers FBIP sidesteps
this entirely and makes it **lock-free across cores**.

Consider summing or transforming the two children of a tree in parallel:

<!-- scroll:skip -->
```march
Node(l, r) -> Node(inc_leaves(l), inc_leaves(r))
```

`l` and `r` are **disjoint subtrees**. When the parent `Node` is uniquely owned,
each child is uniquely owned within its own branch: RC == 1 in its own context.
Hand `l` to one core and `r` to another and each rewrites its subtree in place
with **no state to synchronize**: there is no shared cell two cores could both
touch, so there's no lock, no atomic RC traffic, no contention. Uniqueness *is*
the disjointness proof.

This is exactly the property the `parallel` benchmark relies on: sibling subtrees
have independent RC chains, so in-place reuse stays correct on both sides with no
locking. The same idea scales to actor message passing; see the
[parallelism](/docs/parallel-collections/) guide, and
[linear types]({{ site.baseurl }}/docs/linear-types/) for the ownership-transfer
("zero-copy send") case where a `linear` value is *guaranteed* RC == 1.

---

## Drop cascades: freeing is work you scheduled

Deterministic does not mean free. When the last reference to a structure dies,
its children's references die with it, and *that work happens right there*.

March frees an aggregate in one of two ways. Usually the structure is
**destructured**: a `match` arm that owns the value it matched on releases the
box and hands the children to the extracted bindings, so the cost is spread
across a traversal you were doing anyway. But when a structure is released
**without** being taken apart (you borrowed it, or ignored it, and the owner
simply drops it at the end of its scope), the compiler synthesizes a deep-drop
function for that type and calls it instead. Conceptually:

```
drop a list  =  free this cell, then drop its element, then drop the rest
```

So dropping a one-million-element list walks one million cells. What that means
in practice:

- **Cost is proportional to what actually dies**, not to heap size, and not to
  how much data is still live. Dropping a *shared* structure (someone else still
  retains it) is O(1); only the last owner pays the walk.
- **It will not overflow the stack.** The recursive step is in tail position and
  compiles to a loop, so long lists iterate rather than recurse.
- **The stall is schedulable.** Because the release point is a program point you
  can see, you can move it: release a large structure before a latency-critical
  section instead of inside one, or hand it off to a task with a loose
  deadline. That is the real advantage over a tracing GC: not that the work
  vanishes, but that you decide where it lands.
- **Ignore it and it shows up in tail latency.** A request handler that builds
  and releases a large intermediate structure pays that walk inside the request.
  This is the most likely reason a p99 looks poorer than a p50 in otherwise
  allocation-light March code.

---

## Cycles: not collected, and not reachable from ordinary code

**March has no cycle collector.** Reference counting cannot reclaim a reference
cycle: each object in the loop is still referenced, so no count can fall to
zero. If a cycle were to form, it would leak: silently, permanently, with no
diagnostic.

The reason this is not a practical hazard is that the language makes cycles hard
to build in the first place, rather than cleaning them up afterwards:

- **Immutable data cannot close a cycle.** Closing a loop requires writing a
  back-pointer into a value that already exists. March values are built once and
  never mutated, so ordinary data forms trees and DAGs, never cycles.
- **Linear values cannot participate in one.** A cycle needs at least two
  references to the same value; `linear` means exactly one owner.
- **Actors do not share pointers.** One actor reaches another through a
  capability, not a raw pointer into its heap, so there is no material a
  cross-actor cycle could be made of.

Two caveats worth stating clearly. This is a *design argument*, not a mechanized
proof: no part of March is mechanically verified today (a Lean 4 metatheory
effort is planned, not started), and no runtime detector would tell you if the
argument were wrong. And it covers the data you write: the runtime
does build self-referential shapes internally (a self-recursive closure captures
itself), which are handled by compiler-inserted drops on specific paths rather
than by reference counting by itself. The residual risk therefore sits in the
compiler, not in your program.

A deferred, per-actor cycle collector is sketched in the GC design notes for a
future in which March exposes unrestricted mutable values. None of it is
implemented today, and no part of the language today needs it.

---

## Where this sits in the bigger picture

FBIP doesn't work in isolation; it's one layer of several that reinforce each other. You don't
need to understand every layer below to use March, but here's how they fit together:

- **[`linear` / `affine` values]({{ site.baseurl }}/docs/linear-types/)** have
  statically known lifetimes: the compiler already knows, from just the type,
  *exactly* where each one is used for the last time, so it can insert `free` there
  directly, with zero RC bookkeeping at all. A `linear` value is the *strongest* FBIP
  case: RC == 1 by construction, guaranteed by the type system rather than inferred by
  the compiler.
- **Immutable-by-default** means pointer fields are never written after
  construction, which is what eliminates write barriers, and what makes in-place
  reuse unobservable.
- **Whole-program monomorphization and defunctionalization**, two compile-time passes
  that turn generic, closure-using code into plain, concrete code (a separate copy of a
  generic function per concrete type it's used with; closures turned into ordinary data
  instead of heap-allocated function values), remove a lot of what would otherwise force
  heap allocation. That, in turn, lets the compiler prove that many values never
  outlive the function call that created them, so it can put them on the stack instead
  of the heap entirely (`⚡ stack-allocated`).

The net effect: most values never touch the heap, the ones that do are usually
reused rather than reallocated, and the residual frees are deterministic `dec`
operations the compiler already wrote, not a collector you have to wait for.

---

## Next Steps

- [Linear Types]({{ site.baseurl }}/docs/linear-types/): ownership that
  guarantees RC == 1, and zero-copy actor sends.
- [Safety by Construction]({{ site.baseurl }}/docs/safety-by-construction/):
  how the safety layers stack on one function.
- [Parallelism](/docs/parallel-collections/): the scheduler that runs
  disjoint, uniquely-owned subtrees across cores.
- [LSP & Editors]({{ site.baseurl }}/docs/lsp/): turning on the `♻ / ⧉ / ⚡`
  performance hints.
