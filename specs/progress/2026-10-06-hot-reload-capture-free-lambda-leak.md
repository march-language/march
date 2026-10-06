# `--hot-reload` builds leaked every capture-free lambda they called

**Date:** 2026-10-06
**Filed:** 2026-10-05, from LeakSanitizer during observe R4b
([progress](2026-10-05-observe-r4b-signed-debug-verbs.md)): one 24-byte
leak per `Actor.inspect_state` of an actor with a `List` field.

## The bug

In an ordinary build a lambda that captures nothing (`fn x -> show(x)`
inside `Show(List)`, `fn x -> x + 1` passed to `List.map`) is one immortal
global closure (`Llvm_emit`'s static-closure arm), so the reference every
call hands its apply fn needs no release. A `--hot-reload` build turns static
lambdas off for the whole module (`Llvm_emit`: `hr_config <> None`), so each
use allocates a 24-byte heap closure, and nothing released it. `Perceus`
already had the fix, case (3) of `insert_apply_fn_clo_drop`: a `dec_rc $clo`
at entry of an apply fn whose body never mentions `$clo`, but gated on
`repl` (the REPL/JIT, the other place lambdas are heap closures).

Measured with `live_allocs()` over 10 000 iterations: `to_string` of a
`List(String)`, `List.map` with `fn x -> x + 1`, and `List.fold_left` with a
capture-free lambda each grew by 9 999 objects under `--hot-reload`, and by
nothing in a plain build. A lambda that captures a heap value never leaked:
its apply fn mentions `$clo`, and case (1) releases it.

## The fix

`Perceus.perceus ?heap_lambdas` (new): "capture-free lambdas are heap
closures here". The case-(3) drop fires when `repl || heap_lambdas`.
`Contract_pipeline` sets it from the same `hot_reload` config that turns the
static arm off, so the two always agree. Base binaries and patches are both
compiled with `--hot-reload`, so both sides of a call follow the same rule.

## Tests

`test/native/hot_reload_lambda_leak_probe.march`, compiled with
`--hot-reload Main`: the three shapes above, each `flat: true` when its
`live_allocs()` delta stays under 100 over 10 000 iterations. Red control:
with `~heap_lambdas:false` all three read `flat: false`. The existing
`--hot-reload` goldens (`actor_inspect_state` HCR leg, `observe_types_hr`,
`observe_debug`), the compiler and codegen quick suites, and forge's
`test_upgrade_from` (hot patches built and activated) pass.
