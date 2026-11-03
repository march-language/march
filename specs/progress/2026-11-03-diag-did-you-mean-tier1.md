# Did-you-mean ranked by type fit (diagnostics-depth X8, tier 1)

Lands tier 1 of §X8 in `specs/plans/2026-11-02-diagnostics-depth-plan.md`. Tiers 2 (search by
type when spelling finds nothing) and 3 (refinements and capabilities) remain open in
`specs/todos/2026-11-02-diag-did-you-mean-ranking.md`.

**Mechanism: structural comparison, not trial unification.** `Typecheck_env.could_fit` matches
two live `ty`s structurally (an unresolved variable or `TError` matches anything; schemes are
read through `scheme_body`, without instantiation). It never writes a link and mints no fresh
variable, so suggestions cannot change inference; no undo trail was added to
`typecheck_unify.ml`. It is weaker than unification only in treating each variable occurrence
independently, which matters for ranking only. The constructor test is cheaper still: the
candidate's parent type against the expected type's head (`ctor_fits_need`).

What changed (`lib/typecheck/typecheck_env.ml`, the "Did-you-mean ranking" section):
- One spelling window for every suggester (`spelling_max_dist`: distance ≤ 1 for names of up to 3
  letters, else ≤ 2 or ≤ length/3, and below the length so `z` never "means" `x`). The
  constructor suggester used a first-two-letters heuristic (`LinearMapRep` → `LiveProcess`);
  a qualified `Q.m` is now matched only against `Q`'s constructors.
- Ranking (`rank_candidates`): fit first (when any candidate fits, only fitting ones are shown),
  then locality (current module; other user code and the prelude; stdlib modules, dropped when
  anything nearer is in range), then distance, then name.
- What the position needs reaches the error site through `pending_suggest_need` in
  `typecheck.ml`, keyed by the span of the expression being inferred: `check_expr`'s
  infer-then-unify fallback records the expected type, `send` records the pid (an actor message
  fits when its actor's state could be the pid's), patterns pass their expected type, a field
  access its expected type, a record update the assigned value's type.
- Generated names are never suggested (`is_generated_name`: `$`-mangled names and the `S_…`
  session-state constructors of `@[endpoints]` modules). Actor messages read "message of actor
  `A`" instead of "from type `A_Msg`". A qualifier that owns constructors but not this one says
  "`Stream_Prod` has no constructor `Secret`." instead of listing 15 unrelated names.
- `unknown_record_field` gains "Did you mean `f`?".

Corpus: `unknown_constructor_2` (the `Pokee` send, with a second actor's `Pake` in range),
`_3` (annotation picks `Postal` over a nearer same-module `Poss` and stdlib `Post`), `_4`
(`Stream_Prod.S_ned` offers no `S_end`), `unknown_record_field_2` (`conut` → `count : Int`, not
`cont : String`). Goldens moved: `unknown_constructor_1` (no more `LiveProcess`/`Limit.Rate`),
`unknown_qualified_name_2` (15-line list → one sentence; its `S_end` allowlist line removed).
