# Actor-system hardening, phase 2: the distributed plane

Filed at the close-out of the actor-system-hardening plan
(`.superpowers/sdd/2026-08-11-actor-system-hardening/`, Tasks 1-16 + 12b).
Phase 1 hardened the single-node actor runtime end to end (bounded mailboxes,
observability, call-storm/late-reply correctness, proc/registry/VMA scaling,
send-path locking, supervision timing/backoff) and is validated by
`scripts/actor-load.sh`'s four-scenario harness. The plan's self-review
explicitly scoped the distributed plane (cross-node messaging, monitors, and
migration) out of phase 1; this file is that deferred scope, so it isn't lost.

## Items

1. **Per-peer flow control.** Cross-node sends currently have no
   backpressure mechanism analogous to phase 1's bounded local mailboxes
   (`Actor.set_queue_limit`, Task 7-9) — a slow or stalled peer connection can
   accumulate unbounded outbound queue growth on the sending node. Needs a
   per-peer credit or window scheme, plus a policy decision for what happens
   at the limit (drop, block the sender, disconnect the peer).

2. **Control/data connection split.** Distributed control traffic (monitor
   fires, node up/down, capability revocation propagation) currently shares
   the same connection(s) as ordinary message traffic. A control-plane
   message queued behind a burst of large data-plane messages can be
   delayed arbitrarily — e.g. a `MONITOR_FIRE` notification (see item 3)
   sitting behind megabytes of in-flight actor messages. Splitting into a
   dedicated low-latency control channel per peer removes this coupling.

3. **MONITOR_FIRE delivery guarantees.** `march_dist_monitor_fire_pid`
   (called from `do_actor_death`, `runtime/march_runtime.c:3104`) sends a
   best-effort notification to remote watchers; there is currently no
   retry, ack, or at-least-once guarantee if the fire is lost to a
   transient network issue or arrives before the peer has finished
   registering the monitor. Local monitors (same file, `:3087`-`:3099`) are
   synchronous and unconditional; the remote path has no equivalent
   reliability story. Needs a decision on the delivery contract (at-most-once
   is the current de facto behavior; decide whether at-least-once is
   required and what dedup key that implies).

4. **Declaration-site `mailbox N policy` syntax.** Task 7-9 shipped
   `Actor.set_queue_limit(pid, limit, policy)` as a runtime call. The plan's
   ergonomics goal was also a declaration-site form (e.g. `actor Foo do
   mailbox 1000 drop_old ... end`) so bounds are visible in the actor
   definition itself rather than requiring a separate call after spawn.
   Parser/typecheck/desugar work; the runtime primitive it would lower to
   already exists.

5. **Full epoch-based proc reclamation, replacing leak-don't-free.** Task 12
   fixed the proc/VMA growth cliff for the *common* churn case (see
   `specs/progress/` for that task's entry — recycling via a free-list) but
   deliberately left proc *structures themselves* on a "peak-concurrency
   cap, never shrinks" design (documented as intentional in the Task 12
   ledger note) rather than true epoch-based reclamation that could return
   memory to the OS after a burst subsides. A full epoch-GC-style scheme
   (hazard pointers or grace-period reclamation, matching how `pid_index`/
   `epoch` already work for capability revocation) would let the proc pool
   shrink after a load spike instead of holding its high-water mark
   permanently.

6. **Interpreter `block` mailbox policy.** `Actor.set_queue_limit`'s
   `block_sender` policy (Task 8-9) is fully implemented and tested in the
   compiled/native runtime (parking the sender via the scheduler) but the
   tree-walking interpreter's `mailbox_enqueue` does not implement the
   parking half — Task 9's ledger note records that unknown/unimplemented
   policy ints are silently treated as unbounded there. Bringing the
   interpreter to parity (or explicitly rejecting `block_sender` at
   typecheck time when targeting the interpreter, if parking isn't feasible
   without a green-thread scheduler) closes that native/interpreted
   behavior gap for anyone testing mailbox backpressure under `march run`
   before compiling.
