# Typing corpus index (t01–t20 accept, t01–t15 reject)

Navigable map of the Core March **static-semantics** conformance corpus: each
program in this directory (`specs/lang/types/accept/*.march`,
`specs/lang/types/reject/*.march`) to the typing rule(s) it anchors in
`specs/lang/core-march-types.md`. See that document's §3 for the full
per-program prose and §4 for the accumulated findings each `reject/` witness
sometimes doubles as evidence for.

## The `--check` accept/reject harness model

Unlike the operational golden corpus (`specs/lang/golden/`, which runs each
program through BOTH the interpreter and the compiled backend and diffs their
output — there is something to differentially compare), March has only **one**
typechecker: it runs identically before both `eval` and `--compile`. So this
corpus's anchor is the compiler's own `--check` mode instead of a diff:

- **`accept/*.march`** — must typecheck: `march --check file.march` must exit
  **0**.
- **`reject/*.march`** — must be rejected: `march --check file.march` must exit
  **1**, AND its `--check` stderr/stdout output must contain the exact
  substring named in the program's own first-line annotation,
  `-- EXPECT-ERROR: <substring>`. Pinning the substring (not just "rejected
  somehow") catches a typechecker regression that rejects the program for the
  WRONG reason as well as one that stops rejecting it at all.

Run the whole corpus:

```
dune build bin/main.exe
MARCH_BIN=$PWD/_build/default/bin/main.exe specs/lang/types/check_types.sh
```

Exit 0 iff every program behaves as declared (currently 35/35 — 20 accept, 15
reject). See `specs/lang/core-march-types.md` §3 for the harness's full
description and the invariant it protects (a spec that misdescribes the
typechecker, AND a real typechecker regression, both show up as a harness
failure).

**CI:** this harness is wired into its own `types-check` dune alias — a
*separate, slow, opt-in* lane, deliberately not part of the default
`@runtest`/`@oracle` sweeps (`reject/` programs deliberately fail to
typecheck, so they cannot ride the operational side's both-ways
interpret-vs-compile oracle the way `specs/lang/golden/` does — see the
"Why not `@oracle`" note at the bottom of this file). Run it directly with
`dune build @types-check` (from `test/`, or `dune build test/@types-check`
from the repo root) or as part of the CI workflow's dedicated step.

## Provenance

| Range | Task | Constructs added |
|---|---|---|
| `accept/t01`–`t04` | walking-skeleton v0 | literals, lambda/application, `let`-polymorphism, `if` |
| `reject/t01`–`t04` | walking-skeleton v0 | unify mismatch, unbound var, T-App arity, `if`-branch mismatch |
| `accept/t05`–`t07`, `reject/t05`–`t06` | Task 1 | ADT constructors + `match` (T-Con, T-Match, P-Con) |
| `accept/t08`–`t10`, `reject/t07`–`t09` | Task 2 | tuples + records (T-Tuple, T-Record, T-Field, T-Update, P-Tuple) |
| `accept/t11`–`t12` | Task 3 | atoms (T-Atom-0, T-Atom-N, P-Atom) |
| `accept/t13`–`t15`, `reject/t10`–`t11` | Task 4 | match guards (T-Guard), scrutinee-less `match do` (T-Cond); pattern-typing relation completed |
| `accept/t16`–`t17`, `reject/t12` | Task 5 | local recursive functions (T-LetFn) |
| `accept/t18`–`t20`, `reject/t13`–`t15` | Task 6 | interface-constraint model (T-Discharge, §2.1/§2.1a/§2.1b), boolean primitives |
| — | Task 7 | no new programs — consolidation + this INDEX + CI wiring only |

## `accept/` — must typecheck

| Program | Anchors | Notes |
|---|---|---|
| `t01_literals` | T-Lit (Int/Bool/String) | |
| `t02_lambda_app` | T-Abs, T-App, annotated `Int -> Int` param | |
| `t03_let_poly` | **T-Let generalization** — a local `id = fn x -> x` used at both `Int` and `String` | proves let-polymorphism (§4.1 finding 1) |
| `t04_if` | T-If (Bool cond, matching branches) | |
| `t05_adt_construct_match` | T-Con + T-Match — a 2-ctor ADT (`Hue = Rood \| Bloo`) constructed and matched exhaustively | |
| `t06_payload_ctor_branch` | P-Con — a payload-carrying ctor (`Circle(Int)`) bound to a pattern var in a branch | |
| `t07_generic_option_two_types` | T-Con/P-Con with a fresh instantiation per occurrence — `Box(a) = Full(a) \| Vacant` used at both `Int` and `String` | §4.1 finding 4 witness |
| `t08_tuple_construct_destructure` | T-Tuple + P-Tuple — a tuple built and destructured by both a `match` and a function-arg `PatTuple` | |
| `t09_record_literal_field` | T-Record + T-Field — a record literal (`{ x: 1, y: 2 }`) with both fields read via `EField` | |
| `t10_record_update_existing_field` | T-Update — `{ p with x: 100 }` on an existing field, result type unchanged | |
| `t11_atom_nullary_eq_match` | T-Atom-0 + P-Atom — a nullary `:ok` returned, compared via `==`, matched by a nullary `PatAtom` | |
| `t12_atom_payload_and_name_erasure` | T-Atom-N + P-Atom — payload atom `:count(n+1)` matched with payload bound, plus two differently-tagged nullary atoms proving name-erasure | §4.1 finding 8 witness |
| `t13_match_guard` | (T-Guard) — three `when`-guarded `PatVar` arms, guard checked against `Bool` in the pattern-extended env | |
| `t14_nonexhaustive_match_still_typechecks` | **(T-Match: Exhaustiveness) — the brittleness witness** — a 2-ctor ADT `match` covering only ONE ctor | exhaustiveness is a Warning, not an Error — §4.1 finding 9 |
| `t15_econd_chain` | (T-Cond) — a 3-arm `match do` boolean chain, all conditions `Bool`, all bodies `String` | |
| `t16_letfn_factorial` | (T-LetFn) — a local self-recursive `fn go(k, acc)` (factorial), monomorphic inside its own body | |
| `t17_letfn_generalized_after_block` | **(T-LetFn) generalization** — a local `fn id_rec(x)` used at both `Int` and `String` in the REST of the block | §4.1 finding 13 witness |
| `t18_num_constraint_discharged` | (δT-Add, T-Discharge) — `1 + 2` (Int) and `1.0 +. 2.0` (Float) both discharge cleanly | |
| `t19_eq_ord_constraint_discharged` | (δT-Eq, δT-Ord, T-Discharge) — `x == y` and `x < y` on two `Int`s discharge against built-in instances | |
| `t20_bool_ops` | (δT-And, δT-Or, δT-Not) — `&&`/`\|\|`/`not` over `Bool`-typed comparisons | |

## `reject/` — must be rejected (exit 1 + pinned substring)

| Program | Anchors | `EXPECT-ERROR` substring |
|---|---|---|
| `t01_int_vs_string` | unification mismatch | `` expected `Int` but got `String` `` |
| `t02_unbound_var` | T-Var, `x ∉ Γ` | `` I cannot find `undefined_var` `` |
| `t03_arity` | T-App arity (no partial application) | `expects 1 argument, but got 2` |
| `t04_if_branch_mismatch` | T-If branch unification | `Both branches of an if expression must return the same type` |
| `t05_ctor_arity` | T-Con arity (`ECon` arm) | `` Constructor `Circle` expects 1 argument(s) but I got 2. `` |
| `t06_match_branch_mismatch` | T-Match branch-body unification | `All branches of a match must have the same type.` |
| `t07_field_missing` | T-Field "no such field" (`EField` arm) | `` This record does not have a field called `z`. `` |
| `t08_tuple_arity_mismatch` | T-Tuple/unify length mismatch, via a `(Int,Int)`-annotated param checked against a 3-tuple | `` expected `(Int, Int)` but got `(Int, Int, Int)`. `` |
| `t09_record_update_missing_field` | T-Update "no such field" (concrete-`TRecord` base) | `` This record does not have a field called `z`. `` |
| `t10_guard_not_bool` | (T-Guard) non-Bool guard (`n when n + 1 -> …`) | `Match guards must be Bool.` |
| `t11_econd_condition_not_bool` | (T-Cond) non-Bool condition (bare `n -> …` where `n : Int`) | `` Each condition in `match do` must be Bool. `` |
| `t12_letfn_ret_annot_conflict` | (T-LetFn) declared return-type annotation (`fn go(k) : Int`) conflicts with the self-consistent inferred `String` body | `` expected `Int` but got `String` `` |
| `t13_num_no_impl_string` | (T-Discharge, `CNum`) — `x + y` on two agreeing `String`s, violating `+`'s own `Num` obligation at the enclosing `fn`'s discharge point | `String does not implement Num (only Int and Float do)` |
| `t14_ord_no_impl_adt` | (T-Discharge, `CInterface "Ord"`) — `a < b` on a bare 2-ctor ADT with no `impl Ord` | `` `Hue` does not implement interface `Ord` `` |
| `t15_and_non_bool_operand` | (δT-And) — `1 && true`, an `Int` operand against `&&`'s fixed `Bool → Bool → Bool` | `March does not coerce Int to Bool` |

**Result: 35 / 35 (20 accept, 15 reject).**

## Coverage notes (deliberately absent programs, and why)

- **No atom-specific `reject/` program.** Every `EAtom`/`PatAtom` occurrence
  synthesizes the single bare `Atom` type (T-Atom-0/T-Atom-N, P-Atom) — there
  is no per-tag/per-arity typing distinction to violate, so atoms cannot
  originate a type error in isolation (a payload sub-expression error, e.g.
  `:count(1 + "x")`, comes from `+`'s own `Num` constraint, already covered).
  See `core-march-types.md` §3.
- **No polymorphic-recursion `reject/` program.** Verified live during Task 5
  (a local `fn go(x)` recursively calling itself at `Int` then `String`
  fails), but not committed as a corpus program — it would restate
  `reject/t01`'s ordinary T-App mismatch shape rather than add new coverage.
  See `core-march-types.md` §2 (T-LetFn).
- **No `reject/` program for finding 15 (the `when Iface(a)` constraint-
    survival gap) or finding 16 (the `let`-annotation-ignored gap).** Both are
  real, filed typechecker gaps (`specs/todos.md`, "Compiler: Type System") —
  but a `reject/` program encoding either would assert a behavior this
  document identifies as WRONG (the program currently, incorrectly,
  typechecks), which would defeat the corpus's purpose of pinning CORRECT
  behavior. Once each is fixed, a `reject/` witness should be added here (see
  `core-march-types.md` §4.1, findings 15–16, for the exact repros to convert).
- **No exhaustiveness/redundancy `reject/` program.** Both are Warnings, never
  Errors (`--check`'s exit code filters strictly on `severity = Error`), so a
  non-exhaustive/redundant `match` can never produce a passing `reject/`
  program under this harness — `accept/t14_nonexhaustive_match_still_
  typechecks` is the (correct) witness that this is so. See
  `core-march-types.md` §2 "Exhaustiveness and redundancy" and §4.1 finding 9.

## Why not `@oracle`? (the harness-model difference from the golden corpus)

`specs/lang/golden/` rides `test/test_oracle.ml`'s both-ways
interpret-vs-compile sweep (see that directory's own `INDEX.md`) because every
golden program **runs** and produces comparable stdout on both backends. This
corpus is structurally different: every program here is `--check`-only, and
**`reject/` programs are deliberately malformed — they are SUPPOSED to fail to
typecheck.** Feeding a `reject/` program into the oracle's interpret-vs-compile
sweep would make it indistinguishable from an ordinary compile failure (a
regression the oracle is built to catch), not a correctly-rejected program —
there is no "expected output" to diff against for a program that must not run
at all. That is why this corpus needs its own harness (`check_types.sh`,
keyed on `--check`'s exit code plus a pinned error substring) and its own CI
lane (`types-check`, see `specs/lang/core-march-types.md` §5/§6) rather than
extending `@oracle`'s sweep.
