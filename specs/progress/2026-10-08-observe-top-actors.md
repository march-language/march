# Observe: biggest actors with their supervision (`TOP stack`, `Recon.top`, `forge top`, `:top`)

Logged 2026-10-08. Request: "a way to quickly ask for a list of actors/processes
by size and get supervision info".

## What "size" means

What the runtime can attribute to one actor today, by measure:

| Measure | Available | Notes |
|---|---|---|
| Mailbox depth (`mbox + held`) | yes, already (`TOP mbox`) | queued work; each queued message is a heap object, so it is also memory |
| Committed machine stack | **new** (`TOP stack`) | `mmap base + reservation - stack_base`: grown by the guard-page handler, never shrinks, so it is the deepest recursion the actor has done, in pages (4 KiB Linux, 16 KiB macOS arm64; every actor has one page). Read from fields the observe walk already visits. No hot-path cost: nothing is counted at spawn, send or dispatch |
| Messages in/out, dispatches | yes (`slices`, `msgs_in`, `msgs_out`) | activity, not size; cumulative here, windowed through `TOP ... <window>` / `Recon.proc_window` |
| Crashes | yes (`crashes`) | own + children's, last hour |
| **Heap bytes owned by the actor** | **no** | the heap is shared and reference-counted; objects have no owner, so nothing knows which actor "holds" a value |
| State record size | no | the observe walk deliberately never dereferences `m->actor` (C7, and a use-after-free window against the dying actor); `STATE` (debug tier) reads one actor's state |

`mbox` stays the default ranking; `stack` is the memory-flavoured one. They answer
different questions and neither is "heap".

### What heap bytes would cost

Two routes, neither done:
- **Count at allocation**: a per-proc counter bumped in `march_alloc`/free (needs
  the allocating proc, a TLS read, plus an owner for objects that move between
  actors in messages). Measurable on `bench/binary_trees` and `bench/list_ops`;
  not cheap, and the numbers are wrong for shared (RC > 1) values.
- **Walk on demand**: a verb that, for the top N candidates only, traverses the
  actor's state record and sums reachable cells. Zero steady-state cost but needs
  the actor stopped (or a snapshot under its mailbox lock) and a deref the
  observe tier forbids; the natural home is the debug tier, next to `STATE`.
Filed as `specs/todos/2026-10-08-observe-per-actor-heap-bytes.md`.

## What changed

- `runtime/march_runtime.c`: `march_obs_actor.stack_bytes`, filled in the walk.
- `runtime/march_observe_snapshot.c`: `TOP stack`; every `TOP` row now carries
  `stack_bytes`, `crashes`, `child_crashes`, `children`, `link`
  (`supervised`/`spawned`/`none`), `parent`, `parent_type` (supervisor's type
  name, hot-reload builds), `spawned_by`, and for a supervisor `supervisor`
  (`strategy`, `max_restarts`, `window_secs`, `restarts_held`). Ties break by pid
  (they broke by walk order before). `ACTORS`/`ACTOR` rows gain `stack_bytes`.
- `lib/eval/eval_observe.ml`: the same fields under the interpreter (`stack_bytes`
  is 0; `spawned_by` null).
- `stdlib/recon.march`: `Recon.top`, `TopRow`, `Supervision`, `format_top`,
  `print_top`. Field names avoid the keywords `strategy` and `max_restarts`
  (`policy`, `limit`). `"mailbox"` is accepted for `"mbox"`.
- `forge top`: `--sort stack`, supervision columns, `--json`. Same ssh tunnel and
  observe tier as the other verbs; no `Actor.Debug` capability.
- `bin/shell_cmd.ml`: `:actors` and `:top [metric] [n]` (client-side sugar for
  `Recon.print_top(intro, ...)`; `forge rpc` unchanged).

A client-side composition from `ACTORS` was rejected: `ACTORS` is capped at 10 000
rows, so ranking 100 000 actors by stack from it would rank the wrong subset, and
supervisor policy needs one `ACTOR` call per supervisor.

## Measurements (macOS arm64, 100 000 actors: 70 000 bare + 10 000 supervisors x 2 children)

| Request | node time | reply |
|---|---|---|
| `TOP stack 10` | 17-18 ms | 2.3 KB |
| `TOP mbox 10` | 16-18 ms | 2.3 KB |
| `TOP mbox 1000` | 18 ms | 219 KB |
| `ACTORS mbox 10000` | 31-34 ms | 3.4 MB |
| `MEM` (the bare walk) | 10 ms | |

So the ranking costs about 7 ms over the walk (supervision rows and the pid index
are built for the rows shown only).

## Tests

- `observe_snapshot_check` (`native_observe_snapshot`, `native_observe_crashes`,
  `native_observe_types_hr`): ranking order and pid tie-break, supervisor policy
  and restarts held, `link` supervised/spawned/none, `parent_type`, and a
  deliberately deep-recursing actor ranking first on `stack` (the fixture
  subtracts, because LLVM turns a recursive addition into a loop and the stack
  would not grow).
- `recon_basic` (interpreter and compiled, same expected output): `Recon.top`.
- `native_forge_top`: `forge top --once` table and `--json` against the snapshot
  node (STACK column masked: page size differs).
- `forge/test/test_observe_cli.ml`: row rendering.
- `shell_session`: `Recon.top`, `:top`, `:actors`, usage errors.
