# Design: abstract refinements over several arguments, and the relational element fact they need (`Map.filter`)

**Date:** 2026-10-18
**Status:** design. Nothing is built. Probed on `ba8db5805` (0.6.0 + docs),
compiler `_build/default/bin/main.exe` built 2026-10-18, z3 4.16.0 (CI has 4.8.12).
**Closes, when phase 4 lands:** the `Map.filter` bullet of
`specs/todos/2026-09-20-abstract-refinements-multi-arg-callbacks.md` (its gate,
"the one-argument rule landed through phase 3 and the stdlib used it", is met:
phases 1-4 landed 2026-09-21..10-08 and `List.filter`/`find`/`take_while`/`Option.filter`
carry it).
**Prior designs this continues:** `specs/2026-09-20-abstract-refinements-design.md`
(the one-argument rule; its format is copied here; cited as **AR §n**) and
`specs/2026-09-18-parametric-element-flow-design.md` (element slots, sources, P1/P2;
cited as **EF §n**).

**Sibling designs being written at the same time, and where the line falls:**

| Sibling | Owns | This design |
|---|---|---|
| `specs/2026-10-18-fold-accumulator-invariants-design.md` | `fold_left`'s accumulator invariant. That is a *negative and positive* occurrence of `b` in `f : b -> a -> b`, discharged by induction over the fold. It is not the element rule, so `p(acc, x)` on a fold callback is **not** an abstract refinement in this design's sense. It drops the `fold_left` bullet from the multi-arg todo. | disjoint. No fold signature gains a `p` here, and nothing here reasons about an accumulator. |
| element-flow follow-ups (a) | domain facts for multi-parameter lambdas (`x` in `fn (acc, x) -> …`), the scalar-demand entry point | disjoint. This design needs no lambda domain fact. Both touch `callback_sig_of_ty` (§5.3). Whichever lands second rebases. The change here is limited to two codomain shapes for that reason. |
| one-argument leftovers | `List.partition`, `Deque.filter` | out of scope here. |

The one-argument rule says what a filtered `List` keeps. A `Map`'s filter
callback decides on a key **and** a value together. So the fact it produces,
"every entry `(k, v)` satisfies `p(k, v)`", relates two type-argument slots.
The checker today stores an independent fact per slot (§0, finding F3). It
cannot hold that fact, and it cannot even read a hand-written one correctly
(rows r3, r4).

This design therefore has two halves:
- a **relational element fact**: a predicate over several slots of one container, per entry (§2, phases 0-1);
- the **arity-n abstract refinement** that produces one (§3-§5, phases 2-4).

The first half is useful on its own.

---

## 0. Where things stand (probed 2026-10-18 on `ba8db5805`)

Every row is a scratch program run as
`HOME=<private> march --check --refine-report --refine-report-sites probe.march`.
Each verdict is the ledger line for that call; `cap verified` variants were used
to read skip details. Helpers:
- `need_vals(m : Map(String, {Int | _ > 0}))`, `need_keys(m : Map({Int | _ > 0}, String))`, `need_rel(m : Map({x : Int | true}, {y : Int | y > x}))`;
- for a user two-parameter container `type Assoc(k, v) = ANil | ACons(k, v, Assoc(k, v))`: `need_pos(a : Assoc(Int, {Int | _ > 0}))`, `need_arel(a : Assoc({x : Int | true}, {y : Int | y > x}))`, `need_gt(k : Int, v : {Int | _ > k})`.

`Map.filter` callbacks are curried. `Map.filter`'s body calls `pred(k)`
then `p(v)` (`stdlib/map.march:713-727`), so a caller passes `fn k -> fn v -> …`.
An uncurried `fn (k, v) -> …` is rejected by the typechecker (`callback_arity_mismatch`, probe r1).

### Map today: no slot fact survives any `Map` function

| Row | Program | Today (measured) | After |
|---|---|---|---|
| m1 | `need_vals(Map.filter(src(), fn _k -> fn v -> v > 0, Map.str_cmp))` | skip, `parametric-source-unproved` ("`Map.filter` is not known to be parametric…") | **proved** (phase 4) |
| m2 | `need_keys(Map.filter(m, fn k -> fn _v -> k > 0, Map.int_cmp))` | skip, `parametric-source-unproved` | **proved** (phase 4) |
| m3 | `need_rel(Map.filter(m, fn k -> fn v -> v > k, Map.int_cmp))` | skip, `parametric-source-unproved` | **proved** (phase 4) |
| m4 | `need_vals(Map.filter(m, fn _k -> fn v -> v >= 0, …))` | skip, same | skip, `abstract-refinement-too-weak` |
| m5 | `need_vals(Map.filter(m, fn k -> fn v -> k > 0 && v > k, …))` | skip, same | **proved**: projection, fresh `k` (§2.4) |
| m6 | `need_vals(Map.filter(m, fn k -> fn v -> v > k, …))` | skip, same | skip, too-weak (`k = -1, v = 0`) |
| m7 | `fn k -> fn v -> v > now` (captures `now`) | skip, same | skip, `abstract-refinement-uninstantiated` |
| m8 | `let m2 = Map.filter(m, fn _k -> fn v -> v > 0, …)` then `need_vals(m2)` | skip, `unreflectable-subject` | **proved** (the `lets` channel, as AR phase 2 B7) |
| m9 | `need_vals(m)` with `m : Map(String, {Int | _ > 0})` | **proved** | proved (unchanged) |
| m10 | `need_vals(Map.insert(m, "b", 5, …))`, `m` refined | skip, `parametric-source-unproved` | unchanged (out of scope, §8) |
| m11 | `need_vals(Map.insert(m, "b", 0, …))` | skip (not a violation) | unchanged |
| m12 | `cap verified` module, `Map.size(Map.filter(m, fn k -> fn v -> v > k, …))`, no demand | accepted, 0 obligations | accepted, 0 obligations (definer exemption, §5.5) |

### A user two-parameter container: the slots are independent, and a hand-written relation is misread

| Row | Program | Today (measured) | After |
|---|---|---|---|
| h1 | `type Wrap(k, v) = Wrap(List((k, v)))`; `fn mk() : Wrap(Int, {Int \| _ > 0}) do Wrap([(1, 0 - 5)]) end`; `need(mk())`, under `cap verified` | **proved: a false proof** | skip, `unreflectable-subject` (phase 0) |
| h2 | `need(Wrap([(1, 0 - 5)]))` under `cap verified` | **no obligation at all**, accepted | skip; error under `cap verified` (phase 0) |
| r1 | `need_arel(ACons(1, 2, ANil))` | skip, `solver-undecided` | **proved** (phase 1) |
| r2 | `need_arel(ACons(5, 2, ANil))` | skip, `solver-undecided` | **violation** (phase 1) |
| r3 | `fn proj(a : Assoc({x : Int \| x > 0}, {y : Int \| y > x})) … need_pos(a)` | **violation, a false one** ("e.g. x = -1, (elem) = 0") | **proved** (phase 1) |
| r4 | `need_arel(a)`, `a : Assoc({x : Int \| x > 0}, {y : Int \| y > x})`, demand spelled `{a : Int \| true}, {b : Int \| b > a}` | **violation, a false one** | **proved** (phase 1) |
| r4' | same with `a`'s binders spelled `x`/`y` like the demand's | proved, but only because the free names coincide | proved, by the relation |
| r5 | `ACons(k, v, _) -> need_gt(k, v)` on `a : Assoc({x \| true}, {y \| y > x})` | skip, `solver-undecided` | **proved** (phase 1) |
| r6 | `rel_wrong(m : Assoc({x \| true}, {y \| y >= x}))` → `need_arel(m)` | violation (for the wrong reason: free `a`, `x`) | violation (`x = 0, y = 0`) |
| r7 | `fn capt(x : {Int \| _ > 1000}, a : Assoc(Int, {y : Int \| y > x})) … need_big(a)` (slot names a *parameter*) | **violation, a false one** (`x = -1`) | unchanged here; filed (§8) |

