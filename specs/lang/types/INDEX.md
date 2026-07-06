# Typing corpus index (t01–t31 accept, t01–t25 reject)

Navigable map of the Core March **static-semantics** conformance corpus: each
program in this directory (`specs/lang/types/accept/*.march`,
`specs/lang/types/reject/*.march`) to the typing rule(s) it anchors in
`specs/lang/core-march-types.md`. See that document's §3 for the full
per-program prose and §4 for the accumulated findings each `reject/` witness
sometimes doubles as evidence for.

**Note (`t27`–`t28`):** these two `accept/` programs anchor **operational**
(runtime method-DISPATCH) rules in `core-march.md` §4.4.2, not typing rules in
`core-march-types.md` — they ride this same `--check`-plus-run harness because
they are, first, ordinary well-typed programs (the `--check` half of the
corpus model still applies), and the harness has no separate "run and check
the printed value" lane of its own. Their expected VALUE (not just exit code)
is documented in their own table row below and re-verified by running them
interpreted, not only `--check`ing them.

**Note (`t29`–`t30`):** these anchor `core-march-types.md` §2.4 (`derive`/
`satisfy` as `DImpl` GENERATORS, a typing/desugar-time concern) — `t29` is
also a run-value witness for `core-march.md` §4.4.4 (derive-generated impls
dispatch through the identical rules as hand-written ones), same
dual-purpose pattern as `t27`–`t28` above.

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

