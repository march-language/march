`[P3]` A callback chain with a concrete `{Bool | _ == e}` codomain carries no contract

Filed 2026-10-21 by the multi-arg review fixes
(`specs/progress/2026-10-21-abstract-multiarg-review-fixes.md`, finding C2). Phase 2
(`specs/2026-10-18-abstract-refinements-multi-arg-design.md` §5.3) built an
n-parameter callback signature for two shapes of chain:

- (i) a definer of a current abstract refinement, `keep : ({x : k | true}) -> ({y : v
  | true}) -> {Bool | _ == p(x, y)}` (or the sugar `k -> v -> Bool[p]`);
- (ii) a concrete predicate contract, `kk : ({x : Int | true}) -> ({y : Int | true})
  -> {Bool | _ == (y > x)}`.

Shape (ii) gave the body the fact `kk$ret == (v > k)` at `kk(k, v)`, and nothing
obliged the callable passed for `kk`: a chain's codomain is an arrow, so
`check_pass_sites`' covariant half owes nothing. `h(fn (_a, _b) -> true, 0 - 5, 1)`
proved `need_pos(k)` under `if keep(k, v)` (review repro `f2.march`). The controller
ruled that only shape (i) builds the n-parameter signature; shape (ii) is the
one-parameter signature of today (no fact), and the phase-2 test `cb_passthrough` is
now pinned uninstantiated.

Shape (ii) back, soundly: an obligation at every pass site for a chain codomain
`{Bool | _ == e}` over the chain's binders. For an argument `a` passed there:

- read `a` the way `instantiate_abstract_n` reads a callable for an n-ary `p` (an
  uncurried or curried lambda, a `let`-bound lambda, a name with a proved `{Bool | _
  == e'}` return over n parameters), giving `(ys, q)`;
- oblige `∀ ys. dom_1(y1) ∧ … ∧ dom_n(yn) ⇒ (q ⇔ e[ys])` in one scratch query (one
  ledger entry, `Callback_codomain`), the domains as hypotheses;
- an argument that cannot be read is the recorded skip the one-argument pass site
  files ("declares no proved return refinement to imply it from").

Then `chain_sig_of_ty` may build the signature for shape (ii) again, and
`refine_audit`'s `Arrow_codomain` rule reports it enforced (today it is honestly
unenforced: test "C2 audit" in group `abstract-multiarg-review`).
