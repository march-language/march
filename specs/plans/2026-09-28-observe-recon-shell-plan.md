# Observe, Recon, Shell: implementation plan

**Date:** 2026-09-28
**Status:** Specced; nothing built.
**Parent:** [`2026-09-24-observe-recon-shell-design.md`](../2026-09-24-observe-recon-shell-design.md)
(the design) and its todo [`todos/2026-09-24-observe-recon-shell.md`](../todos/2026-09-24-observe-recon-shell.md).
**Siblings:** [`2026-09-23-per-actor-introspection-design.md`](../2026-09-23-per-actor-introspection-design.md)
(push alarm, `inspect_state`, trace ring; adopted here as items R4 and R8) and
[`2026-09-21-distributed-authority-and-deploys-plan.md`](2026-09-21-distributed-authority-and-deploys-plan.md)
(epochs, drains, `forge deploy`, reconciler; untouched here).
**Ground truth:** every `file:line` below was read at `origin/main` `216f45fba`
on 2026-09-28. Line numbers drift; the function names are the stable handle.

This plan turns the design into PR-sized items. It also **corrects the design
where a review and a re-read of current code proved it wrong** (§C). Where the
two documents disagree, this plan wins, and the design's header says so.

Out of scope, as in the design: process orchestration, hot-upgrade mechanics,
certificates and link encryption, a metrics bus, and defining types or actors
from the shell.

---

## Summary

| # | Item | Size | Needs | Unlocks |
|---|---|---|---|---|
| R0 | Groundwork: observe socket thread, JSON writer, test harness | 3 days | — | everything |
| R1 | Snapshot layer + observe verbs (no new counters) | 1 week | R0 | R2, R3, R6 |
| R2 | Counters (slices, msgs in/out, last active), scheduler idle time, crash ring | 1 week | R1 | R3, R6 |
| R3 | `Recon` observe tier, `forge top`, `forge diagnose`, `forge status` | 1 week | R2 | — |
| R4 | Debug tier: `Actor.Debug`, `inspect_state` (introspection B1), `STATE`, `MESSAGES` | 2 weeks | R1 | R5, R8, R10 |
| R5 | Remote shell groundwork: nonces, body hashing, name-table pinning, fragment build | 2 weeks | R4 | R6-shell |
| R6 | `forge rpc` / `forge shell` over signed `EVAL` | 1.5 weeks | R5 | R11 |
| R7 | `forge observe` TUI, `WATCH`, crash dump | 1.5 weeks | R2 | — |
| R8 | Tracing with mandatory limits (introspection C1/C2) + boundary call tracing | 2 weeks | R4 | — |
| R9 | `forge release build` + `bin/<app>` launcher | 4 days | R3 | — |
| R10 | `Recon.which` / `Recon.source` | 3 days | R4 | — |
| R11 | Transcripts, `--env` fan-out, notebook attach, `Observe.serve_http` | 1–3 days each | R6, R3 | — |

R0–R3 need no compiler change and no signing. They are the first PRs and can
merge while R4+ is still being argued. R5 is the security-sensitive one and
gets a dedicated review before R6 starts. R7, R8, R9, R10 are independent of
each other once their prerequisite lands.

Critical path to a working remote shell: R0 → R1 → R4 → R5 → R6, about seven
weeks of focused work. Critical path to "an on-call engineer can see what a
node is doing": R0 → R1 → R2 → R3, about three weeks.

---

## C. Corrections to the design

Each row is a claim the design makes that current code contradicts, and what
this plan does instead. The review of 2026-09-25 found C1–C9; the
re-read of 2026-09-28 found C10–C14.

