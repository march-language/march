# Changelog

All notable changes to March are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow
[Semantic Versioning](https://semver.org/).

This file starts at the point March adopted a changelog (2026-07-21).
Implementer-level detail on every change (including everything that shipped
before this file existed) lives in `specs/progress/` and `specs/todos/`;
git log is authoritative for exact commits.

**Past releases.** Older releases live in one file each under [`changelog/`](changelog/):

- [0.4.0](changelog/0.4.0.md) - 2026-09-10
- [0.3.0](changelog/0.3.0.md) - 2026-08-23
- [0.2.0](changelog/0.2.0.md) - 2026-07-23
- [0.1.1](changelog/0.1.1.md) - 2026-07-21

## [Unreleased]

### Added
- **Every diagnostic has a code, and `march --explain <code>`.** Each error,
  warning and hint ends its first line with its code in brackets
  (``expected `Int` but got `String`. [type_mismatch]``), `--check-json` always
  carries it, and the LSP links codes to their page. `march --explain <code>`
  prints an explanation with a failing and a fixed program; the ten most common
  codes have pages so far (also on the site under `docs/errors/`).
- **`List.filter` keeps what its predicate says.** `sum_pos(List.filter(ys, fn y -> y > 0))`
  now proves a `List({Int | _ > 0})` demand, directly or through a `let`, and
  combines with the input's own element refinement. A predicate too weak for
  the demand is reported as `abstract-refinement-too-weak` (an error only under
  `cap verified`). This is the first *abstract refinement* (a refinement
  parameterised by a predicate), and user functions can declare one the same
  way; see "Abstract refinements" in the refinement types reference.
- **Cluster name registry tombstones expire.** An unregistered name used to leave a
  tombstone in every node's registry forever, so a long-running cluster's registry, and
  every anti-entropy round over it, grew with every name ever unregistered (two per
  finished session). A tombstone is now dropped 3 hours after it was first seen;
  `MARCH_REGISTRY_TOMBSTONE_GRACE_MS` or `tombstone_grace_ms` in `ClusterNode.config`
  changes that. Keep it well above the longest partition the cluster should heal from.
  Collection starts once every node in a cluster runs this version.
- **`march --debug-info`.** Compiled binaries carry function-level DWARF: every
  March function gets a `DISubprogram` at its defining line (lifted lambdas at
  the lambda's line, specialisations at the generic's), and the link gets `-g`,
  so `lldb`/`gdb` backtraces, ASan reports and `perf` profiles name March
  functions and files instead of `march_main + 1400`. The IR also carries a
  `!march.provenance` node per function recording where the compiler derived it
  from (monomorphisation, lambda lifting, fusion, specialisation). Off by
  default; the emitted code is unchanged when off. `--dump-provenance` prints
  the same table as text. Distinct from `--debug`, the interpreter's debugger.
- **A remote shell on a running node: `forge shell` and `forge rpc`.**
  Against a node built with `--hot-reload --signing-pubkey`, `forge shell`
  (or `march --shell <reload socket>.shell app.march`) typechecks the
  project once. It then compiles each input into a small signed library that
  the node loads and runs as a task. `forge rpc 'expr'` runs one input and
  exits 1 if it did not run. It prints the result
  and anything the input printed. `let` bindings persist across inputs; a
  trailing `limit: N` shortens long lists. Capabilities are pre-bound
  (`console`, `clock`, `intro`, `debug`), and the node allows only those in
  its `$MARCH_SHELL_POLICY` file. A panic or a timeout ends only that input,
  and a deploy ends the session. Every input is audited with its source.
  Inputs can call the program's own functions and its `MARCH_LIB_PATH`
  libraries, a Depot query for example. The policy does not yet see the
  capabilities an input reaches through that code, only the pre-bound ones
  it names.
- **Several native libraries per project.** forge.toml can declare `[[ffi]]`
  once per C library and `[[ffi.rust]]` once per Rust crate. forge compiles and
  links all of them, in order. A single `[ffi]` table works as before.

- **`--dump-impl-hashes`.** With `--emit-llvm` or `--compile`, writes
  `<file>.hashes` beside the output: one `symbol<TAB>impl_hash<TAB>sig_hash`
  line per post-TIR definition, sorted, straight from the CAS hashing that keys
  the compilation cache. `scripts/determinism-oracle.sh` compiles the IR-oracle
  corpus under a cold and a warm private `$HOME` from two cwds and fails on any
  difference in the IR or these hashes; CI runs it as the `determinism` job.
- **`--rc-trace`: leak reports that name the function.** A program built with
  `march --rc-trace` (or `MARCH_RC_TRACE=1`) tags every runtime call it makes
  with a site id, so the `MARCH_TRACE_GC=1` trace now records *who* allocated,
  retained and released each object; the new `scripts/gc-trace-report.py`
  folds the trace into per-object histories and prints every object still live
  at exit with its type, allocation site and each inc/dec as
  `<fn>#<ordinal>:<runtime callee>`, plus any count that went negative or was
  freed twice and a per-site summary. String allocations are traced too (they
  were not before), string-literal cells are reported as immortal rather than
  leaked, and `kill -USR2` flushes a live process's trace. Release builds are
  byte-identical with the switch off. `MARCH_SANITIZE=1` builds additionally
  abort on a `march_free` of a shared object and on a TRMC hole fill that finds
  its slot already written.
- **Native arrays may be sent in messages, captured by tasks and shared with
  parallel code.** `NativeIntArr`, `NativeFloatArr`, `NativeF32Arr`,
  `NativeI32Arr` and `NativeU8Arr` are copy-on-write values: a write to an
  array nobody else holds is in place, the first write to a shared array copies
  it (O(n), once), and each holder sees only its own writes. They were rejected
  in actor messages by analogy with `RingBuf`; the runtime never shared their
  mutations, so the rejection is gone. The typing corpus fixtures `t164`,
  `t165`, `t169`, `t170` flipped from reject to accept.
- **SWIM timings from the environment.** `ClusterNode.config` takes its SWIM
  probe period, ack timeout and suspect timeout defaults (1 s, 500 ms, 3 s) from
  `MARCH_SWIM_PERIOD_MS`, `MARCH_SWIM_ACK_MS` and `MARCH_SWIM_SUSPECT_MS` when
  set, so a slow or loaded host can stop taking healthy peers for dead without
  a rebuild. A record update of the config still wins.
- **Signed debug requests on the observe socket.** `forge observe --state PID`
  returns a running actor's state (what `Actor.inspect_state` returns inside
  the program), and `forge observe --crashes-full` returns recent crashes with
  their panic messages. A node answers only if it was built with
  `--hot-reload --signing-pubkey`, the request is signed by that deploy key,
  and its `$MARCH_DEBUG_POLICY` file lists the verb (no file: nothing is
  allowed). Each request carries a nonce and a 30 s expiry, so a captured
  request cannot be replayed, and every attempt is written to the audit log.
- **A multi-host lab, and `examples/lab_app`.** `scripts/lab/run.sh` starts four
  Debian containers on a private Docker network, deploys `examples/lab_app` (a
  three-role choreography with a loop, a choice, an actor-hosted role placed
  `count = 1`, role grants and a `[control]` section) to them with the real `forge`
  over ssh, and checks hot deploys, restarts on persisted patches and failover, with
  sessions flowing throughout. It runs on demand, not in CI; see the Multi-host Lab
  docs page. Its first runs filed nine bugs under `specs/todos/2026-10-0[45]-lab-*`,
  among them a pushed topology closing the control plane's leader role on every node.
- **`Actor.inspect_state`: read a running actor's state.** The `sys:get_state`
  equivalent. `Actor.inspect_state(Actor.debug(io), pid, timeout_ms)` returns
  the actor's state fields as `{ count: 3, tags: [a, b], best: Some(3) }`,
  each field printed by its own `Show` (a field holding functions prints
  `<opaque>`), in declaration order, the same on the compiled and
  interpreted backends. The request skips the actor's mailbox
  limit, so a full mailbox still answers. It fails cleanly
  (`InspectTimeout`, `InspectDead`, `InspectSelf`, `InspectFailed(why)`) when
  the actor is busy inside a nested `receive`, gone, the caller itself, or a
  field's `Show` panics; the actor keeps running in every case. It needs the
  new `Cap(Actor.Debug)`, minted from `Cap(IO)` by `Actor.debug`.
- **`forge top`, `forge diagnose` and `forge status`.** `forge top` watches a
  node's busiest actors (by mailbox depth, crashes, or message and dispatch
  rate) refreshed in place. `forge diagnose` checks a node over a window for
  growing mailboxes, actors dropping at their limit, saturated or imbalanced
  schedulers, crash loops, a heap climbing with no new actors and stuck
  hot-reload epochs, and exits 0, 1, 2 or 3 (nothing, warnings, critical,
  unreachable). `forge status` adds each node's actors, queued messages,
  memory, load, recent crashes and deepest mailbox to the topology report.
  The same findings are in the stdlib as `Diagnose`, so a program can check
  itself, and remote sends now count in an actor's sent messages.
- **`Recon`: a program's view of itself.** The new stdlib module answers, from
  March code, the questions `forge observe` asks a node: `Recon.info` (one
  actor's mailbox, counters, supervisor and names), `actors`, `proc_count`
  and `proc_window` (the actors highest on mailbox depth, crashes or message
  rate), `tree`, `node_stats`, `crashes` (kind, actor and restart number,
  never the panic text), `epochs` and `scheduler_usage`. Every function takes
  a `Cap(Actor.Introspect)`, and they work interpreted as well as compiled.
- **`--dump-phases`/`MARCH_DUMP_TXT` now include a `tir-trmc` stage.** The
  TIR is snapshotted right after `Trmc.transform_module`, before the first
  existing checkpoint (`tir-mono`), so the tail-recursion-modulo-cons rewrite
  can be read on its own instead of only through the mono stage that follows it.
- **A read-only observe socket on every compiled program.** Set
  `MARCH_OBSERVE_SOCKET=<path>` (or just `MARCH_HOT_RELOAD_SOCKET`, which puts it
  at `<path>.observe`) and the program answers one-line requests with one line of
  JSON. It serves `HELP` and `PING` today and is the base the coming
  `forge observe`, `forge top` and `forge diagnose` build on. It is separate from
  the hot-reload socket, so an observer can never block a deploy; the socket is
  owner-only and holds at most eight clients at once.
- **`forge observe` and the observe socket's snapshot verbs.** A running program now
  answers `ACTORS [mbox|status|epoch|pid] [n]` (every live actor with its mailbox
  depth, status, scheduler, code epoch, supervisor and registered names), `ACTOR <pid>`
  (one actor, its children and supervisor settings, or how a dead one died: the
  kind only, never the panic text), `TREE` (the supervision tree plus the
  unsupervised actors), `NAMES`, `SCHED`, `MEM`, `EPOCHS` and `SNAPSHOT` (several of
  them from one consistent walk). `forge observe [REQUEST] [--section S] [--json]`
  asks the forge.toml hosts over ssh, or a local socket with `--socket`. Reading
  100 000 actors takes about 20 ms, and nothing is added to the scheduler's hot path.
  Actor type names need a `--hot-reload` build.
- **Observe counters, scheduler utilisation and a crash ring.** Every actor row
  now carries how often it ran, messages received and sent, how long since it
  last ran, and the messages an `Actor.call` is holding while it waits (an
  actor stuck in a call no longer looks idle). `SCHED [window_ms]` reports
  each scheduler's utilisation, `CRASHES [n]` the last crashes (kind, actor,
  supervisor, restart number; never the panic text), and `TOP <attr> <n>
  [window_ms]` the actors highest on mailbox depth, crashes, or messages and
  dispatches over a window. `TREE` nests actors under the actor that spawned
  them. The counters add nothing measurable to the message path.
- **An in-cluster control plane for hot deploys (distributed deploys, step 12a).** A
  `[control] candidates = "<host label>"` section in `topology.toml` makes every node run
  an Agent and the labelled nodes serve a control API; one of them leads (`count = 1`
  placement). A release, built and signed by forge (it holds the only key), is stored on
  every reachable candidate, then carried out step by step with canary gates; nodes
  verify every signed line themselves, so a compromised control node can delay a deploy
  but not forge one. No ssh is involved in a hot deploy. A leader killed mid-rollout is
  replaced and the release finishes without applying a step twice. Leadership needs
  `Ctl.Control:offer` in the node's certificate. Restart-class changes still go through
  the process backend.
- **`forge deploy` goes through the control plane when the topology has a `[control]`
  section.** It builds and classifies as before, writes the hot pools and the topology
  push into one release signed with your deploy key, uploads the patches to the
  candidates, sends the release and follows it step by step until it completes or halts,
  printing the leader's reason when it halts. Nothing reaches a node by ssh for a hot
  change; restart-class steps still run over ssh, in plan order, and `--plan` lists them
  ("NEEDS SSH") and prints the release it would sign. `--via ssh` is the break-glass path,
  `--status` shows the leader's view of the newest release, and `--audit [N]` shows the
  leader's audit log: every release offered (accepted, or refused at the compare-and-set
  and why), every step ordered and its answer, and each release's end, as JSON lines kept
  on every candidate. `forge test --upgrade-from` deploys through the control plane too
  when the topology has one, and `forge run --processes` gives each local process its own
  control directory and control port. See "Through the in-cluster control plane" in
  docs/hot-code-reload.md.
- **Node certificates and revocations delivered by the control plane (distributed
  deploys, step 12b).** `forge cluster cert <node> --node-key <key> --deliver <host:port>`
  renews a running node's certificate through the control plane: no file to copy, no
  restart. The node takes it live, its links and sessions stay up, and it saves the
  certificate for its next start. `forge cluster revoke ... --deliver` reaches every node,
  and each drops the revoked node's links. A node checks both the deploy key's signature
  on the release and the operator's on the certificate or token, and refuses a certificate
  naming another node. Issuance stays with the operator; the control plane holds no
  operator key.
- **Native builds allocate from a vendored mimalloc.** `march_alloc`, the allocator
  behind every March value, now draws from a statically linked mimalloc instead of
  libc `calloc`, with no new system dependency. Allocation-heavy programs get
  faster: `binary_trees` 233 to 165 ms (-29%) and `list_ops` 76 to 62 ms (-18%),
  with `tree_transform` about 3% faster. The cost is a larger resident set (7 MB to
  14 MB on `binary_trees`). Set `MARCH_MALLOC=libc` when compiling to get the old
  allocator; `MARCH_SANITIZE` builds, hot-reload patches and the REPL always use libc.
- **`Array.sort_by`, `Array.sort_by_key`, `RRB.sort_by` and `RRB.sort_by_key`.**
  Stable sorts for the persistent vectors: `sort_by` takes the same comparator
  as `List.sort_by` (`fn (a, b) -> a <= b`), and `sort_by_key` takes a function
  returning an `Int` key, which it calls once per element. Elements that compare
  equal keep their order. Sorting 100,000 pairs takes about 50 ms with `sort_by`
  and 23 ms with `sort_by_key`, against 250 ms for converting to a list, calling
  `List.sort_by` and converting back. They work compiled, interpreted and on the
  JavaScript target.
- **`--target-cpu <cpu>` for compiled builds.** Passes `-march=<cpu>` (x86_64) or
  `-mcpu=<cpu>` (arm64) to the C compiler, e.g. `--target-cpu native` to use the host's
  full SIMD width. The default is unchanged (`-msse4.2` on x86_64) and the CPU is part of
  the build-cache key, so a baseline binary never satisfies a `--target-cpu` build.
- **`forge add` checks a new dependency's capabilities before keeping it.** When
  the project has a `forge.caps.lock` (from `forge audit --record`), a
  dependency the add brings in or changes that asks for a capability it was not
  granted is refused: the delta is shown and `forge.toml` and `forge.lock` are
  left as they were. `--accept-caps` keeps it and records the new set. Only the
  dependencies the add touched are analyzed. `forge outdated` now shows, under
  each outdated registry dependency, whether the newer release asks for new
  capabilities. `forge.caps.lock` records which mode (`declared`/`inferred`)
  produced it.
- **A cluster node's certificate can be replaced while it runs.** In
  certificate mode, a renewed certificate used to need a restart. Now the node
  watches the files `MARCH_NODE_CERT` and `MARCH_NODE_KEY` name
  (`MARCH_NODE_CERT_POLL_MS`, default 10 s) and takes a new certificate when
  one appears, or code can call `ClusterNode.replace_cert(node, cert_text,
  key_hex)`. The new certificate must verify under the operator key, name the
  node and its key, and not be revoked. Existing links are not reconnected:
  each peer is sent the new certificate over the link with a proof that the
  node holds its key, so sessions keep running past the old certificate's
  expiry. A new key works the same way. `on_security_event` reports each
  replacement as `CertReplaced` or `CertRefused` (two new `SecurityEvent`
  constructors: a `match` that named every constructor needs a new arm).

### Changed
- **`RingBuf` is linear: every operation consumes the buffer and hands it
  back.** `push` and `clear` return the buffer; `pop`, `get`, `peek_oldest`,
  `peek_newest`, `size`, `cap`, `is_empty` and `is_full` return their answer
  beside it (`let (n, rb) = RingBuf.size(rb)`); new `snapshot` reads the
  elements out and keeps the buffer; `to_list` and new `drop` end it. A buffer
  can no longer be aliased, captured by a closure, stored at module level or
  put in a `Vault` (each is a compile-time error, the existing linear-type
  errors), and it may now be *sent* in a message or passed to `spawn`, which
  moves it. In actor state write `{ state with buf: RingBuf.push(state.buf,
  x) }`. Migration table: design spec section 5. **New rule for every linear
  type:** a module-level `let` of a `RingBuf`, `Handle` or `LinearMap` is
  rejected, since a module-level value can never be consumed exactly once.
- **Builds against OCaml 5.5.1 (was 5.3.0).** CI, the CI Docker images and the
  install docs now use OCaml 5.5.1; the minimum stays `ocaml >= 5.3.0`, and the
  source needed no changes. The REPL's `notty` dependency (0.2.3 does not
  compile on OCaml 5.4+) is now vendored from the community fork under
  `vendor/notty/` until a fixed release is on opam, and the `js_of_ocaml < 6.4.0`
  cap is lifted (6.4.1 compiles the browser bundle). Compiler speed is unchanged
  within noise.
- **Faster `--compile` once whole-program optimisation is done.** Two lookups
  that scanned every definition in the program (stdlib included) for each name
  reference, one in the CAS dependency hashing and one in the allocation-contract
  checks, now use a hash table or compute the name once. On
  `examples/topology_app` at `--opt 2` that took ~7 s of CPU off every compile
  that gets past optimisation: a comment-only edit (a cached-binary hit) went
  from 11.2 s to 4.3 s and a one-function edit from 26.0 s to 18.4 s. Cache
  keys are unchanged, so existing caches stay valid. `--timings` now reports
  the two phases as `alloc-contract` and `cas-hash`.
- **Parse errors are now emitted by `--check-json`.** A file that does not
  parse used to produce an empty NDJSON stream (the error went to stderr
  only); it now produces one line per syntax error, with `code` set to
  `parse_error`, `syntax_error` or `lex_error`. Every `--check-json` line also
  gains `labels` (the secondary source spans, each with its message) and
  `notes`. Existing fields are unchanged and `forge fix` ignores the new ones.
- **A call to an unknown function is now a compile error, not a link error.**
  When native code generation met a direct call to a name that is neither a
  function in the program, an extern, nor a runtime builtin, it used to emit a
  forward `declare` and leave the failure to the linker (or link the call to an
  unrelated C symbol of the same name). It now stops with
  ``error: `foo` (called from `bar`) is not a function in scope and not a
  runtime builtin`` and exits 1.
- **Chained `NativeArray` maps compile to one loop.** With the optimizer on,
  `map_*(map_*(a, f), g)`, a `map2_*` with a mapped input on either side, and a
  `map_*` of a `map2_*` are rewritten into a single call whose callback is the
  two lambda bodies composed, so no intermediate array is allocated or walked
  (4M elements: Int 3-deep map chain 5.2 → 1.0 ms, Float 4.8 → 0.6 ms, map
  feeding map2 3.0 → 0.8 ms). It applies when every callback is a lambda
  written at the call, its body has no effects (and no division, which can
  trap), the intermediate is used only once, and nothing observable runs
  between the two calls; int, float, i32 and u8 arrays, not f32. Results are
  unchanged. `MARCH_NO_NATIVEARR_FUSION=1` turns it off.
- **Compiled `Int` arithmetic normalises to 63 bits lazily, not after every
  operation.** `+ - *`, negation and `int_shl` leave their result in the full
  64-bit register and the reduction modulo 2^63 happens where the value is
  observed (a comparison, a call into the runtime, a store, printing, ...).
  Every program prints what it printed before — the parity suite against the
  interpreter is the gate — but the shift pair the previous scheme put between
  `fib(n-1) + fib(n-2)` and `ret` is gone, so LLVM's accumulator
  tail-recursion elimination fires again: `bench/fib.march` is ~17% faster
  compiled (same-box A/B), and arithmetic that feeds a list cell or record field
  no longer pays a shift pair on the way in.
