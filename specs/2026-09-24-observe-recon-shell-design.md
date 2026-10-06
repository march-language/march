# Observe, Recon, Shell: operator tooling for running March nodes

**Date:** 2026-09-24
**Status:** design, nothing built. **Superseded in part** by the implementation plan
[`plans/2026-09-28-observe-recon-shell-plan.md`](plans/2026-09-28-observe-recon-shell-plan.md),
whose §C lists the claims here that current code contradicts (the shell's
dispatch ids and attach hash, fragment size, cap-marker checking, timeouts, the
single-client socket, counters, crash dumps). Where the two disagree, the plan wins.
**Revised 2026-10-05** (shell interaction): §6.2–6.5 now agree with the plan,
and §6.9 adds the interactive session: a warm compiler so an input answers in
well under a second, a `limit: N` on rendered results, captured `println`,
pre-bound caps, and a session that a deploy ends. The plan's R5–R6 carry the
work.
**Working names:** `forge observe` (Observer), `Recon` (the stdlib diagnostics
module), `forge shell` (remote shell), `forge release` (the app bundle).
**Method:** the ground truth in §1 was read from this worktree on 2026-09-24
(main at `3be7bef34`). Prior art in §2 was checked against the projects' own
documentation; URLs are given where a claim would be surprising.
**Builds on:** [`2026-09-23-per-actor-introspection-design.md`](2026-09-23-per-actor-introspection-design.md)
(push alarm, `inspect_state`, message tracing), which this design adopts
unchanged and extends, and
[`plans/2026-09-21-distributed-authority-and-deploys-plan.md`](plans/2026-09-21-distributed-authority-and-deploys-plan.md)
(epochs, drains, `forge deploy`, the control plane), which owns everything
about *changing* a running system. This document owns *seeing* and *poking*
it, and the operator-facing packaging around both.

---

## Decisions needed

1. **One channel or two.** *Recommendation:* extend the hot-reload Unix socket
   (`runtime/march_reload.c`) into the **node control socket**, with three verb
   tiers (§3.2). No second socket, no in-process HTTP server. *Why:* the
   reload socket already has framing, ed25519 signatures, a capability policy,
   an audit log, an ssh-tunnel driver in forge, and a per-host model
   (`forge/lib/hosts.ml`). The 2026-08-02 audit reached the same conclusion.
   The alternative, a `/debug` HTTP endpoint the way Go's pprof or Phoenix
   LiveDashboard do it, puts a listening TCP port and the HTTP stack into every
   binary and needs its own auth story. It can be added later *on top of* the
   snapshot API as a stdlib module (§5.6), never as the primary channel.
2. **How a remote shell executes code.** *Recommendation:* compile on the
   operator's machine against **the code the node runs** (every boundary
   function the fragment reaches must have the node's `impl_hash`, refused
   on mismatch), in a **warm compiler session** that compiles only what each
   input adds; ship the fragment as a signed `EVAL` over the session's one
   connection; run it as a bounded task; and have the fragment render its
   own result, within a `limit` (§6). *Why:* compiled March binaries cannot
   describe their own values (`march_value_to_string` prints `#<tag:N>` for
   any ADT, `runtime/march_runtime.c:9640`), and they do not carry the
   compiler. The client does carry it, and it knows the fragment's type, so
   it can generate the `show`. The alternative, an in-process ORC JIT, means
   libLLVM in every production binary. It stays an optional backend (§6.7).
3. **Who may see what.** *Recommendation:* three tiers that mirror the caps:
   **observe** (counters, names, tree shape; unsigned, socket permissions
   only), **debug** (state, message payloads, traces; signed), **exec**
   (eval, replace-state, kill, drain, activate; signed, policy-checked,
   audited with the source text). *Why:* the introspection design already
   split `Actor.Introspect` from `Actor.Debug` on exactly the line "does this
   reveal payloads". Exec is the line "does this change the system". Erlang's
   cookie-equals-root model is the thing every ecosystem review flags.
4. **Per-actor cumulative counters.** *Recommendation:* add `msgs_in`,
   `msgs_out`, `reductions_total`, `last_active_ms` to `march_proc`, written
   only by the proc's own thread with plain stores, read with relaxed loads
   (§4.2). *Why:* Observer's `Reds`/`MsgQ` columns and recon's
   `proc_window(reductions, …)` are the two most used pivots, and both need
   them. The introspection design's constraint (no new atomic on the send
   path) is kept: the receiver counts on dequeue, the sender counts on its
   own proc.
5. **Scope of `forge release`.** *Recommendation:* a directory bundle with a
   `bin/<app>` launcher whose verbs copy `mix release` (§7.2), and nothing
   about hot upgrades that the deploys plan does not already own. *Why:* the
   plan's §6.5 (host-persisted patch stacks) and §6.8 (`forge deploy`) are the
   upgrade story. What is missing is the *artifact* and the *launcher*, and
   both are small.
6. **Cluster-wide views in v1.** *Recommendation:* forge fans out over the
   existing per-host ssh tunnels and merges snapshots client-side (§5.4).
   The in-cluster `Control`/`Agent` protocol (plan step 12) later carries
   the same verbs over cluster frames; the verb set is designed so that
   move changes no client. *Why:* step 12 is P3 and far out; the ssh path
   works today.

---

## 0. The problem

An operator with a March node in production today can: ping it, list its
hot-reload versions and pinned epochs, and activate a patch. They cannot see
which actors exist beyond a pid list, how deep any mailbox is without writing
March code that runs *inside* the node, which supervisor owns what, why the
last crash happened, what a scheduler is doing, or what an actor's state is.
They cannot run an expression against the node. They cannot get a
crash-time snapshot. And there is no bundle to hand to a host: "the release"
is a git tag (`forge/lib/cmd_release.ml`, 23 lines).

BEAM operators have Observer for looking, `recon` for prodding safely,
`bin/app remote` for a shell, and `mix release` for the artifact. Unison
operators have something different and worth stealing: code identity is a
hash, so "which version is running" and "is my shell compatible with it" are
the same question with an exact answer, and a deploy is a function call that
returns a hash. This design gives March all four tools, on the channel it
already has, shaped by the constraints its runtime already imposes.

---

## 1. Ground truth

### 1.1 What the runtime already knows (and does not expose)

Compiled actors are two structs. `march_actor_meta`
(`runtime/march_runtime.c:2148-2335`) holds the monitor list, supervisor
strategy and restart settings, the parent supervisor entry `sup_pe` and
`sup_child_index`, the children array with `restart_type`, `shutdown_ms`,
`crash_streak` and `last_crash_ms`, the actor type via `dispatch_name_id`,
the HCR epoch fields and `hcr_dropped`, and the registered names
`reg_names[]`. `march_proc` (`runtime/march_scheduler.h:230-455`) holds
`status`, `priority`, the remaining slice budget `reductions`, atomic
`mbox_count` / `user_mbox_count`, `mbox_limit`, `mbox_policy`, stack base and
size, `owner_sched`, `crash_message` and `code_epoch`. The global table is
`g_actor_tbl` with lock-free chains (`:2367`), walked today by
`actor_pid_indices` (`:9504`). A `march_proc *` is valid only inside a
reclamation critical section (`runtime/march_reclaim.h`), so every reader
copies out and never parks.

Per-scheduler counters exist in C only: `march_sched_thread_stat(sched_id,
which)` (`runtime/march_scheduler.c:406`) with STARTED, ENTERED, DISPATCHES,
IDLE_POLLS. Nothing in `lib/` or `stdlib/` reads them. Global counters reach
March through `sched_stat : Int -> Int` (`stdlib/scheduler.march:9`): live
procs, total spawned, run-queue depth, dropped messages, reclamation counters.