| # | Design said | Actually | This plan |
|---|---|---|---|
| C1 | Fragments call app functions "through the dispatch table at the node's current epoch". | Call sites bake an integer NAME_ID (`lib/tir/llvm_emit_call.ml:374-393`), and ids are `List.sort_uniq` over *the build's own* boundary names (`lib/tir/hot_reload.ml:83-110`). A fragment build that adds names shifts ids and calls the wrong slot. | R5.3: the compiler takes the node's id table (from `ABI_QUERY`) and assigns ids from it. |
| C2 | Attach refuses unless the client reproduces the node's `cas_hash`. | `cas_hash` mixes in the compiler executable's bytes, target, flags and signing key (`bin/main.ml:876`, `:1000-1014`), and a fragment build adds a `compile-so` tag. It can never match. | R5.4: attach compares **per-function `impl_hash`** for every boundary function the fragment reaches, plus a collision-set tag digest. Unison's idea at the right granularity. |
| C3 | A fragment is "a few hundred KB, only `__eval`". | A `--compile-so` patch is the whole program's IR, app plus stdlib, runtime symbols undefined (`bin/main.ml:3752-3779`). | R5.5: a `--fragment` emission mode; R5.1 measures today's patch size first so the win is known. |
| C4 | The node checks the fragment's cap markers, "not the client's word". | `cap_root` is recomputed over the client-sent `caps:` list (`runtime/march_reload.c:1295`, `compute_cap_root`). | R5.6: the compiler emits a `__march_cap_manifest` string in every patch; after `dlopen` the node recomputes `cap_root` from it and requires equality with the signed root. |
| C5 | A fragment over budget "is killed at its next preemption check, the same way any actor is". | Reductions only preempt. Deadline cancellation exists for **tasks** (`cancel_requested` + `march_sched_cancel_point`, `runtime/march_scheduler.c:3180-3208`), not actor procs. | R6.2: `__eval` runs as a task; timeout sets `cancel_requested` on that proc and raises `march_preempt_request`. |
| C6 | Moving `DRAIN` to the signed tier closes its todo. | Already fixed and signed on 2026-09-24 (`specs/progress/2026-09-24-dd-review-drain-current-epoch-kills-every-actor.md`). | Dropped from scope. |
| C7 | The observe tier shows crash reasons. | Crash messages are user `panic` strings and can hold payloads. | Observe shows the crash **kind** (`Crash`/`Killed`/`Normal`/`draining`) and type; message text is debug tier. |
| C8 | Counters are plain stores read with relaxed loads. | That is a C11 data race. | `_Atomic uint64_t` with `memory_order_relaxed` store and load: same instruction on x86-64 and arm64. |
| C9 | Crash dumps run the snapshot layer from a signal handler. | JSON building allocates; not async-signal-safe. | R7.4: dumps on `march_panic`'s unsupervised path and on `abort` only, never from a fatal-signal handler. |
| C10 | Observe verbs go on the existing socket. | The server is **one thread serving one client at a time** (`march_reload.c:2470-2513`, `handle_client` inline). ACTIVATE6 keeps state in static buffers (`:2054-2059`). A connected observer would block deploys. | R0.1: a **separate observe thread and socket** (`MARCH_OBSERVE_SOCKET`). The reload server is not touched until R5. |
| C11 | Per-actor `reds_total` from consumed budget. | Compiled code never decrements `p->reductions`; it polls `march_preempt_request` (`march_scheduler.c:2652-2673`). Consumed reductions are not measurable. | R2: count **slices** (dispatches of this proc) instead, and an optional `run_ns` behind the armed flag. |
| C12 | Scheduler `busy_ns` from two clock reads per dispatch. | Would cost ~40 ns per dispatch; the gate is 1%. | R2.3: time only the **idle** path, which already sleeps 1 ms (`march_scheduler.c:1964-1973`). Utilisation = 1 − idle/wall. Zero cost when busy. |
| C13 | String/heap live counters become always-on. | `MARCH_STRING_STATS` counters are atomic and gated (`march_runtime.c:135-224`); making them always-on adds an RMW per allocation. | `MEM` uses the unconditional live-object gauge (`march_live_slot`, `march_runtime.c:292-392`) only. |
| C14 | Signed lines are safe to accept. | No nonce or expiry; any captured signed line can be replayed (`march_dispatch.c:643-646`). `CAS_PUT` never hashes the body (`march_reload.c:1636`). | R5.2: `EVAL` carries `nonce:` and `not_after_ms:`; R5.2 also hashes uploads. |
| C15 | Design §1.5 reuses `lib/repl/tui.ml`. | 164 lines, REPL-specific, and `march_repl` drags typecheck, eval and JIT into forge. | R7: add `notty` to `march_forge` directly. |
| C16 | Open question 1 (can the socket thread enter a reclamation critical section?). | Yes. Slots are per OS thread, registered lazily (`runtime/march_reclaim.h:30-35`); the preempt daemon already reads procs this way (`march_scheduler.c:3615-3690`). | Resolved. The rule that binds: never park or sleep inside a section. |
| C17 | The design cites a private memory note. | Not a repo artifact. | Removed from the design. |

---

## Apparatus rules for every item

These are the traps that have produced vacuous greens in this repo. Each item's
Acceptance assumes them.

1. **Runtime edits must be restaged.** A `runtime/*.c` change is invisible to
   `dune build bin/main.exe`; build a target that restages `_build/default/runtime`
   (any native test rule, or `scripts/run-tests.sh`, which does). Prove a test
   goes RED with the change reverted before trusting GREEN.
2. **New `.c` files** need a `runtime/sources.list` line with a role, and
   `scripts/check-runtime-sources.sh` must pass. The link lists in
   `bin/main.ml`, `bin/toolchain.ml` and `test/test_helpers.ml` follow it.
3. **Cost gates are same-box A/B**, never absolute ms: two compilers, one built
   at the base commit, `bench/actors/fanin_flood.march` compiled
   (`--compile --opt 2`), n ≥ 40 interleaved runs per arm, load average < 10
   (read it with `sysctl -n vm.loadavg`, space-separated). Fail if the
   `MARCH_NUM_SCHEDULERS=1` median moves more than 1%, or the 8-scheduler
   median moves more than the base arm's own p25–p75 half-width. Also run
   `bench/actors/call_storm.march` and `spawn_churn.march` once each as a
   sanity check.
4. **ASAN runs in Docker** (this Mac hangs ASAN binaries). Any item that adds a
   foreign-thread reader of proc or meta structs runs the ASAN corpus sweep on
   Linux before merge.
5. **Never pipe `march --compile`**; redirect to a file.
6. **Private `HOME`** for any test that touches `~/.march/cas` or the audit log.
7. `scripts/run-tests.sh` does **not** run forge suites; forge items run
   `dune test forge/test --root .` too.

---

## R0. Groundwork (3 days)

**Why.** Everything else needs a socket that does not block deploys (C10), a
JSON writer in C, and a test harness shaped like the one the reload server
already has.

**What.**

1. **`runtime/march_observe.c` + `.h`**, role `core` in `runtime/sources.list`
   (so it links in every native binary, cross-Linux included, unlike
   `march_reload.c` which is dropped there, `bin/main.ml:3698-3704`).
   - `void march_observe_server_start(const char *path)`: no-op on NULL or
     empty. Creates a Unix socket at `path` with mode `0600`, one detached
     pthread (stack 1 MiB), `accept` loop, **one short-lived detached thread
     per connection**, capped at 8 concurrent (the 9th gets `ERR busy` and a
     close). Each connection reads one line, answers, and closes, except
     `WATCH` (R7).
   - Line reader copied from `march_reload.c:476` (`read_line`), max 4096.
   - Verbs: `HELP`, `PING` only in R0.
2. **Start it from every `@main`.** In `lib/tir/llvm_toplevel.ml`, next to the
   `hr_setup` block (`:1024-1029`) but **outside** the `--hot-reload`
   conditional: `getenv("MARCH_OBSERVE_SOCKET")`, call
   `march_observe_server_start`. When unset and `MARCH_HOT_RELOAD_SOCKET` is
   set, default to `<reload_socket>.observe`. Not emitted under
   `--compile-so` (no main) or WASM.
