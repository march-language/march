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
