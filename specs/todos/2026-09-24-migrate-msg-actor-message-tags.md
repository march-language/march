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
