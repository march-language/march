# `[P1]` Compiled `migrate_msg` cannot match a real old-format message: constructor tags differ

**Found** 2026-09-24 while building `forge test --upgrade-from` (build step 8). Owned by
codegen (`lib/tir/llvm_toplevel.ml`), not by the step-8 work; the step's passing fixture
avoids the feature (`forge/test/fixtures/upgrade/good`).

**What.** `<actor>_migrate_msg(m : OldMsgs.Msg) : Option(<Actor>.Msg)` is called by the
runtime with a real message the OLD version's code allocated. That message carries an
actor-message tag from the global actor-message range (`0x0100_0000 + n`, handed out by
`variant_ctor_tags` in BUILD order over every actor message type in the program). The
user's `OldMsgs.Msg` is an ordinary variant, so the compiled `match` in `migrate_msg`
switches on tags `0, 1, ...` and falls to `panic("non-exhaustive pattern match")`, which
kills the actor's process. Observed: v1 `Tally` with handlers `Add | Legacy` (tags
16777261/16777262), v2 removes `Legacy` and writes `tally_migrate_msg(m : TallyMsgV.Msg)`
with `type Msg = Add(Int) | Legacy(Int)`: the deploy logs `migrate_msg: found
__migrate_msg_Tally for slot 7` and the process dies with the panic on the first
`Legacy` from the old feeder. The runtime path (`hcr_route_slow`,
`runtime/march_runtime.c`) and the wrapper (`Desugar_migrate`) are fine; the mismatch is
only in what tag the old message carries versus what the user's type compiles to.

A second problem sits behind it: removing a handler from one actor shifts the global
counter, so every actor message type declared AFTER it in build order gets different
tags in the new build than the old messages carry (`Add` itself moved from 16777261 in
the old build to 16777261 in the new only because `Tally` is the last actor). `test/test_hcr_migrate_order.c`
does not see either: it builds its old messages by hand in C with the tags the new code
expects.

**Fix sketch.** Either (a) compile `migrate_msg`'s parameter type against the OLD
version's tags: the `.schemas.json` of the running version records the handlers, so the
build of a patch can be given `--prior-schema` and assign `OldMsgs.Msg`'s constructors
the tags the old `Tally.Msg` had (by name); or (b) make actor-message tags stable across
builds (hash of `Actor.Ctor` instead of a counter), which also fixes the shifting for
other actors and matches how `@[remote]` codecs already key on names. (b) is the real
fix; (a) is the smaller one.

**Test to add.** A compiled two-version scenario: build v1 (two handlers), start it with
a reload socket and a feeder task, deploy v2 (one handler removed + `migrate_msg`), and
assert `PINS` reports `converted:N dropped:0` and the process is alive. `forge test
--upgrade-from` on such a fixture is exactly that test once this is fixed; the fixture
that will exercise it is described in `forge/test/fixtures/upgrade/good/src/upgrade_app.march`.

---

## Fixed 2026-09-25

**Choice.** Fix (a)'s idea, applied in codegen with no new flag, on top of (b):

1. **Actor-message tags are stable (b).** `Llvm_toplevel.actor_msg_tag_table` gives
   each `<Actor>_Msg.<Ctor>` the tag `0x0100_0000 + 24 bits of MD5("<Actor>_Msg.<Ctor>")`,
   assigned in sorted key order with upward probing on a slot collision (so every
   tag in one build stays distinct, as Finding 19 needs). Removing a handler, adding
   an actor, or reordering declarations no longer moves any other constructor's tag.
   Probing is the one way a tag can still move between builds (two keys hashing to
   the same slot, with a different set of keys in the other build); at a few
   hundred constructors in 2^24 slots that is rare.
