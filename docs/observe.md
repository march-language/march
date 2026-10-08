---
layout: docs
title: Observing a running node
nav_order: 15.2
permalink: /docs/observe/
---

# Observing a running node

A compiled March program can answer questions about itself while it runs: which
actors exist, how deep their mailboxes are, who is crashing, how busy each
scheduler is, how much memory is live, and which hot-reload epochs are still
pinned. It answers on a Unix socket, read-only, and `forge` has four commands
on top of it. This page is for the person on call: how to turn it on, what every
number means, and what to do when one looks wrong.

- [Turning it on](#turning-it-on)
- [The protocol](#the-protocol)
- [The verbs](#the-verbs)
- [The forge commands](#the-forge-commands)
- [Reading diagnose findings](#reading-diagnose-findings)
- [From inside a program: Recon and Diagnose](#from-inside-a-program-recon-and-diagnose)
- [Walkthrough: a node is slow, what now](#walkthrough-a-node-is-slow-what-now)
- [Interpreter vs compiled, and what is not there yet](#interpreter-vs-compiled-and-what-is-not-there-yet)

Everything here is the **observe tier**: it reports counts, states and kinds,
never message contents, actor state, or panic text. Reading actor state is a
separate, later debug tier (see the [end of the page](#what-is-not-there-yet)).

---

## Turning it on

Set one environment variable when you start the program:

```bash
MARCH_OBSERVE_SOCKET=/run/myapp/observe.sock ./myapp
```

| Variable | Effect |
|---|---|
| `MARCH_OBSERVE_SOCKET=<path>` | Serve the observe socket at `<path>`. |
| `MARCH_HOT_RELOAD_SOCKET=<path>` | If `MARCH_OBSERVE_SOCKET` is not set, the observe socket is served at `<path>.observe`, next to the reload socket. This is the path `forge` uses for `[hot-reload]` hosts. |
| `MARCH_OBSERVE_IDLE_MS=<ms>` | How long a connected client may stay silent before it is dropped (default 5000). |
| `MARCH_NODE_NAME=<name>` | The `node` field of every reply (default `pid:<os pid>`). |

Any compiled program serves it: no compiler flag is needed (the server is
started by the runtime's scheduler entry, `runtime/march_observe.c`). With
neither socket variable set, nothing is started. The interpreter does not serve
a socket; it answers the same questions in-process (see
[Recon](#from-inside-a-program-recon-and-diagnose)).

**Permissions.** The socket is created mode `0600`: only the user the program
runs as (and root) can connect. The filesystem permissions are the
authentication; there is no other. It is a separate socket from the hot-reload
socket, with its own threads, so an observer can never block or delay a deploy.

**The path.** A stale socket left at the path by an earlier run is replaced. Any
other kind of file there is left alone, the server does not start, and the
program logs `march: observe socket path exists and is not a socket`. A path
longer than the platform's Unix-socket limit (103 bytes on macOS, 107 on Linux)
is refused with a log line too. In both cases the program itself keeps running.
The socket is unlinked when the program exits.

**Limits.** At most 8 connections are served at once; the ninth gets
`"error":"busy"`. At most two windowed requests (`TOP` over a window) run at
once, so they cannot take every connection. A request line is at most 4096
bytes.

**What it costs.** Nothing runs until a client connects: one accept thread
waits on the socket. The counters the verbs report (dispatches, messages in and
out, last run time) are always kept, socket or not. Measured on Linux arm64
with `bench/actors/fanin_flood.march --opt 2` (a message-bound microbenchmark),
the counters cost about **+0.9%** at one scheduler (+0.92%, 95% interval
+0.73% to +1.16%, against the pre-counter runtime; later review fixes added
about 0.3% more), and nothing measurable at eight schedulers (every 8-scheduler
leg was inside the A/A noise). An open, idle socket measured +0.77% (1
scheduler) and -0.54% (8 schedulers), both inside the noise. A query walks the
actor table once: about 9-11 ms per 100 000 actors for the walk, about 20 ms for
a full `ACTORS` reply. Details: `specs/progress/2026-10-02-observe-r2-counters-crash-ring.md`
and `specs/progress/2026-10-02-observe-r1-snapshot-verbs.md`.

---

## The protocol

Connect, send **one line**, read **one line** of JSON, and the server closes the
connection. `\r\n` line endings are accepted. Verb names are upper case and
case-sensitive over the raw socket (`ping` is an `unknown_verb`; `forge observe`
upper-cases the verb for you).

```bash
echo PING | nc -U /run/myapp/observe.sock
```

```json
{"proto":"march.observe/1","node":"web-1","at_ms":1791167992809,"took_us":2,"truncated":false,"data":"pong"}
```

Every reply is this envelope:

| Field | Meaning |
|---|---|
| `proto` | Always `"march.observe/1"`. |
| `node` | `MARCH_NODE_NAME`, or `pid:<os pid>`. |
| `at_ms` | Wall-clock time of the reply, Unix milliseconds. |
| `took_us` | How long the verb took on the node, microseconds (includes any window it slept). |
| `truncated` | `true` if the verb's output passed the 16 MB reply limit; `data` is then `null`. |
| `data` | The verb's answer. Present on success. |
| `error` | An error code, in place of `data`. |

Error codes:

| Code | Meaning |
|---|---|
| `unknown_verb` | No such verb (check the case). `HELP` lists them. |
| `bad_args` | The arguments did not parse: an unknown sort or section, a number out of range, an extra word. |
| `not_found` | `ACTOR <pid>` for a pid that was never spawned. A pid that lived and died is not an error; it answers with `alive: false`. |
| `busy` | Eight connections are already open, or two windowed `TOP`s are already running. Retry. |
| `line_too_long` | The request line was over 4096 bytes. |
| `windowed_in_process` | A windowed `SCHED` or `TOP` was asked in-process (through `Recon`/`observe_query`): the window would sleep a scheduler thread. `Recon` takes its windows differently; you only see this if you build the request yourself. |
| `out_of_memory` | The node could not allocate the reply. |

---

## The verbs

`HELP` lists every verb the node serves with its arguments and tier:

```json
{"name":"ACTORS","tier":"observe","args":"[mbox|status|epoch|pid] [n]","help":"live actors, sorted, at most n (default 100, max 10000)"}
```

| Verb | Arguments | Answers |
|---|---|---|
| `HELP` | | the verb table |
| `PING` | | `"pong"` |
| `ACTORS` | `[mbox\|status\|epoch\|pid] [n]` | live actors, sorted, at most `n` |
| `ACTOR` | `<pid>` | one actor in detail, alive or dead |
| `TREE` | | the supervision tree and the unsupervised actors |
| `NAMES` | | registered names and their pids |
| `SCHED` | `[window_ms]` | scheduler threads, utilisation, scheduler counters |
| `MEM` | | RSS, peak RSS, live heap objects, queued messages |
| `EPOCHS` | | hot-reload epochs, pins, dispatch slots, reload counters |
| `CRASHES` | `[n]` | the last `n` crashes, without messages |
| `TOP` | `<attr> <n> [window_ms]` | the `n` actors highest on one attribute |
| `SNAPSHOT` | `[sections]` | several of the above from one actor walk |
| `STATE` | `<sig> nonce:… not_after_ms:… pid:<p> [timeout_ms:<t>]` | debug tier: one actor's state ([below](#the-debug-tier-signed-requests)) |
| `CRASHES_FULL` | `<sig> nonce:… not_after_ms:… [n:<n>]` | debug tier: `CRASHES` with each crash's message |

The example replies below are real output from
`test/native/observe_snapshot.march` (3 supervisors of 4 children each, 5 bare
actors, one of them stalled with 500 messages queued, one supervised child
crashed), trimmed to fit.

### ACTORS

`ACTORS [mbox|status|epoch|pid] [n]`. Default `mbox 100`; `n` is 1 to 10 000;
the two words may come in either order.

| Sort | Order |
|---|---|
| `mbox` | deepest waiting work (`mbox + held`) first |
| `status` | running, then runnable, then waiting, then exiting; deepest mailbox within each |
| `epoch` | oldest code epoch first (the actors holding a drain back) |
| `pid` | ascending pid |

```json
{"total":20,"shown":3,"sort":"mbox","actors":[
  {"pid":15,"type":null,"names":["hot"],"status":"waiting","mbox":500,"user_mbox":500,"held":0,
   "mbox_limit":0,"mbox_policy":"unbounded","code_epoch":1,"cap_epoch":0,"sched":0,"pinned":false,
   "draining":false,"parent":null,"children":0,"spawned_by":null,"slices":1,"msgs_in":1,"msgs_out":0,
   "crashes":0,"child_crashes":0,"idle_ms":9592},
  ...]}
```

`total` is every live actor; `shown` is how many rows follow. Every actor row,
here and in `ACTOR` and `SNAPSHOT`, has these fields:

| Field | Meaning |
|---|---|
| `pid` | The pid index (what `pid_to_int` returns). Pids are never reused. |
| `type` | The actor type's name, **only in builds compiled with `--hot-reload`** (the name comes from the dispatch table). `null` otherwise. |
| `names` | Names it is registered under (`Actor.register`), possibly empty. |
| `status` | `running` (on a scheduler now), `runnable` (queued to run), `waiting` (blocked: waiting for a message, a timer, a reply or I/O), `exiting` (finished, death not yet processed), `starting` (spawned, not yet run once). |
| `mbox` | Messages queued in its mailbox, user and control messages together. |
| `user_mbox` | The user messages among them. |
| `held` | Messages an `Actor.call` has taken off the mailbox while this actor waits for the reply. They go back on the mailbox after the reply. An actor stuck in a slow call shows `mbox: 0` and a large `held`; the `mbox` sorts and `MEM` count `mbox + held` as its waiting work. (`mailbox_size(pid)` in March code still reads the mailbox alone.) |
| `mbox_limit` | Its mailbox limit, `0` for unbounded. |
| `mbox_policy` | What happens at the limit: `unbounded`, `block` (the sender waits), `drop_new`, `drop_old`. |
| `code_epoch` | The hot-reload code epoch the actor is running (1 in a program that has never been reloaded). |
| `cap_epoch` | The pid's capability epoch, bumped when a supervisor respawns the slot. |
| `sched` | The scheduler that last ran it, `null` if none has. |
| `pinned` | `true` if it may only run on scheduler 0 (the process main thread). |
| `draining` | `true` while it is being stopped gracefully: new sends are refused, the queue is being finished. |
| `parent` | Its supervisor's pid, `null` when unsupervised. |
| `children` | How many supervised children it has (greater than 0: it is a supervisor). |
| `spawned_by` | The pid of the actor that spawned it, `null` if it was spawned from outside an actor (e.g. from `main`). |
| `slices` | Times it has been dispatched (run), since spawn. |
| `msgs_in` | User messages it has received, since spawn. |
| `msgs_out` | Messages it has sent that were enqueued, since spawn, including `Actor.call` requests and replies, and sends to other nodes (`NodeSend`, `Node`). Sends from a task or from `main` do not appear: they are not actors and have no row. |
| `crashes` | Crash-ring entries for this pid in the last hour. A restarted child gets a new pid, so this is usually 0 on live rows; see `child_crashes`. |
| `child_crashes` | Crash-ring entries in the last hour whose supervisor is this pid: where a crash-looping slot's count lands. |
| `idle_ms` | Milliseconds since it last ran (1 ms resolution), `null` if it never has. |

`slices`, `msgs_in` and `msgs_out` are cumulative. For a rate, use `TOP` with a
window.

### ACTOR

`ACTOR <pid>`: one actor in detail.

```json
{"pid":4,"alive":true,"cap_epoch":0,
 "actor":{"pid":4,"names":["sup_one"],"status":"waiting","children":4,"child_crashes":1, ...},
 "children":[20,1,2,3],
 "spawned":[],
 "supervisor":{"strategy":"one_for_one","max_restarts":5,"window_secs":60,
               "restarts_held":1,"restart_ages_ms":[15179]},
 "terminal":null}
```

| Field | Meaning |
|---|---|
| `alive`, `actor` | Whether it is live, and its row (above) if so; `actor` is `null` when dead. |
| `children` | Its supervised children's pids, in `supervise`-block order. |
| `spawned` | Unsupervised actors it spawned that are still alive. |
| `supervisor` | For a supervisor: its strategy (`one_for_one`, `one_for_all`, `rest_for_one`), `max_restarts` within `window_secs`, how many restarts are currently inside the window (`restarts_held`), and their ages (up to 16). `null` otherwise. |
| `terminal` | For a dead actor: `{"kind": "Crash" \| "Killed" \| "Normal"}`. |

A dead actor answers with the kind of death and nothing else:

```json
{"pid":0,"alive":false,"cap_epoch":0,"actor":null,"children":[],"spawned":[],"supervisor":null,"terminal":{"kind":"Crash"}}
```

The panic message is never shown here or anywhere in the observe tier: panic
strings can carry payloads (tokens, user data). It is kept in the node's crash
ring for the planned debug tier.

### TREE

```json
{"total":20,
 "roots":[{"pid":4,"type":null,"names":["sup_one"],"status":"waiting","mbox":0,"link":null,
           "children":[{"pid":20,"status":"waiting","mbox":0,"link":"supervised","children":[]}, ...]}, ...],
 "unsupervised":[15,16,17,18,19],
 "truncated":false}
```

A root is an actor with no supervisor that supervises or spawned something live.
Children nest under their supervisor (`link: "supervised"`), or, if
unsupervised, under the live actor that spawned them (`link: "spawned"`).
Actors in neither role are listed by pid in `unsupervised`. A node's `mbox` here
is waiting work (`mbox + held`). The tree is cut at 64 levels or 10 000 nodes,
and `truncated` says so.

### NAMES

```json
{"names":[{"name":"hot","pid":15},{"name":"sup_one","pid":4}]}
```

Sorted by name. Local registrations only (no global registry).

### SCHED

`SCHED [window_ms]`: default 200, at most 5000. With a window the observe thread
samples each scheduler's idle time, sleeps the window, samples again, and
reports utilisation over it. `SCHED 0` reports lifetime figures only and does
not sleep.

```json
{"schedulers":14,"window_ms":200,
 "threads":[{"id":0,"started":true,"entered":true,"dispatches":23,"idle_polls":8683,"idle_ms":10302,
             "utilisation":0.0043,"lifetime_utilisation":0.00056}, ...],
 "utilisation":0.0049,"lifetime_utilisation":0.0004,
 "live_procs":21,"procs_spawned":22,"runq":0,"stack_failures":0,"msgs_dropped":0,
 "stacks_recycled":1,"timers":2,"ctx_released":1,"procs_freed":1,"procs_awaiting_free":0,
 "metas_freed":1,"metas_awaiting_free":0}
```

Utilisation is `1 - idle/wall` (0.0 to 1.0); idle time is only counted on the
scheduler's idle path, so a scheduler running any green thread, actor or task,
counts as busy. The top-level `utilisation` averages the schedulers that have
started. `idle_ms` per thread is cumulative idle time. `runq` is what is queued
to run right now across the node; `msgs_dropped` is the node's total of messages
dropped at a mailbox limit. `dispatches` and `idle_polls` are a racy read of
per-thread fields and only good for orders of magnitude.

### MEM

```json
{"rss_bytes":4816896,"peak_rss_bytes":4816896,"live_objects":527,"stacks_recycled":1,"queued_messages":500,"actors":20}
```

| Field | Meaning |
|---|---|
| `rss_bytes` | Resident set size now (`null` where the platform gives none). |
| `peak_rss_bytes` | Highest RSS so far. |
| `live_objects` | Heap cells allocated and not yet freed. Queued messages are heap objects, so a deep mailbox raises it. |
| `queued_messages` | The sum of every actor's waiting work (`mbox + held`). |
| `actors` | Live actors. |

### EPOCHS

```json
{"current":1,"pins":[{"epoch":1,"pins":20,"current":true,"draining":false}],"slots":[],
 "counters":{"deferred":0,"converted":0,"dropped":0,"killed":0,"stopped":0,"advances":0,
             "early":0,"forced":0,"markers_live":0,"markers_lost":0}}
```

`pins` lists every epoch something still runs, with how many units pin it and
whether it is draining. `slots` (hot-reload builds only) lists each dispatch
slot: name, implementation hash, epoch, activation time and signer. `counters`
are the hot-reload delivery counters; see [Hot Code Reload](hot-code-reload.md).

### CRASHES

`CRASHES [n]`: the last `n` crashes, newest first (default 20, at most 256; the
ring keeps 256).

```json
{"total":1,"crashes":[{"seq":1,"kind":"crash","pid":0,"type":null,"code_epoch":1,"supervisor":4,"restart":1,"at_ms":1791167983217}]}
```

| Field | Meaning |
|---|---|
| `total` | Crashes since the node started (the ring keeps the last 256). |
| `kind` | `crash` (an actor died abnormally), `draining` (killed at a hot-reload hard deadline), `panic` (an unsupervised panic, recorded just before the process exits). |
| `pid`, `type` | The actor that died; `type` only in `--hot-reload` builds. |
| `supervisor` | Its supervisor's pid, `null` if unsupervised. |
| `restart` | The slot's crash streak, read after the supervisor was told: 1 for the first crash, 3 for the third in a row. |
| `at_ms` | Wall-clock time, Unix milliseconds. |

There is no message field, by design: the observe tier never returns panic
text. The ring keeps the message for the planned debug tier, which will need a
separate capability.

### TOP

`TOP mbox|crashes|slices|msgs_in|msgs_out <n> [window_ms]`: the `n` actors
highest on one attribute (`n` up to 10 000).

- `mbox` ranks by waiting work (`mbox + held`) now. No window.
- `crashes` ranks by `crashes + child_crashes` (last hour), so a crash-looping
  supervisor comes first. No window.
- `slices`, `msgs_in`, `msgs_out` rank by **how much the counter rose** over
  `window_ms` (default 1000, at most 5000): two walks, the observe thread asleep
  between them. An actor born during the window counts from 0. An explicit
  window of `0` ranks by the cumulative counter instead, with no sleep.

```json
{"attr":"mbox","window_ms":null,"total":20,
 "top":[{"pid":15,"value":500,"type":null,"names":["hot"],"status":"waiting","mbox":500}, ...]}
```

`value` is what was ranked; `window_ms` is `null` when no window was used. Only
two windowed `TOP`s run at once; a third gets `busy`.

### SNAPSHOT

`SNAPSHOT [sections]`, sections as a comma list or words, from `actors`, `tree`,
`names`, `sched`, `mem`, `epochs`, `crashes` (default: all). Every actor section
comes from **one** walk, so they agree with each other.

```json
{"mem":{"rss_bytes":2834432,"queued_messages":500,"actors":20, ...},
 "crashes":{"total":1,"crashes":[ ... ]}}
```

Each section is that verb's data, with fixed arguments: `actors` is
`ACTORS mbox 100`, `sched` is `SCHED 0` (lifetime only, never sleeps), `crashes`
is `CRASHES 20`. This is what `forge diagnose` and `forge status` read.

---

## The debug tier: signed requests

The verbs above show counts, never data. Two more show data: `STATE` (an
actor's state) and `CRASHES_FULL` (crashes with their panic messages). A node
answers them only when all of these hold:

1. **It was built with a deploy key**: `march --compile --hot-reload <Mod>
   --signing-pubkey <base64>`, the same key `forge deploy hot` signs patches
   with. Any other build answers `signing_not_configured`.
2. **The request is signed by that key.** The signature covers the whole line
   except the signature itself, so changing the pid or the expiry after signing
   gives `bad_signature`.
3. **It is fresh.** Each request carries a random `nonce` (16-64 hex digits) and
   a `not_after_ms` wall-clock expiry at most 60 s ahead. A node refuses an
   expired request (`expired`), one that expires too far ahead
   (`not_after_too_far`), and a nonce it has already seen (`replay`). It
   remembers the last 256 unexpired nonces. If all 256 are still unexpired it
   refuses new requests (`nonce_ring_full`) rather than forget one.
4. **The node's policy allows the verb.** `$MARCH_DEBUG_POLICY` names a file
   that lists the allowed verbs one per line (`#` starts a comment). With no
   file, nothing is allowed (`policy`). The file is read on every request, so
   editing it takes effect at once.

The checks run in that order: an unsigned client learns nothing about the
policy. Every attempt, allowed or not, appends a line to the audit log the
reload server writes (`$MARCH_AUDIT_LOG`, default
`~/.local/share/march/audit.jsonl`):

```json
{"ts":1791223456789,"type":"debug","verb":"STATE","pid":42,"nonce":"9f3c…","signer":"<pubkey hex>","result":"ok"}
```

`forge observe` builds and signs these requests for you:

```bash
forge observe --socket /run/myapp/observe.sock --state 42          # STATE, 1 s to answer
forge observe --env prod --state 42 --timeout-ms 5000
forge observe --env prod --crashes-full --count 50
```

It signs with `~/.march/ed25519_secret.key` and makes each request valid for
30 s, so a node whose clock differs by more than 30 s refuses it. forge then
says which way the clock is off.

A `STATE` reply's `data` is `{"pid":42,"state":"{ n: 5, tags: [x] }","error":null}`.
`state` is exactly what `Actor.inspect_state` returns inside the program: the
state fields in declaration order, each printed by its `Show`, `<opaque>` for a
field that holds functions. When the actor cannot answer, `state` is `null` and
`error` says why:

- `dead`: the pid is not running.
- `timeout`: the actor did not answer within `timeout_ms` (the node allows at
  most 10000; `forge observe --timeout-ms` at most 8000, since forge waits 10 s
  for any reply).
  An actor is asked between messages, so one stuck in a long handler or a
  nested `receive` cannot answer.
- `render failed: …`: a field's `Show` panicked. The actor keeps running.
- `the actor's code changed by a hot reload …`: the renderer predates a reload
  that may have changed the state's layout.

The request skips the actor's mailbox limit, so a full mailbox still answers.

## The forge commands

All four take a target the same way:

- `--socket PATH`: a local observe socket (the program's `MARCH_OBSERVE_SOCKET`).
- otherwise the `[hot-reload]` hosts in `forge.toml`, reached over ssh at
  `<reload socket>.observe`; `--env NAME` picks the `[[hot-reload.env]]`
  entries with that name. `forge status` also reads `topology.toml`.

### forge observe

```
forge observe [REQUEST...] [--section S]... [--json] [--socket PATH] [--env NAME]
forge observe --state PID [--timeout-ms MS] | --crashes-full [-n N]   [--socket PATH] [--env NAME]
```

Sends one request and prints the reply envelope (indented, or one line per host
with `--json`). The request is the positional words; the first is upper-cased,
so `forge observe actors mbox 20` works. With no words it sends `SNAPSHOT`;
`--section` (repeatable) narrows it.

```bash
forge observe --socket /run/myapp/observe.sock                 # SNAPSHOT, every section
forge observe --socket /run/myapp/observe.sock actors mbox 10  # the 10 deepest mailboxes
forge observe --socket /run/myapp/observe.sock ACTOR 42
forge observe --env prod --section mem --section crashes       # every prod host, over ssh
forge observe --env prod TOP msgs_in 10 2000 --json
```

Exit 0 when every target answered; 1 if any failed, including an error reply
(`error: observe: unknown_verb`).

### forge status

```
forge status [--json] [--socket PATH] [--env NAME]
```

One line per node. With a `topology.toml`, it first prints `forge topology
status`'s report (alive, versions, drift), then the observe line for each node
that has a socket; otherwise it reads the `[hot-reload]` hosts.

```
web-1: actors 1, queued 1550, rss 5 MB, busy 0%, crashes (1h) 0, deepest mailbox sink (pid 0) 1550
```

`busy` is the lifetime utilisation over all schedulers (since start, not now:
use `forge diagnose` or `SCHED` for now). `crashes (1h)` counts the crashes in
the last 20 ring entries that fall in the last hour. The deepest mailbox is
named by its first registered name, else its type, else `?`. A node that does
not answer prints `observe unavailable (<reason>)`. `--json` prints one
`march.status/1` document:

```json
{"proto":"march.status/1","topology":null,"nodes":[{"name":"web-1","observe":{"actors":20,"queued":500,"rss_mb":2,"utilisation":0.0003,"crashes_hour":1,"deepest":{"pid":15,"name":"hot","waiting":500}}}]}
```

### forge top

```
forge top [--sort ATTR] [-n N] [--window MS] [--once] [--socket PATH] [--env NAME]
```

Redraws the busiest actors in place until interrupted. `--sort` is `mbox`
(default), `crashes`, `slices`, `msgs_in` or `msgs_out`; the last three rank the
change over `--window` (default 1000 ms), which is also their refresh. The
others refresh every max(1 s, 4x the time the node took to answer). `-n` is the
row count (default 20; note it is `-n`, not `--n`). `--once` prints one frame
with no screen control, for scripts and tickets. Over `--env`, it watches the
first matching host.

```
web-1  actors 1, queued 2598, rss 5 MB, busy 0%, crashes (1h) 0, deepest mailbox sink (pid 0) 2598
sorted by msgs_out over 1000 ms

     PID  NAME                 TYPE               STATUS        MBOX   MSGS_OUT
       0  sink                                    waiting       2597          0
```

The first line is the `forge status` summary. `MBOX` is waiting work
(`mbox + held`); the last column is the ranked value.

### forge diagnose

```
forge diagnose [--window MS] [--dump FILE] [--json] [--socket PATH] [--env NAME]
```

Takes two `SNAPSHOT`s `--window` apart (default 1000 ms), runs a fixed list of
checks over the pair, and prints a `march.diagnose/1` envelope per target:

```json
{
  "proto": "march.diagnose/1",
  "node": "web-1",
  "window_ms": 1000,
  "findings": [
    {
      "id": "mailbox.growth",
      "severity": "critical",
      "rows": [ { "pid": 0, "mbox": 2066, "delta": 499, "names": [ "sink" ] } ],
      "next": "forge observe ACTORS mbox 20, then ACTOR <pid> for the deepest"
    }
  ],
  "coverage": {
    "ran": [ "mailbox.growth", "mailbox.over_limit", "sched.saturated", "sched.idle_imbalance",
             "crash.loop", "rc.climb", "epoch.stuck", "epoch.old_units" ],
    "unavailable": {
      "cluster.suspect": "no cluster section yet (observe plan R1.3)",
      "names.lost": "global-registry Lost events are not recorded"
    },
    "partial": {
      "mailbox.over_limit": "per-actor dropped counts are not tracked; the node total is used"
    }
  }
}
```

Each finding has an `id`, a `severity` (`warning` or `critical`), the `rows`
that triggered it, and `next`: the command to run next.

| Exit | Meaning |
|---|---|
| 0 | nothing found |
| 1 | warnings only |
| 2 | at least one critical finding |
| 3 | a target could not be reached |

With several targets the exit code is the worst of them. `--dump FILE` also
writes the raw before/after pair (`{"before": ..., "after": ...}`) for the first
target, in the same format as the test fixtures in
`forge/test/fixtures/diagnose/`: attach it to the incident, or turn it into a
regression fixture.

`forge diagnose` is a good health probe for a cron job or a deploy gate:

```bash
forge diagnose --env prod --json > diagnose.json; rc=$?
[ "$rc" -ge 2 ] && page-someone < diagnose.json
```

---

## Reading diagnose findings

Each check compares the **before** and **after** snapshots. Thresholds below are
exact, from `forge/lib/diagnose.ml`; `stdlib/diagnose.march` implements the same
checks with the same thresholds, and both are tested against the same fixtures.
"Waiting work" is `mbox + held`.

### mailbox.growth

**Fires when** an actor's waiting work rose across the window (any increase) and
is at least 10 in the after snapshot. **Critical** if one of those actors holds
more than half of the node's queued messages and the node has 100 or more
queued; **warning** otherwise. The rows are the five that grew most, with their
depth and growth (`delta`).

**Usually means** a consumer slower than its producers: a handler blocked on
something slow (a call, I/O, a sleep), a hot actor everyone sends to, or a
consumer that crashed and restarted and is catching up. A large `held` with
`mbox` near 0 means the actor is waiting in an `Actor.call` while work piles up
behind it.

**Next:** `forge observe ACTORS mbox 20`, then `ACTOR <pid>` for the deepest.
Look at its `status` (is it running, or waiting?), `idle_ms` (has it run
lately?), and `held`. `forge top --sort msgs_in` tells you whether it is still
draining at all. If the queue is bounded by design, give the actor a mailbox
limit and a policy rather than letting it grow.

### mailbox.over_limit

**Fires when** an actor with a mailbox limit and a `drop_new` or `drop_old`
policy has waiting work at or over its limit, **and** the node's dropped-message
total (`SCHED`'s `msgs_dropped`) rose during the window. **Warning.** Actors with
the `block` policy never trip it (their senders wait instead).

**Usually means** the node is shedding load: messages to that actor are being
discarded. This is the policy working, but someone is losing messages.

**Next:** decide whether dropping is acceptable. If not, raise the limit, add
consumers, or slow the producers upstream. This check is *partial*: per-actor
drop counts are not tracked, so a drop elsewhere on the node in the same window
also satisfies the second condition.

### sched.saturated

**Fires when** some scheduler was more than 95% busy over the window (idle time
under 5% of the wall time between the snapshots) **and** the node's run queue was
non-empty in the after snapshot. **Warning.**

**Usually means** the node is CPU-bound: there is runnable work and no idle
scheduler to take it. Latency rises for everything on that node.

**Next:** `forge observe TOP slices 10 1000` shows who is being dispatched most
(or `forge top --sort slices`). A single actor at the top is a hot spot to
split or shard; a broad spread means the node needs more cores or less work.

### sched.idle_imbalance

**Fires when** the node has at least two schedulers with data, one more than
80% busy over the window and another less than 20% busy. **Warning.**

**Usually means** one scheduler carries the load. Common causes: work pinned to
scheduler 0 (the main thread: `pinned: true` in the rows), or one hot actor,
which can only run on one scheduler at a time. On a lightly loaded node with one
busy actor this fires and is harmless.

**Next:** `forge observe ACTORS status 20` and look at `sched` and `pinned` on
the running actors; `TOP slices 10 1000` for the hot one.

### crash.loop

**Fires when** the crash ring holds 3 or more crashes with the same supervisor.
**Critical** if 3 or more fall in the last minute (before the after snapshot's
time); **warning** if 3 or more fall in the last hour. Rows are the supervisors
and their counts. Only supervised crashes count (an unsupervised panic has no
supervisor), and only the 20 most recent ring entries are read (the snapshot's
`crashes` section).

**Usually means** a child that cannot start or keeps hitting the same bad input.
When the supervisor exhausts `max_restarts` within its window, it gives up and
the failure moves up the tree.

**Next:** `forge observe CRASHES 20` for the kinds, pids and restart numbers, then
`ACTOR <supervisor>` for its strategy, `max_restarts`, and how many restarts it
is currently holding (`restarts_held`, `restart_ages_ms`). The panic text is not
available from the observe tier; check the program's own logs.

### rc.climb

**Fires when** live heap objects (`MEM`'s `live_objects`) were at least 1000
before and grew by more than 10% across the window, **while** the actor count
stayed within 5%. **Warning.** Never fires under the interpreter (no gauge).

**Usually means** memory is being held with no new actors to explain it: a leak,
a cache without a bound, or messages piling up. Queued messages are heap
objects, so this often fires together with `mailbox.growth`; fix that first and
see whether this one goes away.

**Next:** take `forge observe --section mem` a few times over minutes. A steady
climb with flat `queued_messages` and flat actors is a leak worth a bug report.
A one-window spike that settles is usually a burst of work.

### epoch.stuck

**Fires when** any pinned hot-reload epoch is marked draining. **Warning.**

**Usually means** a deploy is still waiting for actors to leave old code: a
long-running handler, or an actor that never receives the migrate marker.

**Next:** `forge hot-reload status`; then `forge observe ACTORS epoch 20` lists
the actors on the oldest epoch first.

### epoch.old_units

**Fires when** some epoch two or more behind the current one still has pins.
**Warning.**

**Usually means** units still run code two or more deploys old, which every
later deploy's drain has to wait for.

**Next:** `forge observe ACTORS epoch 20` to find them, and `ACTOR <pid>` for
what they are doing.

### Coverage

The envelope's `coverage` says what was and was not checked, so an empty
`findings` list is never read as "healthy" for things nobody looked at:

- `ran`: every check above.
- `unavailable`: `cluster.suspect` (the snapshot has no cluster section yet, so
  unreachable or suspect peers are not reported) and `names.lost` (global
  registry `Lost` events are not recorded).
- `partial`: `mailbox.over_limit`, which uses the node's total dropped count
  because per-actor drop counts are not tracked.

Two more limits come from the snapshot itself: its `actors` section is the 100
deepest mailboxes (so `mailbox.growth` sees at most those), and its `crashes`
section is the last 20 crashes (so `crash.loop` sees at most those).

---

## From inside a program: Recon and Diagnose

The stdlib modules `Recon` and `Diagnose` ask the same questions from March
code, in-process, on both the interpreter and compiled code. Every function
takes a `Cap(Actor.Introspect)`, which `main` mints from its `IO` capability
with `Actor.introspect(io)`; a module that names the capability declares
`needs Actor.Introspect`. Nothing here returns a panic message.

| Function | Returns |
|---|---|
| `Recon.info(c, pid)` | `Option(ActorInfo)`: one live actor (`None` if dead or never spawned) |
| `Recon.actors(c)` | `List(ActorInfo)`, deepest mailbox first (at most 10 000) |
| `Recon.proc_count(c, attr, n)` | `List((Int, Int))`: (pid, value), highest first; counters are cumulative |
| `Recon.proc_window(c, attr, n, window_ms)` | the same, ranked by the rise over the window (`slices`, `msgs_in`, `msgs_out`) |
| `Recon.tree(c)` | `List(SupNode)`: `SupNode(pid, type, names, children)` |
| `Recon.node_stats(c)` | `NodeStats`: actors, queued, `rss_bytes`, `live_objects`, schedulers, `crashes_total` |
| `Recon.crashes(c, n)` | `List(CrashReport)`: seq, kind, pid, type, supervisor, restart, at_ms |
| `Recon.epochs(c)` | `EpochReport`: current epoch and (epoch, pins) pairs |
| `Recon.scheduler_usage(c, window_ms)` | `List((Int, Float))`: (scheduler id, fraction busy) |
| `Diagnose.run(c, window_ms)` | `List(Finding)`: the `forge diagnose` findings for this program |
| `Diagnose.findings(before, after)` | the same over two `SNAPSHOT` envelopes you already have |

`ActorInfo` carries `pid`, `type_name`, `names`, `status`, `mbox`, `held`,
`parent`, `children`, `slices`, `msgs_in`, `msgs_out`, `crashes` and
`child_crashes`, with the meanings in the [row table](#actors). A
`Diagnose.Finding` is `{ id, severity, rows, next }`, where `rows` is a list of
pids (or scheduler ids, supervisor pids, epochs) rather than forge's objects.

The windowed functions (`proc_window`, `scheduler_usage`, `Diagnose.run`) take
two samples and sleep the **calling** green thread between them, so call them
from a task or an actor that can afford to wait, not from a hot handler.

A node report from `main`:

```march
mod Main do
  needs IO
  needs IO.Console
  needs Actor.Introspect

  actor Worker do
    state { n : Int }
    init  { n: 0 }
    on Work(k : Int) do
      { n: state.n + k }
    end
  end

  fn report(c : Cap(Actor.Introspect)) do
    let ns = Recon.node_stats(c)
    println("actors " ++ int_to_string(ns.actors) ++ ", queued " ++ int_to_string(ns.queued))
    match ns.rss_bytes do
      Some(b) -> println("rss " ++ int_to_string(b / 1048576) ++ " MB")
      None -> println("rss unknown (interpreter)")
    end
    -- The three deepest mailboxes, as (pid, waiting).
    List.each(Recon.proc_count(c, "mbox", 3), fn p ->
      match p do
        (pid, depth) ->
          let label = match Recon.info(c, pid) do
            Some(a) -> String.join(a.names, ",")
            None -> "(gone)"
          end
          println("  pid " ++ int_to_string(pid) ++ " " ++ label ++ ": " ++ int_to_string(depth))
      end)
  end

  fn main(io : Cap(IO)) do
    let c = Actor.introspect(io)
    let w = spawn(Worker)
    let _r = Actor.register(w, "worker")
    let _ = send(w, Work(1))
    report(c)
  end
end
```

Rates, scheduler load and recent crashes:

```march
mod Main do
  needs IO
  needs IO.Console
  needs Actor.Introspect

  fn busiest(c : Cap(Actor.Introspect)) do
    -- Who handled the most messages over the next half second.
    List.each(Recon.proc_window(c, "msgs_in", 5, 500), fn p ->
      match p do
        (pid, n) -> println(int_to_string(pid) ++ ": " ++ int_to_string(n) ++ " in 500 ms")
      end)
    -- How busy each scheduler was over the next second.
    List.each(Recon.scheduler_usage(c, 1000), fn s ->
      match s do
        (id, u) -> println("scheduler " ++ int_to_string(id) ++ ": " ++ float_to_string(u))
      end)
    -- Recent crashes: how, where, and which restart, never the message.
    List.each(Recon.crashes(c, 5), fn cr ->
      let sup = match cr.supervisor do
        Some(s) -> int_to_string(s)
        None -> "none"
      end
      println(cr.kind ++ " under " ++ sup ++ ", restart " ++ int_to_string(cr.restart)))
  end

  fn main(io : Cap(IO)) do
    busiest(Actor.introspect(io))
  end
end
```

A self-check, for a health endpoint or a periodic task:

```march
mod Main do
  needs IO
  needs IO.Console
  needs Actor.Introspect

  fn check(c : Cap(Actor.Introspect)) : Bool do
    let fs = Diagnose.run(c, 1000)
    List.each(fs, fn f ->
      println(f.severity ++ " " ++ f.id ++ ": " ++ f.next))
    List.any(fs, fn f -> f.severity == "critical")
  end

  fn main(io : Cap(IO)) do
    let c = Actor.introspect(io)
    if check(c) do
      println("critical finding")
    else
      println("healthy")
    end
  end
end
```

---

## Walkthrough: a node is slow, what now

Requests to `web-1` are timing out. Start wide and narrow down.

**1. Is it alive, and what does it look like?**

```bash
forge status --env prod
```

```
web-1: actors 1, queued 1550, rss 5 MB, busy 0%, crashes (1h) 0, deepest mailbox sink (pid 0) 1550
```

It answers, nothing is crashing, and the schedulers are mostly idle over its
lifetime. But 1550 messages are queued, all of them on `sink`. A mostly idle
node with a deep queue is a consumer that is stuck, not a node that is
overloaded.

**2. What is wrong right now?**

```bash
forge diagnose --env prod --dump /tmp/web-1-incident.json
echo $?    # 2: critical
```

Its `findings`, in short: `mailbox.growth` (critical; row `{"pid": 0, "mbox":
2066, "delta": 499, "names": ["sink"]}`) and `rc.climb` (warning; live objects
1574 to 2073, actors 1). `sink`'s queue grew by about 500 a second and it holds
the whole node's queue, so this is critical. `rc.climb` is the same queue seen
from the heap: messages are heap objects. The `--dump` file keeps both raw
snapshots for the incident ticket.

**3. Is it draining at all?**

```bash
forge top --env prod --sort msgs_in --once -n 5
```

```
web-1  actors 1, queued 2598, rss 5 MB, busy 0%, crashes (1h) 0, deepest mailbox sink (pid 0) 2598
sorted by msgs_in over 1000 ms

     PID  NAME                 TYPE               STATUS        MBOX    MSGS_IN
       0  sink                                    waiting       2597          0
```

`sink` received nothing in the last second while its queue kept growing.

**4. What is it doing?**

```bash
forge observe --env prod ACTOR 0
```

```json
{"pid":0,"alive":true,"actor":{"pid":0,"names":["sink"],"status":"waiting","mbox":2616,
 "held":0,"msgs_in":1,"msgs_out":0, ...},"supervisor":null,"terminal":null}
```

`msgs_in: 1`: it has taken one message off its mailbox since it started, and is
`waiting` inside that handler, not in `receive`: the first handler is blocked
(here, a long sleep; in production, typically a slow call or I/O). With `held`
large instead, it would be waiting in an `Actor.call`. The fix is in that
handler: give the slow operation a timeout, move it to a task, or put a mailbox
limit on `sink` so the node sheds load instead of growing.

---

## A remote shell: forge shell and forge rpc

`forge shell` evaluates March on a running node. Each input is compiled on
your machine against the project, as `forge build` would compile it, into a
small library. That library is signed with the deploy key and sent to the
node, which loads it and runs it as a task. The node answers with the
result and anything the input printed.

```
$ forge shell --env prod
attached at epoch 3 (:help for commands, :quit to leave)
march> Actor.list(intro)
[Pid(0), Pid(1), Pid(2)]
march> let c = Actor.whereis(intro, "counter")
c : Option(Pid(a))
march> List.range(1, 1000) limit: 3
[1, 2, 3, … 996 more]
march> println("hello")
hello
()
```

```bash
forge rpc --env prod 'Scheduler.live_procs()'   # one input; exit 1 if it did not run
```

What a node needs:

- **A deploy key.** A `--hot-reload` build with `--signing-pubkey`, the same
  key `forge deploy hot` signs with (`~/.march/ed25519_secret.key` on your
  machine).
- **A shell policy.** `$MARCH_SHELL_POLICY` names a file listing, one per
  line, the capabilities an input may use. With no file, nothing is allowed.

Inputs:

| You type | It does |
|---|---|
| `<expr>` | runs it and prints the value (collections and strings cut at 50) |
| `<expr> limit: N` / `limit: all` | the same, cutting at `N` / not at all |
| `let x = <expr>` | runs it and keeps the value on the node for later inputs |
| `:t <expr>` | the expression's type; nothing runs |
| `:limit N`, `:caps`, `:help`, `:quit` | |

Capabilities are pre-bound names: `console` (`Cap(IO.Console)`), `clock`,
`intro` (`Cap(Actor.Introspect)`), `debug` (`Cap(Actor.Debug)`).

A value prints by its type, the way you would write it:

```
march> Json.parse("{\"a\": [1, true]}")
Ok(Object([("a", Array([Number(1.), Bool(true)]))]))
march> [{ name: "first", tags: ["a", "b", "c"] }] limit: 2
[{ name: "fi"… 3 more chars, tags: ["a", "b", … 1 more] }]
```

- Records, tuples and constructors print field by field, with constructor
  names. A type that derives `Show` prints as its derived `show` would.
- Strings print quoted and escaped.
- The limit applies at every depth: each list, Array, Map and Set shows at
  most `N` elements then `… n more`, and each string at most `N` characters
  then `… n more chars`. `limit: all` (or `:limit 0`) turns it off.
- A type with a hand-written `Show` prints through its `show`, cut at 16 KiB
  with `… (n more bytes)`.
- A function prints `<fn>`; a Pid and other runtime values print as
  `to_string` prints them, as does a type whose constructors are private
  (`ptype`).

The shell generates this renderer from the input's static type, into the
input's fragment only (`bin/shell_render_gen.ml`, stdlib `ShellRender`); the
node's code is not changed.

The node refuses an input whose compiled code uses a capability its policy
does not list (`** refused: policy IO.Clock`). This counts capabilities the
input reaches through program and library code, not only the names it
uses: calling a program function that reads the clock needs `IO.Clock`.
The fragment carries its capability list, and the node checks it against the
signed request after loading the fragment, before running it.

**Your checkout must match the node's build** for the code an input reaches.
When a session starts, the shell compares a hash of every declaration in
your source with the node's and names the ones that differ. An input that
reaches one of them is refused, with the list:

```
error: this input reaches code that differs from the node's build:
  evens differs
```

Inputs that reach only unchanged code still run. A type whose constructors
are numbered differently on the node (reordered, added) is always refused,
since values built here would be read back wrongly there.

What happens when:

- **An input panics.** You see `** panic: <message>`; the node and the
  session carry on.
- **An input runs too long.** It is cancelled after `--timeout-ms` (default
  10 s, at most 30 s) and you see `** timeout`. A loop that never reaches a
  cancellation point is reported as still running on the node.
- **A deploy happens.** The session ends with "the node was redeployed".
  Bindings belong to the session, so they go with it.
- **Anything is sent.** Every input, accepted or not, is appended to the
  node's audit log with `"type":"shell"`, the signer and the source.

Under the hood `forge shell` runs `march --shell <reload socket>.shell
<entry>` with the project's `MARCH_LIB_PATH`, through an ssh tunnel for a
remote host. Running that directly works too.

## Interpreter vs compiled, and what is not there yet

### Interpreter differences

Under the interpreter there is no socket and no `forge` access; `Recon` and
`Diagnose` work, answered from the interpreter's actor table
(`lib/eval/eval_observe.ml`) with the same field names. By design:

- `node` is `"interpreter"`, and there is one scheduler.
- Delivery is eager, so mailboxes are usually 0 and `held` is always 0.
- Memory gauges (`rss_bytes`, `peak_rss_bytes`, `live_objects`) are `null`
  (`None` in `NodeStats`), so `rc.climb` never fires.
- There are no code epochs (always 1, no pins) and `idle_ms` is `null`.
- There is no crash ring: `CRASHES` lists the dead actors whose death was a
  crash, newest pid first.
- Actor type names are always present.
- A windowed `SCHED` or `TOP` is refused with `windowed_in_process`, as it is
  for any in-process caller on the compiled side (`Recon`'s windowed functions
  do not use them).

### What is not there yet

- **Actor type names without `--hot-reload`.** The `type` field is `null` in
  ordinary builds (`specs/todos/2026-10-02-observe-actor-type-names-without-hot-reload.md`).
  Register long-lived actors under names (`Actor.register`) so rows are
  recognisable.
- **The cluster section.** `SNAPSHOT` has no view of peers, so `diagnose`
  reports `cluster.suspect` as unavailable
  (`specs/todos/2026-10-02-observe-r1-cluster-section.md`).
- **Mailbox contents (`MESSAGES`).** The rest of the debug tier: the queued
  messages of an actor, most useful exactly when it is stuck and cannot render
  them itself (`specs/todos/2026-10-05-observe-messages-verb.md`).
- **The rest of the remote shell.** It works (see above), but:
  - a program-defined actor cannot be spawned from the shell;
  - it has not had its security review yet (plan R5).
- **A TUI (R7).** An interactive `forge observe` with `WATCH` and crash dumps;
  today `forge top` is the live view.
- **Tracing (R8).** Message and call tracing with mandatory limits.

The plan for all of these is `specs/plans/2026-09-28-observe-recon-shell-plan.md`.

See also: [Tooling](tooling.md), [Hot Code Reload](hot-code-reload.md),
[Supervision](supervision.md), [Topology](topology.md),
[Overload resilience](overload-resilience.md).
