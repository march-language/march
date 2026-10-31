# Design: refinement reflection, lemmas, and unfolding

**Date:** 2026-10-29
**Status:** design, revised after a fresh-context review (§12). Nothing built. Phases 0-3 below, one PR each; later phases listed.
**Base commit:** `7df0dc808` (origin/main, "browser: regenerate the in-browser REPL and live compiler").
**Probe environment:** compiler `_build/default/bin/main.exe` built from that commit with
`dune build --root . bin/main.exe`; z3 4.16.0 on PATH (CI has 4.8.12); macOS (Darwin 25.6),
load average 5-8. Every checker row was run from a script that sets a fresh `HOME=$(mktemp -d)`
per run:

```
HOME=$(mktemp -d) main.exe --check --refine-report --refine-report-sites probe.march
```

The probe programs live in the session scratch area (`refl/*.march`), not in the tree. Outputs
below are verbatim, except that the `non_tail_recursion` and `unused_binding` warnings every
probe draws are cut, and stdlib skip lines are cut. A row that says "interpreted" ran
`main.exe probe.march`.

**Prior designs this continues:**
- `specs/2026-06-21-measure-axioms-design.md` (measures as z3 axioms over datatypes);
- `specs/2026-10-26-termination-checking-design.md` (**TERM**) and its progress notes
  `specs/progress/2026-10-27-termination-phase{0..4}.md`, `2026-10-28-termination-phase5.md`;
- the language reference, `specs/lang/refinement-types.md`, sections "Measures: Refining over
  Data Structures" (`:1192`), "The measure soundness gate" (`:1640`) and "Termination" (`:4060`).

---

## Terms used in this document

These are Liquid Haskell (LH) terms. Each is defined once here.

- **Reflection.** Making an ordinary program function usable inside a refinement predicate,
  with its body as its meaning. After reflection, `reverse(reverse(xs)) == xs` is a statement
  about the real `reverse`, not about an unknown symbol.
- **Logic function.** The z3 function symbol that stands for a reflected function. This design
  names it `f$r` for a program function `f`.
- **Unfolding.** Adding one instance of a function's definition to a query: "for these
  particular arguments, `f$r(a, b)` equals the body of `f` with `a` and `b` substituted".
  An unfolding is a fact about specific terms, never a statement "for all".
- **Guarded equation.** One unfolding, split per `match` arm (or `if` branch): "if `xs` is
  `Nil` then `cat$r(xs, ys) = ys`". The guard is the arm's condition.
- **Proof by logical evaluation (PLE).** LH's algorithm. It unfolds every reflected call in a
  query, then unfolds again each new call whose guard the facts already decide, until nothing
  new appears. This design builds single unfolding first (D12) and the repeated, decided form
  later (D13).
- **Fuel.** A bound on how many times unfolding may repeat along one chain of calls.
- **Lemma.** A function whose return type states a theorem. Calling it puts the theorem into
  the facts at the call site. Its body is the proof.
- **Induction hypothesis (IH).** Inside a recursive lemma (or function), the assumption that
  the recursive call already satisfies the declared contract. TERM grants it only behind a
  termination certificate.
- **Erasure.** Removing code that exists only for the checker (lemma calls, lemma functions)
  before the program is compiled or run.

---

## 0. Where things stand (probed 2026-10-29 on `7df0dc808`)

### 0.1 Probe (a): `append` and `reverse` written today

The probe functions are named `cat` and `rev`, because `app` is a keyword (it starts an `app`
declaration). Their bodies:

```march
fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
  match xs do
    Nil -> ys
    Cons(h, t) -> Cons(h, cat(t, ys))
  end
end

fn rev(xs : List(Int)) : List(Int) do
  match xs do
    Nil -> Nil
    Cons(h, t) -> cat(rev(t), Cons(h, Nil))
  end
end
```

| Row | Program | Today (measured) |
|---|---|---|
| a1 | `cat : {List(Int) \| len(_) == len(xs) + len(ys)}`, `rev : {List(Int) \| len(_) == len(xs)}`; `need3(cat([1], [2, 3]))`, `need3(rev(…))` | **4 proved**, 0 skipped. Tier 2 structural induction proves both contracts; the calls use them |
| a2 | `cat` with no contract; `law(xs, ys) : {Int \| _ == len(xs) + len(ys)}` returning `List.length(cat(xs, ys))` | **skip `unreflectable-subject`** (postcondition `law`) |
| a3 | `revrev(xs) : {List(Int) \| _ == xs}` returning `rev(rev(xs))` | **skip `unreflectable-subject`** (postcondition `revrev`) |
| a4 | lemma shape: `revrev_lemma(xs) : {Unit \| rev(rev(xs)) == xs}` and `len_app_lemma(xs, ys) : {Unit \| len(cat(xs, ys)) == len(xs) + len(ys)}`, both with body `()` | two **`refinement_unchecked`** warnings per predicate, and **skip `unreflectable-subject`** for both |
| a5 | ground call with `assert`: `let a = cat([1], [2])`, `assert List.length(a) == 2`, `need2(a)` | **1 proved** |
| a6 | a5 without the `assert` | **skip `unconstrained-subject`**: "no fact the checker derived constrains `a`" |

The exact failure for `len(append(xs, ys)) == len(xs) + len(ys)` (a4):

```
skip	user	a4_lemma_unit.march:20:5	unreflectable-subject	postcondition	len_app_lemma	len(cat(xs, ys)) == len(xs) + len(ys)

-- WARNING ---------------------------- a4_lemma_unit.march

`cat` is not a measure or known predicate, so this refinement is not checked. Annotate the function `@[measure]`, or use a supported predicate. [refinement_unchecked]

20 |   fn len_app_lemma(xs : List(Int), ys : List(Int)) : {Unit | len(cat(xs, ys)) == len(xs) + len(ys)} do
                                                                      ^^^^^^^^^^^
```

The exact failure for `reverse(reverse(xs)) == xs` (a4):

```
skip	user	a4_lemma_unit.march:16:5	unreflectable-subject	postcondition	revrev_lemma	rev(rev(xs)) == xs

-- WARNING ---------------------------- a4_lemma_unit.march

`rev` is not a measure or known predicate, so this refinement is not checked. Annotate the function `@[measure]`, or use a supported predicate. [refinement_unchecked]

16 |   fn revrev_lemma(xs : List(Int)) : {Unit | rev(rev(xs)) == xs} do
                                                 ^^^^^^^^^^^^
```

(The warning is printed once for `rev(rev(xs))` and once for the inner `rev(xs)`.)

What can be proved today, then: any fact a **contract** states (a1), and any fact an `assert`
states at run time (a5). Nothing a function's **body** says reaches the solver, so a3/a4 fail
however simple the function. The warning's advice ("annotate `@[measure]`") is a dead end for
both: probe (b) shows why.

### 0.2 Probe (b): a two-argument measure

| Row | Program | Today (measured) |
|---|---|---|
| b1 | `@[measure] fn cat(xs : List(Int), ys : List(Int)) : List(Int)` (the a2 body); a lemma-shaped `{Unit \| len(cat(xs, ys)) == …}` | **error `invalid_measure`**, and the predicate is still `refinement_unchecked` |
| b2 | `@[measure] fn count_ge(xs : List(Int), k : Int) : Int` (`if h >= k do 1 + count_ge(t, k) else count_ge(t, k) end`); `need_small(count_ge([5], 3))` | **error `invalid_measure`**; the call is skip `unreflectable-subject`: "the argument `count_ge(Cons(5, Nil), 3)` could not be translated to SMT, so no goal was built" |

```
-- ERROR ----------------------- b1_two_arg_measure.march
@[measure] `cat` takes 2 parameters. A measure is a function of the single value it measures, and a predicate can only apply it to one argument, so no predicate mentioning `cat` could be translated. [invalid_measure]
3 |   fn cat(xs : List(Int), ys : List(Int)) : List(Int) do
```

There is no fallback: a multi-parameter measure is rejected outright (`measure_shape_error`,
`refine_encode.ml:2372-2401`).

### 0.3 Probe (c): a measure returning a list, and the Bool and gate rows

| Row | Program | Today (measured) |
|---|---|---|
| c1 | `@[measure] fn rev1(xs : List(Int)) : List(Int)` (structural); `{Unit \| len(rev1(xs)) == len(xs)}` | **accepted with no diagnostic**, but nothing reasons about it: skip `unreflectable-subject`. A silent fallback |
| c2 | `@[measure] fn all_pos(xs : List(Int)) : Bool` (`h > 0 && all_pos(t)`); `need(xs : {List(Int) \| all_pos(_)})` on `[1, 2]` and `[1, -2]` | both calls skip **`float-sort-gate`** |
| c2b | Bool measures with no element comparison: `even_len` (`not even_len(t)`) and non-recursive `pos_nat` on `type Nat = Z \| S(Nat)` | all four calls skip **`float-sort-gate`** |
| c2c | `{Nat \| pos_nat(_) == true}` | skip **`sort-conflict`**: "reflecting it would declare one symbol at two different sorts" |
| c4 | Int measure `sz`; `need(xs : {List(Int) \| sz(_) == 2})` on `[1, 2]` and `[1]` | **1 proved, 1 violated**: the measure machinery works for Int |
| c3b | `@[measure]`s whose `Nil` arm calls a user function that prints (`noisy`), panics (`boom`) or loops (`spin`) | **no `invalid_measure`**; the call skips `solver-undecided` |
| h2 | `@[measure]`s whose arm calls `show(h)` (a user `impl Show`) or builds `"${h}"` | **no `invalid_measure`**; skip `solver-undecided` |

### 0.4 Probe (e): how VCs are cached and keyed

| Row | Experiment | Today (measured) |
|---|---|---|
| e1 | a1 checked cold, then warm, under one private HOME, then with `cat`'s body edited (the recursive call moved into `let r = cat(t, ys)`) and its contract unchanged | 273 VC files after run 1; **273 after run 2; 273 after run 3, 0 new entries**. All verdicts unchanged (4 proved) |

The cache is content-addressed on the SMT text:

```ocaml
(* lib/refine/vc_cache.ml:6-7 *)
let key_of_vc ?(preamble = "") (vc : Smt.vc) : string =
  March_cas.Blake3.hash_string (preamble ^ "\n" ^ Smt.assertion_block vc)
```

The e1 edit happens to produce identical SMT text, so it shows only that a **caller's** VC holds
the callee's contract, never its body. A semantic edit of a body does change that function's
**own** postcondition VC: the review re-ran e1 with `rev`'s body changed and measured
`vc entries: 274, new: 1` (the new key is `rev`'s own post). No caller key changed in either run.

### 0.5 Probe (d): which functions D1 would reflect

Method: `--emit-core-ast` for each of the 135 `stdlib/*.march` and 417 `test/native/*.march`
files, plus `--check --termination-report` for the certificates, then a script over the JSON
(the D6 / D10 / D11 rules approximated, below). The script is a measurement; nothing in the
compiler trusts it.

A top-level `fn` (any `mod` depth; impl methods, handlers, externs and `main` excluded) counts as
reflectable when:
- it has none of `@[diverges]`, `@[trusted]`, `@[assume]`;
- no parameter has a function type, the body has no lambda, no call through a variable, and
  no function named as a value (D10);
- it has no `spawn` / `send`;
- no `non_exhaustive_match` diagnostic falls inside it;
- every recursive unit it owns (itself and its local `fn`s, named `f/go` by the termination
  report) has certificate `structural` or `metric` (D6);
- every callee survives the same test, or is a constructor, or is one of today's z3 operators
  (`+ - * negate not && || == != < <= > >= / %`, and the `len` spellings `List.length`,
  `String.byte_size`, `string_byte_length`). This is a greatest fixpoint (D11).

Divisions are counted, not excluded: D6 needs each `/` by a non-literal to have its
`Division` obligation proved, and the script cannot see that.

The script is deterministic: the fixpoint iterates in sorted order, and each unreflected
function's blocker is chosen **after** the fixpoint (a builtin or unresolved callee first, else the
first callee, in sorted order, that did not survive). Three runs under `PYTHONHASHSEED=1`, `2`
and `3` give the same MD5 of the whole output (`5dc60888620bd8d1cb498a6cf79eacf3`). The first
version iterated a Python set, so its breakdown (not its totals) moved with the hash seed; the
review measured that.

| | stdlib (135 files) | test/native (417 files) |
|---|---|---|
| top-level functions | 3,947 | 2,186 |
| **reflectable under D1** | **817 (20.7%)** | **384 (17.6%)** |
| of which recursive (certified) | 164 | 63 |
| of which non-recursive | 653 (103 take no arguments) | 321 (76 take no arguments) |
| of which take 2 or more parameters | 295 | 102 |
| of which divide by a non-literal (need a proved `Division`) | 8 | 1 |
| of which mention `Float` in the signature | 18 | 21 |

If no stdlib callee counted as reflected, the review measured test/native at 382; with the stdlib
reflected (§2.6), the 384 above is the figure.

The first blocking reason of the rest:

| Reason | stdlib | test/native |
|---|---|---|
| calls a builtin with no z3 meaning, or an unresolved name | 1,225 | 452 |
| it is `main` | — | 417 |
| calls a function that is itself not reflectable | 662 | 218 |
| contains a lambda | 361 | 212 |
| calls through a variable | 338 | 197 |
| a recursive unit without a `structural`/`metric` certificate | 190 | 174 |
| a parameter of function type | 136 | 48 |
| names a function as a value | 117 | 15 |
| `@[diverges]` / `@[trusted]` / `@[assume]` | 57 | 3 |
| `spawn` / `send` | 40 | 65 |
| non-exhaustive match (unguarded only, see below) | 4 | 1 |

The builtins that block most often: `++` (295), `int_to_string` (110), `panic` (79),
`string_concat3` (68), `bool_to_string` (36), `string_byte_at` (32), `*.` (31),
`get_actor_field` (30), `string_concat_n` (29), `+.` (28), `int_and` (28).

D18's functions come out as expected: `List.append`, `List.reverse`, `List.take` and
`List.drop` are reflectable; `List.filter` is not (a function-typed parameter and a call through
it). Of `List`'s functions, 22 are reflectable in all (among them `sum_int`, `zip`, `split_at`,
`nth_opt`).

Accuracy, and what the script does not see:
- Callee resolution is lexical and module-qualified, but does not follow `use`/`alias` imports,
  so some "unresolved" callees are really stdlib functions (an undercount).
- Effects are caught only as calls or as `spawn`/`send` nodes.
- Comparisons and `==` are counted as encodable whatever their type, so Float and user-`Ord`
  comparisons are over-counted.
- R1's "no captured variables" is not checked for local functions.
- A guarded match that can fall through (C2 of the review) is invisible to it, as it is to
  today's `non_exhaustive_match` diagnostic; the review found 2 such functions.
- The 103 + 76 zero-argument functions include constants that are already folded today.

Treat the totals as ±10%. The breakdown is exact for the script, not for the compiler. The script
is `refl/reflectable.py` in the session scratch area.

### 0.6 Probe (f): builtins with a z3 meaning today

| Group | Names | Where |
|---|---|---|
| Int and Bool operators | `+ - * negate not && \|\| == != < <= > >=` | `predicate_operators`, `refine_encode.ml:1040-1052` |
| Int division | `/ %`: by a literal as `div`/`mod` of the truncated value; otherwise only where both sides are known non-negative, with a non-zero side condition | `refine_scope.ml:111-249` (the `Ite` at `:225` encodes truncation) |
| Float operators | `+. -. *. /.` are vocabulary but are translated only over literals; comparisons go to the FloatingPoint theory | `refine_encode.ml:1043-1047` |
| `len` | `List` (`$len` over the `List` datatype) and `String` (`$strlen`), with the aliases `List.length`, `String.byte_size`, `string_byte_length`; `Array.length` aliases the stdlib measure `pvec_length` | `measure_alias`, `refine_encode.ml:956-961` |
| sets | `elts keys member union inter diff subset singleton card empty` | `set_vocabulary`, `:1358` |
| constructor testers | `is_<Ctor>` for every constructor | `known_predicate_fn`, `:1349-1351` |
| constant functions | a zero-argument `fn` whose body folds (literals, `+ - *`, `negate`, `&& \|\| not`, other constants) | `register_const_fns`, `:2265`; probe h3: `idx(256)` against `_ < two_x()` is **violated** |
| builtin return facts | only `pmap_threshold() > 0` | `builtin_ret_refinements`, `:785-791` |
| user measures | `@[measure]` functions (single ADT parameter, Int or Set result) | `build_measure_preamble`, `:2980` |

A one-argument non-measure call in a predicate is untranslatable. Probe h3,
`idx2(i : {Int | _ < inc(3)})`:

```
skip	user	h3_const_fold.march:12:12	unreflectable-predicate	precondition	idx2	_ < inc(3)
`inc` is not a measure or known predicate, so this refinement is not checked. Annotate the function `@[measure]`, or use a supported predicate. [refinement_unchecked]
```

