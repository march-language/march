`[P3]` A user-level `NodeQueue.start_local` call fails the capability ceiling in stdlib `Socket`

Found while writing `test/session/cert_authz.march` (dd step 11b), whose fake
cluster dictionary needs a real data queue for `queue_for`.

Repro (the compiler at the step-11b branch; nothing in it is step-11b code):

```march
mod Sl do
  needs IO
  needs IO.Console
  needs IO.Mut
  needs IO.Spawn
  needs IO.NetConnect
  fn main(_c : Cap(IO)) do
    let _q = NodeQueue.start_local(fn _ -> ())
    println("ok")
  end
end
```

`march --compile` fails with:

```
module `Socket` uses `IO.NetConnect` but does not declare `needs IO.NetConnect`.
```

`stdlib/socket.march` declares no `needs` at all. The same queue made inside
`ClusterNode.start` compiles, so the ceiling walk charges a direct user call
differently from one mediated by a module that declares `needs IO.NetConnect`.
Either `Socket` should declare what it uses, or the ceiling should treat it as
the other stdlib modules are treated; decide which after reading
`Typecheck_modcaps`. Until then `test/dune` compiles `cert_authz` with
`--no-cap-strict` (the comment on that rule points here).
