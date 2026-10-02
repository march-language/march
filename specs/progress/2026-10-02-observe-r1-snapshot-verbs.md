# Observe R1: the snapshot layer, its verbs, and `forge observe`

**Date:** 2026-10-02
**Plan:** [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md), item R1.
**Tracking todo:** [`todos/2026-09-24-observe-recon-shell.md`](../todos/2026-09-24-observe-recon-shell.md).
**Builds on:** [`2026-10-01-observe-r0-socket.md`](2026-10-01-observe-r0-socket.md).

## What exists now

- **The snapshot layer** (`march_obs_actors`, `march_obs_actor_extra_get` in
  `runtime/march_runtime.c`, beside the actor table). One copy-out walk of the
  live actor table inside one reclamation critical section, the same walk as
  `march_actor_pid_indices`. Each row: pid, capability epoch, type name,
  status, mailbox depth (all / user), mailbox limit and policy, code epoch,
  scheduler, pinned, draining, supervisor pid and slot, number of children,
  registered names. The rows are plain data: sorting, tree building and JSON
  happen after the section, with no lock held. The crash message is never read
  (C7): `ACTOR` of a dead actor reports the death KIND only.
- **The verbs** (`runtime/march_observe_snapshot.c`, role `core`/`jit`),
  registered on the observe server through a new `march_observe_add_verbs` hook
  (the server file stays standalone, so `test_observe` still links it alone):

  | Verb | Data |
  |---|---|
  | `ACTORS [mbox\|status\|epoch\|pid] [n]` | `{total, shown, sort, actors:[row]}`; default `mbox 100`, n ≤ 10 000 |
  | `ACTOR <pid>` | `{pid, alive, cap_epoch, actor:row, children:[pid], supervisor:{strategy, max_restarts, window_secs, restarts_held, restart_ages_ms}, terminal:{kind}}`; `not_found` for a pid never spawned |
  | `TREE` | `{total, roots:[node], unsupervised:[pid], truncated}`; depth cap 64, node cap 10 000 |
  | `NAMES` | `{names:[{name, pid}]}` sorted by name |
  | `SCHED` | per-scheduler started/entered/dispatches/idle_polls, and the `march_sched_stat` globals by name |
  | `MEM` | `rss_bytes` (now), `peak_rss_bytes`, `live_objects` (the unconditional gauge, C13), `stacks_recycled`, `queued_messages`, `actors` |
  | `EPOCHS` | current epoch, pins, dispatch slots, hot-reload delivery counters |
  | `SNAPSHOT [s,...]` | the named sections (default all), the actor ones from ONE walk; each section is that verb's data |

  Bad arguments answer `"error":"bad_args"`.
- **`forge observe [REQUEST...] [--section S] [--json] [--socket PATH] [--env NAME]`**
  (`forge/lib/cmd_observe.ml`): one request, the reply envelope printed as JSON
  (indented, or one line per host with `--json`). Targets are the forge.toml
  `[hot-reload]` hosts over ssh (`--env` picks entries by name, as
  `forge hot-reload status` does), or a local observe socket with `--socket`.
  `Observe_client.query_socket` addresses a socket by its own path.

## Measured

- **100 000 idle actors** (compiled `--opt 2`, this Mac, load ~8), 11 queries
  each, median / max `took_us`: `ACTORS` 18.9 / 20.4 ms, `ACTORS mbox 10000`
  25.8 / 28.4 ms (2.2 MB reply), `TREE` 21.2 / 22.0 ms, `SNAPSHOT` 21.9 / 24.4 ms,
  `MEM` 10.7 / 11.5 ms, `NAMES` 8.8 / 9.9 ms. Target was < 50 ms; no cap needed.
  The walk itself is the ~9-11 ms of `NAMES`/`MEM`; the rest is sorting and JSON.
- **Concurrency.** 16 churner actors each spawning, registering, messaging and
  killing actors (and every 8th iteration a 2-child supervisor) in a loop, polled
  at ~100 Hz with every verb in rotation by a C poller:
  - macOS: 1 177 polls, 0 bad replies, worst `took_us` 23.4 ms.
  - Linux arm64 ASAN (Docker, `march-amdr-repro`): 3/3 runs clean, ~350 polls
    each, 0 bad replies, worst 26 ms. The full-size workload (8x more spawns)
    exhausts ASAN's shadow memory in the container WITH OR WITHOUT the socket
    (control run aborts the same way), so the ASAN legs use the reduced
    workload, as QW4 did.