Epochs: every proc carries `code_epoch`; each dispatch slot keeps a ring of
three versions and an eight-entry pin table (`runtime/march_dispatch.h:163-200`).
`VERSIONS_DETAIL` and `PINS` already serialise this.

Cluster: `ClusterNode` copies members and names into Vault tables
(`stdlib/cluster_node.march:52-54`); `ClusterLoad` samples piggyback on SWIM
gossip (`stdlib/cluster_load.march`); `subscribe` delivers `NodeUp` /
`NodeSuspect` / `NodeDead` / `NodeRejoined`.

### 1.2 What March code can see

`Actor.list`, `Actor.top_by_mailbox`, `Actor.over_mailbox`, `Actor.whereis`,
`Actor.registered` (`stdlib/actor.march:183-247`), all gated by
`Cap(Actor.Introspect)`, a proof cap minted only by `Actor.introspect(io)`
(`:62`, `:74`). Ungated: `mailbox_size`, `is_alive`, `get_actor_field` (racy,
returns a pointer without an RC increment; slated for the stdlib-only gate),
`actor_get_int`, `actor_terminal_reason`, `sched_stat`. `System.mem_peak_bytes`
and host-level memory and load (`stdlib/system.march:57-90`). Monitors exist;
links do not, by design (`specs/lang/actors.md:405`). There is no supervisor
tree walk, no per-actor info record, no tracing, no crash log, no metrics
bus. `IO.Telemetry` is declared (`lib/typecheck/typecheck_builtins.ml:1870`)
with no builtins behind it. Logger appenders are no-op stubs when compiled
(`runtime/march_runtime.c` near `:11790`); compiled `Logger` always writes
`[LEVEL] msg {fields}` to stderr.

### 1.3 The one way in: the reload socket

`runtime/march_reload.c`. A pthread listening on a Unix-domain socket named
by `MARCH_HOT_RELOAD_SOCKET`, started at `lib/tir/llvm_toplevel.ml:932`, only
in binaries built with `--hot-reload <Prefix>`. Newline-delimited text.
Verbs: `PING`, `HCR_INFO`, `ABI_QUERY`, `VERSIONS`, `VERSIONS_DETAIL`,
`GET_EPOCH`, `PINS`, `CAS_CHECK`, `CAS_PUT`, `ACTIVATE`..`ACTIVATE5`,
`BEGIN_BATCH` / `COMMIT_BATCH` / `ROLLBACK_BATCH`, `DRAIN`. Activations are
ed25519-signed against a public key compiled into the binary, the signed
payload names the function, `impl_hash`, `cas_hash`, migrate bits, epoch and
`cap_root`; `cap_root` is recomputed and checked against
`$MARCH_DEPLOY_POLICY`; every activation appends a JSON line to
`$MARCH_AUDIT_LOG`. Loading is `dlopen(RTLD_NOW|RTLD_GLOBAL|RTLD_DEEPBIND)`
plus identity markers `__march_hcr_abi/target/prefix`. `DRAIN` is unsigned
today (`specs/todos/2026-09-24-dd-review-drain-current-epoch-kills-every-actor.md`).

Forge reaches it through `ssh -N -L` (`forge/lib/cmd_deploy_hot.ml:456`),
uploads the `.so` in-band with `CAS_PUT`, and models hosts as
`{name; ssh; socket; pubkey; labels}` (`forge/lib/hosts.mli`) with rolling,
simultaneous and canary strategies.

### 1.4 Interactive tooling

The REPL (`lib/repl/`, `lib/jit/`) JIT-compiles each input to a fragment,
either a `.so` loaded with dlopen or IR fed to an in-process LLJIT (ORC),
keeps variables in `march_repl_slots[]` read back by `march_repl_get(slot)`
(`runtime/march_extras.c:2270`), and prints values by walking the heap with
the compiler's type and constructor tables (`lib/jit/repl_jit.ml:713`).
Once an `actor` is declared the session falls back to the interpreter. The
DAP debugger is launch-only and interpreter-only. The notebook re-runs cells
as fresh subprocesses. Nothing attaches to a running process. `march-lsp
query` answers static questions only (hover, type, symbols, definition,
references, diagnostics).

### 1.5 The REPL TUI

`lib/repl/tui.ml` is a terminal UI already in the tree; `forge observe`
reuses its input and rendering layer rather than adding a second TUI
dependency.

---

## 2. Prior art, and what each one decided for us

| System | What it got right | What we take | What we avoid |
|---|---|---|---|
| **OTP Observer** | The process table as the universal pivot (`Pid, Name, Reds, Memory, MsgQ`), the supervision tree as a first-class view, a table viewer for ETS, the same panels for a live node and a crash dump (`crashdump_viewer`). | Panel set and column vocabulary (§5.1); `MARCH_CRASH_DUMP` writes the same snapshot the live verb returns (§5.5). | wx dependency; `process_info(messages)` freezing a node; no history. |
| **`observer_cli` 2.0** | Split into `tui` and a non-interactive `diagnose` with a versioned JSON envelope and stable exit codes, "aimed at runbooks and AI agents". | The two-plane split: `forge diagnose` (§5.3) is the scriptable plane, `forge observe` the interactive one, both over one verb set. | Requiring matching Erlang versions on both ends (we match by hash instead). |
| **`recon`** | `proc_count(attr, n)` / `proc_window(attr, n, ms)`; `info` that never returns a mailbox; `scheduler_usage`; `bin_leak`; `get_state`; `remote_load`; `source`; tracing with a **mandatory** limit `{n, ms}` and a tracer separate from the formatter. | The `Recon` module API (§4) almost verb for verb; mandatory trace limits (§4.5); windows over lifetime counters. | Anything that walks all processes twice; `bin_leak`'s forced global GC (March has no per-process GC; the analogue is an RC-leak witness, §4.4). |
| **Erlang in Anger** | The order of investigation: node-wide metric first, then top-N, then one process; never pull a mailbox; keep the tools *in* the release. | `forge diagnose`'s finding order; the `Recon` module ships in the stdlib so it is in every binary. | |
| **`sys`** | `get_state`, `replace_state`, `suspend`/`resume`, `statistics` (`reductions, messages_in, messages_out`), `log` ring, all as system messages the actor loop handles between user messages. | `Recon.statistics` fields (§4.2); `replace_state` through the same in-band tag as `inspect_state` (§4.6); the epoch marker is already our `suspend`. | Behaviours that ignore their mailbox blocking system messages: our in-band requests carry a timeout and the socket reports `InspectTimeout`. |
| **`mix release`** | One `bin/<app>` with `start / daemon / stop / pid / version / eval / rpc / remote`; `eval` on a fresh VM vs `rpc` against the running one vs `remote` as a shell. | The launcher verb set (§7.2) and the three-way split `forge eval` / `forge rpc` / `forge shell` (§6.1). | Cookie as root; hot upgrades bolted on and abandoned. |
| **OTP release_handler** | `code_change/3` driven by the supervision tree, two live versions, `soft_purge`. | Nothing new: the deploys plan already has `migrate_state`, three versions per slot, soft/hard drains. | Hand-written appups. The plan's `--plan` output is the automated appup. |
| **Unison** | Definitions are hashes; names are pointers; a deploy is `run deploy` returning a `ServiceHash`; `ServiceName.assign` is blue/green; transcripts are executable docs and tests. | `forge shell` **refuses to run a fragment unless every function it reaches has the node's `impl_hash`** (§6.2); `Recon.source(fn)` and `Recon.which(fn)` answer "what is actually running" from CAS (§4.7); `forge shell --transcript` (§6.6). | Codebase-as-database. |
| **Livebook attached node** | Cells evaluate on the target; a notebook becomes a runbook with charts. | `forge notebook --attach <host>` routes cells through `EVAL` (§6.8, later). | |
| **JVM `jcmd`** | One verb; the *target* enumerates its subcommands (`jcmd <pid> help`); JFR's "dump the last N minutes on incident". | `HELP` verb so old forges work against new nodes (§3.3); the crash ring and trace ring are the "last N" (§4.3, §4.5). | JMX/RMI. |
| **tokio-console** | Instrumentation as a subscriber speaking a versioned protocol; automatic lints over the stream (`never yielded`, `lost waker`). | `forge diagnose` findings are lints over a snapshot (§5.3). | Overhead when on; we keep the armed-flag rule from the introspection design. |
| **Go pprof** | Profiles as endpoints with `?seconds=30` windows. | `TOP … window_ms` (§3.3). | A TCP debug port by default. |
| **Fly `ssh console`, `kubectl exec`** | Short-lived certs minted by the platform; `--select` an instance; `-C` one-shot. | `forge shell --select`; `forge rpc` is the `-C`. Certs come with plan step 11. | A shell on the *box* rather than in the *runtime*. |
| **SLIME/Swank** | Small RPC protocol many front-ends speak; conditions with restarts. | The socket is the Swank; the TUI, `diagnose`, the notebook and an editor are front-ends. | An unauthenticated socket. |
| **Dark** | Traces of real traffic shown in the editor. | Out of scope, noted for the trace ring's future consumers. | |

