# Design: the four open refinement P3s

Written 2026-09-13, after the enforcement plan
(`specs/plans/2026-09-13-refinement-enforcement-holes-plan.md`), the two
silent holes (`specs/progress/2026-09-13-string-return-refinement-enforced.md`,
`specs/progress/2026-09-13-desugar-dropped-refinement-enforced.md`) and
container subtyping (`specs/progress/2026-09-13-container-subtyping.md`)
landed. What is left on refinements is four P3 items, each small enough to
design fully here and each independent of the others. One section per item:
the problem as it stands, the design, the soundness argument, the tests that
would prove it (a REJECT fixture for every new obligation, and a control for
every new assumption), and the effort.

Shared facts every section relies on (verify before building; lines drift):

- `Refine_scope.callback_sig_of_ty` synthesises the `fn_sig` a call through a
  refined callback parameter is checked against; it fills only `refined`
  (the domain) and leaves `ret = None` (the codomain).
- `Refine_check.pass_site_obligation` / `check_pass_sites` are the pass-site
  contravariance check (decision (a) of the plan); `Callback_domain` and
  `Element_domain` share one definite-failure rule in `check_call`: a
  `Refuted` model on a fresh symbolic subject whose only constraint is the
  declared refinement is a real counterexample.
- `Refine_scope.elem_refinement` is the single test of "does the checker
  model this container"; `contenv` is the element-fact channel;
  `check_elements` is the element-obligation site.
- `check_call`'s `reflect_cache` memoises the reflection of every name the
  predicate mentions, keyed by the name (`"$self"` for the refined
  parameter's own binder, `"$path$<n>"` for path-fact names, the bare name
  for a sibling parameter).
- `reflect_field` (call-site datatype reflection, `refine_call.ml`) mints a
  fresh unconstrained `_eN` for every non-datatype constructor field;
  `term_fits_sort` already admits a scalar term at an `SInt`/`SBool` field.

---

## 1. Arrow positions: the domain is enforced but reported otherwise; the codomain is not enforced

Todo: `specs/todos/2026-09-13-arrow-position-refinements.md`. Hole fixture:
`test/refine_audit/holes/arrow_domain.march` (the last one in the set).

### Where it stands

`fn apply(f : ({Int | _ > 0}) -> Int, x : Int)`: a call `f(x)` inside `apply`
IS checked (the callback env, since 2026-07-26), and passing a callable to
`apply` is checked at the pass site (contravariance, plan phase 2). The
audit nonetheless reports the `Arrow_domain` site Unenforced, because rule 1
("nested is unenforced") fires before anything looks at the arrow. That is
an audit-precision gap, not a checker gap.

`fn apply(f : Int -> {Int | _ > 0})`: the CODOMAIN refinement is genuinely
unenforced on both sides. `callback_sig_of_ty` leaves `ret = None`, so `let
y = f(x)` inside `apply` learns nothing about `y`; and nothing at the pass
site asks whether the passed callable's own return satisfies `_ > 0`.

### Design

**1a. Audit precision.** In `Refine_audit.classify`, before rule 1:

- a site with `position = Arrow_domain`, origin `Param _` / `Lambda_param _`
  / `Let_annot _`, whose declared type `callback_sig_of_ty` accepts (a
  single-argument arrow with a refined domain) reports `Enforced`;
- everything else at `Arrow_domain` keeps the current reason, reworded to
  say what IS modelled: a single-argument arrow's domain at a parameter or
  `let`; a multi-argument (tupled or curried) domain, or an arrow inside a
  container or record field, is not.

The `arrow_domain` hole fixture retires; the pinned-audit fixtures need no
change (they use the two-layer container shape).