3. **JSON writer** `runtime/march_json_out.c/.h` (role `core`): a bounded
   growable buffer with `jw_obj_begin/end`, `jw_arr_begin/end`, `jw_key`,
   `jw_str` (escaping per RFC 8259), `jw_i64`, `jw_u64`, `jw_f64`, `jw_bool`,
   `jw_null`. No allocation after a caller-supplied cap is hit: it sets
   `truncated` and the envelope reports it. `march_reload.c` has private JSON
   helpers for the audit log (`json_write_str`, `:552-629`); leave them.
4. **Envelope** on every reply:
   `{"proto":"march.observe/1","node":<MARCH_NODE_NAME or pid>,"at_ms":…,"took_us":…,"truncated":false,"data":…}`.
5. **Test harness** `test/test_observe.c` modelled on
   `test/test_reload_activate4.c:120-160` (`connect_sock`, `send_line`,
   `read_resp`), linked against the full runtime like `test_hcr_migrate_order`
   (`test/dune:410-437`). A tiny JSON checker in the test (or `jq` if
   present, skip-with-message if not; never skip silently).
6. **Native test** `test/native/observe_ping.march`, a program that sleeps
   2 s, compiled **without** `--hot-reload`. The dune rule runs it with
   `MARCH_OBSERVE_SOCKET` set and, while it runs, a tiny C client
   (`test/observe_client.c`, built by the same rule; the stdlib `Socket`
   module has no Unix-domain connect) sends `PING` and diffs the reply
   against `.expected`. Proves the socket starts in a non-hot-reload binary.
7. **Forge client module** `forge/lib/observe_client.ml`: `query : Remote.transport -> Hosts.host -> string -> (Yojson.Safe.t, string) result`,
   reusing `Remote.use_socket` / `Remote.connect_with_timeout`
   (`forge/lib/remote.ml:60-80`) and `Cmd_deploy_hot.send_line`/`recv_line`
   (`:570-579`). Host gains an optional `observe_socket`; default
   `<socket>.observe`.

**Acceptance.** `test_observe` connects to a runtime started in-process, gets
`PONG`, gets `HELP` listing `PING`/`HELP` with tier `observe`, and a 9th
concurrent connection gets `ERR busy`. The native test passes compiled and is
RED with the `llvm_toplevel.ml` call removed. `check-runtime-sources.sh` is
green. A deploy (`test_reload_activate4`) passes unchanged while an observe
client holds a connection open.

---

## R1. Snapshot layer and observe verbs (1 week)

**Why.** The design's first rule: one C layer answers both the socket and
`Recon`. This item builds it from fields that already exist, with no new
counters, so it cannot move a benchmark.

**What.**

1. **Snapshot functions** in `march_observe.c`, each writing into a
   `march_jw *`:
   - `obs_actors(jw, sort, n)`: walk `g_actor_tbl` exactly as
     `march_actor_pid_indices` does (`march_runtime.c:9905-9945`), inside one
     `march_reclaim_enter`/`exit`. Per linked meta, copy out: pid, actor type
     name (`dispatch_name_id` → `march_dispatch_id_to_name`,
     `runtime/march_dispatch.h:83`), `reg_names` (read under runtime's `g_registry_mu`,
     `march_runtime.c:3339`; copy the strings, drop the lock), `draining`,
     `hcr` epoch fields (`:2331-2336`), `sup_pe != NULL`, `sup_num_children`.
     From the proc (`meta_gt`): `status` (`march_scheduler.h:156-166`),
     `mbox_count`, `user_mbox_count`, `mbox_limit`, `mbox_policy`,
     `stack_size`, `owner_sched`, `code_epoch`, `pinned`, `is_daemon`.
     **Never** read `crash_message` here (C7).
     Rows go to a stack-allocated array first; sorting and truncation happen
     after `march_reclaim_exit`. No lock is held while writing JSON.
   - `obs_actor(jw, pid)`: one row plus supervisor config
     (`:2278-2288`), restart timestamps (copied under `g_supervise_mu`,
     `:4799`), children as pids (via `meta_pin` for the supervisor record,
     `:3254-3272`), terminal reason from the tombstone (`march_pid_entry`,
     `:2194-2213`) as **kind only**.
   - `obs_tree(jw)`: roots are actors with `sup_pe == NULL` and
     `sup_num_children > 0`; recurse through `sup_children`. Depth-capped at
     64, node-capped at 10 000, `truncated` otherwise. Bare-spawned actors are
     listed under a synthetic `"unsupervised"` root (open question 4 of the
     design stays open; see R2.6).
   - `obs_names(jw)`: `march_actor_registered` (`:3461`) plus reverse
     lookups; cluster names come in R1.3.
   - `obs_sched(jw)`: per scheduler `march_sched_thread_stat` (`march_scheduler.c:406-416`):
     started, entered, dispatches, idle_polls; globals from `march_sched_stat`
     0–11 (`:378-404`).
   - `obs_mem(jw)`: RSS now (`getrusage`/`mach_task_basic_info`), peak
     (the existing `peak_rss_bytes` helper behind `System.mem_peak_bytes`), the
     unconditional live-object gauge (`march_live_slot` sum), recycled stacks
     (`sched_stat`), mailbox nodes live (sum of `mbox_count` from the actor
     walk; reported, not re-walked).
   - `obs_epochs(jw)`: move the body of `VERSIONS_DETAIL` + `PINS`
     (`march_reload.c:1583`, `:2338`) into a shared function in
     `march_dispatch.c` that fills a struct; both the reload verbs and
     `obs_epochs` call it. The reload verbs' text output must stay
     byte-identical (forge parses it).
