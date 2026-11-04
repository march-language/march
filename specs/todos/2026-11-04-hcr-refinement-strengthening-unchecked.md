`[P1]` A hot deploy that only strengthens a refinement is neither migrated nor checked

Found 2026-11-04 on `b86c86a63` while planning
`specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§3.3).

**Reproduction** (statically; no live reload server was run). Two builds of one actor,
each with `march --compile --compile-so --hot-reload Main -o app.so app.march`:

```march
mod Main do
  needs IO.Console
  @invariant(count >= 0)                 -- v2: count >= 1
  actor Tally do
    state { count : {Int | _ >= 0} }     -- v2: _ >= 1
    init  { count: 0 }                   -- v2: 1
    on Bump(n : {Int | _ > 0}) do        -- v2: _ > 5
      { state with count: state.count + n }
    end
    on Share(total : Int) do
      println(int_to_string(per(total, state.count)))
      state
    end
  end
  fn per(a : Int, b : {Int | _ != 0}) : Int do a / b end
  fn main() : Int do 0 end
end
```

- **The refinements are erased from the schema.** `app.so.schemas.json` records `count` as
  `"Int"` and `Bump` as `["Int"]` in both builds (`bin/main.ml` `ty_to_schema_str` works on
  TIR types). With the `@invariant` lines removed, the two sidecars are byte-identical, so
  `forge deploy hot` sees no state change: no `migrate_state` is required and none runs.
- **A stronger `@invariant` passes too.** With the `@invariant` lines, the sidecars differ
  only in `"invariant"`, and
  `march --check-migration --prior-schema v1/... --new-schema v2/... v2/app.march` exits 0
  with no output. `bin/schema_migration.ml` verifies only actors that have a
  `migrate_state` (`find_migrate_fn ... None -> ()`).
- **The new code's proofs rest on the false assumption.** `per(total, state.count)`'s
  `_ != 0` is `refinement_unverified` in v1 and **proved** in v2. It is proved from
  `count >= 1`, which the checker assumes of the incoming state in every handler. A live v1
  actor still at `count: 0` gets the v2 handler after the deploy, and the "proved" division
  divides by zero. The same holds for `Bump`'s parameter: queued messages and senders still
  on the old epoch were checked against `n > 0` only.

**Fix.** Carry refinements and invariants in `.schemas.json`. At deploy time, prove:
- unchanged-shape state with no `migrate_state`: old refinement and invariant imply the new
  ones (an identity migration);
- unchanged message type: old handler parameter refinement implies the new one
  (contravariant);
- `Actor.call` replies: the new reply's refinement implies what old-epoch callers expect
  (covariant).

When the implication fails, the deploy is refused with a counterexample, unless a
`migrate_state` exists and proves against the old refinement. RED control: this pair of
builds must be refused.