- **ASAN corpus sweep** (rule 4: a new foreign-thread reader of proc and meta
  structs): every `test/native` fixture that spawns actors, minus network/FFI/HCR
  ones, 82 programs, each run with the observe socket on and the poller querying
  it for the program's lifetime. 81 exit 0 with no AddressSanitizer report.
  `sched_stress` aborts on ASAN shadow-memory exhaustion, and does so identically
  with no socket (2/2 control runs), so it is the container's limit, not R1.
- **A/B gate (rule 3).** The primary gate is the instruction-level one, and it
  holds: `march_scheduler.c` compiles to the same instructions on main and this
  branch (`-O2`, arm64, disassembly diffed), and in `march_runtime.c` the only
  changed functions are `march_actor_register`, `march_actor_register_child`,
  `march_actor_stop`, the three restart paths, `march_run_scheduler` (the
  install call) and `march_run_until_idle` (it inlines the latter). `march_send`,
  `march_spawn_common`, `find_meta` and the actor loop are byte-identical.
  Measured, `bench/actors/fanin_flood.march --opt 2`, n = 200 interleaved per arm:

  | Box | Arms | 1 scheduler | 8 schedulers |
  |---|---|---|---|
  | Linux arm64 container, load ≤ 3 | A/A | -0.00% (half-IQR 0.88%) | +0.32% (4.59%) |
  | | main vs branch | -0.04% PASS | -1.15% PASS |
  | | main vs branch, socket open and idle | +0.77% PASS | -0.54% PASS |
  | | main vs main + 1 unused function | | +0.37% |
  | macOS (dev Mac), load 9.6-11 | A/A | | -0.74% (6.86%) |
  | | main vs branch (3 runs) | +1.19%, +1.44% | +10.39%, +6.29%, +7.64% |
  | | main vs main + 1 unused function | | +4.79% |

  On the Mac, adding one never-called function to main's runtime moved the
  8-scheduler median by +4.8%: this benchmark there is sensitive to code
  placement, and the branch's executed code is unchanged. On the quiet Linux
  box every leg is inside the A/A noise. Sanity runs (Linux, 8 schedulers):
  `call_storm` +0.12% (n = 20); `spawn_churn` +5.64% (n = 20, half-IQR 6.3%),
  rerun at n = 100: +0.45% at 1 scheduler, -4.81% at 8.

## The design change the stress test forced

The first version read `sup_pe` under `g_tbl_mu` and the names under
`g_registry_mu`, one lock pair per actor, as the plan said. Under the churn test
that made replies wait **seconds** (worst 3.9 s for `SNAPSHOT`, 1.5 s for
`NAMES`; `SCHED`, which takes no lock, stayed at 34 µs): every per-meta
acquisition queued behind 16 actors spawning and dying. With the locks removed
(an experiment, not shipped) the worst reply was 22 ms.

What shipped: the writers of the fields the walk needs now store them with
`__atomic` stores (`sup_pe` released after `sup_child_index`; `sup_num_children`,
`dispatch_name_id`, `reg_name_count`; the proc's `owner_sched`, `mbox_limit`,
`mbox_policy`). They still hold whatever locks they held before; on arm64 and
x86-64 a relaxed store is the same instruction as a plain one, and the one on a
hot path (`owner_sched`, once per dispatch) is relaxed. The walk reads them
lock-free and takes `g_registry_mu` only for an actor whose count says it holds
a name. Worst reply under the same churn: 23 ms.

## Review fixes

An independent review of the diff found no memory-safety defect and no missed
writer, and these, all fixed:
- **A tree deeper than ~14 supervisors blanked the reply.** The JSON writer
  nested at most 32 levels while TREE allows 64 supervision levels (two JSON
  levels each), so a deep tree made `TREE`, and `SNAPSHOT` with it, answer
  `"data":null`. `MARCH_JW_MAX_DEPTH` is now 160, with a `_Static_assert` tying
  it to `TREE_MAX_DEPTH`, and `test_observe` writes 131 nested levels.
- `ACTOR <pid>` listed children with a children x actors scan; now one pass and
  a sort.
- `ACTORS 5 7` and `ACTORS mbox pid` were accepted (last one won); now
  `bad_args`.
- A failed `strdup` while copying names could leave a NULL inside the counted
  range; the array is compacted.
- The checker had no client timeout (a hung verb would hang the rule) and
  trusted the fixture's 300 ms sleep; it now times out each read after 10 s and
  first waits up to 20 s for the state its checks assume.