### Abstract definers of two arguments

| Row | Program | Today (measured) | After |
|---|---|---|---|
| s1 | long form, curried: `keep : ({x : k \| true}) -> ({y : v \| true}) -> {Bool \| _ == p(x, y)}` | not abstract: "`p` is not a measure or known predicate" warning | **abstract** `p`, arity 2; no warning (phase 2) |
| s2 | sugar, tuple domain: `keep : (k, v) -> Bool[p]` | parse error: "…from a ONE-argument callback; this one takes several" | parse error, corrected text: a `(k, v)` domain is ONE tuple argument; write `k -> v -> Bool[p]` (phase 3) |
| s3 | sugar, curried: `keep : k -> v -> Bool[p]`, return `Map(k, v[p])` | inner arrow read as an arity-1 definer over `v`: return obligation skip, `unreflectable-subject` | `p` is arity 2; `Map(k, v[p])` is a hard error, fix `Map(k[p], v[p])` (phase 3) |
| s4 | long form with a tuple domain `(({x : k \| true}, {y : v \| true})) -> {Bool \| _ == p(x, y)}` | unknown-predicate warning | unchanged: a tuple is one argument (§1.1) |
| s5 | curried long form applying `p` to the LAST binder only: `… -> ({y : v \| true}) -> {Bool \| _ == p(y)}`, return `Map(k, {v \| p(_)})` | accepted, inert (return skip; call `parametric-source-unproved`) | **hard error**: `p` is applied to 1 of the callback's 2 arguments (rule W1, decision D3) |
| a1 | user `filt(a : Assoc(k, v), keep : <s1>) : Assoc({x : k \| true}, {y : v \| p(x, y)})`, body `if keep(k, v) do ACons(k, v, filt(t, keep)) …` | two unknown-predicate warnings, return unchecked | return **proved** (phase 2, §6) |
| a2 | `need_pos(filt(a, fn (_k, v) -> v > 0))` | skip, `parametric-source-unproved` | **proved** (phase 2) |
| a3 | a curried call in a body: `keep(k)(v)` | **parse error**: "`f(...)(...)` is not a chained call" | unchanged. In a body, a curried callback is called `let g = keep(k)` then `g(v)` (§6.3). |
| a4 | `cap verified`, `count(a, fn (k, v) -> v > k)` where `count`'s `keep` is the s1 shape | accepted, 0 obligations | accepted, 0 obligations (definer exemption) |

Facts the design rests on, each verified on `ba8db5805` rather than assumed:

- **F1. `Refine_abstract.applications` sees only single-argument applications**
  (`refine_abstract.ml:75-88`): `p(x, y)` falls to the generic `EApp` arm and
  is never a candidate. So s1 is the unknown-predicate warning, and nothing
  else about a two-argument `p` exists today.
- **F2. The parser's definer rewrite is local to one arrow.**
  `abstract_definer_arrow` (`parser.mly:44-74`) runs at each `ty ARROW ty`
  reduction (`parser.mly:1464`), innermost first. `k -> v -> Bool[p]` becomes
  `k -> ({$x : v | true} -> {Bool | _ == p($x)})`, an arity-1 definer over
  `v` under a curried arrow (s3). The tuple-domain message (s2) calls `(k, v)`
  "several arguments", but in March's type grammar `(A, B) -> R` is a callback
  of one tuple argument. A two-argument callback is `A -> B -> R`, for both
  call styles.
- **F3. Element facts are per slot.** `type elem = Refined of (binder, pred,
  sort) | Container of string * elem option list` (`refine_scope.ml:1391`),
  `contenv = (string * (string * elem option list)) list` (`:1393`).
  `elem_refinement` (`:1425-1445`) reads each type argument into its own slot,
  with no knowledge of its siblings. A slot predicate naming a sibling's
  binder keeps that name **free**. That is why r3/r4 are false violations
  (the free `x` is chosen `-1`) and r1/r2/r5 are undecided.
- **F4. Map's representation hides both parameters.**
  `ptype Map(k, v) = HamtMap(HEntry(k, v))` (`map.march:33`). The one field is
  role `Other`, so `ctor_hidden_params` for `Map` is `[0; 1]`
  (`refine_encode.ml:1441`, computed at `:1793-1815`). As a result:
  - `container_paths` refuses every `Map` source (`refine_param.ml:510-529`);
  - `sources_of` is `None` (`:540-551`);
  - no `Map` function's result carries a slot fact parametrically (m1, m10);
  - and none can, whatever its annotations.

  `Map`'s functions also have unannotated parameters, so P1 fails as well
  (`generic_in_inferred`, `:426-456`). `Map` values carry slot facts only from
  a declared parameter (m9).
- **F5. A hidden-parameter construction is vacuously "checked".** The
  `ECon` arm of `check_elements` (`refine_check.ml:1101-1117`) treats an
  `Other` field as `true` even when that field's type mentions a demanded
  type parameter. This is a live false proof. h1 is `proved` under
  `cap verified` for a `Wrap` holding `-5`, and h2 files no obligation at all.
  `Map`'s own constructor `HamtMap` is exactly this shape. So a
  definition-side "proof" of any `Map` element return inside `map.march`
  would be vacuous today. **That must be fixed first** (phase 0).
- **F6. The two call styles share one type.** `List.fold_left`'s
  `f : b -> a -> b` is called `f(acc, x)` (uncurried); `Map.filter`'s
  `pred` is called `pred(k)` then `p(v)` (curried). Which one a lambda must
  be is decided by how the callee calls it (`callback_arity_mismatch`, probe
  r1). `f(a)(b)` is a parse error (a3).
- **F7. `abstract_flow` is single-slot by construction.** It matches
  `slots = [Some (Refined demand)]` (`refine_check.ml:968-970`) and
  `abstract_slot_of_ty` matches a one-argument `TyCon` (`:839-851`).
  `instantiate_abstract` takes one-parameter lambdas only (`:895-955`).
  `named_predicate` takes `param_names = [n]` only (`:864-879`).
- **F8. The SMT symbol is unary.** The `$abs_p` arm (`refine_scope.ml:310-311`)
  matches `[ a ]`. The guards in `mentions_str`/`wellsorted`/`formula_wellsorted`
  match `App (f, [ _ ])` (`refine_encode.ml:242, 279, 473`).
  `abs_apps`/`abstract_preamble` assume one argument (`:328-371`).
- **F9. `@[assume]` assumes only a container-level predicate.**
  `assumed_return` reads the top-level `TyRefine` (`refine_post.ml:1763-1766`).
  An element return is trusted only through `elem_ret_proved`
  (`refine_param.ml:151`), which only a proof enters (`gate_elem_returns`,
  `refine_check.ml:3965-4010`).
- **F10. No definer pass-site obligation exists for a chain.**
  `pass_site_obligation` returns `None` for a callable whose signature has more
  than one parameter (`refine_check.ml:413-433`). A chain codomain
  (`v -> {Bool | …}`) is an arrow, not a `TyRefine`, so no codomain check runs
  (a4, m12: zero obligations). The exemption AR's re-probe item 4 needed is
  vacuously true here, and §5.5 pins it so it stays true.

---

## 1. Surface syntax

### 1.1 The definer: a callback chain

An arity-n abstract refinement is defined by a callback of n arguments. In
March that is a **curried arrow chain** `D1 -> … -> Dn -> Bool` (F6). A tuple
domain `(D1, D2) -> Bool` is one argument and defines nothing new (s4 stays
a warning; s2 stays an error, with a corrected message).

Long form (no grammar change, accepted from phase 2):

