# Refinement predicates: general truncating `/` and `%`

**Done 2026-09-24.** Increment 2 (the last open part) of the item filed
2026-09-16 as `specs/todos/2026-09-16-refine-predicate-language-widening.md`
(this file is that todo, moved). Earlier parts: non-linear `*`
(`2026-09-16-refine-nonlinear-multiplication.md`), the empty-string length
fact (`2026-09-16-refine-empty-string-length.md`), and increment 1, the
truncation-safe fragment (`2026-09-22-refine-predicate-division-fragment.md`).

## Encoding

March's `/` and `%` truncate toward zero and the remainder takes the
dividend's sign (`specs/lang/core-march.md` δ-Div-I/δ-Mod-I: OCaml's `/` and
`mod`). SMT-LIB's `div`/`mod` are Euclidean. Truncation is odd in the dividend
(`(-a)/d = -(a/d)`, `(-a)%d = -(a%d)`), and on a non-negative dividend it
equals Euclid for either sign of divisor (increment 1's argument), so:

    a / d  ~>  (ite (>= a 0) (div a d) (- (div (- a) d)))
    a % d  ~>  (ite (>= a 0) (mod a d) (- (mod (- a) d)))

exact for every sign of `a` and every non-zero `d`. Spot values:
`(-7)/2 = -3`, `7/(-2) = -3`, `(-7)/(-2) = 3`, `(-7)%2 = -1`, `(-7)%(-2) = -1`,
`7%(-2) = 1`, which are OCaml's answers. `lib/refinecheck/witness.ml`'s
`eval_operand` evaluates `/`/`%` with OCaml's operators (`None` on a zero
divisor), so it matches the encoding everywhere the divisor is non-zero.

- **Fast path kept.** When `Refine_scope.known_nonneg` proves the dividend
  non-negative (increment 1's syntactic rules, incl. the `&&`-chain facts) the
  plain `div`/`mod` is emitted with no `ite`. So every predicate that
  reflected before reflects to the identical term (identical VC text and
  cache key). The SMT-side non-negativity query was not adopted: the
  `ite` already makes it unnecessary for soundness.
- **Divisor.** A non-zero literal (either sign) stays `Smt.DivLit`/`ModLit`
  (linear). Anything else is the new `Smt.Div`/`Smt.Mod` (non-linear;
  `Undecided.nonlinear` counts them, so an undecided goal is
  `nonlinear-goal`).
- **New `Smt` constructors:** `Div`, `Mod`, `Ite`, with arms in every
  exhaustive term walk (`smt.ml` `children`/`render`; `refine_encode.ml`
  `mentions_str`, `wellsorted`, `mentions_float`, `formula_wellsorted` (an
  `Ite` is a formula iff both branches are, so the Int-valued one is refused
  in Bool position), `pin_set_sorts` (a wildcard walk, given explicit arms),
  `vc_set_elem_sorts`, `resolve_set_sorts`' `infer`/`rewrite` (same c, a, b
  slot order in both), `term_sorts`; `undecided.ml` `consts`/`app_heads`/
  `nonlinear`; `return_infer.ml` `collect_consts`).

## Side condition: a zero divisor

At a zero divisor March's `/` panics, so the predicate has no value; a
refinement's value set is where the predicate evaluates to `true`, and a panic
is not `true`. `Refine_scope.smt_of_r` therefore reflects a Boolean-shaped
predicate `p` (top is a comparison or `&&`/`||`/`not`: `bool_shaped`) as
`defined(p) && p'`, where `definedness` is computed on the *reflected* term
(no sub-expression reflected twice; resolvers may mint fresh constants):
`D(a && b) = D(a) && (a => D(b))`, `D(a || b) = D(a) && (a || D(b))`,
`D(not a) = D(a)`, `D(Div(x, d)) = D(x) && D(d) && d != 0`, otherwise the
conjunction over children. This follows March's left-to-right
short-circuiting, so `d != 0 && _ / d > 0` is defined everywhere and
`_ / d > 0 && d != 0` is not. The conjunct makes the reflection exact in any
polarity (goal, assumption, under `not`, in a negated path guard). A predicate
with no non-literal divisor gets no conjunct.

