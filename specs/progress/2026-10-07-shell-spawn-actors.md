# The remote shell spawns the program's own actors

Date: 2026-10-07. Follows `2026-10-07-shell-calls-node-functions.md` (linking a
fragment against the node's functions). Removes "a program-defined actor
cannot be spawned from the shell" from `docs/observe.md`'s "not there yet".

## What happened before

Against `test/native/shell_node.march` (`actor Counter`), a session of

```
let k = spawn(Counter)
send(k, Bump(5))
Actor.inspect_state(debug, k, 500)
```

compiled and ran, but spawned the WRONG actor:

```
k : Pid({ n : Int })
Some(())
Err(InspectFailed("no state renderer for this actor"))
```

and `Recon.info(intro, 1)` gave the shell-spawned actor an empty type name
where the node's own Counter (pid 0) says `Counter`.

## Root cause

The fragment carried its own copy of the actor: `Counter_spawn`,
`Counter_dispatch`, `Counter_Bump` and the inspect registration were all
compiled into the fragment's `.so` (`nm frag-0.so`), because the node had no
`Counter_spawn` to link against: the node's optimiser inlines the spawn fn
into `main` and drops it, so it was never in the shell identity table's `x`
rows (`Counter_dispatch` is there in the binary but is a hot-reload slot,
deliberately not linkable). So the actor:

- ran the fragment's handler code, with `dispatch_name_id` 0 (a fragment is
  emitted without a hot-reload config, so the alloc never calls
  `march_actor_set_dispatch_id`): no slot, no type name, and no deploy would
  ever upgrade it, since `hcr_snapshot` walks actors by `dispatch_name_id`;
- had no state renderer: the inspect table is keyed by the dispatch closure
  in the actor record's word 2, and the fragment's registration did not
  match its record's key (not dug into further: a fragment is emitted with
  no static closures, as for any REPL/JIT code, so the two references to
  `Counter_dispatch` likely built two closures; with the node's spawn fn
  this path is gone);
- would have kept running the fragment's code for ever (fragments are never
  dlclosed, so it did not crash when the session ended, but it was not the
  node's actor in any useful sense).

## Design

The spawned actor must run the node's code. The fragment calls the node's
own spawn fn rather than copying it:

- **Node side (`bin/main.ml`)**: a shell node's build (the same condition that
  emits `__march_shell_ident`: `--compile --hot-reload`, not `--compile-so`)
  roots `<Actor>_spawn` for each of the program's own actors (those whose
  `<Actor>_dispatch` is a slot, `Hot_reload.is_slot_actor_dispatch`; the
  stdlib's actors are left alone) through the contract pipeline's
  `extra_roots`. Rooting only stops DCE dropping it; callers still inline
  it, and its body is optimised as before. Being an ordinary non-slot
  function with recorded parameter modes, it then lands in the `x` rows by
  the existing rule (`Shell_ident.node_fns`), e.g.
  `x Counter_spawn ptr() -`.
- **Client side**: nothing new is needed to link it: `Shell_ident.linkable`
  picks `Counter_spawn` like any other node function, and after linking,
  the fragment's prune drops the copied dispatch, handlers and inspect
  registration. The node's `Counter_spawn` allocates the record with the
  node's static dispatch closure, calls `march_actor_set_dispatch_id` (it is
  node code, emitted with the hot-reload config), registers the node's
  renderer and call tags: the actor is indistinguishable from one `main`
  spawned.
- **Refusal (`Repl_jit.shell_compile`)**: if a fragment would still carry a
  slotted actor's `<Actor>_dispatch` after linking (a node built before this
  change, `MARCH_SHELL_NO_LINK`, or an actor whose init parameters are not
  plain types, e.g. a function, which `linkable` never links), the input is
  refused with "this input spawns actor X, but cannot call the node's
  X_spawn ...", rather than spawning an actor running the shell's code.

Lifetime: the actor is the node's; it does not reference the fragment's
code, so it outlives the session (tested) and a deploy reaches it like
any other Counter (by `dispatch_name_id`, the same field `Recon` reads for
its type name, which the test checks; a hot deploy against a shell-spawned
actor was not run end to end).

Capabilities: spawning an actor needs no capability in the program, and
none here. The fragment's manifest still counts the capabilities the
actor's handlers use: `reached_caps` is taken over the whole self-contained
reach set before linking, so linking `Counter_spawn` adds the caps its copy
would have carried, exactly as for any other linked function.

## Tests

`test/dune` `native_shell_session.out` (expected
`test/native/shell_session.expected`):

- `test/shell/session.txt` gains `let k = spawn(Counter)`, two sends,
  `Actor.inspect_state(debug, k, 500)` -> `Ok({ n: 12 })`, `Actor.list` ->
  `[Pid(0), Pid(1)]`, and `Option.map(Recon.info(intro, 1), fn a ->
  a.type_name)` -> `Some(Counter)` (on the slot).
- A second session (`test/shell/session_after.txt`) finds pid 1 alive,
  sends `Bump(100)` and reads `Ok({ n: 112 })`: the actor outlived the
  session that spawned it.
- A third session with `MARCH_SHELL_NO_LINK=1` (`test/shell/session_nolink.txt`)
  shows the refusal and that no actor was spawned.

RED proof: with `bin/main.ml` and `lib/jit/repl_jit.ml` restored from
origin/main by file copy, the same golden differs in exactly the spawned
actor's lines: `Err(InspectFailed("no state renderer for this actor"))` for
both inspects, and `Some()` for the type name.

All four shell goldens (`native_shell_{session,node,skew,link}.out`) pass,
and `scripts/run-tests.sh -q compiler`.

Not done: ASAN. On this macOS box an ASAN build of the node spins forever in
`__asan::InitializeShadowMemory` (dyld shared-cache iteration) before
`main`, independent of this change. No RC or ownership code was touched;
the fragment's call to `Counter_spawn` uses the node's recorded parameter
modes like every linked call.