Not fixed, by design for R1: the walk copies every live actor even for
`ACTORS 10` (about 20 ms per 100 000 actors, held inside one reclamation
section). At millions of actors that should become a bounded top-N walk; R3's
`forge top` polls it, so it is noted there.

## Tests

- `test/test_observe.c` (41 checks, +9): 131-level nesting writes, nesting past the limit is refused, registration before start, refusal after
  start, a registered verb's arguments and error codes, `HELP` lists registered
  verbs with their tier.
- `test/native/observe_snapshot.march` + `test/observe_snapshot_check.ml`
  (golden `observe_snapshot.expected`, 29 checks): 3 supervisors x 4 children,
  5 bare actors, a 500-message burst on one, one supervised child crashed with a
  panic string. Asserts `ACTORS mbox 1` names the burst target with 500 queued,
  `TREE` has 3 roots of 4 plus 5 unsupervised, the one dead pid answers `ACTOR`
  with kind `Crash` and no other field, no reply to any verb contains the panic
  text, the supervisor's config and restart, `NAMES`, `SCHED`, `MEM`, `EPOCHS`,
  `SNAPSHOT` (all sections, one walk, a subset), every argument error, `HELP`.
- `test/native/observe_types_hr.march` (built `--hot-reload Main`): type names in
  rows, the dispatch slot in `EPOCHS`.
- Red checks: with the supervisor link dropped in the walk, 4 checks FAIL; with a
  `message` field added to `ACTOR`'s terminal object, 2 FAIL; with
  `march_observe_snapshot_install` removed from `march_run_scheduler`, the
  checker stops at its first query and the golden diff fails.
- `forge/test/test_observe_client.ml` (+3): `query_socket`, the request line,
  host selection from forge.toml.

## Deviations from the plan

1. **No `VERSIONS_DETAIL`/`PINS` refactor.** Both reload verbs are thin
   formatters over public accessors (`march_dispatch_*`, `march_epoch_pin_table`,
   `march_hcr_counters_get`); `EPOCHS` calls the same accessors. The reload
   verbs are untouched, so their byte-identity holds by construction and the
   planned golden is moot.
2. **Verbs in their own file** (`march_observe_snapshot.c`), registered through
   a hook, rather than inside `march_observe.c`, so the server's unit test keeps
   linking it alone.
3. **No per-meta locks** (above).
4. **The cluster section (R1.3) is split out** to
   [`todos/2026-10-02-observe-r1-cluster-section.md`](../todos/2026-10-02-observe-r1-cluster-section.md):
   it needs a new builtin (about nine sites) and a two-node test, and nothing
   else in R1 depends on it.
5. **`--host` is not a flag.** Hosts come from forge.toml by `--env` name, as
   every other forge command that talks to hot-reload hosts does, or from
   `--socket` for a local process.
6. **Type names only in `--hot-reload` builds**: they come from the dispatch
   table. Filed: [`todos/2026-10-02-observe-actor-type-names-without-hot-reload.md`](../todos/2026-10-02-observe-actor-type-names-without-hot-reload.md).
7. **Per-scheduler counters are still a racy read** of plain fields owned by
   each scheduler thread (`march_sched_thread_stat`, as before); R2 makes them
   atomics.

## Found on the way

- [`todos/2026-10-02-supervise-block-fails-to-compile-with-hot-reload.md`](../todos/2026-10-02-supervise-block-fails-to-compile-with-hot-reload.md):
  any `supervise` block fails in clang under `--hot-reload` (pre-existing; the
  reason the supervisor fixture is not also a hot-reload build).
- [`todos/2026-10-02-actor-call-held-messages-invisible-to-mailbox-count.md`](../todos/2026-10-02-actor-call-held-messages-invisible-to-mailbox-count.md):
  an actor blocked in `Actor.call` holds the messages that arrive meanwhile
  outside every mailbox count, so it looks idle to `mailbox_size`, `top_by_mailbox`
  and `ACTORS`.
- **The observe thread once failed to start on Linux.** In one run of forge's
  deploy e2e (`forge/test/test_deploy_e2e.ml`, a hot-reload node in an sshd
  container) the node logged `march: observe socket thread: Invalid argument`
  (R0 code: `pthread_create` with a 256 KiB stack), and the same run failed
  with `did not answer COMPACT after the restart`. Two reruns, one with this
  PR's fix disabled, passed with no observe message, so both are intermittent
  and the link between them is unproven. Thread creation now retries with the
  default stack on `EINVAL` (`spawn_detached` in `runtime/march_observe.c`),
  which glibc returns when a requested stack cannot hold the static TLS.