Exit 0 iff every program behaves as declared (currently 56/56 — 31 accept, 25
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
| `accept/t21`–`t22`, `reject/t16`–`t17` | Typechecker fixes (2026-07-05) | witnesses for findings 16 (`f0f5299c`, let-annotation enforcement), 15 (`8cbd6dd2`, generic `when`-constraint re-check), and 13 (`7e40dc5b`, ELetFn diagnostic dedup — pins `reject/t12` at one diagnostic, no new program) |
| `accept/t23`–`t25`, `reject/t18`–`t21` | Widening slice 1, Task 1 (2026-07-06) | user-defined `interface`/`impl` DECLARATION checking (§2.3: `(T-Interface)` registration, `(T-Impl)`'s ordered checks — missing/extra-method, signature-match, unknown-interface — and default methods) |
| `accept/t26`, `reject/t22` | Widening slice 1, Task 2 (2026-07-06) | superclass/`requires` and `when`-clause discharge (mandatory enforcement, §2.3), the `impl_matches_ty` structural-match judgment named as its own rule, `(T-ImplMatch)` |
| `accept/t27`–`t28` | Widening slice 1, Task 3 (2026-07-06) | method-DISPATCH operational rules (`core-march.md` §4.4.2, not `core-march-types.md`): the four-name `impl_tbl` type-directed lookup for `Show`/`Eq`/`Ord`/`Hash`, and ordinary lexical `env`-binding dispatch for user-defined interfaces |
| — | Widening slice 1, Task 4 (2026-07-06) | no new programs — coherence/overlap is a runtime interp-vs-compiled DIVERGENCE (`core-march.md` §4.4.3), which a single-`--check`-invocation harness cannot witness; documented in prose + filed in `specs/todos.md` instead |
| `accept/t29`–`t30`, `reject/t23`–`t24` | Widening slice 1, Task 5 (2026-07-06) | `derive`/`satisfy` as `DImpl` GENERATORS (§2.4): the closed five-interface `derive` set + `Json`'s `JsonTo`/`JsonFrom` pseudo-interface special case, `satisfy`'s name-matching all-or-nothing wiring, and the filed `derive X for UnknownType` silent-no-op gap (§4.1 finding 17) |
| `accept/t31`, `reject/t25` | Widening slice 2, Task 1 (2026-07-06) | cross-module **visibility fix** — `load_module_into_env`'s `ex_public` gate for `ExFn`/`ExValue` (a private `pfn`/value is no longer callable cross-module: `reject/t25` pins `is private to module \`Array\``); the ACCEPT side proves the gate is narrow — a PUBLIC cross-module call still resolves and the OPAQUE-TYPE pattern (a private `ptype`'s bare name usable in a cross-module annotation, `ExType`/`ExRecord` left ungated) still holds (`accept/t31`) |

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
| `t21_let_annot_ok` | **(T-Let annotation, finding 16 fix)** — a correct `let x : Int = 5` and a polymorphic RHS bound at a more specific instance (`let f : (Int) -> Int = fn n -> n`) both typecheck | |
| `t22_generic_when_constraint_satisfied` | **(T-Discharge via instantiate, finding 15 fix)** — a generic `when Ord(a)`/`when Eq(a)` bound SATISFIED at the call site (Int/String) still typechecks | |
| `t23_interface_impl_basic` | (T-Interface), (T-Impl) — a minimal user-declared `interface Speak(a) do fn speak : a -> String end` + `impl Speak(Dog)` providing exactly `speak` | run-witnessed: prints `"Rex"` |
| `t24_interface_impl_generic_head` | (T-Impl), `impl_matches_ty` wildcard semantics — a generic/parameterized impl head `impl Describe(Box(a))`, used at both `Box(Int)` and `Box(String)` | |
| `t25_interface_default_method` | **(T-Impl) default methods** — an interface method with a default body, omitted by the impl; `inject_defaults` (desugar) splices the default in before typecheck ever sees the impl, so no missing-method error fires | run-witnessed: `greeting(Cat("Tom"))` prints `42` (the default, not a value the impl ever defined) |
| `t26_impl_superclass_satisfied` | **(T-Impl) superclass discharge** — `interface Greet(a) requires Speak(a)`, with `impl Speak(Dog)` declared before `impl Greet(Dog)` | run-witnessed: prints `"Hello, Rex"` — the bound SATISFIED |
| `t27_user_iface_lexical_dispatch` | **operational (`core-march.md` §4.4.2, E-DImpl)** — a user `interface Speak(a)` + one `impl Speak(Dog)`; `speak(Dog("Rex"))` resolves via ORDINARY lexical `env` binding, not a type-directed table | run-witnessed: prints `"Rex says Woof"` |
| `t28_derive_impl_tbl_dispatch` | **operational (`core-march.md` §4.4.2, E-Dispatch-Builtin)** — `derive Show, Eq for Color`; `show(Red)`/`Green == Green`/`Red == Blue` all dispatch through the runtime `impl_tbl` hashtable keyed `(iface, type_name)` on the argument's dynamic type | run-witnessed: prints `Red` / `true` / `false` |
| `t29_derive_eq_show` | **(§2.4) `derive` as a `DImpl` generator** — `derive Eq, Show for Color` expands (desugar-time) into ordinary `impl Eq(Color)`/`impl Show(Color)` blocks, indistinguishable from hand-written ones; also a run-value witness for `core-march.md` §4.4.4 (derive-generated impls dispatch through the SAME `impl_tbl` rule as §4.4.2) | run-witnessed: prints `Red` / `true` / `false` |
| `t30_satisfy_wiring` | **(§2.4) `satisfy` as a `DImpl` generator** — `satisfy Named for Person` wires an EXISTING top-level `fn name` to `interface Named(a)`'s one method purely by name match, no `impl` block written | run-witnessed: prints `"Ada"` |
| `t31_cross_module_public_and_opaque_ptype` | **module visibility — the ACCEPT side (slice 2, Task 1)** — a PUBLIC cross-module call (`Array.length(Array.empty())`) still resolves, AND a private `ptype`'s bare type NAME (`ConsistentHash.HashRing(String)`) is still usable as a cross-module param annotation (the opaque-type pattern; `ExType`/`ExRecord` left ungated). Witnesses the narrowness of the `ExFn`/`ExValue` gate that `reject/t25` exercises | run-witnessed: exit 0, `length(empty()) == 0` |

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
| `t16_let_annot_mismatch` | **(T-Let annotation, finding 16 fix)** — `let x : Int = "foo"` now rejects (the annotation is a checking context for the RHS) | `` expected `Int` but got `String`. `` |
| `t17_generic_when_constraint_unsatisfied` | **(T-Discharge via instantiate, finding 15 fix)** — `same(Rood, Rood)` with `fn same(a, b) when Eq(a)` on a no-`Eq` ADT now rejects | `` `Hue` does not implement interface `Eq`. `` |
| `t18_impl_missing_method` | (T-Impl) missing required method — an interface with two methods, an impl providing only one (no default on the omitted one) | `` Missing method `greet` in `impl Speak(Dog)`. `` |
| `t19_impl_extra_method` | (T-Impl) extra undeclared method — an impl provides a method the interface never listed | `` Interface `Speak` does not declare a method `bark`. `` |
| `t20_impl_signature_mismatch` | (T-Impl) signature-match — a provided method's inferred body type disagrees with the interface's declared signature | `` `speak` in `impl Speak` must match the interface signature `` |
| `t21_impl_unknown_interface` | (T-Impl) interface-existence — `impl` of an interface name never declared with `interface` | `` Unknown interface `NotDeclared` — is it declared above this impl? `` |
| `t22_impl_superclass_unsatisfied` | **(T-Impl) superclass discharge, unsatisfied** — `interface Greet(a) requires Speak(a)`, `impl Greet(Dog)` declared with no `impl Speak(Dog)` anywhere in scope — mandatory rejection, not a conditional gap | `` Cannot implement `Greet(Dog)`: required superclass `Speak(Dog)` is not satisfied. `` |
| `t23_derive_unknown_interface` | (§2.4) `derive` targets a CLOSED five-interface set — `derive Frobnicate for Color`, an interface name outside `{Eq, Show, Hash, Ord, Json}` | `` Unknown derive target `Frobnicate` for type `Color`. `` |
| `t24_satisfy_missing_function` | (§2.4) `satisfy` all-or-nothing — `satisfy Named for Person` where no top-level `fn name` exists anywhere in the module | `` satisfy Named for Person: no function `name` found in scope. `` |
| `t25_cross_module_private_fn` | **module visibility — the REJECT side (slice 2, Task 1)** — `Array.lst_rev(...)`, a real private `pfn` (stdlib/array.march:39), is no longer callable by qualification from unrelated code; `load_module_into_env`'s new `ex_public` gate for `ExFn`/`ExValue` makes the qualified lookup miss, so `qualified_error_msg` reports the private-access message (the same shape the `ExCtor` gate already produced for private constructors) | `` is private to module `Array` `` |

**Result: 56 / 56 (31 accept, 25 reject).**

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
- **No `reject/` program for a duplicate `interface` declaration or an
  interface method that never mentions its own type parameter.** Both are
  real gaps in the `(T-Interface)` arm (§2.3): a second `interface Speak(a)`
  in the same module silently replaces the first in `env.interfaces`
  (ordinary `StrMap.add`, no "already declared" check), and a method signature
  like `fn bar : Int -> Int` inside `interface Foo(a) do ... end` — which never
  uses `a` at all — still typechecks with `CInterface(Foo, a)` attached to an
  otherwise-free variable. Neither is committed as a corpus program: both are
  narrow, low-value-to-pin edge cases (flagged, not fixed, in this task) rather
  than confirmed regressions worth a dedicated `reject/` witness. See
  `core-march-types.md` §2.3.
- **No coherence/overlap corpus entry here.** Two impls of the same interface
  for the same type both typecheck with no diagnostic (`env.impls`'s
  "insert-only, search by structural match" registration shape, §2.3 item 1) —
  this is a genuine divergence between the interpreter and compiled backends
  at RUNTIME, not a `--check`-time accept/reject distinction, so it cannot be
  encoded in this harness at all (a `--check` program cannot witness an
  interp-vs-compiled split). Documented and filed as its own task's subject
  (`core-march.md`'s dispatch/coherence section, `specs/todos.md`).
- **No `reject/` program for a multi-argument superclass or `when` constraint.**
  Both the superclass-discharge and `when`-clause-discharge steps (§2.3,
  typecheck.ml:7086–7103, 7118–7143) only handle a single-argument constrained
  type (`| [ty] -> ... | _ -> ()`); a hypothetical multi-argument constraint
  would silently skip the check. Not committed as a corpus program because
  March's interface grammar only supports one type parameter per interface
  (`parser.mly:769-786`), so no `interface`/`impl`/`requires`/`when` surface
  syntax the parser accepts can actually produce a multi-argument constraint
  today — the branch is very likely dead code, not a live, reachable gap.
- **No `reject/` program for `derive X for UnknownType`.** A real, filed gap
  (`specs/todos.md`, "Compiler: Type System"; `core-march-types.md` §4.1
  finding 17): `derive Eq for Ghost`, where `Ghost` is never defined, silently
  no-ops (exit 0, no diagnostic) instead of rejecting — `expand_derive`'s
  `None` branch (`desugar.ml:1659`) returns `[]` with no `Err.error` call. Not
  committed as a `reject/` program for the same reason findings 15–16 aren't:
  it would assert behavior this document identifies as WRONG. See
  `core-march-types.md` §2.4 and §4.1 finding 17 for the exact repro to
  convert once fixed.

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
