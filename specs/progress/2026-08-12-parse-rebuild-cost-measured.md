# `[P2]` `Parse`: grammar-rebuild cost measured at 1.6×, not the 15× it was blamed for

**Status:** Investigated and closed without a code change (2026-08-12). The
filed premise was wrong.

## The claim, and why it was plausible

`delay(thunk)` calls `thunk()` each time it is *run*, so every recursive
descent re-executes the rule constructor. For a grammar written the natural
way, each nested value re-allocates the whole alternative chain — O(depth ×
grammar size) allocations per document. After the combinator JSON parser came
in **16.5× slower** than hand-written recursive descent
(`2026-08-12-json-combinator-ab.md`), this was filed as the leading suspect,
with the note that 16.5× was therefore "an upper bound, not a settled number",
and that a memoizing `delay` "would remove the larger term".

## The measurement

Isolated directly: the same grammar, the same input, the same work — once with
the element parser built **once and shared**, once with it **rebuilt per
element** through `delay`. 2001 elements, 100 iterations, compiled `--opt 2`,
each variant run in both positions.

| Element parser | Shared | Rebuilt | Overhead |
|---|---|---|---|
| trivial (`take_while1`) | 0.0442s | 0.0548s | **1.24×** |
| realistic (six-way `alt` with `map`/token wrappers) | 0.2153s | 0.3432s | **1.59×** |

Rebuilding a realistically-sized rule costs about **60%**, not fifteen hundred
percent. It accounts for roughly a 1.6× factor out of 16.5×.

## What that means

**The dominant cost is the combinator execution model itself** — one
`ParseReply` allocation per combinator step, plus closure indirection — not
grammar reconstruction. A memoizing `delay` would buy ~1.6×, which is real but
not transformative, and it is not free: it needs a mutable cell that March's
stdlib surface does not currently offer, and the knot-tying problem means a
recursive rule cannot simply be hoisted to a module-level value.

So: **not built.** The measurement is the deliverable. If combinator
throughput ever needs to improve, the target is the per-step allocation, and
this note says where not to look first.

## The lesson worth keeping

"Leading suspect" was doing real work in that todo, and it was wrong. The
isolating experiment cost one small program and ten minutes; building the
memoization would have cost a mutable-cell design, a new stdlib primitive, and
a knot-tying workaround — to win 1.6× while the actual 10× sat untouched.
A filed cause is a hypothesis, not a finding, until something separates it
from the alternatives.
