# Golden corpus index (g01–g34)

Navigable map of the Core March golden conformance corpus: each program in this
directory (`specs/lang/golden/*.march`) to the construct(s) and operational
rule(s) it anchors in `specs/lang/core-march.md`. Every program is verified to
produce **identical output interpreted and compiled** — run the whole corpus
with `specs/lang/golden/verify.sh` (34/34 MATCH, exit 0). See §5 of
`core-march.md` for the full per-program prose (divergences found and routed
around, expected output, guardrails).

Provenance: `g01`–`g08` are the walking-skeleton's original corpus; `g09`–`g13`
Task 1; `g14`–`g16` Task 2; `g17`–`g20` Task 3; `g21`–`g23` Task 4; `g24`–`g27`
Task 5; `g28`–`g30` Task 6; `g31`–`g32` Task 7; `g33` post-Phase-1 corpus
widening after the concurrent `float_to_string` backend-unification fix landed.

| Program | Construct anchored | Rule(s) in core-march.md §4 |
|---|---|---|
| `g01_let_arith` | block `let`, `Int`, `+` | E-Blk-Let (§4.2), δ-Add-I (§4.4) |
| `g02_lambda_app` | lambda + application | E-Lam, E-App-Clo (§4.2) |
| `g03_bool_eq` | `Bool`, `==` | δ-Eq-I / δ-Eq-B (§4.4) |
| `g04_adt_match` | 2-ctor ADT, `match`, payload-free `PatCon` | E-Match (§4.2), match(PatCon …) (§4.3) |
| `g05_adt_payload` | ADT payload, `PatCon C [x]` binding | E-Con (§4.2), match(PatCon C [p…], VCon …) (§4.3) |
| `g06_hof` | higher-order function (closure passed as arg) | E-Lam, E-App-Clo (§4.2) |
| `g07_match_lit` | `PatLit` + `PatWild`, first-match-wins | match(PatLit …), match(PatWild …) (§4.3); branch-selection (§4.3) |
| `g08_nested_let_shadow` | nested block + `let` shadowing | E-Blk-Let (§4.2), assoc-list first-occurrence lookup (§4.1) |
| `g09_literals` | `LitFloat`/`LitString`/`LitAtom` (via `EAtom`) + atom `==` | E-Lit, E-Atom-0 (§4.2); δ-Eq-* (§4.4); match(PatLit …) (§4.3) |
| `g10_arithmetic` | `-`,`*`,`/`,`%`, truncating `/`/`%`, unary `negate`, Float `-`/`*` | δ-Sub/Mul/Div/Mod-I, δ-Neg-I, δ-Sub-F/δ-Mul-F (§4.4) |
| `g11_comparison` | `!=`,`<`,`<=`,`>`,`>=` on Int/Float/String | δ-Neq/Lt/Le/Gt/Ge-* (§4.4) |
| `g12_bool_ops` | `&&`,`\|\|`,`!`/`not`, `++` | δ-And, δ-Or, δ-Not, δ-Concat (§4.4) |
| `g13_strict_bool` | `&&`/`\|\|` **strictness** (rhs side effect fires) | §4.4.1 (strict, not short-circuiting); E-App-Prim (§4.2) |
| `g14_tuple_let` | `ETuple` construction, `PatTuple` in a block `let` | E-Tuple (§4.2), match(PatTuple, VTuple) (§4.3) |
| `g15_tuple_match` | `PatTuple` as a `match` branch, alongside a literal-tuple pattern | E-Match (§4.2), match(PatTuple …) + branch-selection (§4.3) |
| `g16_tuple_nested` | nested `ETuple` destructured by nested `PatTuple` in a `match` | E-Tuple (§4.2), match(PatTuple …) via match_list recursion (§4.3) |
| `g17_record_literal_field` | `ERecord` construction + `EField` access (left-to-right field eval) | E-Record, E-Field (§4.2) |
| `g18_record_update` | `ERecordUpdate` on an existing field (functional/persistent) | E-Update (§4.2), §4.2.1 |
| `g19_record_update_multi_field` | `ERecordUpdate` naming multiple existing fields | E-Update, E-Field (§4.2) |
| `g20_record_nested` | record nested in a record field, chained `EField`/`ERecordUpdate` | E-Field, E-Update (§4.2) |
| `g21_atom_match` | nullary `EAtom`/`VAtom` matched against nullary `PatAtom` | E-Atom-0 (§4.2), match(PatAtom a [], VAtom) (§4.3) |
| `g22_atom_payload_match` | payload `EAtom`/`VCon` matched against payload `PatAtom`, binding payload | E-Atom-N (§4.2), match(PatAtom a [p…], VCon …) (§4.3) |
| `g23_atom_returning_fn` | atom-returning fn, result via atom `==` and via `match` | E-Atom-0 (§4.2), δ-Eq-* (§4.4), match(PatAtom …) (§4.3) |
| `g24_nested_con_tuple` | deeply nested pattern (con → tuple → con → var) | match(PatCon/PatTuple …) via match_list at depth (§4.3) |
| `g25_guard_fallthrough` | guard `when n > 10` FALSE ⇒ falls through to a later branch | branch-selection guard rule (§4.3, `eval.ml:7340`) |
| `g26_catchall` | specific `PatCon` branches then a `PatWild` catch-all keeping `match` total | match(PatWild …) (§4.3), exhaustiveness/no-match rule (§4.3) |
| `g27_guard_binding` | guard reading its OWN branch pattern's bound variables | branch-selection: guard in pattern-extended env (§4.3); reachable substitute for `PatAs` (§4.3.1) |
| `g28_letfn_factorial` | local self-referential `fn go(n)` (factorial) via env-ref knot | E-LetFn (§4.2) |
| `g29_letfn_capture` | local recursive `fn go` closing over an outer `let` while recursing | E-LetFn (§4.2), env-ref re-read (§4.2 prose) |
| `g30_letfn_sum_result` | recursive `fn go` whose result is bound by a following `let`, used by rest of block | E-LetFn: binding visible to block continuation (§4.2) |
| `g31_cond_middle_arm` | `ECond` chain where a MIDDLE arm is the first `VBool true` | E-Cond-Sel (§4.2) |
| `g32_cond_all_false_catchall` | `ECond` all-specific-false ⇒ terminal `_ ->`/`true ->` catch-all | E-Cond-Sel with `_`-sugar catch-all; E-Cond-Fail (all-false raises) (§4.2) |
| `g33_float_show` | whole-number `Float` display via `float_to_string` (observation primitive) — pins the cross-backend format after the `0a2d3f53` fix | §5 observation-primitive note (not a §4 core rule; float arithmetic/ordering deferred) |
| `g34_nested_tuple_let` | nested `PatTuple` destructured in a block `let` — added after the `3f719a8e` lowering fix the corpus surfaced | E-Blk-Let + `match(PatTuple)` componentwise `match_list` (§4.2/§4.3) |

