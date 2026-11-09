`[P2]` H5: the rollback round trip is proved on every build

Phase F of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§3.4 H5, §7). The
convention the design left open: the reverse migration is `<actor>_rollback_state`, declared
beside `<actor>_migrate_state` in the same module. The rollback deploy itself is unchanged
(its `migrate_state` is this function); what is new is the law.

## What

- `lib/desugar/desugar_rollback.ml` (new, wired in `Desugar.desugar_module` after the other
  migration passes; never in the stdlib): when both functions are declared at one module
  level, it adds `@[lemma] fn <actor>_rollback_roundtrip(old : A) : {Unit |
  <actor>_rollback_state(<actor>_migrate_state(old)) == old} do () end`, `A` being
  `migrate_state`'s own parameter type. Typechecked like user code, proved by the lemma
  checker, removed by `Lemma_erase`. Every node has its own span derived from the rollback
  declaration's (reflection keys sites and units by span); the lemma's name is that
  declaration span, which a failure points at. A user-declared `<actor>_rollback_roundtrip`
  suppresses the generated one.
- `Refine_anon.lift`: every anonymous record in the signature of a `*_migrate_state`,
  `*_rollback_state` or `*_rollback_roundtrip` function is lifted, refined or not (and the
  result type too), so those functions reflect: an anonymous record has no sort. Shapes are
  keyed by field name, and a shape a declared record type already has is lifted to that
  type, never to a synthetic twin.
- `Refine_reflect.record_of_fields_inst`: an actor's state sort (`Refine_encode.actor_state_adts`,
  filled when the actor's fields are registered) gives way when exactly one other record
  sort shares its field set. A migration's result usually has the actor state's field set,
  and the two made every such record type ambiguous (declined).
- `--guarantees`: a `rollback round trip` line (`proved`; `violated` from
  `Refine_call.lemma_refuted`, since a refuted lemma's ledger row stays the stage-1 skip;
  `not proved` with the reason).

## Tests

`test_refinecheck` suite `hcr-rollback` (3 cases: a faithful rollback proves; a lossy one is
refused with `old = { count: 3, announced: true }` and labelled `violated`; no
`rollback_state` means no lemma and no line). RED, each with `bin/main.exe` rebuilt (the
suite drives the CLI): the desugar pass off, the lift-all off, and the actor-sort give-way
off each turn cases 0 and 1 red.

## Residual

- A state record with a `String` field: records with a String field are not usable in a
  lemma's predicate even as declared types (todo
  `2026-11-08-reflect-records-with-string-fields`), so the round trip is `not proved` there.
- The law is per pair of functions in one build; nothing ties the rollback deploy's
  `migrate_state` to the function proved here (a deploy could ship a different one).