2. **Verbs:** `SNAPSHOT [sections]`, `ACTORS [sort] [n]` (sort: `mbox`,
   `status`, `epoch`; n ≤ 10 000, default 100), `ACTOR <pid>`, `TREE`,
   `NAMES`, `SCHED`, `MEM`, `EPOCHS`. `HELP` lists them with arity and tier.
3. **Cluster section** is published by March code, read by C. `ClusterNode`
   already mirrors members and names into Vault tables
   (`stdlib/cluster_node.march:52-54`); it cannot be called from the observe
   thread (no March code may run on a foreign thread). So: a stdlib-only
   builtin `observe_publish_section : String -> String -> Unit` copies a
   JSON string into a C table (name → owned string, under a small mutex),
   and `CLUSTER` returns the stored string verbatim inside the envelope with
   its `published_at_ms`. `ClusterNode`'s ticker publishes `"cluster"` on
   every SWIM period (1 s by default), so the section is at most one period
   stale and is reported as such. Before `ClusterNode.start` runs, `CLUSTER`
   returns `{"available":false}`. Programs can publish their own sections the
   same way; `SNAPSHOT` includes every published one.
4. **Forge:** `forge observe --json [--host H | --env E] [--section S]`
   prints the envelope. No TUI yet.

**Acceptance.**
- `test_observe` spawns 3 supervisors × 4 children plus 5 bare actors, sends
  a burst to one, and asserts `ACTORS mbox 1` names it, `TREE` has 3 roots with
  4 children each plus the unsupervised root with 5, `ACTOR` of a dead child
  reports kind `Crash` and **no message text**.
- A concurrency test: 16 threads spawning and killing actors for 5 s while the
  socket is polled at 100 Hz. Linux ASAN (Docker) clean.
- `ACTORS` over 100 000 idle actors: `took_us` recorded in
  `specs/progress/` (target < 50 ms; if it misses, the verb gets a hard n cap
  and a note, not a redesign).
- `forge hot-reload status` output is byte-identical before and after the
  `VERSIONS_DETAIL` refactor (golden captured from `test_reload_activate4`).
- A/B gate (rule 3) shows no movement, run once to prove the socket thread
  idle costs nothing.

---

## R2. Counters, scheduler idle time, crash ring (1 week)

**Why.** Observer's `Reds`/`MsgQ` pivots and recon's `proc_window` need
cumulative per-actor numbers. The crash ring is what `diagnose` reads first.

**What.** Three commits, each with its own A/B.

1. **Per-proc counters** in `march_proc` (`runtime/march_scheduler.h:238-483`),
   one cache line at the end so no existing field moves:
   `_Atomic uint64_t slices, msgs_in, msgs_out, last_run_ms;` (C8, C11).
   - `slices`: incremented at the slice start in `sched_loop`, next to
     `stat_dispatches++` (`march_scheduler.c:2027-2029`). Owner scheduler
     writes; relaxed.
   - `last_run_ms`: same site, from the scheduler's cached coarse clock if one
     exists; otherwise add a per-scheduler `now_ms` refreshed on the idle path
     and every 1024 dispatches. Never a syscall per dispatch.
   - `msgs_in`: in the dequeue after `mbox_unlink` (`march_scheduler.c:3113`),
     user messages only (skip markers and control). Receiver writes.
   - `msgs_out`: in `march_send` after `march_sched_send` returns success
     (`march_runtime.c:7076`), on `march_sched_current()` (`:2594`) when
     non-NULL. Read the TLS **after** any park in the BLOCK-policy path
     (`march_scheduler.c:2960-2975`), never cached across it. Remote sends
     (`Node.send`) are counted in R3 at the stdlib wrapper (design open
     question 2, resolved "yes").
   - Interpreter parity: same four fields on `actor_inst`
     (`lib/eval/eval_runtime.ml:207`), incremented at the matching points, so
     `Recon` tests run on both backends.
2. **Scheduler idle time** (C12): `_Atomic uint64_t idle_ns` and `started_ns`
   on `march_scheduler` (`march_scheduler.h:504-507`). On the idle path
   (`march_scheduler.c:1964-1973`), read the monotonic clock before
   `march_reclaim_offline()` and after `march_reclaim_online()`, add the
   difference. Nothing on the busy path. `SCHED` reports
   `utilisation = 1 - Δidle/Δwall` over two samples taken `window_ms` apart
   (the socket thread sleeps between them **outside** any critical section).
   Pad `g_scheds` entries to 64 bytes while here (`march_scheduler.c:127`);
   measure separately, since padding alone can move the 8-scheduler number.
3. **Crash ring**: `static march_crash_report g_crash_ring[256]` +
   `_Atomic uint64_t g_crash_seq`, written under a new leaf mutex
   `g_crash_mu` (crashes are rare; never taken on a hot path). Fields: seq,
   pid, type name id, kind, message (copied, truncated at 512 bytes), epoch,
   supervisor pid, restart number, `at_ms`, and a short backtrace string when
   `MARCH_BACKTRACE` is set. Write sites:
   - supervised crash landing, just before `do_actor_death(…CRASH…)`
     (`march_runtime.c:4435`);
   - `march_panic`'s unsupervised path before `exit(1)`
     (`march_runtime.c:1545-1550`), so the crash dump (R7.4) sees it;
   - `hcr_hard_kill` (`:6372-6404`) with kind `draining`.
   The ring entry for a supervised crash is written in `do_actor_death`
   (`:5688`) right after its call to `march_supervisor_notify` (`:5815`), so
   `crash_streak` (`:5313-5317`) is already updated; read it under
   `g_supervise_mu` there, never at the panic landing site.
   Each entry is also emitted through `Logger` at `error` with fields (compiled
   today that is the stderr fallback; fine).
4. **Verbs:** `CRASHES [n]` (observe tier: kind, type, pid, epoch, supervisor,
   `at_ms`, restart number; message text withheld until R4 adds the debug
   tier), `TOP <attr> <n> [window_ms]` with attr in
   `mbox|slices|msgs_in|msgs_out|stack|crashes` (windowed attrs rank deltas
   between two walks).