## Coverage notes (rules NOT anchored by a golden program, and why)

Some rules in `core-march.md` §4 are stated for fidelity to `eval.ml` but are
deliberately NOT exercised by any golden program — each has a `core-march.md`
note explaining why:

- **`match(PatRecord …)`** and **`match(PatAs …)`** — implemented in the
  interpreter but have **no surface grammar** (parse errors), so no `.march`
  source program can construct them. Collected in §4.3.1; `g27` is the reachable
  substitute for `PatAs`'s "bindings visible to the arm" semantics.
- **E-Cond-Fail (genuinely all-false)** and the **`Match_failure`
  exhaustiveness** case and the **`&&`/`||` crashing strictness** witness — all
  RAISE at runtime, and `verify.sh` treats any nonzero interpreter exit as an
  automatic `INTERP FAIL`, so a crashing program can never register as a golden
  `MATCH`. `g32` (routed through a `_ ->` catch-all) and `g13` (a non-crashing
  `println` side-effect witness) are the non-crashing substitutes.
- **`ERecordUpdate` on a missing field** — the adjudicated-and-converged
  divergence (§4.2.1). Its resolved form is "both backends reject with a nonzero
  exit", which (per the harness limitation above) cannot be a golden `MATCH`; it
  is pinned instead by a unit test
  (`test/test_properties.ml`,
  `test_record_update_missing_field_on_erased_base_converged`).