---

## 3. Architecture

### 3.1 One picture

```
 operator machine                           host
 ┌──────────────────────┐    ssh -L      ┌──────────────────────────────┐
 │ forge observe (TUI)  │──────────────▶ │ node control socket (pthread)│
 │ forge diagnose (json)│                │   observe │ debug │ exec     │
 │ forge shell / rpc    │  EVAL + .so    │      ▼        ▼       ▼      │
 │ forge deploy/status  │──────────────▶ │  C snapshot layer   dlopen   │
 │ march shell-session  │                │  march_observe_*    EVAL run │
 └──────────────────────┘                │      ▲                       │
          ▲                              │  Recon / Actor / Trace stdlib│
          │  same verbs, later           │  (in-node March code)        │
   Control/Agent protocol (plan step 12) └──────────────────────────────┘
```

Three rules hold the pieces together:

- **One snapshot layer.** Every number the socket returns, `Recon` returns
  too, from the same C function (`runtime/march_observe.c`, new). The socket
  handler is a serialiser over that layer; the builtins are wrappers over it.
  There is no fact an operator can see that a program cannot, and vice versa.
- **The socket is the protocol.** Every front-end (TUI, `diagnose`, shell,
  notebook, a future editor plugin, the in-cluster agent) speaks the socket
  verbs. Verbs are versioned by a `HELP` response, never by a client release.
- **Nothing costs anything while off.** Snapshot reads copy out of structs
  that exist already. Counters are plain stores on the owning thread. Tracing
  and alarms keep the introspection design's `g_introspect_armed` gate. The
  acceptance bound is that design's Decision 6, reused verbatim.

### 3.2 Tiers and who may use them

| Tier | Verbs | Auth | Reveals |
|---|---|---|---|
| **observe** | `HELP`, `PING`, `SNAPSHOT`, `ACTOR`, `TOP`, `TREE`, `NAMES`, `SCHED`, `MEM`, `EPOCHS`, `CLUSTER`, `CRASHES`, `TABLES`, `WATCH` | connect to the socket (filesystem permissions; the ssh tunnel is the remote auth) | existence, counts, names, types, tree shape, epochs, crash *reasons* (not payloads) |
| **debug** | `STATE`, `CRASHES_FULL`, `MESSAGES`, `TRACE_START` / `TRACE_DRAIN` / `TRACE_STOP`, `TABLE_ROWS`, `SOURCE` | signed request (the deploy key, a nonce and an expiry), the verb listed in `$MARCH_DEBUG_POLICY` (as built in R4b) | state renderings, message payloads, table rows |
| **exec** | `EVAL`, plus today's `ACTIVATE*`, `DRAIN`, `*_BATCH`; `REPLACE_STATE`, `KILL`, `SUSPEND` / `RESUME` are `EVAL`s of `Recon` calls (§6.4) | signed, `cap_root` checked against `$MARCH_SHELL_POLICY` (for `EVAL`) or the deploy policy, audit line carries the fragment source | changes the system |

`DRAIN` moves from unsigned to exec, which closes the open todo. The debug
and shell policies are separate files (`$MARCH_DEBUG_POLICY`,
`$MARCH_SHELL_POLICY`), so the deploy policy's parser, which `ACTIVATE6`
depends on, is not touched. A binary built
without `--hot-reload` still gets the **observe** tier when
`MARCH_CONTROL_SOCKET` is set (the env var is a new alias of
`MARCH_HOT_RELOAD_SOCKET`; both work); debug and exec need the signing key
compiled in, which only `--hot-reload` builds have. The socket thread's
startup moves out of the hot-reload conditional in `llvm_toplevel.ml:932`.

### 3.3 Verb inventory (observe tier)

All replies are one JSON document per verb, in an envelope
`{"proto":"march.observe/1","node":…,"at_ms":…,"data":…}`. `HELP` returns
the verb list with tier and arity, so an older forge can tell what a newer
node offers and a newer forge degrades on an older node.

