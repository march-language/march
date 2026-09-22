# `[P1]` Distributed deploys, groundwork G1: measure the hot-reload boundary cost (not done)

**Parent:** [../plans/2026-09-21-distributed-deploys-groundwork-plan.md](../plans/2026-09-21-distributed-deploys-groundwork-plan.md), G1;
[../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), II.7.
Its result can reorder build steps 5-12, so do it before step 6.

**Status (2026-09-22).** Everything is built and verified; no timing was taken. A
load-gated runner (start a sample only at 1-minute load average below 4) waited about
90 minutes while other sessions kept the 14-core machine at load 14-82, then was
stopped. Run it on an idle machine.

## What is ready

- `bench/actor_ping.march` (committed): two actors exchange 1,000,000 messages; each
  handler calls `Game.relay`, whose call to `Game.step` is a boundary-to-boundary call.
  Build the hot-reload variant with `--hot-reload Game`, not the entry module's name
  (nested functions are named `Game.<fn>`, entry-module functions get bare names).
- `bench/list_ops_nested.march` (committed): `bench/list_ops.march` with its helpers in
  `mod Ops`. **`list_ops.march` itself measures nothing under `--hot-reload`**: every
  helper is an entry-module `pfn` with a bare name, so no function is on the boundary
  and the emitted IR has zero `march_dispatch_enter` calls. Measure both; only the
  nested one says anything about the boundary. Even there, only the three
  helper-to-`irev` calls go through dispatch (self tail calls become loops, the
  per-element work is closure calls), so it is a floor on the cost, not a typical app.
- The two prototype variants (not merged, as G1 says):
  - `march_proc` gains `uint32_t code_epoch` (initialised in `sched_spawn_common`; for
    the measurement from `MARCH_G1_EPOCH`, default 0).
  - `march_dispatch_enter_unit(id, out)`:
    `march_dispatch_enter_gen(id, march_sched_current() ? ...->code_epoch : 0, out)`.
    Variant "unit": `hcr_enter` (runtime/march_runtime.c) calls it, and the compiler
    (`lib/tir/llvm_emit_call.ml`, the non-`compile_so` branch) emits it instead of
    `march_dispatch_enter`.
  - Variant "hoist": `actor_green_thread` reads `self->code_epoch` once per message and
    passes it to `hcr_enter`, which calls `enter_gen` with it; compiled call sites
    call `enter_gen` with a constant epoch.
  - Run each prototype with epoch 0 AND epoch 1: `enter_gen` short-circuits to plain
    `enter` when the epoch is 0, so epoch 0 alone measures only the TLS read, not the
    ring scan.
- Verify each binary before timing: `nm` shows `_march_dispatch_enter_unit` only in the
  prototype builds, `otool -tv` shows the expected `enter_gen`/`enter_unit` call count
  (list_ops 1, list_ops_nested 7, actor_ping 2), and outputs are `333333666666` and
  `1000000`.

## Traps found while preparing

- The staged runtime under `_build/default/runtime` was stale (all four HCR files
  differed from `runtime/`); `dune build bin/main.exe` does not restage it. Build the
  runtime files as targets first, and check with `cmp`.
- `actor_ping` printed `730492` once with only `run_until_idle()` before reading the
  counts (`specs/todos/2026-09-22-run-until-idle-returned-mid-ping-pong.md`); it now
  loops until the total reaches n.
- `spawn(Game.Player)` from the parent module fails to link
  (`specs/todos/2026-09-22-nested-actor-spawn-link-error.md`); the bench spawns from
  inside `Game`.
- Build every variant with a fresh HOME and project directory so no CAS artifact is
  shared, and record CPU time beside wall time (actor_ping is mostly system time).

## Acceptance

A table in `specs/progress/` with five-run medians (plain first, discarded as
warm-up) for plain, `--hot-reload`, unit (epoch 0 and 1) and hoist (epoch 0 and 1) on
`list_ops`, `list_ops_nested` and `actor_ping`, all `--opt 2`, compiled, with the load
average of each sample; and one sentence per II.7 threshold: `--hot-reload` versus
plain above about 10 % on `list_ops` (use `list_ops_nested`) → Model B first;
`enter_unit` versus `enter` measurable on `actor_ping` → hoist the read.
