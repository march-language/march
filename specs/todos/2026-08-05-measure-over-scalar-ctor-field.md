# `[P3]` A `@[measure]` whose value is a scalar constructor FIELD is inert

Filed while attempting to contract `Array.get`/`Array.set`/`Array.pop` with a
bounds precondition (the `List.nth` treatment) as part of the proof-based
`cap no_panic` work. The attempt was **gated on feasibility and the gate came
back NO-GO**; this file records exactly where it breaks so the next attempt
does not re-derive it.

## The shape that does not work

`Array` is a persistent vector, `ptype PVec(a) = PVec(Int, Int, TrieNode(a), List(a))`
(`stdlib/array.march`), and it stores its element count directly:

```march
fn length(v) do
  match v do
  PVec(n, _, _, _) -> n
  end
end
```

Tagging this `@[measure]` **produces no error and no warning**. The M-b
soundness gate passes (it is total, terminating and pure), `build_measure_preamble`
accepts it, and `--refine-report` shows the contract's obligation being raised
at each call site. It simply never discharges — in either direction.

## Root cause: scalar constructor fields are erased before the solver sees them

`Refine_check.reflect_field` (`lib/refinecheck/refine_check.ml`, in the
call-site reflection near `reflect_dt`) reflects a constructor argument into
the SMT datatype term, and for any field whose sort is not a datatype it
substitutes a **fresh unconstrained constant**:

```ocaml
and reflect_field a = function
  | Smt.SData sub when sub <> "Elem" -> reflect_dt sub a
  | sort ->
    (* element / Int field: irrelevant to a structural measure -> fresh const *)
    incr dt_counter;
    let nm = Printf.sprintf "_e%d" !dt_counter in
    decls := (nm, sort) :: !decls;
    Some (Smt.Const nm)
```

The comment states the assumption plainly: a scalar field is "irrelevant to a
structural measure". That is true of every `@[measure]` in the tree today —
all of them are structurally recursive, so their value depends only on the
constructor TAGS and on sub-measures, never on an `Int` payload. It is exactly
false for `Array.length`, whose value IS the `Int` payload.

Dumping the VC for a literal-constructed vector makes it concrete. For
`aget(PVec(3, 0, TrieEmpty, Cons(x, Nil)), 1)` against
`idx : {Int | _ >= 0 && _ < length(v)}`, the goal sent to z3 is:

```smt2
(assert (not (and (>= 1 0) (< 1 (length (PVec _e3 _e2 TrieEmpty (Cons _e1 Nil)))))))
```

The `3` has become `_e3`, an unconstrained `Int`. The measure preamble is
correct and complete —

```smt2
(declare-fun length (M_PVec) Int)
(assert (forall ((n Int) (_w1 Int) (_w2 M_TrieNode) (_w3 M_List))
  (! (= (length (PVec n _w1 _w2 _w3)) n) :pattern ((length (PVec n _w1 _w2 _w3))))))
```

— so the axiom instantiates fine and yields `length(...) = _e3`. With `_e3`
unconstrained, `1 < _e3` is neither valid nor unsatisfiable, so the obligation
is `solver-undecided` and the checker correctly stays silent. Nothing is
wrong downstream of the erasure; the information was destroyed upstream.

## Bisection (scratch fixtures, `--check --refine-report`, caches cleared)

Everything below uses the same call shape as the working `List.nth`/`Tree.size`
suites, differing only in the measure body.

| measure body | non-recursive | proves? |
|---|---|---|
| `Node(l,x,r) -> 1 + size(l) + size(r)` (control) | no | **1 proved** |
| `N3(k, rest) -> 1 + size3(rest)`, ctor has an `Int` field | no | **1 proved** |
| `N5(k, rest) -> 1 + size5(rest) - 0` (not syntactically non-negative) | no | **1 proved** |
| `Box(_, _) -> 3` (single arm, literal body) | yes | **1 proved** |
| `Box(n, _) -> n` (single arm, field read) | yes | 0 proved |
| `Node4(n, m) -> n + 0` (two arms, field read) | no | 0 proved |
| `PVec(n,_,_,_) -> n` (the real `Array.length` shape) | yes | 0 proved |

The discriminator is *not* single-arm-ness, *not* non-recursion, and *not* the
syntactic non-negativity classification (`measure_body_nonneg` rejects a bare
variable body, but the `- 0` row shows a non-classified measure still proves).
The discriminator is solely **"does the measure's value depend on a scalar
constructor field"**. A non-recursive single-arm measure is otherwise fully
supported.

## Why the contract was not shipped anyway

`Panic_surface_by_proof` is fail-closed: only `Proved` is silent, and
`Skipped _` produces the panic-surface error. So adding `Array.get`/`set`/`pop`
to the covered set on top of an inert contract would reject *every* call under
`cap no_panic`, with no index — however obviously in range — able to satisfy
it, while advertising the name as proof-checked. Under `cap verified` it would
surface a permanently-undischargeable obligation. Both are worse than the
current honest syntactic ban.

## Partially mitigated 2026-08-05: the inertness is no longer silent

The underlying limitation is still open (everything above stands), but the
*silence* is fixed. `build_measure_preamble` now records an axiomatised measure
whose arm body is a bare erased-field read into `measure_scalar_field_dep`, and
`check_module` emits a warning at the measure's definition:

> `@[measure] `length` reads a constructor field that is not itself a data
> type, so its value cannot be computed at a call site and refinements using it
> will never be proved or refuted.`

Diagnostic only — it feeds no axiom, VC or verdict, so it cannot change what
any existing contract proves. It deliberately **under**-reports: the predicate
is "the body IS a bare field read", not "the body mentions an erased field",
because the broader version had a real false positive (`Zleaf(n) -> 0 * n`
mentions `n` but does not depend on it — caught by the LOAD-BEARING case in
test_refinecheck.ml's `measure-base-case-axiom` group while the broad version
was in tree). So `Node(n, m) -> n + 0` is equally inert and still draws
nothing. Tests: `measure-scalar-field-warn` (warn case, two negative controls,
plus the `0 * n` false-positive regression control).

## What a fix would look like

Reflect a scalar constructor field CONCRETELY when the actual argument is a
literal (or otherwise reflectable scalar), instead of always minting `_eN`.
`term_fits_sort` already accepts "any scalar term except a constructor
application" at an `SInt`/`SBool` field, so the datatype term stays well-sorted
and the `z3 -in` channel-desynchronisation hazard that motivated the erasure
does not apply to this case. The fresh-constant fallback must stay for a
non-literal scalar (an opaque variable), which is the actual case the comment
is protecting.

Risk to weigh before doing it: this widens what every existing contract can
prove, so it needs a full stdlib + ecosystem `--refine-report` sweep for new
violations (false positives), not just a "still compiles" check.

Only after that lands can `Array.get`/`Array.set`/`Array.pop` be contracted.
Until then `Array.get`/`Array.set`/`Array.pop` stay on the syntactic
`cap no_panic` ban list. (`Array.pop` was on NEITHER list when this was filed
and could panic inside `cap no_panic`; fixed the same day —
`specs/progress/2026-08-05-array-pop-not-on-no-panic-ban-list.md`.)
