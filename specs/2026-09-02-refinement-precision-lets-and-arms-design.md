# Two precision gaps: `let` equalities and nested-pattern facts

Filed 2026-09-02. Status: **landed 2026-09-02** (`211b501c`, `40c51d1d`,
`f1801a38`). Both parts shipped in the simplified forms described under
"Corrections made while planning" below, not in the original Design A / Design
B forms, which are kept for the record.
Landed record, with the corpus sweep, the oracle classification and the
measured deviations: `specs/progress/2026-09-02-refinement-precision-lets-and-arms.md`.

## Problem

The 2026-09-01 diagnosis work named two facts the checker never derives and
left them out of scope. Both are now measured.

**A. `let`-bound values.** A `let` with a literal or arithmetic right-hand
side records nothing: the block fold in `refine_check.ml:247-263` populates
`lets` only for `EApp` and alias `EVar` right-hand sides, and
`scope_add_binding` only for an annotated `let` or a call with a refined
return. `reflect_scalar` (`refine_resolve.ml:479-514`) then reflects the name
as a bare unconstrained constant. So `Enum.chunk_every(xs, 0)` is a definite
violation while `let n = 0` followed by the same call is `unconstrained-subject`.

**B. Nested-pattern binders.** In `stdlib/list.march:124-130`:

```march
Nil          -> panic("List.last: empty list")
Cons(x, Nil) -> x
Cons(_, t)   -> last(t)
```

`t` is a `Cons`, but the recursive call reports `unconstrained-subject`. Two
independent reasons (`refine_check.ml:306-463`): the arm-exclusion machinery
only phrases facts over the top-level scrutinee, and it abstains on
`Cons(x, Nil)` because `arm_excludes_tag` (`refine_scope.ml:615-626`) requires
irrefutable sub-patterns. A binder like `t` receives no scope entry of any
kind; its SMT term is a fresh `Const "t"` (`refine_call.ml:1570`). The `len`
bridge is `path_resolve_tester` (`refine_call.ml:1899-1932`), which fires only
on a bare variable argument.

**Corpus evidence, stated plainly.** Over `stdlib/list.march`'s six user-code
skips: one is shape B (line 128, `last`) and none is shape A with a literal.
The other four are `let t = pmap_threshold()` (an unrefined builtin return) and
`let csize2 = if ... end`, which neither part of this design reaches. The
value of A is generality; the value of B is that the flagship example
verifies. Neither should be sold as a large corpus win.

## Non-goals

- No `if`-expression right-hand sides in A. Encoding `ite` is a separate
  decision with its own soundness questions.
- No facts for builtin calls without a refined return (`pmap_threshold()`).
  That is a stdlib annotation question, not a checker one.
- No change to reporting. Every obligation that moves must move to `proved`
  or `violated`; a skip that changes bucket is a bug.

**Corrections made while planning (2026-09-02), before implementation.**
Both designs below simplify once the existing path-fact machinery is read
closely. (A) A `let` equality needs no new channel: pushing `n == rhs` as an
ordinary PATH fact reuses the path translator, which already reflects
arithmetic over variables, the `path_shadow` rule, which already retires a
fact when `n` or any mentioned name rebinds, and `push_user`, so
`Undecided.diagnose` sees it. (B) The nested-pattern fact can be phrased over
the current arm's BINDER, `not is_Nil(t)`, which `path_resolve_tester`
already bridges to `len(t) > 0` for a bare variable; no selector aliasing and
no bridge extension are needed for the `Cons(x, Nil)` shape. The plan
implements the simplified forms; the original text is kept below for the
record.

## Design A: a `let` equality channel

Add `lets_eq : (string * A.expr) list` to `call_ctx` (all three construction
sites in `refine_check.ml`, per that record's "all of them, or none" note).
The block fold records `(n, rhs)` when `rhs` is a literal or an arithmetic
expression over literals and names (the shapes `reflect_scalar` already
reflects). Shadowing follows `launder_shadow` exactly: an entry retires when
its key rebinds or when any name its right-hand side mentions rebinds.

At `check_call`, for each entry, reflect the right-hand side with
`reflect_scalar` under the current scope; if it reflects, `push_user
(Smt.Eq (Smt.Const n, term))` and declare `n` at that sort. If it does not
reflect, push nothing. These are user facts (the author wrote the binding), so
they go through `push_user`, not `push_structural`, and `Undecided.diagnose`
sees them.

Soundness: the equality holds at every point after the binding until the name
or a mentioned name rebinds, which is exactly the shadow rule. The right-hand
side shapes admitted are pure and deterministic.

## Design B: nested-pattern binder facts

Three pieces, each pinned separately.

1. **Binder as selector.** When an arm's pattern is `PatCon (ctor, subs)` over
   a bare scrutinee `s`, and `subs` at index `i` is `PatVar t`, register
   `t -> App ("<ctor>_<i>", [term_of s])` in a new binder-alias map on
   `call_ctx`, shadowed on rebinding of `t` or `s`. `reflect_dt` consults the
   map before minting a fresh constant. The selector spelling is the one
   `refine_resolve.ml:264` already emits and `undecided.ml`'s `known_head`
   already whitelists.
2. **Refutable-sibling exclusion.** Extend the arm loop's exclusion fold
   (`refine_check.ml:427-444`) so that a previous unguarded arm
   `PatCon (c, subs)` with a refutable `PatCon (d, [])` at index `i` yields
   the path fact `not is_d (<c>_<i>(s))` for later arms whose head is also
   `c`. Only nullary sub-constructors and one level of nesting, which is the
   `Cons(x, Nil)` shape. A guarded previous arm yields nothing, as today.
3. **Bridge over selectors.** `path_resolve_tester` accepts an argument that
   is a selector application whose result sort is the `List` sort, producing
   `len(<c>_<i>(s)) = 0` or `> 0` via `resolve_measure_app` instead of
   `measure_of_var`.

With all three, `last(t)`'s goal `len$t > 0` reflects as
`len(Cons_1(xs)) > 0`, and the path carries `not is_Nil(Cons_1(xs))`, which
the existing rewrite turns into `len(Cons_1(xs)) > 0`.

Soundness: arm order is evaluation order, and a previous unguarded arm that
did not match means its pattern did not match, which for a nullary
sub-constructor at a fixed field is exactly the negated tester over the
selector.

## Testing

A: `let n = 0` into `{Int | _ > 0}` is `violated` with the same
argument-level label the literal case prints; `let n = k + 1` under a guard
`k >= 0` into `{Int | _ > 0}` is `proved`; rebinding `k` between the `let` and
the call retires the fact (the obligation is skipped, never proved). Mutation:
disable the push and the `proved` case reddens.

B: `stdlib/list.march`'s `last` verifies (`proved` at line 128), asserted on
the real file through the corpus sweep as well as on a fixture. A guarded
sibling arm produces no exclusion (silence test). A two-level nesting
(`Cons(x, Cons(y, Nil))`) produces no exclusion (silence test, since only one
level is admitted). Three mutations, one per piece, each reddening its own
case.

## Measurement and oracle

Sweep the corpus before and after. Report the per-bucket table; every moved
obligation must move to `proved` or `violated`. Run `scripts/refine-oracle.sh`
with RED-proof first and classify every moved line as "newly proved",
"newly violated", or unexplained; unexplained is a bug.

## Cost

A: one `reflect_scalar` per `lets_eq` entry per call site; entries are few.
B: one selector term per nested binder; no new solver queries. Measure cold
`--check` on a trivial file against the pre-change compiler.
