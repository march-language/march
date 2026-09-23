# Distributed deploys, build step 2: unforgeable local references (`Actor.Introspect`)

**DONE 2026-09-22.** Section 1, II.1 and D31 of
[../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md).
Builds on G3 (`Typecheck_builtins.stdlib_only`,
[2026-09-22-stdlib-only-builtins.md](2026-09-22-stdlib-only-builtins.md)) and G2
([2026-09-22-cap-narrowed-signature-grant-test.md](2026-09-22-cap-narrowed-signature-grant-test.md)).

## What landed

- `stdlib/actor.march` declares `proof cap Introspect` and the one minting function
  `Actor.introspect(io : Cap(IO)) : Cap(Actor.Introspect)` (`mint_cap(io)`, so Check 6
  makes `Actor` the only minter). The four operations that turn something anyone can
  write down into a Pid take the cap as their first argument:
  `Actor.pid_from_int(c, n)`, `Actor.whereis(c, name)`, `Actor.registered(c)`,
  `Actor.list(c)`, and through `list`, `Actor.top_by_mailbox(c, n)` and
  `Actor.over_mailbox(c, t)`. `Actor.register`/`unregister` are unchanged.
- `Typecheck_builtins.stdlib_only` is populated: `pid_of_int`, `actor_pid_indices`,
  `actor_whereis`, `actor_registered`, each suggesting its wrapper and naming
  `Actor.introspect`. A user reference is
  ``` `pid_of_int` is internal to the standard library; use `Actor.pid_from_int(cap, n)` (see `Actor.introspect`) ```.
- **Every stdlib loader registers what it loaded.** `Typecheck_builtins.stdlib_span_files`
  (moved from `bin/main.ml`) and `note_stdlib_decls` (a union into
  `stdlib_source_files`) are called by `Toolchain.load_stdlib` (both the AST-cache hit
  and miss paths; this covers `compile`, `--check`, `march test`, `march check`, the REPL
  and its JIT, `warm-cache`, the DAP) and by the LSP's `Analysis.load_stdlib` (so
  `Typecheck_cache.base_env` checks the stdlib with the set populated). Forge does not
  typecheck in process (it shells out to `march check`); `lib/search` reads the builtin
  tables only. The compile driver still sets the ref itself at its check site, as before.
- **A shipped stdlib module named on the command line is the stdlib's for the gate.**
  `march --check stdlib/actor.march` spells the entry as the command line did, not as
  `load_stdlib` stamped its own copy, so the set did not contain it and the gate rejected
  the module's own `pid_of_int`. The driver now adds the entry (and `march check`'s files)
  when `is_shipped_stdlib_file`; `user_diag_file` tests the entry first, so its
  diagnostics still show.

## The wrapper is `pid_from_int`, not `pid_of_int`

The plan wrote `pid_of_int(c, n)`. A module-level `fn pid_of_int(c, n)` whose body calls
the builtin `pid_of_int(n)` *typechecks* against the builtin (exit 0) but *runs* the
module's own function on both backends: the interpreter recurses into an arity error and
the compiled program fails in clang. The typechecker and the runtimes disagree on what a
bare name means when a module function shadows a builtin; that is a separate bug
(t168 pins the typecheck side of shadowing), so the wrapper got its own name.

## Deviations from the todo, and why