```march
keep : ({x : k | true}) -> ({y : v | true}) -> {Bool | _ == p(x, y)}
```

Sugar (phase 3; same tokens as today, new meaning of the chain):

```march
keep : k -> v -> Bool[p]
```

The sugar desugars to exactly the long form, with parser-made binders. A
domain that names its binder keeps it (`({x : Int | x > 0}) -> v -> Bool[p]`),
as in AR phase 4.

### 1.2 Occurrences: a relation over sibling slots

A positive or negative occurrence of an arity-n `p` relates n slots of **one
container type application**. Long form: the slot predicates name each other's
binders.

```march
: Map({x : k | true}, {y : v | p(x, y)})
```

Sugar (phase 3): mark every slot `p` relates, in slot order.

```march
: Map(k[p], v[p])
```

For an arity-1 `p`, `Map(k[p], v[p])` keeps its phase-4 meaning (two unary
facts). For an arity-2 `p` it is the relation. Arity comes from the definer in
the same signature, so this is resolved in `Refine_abstract`, not the parser
(§1.4).

`Map.filter`'s signature after phase 4:

```march
@[assume]
fn filter(m : Map(k, v), pred : k -> v -> Bool[p], cmp : k -> k -> Bool)
    : {Map(k[p], v[p]) | subset(keys(_), keys(m))} do … end
```

### 1.3 Concrete relations (phase 1, no abstract refinement involved)

The long form of §1.2 with a concrete predicate is a **relational element
refinement**: `Assoc({x : Int | true}, {y : Int | y > x})` reads "every entry's
value exceeds its key". This is what an instantiated `p` becomes at a call
site (§4). It is also what a user writes for a relational demand (`need_rel`).
It already parses and is misread today (r1-r6).

Name resolution (my call): inside one type application, a slot predicate sees
the binders of **all** sibling slots, in any order. A sibling binder shadows a
value parameter of the same name. A predicate may mention siblings and value
parameters together. Such a fact is then not closed and is not usable at a
call site, the same rule as today's `List({Int | _ < n})` (`entry_is_closed`,
`refine_param.ml:245-251`).

### 1.4 Well-formedness

Added to `Refine_abstract.check` (`refine_abstract.ml:204`). Hard errors,
code `abstract_refinement_misuse`, like AR §1's rules:

- **W1. Definer arity.** A definer sits in the final codomain of an arrow
  chain parameter and applies `p` to exactly the chain's domain binders, each
  once, in chain order. `p(y)` under a two-binder chain (s5) is an error:
  "`p` is applied to 1 of the callback's 2 arguments; write `p(x, y)`".
  (Decision D3.)
- **W2. Occurrence shape.** For arity n ≥ 2, every positive or negative
  occurrence's arguments are n distinct binders of slots of the same type
  application (sibling binders). Each slot's base is a type variable or a
  scalar, not a nested container. A single-slot `v[p]` / `p(_)` of an arity-2
  `p` is an error naming the fix `Map(k[p], v[p])`.
