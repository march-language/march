`[P2]` A user actor named like a stdlib actor crashes the compiler (fixed 2026-09-30)

Filed 2026-09-30 while making stdlib actors non-slots (the
`2026-09-30-stdlib-actors-not-hot-reload-slots` work). The todo was never
committed on its own; this file records both the report and the fix.

**Report.** Actor glue is bare-named (`<Actor>_Msg`, `<Actor>_dispatch`,
`<Actor>_spawn`, handlers) whatever module declares it, and the stdlib is loaded
whole, so an app actor named `Anchor` (Topology), `Writer` (NodeQueue),
`Endpoint`/`HostWatch`/`OfferActor`/`ApInbox` (SessionNode) or
`CtlWriter`/`RegWatch`/`ClusterNodeActor` (ClusterNode) collided with the
stdlib's. On main (67d7d37ae):

```march
mod App do
  needs IO
  actor Anchor do
    state { n : Int }
    init { n: 0 }
    on Bump() do { n: state.n + 1 } end
  end
  fn main(cap : Cap(IO)) do
    let w = spawn(Anchor)
    send(w, Bump())
    println("ok")
  end
end
```

`march --emit-llvm app.march` exited 3: `internal compiler error:
Failure("actor-message tag table has no row for Anchor_Msg.Bump")`
(`Llvm_toplevel.actor_msg_tag_table`).

**Wider than the ICE.** The regression fixture
(`test/native/user_actor_named_like_stdlib.march`: app `Anchor`, `Writer`, a
nested `ClusterNodeActor`, and a live `NodeQueue.start_local` queue) showed two
more failures with the fix disabled:

- `--compile` rejected the app with capability-ceiling errors (`module Net uses
  IO.Clock / IO.Mut ...`): the typechecker's actor-keyed capability tables
  charged the app's nested `ClusterNodeActor` the stdlib one's needs;
- interpreted, it "ran" but was wrong: `Writer written = 7` instead of 12.
  NodeQueue's own `spawn(Writer)` spawned the APP's Writer, so the stdlib queue
  never delivered its frame. The report's "interpreted, it runs" was a silent
  miscompile, not a working backend.

**Options.** (a) Reject the collision with a diagnostic: rejected, because
the stdlib is loaded whole, so it would forbid nine names in every program,
including ones that never touch Topology or ClusterNode, and every new stdlib
actor would break someone's app. (b) Qualify the stdlib side: chosen.

**Fix.** `Desugar_actor_names` (which already renamed same-named nested actors
within one file, 2026-09-28) now qualifies EVERY actor of a standard-library
file, root-level ones included, with the file's module path joined by `__`:
`Topology__Anchor`, `NodeQueue__Writer`, `SessionNode__Endpoint`,
`ClusterNode__ClusterNodeActor`, ... Its existing lexical reference rewriting
(spawn targets, supervise child types, `<Actor>.Msg` types) carries the
in-file references (`spawn(Anchor)` -> `spawn(Topology__Anchor)`). No stdlib
actor is referenced from another file, and no runtime C, test or tool names a
stdlib actor's glue symbol.

App actors are untouched: a user file's actors keep their bare names unless
they collide with a sibling in the same file (unchanged rule), so
`spawn(X)` -> `X_spawn`, the hot-reload manifest, `.schemas.json` and dispatch
slot names spell app actors exactly as before.

**Provenance, not names.** Whether a file is the stdlib's is loader provenance:
desugar cannot depend on the typechecker, so
`Desugar_actor_names.is_stdlib_file` is a hook the stdlib loaders install as
`Typecheck_builtins.file_is_stdlib` next to their `note_stdlib_root`
(`bin/toolchain.ml`'s `load_stdlib`, `lsp/lib/analysis.ml`'s `load_stdlib`),
before any stdlib file is parsed. The stdlib AST cache is keyed on the compiler
identity, so no blob with the old spelling is reused. The default (nothing is
the stdlib's) applies to test harnesses that load single stdlib files without
a root; they keep the bare spelling consistently.

**Interaction with the stdlib-actors-not-slots work.** That change decides
slot-ness by loader provenance keyed by fn name, and lets a user's claim win
when the same bare name is recorded from both sides. With this fix a stdlib
actor's fns never share a bare name with a user's, so that tie-break no longer
arises. A test there that looks for `@Writer_dispatch(` as the STDLIB Writer's
symbol would need `@NodeQueue__Writer_dispatch(`.

**Visible in diagnostics.** A stdlib actor appears under its qualified name in
any message that names it (e.g. a capability chain through
`NodeQueue.NodeQueue__Writer`).

**Verification.**
- `test/native/user_actor_named_like_stdlib.march`, compiled
  (`native_user_actor_named_like_stdlib`) and interpreted: prints `Anchor n =
  2`, `Writer written = 12`, `ClusterNodeActor beats = 42`. Both rules go red
  with the hook disabled (compile error; interpreted wrong total).
- `test_compiler` `desugar` "stdlib actors qualified": the stdlib provenance
  renames `Box` -> `Topo__Box` and `Inner.Box` -> `Inner.Topo__Inner__Box` and
  every `spawn` to them; the same source as a user file keeps the root `Box`.
  Red with the hook ignored.
- The report's repro (`actor Anchor`) and an app `Writer` alongside
  `NodeQueue.start_local`: `--emit-llvm` shows `@Writer_dispatch` and
  `@NodeQueue__Writer_dispatch` side by side; compiled and run, correct.

**Not covered.** A user actor literally named `Topology__Anchor` would still
collide (the pass only avoids names within one file). Cross-file collisions
between two USER library files (via `MARCH_LIB_PATH`) are still unhandled, as
the 2026-09-28 entry notes.
