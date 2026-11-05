# Stdlib lemma and refinement sweep beyond `List` (design, 2026-11-04)

Reflection phase 3 (`specs/2026-10-29-refinement-reflection-design.md` §10, D18) shipped one
stdlib lemma set: 13 lemmas in `stdlib/list.march` over `append`, `reverse`, `take` and `drop`,
admitted through `stdlib/lemmas.verified`. No other module has a lemma, and no phase plans
any. This document surveys the rest of the stdlib and lays out the sweep in phases, ordered by
what proves today.

## 1. What a sweep can add

The stdlib can carry two kinds of law:
- **A refined result type**, such as `fn min_int(a, b) : {Int | _ <= a && _ <= b}`.
  - Every caller gets it, with nothing to write.
  - A proved one is a fact at call sites (`gate_unverified_posts`).
  - This is the first choice whenever the law is about one call's result.
  - It must not add a **precondition**: a refined parameter is a new obligation at every
    existing caller, which is a breaking change. A law that holds only under a condition is
    stated as a conditional result (`{Int | high < low || (_ >= low && _ <= high)}`).
- **A lemma**, for a law that relates several calls (`to_option(to_result(o, e)) == o`), or
  that a caller needs only sometimes. It costs nothing at run time (it is erased), but a caller
  has to call it.

Both have to be proved, never assumed. An `@[assume]` contract is a trusted axiom. The stdlib
already has many: `Map`'s and `Set`'s `keys` / `elts` contracts, such as
`Map.insert : keys(_) == union(keys(m), singleton(key))`. Proving those is a separate,
larger effort (§4).

## 2. Survey (measured 2026-11-04, compiler at the return-contract fix)

**Method.**
- `march --check --stdlib-source --reflect-report stdlib/<m>.march` for which functions reflect.
  For `list.march` this over-reports R6 "a name more than one declaration could denote",
  because the file is loaded twice.
- Candidate laws written as user lemmas over the qualified names, then
  `--refine-report-sites=all`.
- Return contracts written on copies of the stdlib bodies.

| Module | Functions | Reflected / specialised |
|---|---|---|
| `List` | 98 | 18 reflected (plus `take`, `drop`, `filter`, `map` per phase 3/5) |
| `Option` | 14 | 6 reflected, 5 specialised (`map`, `flat_map`, `filter`, …) |
| `Result` | 14 | 6 reflected, 4 specialised |
| `Math` | 35 | 10 reflected (`min_int`, `max_int`, `clamp_int`, constants, `lerp`) |
| `Tuple` | 13 | 8 reflected, 5 specialised |
| `Map`, `Set` | 71, 58 | internal list helpers only; the public API is `@[assume]` over `keys` / `elts` |
| `String`, `Range` | 39, 19 | 1 each |

### 2.1 Proves today (generic `a` where it applies)

| Law | Kind |
|---|---|
| `Option.unwrap_or(Some(x), d) == x`, `Option.unwrap_or(None, d) == d` | lemma |
| `Option.is_some(o) == !Option.is_none(o)` | lemma |
| `len(Option.to_list(o)) <= 1` | lemma |
| `Result.to_option(Option.to_result(o, e)) == o` | lemma |
| `Result.is_ok(r) == !Result.is_err(r)` | lemma |
| `Result.unwrap_or(Ok(x), d) == x`, `Result.unwrap_or(Err(e), d) == d` | lemma |
| `Result.to_option(Ok(x)) == Some(x)` | lemma |
| `Math.min_int : {Int \| _ <= a && _ <= b && (_ == a \|\| _ == b)}`, and `max_int` dually | result type |
| `Math.min_int(a, b) + Math.max_int(a, b) == a + b` | lemma |
| `Math.clamp_int`: result within `[low, high]` when `low <= high` | conditional result type |
| `List.head_opt(Cons(x, xs)) == Some(x)` | lemma |
| `List.length(xs) == len(xs)` (by induction) | lemma |
| `List.drop(List.append(xs, ys), len(xs)) == ys` | lemma |
| `List.nth_opt(List.append(xs, ys), i) == List.nth_opt(xs, i)` for `0 <= i < len(xs)` | lemma |

**Measured when building S1: most of these prove, but help no caller.** A caller was checked
with and without each law (`specs/progress/2026-11-04-stdlib-lemma-sweep-s1.md`):
- **Already proved by unfolding, no lemma needed:** the `Math` laws (`min + max == a + b`,
  `clamp_int` in range), `len(Option.to_list(o)) <= 1`, the `to_result` / `to_option` round
  trip, and `Result.unwrap_or(Ok(x), d) == x` when the call is `let`-bound.
- **Not translated as a call's subject, with or without the lemma:** `Option.unwrap_or` as a
  direct argument, `Option.is_some` / `is_none`, `Result.is_ok` / `is_err`, and
  `List.head_opt`. The lemma's fact is there, but the goal is never built
  (`unreflectable-subject`). That is a checker gap of its own
  (`specs/todos/2026-11-04-stdlib-call-subjects-unreflectable.md`), and the lemmas wait for it.