5. **Rows** from R1 gain `slices`, `msgs_in`, `msgs_out`, `last_run_ms`,
   `crashes` (count of ring entries for that pid in the last hour).
6. **`spawned_by`** (design open question 4): one `int64_t` on the meta, set
   at spawn from `march_sched_current()`'s actor pid, never updated. `TREE`
   uses it to nest bare-spawned actors under their spawner. Separate commit;
   drop it if the A/B on `spawn_churn` moves.

**Acceptance.**
- A native test with a ping-pong pair: after N round trips, `ACTOR` shows
  `msgs_in == msgs_out == N` on each side (exact; there is no concurrency in a
  pair). Same test interpreted gives the same numbers.
- `SCHED` on an idle node reports utilisation < 5%; with 4 CPU-bound actors on
  4 schedulers, > 90%.
- A supervisor whose child panics 3 times: `CRASHES 10` has 3 entries with
  restart numbers 1, 2, 3 and no message text.
- A/B gate (rule 3) per commit: counters, idle time, padding, `spawned_by`.
  Results table in `specs/progress/`. A commit that fails the gate is
  reverted, not tuned in place.

---

## R3. `Recon` observe tier, `forge top`, `forge diagnose`, `forge status` (1 week)

**Why.** Operators need the scriptable plane first; programs need the same
numbers from March code.

**What.**

1. **Builtins** (the nine-site checklist; model on `sched_stat`, whose sites
   are `typecheck_builtins.ml:980`, `eval_builtins.ml:337-347`,
   `llvm_builtins.ml:1028-1029` and `:1849`, `defun.ml:97`, `purity.ml:91`,
   `test/test_codegen.ml:14062`, plus the stdlib-only table at
   `typecheck_env.ml:1630`). All stdlib-only:
   - `observe_query : String -> String` returns the same JSON the socket
     returns for a verb line. One builtin, not one per verb: the verb set can
     grow without touching nine sites again. Marked impure.
   - Interpreter: `lib/eval/eval_builtins.ml` builds the same JSON from
     `actor_registry` (`eval_runtime.ml:262`).
2. **`stdlib/recon.march`**, observe tier only, all taking
   `Cap(Actor.Introspect)`:
   `info(c, pid) : Option(ActorInfo)`, `proc_count(c, attr, n)`,
   `proc_window(c, attr, n, window_ms)`, `tree(c) : List(SupNode)`,
   `scheduler_usage(c, window_ms) : List((Int, Float))`,
   `node_stats(c) : NodeStats`, `crashes(c, n) : List(CrashReport)`,
   `epochs(c) : EpochReport`. Decoding uses `stdlib/json.march` with typed
   records (`derive Json`). Doctests per the stdlib conventions (`march>`).
3. **`stdlib/diagnose.march`**: the eight findings of design §5.3, each a
   pure function over one or two `NodeStats` snapshots returning
   `List(Finding)`; `Finding = {id, severity, rows, next}`. Pure functions
   mean the tests are table-driven with hand-built snapshots, no live node.
4. **`forge top [--host H|--env E] [--sort attr] [--window ms] [--once]`**:
   plain ANSI redraw (no TUI library yet), 20 rows, refresh every
   `max(1 s, 4 × took_us / 1e6 s)`. `--once` prints one frame for scripts and tests.
5. **`forge diagnose [--host H|--env E] [--window ms] [--dump FILE]`**: forge
   is OCaml and cannot call `diagnose.march`, so the eight findings are ported
   to `forge/lib/diagnose.ml` over the JSON. `diagnose.march` stays for
   in-program use. Both are tested against the **same** fixture snapshots
   (`forge/test/fixtures/diagnose/*.json`) and must produce the same finding
   ids, so they cannot drift silently. Output:
   `{"proto":"march.diagnose/1","findings":[…],"coverage":{…}}`, exit
   `0/1/2/3` as designed.
6. **`forge status [--env E] [--json]`**: a top-level command. When a
   topology exists, it wraps `Reconcile.status_text` (`forge/lib/reconcile.ml:993`)
   and appends per-node observe data (crash count last hour, utilisation,
   largest mailbox). Without a topology it uses `[hot-reload]` hosts. Register
   in `forge/bin/main.ml` (`known_builtin_names` `:15-21`, `cmds`
   `:1776-1779`).
7. **Remote sends**: `Node.send` increments the caller's `msgs_out` through a
   stdlib-only builtin `observe_count_send : Unit -> Unit`.

**Acceptance.**
- `test/stdlib/recon_test.march` (run by `scripts/run-tests.sh stdlib_march`)
  checks `info`, `proc_count`, `tree` on both backends.
- `forge/test/test_diagnose.ml`: each finding fires on its fixture and not on
  `healthy.json`; `diagnose.march`'s test runs the same fixtures and gets the
  same finding ids.
- `forge/test/test_observe_cli.ml` against a fake observe server (pattern:
  `fake_reload_server`, `forge/test/test_reconcile.ml:159`): `forge top --once`
  and `forge status --json` render the fixture.
- One real-binary test (`(rule (alias runtest))` with `MARCH_TEST_BIN`,
  pattern of `test_topology_run`): a native program with a runaway mailbox;
  `forge diagnose` exits 2 with `mailbox.growth`.
- CHANGELOG `### Added`: `forge top`, `forge diagnose`, `forge status`,
  `Recon`.

---

## R4. Debug tier (2 weeks)

**Why.** State and payloads are what incidents actually need, and they must
sit behind a stronger gate than counts.

**What.**

1. **`proof cap Debug`** in `stdlib/actor.march` beside `Introspect` (`:62`),
   minted by `Actor.debug(io : Cap(IO)) : Cap(Actor.Debug)`.