| Verb | Returns |
|---|---|
| `SNAPSHOT [sections]` | every section below in one document; `sections` is a comma list to trim it |
| `SCHED` | per scheduler: id, `dispatches`, `idle_polls`, `entered`, run-queue length, **utilisation over the last window** (§4.3); globals from `sched_stat` |
| `MEM` | RSS now and peak, string alloc/free counters (from `MARCH_STRING_STATS`'s counters, now always maintained), stack pool size, mailbox nodes live, CAS artifact bytes on disk; RC-witness counters (§4.4) |
| `ACTORS [sort] [n]` | the process table: `pid`, `type` (from `dispatch_name_id`), `names`, `status`, `mbox`, `mbox_user`, `mbox_limit`, `policy`, `reds_total`, `msgs_in`, `msgs_out`, `stack_bytes`, `epoch`, `parent`, `children`, `monitors`, `crashes`, `last_active_ms`, `draining` |
| `ACTOR <pid>` | one row plus `sup` (strategy, window, backoff, restart timestamps), `reg_names`, `hcr` (pinned epoch, dropped, pending) and the terminal reason if dead |
| `TOP <attr> <n> [window_ms]` | top-*n* by `mbox | reds | msgs_in | msgs_out | stack | crashes`; with a window the node takes two samples `window_ms` apart and ranks the delta (recon's `proc_window`) |
| `TREE [root]` | the supervision forest as nested rows, from `sup_children[]` and `sup_pe` |
| `NAMES` | local registry (name → pid) and, when a `ClusterNode` is up, the global registry's entries with owner node |
| `EPOCHS` | `VERSIONS_DETAIL` + `PINS` + per-epoch unit counts + drain progress; unchanged data, one verb |
| `CLUSTER` | self identity, members with SWIM state and incarnation, `ClusterLoad` samples with age, link counts, stale bindings |
| `CRASHES [n]` | the crash ring (§4.3): last *n* crash reports |
| `TABLES` | Vault tables: name, size, memory estimate, owner, access mode (the ETS table viewer's top level) |
| `WATCH <sections> <interval_ms> <max>` | streams `SNAPSHOT` deltas at the interval, at most `max` frames, then closes. `max` is mandatory. |

Debug tier: `STATE <pid> [timeout_ms]` is the introspection design's
`inspect_state` over the socket; `MESSAGES <pid> <n>` renders the first *n*
queued messages (never the whole mailbox; *n* ≤ 100, hard-coded);
`TRACE_*` wrap `stdlib/trace.march`; `TABLE_ROWS <table> <n> [prefix]`
samples rows; `SOURCE <fn>` returns the CAS-stored source of the running
`impl_hash` (§4.7).

Exec tier is §6.

---

## 4. `Recon`: the in-language API

`stdlib/recon.march`, a thin module over the same C layer. Naming follows
recon where the semantics match, and does not where they do not (March has no
binaries to leak and no per-process heap).

### 4.1 Signatures

```march
mod Recon do
  -- observe tier: Cap(Actor.Introspect)
  fn info(c : Cap(Actor.Introspect), pid : Pid(a)) : Option(ActorInfo)
  fn proc_count(c, attr : Attr, n : Int) : List((Pid, Int))
  fn proc_window(c, attr : Attr, n : Int, window_ms : Int) : List((Pid, Int))
  fn tree(c) : List(SupNode)                      -- forest of supervisors
  fn scheduler_usage(c, window_ms : Int) : List((Int, Float))
  fn node_stats(c) : NodeStats
  fn crashes(c, n : Int) : List(CrashReport)
  fn tables(c) : List(TableInfo)
  fn epochs(c) : EpochReport

  -- debug tier: Cap(Actor.Debug)
  fn get_state(d : Cap(Actor.Debug), pid, timeout_ms) : Result(String, InspectError)   -- = Actor.inspect_state
  fn messages(d, pid, n : Int) : List(String)
  fn source(d, name : String) : Option(String)
  fn which(c : Cap(Actor.Introspect), name : String) : Option(FnVersion)  -- impl_hash, epoch, since_ms

  -- exec tier: Cap(Actor.Debug) plus the operation's own cap
  fn replace_state(d, pid : Pid(s), f : s -> s, timeout_ms) : Result(Unit, InspectError)
  fn suspend(d, pid, timeout_ms) : Result(Unit, InspectError)
  fn resume(d, pid) : Result(Unit, InspectError)
end

type Attr = Mailbox | Reductions | MsgsIn | MsgsOut | Stack | Crashes
```

`ActorInfo` is the `ACTORS` row as a record. `SupNode = {pid, type, names,
strategy, children : List(SupNode), restarts_in_window : Int}`.
`CrashReport = {pid, type, names, reason : Reason, message : String, epoch,
supervisor : Option(Pid), restart_no : Int, at_ms : Int, backtrace :
Option(String)}`.

`replace_state` is typed on `Pid(s)`, which is the minting-door problem the
introspection design's Decision 3 describes: `s` is caller-chosen. It goes
through the same runtime shape check as the typed `get_state` (B2), so it is
staged after B2 and only lands if B2 does.

### 4.2 The four counters (Decision 4)

Added to `march_proc`: `uint64_t reds_total, msgs_in, msgs_out, last_active_ms`.

- `msgs_in` is incremented by the receiving proc when it **dequeues** a
  message, in the loop that already decrements `mbox_count`. Only the owner
  thread writes it.
- `msgs_out` is incremented on the **sender's** proc after a successful
  enqueue. The sender is the current proc; no lookup, no lock. A send from a
  foreign thread (runtime-originated) counts nowhere.
- `reds_total` is bumped by the scheduler when a slice ends, by the budget
  consumed. One store per slice.
- `last_active_ms` is set at slice start.

Readers use relaxed loads and accept torn reads; a snapshot is a sample, not
an audit. This adds four stores per slice or per message on the owning thread
and zero atomics. The interpreter mirrors them on `actor_inst`
(`lib/eval/eval_runtime.ml:207`) so `Recon` is backend-independent.

Per-actor **memory** is not knowable cheaply: the heap is a shared RC heap
with no per-actor arena. The row reports `stack_bytes` (known) and `mbox`
(known). A deep size of the state is a debug-tier operation that walks the
state through the generated `Name_inspect` function with a byte counter
instead of a printer; it shares B1's code path and is listed as B1b.

### 4.3 Scheduler utilisation and the crash ring

`march_sched_thread_stat` already counts `dispatches` and `idle_polls`. Add
`busy_ns`, accumulated on each scheduler thread between picking a proc and
parking (one `clock_gettime` pair per dispatch, on the scheduler thread, no
sharing). `SCHED` and `Recon.scheduler_usage(window_ms)` report
`busy_ns / window_ns` per scheduler over two samples. This is recon's
`scheduler_usage`, and it is the number OS CPU cannot give (spinning inflates
OS CPU; `busy_ns` does not count idle polls).

The **crash ring** is a fixed array of 256 `CrashReport`s in the runtime,
written where `proc->crash_message` is set for a supervised actor
(`march_runtime.c:1440-1460`) and where an unsupervised panic prints its
backtrace. The write takes a small mutex (crashes are rare). `Logger` also
emits one line per entry at `error`, with the fields, so the crash log exists
even when nobody attaches. This is the crash-report log the introspection
survey found missing, and it is what `forge diagnose` reads first.

### 4.4 The RC-leak witness (`bin_leak`'s analogue)

recon's `bin_leak` forces a GC and reports who shrank. March has no GC to
force. The analogue is a **witness counter**: `MEM` reports `strings_live`,
`heap_objs_live` (alloc minus free counters that `MARCH_STRING_STATS` and
`MARCH_TRACE_GC` already maintain behind env vars; they become always-on
counters, relaxed-atomic per scheduler, summed on read), and their deltas
over a window. `forge diagnose` flags a monotonic climb with a flat actor
count. It cannot name the culprit; that needs the per-actor deep size (B1b)
sampled over time, which the `TOP stack` and `STATE` paths give.

### 4.5 Tracing

Adopted from the introspection design §5 unchanged: `stdlib/trace.march`
with `start`, `trace(c, s, pid, flags)`, `untrace`, `drain(s)`, `dropped`,
`stop`, a bounded ring per session, pull delivery, `Sent | Received | Spawned
| Exited | Dropped` events. This design adds two things.

**Mandatory limits.** `Trace.start(c, limit : Limit)` where
`Limit = Count(n) | Rate(n, ms)`; the session stops itself at the limit and
records why. There is no unlimited session. This is recon_trace's rule, and
the reason it is safe to hand to an on-call engineer.

**Call tracing at the unit boundary.** Every reloadable function already
passes through `march_dispatch_enter_unit(NAME_ID)`. When a trace session
names a function (by name id, `Trace.calls(c, s, "Orders.place", limit)`),
`enter_unit` writes a ring event with the caller pid, name id, epoch and a
timestamp when the per-slot `traced` bit is set. The bit is checked with a
load that is already on that path (the slot lookup). This gives recon_trace's
`calls/2` for app-prefix functions only, with arity but not arguments
(arguments are erased at that boundary; rendering them needs the fragment
mechanism of §6 and is not v1). Non-reloadable code (stdlib, deps) is not
traceable; that is the same line the hot-reload boundary draws.

### 4.6 `replace_state`, `suspend`, `resume`

All three ride the in-band system tag the introspection design introduces
for `inspect_state` (`MARCH_SYS_INSPECT_TAG`): a request record in the
mailbox, handled by the actor loop between user messages, answered on a
reply channel with a timeout. `suspend` parks the loop on the next system
message until `resume`; while suspended, the mailbox fills and the observe
row shows `status: suspended`. `replace_state` runs the closure on the
actor's own thread, on its own stack, so linearity and RC are exactly those
of a handler. A `replace_state` whose closure panics leaves the state as it
was and reports `InspectFailed`.

The epoch marker (plan §6.1) is already a suspend-and-migrate; `suspend`
reuses its parking path and adds a resume condition.

### 4.7 `source` and `which` (Unison's lesson)

`which(name)` reads the dispatch slot: `impl_hash`, epoch, the time the
version was activated (from the audit log's `ts_ms` mirrored into the slot).
`source(name)` returns the March source of that `impl_hash`. For this the
compiler stores each reloadable function's source span text in the CAS
under its `impl_hash` at build time (`lib/cas/`, one small blob per function;
the manifest already lists the hashes). `forge deploy hot` uploads those
blobs alongside the `.so` with `CAS_PUT` when the policy's `debug:` section
is on. This is recon's `source/1` without decompilation, and it answers the
question every incident asks: "what is *actually* running here", by hash,
not by tag.

---

## 5. `forge observe`, `forge top`, `forge diagnose`

### 5.1 Panels

`forge observe [--host H | --env E] [--select]` opens the TUI on
`lib/repl/tui.ml`. Panels, each a `SNAPSHOT` section rendered, with the
Observer names where the concept matches:

| Panel | Source verb | Notes |
|---|---|---|
| **System** | `SNAPSHOT` header, `MEM`, `HCR_INFO` | build target, abi, `cas_hash`, uptime, schedulers, RSS, epoch |
| **Load** | `SCHED`, `MEM` over `WATCH` | per-scheduler utilisation and run-queue sparklines; string/heap live counters |
| **Actors** | `ACTORS` | the pivot table; sort keys `m` mailbox, `r` reductions (window), `i/o` msgs, `c` crashes, `s` stack; `Enter` opens the actor view |
| **Actor** | `ACTOR`, and `STATE` / `MESSAGES` when the debug tier is available | `t` starts a trace on this actor with a `Rate(100, 1000)` default limit |
| **Supervision** | `TREE` | Observer's Applications tab; restart counts per node; `Enter` jumps to the actor |
| **Names** | `NAMES` | local and global registries |
| **Epochs** | `EPOCHS` | versions per slot, pins, drains in progress; this panel has no BEAM equivalent and is the one a deploy is watched from |
| **Cluster** | `CLUSTER` | members, SWIM state, load samples and their age; `n` switches the observed node (Observer's Nodes menu, LiveDashboard's node switcher) |
| **Tables** | `TABLES`, `TABLE_ROWS` | Observer's Table Viewer over Vault |
| **Crashes** | `CRASHES` | the ring; `Enter` shows backtrace |
| **Trace** | `TRACE_*` | sessions, limits, drained events, drop counts |

`--json` on any panel prints the underlying document and exits.
`--dump <file>` loads a crash-dump file (§5.5) into the same panels with the
live-only panels greyed out; this is `crashdump_viewer` for free.

### 5.2 `forge top`

`forge top [--host H] [--sort attr] [--window ms]` is one screen, refreshed:
the System header, the Load line, and the top-20 actors by the chosen
attribute over the window. It is the first thing to run on an incident, and
it is what `observer_cli`'s home screen is.

### 5.3 `forge diagnose`

Non-interactive. Takes one `SNAPSHOT` (two, `window_ms` apart, when a window
is asked for), runs a fixed list of **findings** over it, and prints a JSON
envelope `{"proto":"march.diagnose/1","findings":[…],"coverage":{…}}` with
stable exit codes: `0` nothing found, `1` warnings, `2` at least one
`severity: critical`, `3` could not connect. `coverage` names every probe
that ran and every one that could not (no debug tier, older node), so a
finding's absence is never mistaken for health. This is `observer_cli
diagnose`'s envelope and tokio-console's lints, on our data. Initial
findings, in Erlang-in-Anger order:

1. `mailbox.growth`: any actor whose `mbox` rose across the window, sorted by
   delta; critical when one actor holds more than half the node's queued
   messages.
2. `mailbox.over_limit`: actors at their `mbox_limit` with a `DropNew` /
   `DropOld` policy and a non-zero dropped count.
3. `sched.saturated`: any scheduler over 95% for the window with a non-empty
   run queue; `sched.idle_imbalance` when one scheduler is over 80% and
   another under 20%.
4. `crash.loop`: a supervisor whose `restarts_in_window` is within one of its
   max, or an actor with more than three entries in the crash ring in the
   window.
5. `rc.climb`: `heap_objs_live` or `strings_live` up more than 10% across the
   window with the actor count flat (§4.4).
6. `epoch.stuck`: a drain past its soft deadline, or a `WAIT`ing activation;
   `epoch.old_units`: units still pinned to an epoch two or more behind.
7. `cluster.suspect`: members in SWIM `suspect`, load samples older than 10 s,
   stale bindings above zero.
8. `names.lost`: global-registry `Lost` events in the window.

Each finding carries the rows that triggered it and a one-line `next`
("run `forge observe --host H`, Actors, sort by mailbox"; "`forge shell` then
`Recon.get_state`"). Findings are a stdlib module (`stdlib/diagnose.march`)
so a program can run them on itself and page someone; forge just calls it.

### 5.4 Cluster-wide views (Decision 6)

With `--env E`, forge opens one tunnel per host from `[[hot-reload.env]]`
(reusing `Hosts.run_on`), takes `SNAPSHOT` from each, and merges: the Cluster
panel shows every node's view of membership side by side (disagreement is a
finding), the Actors panel gets a `node` column, `forge diagnose --env E`
runs findings per node and adds cross-node ones (`cluster.split_view`,
`epoch.skew`: nodes at different epochs for longer than a deploy's hard
deadline). Snapshots are taken in parallel; a host that does not answer in
`--timeout` is a `coverage` gap, not a failure.

When plan step 12 lands, the `Agent` role wraps the same verbs, and
`--env` fans out over one cluster connection instead of *n* tunnels. No
panel changes.

### 5.5 Crash dumps

`MARCH_CRASH_DUMP=<path>`: on an unsupervised panic, an abort, or a fatal
signal the runtime can still handle, write a `SNAPSHOT` document (all
observe sections, plus the crash ring and the panicking proc's backtrace) to
the path before exiting. The writer uses the same snapshot layer with a flag
that skips anything that would take a lock (it may be running from a signal
handler on a wedged node): those sections are marked `partial`. `forge
observe --dump` and `forge diagnose --dump` read it. This is Erlang's
`erl_crash.dump` plus `crashdump_viewer`, and it is why the observe layer
must be lock-free where it can be.

### 5.6 An HTTP view, later

A stdlib module `Observe.serve_http(io, port)` that serves `SNAPSHOT` as
JSON and a static page over it is a one-day job once the snapshot layer
exists, and it is how a March program gets a LiveDashboard-shaped page
without forge. It is deliberately after everything else and gated by
`IO.NetListen` like any listener. It is not the control channel.

---

## 6. `forge shell`: the remote shell

### 6.1 Three verbs, as in `mix release`

| Command | Runs where | For |
|---|---|---|
| `forge eval "<expr>"` | a fresh process from the release bundle, no node, same binary and env | migrations, one-off scripts, `Release.migrate()`-style tasks; nothing here is new, it is `march` on the bundle with `MARCH_POOLS` unset |
| `forge rpc --host H "<expr>"` | the running node, one fragment, prints the rendered result, exits | scripted checks, `kubectl exec -- cmd` shape |
| `forge shell --host H` | the running node, a session of fragments with persistent bindings | the remote shell |

### 6.2 Attach: identity by hash (Decision 2)

On connect, forge asks the node for `HCR_INFO` (target, abi, module prefix,
code epoch, the collision-set tag digest) and `ABI_QUERY` (every boundary
slot with its `impl_hash`). The whole-binary `cas_hash` can never match a
fragment build (it mixes in the compiler executable, flags and the signing
key), so identity is checked **per function**: for every boundary function a
fragment reaches through dispatch, the client's `impl_hash` must equal the
node's. A mismatch is a hard stop that names the functions and both hashes.
`--force` runs read-only fragments anyway (no `Actor.Debug`, no caps beyond
the read set), marks the prompt `[skew]`, and refuses anything that writes.
A differing tag digest is a hard stop even with `--force`. This is Unison's
rule at the granularity March can check: the client never guesses whether
its idea of a function matches the node's, it knows. There is no runtime on
the client side that has to match anything; only the compiler's output does,
and that is what the hashes cover.

### 6.3 A fragment

Each input becomes a module

```march
mod __Shell_N do
  fn __eval(console : Cap(IO.Console), intro : Cap(Actor.Introspect), …) : String do
    let __r = <expr>            -- earlier bindings read from the session's slots
    __render(__r, <limit>)      -- generated for the inferred type (§6.9)
  end
end
```

`__eval`'s parameters are exactly the narrowed caps `$MARCH_SHELL_POLICY`
grants (never `Cap(IO)`: a hook that takes the root cap records `caps=IO`,
which covers every leaf and hides any widening). They are the pre-bound
names the user types (§6.9).

The fragment is compiled **against the node's program**: app and stdlib
calls resolve to the node's own symbols, and calls to boundary functions go
through the node's dispatch table at its current epoch, using the node's
NAME_IDs (plan R5.3). It carries only `__eval`, its lambdas, and any
generic instantiation the node does not already have. Building it as a
whole-program `--compile-so` is not an option: a module with no `main` gets
no stdlib pruning, and that build took **82 s** (`llvm-emit` 52 s, `clang`
27 s) on 2026-10-05, against 3.2 s for the same patch with a `main`. The
plan's R5.5 (`--fragment` emission) is therefore required, not an
optimisation.

A `let x = …` input stores into a session slot (`march_repl_set`) and
renders `x`; later fragments read the slot with the type forge remembered.
This is exactly what `lib/jit/repl_jit.ml` does for the local REPL, moved to
a different process: the client owns the type environment, the node owns the
values.

### 6.4 `EVAL`: the verb

```
EVAL <sig> name:<__Shell_N> so_blake3:<h> epoch:<E> cap_root:<r> nonce:<n> not_after_ms:<t> timeout_ms:<t> limit:<n> caps:<csv> src_b64:<s> so_b64:<bytes>
```

Signed, with a nonce and an expiry (the R4b machinery). The fragment's bytes
ride **inline** (`so_b64`, refused over 4 MiB), so one input is one round
trip, not a `CAS_PUT` and then an `EVAL`. The node:

1. checks the signature, nonce and expiry, and that `epoch` is its current
   code epoch (if not, the session is over, §6.9);
2. checks the bytes against `so_blake3`;
3. checks `caps` against `$MARCH_SHELL_POLICY` (a flat cap list; no file
   means deny all);
4. writes an audit line with the source;
5. `dlopen`s the fragment and requires its `__march_cap_manifest` to hash to
   the signed `cap_root`;
6. spawns `__eval` as a **task** at the current epoch, with its `println`
   output captured (§6.9);
7. waits on a condition the task signals, outside any reclamation section,
   and replies `OK <b64 result> out:<b64 captured>`, `TIMEOUT`,
   `TIMEOUT uncancellable`, `PANIC <b64 msg>`, or `ERR <code>`.

On timeout it sets `cancel_requested` on the task and raises the preempt
flag; the task unwinds at its next cancel point. A fragment stuck in a
foreign call cannot be cancelled and is left running, reported by `ACTORS`.

`EVAL` is served by a **shell listener** beside the reload socket
(`<reload socket>.shell`): one thread per session connection, a few
sessions at most. It shares the reload server's `dlopen` and registry under
a mutex held only while loading, never while a fragment runs. The reload
socket itself stays one-client and is never held by a shell, so an open
session never blocks a deploy.

The fragment's `.so` is `dlclose`d when its `refs` drop to zero. A fragment
that spawned an actor or stored a closure keeps a reference and stays
loaded; the reply says `pinned:true`, and `EPOCHS` lists pinned fragments by
name.

`REPLACE_STATE`, `KILL`, `SUSPEND`, `RESUME` are not separate wire verbs:
they are `EVAL` of `Recon.replace_state(…)` and friends, and the shell
policy decides whether `Actor.Debug` is on the table. One verb, one audit
path, one cap check.

### 6.5 What the shell can and cannot do

- Can: call any app or stdlib function at the node's epoch, read state
  (`Recon.get_state`), bind values across inputs, spawn actors (they are
  charged to the shell's caps, and outlive the fragment as pinned units),
  send messages to any pid it can name (holding a pid is authority, as
  everywhere in March).
- Cannot: define a new type, actor, module or impl (the fragment would not
  agree with the node's shape ids; `forge deploy` is the path, and the shell
  says so), redefine an existing function (that is `ACTIVATE`), exceed the
  shell policy's caps, run longer than `timeout_ms` (30 s at most), or call
  a function whose `impl_hash` differs from the node's.
- Prints values through the fragment's generated renderer, so records and
  ADTs render with constructor names, which the node alone cannot do.

### 6.6 Transcripts

`forge shell --transcript session.md` runs a Markdown file with
` ```march ` input fences against the node and writes `session.output.md`
with each input's rendered output under it; `--check` fails if the output
differs from the file's recorded output. This is Unison's `ucm transcript`,
and it turns a runbook into a test: the cluster's two-node scenarios
(`scripts/two-node.sh`) can assert on `Recon` output instead of grepping
logs, and an incident's shell session is a reviewable document.

### 6.7 An in-process JIT backend, optional

Binaries linked against libLLVM (`MARCH_JIT_BACKEND=orc` already exists for
the REPL) could accept `EVAL_IR` with LLVM IR instead of a `.so`, saving the
client-side link and the `CAS_PUT`. It changes nothing above the verb and is
listed so nobody builds the shell around it: production binaries do not link
libLLVM.

### 6.8 Notebook attach, later

`forge notebook --attach H` routes each cell through `EVAL` instead of a
fresh subprocess, which is Livebook's attached-node runtime. Cells that
declare types or actors are refused with the §6.5 message. Not v1.

### 6.9 The interactive session

The shell is only useful if an input answers about as fast as a local
REPL. Today's path is far from that: the quick-win prototype took a 2.9 s
median round trip, 2.6 s of it compiling (and 82 s for a fragment without a
`main`, §6.3). The local REPL already shows what is possible: with its
compiler warm, an input costs about 10 ms to typecheck, lower, monomorphise
and optimise, 2-3 ms to emit IR, ~130 ms in clang, and ~190 ms to `dlopen`
(measured 2026-10-05 with `MARCH_JIT_PROFILE=1`).

**Target.** On a warm session against a local socket, an expression over
existing functions answers in **p50 ≤ 300 ms, p95 ≤ 600 ms**, excluding the
expression's own run time. Over ssh, add one network round trip per input
and nothing else. Attaching (loading and typechecking the project once) may
take a few seconds; the prompt says so while it does.

**How.**

- **A warm compiler.** `forge shell` starts one `march shell-session`
  process per session. It loads the stdlib and the project once, keeps the
  typecheck environment and the lowered program in memory, and per input
  compiles only the input and what it newly needs (the REPL's
  `partition_fns` / `mark_compiled_fns`). It emits LLVM IR for a handful of
  functions and runs clang at `-O1` on that alone.
- **One connection, one round trip.** The session keeps one connection
  (one ssh tunnel) to the shell listener for its lifetime. Each input is a
  single `EVAL` with the fragment inline.
- **Instant meta commands.** The common questions compile nothing: `:state
  PID`, `:actors [n]`, `:top ATTR [n]`, `:crashes [n]`, `:mem` go straight to
  the observe and debug verbs. `:t EXPR` (type), `:doc NAME` and `:search Q`
  run in the local compiler only. `:caps` lists the pre-bound caps,
  `:limit N` sets the session's render limit, `:quit` ends the session.
- **Line editing** in forge with `notty`, as R7's TUI uses (forge does not
  link the REPL's `lib/repl/tui.ml`, which drags the typechecker and JIT into
  forge): history in `.forge/shell_history`, and completion asked of the
  `march shell-session` process, which has the typecheck environment.

**Rendering, and `limit: N`.** Every result is rendered by a renderer the
client generates from the result's static type (plan R5.7). The renderer
takes a limit: every list, array, map, set and string shows at most `N`
elements (characters, for a string), and says how many it left out:

```
march@prod-1> Actor.list(intro)
[Pid(0), Pid(1), Pid(2), …, Pid(49), … 4 950 more]     -- the default limit, 50
march@prod-1> Actor.list(intro) limit: 3
[Pid(0), Pid(1), Pid(2), … 4 997 more]
march@prod-1> Actor.list(intro) limit: all
[Pid(0), Pid(1), Pid(2), Pid(3), …                     -- every one of the 5 000
```

`limit: N` at the end of an input sets the limit for that input only;
`limit: all` lifts it. `:limit N` changes the session default, and `forge rpc
--limit N` sets it for one call. The limit applies at every depth, so a list
of 1 000 records each holding a 1 000-element list renders 50 × 50. A type with
a hand-written `Show` cannot take a limit; its output is cut at 16 KiB with
`… (n more bytes)`. A whole reply is cut at 1 MiB on the node regardless,
so no input can make the node build an unbounded string. `limit: N` is
shell syntax, recognised only at the very end of an input; it never reaches
the compiler.

**Captured output.** `println` and friends inside a fragment write into a
buffer on the task (the runtime checks for a per-proc capture before writing
to stdout), and the reply carries it, so the operator sees it above the
result instead of it landing in the node's log. Output from actors or tasks
the fragment spawns is not captured; it goes where their output always goes.

**Pre-bound caps.** The user never types a cap's construction. `__eval`
takes the caps the shell policy grants, under fixed names: `console`,
`clock`, `intro` (`Actor.Introspect`), `dbg` (`Actor.Debug`), and so on.
`:caps` lists them. An input that needs a cap the policy does not grant is
refused before it is compiled, naming the cap.

**Confirmation.** An input asks `y/N` before it runs, naming what it would
do, if it uses a cap outside the read set (`console`, `clock`, `intro`,
`dbg`), or if the input itself calls `send`, `kill`, `Actor.stop`, or a
`Recon` write (`replace_state`, `suspend`, `resume`), directly or in a lambda
it defines. Calls into app functions are not looked inside: the question
guards against slips, while the shell policy is the security boundary.
`--yes` skips it for scripts; `forge rpc` never asks, and refuses such an
input without `--yes`.

**A deploy ends the session.** Every `EVAL` names the code epoch the session
attached at. When a deploy moves the node to a new epoch, the next `EVAL`
gets `ERR epoch_changed <old> <new>`, and the shell listener also closes idle
sessions with that line. The shell prints that the node was redeployed, that
the session and its bindings are gone, and exits (`forge shell` started with
`--reconnect` re-attaches instead, with no bindings). A node restart drops the
connection, with the same result. The session's slots belong to its
connection (a range handed out when the session says hello) and are freed
when it closes, so neither case leaks them, and no `SLOT_FREE` message is
needed.

**Several nodes.** `--select` (or `--env`) runs each input on every selected
node in turn and prints one result per node, prefixed with its name. The
identity check runs per node; a node that fails it is skipped with the
reason. Bindings are per node: `let x = …` binds `x` on each node to that
node's value.

---

## 7. Deploy tooling: the bundle and the launcher

The deploys plan owns `forge deploy`, `--plan`, drains, patch persistence and
compaction, the reconciler, hosts and certificates. This section adds only
what an operator holds in their hands.

### 7.1 `forge status`

Plan §6.9 names it; this fixes its shape. `forge status [--env E]` prints,
per pool and host: node name, `cas_hash` (short), epoch, live versions per
slot that are not at the base, pinned units per epoch, drains in progress
with deadlines, dropped or converted messages since the last deploy, SWIM
state as seen by that node, crash count in the last hour, and the last audit
line's timestamp and signer. `--json` is the `march.status/1` envelope.
Everything comes from `EPOCHS`, `CLUSTER` and `CRASHES`; there is no
status-only verb.

### 7.2 `forge release build` and `bin/<app>`

`forge release build [--target T] [--profile P]` produces
`.march/release/<app>-<version>-<target>/`:

```
bin/<app>                 launcher script
lib/<app>                 the binary (HCR baseline when [hot-reload] is set)
lib/<app>.hcr_manifest    from the build
lib/<app>.schemas.json    from the build
lib/patches/              empty; the host-persisted patch stack (plan §6.5) lives here
etc/topology.json         exported topology for this env
etc/policy                MARCH_DEPLOY_POLICY (caps)
etc/debug_policy          MARCH_DEBUG_POLICY (debug verbs allowed)
etc/shell_policy          MARCH_SHELL_POLICY (caps a shell fragment may hold)
etc/pubkey                the signing public key, for `forge cap inspect`
etc/env                   sourced by the launcher; MARCH_* defaults, overridable
RELEASE                   name, version, target, cas_hash, compiler version, built_at
```

`forge release build --tar` also writes the tarball. `forge release` (today's
tag-only command) becomes `forge release tag`.

`bin/<app>` verbs, from `mix release` with the ones that do not apply
removed:

| Verb | Does |
|---|---|
| `start` | foreground, env from `etc/env`, `MARCH_CONTROL_SOCKET=run/<app>.sock`, `MARCH_CRASH_DUMP=run/crash.json`, `MARCH_AUDIT_LOG=run/audit.jsonl` |
| `daemon` | `start` detached, pid in `run/<app>.pid`, stdout to `log/` |
| `stop` | `DRAIN` soft/hard from the topology, then SIGTERM |
| `restart` | `stop` then `daemon` |
| `pid`, `version`, `ping` | what they say; `version` prints `RELEASE` and, if running, the node's epoch and live hashes |
| `status` | `forge status` for this one node, without forge |
| `eval "<expr>"` | §6.1, a fresh process |
| `rpc "<expr>"`, `shell` | §6.1, against the running node; these need `march` on the host or an operator machine, so they print the `forge` command to run when it is absent rather than pretend |
| `observe`, `diagnose` | same rule |

The launcher is generated March-free shell so it runs on a host with nothing
but the bundle. Process orchestration (who restarts the daemon) stays with
systemd, k8s and friends, per plan D8; `forge topology gen systemd` already
emits the unit, and it points at `bin/<app> start`.

### 7.3 Rollback

`forge deploy` rollback is the plan's "deploy the previous version forward".
This design adds the operator's view of it: `forge status` shows the previous
epoch's hashes, `forge deploy --rollback` is sugar for a deploy of the
manifest recorded at `.prev`, and the audit log entry says `rollback_of:<E>`.

---

## 8. Cost and acceptance

- **Disabled cost.** The four proc counters (§4.2) are plain stores on the
  owning thread; `busy_ns` is two `clock_gettime` calls per dispatch on the
  scheduler thread; the crash ring is written only on a crash; the observe
  tier reads copy out of existing structs. The gate is the introspection
  design's Decision 6: same-box interleaved A/B on
  `bench/actors/fanin_flood.march`, n ≥ 40 per arm, load average < 10;
  fail if the 1-scheduler median moves more than 1%. Run it once for the
  counters and once for `busy_ns`; they are separate commits.
- **Snapshot cost.** `ACTORS` on 100k actors is one walk of `g_actor_tbl`
  with one copy-out per row, no parking, and it runs on the socket thread,
  not a scheduler. Its wall time is reported in the envelope
  (`"took_ms"`), and `forge observe` refreshes no faster than 4× that.
- **Foreign-thread reads.** The socket thread is not a scheduler thread.
  `march_reclaim`'s critical sections must be enterable from it (the reload
  thread already dlopens and touches slots from there, but not proc structs).
  This is the first thing to verify in stage 1; if it is not possible, the
  snapshot is taken by a system green thread the socket thread asks and
  waits on, which costs one hand-off and nothing else.
- **Fragment cost.** One `dlopen` and one task per `EVAL`; a fragment's
  `.so` is kept until its `refs` hit zero. A shell that runs 1,000 inputs
  has loaded 1,000 small objects; `dlclose` returns them. This is the
  REPL's existing model and its existing leak surface. A warm
  `march shell-session` holds the project's typechecked and lowered program
  in memory on the operator's machine (hundreds of MB for a large app),
  which is the price of a sub-second input.

---

## 9. Security

- The observe tier reveals structure, names, counts and crash reasons.
  Payloads never appear below the debug tier. `MESSAGES` is capped at 100
  and never returns a whole mailbox.
- Debug and exec are signed with the deploy key. The audit line for `EVAL`
  carries the source, the signer and the `cap_root`. "Who ran what on prod"
  is answered by `grep EVAL run/audit.jsonl`.
- `$MARCH_SHELL_POLICY` is enforced by the compiler's cap ceiling plus
  the node's `cap_root` recomputation; a fragment's authority is
  what its markers say, and the node checks the markers, not the client's
  word.
- The socket is filesystem-permissioned; the ssh tunnel is the remote
  authentication until plan step 11's certificates, which slot in under the
  same verbs.
- A `--cap-sandbox` binary on Linux does not filter the socket thread today
  (`specs/todos/2026-09-21-cap-sandbox-linux-reload-thread-unfiltered.md`);
  `EVAL` inherits that gap and the fix is that todo's.
- Trace and watch have mandatory limits; an operator cannot start an
  unbounded stream by omission.

---

## 10. Build order

Each stage lands alone and is useful alone. Sizes are rough.

1. **Snapshot layer + observe verbs on the existing socket** (`runtime/
   march_observe.c`, `SNAPSHOT`/`ACTORS`/`ACTOR`/`TREE`/`NAMES`/`SCHED`/
   `MEM`/`EPOCHS`/`CLUSTER`/`TABLES`/`HELP`; `MARCH_CONTROL_SOCKET` alias;
   socket starts without `--hot-reload`). No new counters yet: rows carry
   what the structs have. `forge observe --json` and `forge top` over it.
   ~1 week. Verify the foreign-thread question first.
2. **The counters and the crash ring** (§4.2, §4.3, `CRASHES`, `TOP … window`),
   each with its A/B. `Recon` module with the observe-tier functions.
   ~1 week.
3. **`forge diagnose`** and `stdlib/diagnose.march` with the eight findings;
   `forge status`. ~3 days.
4. **Introspection design stages A and B1** (push alarm, `inspect_state`) as
   specced there, plus `STATE` and `MESSAGES` on the debug tier, the policy's
   `debug:` section, and `DRAIN` moved to exec. ~2 weeks (their estimate).
5. **`forge shell` / `forge rpc`** (§6.2–6.5, §6.9): fragment build, warm
   compiler session, `EVAL` on the shell listener, per-function identity,
   slots, `limit`, captured output, audit with source. ~3.5 weeks. `forge eval` is
   a day on top of stage 7's bundle, or a flag on `forge run` before it.
6. **`forge observe` TUI** over `lib/repl/tui.ml`, all panels, `WATCH`,
   `--dump` and `MARCH_CRASH_DUMP`. ~1.5 weeks.
7. **`forge release build` and `bin/<app>`** (§7.2). ~4 days.
8. **Tracing** (introspection stage C plus §4.5's limits and unit-boundary
   call tracing), `TRACE_*`, the Trace panel. ~2 weeks.
9. **`source` / `which`** (§4.7): per-function source blobs in CAS, uploaded
   under `debug:`. ~3 days.
10. **`replace_state` / `suspend` / `resume`** (§4.6), after and only if the
    typed `get_state` (introspection B2) lands. ~1 week.
11. **Transcripts** (§6.6), **`--env` fan-out** (§5.4), **notebook attach**
    (§6.8), **`Observe.serve_http`** (§5.6). Each a few days, in any order.

Stages 1–3 need no compiler change and no signature; they are the safe first
PRs. Stage 5 is the one with a security review.

---

## 11. Open questions

1. Can the socket thread enter a reclamation critical section, or must
   snapshots be delegated to a green thread (§8)? Decides stage 1's shape.
2. Should `msgs_out` count sends to remote pids (they go through
   `ClusterNode`, not the local enqueue)? Proposed: yes, counted at the
   `Node.send` wrapper on the sender's proc.
3. The fragment needs the project's modules to compile against. For a node
   deployed from a CI build, the operator's checkout must produce the same
   per-function `impl_hash`es (§6.2). That has not been tested across
   machines. Stage 5 should include a cross-machine test, and `forge shell`
   should say which functions differ when they do.
4. `TREE` from `sup_children[]` covers supervisor-spawned actors; actors
   spawned bare have `sup_pe = NULL` and appear as roots. Is a `spawned_by`
   pid worth one word on the meta so the forest has a real root? Proposed:
   yes, set at spawn, never updated; it is the Observer "initial call" column.
5. Whether `HELP` should also enumerate the stdlib's `Recon` version so a
   transcript can pin what it was written against. Proposed: yes, one field.
6. Cluster-wide `NAMES` merges the global registry as each node sees it;
   disagreement is a finding. Should `forge diagnose` try to say which node is
   right (higher vector clock)? Proposed: no in v1; show both.

## 12. Non-goals

- Process orchestration (restarting daemons, scaling machines): plan D8.
- Hot upgrade mechanics, drains, migration, `--plan`: the deploys plan.
- Link encryption, certificates, per-frame MACs: plan steps 11–12.
- A web dashboard as the primary interface (§5.6 is optional and later).
- Defining types or actors from the shell (§6.5).
- Argument capture in call traces (§4.5).
- A metrics bus (`:telemetry`-style events, histograms). The counters in this
  design are the metrics a node exposes; a bus is a separate design, and its
  first prerequisite is making `Logger` appenders work when compiled, which
  is filed as
  [`todos/2026-09-26-compiled-logger-appenders-are-no-ops.md`](todos/2026-09-26-compiled-logger-appenders-are-no-ops.md).
