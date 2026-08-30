`[P2]` Counterexample surfacing for refinement failures (filed 2026-08-30)

Turn Z3 models for failed refinement obligations into concrete,
interpreter-validated failing inputs rendered in source terms — e.g.
`clamp(0) returns -1` instead of silence or "solver-undecided".

Design: `specs/2026-08-30-counterexample-surfacing-design.md`.

Summary: new `lib/refinecheck/witness.ml` (decode model → execute via
fuel-limited, effect-stubbed `march_eval` → confirm the violation →
deterministic shrink), wired into four sites: return contracts
(`refine_post.ml`), call-site preconditions (`refine_call.ml`),
`division_safety.ml`, and `cap verified` undecided obligations. Plus an
enumerative small-value battery for unreflectable obligations (`x * y`)
that SMT never sees. Confirmed witnesses are errors by default;
unconfirmed models keep today's behavior. Behavior change (silent accepts
→ errors on confirmed violations) needs a CHANGELOG entry when it lands.