2. **Introspection design stage B1 exactly as specced there** (§4.4 of that
   design): the reserved `MARCH_SYS_INSPECT_TAG`, the generated per-actor
   `Name_inspect` renderer, `Actor.inspect_state(d, pid, timeout_ms) :
   Result(String, InspectError)`. Handled in `actor_green_thread` beside the
   epoch-marker skip (`march_runtime.c:4511`).
3. **Debug verbs on the observe socket**, signed:
   `STATE <sig> nonce:<hex> not_after_ms:<t> pid:<p> timeout_ms:<t>`,
   `MESSAGES … pid:<p> n:<n>` (n ≤ 100, renders queued messages through the
   same generated renderer; the mailbox is walked under `mbox_lock` and
   copied out as rendered strings, never as heap values), `CRASHES_FULL`
   (message text). Signing: factor `verify_signed_line`
   (`march_reload.c:856-880`) into `march_sig.c` (role `core`) so both
   servers use it; the pubkey is the compiled-in `MARCH_SIGNING_PUBKEY_HEX`, which
   the driver passes on the one command line that compiles every runtime
   source (`bin/main.ml:3678`, `:3859`), so a `core`-role `march_sig.c` sees
   it too. A binary without a key answers `ERR signing_not_configured` to
   every debug verb, as the reload server does.
4. **Replay protection** (C14), shared with R5: `march_sig.c` keeps a
   256-entry ring of seen nonces per process and rejects a nonce it has seen
   or a `not_after_ms` in the past; clients send `now + 30 s`. Clock skew
   beyond 30 s is an error the client reports clearly.
5. **Policy**: `$MARCH_DEPLOY_POLICY` is a flat cap list today
   (`march_reload.c:1213-1240`). Add an optional second file,
   `$MARCH_DEBUG_POLICY`, listing allowed debug verbs one per line (default:
   none allowed when the file is absent **and** the key is present; operators
   opt in). Keeping it a separate file avoids changing the deploy policy
   parser that ACTIVATE6 depends on.
6. **Audit**: every debug verb appends a line to the existing audit log with
   `"type":"debug"`, verb, pid, signer, nonce. Reuse the writer at
   `march_reload.c:552-629` by moving it into `march_sig.c`.
7. **Forge**: `forge observe --host H --state PID` and `--messages PID` sign
   with the deploy key (`March_ed25519.Ed25519.sign_str`, as
   `Cmd_deploy_hot` does at `:1394`).

**Acceptance.**
- Introspection design B1's own acceptance list.
- `test_observe`: unsigned `STATE` → `ERR bad_signature`; replayed nonce →
  `ERR replay`; expired → `ERR expired`; no policy entry → `ERR policy`;
  valid → rendered state; every attempt audited.
- A/B gate: the inspect tag check sits in the actor loop, so run it.

---

## R5. Remote-shell groundwork (2 weeks, then a security review)

**Why.** C1–C4 and C14 are each a way for the shell to run the wrong code or
the wrong authority. They are fixed here, before any `EVAL` exists.

**What.**

1. **Measure first.** Build a hot-reload patch for `bench/actors/call_storm.march`
   and for a mid-size app (the conduit test app if available, else the
   largest `test/two_node` program). Record `.so` size and `dlopen` time in
   `specs/progress/`. This number decides whether R5.5 is a must or a
   later optimisation.
2. **Body hashing** (C14): `CAS_PUT` computes BLAKE3 of the received bytes and
   stores the digest beside the artifact. New signed verbs (EVAL) sign
   `so_blake3:<hex>`, and the server compares it with the stored digest before
   `dlopen`. Existing ACTIVATE verbs are unchanged in this item; file a
   todo to extend them.
3. **Pinned NAME_IDs** (C1): a compiler flag
   `--hcr-name-table FILE` where FILE is the node's `ABI_QUERY` output
   (`SLOT <id> <name> <impl> <sig> [callers:]`, `march_reload.c:1545-1560`).
   `Name_table.build` (`lib/tir/hot_reload.ml:83-110`) then assigns ids from
   the file for every name it contains, and **fails the compile** if the
   fragment would dispatch to a name absent from the file. Ids for the
   fragment's own new functions are never dispatched (they are not boundary
   slots on the node); calls to them stay direct.
   Unit tests in `test/test_hot_reload.ml`; a TIR snapshot fixture showing a
   baked id that differs from the sorted default.
