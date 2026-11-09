# HCR H7: actor-message tag consistency checked at deploy

Phase F of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (§3.4 "H7. Tag
consistency", §7). Landed 2026-11-08.

## The gap

A message is a heap cell whose constructor tag the sender's build chose; after a hot deploy
the receiver's new build (its dispatch, or its `<actor>_migrate_msg`) reads it. Tags come
from `Llvm_toplevel.actor_msg_tag_table`: 24 bits of the MD5 of `"<Actor>_Msg.<Ctor>"`,
keys placed in sorted order, and a key whose slot is taken probes upward. So the tag is a
function of the name alone except when two keys collide: then the later-sorted one's tag
depends on which other keys the build has, and it can move between two builds. Nothing
compared the two builds' tags at deploy.

## What changed

- **Writer** (`bin/main.ml`, the `.schemas.json` writer): every `handlers` and
  `migrate_msg_from` entry carries `"tag":<int>`, read from `actor_msg_tag_table` over the
  same final TIR module `emit_module` receives, with the same pins
  (`Llvm_toplevel.current_migrate_pins`, now exported). Lookup is `<Actor>_Msg.<Ctor>`,
  falling back to the unique key ending in `.<Actor>_Msg.<Ctor>` (module-qualified
  declarations). The table is lazy, so a build without actors never computes it.
- **Reader** (`forge/lib/schema_diff.ml`): `ctor.tag : int option`; a schema without the
  field parses with `None`.
- **Comparison** (`Schema_diff.tag_check`): for each constructor the running version's
  handlers and the new build's handlers or `migrate_msg_from` both name, `Tag_moved` when
  the tags differ, one `Tags_unrecorded why` when either side has no tag (a baseline from
  an older compiler, or one without handler recording), `Tags_agree n` otherwise.
  `Schema_diff.tag_moved_message` is the one refusal text.
- **`march --check-migration`** (`bin/schema_migration.ml`): two new verdicts. `Refused why`
  (law `<Actor>.<Ctor>.tag`) never passes, `--accept-unproved` included. `Noted why` (law
  `<Actor>.tags`) prints and passes. Agreement is one summary line for all actors (every
  stdlib actor the prelude links in would otherwise add a line to every check). The check
  runs before, and independent of, the refinement laws.
- **`forge deploy hot`** (`forge/lib/cmd_deploy_hot.ml`): runs `tag_check` in process on
  every deploy, not only when an actor has contracts (the `--check-migration` shell-out
  only runs then). A moved tag aborts (`actor-message tag moved — deploy aborted`); an
  unrecorded baseline prints one `NOTE: actor-message tags not compared for <actors>: <why>`
  per reason (an older baseline covers every stdlib actor too, so not one line each).
- `Schema_diff.same_message_type` replaces the two structural `f = oh` comparisons of
  `migrate_msg_from` against the running handlers (`cmd_deploy_hot.ml`, `deploy_plan.ml`),
  ignoring tags, so an untagged baseline is not misread as a different old message type.

The refusal:

```
migration: Tally.Bump.tag: REFUSED, Tally.Bump's actor-message tag moved: the running version tags it 0x01c15dfc, this build 0x01c15dfb. Tags are a hash of the qualified name Tally_Msg.Bump, and a name whose hash slot another constructor holds probes to the next free one, so a hash collision in one of the two builds moved it; a message the running version built would be read as another constructor or dropped. A restart deploys it safely; a hot deploy cannot.
```

## Tests

- `test/test_codegen.ml` `actor_dispatch_codegen` "H7: actor-message tags ignore
  declaration order (with a colliding pair)": two type lists with the actors, their
  handlers and interleaved ordinary variants in different orders, the second with an extra
  actor, plus `Clash_Msg.C5264`/`Clash_Msg.C796`, found by a birthday search, which share
  slot `0xa81246`. Every shared key keeps its tag, the installed heap tags
  (`variant_ctor_tags`) agree by constructor name, and the pair shows the move: `C796` alone
  takes the slot, next to `C5264` it probes one up.
- `forge/test/test_forge.ml` `hcr-cap-gate` "schemas: actor-message tags compared at deploy
  (H7)": parse of `tag`; equal, new handler, moved, removed handler through
  `migrate_msg_from` (moved and agreeing), untagged baseline, untagged new build, the
  message's content, `same_message_type` ignoring tags.
- `test/test_refinecheck.ml` `hcr-variance`, through the real `march --check-migration`:
  equal tags (exit 0, summary line); a moved tag (exit 1, the refusal, also with
  `--accept-unproved Tally` and an image-embedded `["*"]`); an untagged baseline (exit 0,
  the `not compared … not a refusal` line); and the writer: two `--compile-so --hot-reload`
  builds of reordered actors and handlers (one with an extra actor) record a tag for every
  handler, the same tags, each one present in the emitted IR, and the check between them
  passes. (`test_refinecheck` now links `march_forge` to read the sidecar with
  `Schema_diff`. The two builds run under a private `HOME`: a hit in the shared
  `~/.march` CAS restores the `.so` and sidecars but writes no `.ll`, which made the first
  version of this test fail on its second run.)

## RED evidence (each perturbation applied alone, run, restored)

- `actor_msg_tag_table` without the key sort (`List.rev !keys`): the codegen H7 test fails,
  `Clash_Msg.C5264 keeps its tag across the reordering`, expected `27791942`, got
  `27791943` (the existing stable-tags test fails too).
- The hash replaced by a counter (`place 0`): the codegen H7 test fails,
  `Other_Msg.Poke keeps its tag`, `16777218` vs `16777219`.
- `tag_check` returning `[]`: the forge test fails (`equal tags agree`), and hcr-variance
  15-18 all fail (no summary line, a moved tag exits 0, no `not compared` line).
- The writer's `tag` field removed: hcr-variance 18 fails, `Tally.Bump has no tag in
  …/a.so.schemas.json`.

## Residuals

- The forge in-process path (`forge deploy hot` against a server) is not driven by a test;
  it calls the same `tag_check` and `tag_moved_message` the tests pin.
- A baseline's own `migrate_msg_from` (messages from two deploys back still queued) is not
  compared, only its handlers.
- `forge deploy --plan` (`deploy_plan.ml`) does not show a moved tag; the deploy refuses it.
- `same_message_type` still compares `refines`, as the old `f = oh` did; `migrate_msg_from`
  never records refinements, so a running version with a refined handler parameter reads as
  a different old type. Pre-existing, unchanged here.
- A refusal says to restart; nothing yet helps pick a rename that removes the collision.