### 0.7 Probe (g): `==` on a type whose `Eq` is hand-written

```march
type P = P(Int, Int)

impl Eq(P) do
  fn eq(a : P, b : P) : Bool do
    match (a, b) do
      (P(x, _), P(y, _)) -> x == y
    end
  end
end

fn need(p : {P | _ == P(1, 2)}) : Int do 0 end
```

| Row | Program | Today (measured) |
|---|---|---|
| g2 | the same `need`, with `derive Eq for P`; `need(P(1, 2))`, `need(P(1, 3))` | **1 proved, 1 violated**. Correct: derived Eq is structural equality |
| g3 | hand-written `Eq` above; `need(P(1, 3))` | **`refinement_violated`**: "argument `p` of `need` does not satisfy precondition `_ == P(1, 2)`" |
| g4 | interpreted: `println(if P(1, 3) == P(1, 2) do "eq" else "ne" end)` | prints **`eq`** |

So in g3 the predicate's `==` is z3 datatype equality, while the program's `==` runs the
user's `eq`. The checker is consistent with what the predicate means (structural equality), but
the user who wrote `_ == P(1, 2)` with their `Eq` in mind gets a violation for a value their `==`
accepts, and nothing explains it. §3.5 keeps the meaning, documents it and warns; phase 0 files
the missing warning.

### 0.8 Probe (h): a `Unit` return refinement today

| Row | Program | Today (measured) |
|---|---|---|
| h1 | `fn bogus(n : Int) : {Unit \| n == n + 1} do panic("never") end` and `fn spin(n : Int) : {Unit \| n == n + 1} do spin(n) end` | both skip **`unreflectable-subject`**. Nothing is "proved", and nothing is checked |

A `{Unit | P}` return is never checked today, because its subject `()` has no SMT sort. A lemma
(D3) needs exactly this to be checkable. The two bodies are the soundness controls for that.

### 0.9 Corpus counts: `@[measure]` uses

| Where | `@[measure]` functions |
|---|---|
| `stdlib/` | **2**: `Array.pvec_length` (non-recursive field read, `array.march:395`) and `SortedSet.sorted_set_elts` (a set-valued measure, `sorted_set.march:29`) |
| `test/native/` | **0** |
| `test/errors/` | 1 (`non_tail_recursion_1.march:24`, `size` over a `Tree`) |
| `specs/lang/types/` | 1 (`reject/t109_refine_induction_propagates.march:24`, the same `size`) |
| `test/test_refinecheck.ml` (inline programs) | 113 occurrences of the attribute text; the measures' result types are 79 `Int` and 8 `Set`, and **no `Bool`** |
| `test/test_refine_term.ml` | 12 occurrences |

### 0.10 The cost probe

Two measurements over the refine-oracle corpus (`test/native/*.march` and `stdlib/*.march`, 553
files), one private HOME, `.march/cas/vc` cleared once, load average 5-8.

**Today's obligations** (`--check --refine-report --refine-report-sites`, per file):

| | Obligations | Proved | Trusted | Skipped | Violated |
|---|---|---|---|---|---|
| the stdlib, checked inside **every** program | 220 | 145 | 35 | **40** (22 `unconstrained-subject`, 10 `partial-conjunct`, 5 `solver-undecided`, 3 `unreflectable-subject`) | 0 |
| `test/native` user code, all 417 programs together (29 programs have any) | 120 | 102 | 0 | **18** (11 `solver-undecided`, 4 `unconstrained-subject`, 2 `unreflectable-subject`, 1 `partial-conjunct`) | 0 |

Whole sweep: 423 s wall, 0.76 s per file on average; the slowest file 1.81 s
(`actor_call_canonical`).

**Where reflection would touch an obligation** (the probe (d) script over the AST). An obligation
site "gains unfoldings" when its arguments (a call to a function with a refined parameter) or its
body (a function with a refined return) contain a call to a reflectable function. The body test
over-approximates: any call in the body counts.

| | Call sites with an obligation | ... that gain unfoldings | Refined returns | ... that gain unfoldings |
|---|---|---|---|---|
| stdlib | 263 | 18 (7%) | 63 | ≤ 18 (≤ 29%) |
| test/native | 135 | 8 (6%) | 0 | — |

(A note on method: the first sweep also passed `--termination-report`, which turns on every
termination obligation; its counts, 274 + 199 `not-decreasing` skips, are not refinement
obligations and are not used here.)

### 0.11 Facts the design rests on, each verified on `7df0dc808`

- **F1. A function's body never reaches the solver.** Only contracts do (a1 against a2-a4;
  e1). The predicate translator treats any call that is not a measure, an operator, a
  constructor tester or a constant function as untranslatable (`known_predicate_fn`,
  `refine_encode.ml:1349`), and the warning names `@[measure]` as the remedy.
- **F2. Measures are one-parameter by rule.** `measure_shape_error` rejects zero and two or more
  parameters (`refine_encode.ml:2372-2401`; b1, b2).
- **F3. Measures are quantified axioms with a constructor pattern.** For each arm,

  ```
  (assert (forall (vars) (! (= (m (C vars)) body) :pattern ((m (C vars))))))
  ```

  (`arm_axiom`, `refine_encode.ml:2719-2830`). A non-recursive measure becomes a quantifier-free
  `define-fun` instead (`measure_definition`, `:2931-2978`), because model-based quantifier
  instantiation could not close a satisfiable query over the `forall` form (the 2026-09-13
  `Array` sweep). The `:pattern` fires only when z3's E-graph holds `m` applied to a term equal
  to a constructor application. That is z3's own version of "unfold only when the constructor
  is decided" (D13), without a fuel bound.
- **F4. The measure body translator is a narrow fragment.** `smt_of_axiom_body`
  (`refine_encode.ml:2455-2484`) accepts Int literals, bound pattern variables, a measure applied
  to a bound variable, `+`, `-`, a literal times a term, and the set operators. It has no `if`,
  no comparison, no Bool literal, no nested `match`. That is why b2's `if` could never have been
  a measure.
- **F5. Bool measures do not work at all.** The result sort is hard-coded to `Int` for every
  non-set measure: `"(define-fun %s ((x %s)) Int %s)"` (`:2978`) and `| None -> "Int"` in the
  instance declarations (`:2878-2883`). Every use skips `float-sort-gate` or `sort-conflict`
  (c2, c2b, c2c). No test has a Bool measure (§0.9). The reference (`:1194`) says "an `Int` (or
  `Bool`)". Filed in phase 0.
- **F6. A list-returning measure is accepted and ignored** (c1). The shape gate checks the
  parameter count, not the result sort, and `build_measure_preamble` drops the measure from
  `axiom_measures` when an arm does not translate. No diagnostic says so.
- **F7. The measure gate is syntactic and looks only at the measure's own body.**
  `measure_gate_errors` (`refine_encode.ml:4296-4368`) rejects `spawn`, `send`, `dbg`, `assert`,
  direct calls to `panic`/`todo`/`unreachable`/`exit`, possibly-zero `/` and `%`, non-structural
  self-calls and a non-exhaustive match on the parameter. It does not follow callees: c3b's
  `noisy`/`boom`/`spin` and h2's `show` and interpolation pass. TERM phase 1 added the SCC
  certificate (`refine_check.ml`, beside the call at `:8671`), but a callee in a different SCC
  is still not examined. Harmless today only because such an arm fails to translate (F4), so
  the measure falls back to an uninterpreted symbol.
- **F8. Predicate `==` is z3 equality, whatever the type's `Eq`** (g3). A scalar `Float` `==` is
  the exception: it becomes IEEE `fp.eq` (`refine_encode.ml:404`). Nothing warns a user whose
  type has a hand-written `Eq`.
- **F9. The VC cache key is the SMT text** (`vc_cache.ml:6-7`): BLAKE3 of the preamble and the
  assertion block. `unknown` is never cached (`refine.ml:153-170`). Entries live under
  `<project>/.march/cas/vc`. So the cache is correct for any encoding that puts what a proof
  depends on into the query text. Today a callee's body is not in it (e1).
- **F10. The early source CAS skips the whole check on a warm cache**, keyed on every input
  byte (`bin/main.ml:3005-3035`); `--refine-report`, `--refine-report-sites` and
  `--termination-report` bypass it. Any edit anywhere re-runs the check. The LSP re-checks one
  file against its dependencies' declarations (`lsp/lib/analysis.ml:2546-2552`).
- **F11. `--dump-impl-hashes` hashes post-TIR definitions** (`lib/cas/hash.ml:1-18`): a
  `sig_hash` of the signature and an `impl_hash` of signature plus body, used by the CAS and by
  hot-code-reload admission (`lib/tir/hcr_abi.ml`). Nothing in it is about the logic. A
  body-only change keeps `sig_hash`, which HCR reads as "interface unchanged".
- **F12. Termination certificates exist and gate the IH** (TERM phases 1-3):
  - certificates are `structural`, `metric`, `trusted`, `diverges` or `unproved:<reason>`
    (`Refine_term.finish`);
  - the IH at a call needs an eligible certificate, the call reached by the scratch walk, and
    its preconditions proved (`ih_prepare`, rule (a));
  - interface methods, and builtins whose scheme has an interface constraint (`==`, `<`,
    `show`), get **dispatch edges** to every reachable `impl`;
  - an unresolved callee fails closed (`unproved:unresolved`).
  This is the call graph and the certificate D6 needs.
- **F13. `@[lemma]` does not exist, and unknown attributes warn.** `known_fn_attributes`
  (`refine_check.ml:7711-7713`) is `assume, decreases, diverges, measure, no_alloc,
  no_warn_recursion, trusted, trusted_linear, vectorize`.
- **F14. `opaque` is a keyword** (`lexer.mll:116`, for `opaque type`). `@[opaque]` therefore
  never reaches the `LOWER_IDENT` attribute rules (`parser.mly:526-539`), exactly like
  `transient`, which has its own productions (`:540-546`). The same holds for tree-sitter,
  whose attribute rule is `@[identifier(expr, …)]` (`grammar.js:111-114`) under `word:
  $.identifier`.
- **F15. An attribute payload is one name, except `decreases`** (`parser.mly:529-539`). A
  labelled payload such as `fuel: 3` is not an expression, so it parses nowhere today.
- **F16. The stdlib's D18 functions** (`stdlib/list.march`):
  - `append` (`:323`) and `drop` (`:871`) are direct structural recursions;
  - `reverse` (`:303`) calls a local accumulator `go(lst, acc)`;
  - `take` (`:847`) calls a local `go(lst, k, acc)`, which ends with `reverse(acc)`;
  - `filter` (`:422`) takes `pred : a -> Bool[p]`, a function value with an abstract
    refinement.

  The termination report certifies all of them `structural`: `append`, `filter`, `drop`,
  `reverse/go`, `take/go`.
- **F17. March is call-by-value** (TERM F11). Partial correctness already makes a proved
  contract safe to assume for proofs. What it does not give is a sound **logic function**: a
  definition that may diverge or abort is an inconsistent or meaningless equation (TERM §4.1).
- **F18. Compiled `Int` is 63-bit and wraps; the checker's Int is mathematical.** The
  reference says the checker's arithmetic is over unbounded integers; the runtime normalises
  to 63 bits. Any fact about `n + 1 > n` is true in the logic and false at the maximum `Int`.

- **F19. A metric certificate can hold only on a refined domain** (probe r1). The certificate is
  computed under the parameter refinements, so it says nothing about arguments outside them.
- **F20. A guarded match draws no `non_exhaustive_match` warning**, even when it can fall through
  (probe r2). `typecheck_exhaustive.ml:719-739` records it in `nonexhaustive_match_spans`
  instead, and the program panics at run time.
- **F21. Predicate vocabulary wins over a user function of the same name** (probe r3): with a
  user `fn len(xs) = 7`, the predicate `len(_) == 1` still means the builtin `$len`.
- **F22. There are no refutable `let` patterns.** `let Cons(h, _) = xs` is a `syntax_error`
  (probe r4), so R5 has only `match` and multi-head clauses to cover.

### 0.12 Probes from the review, re-run on `7df0dc808`

The review supplied these programs; each was re-run here with the same script and a fresh HOME.

| Row | Program | Measured |
|---|---|---|
| r1 | `fn p(n : {Int \| _ >= 0}) : Bool do if n >= 0 do true else not p(n) end end`, and the same with `@[decreases(n)]` (`q`), and `cnt(n : {Int \| _ >= 0})` counting down | `--termination-report`: `p … cert=metric`, `q … cert=metric`, `cnt … cert=metric` (`certificate: 0 structural, 3 metric, 0 trusted, 0 unproved`) |
| r2 | `fn guarded(xs : List(Int)) : Int do match xs do Cons(h, _) when h > 0 -> h  Nil -> 0 end end`; `main` prints `guarded(Cons(0 - 1, Nil))` | `--check`: no diagnostic, exit 0. Interpreted: `panic: match failure — Non-exhaustive pattern match: no branch matched the value [-1].` |
| r3 | `fn len(xs : List(Int)) : Int do 7 end`; `need(xs : {List(Int) \| len(_) == 1})` on `Cons(1, Nil)`; `main` prints `len(Cons(1, Nil))` | `--check`: `1 proved`. Interpreted: prints `7` |
| r4 | `let Cons(h, _) = xs` in a function body | `-- ERROR … I got stuck here: [syntax_error]`, pointing at `Cons` |


---

## 1. What reflection adds, in one example

```march
fn is_small(n : Int) : Bool do n < 10 end

fn need_small(n : {Int | _ < 10}) : Int do n end

fn f(n : Int) : Int do
  if is_small(n) do need_small(n) else 0 end
end
```

Today `need_small(n)` is skipped: the path fact `is_small(n)` is an unknown symbol. With
reflection, the checker adds one unfolding:

```
is_small$r(n) = (n < 10)
```

The path fact `is_small$r(n)` then gives `n < 10`, and the call is proved. Nothing was
annotated.

A lemma does the same for a recursive fact:

```march
@[lemma]
fn len_cat(xs : List(a), ys : List(a)) : {Unit | len(cat(xs, ys)) == len(xs) + len(ys)} do
  match xs do
    Nil -> ()
    Cons(_, t) -> len_cat(t, ys)
  end
end
```

- In the `Nil` arm, the unfolding `is_Nil(xs) => cat$r(xs, ys) = ys` closes the goal.
- In the `Cons` arm, the unfolding gives `cat$r(xs, ys) = Cons(h, cat$r(t, ys))`. The call
  `len_cat(t, ys)` is the induction hypothesis: `len(cat$r(t, ys)) == len(t) + len(ys)`.
  `len` of a `Cons` is one more than `len` of its tail. The goal follows.
- `len_cat` is structurally recursive, so TERM certifies it, so the IH is allowed (D3).

Any caller can now write `len_cat(a, b)` before a call that needs the length of `cat(a, b)`.
The call is erased before code generation (D5).

---

## 2. Which functions are reflected (D1, D6, D10, D11)

### 2.1 The rule

Reflection is automatic (D1). A function `f` is **reflected** when all of these hold:

| # | Condition | Source of truth |
|---|---|---|
| R1 | `f` is a top-level `fn` or a local `fn` with no captured variables. Not an `impl` method, actor handler, `extern`, `main`, or lemma | the TERM unit table (`Refine_term`, `u_top`) |
| R2 | `f` terminates: its SCC certificate is `structural` or `metric`. Not `trusted`, not `diverges`, not `unproved` (D6). A non-recursive unit passes R2 by itself; its callees answer for themselves under R6. A `metric` certificate holds only on the refined domain, so every unfolding is guarded by the parameter refinements (§3.6, C1) | `Refine_term.finish` |
| R3 | `f` has no effect: no `spawn`, `send`, `receive`, `dbg`, actor field access, and no effectful callee (R6 makes every builtin outside the table of §2.3 a blocker) | the body walk |
| R4 | `f` cannot fail: no `panic`/`todo`/`unreachable`/`exit` (R6), no runtime `assert`, and every `/` or `%` has its `Division` obligation **proved** (D6) | the obligation ledger, read per span (`Obligation.by_span`) |
| R5 | every `match` in `f` covers all cases, including multi-head clauses after desugaring and **guarded** matches whose guardless arms do not cover (D6) | the typechecker's `nonexhaustive_match_spans` (`typecheck_exhaustive.ml:719-739`), which records guarded matches too; **not** the `non_exhaustive_match` warning, which a match with any `when` guard never emits (C2) |
| R6 | every callee is reflected, a lemma (translated as `()`, §3.4, I2), a constructor, or a builtin with a z3 meaning (§2.3) (D11). A callee is matched by its **resolved identity** (the typechecker's binding, `Builtin_name` for builtins), never by its spelling (I3). Interface dispatch counts as a call to every reachable `impl` (TERM phase 3's dispatch edges), so `show`, interpolation, `compare` and a user `<` block. `==` is the D7 exception, and only when every reachable `eq` is itself total and pure (§3.5) | the TERM call graph, its dispatch edges |
| R7 | `f` is first-order: no parameter of function type, no lambda, no call through a variable, no function named as a value (D10) | the TERM graph's lambda and reference edges, plus a parameter-type check |
| R8 | every parameter sort and the result sort are encodable (§3.2), every parameter refinement translates (it becomes the unfolding guard), and the result is not `Unit` | §3.2 |
| R9 | `f` is not marked `@[opaque]`, `@[assume]` or `@[trusted]` (§2.5), recursive or not | attributes |
| R11 | `f`'s name is not predicate vocabulary (`len`, `elts`, `keys`, the set operators, `is_<Ctor>`). In a predicate such a name always means the builtin, so a user `len` cannot be reflected under it (I3) | the vocabulary tables (`refine_encode.ml:1040-1052`, `:1358`) |