4. **Attach identity** (C2): forge fetches `ABI_QUERY` and `HCR_INFO`,
   compiles the fragment with the pinned table, and compares, for every
   boundary function the fragment reaches through dispatch, the client's
   `impl_hash` with the node's. Any mismatch is a hard stop listing the
   functions and both hashes. `--force` allows it only for read-only
   fragments (no `Actor.Debug` in the fragment's caps) and marks the session
   `[skew]`. Collision-set constructor tags (`llvm_toplevel.ml:698-703`) get a
   compiler-emitted marker `__march_hcr_tags` (BLAKE3 of the ordered
   type-name list) beside the existing identity markers, reported by
   `HCR_INFO` as `tags:<hex>`; a mismatch is a hard stop even with `--force`. Actor message tags are hashed
   (`llvm_toplevel.ml:583-620`) and record shapes are interned in the host
   runtime (`march_extras.c:2387-2413`), so neither needs a check.
5. **`--fragment` emission** (C3): with `--fragment NAME`, lowering keeps only
   the fragment module's functions, their non-boundary transitive callees from
   the app, and stdlib functions they reach; boundary callees become
   dispatch-only references (no body). Hidden visibility as today. Built on
   the existing `--compile-so` path (`bin/main.ml:3752-3779`); `--fragment`
   implies `--hot-reload <Prefix>` so the identity markers the loader checks
   (`march_hcr_patch_identity_ok`) are present. If R5.1 shows a
   whole-program patch is small enough (under 2 MB and under 20 ms to
   `dlopen`), defer this step and file it; correctness does not depend on it.
6. **Marker check** (C4): today's cap markers are one symbol per cap
   (`@__march_cap_<path> = constant i8 1`, `llvm_toplevel.ml:1652`) and forge
   reads them with `nm` (`forge/lib/cap_binary.ml:22`); there is no
   in-process reader, and walking a loaded image's symbol table differs per
   platform. So the compiler additionally emits, in every `--hot-reload` or
   `--fragment` `.so`, one symbol `__march_cap_manifest`: a NUL-terminated
   string of the sorted, normalised cap paths joined by `\n`, the exact
   input of `compute_cap_root`. After `dlopen` the server `dlsym`s it,
   recomputes the root, and requires it to equal the signed `cap_root`.
   What this proves: the signed line describes *this* artifact, so a stale
   or buggy client cannot deploy a fragment under a narrower declaration
   than the compiler gave it. What it does not prove: anything about a
   signer who edits both. That is the deploy key's trust, and it is the
   same trust `ACTIVATE` already places in it. `forge cap inspect` gains a
   check that the manifest and the per-cap markers agree. Test: a `.so`
   whose manifest is patched to drop one cap is refused with `ERR cap_tamper`.
7. **Type-directed rendering**: the fragment's `__eval` returns
   `show(result)`. For types without a `Show` impl, the fragment build runs
   `derive Show` (`lib/desugar/desugar_derive.ml:297`) on demand for the
   result type and every type it reaches, **inside the fragment only**, so
   the node's types are not changed. Opaque runtime types (Pid, closures,
   Vault handles) use the existing `march_value_to_string`. Spike first: if
   on-demand derive for a type declared in another module is not possible
   without re-typechecking that module, fall back to the REPL's approach and
   return a heap walk description, and record which.

**Acceptance.**
- Each of 2–6 has a test that goes RED with the change reverted.
- **Security review** of R5 as a unit by someone who did not write it, with
  the threat model: an attacker who can reach the socket but lacks the key;
  an attacker who captured one signed line; an operator whose checkout is one
  commit behind the node; a fragment that under-declares its caps.
  Findings filed as todos before R6 merges.

---

## R6. `forge rpc` and `forge shell` (1.5 weeks)

**What.**

1. **`EVAL` verb on the reload socket** (not the observe socket: it loads
   code, and the reload server already owns `dlopen`, CAS and activation
   bookkeeping). Signed line:
   `EVAL <name> so_blake3:<h> cas_hash:<c> epoch:<E> cap_root:<r> nonce:<n> not_after_ms:<t> timeout_ms:<t> caps:<csv> src_b64:<s>`.
   Flow: verify signature, nonce, expiry (R4.4); check body digest (R5.2);
   check policy against `$MARCH_SHELL_POLICY` (a flat cap list like the
   deploy policy; absent means **deny all**); `dlopen`; marker check (R5.6);
   spawn `__eval` as a **task** from the server thread
   (`sched_spawn_common` accepts a foreign thread, `march_scheduler.c:1705-1735`)
   at the current epoch; wait on a condition the task signals, **outside**
   any reclamation section; reply `OK <b64 result>`, `TIMEOUT`,
   `PANIC <b64 msg>` or `ERR …`. Audit line with the full source.
   While a fragment runs, the reload server is blocked (it serves one client).
   That is acceptable for v1 and stated in `forge shell --help`; the
   `timeout_ms` cap is 30 s.
2. **Timeout** (C5): on expiry, set `cancel_requested` on the task's proc and
   `march_preempt_request = 1`, as `march_sched_stop_epoch` does
   (`march_scheduler.c:3187-3208`); the task longjmps at its next
   `march_sched_cancel_point`. A fragment stuck in a foreign call cannot be
   cancelled; the reply says `TIMEOUT uncancellable` and the proc is left and
   reported by `ACTORS`.
3. **Unloading**: `dlclose` when the fragment's dispatch refs drop to zero. A
   fragment that spawned an actor or stored a closure keeps its handle; the
   reply says `pinned:true`, and `EPOCHS` lists pinned fragments by name.
4. **Bindings across inputs**: `let x = e` compiles to a fragment that stores
   into a slot with `march_repl_set` (`runtime/march_extras.c:2291-2299`,
   4096 slots, `core` role, so present in every binary) and returns
   `show(x)`. Forge keeps
   the slot→type map for the session. Slots are per node, not per session:
   add a `SLOT_ALLOC <n>` verb that reserves a range (fails past 4096) so two
   concurrent shells do not collide, and a `SLOT_FREE` the client sends on
   exit; a session that dies without freeing leaks its range until restart,
   which `EPOCHS` reports.
5. **Commands**: `forge rpc --host H 'expr'` (one fragment, print, exit 0/1),
   `forge shell --host H [--select]` (line editing via plain stdin in v1,
   history in `.forge/shell_history`), `forge eval 'expr'` (runs locally on the
   release bundle, R9; before R9 it is `march` with the project's entry and
   `MARCH_POOLS` unset).
6. **Refusals with a reason** for inputs that declare a `type`, `actor`,
   `mod` or `impl` (design §6.5): "definitions need a deploy: `forge deploy
   hot`".

**Acceptance.**
- `test/test_shell_e2e.ml`, real binaries (pattern: `test_upgrade_from.ml`):
  start a `--hot-reload` node with a counter actor; `forge rpc` reads it via
  `Recon.get_state`; a `let` in one input is visible in the next; a fragment
  that loops forever returns `TIMEOUT` inside `timeout_ms + 1 s` and the node
  keeps serving; a fragment needing `IO.NetConnect` is refused under a policy
  without it; the audit log has every input.
- **Skew test:** change one boundary function's body in the client checkout;
  `forge shell` refuses and names it; `--force` then allows a read-only
  fragment and refuses `replace_state`.
- CHANGELOG `### Added`: `forge rpc`, `forge shell`, `forge eval`.

---

