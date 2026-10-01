`[P2]` A user actor named like a stdlib actor crashes the compiler

Filed 2026-09-30 while making stdlib actors non-slots
([../progress/2026-09-30-stdlib-actors-not-hot-reload-slots.md](../progress/2026-09-30-stdlib-actors-not-hot-reload-slots.md)).

Actor glue is bare-named (`<Actor>_Msg`, `<Actor>_dispatch`, ...) whatever
module declares it, so an app actor named `Writer`, `Anchor`, `Endpoint`,
`RegWatch`, `HostWatch` or `ClusterNodeActor` collides with the stdlib's. On
main (49b92ce1a), with or without `--hot-reload`:

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

`march --emit-llvm app.march` exits 3: `internal compiler error:
Failure("actor-message tag table has no row for Anchor_Msg.Bump")`. Interpreted,
it prints `ok`. The flat actor namespace should
either qualify stdlib actor glue or reject the collision with a diagnostic.