**1b. Codomain assumption.** `callback_sig_of_ty` fills `ret` from a refined
codomain (`return_refine_sorted`'s shape applied to the codomain type) and
`ret_sort` accordingly. Consumption goes through `scope_add_binding
~postcond`, whose `postcond` is `postcond_of ctx defs` — resolution by NAME in
`defs`, which never sees a callback. Extend `postcond_of` to consult the
callee env when name resolution fails: `visit` already has `cb` in hand at
every `let`, so `postcond_of ctx defs` becomes `postcond_of ctx defs cb`
(one extra argument at the ~6 construction sites of `call_ctx`). A local
`fn`'s proved return (phase 1) and a `let`-bound lambda's are then consumed
by the same change, closing the "honest but not yet consumed" note in
`specs/progress/2026-09-13-block-fn-refinement-enforced.md`.

**1c. Codomain obligation, at the pass site.** Extend `pass_site_obligation`
to a second check when the expected arrow's codomain is refined: the passed
callable's own return refinement must IMPLY it. Sources, as for the domain:

- a named function or local with a PROVED `ret` (its `fn_sig.ret`, which
  `gate_unverified_posts` has already cleared when unproved): the VC
  `ret_pred($r) ⇒ codomain_pred($r)` on a fresh `$r`, subject
  `Callback_codomain` (new, with the domain's definite-failure rule: `$r`'s
  only constraint is the callable's own return refinement);
- an inline lambda: run `check_fn_post_verdict` on the synthesised
  definition with `fn_ret_ty = the codomain type`, i.e. verify the lambda's
  body against the expected codomain directly (the lambda has no
  declaration of its own to imply from);
- a callable with no return refinement: a recorded skip.

Wording: "the return of `g`, passed where `Int -> {Int | _ > 0}` is expected,
does not satisfy the expected codomain refinement".

### Soundness

1b admits a fact only when the passed callable was obliged to establish it
(1c), exactly the phase-2 pairing for the domain: no assumption without an
obligation at every route in. 1c's implication is definite by the same
argument as `Callback_domain`. A multi-argument callback is neither obliged
nor assumed (as today), and the audit says so.

### Tests

`arrow-position` group: (1a) `classify` on `apply`'s parameter is Enforced;
a two-argument arrow stays Unenforced with the reworded reason. (1b) `fn
apply(f : Int -> {Int | _ > 0}, x : Int) do let y = f(x)  need(y) end` proves
under `cap verified`; the control with an unrefined codomain fails. (1c)
`apply(fn n -> 0, 1)` is rejected (the lambda's body returns 0 under the
expected `_ > 0`); `apply(pos_fn, 1)` with `fn pos_fn(n : Int) : {Int | _ >
0}` proves; `apply(unrefined_fn, 1)` is a recorded skip. A ledger assertion
on the skip. Oracle IDENTICAL expected (no corpus program refines a callback
codomain today); `refine-oracle.sh` decides.

Effort: 1a half a day; 1b+1c one to two days, mostly the `postcond_of`
plumbing.

---

## 2. Container subtyping beyond one layer of `List` / `Option`

Todo: `specs/todos/2026-09-13-container-subtyping-other-containers.md`.

### Where it stands

`elem_refinement` admits `List(…)` / `Option(…)` with a refinement one layer
down. Three shapes remain unenforced, reported by the audit as `Type_arg`,
`Nested`: (a) other containers (`Result({Int | p}, e)`, `Map(k, {Int | p})`,
`Set({Int | p})`, a user ADT's argument), (b) two layers
(`List(List({Int | p}))`), (c) elements reached through a stdlib function
(`List.head(xs)` returns `Option(Int)` as far as the checker knows).

### Design

**2a. Other registered containers.** Generalise `elem_refinement` from the
two hard-coded names to "a registered ADT whose constructors carry the type
argument at a known field position". `register_adt_names` /
`register_field_sorts` already record every constructor's field sorts; what
is missing is which field holds which TYPE PARAMETER. Record, per variant
constructor, the list of `(field index, type-parameter index)` pairs where
the field's declared type is a bare type variable (`Cons(a, List(a))` → field
0 is parameter 0; `Some(a)` → field 0 is parameter 0; `Ok(a)` / `Err(e)` of
`Result(a, e)` → `Ok`'s field 0 is parameter 0, `Err`'s field 0 is parameter
1). Then:

- `elem_refinement` returns, for `C(t1, …, tn)`, the list of
  `(parameter index, refinement)` for every refined argument;
- `check_elements` on a literal `K(args)` looks up `K`'s pairs and checks
  each argument at a parameter position that has a refinement — this is
  exactly the current `Cons`/`Some` arm, table-driven; a self-typed field
  (`List(a)` in `Cons`) recurses with the same container refinement, as the
  tail does today;
- the `EMatch` element facts use the same table: a `PatVar` sub-pattern at
  a refined parameter position gets the fact, at a self-typed position gets
  the container entry.

`Map` and `Set` are opaque runtime types, not ADTs the checker registers;
they stay out until a literal syntax and constructor model exist for them —
the audit reason names them.

**2b. Two layers.** `contenv` entries become
`(container, element : elem_ty)` where `elem_ty` is either a refinement
(today) or a nested container entry. `check_elements` on a literal whose
element is itself a container recurses with the inner entry; `EMatch`
hands a `PatVar` at a nested position the inner CONTAINER entry (into
`contenv`), not a scalar fact. One layer of recursion is enough for the
todo's shape; the representation admits any depth.

**2c. Elements reached through a stdlib function.** This is the parametric
half and the only part that is a design decision rather than an extension:
`List.head : List(a) -> Option(a)` must be read as carrying the element
refinement through `a`. Proposed rule, deliberately narrow: for a call whose
callee's DECLARED signature has a type parameter `a` appearing (i) in one
argument position as the element of a container the actual is a `contenv`
variable of, and (ii) in the return type as the element of a modelled
container, the result carries the actual's element refinement — i.e. `let
h = List.head(xs)` with `xs : List({Int | p})` puts `h` into `contenv` as
`Option` with `p`. This needs the callee's parameter and return TYPES, which
`fn_sig.param_tys` has and `fn_sig` lacks for the return (`ret` is the
refinement, not the type): add `ret_ty : A.ty option` to `fn_sig`. No
inference of element refinements FROM a body (`List.map`'s result is not
known to satisfy anything); functions that build containers from elements
stay opaque, which is a recorded skip at the consumer, not silence.

### Soundness

2a/2b add obligations at every construction the same way one layer does;
the assumption side is table-driven from the same registry, so a fact is
only handed out where the corresponding position is obliged. 2c is sound
because it is purely parametric: a value of type `a` that came out of the
container went INTO it under the obligation, and the rule fires only when
the typechecker's signature says the return element IS that `a`. The one
hazard is a stdlib function whose declared signature is more general than
its behaviour (a `List(a) -> Option(a)` that could manufacture an `a`) —
impossible for a parametric `a` with no `a`-valued inputs beyond the
container, which is what condition (i) enforces.

### Tests

`container-subtyping-2` group: `Result({Int | p}, String)` literal `Ok(0)`
rejected / `Err("x")` unaffected; a user `type Tree(a) = Leaf | Node(Tree(a),
a, Tree(a))` with `Node(Leaf, 0, Leaf)` rejected under `Tree({Int | p})` and
the `Node(_, x, _)` arm proving `need(x)`; `List(List({Int | p}))` literal
`[[1], [0]]` rejected and `match xs do Cons(inner, _)` handing `inner` the
inner entry; `List.head(xs)` then `Some(h) -> need(h)` proving, with an
unrefined-`xs` control. Oracle: expect NO change in verdicts (stdlib passes
no refined containers), but 2c changes `fn_sig`, so the types oracle should
be run too.

Effort: 2a one day (the registry extension is the bulk); 2b half a day; 2c
one to two days, and it should land last.

---

## 3. Sibling-parameter blame: `unreflectable-predicate` names the wrong leaf

Todo: `specs/todos/2026-09-03-sibling-parameter-opaque-actual.md`.

### Where it stands

`fn at(i : {Int | _ < n}, n : Int)` called as `at(i, lane(4))`: `i` reflects,
`n`'s actual `lane(4)` is opaque, and the obligation files as
`unreflectable-predicate: the predicate's n has no SMT translation`. The
predicate is fine; the SUBJECT that failed is a sibling's actual. The
`self_reflection_failed` computation reads only `reflect_cache["$self"]`.

### Design

Replace the boolean with a three-way attribution computed from the memo,
in this order:

1. `"$self"` failed → `Unreflectable_subject` naming the self actual (today).
2. otherwise, any key `k` that is one of `sg.param_names` other than the
   self parameter, with entry `Some None` → `Unreflectable_subject` naming
   THAT parameter's actual: "the argument passed for `n` (`lane(4)`) has no
   SMT translation, so the predicate `_ < n` cannot be decided here" — the
   existing `self_display` fallback logic (render the actual, else name the
   parameter) reused with the sibling's index.
3. otherwise → `Unreflectable_predicate` naming the failing leaf (today).

Only `Some None` entries under a parameter name count; `"$path$…"` keys and
`Some (Some _)` entries are ignored, so a path fact that failed to reflect
(already dropped silently, by design) is never blamed as a subject. Where
several siblings failed, name the first in parameter order and say "and N
more".

The memo must actually be populated for the sibling: it is, since
`resolve_var` for a non-self parameter name goes through `reflect_cached
name` (the todo's line-1316 note). Verify with the `f6` fixture before
trusting it.

### Soundness

Diagnostic only: the verdict stays `Skipped`, only the reason and message
change. The ledger slug moves from `unreflectable-predicate` to
`unreflectable-subject` for these obligations, which `--refine-report`
counts separately — `test/refine_audit/corpus.baseline` and the refine
oracle will show any corpus program whose slug moves; each such line is a
message that was WRONG before, so the diff is the review artifact, and the
baseline is regenerated with it.

### Tests

`obligation-reasons` group: the `f6` fixture files
`unreflectable-subject` naming `lane(4)`, and its message does not contain
"the predicate's `n`"; a control where `n`'s actual is a literal and the
predicate genuinely has an untranslatable leaf (`_ < n && is_prime(n)`) still
files `unreflectable-predicate` naming `is_prime(n)`; a two-sibling case
names the first and counts the rest. The whole-plan review's `f6` text is
reproduced verbatim in the todo and is the fixture.

Effort: half a day.

---

## 4. `@[measure]` over a scalar constructor field is inert

Todo: `specs/todos/2026-08-05-measure-over-scalar-ctor-field.md`.

### Where it stands

`reflect_field` erases every non-datatype constructor field to a fresh
`_eN`, so `length(PVec(3, …))` is `length(PVec(_e3, …))`, the measure axiom
yields `_e3`, and every bounds obligation over `Array.length` is
solver-undecided. The measure definition gets a warning
(`measure_scalar_field_dep`, 2026-08-05); the checker stays silent at every
call site. This is what blocks `Array.get` / `set` / `pop` contracts under
`cap no_panic`.

### Design

**4a. Reflect a scalar field concretely when the actual is reflectable.** In
`reflect_field`, for a field at sort `SInt` / `SBool` / `Float64`: if the
actual sub-expression reflects through the ordinary scalar reflection
(`reflect_scalar` with the field's sort — a literal, a refined local, an
arithmetic of those), use that term; otherwise mint `_eN` as today. The
datatype term stays well-sorted (`term_fits_sort` already admits a scalar
term at a scalar field), so the `z3 -in` channel hazard that motivated the
erasure does not arise. The fresh-constant fallback is what protects an
opaque variable, and it stays.

**4b. A measure whose value is a scalar field, on a VARIABLE actual.** The
literal case is what 4a proves; the common case is `aget(v, i)` with `v` a
parameter. There the field is unknown, and the only source of a fact is a
refinement on `v` itself or a path guard: `v : {PVec | length(v) > 0}` or
`if i < Array.length(v) do aget(v, i)`. Both already reach the solver as
facts over `length(v)` (the measure application over the constant `v`), so
with 4a the axiom is no longer needed for them at all — the obligation `i <
length(v)` is discharged from the guard directly. Verify this is already
true (it should be: the guard and the goal meet on `length(v)` as an
uninterpreted application) and pin it; if it is not, that is the bug to
fix, not the erasure.

**4c. Lift the measure-definition warning out of `measure_axioms`.** The
todo's own sub-item: the fact reported is about the measure's shape, not
about whether axioms were requested this run; hoist it above the `if
measure_axioms` guard so `--no-measure-axioms` does not silence it.

Then, and only then, contract `Array.get` / `set` / `pop` with the `List.nth`
treatment and add them to `Panic_surface_by_proof`'s covered set — as a
separate change, gated on a full stdlib + ecosystem `--refine-report` sweep,
because widening what every contract can prove can also widen what it
refutes.

### Soundness

4a reflects a value the checker already knows (a literal or an
already-reflected scalar) into a position that was previously an
unconstrained constant: every VC becomes STRONGER on the assumption side
and unchanged on the goal side, so a proof that appears is a real proof, and
a refutation that appears is a real counterexample only under the
definite-failure rule, which requires `¬G` valid under the (now stronger)
assumptions — still sound. The risk the todo names is real but is a
false-POSITIVE risk only in the sense of newly REJECTED code that was
genuinely wrong and previously unverified; the sweep is what measures how
much of that exists.

### Tests

`measure-scalar-field` group: `aget(PVec(3, 0, TrieEmpty, [x, y, z]), 1)`
proves and `…, 5)` is refuted (4a); `fn f(v : PVec(Int), i : Int) do if i <
length(v) do aget(v, i) else 0 end end` proves (4b); the `0 * n` false-positive
control of the existing `measure-scalar-field-warn` group stays green; the
warning fires under `--no-measure-axioms` (4c). Oracle: expect a diff —
every stdlib obligation over `Array.length` that moves from skipped to
proved is the point; review each moved line, and any that moves to
VIOLATED is a real stdlib bug or a real false positive and blocks the
change until understood.

Effort: 4a+4c one day; 4b half a day if it holds, unknown if it does not;
the `Array` contracts a further day plus the sweep.

---

## Order

3 (half a day, diagnostic-only, zero risk) → 1a (half a day, audit-only) →
4a/4c (one day, the one that unblocks `Array` contracts) → 1b/1c → 2a →
2b → 2c → 4b + the `Array` contracts. Each is its own PR with its own
oracle run against a compiler built at that PR's base.