## R7. `forge observe` TUI, `WATCH`, crash dumps (1.5 weeks)

**What.**

1. Add `notty`, `notty.unix` to `forge/lib/dune` (C15). New
   `forge/lib/observe_tui.ml`: panels System, Load, Actors, Actor, Supervision,
   Names, Epochs, Cluster, Crashes, and (after R8) Trace, as designed §5.1.
   Pure render functions `panel -> Yojson.Safe.t -> Notty.image` so tests
   render fixtures to text without a terminal.
2. **`WATCH <sections> <interval_ms> <max>`** on the observe socket: streams
   envelopes, `max` mandatory and ≤ 3600, interval ≥ 250 ms. It holds one of
   the 8 connection slots.
3. Node switching: `n` cycles hosts from `--env`.
4. **Crash dumps** (C9): `MARCH_CRASH_DUMP=<path>` makes `march_panic`'s
   unsupervised path write a full `SNAPSHOT` (plus the crash ring with
   message text, since the dump file is operator-owned) to `<path>.tmp` and
   rename it. `abort()` skips `atexit` hooks, and the runtime calls it at 28
   sites (`march_runtime.c`, `march_scheduler.c`, `march_reclaim.c`); those
   get a `march_fatal(msg)` wrapper that writes the dump **only if the
   caller is not inside a reclamation critical section and not on a signal
   stack**, then aborts. No signal handler ever writes the dump; a SIGSEGV
   produces none, and the doc says so. `forge observe --dump FILE` and `forge diagnose --dump FILE` read it,
   greying live-only panels.

**Acceptance.** Render tests per panel over fixtures; a native test that
panics with `MARCH_CRASH_DUMP` set produces a file `forge diagnose --dump`
parses with `crash.loop` or at least the crash entry; manual screenshots of
the TUI against a real node attached to the PR.

---

## R8. Tracing (2 weeks)

**What.**

1. Introspection design stages C1/C2 as specced (`stdlib/trace.march`, ring
   per session, pull delivery, `g_introspect_armed`).
2. **Mandatory limits**: `Trace.start(c, limit)` where
   `Limit = Count(Int) | Rate(Int, Int)`; no constructor without a limit.
3. **Boundary call tracing**: a `traced` bit per dispatch slot, checked in
   `march_dispatch_enter_unit` next to the slot load it already does; when
   set, write `{pid, name_id, epoch, at_ns}` into the session ring. App-prefix
   functions only, arity but no arguments.
4. Verbs `TRACE_START/DRAIN/STOP` on the observe socket, debug tier, signed.
   The Trace panel in R7's TUI.

**Acceptance.** The introspection design's C acceptance; a `Count(10)` session
stops itself after exactly 10 events; A/B on `call_storm.march` with tracing
compiled in and disarmed shows no movement.

---

## R9. `forge release build` and `bin/<app>` (4 days)

**What.**

1. Turn `release` into a `Cmd.group` (`forge/bin/main.ml:866-873`) with
   `~default` = today's behaviour so `forge release --bump` keeps working
   (no breaking rename; the design's `release tag` becomes an alias).
   Add `build [--target T] [--profile P] [--tar]`.
2. Layout as design §7.2, written by `forge/lib/cmd_release_build.ml`. The
   launcher is generated POSIX `sh`, tested with `shellcheck` when present.
3. Launcher verbs `start|daemon|stop|restart|pid|version|ping|status|eval`,
   plus `rpc|shell|observe|diagnose` that print the forge command when
   `forge` is not on the host. `stop` is SIGTERM with the topology's soft
   deadline as grace, then SIGKILL; a drained stop needs the deploy key and
   is `forge deploy --drain`, not the launcher's job (a POSIX `sh` script
   cannot sign).
4. `forge topology gen systemd` points `ExecStart` at `bin/<app> start` when a
   release dir is given.

**Acceptance.** `forge/test/test_release_build.ml` (real binaries): build,
`bin/<app> daemon`, `ping`, `version` shows the epoch, `stop`; a cross build
for `linux/amd64` produces the tree (skip with a message without zig). CHANGELOG.

---

## R10. `Recon.which` and `Recon.source` (3 days)

**What.** At `--hot-reload` build time, store each boundary function's source
span text in the CAS under its `impl_hash` (`lib/cas/`); `forge deploy hot`
uploads them with `CAS_PUT` when `$MARCH_DEBUG_POLICY` allows `SOURCE`. Verbs
`WHICH <name>` (observe: impl_hash, epoch, activated_at) and `SOURCE <name>`
(debug). `Recon.which`/`Recon.source` wrap them.

**Acceptance.** After a hot deploy, `SOURCE` returns the new body and `WHICH`
the new hash; before, the old ones.

---

## R11. Later items (1–3 days each)

- **Transcripts** (`forge shell --transcript f.md [--check]`): run ```` ```march ````
  fences, write `f.output.md`, diff under `--check`. Convert one
  `test/two_node` scenario's log greps to a transcript as the proof.
- **`--env` fan-out** for `observe`, `top`, `diagnose`, `status`, `rpc`:
  parallel per host via `Remote`, missing hosts become `coverage` gaps; add
  `cluster.split_view` and `epoch.skew` findings.
- **Notebook attach** (`forge notebook --attach H`): cells through `EVAL`.
- **`Observe.serve_http(io, port)`**: `IO.NetListen`, serves `SNAPSHOT` JSON
  and a static page, calls `observe_query`.

---

## Decision-graph and spec bookkeeping per item

Each item's PR moves nothing out of `specs/todos/2026-09-24-observe-recon-shell.md`
until the last item lands; instead it adds a dated file to `specs/progress/`
named `YYYY-MM-DD-observe-rN-<slug>.md` with the A/B table and test list, and
ticks the item in the todo. Items that find new defects file them as their own
todos. The todo moves to `specs/progress/` when R10 lands; R11 items get their
own todos then.