R1-R9 and R11 form a greatest fixpoint over the call graph: start with every unit that passes the local
tests, and drop any unit with a dropped callee, until nothing changes. A mutual SCC is
reflected as a whole or not at all.

Reflection never changes a verdict by itself. It only adds facts. Where those facts change a
proof, §6 governs what may move.

### 2.2 Why each condition

- **R2 (termination).** An unfolding asserts `f$r(a) = body[a]`. For a diverging `f`, that
  equation can be inconsistent: `spin(n) = spin(n) + 1` gives `0 = 1`. A metric certificate is
  as good as a structural one: both prove that `f` is a total function on its domain.
- **R3, R4, R5 (purity and totality).** A predicate's call must denote the value the program
  computes. An effect has no value in the logic. A `panic` path has no value at all, so the
  equation would assert something about a value that never exists. A non-exhaustive match
  leaves an arm undefined. Strictly, the guarded equations of a partial function are still
  consistent (the missing case is just unconstrained), but D6 rules partial functions out, and
  that keeps the meaning of a predicate simple: a reflected call always has a value.
- **R6 (callees).** A reflected body is translated term by term. An untranslatable callee would
  have to become an uninterpreted symbol, and an uninterpreted symbol inside a definition is
  how F7's gaps would come back.
- **R7 (function values).** A call through a value has no fixed definition to unfold. D10
  defers it to phase 5 (§10).

### 2.3 Builtins with a z3 meaning (the R6 table)

Phase 1 uses exactly today's vocabulary (§0.6), with these rulings:

| Builtin | In the table? |
|---|---|
| `+ - * negate`, comparisons on `Int`, `&& \|\| not`, Bool and Int literals | yes |
| `/ %` | yes, when the `Division` obligation at that span is proved (R4). Encoded with today's truncation `Ite` (`refine_scope.ml:225`) |
| `==`, `!=` | yes, per §3.5: SMT `=` for fully derived, Float-free types; otherwise the opaque `eq$T`, and only if every reachable `eq` passes R2-R7 |
| `List.length`, `len` on `List` | yes (`$len`) |
| `string_byte_length`, `String.byte_size` | yes (`$strlen`, D9) |
| `Float` arithmetic and comparison (`+. -. *. /.`, `<.` and friends, `==` at `Float`) | yes, as **opaque** symbols (D9): one uninterpreted, total function per operator. Never the FloatingPoint theory inside a reflected body, so NaN and signed zero can never be reasoned about wrongly |
| `String` literals | yes: each distinct literal is a fresh `$Str` constant, all literals in a query are asserted pairwise `distinct`, and `$strlen` of each is fixed to its byte length |
| any other `String` or `Float` builtin (`string_slice`, `float_to_int`, `int_to_float`, …) | **no** (D9): the function is not reflected |
| set vocabulary | only inside a function whose result is a `Set` (a set-valued measure today) |
| constructors, tuples, record construction, field access, record update | yes: datatype constructors and selectors (§3.2) |
| `is_<Ctor>` | yes |
| constant functions | yes (they are folded, as today) |
| everything else (`println`, `int_to_string`, `++`, `string_concat*`, bit operations, …) | **no** |

Bit operations (`int_and`, `int_shl`, …) could map to z3 bit-vectors, but the checker's `Int`
is not a bit-vector, so they stay out until the overflow phase (§10, phase 6) decides the Int model.

### 2.4 Diagnostics: making the automatic rule visible

Because reflection is automatic, a function silently stops being reflected when its body gains
a blocker. The design makes that visible in three places.

1. **The predicate warning names the blocker.** Today's `refinement_unchecked` text
   ("`rev` is not a measure or known predicate") becomes, for a function that exists but is not
   reflected:

   ```
   `rev` is not reflected, so this refinement is not checked: it calls `println`, which has an effect (line 14). [refinement_unchecked]
   note: a function is usable in a predicate when it terminates, has no effects, cannot fail, and calls only such functions.
   ```

   The reason is the **first** blocker in R-order, with the span of the offending expression.
   Through a callee, the note follows the chain: "`rev` calls `helper`, which is not reflected:
   it calls `println`".
2. **`--reflect-report`** (new flag, phase 0) prints one row per user function:

   ```
   reflect	list.march:303:5	reverse	reflected	unfold
   reflect	app.march:12:5	render	no	R3:calls println (app.march:14:5)
   ```

   It bypasses the early CAS exit, like `--termination-report`.
3. **The proof note.** A stage-2 proof (§4.4) that used a definition says so in
   `--refine-report-sites=all` and in the LSP hover of the obligation:

   ```
   proved	user	app.march:30:12	precondition	need_small	_ < 10	uses: is_small
   ```

   The `uses:` list is the set of definitions in z3's unsat core (§4.4). It is what makes "a
   change inside `is_small` can change this proof" visible.

### 2.5 Opting out: `@[opaque]`

`@[opaque]` on a function stops its reflection. Callers see only its contract, exactly as today.
Reasons to use it:
- **Interface stability.** A library function's body becomes part of what callers' proofs depend
  on (§7). `@[opaque]` keeps a body free to change.
- **Cost.** A large function whose unfolding slows z3 (§8).

Rules:
- `@[opaque]` with `@[measure]` (or `@[reflect(…)]`) is an error, `reflect_conflict`.
- `@[opaque]` on a function that would not be reflected anyway is the existing
  `attribute_no_effect` warning.
- Parsing: `opaque` is a keyword (F14), so the parser gains one production,
  `AT LBRACKET OPAQUE RBRACKET`, beside the `TRANSIENT` ones, and `grammar.js`'s `attribute`
  rule gains `'opaque'` as an alternative to `$.identifier`. This is a grammar change, so per
  `CLAUDE.md` the same PR extends `tree-sitter-march/grammar.js`.
- `@[assume]` and `@[trusted]` also imply opaque. A function whose contract the user asked the
  checker to trust has a body the checker has not verified to match it, and unfolding the body
  next to the trusted contract could contradict it.

### 2.6 The standard library

The stdlib is reflected automatically, under exactly the same rules as user code (D1, and the
D1 clarification of 2026-10-29 in §11.1). So are libraries reached through `MARCH_LIB_PATH`.
There is no list of stdlib functions to opt in.

- **From phase 1**, every stdlib function that passes R1-R9 and R11 is reflected. Probe (d)
  counts 817 of them. `--reflect-report`, run on a stdlib file, lists them with their status.
- **The opt-out is `@[opaque]`**, function by function (§2.5). Phase 1 marks a stdlib function
  `@[opaque]` only with a stated reason (its body is expected to change for performance, or its
  unfolding measurably slows checking), and the phase-1 progress note lists every function so
  marked, with the reason. None is known today.
- **The two stdlib `@[measure]`s** stay measures (§5): the attribute asserts reflection and keeps
  their axiom-tier encoding.
- **A stdlib function that is not reflected** reports its first blocker like any other:

  ```
  `List.map` is not reflected, so this refinement is not checked: it calls `f`, a function value (R7). [refinement_unchecked]
  ```

- **Cost.** Stdlib obligations whose frontier holds a reflected stdlib call run stage 2 from
  phase 1, in every program. §8 bounds this, and §6.3's budget applies from phase 1.
- **Interface.** A stdlib body edit can now change user proofs (§7). The D17 hashes, the `uses:`
  note and the monotone gate over the corpus make every such change visible in the PR that makes
  it.

#### Considered and rejected: a stdlib allowlist