- **`cluster_node.march` and `session_node.march` keep their raw `pid_of_int` calls**
  (17 and 2 sites) instead of minting in `ClusterNode.start` and carrying the cap in
  `ClusterHandle`. `start(cfg)` takes no `Cap(IO)` (the plan's "it already needs
  `Cap(IO)` there" is wrong), so it cannot mint; and `ClusterNodeActor`'s `init` must
  build a placeholder `ClusterHandle` before `Boot` arrives, which no code outside
  `Actor` could give a cap field. Changing `start`'s arity would have touched all 45
  two-node fixtures and the clustering chapter for no enforcement gain: the cap is erased
  at runtime, and the gate exempts stdlib files by construction, so the boundary is the
  same either way. Both modules were nevertheless checked alone: their diagnostics are
  unchanged from before this change.
- `march --check stdlib/actor.march` reports two pre-existing errors
  (`expected Pid but got Pid(q2)` on `top_by_mailbox`/`over_mailbox`'s return
  annotation); the unmodified module gives the identical two under the same compiler,
  and the stdlib self-check ratchet in `test/test_stdlib_march.ml` already pins them.

## Plan corrections made in the same commit

II.1 and II.3 said `Cap(IO.NetListen)` unifies with `Cap(IO)` and that only the grant
walk stops a narrowed caller; section 7's role-body passage repeated it. G2 showed the
opposite: amplifying a cap is a type error, and the walk rejects it independently. All
three passages now say so; D31's conclusion stands. II.1's "Open: no stdlib-only
mechanism" and the `cluster_node` minting bullet were updated to what landed.

## Migration (also in CHANGELOG, Changed)

`fn main(io : Cap(IO))`, `let c = Actor.introspect(io)`, forward `c`; a function taking
it declares `needs Actor.Introspect`; `pid_of_int(n)` becomes `Actor.pid_from_int(c, n)`.
Migrated: 20 `test/native/` goldens (the supervisor-restart and registry tests; expected
outputs unchanged), `test/cap_mock/cap_mock_supervised{,_nested}`,
`test/session/stream_actor{,_events}_supervised`, `test/two_node/hosted_restart/node_b`,
`bench/actors/crash_loop`, `examples/supervision_strategies`, the eval round-trip test in
`test/test_stdlib_suite.ml`, and the `actors.md`/`supervision.md` chapters (docs
regenerated). A `Killer` actor that forged a Pid inside a handler now receives the Pid in
its message; handlers cannot mint and a test actor has no reason to hold the cap.

## Tests

- `test/test_stdlib_only.ml`: the "lands with an empty table" case became "shipped table
  gates the four forging builtins" (names, every suggestion names `Actor.introspect`, and
  `pid_of_int`/`actor_whereis` from user code are errors with the real table).
- Typing corpus: `reject/t287_pid_of_int_without_introspect` (EXPECT-ERROR
  `Actor.introspect`) and `accept/t291_introspect_minted_in_main_forwarded` (mints in
  `main`, forwards, exercises every wrapper); `reject/t158` still rejects on `ActorCap`.
  `dune build @types-check --force`: 411 passed, 0 failed.
- `test/native/pid_of_int_roundtrip.march` now forwards the cap through a helper and is
  the compiled acceptance program; all four migrated cap-mock/session goldens match their
  expected output through their dune rules.

## Follow-up (same day)

`mod Actor` also declares `needs Actor.Introspect`. #591's whole-stdlib ratchet
(`test_compiler.ml`, `check_stdlib_like_cli`) checks every module under a
`StdlibBaseline` wrapper, where a `proof cap` registers as
`StdlibBaseline.Actor.Introspect`, so the declaring-module exemption in Check 1
misses the bare `Actor.Introspect` and counted 7 "not declared in `needs`"
errors for `actor.march` (the same class as all 9 of `session.march`'s
ratchet entries). The declaration is honest on its own and puts the count back
at the 2 pre-existing errors; the harness/registration mismatch is #591's to
revisit.

(Correction, 2026-09-23: the diagnosis above is wrong. The cap registers as
`Actor.Introspect`; the exemption missed it because a NESTED module's Check 1
ran against the outer env, before its own proof caps were registered. Fixed in
the typechecker and the `needs Actor.Introspect` line removed; see
`2026-09-23-nested-module-own-proof-cap-exemption.md`.)

## Not done

- Cross-node references (`GlobalPid.make`, `GlobalRegistry.lookup`) are untouched until
  section 3's certificates exist (as the plan says).
- The typecheck/runtime disagreement on a module-level function shadowing a builtin
  (above) is not fixed here.
