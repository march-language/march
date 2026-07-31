- ✅ **Tier 1 relational postcondition propagation (`lib/refinecheck/refine_check.ml`,
  2026-07-24).** A return refinement that mentions a parameter now propagates to
  call sites, closing the Tier 0 gap. `pred_is_closed` (a boolean accept/reject)
  became `classify_pred : binder -> params -> expr -> pred_scope` returning
  `Closed | Relational of string list | Unusable`, and `postcond_of` gained the
  call's actual arguments so it returns a predicate already instantiated in the
  CALLER's namespace — both propagation sites (`scope_add_binding` for a
  `let`-bound call, `reflect_scalar` for an inline one) therefore needed no
  substitution logic of their own. `subst_params` substitutes **simultaneously**
  (so `f(m, 1)` against `{Int | _ < n + m}` gives `_ < m + 1`, not `_ < 1 + 1`)
  and never rewrites an application HEAD, so a formal sharing a measure's name
  cannot turn `len(xs)` into `40(xs)`. Formals map to actuals positionally,
  matching the precondition side's existing `check_call` convention. **Skip,
  don't guess:** if any parameter the predicate mentions has no actual, the whole
  instantiation is abandoned — a partially substituted predicate would mix
  callee and caller namespaces, the exact conflation behind an earlier
  false-positive class. The Tier 0 safety guarantee is inherited unchanged:
  `gate_unverified_posts` still clears `ret` on any postcondition the definition
  side did not POSITIVELY VERIFY (confirmed by probe: `below`'s `_ < n`
  verifies, `shady`'s does not), so a stale or unprovable relational contract
  cannot travel. Known conservatism around pattern parameters — investigated
  2026-07-25 and found LARGER than first recorded, see the dedicated open item
  below. 13-program
  adversarial sweep (name collision, pattern formal, match/if arms, four
  shadowing forms, `len` measure, extra args, recursion) all exit 0 on a cold
  VC cache; the headline `takepos(below(0))` exits 1. `test_refinecheck.exe`:
  154 tests, exit 0 (was 137); `test_refine`/`run_compiler`/`run_eval` exit 0;
  a six-kind multi-violation file reports all six with zero `(error`.