- **W3. Sorts per position.** Position i's base agrees across the definer
  (domain i) and every occurrence (that slot's base). This generalises AR rule 4.
- **W4. Entry shape.** The container is *entry-shaped* for the related slots
  S (§2.2). Otherwise: "`Two` has a constructor carrying a `k` without a `v`,
  so a relation between them has no entries to hold of."
- **W5. No mixed arity.** One `p`, one arity, everywhere in the signature.

Kept from AR §1: a name is abstract only if the signature defines it (rule 3).
Also kept: the vacuity warning, the nested-application error, and the
unknown-predicate warning exemption, now for n-ary applications too.

For a **concrete** relation (§1.3) that breaks W2 or W4, the checker warns
`refinement_unchecked` ("this relation is not checked: …"). It then treats
the relation as not written: never assumed, never obliged. This is the existing
convention for a predicate the checker cannot read, and it adds no error code
(my call).

---

## 2. The representation: a relational fact in the element entry (the crux)

### 2.1 Options compared

| | R1: entry record with relations | R2: a pseudo-slot | R3: a side channel | R4: sibling names inside slot predicates |
|---|---|---|---|---|
| Shape | `entry = { cont; slots; rels }`, `Container of entry` | `slots @ [Some (Joint rel)]` | `relenv : (string * rel list) list` beside `contenv` | keep `elem`; a slot's predicate may name sibling binders |
| Existing readers | **compile errors at every site** (≈20: `refine_check.ml` 15, `refine_scope.ml` 3, `refine_param.ml` 2), so none is missed | silently misread: `List.length slots` (`demand_flow`'s `List.length rargs = List.length slots`, `refine_check.ml:1236`), `List.nth slots i`, `agreed_elem_slot`'s `key`, `abstract_flow`'s `[Some (Refined _)]` all see a phantom slot | every binding site must shadow one more channel; one miss = a stale relation surviving a rebind (unsound) | exactly today's state, where every reader treats the sibling as free: r3/r4 false violations |
| Nested containers (`List(Assoc(k, v))`) | free: `Container of entry` carries rels | awkward | impossible (keyed by variable) | free |
| Single-slot facts | unchanged in `slots`; `normalize` folds a unary relation into its slot | unchanged | unchanged | unchanged |
| Cost | mechanical type migration (phase 1a, inert) | small diff, high risk | large threading (`check_elements` already takes 13 arguments) | audit every reader anyway |

**Recommendation: R1.** The type change is the point: every site that reads
an entry must decide what a relation means there. The compiler enumerates
those sites. R2 and R4 look cheaper only because they let a site ignore the
relation silently. A silent misread is how F3's false violations happened.

### 2.2 R1 precisely

```ocaml
(* refine_scope.ml, replacing :1391-1393 *)
type elem =
  | Refined of (string * A.expr * string option)      (* unchanged: binder, pred, sort marker *)
  | Container of entry
and entry = { cont : string; slots : elem option list; rels : rel list }
and rel = {
  rel_args : (int * string * string option) list;  (* (slot index, binder, sort marker); ≥ 2, distinct, ascending *)
  rel_pred : A.expr;                               (* over the rel_args binders *)
}
type contenv = (string * entry) list
```

**Meaning.** For every *entry* of the value, each slot fact holds of that
entry's component and each relation holds of its components jointly.

An **entry** of a container value is:
- for an ADT container, one constructor occurrence's `Param` fields, one per slot;
- for an opaque container (all parameters hidden, no `Param` fields: `Map`, `HashMap`), an abstract `(k, v)` pair of the value. The checker never constructs or destructs such entries; it only compares declared and assumed ones.

**Entry-shaped** for slot set S (W4): every constructor of the container has,
for each i ∈ S, the same number of `Param i` fields, and that number is 0 or 1.
- `Assoc` and `OrderedMap.Tree` are entry-shaped for {0, 1}.
- `Map` is entry-shaped vacuously (HamtMap: zero `Param` fields).
- `type Two(k, v) = K(k) | V(v)` is not: `V(-5)` is in no entry, yet projecting `x > 0 && y > x` onto `v` would claim `-5 > 0`.

This is the soundness reason for W4. It gets a test (`two_not_entry_shaped`).

**Invariants**, enforced by `normalize_entry : entry -> entry`, which every
constructor of an entry goes through:
- (I1) every relation mentions ≥ 2 slots; one mentioning one slot is conjoined into that slot (`&&` at the AST level, incoming first, AR §3.4 order); `true` relations drop;
- (I2) a relation's slots are scalar slots (never `Container`);
- (I3) sort markers come from the slot's declared base when present.

(I1) is what keeps every existing path byte-identical: a fact over one slot is
always a slot fact, never a relation. That includes an instantiated `q(k, v)`
that happens to mention only `v` (m1, m2).

**Have vs want.** Dropping a relation is always sound on the *have* side (an
assumption lost). On the *want* side (a demand), a relation the routine cannot
check is a **recorded skip, never a drop**. Every function below states which
side it is on.

### 2.3 New helpers (in `refine_param.ml` unless noted)

| Helper | Purpose |
|---|---|
| `entry_of_slots c slots` | today's `(c, slots)` → `{ cont = c; slots; rels = [] }`; used by the inert migration (1a) |
| `normalize_entry` | (I1)-(I3) |
| `entry_meet a b` | §3.4 conjunction: slots pairwise `&&` (incoming first), rels concatenated, normalised |
| `entry_is_closed` (extended, `:245`) | also every rel predicate mentions only its `rel_args` binders |
| `entry_mentions` (extended, `refine_check.ml:716`) | also scans rels |
| `entry_shaped c s` (`refine_encode.ml`, beside `ctor_param_fields`) | W4 / §2.2 |
| `ctor_field_params` (new table, `refine_encode.ml`, filled in `register_field_sorts` `:1773`) | per constructor, per field: the type parameters the field's type mentions. Phase 0 reads it. |
| `elem_refinement` (extended, `refine_scope.ml:1425`) | a slot predicate naming sibling binders (§1.3) becomes a `rel`. A shape violation (W2/W4 for a concrete relation) drops the relation, and `warn_predicate_ty` warns at the declaration. |
| `entry_implies cx ~have ~want` (`refine_check.ml`) | the one implication routine (§2.4) |
| `elem_markers_of_arg` (generalises `elem_marker_of_arg`, `refine_check.ml:1386`) | `T.TCon (_, es)` → one marker per type argument |

### 2.4 `entry_implies`: projection and relational subtyping

`check_elements`' subtyping arm (`refine_check.ml:1132-1165`) becomes a call to
`entry_implies ~have:src_entry ~want:entry`, and so does `abstract_flow` (§4.3).
For a `have` with no relations and a `want` with none, it must do **exactly**
what the arm does today: same queries, same ledger triples (phase 1a test).

For each want obligation, i.e. each refined want slot i and each want relation R:

1. Declare one fresh constant `$elem_j` per slot j of the container. These are
   deterministic names, with no counter (determinism oracle). Each constant is
   a scope entry `("$elem_j", have slot j's fact)`, or `{s | true}` at slot j's
   sort when the have slot is empty. The sort comes from:
   - the have slot's marker;
   - else the want slot's marker;
   - else `elem_markers_of_arg`;
   - otherwise **decline**: a recorded skip "the element type of slot j is not known here". Defaulting to Int was AR phase 2's q09b false violation.
2. Every have relation, instantiated at the `$elem_j`, is added as a **path
   fact** (`(pred, false)` on `cx.path`, the representation `EIf` already uses,
   `refine_check.ml:2145-2148`).
3. Goal:
   - for slot i, the want predicate at `$elem_i`;
   - for R, `R` at its slots' constants (an `elem_sig` over the last of them, the others in scope).

   Each goes through `check_call ~subject:Element_domain`, one ledger entry each, as today.
4. If have slot i is empty and **no** have relation mentions i, the result is
   today's skip ("the elements of `x` are not known to satisfy it").

**Partial demands.** The question was what `D(v)` means against `q(k, v)`.
The result says: every value `v` of the container sits in some entry `(k, v)`
with `q(k, v)`, so `∃k. q(k, v) ∧ S_k(k)`. The query asks for validity of
`q(k, v) ∧ S_k(k) ∧ S_v(v) ⇒ D(v)` with `k` a fresh constant. Validity
quantifies `k` universally, and `(∃k. A) ⇒ D ≡ ∀k. (A ⇒ D)` when `k` is not
free in `D`. The fresh-constant query is therefore **sound and complete** for
the projection. It never needs a quantifier. A demand on `k` alone is symmetric
(m2). A `q` mentioning only `v` never reaches this path: (I1) has already made
it a slot fact (m1).

Including all slots' facts and all relations, rather than the ones connected
to i, is my call. It is still sound (true facts about extra fresh constants),
and the arity is the container's type-parameter count, so the query is small.

### 2.5 Every site, and what a relation means there

| Site | Side | Rule |
|---|---|---|
| `container_entry_of_expr` (`refine_check.ml:725`) | have | carries the entry whole; `EVar` from `contenv`; the self-call hypothesis (`elem_ret_hyp`, `refine_param.ml:162`) carries rels |
| `declared_elem_return` (`:751`) | have | rels included when `entry_is_closed` and not `entry_mentions` callee abstracts |
| `parametric_return` / `agreed_elem_slot` (`:601-714`) | have | slots unchanged. Rels are carried only when every tyvar a rel relates has exactly one source, all those sources are the same `Src_elem (i, [(C, j)])` into the return's container `C`, and the return's type arguments map slot-for-slot. Otherwise rels are dropped (sound). |
| `check_elements`, `ECon` arm (`:1101`) | want | slots as today. For each want rel R over S: if the constructor carries one `Param i` field per i ∈ S, one obligation `R[args := field exprs]` through `check_call` on a synthetic relational signature `$r0 … $r(n-1)` whose last parameter is refined by R over the earlier ones (the shape `need_gt(k, v : {Int | _ > k})` already checks). If it carries none, nothing is owed. A hidden field is phase 0's skip. |
| `check_elements`, subtyping arm (`:1132`) | want | `entry_implies` (§2.4) |
| `demand_flow` (`:1227`) | want | slot demands unchanged. A want rel over tyvars {b1..bn} is discharged only when all `b` share one `Src_elem (i, [(C, _)])`, by `check_elements` of argument i against an entry carrying R at those slots. Otherwise `` `Unproved "a relation between `b1` and `b2` cannot be traced through separate sources" ``. |
| `match` facts (`:2116-2141`) | have | `PatVar`s at `Param i` fields take slot facts as today. Each rel all of whose slots are bound by `PatVar`s in this constructor becomes a path fact over those variables (r5). The `Self` binder takes the whole entry. |
| `cont_add_param` / `cont_add_binding` (`refine_scope.ml:1452-1482`) | have | unchanged logic; the entry now carries rels |
| `lets` re-examination (`refine_check.ml:1165-1186`) | want | unchanged; passes the entry to `abstract_flow` |
| `check_pass_site_elements` (`:1484`) | want | as `check_elements` |
| `refine_audit` | — | a rel is one contract site, enforced iff the function's tails are checked |
| `cap verified` | — | no new path: every new skip goes through `record_elem_skip`, `record_param_skip` or `record_abstract_verdict`, which escalate |

---

## 3. The logic

### 3a. Definition side: `$abs_p` over several sorts

Inside the declaring function, `p(e1, …, en)` translates to
`Smt.App ("$abs_p", [t1; …; tn])`. The arm in `smt_of_r_marked`
(`refine_scope.ml:310`) generalises from `[ a ]` to the argument list.
`abs_apps` returns `(f, args)`. `abstract_preamble` emits
`(declare-fun $abs_p (S1 … Sn) Bool)`, with each `Si` from the argument
constant's declared sort (default Int, the erased type-variable sort, as today).
If one query mentions `$abs_p` at two different sort tuples, the preamble
refuses and the query is a skip (`sort_conflict`, `refine_encode.ml:211`); W3
makes this unreachable from a well-formed signature. The `[ _ ]` arms in
`mentions_str`, `wellsorted` and `formula_wellsorted` (`refine_encode.ml:242, 279, 473`)
become `_` for an `$abs_` symbol, and `resolve_sorts_exact` likewise. Without
that, `wellsorted` would send a `Str` argument through `int_side` and refuse
it. For arity 1 every query's text is unchanged, so cache keys and oracle are
unchanged.

### 3b. Call site: `p` is instantiated, never sent

As AR §2b: the definer's actual yields `q(y1, …, yn)`. Every occurrence
`p(a1, …, an)` in the callee's return (or parameter) entry is β-replaced by
`q[yi := ai]`, the entry is normalised, and the result is an ordinary
relational entry. No uninterpreted symbol reaches a call-site query, which stays
quantifier-free.

---

## 4. Call sites

### 4.1 Instantiation (`instantiate_abstract`, `refine_check.ml:895`, generalised to arity n)

| Actual at the definer index | `q` | Notes |
|---|---|---|
| `fn (y1, …, yn) -> body` (uncurried) | body over `y1..yn` | for an uncurried-calling callee (F6) |
| `fn y1 -> fn y2 -> … -> body` (curried, nested one-parameter lambdas) | the innermost body over `y1..yn` | `Map.filter`'s form. The intermediate lambdas must have no body other than the next lambda. |
| eta: `fn (a, b) -> g(a, b)` / `fn a -> fn b -> g(a, b)` | `g`'s, as named | as AR phase 3 |
| a `let`-bound lambda of either form | the lambda | via `local_lambda_of` (`:892`), as AR phase 3 |
| a named function with a **proved** `{Bool \| _ == e}` return over its n parameters | `e` | `named_predicate` (`:864`) generalised to `param_names = ns`. It is only reachable for an uncurried callee: a curried caller rejects a two-parameter function by typecheck. |
| a callback parameter whose type is a chain with a `{Bool \| _ == e}` final codomain | `e` over the chain binders | through §5.3's chain signature |
| anything else; a body mentioning any name but `y1..yn`; a body calling an unreflected function; a lambda of the wrong arity | — | `abstract-refinement-uninstantiated`, naming why (m7) |

The capture-free and opaque-call declines are AR's, applied to the innermost
body with the parameter list `y1..yn` (`classify_pred` over the list).

### 4.2 Produced entry and discharge

`abstract_flow` (`refine_check.ml:962`) generalises:

1. Read the callee's return entry **syntactically**, keeping `p`
   (`abstract_entry_of_ty`, replacing `abstract_slot_of_ty` `:839`).
   `elem_refinement` cannot be used, because a tyvar slot is admitted only
   inside the declaring definition (`abstract_tyvar_slot`, `refine_scope.ml:1417`).
   No application of a callee abstract means `None`, and the caller falls
   through to `demand_flow` as today.
2. Gates:
   - the callee's element return is in `elem_ret_proved`, or, from phase 4, is an `@[assume]` element return (§7.2);
   - P1/P2 (`parametric_ok`, `refine_param.ml:461`) for the positive bases, for a proved callee, exactly as arity 1;
   - P1 only for an assumed callee (it has no checked body for P2 to be about).
3. Instantiate each abstract `p` the return applies (§4.1), check arity, β-substitute, normalise: that is the **produced** entry.
4. **Conjunction** (AR §3.4, generalised): if every positive base's sources are the same single `Src_elem (j, [(C, _)])` and argument j has an entry (`container_entry_of_expr`), produced := `entry_meet arg_entry produced`. For `Map` this never applies (F4, `sources_of = None`). §8 names the cost. When it is declined *and* the argument does carry an entry, a too-weak detail says so: "…; `m`'s own element facts are not carried through `Map.filter`". (My call: the reason stays too-weak, the sentence stops it misleading.)
5. `entry_implies ~have:produced ~want` in a scratch ledger, with `strict_verified := false`, as today:
   - every obligation proved → `` `Proved ``;
   - any refuted → `` `Too_weak `` (detail: the source as written, and the first unimplied want slot or relation);
   - otherwise `` `Undecided ``.

   One `record_abstract_verdict` per demanded call, as today, with predicate `first_slot_pred` (my call: one obligation per call, not per slot, so arity-1 ledgers are unchanged).

For arity 1, a single-slot `want` and a produced entry without rels, steps 1-5
must yield the same verdict, detail and ledger line as today. The phase 2
oracle diff is restricted to new fixtures.

### 4.3 Negative occurrences

`abstract_param_entry` (`refine_check.ml:1408`) generalises the same way. A
parameter `m : Map(k[p], v[p])` instantiates `p` at the call and obliges the
argument against the produced relational entry, using `elem_markers_of_arg` for
the sorts. An unknown sort declines (`uninstantiated`), as AR phase 2's
pressure-test fix (a) requires.

### 4.4 VC cache

The key is the full query text (AR §8, verified in AR phase 2). The instantiated
`q` and the fresh-constant names appear in it. One test: two calls whose
lambdas differ only in the relation (`v > k` vs `v >= k`); the second must not
inherit the first's verdict.

---

## 5. Inside the declaring function

### 5.1 `collect`, roles and arity (`refine_abstract.ml`)

- `applications` returns `(name, arg list, span)` for any arity. Arguments are classified as today: bare variable or `_`, else `$computed`.
- `walk_ty`'s `TyArrow` arm (`:133-139`) walks a **chain**: for a parameter `D1 -> … -> Dn -> C`, a definer occurrence in `C` records the binder list `[b1..bn]` (each `Di`'s binder) and per-position bases. The current per-arrow `dom_binder` is the n = 1 case.
- A `TyCon` walk records, for each slot predicate, the application's sibling binders, so W2 can check occurrence arguments against them.
- New: `arity_of : … -> string -> int option`, and `positive_bases` replacing `positive_base` (`:329`) with one base per position.
- `definer_index` (`:307`) is unchanged.

### 5.2 Element slots over type variables

`abstract_tyvar_slot` (`refine_scope.ml:1417`) admits a tyvar slot whose
predicate applies a current abstract. It is extended: a relation whose
predicate applies a current abstract is admitted inside the declaring
definition, and nowhere else (the same B4 exclusion via `entry_mentions`).
`has_elem_return` (`refine_check.ml:3959`) counts such a return.

### 5.3 The callback's own contract: `callback_sig_of_ty` on a chain

`callback_sig_of_ty` (`refine_scope.ml:845`) builds a one-parameter signature
named `$cb_arg`. For a chain it now builds an n-parameter signature
`[$cb_arg; $cb_arg2; …]`, with `param_tys` the domains and `ret` the final
codomain rewritten over those names (each domain binder renamed, as the 2026-10-06
callback-binder fix does for one). This happens **only** when the final codomain is
- (i) a definer of a current abstract, or
- (ii) `{Bool | _ == e}`, a predicate contract (needed for callback passthrough, §4.1).

Every other chain keeps today's one-parameter signature, so no existing
obligation or fact moves. The phase 2 oracle must show no change outside the
new fixtures; any other change is a scope bug in this condition. The
`declared_elem_return` marker test `sg.param_names = [ callback_param_name ]`
(`refine_check.ml:758`) becomes "`List.hd sg.param_names = callback_param_name`".

A call through it with **all n arguments**, `keep(k, v)`, reflects to
`keep$ret == $abs_p(k, v)` through `postcond_of`. A call with fewer arguments
(`let g = keep(k)`) must get **no** postcondition, because the result is a
function. There is a test for this (`partial_call_no_fact`).

### 5.4 The judgment

The user container of row a1:

```march
fn filt(a : Assoc(k, v), keep : k -> v -> Bool[p]) : Assoc(k[p], v[p]) do
  match a do
  ANil -> ANil
  ACons(k, v, t) -> if keep(k, v) do ACons(k, v, filt(t, keep)) else filt(t, keep) end
  end
end
```

How the body discharges it:
- `ACons(k, v, …)` owes `$abs_p(k, v)` (§2.5 `ECon` row). The branch gives `keep(k, v) == true`, and §5.3 gives `keep(k, v) == $abs_p(k, v)`. Together they are one quantifier-free implication.
- The `filt(t, keep)` tails are the self-call hypothesis (EF §3.2, `structural_subvars`). The hypothesis entry carries the relation.
- `ANil` owes nothing (it carries no `Param` field).

The function enters `elem_ret_proved` through the existing `gate_elem_returns`
rounds.

**Negative test (a1-bad):** `fn bad(a : Assoc(k, v), keep : …) : Assoc(k[p], v[p]) do a end`
must not prove. `a`'s entries carry nothing about `p`, so `entry_implies`
skips on the relation.

### 5.5 Pass sites

No codomain obligation is owed for an arity-n definer (F10). Passing any
callable for the defining parameter is allowed, by the AR definer argument:
`p` *is* what the callable returns. §5.3 must not introduce one. Rows m12/a4
pin it under `cap verified`.

### 5.6 Not supported inside a body (named, not silent)

- A curried callback called in two steps (`let g = keep(k)` then `g(v)`, `Map.filter`'s own style) gives `g(v)` no fact. A combinator written that way does not prove its relational return. That is why `Map.filter` is `@[assume]` rather than rewritten (§7). A `lets`-channel record of the partial application would close it: filed (§8).
- `keep(k)(v)` is not March syntax (a3).

---

## 6. Soundness

| New assumption | Justified by | Guarded by |
|---|---|---|
| a relation in a declared entry holds per entry | the declaration; obliged at every construction (§2.5 `ECon`) and every subtyping step (§2.4) | W4 entry shape; phase 0 (no hidden field is vacuously true); `entry_is_closed` at call sites |
| projection of a relation onto one slot | `(∃k. A) ⇒ D ≡ ∀k. (A ⇒ D)`; every slot value lies in some entry | W4 (entry-shaped); fresh constants per slot; declines on unknown sort |
| a relation as a `match` path fact | the binders are the components of one entry | only when all its slots are `PatVar`s of the same constructor occurrence |
| rels through `parametric_return` | parametricity: the result's entries are the source's entries | single common `Src_elem` source, slot-for-slot type arguments, P1/P2 |
| `$abs_p` n-ary inside the body | uninterpreted; the body knows only the callback's contract | one declaration per sort tuple; W3; `sort_conflict` |
| `keep(k, v) == $abs_p(k, v)` | the chain codomain; every callable passed is by definition `p` | full-arity calls only; §5.3's two shapes only |
| the produced entry at a call | the callee's proved (or, phase 4, assumed) element return | `elem_ret_proved` / §7.2; P1/P2 (proved) or P1 (assumed) |
| the instantiation `q` | what the actual callable returns | capture-free; opaque-call decline; arity check; proved named returns only |
| conjunction with the input entry | both hold per entry; the result's entries are the input's | single common source; never for `Map` |
| an `@[assume]`d element return (phase 4) | trust, as every `Map` contract already is | counted `trusted` in the ledger and the audit; a runtime property witness in `test/stdlib/test_map.march` |

Every row gets a REJECT or SKIP control in the tests (§9), per the standing
rule that accept-only witnesses cannot distinguish a working rule from one that
checks nothing.

**What is deliberately not claimed.**
- `Map.filter` promises nothing about entries it dropped.
- Projection never yields a relation between two *different* entries (sortedness, `sort_by`'s `a -> a -> Bool`). An arity-2 `p` over two elements of the same container is a different mechanism and out of scope.
- A fold accumulator invariant belongs to the sibling design.

---

## 7. The standard library

### 7.1 Which combinators

| Combinator | Verdict | Why |
|---|---|---|
| `Map.filter` | **carries it, `@[assume]`** (phase 4) | Its body goes `entries(m)` (a `List((k, v))`: tuples are not modelled) → `insert` (itself `@[assume]`, no element return), and calls `pred` curried (§5.6). The checker cannot see into it. Every other `Map` contract is already `@[assume]` for the same reason. |
| `HashMap.filter` | same recipe; **not in phase 4** (my call: one carrier per PR) | same HAMT shape, unannotated today; filed |
| `OrderedMap.filter` / `tree_filter` | out | `Tree(k, v)` is entry-shaped and `tree_filter` calls `f(k, v)` uncurried, which is the ideal case. But the public type is an anonymous record `{cmp, tree}` (no element slots through `TyRecord`), and the body routes entries through `tree_min : Option((k, v))` (tuples) and `balance`. Filed. |
| `Map.find` / `any` / `filter_map` / `partition` | do not exist in `Map` | — |
| `List.filter` over pairs (`List((k, v))`) | out | a tuple element has no slots; would need tuple-as-container. Filed. |
| `sort_by`, `zip_with` (`a -> a -> Bool`, `a -> b -> c`) | not this mechanism | a relation between entries, or not a filter |
| `List.fold_left` | sibling design | invariant, not element rule |

### 7.2 `@[assume]` for an element return (phase 4)

Today `@[assume]` assumes only the container-level predicate (F9). Phase 4
extends it so that an `@[assume]` function whose return has an element entry
(slots, rels, or abstract applications) is entered into a new table
`elem_ret_assumed` beside `elem_ret_proved` (`refine_param.ml:151`). Its body's
tails are **not** walked for that entry (they would only skip). Accounting:
- the definition counts one `trusted` postcondition per such entry, as `assumed_return` contracts do;
- `refine_audit` counts it trusted;
- `--refine-report` shows it under `trusted`.

Consumers:
- `declared_elem_return` (closed, non-abstract entries);
- `abstract_flow` gate (§4.2 step 2).

It is accepted under `cap verified` exactly like an assumed scalar return.

The witness: a `Check.all` property in `test/stdlib/test_map.march`. Over
random `List((Int, Int))`, build a map and a threshold-family predicate, and
assert every entry of `Map.filter(m, fn k -> fn v -> pred)` satisfies `pred`.
It must go RED when `Map.filter`'s `if p(v)` is inverted (perturbation shown in
the progress note). The existing tests at `test_map.march:219-223, 354-362` stay.

Also in phase 4, `Map.filter` gains parameter annotations `m : Map(k, v)`,
`pred : k -> v -> Bool[p]`, `cmp : k -> k -> Bool` so P1 can hold. **Trap**
(memory: stdlib signature edits): a wrong stdlib annotation can typecheck to
an internal error that `--check` does not print. Run the full
`scripts/run-tests.sh` (the compiler suite's stdlib ratchet) before trusting
`--check`. If P1 still fails for `Map.filter` with honest annotations, the
annotations are wrong. Fix them, and do not drop the P1 gate.

---

## 8. Scope

In scope:
- relational element facts over the scalar slots of an entry-shaped container, written concretely or produced by an arity-n abstract refinement;
- a definer on a curried arrow chain;
- instantiation from curried or uncurried lambdas, `let`-bound lambdas, eta, n-parameter named predicates with a proved contract, and chain-typed callback parameters;
- projection of a relation onto any slot subset;
- `Map.filter` (assumed).

Out of scope, each filed as a `specs/todos/` entry by the phase named, so no
guarantee is read into its absence:

- **`Map` element flow through `Map`'s own functions** (`insert`, `remove`, `get`, `merge`, `map_values`: m10/m11). `Map` hides both parameters (F4) and its functions are unannotated. Needs an opaque-container source rule ("a ptype's own module functions are the only producers"). Without it, `Map.filter(pos_map, …)` loses `pos_map`'s own facts (§4.2 step 4). Filed in phase 4: `map-element-flow-through-combinators`.
- **The slot-names-a-parameter false violation** (r7: `{y : Int | y > x}` with `x : {Int | _ > 1000}` a parameter reports `x = -1`). A separate defect in how the subtyping query scopes a free parameter name. Filed in phase 0: `elem-slot-naming-parameter-false-violation`.
- A curried two-step call inside a body (§5.6). Filed in phase 2.
- `HashMap.filter`, `OrderedMap.filter`, tuple elements (`List((k, v))`) (§7.1). Filed in phase 4.
- Relations over nested-container slots (I2), or across nesting levels (`Assoc({x | …}, List({y | y > x}))`).
- Bounded refinements, `impl` dispatch, `interface` methods, inference: unchanged from AR §6.

---

## 9. Phases, one PR each

Conventions as in AR §7:
- every step keeps `test_refinecheck.exe` green;
- every new rule lands with a fixture that goes RED without it;
- ledger triples are asserted, never exit codes;
- `--root .`, z3 on PATH, CI's z3 4.8.12 noted;
- `scripts/refine-oracle.sh` under a private `HOME`, every diff line explained;
- audit baselines regenerated with the reason stated.

Conformance fixture numbers are written `tNNN`: take the next free number at landing (the fold sibling design plans `t325`/`t326`).

Each phase:
- adds a `specs/progress/2026-MM-DD-abstract-multiarg-phaseN.md` note;
- adds a `CHANGELOG.md` `[Unreleased]` bullet (phase 0 `### Fixed`, phases 1-4 `### Added`);
- updates `specs/lang/refinement-types.md` and runs `scripts/gen-lang-docs.py` (committing `docs/refinement-types.md`).

New `test_refinecheck` groups are registered in the suite list at
`test/test_refinecheck.ml:18870-18884`.

### Phase 0: no vacuous hidden-field construction (soundness, independent)

**Change.** `ctor_field_params` (§2.3). In the `ECon` arm, an `Other` field
whose type mentions a type parameter j whose demanded slot is `Some` is a
recorded skip (`unreflectable-subject`: "`Wrap`'s field holds `v` inside
`List((k, v))`, which the element model does not see into"), not `true`. A
skipped tail keeps the function out of `elem_ret_proved`.

**RED tests** (group `hidden-field-elements`):
- h1 (`need(mk())` must be a skip, not proved; under `cap verified` an error);
- h2 (an obligation exists and skips);
- control: `Assoc`/`Cons`/`Some` constructions unchanged (literal proved, literal violated).

**Oracle.** Every changed line must be a former vacuous proof. If a stdlib
function's element return stops proving, list it. Each one was a false proof.
**Files** the r7 todo.
**Docs.** "What element refinements do not do": a container whose constructor
hides a parameter inside another type (`Box(Int -> b)`, `Wrap(List((k, v)))`)
has its element refinement checked at no construction.

### Phase 1: relational element facts (R1)

- **1a (commit, inert).** The type migration of §2.2 with `rels = []`
  everywhere and `entry_implies` equal to today's arm. **Oracle IDENTICAL, audit
  baselines byte-identical, `stdlib/list.march` ratchet unchanged.**
- **1b.** `elem_refinement` reads sibling-binder slots into rels; `normalize_entry`;
  W2/W4 for concrete relations (warning, §1.4); §2.4 projection and relational
  subtyping; §2.5's `ECon` relation obligations and `match` path facts;
  `parametric_return`/`demand_flow` relation rules; audit.

**RED tests** (group `relational-elements`):

| Test | Asserts | Red without |
|---|---|---|
| r1 / r2 | literal relation proved / violated (witness names both fields) | `ECon` rel obligation |
| r3 / r4 | projection and alpha-renamed relational subtyping proved (were false violations) | `entry_implies` |
| r4' control | same-name spelling still proved | — |
| r5 | `match` binders `need_gt(k, v)` proved | path fact |
| r6 | weaker relation still a violation | — |
| `proj_insufficient` | `{x \| true}, {y \| y > x}` into `Assoc(Int, {Int \| _ > 0})` is a **violation** with `x = -1, y = 0`: it does not imply. Controls that the projection is not vacuous. | — |
| `two_not_entry_shaped` | `type Two(k, v) = K(k) \| V(v)` with a relation: warning, relation neither assumed nor obliged (a `V(0 - 5)` into a projecting demand is not proved) | W4 |
| `nested_slot_rel` | relation naming a `List(...)` slot: warning, unchecked | I2 |
| `rel_through_reverse` | a parametric `Assoc(k, v) -> Assoc(k, v)` reverse keeps the relation | `parametric_return` rel rule |
| `rel_two_sources` | `zip`-shaped two-source callee: relation dropped, demand skip `parametric-source-unproved` | — |
| `sibling_shadows_param` | `fn f(x : Int, a : Assoc({x : Int \| true}, {y \| y > x}))`: the sibling is meant | — |
| `unary_rel_is_slot` | `{x \| true}, {y \| y > 0}`: ledger byte-identical to the plain unary form | (I1) |
| `determinism` | two runs, cold/warm `HOME`: identical `.ll`/ledger (`scripts/determinism-oracle.sh --corpus small`) | — |

**Conformance:** `specs/lang/types/accept/tNNN_relational_element_refinement.march`
(r1, r3, r5 under `cap verified`), `reject/tNNN_relational_element_violated.march` (r2), INDEX.
**Docs:** a new subsection "Relational element refinements" under element
refinements (§1.3 syntax, entry shape, projection, what is not checked).

### Phase 2: arity-n abstract refinements (long form only)

§3a's SMT arm, preamble and guards; §5.1 collect/roles/W1-W5; §5.2; §5.3; §4.1-§4.3.

**RED tests** (group `abstract-multiarg`):

| Test | Asserts | Red without |
|---|---|---|
| s1 roles | `p` abstract, arity 2, no unknown-predicate warning | n-ary `applications` |
| W1 (s5) / W2 / W3 / W5 | one hard error each, with its fix text | each rule |
| a1 | `filt`'s return proved (definition side) | §3a + §5.3 |
| a1-bad | returning the input: not proved (skip) | — |
| `partial_call_no_fact` | `let g = keep(k)` yields no postcondition | — |
| a2 | `need_pos(filt(a, fn (_k, v) -> v > 0))` proved | §4 |
| `curried_lambda` | a curried-calling `filt2` with `fn _k -> fn v -> v > 0` proved | §4.1 curried arm |
| `key_projection` | demand on keys only proved | — |
| `rel_demand` | `need_arel(filt(a, fn (k, v) -> v > k))` proved | — |
| `projection_fresh_k` (m5 shape) / `projection_too_weak` (m6 shape) | proved / too-weak | §2.4 |
| `too_weak` (m4 shape) | too-weak, detail names the lambda | — |
| `capture` (m7) / `opaque` / `wrong_arity_lambda` | uninstantiated | — |
| `named2` | `above(k : Int, v : Int) : {Bool \| _ == (v > k)}` passed to `filt` proved; unproved-return control uninstantiated | `named_predicate` n-ary |
| `cb_passthrough` | a chain-typed callback parameter passed through proved | §5.3 (ii) |
| `let_lambda` | `let keep = fn (k, v) -> v > k` proved; rebinding retires it | — |
| `conjunction` | `filt(pos_assoc, fn (_k, v) -> v < 100)` into `{_ > 0 && _ < 100}` proved; control without the incoming fact too-weak | §4.2 step 4 |
| `negative_occurrence` | `need(a : Assoc(k[p], v[p]) …)` long form: refined input proved, literal violated, unrefined skip, opaque uninstantiated | §4.3 |
| `cache` | two lambdas differing only in the relation: independent verdicts | §4.4 |
| a4 / `cap verified` | no definer obligation; a too-weak demand is an error, a proved one is not | §5.5 |
| `arity1_unchanged` | the AR phase 2/3 groups pass unmodified | — |

**Oracle:** changes only in new fixtures. **Files** the §5.6 todo.
**Conformance:** `accept/tNNN_two_argument_abstract_refinement.march`,
`reject/tNNN_two_argument_abstract_too_weak.march`.
**Docs:** the "Abstract refinements" section gains the two-argument form
(long form). "One argument only" becomes "**`Map.filter` does not carry it yet**".

### Phase 3: sugar

**Parser** (`parser.mly`, semantic actions only, **no production change**):
- `abstract_definer_arrow` marks the codomain it generates with the unforgeable binder `Some "_"` on the `Bool` refinement, so its output is recognisable.
- When `cod` is `TyArrow (dom2, <that marked definer>)`, the outer reduction extends the chain: it binds `dom` (its own named binder if it has one, else `"$x" ^ string_of_int (depth+1)`; innermost stays `$x`, keeping arity-1 output's binders) and prepends it to `p`'s arguments.
- The tuple-domain error text is corrected (s2).

**`ast.ml` `show_ty`** (`:526`): the marked definer codomain prints as
`Bool[p]` (arrow chains print `k -> v -> Bool[p]`).

**`Refine_abstract.expand_markers`**: a pre-pass applied to every `DFn`'s
declared types before `Refine_check` builds its tables. For an arity-n `p`
(n ≥ 2), the marker slots `T(…k[p]…, …v[p]…)` of one application become the
long form `T({$s0 : k | true}, {$s1 : v | p($s0, $s1)})`. A number of marked
slots ≠ n is W2's error.

**Menhir:** conflicts stay **7** (`_build/default/lib/parser/parser.conflicts`).
Only actions change, so the count cannot move, but it is asserted.

**Tree-sitter:** `k -> v -> Bool[p]` and `Map(k[p], v[p])` are existing
tokens and rules (`abstract_refinement_type`, arrows). `tree-sitter-march/grammar.js`
needs no change and the new fixtures parse. State that in the PR, and run
`scripts/check-tree-sitter.sh` (CI job `tree-sitter`): green with no
`known-failures.txt` or `keyword-allowlist.txt` entry. No new keyword.

**RED tests** (group `abstract-multiarg-sugar`):
- role equivalence of the s3 sugar with the s1 long form (the AR-phase-4 role summary, `D=` included);
- `Map(k, v[p])` W2 error; `Map(k[p], v[p])` with an arity-1 `p` keeps two unary facts;
- s2 new message;
- `show_ty` round-trip;
- **arity-1 equivalence:** `refine-oracle` IDENTICAL and audit byte-identical over the AR corpus after the binder-marker change. This is AR phase 4's D6 proof, re-run.

The AR-phase-4 test `a curried Bool[p] proves nothing and violates nothing`
(`test/test_refinecheck.ml:18066`) is deliberately rewritten: its signature
(`List(Int[p])` with `Int -> Int -> Bool[p]`) is now a W2 error. Say so in the
progress note.

**Grammar corpus:**
- `specs/lang/grammar/parse/p43_abstract_refinement_two_argument_sugar.march`;
- `reject/r20_bool_sugar_two_argument_single_slot.march`;
- `reject/r19`'s `-- EXPECT-ERROR:` line and `specs/lang/grammar/INDEX.md:104` updated to the new text;
- INDEX counts (doc-lint's conformance-corpus check).

**Docs:** replace the curried bullet (`specs/lang/refinement-types.md:2180-2181`)
and the tuple wording (`:2176-2178`).

### Phase 4: `Map.filter`

- §7.2: `elem_ret_assumed` and its accounting.
- `Map.filter`'s annotated signature (§1.2) with its `doc` paragraph extended ("…and that every entry satisfies `pred`").
- The witness property test.
- Audit baselines.

**RED tests** (group `abstract-map`): m1, m2, m3, m4, m5, m6, m7, m8 (each
the verdict in §0's After column), m9 unchanged, m12 (`cap verified`, no
demand: no error), and `assumed_counted` (one `trusted` at the definition). The
`stdlib/cluster_node.march:920` call (`fn _a -> fn until -> until > now`)
files no obligation, since it has no demand. The oracle shows it unchanged.

**Full sweep:**
- `stdlib`, `test/native`, `test/stdlib`, and the ecosystem repos (`conduit`, `depot`: 77 lib files, base vs branch, `--check --refine-report`), because a new fact can turn a skip into a violation;
- full `scripts/run-tests.sh`, for the stdlib-signature trap.

**Files** the §8 phase-4 todos.

**Todo bookkeeping:**
- `git mv specs/todos/2026-09-20-abstract-refinements-multi-arg-callbacks.md specs/progress/…`, if the fold sibling has already dropped its `fold_left` bullet (its plan says it does);
- otherwise edit the todo down to that bullet.

**Docs:**
- "Only four combinators" becomes five;
- remove "`Map.filter` does not carry it yet";
- the Set-Refinements `Map` paragraph mentions the assumed entry fact;
- correct the reference's `(k, v) -> Bool` to `k -> v -> Bool` (curried).

---

## 10. Performance

New queries:
- one per want obligation (refined slot or relation) per demanded call (§2.4/§4.2), in a scratch ledger, plus the existing one ledger entry;
- one per want relation per construction (§2.5).

Program text without relations or arity-n abstracts sends exactly today's
queries, which phase 1a proves with an IDENTICAL oracle.

Budget: cold `--check --stdlib-source stdlib/list.march` and
`stdlib/map.march` within **110%** of the pre-change time. Protocol as AR §8:
private `HOME`, `.march/cas/vc` cleared once, interleaved A/B, five runs, median,
and the load average recorded (memory: a high load makes timings lie). The
fresh-constant names are fixed strings, so warm runs hit the VC cache.

---

## 11. Decisions

Settled here (my calls, each revisitable without reopening the design):

1. **R1** (entry record with relations) over a pseudo-slot, a side channel, or sibling names left in slot predicates (§2.1).
2. **Normal form (I1):** a one-slot fact is always a slot fact. A partial instantiation is therefore never a relation (§2.2).
3. **Projection** by fresh constants per slot with all have facts; sound and complete (§2.4).
4. **One ledger obligation per demanded call** in `abstract_flow`, as for arity 1 (§4.2).
5. **A concrete relation that breaks W2/W4 warns `refinement_unchecked`** and is ignored both ways. No new error code (§1.4).
6. **Sibling binders shadow value parameters**, and are visible in any slot order (§1.3).
7. **Chain callback signatures only for the two codomain shapes** of §5.3, so no unrelated chain gains obligations.
8. **No new skip reasons.** Existing slugs with new detail text.
9. **`HashMap.filter` is not in phase 4**; it is filed with the same recipe.
10. **The too-weak detail notes a declined conjunction** (§4.2 step 4).

Open for the user, each with a recommendation, in the order they block:

- **D1. `Map.filter`'s fact is `@[assume]`d (§7.2).** Recommended: yes, with
  the runtime property witness. Every `Map` contract is already assumed, and
  the body cannot be proved without tuple elements and two-step curried calls
  (§5.6, §7.1). Alternatives: rewrite `Map.filter` to a structural HAMT walk
  (still blocked by `HCollision`'s tuple list), or ship phases 0-3 and leave
  `Map` out.
- **D2. Concrete relational element refinements are a user-facing feature
  (§1.3), not only the internal form of an instantiated `p`.** Recommended:
  yes. A relational *demand* (`need_rel`) needs a spelling anyway, and the
  spelling already parses and is misread today, with false violations (r3/r4).
  The alternative is to reject a sibling-binder slot with an error, which still
  needs phase 1's machinery for instantiated relations.
- **D3. Two currently-accepted, inert shapes become hard errors:** the
  curried long form applying `p` to some of the chain's binders (s5), and an
  arity-2 `p` marking a single slot (the AR-phase-4 curried test). Recommended:
  yes. Accepting `p(y)` under a two-binder chain is the "binds only one
  argument" half-measure the 2026-09-20 review rejected, and arity n makes it
  unnecessary (a `q` over `v` alone normalises to a slot fact). The phase 2
  oracle sweep shows whether anything outside the test suite uses either shape.
