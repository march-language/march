# `[P2]` Distributed actors 4/4: the known small gaps, with fixes

Filed 2026-09-14. Two items already recorded elsewhere, each blocking one of
the other three files, each with a concrete fix proposed here so they stop
being "known".

## A. `node_discovery` is quarantined for a race that has since been fixed

**Tracked as:** `test/node_discovery_quarantined` in
[[2026-07-24-quarantined-tests-coverage-that-is-currently-dark-inventory-2026]],
re-quarantined 2026-08-08 because two actors' `println`s tore on ~1-in-2
ubuntu CI runs (`...peer=node-anode-a: handshake...`). The `test/dune`
comment still says the cause is "a pre-write allocator/GC race", not I/O.

**That diagnosis was superseded on 2026-08-21.**
`specs/progress/2026-08-21-println-writev-not-atomic-across-threads.md`
measured the tear falling *between the two iovecs* of `march_println`'s
single `writev` — POSIX promises no atomicity between competing writers —
and added `march_stdout_mu` around the `writev`. `print_line` compiles to
`march_println` (`llvm_builtins.ml`), so the fixture's output path is now
locked. **Measured today (2026-09-14):** the quarantined golden's binary,
run 60 times directly (not through dune, whose cache would replay one run),
matched the sorted expected output 60/60 with no crash, at load ~8. The
1-in-2 tear is gone locally.

**Why it matters here:** the two-node harness in
[[2026-09-14-two-node-failure-semantics-harness]] prints from both nodes,
and the quarantine's stated reason would apply to every scenario.

**What to do:** un-quarantine by trial, not by argument. Add a CI job that
runs the compiled `node_discovery` binary 200 times on the ubuntu leg (where
the tear was seen) and diffs each sorted run; if it is clean, move the rule
back under `runtest`, delete the stale comment, and record the 08-21 fix as
the reason in the inventory. If it tears, capture the torn output — it is
then a *different* bug from the one the mutex closed, and the
allocator/GC theory gets its first real evidence. One more thing to check
on the way: the memory of a `node_discovery` SIGBUS at ~28/150 on `main`
(2026-09-09) did not reproduce in these 60 runs; the 200-run job settles
whether it was load.

## B. The interpreter cannot park a sender (`block_sender` policy)

**Tracked as:** item 6 of [[2026-08-11-actor-hardening-distributed-plane]].
`Actor.set_queue_limit(pid, n, block_sender)` parks the sending green
thread natively; the tree-walking interpreter's `mailbox_enqueue` treats
the policy as unbounded. The flow-control design in
[[2026-09-14-distributed-plane-flow-control-and-control-channel]] offers the
same policy for remote sends and inherits the gap.

**Fix, the honest one:** reject at typecheck time, not at runtime. The
interpreter is the `march run` / test backend; a program relying on
`block_sender` backpressure silently gets none there and then behaves
differently compiled — the worst kind of parity gap. The typechecker
already knows the target backend for interpreter-only builtins
([[2026-09-11-interpreter-only-builtins-rejected-at-lowering]] did the
reverse direction); do the same here: `block_sender` under the interpreter
is a hard error naming the flag ("`block_sender` needs the native scheduler;
compile this program, or use `drop_new`/`drop_old` under `march run`"). The
re-entrant alternative (run the target from inside `send` until it has
room) was judged too risky in the 2026-09-10 review and nothing has changed
that.

**Shipped 2026-09-14**, one step short of the proposal: the refusal is at the
*call* in the interpreter (`eval_builtins.ml`, `actor_set_mailbox_limit` with
policy 3 raises with a message naming `drop_new`/`drop_old` and "compile this
program"), not at typecheck. The policy is a runtime `Int`, so a static check
would only catch the literal spelling; the call-site refusal catches every
spelling and costs nothing. Unit test in `test_stdlib_suite.ml`
("block_sender refused under the interpreter"), proved to fail with the arm
disabled. Docs updated in both trees.

## C. Declaration-site `mailbox N policy` (item 4 of the hardening file)

Not blocking anything above; listed so the set is complete. A parser +
desugar slice lowering to `actor_set_mailbox_limit` after each spawn site.
Do it when a fixture wants it; the runtime primitive exists.
