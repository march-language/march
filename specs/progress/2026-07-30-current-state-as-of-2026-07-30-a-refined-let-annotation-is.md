# Current State (as of 2026-07-30, a refined `let` annotation is CHECKED)


**Counts:** `test_refinecheck` 365 (was 358), typing corpus 233/233 (was
231/231), `check-docs.sh` exit 0, stdlib false-positive sweep EMPTY.

The last refined position in the language that obliged nobody now does.

**The gap.** `let ys : {List(Int) | len(_) > 0} = []` compiled, and reported
`1 proved, 0 violated, 0 skipped`. `scope_add_binding`'s annotated arm —
`A.PatVar n, Some r -> (n.A.txt, r) :: sc` — admitted the predicate into the
refined scope channel **unconditionally**, so the annotation became a *fact*
about `ys` and the later `inner(ys)` was discharged off it. `cap verified`,
whose entire premise is "if it compiles, it is proved", accepted the module.
An author writing an annotation to *document* an invariant instead silently
manufactured it. Every other refined position (a parameter at a call site, a
return refinement, an `impl` method parameter) obliges somebody; this one did
not, and the direction was silent-unsound rather than false-positive, which is
why it survived so long.

**The fix.** `check_let_annotation` (`lib/refinecheck/refine_check.ml`, called
from the block-fold's `ELet` arm BEFORE `scope_add_binding` extends the scope)
reflects the binding as a synthesized one-parameter call: the annotation is the
precondition, the bound expression is the sole argument, and `check_call`
answers it with every resolver it already has — measures, constructor tags,
records, the composition machinery from PR #121/#126 — and the same
definite-failure stance, so an undecidable annotation is skipped, never
reported. There is no new solver code.

Two details are load-bearing. `param_names` carries the **let name**, not the
refinement's binder: `check_call` resolves the refined value through
`actual_of_name`, and only this arrangement makes the `len(ys)` spelling land on
the bound expression (the binder travels separately in `rparam.binder`). And the
bound name is shadowed out of all three fact channels first, so the predicate's
`ys` can never be attributed to an *outer* `ys` — the false-positive direction
this subsystem must never take.

**An unproven annotation grants no fact.** This is the half that is easy to miss:
filing the obligation but still admitting the predicate would re-open the hole in
a quieter form, since `let ys : {List(Int) | len(_) > 0} = zs` for an opaque `zs`
would file a Skipped obligation and then still hand `len(ys) > 0` to every later
goal — `inner(ys)` reporting Proved on a premise nobody established. It now
measures `0 proved, 0 violated, 2 skipped`. The cost is precision (an invariant
the author knows but the checker cannot see is no longer usable) and it lands
entirely in the safe direction, as more skips.

**A second gap closed as a side effect.** `{Int | n > 0}` over `let n` was the
one spelling that was not even trusted — it resolved against nothing and was
merely inert (`0 proved, 0 violated, 1 skipped`). Routing through
`param_names = [let name]` makes `n` denote the bound value, so `0 - 5` is now
seen and reported. All three spellings (`_`, `{v : T | p(v)}`, the bound name)
now behave alike, verified at 6 proved / 0 skipped for a three-spelling witness.

**+7 tests (358 → 365)**, a `let-annotation` group asserting obligation COUNTS
with each case's measured PRE-fix count recorded in its comment — four
false-annotation shapes (three spellings plus Int) that measured `1 proved` and
must now be `1 violated`, the true annotation that must be exactly `2 proved`
(asserting `>= 1` would have been vacuous), and the undecidable control that must
be `0 proved, 0 violated, 2 skipped`. The suite's first draft had four vacuous
cases and one that did not compile; all five were caught by measuring pre-fix
counts rather than by review. Bracketed in the corpus by
`accept/t130_refine_let_annotation_checked_and_composes` and
`reject/t131_refine_let_annotation_false`.

**Blast radius: none in-tree.** A refined `let` annotation appears 0× in
`stdlib/` and 0× in `specs/lang/types/` — all 98 `: {` occurrences in the stdlib
are on `fn` signature lines. The stdlib sweep is empty and every one of the 231
pre-existing corpus files is unchanged, so unlike the composition work (which
added assumptions consumed by many existing call sites and needed five
false-positive fix rounds) this change fires only on a construct no checked code
currently uses.
