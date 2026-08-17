# Same-named actors across modules can trigger a spurious grant error

Filed while fixing the actor grant bypass
(`specs/progress/2026-08-16-actor-handler-grant-bypass.md`). This is a
FALSE POSITIVE — it rejects valid code. It is SOUND (over-approximation:
it can only over-charge the grant, never mask a leak), so it is a UX bug,
not a security bug.

## Repro (single compilation unit, two modules, same bare actor name)

```march
mod Safe do
  needs IO.Console
  actor Worker do
    state { n : Int }  init { n: 0 }
    on Go() do println("safe") { n: state.n + 1 } end
  end
  fn run() : () do let _p = spawn(Worker) () end
end

mod Danger do
  needs IO.FileWrite
  actor Worker do          -- SAME bare name, different module
    state { n : Int }  init { n: 0 }
    on Go() do let _ = file_write("/tmp/x", "x") { n: state.n + 1 } end
  end
end

mod App do
  use Safe
  needs IO.Console
  fn main(cap : Cap(IO.Console)) : () do
    Safe.run()             -- only Safe.Worker is spawned; Danger.Worker never is
  end
end
```

`--check` wrongly rejects: `` `main` is granted `Cap(IO.Console)`, but the
program reaches `IO.FileWrite` (reached from `main`: main → Safe.run → Worker
→ Worker_Go) ``. The cited chain is also misleading — it points at `Safe`'s
`Worker` but the `IO.FileWrite` is `Danger`'s.

Only reproduces when both actors are in the analyzed set (same file, or both
imported). A dependency that merely sits on `MARCH_LIB_PATH` without being
`use`d does not trigger it.

## Root cause

Actor message handlers are keyed by the actor's BARE name
(`<Actor>_<Msg>` = `Worker_Go`) in `env.cap_closures`, per the C1 fix
(2026-08-06) which chose bare keying to match TIR's `lower_handler` naming.
Two same-named actors in different modules therefore share the key
`Worker_Go`, and `record_fn_caps` UNIONs their capability closures. The
2026-08-16 grant fix bridges the actor-name node to `Worker_Go` and makes it
reachable from `main`, so spawning EITHER `Worker` now pulls in the merged
caps of BOTH.

The bare keying predates the grant fix; the grant fix is what makes the merge
observable (previously the merged closure was never reached from `main`).

Note two same-named cross-module actors DO compile and link (verified), so
this is valid code — TIR must disambiguate the handler symbols somehow even
though the cap-closure keying does not. That mismatch is the real defect.

## Fix direction

Key handler capability closures (and the grant bridge) by whatever name TIR
actually emits for each handler after cross-module disambiguation, not the
bare `<Actor>_<Msg>`. This needs the TIR handler-naming/collision-renaming
logic (lib/tir/lower_actor.ml, and the collision_set handling) as the source
of truth, and must stay consistent with the HCR manifest format that also
asserts the bare spelling. Until then, the over-approximation stands: it is
sound, and the workaround is to not reuse an actor name across two modules in
one build, or to widen the grant.