- **Heap objects are no longer zero-filled on allocation.** `march_alloc`, the
  allocator behind every constructor, closure, tuple and record in compiled
  code, is now a plain `malloc` (or `mi_malloc`) instead of a `calloc`. The
  2026-08-04 x86/glibc ablation put the zeroing at about 11% of
  `binary_trees`; on Apple Silicon it measures flat with either allocator, so
  treat this as a contract simplification rather than a speed-up until it is
  re-measured on x86. Every runtime and codegen allocation site was audited to
  write all of its fields before the object can be read, and the four that
  leaned on the zeroing (the TRMC hole slot, `Task.spawn`'s result words, a
  native-array header word, a ring-buffer cell's type id) now store their zeros
  explicitly. No source-level change.

### Fixed
- **`Map.fold` with a closure that captures a value no longer leaks the closure.** Every
  such fold leaked one closure, and so did a closure that tail-called another closure it
  had captured after dropping an argument of its own. Cluster nodes did both on every
  session.

- **A missing `end` is reported at the construct that is missing it.** Instead of
  "Parse error in declaration" at the end of the file or the next `fn`, the error
  points at the `if`/`fn`/`match`/`mod` that was never closed. It says where the
  parser noticed, and it carries a fix that inserts the `end`, which `forge fix`
  can apply. An `else if` chain one `end` short gets a note explaining that each
  `if` closes separately.
- **A program no longer hangs on exit after `ClusterNode.stop` while one of its sessions
  is finishing.** Stopping the node ended its connection to itself without telling the
  sessions using it, so a session whose last messages were still in flight could wait
  for them forever and keep the process alive.

- Compiled programs no longer risk a use-after-free when two scheduler threads
  touch records of a not-yet-seen shape at the same time. Registering a new
  record shape could free the shape table while another thread was reading a
  field through it (seen as an ASAN heap-use-after-free in a cluster node's
  state drop).
- A comment-only edit is a compile-cache hit again. Since the `--rc-trace` change, a
  `--compile` whose typed IR was unchanged printed `compiled out (cached)` and then
  emitted LLVM IR, ran clang and printed `compiled out` anyway, so the hit saved
  nothing; it now stops at the cache lookup.
- **`typed_array_*` functions no longer leak their argument.** In compiled
  code, each call to `typed_array_from_list`, `typed_array_length`,
  `typed_array_get`, `typed_array_map` and the rest of the family leaked the
  array or list it was given. `DataFrame` columns are built on these.

- A green thread started from a runtime thread that is not a scheduler (the
  hot-reload server's drain, the new shell listener) no longer inherits that
  thread's blocked signals. With SIGSEGV blocked, the first time its stack
  had to grow killed the whole process silently on Linux.
- A call of another module's function with too few arguments
  (`List.map([1, 2])`) is now a type error. It used to typecheck, then fail
  at run time: an `arity mismatch` panic interpreted, a crash compiled, and a
  crash of the whole REPL session.
- **A callback contract that names its argument now works.** With
  `keep : ({x : Int | true}) -> {Bool | _ == (x > 0)}`, a guard `if keep(h)`
  establishes `h > 0`, and `let b = keep(h)` binds `b == (h > 0)`; both used
  to establish nothing. Passing a named function whose proved return matches
  (`is_pos(n) : {Bool | _ == (n > 0)}`) was wrongly REJECTED with a bogus
  witness (`n = 0, x = 1`) and now compiles; a matching lambda (`fn y -> y > 0`)
  is now proved rather than skipped. A callback that defines an abstract
  refinement (`_ == p(x)`) is no longer a skip, or a `cap verified` error, at
  every call.
- **A hot deploy over the reload socket no longer drops its connection while
  the control plane's Agent polls the node.** The socket server read a
  request line from the Agent's in-process request instead of the socket
  whenever the two overlapped, then closed the deploy's connection mid-batch
  (`hcr_deploy: connection closed` / `Connection reset by peer`, the node
  itself unharmed). It hit roughly one deploy session in ten on a node that
  runs the control plane.
- **`let b = a` keeps `a`'s refinement facts when `a` is an `Int`.** A plain
  variable alias used to drop every fact about its value (`let b = a + 0`
  kept them), so `take_pos(b)` was skipped even when `a` was a refined
  parameter or a positive literal. It is now proved, and a violating value is
  reported through the alias. Non-`Int` aliases still carry nothing.
- **Tuples can be compared with `==` and `!=`.** `(1, ["x"]) == (1, ["x"])`
  used to be rejected with "does not implement interface `Eq`". A tuple is now
  `Eq` when every component is. Compiled code also compared a tuple's Float
  component by address instead of by value, so `(1, 2.5) == (1, 2.5)` was
  false in compiled code (for example inside `List.member`). Tuples are still
  not ordered with `<`.
- **A nested type named like a runtime type no longer crashes when it is matched.** A
  module-local `type Down = Down(Int)` (or another name the runtime reserves) was built
  one way and read another in compiled code, a segfault on the first `match`.

- **No false refinement error for a lambda that uses a local.** A lambda passed
  where a refined return is expected (`ap(fn y -> h(y), 1)` with
  `f : (Int) -> {Int | _ > 0}`) that called or read a parameter or `let` of the
  enclosing function could be reported as a definite violation, with a
  counterexample computed from a module-level function of the same name. Such a
  lambda is now left unchecked (a recorded skip), as intended.
- A `--hot-reload` build no longer leaks a small object each time it calls a
  lambda that captures nothing (`List.map(xs, fn x -> x + 1)`, `to_string` of
  a list, `Actor.inspect_state` of an actor with a list field). Ordinary
  builds were not affected.
- **NativeArray operations no longer leak the array they read.** In compiled
  code, `map`, `map2`, `fold`, `from_list`, the width conversions and the
  DataFrame column reductions kept a reference to their input that nothing
  released, so a chain like `map(map(a, f), g)` leaked its whole intermediate
  array on every call, and `from_list` leaked its list. A `map` or `map2` over
  Float or f32 arrays whose callback could not be inlined also leaked two
  Float boxes per element, and `DataFrame.filter` leaked each column it
  filtered.
- **The language server resolves dependencies the way `forge build` does.**
  It used to put every cached version of a git dependency on its search path,
  including each version's `test/` and `priv/` files, and it missed registry
  and transitive dependencies. Editors then showed errors from files the build
  never reads. It now uses the version `forge.lock` names, and only that
  version's `lib/`.

- **A value matched by `_` inside a tuple or constructor pattern is now fully freed.** In
  `match pop(q) do (None, _) -> ...`, the value the `_` stood for was freed without its
  contents, so a dropped `Deque` leaked both of its lists. This also cost a cluster node a
  few objects for each frame it queued.

- **A dead actor's memory is released.** An actor that was killed or stopped kept its
  state (lists, maps, strings, closures) allocated for the rest of the program, and an
  actor that had ever been the target of `Actor.call` was never freed at all, because
  each call leaked a reference to it.

- **A cluster session no longer leaves its party behind.** Each finished session leaked the
  party record, the session capability's closures and the handles of thirteen session
  tables. Every session operation (send, receive, register, close) also leaked a
  reference. A session now leaves about 90 objects behind instead of about 160.

- **A program that declares a type with a stdlib type's name (`Value`, `State`, `Event`,
  `Error`, ...) no longer crashes when compiled.** Dropping a value of the stdlib type
  (a `Msgpack.Value`, say) segfaulted, because the drop only knew the program's own type.

- **Reading a record field whose type is never pinned down (`record_get(r, "y")` printed
  or shown) no longer double-frees or leaks in compiled code.** The result was released
  once too often, a use-after-free that only showed under ASAN. Showing it leaked one
  string per call.

- **Every in-place write now synchronises with the reference it reuses.** The
  sole-ownership test behind FBIP reuse, `NativeArray.set`/`sort` and the SIMD
  store read the reference count with a relaxed load, so a cell another thread
  had just released could be mutated in place without ordering against that
  thread's last reads (a C11 data race, harmless on x86 in practice). The test
  is an acquire load now, in the C runtime (`march_rc_is_unique`) and in
  emitted code; free on x86-64, one `ldar` on arm64.
- **A dead linear value's resource destructor runs.** Freeing a dead linear
  binding bypassed the reference-count path and so skipped the destructor a
  resource cell (a `RingBuf`, an FFI resource) carries, leaking its native
  store and elements. `march_free` runs it now, as `march_decrc` always did.
- **Compiled code no longer leaks records whose ownership differs between branches.**
  A record released on one path of a `match` or `if` was leaked on the others. A record
  passed to a function and then updated (`{ st with .. }`) was never released at all. A
  record type named without its module inside another type was freed without its fields.
  Cluster nodes hit all three on every session (registry entries, the node's whole old
  state).
- **`Crypto.sha256`, `sha512`, `md5`, the HMAC, signing and base64 builtins no longer leak
  their argument.** Compiled code leaked every string or `Bytes` it hashed or encoded. The
  cluster registry rehashes its Merkle tree on every update, so a node leaked one string
  per registry entry per update. With these fixes a cluster session leaves about 160
  objects behind instead of about 730.
- **A locally bound generic lambda no longer leaks memory when it returns a
  Float.** `let keep = fn (p, x) -> p` called directly with Float arguments,
  as in `keep(1.0, x)`, leaked one boxed Float per call in compiled code. The
  interpreter was unaffected.

- **`char_to_int`, `char_is_digit`, `char_is_alphanumeric` and `char_is_whitespace` no
  longer leak their argument.** Compiled code leaked the one-character string on every call.
  `Msgpack` calls `char_to_int` for each byte of every string it encodes, so every cluster
  frame leaked one object per byte of its strings.

- **A closure that is dropped without being called now frees what it captured.** Before,
  only calling a closure released its captured values; one dropped from a list, record or
  table, or never applied, leaked all of them. Cluster nodes hit this on every session and
  every registry update: a single-node session left about 4,400 objects behind, now about
  1,400.

- **Derived implementations (`derive Eq`, `Ord`, `Json`, ...) are no longer typechecked with
  another program's types.** Their generated code got placeholder source positions from a
  counter that restarted in every compiler process, and the stdlib's cached, already
  desugared code carried the positions of the process that wrote the cache. A later build
  of a different program could reuse the same positions and lower a derived function with
  unrelated types. It surfaced as `forge deploy` reporting every derived `Eq` changed
  after an unrelated protocol edit.

- **A restarted cluster node's offers are visible again.** After a rolling restart, a node
  that registered its access points anew could have them erased on every node: its peers
  still held the bindings from its previous run under a newer clock, and retiring those
  stale bindings removed the live ones too. Initiators were then refused with "no access
  point is registered" until every node was restarted at once.

- **Dropping a value of a stdlib type that shares its short name with another (`Value`,
  `State`, `Level`, `Event`, `Error`, `Mode`) now frees what it holds.** Such a value was freed
  shallowly, so its contents leaked: a decoded `Msgpack.Bin` lost its whole byte list. Every
  cluster message is decoded that way, so a node leaked roughly one object per byte of
  every message it received. In the multi-host lab, nodes grew by hundreds of thousands
  of objects per session and were killed for running out of memory within minutes.

- **A protocol branch named `none`, `some`, `ok`, `err`, `nil` or `cons` no longer breaks the
  build.** Such a label gives the protocol's message type a constructor of the same name,
  and the code `@[endpoints]`, `derive` and the control plane's `[control]` wiring generate
  used the prelude's `Some`, `None`, `Ok`, `Err`, `Nil` and `Cons` unqualified, so they
  became ambiguous: up to 49 errors, each blaming the compiler. Generated code now names
  them `Option.None`, `Result.Ok`, `List.Cons` and so on.

- **A pushed topology no longer takes away the control plane's leader.** Re-reading a
  topology (a signed push from `forge deploy` or `forge topology apply`, SIGHUP, or a restart)
  closed the control plane's own `Ctl.Control` role on every node, because the topology file
  cannot name it, so a cluster with `[control]` had no leader after its first deploy and
  every later cluster deploy, `forge cluster cert --deliver` and `revoke --deliver` had
  nothing to talk to. Roles the build places itself are now pinned, and a re-read leaves
  them alone.

- **Parse errors on the command line now point at the token the message is
  about, not the token after it.** `if x then 1 end` used to put the caret
  under `end` (or under the next line) while the message talked about `then`;
  `march`, `march fmt`, `march test` and the REPL now underline `then`, the
  position the editor integration already showed.
- **A stray character or an unterminated string is now an ordinary error.**
  `march`, `march test` and `march fmt` used to die with `Fatal error:
  exception Lexer_error(...)` and an OCaml backtrace on a character the
  lexer rejects or a string that never closes; they now print the error with
  its source line and exit 1, like any other syntax error. A file on
  `MARCH_LIB_PATH` with such an error no longer aborts the whole compile.
- **A cold `$HOME` stdlib cache no longer compiles differently from a warm one.** The first
  compile after a cold cache used the live stdlib type environment, whose type variables the program
  could link, so it produced different IR (an extra specialised clone, shifted lambda ids) and a
  different compilation-cache key than every later compile of the same source.
- `forge top -n` and `forge observe -n` also accept `--count`; `--n` was
  documented but never parsed.
- **Compiling a file with no `main` no longer emits the whole standard
  library.** A module with no `main`, tests or exports (a library file, or a
  topology app compiled without its `--topology` digest) kept all ~8,000
  stdlib functions, so a one-line file took minutes in `llvm-emit` and `clang`
  and wrote 45 MB of IR. It now compiles the functions the file declares and
  what they reach: a topology app's IR went from 47 MB to 8 MB. Shared-object,
  hot-reload, JS and WASM-island builds are unchanged.
- **A record field read on a value the compiler typed as a scalar now stops
  with an internal error naming it,** instead of writing LLVM IR that clang
  rejects (`'%w63…' defined with type 'i64' but expected 'ptr'`).
- **Security: a node can no longer be rolled back to an older certificate, and a
  recorded certificate update cannot be replayed (step-12 security review).**
  A node now refuses a replacement certificate issued before the one it holds.
  `forge cluster cert` serials now start with the issue time in unix
  milliseconds (`<ms>-<random>`); the signed certificate format is unchanged.
  The control plane's Agent also keeps its certificate-release floor on disk
  (`$MARCH_CONTROL_DIR/cert-floor-<node>`). Before, a restart lost the floor, and
  a compromised leader could replay an older, genuinely signed cert release to
  restore removed roles or flags. A `CERT_UPDATE` (live certificate
  replacement on a link) is now signed over that link's handshake transcript
  and a per-link counter. Before, an update recorded off the wire could be
  replayed on a link made with a leaked old key, and that link then survived
  the old certificate's revocation. The frame format changed: a peer from
  before this change refuses the new update (and is refused by it), then
  redials under the new certificate when the old one expires, as a peer from
  before live replacement does.
- **A session no longer fails to form when its access point is replaced mid-invitation.**
  When a hosting actor re-offered a role (for example after a hot deploy moved it
  to a new protocol version) and closed the old offer, an initiator that had
  just invited the old offer waited out the whole setup time (20 s) and then
  failed with `NoOffer(.., "<node> did not answer")`: the invitation reached a
  node whose offer had already dropped its route, so no one answered it.
  `SessionNode.initiate` now notices the offer's name was unregistered, withdraws
  the invitation, and looks again for the replacement offer, as it already did
  for an offer that refused with "closing".
- **Vault writes release what they replace, and session tables are freed.**
  Overwriting or dropping a Vault entry released only the old value's own cell,
  never its fields or list spine, so `Vault.set` of a record in a loop grew
  without bound (100,000 overwrites of a 50-string record: 576 MB). Writes now
  hand the displaced value back to the typed wrapper, which drops it at its
  type; a Vault(Float) write no longer leaks a box either. New `Vault.close(t)`
  unregisters, empties and frees a table (a handle used afterwards sees an empty
  table), and `Vault.live_tables()` counts the tables a process holds. Every
  `SessionNode` session closes its 13 tables when it ends, by any path, and
  `Session.in_process()` gained `close`; before, each session kept about 300 KB
  of tables for the life of the process.
- **A compiled program that calls `Process.set_env` at the top of `main` no
  longer crashes, now and then, at startup.** On Linux the runtime read
  the environment from the main thread while `main` was already running on a
  worker, and `setenv` freed the array it was reading, so the program died with
  `fatal SIGSEGV ... sched=-1` in `getenv`. The runtime now reads those settings
  before `main` can start.
- **Security: a signed hot deploy now runs only the bytes the operator signed.**
  A signed `ACTIVATE` named its artifact by the compiler's compilation hash, and
  nothing checked the bytes stored under it, so anyone who could write a node's
  artifact store (`CAS_PUT` over the reload socket or the unauthenticated control
  API) could make an operator's genuine deploy, or a restart's replay, load their
  own code. forge now sends `ACTIVATE7`, which signs the BLAKE3 of the patch's bytes.
  The node checks it on a private copy before loading anything; other bytes get
  `ERR artifact_digest` and none of their code runs. `CAS_CHECK` and `CAS_PUT` take
  the digest too, so forge uploads a substituted artifact again and the node refuses
  a corrupt upload. Once a node holds a release (or under
  `MARCH_HCR_REQUIRE_RELEASE=1`) it refuses the older verbs, which sign no digest
  (`ERR artifact_digest_required`), and does not replay them after a restart: such
  a function comes back on the base build until the next deploy. Deploying to a
  server that predates `ACTIVATE7` now fails with "upgrade the server binary".
- **Security: the hot-reload socket is owner-only whatever the umask.** It was
  created with the inherited umask's mode, so a node started under `umask 000`
  let any local user connect. It is now `0600`, and a peer running as another
  user (other than root) is disconnected.
- **Topology now reports two roles that share one endpoint on a node.** Two roles
  placed on one node that serve the same protocol role through the same offer
  function want the same endpoint name, so the second could never be offered;
  Topology retried it every placement tick without a word, and the role was
  simply missing from `Topology.offered`. The conflict is now reported once
  (naming the role holding the name), written to the node status file as a
  `conflict <role> held-by <role>` line, and retried with backoff (or as soon as
  the node's offers change) rather than every tick; the role is offered, with a
  report, once the holder's offer closes. A refusal just after an offer on the
  node closed (its name is still being released) is still retried quietly.
- **Security: the control plane's TCP API no longer takes writes from anyone who can
  reach it.** Any peer could append forged lines to a candidate's audit log
  (`AUDIT_COPY`) and fill its disk with artifacts under made-up hashes (`CAS_PUT`, 64 MiB
  a call, never removed). Now the candidates' own copies (`AUDIT_COPY`, `RELEASE_COPY`)
  need the cluster's handshake (the cluster secret, or a certificate carrying
  `Ctl.Control:offer`); `CAS_PUT` takes only a hash that a release signed by your deploy
  key, `STAGE`d on the same connection, names; uploads no stored release adopts are
  capped (`MARCH_CONTROL_CAS_PENDING_MAX_BYTES`) and removed after a grace period; the
  audit log rotates past `MARCH_CONTROL_AUDIT_MAX_BYTES`; and a candidate serves at most
  `MARCH_CONTROL_MAX_CONNS` connections, closing idle ones. Reads stay open. forge
  stages its uploads itself. Candidates must be upgraded together: an older one's copies
  are refused. See "Who may write to the control API" in the hot-reload guide.
- **`MARCH_NO_UNBOX=1` is now part of the compilation cache key.** It classifies
  every type Boxed and so changes the emitted code, but was not in the CAS key,
  so an A/B run reused whichever variant was cached first. It now adds a
  `nounbox` tag, as `MARCH_NO_INLINE_RC` and `MARCH_NO_HOF_SPEC` already did.
- **A branch that returns a record's field no longer frees it (compiled).** In
  `"sig " ++ (if r.signature == "" do "-" else r.signature end)`, compiled code
  handed out `r.signature` without taking a reference, so the next read of the
  field found freed memory (`sig -` on the second call, a use-after-free under
  ASAN). This was `Control.serialize`'s bug. The same shape, and the plain
  `if r.f == "" do "-" else r.f end`, also leaked the record on every call that
  took the second branch.
- **The control plane's leader no longer crashes when its wiring has a type error.**
  Type errors in the generated control-plane wiring were silently dropped, so
  ill-typed wiring compiled into code that read records with the wrong layout
  (both leader candidates died with SIGSEGV). They are now reported. The two
  that were live on the certificate-save error path are fixed.
- **An `@[endpoints]` protocol now works in any module.** A protocol declared in a
  nested module, in a library module found through `MARCH_LIB_PATH`, or in a
  standard-library module failed with "Unknown module `P_A`"; only one at the entry
  file's top level worked. The generated modules are now addressable by their
  qualified name (`Net.Fan_C.register(s, 0)`) from anywhere. Underneath, a qualified
  type written relative to an enclosing module (`A.T` inside `mod Outer` naming its
  sibling `Outer.A`) now resolves, and a protocol in the standard library no longer
  makes a program's own bare `from_json` call ambiguous when compiled.
- **A hot patch of a topology role body is no longer refused by the node's
  capability policy.** A role body holds the session it is handed, so its own
  caps include `Session.Live`, and a node running the policy `forge host init`
  writes refused every such patch with `ERR cap_policy Session.Live` unless you
  wrote `Session.Live` into the pool's `caps`. The node's admission gate now
  polices IO capabilities only: a proof capability (`Session.Live`,
  `ClusterNode.Live`, your own `proof cap`) carries no IO authority and is not
  checked against `MARCH_DEPLOY_POLICY`; an IO capability outside the policy is
  refused as before. And in a topology with a `[control]` section, every hot patch
  was refused with `ERR role_cap_policy Ctl.Agent ...`, because the policy
  bounded the control plane's own roles: the generated policy now ends with a
  `serves` line, and the gate bounds only the closures of the roles the node's
  pool serves. Re-run `forge host init` (or deploy a restart) to rewrite an
  existing policy; one without a `serves` line still bounds every role. Both
  `forge deploy hot` and releases through the control plane go through the same
  gate.
- **Topology firewalls no longer split the cluster membership.** `forge topology gen
  ufw` / `do-firewall` and `forge host init` opened the cluster port into a pool only
  from the pools it exchanges protocol messages with, but SWIM probes every member, so
  two pools that shared no protocol saw each other as unreachable (and `count = n`
  placement ranked on that wrong membership). The cluster port is now open between all
  cluster members; pools are kept apart by node certificate, as before. Public ports and
  the control-port rule are unchanged.
- **A supervisor now works in a program built with `--hot-reload`.** Any actor with a
  `supervise` block failed to compile under `--hot-reload` (`use of undefined value
  '@$sup_child_ptr_a'`). Behind that, the runtime read each child's pid from the wrong
  word of a hot-reload supervisor, so stopping the tree could stop an unrelated actor
  and a restart wrote past the actor, and `get_actor_field` found no state field of a
  hot-reload actor.
- **Hot reload: a patch that adds a function no longer crashes the running node.**
  A patch `.so` called hot-swappable functions by its own build's slot numbers,
  which shift when the new version adds or removes one. Since the entry
  module's functions became hot-swappable, this sent calls to the wrong
  function (SIGSEGV on both nodes of the `protocol_expand_contract` deploy). A
  patch now looks its slots up by name when it is loaded. Also, a later deploy
  that changes such a newly added function now redeploys its callers to carry
  it, rather than leaving them on the old copy.
- **Compiled HTTP servers no longer leak ~0.5 KiB per request.** Neither the
  thread-pool nor the event-loop server released the `Conn` a handler returns
  after writing the response, so every request leaked the result record and
  its strings (a text-only handler grew 158 MB in 10 s at 31k req/s; forgepm
  at 800 req/s grew 400 MB/min). `HttpServer.listen` now hands the runtime a
  compiled `Conn -> Unit` release function, applied once the response bytes
  are written (after deferred writes drain, or on close). `http_server_listen`
  takes that function as a fifth argument.
- **A borrowed aggregate dropped by a closure trampoline is released deeply.**
  A top-level function with a borrowed parameter, passed as a closure value,
  had that argument released by its `$clo_wrap` with a shallow `march_decrc`,
  orphaning the aggregate's children; the trampoline now calls the type's
  synthesized deep drop when one exists.
- **A release through the control plane no longer orders functions the nodes cannot
  patch.** forge recorded a release's signed lines against the last deployed manifest,
  which lists every function, including the control plane's own wiring, which has no
  hot slot. A release that changed one of them ordered its activation and every node
  refused the whole batch (`commit_partial_failure`). forge now asks the candidates which
  slots the nodes have and activates only changed functions among them, as
  `forge deploy hot` does against a real node. A cluster leader
  also no longer waits forever for a cluster member that runs no agent (a client, an
  upgrade test's traffic node): an unmarked member is waited for 20 s
  (`MARCH_CONTROL_AGENT_GRACE_MS`).
- Compiled: a dying tuple releases its boxed `Float` fields, and a dying
  `List(Float)` cell (any generic container slot holding a Float) releases the
  box in that slot; both leaked one object per Float before.
- Compiled: a tuple or record holding a niche-encoded `Option` (`Some(tree)`)
  releases the payload deeply when dropped; the subtree leaked before.
- Compiled: an aggregate whose field type still mentions a type variable (a
  tuple destructured inside a polymorphic local `fn`) is released instead of
  skipped; its lists are walked and freed.
- Compiled: a generic named function passed where a `Float -> Float -> Float`
  closure is expected returned the wrong value (its trampoline unboxed the
  arguments per the use-site type instead of forwarding them as the function
  is defined).
- Compiled: a self tail call inside a nested-pattern match arm
  (`Cons(a, Cons(b, rest)) -> … f(Cons(b, rest))`) is now a loop; it recursed
  once per element and overflowed the green-thread stack at ~8,000 elements.
  A match's fall-through join point with a single call site is put back in
  place by the lowering instead of becoming a closure.
- Compiled: a nested pattern with a default arm that uses the scrutinee no
  longer leaks the matched value (the dead join-point closure's release is
  deep), and Perceus no longer releases a scrutinee ahead of a pattern field
  the arm still reads.
- **`==` inside a `test`/`setup` body is checked where it is written.** The
  `Eq`/`Ord`/`Num`/interface constraints a test or setup body raised stayed
  pending until the next top-level `fn` or `let`, so a `fn` placed between two
  `describe` blocks was blamed for every `==` in the tests above it ("`T` does
  not implement interface `Eq`" at the fn's span), and with no later `fn` they
  were never checked at all. They are now reported at the test itself. Tests
  that compared a type with no `Eq` impl, which used to pass unchecked, are now
  rejected; to keep them working, these stdlib types now `derive Eq`:
  `Cli.FlagArity`, `Control.CtlHosts`/`CtlAction`/`CtlGate`/`StepOrder`/
  `CtlDecision`, `File.FileKind`, `Membership.MemberStatus`/`Member`,
  `NodeCert.Cert`, `NodeIdentity.Identity`, `RemoteCall.CallError`/`Verdict`/
  `ReplyResult`/`CallReply`, `Swim.Action` and `VectorClock.ClockOrder`.
- **Hot reload: the entry module's own top-level functions can be hot deployed.**
  The compiler names them without the entry module's prefix, so with
  `--hot-reload <EntryModule>` (what forge passes) a role body, hook or helper
  written at the top of the entry file had no dispatch slot: `forge deploy hot`
  answered "no hot-deployable changes" and the old code kept running. They are now
  slots, chosen by where the compiler loaded them from; `main` stays off the
  boundary, and so does the control plane a `[control]` topology splices into the
  entry module (it runs the deploy), including its `CtlRespawner` actor. A
  function's call to itself stays a direct call, so a recursive function costs
  nothing extra in a `--hot-reload` build (dispatching it made `fib` 4.8x slower).
- **Hot reload: a one-line edit to a topology app no longer plans a restart.** A
  function's hot-reload identity hashed the numbers the compiler gives lambdas,
  join points and type variables, which any edit renumbers, so every function that
  merely referred to one (the generated `main`, `Front.start`, ...) looked changed,
  and an unslotted `main` changing made `forge deploy` restart the pool. An edit
  inside a role body's closure was planned as a restart too, because the manifest
  never said which function builds the closure. Now a handler edit flags that
  handler and its actor's dispatch only, a closure edit flags the function that
  builds it, and both deploy as hot patches.
- **A let-bound lambda that ignores or returns a `Float` argument no longer
  crashes compiled code.** A lambda bound with `let` and left generic, such as
  `let keep = fn (acc, x) -> acc`, freed the `Float` it was given when it
  ignored it, and the caller freed it again. That happened when the lambda was
  passed to `NativeArray.fold_float`, `fold_f32` or `typed_array_fold`, or called
  through a parameter typed `Float -> Float -> Float`. It showed up as
  `RC underflow` on macOS and `malloc(): unaligned fastbin chunk detected` on
  Linux. Such a lambda that returns its `Float` argument, or passes it on to
  another closure, also no longer leaks it.
- **A compiled `Array` that is built, updated and dropped no longer leaks its
  trie.** `Array.from_list`, `push`, `set` and `pop` leaked about one object per
  element once a vector held more than one 32-element leaf (a 1,100-element
  `from_list` leaked 2,224 objects per build, 40,000 leaked 81,118). Four compiler
  causes (a tuple bound by `let (a, b) = ..` was never released when its scope ended
  in an `if`, `match` or arithmetic; nested local functions lost their frame tuples;
  a nested pattern with a default arm leaked its join-point closure; an `Option` of
  a tree in a tuple was released shallowly) are worked around in `stdlib/array.march`
  or fixed in Perceus. Loops that destructure a tuple are still compiled to loops.
- **Compiled `Seq` constructors and combinators no longer leak.** Draining
  `Seq.from_list`, `Seq.from_string_lines`, `Seq.map`, `Seq.filter` and
  `Seq.concat` with `Seq.count` or `Seq.fold` leaked 3 to 5 heap objects per
  use, so `Process.run_stream` leaked on every call. The compiler leaked a
  closure's forwarded captures, reused a dying `Seq` cell as a capture-free
  closure, missed closures stored through cell reuse, and left a dead
  join-point closure holding references in `match ... rest -> ...` fall-throughs.
  A capturing lambda handed to `Seq.map` still leaks one object per use.
- **Compiled `to_string(())` prints `()`.** A compiled program printed `0` for
  the unit value, in `to_string`, `show`, string interpolation and inside
  containers (`Some(())` printed `Some(0)`). It now prints `()` as the
  interpreter always did.
- **Compiled actors no longer leak every message they receive.** A compiled
  actor never released a delivered message, its heap fields, or the state
  record a handler returned, so memory grew with every message for the life of
  the program. A `send` written as a statement also leaked the `Some(())` it
  returns. All three are released now; the interpreter was never affected.
  `send` now returns one shared `Some(())` instead of allocating one per call,
  so a send-heavy program is no slower for the extra frees (14% faster on
  `bench/actors/fanin_flood.march` at 8 schedulers).
- **A named record read only through its fields is freed (compiled).** A value
  of a declared record type (`type Pair = { a : String, b : String }`) that was
  built, read through `r.a`, and then dropped leaked its cell and every heap
  value it held. It is now released at the end of its scope, as an anonymous
  record already was.
- **An app actor may share a name with a standard-library actor.** An app
  `actor Anchor`, `Writer`, `Endpoint`, `HostWatch`, `RegWatch`, `CtlWriter`,
  `OfferActor`, `ApInbox` or `ClusterNodeActor` used to collide with the
  stdlib's own actor of that name: `--compile` and `--emit-llvm` died with an
  internal compiler error (`actor-message tag table has no row for
  Anchor_Msg.Bump`) or charged the app the stdlib actor's capabilities, and the
  interpreter could spawn the app's actor where the stdlib meant its own. The
  stdlib's actors now get module-qualified internal names
  (`Topology__Anchor`); app actors keep theirs, so spawn symbols and
  hot-reload manifests are unchanged.
- **A DataFrame column of nothing but nulls keeps its nulls.** CSV/JSON loading and
  `summarize` used to turn an all-null column into a plain string column of `""`, so the
  rows read back as empty strings; they now read back as `NullVal`.
- **Linux `--cap-sandbox` now filters threads that already exist when the
  sandbox is installed.** The seccomp filter covered only the installing
  thread and its later children, so the hot-reload server thread (started
  before `main`) and any thread started by a C library constructor ran
  unfiltered. The filter is now installed with `SECCOMP_FILTER_FLAG_TSYNC`, so
  it covers the whole process, as the macOS sandbox already did.
- **A program that calls `NodeQueue.start_local` itself now compiles under the
  capability ceiling.** Stdlib `Socket` declared no `needs`, so the ceiling
  rejected any such program with "module `Socket` uses `IO.NetConnect` but does
  not declare `needs IO.NetConnect`", whatever the program granted. `Socket` now
  declares `needs IO.NetConnect`. A program whose `main` is not granted
  `IO.NetConnect` is still rejected.
- **`[ffi.rust]` crates now work under the interpreter.** `forge run`,
  `forge interactive` and interpreted `forge test` used to fail at the first
  Rust extern with "symbol not found for interpreter FFI", and printed a
  compile-only warning. The compiler now links every static archive given with
  `--ffi-link` (such as the crate's `lib<name>.a`) whole into the interpreter's
  FFI shim, so the crate's functions resolve and a project gives the same
  output interpreted and compiled. Compiled `[ffi.rust]` builds also link on
  Linux now: the archive used to come before the program on the link line, and
  GNU ld then skipped it (`undefined reference`).
- **A compiled filter-shaped recursive function no longer overflows the stack
  when its branches alternate.** A function with one `Cons(x, self(..))` arm and
  one plain `self(..)` arm (a hand-written `filter`) is turned into a loop by
  tail-recursion-modulo-cons, but the plain arm re-entered the original
  function instead of continuing the loop, pushing a frame each time the input
  switched arms. Keeping every other element of a 1,000,000-element list died
  with SIGBUS in the stack guard page; all-kept and all-dropped inputs ran fine.
- **SIGTERM no longer cuts the sessions a node initiated.** `Topology`'s drain
  counted only its offers' sessions, so a node that serves no role exited 0 at once
  on SIGTERM, cutting sessions it had started with `initiate_R` (from a hook or a role
  body) or `cluster_R`. The drain now waits for those sessions too, under the same
  soft and hard deadlines.
- **Logger appenders work in compiled programs.** Compiled,
  `Logger.add_appender` did nothing, `Logger.list_appenders()` was always
  empty, and every message went to the stderr fallback line. Appenders now
  receive each `LogEntry` exactly as they do interpreted, newest
  registration first. An atom field (`Logger.LAtom(:closed)`) now logs as
  `:closed` rather than `null`.
- **Compiled programs no longer leak memory on every subprocess call.** Each
  `Process.spawn_async` leaked its argument list and the `LiveProcess` handle
  it returned (the handle could never be freed once `read_line`, `write`,
  `kill` or `wait_proc` had used it), and `Process.run`, `Process.env` and
  `Process.set_env` leaked their arguments on every call.
- **Editor highlighting (tree-sitter) now covers current March syntax.** The
  tree-sitter grammar that Zed highlights from failed to parse most real files
  (713 of 919 in the repo), so they rendered as one long error region. It now
  parses every file the compiler accepts, including record literals, multi-line
  match arms and lambdas, patterns, actors, protocols and declarations added
  since March. Zed's highlight and outline queries, broken since August, compile
  again. A CI job keeps the grammar in step with the compiler.
- **A source-tree `march` no longer builds its runtime from a partial copy of
  `runtime/`.** If a build had copied only some runtime C files into
  `_build/default/runtime` (the vault scaling benchmarks do), the compiler used
  that directory anyway and left the missing files out of the runtime. The REPL
  then couldn't load its cached stdlib and recompiled it (~25 s) on every
  start. The compiler now uses a runtime directory only when it holds every
  core file listed in its `sources.list`.

- **`run_until_idle()` no longer returns while actors are still exchanging
  messages.** Its idle check read processes one at a time, so a message
  sent between two reads went unseen. About 1 run in 100 of a busy
  two-actor ping-pong returned early (compiled, 14 scheduler threads). The
  check now retries if any message was sent or process spawned while it ran.
  `specs/lang/actors.md` states what `run_until_idle()` does and does not
  wait for.
- **`march --check` of a module with several `@[endpoints]` protocols is fast
  again.** Each protocol made every later one roughly twice as slow to typecheck:
  one module with six protocols took about 9 minutes. It now takes under a
  second, and time grows roughly linearly with the number of protocols (16
  protocols: 1.6 s). Diagnostics are unchanged.
- **A path-scoped `needs IO.FileRead("...")` now covers `csv_open`.** A
  literal path passed to `csv_open` was never checked against the declared
  scope, so `csv_open("/etc/passwd", ...)` compiled under
  `needs IO.FileRead("/srv/data")`. It is now rejected like `file_read`.
- **`Process.spawn_async` no longer hands a running process's slot to a new
  one.** Compiled code kept live processes in a fixed table of 64 with no
  lock. The 65th spawn silently closed the first process's pipes, so a
  `LiveProcess` held that long read from and wrote to nothing or to another
  child, and two threads spawning at once could take the same slot. The
  table is now locked and grows as needed. A handle used after `wait_proc` no
  longer reaches whichever process took its slot next. Interpreted,
  `wait_proc` on a child that reads its stdin (such as `cat`) no longer
  hangs.
- **`get_actor_field` no longer keeps the actor it reads alive forever.**
  In compiled code each call leaked one reference to the actor's record, so
  an actor that was ever probed with `get_actor_field` was never freed.
- **A caught panic reads the same compiled and interpreted, and compiled
  `unreachable()` no longer crashes.** When a thunk passed to
  `__try_call` / `__try_call_val` panicked (the call behind `Check`'s
  property runner), compiled code returned `Err("boom")` where the
  interpreter returned `Err("panic: boom")`. Compiled now matches, and
  `todo(msg)` likewise reads `todo: msg`. Compiled `unreachable()` used to
  segfault; it now panics with `unreachable: reached unreachable code`.
- **On macOS, `IO.NetConnect` no longer lets a sandboxed program listen.** Under
  `--cap-sandbox` and `forge cap run`, any network capability granted the whole
  `network*` class, so a program holding only `IO.NetConnect` could still bind
  and accept connections. The grant is now split: `IO.NetConnect` allows
  outbound connections (DNS, TCP and TLS clients keep working), `IO.NetListen`
  allows bind and inbound, `IO.Network` allows both. Linux already worked this
  way.

- **The parent module can send to a nested actor by qualified message name.**
  `send(p, Inner.Set(1))` from the module enclosing `Inner` failed with
  "I don't know a constructor called `Inner.Set`", although `Inner.A(1)` and
  `spawn(Inner.Box)` worked. A nested actor's message constructors are now
  reachable qualified, and so is an `Inner.Box.Msg` annotation. The bare
  name stays local to the actor's module.

- **A module that `import`s a sibling declared later in the file is now
  checked against that sibling's capabilities.** Sibling modules were
  checked in declaration order unless a qualified reference said otherwise,
  so `import Sibling` followed by bare calls into a later `Sibling` ran
  before `Sibling`'s capabilities were known, and the missing-`needs` error
  for the import was silently skipped. An import now orders the importer
  after the sibling, unless the two modules import each other.

- **Sending a linear message can no longer fail to link.** The compiler
  lowered a `send` whose message was linear to `march_send_linear`, which
  only the unit-test runtime defines, so a program that reached that path
  would have failed with an undefined symbol. It now compiles to the ordinary
  `send`. Compiled programs also no longer declare the unused
  `march_msg_copy`, `march_msg_move` and `march_process_alloc`.
- **Two actors with the same name in different modules are now two actors.**
  An actor `Box` in `mod A` and another `Box` in `mod B` (or at the file's
  root) shared one definition: the interpreter spawned the same actor for
  both, and compiled code ran one dispatch function against both state
  shapes (wrong state, a `no field` panic, or an internal compiler error).
  The nested ones now get distinct internal names (`A__Box`, `B__Box`), so
  `spawn(Box)` inside `A`, `spawn(A.Box)` from the parent and `Box.Msg` all
  reach the right actor. Actors whose names are unique keep their names, so
  hot-code-reload manifests are unchanged. Two actors of one name in the
  same module are now an error.
- **Actors that message each other back and forth are up to 2.6x faster.** With
  several scheduler threads, sending to an actor that was just going to sleep could
  make the sender wait a millisecond or more before delivering. A two-actor
  ping-pong of 1,000,000 messages took 3.07 s; it now takes 1.18 s. Actor programs
  built with `--hot-reload` were affected less (1.45 s -> 1.22 s).
- **`march --check` no longer passes a protocol expand it refuses, from its cache.**
  After a clean `--check` with `--protocol-baseline` and `--protocol-expand`, the same
  check without the baseline (which the compiler refuses) exited 0 from the cache
  without checking anything. The baselines and the expand labels are now part of the
  check's cache key.
- **A remote message sent after a hot deploy now reaches an actor whose message type
  the deploy changed.** Each cluster link's reader task kept the code of the moment
  the link formed. So a message from a peer already on the new format was decoded by
  the old route code, stamped as an old-format message, and then converted with
  `migrate_msg` or dropped. A link reader now moves to the new code at the next frame
  it reads, and so do the node's ticker and acceptor, so a cluster node no longer
  keeps the old code pinned after a deploy.
- **`ClusterNode.stop` now closes the node's link to itself.** After `stop`,
  `queue_for` on the node's own id still returned a queue, a send to a local
  process was still delivered, and every stopped node left its loopback handler
  registered for the life of the process. A process that starts and stops nodes
  (tests, embedding) leaked one per node and kept local sessions reachable after
  stop. Now `queue_for(own id)` is `None`, a send to the node itself is refused,
  and the handler is released.
- **A recorded hot-deploy request can no longer be replayed against a node.** Signed
  `ACTIVATE`, `TOPOLOGY` and `DRAIN` requests carried nothing that made them fresh, so
  anyone who could reach a node's reload socket could send an old one again, rolling a
  function back or re-pushing an old placement. forge now sends each signed request
  inside a numbered release (`SEQ`). The node remembers the newest release it accepted,
  across restarts. It refuses older releases, two different releases with the same
  number, and, once it holds one, any unwrapped signed request. `MARCH_HCR_REQUIRE_RELEASE=1`
  requires releases from the first request. Older servers keep getting unwrapped requests.
  Every release accepted or refused, and every `DRAIN`, is now audited.

- **The signed topology push is now the one a node applies, including after a restart.**
  The node used to verify a pushed topology, then apply an unsigned copy forge wrote
  alongside it. A restarted node came back on its built-in placement rather than the one
  last pushed. `Topology` now reads the verified copy first, and applies it at start.
- **A closed or refused session offer no longer leaks its actor and two
  Vault tables.** `SessionNode.close_offer` left the offer's `OfferActor`
  running for the life of the process, and an `offer_*` refused with
  `AlreadyOffered` left one behind per try, which Topology's placement loop
  made once per tick while a released name was still held. Each offer also
  created two Vault tables, which are never freed. A closed offer's actor now
  ends once no session runs under it (at once when none does), a refused
  offer's at once, and offers keep their state in two shared tables whose
  keys are dropped when the actor ends. Plain and hosted offers alike.

- **A node healed after a network partition is now reported as rejoined.** If the
  heal's redial closed a duplicate connection at the same moment the link came
  back, the peer passed through Suspect, and its return was reported as `NodeUp`
  instead of `NodeRejoined`. A subscriber that had already seen the peer up never
  heard that it came back.

- **`ClusterNode.register` no longer lets two local processes register the same name
  at once.** The check for a taken name read the node's view, which the node updated
  only on its next turn. So two back-to-back registrations of one name could both
  return `Ok`, and the second caller believed it held a name it never got. A
  registration still waiting for the node's turn now counts as taken: the second
  one returns `Err(Taken(first))`.
- **Deep tail recursion that hands a freshly built value to a parameter the
  callee only reads no longer overflows the stack or leaks.** A pair of
  mutually tail-recursive functions in that shape (e.g. `take_next`/`inspect`
  passing `"refused " ++ x` along) was compiled as real recursion and died with
  a stack overflow on a long enough input (1,000,000 steps), and a
  self-recursive function in the same shape leaked one value per iteration.
  Both now run as loops, and those values are released when the loop returns,
  as the recursion would have released them.

- **A compiled `match` on string literals no longer leaks memory.** Each arm
  it tried allocated a copy of that arm's literal and never freed it, so a
  string `match` in a loop grew memory without bound: one string per arm
  compared, on every evaluation.
- **Compiled `Logger` now behaves like the interpreted one, and no longer
  crashes or leaks.** `Logger.current_fields()` handed back the runtime's own
  field stack without a reference, so the next logger call aborted with
  `RC underflow`; `Logger.with_fields` and `Logger.with_scope` did not compile
  at all (`use of undefined value '@logger_add_field'`); per-module levels
  (`Logger.set_module_level`, `Logger.log_in`) were ignored; the default level
  was Debug instead of Info; every log line printed its context fields twice;
  `Logger.with_context` fields never appeared on a log line and
  `Logger.clear_context` left structured fields in place; and each log call
  leaked its strings and field list. `__try_call`, `__try_call_val`,
  `http_fetch` and the Logger builtins now have checked C prototypes, and a
  new test fails if any builtin reaches the runtime without one.
- **`forge topology gen systemd` names the variables the runtime reads**:
  `MARCH_POOLS` and `MARCH_TOPOLOGY_FILE` (it wrote `MARCH_POOL` and
  `MARCH_TOPOLOGY`, which nothing reads), and adds `User=march`, the reload
  socket, the status file and `HOME`. `forge topology gen ufw` now allows ssh
  before `ufw --force enable`, which otherwise locked the operator out.
- **`forge deploy hot` checks a patch's target identity before uploading it.**
  #606 taught the reload server to answer `HCR_INFO` (target, HCR ABI, module
  prefix) but forge never asked, and it never read the manifest's `# hcr_abi`
  line. A patch built for another target, ABI or module prefix is now refused
  with both identities named, before any artifact is sent; a server too old to
  answer is still accepted for a native patch (with a note) and refused for a
  cross-target one. The runtime's own check after `dlopen` is unchanged.
- `forge run --processes` no longer occasionally assigns two pools the same cluster port (seen on Linux CI as `tcp_listen: bind failed`); the ports for all processes are now reserved together.
- **A top-level function named like a builtin now compiles.** Defining, for
  example, `fn file_read(n : Int) : Int` or `fn dns_resolve(...)` in your
  program (about 330 builtin names are affected) ran fine interpreted, but
  `--compile` failed with clang's `invalid redefinition of function
  'march_file_read'` once the function was large enough not to be inlined or
  was passed as a value. The function now gets its own symbol, and calls to
  it reach it, including from a nested module or an `impl` in the same file,
  matching the interpreter. Stdlib code that calls the builtin of the same
  name (such as `String.reverse`) still calls the builtin. In compiled builds,
  a call through a parameter or local named like a builtin is also no longer
  charged that builtin's capability.
- **A parameter or local named like a builtin no longer demands that
  builtin's capability.** `fn go(file_read : String -> String) do
  file_read("x") end` was rejected on both backends with "function bodies in
  `M` call builtins that require `Cap(IO.FileRead)`", although the call goes
  to the parameter. The capability check now treats a name bound by a
  parameter, `let`, lambda parameter, match-arm pattern or local `fn` as that
  local inside its scope, the same rule compiled builds already used. The
  `cap pure` / `cap deterministic` checks and the "requires `needs`" hint
  follow the same rule. A real builtin call outside that scope, such as in
  another function, still needs the capability.

- The interpreter no longer dies with `stub NAME called before initialisation` when a nested module calls an enclosing module's fn that is declared after the nested module. This covers calls from the nested module's own fns, its impl methods and actor handlers, and modules nested further down. Compiled programs already worked (#645). A module-level `let` that calls a fn declared after it still fails, as before.

- **`dns_resolve` / `Dns.resolve` now return the same list interpreted and compiled.**
  The interpreter listed each address once per socket type (`"127.0.0.1"` came back
  as `[127.0.0.1, 127.0.0.1]`), and compiled code also returned IPv6 addresses
  (`"localhost"` gave `[127.0.0.1, ::1]`) that no March socket can connect to. Both
  now return IPv4 addresses only, each once, in the resolver's order, as the `Dns`
  module documents. A host with no IPv4 address (including an IPv6 literal) is
  `NotFound` on both, where compiled code used to report a resolver error message.

- `forge run --processes` no longer occasionally assigns two pools the same cluster port (seen on Linux CI as `tcp_listen: bind failed`); the ports for all processes are now reserved together.

- **A process now exits after a hot deploy even when an actor is blocked in a nested
  `receive()`.** A queued epoch marker was counted as mail the actor could take, so
  shutdown never stopped it and the process spun for ever.
- **`get_actor_field` is `Pid(a) -> String -> Option(Int)`.** It was a free
  `Option(b)`, an unchecked cast: a field could be read back as any type, and a pid
  stored as an Int read back as a `Pid` crashed compiled code. It now returns `Some`
  only for an Int-like field and `None` otherwise.
- **A draining node withdraws from role placement at once.** On SIGTERM it unregisters
  its placement markers and leaves the cluster before exiting. A `count = n` role is
  re-offered elsewhere instead of staying unavailable for the whole drain plus SWIM's
  suspect timeout.
- **A ClusterNode's internal Vaults can no longer be found by name**, which let any
  code with `IO.Mut` stop the node or rewrite its routes without the node capability.
- **Hot-reload dispatch can no longer select a newer version for an older caller**
  when a ring slot is reclaimed and republished between the lookup and the pin.
- **A compiled `<actor>_migrate_msg` now matches the real old-format messages a hot
  deploy hands it.** The runtime passes a message the previous build allocated, but the
  user's old message type was compiled with ordinary tags, so the match panicked
  "non-exhaustive pattern match" and killed the process on the first old message. The
  old type is now compiled with the actor's message representation and tags, by
  constructor name. Actor-message tags are also stable across builds: removing a
  handler no longer renumbers every later actor's messages, which silently dropped
  their queued messages after a deploy. Hot-reload patches built by this compiler carry
  ABI id `march-hcr-v3` and are refused by older running binaries.
- **A cached `--compile --compile-so` build restores its `.hcr_manifest` and
  `.schemas.json`**, not only the `.so`. `forge deploy hot` no longer reports "no
  manifest" after a second build of the same source.
- **Hot reload: a patch `.so` no longer carries its own copy of the C runtime.**
  `march --compile --compile-so` linked every runtime object into the patch,
  so code the patch ran used a second scheduler table and a second vault
  registry: the first task a new-code handler spawned killed the process
  ("no green thread running on this scheduler") and `Vault.whereis` from new
  code could not see state the old code created. A patch now links only its
  own IR (plus the HCR identity strings) and binds every runtime symbol to the
  host process at `dlopen` time, on macOS and Linux. User FFI shim sources are
  no longer linked into a patch either; a patch needing a new shim fails to
  load instead of carrying a private copy.
- **Hot reload: calls from non-reloadable code into reloadable code now reach
  the patch.** A call dispatched only when both caller and callee were
  reloadable, so the generated topology `main`, the entry module's closures,
  actor handlers and stdlib callbacks called the baseline for ever after a
  deploy (`Topology.reoffer` reopened roles with the old body). A call now
  dispatches whenever its callee is reloadable; the boundary cost is
  unchanged (see `specs/progress/2026-09-25-hcr-dispatch-callee-only-rule.md`).
- **Hot reload: the entry file's nested modules are on the boundary.**
  `--hot-reload <EntryModule>` (what forge passes) never matched a nested
  module of the entry file, so a single-file topology app could hot-deploy
  nothing but actor handlers and `forge deploy hot` reported "No
  hot-deployable changes" for a changed role body. The entry file's own
  top-level functions remain off the boundary (filed).
- **Hot reload: a change inside a lambda a boundary function builds now
  deploys.** A boundary function's slot hash did not cover the lambdas
  lowering lifts out of it, so editing a session body (always a lambda)
  left the function's hash unchanged and `forge deploy hot` activated
  nothing. Lifted, bare-named helpers are now folded into the hash, by their
  body rather than their compiler-numbered names, so an unrelated edit does
  not make stdlib actors look changed and get hot-swapped.
- **`SessionNode.initiate` survives a re-offer.** When the only access point for a
  role answered "closing" (its replacement's registration not yet propagated), the
  session was reported as having no offer; it now looks again within the setup time.
- **Hot reload works under AddressSanitizer.** The reload server loaded a
  patch with `RTLD_DEEPBIND`, which ASan refuses; a patch is now bound
  locally at link time instead (`-Wl,-Bsymbolic` on Linux) and loaded
  without it.
- **Compiling the same source twice at once (different `-o` or `--opt`) no longer
  fails at random with `Undefined symbols: "_main"`.** Both compiles wrote their LLVM
  IR to the same `<source>.ll` file and handed it to clang, so one could truncate the
  file while the other's clang was reading it. Now each compile writes its IR to a
  private temp file and links from that. When clang finishes, the temp is atomically
  renamed onto `<source>.ll`, so the IR still ends up where it always has, on failure
  too.

- `forge run --processes` no longer occasionally assigns two pools the same cluster port (seen on Linux CI as `tcp_listen: bind failed`); the ports for all processes are now reserved together.
- **Multi-threaded programs no longer occasionally abort with SIGTRAP (or a bare
  `Killed: 9`) at shutdown under load.** When a scheduler worker thread exited, a
  preemption tick already on its way could land inside the thread's teardown, and
  the tick handler touched thread-local storage that the teardown was rebuilding,
  which crashed the memory allocator. It hit about 0.3% of runs under heavy
  parallel load, with no output, and never reproduced on a rerun. Ticks that
  arrive after a thread has left its scheduler loop are now dropped, and worker
  threads block the tick signal before they exit.
- **The bare `sha256` builtin now typechecks as `Bytes -> String`, matching what it
  has always returned** (a 64-char lowercase hex string, like `Crypto.sha256`,
  `md5` and `sha512`). It was declared `Bytes -> Bytes`, so `Bytes.length(sha256(b))`
  typechecked and then crashed on both backends (a match failure interpreted,
  `fatal SIGBUS` / exit 138 compiled). Compiled `sha256` of a `Bytes` also crashed
  regardless of how the result was used (see the `Base64.encode` / `sha256`
  entry below for the runtime side); the builtin now also has its own runtime
  entry, chosen by the compiler from the static type, so it never guesses.
  For a raw digest use `hmac_sha256_bytes` / `sha1_bytes`.
- **A top-level function named like a capability builtin no longer fails a
  compiled build's capability ceiling.** A `fn dns_resolve(x : Int) : Int` (or
  `fn file_read(...)`, …) in the entry module was charged the builtin's
  capability, so `--compile` rejected it with "module `M` uses `IO.Network` but
  does not declare `needs IO.Network`", while the interpreter ran the same
  program. A call to a function the program defines is now attributed to that
  function.
- **Compiled `uuid_v7()` and `unix_time_ms()` now show up in the binary
  capability audit.** Both compiled, but no IO.Clock marker was emitted for
  them, so `forge cap inspect` under-reported any binary that used them.
  `uuid_v7`, `uuid_v7_at` and `dns_resolve` are now the prefixed runtime
  functions `march_uuid_v7`, `march_uuid_v7_at` and `march_dns_resolve`. Before
  the rename, any symbol spelled `dns_resolve` in a binary counted as an
  IO.Network witness.
- **Compiled `dns_resolve` no longer leaks its host argument** (one String per
  call). **Compiled `uuid_v7_at` with a negative timestamp now errors** as the
  interpreter does, instead of returning a UUID with a garbage timestamp.
- **Compiled code no longer reads freed memory through a record field after
  handing the record to a function.** Reading a field into a local
  (`let x = r.a`), then passing `r` to a function that takes ownership of it,
  then using `x`, read a string the callee had already released: garbage
  output, or another value's bytes. The interpreter was unaffected.
- **A nested module's call to a sibling module now links when compiled.** Inside
  `mod Outer do mod A ... end mod B do ... A.f(x) ... end end`, the call `A.f`
  ran interpreted but a compiled program failed to link (`A.f` undefined),
  whenever `Outer` was itself nested in the entry module, or was a library
  (`MARCH_LIB_PATH`) or stdlib module.
- **Capability Check 4 now fires for mutually importing sibling modules when the
  importee is declared later.** With `mod A` doing `import B` and `mod B` doing
  `import A`, the module checked first found no capabilities for the other and
  silently skipped the check. It is now deferred until the whole module run and
  requires the importee's full declared set (fail-closed), so the same program
  is rejected in either declaration order.
- **Destructuring a tuple and moving its fields on no longer leaks in compiled
  programs.** `match t do (a, _, c) -> f(Box(a, c)) end` leaked the moved fields
  (two objects per call), and a field the pattern never used was never freed.
  The compiler treated a tuple pattern's fields as borrowed although the match
  hands them over as owned; they now follow the same ownership as a constructor
  pattern's.
- **A record field returned out of the scope that owns the record is no longer
  freed with it (compiled).** `let a = match f() do Some(m) -> m.addr ... end`
  handed the caller a String the record still owned, and it was freed when
  the record was dropped: a use-after-free once the record held the last
  reference (it crashed a cluster node on a peer reconnect). The field now
  gets its own reference first.
- **`Process.run_stream` works in compiled programs and no longer leaks.** The
  compiled runtime returned the raw stdout String under the `Seq(String)` type
  (any `Seq` operation on it panicked) and leaked three objects per call. Both
  backends now build the `Seq` from the captured output the same way, and the
  runtime releases what it allocated on the way.
- **Tail-recursion-modulo-cons now covers a computed call argument and nested
  helper functions.** `Cons(a, r(a + 1, b))` was compiled as a plain non-tail
  recursion (stack overflow on long lists) although the same code with `a + 1`
  bound on its own line was optimised; and a natural-style nested `fn go` was
  reported as eligible but never rewritten. Both are now transformed, so a
  1,000,000-element list built this way no longer overflows the stack.
- **`Actor.top_by_mailbox` / `Actor.over_mailbox` and `NodeCall` typecheck cleanly.** The
  two mailbox helpers now return `List((Pid(a), Int))` (the parameterized `Pid`) and
  `NodeCall` names `RemoteCall.NoConnection` explicitly instead of the ambiguous bare
  constructor; seven hidden stdlib type errors are gone.
- **Compiled and interpreted programs now agree on `Int` overflow.** `Int` is
  63-bit and wraps on overflow ([Int width and overflow](specs/lang/type-system.md#int-width-and-overflow)).
  Compiled code used to do 64-bit arithmetic in registers, so
  `int_max_value() + int_max_value()` (or the same sum on two values read from a
  `NativeArray`) printed `9223372036854775806` compiled and `-2` interpreted. The
  compiled value also changed once it was stored in a list, tuple or closure. Compiled
  `+ - * /`, negation, `int_shl`, `int_div`, `int_abs` and `int_pow` now wrap
  to 63 bits, and compiled `int_max_value()`/`int_min_value()` return
  `4611686018427387903`/`-4611686018427387904` instead of the 64-bit limits.
  Compiled `int_popcount(-1)` is 63, as interpreted.
- **Compiled `int_shl`/`int_shr` with a shift count outside `[0, 62]` now panic**
  with `int_shl: shift out of range` (as the interpreter does) instead of
  returning an undefined value. Compiled `int_pow` with a negative exponent
  panics with `int_pow: negative exponent` instead of returning `0`.

### Added
- **`forge deploy` splits a monolith's protocol change into expand and contract (D21).**
  When one build both makes a choice that gained a branch and receives it, `forge deploy
  --plan` now shows two deploys and why: the expand, built with `--protocol-expand
  <P>:<label>` (the receivers run the new version; the chooser keeps offering under the
  previous fingerprint and cannot choose the new branch), then the contract, the plain
  build, on the next `forge deploy`. It compares against what the environment runs
  (`.forge/deploy/<env>/protocols/`, in the compiler's baseline format), so every patch
  and base image is also built with the compatibility table for the running version,
  which it previously lacked. A change the compatibility rule does not allow, including
  unlabelled messages a new branch renumbers, is reported as breaking, naming the
  messages. This replaces the earlier split that held the chooser's functions back.
- **The `ssh` reconciler backend** (build step 10b of the distributed-deploys
  plan). A topology overlay with `[backend] kind = "ssh"` makes `forge topology
  apply --env <env>` and `forge topology status --env <env>` work on the
  overlay's hosts over ssh: a topology push is the signed `TOPOLOGY` verb on each
  node's reload socket (through an ssh tunnel), then the digest file and a SIGHUP
  to the pool's systemd unit; status shows each node's report, its restored patch
  stack, the stack's size and target, and flags code that drifted from what forge
  last deployed. `FORGE_SSH_CONFIG=<file>` passes `-F <file>` to every ssh forge
  starts.
- **`forge host init --env <env>`** prepares every host of an ssh topology once,
  over ssh: the `march` user and directories (code, the service's HOME whose CAS
  root holds the persisted patch stack, run state), the pool's systemd unit with
  the host's own `Environment=` (node name, labels, cluster port and address,
  seeds, reload socket, status and topology files, `MARCH_DEPLOY_POLICY`), the
  deploy public key, a shared cluster secret or, with an operator key from
  `forge cluster keygen`, a node certificate per node, the node's capability
  policy from its pool's written or derived `caps`, and the pool's ufw rules
  (applied when ufw is installed). A second run changes nothing. Each host's
  target (`linux/amd64`, `linux/arm64`) is recorded in `.forge/hosts/<env>.json`.
- **`forge deploy --plan --env <env>`** shows, per pool and build, what a deploy
  of the working tree would do, in six blocks: what changed (functions, actor
  state and message types, protocols with fingerprints, placement, hooks, the
  base image), the mechanism and why (hot patch, hot patch + migration, hot patch
  + protocol drain, restart, topology push), order and splits (the pools that
  receive a new choice branch before the pool that makes it; in a monolith, the
  expand/contract split into two deploys, D21), drains with the live sessions
  each node reports, what may be lost (queued messages with no `migrate_msg`,
  sessions cut at the hard deadline, renumbered unlabelled messages), and
  authority (a widening role closure or derived pool capability, and the
  `--grant-cap` it needs) with each pool's derived values.
- **`forge deploy --env <env>` carries the plan out** (confirmation, or `--yes`):
  pool by pool in the plan's order, a hot patch through an ssh tunnel to each
  node's reload socket (rolling with a health gate, `simultaneous`, or
  `--canary N`), a restart onto a base image cross-built for each host's
  recorded target (uploaded, the unit restarted, the node's reload socket
  waited for), then the signed topology push; what was deployed becomes the
  next plan's baseline in `.forge/deploy/<env>/`. A D21 split stops after
  deploy one and does deploy two when run again. A change the running base
  cannot swap (a function with no dispatch slot and no changed caller that has
  one, such as a closure body) is planned as a restart instead of a hot patch
  that would activate nothing.
- **Patch-stack compaction: `forge deploy --compact --env <env>`**, and
  automatically when a node reports a persisted patch stack longer than
  `[hot-reload] compact_after = N`: each build's base image is rebuilt from the
  current version, its hosts restart onto it, and their persisted stacks are
  cleared (forge checks each node reports an empty stack afterwards).
- **Protocol changes across versions** (build step 9 of the distributed-deploys
  plan). Every `@[endpoints]` protocol's `<P>_Msg` module now has `compat()`: per
  role, the previous fingerprint that role may form a session with. It is computed at
  build time against the previous version of the protocol, which the compiler reads
  with `--protocol-baseline <file>` and writes with `--emit-protocols <dir>`;
  `forge build` keeps it in `.forge/protocols/<P>.json` for any project that declares a
  protocol. One change counts as compatible so far: a `choose` gaining a branch, for the
  roles that receive that choice (not the one that makes it), and only if every message
  both versions exchange keeps its wire tag and payload type. An unlabelled message
  renumbered by the new branch makes the change breaking, and the explanation names the
  tags that moved.
- **Access points form mixed-version sessions.** Offer names carry the fingerprint, so
  a node can offer two versions of one role; initiators invite only offers their table
  allows (no round trip wasted on "protocol differs"), and an offer accepts a version
  its table, or a newer initiator's check, allows. `Topology.reoffer` reopens a role
  whose protocol changed with a fresh hosting actor and stops the old actor once its
  sessions have ended.
- **`--protocol-expand <P>:<label>`** builds the first half of a two-deploy protocol
  change for a binary that both makes and receives the changed choice: the chooser
  stays on the previous fingerprint and cannot pick the new branch. forge's
  `Protocol_split.plan` says when a change needs it.
- **Typed remote messages carry a schema hash.** `Node.send` / `Node.enqueue` put the
  message type's structural hash in the frame; an `@[remote]` actor accepts a matching
  (or absent) hash, converts an older shape through its `migrate_msg`, and refuses
  anything else with `DELIVERY_FAILED`. A node built before this refuses the longer
  frame, so upgrade receivers first.
- **Unlabelled steps in a protocol your topology uses are now a warning at the step**
  (D25), in `march --topology` output and in the editor, with a suggested label.
  Positional names (`Msg_A_B_2`) renumber when a step is added before them, which
  breaks a hot deploy; a label pins the wire tag. `forge topology check` already
  warned once per protocol in `topology.toml`.
- **Sessions drain automatically at loop boundaries** (D27, build step 6's
  follow-ups). When a node is draining (a hot deploy's `DRAIN`, or SIGTERM under
  `Topology.drain_on_signal`), every session it takes part in ends at the next
  iteration boundary of a protocol `loop`: the message that would start the next
  iteration goes back to its sender, marked undelivered, the receiving role ends
  there, and a role waiting on a drained role ends at that receive. No message is
  silently lost: each role's `run_<Role>` reports how many of its own messages came
  back. Every receive and offer gains an `_or_drain` form taking a drain handler,
  `(role, undelivered, token) -> Yield`, which gets the returned messages decoded
  and finishes with the generated `<Role>.drained(s, token)`; a receive without one
  simply ends. `loop atomic do ... end` opts a loop out. `Session.Ops` gains
  `suspend_at_boundary` and `on_drain`; `Session.in_process` stands in for the
  epochs with `drain_role`, `step` and the `sent`/`consumed`/`returned` counters;
  `SessionNode.drain_epochs(io, soft_ms, hard_ms)` drains a node from code.
- **A remote delivery an actor drops is answered with `DELIVERY_FAILED`.** A message
  from another node that the receive loop drops after a hot deploy changed the
  actor's message type (no `migrate_msg`, or one that returned `None`) now reaches
  the sending node's `ClusterNode.on_delivery_failed` handler with its sequence
  number and the reason, instead of only being counted.

- **`NativeArray.sort_i32`, `sort_f32` and `sort_u8`: every NativeArray width
  can now be sorted.** Same ownership as `sort_int`: in place when the array is
  uniquely owned, copy-on-write when it is shared. `sort_i32` is the same
  algorithm as `sort_int` on 4-byte elements. `sort_f32` orders by IEEE 754
  `totalOrder` exactly like `sort_float` (NaN at a fixed end, `-0.0` before
  `+0.0`), without widening to f64. `sort_u8` is a counting sort, about 0.3 ms
  for a million bytes whatever their order. The interpreter and compiled builds
  produce the same order, NaN included.
- **Node certificates for clusters** (build step 11a of the distributed-deploys
  plan, part 1). New `NodeCert` module: a certificate names a node
  (`spiffe://<trust-domain>/pool/<pool>/node/<name>`), its role permissions
  (`Proto.Role:offer` / `Proto.Role:initiate`), flags (`raw_send`), an expiry and
  a serial, and is signed ed25519 by an operator key; `NodeCert.verify(cert,
  operator_pubkey, now)` checks it, and operator-signed revocations name a
  serial or a whole node. `forge cluster keygen` makes the operator keypair (a
  separate key from the hot-reload deploy key), `forge cluster cert <node>
  --roles ... --flags ... --days N` issues a node key and certificate, and
  `forge cluster revoke --serial S | --node N` prints a revocation token. New
  builtins `ed25519_seed_keypair`, `ed25519_sign`, `ed25519_verify` and
  `x25519` (RFC 8032 / RFC 7748, over the runtime's TweetNaCl, which gained
  X25519).
- **Certificate mode for the cluster handshake** (step 11a, part 2). With
  `MARCH_NODE_CERT`, `MARCH_NODE_KEY` and `MARCH_CLUSTER_OPERATOR_PUBKEY` set
  (values or files), `ClusterNode.config_from_env` authenticates peers by
  certificate instead of `MARCH_CLUSTER_SECRET`: each node verifies the other's
  certificate against the operator key, its expiry and the node's name, then
  proves it holds its certificate's key by signing the peer's nonce and the
  handshake transcript. Shared-secret mode is unchanged and stays the default; a
  certificate node and a shared-secret node refuse each other with a message
  naming what to set. `ClusterNode.peer_cert(c, node_id)` returns the
  certificate a peer presented, `ClusterConn.connect_split_auth` /
  `accept_split_auth` do the same for direct connections, and
  `ClusterNode.on_security_event` reports refused handshakes.
- **Per-frame MAC on cluster connections** (step 11a, part 3). After the
  handshake every frame carries a sequence number and an HMAC-SHA256 tag under a
  per-connection, per-direction key (HKDF over the handshake transcript; from an
  X25519 agreement in certificate mode, from the secret in shared-secret mode). A
  modified, injected or replayed frame is dropped and counted
  (`ClusterNode.frames_rejected`, a `FrameRejected` security event), and three
  on one connection close it. This is integrity, not encryption: frames stay
  readable on the wire. Shared-secret nodes negotiate it, so they still talk to
  older nodes (unsealed). New `bench/cluster_frames.march`.
- **Certificate expiry and revocation** (step 11a, part 4). A peer whose
  certificate expires, or is revoked, is disconnected and reported as
  `NodeDead(_, "certificate expired")` / `NodeDead(_, "certificate revoked")`,
  so its sessions are cancelled as for any dead node, and its handshakes are
  refused from then on. `ClusterNode.revoke(c, token)` takes a token from
  `forge cluster revoke`; `MARCH_CLUSTER_REVOCATIONS` seeds the list at
  startup; nodes pass revocations on to each other, and only the operator's
  signature makes one count. `ClusterNode.revocations(c)` lists them.
- **Access points check certificates both ways** (build step 11b of the
  distributed-deploys plan, part 1; certificate mode only). An initiator skips,
  before inviting it, any offer whose node's certificate does not name
  `Proto.Role:offer` for the role, and lists it in `NoOffer`'s reasons ("node-b
  not authorized for Checkout.Ledger, not invited"): offer names are registry
  names any member can write, so the check is on the certificate of the node
  holding the offer. An offer refuses an initiator whose certificate does not
  name `Proto.Role:initiate` for the role it plays ("initiator node-a not
  authorized for Checkout.Client"). A node whose own certificate does not allow
  a role gets `Err(Unauthorized(role, why))` from `offer_<Role>`, and once a
  session forms each party checks that every role's endpoint is on a node
  certified for that role. Shared-secret mode checks nothing, as before. New
  `SessionAP` module (`SessionAP.authorize(cert, proto, role, mode)`),
  `ClusterNode.own_cert`, `ClusterNode.certified` and
  `ClusterNode.authorize_peer`; `NodeSend.Delivery` gains `from_node`, the
  verified peer a frame arrived from. The generated `offer_<Role>`,
  `offer_hosted_<Role>` and `initiate_<Role>` pass the protocol's role names
  (`SessionNode.offer_role`, `offer_hosted` and `initiate` take a `roles`
  argument after the fingerprint).
- **Raw sends need `raw_send` at both ends** (step 11b, part 2; certificate mode
  only). `ClusterNode.send_msg` refuses a raw send to or from a peer unless both
  nodes' certificates carry `raw_send` (`Err(NodeQueue.NotAuthorized)`, a new
  `EnqueueError` variant); `ClusterNode.queue_for` (what `Node.enqueue` uses)
  returns `None`; an inbound raw frame from such a peer is dropped before any
  route and answered `DELIVERY_FAILED`. On direct certificate-mode connections
  `NodeSend.cast` (`Node.send`) is refused and `NodeCall.call` (`RemoteCall`)
  returns the new `CallError.Forbidden`, which the serving side also answers.
  Session traffic (`ClusterNode.session_tags()`, to a route opened with the new
  `ClusterNode.route_session`) and ClusterNode's own control frames are exempt;
  SessionNode uses `route_session` and the new `session_queue_for`. Refusals are
  counted (`ClusterNode.raw_refused`, `NetKernel.raw_refused`) and reported as the
  new `RawSendRefused(node_id, what)` security event. A node's sends to itself are
  never refused.
- **Registry lookups follow the raw-send rule** (step 11b, part 3; certificate
  mode only). `ClusterNode.lookup` and `names` hide a binding unless this node's
  and the holder's certificates both carry `raw_send` (a name you cannot
  raw-send to is not a reference you should hold); a node's own bindings, and
  the coordination namespaces `ap:`, `session:` and `topo:`
  (`ClusterNode.reference_namespaces()`), always show. Each replica records who
  registered a binding (`ClusterNode.registrant(c, name)`, the certificate
  identity; `GlobalRegistry.Entry` gains `registrant`, `register_as`); it is not
  on the wire or in the Merkle hash. `GlobalPid.make` stays pure: sending to a
  pid is what is checked.
- **The direct session runner speaks certificate mode** (step 11b, part 4).
  `run_<Role>` / `host_<Role>` / `host_<Role>_or` authenticate by certificate
  when `MARCH_NODE_CERT` is set (new `ClusterNode.auth_from_env(name, secret)`,
  the variables a cluster node reads), over `ClusterConn.connect_split_auth` /
  `accept_split_auth`, and each side refuses a peer whose certificate does not
  let it play the role it announces ("role Audit.A is played by node-a: not
  authorized for Audit.A"). Without it, the shared secret as before.
  `SessionNode.run`, `run_hosted` and `run_hosted_or` take the protocol name and
  role names after the fingerprint (the generated runners pass them).
- **Placement changes on a running system and upgrade tests** (build step 8 of the
  distributed-deploys plan). A topology app's nodes re-read their topology on
  SIGHUP and move their own offers: a role's placement, capacity, or a pool that
  stops serving it applies with no code change and no restart. `forge topology
  apply [--env E]` is one reconciliation pass over the cluster `forge run
  --processes` started (recorded in `.forge/run/state.json`): it diffs, pushes,
  waits for every node to apply, and reports each node's offers; a change that needs
  a rebuild and restart is refused and listed. `forge topology status` shows each
  node's applied topology, offers and (with `forge run --processes --hot-reload`)
  its code versions and epoch pins. `forge test --upgrade-from <ref>` checks out
  the ref, starts it as local processes with reload sockets, drives
  `test/upgrade_*.march` through it, hot-deploys the working tree into the running
  processes, and fails on the reload servers' counters (messages dropped, actors
  killed by a hard deadline, markers lost) or the test file's own checks.
- **Hot reload: per-role capability closures, restart durability and signed
  topology pushes** (build step 10, first half, of the distributed-deploys plan).
  The `--compile-so` manifest gains a `ROLE <Proto.Role> caps=...` line per role
  with a grant: the role's full capability closure (everything its code reaches)
  with each capability's reach chain. `forge deploy hot` stops a deploy that
  widens a role's closure unless `--grant-cap` covers it, naming the role and the
  chain, and sends such builds with the new `ACTIVATE6` message, which signs one
  digest per role; the server recomputes each from the closures it receives
  (`ERR role_cap_tamper`) and checks every closure against `MARCH_DEPLOY_POLICY`
  (`ERR role_cap_policy <role> <cap>`), so a patch that only calls an existing,
  more powerful helper no longer slips past the node's policy. The reload server
  now persists its applied patch stack on the host (under the CAS root) and
  replays it at start, before `main` runs, re-verifying every signature; a bad
  entry is skipped with an audit line, a different base build or
  `MARCH_HCR_NO_REPLAY=1` starts clean, and `VERSIONS_DETAIL` reports a
  `RESTORED` line. New signed `TOPOLOGY` verb (`Cmd_deploy_hot.push_topology`)
  persists the pushed topology and hands it to a runtime hook; new `COMPACT` verb
  reports the patch stack's size, which `forge hot-reload status` prints.
- **Refinement predicates: `/` and `%` in general.** A predicate may now divide
  a possibly-negative value, or divide by a variable: `{Int | _ / 2 == -3}` and
  `{Int | d != 0 && _ / d > 0}` are checked instead of skipped. The checker uses
  March's truncating division (`-7 / 2` is `-3`, `-7 % 2` is `-1`), not the
  solver's Euclidean one, so `f(-7)` proves and `f(-5)` is reported. Dividing by
  zero panics, so a predicate is false wherever it would divide by zero,
  following `&&`/`||` short-circuiting: with `_ / d > 0`, a call with `d == 0` is
  a violation and one that cannot rule out `d == 0` is not proved.
- **`forge audit --inferred --allow-unanalyzable`** gates on the dependencies
  that typecheck, so a project can adopt the capability gate before its whole
  dependency graph checks cleanly. Every unanalyzable dependency is still listed
  with its reason on every run, and none is treated as asking for nothing.
  `--record` leaves unanalyzable dependencies out of `forge.caps.lock` and keeps
  any set recorded for them earlier.
- **`NativeArray.sort_float` — a `Float` array can now be sorted.** Same
  algorithm and ownership as `sort_int` (unstable, in place when uniquely owned,
  copy-on-write when shared), 1.9–18x faster than libc `qsort` at 5 million
  elements. Floats sort by IEEE 754 `totalOrder`, so NaN has a defined place:
  `-NaN < -Inf < ... < -0.0 < +0.0 < ... < +Inf < +NaN`. Note that `-0.0` sorts
  before `+0.0` even though `-0.0 == 0.0` and `compare(-0.0, 0.0)` is `0`. The
  interpreter and compiled builds produce the same order, NaN included.
- **Editor support for `topology.toml`** (build step 7 of the distributed-deploys
  plan). `march-lsp` recognises `topology.toml` and `topology.<env>.toml` and shows
  `forge topology check`'s diagnostics on forge's lines, computed by forge's own
  code; the base file also shows what each overlay adds (a `place.count` above the
  host count, a missing host label). Names resolve against open editor buffers, so
  renaming a function in a `.march` file updates the topology file's diagnostics at
  once. Go to definition on `body`, `actor` and `start` strings and on
  `"Protocol.Role"` strings (protocol part to the `protocol`, role part to the role);
  completion of functions, actors, roles, host labels, keys per section and pool
  names in an overlay's `[pool.` header; hover on a role showing its `role R needs`
  grant and its body type. Attach the server to those file names in your editor
  (`lsp/docs/editors.md`).

### Changed
- **Compiled code no longer makes a function call for every reference-count
  update.** The common case of each increment and decrement is now inlined into
  the calling function, and the runtime is called only to free an object or while
  `MARCH_TRACE_GC` is on. Closure-heavy code gets about 25% faster
  (`bench/list_ops.march`), tree code 6–12%. Let bindings now also get stack
  slots LLVM can keep in registers, so deep non-tail recursion uses less stack
  than before. Behaviour, trace output and leak accounting are unchanged. It is
  off for wasm and sanitizer builds, and `MARCH_NO_INLINE_RC=1` turns it off.
- **Float lambdas passed to `List.fold_left`, `List.map` and similar are up to
  25× faster when compiled.** A call that hands a lambda to a function which
  passes it straight through its own recursion (`fold_left`, `map`, `filter`,
  `filter_map`, `find`, `any`, `all`, and your own functions written the same
  way) now gets a copy of that function in which the lambda is called directly,
  and usually inlined, instead of through a closure that boxes every Float.
  `List.fold_left` over 2M Floats takes about 4.5 ms instead of 113 ms, and
  `List.map` about 55 ms instead of 132 ms. Results are unchanged. It is off
  under `--hot-reload`, and `MARCH_NO_HOF_SPEC=1` turns it off.
- **`NativeArray.fold_*` with a lambda is up to 67× faster when compiled.** A fold
  whose callback is a lambda written at the call site, with an `Int` or `Float`
  accumulator matching the array's elements, now compiles to a loop in the calling
  function instead of calling the runtime once per element. A Float fold no longer
  allocates a box for every element and accumulator: 4M elements take about 3 ms
  instead of 200 ms. Int folds vectorize and run about 21× faster. Results are
  unchanged, Float addition keeps its left-to-right order, and other folds
  (String or record accumulators, or a callback passed in as a variable) behave
  exactly as before.
- **Breaking: `Seq.batched`, `Flow.batch` and `Gen.frequency` now declare their
  preconditions in the signature.** `Seq.batched(seq, n)` and `Flow.batch(stage, n)`
  take `n : {Int | _ > 0}`, and `Gen.frequency(pairs)` takes
  `pairs : {List((Int, Generator(a))) | len(_) > 0}`. Each already forwarded to a
  contracted callee without restating the contract, so a zero batch size or an
  empty list compiled and failed at run time; a literal violation is now a
  compile error, and an unproven argument is a hint (an error under
  `cap verified`). To migrate, run `march --check --refine-suggest <fn>` on the
  caller, which prints the refinement to add to its parameter, or guard the call
  with `if n > 0` / a `match` on the list.
- **A small scalar aggregate built in the arms of an `if`/`match` no longer
  allocates.** When every arm builds the same unboxed type (for example
  `if c do P2(a, 1) else P2(1, a) end`), the join now holds the struct directly
  instead of boxing it in each arm and freeing it at the merge. A loop of 50
  million such constructions went from 1.61 s to 0.07 s (`bench/branch_aggregate.march`).
- **`test/stdlib/test_properties.march` now runs in CI, nightly.** Its 240
  property tests (about 4 minutes) were on a dune alias nothing ran. The
  nightly workflow's new `stdlib-properties` job runs them; they stay out of
  the per-PR `dune runtest`, which they would slow too much.
- **The standard library's actors are no longer hot-reload slots.** Under
  `--hot-reload`, only your own actors' dispatch functions get a slot; the
  stdlib's (the cluster node that answers SWIM pings, session endpoints, the
  node-queue writers, ...) do not, so a hot deploy never activates, pauses or
  migrates them. A stdlib change comes with a toolchain change and deploys by
  restart: the `.hcr_manifest` now records the stdlib it was built against
  (`# stdlib_hash`), `forge deploy --plan` plans a pool whose stdlib changed as
  a restart and says why, and `forge deploy hot` refuses such a build instead
  of reporting the server up to date. Which actors are the stdlib's is decided
  by where the compiler loaded them from, so an actor of yours named like a
  stdlib actor, or in a file named like a stdlib file, keeps its slot. A
  `--hot-reload` binary with no slot of its own (all its code in the entry
  module) now still starts its reload server; before, it got one only
  because the stdlib's actors had slots.
- **`Array.from_list` (and `RRB.from_list`) is about 8x faster.** It now builds
  the vector in one pass instead of appending one element at a time: 100,000
  elements take 6.6 ms instead of 54 ms. The resulting vector is the same.
- **NativeArray index loops no longer re-read the array length every iteration.** The
  `native_*_arr_length` accessors are declared pure and speculatable in the emitted IR, so
  LLVM hoists them (and the SIMD load/store bounds check that calls them) out of loops.
  `bench/simd_kernels.march`'s `dot_simd` is about 12% faster; results are unchanged.
- **`NativeArray.sort_*` is up to 7x faster on nearly-sorted input and 4-5x
  faster on input made of two sorted runs.** An array that is sorted apart from
  a few misplaced elements, or that rises and then falls, now takes a quick
  special path: 1,000,000 nearly-sorted integers sort in 1.7 ms instead of
  11.6 ms. Other inputs are unchanged. The special path may briefly allocate up
  to half the array's size, and falls back to the normal sort if it cannot.
- **`List.map`, `filter`, `filter_map`, `append`, `flat_map` and `range_step` walk
  the list once instead of twice.** They were accumulator loops followed by a
  `reverse`; they are now written in natural recursive style, which
  tail-recursion-modulo-cons compiles to a single loop that fills each new cell
  in place. Compiled `--opt 2`, 20k-element lists: `map` 0.53 s -> 0.24 s
  (`bench/list_producers.march`), `append` 2.0x, `filter`/`filter_map` 1.3x,
  `flat_map` 1.2x, `range_step` 1.4x. Results and signatures are unchanged, and a
  1,000,000-element list still works compiled and interpreted.
- **`NativeArray.sort_int`, `sort_float`, `sort_i32` and `sort_f32` sort random
  data 17-26% faster.** The step that finishes off short runs of up to 32
  elements now uses larger sorting networks and a merge (the layout Rust's
  standard library uses) and is twice as fast on its own. Sorting 1,000,000
  random integers went from 13.0 ms to 10.8 ms; already-ordered and
  few-distinct-value inputs are unchanged.
- **Functions that only read a data structure no longer take ownership of it
  because of a number inside it.** A function reading a `Node(Int, Tree, Tree)`
  or a `List(Int)` was treated as consuming the whole value as soon as it used one
  of the numbers, so every call on a shared value paid a reference-count update
  per node. Summing a shared binary tree of depth 16 300 times now takes 0.11 s
  instead of 0.30 s; reading a shared 10k-element list with `List.sum_int`,
  `fold_left` and `nth` is 20% faster.
- **The generated hosted event API's `cancel` takes the session: `cancel(s, parked)`.**
  The epoch hold a hosting actor takes for a session is now the transport's, taken at
  `register` and released at `close` for both hosting patterns (before, only the
  `take_idle` pattern held, and `finish`/`cancel` released a hold the many-session
  pattern never took); `cancel` releases through `Session.release_epoch(s)`, which,
  like `Session.hold_epoch`, now takes a `Cap(Session.Live)`. `Session.epoch_holds_here()`
  reads the running actor's hold count. A session party's hold is taken at its
  Endpoint's spawn and released on every runner's exit (cluster sessions used to pin
  their epoch for the life of the process). The reload server's `DRAIN` is signed and
  refuses the current epoch.
- **`run_<Role>` (and `cluster_`, `initiate_`, `host_` fronts) return
  `Result(Session.Outcome, RunError)`** instead of `Result((), RunError)`:
  `Ok(Session.Finished)` for a session every role completed, `Ok(Session.Drained(n))`
  for one ended by a drain. Code matching `Ok(_)` compiles unchanged.
- **A session whose party endpoint is killed at a hot deploy's hard drain deadline
  ends as `Err(Left("draining"))`**, as a hosted one already did, instead of a
  cancellation naming the endpoint.
- **Tasks pinned to an epoch are cancelled at the hard drain deadline**: a task
  computing without receiving is unwound at its next yield point and its `Task`
  handle completes as `Err("task cancelled")`, instead of running on.
- **Hot reload: the unified epoch model and drains** (build step 6 of the
  distributed-deploys plan). Every unit of work (actor, task, session) runs at the
  epoch of the deploy it started under, and every call it makes, from the base
  binary or a hot patch, resolves to the newest version at or before that epoch.
  A deploy puts a marker in every live actor's mailbox; the actor finishes its
  queued messages on the old code, then applies each passed deploy's
  `migrate_state` in order and moves. The marker ignores mailbox overflow
  policies, so a full `DROP_NEW` mailbox no longer loses it. A sender that already
  moved can make a receiver move early when the message type changed, keeping
  FIFO order. New `<actor>_migrate_msg(m : Old) : Option(<Actor>.Msg)` converts
  old-format messages that arrive after an actor moved (else they are dropped and
  counted); `<Actor>.Msg` names an actor's message type; `forge hot-reload
  migrate-msg-stub <Actor>` writes one from the running version's handlers, and
  `forge deploy hot` refuses a `migrate_msg` whose old type does not match them.
  Drains retire old epochs: a soft deadline (`MARCH_HCR_DRAIN_MS`, 5 s) moves
  stragglers at once, an optional hard deadline (`MARCH_HCR_HARD_DRAIN_MS`, or the
  reload server's `DRAIN epoch:<E> soft_ms:<n> hard_ms:<n>`) kills actors still on
  the old epoch for their supervisor to restart on the new code. Session parties
  and generated hosted endpoints take epoch holds, so an actor with a live old
  session stays old until it ends. Up to three live versions per function; a
  deploy that needs a fourth while all are in use gets `WAIT epoch:<E> pins:<n>
  deadline_ms:<t>` and stays queued, which `forge deploy hot` prints and polls.
  New reload-server verbs `PINS`, `DRAIN`, `ACTIVATE5`; `forge hot-reload status`
  shows the pinned epochs and the deferred/converted/dropped/killed counters.
- **Topology apps run: a generated `main`, placement, `forge run` and
  `forge run --processes`** (build step 3 of the distributed-deploys plan). A
  project with a `topology.toml` needs no `main`: `march --topology` generates one
  that starts the cluster node from the environment, runs each pool's `start` hook
  (with one narrowed `Cap(P)` per capability it declares, then the node handle;
  a hook still running after `MARCH_HOOK_TIMEOUT_MS` stops the process), opens the
  offers the topology places on the node, drains on SIGTERM/SIGINT and re-offers a
  role whose offer or actor died. A `body` binding receives the hook's environment,
  the session, the role's granted caps and its entry state; an `actor` binding is
  spawned per offer with the environment as its `init` argument and receives
  `Start`/`Deliver`/`Cancel`. The new `Topology` stdlib module does the placement:
  `on` labels from `MARCH_NODE_LABELS`, `count = n` by rendezvous hashing over the
  live members that serve the role (a dead node's role moves; a rejoined node
  counts after `MARCH_PLACEMENT_SETTLE_MS`), a lost role drained rather than cut.
  `march --topology` now also checks each binding's shape, role grants and hooks
  against a pool's written `caps`, and a pool's actual reach after typechecking
  (`--topology-isolate-foreign` adds the `IO.Foreign` isolation check);
  `--emit-core-ast` reports each pool's derived `caps` and `initiates`, which
  `forge topology export` now prints instead of `"caps": null`. `forge run` on a
  topology app always compiles and runs every pool in one process; `--processes`
  runs one process per pool as a local cluster (`--fail-fast`, `--env` for host
  labels), and Ctrl-C drains and stops them all. See `docs/topology.md` and
  `examples/topology_app`.
- **A cluster node can talk to itself.** `ClusterNode.queue_for(node, own_id)` is
  now a loopback link (ordered, no credit flow control), so two roles of one
  session can run on the same node: `initiate_<Role>` may pick its own node's
  offer, and prefers it.
- **The topology file, static half** (build step 7 of the distributed-deploys plan).
  `topology.toml` next to `forge.toml` binds each offered `Protocol.Role` to a
  `body` function or an `actor`, groups roles into `[pool.*]` sections
  (`start` hook, `serves` incl. `"*"`, `initiates`, `caps`, `isolate`, `public`
  ports, `place = { on = "label" }` / `{ count = n }` placement rules), with
  `[drain]` deadlines and `[backend]`; `topology.<env>.toml` overlays deep-merge
  tables and replace arrays. `forge topology check` validates it against the
  project's sources with `file:line` errors (unknown keys are errors, unbound
  served roles, names that resolve to nothing, labels no host carries, `count`
  above the host count, isolated pools sharing a role, a written `initiates`
  narrower than the code) and warns about unlabelled protocol steps; it runs
  automatically in `forge build`, `forge run` and `forge deploy hot` and writes
  the digest `.forge/topology.json` (schema version 1, documented in
  `specs/features/topology.md`). `forge topology export --json` adds each pool's
  derived `initiates` and the pool connectivity graph; `forge topology gen`
  writes `systemd` units, `ufw` scripts, DigitalOcean firewall JSON
  (`do-firewall`) or a `compose` file, or runs a `forge-topology-<target>`
  plugin from PATH with the export on stdin. `march --topology <json>` reads the
  digest and checks its version and bound names (nothing more yet). See
  `docs/topology.md`.
- **Parameterised actor `init`.** `init(env : T, n : Int) { … }` declares
  parameters that `spawn(A, env, 3)` supplies; they are in scope in the init
  expression, and every argument is checked against the matching parameter.
  Arity mistakes are reported with the actor's `init` signature (`spawn(A)` on
  an actor that takes parameters, or extra arguments on one that takes none).
  A supervised child can be given its arguments in the `supervise` block
  (`Worker w(db)`, with the supervisor's own `init` params in scope), and a
  restart re-supplies the same values. `init()` is the zero-parameter spelling
  of the bare form. Decision D24 of the distributed-deploys plan; see the
  actors and supervision chapters of the language reference.
- **Per-role grants in protocols: `role R needs IO.X, ...`.** A protocol can
  now say what each role's code may do, with the same capability paths (and
  the same did-you-mean on a typo) as a module's `needs`. The line comes
  before the first message step and is not part of the protocol's
  fingerprint: a grant is about the role's code, not the wire, so two nodes
  built with different grants still talk. `role` stays an ordinary identifier
  everywhere else. The grant is a value (D34): a granted role's body takes one
  `Cap(P)` per path, in order, after `Cap(Session.Live)` and before its entry
  state, every `<P>_Run` front narrows them from its `io` and passes them, and
  a hosted role receives them through `start`. A role with no grant line is
  unchanged. The grant is checked: at every call of a runner front, everything
  the callback reaches (helpers, values, spawned or hosted actors) must sit
  under the role's grant, reported with the chain from the body, as `main`'s
  grant is; and a role's grant must fit within `main`'s.
  `march --dump-role-authority` prints, per runner call, what the role's code
  reaches and the functions and actors it holds references to, with their
  capabilities: the effective-authority report, a report rather than a check.
- **Scripted and chaos peers for every `@[endpoints]` role.** Each role
  module now carries `Step`, `script(s, st, steps)` and `chaos(s, st, seed)`,
  two bodies of the role's own type derived from its projection. A script is
  a list of expected receives and canned sends checked against the state as
  it runs; a mismatch panics with the state, what was expected and what came,
  failing the test rather than the session. A chaos peer takes every choice
  by the seed, generates every payload (a `Gen.Generator` argument per user
  payload type the role sends) and leaves the session at its `may crash`
  points when the seed says so. Both run over the in-process transport with
  no sockets, and unchanged over the network.
- **A targeted diagnostic for `fn (a, b) -> …` used as a callback over a
  tuple.** `fn (a, b) -> …` is a two-parameter (curried) lambda, not a lambda
  that destructures a pair, so `List.map(pairs, fn (k, v) -> v)` was wrong in a
  way the typechecker used to report badly: either it was accepted with a
  nonsense type (the result variable absorbed the extra arrow, giving
  `List(b -> b)`) or it failed with the misleading "this type would have to be
  infinitely recursive … Did you forget to apply it". A multi-parameter lambda
  checked against a one-argument callback over a tuple of the same arity now
  says so and suggests `fn pair -> match pair do (a, b) -> … end`. Genuinely
  curried callbacks such as `List.fold_left`'s `b -> a -> b` are unaffected,
  including when the accumulator is itself a tuple.
- **Interpreted `int_shr` is now an arithmetic (sign-propagating) shift**, as it
  already was compiled: `int_shr(-8, 1)` is `-4`. It used to be a logical shift
  in the interpreter, so `int_shr(-8, 1)` printed `4611686018427387900`.
  Non-negative inputs give the same result as before.

### Removed
- **The `respond` builtin is gone.** It was an interpreter no-op stub
  (`respond(x)` returned `()`), had no callers, and never had a compiled
  lowering.
- **`MARCH_NO_TRMC` is gone.** The environment variable turned off
  tail-recursion-modulo-cons for every compile in the process, including the
  stdlib, which increasingly depends on the transform to avoid overflowing the
  stack on long lists. (The `--no-trmc` flag that briefly replaced it is gone
  too; see Changed.) `MARCH_TRMC` (already a no-op) is ignored.

### Changed
- **Programs that use the cluster transport directly need `IO.Mut` and
  `IO.Clock` in their grant.** `NetKernel`, `ClusterConn`, `PeerReader`,
  `NodeSend`, `NodeCall` and `NodeQueue` now reach a process-wide table (the
  per-connection MAC state) and the clock (handshake deadline, certificate
  expiry), and the capability check is a ceiling on the whole program. A
  `main(io : Cap(IO))` program sees no change; one with a narrow grant must add
  `needs IO.Mut` / `needs IO.Clock` and the matching `Cap(IO.Mut)` /
  `Cap(IO.Clock)` parameters (nine `test/native` loopback fixtures and the
  `restart` two-node scenario did).
- **`forge audit --inferred` caches each dependency's result** under
  `.forge/audit-cache/`, keyed on the dependency's files, the files on its lib
  path and the compiler. A repeat audit re-analyzes only the dependencies whose
  inputs changed, instead of rerunning `march caps` (minutes each) for all of
  them. A cached result prints the same output as a fresh one.
- **An unanalyzable dependency now fails `forge audit --inferred`.** A dependency
  that does not typecheck is listed as `NOT ANALYZABLE` with the compiler's
  reason, the check exits 1, and `--record` refuses to write a baseline.
  Previously the audit printed the error to stderr, used the dependency's
  declared `needs` set in its place and passed.
- **forge checks cached dependencies on online builds too.** `forge build`,
  `check`, `run`, `test` and `bench` re-hash each cached git or registry
  dependency against `forge.lock`, once per command. Before, only `--offline`
  did this. A tree that was edited or corrupted is fetched again, checked, and
  swapped in, with a one-line note. If the fresh copy does not match
  `forge.lock` either, the command fails, naming the dependency and both hashes,
  because `forge.lock` or the upstream source has changed. A clean cache prints
  nothing and fetches nothing. `forge deps` also no longer keeps an edited
  cached git tree and writes that tree's hash into `forge.lock`: it replaces the
  tree with the fresh clone. `--offline` is unchanged: a mismatch is an error.
- **Hot reload: a second deploy while actors are still migrating is accepted**
  (it used to be refused with `ERR publish_failed`); each actor applies both
  migrations in order. Past the soft drain deadline, messages in an unchanged
  format now run on the new code against the migrated state instead of being
  dropped; only old-format messages are dropped (or converted by `migrate_msg`).
  The compiled `main` follows the newest code; every other unit keeps the code it
  started with.
- **Breaking: a running cluster node is a capability, `Cap(ClusterNode.Live)`.**
  `ClusterNode.start` takes the root capability first, `start(io, cfg)`, and returns
  `Result(Cap(ClusterNode.Live), String)`; the `ClusterNode.ClusterHandle` type is gone.
  Every `ClusterNode` operation, and the generated `<P>_Run.cluster_*`, `offer_*`,
  `initiate_*` fronts, take the capability where they took the handle. Migration: call
  `ClusterNode.start(io, cfg)` from `main(io : Cap(IO))` (or wherever you hold `Cap(IO)`),
  write `Cap(ClusterNode.Live)` where you wrote `ClusterNode.ClusterHandle`, and add
  `needs ClusterNode.Live` to a module whose signatures name it. A function of yours can no
  longer return the node it started (only `ClusterNode` may produce the capability): start
  it in `main` and pass it down. Every operation goes through the capability's dictionary
  (`ClusterNode.ClusterOps`), so a test can attach its own with `ClusterNode.attach(io, ops)`
  (`ClusterNode.ops_stub(id)` panics on every operation it is not given) and inject
  membership events with no sockets. New accessors: `ClusterNode.node_id(node)` and
  `ClusterNode.next_id(node, key)`.
- **The "consider narrowing `Cap(IO)`" hint skips proof-capability factories.** A function
  that returns its own module's proof capability (`Session.attach`, `Actor.introspect`,
  `ClusterNode.start`) must take the root capability, because `mint_cap` only accepts
  `Cap(IO)`, so the hint could not be acted on.
- **Breaking: every `Stats` function that needs a non-empty list now says so
  in its signature.** `Stats.median`, `std_dev`, `iqr`, `iqr_default` and
  `quantile_default` take `{List(Float) | len(_) > 0}` (joining `mean`,
  `min_val`, `max_val`, `percentile`, `quantile`, `quantiles`, `variance`,
  `five_number_summary` and `mode`), and `quantile_default`'s `q` is now
  `{Float | _ >= 0.0 && _ <= 1.0}`, the same as `quantile`'s. Previously these
  five forwarded to a contracted function without restating the contract, so
  the checker could not see through them: `Stats.median([])` compiled and
  panicked at run time. **What breaks:** a call with a provably empty list (or
  an out-of-range literal `q`) is now a compile error; a function that passes
  its own unrefined `List(Float)` parameter gets a "propagates a requirement
  it doesn't declare" warning (an error in a `cap verified` module). **How to
  migrate:** `march --check --refine-suggest <your_fn> file.march` prints the
  refinement to declare on your function's parameter
  (`xs : {List(Float) | len(_) > 0}`), or guard the call with `match xs do
  Nil -> … _ -> Stats.median(xs) end`, which the checker proves. `sum`,
  `count`, `variance_pop`, `std_dev_pop` and the `*_safe` variants still
  accept any list. `DataFrame`'s `Median` aggregation now yields a null value
  for an empty group instead of reaching `Stats.median` with one.
- **Reaching an actor you were never handed a Pid for now takes a capability.**
  `Actor.whereis`, `Actor.registered`, `Actor.list`, `Actor.top_by_mailbox` and
  `Actor.over_mailbox` take a `Cap(Actor.Introspect)` as their first argument, and the
  `pid_of_int` builtin is replaced by `Actor.pid_from_int(c, n)`. The cap is minted once
  from the root capability: `let c = Actor.introspect(io)` in `main(io : Cap(IO))`, then
  forward `c` (a function that takes it declares `needs Actor.Introspect`). A Pid is
  thereby an unforgeable reference: code that holds neither a Pid nor the cap can message
  nobody it was not introduced to. The raw builtins (`pid_of_int`, `actor_pid_indices`,
  `actor_whereis`, `actor_registered`) are internal to the standard library; calling one
  is a typecheck error naming the wrapper to use. `Actor.register` and `unregister` are
  unchanged.
- **`Config` values are read through typed keys (breaking).** The untyped
  `Config.put(:ns, :name, value)` / `Config.get(:ns, :name)` let a value
  stored as an `Int` be read back as any type, e.g. handed to `is_alive` as a
  `Pid` (interpreted: `is_alive: expected Pid`; compiled, every tuple-keyed
  Config call panicked in `Vault` before getting that far). A key now names
  its value type: `let port = Config.key(:myapp, :port, Config.int())` is a
  `Config.Key(Int)`, `Config.put(port, 4000)` only accepts an `Int`, and
  `Config.get(port)` is an `Option(Int)`. Storage stays heterogeneous; each
  value is stored tagged, so a key minted for the same path with a different
  codec reads `None` from `get` and `Err(Config.KeyWrongType(path, expected,
  found))` from the new `Config.fetch`, never a value at the wrong type.
  Codecs: `Config.int()`, `float()`, `string()`, `bool()`, `atom()`,
  `list(c)`, and `Config.codec(name, encode, decode)` for your own types.
  Migration: `Config.put(:a, :b, v)` → `Config.put(Config.key(:a, :b,
  <codec>), v)`; `Config.get(:a, :b)` → `Config.get(<that key>)`;
  `put_in`/`get_in`/`get_in_with_default`/`require_in`/`validate_in` →
  the same call on `Config.key_in(:a, :section, :b, <codec>)`;
  `store_put(s, :a, :b, v)`/`store_get(s, :a, :b)` (and their `_in` forms) →
  `store_put(s, key, v)`/`store_get(s, key)`; `from_env*`, `validate`,
  `get_with_default` and `require` take the key in place of `ns, key`.
  `validate`'s not-set message now names the key
  (`"Config: key :a/:b not set"`). `put_endpoint`, `endpoint_port`,
  `endpoint_host`, `secret_key_base` and `env`/`is_*` are unchanged. The old
  forms fail to typecheck (a misleading "This is not a function" on
  `Config.put(a, b, c)`: it is the arity change).
- **A malformed `forge.toml` is an error that names its line, and an unknown key is a
  warning.** forge used to drop any line it could not parse, ignore a `[section`
  header with no `]` and any text after a value, and ignore keys it did not know, so a
  typo was silently a no-op. A bad line now fails with `forge.toml:<line>: <reason>`,
  and an unknown key in a section forge reads (`[package]`, `[ffi]`, `[hot-reload]`,
  `[[hot-reload.env]]`, `[deps.<name>]`, ...) prints
  `forge.toml:<line>: warning: unknown key '<key>' in [<section>]`. Arrays may now
  span lines and end with a trailing comma, and a quoted key loses its quotes. A
  malformed TOML file read by any other forge command is reported as an error rather
  than an internal-error backtrace.
- **Tail-recursion-modulo-cons always runs; `--no-trmc` and `--trmc` are
  removed.** Passing either is now the ordinary "unknown option" error. There
  is no supported way to turn TRMC off: the stdlib's list producers are being
  written in natural recursive style, which is a loop only because TRMC runs,
  and with it off they would overflow the green-thread stack on lists of
  20k-30k elements (exit 138, no output). The `@[no_alloc]` "TRMC-eligible …
  check for `--no-trmc`" note and the flag mention in the "not in tail
  position" warning (compiler and language server) are gone with it.
- **An interpreted run of a `[ffi.rust]`-only project now says up front that
  Rust FFI is compiled-only.** `forge run`, `forge interactive` and interpreted
  `forge test` (`--coverage` / `MARCH_TEST_INTERPRETER=1`) print one warning
  naming the crate and pointing at `forge run --compiled` / `forge build` /
  `forge test`, instead of leaving only the generic "symbol not found for
  interpreter FFI" at the first extern call. Cargo's static archive cannot be
  loaded by the interpreter; projects that also have `[ffi] sources` are not
  warned.
- **A path scope that could not take effect is now a compile error instead of
  being silently ignored.** `needs IO.Network("/etc")` (only `IO.FileRead`,
  `IO.FileWrite` and `IO.FileSystem` take a scope, so this includes `needs
  IO("/srv")`; use `IO.FileSystem("/srv")`) and a relative scope such as
  `needs IO.FileRead("etc/myapp")` are rejected with an explanation.
- **Vault writes to unrelated keys no longer serialise on one lock per table.** The
  lock is now sharded by key, the way ETS partitions a table. Four threads writing
  their own keys went from 11.8x-13.1x the time of a single thread to 2.5x-3.2x,
  where serialising would be 4x; reads are unchanged. Two consequences: a table costs
  about 18 KB more, and `Vault.size`/`Vault.keys` walk shard by shard, so their result
  is a recent count rather than a single instant's snapshot of the whole table.
### Added
- **Actors can declare an `on_stop do ... end` terminate callback.** It runs
  once on a graceful stop (`Actor.stop`, a self-stop, or a supervisor's
  tree teardown), on the actor's own thread after the queued messages have
  drained, with the final `state` and `self` in scope, so an actor can flush,
  checkpoint, or hand work back before it dies. Semantics follow OTP's
  `terminate/2`: it may send (and wait on an `Actor.call`); a panic inside it
  is logged to stderr and the actor still dies normally (no restart, and a
  tree teardown carries on); it never runs on `kill`, a crash, or a
  `shutdown brutal` child; and it counts against the stop's `timeout_ms` /
  child `shutdown` budget, past which the actor is killed. Same behaviour
  interpreted and compiled. See "Stopping an Actor" in the actors chapter.
- **The type checker can reserve a builtin for the standard library.** A reference to
  a reserved builtin from user code, the REPL included, is an error that names the
  stdlib function to use instead:
  `` `pid_of_int` is internal to the standard library; use `Actor.list(cap)` ``. No
  builtin is reserved yet: the raw actor-reference builtins will be once their
  capability-taking wrappers exist.
- **A warning when a function's body fixes a type variable its signature
  names.** `fn bad(xs : List(a)) : List(a) do [0 - 5] end` used to typecheck
  silently as `List(Int) -> List(Int)`, with the mistake surfacing only as a
  mismatch at some caller. It now warns at the `a` in the signature, naming
  the type the body gave it (`Int`) with a hint to write that type or make the
  body generic. Two signature variables that the body makes equal
  (`fn second(x : a, y : b) : a do y end`) warn too. Only variables you wrote
  in the signature are checked, and not when the body already has a type
  error. The warning code is `annotated_tyvar_fixed`. Signature type variables
  are planned to become rigid later, which will make this an error.
- **A choreography role's first state now has a name: `<P>_<Role>.Entry`.** A role
  body's signature used to have to spell the state `register` yields, which meant
  working out `S_` plus the first step of that role's own projection
  (`Fan_C.S_recv_Msg_A_C_1`). Every generated role module now also declares `Entry`,
  a transparent alias for that state, so the body reads
  `st : Fan_C.Entry`. Being an alias, it is the state type at every later step: the
  linearity that stops a session being replayed or abandoned is unchanged, and each
  role's `Entry` still resolves to its own state rather than to one type shared
  across roles. The `S_` spellings keep working.
- **`Session.in_process()`: a network-free session transport in the standard library.**
  Attach it with `Session.attach(io, t.ops)`, run every role in one program, and
  `t.drain(())` to deliver. Failure paths work as on the network: a role that leaves
  cancels the peers waiting on it, an undecodable message cancels its receiver, and
  `t.crash(role, cause)` sends a waiting peer down its `or crash` branch.
  `Session.in_process_with(trace)` reports what the transport itself does, and
  `t.take(())` serves endpoints hosted in actors. Replaces the hand-written
  `Session.Ops` the guide used to point at.
- **Refinement predicates can use `/` and `%`** where March's truncating
  division agrees with the solver's: a non-zero integer-literal divisor over a
  dividend known to be non-negative, e.g. `{Int | _ >= 0 && _ / 2 < 10}` or
  `{Int | _ < len(xs) / 2}`. Violations are confirmed with a concrete
  counterexample like any other; a division outside that fragment is still not
  checked, and now says why (in a warning at the definition and in the skip
  detail).
- **`forge --offline` (or `FORGE_OFFLINE=1`) builds with no network access.**
  The global flag starts no network process of any kind (no `git clone`, no
  registry query or registry-client compile, no toolchain download, no
  `npm install`). Git and registry dependencies resolve only through
  `forge.lock` to their cached commit or version. Each cached tree is re-hashed
  against the lockfile, and a mismatch fails the build. A dependency missing
  from the cache is warned about by name and skipped. A missing `forge.lock`,
  or one that is not a lockfile, gets a single error. `forge deps --offline`
  lists each dependency as cached or missing and exits non-zero on a miss.
  `forge add` (registry or git) and `forge outdated` refuse offline.
- **forge caches registry tarballs** at `~/.march/cas/tarballs/<sha256>.tar.gz`,
  keyed by the registry's published checksum. Installing the same version again
  reuses the cached tarball instead of downloading it. Offline, a registry
  dependency whose tree was deleted is re-extracted from the cached tarball.
  Every read re-hashes the tarball, and a corrupt one is discarded instead of
  being extracted.
- **`forge.toml` `[package] pin_main = true` runs a program's `main` on the
  process main thread** (what Cocoa and GLFW need to open a window) by compiling
  with `march --pin-main`, so a double-clicked app no longer depends on
  `MARCH_PIN_MAIN=1` being set. It covers `forge build`, `forge run --compiled`,
  `forge bench` and `forge install`. forge's TOML reader now understands bare
  `true`/`false`; a non-boolean `pin_main` is an error.
- **`MARCH_PREEMPT_SIGNAL` chooses the green-thread preemption signal** (`USR1`,
  the default, `USR2`, or on Linux `RTMIN[+n]`); embedders can call
  `march_sched_set_preempt_signal`. `Signal.watch` reserves whichever signal is
  in use, so moving preemption to `USR2` makes `Signal.Usr1` watchable.
- **The hot-code-reload audit log records each deploy's capability set.** Every
  line now has `caps` and `cap_root` (`null` for deploys over pre-v4 protocols),
  so "when did this node last gain capability X" can be answered from the log
  alone, including widenings authorized with `--grant-cap`.
- **A choreography role hosted in an actor takes its crash branch.** A protocol
  that declares `may crash C` behaved one way in a role run from callbacks (the
  crash branch, the session continuing) and another in a role hosted in an actor
  (cancelled, as before crash branches existed). `resume` now returns a
  `Crashed_<Msg>` event beside the `Got_<Msg>` ones, carrying the crashed role,
  the cause and the crash branch's first state, so the actor takes the branch
  from the delivery handler it already has. `host_<Role>`,
  `offer_hosted_<Role>` and `cluster_hosted_<Role>` need no new callback. See
  `docs/choreography.md`, "When a role may crash".
- **A signature may declare an abstract refinement** — a predicate it is
  polymorphic in, Liquid Haskell style: `fn filt(xs : List(a), keep : ({x : a |
  true}) -> {Bool | _ == p(x)}) : List({a | p(_)})`. This release checks such a
  signature's well-formedness (applied to the binder in scope, one type per
  name, no nesting, and a warning when nothing consumes it) and stops reporting
  the declared name as unknown predicate vocabulary. It does not yet prove
  anything with it: `List.filter`'s result still carries no refinement, which
  is the next phase. See `specs/2026-09-20-abstract-refinements-design.md`.

- **`take_closed` on every `@[endpoints]` role module.** A session that has finished or
  been cancelled leaves a linear `Closed_<Role>` value that the actor hosting it still has
  to consume. The role module now generates `take_closed`, which takes that role's own
  `Parked_<Role>` and returns `()`, and panics if the endpoint has not finished. The guide
  previously told readers to write a one-line function with a `linear` parameter instead;
  being generic, it would drop any linear value, including a live endpoint.
- **Crash branches in choreographies.** A protocol can declare the roles that `may crash`,
  and a receive from such a role carries `or crash do ... end` (or a `crash` branch of the
  `choose` it heads): what the receiver does if that role crashes before sending. The
  receiver's generated `recv_<Msg>` takes a second callback with a live state, so the
  conversation goes on without the crashed role instead of being cancelled; other roles are
  told by the detector's messages, as for a `choose`. Six well-formedness rules are checked at
  the protocol, `Session.Ops` gains `on_crash`, and the network runner takes the branch by
  the same rule that decides a cancellation (the role is gone with nothing queued). A role
  hosted in an actor does not take crash branches yet. See the choreography guide, "When a
  role may crash".

### Fixed
- **Compiled `Map` and `Set` now use the comparator you pass.** In compiled
  code, calling a local (a parameter, `let`, pattern variable or lambda
  parameter) whose name is also a builtin or interface method (`eq`,
  `compare`, `hash`, `show`, `to_string`) called the builtin instead of the
  local. `Map` and `Set` name their comparator-derived closure `eq`, so
  compiled they compared keys with `==` and never called the comparator: a
  `Float` NaN key was never found and re-inserting it added a second entry,
  and a comparator that is not `==` behaved differently from the
  interpreter. A local of that name now shadows the builtin, as it does
  interpreted. With that fixed, a top-level function that returns a closure
  (`fn lt(a) do fn b -> a < b end`, including `Map.int_cmp` / `Map.str_cmp`)
  passed as a value and called curried no longer crashes compiled programs
  with SIGSEGV.

- **Per-role grants check the value that reaches the runner, not the expression at the
  call.** `check_role_grants` used to walk only a literal lambda or a directly named
  function; a body bound with `let`, passed through a parameter, calling a `let`-aliased
  function or a local closure was charged nothing and `--check` accepted it. The root is
  now resolved through the calling function's bindings (`let` right-hand sides, aliases,
  parameters at their call sites, call results), local closures are charged and named in
  the chain (`body → sv → save`), and a body with no static origin (a record field, a
  message) is reported as "cannot verify role grant … value not statically known" instead
  of passing silently. `--dump-role-authority` now lists the captured local closures and
  the pids the body holds. A `role R needs` naming a non-IO capability (`Session.Live`,
  `ClusterNode.Live`, `LibC`) is one error at the grant line instead of a spray of errors
  inside generated code. Corpus `reject/t295`.
- **`march --check` no longer reuses a `--no-cap-strict` verdict.** The `--check`
  fast path caches a clean verdict per source digest, but that key ignored
  `--no-cap-strict`, so `march --check --no-cap-strict f.march` exiting 0 made the
  next plain `march --check f.march` of the same source exit 0 silently instead
  of reporting the capability-ceiling error. The key now carries the cap-strict
  setting, as the `--compile` key already did.
- `to_string`/`println` of a List, Option, Result or tuple no longer aborts
  `march --jit` or the JIT REPL with an internal compiler error ("ambiguous
  interface-method call to `Show$List.show`"). The prelude's generic `Show`
  impls are now specialised at the call site, as they are under `--compile`.

- A function in a nested module that calls a function of an enclosing module
  (`mod Outer do pfn helper ... mod Inner do fn f(x) do helper(x) end end end`)
  now compiles. Before, the compiled program failed to link with `helper`
  undefined, while the interpreter ran it. This applied at any nesting depth,
  whether the enclosing function was declared before or after the nested
  module, and in `MARCH_LIB_PATH` modules, stdlib modules and the entry file
  alike. The qualified spelling `Outer.helper(x)` also now works from inside
  `Outer` for a `pfn`: it was rejected as private in a stdlib module, and in
  the same file it could bind a same-named function of the nested module
  instead. `Compress`'s internal `lift_encode_error` / `lift_decode_error`
  are private again.

- `compare` on a NaN `Float` now gives the same answer compiled as interpreted:
  NaN compares equal to NaN and less than every other value (OCaml's
  `Float.compare`). Compiled `compare` returned 0 whenever either operand was
  NaN, so NaN "equalled" everything and a sort by `compare` scattered the NaNs.
  `compare_float` now has the same order on both backends (the interpreter's
  also returned 0 for NaN). `==`, `<` and the other operators stay IEEE 754.
- **Compiling a module with no `main` no longer takes minutes.** A TIR pass
  rewrote the rest of a function twice for every non-capturing closure it
  found ineligible, so a function that builds a record of many small lambdas
  (`ClusterNode.ops_stub`) cost 2^k traversals; a compile with a `main` never
  reached it, a main-less one (`forge build` on a library, `--cap-strict`
  checks) did. Same generated code, one traversal.
- **Cluster handshake reflection.** A shared-secret node accepted a peer that
  sent the node's own hello back to it and then its own proof back; a nonce
  equal to ours is now refused.
- The stdlib-only builtin gate (`pid_of_int`, `actor_whereis`, `actor_registered`,
  `actor_pid_indices`, `epoch_hold`, `epoch_release`) now fires at name
  resolution, closing four bypasses found in review: it applies inside `impl`
  bodies, interface default methods, `test`/`describe`/`setup`/`setup_all`
  blocks and actor `init`, a `let pid_of_int = pid_of_int` alias no longer
  switches it off for its module, both REPLs (interpreter and JIT) reject the
  gated builtins, and a user file that happens to be named like a stdlib file
  (`json.march`) is no longer exempt. Stdlib-ness is now the loader's
  provenance (the file lives under the stdlib directory the compiler loaded),
  plus an explicit `--stdlib-source` flag for checking a stdlib file by another
  path, which is also part of the `--check` cache key.
- **Compiled `to_string` no longer quotes strings inside a List or Result of
  unknown static type.** When the type was erased, for example when the value
  reached `to_string` through a closure stored in a container, a compiled
  program printed `["a", "b"]` and `Ok("x")` where the interpreter prints
  `[a, b]` and `Ok(x)`. Compiled output now matches the interpreter. Strings
  inside a user constructor or record are still quoted (`B("x")`), as the
  interpreter quotes them. `~H` interpolation still quotes every nested string.
- **Floats at the JIT REPL print correctly and no longer crash the session.** Any
  Float inside a list, `Option`, `Result` or tuple printed as garbage like
  `[2.15e-313, 2.15e-313]` at the (default, JIT-backed) REPL prompt, including
  `NativeArray.to_list_float` and `to_list_f32` results and a plain `[3.5, 1.25]`
  literal; they now print their values. Separately, an expression that returned a
  Float, followed by any expression returning a list, string or other heap value
  (`3.5` then `[1, 2]`, or `NativeArray.get_float(a, 0)` then
  `NativeArray.to_list_float(a)`), killed the REPL with a segmentation fault; it now
  runs. The interpreter, `--compile` and `march --jit file.march` were not affected.
- **`forge audit --inferred` names a toolchain too old for `march caps`.** When
  the toolchain's `march` predated the `caps` subcommand (before 0.3.0), it read
  `caps` as a file name and failed, so every dependency showed as unanalyzable
  and nothing pointed at the compiler. The audit now checks the compiler before
  analyzing anything and stops with one error that gives the toolchain's path,
  its version and the version it needs. A `.march-version` pin whose toolchain
  is not installed is also an error now; the audit used to fall back to
  whatever `march` was on `PATH`.
- **Sixteen builtins that ran interpreted but failed to link when compiled now
  compile or give a clear error.** A `--compile`d call used to fail at link time
  with `Undefined symbols: _<name>` and no March location. `char_is_alpha`,
  `char_is_uppercase`, `char_is_lowercase`, `char_to_uppercase`,
  `char_to_lowercase`, `float_from_string`, `print_int`, `print_float` and `tap`
  now compile, and the compiled output matches the interpreter. The
  dynamic-supervisor queries (`Supervisor.stop_child`, `which_children`,
  `count_children`), `App.stop` and `task_spawn_link` only work in the
  interpreter, so a compiled call is now an error at the call site that says so
  and names the compiled alternative. `to_json` on a type with no `derive Json`
  now reports the missing codec even when no type in the program derives
  `Json`. `task_spawn_link(f, pid)` is now typed with the two arguments the
  interpreter takes. Before, no typechecked program could call it.
- **A zero-argument lambda is a `() -> T` everywhere.** `fn () -> 3` (or `fn -> 3`)
  in a record literal, or bound with `let` and passed on, was typed as its result,
  so it could not fill a `() -> Int` record field ("expected `() -> Int` but got
  `Int`"). It is now `() -> T` wherever it appears and `f()` calls it, on both
  backends. Passing a zero-argument named fn by bare name where a generic
  function calls it with `()` (`apply(answer)` with `fn apply(f) do f() end`) is
  now a type error; it used to crash compiled code. Also fixed: a fn with a
  required parameter after a defaulted one (`fn f(a, b \\ "x", c)`) forwarded
  the short call `f(1, 2)` with its arguments out of order.
- **Compiled `Base64.encode` and `sha256` on a `Bytes` no longer crash.** Since
  boxed constructor cells began carrying a runtime type id (0.4.0), a compiled
  `Base64.encode(Bytes.from_string("x"))`, `Base64.url_encode`/`mime_encode`, or
  `sha256(bytes)` died with `fatal SIGBUS` (exit 138): the runtime mistook the
  `Bytes` value for a `String`. The interpreter was unaffected.
- **`pid_to_int` and supervise blocks no longer leak the actor record.**
  Compiled, every `pid_to_int(p)` and `Actor.set_queue_limit(p, …)` call kept
  one reference to `p`'s actor record, and every supervise-block child was
  held two extra times by its supervisor's spawn code (the supervisor itself
  twice more), so an actor that had been through any of them was never freed
  after it stopped. They now leave the count alone.
- **`--cap-sandbox` write scopes behind a symlink no longer deny every write.** On
  macOS, `needs IO.FileWrite("/tmp/myapp")` refused even in-scope writes, because
  the kernel matches the resolved path (`/private/tmp/myapp`) and the scope was
  baked into the profile as written. The binary now resolves each scope with
  `realpath()` at startup, on the machine it runs on, before installing the
  sandbox. A scope that does not exist yet resolves through its longest existing
  parent, and a scope that is itself a symlink resolves to its target. Writes
  outside the scope are still refused.
- **`Compress` decoders and encoders return the `Compress.Error` their signatures
  promise.** They used to pass the codec's message string straight through as the
  error, so matching `Err(Compress.InvalidInput(_))` never matched. Now corrupt or
  truncated input is `InvalidInput(msg)`, hitting the decompressed-size cap is
  `InsufficientOutput`, and out of memory, a failed codec init or a library that
  was not built in is `Io(msg)`; `msg` is still the codec's message. The streaming
  functions (`Gzip.encode_stream`/`decode_stream`, `Zstd.encode_stream`/
  `decode_stream`) typecheck when you call them now: their `Seq(Bytes)`
  annotation could never match a real `Seq` and has been removed. `Brotli.encode`
  and `Brotli.encode_mode` also typecheck: the typechecker gave the builtin under
  them one parameter too few. New `Compress.lift_encode_error`/`lift_decode_error`
  expose the mapping.
- **`RRB.from_array`/`RRB.to_array` and `AhoCorasick` use the Array module's real
  type, `Array.PVec(a)`.** They were annotated `Array(a)`, a type that does not
  exist, so an `Array.from_list(...)` value could not be passed to
  `RRB.from_array`, and `RRB.to_array`'s result could not be annotated
  `Array.PVec(a)`. Write `Array.PVec(a)` where you need the type: March has no
  type-alias syntax, so `Array(a)` could not be made to mean it.
- **`Plot.save` returns `Result(Unit, File.FileError)`.** It was declared
  `Result(Unit, String)` but returned the `File.FileError` from the write, so the
  declared type was wrong. Code that matched the error as a `String` needs to match
  `File.FileError` instead.
- **`Logger.with_scope`'s body typechecks.** The builtin `try_finally` under it was
  typed as passing its callbacks an `Int`, which matched neither backend and
  rejected the `() -> a` thunk `with_scope` takes. It is now typed `() -> a`.
  Callbacks written `fn _ -> ...`, which is every existing caller, are unaffected.

- **`forge bench` now links a project's FFI code.** Benchmarks were compiled
  without the `[ffi]` C sources/link flags and `[ffi.rust]` archive that
  `forge build`, `forge run` and `forge test` pass, so a benchmark calling any
  extern failed to link (`Undefined symbols`) while the same code built and
  tested fine. A `[ffi.rust]` cargo build failure is now reported once, before
  any benchmark compiles.
- **Spawning a nested actor from its parent module compiles.** `spawn(Inner.Box)`
  written outside `mod Inner` passed `--check` and ran interpreted, but `--compile`
  failed to link with `Undefined symbols: "_Inner.Box_spawn"`. It now links and runs.
  A `mailbox N policy` declared on such an actor is also applied at a qualified spawn;
  before, it was silently skipped there.
- **A dead actor's metadata is now returned, and sends no longer slow down
  after actor churn.** Each actor's runtime bookkeeping (about 300 bytes) used
  to be kept for the life of the program, and it stayed on the lookup path of
  every `send` and `Actor.call`, so a node that had churned 200,000 short-lived
  actors took 3 seconds instead of 45 ms to send 200,000 messages to one
  long-lived actor. It is now freed once no other thread can still be reading
  it, leaving a 56-byte record per pid for what a dead pid can still be asked
  (its terminal reason, `Pid(n)` display, capability epoch): 200,000 churned
  actors retain 18.5 MB instead of 65.6 MB, and send speed no longer depends on
  how many actors have died. `Scheduler.stat(10)` counts freed actor metadata
  and `stat(11)` that waiting to be freed. `Actor.pid_from_int` on the pid of an
  actor that has died now returns a dead Pid; it used to return a pointer to
  the dead actor's record, which could already have been freed.
- **A protocol `choose` branch can now continue with a labelled message step.** A branch
  body line such as `tick: A -> B : Int` after the branch's first message was read as the
  start of the next branch and failed with "I got stuck here"; it now continues the branch,
  as an unlabelled `A -> B : Int` line already did.

- **Fourteen stdlib wrappers over builtins the typechecker did not know now
  typecheck**, and the interpreter and compiled backends agree on each.
  `System.os()`/`System.arch()` return a lowercase `String` (`"macos"`,
  `"aarch64"`), and misusing one is a type error instead of a runtime crash;
  compiled programs calling them previously failed to link. Compiled
  `Crypto.sha512` returned the SHA-256 digest, compiled `UUID.v5` crashed with
  SIGBUS, compiled `IO.warn`/`Logger.appender_stderr` printed a blank line after
  every message, and `System.version()` said `march/dev` compiled and `0.1.0`
  interpreted; it now reports the compiler's real version in both. Compiled
  `IO.read_line` no longer splits lines longer than 4096 bytes. `print_stderr`
  now requires `IO.Console`, like `print`.
- **`csv_next_row`'s result now matches against `CsvEof` / `Row`.** The builtin
  is typed with the qualified `Csv.CsvRow`, and builtin signatures skipped the
  qualified-to-bare canonicalization that written type annotations get, so
  matching its result against the bare constructors was a type error both ways.
  `stdlib/csv.march` carried 12 such errors, hidden because stdlib diagnostics
  are filtered, which left `Csv.each_row`, `Csv.read_all` and
  `Csv.each_row_with_header` unchecked. Builtin signatures now go through the
  same canonicalization, so any future builtin typed with a qualified name is
  covered too.
- **Two modules can each name their capability dictionary `Ops`.** A
  `proof cap X with T` resolved `T` by its bare name first, so when two modules
  each declared a same-named dictionary record, one module's `cap_impl` /
  `cap_dict` bound to the other's record and failed with "expected `Ops` but got
  `Ops`" (or, worse, accepted the other module's fields). The declaring module's
  own record now wins.
- **A nested module can use its own `proof cap` without declaring it in
  `needs`.** `proof cap Key` in `mod Vault` has always meant `Vault` may take a
  `Cap(Vault.Key)` without also writing `needs Vault.Key`, but that only worked
  when `Vault` was the file's top module. Nested inside another module, every
  such use was rejected with "`Cap(Vault.Key)` used in module `Vault` but
  `Vault.Key` is not declared in `needs`". Uses from any other module still
  need the `needs` line.
- **A finished task or a dead actor no longer keeps its process record
  forever.** Every green thread's bookkeeping record (256 bytes) used to be
  kept for the life of the program once the thread ended, so a server that
  churns tasks or actors grew without bound: 400,000 awaited tasks held
  about 120 MB, and each dead actor about 600 bytes. The record is now freed
  once no other thread can still be reading it, so the same 400,000 tasks
  peak at about 23 MB and a dead actor costs about 350 bytes (the actor's
  own metadata is the remaining term, still to come). `Scheduler.stat(8)`
  counts records freed and `stat(9)` those waiting to be. An `Actor.reply`
  whose caller has already given up and exited is now dropped cleanly, as
  is a reply to a value that is not a reply reference.
- **A self-stop in the interpreter now drains like the compiled backend.**
  `Actor.stop(self, t)` from a handler used to kill the actor on the spot in
  `march run`, discarding its queue and the state the handler was about to
  return; it now finishes the handler, drains, and then dies, as compiled
  binaries already did.
- **`OrderedMap.keys`, `OrderedMap.values` and `OrderedMap.from_list` work.**
  All three passed a two-parameter lambda where a pair callback was expected
  (and `from_list` had `List.fold_left`'s arguments in the wrong order), so
  they returned a list of functions: `List.each(OrderedMap.values(m), println)`
  failed with "expected `a -> a` but got `String`" at the caller's own line.
  The test meant to catch this typechecked `ordered_map.march` in isolation,
  where a call into another stdlib module resolves to an unconstrained type
  variable and checks nothing; it now typechecks each file inside the whole
  stdlib, as the compiler does. `values` was found independently by the new
  `annotated_tyvar_fixed` warning, which saw the signature's `v` fixed to a
  function type; annotating a call (`let vs : List(String) =
  OrderedMap.values(m)`) was rejected outright.

- **A `MARCH_SANITIZE=1` compile no longer returns a cached ThreadSanitizer
  binary.** The compile cache recorded only *whether* `MARCH_SANITIZE` was
  set, not which sanitizer it selected, so building a program with
  `MARCH_SANITIZE=thread` and then with `MARCH_SANITIZE=1` printed
  `compiled ... (cached)` and handed back the TSAN build instead of an
  ASan+UBSan one. Anything checked that way was checked by the wrong
  sanitizer. The cache key now includes the sanitizer, so the two builds are
  cached separately. Each such key changes once, so the first sanitized build
  after upgrading is not a cache hit.
- **`forge deploy hot` builds the same entry file as `forge build`.** `forge build`,
  `check` and `run` defaulted to `lib/<name>.march` and the hot-deploy build step to
  `src/<name>.march`, so a project that built could not be hot-deployed without an
  explicit `entrypoint`, and the other way round. Every forge command now uses
  `[package] entrypoint` if set, else the first of `lib/<name>.march` and
  `src/<name>.march` that exists, and reports a missing entry the same way.
  `forge install` and `forge interactive` now honour `entrypoint` too.
- **Renaming a linear value with `let` no longer lets it be dropped.** In
  `fn f(linear h : Res) ... let h2 = h`, the rename consumed `h` but left `h2`
  ordinary, so `h2` could be ignored with no error. `h2` now takes over `h`'s
  obligation and must be used exactly once, whether `h` is a `linear` parameter
  or a `linear let` local.
- **A protocol whose payload types differ in their DEFINITIONS is now caught when
  the session is set up, not as an undecodable message once it is running.**
  `<P>_Msg.fingerprint()` digested each payload type by NAME, so two nodes whose
  `Thing` was `{ x : Int }` on one and `{ x : String }` on the other shared a
  fingerprint: the session formed and the skew surfaced mid-session, on the
  receiving side, as `Protocol(role, "undecodable message: ...")`. The digest now
  folds a payload type's definition in, recursively, for every type declared in
  the same module — a variant's constructors and a record's fields in declaration
  order, with type parameters substituted. A payload type from ANOTHER module is
  out of reach when the digest is computed and is still recorded by name (marked
  `extern:` so the digest at least says the definition was unavailable), so a
  change below such a type's name remains invisible to the check.
  **Compatibility:** every fingerprint changed. A node built before this change
  and a node built after will now refuse each other at the access point — and, on
  the direct runner, at the handshake. That is the check working, not a
  regression; rebuild both sides from the same source.
- **The direct runner (`<P>_Run.run_<Role>`, `host_<Role>`, `host_<Role>_or`) now
  exchanges the protocol fingerprint too, not only access points.** It rides the
  session hello as an optional trailing field, so a node built before this change
  is read rather than deadlocked on — and is refused with a message saying it sent
  no fingerprint. A mismatch is a setup error (`Connect`/`Accept`) naming both
  fingerprints, not a retry loop. The cluster runner (`cluster_<Role>`) finds its
  peers through the cluster registry rather than a hello and is NOT yet covered;
  an access point still checks every cluster session it brokers.
- **Compiled `send_checked` and `is_cap_valid` no longer intermittently accept a cap
  whose actor was killed.** About one run in five, a cap taken while the actor was
  alive still validated after `kill`: `is_cap_valid` answered `true` and
  `send_checked` returned `:ok`, and the message went into freed memory. The
  interpreter was always right. Both now check the actor's runtime metadata instead
  of its (possibly freed) record, and `send_checked` returns `:ok` only when the send
  was actually accepted.
- **On Linux, `--cap-sandbox` now stops a program without `IO.NetListen` from
  accepting connections.** Holding only `IO.NetConnect` (an HTTP client, say)
  allowed `socket()`, and nothing denied `bind`/`listen`, so such a program
  could still open a listener. Both are now denied unless `IO.NetListen` is
  held; connecting is unaffected. macOS does not separate the two yet.
- **A scheduler thread that cannot be created is reported instead of crashing the program at
  exit.** Under a process/thread limit (a container `pids` limit, `ulimit -u`) a compiled
  program could run to completion and then die with SIGSEGV while joining a thread that was
  never started. It now prints how many scheduler threads it is running on and carries on
  with those.
- **A hot deploy that changes an actor's state no longer runs new handlers on
  old state.** Messages already in an actor's mailbox when the deploy landed
  were handled by the new code against the old-shaped state, which could read
  the wrong fields. Now they finish on the old code, and the actor runs
  `migrate_state` and switches to the new code when it reaches them. Old
  messages still waiting after a drain deadline (5 s, or `MARCH_HCR_DRAIN_MS`)
  are dropped and reported on stderr. A second schema-changing deploy is
  refused until every actor has switched. Also fixed: with more than 2048 live
  actors of a type, the ones past the 2048th were never migrated at all. See
  `docs/hot-code-reload.md`, "Messages queued during a deploy".
- **forge finds a dependency's own dependencies again under the version-keyed
  cache.** `forge deps` looked for an installed registry package's `forge.toml`
  in the old flat `deps/<name>` directory, so it never installed that package's
  own dependencies. The build's transitive walk ignored `forge.lock`, so it
  dropped the dependencies of any dependency that had more than one version
  cached.
- **A refinement check on an argument that multiplies two variables is no longer
  skipped.** `need_pos(y * y + 1)` against `{Int | _ > 0}` was reported as
  "the argument could not be translated to SMT", even though predicates and
  postconditions already accepted the same product. It now proves, so
  `List.map(ys, fn y -> y * y + 1)` meets a positive-element demand too. A
  product that really breaks the contract (`need_pos(y * y - 1)` under
  `y == 0`) is reported with a counterexample. A product goal the solver cannot
  settle is skipped with the reason `nonlinear-goal`.
- **A function with a default argument no longer inherits the capabilities of an
  interface method with the same name.** In a module that declares both an
  interface method `f` (with a default body, or implemented by an `impl`) and a
  plain `fn f(x, y \\ 1)`, the inferred capability closure of the pure `f`, and
  of every function calling it, picked up whatever the method's body used (for
  example `IO.Console`). The non-defaulted case was already handled correctly.
- **`float_nan`, `float_infinity`, `float_neg_infinity`, `float_epsilon`,
  `float_is_nan`, `float_is_infinite` and `typed_array_slice` now work in
  compiled programs.** They typechecked and ran interpreted, but `--compile`
  failed at link time with `Undefined symbols: _float_nan` (and so on). The
  compiled results match the interpreter exactly, including the NaN bits and
  `typed_array_slice`'s clamping of out-of-range bounds. A new test fails when a
  typechecked builtin has no compiled lowering and is not explicitly listed as
  interpreter-only.
- **`forge fix --contracts` no longer breaks a function whose `doc` string
  shares its line.** On `doc "…" fn f(…)` (or `@[attr] fn f(…)`) the fix put
  `@[no_alloc]` on the line above, in front of the `doc`, and the file stopped
  parsing. It now goes inline, just before `fn`. A function whose `fn` starts
  its own line still gets the attribute on the line directly above it, below
  any `--` comment block and after the `doc` string, which is how the stdlib
  writes it.
- **`--refine-report` and the compiler's errors now agree on inductive
  postconditions.** For a recursive function over a list or tree, the report
  could count a postcondition as `violated` while the program compiled cleanly,
  including for true contracts such as a `copy2` that walks a list two elements
  at a time. A violation now counts only when running the function reproduces it,
  and it is then reported as an error naming the failing call (for example
  `grow([]) returns []`). Anything the checker cannot reproduce is counted as
  skipped (`refuted-unconfirmed`). Relatedly, an inner pattern that reuses an
  outer name (`Cons(h2, t)` inside the arm that bound `t`) no longer lets a false
  contract count as proved; that return is now skipped.
- **A linear value can no longer be discarded with `let _ = …`.** A `_` binding
  counted as the value's one use whenever the value was linear because of how it
  was *bound* rather than what its type says — a `linear x : a` parameter or a
  `linear let` local, whose type stays a plain type variable or `Int`. One generic
  `fn launder(linear v : a) : () do let _ = v  () end` was therefore enough to drop
  any linear value in the program, silently. A wildcard is not a use: such a `let`
  is now rejected, naming the value and pointing at how to consume it (for a session
  endpoint, the generated `take_closed` / `take_idle`). Session endpoints keep their
  own, narrower rule — only a `Chan` that reached `End` must be closed, so a
  mid-protocol drop is still legal. See `docs/linear-types.md`.

- **A watched signal no longer crashes a compiled program on Linux/aarch64.**
  Any signal handled by the runtime (`Signal.watch`, or SIGTERM/SIGINT while an
  HTTP server is listening) could arrive on a green thread's small stack, and
  an arm64 Linux signal frame does not fit there. `Signal.raise` of a watched
  signal died every time with `fatal SIGSEGV si_code=128 addr=0x0`. The
  handlers now run on the scheduler thread's alternate signal stack.
- **March no longer takes over a host process's SIGUSR1.** Preemption replaced any
  existing SIGUSR1 handler for good, so March embedded in another program (the
  Erlang VM uses SIGUSR1 for crash dumps) silently disabled the host's handler.
  The previous handler is now called for every signal that is not one of
  March's own preemption ticks, and it is restored when the scheduler stops.
- **On macOS, `--cap-sandbox` now stops a program without `IO.Process` from
  executing another program.** The embedded sandbox profile allowed `exec`
  unconditionally and only gated `fork`, so such a program could still replace
  itself with an arbitrary binary (directly, or through `extern` C). `exec` is
  now granted only with `IO.Process`, as it already was on Linux. `forge cap
  run` is unchanged: its wrapper has to exec the target, so it still allows it.
- **A hot-code-reload publish could unload a version while a caller was entering
  it.** Reclaiming an old version's ring slot closed its shared object before
  marking the slot retired, so a caller that had just passed the liveness check
  could pin it and call into code being unmapped. The slot is now retired first,
  and the object is closed only if no caller pinned it in the meantime.
- **Re-registering a `Signal.watch` watcher could lose a signal delivered during
  the call.** The pending flag was cleared after the new watcher was installed,
  so a delivery in between was erased. It is now cleared first.
- **A false postcondition could be proved when a `match` reused a name.**
  Structural induction trusted a variable as a component of the matched value
  by its name alone, so `Cons(_, t)` in a `match` on a *different* list was
  treated as a smaller piece of the first one: `copy(xs, ys) : {List(Int) |
  len(_) == len(xs)}` proved while `copy([1], [5, 6, 7])` returns three
  elements. The same hole let a `@[measure]` that recurses forever pass the
  termination check. A name is now trusted only when every binding of it is a
  structural one.

- **`march --emit-core-ast` now reports the same verdict as `march --check`.** A program
  rejected only by an allocation contract (`cap no_alloc`) or by the stdlib-mediated
  capability ceiling was emitted as `"verdict":"accept"` with exit 0, and without the
  diagnostic, while `--check` rejected it. Both are now folded into the JSON's verdict and
  `"diagnostics"`.
- **`file_close` and `csv_close` return `:ok` compiled, as they always did interpreted.**
  Compiled code returned a heap `Ok(())` cell, so `csv_close(h) == :ok` was `false` and
  the result printed as `:<atom>`. `file_close`'s declared type changes from `Unit` to
  `Atom` to match; code that ignores the result is unaffected. A second `file_close`
  on the same handle is now a no-op rather than a double close.
- **Two mutually tail-recursive functions passing a string or list along no longer read
  freed memory.** The compiled mutual-tail-call loop released a forwarded argument on the
  back edge, one iteration before its next read (`refused: no-y; refused: no-y` for an
  accumulator built from `"no-x"`, `"no-y"`; a heap-use-after-free under ASAN), and the
  naive fix (skip the release) leaked it instead. A group whose back edge would drop a
  forwarded argument is now compiled as ordinary calls; groups that forward only
  integers or borrowed list cells keep their loop.
- **A choreography payload type without a JSON codec is a check-time error.** A type
  declared in the module and used as a message payload without `derive Json` used to pass
  `march --check`, fail the compile with an internal "ambiguous interface-method call", and
  panic the interpreter at the first message. The error now names the step and the type.
- **Session-state type errors explain themselves.** A step called in the wrong state
  (`expected `S_recv_...` but got `S_send_...``) now says both are states of a generated
  role, what `S_<step>` means, and that the cause is either the protocol's order or a body
  run as the wrong role; a callback that returns a state instead of `Yield` is told to
  `close`.
- **Two choreography nodes with different secrets fail at once, and say so.** The dialing
  side kept retrying after the listener rejected its handshake and reported "Connection
  refused" at the end of the setup time; it now stops on the rejection and asks whether
  both nodes run with the same secret.
- **A lambda passed before the value it receives can no longer drop a linear value.**
  `ap2(fn s -> 0, S1(1))` was accepted while the same call with the arguments the
  other way round was rejected: the lambda was checked before its parameter's type
  was known and then never checked again. It is now rejected ("The linear value `s`
  was never used").

- **`linear x : a` now requires every parameter holding an `a` to be marked.** In
  `fn f(linear x : a, y : a)`, callers could pass a linear value for `y` too, but
  only `x` was checked, so the body could drop or duplicate `y`. Such a parameter is
  now an error that says to mark it `linear`. A function-typed parameter such as
  `k : a -> Int` needs no mark.

- **One slow choreography session no longer holds up the others between two nodes.** A
  frame for a session that was not set up yet made the node's shared reader poll for it,
  up to 10 seconds, while every other session's frames waited. Such a frame is now held
  by its own session. This also fixes a session whose first message arrived before its
  handler and was never delivered.
- **A cluster session gives up on a peer that stops reading.** Session frames queue
  without limit so none is dropped, and cluster mode has no heartbeat to notice a peer
  that is alive but not reading. Past `MARCH_SESSION_QUEUE_MAX_BYTES` (64 MiB by
  default) queued for a peer, the session treats it as gone.
- **On Linux, a refused `tcp_connect` / `Socket.connect_timeout` now says it was refused.**
  After a connect that had to wait, the error often read `Interrupted system call` (or
  `Success`) instead of `Connection refused`, because the outcome was read back from the
  wrong thread's `errno` once the waiting task resumed on another scheduler thread. A
  cluster node relies on that text, so a crashed peer was declared dead only by SWIM's
  suspect timeout, seconds later, instead of at once by the refused redial.
- **A discarded `task_await` now waits in compiled code.** `let _ = task_await_unwrap(t)`,
  an unused `let x = task_await(t)` and similar were deleted by the optimizer, which
  wrongly took the await builtins for pure: compiled programs ran on without waiting,
  while the interpreter waited. Other effectful builtins (file and directory writes,
  sockets, task cancellation, process control, in-place array writes, `panic`) were
  also treated as pure and are now protected by family-wide rules.
- **A type annotation on a module-level `let` is now checked.** `let x : Int = "hello"`
  directly inside a `mod` used to be accepted, because the annotation was ignored there
  (a `let` inside a function body was always checked). It is now an error
  (``expected `Int` but got `String` ``), so code with a wrong module-level annotation
  will stop compiling.
- **A choreography role that works for a long time before its first message is no longer
  taken for dead.** Heartbeats used to start only once a role reached its first send or
  receive, so one that computed past the heartbeat timeout (10 s by default) before then
  had its peers cancel the session. They now start as soon as the nodes connect. The
  choreography guide also now says that callbacks and cancel handlers must return, and
  that `host_<Role>` must not be called from inside the host actor's own handlers.

- **A choreography role no longer waits for ever for a peer that never connects.** The
  role runner's accept had no deadline, so a listening role whose peer never started, or
  failed its own setup, waited indefinitely, and with three or more roles one failed
  node could hold the rest. Setup now gives up after 20 seconds
  (`MARCH_SESSION_CONNECT_MS`) with an error naming the missing roles, and a role that
  fails setup closes the connections it already made so its peers fail promptly too. A
  peer that connects and then says nothing is refused the same way. New builtin
  `tcp_accept_timeout`, new `ClusterConn.accept_split_within` /
  `connect_split_within`, and `tcp_recv_exact` now honours `tcp_set_recv_timeout`.
- **`Actor.call` from inside an actor's handler no longer steals the actor's messages.**
  A message sent to the calling actor while it waited for the reply was returned as the
  call's answer (a meaningless number) and never reached its handler. Such messages now
  wait in the mailbox, in order, and are handled once the handler returns. The
  interpreter, which instead ran them in the middle of the waiting handler and lost their
  state changes, behaves the same way now. `NodeQueue.BlockSender` is safe to use in a
  handler.
- **Choreography sessions no longer lose messages or hang on large ones.** A message over
  4 KB was silently refused, which left both nodes waiting on each other forever, and a
  burst of messages lost most of them while both sides still reported success. A message
  just over 3 KB following a small one could also hang. Messages of any size and any burst
  now arrive; a sender never waits, and a peer that stops reading is dropped by the
  heartbeat. `NodeQueue` gains an `Unbounded` policy and accepts a message larger than its
  whole budget when the queue is empty.
- **A record or actor-state field that holds a linear value is now tracked like a linear
  field.** A field such as `slot : Option(Parked_B)` used to be an ordinary field: an actor
  could overwrite it with `None` and silently drop the value inside, and a record's field
  could be read twice. Both are now errors, as they already were for a field whose own type
  is linear.

### Documentation
- **Agent debugging guidance.** A `march-debug` skill maps each symptom
  (compiled/interpreted divergence, crash, leak, slow compile, stale cache, red
  CI, "prove this refactor moved nothing") to the first command and how to read
  it; a `steward` skill records the known CI flakes and the one-re-run policy,
  how to find the real failure in the macOS `all` log, and what CI enforces
  (including registering a new `bench/*.march` in `test/test_bench_gate.ml`).
  `CLAUDE.md` gains a short "When something breaks" pointer, and a hook prints a
  one-line hint after a failed compile, test or build. doc-lint now also checks
  `scripts/*.sh`/`*.py` pointers in the current docs and the skills.
- **Data-race freedom, written down.** `actors.md` says what a message may
  carry (a linear value moves, everything else is immutable or copy-on-write),
  `linear-types.md` has a `RingBuf` section and the module-level `let` rule,
  `memory-model.md` states the acquire-ordering guarantee behind every in-place
  write, and `parallelism.md` says which captured values parallel code may touch.
- **Observing a running node** (`docs/observe.md`), an operator's guide to the
  observe socket and `forge observe`/`top`/`status`/`diagnose`: turning the
  socket on and what it costs, the protocol and error codes, every verb with a
  real reply and what each actor-row field means, the forge commands' flags and
  exit codes, each `forge diagnose` finding with its exact threshold and what to
  do next, `Recon` and `Diagnose` from March code, a worked "a node is slow"
  incident, and the interpreter's differences. The section in `docs/tooling.md`
  is now a short summary linking to it.
- **Choreography** reference (`docs/choreography.md`): the test-script example used a
  constructor (`Expect_Msg_Prod_Cons_1`) that does not exist for the labelled `Stream`
  protocol (now `Expect_Item`), and the offer example passed a `RunError` to `panic`. The
  session-outcome table now lists `NoOffer`, `AlreadyOffered` and `Unauthorized`. Two stale
  limits are gone (roles may share a cluster node; hot patches no longer carry their own
  runtime). The page also gains a reading guide, the full `Stream` protocol and role B,
  and a separate "Certificate mode" section; "Per-role grants" moves after the walkthrough.
- **Cluster certificates** operator guide (`docs/cluster-certificates.md`):
  keys, issuing, configuring nodes, renewal, revocation, what the MAC does and
  does not protect. The clustering reference's "Authentication & Handshake"
  section covers both modes, the per-frame MAC and the threat model.
- **The actors chapter now documents `Actor.stop`** (graceful, synchronous,
  reverse-order supervisor teardown), which shipped 2026-09-08 without a
  section of its own.
- **A design for distributed authority, topology and hot deploys, and its groundwork
  plan** (`specs/plans/2026-09-21-distributed-authority-and-deploys-plan.md`,
  `specs/plans/2026-09-21-distributed-deploys-groundwork-plan.md`). The remaining
  build steps are filed as `specs/todos/2026-09-22-dd-*.md`.
- **A capability's dictionary type must be monomorphic, and the capabilities chapter now says
  so.** `proof cap Live with Ops` cannot attach a parameterised `Ops(m)`; the "Runtime
  dictionaries" section explains the limitation and the way around it (a concrete
  representation at the boundary, as `Session.Ops` does with `Bytes`).
- **The language-reference pages on march-lang.org are now generated from
  `specs/lang/`, and the two copies have been reconciled.** Each chapter used to exist
  twice, as independent prose that had drifted both ways, so corrections made in one copy
  never reached readers of the other. The published pages gain sections that had existed
  only in the spec, including supervision restart types and graceful stop, the
  `cap no_panic` division section, and loop/stop session protocols. Several claims that
  were wrong in one copy or both are corrected:
  - an unhandled `offer` branch is a compile error, not a warning;
  - compiled `MPST` programs run;
  - interface method names can be module-qualified in compiled code;
  - supervisor backoff doubles from `2 × base`, at most 7 times;
  - `pmap` stays sequential for a list of exactly the threshold length;
  - the `opaque type` constructor bypass is closed;
  - `docs/types.md`'s `parse_int` example now typechecks.

  Edit `specs/lang/`, run `scripts/gen-lang-docs.py`, and commit both. Doc-lint fails on a
  hand-edited or stale `docs/` chapter.

### Changed
- Cluster membership records a node's creation, name and advertised address: a restarted
  node outranks every verdict about its previous life, and `GlobalRegistry` bindings carry
  the holder's creation (a binding from before a restart no longer names whatever process
  now has that pid). `GlobalRegistry.unregister_own` removes a binding only if it is yours.
- **A choreography session no longer ends for everyone when one role fails.** Following the
  Maty model (Fowler and Hu, OOPSLA 2026), a failed role is cancelled, and another role is
  cancelled only if it was waiting on it with nothing from it still queued; a role that no
  longer needs it carries on and can finish. Cancellation spreads to exactly the roles that
  depend on it. `SessionNode.RunError.PeerGone` is replaced by `Cancelled(role, cause)`,
  where `cause` traces the failure back to where it began, and `Left(why)` is new.
- A peer that stops answering without closing its connection (hung, paused, partitioned) is
  detected by a heartbeat (`MARCH_SESSION_HEARTBEAT_MS`, `MARCH_SESSION_TIMEOUT_MS`).

### Added
- **Hosted access points: one actor serving many choreography sessions.**
  `<P>_Run.offer_hosted_<Role>(io, node, capacity, actor, start, deliver, cancel)` offers
  a role over a cluster node with every accepted session hosted in one actor, which keeps
  one `Parked_<Role>` per session id in a `LinearMap`; the callbacks carry the session id
  (`start(sid, s)`, `deliver(sid, s, from, msg, ep)`, `cancel(sid, s, role, cause, ep)`).
  `cluster_hosted_<Role>(io, node, session, actor, ...)` is the same for one session under
  an agreed id. `SessionNode.offer_hosted` and `run_cluster_hosted` underneath. The guide's
  "Many sessions in one actor" shows the actor shape.
- **A protocol step can name its message.** `item: Prod -> Cons : Int` makes every
  generated name say `Item` (`send_Item`, `recv_Item`, `S_recv_Item`, `await_Item`,
  `Got_Item`, `Stream_Msg.Item`) instead of `Msg_Prod_Cons_1`. Unlabelled steps keep their
  names exactly. A label on a `choose` branch's head message (the branch label already
  names it) and a label spelling a synthesised `Msg_` name are errors; two steps may share a
  name when their payloads agree and no single role takes both, and a role that would get
  two functions of one name is now told so instead of the second silently shadowing the
  first. Renaming a step changes the protocol's fingerprint.
- **`<P>_Run.error_message(e)` and `<P>_Msg.role_name(n)`**: a `RunError` spelled with the
  protocol's role names instead of numbers. `offer_<Role>` now returns `RunError` like the
  other entry points (`AlreadyOffered(role)` when the node already offers that role).
- **Choreography access points: a node can offer a role for many sessions.**
  `<P>_Run.offer_<Role>(io, node, capacity, body)` offers a role on a cluster node, and
  `<P>_Run.initiate_<Role>(io, node, body)` starts one session, minting a fresh session id
  and inviting one offer of each other role. An offer refuses when it is full, closing, or
  built from a different version of the protocol (protocols now carry a fingerprint); the
  initiator then tries the next one, and reports `NoOffer(role, why)` if a role cannot be
  filled. After a failure a supervisor restarts the program, it offers again, and the next
  session forms with no cross-node coordination.
- **`ClusterNode`, a running cluster node**: `ClusterNode.start(config)` joins from seed
  addresses, keeps one authenticated connection pair per peer, runs SWIM failure detection
  continuously, learns every peer's advertised address from gossip (so a node reaches peers
  it was never configured with), and reports peers up / suspect / dead / rejoined to
  `subscribe`rs. A connection that closes is a hint; a refused reconnect or SWIM's timeout
  is a death; a dead peer that comes back is reconnected and rejoins. Names:
  `ClusterNode.register / unregister / lookup / watch` keep a live cluster-wide registry;
  a dead or restarted holder's binding is hidden, and after a partition heals one binding
  wins everywhere and the loser's watchers hear `Lost`. A global name is not a lock.
  Messages: `ClusterNode.route / send_msg / queue_for / monitor_remote / on_peer_closed`
  carry actor messages, remote monitors and flow control over the same connection pair.
  Choreographies: `<P>_Run.cluster_<Role>(io, node, session, body)` runs a role over the node,
  finding its peers by name, sharing the node's connections, and using the node's failure
  detector instead of a per-session heartbeat.
- `Socket.connect_timeout(host, port, ms)` (builtin `tcp_connect_timeout`): a connect that
  gives up after `ms` when the peer never answers, instead of waiting out the kernel's SYN
  retries (a minute or more behind a dropped-packet partition).
- **Element refinements flow through expressions, callbacks and polymorphic combinators.**
  A `List({Int | _ > 0})` (or `Option`, `Result`, user variant) contract is now met by
  `sum_pos(List.take(xs, 2))` without a `let`, by `match List.head_opt(xs) do Some(h) ->`,
  by a call to a function whose declared container return was proved, by a return tail
  that names a local `let`, and by `List.map(ys, f)` / `flat_map` / `filter_map` /
  `Option.map` when every way an element can enter the call meets the demand (a lambda
  passed where the element type is taken also gets its source's element refinement as a
  fact). A hand-written refined `map` proves through its callback's codomain and its
  structurally recursive self-call, and a lambda that breaks a declared refined codomain
  (`fn y -> y - 1` where `(Int) -> {Int | _ > 0}` is expected) is now reported with a
  witness instead of skipped. A call whose sources do not all meet the demand is a skip
  with the new `--refine-report` reason `parametric-source-unproved`, never an error
  outside `cap verified`.
- **Failure handlers in the generated session API:** `recv_<Msg>_or` and `offer_<…>_or` take a
  cancel handler that learns which role failed and why but holds no session state, so it
  cannot talk in the failed session. Also `leave_<state>` to leave a session on purpose,
  `cancel(parked)` for actor-hosted roles, and `<P>_Run.host_<Role>_or`.
- **`LinearMap`, a keyed collection for linear values** (`stdlib/linear_map.march`). A
  `Map` cannot hold a linear value; `LinearMap(k, v)` can, checked statically: every
  operation consumes the map and hands it back, `put` returns the value it displaced,
  `take`/`take_slot` are the only ways a value leaves, and the map (itself linear) ends in
  `drain`, `to_list` or `dispose`. An actor hosting several sessions can keep one parked
  session per id in its state. Also `always_linear opaque type`, a linear type with
  private constructors.

### Fixed
- **A compiled list-building loop could corrupt a list it did not own.** A function of the
  shape `Cons(h, f(t, ys))` (compiled to a loop, "tail recursion modulo cons") walking a list
  whose cells were shared with another holder reused those cells in place. The smallest case
  is appending onto the result of an earlier append twice; in the standard library,
  `Msgpack.encode` of the same `Msgpack.bin` payload twice. It crashed or returned garbage;
  `--no-trmc` was correct.
- **A compiled program could double-free a field read three records deep** (`st.a.b.c`)
  and passed to a function that consumes it: the second such read crashed or read freed
  memory. Two levels deep was fine.
- **A library module without a `main` is no longer charged `IO.Console` for a
  function name it shares with the stdlib.** `march --compile` on a three-line
  module declaring `fn add` failed with "uses `IO.Console` but does not declare
  `needs IO.Console`", because the capability check treated `BigInt.add`,
  `Set.add` and the other stdlib functions named `add` as the module's own.
  `forge fix --contracts` no longer needs to switch the check off to work around it.

- **`forge publish` no longer lets a breaking change ship as a patch when a
  function has no return-type annotation.** Changing what such a function
  returns was invisible to the semver check, so it certified the release as a
  PATCH. A body change to an unannotated public function now requires a major
  version (for packages at 1.0.0 or later), and the error names the function.
  Annotate the return type to get a precise verdict instead.

- **`MARCH_STDLIB` now applies to every stdlib lookup.** A `march` run through a
  symlink with `MARCH_STDLIB` set could fail to build a hello-world program with
  an error about a stdlib module the program never used (`ConsistentHash.get`).
  Part of the compiler ignored the override.

- **The REPL no longer runs on another checkout's parsed stdlib.** The
  parsed-stdlib cache in `~/.cache/march` was keyed on the stdlib's text and the
  compiler build but not its location, so two checkouts of March with the same
  stdlib shared one cache entry, and the second ran on the first's parse. Under
  the REPL/JIT this gave wrong answers — `Path.is_absolute("/etc")` returned
  `false` on macOS — that appeared and disappeared with unrelated edits.

- **Refinement checker: a polymorphic function no longer lends element refinements it
  cannot justify.** A function whose signature says `List(a) -> List(a)` but whose body
  fixed `a` (type variables in signatures are not rigid), merged it with another variable,
  took it through an unannotated parameter, or can create one through a builtin such as
  `from_json`, was trusted to preserve its argument's element refinement: `let ys =
  bad(xs)` then `sum_pos(ys)` was reported proved on a list holding `-5`, and `cap
  verified` accepted it. Likewise `append(pos, neg)` took the first list's element
  refinement for the whole result. The checker now reads the inferred parameter types and
  the callee's body, and requires every argument an element can come from to agree,
  before applying the rule; such calls are skipped instead.
- **A record or actor-state field that holds a linear value is now tracked like a linear
  field.** A field such as `slot : Option(Parked_B)` used to be an ordinary field: an actor
  could overwrite it with `None` and silently drop the value inside, and a record's field
  could be read twice. Both are now errors, as they already were for a field whose own type
  is linear.
- Linearity: a `_` over a value that holds a linear value (`let (_, n) = (Some(token), 1)`)
  silently dropped it; it is now rejected like a `_` over the linear value itself.
- Linearity: taking apart a tuple or variant that holds a linear value no longer makes its
  ordinary parts linear (`let (n, t) = (1, token)` leaves `n` an ordinary `Int`), and a
  generic function that opted in with `linear x : a` is no longer refused when its body
  passes `x` on to another generic function that also opted in. Passing it to one that did
  not (which may drop or duplicate it) is now an error; it was accepted or refused depending
  on inference order.
- Writing to a socket whose peer had just gone could kill the process with SIGPIPE; the
  shared send path now suppresses the signal.
- A dead green thread's execution context (880 of its bookkeeping struct's 1136 bytes on
  macOS/arm64) is freed when it dies, instead of being retained for the life of the
  process: memory held after a burst of concurrency drops 4.4× per task and 2.7× per actor
  (measured: −28% peak RSS on the actor-churn load scenario). `Scheduler.stat(7)` counts
  releases.
- `tcp_connect`'s name lookup (`getaddrinfo`) runs on a helper thread and parks the
  green thread: a slow resolver no longer stalls a scheduler thread. That was the last
  blocking call on the dial path.
- An unrefined `Chan.offer` continuation is a session state (`SOfferPending`) rather than
  a checker side table; diagnostics and accepted programs are unchanged.

### Added
- **`Session.fail(s, ep, why)`** and the `fail` op on `Session.Ops`: a delivery the
  generated endpoint code cannot take (undecodable, or a message the state does not
  receive) is handed to the transport instead of panicking in whatever turn it ran in.
  `SessionNode` ends the session and `run` returns `Err(Protocol(role, why))`; the
  same-thread transports panic as before. `<P>_Msg.try_decode` is the non-panicking
  decoder the handlers now use.

### Changed
- Every remaining blocking socket wait parks the green thread instead of holding its
  scheduler thread: `tcp_connect` (the handshake with a remote host), `Socket.write`/`send`
  into a full buffer, the WebSocket reads and `select`, and all of OpenSSL (`SSL_connect`,
  `SSL_accept`, `SSL_read`, `SSL_write`, driven on a non-blocking fd). Deadlines set on the
  fd (`SO_RCVTIMEO`) still bound the TLS handshake and reads.

### Fixed
- **A sorted insert into a list of pairs no longer crashes or returns wrong
  values when compiled.** Matching a list whose elements are tuples or records,
  reading a heap field through a comparison, returning the list on one branch
  and consuming the field on the other, freed the field too early: a
  use-after-free that crashed on some runs and gave a wrong answer on others,
  while the interpreter was always right. `ConsistentHash.add` was one instance;
  the bug was in the compiler, not the library.

- A `receive()` nested inside an actor handler that was still parked when the process
  shut down (or the actor was killed) returned the runtime's no-message sentinel into
  user code, which dropped it: `RC underflow (rc was 0) — aborting`. A stop now ends the
  actor on its normal death path instead.
- Calling a builtin with fewer arguments than it takes (`monitor(pid)` for the
  two-parameter `monitor`) typechecked as a function value — a partial application March
  does not have — which a `let _ =` then discarded silently. It is now the same arity
  error module functions already got.

### Added
- **A session role hosted in an actor, across nodes.** `SessionNode.run_hosted` and the
  generated `<P>_Run.host_<Role>(io, node_id, secret, addrs, host, start, deliver)` drive
  the event API (`Parked_<Role>` in the actor's state, `await_*`/`resume`) from a real
  network party: deliveries go to the actor one per suspension, in mailbox order, and the
  host is monitored — its crash or restart ends the session with `Err(HostGone(ep))`, and
  the peers see `PeerGone`.
- `Pid(a)`'s parameter is phantom to the linearity checker: a pid of an actor whose state
  holds a linear value can be passed to a generic function (`pid_to_int`, a `Pid(a)`
  parameter) — previously refused as "generic in a parameter of that type".
- **The role runner.** `SessionNode.run` starts a role of an `@[endpoints]` protocol from
  its peer set and a role→address table — listen, connect to every lower role, accept every
  higher one, check, attach, serve, tear down — in the order that cannot deadlock, and the
  generator emits its typed front `<P>_Run.run_<Role>(io, node_id, secret, addrs, body)`
  with `<P>_Run.addrs_from_env()` (reads `<P>_<ROLE>_ADDR = host:port`). A node is its role's
  body plus a match on the result. A peer that dies mid-session ends it for everyone:
  survivors get `Err(PeerGone(role, _))` back from `run` instead of hanging.
- **`tcp_shutdown(fd)`** (`shutdown(2)` without close: the one way to wake a reader another
  green thread has parked on that socket) and **`sleep_ms(ms)`** (a parking sleep; programs
  used to shell out to `sleep`, holding a scheduler thread).
- **`SessionNode.require(party, peers)`** checks a multiparty session has a connection to
  every role it will exchange messages with — the generated `<P>_Msg.peers_<Role>()` — and
  names the missing ones at startup rather than failing at the first message.
- The two-node harness (`scripts/two-node.sh`) accepts an optional third node, each node
  with its own listen port (`MARCH_PORT_A`/`_B`/`_C`); the `fan` scenario runs a
  three-role session protocol as three processes.
- **`NativeArray.sort_int` — a flat numeric array can now be sorted.** Unstable
  and in place when the array is uniquely owned, so a threaded
  `let a = NativeArray.sort_int(a)` allocates nothing; a shared array is copied
  instead of mutated. Implemented in the C runtime with no comparator crossing
  the closure boundary: 5–30x faster than libc `qsort` at 5 million elements,
  with already-sorted and reversed input handled in a single linear pass and
  low-cardinality input close to linear. The other element widths (f64, f32,
  i32, u8) are not done yet.
- **`SessionNode` routes by role, so an `@[endpoints]` protocol can run its roles on
  three or more nodes.** `SessionNode.party(my_role, node_id, on_close)` plus
  `accept_from` / `connect_to` per peer; `emit` picks the connection from the message's
  destination role and `serve` reads every peer. The two-node `SessionNode.open` is
  unchanged, and a single-peer party still routes everything to its one connection.
- **`Session.Ops.suspend` takes the role its continuation expects** (0 = any). Messages
  from different peers race, so a transport with several connections parks a delivery
  that arrives before the continuation that wants it. The projector knows the expected
  sender at every receive and now passes it, so generated endpoint code needs no change.
- **An `s == ""` guard now establishes `len(s) > 0` in the else-branch.**
  Previously documented as a gap: the checker knew only that `s` differed from
  the empty literal, and a downstream `{String | len(_) > 0}` contract was
  skipped.

- **A `let` bound to an `if` carries both arms' facts forward.**
  `let c = if x < 1 do 1 else x end` now discharges a downstream `{Int | _ > 0}`
  contract: the checker records the case split rather than dropping the
  binding.

- **`pmap_threshold()` carries the contract `{Int | _ > 0}`.** The three
  `List.pmap`/`pfilter`/`preduce` call sites that pass it to `chunks` are now
  proved rather than skipped, and the refinement checker can propagate return
  contracts for builtins generally.

- **`--refine-report-sites`: every skipped refinement obligation, one line
  each** — `file:line:col`, reason, kind, callee and predicate, tab-separated
  and labelled user or stdlib. `--refine-report` counts skips per reason;
  this attributes them, which is what deciding where to spend effort needs.

- **Refinements may multiply two variables.** `{Int | _ * _ >= 0}` and other
  non-linear predicates now reach the solver instead of being skipped as
  untranslatable: refusing them never bought soundness, since `v * v > 0` is
  exactly `v != 0` over the integers. Multiplication by a literal still keeps a
  query in linear arithmetic; where the solver cannot settle a non-linear goal
  the obligation is skipped with the new reason `nonlinear-goal`, which
  `--refine-report` counts separately from the residual `solver-undecided`.
- **`@[remote]` on an actor**: the compiler generates `<Actor>_Remote.dispatch(pid,
  delivery)`, which routes a typed `Node.send` delivery to the handler that takes its type.
  It returns `Ok(true)` when delivered, `Ok(false)` when no handler takes that type, and
  `Err` when the payload doesn't decode. The receiver's tag comparison uses the same tag the
  sender's compiler mints. A handler type without a codec is a compile error, and so is a
  `@[remote]` actor with no routable handler.
- **`SessionNode`**: the `Session.Ops` network transport. An `@[endpoints]` protocol's
  roles run on two nodes over one split peer connection:
  `SessionNode.open(conn, node_id, accepted, on_close)`, `Session.attach(io,
  SessionNode.ops(link))`, `SessionNode.serve(link)`, `SessionNode.finish(link)`. Flow
  control uses the credit-based `NodeQueue`. The two-node `stream` scenario now uses it
  (267 + 250 lines became 73 + 59).
- Two-node scenario `partition`: two processes running SWIM stop hearing each other,
  each claims the same `GlobalRegistry` name, and both converge on one winner after the
  heal. It needs Linux root for iptables; `scripts/two-node-docker.sh` runs any scenario
  from any host.
- **`SortedSet`'s tree operations are proved against its element set.**
  Insertion, rebalancing, both rotations, node construction, minimum deletion
  and flattening carry refinement contracts proved from their bodies, on one
  assumed comparator law; a differential property test checks `SortedSet`
  against `Set`. The refinement checker gained what that needed: `let` in
  proofs by recursion, nested constructor patterns and catch-all arms, callee
  contracts at any datatype, and scalar contract calls in guards.

- **`card(s)` in refinements: the number of elements of a set.** A query that
  mentions `card` gets finite-set facts about the set terms it contains, so
  `card(elts([7, 7])) == 1`, `card(elts(xs)) <= len(xs)` and "a subset is no
  larger" are proved. `Set.size` and `Map.size` carry assumed `card`
  contracts: `Set.size(Set.insert(Set.empty(), x, cmp)) == 1` is proved, and a
  claim of 2 is reported. See "Cardinality" in `docs/refinement-types.md`.
- **`Node.enqueue(q, to, msg, policy)`**: the typed remote send through a peer's
  `NodeQueue`, so a typed send gets credit-based flow control. It has the same contract
  as `Node.send`: `msg`'s type must `derive Json`, which is checked at the call site,
  and the compiler mints the wire tag. Returns `Ok(seq)` once admitted, or the queue's
  `Backpressure` / `NoConnection`.
- **`NodeQueue.BlockSender(timeout_ms)`**: a remote send that does not fit the peer's
  budget blocks the caller until credit admits the frame (`Ok`), the connection dies
  (`Err(NoConnection)`), or the timeout passes (`Err(Backpressure)`, frame withdrawn).
  Compiled backend; under the interpreter a send that cannot be admitted at once is
  `Err(Backpressure)`. `actor_reply_retain(ref)` lets a handler hold an `Actor.call`
  reply and answer it on a later turn (`test/native/block_sender_loopback`).
- Two-node scenario `monitor_reconnect`: a watcher that drops its connection between a
  remote actor's death and the ack still gets exactly one `Down` after reconnecting; and the
  `restart` scenario's monitor half: a crashed node's monitors fire `NodeDown` locally, once.
  `NodeSend.handle_frame` is the frame-level receiver for readers that dispatch by tag.
- **`Array` operations state their effect on the length.** `Array.empty`,
  `from_list`, `push`, `set` and `map` carry length postconditions, so
  `Array.get(Array.from_list([1, 2, 3]), 7)` is a compile error and a guard on
  `List.length(xs)` or `Array.length(v)` carries through them. `empty`'s is
  proved; the other four are `@[assume]`d, each with a runtime property
  witness.
- **List contracts proved from list code.** A function that recurses over a
  list can have its `elts` and `len` return refinement proved from its body,
  including through a local helper `fn`, a call to another proved function,
  and a parameter refinement used as an invariant. `List.reverse`,
  `List.append`, `List.filter` and `List.dedup` now carry proved element
  contracts, so `member(x, elts(List.reverse(xs)))` follows from
  `member(x, elts(xs))` at a call site. A contract is used only once proved,
  in any declaration order. See "Proved list contracts" in
  `docs/refinement-types.md`.
- `Node.send(peer, to, msg)`: the typed remote send. `msg`'s type must `derive Json`
  (a missing codec is a typecheck error at the call site naming the type, not a
  run-time `to_json` panic), the wire type tag is minted by the compiler from the
  declaration's qualified name so sender and receiver agree by construction, and
  `derive Json` now refuses a type with a local `Pid` anywhere in it (carry a
  `GlobalPid.Pid`). `Node.payload(d)` is the receiver's half. A module may now
  declare `fn send(...)` (reached qualified; the bare call stays the actor primitive).
- **`dist_monitor_forget_node(node_id)`**: when SWIM declares a watcher node dead,
  its watchers and pending `MONITOR_FIRE`s are dropped without writing anything
  (its watchers learn `NodeDown` locally); returns how many were dropped
  (`test/native/monitor_expiry_loopback`).
- **`MONITOR_FIRE` is at-least-once.** A fire the runtime writes stays pending in
  its registry until the watcher's node answers `MONITOR_ACK` (tag 12);
  `dist_monitor_pending()` lists the unacked fires and `DistLink.resend_pending(reg)`
  rewrites each on the watcher node's current control connection, so a fire lost
  to a dropped connection is delivered after the reconnect; watchers dedupe, so a
  resent copy is one `Down` (`test/native/monitor_ack_retry_loopback`).
- **`actor_terminal_reason(pid_index)`**: the reason a local actor died —
  `Some((tag, message))` with the wire's tags (0 Normal, 1 Killed, 2 Crash), `None`
  while alive or unknown — on both backends, keyed by spawn index so a monitor
  request for an already-freed record never touches it. A `MONITOR_REQ` for a pid
  that has already exited can now be answered at once (`test/native/monitor_after_death_loopback`).
- **Cross-node monitors are reachable from March**: `dist_monitor_register(target_pid,
  watcher_node, watcher_pid, fd)` is the surface of the runtime's monitor
  registry, so a node's reader can register a `MONITOR_REQ` and the actor-death
  path fires `MONITOR_FIRE` back to the watcher's node (compiled backend; the
  interpreter refuses it loudly). `test/native/dist_monitor_loopback` pins one
  `Down`, with the real reason, for a remotely killed actor.
- **`NodeQueue`: credit-based flow control for remote sends.** A per-peer
  outbound queue whose writer actor alone owns the data connection: a frame is
  written only while the receiver has granted credit for it (`CREDIT` frames on
  the control connection carry the consumed total), a byte budget bounds what is
  queued, and at the budget `drop_new` refuses with `Backpressure` at once while
  `drop_old` evicts the oldest (reported by `take_evicted`). A stalled peer is
  visible as queue depth, not as a green thread stuck in `write()`.
  `NodeQueue.cast` is the remote-send path through it; the `stream` two-node
  scenario (the `Session.Ops` network transport) runs on it.
- **`mailbox N policy` on an actor declaration** (`mailbox 1000 drop_old`, after
  `init`): the bound `Actor.set_queue_limit` sets per spawn site, declared once
  with the actor and applied at every `spawn`, on both backends. The policy is
  named (`drop_new` / `drop_old` / `block_sender`); an unknown name is a parse
  error, and `block_sender` under the interpreter fails at the spawn with the
  same message the call gives.
- **Control/data split for peer connections**: `ClusterConn.connect_split` /
  `accept_split` open two authenticated connections per peer, told apart by a
  `role` in the hello (a pre-split hello still reads as control); SWIM,
  monitors and `DELIVERY_FAILED` travel on the control connection, actor
  messages and RPC on data, so a control frame never queues behind a large data
  frame (`test/native/control_channel_loopback`).

- **Refinement measures read the payloads of parametric types.** A
  `@[measure]` declared over `Tree(Int)` or `Expr(Int)` now reads its `Int`
  payloads (`sum(l) + x + sum(r)`), a set-valued measure can collect them, and
  a measure declared over `Tree(a)` applies at `Tree(Int)`. These contracts
  were skipped before. A set predicate whose operands have known, different
  element types (`member("a", elts(xs))` with `xs : List(Int)`) is now an
  error at the predicate instead of a silent skip.

- **A remote send's failure reaches the sending actor's mailbox**:
  `NodeSend.cast_from` records the sender under the seq and `NodeSend.on_failure`
  hands a `DELIVERY_FAILED` frame back to it through the caller's dispatch, the
  way a monitor's `Down` arrives, instead of a synchronous read in `main`.
- **SWIM stall-vs-death, executable**: the `stall` two-node scenario SIGSTOPs a
  node running a real SWIM loop; the observer takes it through `Suspect` to
  `Dead` on timeouts alone, and on resume the node refutes with a higher
  incarnation, which the observer accepts as `Alive` (`test/two_node/stall/`).
- **The `Session.Ops` network transport**: the Stream session protocol's two
  endpoints run on two nodes with every message crossing a TCP connection as a
  `NodeSend` ACTOR_MSG, using the generated `@[endpoints]` API and endpoint code
  unchanged from the in-process fixtures (`test/two_node/stream/`). The transport
  is the mailbox one with `emit` sending to the peer node's endpoint actor.
- **Two-node failure-semantics harness**: `scripts/two-node.sh <scenario>` runs two
  compiled March programs as two OS processes, applies a fault from outside
  (SIGKILL/restart, SIGSTOP/SIGCONT), and diffs each node's sorted output. First
  scenario, `restart`: a node restarted with a new creation at the same local pid
  refuses a message addressed to its predecessor (`stale creation`) and accepts
  one addressed to itself. Runs on the ubuntu CI leg.
- **Bounds contracts on `Array.get`, `Array.set` and `Array.pop`.** A negative
  index (`Array.get(v, -1)`) is a compile error, an `i >= 0 && i <
  Array.length(v)` guard satisfies the contract, and `pop` needs
  `Array.length(v) > 0`. An index the compiler can't bound stays silent, as
  for `List.nth`; that includes a literal past the end of an array built by
  `Array.from_list`, whose length the checker does not track. Swept first over
  the stdlib, the native and stdlib test corpora and eighteen ecosystem
  projects: no new errors. See `docs/refinement-types.md`.

- **`pid_to_int(pid)`**, the inverse of `pid_of_int`: a Pid's spawn index (the `N`
  in its `Pid(N)` display), on both backends. Building a `GlobalPid` for a local
  actor previously meant parsing `to_string(pid)`.

- **`PeerReader`: one reader per peer connection, dispatching frames by tag.**
  There was no receive loop: every cross-node consumer read its own frames
  off the shared connection and skipped the ones it did not recognise, so two
  consumers stole each other's frames, and bytes read past a frame boundary
  were dropped. `PeerReader.serve(fd, buf, on_frame)` reads each frame once,
  reports its tag, and hands it to the caller's dispatch; leftovers carry to
  the next frame. `test/native/peer_reader_loopback` delivers three frames for
  two consumers from one `recv()`.

- **`NodeSend`: a one-way message to an actor on another node.** Everything
  cross-node was a synchronous `NodeCall` or a monitor frame. `NodeSend.cast`
  writes an `ACTOR_MSG` frame addressed by `GlobalPid`; `NodeSend.serve_one`
  checks the destination node's `creation` and hands the delivery to the
  receiver's dispatch; every refusal (stale creation, unknown pid or type,
  undecodable payload) comes back to the sender as `DELIVERY_FAILED`.
  Documented in the clustering chapter; `test/native/node_send_loopback`
  runs the exchange over TCP loopback.

- **Set refinements.** A predicate can now state which elements a collection
  holds, Liquid Haskell style: `elts(xs)` and `keys(m)` map a `List`/`Map` to
  its element/key set, and `member`, `union`, `inter`, `diff`, `subset`,
  `singleton`, `empty` and `==` operate on sets, all encoded as quantifier-free
  Z3 arrays. Literal membership, relational contracts (`{List(Int) | elts(_)
  == elts(xs)}`), propagation through calls, `let`s and parameter promises,
  and guards over `Set.contains`/`Map.contains_key` are proved or refuted;
  cardinality is out of scope by design. A `@[measure]` may return a
  `Set(a)` (`free_vars(e)`), typechecked as logic and rejected in expression
  position. Refuted set contracts render their model as a set literal
  (`Set.insert() can return {4}`). See "Set Refinements" in
  `docs/refinement-types.md`.
- **`@[assume]`: an assumed postcondition.** The declared return refinement
  propagates to call sites without a proof and the body is not checked
  against it (Liquid Haskell's `assume`); counted in `--refine-report` under
  `trusted`. Distinct from `@[trusted]`, which only accepts a skip inside
  `cap verified`. The stdlib `Set` and key-affecting `Map` operations now
  carry `@[assume]`d `elts`/`keys` contracts, each with a runtime property
  witness in `test/stdlib/test_set.march` and `test/stdlib/test_map.march`.

- **Endpoint actors under a supervisor, measured.** Two fixtures answer what
  a restart means for a session: a callback-API host routed by name is
  replaceable and the protocol continues (`test/session/stream_actor_supervised.march`);
  an event-API host's parked state dies with it, so a transport routing through
  epoch capabilities detects the restart and abandons the session cleanly
  (`test/session/stream_actor_events_supervised.march`). Documented under
  "Generated endpoints" in the session-types chapter.

- **Container subtyping covers every registered ADT, two layers deep, and
  polymorphic calls.** Element refinements are now contracts for `Result`,
  user variant types (`Node(Leaf, 0, Leaf)` under `Tree({Int | _ > 0})` is
  rejected, and a `match` on it knows the element fact), and any stdlib type
  defined as a variant; for two layers of nesting (`[[1], [0]]` under
  `List(List({Int | _ > 0}))` is rejected); and through a polymorphic call's
  declared signature (`let h = first(xs)` with `first : List(a) -> Option(a)`
  carries `xs`'s element refinement to `h`; `let x = List.head(xs)` gives
  `x` the refinement itself). The pass-through refuses any callee that could
  manufacture an element (`put(xs : List(a), v : a)`). A tuple element or an
  arrow inside a container remains unenforced.

- **A callback's codomain refinement is a contract.** `fn apply(f : Int ->
  {Int | _ > 0}, x : Int)` now knows `f(x) > 0` inside `apply`, and every
  function passed for `f` must return a value satisfying it: a named function
  through its own proved return refinement (`_ >= 0` does not imply `_ > 0`
  and is refuted), an inline lambda through its body (`apply(fn n -> 0, 1)` is
  rejected), and a function with no return refinement as a recorded skip. A
  local `fn`'s or `let`-bound lambda's proved return refinement now reaches
  its callers the same way. `--refine-audit` reports a single-argument
  callback's domain and codomain at a parameter as Enforced.

- **`@[endpoints]` also generates an event-shaped API, so a session endpoint
  can live in an actor's state.** Beside the callback-shaped `recv_*`/`offer_*`,
  every role module now has `Parked_<Role>` (an `always_linear` "awaiting a
  delivery" value), `await_*`/`finish` to park an endpoint, and
  `resume(parked, from, msg, ep)` returning a `Received_<Role>` the actor's own
  handler matches with `state` in scope. Because `parked` is a linear state
  field, a turn that resumes and forgets to park again, or keeps the consumed
  value, is rejected. `test/session/stream_actor_events.march` runs the
  `Stream` protocol this way with the same trace as the function-hosted
  version.

- **Container subtyping: a refinement inside a `List(...)` or `Option(...)`
  type argument is enforced.** `fn f(xs : List({Int | _ > 0}))` now obliges
  every value flowing into `xs`: a list literal element-wise (`f([0, 0 - 1])`
  is rejected twice), a container-typed variable by element implication
  (`ys : List({Int | _ >= 0})` passed to `f` is rejected with witness `0`;
  `List({Int | _ > 5})` passes), and anything else as a recorded skip. The
  same applies to a container return type, an annotated `let`, and a record
  field. On the other side, `match xs do Cons(h, t) -> …` knows `h > 0` and
  `t : List({Int | _ > 0})`, and `Some(x)` knows the element fact. Other
  containers, two layers of nesting, and elements reached through stdlib
  functions remain unenforced and are reported by `--refine-audit`.

- **Two silent refinement holes are closed.** A `{String | ...}` return
  type is now verified against the function's body (`fn f() : {String | _
  == "a"} do "b" end` is a violation; `len(_) > 3` over `"xy"` is refuted),
  where before it filed nothing, not even a skip. A refined default
  parameter (`b : {Int | b > 0} \\ 1`) now obliges a full-arity call
  `f(1, 0)`, resolved to the `f$2` arity variant the runtime dispatches to.
  A multi-head function whose first head has no guard and only variable
  parameters keeps that head's declared types through the clause merge, so
  its refinement is the function's contract (`fn f(n : {Int | n > 0})` then
  `fn f(0)` rejects `f(0 - 1)`); a refinement on a non-dominating head is
  still not adopted, since another head may legitimately handle the value.

- **An `impl` method's parameter refinements are enforced even when the
  method name is ambiguous.** With two impls of `at`, a call
  `at(Crate(0), 0 - 1)` used to resolve to nothing and oblige nobody; it is
  now resolved by the first argument's type, the same rule compilation
  dispatches by, and checked against that impl's own contract (so an impl
  requiring `i >= 10` and one requiring `i >= 0` are told apart by the
  receiver). A call whose receiver type the typechecker cannot name is a
  recorded skip (counted by `--refine-report`, an error under
  `cap verified`), never silence.

- **Stored-field refinements are enforced.** A refined record field
  (`type Box = { v : {Int | _ > 0} }`), variant argument
  (`type W = W({Int | _ > 0})`), or actor state field is now a contract on
  every construction, so `{ v: 0 }`, `{ b with v: 0 }`, `W(0 - 1)`, and an
  `init { value: 0 - 1 }` under `value : {Int | value >= 0}` are rejected,
  and a fact for every reader: `b.v` on a `b : Box` is known to satisfy
  `_ > 0`, and a handler's incoming `state` is known to satisfy its
  invariant (which `init` and every handler result must re-establish). A
  `linear` wrapper is transparent to the refinement. A record literal is
  typed by its field set; two types of one shape make it ambiguous and it is
  not obliged. Refinements inside a type argument (`List({Int | _ > 0})`)
  remain unenforced.

- **An actor handler's parameter refinements are enforced.** `on Inc(n :
  {Int | n > 0})` now obliges every construction of `Inc(...)` in the program
  (`send`, `Actor.call`, or a message bound to a `let` first), so
  `send(c, Inc(0 - 1))` is rejected where the message is built, and the
  handler body assumes `n > 0`. A message name defined by two handlers or
  shared with a variant constructor is neither obliged nor assumed (fail
  closed). A message arriving from a remote node was built by code this
  compiler did not check; the docs state that trust boundary.

- **Passing a refined function is checked at the pass site, and a
  `let`-bound lambda's refinements are enforced.** `apply(take_n, -3)` with
  `fn apply(f : Int -> Int, x : Int)` and `take_n : {Int | _ >= 0} -> Int` is
  now rejected where `take_n` is passed: the expected domain `Int` promises
  nothing, so it cannot imply `_ >= 0` (witness `-1`). The rule is
  contravariant subtyping: a refined callable (named, aliased, local `fn`,
  `let`-bound or inline lambda) may be passed only where the expected
  function type's domain implies its own parameter refinement for every
  value; a domain refined at least as strongly passes, and a domain spelled
  as a type variable (`List.map`'s) promises nothing. A `let g = fn (n : {Int
  | n > 0}) -> ...` is also a contract for its direct callers now, and
  assumes `n > 0` in its body while every use of `g` is obliged. The former
  accept witness `t77_refine_hof_bypass_limitation` is the reject witness
  `t77_refine_hof_pass_site_rejected`. Multi-parameter callables are neither
  obliged nor assumed.

- **A block-level `fn`'s refinements are enforced.** A local
  `fn inner(n : {Int | n > 0}) : {Int | _ > 0} do ... end` inside a function
  body is now a contract on both ends: every direct `inner(...)` after it and
  every recursive call inside it is obliged by the parameter refinement, and
  the return refinement is verified against the body. The body may assume its
  parameters only while `inner` is never passed around as a value; an
  escaping local is checked with them stripped. `--refine-audit` reports both
  positions Enforced.

- **A session endpoint can be hosted in an actor.** `test/session/stream_actor.march`
  runs both roles of a protocol inside actors, with every resumption driven by
  a mailbox delivery, over the same generated `@[endpoints]` API and with the
  same trace as the function-hosted version. The session state lives in the
  transport's continuation rather than in actor state, so the endpoint's host
  turns out to be replaceable: swapping an endpoint's actor for a fresh one
  mid-session continues the protocol from where it was.

- **`@[endpoints]` on a `protocol` generates a typed endpoint API for every
  role**, over the `Session` transport capability. Each session state becomes
  an `always_linear` type and each protocol step a function between them, so
  the ordinary typechecker enforces the protocol: sending out of order is a
  type mismatch, sending twice on one state or abandoning a session is a
  linearity error, an offer takes one callback per label, and a callback
  cannot drop its state because it must return a token only the generated
  wrappers produce. Messages get a `Json` codec over `Bytes`; the LSP sees the
  generated modules because generation happens at desugar time. Protocol
  conformance was previously checked only over the same-thread `Chan`/`MPST`
  runtime; the `Session` capability ran for real but was untyped. This joins
  the two: `test/session/stream_endpoints.march` replays the `Stream`
  protocol through the generated API with the same eight-line trace as the
  hand-written endpoints, on both backends.

- **`Actor.top_by_mailbox(n)` and `Actor.over_mailbox(threshold)`**: the
  "which actor is behind?" question, as `(pid, depth)` pairs — the `n` deepest
  mailboxes deepest-first, and every actor over a threshold (the growing-mailbox
  alarm, polled). Both are snapshots built on `Actor.list()`.
- **Stash / become** is now a documented idiom (`docs/actors.md`, "Stash and
  Become") with a worked multi-step protocol: a `mode` field plus a stash list
  in actor state cover what selective receive is used for, no runtime support
  needed.
- **`MARCH_SUP_TEST_STALL_MS`**, a test seam that lets the runtime's own suite
  force the supervisor restart race by construction. Unset in production; does
  nothing when unset.

### Added
- **`march --pin-main` pins `main` to the process main thread.** Bakes into the
  binary what `MARCH_PIN_MAIN=1` did at run time, so a double-clickable GUI app
  (Cocoa, GLFW) no longer depends on being launched with the variable set. The
  environment variable still works, and can only turn pinning on, never off a
  build that asked for it.

### Fixed
- **A call that could not be specialized is now a compile error when the caller
  and callee disagree about the return representation, instead of silently
  producing a wrong value.** A stdlib module outside the eager load manifest is
  read for export shapes only, so monomorphization reaches its call sites with
  the return type unresolved and emits the generic boxed body — while a caller
  at a concrete niche-eligible type reads the wrong bits as the payload. The
  error names the call, both representations, and the fix. Measured across 316
  programs and 2,204 unspecialized calls before landing: zero false positives.

- **`DataFrame.col_z_score` and `col_normalize` no longer panic on a zero-row
  column.** Both reached `Stats.mean` / `std_dev` / `min_val` / `max_val` with
  an empty list. They now return a zero-row `FloatCol` — the `n = 0` case of
  the zero-variance/zero-range branch each already had. A zero-row frame is
  ordinary: `head(df, 0)` makes one, and so does a filter that matches nothing.

- **A path dep's `source` in `forge.lock` is recorded relative to the project
  root.** It was stored in whatever spelling `forge.toml` used, so an absolute
  declaration leaked a home directory into a committed file and made two
  checkouts of one project produce different lockfiles and different
  `manifest_hash`es. Existing lockfiles take a one-line diff per absolute path
  dep, once.

- **`NativeArray.fold_float` no longer leaks two Float boxes per call
  (compiled).** A fold boxed its initial accumulator at the call site and
  returned a boxed result, and neither was released — two live objects per
  call, independent of the array's length. The per-element boxing inside the
  fold loop was already released and is unaffected. `fold_f32` had the same
  leak; `fold_int` wire-tags instead of boxing and never did.

- **A green thread waiting on a socket no longer holds its scheduler thread.** `tcp_accept`,
  `Socket.recv`, `Socket.recv_timeout`, `tcp_recv_all` and `tcp_recv_exact` now park the
  green thread until the socket is ready (`march_sched_wait_fd`, a kqueue/epoll poller the
  scheduler services), so a program with many connections waiting at once no longer needs
  more scheduler threads than waiters — before, six readers in one process hung a 4-thread
  scheduler solid. A fd's `SO_RCVTIMEO` still bounds an untimed `Socket.recv`.
- **An `if` no longer leaks a value that is dead on one side (compiled).**
  Every `if`/`else` whose two sides disagreed about a heap value leaked that
  value, once per evaluation — a String, a list, a record, a closure
  environment, a SIMD box. Perceus releases a variable in the arms where it is
  dead provided it is live in some other arm, and "some other arm" was computed
  over the tagged branches of the case only; an `if` is one tagged branch plus a
  default, so a value used only on the `else` side was released nowhere. A
  `match` over a variant has all arms tagged and was always correct. The
  vector-in-a-list leak reported against the SIMD fix below was this bug, not a
  gap in the generated drop.
- **A SIMD vector passed to a function that is not tail-recursive, or to a
  closure, no longer leaks (compiled).** Crossing such a parameter boxes the
  vector, and nothing released that box: one 32-byte cell per call. SIMD
  builtins now borrow the vectors they read, which is what makes the release
  safe to place.

- **Refinement checker: a user datatype colliding by bare name with a stdlib
  module's own no longer clobbers it.** `stdlib/ordered_map.march` declares
  `type Tree`; a user `type Tree` joined the same unqualified sort before
  this fix, and whichever was registered last silently overwrote the
  other's constructors. Datatype sort names are now qualified by declaring
  module when two or more collide, resolving to the entry/top-level
  declarant for an unqualified reference from the same top-level code.
  `@[measure]` names are not (an attempt regressed a proof's z3 time from
  instant to minutes); a stdlib rename that dodges a measure-name collision
  (`SortedSet`'s `sorted_set_elts`) is unaffected.
- **A `@[measure]` returning `Set(a)` over a generic `Tree(a)` now proves
  when applied to a concrete instance.** Applying such a measure to a
  `Tree(Int)` term was always a sort-conflict skip; the checker now tracks
  which of the measure's own type parameters its set element is and
  resolves it at the concrete instance, both for the instance's own axioms
  and the query preamble that declares them.
- **`--pmap-threshold` below 1 is rejected instead of hanging.** A cutoff of
  `0` made `List.pmap` never return; the flag now fails with a message.
- **`DateTime.parse_offset` returns `Err` on a malformed offset instead of
  panicking.** The offset minutes were parsed as any two digits and handed
  straight to `fixed_zone_hm`, whose `{Int | _ >= 0 && _ < 60}` contract
  panicked, so `"2026-01-02T03:04:05+01:75"` aborted the process rather than
  failing the parse like every other malformed field. Both the `+HH:MM` and the
  colon-less `+HHMM` path are now range-checked, and the hour is bounded to
  RFC 3339's 00-23 (`"+99:00"` used to be accepted as a zone 356400 seconds from
  UTC). Found by the refinement checker: both call sites were
  `unconstrained-subject` skips, and are now one proved obligation.
- **`test/stdlib/test_datetime.march` actually runs.** It was on
  `test_stdlib_march.ml`'s known-orphan allowlist, so its tests had never
  executed; it is now registered with the other stdlib test files.
- `DataFrame.col_describe` (and `summarize`, which uses it) panicked with
  `Stats.mean: empty list` on a frame that has columns but zero rows — the shape
  `head(df, 0)` produces, and the shape any filter that matches nothing produces.
  Numeric columns with no rows now report `count = 0` and `None` for every
  statistic, which is what the non-numeric columns already did.
- `Node.send` minted a different wire tag for a message type declared at the entry
  module's top level depending on the entry module's name (`App.Note` rather than
  `Note`), so two separately built nodes could not agree on it. The entry module's name
  is now unwrapped, as it already was for nested types.
- `GlobalRegistry` replicas now converge after a network partition. `REGISTRY_SYNC_RESP`
  dropped each entry's vector clock, so a received binding always lost to the local one
  and both sides kept their own. Leaves now carry the clock, and the old encoding still
  decodes.

- **`List.map` and `List.filter` no longer leak a capturing lambda
  (compiled).** Each call leaked the lambda's environment and everything it
  captured — one object per call. Their internal loop hands the callback down a
  recursion through an alias, and it was that alias's release, not the one the
  compiler had keyed its deep drop on, that ended the environment's life.
- **`SortedSet.from_list`, `union`, `intersect` and `difference` work.** All
  four passed their arguments to `List.fold_left` in the wrong order with a
  curried callback, so `SortedSet.from_list([5, 3, 9, 3, 1], cmp)` panicked
  with "non-exhaustive pattern match ... { cmp: <fn>, tree: Leaf }" both
  compiled and interpreted, and `--check stdlib/sorted_set.march` reported 17
  type errors.
- **Interpreter: a user function no longer hijacks a Prelude function's
  internal call of the same name.** With a `pfn show` (or `fn show`) over
  some type in your program, `println("hi")` panicked when interpreted
  (`match failure`) because Prelude's `println` called your `show` instead of
  the builtin one; the compiled binary was already correct. A Prelude
  function's bare references now resolve in Prelude's own scope.
- **No more false "Non-exhaustive pattern match" on matches that mix wildcard
  and constructor sub-patterns in one position.** A fully covered match such as
  `Nd(Lf(a), Lf(b))`, `Nd(Nd(_, _), Lf(b))`, `Nd(_, Nd(_, _))`, `Lf(n)` warned
  `missing case: Nd(_, Lf(0))`; the same happened with tuples like
  `(true, _)`, `(_, true)`, `(false, false)`. A genuinely missing arm still warns.
- **A function that reads a field of a record parameter and hands it to a
  read-only helper no longer frees the record first when compiled.**
  `SortedSet.size(s)` on a set nothing else held panicked with
  "non-exhaustive pattern match" (`SortedSet.size(SortedSet.new(cmp))` was
  enough) while the interpreter printed the size. It only seemed to depend on
  which `SortedSet` functions a program called because a later use of `s`
  kept the set alive. User code of the same shape (`fn f(b) do count(b.tree)
  end`, a match on `b.tree`, or `o.inner.tree`) was affected too.
- Load-aware routing no longer depends on peers' clocks agreeing: a load report received
  through `SwimDriver` is aged from its arrival on the receiving node, so a peer whose
  clock ran ahead no longer sent reports that never went stale (or, behind, stale on
  arrival). Pinned by the two-node scenario `skew`.
- `NodeQueue.take_evicted` reached the writer's `Configure` handler instead of its
  own: `Actor.call` routes by the sentinel's constructor index. It now answers.
- Interpreter: a handler of an actor declared in a module can call a fn declared
  after the actor (was "stub X called before initialisation").
- A cross-node `MONITOR_FIRE` written to a connection whose peer had already closed raised
  SIGPIPE and could kill the node; it now fails quietly and stays pending for resend.
- **Module-qualified constructor patterns whose module name is also a stdlib
  type name now match when compiled.** With a nested `mod Tree do type T =
  Leaf(Int) | Node(T, T) end`, a match on `Tree.Leaf(n)` resolved to the stdlib
  `OrderedMap.Tree`/`SortedSet.Tree` constructors, so the compiled binary
  panicked with "non-exhaustive pattern match" while the interpreter was
  correct. The same program no longer warns about a missing `LWWRegister` case
  (a stdlib type that shares the bare name `T`).
- **Refinement violations on `Array` calls name `Array.length`.** The
  message and its suggested guard spelled the private measure `pvec_length`,
  which does not compile in user code; a literal negative index also showed
  a meaningless `(e.g. negate = 0)` example, which is now omitted.
- `stdlib/dist_supervisor.march` failed a standalone `--check` ("Constructor `Normal` is
  ambiguous between multiple modules"): its restart decision matched `DistLink.DownReason`
  with bare arms that also name the local monitor's constructors. Qualified, and guarded.
- **Refinement checks no longer skip a caller value because it is not an
  `Int`.** A value the callee did not pin to a scalar sort was declared `Int`
  in the solver query, so a `String` element (`need(["a", s])` against
  `member("a", elts(_))`) or an `Option` in a guard (`if o == p do unwrap(o)`)
  met its real sort in the same query and the obligation was silently skipped
  as `sort-conflict`. Parameters, `let` binders, pattern variables, refined
  binders and guard variables now take the type the typechecker gave them, so
  these obligations are proved or reported.
- `derive` inside a nested `mod` was a silent no-op: the derive was never expanded, so
  `derive Json for T` in `mod Inner` generated nothing and the first `from_json` to `T`
  failed at run time. Nested derives (and `satisfy`) now expand at every level.
- **The cluster handshake no longer swallows the peer's first bytes.** It read
  its two frames in 4 KiB chunks and dropped the over-read, so a peer that
  finished the handshake and immediately wrote lost whatever landed in the same
  `recv()` as the proof (reproduced only under load). The handshake now reads
  exactly its own frames (`NetKernel.recv_frame_exact`).
- **`NetKernel.recv_frame` is linear in the frame size.** It appended every
  4 KiB chunk to the accumulated list, quadratic in the frame: a 1 MiB frame
  took 4.1 s. Once the length prefix is known the rest is read with one
  `tcp_recv_exact` and appended once (0.3 s), leftover bytes carried as before.
- **`send` no longer leaks a reference to the actor it sends to.** `send`,
  `kill`, `actor_stop`, `is_alive`, `mailbox_size` and `get_cap` now borrow the
  pid (their runtime implementations only read it), and `self` returns an owned
  reference like `pid_of_int`; together with the runtime holding a running
  actor's own reference, the refcount of an actor is now exactly the references
  the program holds plus one while it runs.
- **A running actor is no longer freed when the program drops its last pid.**
  `let a = spawn(W)` with `a` never used again released the actor record's only
  reference right after spawn, and the actor's own thread then ran on freed
  memory — invisible on macOS, a glibc `tcache` abort on Linux
  (`native_actor_enumeration` on the ubuntu CI leg). The runtime now holds its
  own reference to a live actor, released when its thread finishes.
- **A user function named `own` with two arguments is the user's function again.**
  The lowering rewrote *any* two-argument `own(...)` into resource registration
  (`Drop$<Type>.drop`), so a user `fn own(ep, p)` called with a `Pid` failed to
  link with an error naming nothing the user wrote. The rewrite now applies only
  when the module does not define its own `own`.
- **A user function named after a C symbol the runtime links against (`connect`,
  `log`, `time`, `strlen`, `write`, `exit`, …) no longer hijacks the runtime.**
  Top-level user functions are emitted under their bare name in the same link
  as the C runtime, so `fn connect` *was* the `connect()` the runtime's
  `tcp_connect` called: the program recursed through it to a stack overflow
  before its first print (a single-use `pfn` escaped only by being inlined).
  A bare name in the reserved set is now emitted as `name$u` at its definition
  and every reference; the interpreter was never affected.

- **Set refinements: six correctness fixes from review.** A module's own
  function named like the set vocabulary (`keys`, `member`, …) used in a
  guard is no longer read as a set operation, which had skipped the whole
  call and hidden a real violation; a fact whose set element sorts clash is
  dropped rather than skipping the check. A predicate that applies a set word
  in a non-set shape (`member(xs, 3)`) warns again, and a `@[measure]` may not
  take a set-vocabulary name. A `Set(Bool)` measure, or one whose declared
  element type disagrees with its payload, no longer emits an ill-sorted
  axiom that made every measure query in the module undecided. A record
  field used as a set element (`member(v.name, …)`) now proves. Calling a
  set-valued measure from an `impl` method, actor handler, `test` block or
  top-level `let` is now a `--check` error instead of a link failure.
  `--refine-audit` no longer reports a `{List(_) | len(_) > 0}` return with
  no list measure, or a Tier 2 match on an unannotated parameter, as
  enforced. A chain of `let`-bound `Set.insert`s now carries its membership
  facts through every link.

- **The interpreter refuses the `block_sender` mailbox policy instead of
  silently ignoring it.** `Actor.set_queue_limit(pid, n, 3)` under `march run`
  used to run unbounded, so a program relying on backpressure got none there
  and then behaved differently compiled. It now fails at the call with a
  message naming `drop_new`/`drop_old` and the compiled backend.

- **`node_discovery` is back on `dune runtest`.** It was quarantined on
  2026-08-08 for a torn-stdout race that was fixed on 2026-08-21
  (`march_stdout_mu`); the quarantine outlived the fix. The ubuntu CI job now
  also runs the compiled test 200 times per run as the guard.

- **A record parameter no longer makes an unproven postcondition a "violation".**
  With a record-refined parameter in scope the checker reports any satisfiable
  counterexample directly; it now does so only when every parameter's own
  contract was loaded as an assumption. A contract it cannot translate (a
  `len` conjunct beside the record, for example) previously let the solver pick
  an input that contract forbids and report correct code.
- **An unannotated parameter's name now reaches a relational postcondition.**
  `fn insert(s, elem, cmp) : {… | elts(_) == union(elts(s), …)}` was recorded
  with parameter names `_`, so the contract was classified unusable and never
  propagated; a variable pattern parameter is now a name. A Bool local bound
  to a call with a contract (`let present = Set.contains(…)` then
  `if present`) and a guard that is itself such a call now establish the
  contract on their branch.

- **A `@[measure]` whose value is a scalar constructor field is no longer
  inert.** Call-site reflection erased every scalar constructor field to an
  unknown, so a measure like `Array.length` (which reads `PVec`'s count)
  proved nothing anywhere. A literal's field now reflects concretely
  (`get(Box(3, 0), 5)` against `_ < size(b)` is refuted; `1` proves), and on
  an opaque value a guard over the measure (`if i < size(b)`) decides the
  contract. The measure-definition warning says exactly this instead of
  "never proved or refuted".

- **`--refine-audit` no longer reports a callback's domain refinement as
  unenforced.** `fn apply(f : ({Int | _ > 0}) -> Int, x : Int)` has been
  enforced for some time (a call `f(x)` inside `apply` is checked, and passing
  a function to `apply` is checked where it is passed); the audit's nesting
  rule fired first and called the site unenforced anyway. It now reports
  Enforced for a single-argument arrow at a function or lambda parameter, and
  says precisely what is not modelled (a tupled or curried domain, an arrow
  at a `let` annotation, field, or return) otherwise.

- **A skipped obligation blames the right thing when a sibling argument is
  opaque.** `at(i, lane(4))` against `i : {Int | _ < n}` used to report
  `unreflectable-predicate: the predicate's n has no SMT translation`; the
  predicate is fine, and what failed to reflect was `lane(4)`, the argument
  passed for `n`. It now reports an unreflectable *subject* naming that
  argument. Diagnostic only; no verdict changes.

- **Diagnostics inside generated code are reported.** An error or warning
  the typechecker raised inside a `derive` expansion or an `@[endpoints]`
  module was silently filtered out with the stdlib's, so `march --check`
  exited 0 on a generated function that used a linear value twice. Such a
  diagnostic now prints, without a source excerpt, with a note saying it is in
  code generated for the file.

- **`p : Pid(Int)` is accepted as a type annotation.** The bare name `Pid`
  resolves to the stdlib's `Global_pid.Pid` record, so the one-argument actor
  pid spelling was rejected with "`Pid` expects 0 type argument(s)", and every
  program matching a monitor's `Down` carried the same error invisibly. The
  one-argument form now means the actor pid.

- **`derive Eq` on a single-constructor type, and `@[endpoints]` on a protocol
  whose state can receive every message, no longer generate an unreachable
  catch-all arm** (a "pattern can never be reached" warning that became
  visible with the change above).

- **Calling a closure no longer leaks its arguments (compiled).** A function
  value called with a fresh heap argument (`f(int_to_string(n))`, a
  `List.filter` predicate, the per-element `show` inside `to_string` of a
  `List(String)`) leaked that argument on every call, and an argument still in
  use afterwards could never be freed. This covered lambdas that only read
  their argument or ignore it, a lambda parameter typed with a record alias,
  and a named function passed as a value.

- **Closures no longer leak their environment and captured values
  (compiled).** A function that returns a closure (`fn adder(k) do fn x -> x
  + k end`) leaked the closure and everything it captured on every call.

- **`to_string` of a list and `string_join` no longer leak the list
  (compiled).** Printing a list leaked the intermediate list and its element
  strings on every call (five objects for a two-element list).

- **Awaiting a task that returns a `Float` no longer leaks (compiled).** Each
  `task_await_unwrap` or `task_await` of a `Float` task left one allocation
  behind.

- **Matching a small struct out of an `Option` no longer leaks (compiled).**
  `match o do Some(p) -> ... end` on an `Option` of a two-`Float` record-like
  type leaked one allocation per match.

- **`compare_int`, `compare_float` and `compare_string` work.** Compiled
  programs calling them failed to link, and the interpreter returned a
  `Less`/`Equal`/`Greater` value where the type says `Int`. They now return
  -1, 0 or 1 on both, like `compare`.

- **A generic function has to opt in to receiving a linear value, and a
  container holding one is linear too.** `fn dup(x) do (x, x) end` turned one
  `always_linear` value into two, `fn drop_it(x) do 0 end` leaked one, and a
  tuple holding one could be destructured twice. A generic function now receives
  a linear value only through a parameter marked `linear` (`fn id(linear x : a)
  : a`), which its body must then use exactly once; constructors, operators and
  functions that only return their type variable need nothing. A tuple, list or
  ADT value holding a linear value is tracked like the value itself. **This can
  reject code that compiled before**, including stdlib calls such as
  `List.length` on a list of linear values.

- **A linear value must be consumed on every branch that returns.** `if b do
  sink(st) else 0 end` dropped `st` whenever `b` was false, and was accepted:
  branches merged as "consumed on some branch". A branch that ends in `panic(…)`
  is exempt, since it never returns, and so are affine values and session
  channels. The early `Err` return of `let?` counts as a branch. **This can
  reject code that compiled before.**

- **A record's linear fields can no longer be consumed and kept at the same
  time, and actor state is covered.** In an actor handler, `sink(state.st)`
  followed by `{ state with n: k }` left the consumed `st` in the state for the
  next turn, silently. A record now owns its linear fields: accessing one moves
  it out, using the record whole moves them all, `{ r with … }` keeps what it
  doesn't replace, and each must be consumed before the record goes out of
  scope. A field whose type is `always_linear` counts, and a `linear` qualifier
  on an actor state field is no longer ignored. **This can reject code that
  compiled before**: a handler that returns a brand-new state now has to
  consume the old state's linear fields first.

- **An unannotated parameter is checked for linearity once its body fixes its
  type.** `fn g(st) do sink(st) + sink(st) end`, where `sink` takes an
  `always_linear` value, used `st` twice without complaint (annotating `st`
  made it an error). The same held for inferred lambdas and actor handler
  parameters.

- **A closure passed straight to a function, or a local `fn`, can no longer
  capture a linear value.** The "cannot be captured by a closure" rule only ran
  for a lambda bound with `let`; `run2(fn () -> sink(s))` captured `s`, and a
  `run2` that calls its callback twice consumed it twice.

- **A `_` wildcard can no longer silently drop a linear value.** `let _ =
  S1(1)`, `let (a, _) = (S1(1), S1(2))`, a `_ ->` arm on a linear scrutinee,
  and a `fn _ -> …` callback receiving one were all accepted. Each now reports
  "This `_` discards a linear value". Discarding a non-linear part (`S1(_)`,
  `let _ = sink(s)`) and a `_` arm that ends in `panic(…)` stay legal.

- **A lambda or local `fn` can no longer drop a linear parameter.** A
  callback such as `run(fn st -> 0)` receiving an `always_linear` value, or a
  local `fn g(st : S1)` that ignores `st`, was accepted silently; top-level
  functions and actor handlers already rejected the same code. It now reports
  "The linear value `st` was never used."

- **Comparing or measuring a fresh string or list no longer leaks it
  (compiled).** `==`, `!=`, `<`, `<=`, `>`, `>=` and `string_length` never
  freed a heap argument that had no other owner. A loop comparing freshly
  built strings grew by one object per comparison, and a two-element list
  leaked six. The interpreter was unaffected.

- **A refinement on a lambda's, a block-level `fn`'s, or an actor handler's
  parameter is no longer assumed inside the body.** No caller was obliged by
  those positions (still true; they are the open coverage holes), but the body
  treated the predicate as a fact anyway, so `let g = fn (n : {Int | n > 0})
  -> need(n)` followed by `g(0)` passed `cap verified`. The body is now walked
  with the refinement stripped, the treatment a non-adoptable `impl` method
  already got. Code that only verified through that unproved assumption now
  fails under `cap verified`; see
  `specs/plans/2026-09-13-refinement-enforcement-holes-plan.md` for the phases
  that turn each position into an actual contract.

- **`send(self, msg)` inside an actor handler now delivers.** It silently did
  nothing on both backends and still exited 0. The interpreter stopped the
  handler at the send, and compiled code dropped the message. `self` was never
  actually bound to the actor's pid, so it resolved to the `self` builtin
  function instead. Both `self` and `self()` are now the handler's own pid, the
  same value `spawn` returned.

- **`self` inside an actor handler compiles.** It was a real builtin in the
  interpreter but missing from the compiled backend's builtin table, so the
  emitter produced a call to an undefined symbol and *any* compiled program
  naming `self` failed to link. The runtime accessor it should have pointed
  at existed but returned the wrong thing — a scheduler process pointer
  rather than the actor pointer a pid actually is — which nothing could
  notice while no compiled program could reach it. Both are fixed, and
  `self` outside a handler now fails loudly instead of yielding a stray
  address. Sending *to* `self` still does not deliver, on either backend;
  that is tracked separately.

- **`always_linear` tracking no longer depends on declaration order.** The
  registry of always-linear type names was filled only as declarations were
  checked, in order, so a function checked *before* the type's declaration saw
  an ordinary type and lost both halves of the guarantee: reusing a linear
  value and abandoning one were each silently accepted. Top-level types were
  affected as much as nested ones. Pass 1 now seeds the registry before any
  body is checked. The same change routes the let-binding promotion through
  the shadow-aware lookup, so a nested `always_linear` type no longer infects
  an unrelated type of the same name declared in the current module — a false
  positive on ordinary code that the ordering hole had been masking.

- **An actor handler's parameters are tracked for linearity.** They were bound
  without the promotion a named function's parameters get, so a linear value
  arriving in a message could be duplicated or dropped by the handler with no
  diagnostic at all — the sender's half of the documented zero-copy-move idiom
  was enforced and the receiver's was not. Storing the parameter into the
  returned state counts as consuming it, so an actor that holds a resource
  needs no special case.

- `march --fmt` dropped the `end` that closes a `choose by … :` block inside a
  `protocol`, so formatting a file with a choice produced a program that no
  longer parsed (the loop's `end` closed the choice and the protocol's `end`
  closed the loop). The formatter now emits it; a round-trip regression pins
  the shape.

- **`Vault.new(name)` on an already-registered name returned a fresh, empty
  table in the interpreter** but the existing table compiled, silently
  orphaning the first table's data when run interpreted. Both backends now
  return the same table (ETS semantics).
- **`Err(File.NotFound(p))` can be matched on a file error.** The `file_*` /
  `dir_*` builtins return `File.FileError`, but a cross-module constructor was
  registered under a qualified parent type (`File.FileError`) while every
  annotation and builtin signature denotes the canonical bare name, so the two
  never unified ("expected `FileError` but got `File.FileError`") and a bare
  `NotFound(p)` resolved to the DNS constructor of the same name. Compiled
  `to_string` of such an error rendered `#<tag:N>` for a second reason, fixed
  in the entry below.
- **The interpreter's `file_rename` error now names the path**, as the
  compiled runtime and every other file builtin already did.
- **A record type declared in one typecheck no longer changes a later,
  unrelated one's diagnostics.** The display-only record-name index was
  process-global; it is now carried per-check on the typing environment. This
  affected the test suite, the LSP and the REPL, where several checks share one
  process.
- **`march test --coverage` no longer reports above 100%.** The evaluator
  records every evaluated expression, test bodies included, while the
  denominator deliberately skips them; the numerator is now intersected with
  the walked node set, so hits can never exceed the total.
- **The formatter breaks a too-wide list or record literal across lines.** It
  had a column budget but no multi-line renderer for literals, so a long list
  of records was emitted as one enormous line. A literal that fits is
  unchanged. A single element wider than the budget still overflows.
- **A compiled call to `worker` / `dynamic_supervisor` / `Supervisor.spec` /
  `Supervisor.start_child` is rejected with a positioned error** naming the
  `supervise do … end` alternative, instead of failing at link time with
  `Undefined symbols: _worker`. That value-level supervisor DSL is
  interpreter-only. A user function named `worker` is unaffected.
- **A `--test` build no longer silently drops a sibling test file that fails
  to parse.** `forge test` compiles one entry and discovers the rest via
  `MARCH_LIB_PATH`; an unparsable sibling used to be dropped with a stderr
  note, so the suite ran fewer tests and reported 0 failures. Under `--test`
  it is now a positioned error and the build fails. Ordinary builds, the REPL
  and the LSP keep tolerating unparsable files on the lib path.
- **Cross-compilation now links `tweetnacl.c`.** The cross-compile driver's
  runtime list omitted it (ed25519 for hot-reload ACTIVATE verification);
  found by the new `scripts/check-runtime-sources.sh`.
- **A value whose type is erased at the render site now prints its
  constructor name.** Compiled `to_string` and `~H` interpolation of a value
  that reaches the renderer through a closure stored in a container, a generic
  `List(a)` field, or a polymorphic `${x}` hole printed `#<tag:N>`, and a
  genuine `IOList` in such a hole was stringified instead of flattened as
  markup. Every boxed constructor header now carries a type id in its
  previously unused pad word, so the runtime can tell apart two types that
  share a constructor tag without needing a static type; the stamp folds into
  the existing tag store and costs no extra instruction at `--opt 2`. Niche
  `Option`, single-field wrapper types, tuples and anonymous records still
  render `#<tag:N>` — they have no cell of their own to stamp.
- **Installing one version of a dependency no longer destroys another.** The
  cache was keyed by dependency NAME alone, so every project on a machine
  shared one directory per name. A registry install did an unconditional
  `rm -rf` of it with no check at all, so `forge deps` in a project wanting
  `bastion 0.3.1` silently deleted the `bastion 0.2.0` tree another project was
  building against, which then failed with `Unknown module` for everything that
  dependency provided. Installs now live at
  `~/.march/cas/deps/<name>/<coordinate>` — the resolved commit for a git
  dependency, the exact version for a registry one — so versions coexist, and
  `forge.lock` is read at build time to select the right one. An existing flat
  install is migrated on the next `forge deps` rather than re-downloaded.
- **`forge.lock`'s `hash` field had two incompatible meanings.** For a registry
  dependency it was the published checksum of the `.tar.gz`; for a git
  dependency it was a hash of the extracted source tree. No single integrity
  check could cover both, including the one the code has claimed to perform in
  a comment since it was written. `hash` is now uniformly the tree hash for
  every dependency kind, a new optional `checksum` field carries the registry's
  published digest as provenance, and a `[lockfile] version = 2` marker lets a
  reader tell an old file's registry `hash` from a new one's. Older lockfiles
  are still read.
- **Compiled `to_string` of a file error names its constructor.** `file_read`
  on a missing path printed `#<tag:0>` compiled where the interpreter printed
  `NotFound("/path")`, and the same for the twelve other `file_*` / `dir_*`
  builtins. `mod File`'s `ptype FileError` lowers to the TIR name
  `File.FileError`, but every builtin signature denotes it by the canonical
  bare `FileError`, so the constructor-name descriptor was looked up under a
  name it was not keyed by and the value fell through to the untyped
  renderer. The runtime now stamps the error cell it builds with that type's
  header id, so the renderer identifies the value from the cell itself rather
  than from a name it could not resolve. The `List` and `Result` cells the
  runtime builds are stamped the same way, so a `file_read` error reaching a
  renderer through an erased slot now prints
  `Err(NotFound("/path"))` instead of `#<tag:1>`. The `file_*` / `dir_*`
  regression table is tightened from "either form" to byte equality with the
  interpreter.

### Changed

- **`cap no_alloc` and `@[no_alloc]` are one check.** `cap no_alloc` now puts
  every function in the module (nested modules, impl methods and actor
  handlers included) under a hard `@[no_alloc]` contract, judged on the
  compiled program; the syntactic walk that used to answer for the cap is
  gone. A module whose function calls an allocating helper is now rejected,
  and one that builds a constructor the compiler reuses in place is now
  accepted. An explicit `@[no_alloc(warn)]` (or `assume`/`transient`) on a
  function inside the module overrides the cap. `march --check` and
  `march check` now report both forms, lowering the program when it contains
  either (about 0.9 s extra on a small file, nothing for programs without
  them); the interpreter, `--jit`, the REPL and `march test` print one
  `no_alloc_unchecked` hint instead of judging.
- **`cap no_panic` accepts a guarded `Array.get`/`set`/`pop`.** They were
  banned outright; they now join `List.nth` and friends in the proof-checked
  set, so a call whose bounds guard proves the contract is accepted, and an
  unguarded or off-by-one one is still a panic error.
- **Non-recursive `@[measure]`s reach the solver as definitions, not
  quantified axioms.** A measure whose arms call no measure is encoded as a
  plain `define-fun`. Under the axioms z3 answered satisfiable queries over
  such a measure only at its 3 s timeout, as `unknown`, which cost cold
  checks minutes and left the obligation skipped; the same queries now
  decide in milliseconds. Recursive and set-valued measures are unchanged.
- **A compiled program that segfaults now says where.** A fatal SIGSEGV or
  SIGBUS used to exit 139/138 with nothing on stderr. It now prints one
  `march: fatal …` line first: signal, fault address, program counter, the
  running green thread, and whether the address was in that thread's stack
  guard page (overflow). The exit status is unchanged.

- **Pull requests must not carry `docs/pagefind/`.** The search index is
  bot-owned; CI rejects a PR that touches it (fix: `git checkout origin/main --
  docs/pagefind`). This ends the merge conflicts between any two docs PRs.
- **`runtime/sources.list`** classifies every runtime C file by role, and CI
  checks the compiler drivers, the JIT link list and every dune rule against it.
- The nightly quarantine job derives its alias list from the dune files instead
  of a hand list that had named three deleted aliases for a month.


### Documentation

- **The linear-types chapter no longer describes four fixed bugs as open.**
  It told readers that an `affine` parameter keyword is a parse error, that a
  parameter-bound record's linear field is only warning-checked, that a
  same-named plain type inherits `always_linear`, and that a `linear` return
  type doesn't reach a plain `let`. None of that has been true since July.

[Unreleased]: https://github.com/march-language/march/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/march-language/march/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/march-language/march/releases/tag/v0.1.1
