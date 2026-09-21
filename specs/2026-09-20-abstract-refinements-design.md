# Design: abstract refinements (a refinement parameterised by a predicate)

**Date:** 2026-09-20
**Closes:** item 6 of `specs/todos/2026-09-18-refine-element-flow-followups.md`
("Abstract refinements, so `filter` can produce `List({Int | p})` from a
predicate. A new mechanism in the logic, not plumbing; its own design.")
**Prior design this continues:** `specs/2026-09-18-parametric-element-flow-design.md`
(its row **n** is the motivating case, deferred there in §4.5).

Liquid Haskell writes `filter :: (a -> Bool<p>) -> [a] -> [a<p>]`: the
signature is polymorphic in a *predicate* `p`, instantiated per call site. This
design gives March the same power for the one shape that matters — a container
combinator whose callback decides the element predicate — without quantifiers
in the solver and, for v1, without a grammar change.

---

## 0. Where things stand (probed 2026-09-20, compiler built at `3cac5eaf5`)

| Row | Program | Today | After |
|---|---|---|---|
| n | `sum_pos(List.filter(ys, fn y -> y > 0))`, `ys` unrefined | skip | **proved** (§3) |
| n1 | `sum_pos(List.filter(pos, fn y -> y > 5))`, `pos` refined `> 0` | skip | proved, elements satisfy `_ > 0 && _ > 5` (§3.4) |
| n2 | `sum_pos(List.filter(ys, fn y -> y >= 0))` | skip | **skip**, `abstract-refinement-too-weak`: `y >= 0` does not imply `_ > 0` (§3.3) |
| n3 | `sum_pos(List.filter(ys, is_pos))`, `is_pos` a named fn with a proved `{Bool | _ == (n > 0)}` return | skip | proved (§3.5, phase 3) |
| n4 | `sum_pos(List.filter(ys, f))`, `f` an opaque parameter | skip | skip, `abstract-refinement-uninstantiated` |
| n5 | `List.filter`'s own body against its declared `List({a | p(_)})` | not stated | **proved** from the branch fact (§4) |
| n6 | `fn bad(xs : List(a), k : …) : List({a | p(_)}) do xs end` | — | **violation/skip**: the tails do not satisfy `p` (§4.3) |

Facts the design rests on, each verified on this commit rather than assumed:

- **`{a | p(_)}` already parses.** `fn f(xs : List({a | p(_)})) : Int` compiles
  today with no error (only the unused-parameter warning): the refinement base
  may be a type variable, and an application of an unknown name is a legal
  predicate expression. Verified by probe `s1`.
- **A named domain binder already parses.**
  `k : ({x : a | true}) -> {Bool | _ == p(x)}` compiles today (probe `s4`), so
  a callback's codomain can refer to its own argument with no grammar change.
- **`a[p]` and `Bool[p]` do NOT parse** ("I got stuck here", probes `s2`/`s3`),
  and `a<p>` is ambiguous with `<`/`>` in the predicate expression grammar
  (`parser.mly:327`). LH-style sugar is therefore deferred to §7 phase 4.
- **A predicate variable has no SMT arm today.** `smt_of_r_marked`
  (`refine_scope.ml:79-235`) has no case for `EApp (EVar p, [x])` where `p` is
  not a measure, so the whole predicate falls to `Error` and the obligation is
  an `unreflectable-predicate` skip. That arm is the mechanism this design adds.
- **`Smt.App` is already "uninterpreted-fn application"** (`smt.ml:66`), and
  `$strlen` is the existing precedent for a declared uninterpreted symbol
  (`refine_encode.ml:108-115`). The `$` prefix convention is load-bearing:
  a symbol colliding with a March identifier desynchronises the long-lived
  `z3 -in` channel (`refine_encode.ml:99-107`).
- **Callback parameters already have a stand-in name**, `callback_param_name =
  "$cb_arg"` (`refine_scope.ml:571`), materialised by `callback_sig_of_ty`
  (`:586-632`) — the anchor an abstract refinement's argument binds to.
- **The element channel is `contenv`** with `elem = Refined of (binder, pred,
  sort) | Container of …` (`refine_scope.ml:1112-1114`); demands are matched by
  `demand_flow` (`refine_check.ml:880-1035`) over `sources_of`
  (`refine_param.ml:540-551`), gated by P1/P2 (`refine_param.ml:425-472`).

---

## 1. Surface syntax (v1: no grammar change)

An **abstract refinement** is a lowercase name applied to one argument inside a
refinement predicate, in a signature that also *defines* it. The canonical
declaration is the one the stdlib will carry:

```march
fn filter(xs : List(a),
          keep : ({x : a | true}) -> {Bool | _ == p(x)})
        : List({a | p(_)}) do … end
```

Three occurrences, three roles:

| Occurrence | Role | Called |
|---|---|---|
| `{Bool | _ == p(x)}` on a callback codomain, over that callback's domain binder | **definer**: fixes what `p` means at a call site | *defining occurrence* |
| `{a | p(_)}` in the return | **producer**: the fact callers receive | positive occurrence |
| `{a | p(_)}` in a parameter's element slot | **consumer**: an obligation on the caller | negative occurrence |

Scoping and well-formedness, checked once per signature (`Refine_abstract.collect`):

1. A name is an abstract refinement of this signature iff it is applied to
   exactly one argument inside a refinement in that signature, it is not a
   `@[measure]`, not a known vocabulary name, and not bound as a value
   parameter. (Today such an application is silently unreflectable; §3.6 covers
   the interaction with the existing "predicate applies an unknown function"
   warning.)
2. Its argument must be the binder of the refinement it sits in (`_` or the
   named form) or the domain binder of the arrow whose codomain it refines.
   Anything else is a **hard error** at the declaration: `abstract refinement
   `p` is applied to `y`, which is not this signature's element binder`.
3. **A definer is what makes a name abstract at all** (revised while building
   phase 1). With no definer in the signature, `p(_)` is not an abstract
   refinement: it stays what it has always been, a predicate calling a name the
   checker does not know, and keeps its existing "not a measure, so this
   refinement is not checked" warning. Making that an error would reject
   programs that compile today, which phase 1 must not do — a probe caught the
   first draft of this rule swallowing the warning for every typo in a
   refinement. A definer with no consumer (no positive and no negative
   occurrence) is a **warning**: the refinement is vacuous.
4. All occurrences must sit at the *same* element sort. Mixed sorts are a hard
   error, not a skip — a signature is small and the author can see it.
5. Several abstract refinements per signature are allowed (`p`, `q`), each
   instantiated independently. Nested application (`p(q(_))`) is rejected.

The `{x : a | true}` domain spelling is ceremony forced by v1's no-grammar-change
constraint. Phase 4 (§7) adds the LH-shaped sugar `a[p]` / `Bool[p]`, desugaring
to exactly the above, once the semantics have shipped.

---

## 2. The logic: two modes, both quantifier-free

The whole design is that an abstract refinement is read in one of two ways
depending on which side of the signature is being checked, and neither needs a
quantifier.

### 2a. Definition side — `p` is an uninterpreted symbol

When checking the body of `filter` itself, `p` is declared as an uninterpreted
Bool-valued function of the element sort, alongside the existing preamble
declarations:

```smt
(declare-fun $abs_p (Elem) Bool)
```

`smt_of_r_marked` gains one arm: an application of a name in the current
signature's abstract-refinement set translates to `Smt.App ("$abs_p", [arg])`.
The symbol is registered in the declaration list the same way a measure instance
is (`refine_encode.ml:2679-2689`) so `resolve_sorts_exact` sees its argument
sort and `sort_conflict` (`refine_encode.ml:211`) does not fire. The `$abs_`
prefix keeps it out of the March identifier namespace, per the `$strlen`
precedent.

A call to the callback parameter in the body (`keep(x)`) reflects to
`$abs_p(x)` through the callback's declared codomain `{Bool | _ == p(x)}` —
this is the existing callback-return machinery (`cbenv`), with the new arm
supplying the term.

### 2b. Call site — `p` is instantiated to a concrete predicate

At a call, the definer occurrence is matched against the actual callback to
produce a **concrete** predicate `q(v)`, an ordinary March expression in one
variable (§3.1). Every positive occurrence of `p` in the callee's signature is
then substituted with `q`, and the result flows into the *existing* element
machinery: the call's `contenv` entry becomes `Refined ("_", q, sort)`. Nothing
downstream knows an abstract refinement was involved.

No uninterpreted symbol is sent for the instantiated direction, so a call-site
query stays in the fragment the checker already uses. This is the same trade the
measure encoding makes (`define-fun` for non-recursive measures): keep the
solver's job quantifier-free and decide instantiation in OCaml.

---

## 3. Call sites

### 3.1 Instantiation: where `q` comes from

Given a call `g(…, cb, …)` where `g`'s signature declares `p` with its definer
at parameter `i`, and `cb` is the actual at `i`:

| `cb` shape | `q` | Notes |
|---|---|---|
| inline lambda `fn y -> body` | `body` with `y` as the binder | requires `body` to translate (`smt_of`) and to be capture-free, the same decline `confirm_lambda_post` already makes |
| `let`-bound lambda, in scope | same | via the existing `cbenv` lookup |
| named function with a **proved** return refinement of the shape `{Bool | _ == e}` where `e` mentions only its own parameter | `e` | phase 3; `postcond_of` already carries proved returns |
| anything else (opaque parameter, `impl` dispatch, multi-parameter callback) | — | recorded skip `abstract-refinement-uninstantiated` |

A lambda whose body is not a pure Bool expression (a call into an unrefined
helper, IO, a `match`) yields no `q`: skip, same reason.

### 3.2 Substitution and the produced entry

With `q` in hand, every positive occurrence of `p` in `g`'s return type is
replaced by `q`, producing an ordinary element entry. For `filter` that is
`List({a | q(_)})`. The entry is offered to `container_entry_of_expr`
(`refine_check.ml:640-665`) exactly like a declared element return, so
`check_elements`, `demand_flow`, `let` binding facts and `cap verified` all
work unchanged.

The parametricity gates still apply to the *type* variable `a`: P1
(`generic_in_inferred`) and P2 (`parametric_safe`) must hold for `a`, or the
entry is not offered. An abstract refinement says what the elements satisfy, not
where they came from; row z's soundness bug is orthogonal and stays guarded.

### 3.3 Discharging a demand

When the caller demands `D` on the result (`sum_pos` wants `{Int | _ > 0}`), the
obligation is the implication

```
q(v) ⇒ D(v)     for a fresh constant v of the element sort
```

one query, no quantifier, decided the way every other obligation is. Verdicts
follow the established stance:

- valid → **proved** (row n);
- refuted → recorded skip `abstract-refinement-too-weak`, carrying the witness
  ("`fn y -> y >= 0` admits `y = 0`, which does not satisfy `_ > 0`"). **Not** a
  violation: as in §4.3 of the element-flow design, whether the weaker predicate
  ever admits a bad element depends on the caller's data, and `List.filter([], …)`
  is fine. `cap verified` escalates it like any skip;
- undecided → skip, `solver-undecided`, unchanged.

### 3.4 Conjunction with an incoming element fact

If the container argument already carries an element entry (`pos : List({Int | _ > 0})`)
and the callee's parameter is `List(a)` with `a` in a source position, the
produced entry conjoins: `{a | _ > 0 && q(_)}` (row n1). The conjunction is
built at the AST level (`EApp (EVar "&&", …)`), so the solver sees one ordinary
predicate. Order is fixed (incoming fact first) to keep rendering stable in
diagnostics and baselines.

### 3.5 Negative occurrences

A parameter whose element slot mentions `p` is an obligation on the caller,
discharged against the instantiated `q` by the existing element-subtyping path
(`check_elements` with `Element_domain`). Example: a hypothetical
`fn partition_by(xs : List({a | p(_)}), keep : … ) : …` would require the
caller's container to already satisfy `q`. In scope, but no stdlib function in
phase 2 uses it; the tests cover it with a fixture.

### 3.6 Interaction with the unknown-application warning

The checker today warns when a predicate applies a name outside its vocabulary
(`specs/lang/refinement-types.md`, "A predicate can call a name the checker
doesn't understand"). A declared abstract refinement must be exempt, and a name
that *looks* like one but fails §1's well-formedness must still warn. The
collect pass runs before predicate translation so both hold; a test pins each
direction.

---

## 4. Definition side: earning `List({a | p(_)})`

### 4.1 The judgment

`filter`'s body must prove that every element of its result satisfies `p`. With
§2a's uninterpreted `$abs_p`, the existing Tier 2 element-return machinery does
this with no new proof rule:

```march
fn filter(xs, keep) do
  match xs do
  Nil -> Nil
  Cons(h, t) ->
    if keep(h) do Cons(h, filter(t, keep))    -- path fact: keep(h) == true
    else filter(t, keep) end                   -- self-call, induction hypothesis
  end
end
```

- The `Cons(h, …)` tail needs `$abs_p(h)`. The branch gives `keep(h) == true`,
  and the callback's declared codomain gives `keep(h) == $abs_p(h)`. Together:
  `$abs_p(h)`. That is one quantifier-free implication.
- The recursive tails are the self-call element-return hypothesis that Phase 2
  of the element-flow work already supplies (`structural_subvars`, own name
  only).
- `Nil` is vacuous.

### 4.2 If a definition does not prove

The precedent is established and should be followed rather than widened: a
stdlib contract that cannot be proved from its body is marked `@[assume]` with a
runtime property witness in the module's test file (as `Set`/`Map` and the
`Array` length contracts are). For `filter` the expectation is a proof, not an
assumption — §4.1 is why — and phase 2 does not land until one of the two is
true and stated in the progress note.

### 4.3 The negative test

`fn bad(xs : List(a), keep : …) : List({a | p(_)}) do xs end` must not be
accepted: the tails are `xs`'s elements, which carry nothing about `p`. This is
`gate_elem_returns` doing its existing job against the new entry; row n6 pins it.

---

## 5. Soundness

| New assumption | Justified by | Guarded by |
|---|---|---|
| the produced entry `{a | q(_)}` at a call | the callee's declared contract, proved in §4 for the callee's own body | `elem_ret_proved` for the callee; P1/P2 for `a`; ≥1 defining occurrence |
| `q` is what the callback decides | the callback's codomain contract `{Bool | _ == p(x)}`, obliged at the pass site by the existing contravariance check | `check_pass_sites`; capture-free decline; lambda body must translate |
| `$abs_p` is consistent inside the body | it is uninterpreted: the body may assume nothing about it beyond what the callback's contract states | one declaration per signature per sort; `sort_conflict` on mismatch |
| conjunction with the incoming fact | both hold of every kept element | incoming entry must come from a source the parametric rule already accepts |

Every row gets a REJECT or SKIP control in the tests, per the project's standing
rule that accept-only witnesses cannot distinguish a working rule from one that
checks nothing.

**What is deliberately not claimed.** `filter` does not promise the result is a
*sub*sequence, nor anything about order, length (beyond `len(_) <= len(xs)`,
which is a separate contract), or elements it dropped.

---

## 6. Scope

In scope: one abstract refinement applied to one argument, at the element slot
of a registered container, defined by a one-parameter callback's codomain,
instantiated from an inline lambda (phase 2) or a named function with a proved
return (phase 3).

Out of scope, each to be named in the todo so no guarantee is read into its
absence:

- **Bounded refinements** (LH's `<p, q>` with an implication constraint between
  them). A separate mechanism.
- **Arity > 1** (`p(x, y)`), which is what a `fold`-shaped invariant and
  `Map.filter`'s `(k, v) -> Bool` callback would need; filed as
  `specs/todos/2026-09-20-abstract-refinements-multi-arg-callbacks.md`.
- **`p` over a type variable that is not an element** — a bare scalar return
  `(a) -> {a | p(_)}`, e.g. `Option.filter`-shaped scalars. Same judgment,
  different entry point; a follow-up like §4.5's scalar-demand item.
- **Instantiating from `impl` dispatch**, which is unchecked generally.
- **Abstract refinements in a user's own `interface` methods.**
- **Inference**: nobody's signature gains `p` automatically.

---

## 7. Phases, one PR each

Conventions as in the element-flow plan: every step keeps
`test_refinecheck.exe` green, every new rule lands with a fixture that goes RED
without it, ledger triples asserted rather than exit codes, `--root .`, z3 on
PATH, and CI's z3 4.8.12 noted since the local build is 4.16.

**Phase 1 — surface and well-formedness, inert.** `Refine_abstract.collect`,
the §1 rules, the hard errors, the vacuity warning, the §3.6 warning exemption.
No verdict changes anywhere: the refine oracle must be **identical**, and the
audit baselines and `stdlib/list.march` skip count (CI ceiling 46) must not
move. Tests: each malformed signature its own error, a well-formed one still
producing exactly today's skips.

**Phase 2 — the filter rule.** §2a's SMT arm and declaration, §3.1 instantiation
from inline lambdas, §3.2 substitution, §3.3 discharge, §3.4 conjunction, §4's
definition-side proof, then `List.filter`'s signature. Rows n, n1, n2, n4, n5,
n6. Oracle diff explained line by line; full sweep (`stdlib`, `test/native`,
`test/stdlib`, the ecosystem repos) because a new element fact can turn a skip
into a violation; audit baselines regenerate (enforced count rises by the new
contract).

**Phase 3 — named callables and more stdlib.** Row n3; `List.take_while`,
`Option.filter` and `Map.filter` if §4 proves for each; otherwise `@[assume]`
plus witnesses, stated in the progress note.

**Phase 4 — sugar.** `a[p]` and `Bool[p]`, desugaring to phase 1's forms, with
the menhir conflict count held at its current 9 (`parser.mly:1860-1861`; note
the stale "11" comment at `:1092-1093` and fix it while there). Grammar fixtures
under `specs/lang/grammar/parse/`, and the language reference updated in **both**
`specs/lang/refinement-types.md` and `docs/refinement-types.md`.

Docs at each phase: remove the "**`filter` does not produce a refinement it was
not given**" bullet from "What element refinements do not do" (both copies) only
when phase 2 lands, and close item 6 of the follow-ups todo then.

---

## 8. Performance

Phase 2 adds at most one implication query per demanded call with a callback,
and one extra declaration in the preamble of a query that mentions `p`.
Budget: cold `--check` of `stdlib/list.march` within 10% of its pre-change time,
measured under a private `HOME` with `.march/cas/vc` cleared once, three runs,
median — the same protocol the element-flow design used (0.39 s on 2026-09-16).

The VC cache key must include the instantiated `q`, or two call sites with
different lambdas would share a verdict. That is the one cache hazard in this
design and it gets its own test (two calls, different predicates, second must
not inherit the first's proof).

---

## 9. Decisions (settled 2026-09-20)

1. **The `{x : a | true}` definer spelling ships as v1.** Semantics first; the
   sugar stays phase 4, and `List.filter`'s public type carries the ceremony
   until then.
2. **A refuted demand is never a violation, for now.** §3.3's skip-with-witness
   is the final stance for this design. Promotion through
   `confirm_precond_reachable` on a literal non-empty container is left
   unfiled: revisit only if the skip proves noisy in practice.
3. **Arity > 1 is an accepted gap, filed.** `Map.filter`'s `(k, v) -> Bool`
   callback cannot define an abstract refinement, and a two-argument definer
   binding only its first argument was rejected as a half-measure that would
   need its own soundness argument. Tracked in
   `specs/todos/2026-09-20-abstract-refinements-multi-arg-callbacks.md`; phase 3
   therefore covers `List.take_while` and `Option.filter` but not `Map.filter`.