`Division_safety.syntactic_nonzero` was not reused: it treats `_` as the
binder in every predicate, so it would read `_ > 0` as a fact about an
unrelated divisor `d`, and the definedness conjunct covers every shape it
would have served (and more) exactly.

## Still a skip / limits

- A non-literal divisor in an Int-valued (non-`bool_shaped`) reflection, such
  as a call's actual `f(n / d)`, has nowhere to put the conjunct: it reflects
  only when the divisor is syntactically positive (`known_pos`: positive
  literal, `pos + nonneg`, `pos * pos`), else the division is the failing leaf
  with `division_outside_fragment_hint` (reworded) saying why.
- A refutation whose counterexample has a zero divisor is not confirmed:
  `Witness.eval_pred` has no "panics" value, returns `None`, and the obligation
  lands as a not-verified skip (`nonlinear-goal`/`solver-undecided`; an error
  under `cap verified`), never a report and never a proof. Example: `h(d, 7)`
  against `{Int | _ / d > 0}` with `d` unconstrained. A concrete `h(0, 7)` is
  reported. Teaching the witness a three-valued (true/false/panic) evaluation
  would make these definite; not done here.
- `@[measure]` bodies still reject a non-literal divisor (totality gate,
  unchanged).

## Tests (`test/test_refinecheck.ml`, `obligation-reasons`)

Rewritten: UP2 (was `_ / 2 > 0`, now `_ / weight(_) > 0`, so it stays the
b2-mutation witness with a failing leaf two levels down); "division outside
the fragment: a variable divisor is skipped" and "... a possibly-negative
dividend is skipped" became accepting cases. New "general truncation" cases:
a proof that needs truncation plus a violation Euclid would miss
(`f(-7)` / `f(-5)` against `_ / 2 == -3`); witness-confirmed postcondition
refutations on negative dividends (`_ / 2 * 2 == _`, `_ % 3 >= 0` for
`n < 0`); `%`/`/` with negative operands and negative divisors (proof and
violation); variable divisor with a non-zero guarantee (param refinement,
`d != 0 &&` in the chain, a bounded caller param) and without (`h(0, 7)`
violated; unconstrained `d` not proved); short-circuit order under `not`.

## Evidence

- Green: `test_refinecheck.exe -e` with z3 on PATH, `.march/cas/vc` cleared
  first: 965 run, 0 failed, 0 skipped.
- Red control (lib/ swapped back to origin/main by file copy, new tests kept):
  all 9 new or rewritten division cases fail, e.g. "no skips" expected `[]`
  received `["unreflectable-predicate"; ...]`; `%`-violation expected
  `(0, 1, 0)` received `(0, 0, 1)`; "h(0, 7) is a violation" expected 1
  received 0; "p's counterexample is executed and shown" false; UP2's exact
  leaf detail false. The witness case first passed on main by accident
  (`Witness.confirm_enumerative` tries 0/1/-1/2/10 without the solver), so it
  was rewritten with a `_ >= -4 ||` guard that the whole battery satisfies,
  after which it went red on main.
- `scripts/refine-oracle.sh`: baseline on origin/main's lib, check on this
  change: identical, 6654 lines over 387 fixtures. The corpus has no division
  predicates, so this only shows nothing else moved (the fast path and the
  no-conjunct-without-a-variable-divisor rule keep every existing VC
  byte-identical).
- `test/run_compiler.exe -e`: 1265 run, 1 failure, `tcenv_cli_cache` ("stdlib
  not found next to the compiler"), because the worktree's `_build/default/stdlib`
  had not been staged. After `dune build @stdlib/all` that group passes (3/3).
