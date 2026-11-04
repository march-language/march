`[P2]` An `@invariant` outside the supported grammar is dropped, and the deploy goes unchecked

`docs/hot-code-reload.md` ("What expressions are allowed in `@invariant`") documents it: an
unsupported predicate prints `warning: @invariant on <actor> contains unsupported
expression; omitting` (`bin/main.ml`, the schema writer's `pred_to_string` fallback). The
invariant is then left out of `.schemas.json`, and `forge deploy hot` proceeds with no
migration check for that actor. The user believes a guarantee they don't have.

Filed from `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (gap G3, phase A).
Make it a diagnostic at the `@invariant` span: an error by default, or a warning only under
an explicit opt-out. The longer-term fix (design M2) is to elaborate `@invariant` to a
reflected predicate, so that any reflected call is supported and the grammar table goes
away.

## Fixed (2026-11-04)

- **What changed.** `--hot-reload` builds now report `invariant_not_deploy_checkable` at the
  first part of the `@invariant` the deploy gate can't read. It is an error, and a warning
  when `--accept-unproved <Actor>.state` (or `<Actor>`) names the actor. That override is
  also signed into the patch, where the reload server's audit log records it (progress
  `2026-11-04-hcr-accept-unproved-audited`).
- **Where.** The check is `hcr_invariant_diags` in `bin/main.ml`, over the same grammar the
  schema writer prints (`hcr_pred_to_string`, now top-level). The ad-hoc `eprintf` warning
  is gone. The schema still records `"invariant_unsupported"`, so the deploy gate refuses the
  law unless it was accepted.
- **Builds without `--hot-reload` are unaffected.** There the invariant is only checked at
  run time, and no deploy depends on it.
- **Tests.** `test/native/hcr_schema_contracts`: its `Odd` actor's unsupported invariant now
  builds only with `--accept-unproved Odd.state`, and the expected output pins the recorded
  `accepted_unproved`.
- **Not done.** Design M2, which would elaborate `@invariant` to a reflected predicate so
  that the grammar table goes away.