2. **The user's old type is compiled with the old actor's representation (a, but
   by name, not by `--prior-schema`).** Lowering records every
   `<actor>_migrate_msg(m : T) : Option(<Actor>.Msg)` in `Migrate_msg_pins`
   (`lib/tir/migrate_msg_pins.ml`) with the module prefix it was declared under and
   `T` as written, and binds it to `T`'s declaration once every type is lowered.
   The lowered parameter type is the bare canonical name (`Msg`), which is
   ambiguous as soon as two actors migrate, so the side table is what carries the
   qualifier. Codegen then gives `T`'s constructors the tags
   `<Actor>_Msg.<Ctor>` has (by constructor name, so a removed handler's key such as
   `Tally_Msg.Legacy` is part of the table and probes as it did in the build that
   still had it), and `Kind` forces `T` Boxed exactly like an actor message type
   (`Migrate_msg_pins.has_actor_msg_repr` at every site that tested
   `is_actor_msg_name` for representation: `Kind` x4, `Drop`, `Trmc`). Without the
   Boxed force a one-handler old type would be a Newtype and read the old heap
   cell as its payload.

Why this one: `migrate_msg` stays an ordinary function the typechecker checks as
before (nothing in `lib/typecheck` changed), the forge stub
(`forge hot-reload migrate-msg-stub`) needs no attribute, and no build needs the
running version's schema file to produce correct code. The alternative, a
translation table in the wrapper `__migrate_msg_<Actor>`, would have had to
re-box the old cell into the user type's representation (Newtype / Boxed / Niche
differ by shape), which is the same knowledge spread over more code.

**Consequences, fixed in the same change.**
- `Actor.call`'s positional dispatch added the sentinel's handler index to the
  actor's FIRST tag (`march_actor_set_call_base`), which assumed contiguous tags. It
  is replaced by `march_actor_set_call_tags(actor, tags, n)`: codegen emits each
  actor's tags in handler order as a private constant and the runtime interns a
  copy (never freed; a hot patch holding the original can be dlclosed while the
  actor runs). `test/native/actor_counter` and `simd_actor_msg` pass. The first
  forge run after the tag change hung exactly there (`never signalled
  MARCH_UPGRADE_READY`) before this was fixed.
- The HCR ABI id is now `march-hcr-v3`: a patch built by this compiler would drop
  every actor message a v2 process sends it and references a runtime entry point a
  v2 runtime lacks.
- `bin/main.ml`'s `.schemas.json` writer resolves `migrate_msg_from` through the pin
  table too (the bare-name suffix match returned nothing with two migrating actors).

**Tests.**
- `test/test_stdlib_suite.ml` "HCR migrate_msg: a compiled deploy converts a real
  old-format message" (Slow): the todo's exact repro through a real reload socket
  and `Cmd_deploy_hot.run`. Output: `COUNTERS deferred:0 converted:111 dropped:0
  killed:0 stopped:0 advances:1 ... markers_live:0`, process alive, and `EPOCH 2
  pins:1 current` with no old epoch. With `Migrate_msg_pins.resolve` made a no-op
  it fails with `panic: non-exhaustive pattern match`.
- `forge/test/fixtures/upgrade/migrates` + "an upgrade that removes a handler and
  converts it with migrate_msg passes": before the fix `[app-1] panic:
  non-exhaustive pattern match`, after it `app-1: converted 253, dropped 0, killed 0`.
- `test/test_codegen.ml` "actor-message tags are stable across builds": another
  actor's tags do not move when Tally loses a handler or the declarations reorder,
  and the pinned old type carries v1's `Add`/`Legacy` tags. The Finding-19 codegen
  test now reads its expected tags from the table instead of `16777216/16777217`.

**Pins after a deploy (the memory note's third fact).** In a plain program the old
epoch drains to zero once the feeder task ends and Tally moves (asserted by the HCR
test above): the base epoch holds no pin of its own. In the `forge test
--upgrade-from` topology app, 20 s after the deploy PINS still showed `epoch 1 (6
unit(s)) still pinned by units that are not actors (tasks)` and one actor on the
old epoch. Those are long-lived stdlib tasks (tasks never advance, II.4.3) and one
held/nested-receive actor, not a leak of the base epoch. PINS cannot name units, so
which six tasks is filed as `specs/todos/2026-09-25-name-units-pinning-old-epoch.md`.
