# Plan: enforce the refinement positions that parse and typecheck but are never checked

Filed 2026-09-13. Base: `8eb0d7ee` (main). Branch: `claude/refinements-open-todos-cbfbbb`.

Closes, phase by phase, five open todos:

- `specs/todos/2026-09-03-lambda-param-refinement-unchecked.md`
- `specs/todos/2026-09-03-block-fn-refinement-unchecked.md`
- `specs/todos/2026-09-03-actor-state-and-handler-refinement-unchecked.md`
- `specs/todos/2026-09-03-impl-method-param-refinement-unchecked.md`
- `specs/todos/2026-09-01-nested-refinement-enforcement.md`

and, as a consequence of decision (a) below, the parked
`specs/todos/2026-07-11-p2-compiler-refinement-types-honest-limitation-note-core-march.md`
(the `t77` higher-order bypass).

## Finding that reorders the work: three positions are unsound today, not just unchecked

`Refine_check.visit` ADMITS a lambda's and a block-level `fn`'s parameter
refinements into the body's scope (`lib/refinecheck/refine_check.ml`, the
`A.ELam` and `A.ELetFn` arms call `scope_add_param`), and `visit_decl`'s
`A.DActor` arm does the same for a handler's parameters. No caller is ever
obliged by any of them. So under `cap verified`:

```march
fn need(k : {Int | k > 0}) : Int do k end
fn main() : Int do
  let g = fn (n : {Int | n > 0}) -> need(n)   -- body assumes n > 0
  g(0)                                        -- nobody proves it
end
```

