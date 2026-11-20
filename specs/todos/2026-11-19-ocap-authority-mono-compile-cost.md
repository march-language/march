# Every compiled program monomorphizes `stdlib/authority.march` and then drops it (2026-11-19)

Found during ocap phase 4 (PR A, since `bad07beec`, Authority's run-time policy in
March). Every `--compile` now monomorphizes about 100 `stdlib/authority.march`
functions that are removed before LLVM emission: on
`test/snapshots/src/trmc_modulo_cons.march` the tir-mono function count went from 37
to 144, while the emitted module has 14 defines and none of them from `Authority`.
On native, the launch and the checks run the C policy (`runtime/march_authority.c`,
`Auth_native`), so `launch_init`'s March body is dead there.

The compile-time delta is not measured yet: both arms of a comparison against
origin/main already carry `bad07beec`, so it needs a build of `bad07beec^`
(or a switch that skips the March policy) timed on a hello world and on a
mid-size program, with a private HOME so the CAS does not answer.

What to do: measure it as above; if it matters, make the March policy
unreachable on native when `Auth_native.applicable` holds (so mono never sees
it), and check with `scripts/ir-oracle.sh` that emitted IR does not move.