- **Needed and shipped:** `List.drop_append` (`reflect-fuel` without it), `List.nth_opt_append`
  (`unconstrained-subject`), and `List.take_append` with its accumulator lemma
  `take_onto_append` (moved up from §2.2). The `Math` result types shipped too: callers
  already unfold the bodies, but the types state the laws in the signature.

### 2.2 Blocked, and on what

| Law | Blocker |
|---|---|
| `List.length : {Int \| _ == len(xs)}`, `sum_int(append(xs, ys)) == sum_int(xs) + sum_int(ys)`, `sum_int(reverse(xs)) == sum_int(xs)`, `product_int` likewise | the loop is a local `go` with an accumulator. Its accumulator lemma can't be stated outside the function, so `go` has to be lifted to a `pfn`, as phase 3 did for `reverse_onto` (same TRMC and inlining; ir-oracle reports the rename) |
| `List.is_empty(xs) == (len(xs) == 0)` | `List.is_empty` as a qualified predicate call is refused (`refinement_unchecked`: "never reflected here"), unlike `List.length`. `is_empty` is also declared by `Map`, `Set` and `String`, so this is likely the short-name conflation of `2026-11-03-reflect-type-name-clash-with-stdlib` |
| `Tuple.swap(Tuple.swap(p)) == p`, `Tuple.first(Tuple.swap(p)) == Tuple.second(p)` | the same refusal for `Tuple.*`. Tuples are not a predicate sort |
| any law about `List.map`, `filter`, `fold_left`, `Option.map`, … | a predicate cannot name a function that takes a function (phase 5, D10: such a function is reflected only per call site with a lambda) |
| `Map` / `Set` laws | already axiomatised (`@[assume]` over `keys` / `elts`); proving them is §4 |
| `String` laws | `String` contents are opaque to the logic |

## 3. Phases

**S1: the laws that prove today (§2.1).** No compiler change.
- Lemmas go in `stdlib/option.march`, `stdlib/result.march`, `stdlib/math.march` and
  `stdlib/list.march`, next to the functions they are about, with the doc comment style of the
  phase 3 lemmas.
- Result types go on `Math.min_int`, `max_int` and `clamp_int`. `clamp_int`'s is conditional,
  so no caller gets a new obligation.
- Then:
  - regenerate `stdlib/lemmas.verified` (`scripts/gen-lemma-manifest.sh`);
  - refresh the refinement audit baselines (`audit-baseline`), whose enforced count moves;
  - update the stdlib API docs that `scripts/check-docs.sh` counts.
- Tests (new group `reflect-stdlib-sweep`, in the style of `test/test_refine_stdlib_list.ml`):
  - each lemma, called from user code, closes a precondition that skips without it;
  - each new result type proves at its definition and gives its fact at a caller;
  - a REJECT control per module (a call that does not meet a lemma's precondition gives no
    fact);
  - the manifest test stays green.
- Measure the checker's cost on the stdlib (the manifest admits the lemmas, so a user program
  should not pay for their proofs).

**S2: lift the accumulator loops.**
- `List.length`, `sum_int`, `product_int`, `minimum_int` and `maximum_int` get
  `pfn length_onto`, `sum_onto`, … as phase 3 did.
- Then come the accumulator lemmas, `length : {Int | _ == len(xs)}`, the `sum_int` /
  `product_int` laws over `append` and `reverse`.
- Checks: ir-oracle with phase 3's normalising rename diff, and `bench/list_ops.march` at
  `--opt 2`.

**S3: encoder work, each its own todo.**
- Tuples as a predicate sort, for the `Tuple` laws and the `zip` / `unzip` round trip.
- Qualified `List.is_empty` and other names declared in several modules, which is the name-clash
  todo.

**Not planned here:**
- higher-order laws (the D10 limit);
- `String`;
- §4.

## 4. Separately: proving the `@[assume]` contracts

`Map` and `Set` state their API as trusted contracts over the `keys` / `elts` measures. They
are the trusted base of every proof about a map. Proving them against the AVL implementation
needs:
- measures over the tree (`keys(node)`);
- the balance invariant;
- set reasoning through rotations.

That is a design of its own. The sweep leaves them trusted and lists them in the trusted-base
section of the claim docs, as now.

## 5. Risks

- **A new result type changes callers' verdicts.** It can only add facts. Under `cap verified`
  it can only turn skips into proofs. The refine oracle over the corpus shows each move.
- **Lemma names live in each module's namespace** (`Option.unwrap_or_some`) and must not clash
  with existing functions. The compiler rejects a duplicate.
- **The manifest digests the files a lemma reaches.** Editing `option.march` re-proves its
  lemmas once, and the manifest test catches a stale entry.

## 6. Found on the way

- The obligation text drops parentheses: `{Int | _ <= a && _ <= b && (_ == a || _ == b)}` is
  printed as `_ <= a && _ <= b && _ == a || _ == b`, which reads as a different predicate.
  This is display only (the verdict uses the tree). It needs its own todo.