exits 0, while the same program with `n : Int` exits 1 ("cannot verify
precondition `k > 0` on `need`"). Same for a block `fn inner(n : {Int | n > 0})`
called as `inner(0)`, and for `on Increment(n : {Int | n > 0})` sent
`Increment(0 - 1)`. This is exactly the assume-without-check the checker already
guards against for non-adoptable `impl` methods via `strip_param_refinements`.

Phase 0 closes that first. Every later phase turns an assumption back on only
once its callers are actually obliged.

## Decisions (made 2026-09-13)

**(a) Escaping refined callables: contravariant subtyping at the pass site.**
When a value whose refined signature is known (a `let`-bound lambda, a local
`fn`, or a NAMED refined function) is passed where a function-typed parameter is
expected, the checker proves that the parameter type's domain refinement implies
the callable's own parameter refinement. An unrefined domain (`f : Int -> Int`)
promises nothing, so passing `take_n` (`{Int | _ >= 0}`) there is a VIOLATION at
the pass site, not a silent skip. This closes the `t77` limitation as well: the
witness `accept/t77_refine_hof_bypass_limitation` flips to a reject and moves.
It may reject existing code; the corpus sweep in each phase measures how much.

**(b) Distributed actors: state the trust assumption in the docs.** A handler
body may assume its parameter refinements once every LOCAL construction of the
message is obliged (Phase 3). A message arriving from a remote node is not
checked by this compiler; `specs/lang/refinement-types.md` and `docs/` say so in
words rather than the checker withholding the assumption.

## Shared mechanisms (verify before relying; lines drift)

- `cbenv` (`refine_scope.ml`, `type cbenv = (string * fn_sig) list`) is the
  lexically scoped callee environment consulted by `visit`'s `EApp` arm when
  `resolve_call` finds nothing. A local callable registers here; no top-level
  name is needed to key an obligation.
- `sig_of_clause` builds an `fn_sig` from an `A.fn_clause`; lambdas and
  handlers carry `A.param list`, so a small adapter that wraps each param in
  `A.FPNamed` reuses it unchanged.
- `strip_param_refinements` (`refine_scope.ml`) erases parameter refinements
  from an `fn_def`; Phase 0 needs a `param list` variant.
- Actor messages are constructors: `typecheck.ml` registers each `h.ah_msg` via
  `add_ctor`, so the construction `Increment(x)` is the single obligation point
  for `send`, `Actor.call`, and generated endpoints alike.
- `type_map : (span, ty) Hashtbl.t` is in hand at both `bin/main.ml` call sites
  of `Refine_check.check_module`; `Lower_state.resolve_iface_method` shows the
  first-argument-type dispatch rule the checker should mirror in Phase 5.
- `check_call` already reflects a record literal (`reflect_record_literal`) and
  `recenv` tracks record-typed variables, which Phase 4's field obligations
  build on.

## Phases

Each phase: one commit; a REJECT fixture (not only an accept) in
`test/test_refinecheck.ml`; `refine_audit.ml`'s `classify` updated so the
position reports `Enforced`; the hole fixture leaving `test/refine_audit/holes/`
replaced by a reject fixture elsewhere so `holes.baseline` keeps its
non-vacuity role; the todo `git mv`'d to `specs/progress/`; `CHANGELOG.md`;
both `specs/lang/refinement-types.md` and `docs/refinement-types.md`.

Verification per phase: `./_build/default/test/test_refinecheck.exe -e` run
DIRECTLY with z3 on PATH (`scripts/run-tests.sh` never runs it; quote the `[OK]`
count and confirm the new cases are not `[SKIP]`); `scripts/refine-oracle.sh`
under a private `HOME` with `.march/cas/vc` cleared once before the run;
`scripts/run-tests.sh compiler` for the audit-baseline group.

### Phase 0: stop assuming what nobody proves

- `visit`'s `A.ELam` and `A.ELetFn` arms and `visit_decl`'s `A.DActor` arm walk
  the body with parameter refinements STRIPPED (a `param list` analogue of
  `strip_param_refinements`). Names are still shadowed exactly as before.
- Reject fixtures: the three probes above (lambda direct call, block fn, actor
  handler), each with an unrefined control that already rejects.
- Expected fallout: code that verified only through the unproved assumption now
  fails under `cap verified`. Sweep stdlib + `test/native` + the oracle corpus
  and list every program that moved.

### Phase 1: block-level `fn`, parameters and return

- In the `EBlock` fold, the `A.ELetFn` case registers `n -> sig_of_clause` in
  `cbenv` (replacing the bare `cb_shadow`), and inside its own body too, so a
  recursive call is obliged.
- Assumption is restored inside the body only if `n` NEVER ESCAPES the block:
  every occurrence after the definition is in callee position. Otherwise stays
  stripped (until Phase 2's pass-site check makes escape safe).
- Return: synthesize an `fn_def` and run `check_fn_post_verdict`; fill
  `fn_sig.ret` only on a proved verdict. A predicate mentioning a captured outer
  name is a recorded skip, not a guess.

### Phase 2: lambdas, and contravariant subtyping at the pass site

*Landed 2026-09-13*; see
`specs/progress/2026-09-13-lambda-param-refinement-enforced.md`. One thing
the sketch below missed, found by running the driver on `t77` rather than
trusting the alcotest cases: `check_call`'s definite-failure stance skips an
unconstrained subject, so the pass-site VC came back as a hint, not a
violation, and the tests only passed through `cap verified` escalation. For
the `Callback_domain` subject a `Refuted` model IS the definite failure
(`$cb_x`'s only constraint is the domain), and the tests now assert every
violation in a plain module too. Phase 0 and 1 landed as sketched
(`0043850a`, `a6e6e9eb`).

- `cb_add_binding` learns the `let g = fn (...) -> ...` shape and registers
  `sig_of_clause` of the lambda's params. Direct `g(0)` is then obliged.
- Pass-site rule (decision a): in `check_call`, when an actual is a variable in
  `cbenv` (or a name `resolve_call` resolves to a refined sig) and the callee's
  parameter at that position is a function type, prove for each refined
  parameter of the actual that `domain_pred ⇒ actual_pred` (domain unrefined ⇒
  goal is the actual's predicate alone, which fails unless trivially true). The
  obligation is filed at the pass site with kind `callback-domain`. An inline
  lambda argument is treated the same, by building its sig on the spot.
- Once that lands, lambda and local-fn bodies may assume their parameters
  again (every route to a call is obliged: direct, aliased, or through a
  checked domain).
- `t77` flips: move `accept/t77_refine_hof_bypass_limitation` to `reject/`,
  and close the honest-limitation todo.

### Phase 3: actor handler parameters

- Build `handler_sigs : (qualified msg name -> fn_sig)` beside
  `collect_all_defs`; `visit`'s `A.ECon` arm consults it and calls `check_call`
  on the constructor's arguments. A user variant constructor of the same name
  in scope is a fail-closed skip.
- Restore the handler-body assumption (with the docs note from decision b).

### Phase 4: stored fields, variant arguments, actor state, one nesting layer

- Obligation side: a record literal, a `{r with f: e}` update, and a variant
  constructor are checked as calls to a synthesized constructor `fn_sig` whose
  refined params are the refined fields/arguments (declared under the type's
  qualified name; `collect_all_defs`-style table).
- Assumption side: `b.v` on a `recenv`-tracked variable contributes the field's
  refinement to scope.
- Actor state as an inductive invariant: `init` is a construction; each
  handler's result state is checked as a construction; handler bodies assume
  the field refinements on the incoming `state`.
- `A.TyLinear` is transparent in `refined_param_ty`.
- `witness.ml`: keep `witness_safe_param`'s decline until `admissible` /
  `zero_value` / `battery_values` handle nested refinements; do them in this
  phase, then lift the decline — never before.
- Out of scope: a refinement inside a type ARGUMENT (`List({Int | _ > 0})`)
  needs container subtyping; emit an inert-position warning at the declaration
  so the audit reports it as warned, not silent.

### Phase 5: `impl` methods with ambiguous names

- `Refine_check.check_module` gains `?type_map`; only `bin/main.ml`'s two
  callers pass it, the test callers keep today's behaviour.
- On an unresolved call whose name is defined by ≥1 `impl`, look up the FIRST
  argument's type in `type_map` (the same rule as
  `Lower_state.resolve_iface_method`); exactly one impl for that type ⇒ check
  its sig. Unknown/generic/≥2 ⇒ skip, recorded.
- Method bodies stay stripped: obliging callers without letting the body assume
  is sound; lifting the strip needs a proof that no generic call site escapes
  resolution, a separate change.

## Not in this plan

- `String` return refinements (`2026-09-03-string-return-refinement-unchecked`).
- Desugar-dropped refinements (`2026-09-03-desugar-dropped-refinement-unchecked`).
- Sibling-parameter blame (`2026-09-03-sibling-parameter-opaque-actual`).
- Scalar-ctor-field measures (`2026-08-05-measure-over-scalar-ctor-field`).