An earlier revision proposed reflecting stdlib functions only from a hand-kept list (empty at
first, then D18's five). Its main argument was interface stability: a stdlib body would become a
promise to user proofs only when someone chose to make it one, and users cannot pin the stdlib's
version apart from the compiler's. Its cost argument was weaker, since the frontier and the
two-stage discharge already bound the cost. The user decided on 2026-10-29 that the stdlib is
included in D1: it is reflected automatically, and `@[opaque]` is the per-function answer to the
interface concern.

---

## 3. The encoding

### 3.1 Logic symbols

Each reflected function `f` gets one z3 symbol per sort instance:

```
(declare-fun |r:std:List.append@Int| (List@Int List@Int) List@Int)
```

The symbol must be **injective**: two different definitions must never share a symbol, or one
symbol gets two definitions and the query proves anything (I4). The mangling is:

```
|r:<origin>:<module path>.<name>[/<local>#<line>:<col>]@<instance>|
```

- `r:` marks a reflected symbol. Measure symbols keep their bare names (F3), so the two can
  never collide.
- `<origin>` is `std` for `stdlib/`, `lib:<package>` for a `MARCH_LIB_PATH` library, and `user`
  for the entry program's own modules. A user `mod List` therefore never meets `std:List`.
- `<module path>` is the full nested path (`Outer.Inner`), as TERM's lexical resolution prints it.
- A local function adds `/<local>` **and** its declaration position. TERM already names locals
  `f/go`; the position keeps apart two `go`s declared one after the other in the same function
  (the second shadows the first).
- `@<instance>` is the sort instance (§3.3), spelled as `measure_instance_name` does
  (`refine_encode.ml:3296`).
- The whole name is an SMT quoted symbol (`|…|`), so `/`, `:`, `#`, `.` and `@` are legal. A `|`
  or `\` cannot occur in a March identifier or path.
- The name is a fixed string, with no counter, so the VC cache and the determinism oracle see the
  same text in every run.
- A `@[measure]` in the axiom tier keeps its existing symbol (§5).

The rest of this document writes `f$r` (`cat$r`, `rev$r`) as shorthand for the mangled name.

Phase 1 adds a check, at symbol creation, that no symbol is declared twice with different
definitions; a duplicate is an internal error.

### 3.2 Sorts

| March type | z3 sort |
|---|---|
| `Int` | `Int` (mathematical, D8) |
| `Bool` | `Bool`. This also fixes F5 for reflected functions |
| an ADT, including `List`, `Option`, `Result` and tuples | the datatype the checker already declares (`declare-datatypes`, `refine_encode.ml` `datatype_decls`, `:2669`), at its instance |
| a record | the record sort `record_vc_preamble` declares (`:4033`) |
| `String` | `$Str` (opaque, D9), with `$strlen` |
| `Float` | the checker's Float sort, but every operation on it, `==` included, is an uninterpreted symbol (D9) |
| a type variable `a` | `Elem`, the opaque element sort (§3.3) |
| `Set(a)` | `(Set Elem)` or its instance, as set-valued measures do |
| a function type | not encodable: the function is not reflected (R7, R8) |
| `Unit` | not encodable as a result (R8). A `Unit` parameter is dropped |

A function returning a list therefore has a datatype result:

```
(declare-fun rev$r@Int (List@Int) List@Int)
```

A multi-parameter function is an ordinary multi-argument z3 function. Nothing about measures'
one-argument rule (F2) applies to reflected functions.

### 3.3 Polymorphism and the `Elem` sort

A polymorphic function such as

```march
fn cat(xs : List(a), ys : List(a)) : List(a) do … end
```

is declared at two kinds of instance:
- **At `Elem`**, when the obligation itself is generic (inside another polymorphic function, or a
  lemma over `List(a)`). Every type variable maps to the single uninterpreted sort `Elem`.
- **At a concrete instance** (`List@Int`), when the call's types are concrete. The body is
  translated at that instance. `instance_closure` (`refine_encode.ml:2558`) already closes the
  datatype instances an axiom mentions, to depth 3 (`max_instance_depth`, `:2525`).

This is sound because `Elem` has no axioms:
- a proof at `Elem` holds for every interpretation of `Elem`, so for every instance;
- mapping two different type variables to the same `Elem` is also sound, because a well-typed
  predicate never compares an `a` with a `b`, so any model of the merged query splits into a
  model of the separate one (take `Elem` to be the disjoint union).

The cost of a single `Elem` is precision, never soundness: two calls at different instances
cannot share an unfolding. A **body's** `==` on `Elem` is opaque (§3.5), because the instance's
`Eq` is unknown; a **predicate's** `==` on `Elem` is logical equality.

### 3.4 Translating a body

`Refine_reflect.term_of_body` turns a reflected body into a term over the parameters. It is a
new translator, not `smt_of_axiom_body` (F4):

| March | z3 |
|---|---|
| `match x do C1(a) -> e1 … end` | one **implication per arm**: arm `i`'s condition is "`x` matches arm `i`'s pattern, and matches no earlier arm" (constructor testers, with selectors `a := (C1_0 x)`). There is **never** a final unconditional `else`: unlike `measure_definition` (`:2959-2968`), which makes the last arm the default, an input that matches no arm gets no equation at all |
| a match arm guard `when g` | arm `i`'s condition gains `g`; a later arm's condition gains "not (earlier pattern and earlier guard)". Coverage is R5's job, which for a guarded match reads `nonexhaustive_match_spans` (C2) |
| `if c do e1 else e2 end` | `ite` |
| `let x = e1` then `e2` | substitution (an SMT `let` when `e1` is used more than once) |
| a call of a reflected `g` | `(g$r args)`: **not** unfolded at translation time |
| a call of a lemma (a proof step inside a reflected function, D5) | `()`: the call is erased before the body is translated, exactly as §4.5 erases it before code generation (I2). Its arguments must still be reflectable terms |
| constructor, tuple, record, field access, record update | datatype constructor and selector terms |
| arithmetic, comparison, Bool operators, `len` | today's `smt_of_r_marked` (`refine_scope.ml:260`) translation, so the two translators agree, but dispatched on the callee's **resolved identity**. A user function spelled `len` is a call of that user function (and blocks under R11), never `$len` |
| `==` | §3.5 |

Totality makes the result a total term: the arms of an exhaustive match cover every
constructor (R5), and every callee is total (R6).

### 3.5 `==`: logical equality in predicates, program equality in bodies (D7)

Two different equalities meet here, and the design keeps them apart.

**In a predicate, `==` is logical equality.** A predicate is a specification. `a == b` in a
predicate means "the same value": SMT `=` at the value's sort, for every type, including a type
variable (`Elem`), an ADT with a hand-written `Eq`, and a `Float` or `String` inside a datatype.
The one exception is today's: a predicate comparing two **scalar** `Float` terms keeps the
IEEE `fp.eq` the Float refinements use (`refine_encode.ml:404`).

**In a reflected body, `==` is the program's equality**, the one the program runs. D7 decides its
translation at type `T`:
- **SMT `=`** when `T` is `Int`, `Bool`, `String`, or an ADT or record whose `Eq` is **derived all
  the way down** (derived for `T` and for every type reachable through its fields) and that
  contains no `Float`;
- otherwise **an opaque symbol** `eq$T(a, b)`: Bool-valued, uninterpreted, one per sort. That is
  the case when any type in `T`'s structure has a hand-written `impl Eq`, when `T` is or contains
  `Float` (D9: IEEE `==` is not reflexive on NaN), or when `T` is a type variable.

`!=` is `not` of the same (the built-in `Eq` interface has only `eq`,
`typecheck_builtins.ml:502-504`, so there is no separate `ne` to disagree with).

**The opaque case is allowed only for a total `eq`** (C4). The D7 exception to R6 applies only
when every `impl Eq` reachable from `T` (by TERM's dispatch edges) itself passes R2-R7: it
terminates, has no effect, cannot fail, and is first-order. Then `eq$T` is an unknown but
**total, deterministic** function, which is what an uninterpreted symbol claims. If any
reachable `eq` prints, panics, loops or calls a function value, `==` at `T` is a blocker like
any other non-reflected callee, and the function is not reflected.

**Why this reading (C3).** The two readings the review weighed:
- *Opaque `==` on `List(a)` in predicates.* Then no generic equational lemma can be stated:
  `cat_nil`, `cat_assoc`, `rev_cat`, `rev_rev` (§4.6) and phase 3's `append_assoc`,
  `reverse_reverse`, `take_drop` would all be unprovable.
- *z3 `=` everywhere, predicates and bodies alike.* Then a body's `==` on `List(Float)` would be
  reflexive in the logic and not at run time (`[NaN] == [NaN]` is false), so a reflected
  `same(a, b) = a == b` could be "proved" true where the program says false.

Separating the two keeps every lemma provable (they are predicate statements about values) and
keeps every reflected body faithful (it uses the program's `==`). LH draws the same line: a
specification's `==` is the logic's equality.

**Lemma facts are instantiated, never re-translated.** A polymorphic lemma is proved once, at
`Elem`, with logical `=`. At a call, its post is the **proved SMT term** with `Elem` replaced by
the call's sorts. It is not rebuilt from the source predicate at the call site, so a scalar
`Float` instance cannot silently turn a proved `=` into `fp.eq`.

**What this means for g3.** Today's predicate `==` is already logical equality (F8); g3 is that
meaning meeting a user's `Eq`. The design keeps the meaning, states it in the reference, and adds
a warning, `predicate_eq_structural`, at a predicate that uses `==` at a type with a hand-written
`Eq`:

```
`==` in a refinement means structural equality; `P` has a hand-written `Eq`, which this predicate does not use. [predicate_eq_structural]
```

So g3 stays a violation, with the warning explaining it. No predicate verdict changes.

### 3.6 Unfolding once per call site (D12)

For a call term `f$r(t1, …, tn)` in a query, one unfolding adds the **guarded equations** of
`f`'s body at those arguments. For `cat` at `(xs, ys)`:

```
(assert (=> ((_ is Nil) xs)  (= (cat$r xs ys) ys)))
(assert (=> ((_ is Cons) xs) (= (cat$r xs ys) (Cons (Cons_0 xs) (cat$r (Cons_1 xs) ys)))))
```

- **Each equation is guarded by the callee's domain** (C1). If `f`'s parameters carry
  refinements, their conjunction `pre_f(t1, …, tn)` is added to every arm's guard:

  ```
  (assert (=> (and pre_f ((_ is Cons) xs)) (= (f$r xs) …)))
  ```

  A metric certificate proves termination only for arguments that satisfy the refinements, so
  outside them the definition says nothing. A parameter refinement that does not translate makes
  `f` unreflectable (R8).
- Each assertion is a ground instance of the definition. None is quantified, and none uses
  `define-fun-rec` (D12).
- The new term `cat$r (Cons_1 xs) ys` is **not** unfolded again in phases 1-3.
- **Why this is sound:** `f` is total on its domain (R2-R5), so
  `∀x. pre_f(x) ⇒ (f$r(x) = body(x))` is true of the program, and every guarded unfolding is an
  instance of that true formula. For an input that matches no arm (impossible under R5) or lies
  outside `pre_f`, nothing is asserted. Adding true facts can never
  produce a false proof, however many are added.

### 3.7 Which calls are unfolded: the frontier

Only calls that appear in the obligation are unfolded:
- the goal (the predicate with its subject substituted);
- the subject, when it is itself a call (`need(f(x))`);
- the facts the query assumes: path conditions, parameter refinements in scope, `let` facts,
  callee postconditions, lemma facts, `assert` facts.

A call nested inside another call's arguments is in the frontier too (`len(cat(rev(t), ys))` has
`cat$r(rev$r(t), ys)` and `rev$r(t)`). Calls produced by unfolding are not (phases 1-3).

Two connecting facts are new:
- **A call result.** `let r = f(x)` today makes `r` a fresh constant carrying `f`'s proved
  postcondition. With `f` reflected, the fact `r = f$r(x)` is added too, so `r` meets `f`'s
  unfolding.
- **A subject.** `need(f(x))` today skips `unreflectable-subject` when `f` has no contract. With
  `f` reflected, the subject is `f$r(x)`.

Both connecting facts, and every unfolding, belong to stage 2 of §4.4 only. Stage 1 never sees
them.

The predicate translator gains one arm: an application of a reflected function to translatable
arguments is `App (f$r, args)`, registered in the frontier. This replaces F1's "untranslatable".

### 3.8 Repeated unfolding and fuel (D13, D14), specified now, built later

Each frontier term carries a depth. Terms from the obligation have depth 0. Unfolding a term at
depth `d` produces call terms at depth `d + 1`.

- A depth-0 term is always unfolded (D12).
- A term at depth `d >= 1` is unfolded only when **(i)** `d < fuel`, and **(ii)** its guard is
  **decided** by the facts in scope (D13): its scrutinee is syntactically a constructor term
  after substitution (`cat$r(Cons(1, Nil), ys)`), or a path fact or earlier unfolding equates it
  with one, or its `if` condition is ground-evaluable (`Refine.ground_eval`) or is literally a
  path fact or its negation. Only that arm's equation is added.
- "Decided" is checked syntactically and by congruence over the facts, never by an extra z3
  query. That keeps unfolding linear in the frontier.

**The default fuel is 2.** Reasons:
- Fuel 1 is single unfolding, which phases 1-3 already give.
- Fuel 2 adds exactly one decided step. That closes the common shape where a lemma's arm
  unfolds `f` once and the next call is on a constructor the arm just built (the `Cons` arm of
  `len_cat` written without the helper call; `rev([h])` in §4.6).
- A body with `b` recursive calls gives at most `1 + b` unfoldings per frontier term at fuel 2,
  and `1 + b + b²` at fuel 3. Reversal-shaped bodies have `b = 2` (`cat(rev(t), …)`), so fuel 3
  more than doubles the worst case for one extra step that a one-line `assert` can supply.
- Every unfolding past depth 0 already needs a decided guard, so a proof that needs a third
  step is exactly the place where an explicit `assert` or lemma call documents the reasoning.

**The per-function override is `@[reflect(fuel: N)]`**, `1 <= N <= 8`.
- D1 makes reflection automatic, so `@[reflect]` never turns reflection **on**. It is an
  **assertion**: "this function must be reflected". On a function that fails §2.1, any
  `@[reflect…]` is an error (`invalid_reflect`) naming the blocker, like `@[measure]` today.
- `@[reflect(fuel: N)]` sets the fuel for chains through this function's terms. A bare
  `@[reflect]` asserts reflection with the default fuel.
- Fuel is read **per term**, from the function the term applies: a term `g$r(…)` at depth `d`
  may be unfolded only while `d < fuel(g)`, where `fuel(g)` is `g`'s override if it has one, else
  the default. So an override can **lower** fuel as well as raise it: `@[reflect(fuel: 1)]` makes
  `g` single-unfolding everywhere. `fuel: 0` is not allowed; `@[opaque]` is how a function is
  kept out of the logic.
- `fuel: N` is a labelled payload, which no grammar accepts today (F15). Phase 4 adds a
  production `LOWER_IDENT COLON INT` inside a bracketed attribute payload, only for `reflect`,
  and the matching `grammar.js` alternative. An `INT` cannot start a type, so the menhir
  conflict count is asserted unchanged.

### 3.9 Running out (D15)

- **Fuel.** The reason **`reflect-fuel`** is given, operationally, when stage 2 did not prove
  the query **and** the final frontier holds at least one reflected call term that was **not**
  unfolded: in phases 1-3, any term at depth 1; from phase 4, a term over its function's fuel or
  with an undecided guard. Otherwise the stage-1 reason stands. The message: "the proof may need more unfolding of `f`; add a lemma call or `assert`, or
  raise `@[reflect(fuel: N)]`".
- **Budget.** A hard cap of **32 unfoldings per query** (§8). Past it, the remaining frontier is
  dropped and an unproved query skips **`reflect-budget`** (this takes precedence over
  `reflect-fuel`).
- **Time.** A z3 timeout is today's `solver-undecided`.
- Under `cap verified`, each of these is an error, through the existing escalation of every
  skip. Nothing new is needed there.

---

## 4. Lemmas (D3, D4, D5)

### 4.1 Surface

```march
@[lemma]
fn cat_nil(xs : List(a)) : {Unit | cat(xs, Nil) == xs} do
  match xs do
    Nil -> ()
    Cons(_, t) -> cat_nil(t)
  end
end
```

- A lemma is an ordinary `fn` marked `@[lemma]`. Its return type is a refined `Unit`,
  `{Unit | P}`. `P` may mention the parameters and reflected functions. `_` (the unit value)
  may not appear in `P`.
- Its parameters may carry refinements. They are the lemma's hypotheses: the body assumes them,
  and every call must prove them.
- There is no new proof syntax (D4). A proof is a body made of lemma calls, `assert`s, `match`
  and `if` to split cases, and `let` to name terms, ending in `()`.

### 4.2 What a lemma must be

`@[lemma]` is a compile error, **`invalid_lemma`**, unless:

| # | Rule | Why |
|---|---|---|
| L1 | the result type is `{Unit \| P}` | the post is the theorem |
| L2 | the body passes R3, R4, R5 and R7 (no effects, no failure path, exhaustive matches, first-order), except that `assert` is allowed: in a lemma it is a static obligation, never a runtime check (§4.3, I5) | a lemma never runs, so a `panic` arm would "prove" anything on that path (h1's `bogus` is the control) |
| L3 | every callee is a reflected function, another lemma, a constructor, or an R6 builtin | as R6 |
| L4 | if the lemma is recursive, its SCC is certified `structural` or `metric` (not `trusted`, not `diverges`) | D3: the recursive call is used as the IH |
| L5 | it is not used as a value, not `@[opaque]`/`@[reflect]`/`@[measure]`/`@[diverges]`/`@[trusted]`/`@[assume]` | a lemma has no runtime existence |

### 4.3 Checking a lemma

- A lemma's post goes through `gate_unverified_posts` like any other return. It is admitted only
  once proved, so an unproved lemma gives its callers nothing.
- A `{Unit | P}` post is checked as a **closed** goal: `P` under the body's path and scope facts.
  This is new (h1 shows it is skipped today) and applies to lemmas only. An ordinary function
  with a `{Unit | P}` return keeps today's behaviour.
- **The IH.** The lemma's recursive call gets its own post as a fact exactly when TERM phase 3's
  `ih_spans` admits that call span: certified SCC, the call reached, its preconditions proved
  (rule (a)). Nothing new is built; a lemma is a recursive function with a Unit return.
- **`assert e` inside a lemma** is a **static** obligation of a new kind, `Assertion`. It never
  runs, because the lemma never runs, so its fact is assumed **only if it is proved** (I5):
  - proved: `e` is a fact for the rest of the block;
  - skipped, unknown or refuted: `e` is **not** assumed. The skip is reported, and the lemma's post
    is checked without it.

  This differs from `assert` in ordinary code, where today's path assumes `e` after every `assert`
  (a5), soundly, because the runtime check aborts when `e` is false. A lemma has no runtime check,
  so `@[lemma] fn l(n : Int) : {Unit | false} do assert false  () end` must not prove.
- **An unproved lemma** draws a warning, **`lemma_unproved`**, at the lemma (an error under
  `cap verified`). A refuted post is today's `refinement_violated`.

### 4.4 Calling a lemma, and the two-stage discharge

At a call `l(a1, …, an)` anywhere (D5):
- the preconditions are checked as for any call;
- if `l` is admitted **and** every precondition obligation at that call is proved, the fact
  `P[params := args]` (instantiated from the proved SMT term, §3.5) is added to the facts of
  everything after the call **in its own block**. It does not leak out of an enclosing `if` or
  `match` branch;
- if a precondition is not proved, the fact is withheld and the call draws
  **`lemma_unproved_call`** (a warning; an error under `cap verified`). A refuted precondition is
  `refinement_violated` as usual. There is no runtime fallback, so the fact must never be
  assumed on an unproved call.

Every obligation is then discharged in **two stages**:
1. **Stage 1** is today's query, byte for byte: no unfoldings, no `r = f$r(x)` call-result facts,
  no reflected subjects. Its VC text, and so its cache key, is today's (F9). The one new thing
  that may appear in it is a lemma fact, which exists only after a lemma call, and no corpus
  program has one.
2. **Stage 2** runs only when stage 1 did not prove the goal (skipped, unknown, or refuted) and
  the frontier (§3.7) holds at least one reflected call in the **unfolding tier**. A call of an
  axiom-tier measure does not count: its axioms are already in stage 1, so a stage-2 query would
  be identical (I10). Stage 2 is stage 1 plus the unfoldings and connecting facts.
   - **unsat: proved.** Every unfolding and every connecting fact is named (`:named u1 …`,
     `:named c1 …`), and the unsat core (`:produce-unsat-cores`) gives the `uses:` list of §2.4.
     Naming the call-result facts matters: `let a = f(x)`, `let b = f(x)`, `need(a == b)` is
     proved by congruence alone, with no unfolding in the core, and must still list `f` (I8);
   - **sat:** the model goes through the witness interpreter as today; a refutation is reported
     only if stage 2 also refutes;
   - **unknown:** the stage-1 verdict stands.
3. **A stage-1 refutation followed by a stage-2 proof** (I7):
   - if the witness interpreter **confirmed** the stage-1 model (the program really fails on it),
     stage 2's unsat means the unfoldings contradict a real run. That is an encoding bug: the
     checker reports the internal error **`reflect_inconsistent`** (RED in CI, a compiler-bug
     message to users) and keeps the confirmed violation;
   - if the model was **not** confirmed, the refutation came from a call result the logic knew
     nothing about, and stage 2's proof stands. The monotone gate lists it as withdrawn (§6.2).

**Stage 2's cost controls** (I10):
- its own per-query timeout, **1 s** (stage 1 keeps 3 s);
- an **in-process** negative cache of stage-2 `unknown`s, keyed by the VC text, the z3 version
  and the timeout. It lives as long as one `march` run or one LSP process and is never written to
  disk, so F9's rule (no persisted `unknown`) still holds, while an LSP re-analysis does not pay
  the same timeout on every keystroke.

**The cache stores the core** (I8). `vc_cache.ml` today stores `unsat` or `sat` with a model. A
stage-2 entry also stores its core (`unsat` then a `core` line naming the assertions), so a
warm-cache proof prints the same `uses:` as a cold one. z3 4.8.12 (CI) and 4.16 may return
different but equally valid cores; golden tests therefore assert that `uses:` **contains** the
expected definitions, not that it equals them.

Stage 2 can only add proofs. It cannot turn a stage-1 proof into anything else, because a
stage-1 proof never reaches stage 2.

### 4.5 Erasure (D5)

Erasure is a **front-end pass**, not part of the refinement check (I6). It runs right after
typechecking, on every path that turns source into something that runs:
- `--compile` and `--emit-llvm` (before `March_tir.Lower`);
- the interpreter (before `March_eval.Eval.run_module`);
- the REPL JIT (`lib/jit/`) and the in-browser compiler (`docs/assets/march_compile.js`, built by
  `scripts/build-browser-repl.sh`);
- `forge test`, `forge run` and doctests.

It depends only on the `@[lemma]` attribute, never on a proof verdict, on z3 being installed, or
on the early source CAS. A warm CAS hit returns an artifact that was built from erased code, so
cold and warm builds emit the same IR. The pass (`lib/desugar/lemma_erase.ml`, beside the other
AST rewrites, so every driver that desugars also erases) removes:
- every call to a lemma, replacing it by `()`;
- every lemma declaration.

The refinement checker reads the **un-erased** typed AST (it needs the lemma calls); every
backend consumes only the erased one. So no lemma body, and no static `assert` inside one, ever
runs, whether or not the lemma was proved, and whether or not the check ran at all. An unproved lemma simply gives no facts (§4.3).

Erasure is behaviour-preserving only if the erased argument expressions have no effect and
always finish. So every argument of a lemma call must be a **reflectable term**: variables,
literals, constructors and calls of reflected functions. Anything else is an error,
**`lemma_argument_impure`**: "erasing this call would also erase the effect of `println(…)`;
bind it to a name first".

### 4.6 Worked proof: `rev(rev(xs)) == xs` on probe (a)'s functions

With single unfolding (phases 1-3), each proof step that needs a second unfolding is an
`assert`. Each `assert` is proved by its own single unfolding plus the earlier facts.

```march
@[lemma]
fn cat_nil_left(ys : List(a)) : {Unit | cat(Nil, ys) == ys} do
  ()
end

@[lemma]
fn cat_assoc(xs : List(a), ys : List(a), zs : List(a)) : {Unit | cat(cat(xs, ys), zs) == cat(xs, cat(ys, zs))} do
  match xs do
    Nil -> ()
    Cons(_, t) -> cat_assoc(t, ys, zs)
  end
end

@[lemma]
fn rev_cat(xs : List(a), ys : List(a)) : {Unit | rev(cat(xs, ys)) == cat(rev(ys), rev(xs))} do
  match xs do
    Nil ->
      cat_nil(rev(ys))
    Cons(h, t) ->
      rev_cat(t, ys)
      cat_assoc(rev(ys), rev(t), Cons(h, Nil))
  end
end

@[lemma]
fn rev_rev(xs : List(a)) : {Unit | rev(rev(xs)) == xs} do
  match xs do
    Nil -> ()
    Cons(h, t) ->
      rev_rev(t)
      rev_cat(rev(t), Cons(h, Nil))
      assert rev(Nil) == Nil
      assert cat(Nil, Cons(h, Nil)) == Cons(h, Nil)
      assert rev(Cons(h, Nil)) == Cons(h, Nil)
      assert cat(Nil, t) == t
      assert cat(Cons(h, Nil), t) == Cons(h, t)
  end
end
```

The `Cons` arm of `rev_rev`, step by step (`[h]` is `Cons(h, Nil)`):

| Step | Fact | From |
|---|---|---|
| 1 | `rev$r(xs) = cat$r(rev$r(t), [h])` | unfolding `rev$r(xs)` in the goal, guard `is_Cons(xs)` from the arm |
| 2 | `rev$r(rev$r(t)) = t` | the IH, `rev_rev(t)` (certified structural) |
| 3 | `rev$r(cat$r(rev$r(t), [h])) = cat$r(rev$r([h]), rev$r(rev$r(t)))` | lemma `rev_cat` |
| 4 | `rev$r([h]) = [h]` | the asserts, each by one unfolding plus the ones before it |
| 5 | `cat$r([h], t) = Cons(h, t)` | the last `assert`, proved by one unfolding of `cat$r([h], t)` (giving `Cons(h, cat$r(Nil, t))`) and the fact `cat$r(Nil, t) = t` |
| goal | `rev$r(rev$r(xs)) = rev$r(cat$r(rev$r(t), [h])) = cat$r([h], t) = xs` | congruence over 1-5 |

Phase 4's repeated unfolding makes the five `assert`s unnecessary: each is a decided step.

---

## 5. `@[measure]` under D2

### 5.1 What merging means

D2 merges `@[measure]` into reflection. After the merge there is one concept: a function the
logic knows. Every reflected function can be used in a predicate, with any number of
parameters and any encodable result sort. Today's limits on measures (F2 one parameter, F4 the
body fragment, F5 Int only, F6 the silent list fallback) are gone, because the measure path is
no longer the only way into the logic.

### 5.2 The options for the attribute

| Option | Meaning | Breakage | Verdict |
|---|---|---|---|
| **A. An alias that errors** | `@[measure]` means `@[reflect]` (§3.8): the function must be reflected, else `invalid_measure` naming the first blocker. It also keeps the legacy axiom encoding where it applies (§5.3) | measures that pass today's gate but fail R1-R9 become errors: F7's `noisy`/`boom`/`spin`/`show` shapes. The in-tree count of such measures is to be listed in phase 1 (the two stdlib ones pass) | **recommended** |
| B. A deprecated alias with a warning | as A, plus `deprecated_attribute` pointing at `@[reflect]` | as A, plus a warning on 2 stdlib and 117+ test programs | alternative, once `@[reflect]` has a release behind it |
| C. Removal | `@[measure]` becomes `unknown_attribute` | every measure loses its guarantee; `pvec_length` and `sorted_set_elts` keep working only if they pass R1-R9 and R11 without the attribute, and they lose the axiom tier | rejected for v1 |

**Why A.** Today's `@[measure]` is the one way a user says "this must reach the logic, fail
loudly if it can't". D1 removes the need to opt in, but not the need to **insist**: a refactor that
adds a `println` to a measure must not quietly turn every proof that uses it into a skip.
`@[measure]` is also the word the reference, the error corpus and LH users know. Keeping it as an
exact synonym of `@[reflect]` costs one line in the attribute table.

What changes for an existing measure under A:
- the shape error (F2) is gone; a two-parameter or list-returning `@[measure]` is accepted and
  reflected (b1, b2, c1 become proofs once lemmas exist);
- the gate (F7) becomes R1-R9, so it now follows callees: c3b and h2 become `invalid_measure`;
- the error text keeps the "is not structurally recursive …" wording where R2 is the blocker, so
  the error corpus (`test/errors/`) is stable for those cases.

### 5.3 Two encodings: the axiom tier and the unfolding tier

D12 says definitions reach z3 by unfolding, not by quantified axioms. Today's measures are
quantified axioms (F3), and existing proofs rely on them (§0.9). Switching them to unfolding
would risk exactly the proved-to-skipped moves §6 forbids: a pattern-triggered axiom fires at
any depth z3 reaches, single unfolding does not.

**Ruling:** a function written with `@[measure]` that fits today's measure fragment (one ADT
parameter; Int or Set result, or Bool after F5's fix; body inside `smt_of_axiom_body`'s fragment)
keeps its axioms. This is the **axiom tier**. It is grandfathered, not extended: no function
reaches the axiom tier without the attribute, and a measure outside the fragment is in the
**unfolding tier** like every other reflected function. Both tiers use the same symbol for the
same function, so a predicate can mix them.

Why this is consistent with D12: D12 governs how **reflected definitions** reach z3. The axiom
tier is the pre-existing measure encoding, kept so D2 changes no existing proof. Moving measures
to unfolding is open question Q1, to be decided on phase 4's measurements (when repeated
unfolding can match the axioms' depth).

### 5.4 Keeping today's measure uses proving

- The two stdlib measures pass R1-R9 and R11: `pvec_length` is a non-recursive field read;
  `sorted_set_elts` is structural and calls only the set vocabulary, which R6 admits for a
  set-valued function. Both stay in the axiom tier.
- `test/errors/non_tail_recursion_1.march` and `specs/lang/types/reject/t109_…` use a structural
  `size`: axiom tier, unchanged.
- The `test_refinecheck` measure groups must pass unchanged. Any case whose expected diagnostic
  changes (F7-shaped gate cases) is listed in the phase-1 progress note with the old and new text.
- The oracle gate (§6) on the corpus confirms no measure-backed proof moved.

---

## 6. The oracle gate under D1 and D2

TERM's phases each ended with `refine-oracle` **IDENTICAL**. Automatic reflection changes proofs
on purpose, so identity is the wrong gate. The new gate is **monotone**.

### 6.1 Prerequisite: every obligation's verdict, by site

`--refine-report-sites` prints only skipped obligations. Phase 0 adds
`--refine-report-sites=all`, one line per obligation:

```
proved	user	file:line:col	precondition	need	_ < 10
skip	user	file:line:col	unreflectable-subject	postcondition	law	…
violated	user	file:line:col	precondition	need	…
```

### 6.2 The rule

`scripts/refine-oracle.sh` gains a mode, `monotone <dir>`, that compares the `=all` listing of a
baseline against the current compiler, across the whole corpus (`test/native/*.march` and
`stdlib/*.march`), by `(fixture, site, kind, callee, predicate)`.

| Move | Gate |
|---|---|
| proved → proved, skip → skip, violated → violated | silent |
| **proved → skipped, unknown or violated** | **RED**, no exemptions. §3.5 changes no predicate's meaning, so nothing is expected here |
| skipped → proved | listed under `new proofs`. Each must be explained in the progress note (which definition or lemma it used: the `uses:` column) |
| skipped → violated, or a new site that is violated | listed under `new violations`. **A new violation is a finding**: either a real bug in the corpus (file it, and leave the fixture as it is) or a checker bug (fix it before merging) |
| violated → proved or skipped | listed under `withdrawn violations`. Each must be explained: a stage-1 refutation that the witness interpreter did **not** confirm and stage 2 proved (§4.4). A confirmed refutation that stage 2 proves is never withdrawn; it is an internal error |
| a site that disappears or appears | RED unless explained (a lemma call adds sites; erasure removes none, because the check runs before erasure) |

The mode is proved able to go RED before it is trusted (the `CLAUDE.md` oracle rule): a
perturbation that drops stage 1 for every query must print proved-to-skipped lines, and one that
adds an unconditional `false` fact must print new proofs on vacuous goals.

### 6.3 The timing budget

Interleaved A/B, five runs, median, load average recorded, `.march/cas/vc` cleared once
(TERM §9's protocol), private `HOME`:

| Measure | Budget |
|---|---|
| default `--check` on `stdlib/list.march` and `stdlib/json.march` | **≤ 105%** |
| the corpus sweep's total wall time | **≤ 110%** |
| any single fixture | **≤ 150%**, and no fixture that finished under the 3 s per-query timeout before may hit it after |
| from phase 1: every corpus fixture that calls a reflected stdlib function | ≤ 120% |
| LSP: re-analysis of one edited file that uses a reflected function, warm process | ≤ 120% of today's re-analysis latency, median of 20 edits; no single edit over 1.5 s added |

---

## 7. Reflection as part of a function's interface

With D1, a function's body, not just its signature and contract, can decide a caller's proof. A
change inside `is_small` can make a caller's call to `need_small` fail. This section says how that
is visible and how nothing stale survives it.

### 7.1 The proof cache (D17)

- **Already sound by construction.** An unfolding is VC text, so a body edit changes the text,
  so it changes the key (F9). Probe e1 shows the other half: today a body edit changes no caller
  key, because no caller VC contains a body.
- **D17 explicitly.** Each stage-2 VC's assertion block also carries one comment line per
  reflected definition in its frontier:

  ```
  ; reflect cat$r@Int blake3=4c1f…
  ```

  The hash is BLAKE3 of the function's canonical desugared body, of its R1-R11 status, and of the
  **`Eq` derivation status** (derived all the way down, hand-written, Float) of every type at
  which its body uses `==` (I8). So:
  - a definition the encoding drops (an over-budget term) still keys the proof;
  - a callee that stops being reflected changes the key even if no unfolding text changes;
  - changing a type's `derive Eq` to a hand-written `impl Eq` changes the key of every proof
    whose definitions use `==` at that type;
  - the key states its dependencies, which `scripts/refine-oracle.sh` and humans can read.
- Stage-1 keys are unchanged (they mention no definition).

### 7.2 Across files and builds

- **`--check` and `--compile`.** The early source CAS keys on every input byte (F10), so any body
  edit re-runs the whole check.
- **The LSP.** A file is re-checked against its dependencies' declarations (F10). Phase 1 adds
  to the dependency key (I8):
  - the D17 hash of **every reflected function in the frontier** of any stage-2 query the file's
    last check ran, whether or not it reached the unsat core. Keying on the core would miss a
    definition that a cold run needed and a warm run did not;
  - for every lemma of a dependency file that the file calls: its post hash, its body hash and
    whether it was **admitted** (proved). A dependency lemma that stops proving must re-check its
    callers.

  Without this, editing `lib/util.march`'s `is_small` would leave `app.march`'s squiggle stale.
- **Hot code reload and `--dump-impl-hashes`.** HCR admits a body-only patch when `sig_hash` is
  unchanged (F11). A patch that changes a reflected function's body can invalidate the deployed
  callers' proofs, silently, even under `cap verified`. Phase 1 therefore does two things (I9):
  - adds a fourth column, `logic_hash` (the D17 hash, or `-` for an unreflected function), to
    `--dump-impl-hashes`;
  - makes HCR admission treat a changed `logic_hash` **exactly like a changed `sig_hash`**: the
    patch is refused with "the body of `f` is part of its callers' proofs; redeploy, or mark it
    `@[opaque]`". This is the conservative rule, and it stays until Q4 settles a re-check path.

### 7.3 What a user sees

- the `uses:` note on each stage-2 proof (§2.4);
- `--reflect-report` for the status of every function;
- the `refinement_unchecked` text that names the blocker when a function stops being reflected;
- `@[opaque]` to make a body private to its module's proofs, and `@[reflect]`/`@[measure]` to
  make reflection a checked promise.

---

## 8. Cost

### 8.1 What the probe says

From §0.10:
- **Eager reflection** (unfold in every query) would add unfoldings to about 6-7% of the call-site
  obligations and up to 29% of the stdlib's refined returns. Those queries are mostly proved
  today, so eager unfolding would put proved verdicts at risk of a timeout for no gain.
- **With the two-stage discharge**, stage 2 can run only on a non-proved obligation. In the
  corpus that is at most **18 user-code queries in all 417 programs**, plus the stdlib's **40**
  skips per program.
- **The stdlib's 40 run in every program**, so they matter most. The stdlib is reflected from
  phase 1 (§2.6), so any of the 40 whose frontier holds a reflected stdlib call runs stage 2 in
  every program, from phase 1. That is at most 40 extra queries per program, each under stage 2's
  1 s timeout and the in-process negative cache (§4.4). The phase-1 progress note measures the
  real number and its time over the corpus.
- So the default-mode cost in phases 1-2 is the reflectability analysis (a linear pass over
  TERM's graph, which is already built when a module has a measure or a demanded SCC) plus
  stage 2 on user code's own skips and on those of the 40 stdlib skips whose frontier holds a
  reflected call. The ≤ 105% budget of §6.3 is expected to hold; phase 1
  measures it.

Three loads the first draft missed (review I10), and what bounds each:
- **Phase 3's stdlib lemmas are stdlib obligations, so they would be proved in every program.**
  Ten lemmas, each needing stage 2 and its `assert`s, would join the 220 obligations checked per
  program. Rule: a stdlib lemma is **proved where the stdlib is checked on its own** (the
  `march --check stdlib/list.march` row of the stdlib CI suite and the oracle sweep), and a
  checked-in manifest, `stdlib/.lemmas.verified`, records `(lemma, post hash, body hash)` for
  each proved one. In a user program, a stdlib lemma whose hashes match the manifest is admitted
  without re-proof; one whose hashes do not match is re-proved (and the manifest is stale, which
  a CI check catches). The manifest is written by a script, never by hand.
- **`unknown` is never cached** (F9), so a stage-2 timeout would be paid on every `--check` and
  every LSP re-analysis. Stage 2's own 1 s timeout and the in-process negative cache (§4.4) bound
  it to once per process.
- **An axiom-tier call** (`Array.length` aliased to `pvec_length`) would have triggered a
  stage-2 query identical to stage 1. Axiom-tier calls do not trigger stage 2 (§4.4).

### 8.2 The bounds

| Bound | Effect |
|---|---|
| **Two-stage discharge** (§4.4) | a query stage 1 proves costs exactly what it costs today. Stage 2 runs only on the non-proved share |
| **Frontier = calls in the obligation** (§3.7) | no unfolding of definitions the query does not mention, so a module full of reflected functions costs nothing in queries that do not use them |
| **No re-unfolding in phases 1-3** | at most one unfolding per distinct call term, so the extra assertions are linear in the size of the VC |
| **32 unfoldings per query** | a hard cap; past it, `reflect-budget` |
| **Quantifier-free unfoldings** | every added assertion is ground, so no matching loop can start. The only quantifiers are the axiom-tier measures, as today |
| **`@[opaque]`** | removes one function from every frontier |
| **`@[opaque]` on the stdlib** (§2.6) | a stdlib function that proves costly is taken out of every frontier, with its reason in the phase-1 note |

---

## 9. Soundness

### 9.1 The cases

| Case | The danger | The rule that stops it | REJECT test (phase) |
|---|---|---|---|
| a **diverging function** | `spin(n) = spin(n) + 1` as an equation gives `0 = 1`, which proves anything | R2: only `structural`/`metric` certificates; TERM certifies nothing that diverges (its own REJECT controls) | `sound_diverge`: `fn spin(n : Int) : Int do spin(n) + 1 end` and `need_false(x : {Int \| spin(0) == spin(0) + 1})`, called as `need_false(0)`: `spin` is not reflected, the predicate is `refinement_unchecked`, the call is skipped, never proved. `@[measure]` on `spin`: `invalid_measure` (1) |
| a **partial function** | a value asserted for an input the program never returns from | R4, R5 | `sound_partial`: `hd` with a missing `Nil` arm, and `safe(n) = if n > 0 do n else panic("") end`: neither reflected; `{Unit \| hd(Nil) == 0}` unchecked (1) |
| an **effectful function** | a predicate claiming a value for an action | R3, R6 | `sound_effect`: `noisy(n) = println("hi"); n`: not reflected; c3b's measures become `invalid_measure` (1) |
| a **hand-written Eq through `==`** | a body's `==` translated as z3 equality where the program runs `eq` | §3.5: opaque `eq$T` in bodies | `sound_eq`: `same(a : P, b : P) : Bool = a == b` (g3's `P`) is reflected with `eq$P`, and `{Unit \| same(P(1, 3), P(1, 2)) == false}` must **not** prove (at run time `same` is `true`). Control: with `derive Eq`, the same lemma proves. **Transitive:** `type Q = Q(P)` with `derive Eq for Q` and `P` hand-written: `same_q(Q(P(1, 3)), Q(P(1, 2))) == false` must not prove either. g3 itself stays a violation and gains `predicate_eq_structural` (1) |
| an **effectful, partial or diverging `eq`** (C4) | `same(a, b) = a == b` reflected while `eq` prints, panics or loops; erasing `lemma(same(p, q))` would drop the effect, and `r = same$r(p, q)` asserts a determinism the program lacks | §3.5: the D7 exception only for an `eq` passing R2-R7 | `sound_eq_effect`: three `impl Eq`s, one calling `println`, one `panic`, one recursing on itself with no metric; `same` over each is **not reflected** (`R6: == at P dispatches to impl Eq(P).eq, which calls println`), and `lemma(same(p, q))` is `lemma_argument_impure` (1) |
| **`==` on a polymorphic container in a lemma** (C3) | a lemma proved with logical `=` at `Elem`, then combined with a body's program `==` at `List(Float)` | §3.5: predicates logical, bodies program; lemma facts instantiated from the proved term | `sound_eq_float`: `same(a : List(Float), b : List(Float)) : Bool = a == b`; after `rev_rev(xs)`, `need_true(same(rev(rev(xs)), xs))` must **not** prove (`xs = [NaN]` makes it false at run time). And `@[lemma] fn idl(x : a) : {Unit \| ident(x) == x}` called at a `Float` `x`, then `need_feq(ident(x), x)` with `need_feq(a : Float, b : {Float \| _ == a})`: must **not** prove (scalar `fp.eq` is false on NaN). Control: `rev_rev(xs)` then `need_eq(rev(rev(xs)), xs)` with `need_eq(a, b : {List(Float) \| _ == a})`, a predicate `==` inside a datatype, **proves** (2) |
| a **function value in the body** | no fixed definition to unfold | R7 | `sound_fnvalue`: `apply(f, x) = f(x)`, `twice(x) = List.map([x], fn y -> y + 1)`: not reflected (1) |
| a **lemma's IH without a certificate** | `bad(n) : {Unit \| false} = bad(n)` proves `false` if its self-call is assumed | L4, and TERM's `ih_spans` | `sound_lemma_ih`: that `bad` is `invalid_lemma`; `bad2(n) : {Unit \| n < 0}` recursing on `n - 1` with exit `n == 0` (unproved, witness `n = -1`) is `invalid_lemma`; with exit `n <= 0` and post `{Unit \| n <= 0 \|\| n > 0}` it proves (2) |
| a **lemma proved through a failure path** | h1's `bogus`: a `panic` arm makes the post vacuous, and the lemma never runs to catch it | L2 | `sound_lemma_panic`: `@[lemma] fn bogus(n : Int) : {Unit \| n == n + 1} do panic("x") end` is `invalid_lemma` (2) |
| **removing lemma calls changing behaviour** | an erased argument's effect disappears | §4.5: arguments must be reflectable terms; lemmas are total, so erasing the call removes no effect and no divergence | `sound_erase_ir`: each phase-2 fixture is compiled with and without its lemma calls and lemma declarations (textually removed): `--emit-llvm` byte-identical and `--dump-impl-hashes` identical; `lemma(println_and_return(xs))` is `lemma_argument_impure`. `scripts/ir-oracle.sh` IDENTICAL over the corpus (2) |
| a **stale cache after a body edit** | a warm VC cache answering for the old body | §7.1 | `sound_cache`: `inc(n) = n + 1`, caller `need(inc(1))` with `{_ == 2}` proved; edit `inc` to `n + 2` with the same project cache; the call must be **violated**; and a body edit that changes only reflectability (adding a `println` to a callee) must change the D17 line (1) |
| **Int overflow** (D8) | `{Unit \| inc(n) > n}` is true in the logic and false at the maximum `Int` (F18) | out of scope by D8; documented in the reference; a todo files the overflow phase (§10.3) | `known_overflow`: from phase 2 on, that lemma **proves**, and the test asserts it, labelled as a known gap, so the overflow phase must flip it on purpose (2) |
| **builtins that run user impls** | `to_string`, interpolation, `show`, `compare`, `<` on a user `Ord`, `hash`: a "builtin" whose meaning is user code | R6 counts them as calls, through TERM's dispatch edges; none is in the R6 table | `sound_dispatch`: `f(x : T) = string_byte_length("${x}")`, `g(x : T) = show(x)`, `h(a : T, b : T) = compare(a, b)` with a user `impl` each: none reflected (1) |
| a **call outside the refined domain** (C1) | `p(n : {Int \| _ >= 0}) = if n >= 0 do true else not p(n) end` is certified `metric` (probe r1). Unguarded, the frontier term `p(0 - 1)` unfolds to `p$r(-1) = not p$r(-1)`, a contradiction | §3.6: every equation is guarded by `pre_f(args)` | `sound_domain`: `@[lemma] fn bad(n : Int) : {Unit \| p(0 - 1) \|\| n == n + 1} do () end` must **not** prove (`lemma_unproved`). Control: `@[lemma] fn ok() : {Unit \| p(1)} do () end` proves (2) |
| a **guarded match that can fall through** (C2) | `match xs do Cons(h, _) when h > 0 -> h  Nil -> 0 end` has no `non_exhaustive_match` warning (probe r2), yet panics on `[-1]`. A last-arm default would assert `guarded$r([-1]) = 0` | R5 reads `nonexhaustive_match_spans`; §3.4 never makes the last arm a default | `sound_guarded`: `guarded` is not reflected (`R5: a guarded match may not match`); with a final `_ -> 0` arm it is reflected, and `need_eq(guarded(Cons(0 - 1, Nil)), 0)` proves. And `lemma(guarded(Cons(0 - 1, Nil)))` is `lemma_argument_impure` (1) |
| a **user function spelled like a builtin** (I3) | a user `fn len(xs) = 7` makes `len([1])` 7 at run time while the predicate `len(_) == 1` means `$len` (probe r3). A reflected `g(xs) = len(xs)` translated by spelling would get `g$r = $len` | R6 by resolved identity; R11 | `sound_shadow`: with that `len`, `g(xs) = len(xs)` is **not reflected** (`R6: calls len, which is not reflected (R11: its name is predicate vocabulary)`); `need_eq(g(Cons(1, Nil)), 1)` must not prove; the predicate `len(_) == 1` keeps today's meaning (1) |
| **two definitions, one symbol** (I4) | a collision gives one z3 symbol two definitions, which proves anything | §3.1 mangling, and the duplicate-definition internal error | `sound_mangle`: `f` and `g` each define a local `go` with different bodies (`go(n) = n + 1` and `go(n) = n + 2`); `{Unit \| f(0) == 1}` and `{Unit \| g(0) == 2}` both prove, and `{Unit \| f(0) == g(0)}` must **not**. `h` declares two `go`s in sequence: the same. A user `mod List` whose `append` drops its second argument: `need_eq(List.append(xs, Nil), xs)` inside the user module refers to the user function, and stdlib `List.append` facts never mention it (1) |
| an **unproved static assert** (I5) | `assert false` in a lemma, assumed afterwards, proves any post | §4.3: a lemma `assert` is assumed only when proved | `sound_assert_false`: `@[lemma] fn l(n : Int) : {Unit \| false} do assert false  () end` must **not** prove: `Assertion` skip, then `lemma_unproved` (2) |
| **erasure skipped on some path** (I6) | a warm CAS hit, the JIT or the browser compiler running a lemma body | §4.5: erasure is a front-end pass independent of the check `sound_erase_paths`: a fixture with a lemma and lemma calls. On `--compile`, the interpreter, the REPL JIT and the browser-compiler smoke (`scripts/browser-repl-smoke.js`), the lemma's symbol is absent (`--dump-tir`, or the JIT's symbol table), and the program's output equals the lemma-free program's. With z3 removed from PATH, the same holds. `scripts/determinism-oracle.sh` on the fixture: cold and warm `.ll` identical (2) |
| **encoding contradicts a real run** (I7) | a confirmed stage-1 counterexample "withdrawn" by a stage-2 proof | §4.4: `reflect_inconsistent` | `sound_inconsistent`: a deliberately broken `term_of_body` (swapped arms, a test-only switch) on a fixture with a confirmed violation: `reflect_inconsistent`, verdict stays violated (1) |
| a **stale `uses:`, LSP or HCR result** (I8, I9) | warm cache without a core; LSP keyed on the core; a body-only hot patch | §4.4 core in the cache; §7.2 LSP keys; §7.2 HCR refusal | `sound_uses_warm`: the same fixture's `uses:` cold and warm are equal; the congruence fixture (`let a = f(x)`, `let b = f(x)`, `need(a == b)`) lists `f`; `sound_hcr`: a body-only patch to a reflected function is refused; to an `@[opaque]` one, admitted (1) |

### 9.2 The safety net: the logic against the interpreter (D16)

The rules above make the **definition** of a reflected function a theorem. They do not prove
that `term_of_body` (§3.4) translated it **correctly**. A wrong selector, a wrong arm order, a
truncation mismatch in `/`, or a guard that falls through wrongly would be an unsound equation
that no rule in §9.1 notices. The net is a parity check:

- For a reflected `f` whose parameter types have generators (Int, Bool, `List`, `Option`,
  `Result`, tuples, and user ADTs through a depth-bounded generator the checker derives), draw
  `N` random inputs (`N = 100`, a fixed seed recorded in the report).
- For each input `x`, run the interpreter on `f(x)` with the witness interpreter's fuel
  (`witness.ml:46-51`) to get a value `v`.
- Ask z3 whether `f$r(x̂) ≠ v̂` is satisfiable, where `x̂` and `v̂` are the ground terms, with
  unfolding on decided terms up to a step cap of 10 000 (a ground argument always decides its
  guards).
- unsat: agreement. sat: **an encoding mismatch**, reported with `f`, `x`, the interpreter's `v`
  and the logic's value from the model. That is a compiler bug, never a user error.
- A timeout or the step cap is reported as "not compared", never as agreement.
- **An interpreter failure on a reflected function is RED, not "not compared"** (C2). R2-R5 say a
  reflected function always returns a value, so a `panic`, a match failure, or running out of
  the interpreter's fuel on an input inside `pre_f` means R5 (or R2) admitted something it should
  not have. It is reported as a reflectability bug, with the input.
- **Boundary inputs** (D8). Besides the random draws, every `Int` parameter also takes `0`, `±1`,
  the maximum and minimum 63-bit `Int`, and their neighbours. A mismatch on one of those, where
  the interpreter's answer wrapped, is reported as **overflow-sensitive**, not as an encoding bug:
  D8 says the logic's `Int` is unbounded. `--reflect-report` marks such functions `overflow?`, so
  the overflow phase has its list.

Where it runs (D16):
- **Opt-in in `forge test`**: `forge test --reflection-parity` (beside `--skip-properties` in
  `forge/lib/cmd_test.ml`) runs it over the project's reflected functions.
- **Always in CI**: a test group `reflect-parity` in `test/test_refinecheck.ml` runs it over the
  phase fixtures, and a sweep step runs it over every reflected function of the corpus
  (`test/native` and the stdlib). Any mismatch is RED.

The net also covers the axiom tier: the same comparison runs for every `@[measure]`, which
nothing checks today.

### 9.3 Deliberately not claimed

- **Int overflow** (D8). The logic's `Int` is unbounded. A reflected function that overflows at
  run time has a definition that disagrees with the program at those inputs. Under D1 this now
  reaches ordinary arithmetic (hashes, checksums) that nobody annotated. The parity check's
  boundary inputs (§9.2) **detect** such functions and `--reflect-report` marks them `overflow?`,
  but nothing **prevents** a proof that relies on unbounded arithmetic. The overflow phase decides
  the fix.
- **Float and String content** (D9). Both are opaque, so nothing is claimed beyond length.
- **Stack depth.** A reflected function may still overflow the stack at run time. Its definition
  is still its mathematical meaning.
- **Liquid Haskell features left out of scope** (review minors), each stated so their absence is
  not mistaken for support:
  - **abstract-refinement parameters on reflected functions.** A reflected function's
    `List(a[p])` element refinement is not part of its definition; the definition is over
    `List(Elem)`, and the abstract refinement stays a contract, as today;
  - **reflection of `impl` methods** (R1). A method reaches the logic only through D7's opaque
    `eq$T`, and only for `Eq`;
  - **quantified or existential postconditions.** A lemma's post is a quantifier-free predicate
    over its parameters, as every refinement is today.
- **The interpreter itself.** D16 compares against the interpreter. A bug shared by the
  interpreter and the compiled code is outside this net; `scripts/triage.sh`'s interpreted-versus-
  compiled comparison is the net for that.

---

## 10. Phases

D20's first step ("probes, then single unfolding, then lemmas") is phases 0, 1 and 2 here, in
that order. D18's functions are reflected from phase 1, like the rest of the stdlib (§2.6); phase 3 is the release that makes them provable about, with lifts, lemmas and the manifest. Phases 4-7 are D20's "later".

Conventions, as in TERM §8:
- `test_refinecheck.exe` green at every step;
- every new rule lands with a fixture that goes RED without it (perturbation recorded in the
  progress note);
- ledger triples asserted, never exit codes;
- `dune build --root .`, z3 on PATH, a private `HOME`, CI's z3 4.8.12 noted;
- each phase adds `specs/progress/2026-MM-DD-reflection-phaseN.md`, a `CHANGELOG.md`
  `[Unreleased]` bullet, and updates `specs/lang/refinement-types.md` then runs
  `scripts/gen-lang-docs.py`;
- new diagnostic codes are seeded with `scripts/seed-error-corpus.sh` (`test/errors/<slug>_1.march`,
  `specs/lang/errors/<slug>.md`).

### Phase 0: infrastructure and probes (inert)

**Scope.**
- `lib/refinecheck/refine_reflect.ml` (new): the §2.1 fixpoint over TERM's graph, with a reason
  per unreflected function. Nothing reads it except the report.
- `--reflect-report` (`bin/flags.ml`, `bin/main.ml`), bypassing the early CAS exit.
- `--refine-report-sites=all` (`bin/main.ml`, `obligation.ml`): one line per obligation, any
  verdict.
- `scripts/refine-oracle.sh monotone` (§6.2), proved able to go RED.
- The §0 probes as fixtures under `test/refine/reflect/` (accept side: today's verdicts pinned).
- Todos filed, one file each: F5 (Bool measures never discharge), F6 (list-returning measure
  silently ignored), F7 (the measure gate does not follow callees), F8/g3 (no warning when a predicate's
  structural `==` meets a hand-written `Eq`; phase 1 adds `predicate_eq_structural`), F21 (a user function named like predicate vocabulary is silently ignored by predicates), and the Int-overflow todo for D8.

**RED tests** (group `reflect-report`):

| Test | Program | Expected | Reason |
|---|---|---|---|
| `report_cat_rev` | probe a2's `cat` and `rev` | both `reflected unfold` | positive control |
| `report_effect` | `noisy(n) = println("hi"); n` | `no R3:calls println` | R3/R6 |
| `report_diverge` | `spin(n) = spin(n)` | `no R2:unproved` | R2 |
| `report_trusted_cert` | `@[decreases(n)] @[trusted]` recursion whose metric fails | `no R2:trusted` | D6 excludes trusted |
| `report_trusted_nonrec` | `@[trusted] fn k(n : Int) : {Int \| _ > 0} do n end` (non-recursive) | `no R9:@[trusted]` | R9 applies with no recursion |
| `report_guarded` | the review's `guarded` (probe r2) | `no R5:guarded match may not match` | C2 |
| `report_domain` | the review's `p` (probe r1) | `reflected unfold`, with `guard: n >= 0` in the row | C1: reflected, but guarded |
| `report_shadow` | probe r3's user `len`, and `g(xs) = len(xs)` | `len`: `no R11`; `g`: `no R6:calls len` | I3 |
| `report_eq_effect` | `same` over an `impl Eq` that prints | `no R6:== at P dispatches to impl Eq(P).eq, which calls println` | C4 |
| `report_partial` | `hd` without `Nil`; `safe` with `panic` | `no R5:non-exhaustive`, `no R4:calls panic` | R4, R5 |
| `report_div` | `half(n) = n / 2`; `ratio(a, b) = a / b` | `half` reflected; `ratio` `no R4:division by b not proved` | R4 reads the ledger |
| `report_fnvalue` | `apply(f, x)`, `twice` with a lambda, `h` passing `h` | `no R7:…` each | R7 |
| `report_dispatch` | `show`, interpolation, `compare` on a user `impl` | `no R6:dispatches to impl …` | R6 dispatch edges |
| `report_chain` | `outer` calls `mid` calls `noisy` | `outer`: `no R6:calls mid, which is not reflected` | the fixpoint |
| `report_mutual` | `even`/`odd` on `Nat` | both reflected, one SCC | SCC as a whole |
| `report_local` | `reverse`-style local `go` | `go` reflected as `reverse/go`; a local capturing an outer variable is `no R1:captures k` | R1 |
| `sites_all` | a1 | four `proved` lines, `--refine-report` summary unchanged | the new listing |
| `monotone_red` | the two perturbations of §6.2 | the mode prints RED | the gate can fail |
| inert | — | `refine-oracle` and `ir-oracle` IDENTICAL; `--refine-report` byte-identical | — |

**Oracle gate:** IDENTICAL (nothing reads the analysis).
**Done means:** the probe (d) numbers reproduced by `--reflect-report` within the script's
±10%, every difference explained in the progress note; the todos filed.

### Phase 1: single unfolding of automatically reflected first-order functions, and the measure merge

**Scope.**
- §3.1-§3.7: symbols, sorts, `term_of_body`, guarded equations, the frontier, call-result and
  subject facts, the predicate translator's reflected-call arm.
- §4.4's two-stage discharge for every obligation kind (`refine_call.ml` `check_call`,
  `refine_post.ml` `check_post`), the unsat-core `uses:` note.
- §3.5's `==` rules: program equality in bodies (with the C4 totality condition), logical
  equality in predicates, lemma facts instantiated from the proved term, and the
  `predicate_eq_structural` warning (g3).
- §5: `@[measure]` as option A; F2's shape error removed; F5 fixed (Bool sort); the gate becomes
  R1-R9.
- `@[opaque]` (parser, `grammar.js`, `known_fn_attributes`), `reflect_conflict`.
- §7.1's D17 lines, §7.2's LSP invalidation and `logic_hash` column.
- §9.2's parity check: the `reflect-parity` group and `forge test --reflection-parity`.
- The stdlib reflected under the same rules (§2.6). Any stdlib function marked `@[opaque]` is
  listed in the progress note with its reason. The note reports the monotone gate and timing over
  the whole corpus, stdlib included.
- The review's fixes that land here: domain-guarded unfoldings (C1); R5 on
  `nonexhaustive_match_spans` and per-arm implications with no default (C2); the two equalities
  and the total-`eq` condition (C3, C4); resolved-identity callees and R11 (I3); the injective
  mangling and the duplicate-definition check (I4); `reflect_inconsistent` (I7); the core in the
  cache, named call-result facts, the LSP frontier and lemma keys, the Eq status in the D17 hash
  (I8); the HCR refusal (I9); axiom-tier calls skip stage 2, the 1 s stage-2 timeout and the
  in-process negative cache (I10).

**Files:** `lib/refinecheck/refine_reflect.ml`, `refine_encode.ml` (sorts, gate, shape error,
Bool sort), `refine_scope.ml` (predicate arm, `==`), `refine_call.ml`, `refine_post.ml`,
`refine_check.ml` (driver, attributes), `obligation.ml` (skip reasons `reflect-fuel` and
`reflect-budget`, the `uses` field), `lib/refine/refine.ml` (named assertions, unsat core),
`lib/refine/smt.ml` (comment lines in the assertion block), `lib/cas/hash.ml`,
`lsp/lib/analysis.ml`, `forge/lib/cmd_test.ml`, `lib/parser/parser.mly`,
`tree-sitter-march/grammar.js`, `bin/main.ml`, `lib/refine/vc_cache.ml` (the core line),
`lib/typecheck/typecheck_exhaustive.ml` (exports `nonexhaustive_match_spans`),
`lib/tir/hcr_abi.ml` (the `logic_hash` admission rule).

**RED tests** (group `reflect-unfold`):

| Test | Program | Expected verdict | Reason |
|---|---|---|---|
| `guard_pred` | §1's `is_small` / `need_small` | proved, `uses: is_small` | path fact unfolds |
| `pred_call` | h3's `idx2(i : {Int \| _ < inc(3)})`, `idx2(3)` and `idx2(4)` | proved; violated | predicate arm, non-recursive unfolding |
| `subject_call` | `need(x : {Int \| _ == 2})` called as `need(inc(1))` | proved | subject arm |
| `let_result` | `let r = inc(1)` then `need(r)` | proved | call-result fact |
| `one_step` | `need_eq(a : List(Int), b : {List(Int) \| _ == a})` called as `need_eq(ys, cat(Nil, ys))` | proved | depth-0 unfolding of a recursive function |
| `no_second_step` | a6: `need2(cat([1], [2]))` | **skip `reflect-fuel`** (needs depth 1) | single unfolding only |
| `two_arg` | b2's `count_ge` without `@[measure]`; `need_small(count_ge([5], 3))` | still `reflect-fuel` (recursive); `count_ge(Nil, 3)` proved `== 0` | multi-argument reflection |
| `list_result` | c1's `rev1` without `@[measure]`; `{List(Int) \| _ == Nil}` on `rev1(Nil)` | proved | datatype result sort |
| `bool_measure` | c2b's `pos_nat`: `needp(S(Z))`, `needp(Z)` | proved; violated | F5 fixed |
| `measure_alias_ok` | b1 and b2 with `@[measure]` | no error | F2 lifted |
| `measure_alias_err` | c3b's three measures, h2's two | `invalid_measure` each, naming the callee | gate follows callees |
| `measure_tier` | c4's `sz` | proved / violated exactly as before; VC text unchanged; **no stage-2 query is issued** for its calls (counted with a debug counter) | axiom tier kept; I10 |
| `lemma_in_body` | `fn safe_len(xs : List(Int)) : Int do len_cat(xs, Nil)  List.length(xs) end` (calls a lemma, D5), after phase 2 | reflected; `need_eq(safe_len(Cons(1, Nil)), 1)` proves as without the lemma call | I2: lemma calls are `()` in `term_of_body` |
| `stage2_timeout` | a stage-2 query that takes over 1 s | skip `solver-undecided` after ≤ 1 s; a second check in the same LSP process issues no query | I10 |
| `eq_handwritten` | g3 | still **violated**, now with `predicate_eq_structural` | §3.5: the predicate means structural equality |
| `eq_derived` | g2 | unchanged: 1 proved, 1 violated | control |
| `opaque` | `@[opaque] fn inc`; `need(inc(1))` | skip `unreflectable-subject` as today | opt-out |
| `opaque_conflict` | `@[opaque] @[measure]` | `reflect_conflict` | — |
| `two_stage_identical` | every a1-c4 fixture | stage-1 VC text byte-identical to the baseline's (dump compared) | stage 1 is today |
| `spurious_refutation` | a caller whose stage-1 model gave a fresh call result a bad value, and the unfolding fixes it | proved, listed as a withdrawn violation if it was one | stage 2 before reporting |
| §9.1 rows marked (1) | — | as stated there | soundness |
| `parity` | every fixture's reflected functions | 0 mismatches; a deliberately broken `term_of_body` (arms swapped) gives a mismatch; a deliberately broken R5 (guarded matches allowed) makes `guarded` panic in the interpreter and the net reports it RED, not "not compared"; `h(n) = n + 1` at the maximum `Int` is reported `overflow?`, not as a mismatch | the net goes RED (C2, D8) |
| `budget` | `need(x : {Int \| _ == s40(0)})` where `s40(n) = f1(n) + … + f40(n)` and each `fi(n) = n`, called as `need(0)`: proving it needs 41 unfoldings | skip `reflect-budget`; with 20 terms, proved | the cap |
| `lsp_invalidate` | `app.march` calls `need_small(n)` under `if is_small(n)`; `is_small` lives in `util.march`. Edit it from `n < 10` to `n < 20` | before: proved (no diagnostic); after: `need_small` skipped (`refinement_unverified`), with no edit to `app.march`. Then a dependency lemma that stops proving: its caller's fact is withdrawn | §7.2, I8 |

**Oracle gate:** monotone (§6.2). Expected: no proved-to-skipped line at all; new
proofs only at sites whose frontier holds a reflected user function; no new violation unless it is
a finding; the timing budget of §6.3.
**Done means:** the RED table green; the monotone gate's three lists in the progress note with
every line explained; `ir-oracle` IDENTICAL (nothing here reaches code generation); the
reference's "Measures" section rewritten around reflection, with "Int is mathematical" (D8) stated
in it.

### Phase 2: lemmas

**Scope.** §4: `@[lemma]`, L1-L5 and `invalid_lemma`; closed `{Unit | P}` posts for lemmas;
the IH through `ih_spans`; static `assert` in lemmas (`Obligation.Assertion`); lemma-call facts
and `lemma_unproved_call`, with branch-local scope; `lemma_unproved`; a lemma `assert`
assumed only when proved (I5); erasure as a front-end pass on every path, independent of the
check and of z3 (§4.5, I6), and `lemma_argument_impure`; LSP: lemma calls in hover, the `uses:`
note, dependency-lemma admission in the LSP key.

**Files:** `refine_check.ml`, `refine_post.ml`, `obligation.ml`, `lib/desugar/lemma_erase.ml`
(new), `bin/main.ml`, `lib/jit/` (the REPL driver), `scripts/build-browser-repl.sh` and the
browser compiler entry, `forge/lib/cmd_test.ml`, `lsp/lib/analysis.ml`, `test/errors/`,
`specs/lang/errors/`.

**RED tests** (group `reflect-lemma`):

| Test | Program | Expected verdict | Reason |
|---|---|---|---|
| `len_cat` | §1's lemma; caller `need3(cat(a, b))` after `len_cat(a, b)` with `len(a) == 1`, `len(b) == 2` | lemma proved; call proved; without the lemma call: skip | lemma fact |
| `cat_nil` | §4.1 | proved | IH, structural |
| `cat_assoc`, `rev_cat`, `rev_rev` | §4.6 | all proved | lemmas calling lemmas, `assert` steps |
| `rev_rev_short` | `rev_rev` without the five `assert`s | `lemma_unproved` (skip `reflect-fuel`) | single unfolding |
| `pre_lemma` | `dbl(n) = n + n`; `@[lemma] fn nn(n : {Int \| _ >= 0}) : {Unit \| dbl(n) >= 0} do () end`; called with `k` unknown, then under `if k >= 0` | first: `lemma_unproved_call`, fact withheld (a following `need_nn(dbl(k))` skips); second: proved | hypotheses must be proved |
| `assert_static` | `@[lemma] fn l(xs : List(Int)) : {Unit \| cat(xs, Nil) == xs} do assert cat(xs, Nil) == xs  () end` (no recursion, so the assert is unprovable) | `Assertion` skip, and the post is **unproved**: removing the assert gives the same verdict, adding `cat_nil(xs)` before it makes both prove | static assert is not assumed (I5) |
| `lemma_scope` | `if c do cat_nil(xs) else () end`, then `need_eq(cat(xs, Nil), xs)` after the `if` | skip: the lemma fact does not leak out of the branch; inside the branch, proved | §4.4 scope |
| `ih_pre_unproved` | `@[lemma] fn l(n : {Int \| _ >= 0}) : {Unit \| dbl(n) >= 0}` recursing as `l(n - 2)` under `n != 0` | the recursive call's precondition fails at `n = 1`, so no IH; `lemma_unproved` | TERM rule (a) for lemmas |
| `l3_callee` | `@[lemma]` whose body calls `noisy(0)` | `invalid_lemma` (L3) | L3 |
| `stdlib_lemma_manifest` | (phase 3) a user program calling `List.len_append`; then the same with `stdlib/.lemmas.verified` edited to a wrong hash | first: admitted with no stage-2 query for the lemma; second: re-proved, and the manifest CI check fails | I10 |
| `assert_runtime` | the same `assert` in `main` | unchanged runtime assert, assumed after | D4 outside lemmas |
| `not_unit` | `@[lemma] fn l(x : Int) : Int` | `invalid_lemma` (L1) | — |
| `lemma_as_value` | `let f = cat_nil` | `invalid_lemma` (L5) | — |
| `erase_args` | `cat_nil(noisy_list())` | `lemma_argument_impure` | §4.5 |
| §9.1 rows marked (2) | — | as stated there | soundness |
| `erase_runtime` | a program printing results after lemma calls, interpreted and compiled | same output as the lemma-free program | erasure in both backends |

**Oracle gate:** monotone. No corpus fixture has a lemma, so: no move except phase 1's, and
`ir-oracle` IDENTICAL.
**Done means:** the table green; `specs/lang/refinement-types.md` gains "Lemmas" with §4.6 as its
example; `@[lemma]` in `known_fn_attributes`; the error pages seeded.

### Phase 3: the stdlib `List` set (D18)

**Scope.**
- No reflection change: `List.append`, `List.reverse`, `List.take` and `List.drop` are already
  reflected from phase 1 (§2.6). This phase ships what makes them **useful**: the lifts, the
  lemmas and the manifest below.
- **`reverse` and `take` lift their local `go`** into private top-level functions,
  `pfn reverse_onto(xs, acc)` and `pfn take_onto(xs, k, acc)`. A local is reflected (R1), but a
  lemma about it cannot be stated outside the function, and `reverse(reverse(xs)) == xs` needs
  the accumulator lemma `reverse_onto(xs, acc) == append(reverse(xs), acc)`. The lift is a pure
  refactor: same TRMC and inlining decisions. `ir-oracle` compares hashes and cannot ignore a
  rename, so it is expected to report exactly the fixtures that reach `reverse` or `take` as
  changed; those are checked by a one-off normalising diff (rename `reverse/go` and `take/go`'s
  emitted symbols to the new names in the baseline `.ll`, then compare the text), and by the `bench/list_ops.march` benchmark compiled at `--opt 2`.
- Lemmas shipped in `stdlib/list.march` (erased, so free at run time): `append_nil`,
  `append_assoc`, `len_append`, `reverse_onto_append`, `reverse_append`, `reverse_reverse`,
  `len_reverse`, `len_take`, `len_drop`, `take_drop` (`append(take(xs, n), drop(xs, n)) == xs`).
- The stdlib lemma manifest, `stdlib/.lemmas.verified`, its generating script and its CI
  staleness check (§8.1, I10), so user programs admit the shipped lemmas without re-proving them.
- **`filter` is not in this phase** (the D18 ruling below).
- A cheap substitute for `filter`'s most-wanted fact: a proved postcondition
  `len(_) <= len(xs)` added to its contract. Tier 2's structural IH proves it today; it is a
  contract, not reflection, so D10 is untouched.

**D18 ruling: `filter` moves to the function-value phase.** The options were:
- (a) a first-order specialisation now: for `List.filter(xs, fn x -> x > 0)`, build a
  specialised `filter$k(xs)` with the lambda's body inlined, and reflect that;
- (b) move `filter` to the phase that handles function values.

(a) **is** D10's later phase, built for one function: it needs a closed-lambda test, a
call-site name, a cache key over the lambda's body, capture rules, and the parity net over
specialisations. Building it inside phase 3 would ship that machinery without its own soundness
table. `filter` already has abstract refinements (`a[p]`, "filter keeps what its predicate
says") and the subset-of-`elts` contract, which cover the element facts users ask for. So
`filter` waits for phase 5, and phase 3 adds the length contract above.

**RED tests** (group `reflect-stdlib-list`):

| Test | Program | Expected verdict | Reason |
|---|---|---|---|
| `std_len_append` | user code: `List.len_append(a, b)` then `need3(List.append(a, b))` | proved | stdlib lemma |
| `std_reverse_reverse` | `List.reverse_reverse(xs)` then `need_eq(List.reverse(List.reverse(xs)), xs)` | proved | the accumulator lemma chain |
| `std_take_drop` | `List.take_drop(xs, n)` then `need_eq(List.append(List.take(xs, n), List.drop(xs, n)), xs)` | proved | — |
| `std_len_take` | `n >= 0`, `len(xs) >= n`: `need_len(List.take(xs, n), n)` after `List.len_take(xs, n)` | proved | Int and list together |
| `std_auto` | `need_eq(List.sum_int(Cons(2, Nil)), 2)`; and `List.map(xs, f)` in a predicate | `sum_int` is reflected with no annotation and the call proves; `map` reports R7 (a function value) | the stdlib is reflected automatically |
| `std_filter_len` | `need_le(List.filter(xs, p), len(xs))` | proved through the new contract | the substitute |
| `std_filter_not_reflected` | `{Unit \| List.filter(xs, p) == xs}` | `refinement_unchecked` (R7) | D10 |
| `std_lift_ir` | `--emit-llvm` of the corpus | `ir-oracle` changes only on fixtures reaching `reverse`/`take`; the normalising diff on those is empty | pure refactor |
| `std_parity` | every reflected stdlib function | 0 mismatches | §9.2 |

**Oracle gate:** monotone. Expected: new proofs only at sites that call a D18 function in the
frontier, now that the shipped lemmas are callable; the reflected-stdlib timing row of §6.3, unchanged from phase 1 apart from the lemma manifest.
**Done means:** the table green; the reference's "Lemmas" section gains the stdlib list with each
statement; the stdlib API docs regenerate.

### Phase 4: repeated unfolding (D13) and fuel (D14)

§3.8: depth-tagged frontier, the decided-guard test, default fuel 2, `@[reflect]` and
`@[reflect(fuel: N)]` (parser production, `grammar.js`, `known_fn_attributes`), `invalid_reflect`.

| Test | Program | Expected verdict | Reason |
|---|---|---|---|
| a6 | `need2(cat([1], [2]))` | proved (was `reflect-fuel`) | decided steps |
| `rev_rev_short` | phase 2's row | proved | decided steps replace the `assert`s |
| `undecided_stays` | `need(len(cat(xs, ys)) == …)` with `xs` unknown, no lemma | still `reflect-fuel` | only decided guards unfold |
| `fuel_override` | a 4-element literal through `cat` | skip at fuel 2; proved with `@[reflect(fuel: 5)]` | override |
| `fuel_cap` | `@[reflect(fuel: 9)]` | `invalid_reflect` | cap 8 |
| `reflect_assert` | `@[reflect]` on `noisy` | `invalid_reflect` naming `println` | assertion attribute |
| parser | `@[reflect(fuel: 3)]` parses; conflict count unchanged; tree-sitter green | — | grammar |

Oracle: monotone; timing within §6.3. Then measure Q1 (axiom tier against fuel-2 unfolding on the
measure tests).

### Phase 5: function values (D10)

Specialise per call site, as defunctionalisation does: a call `g(xs, fn x -> e)` where the
lambda is closed over reflectable terms gets a specialised logic function `g$k` with `e`
inlined. Then `List.filter` is reflected. Its own soundness table covers captures,
partial application, recursion through the value, and the parity net per specialisation.

### Phase 6: Int overflow (D8)

Decide the Int model for reflected bodies: either a 63-bit wrap encoding (bit-vectors or `mod`
arithmetic) for reflected arithmetic only, or an overflow obligation at every reflected `+ - *`
in the program. The `known_overflow` test flips. Bit operations can then join the R6 table.

### Phase 7: `--refine-infer` proposes lemma calls (D19)

At a skipped obligation whose stage-2 query failed with a recursive frontier term, propose a call
to an existing lemma whose post mentions that term, or offer a lemma skeleton. Every proposal is
checked before it is offered, as TERM phase 5 does for metrics.

---

## 11. Decisions

### 11.1 The user's decisions (binding, verbatim)

- **D1:** reflection is AUTOMATIC for every function that terminates, is pure and can't fail. There is no opt-in attribute. (I had recommended an explicit `@[reflect]`; the user chose automatic.)
- **D2:** `@[measure]` is MERGED into reflection. (I had recommended keeping it.)
- **D3:** a lemma is an ordinary function marked `@[lemma]` whose result type is a refined `Unit`, for example `{Unit | reverse(reverse(xs)) == xs}`. It is proved by recursion, using the termination induction hypothesis.
- **D4:** no new proof syntax in v1. Proofs are lemma calls plus `assert`.
- **D5:** lemmas may be called anywhere. Every lemma call is removed before code generation.
- **D6:** a function is reflectable only if it has a termination certificate (not trusted, not diverges), no side effects, no failure paths (panic, todo, possibly-zero division), and every `match` covers all cases.
- **D7:** `==` on a type whose Eq is hand-written somewhere in its structure is an opaque function. On primitives and fully derived Eq it is z3 equality.
- **D8:** Int is mathematical integers, as the checker already treats it, and the reference says so. Overflow obligations come in a later phase.
- **D9:** Float and String are opaque, except the string length measure.
- **D10:** a body that calls a function value is not reflectable in v1. A later phase specialises per call site, like the compiler's defunctionalisation.
- **D11:** a reflected body may call only reflected functions, measures and builtins with a z3 meaning. Any other callee makes the function unreflectable.
- **D12:** definitions reach z3 by unfolding once per call site: an equation guarded by the match, not a quantified axiom and not `define-fun-rec`.
- **D13:** repeated unfolding happens only when an argument's constructor or branch is already decided by the facts in scope.
- **D14:** the fuel limit defaults to 2 or 3 per obligation (the spec picks one with a reason), with a per-function override such as `@[reflect(fuel: N)]`. Reconcile that spelling with D1, where no `@[reflect]` is needed.
- **D15:** running out of fuel or time is a skip (unverified), and an error under `cap verified`.
- **D16:** comparing the solver's version of a function with the interpreter on random inputs is opt-in in `forge test`. The CI corpus always runs it.
- **D17:** the proof cache key includes a hash of each reflected body a proof depends on.
- **D18:** the first release reflects stdlib `List` append, reverse, filter, take and drop. Filter takes a function value, so square this with D10: either a first-order specialisation, or move filter to the later phase. Rule on it and say why.
- **D19:** `--refine-infer` proposes lemma calls only in a later phase.
- **D20:** phase 1 covers probes, then single unfolding, then lemmas. Repeated unfolding, function values and overflow come later.
- **D1 clarification (2026-10-29): the stdlib is included.** The stdlib is reflected automatically under exactly the same rules as user code. There is no opt-in list of stdlib functions; `@[opaque]` is the per-function opt-out.

### 11.2 How this design applies them (my rulings, each revisitable)

1. **D1:** automatic for user code, `MARCH_LIB_PATH` libraries and the stdlib alike, from
   phase 1 (§2.6, and the D1 clarification above). Visibility through the named blocker,
   `--reflect-report` and the `uses:` note (§2.4). `@[opaque]` is the opt-out (§2.5). D1's
   "every function" is read as every function with a fixed first-order definition: `impl`
   methods, actor handlers, `extern`s, `main`, lemmas and locals that capture variables have no
   such definition, so R1 leaves them out; `@[assume]` and `@[trusted]` functions have an
   unverified body, so R9 does.
2. **D2:** option A, `@[measure]` an exact synonym of `@[reflect]` that errors when the
   function is not reflectable (§5.2). Existing in-fragment measures keep their quantified axioms
   (the axiom tier, §5.3), so D2 moves no existing proof.
3. **D14:** default fuel **2** (§3.8). `@[reflect]` never enables reflection; it **asserts** it,
   and `@[reflect(fuel: N)]` also sets the fuel. That is how the spelling coexists with D1.
4. **D18:** `filter` moves to the function-value phase; phase 3 gives it a proved length
   contract instead (§10, phase 3).
5. **Two-stage discharge** (§4.4): stage 1 is today's query, so the monotone gate's
   proved-to-skipped rule holds by construction, and the cost falls only on today's non-proved
   share.
6. **§3.5 separates the two equalities (C3):** logical `=` in predicates (so generic lemmas are
   provable), program `==` in bodies (opaque where D7 says, and only for a total `eq`, C4). g3
   keeps its verdict and gains a warning.
7. **A lemma call whose precondition is unproved gives no fact** (§4.4), because erasure leaves
   no runtime check behind.
8. **Lemma-call arguments must be reflectable terms** (§4.5), so erasure removes no effect.
9. **`assert` inside a lemma is static** (`Obligation.Assertion`) and is assumed only when
   proved; outside a lemma it is today's runtime `assert`.
10. **Unfoldings are guarded by the callee's parameter refinements** (§3.6), because a metric
    certificate holds only on that domain.
11. **A match translates to one implication per arm, never a default arm** (§3.4), and R5 reads
    the guarded-match spans.
12. **Callees are matched by resolved identity, and predicate vocabulary cannot be a reflected
    user function's name** (R6, R11).
13. **Erasure is a front-end pass**, independent of the refinement check and of z3 (§4.5).
14. **A confirmed refutation that stage 2 proves is an internal error**, never a withdrawal
    (§4.4).
15. **Phase 1 refuses a hot patch whose `logic_hash` changed** (§7.2).

---

## 12. Review fixes

A fresh-context review of commit `a6d66d22a` found four critical holes (C1-C4), ten important
issues (I1-I10) and a set of minors. Every C and I item's probe or argument was checked; each
one held, and none was rejected. One line per finding:

| Finding | What changed | Where |
|---|---|---|
| C1. Reflection ignored the refined domain | Every guarded equation also carries `pre_f(args)`; an untranslatable parameter refinement blocks reflection (R8). Probe r1 re-run: `p` is `cert=metric`. REJECT `sound_domain` | §0.12 r1, F19, R2, R8, §3.6, §9.1, phase 0 `report_domain` |
| C2. R5 blind to guarded non-exhaustiveness | R5 reads `nonexhaustive_match_spans`; `term_of_body` uses one implication per arm and never a default; an interpreter failure in the parity net is RED. Probe r2 re-run: no diagnostic, run panics. REJECT `sound_guarded` | §0.12 r2, F20, R5, §3.4, §9.1, §9.2, phase 0 `report_guarded`, phase 1 `parity` |
| C3. `==` on `List(a)` broken under both readings | Chose **separate equalities**: logical `=` in predicates (keeps every lemma in §4.6 and phase 3 provable), program `==` in bodies (opaque per D7); lemma facts instantiated from the proved SMT term; g3 keeps its verdict with a `predicate_eq_structural` warning. REJECT `sound_eq_float` with a NaN case and a positive control | §0.7, F8, §3.3, §3.5, §6.2, §9.1, phase 1 `eq_handwritten`, §11.2 #6 |
| C4. D7 exception admitted an effectful or partial `eq` | The exception applies only when every reachable `impl Eq` passes R2-R7; otherwise `==` blocks. REJECT `sound_eq_effect` | R6, §2.3, §3.5, §9.1, phase 0 `report_eq_effect` |
| I1. Stdlib list contradicts D1 | Resolved by the user's D1 clarification: the stdlib is reflected automatically under the same rules, with `@[opaque]` as the per-function opt-out; the list idea is kept only as a "considered and rejected" note. Test `std_auto` | §2.6, §8.1, §6.3, phase 1 scope, phase 3, §11.1, §11.2 #1 |
| I2. Calling a lemma cost a function its reflection | Lemma calls are `()` in `term_of_body`; R6 admits lemma callees. Test `lemma_in_body` | R6, §3.4, phase 1 table |
| I3. Builtins matched by spelling | Callees matched by resolved identity; new R11 bars predicate-vocabulary names. Probe r3 re-run: user `len` prints 7, predicate `len(_) == 1` proved. REJECT `sound_shadow` | §0.12 r3, F21, R6, R11, §3.4, §9.1, phase 0 `report_shadow`, phase 0 todo |
| I4. Symbol naming not injective | Mangling `\|r:<origin>:<path>.<name>[/<local>#<line>:<col>]@<instance>\|`, quoted; a duplicate-definition internal error. REJECT `sound_mangle` | §3.1, §9.1 |
| I5. Unproved static `assert` could be assumed | A lemma `assert` is assumed only when proved; L2 allows `assert` explicitly. REJECT `sound_assert_false`; `assert_static` now shows the post depends on it | L2, §4.3, §9.1, phase 2 table |
| I6. Erasure tied to the check | Erasure is a front-end pass on every path (compile, interpreter, JIT, browser compiler, forge test, doctests), independent of the check, z3 and the CAS. REJECT `sound_erase_paths` with a determinism-oracle row | §4.5, §9.1, phase 2 scope and files |
| I7. Confirmed refutation "withdrawn" by stage 2 | Now the internal error `reflect_inconsistent`; only an unconfirmed refutation can be withdrawn. REJECT `sound_inconsistent` | §4.4, §6.2, §9.1 |
| I8. `uses:`, cache and LSP keys | The cache stores the unsat core; call-result facts are named; the LSP keys on the stage-2 frontier and on dependency lemmas' admission; the D17 hash includes the Eq status of types under `==`; golden `uses:` tests assert containment (z3 4.8.12 vs 4.16). REJECT `sound_uses_warm`; `lsp_invalidate` asserts before and after | §4.4, §7.1, §7.2, §9.1, phase 1 table |
| I9. HCR open while phase 1 ships | Phase 1 refuses a hot patch whose `logic_hash` changed, like a `sig_hash` change; Q4 now asks only whether to replace refusal by re-check. REJECT `sound_hcr` | §7.2, §9.1, Q4 |
| I10. Three missed cost loads | Stdlib lemmas admitted from a checked-in manifest instead of re-proved per program; stage 2 gets a 1 s timeout and an in-process negative cache; axiom-tier calls do not trigger stage 2; an LSP latency row. Tests `measure_tier`, `stage2_timeout`, `stdlib_lemma_manifest` | §4.4, §6.3, §8.1, phase 1-3 tables |
| Minor: breakdown not reproducible | `reflectable.py` made deterministic (sorted fixpoint, blocker chosen after it); three hash seeds give one MD5; tables re-measured (native 384, was 386, now excluding `main`) | §0.5 |
| Minor: §0.4 overclaim | Reworded: callers' VCs hold no body; a function's own post VC does change on a semantic edit (review: 274, 1 new) | §0.4 |
| Minor: counting method | `main` excluded; Float-in-signature counted (18, 21); captures, guarded matches and folded constants listed as unseen | §0.5 |
| Minor: Float contradictory | One rule: Float operations and `==` are opaque symbols in bodies; Float-containing types never get z3 `=` in bodies | §2.3, §3.5 |
| Minor: String literals | Distinct `$Str` constants, pairwise `distinct`, `$strlen` fixed | §2.3 |
| Minor: fuel could not be lowered | Fuel is read per term from its function; `1 <= N <= 8`; `fuel: 0` is `@[opaque]`'s job | §3.8 |
| Minor: ir-oracle "modulo names" | `ir-oracle` expected to flag the renamed fixtures; a one-off normalising diff checks them | phase 3 scope, `std_lift_ir` |
| Minor: vague rows | `reflect-fuel` given an operational definition; `budget`, `lsp_invalidate`, `assert_static` made concrete | §3.9, phase 1-2 tables |
| Minor: missing REJECT controls | `report_trusted_nonrec` (R9), `lemma_scope`, `ih_pre_unproved`, transitive D7 in `sound_eq`, `l3_callee` (L3) | phase 0-2 tables, §9.1 |
| Minor: D8 under D1 | The parity net draws boundary `Int`s and reports `overflow?`; §9.3 says detection, not prevention | §9.2, §9.3 |
| Minor: LH gaps | Abstract-refinement parameters, `impl` method reflection and quantified posts listed as out of scope | §9.3 |
| Minor: refutable `let` patterns | Removed from R5; probe r4 shows they are a syntax error | §0.12 r4, F22, R5 |

No minor was left unfixed. The review's "not checked" list is unchanged in scope: TERM's
dispatch edges for `==`, `show` and interpolation are taken from its phase-3 note (F12); the
z3-version core difference is handled by the containment rule above; and the built-in `Eq` has no
separately overridable `ne` (`typecheck_builtins.ml:502-504`), so `!=` is `not eq`.

---

## 13. New open questions

The decisions above do not settle these. Each has a recommendation.

- **Q1. Do axiom-tier measures ever move to unfolding?** D12 and D2 together suggest one
  encoding. **Recommended:** keep the axiom tier until phase 4 can run the measure test groups and
  the corpus with measures unfolded at fuel 2, under the monotone gate. Move only if nothing goes
  from proved to skipped and timing is within budget. Until then the two tiers coexist (§5.3).
- **Q2. In what order are stdlib lemmas added after phase 3?** Phase 3 ships `List`'s. Every
  other reflected stdlib function is already usable in predicates, but proofs about recursive
  ones need lemmas. **Recommended:** one PR per module, ordered by how often user predicates in
  the corpus mention the module (measured by `--refine-report-sites=all`), each with its
  manifest entries and the parity net; `Option`, `Result` and the first-order parts of `Map`
  first.
- **Q3. Should `@[reflect]` (bare) exist?** It asserts reflection, which D1 makes automatic, and
  `@[measure]` already does the same under option A. **Recommended:** yes, as the canonical
  spelling, because `@[reflect(fuel: N)]` needs the name anyway and a non-measure function
  (`is_small`) reads oddly as `@[measure]`. Revisit option B (deprecate `@[measure]`) once
  `@[reflect]` has shipped in a release.
- **Q4. Hot code reload of a reflected body.** Phase 1 refuses such a patch (§7.2). The open
  question is only whether to replace the refusal with a re-check. **Recommended:** `forge deploy --hot` re-runs `--check` over the whole
  program when any changed function's `logic_hash` differs, and refuses the patch on a new
  violation or a lost proof. A patch to an `@[opaque]` function needs no re-check.
- **Q5. A body's `==` on a type variable.** §3.5 makes it opaque in bodies, which blocks
  reflecting generic membership (`List.member`); predicates are unaffected. **Recommended:** later, allow z3 equality on `Elem` inside a generic
  function with an obligation at each instantiation that the instance's `Eq` is fully derived.
  Not in v1.
- **Q6. Should `assert` in ordinary code also be proved statically when it can be?**
  **Recommended:** report it (a `proved` assert can be erased at `--opt 2` in a later PR), but do
  not change its runtime meaning in this design.
- **Q7. Local functions in lemmas.** R1 reflects a closed local `fn` (`reverse/go`), but no lemma
  can name it. Phase 3 lifts the stdlib's two. **Recommended:** a `--reflect-report` note
  "reflected local `f/go` cannot be named in a lemma; lift it to a `pfn`" and no new syntax.
- **Q8. Ground evaluation by the interpreter.** A call whose arguments are all ground (`cat([1],
  [2])`) could be evaluated by the witness interpreter and asserted as one equation, instead of
  unfolding step by step. It is fast and exact, but it puts the interpreter inside the trusted
  base. **Recommended:** not in the logic. Use it only in the parity net (§9.2), and let phase 4's
  decided unfolding handle ground terms.
- **Q9. Records with a hand-written `Eq` on one field type.** D7 says "hand-written somewhere in
  its structure"; §3.5 reads that as "any type reachable through fields". **Recommended:** that
  reading, computed once per type with a fixpoint over the type graph, and printed by
  `--reflect-report` for each type used with `==`.
- **Q10. The 32-unfolding cap and fuel 2 are guesses before phase 1's measurements.**
  **Recommended:** phase 1's progress note reports the distribution of frontier sizes over the
  corpus, and the cap is set at the 99th percentile times two, rounded up to a power of two.
