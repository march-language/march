# A user `NodeQueue.start_local` call failed the capability ceiling in stdlib `Socket` (fixed 2026-09-30)

Filed 2026-09-25 (`[P3]`) while writing `test/session/cert_authz.march`, whose
fake cluster dictionary needs a real data queue.

**Reproduced on origin/main (771430bf3).** Compiling

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

failed with ``module `Socket` uses `IO.NetConnect` but does not declare `needs
IO.NetConnect` ``. So did the same program with a narrow grant
(`Cap(IO.Console), Cap(IO.Mut), Cap(IO.Spawn), Cap(IO.NetConnect)`), and so did
`test/session/cert_authz.march` without `--no-cap-strict`.

## Cause and decision

The ceiling (`lib/caps/cap_ceiling.ml`, run from `bin/main.ml`) checks every
module's emitted code against that module's own `needs`. Every capped builtin
`stdlib/socket.march` calls (`tcp_connect`, `tcp_connect_timeout`,
`tcp_send_all`, `tcp_recv_chunk`, `tcp_recv_chunk_timeout`, `tcp_recv_timeout`,
`tcp_set_recv_timeout`) is `IO.NetConnect` in `Typecheck_builtins`'
capability table (`tcp_close` is uncapped), but `Socket` declared no `needs`
at all, so any program whose emitted code kept NodeQueue's socket writes
(`NodeQueue.write_frame` -> `NetKernel.write_bytes` -> `Socket.write`) failed,
whatever the program itself granted.

Decision: `Socket` declares what it uses (`needs IO.NetConnect`), like the
other stdlib modules that call capped builtins. The ceiling is not special-cased
for stdlib modules: that would weaken it for every stdlib module. NodeQueue and
cluster_node are unchanged.

## What still rejects

The program's own grant is the ceiling that matters to a user and it is
unaffected: a `main` granted `Cap(IO.Console), Cap(IO.Mut), Cap(IO.Spawn)` but
not `IO.NetConnect` is still rejected, with "the program reaches
`IO.NetConnect` (reached from `main`: main -> NodeQueue.start_local -> ... ->
Socket.write)", before and after the fix.

## Verification

- `test/test_cap_ceiling.ml`: `user NodeQueue.start_local compiles` (grant
  `Cap(IO)`) and `user NodeQueue.start_local, narrow grant` both FAIL on
  origin/main with the `Socket` message and pass on the branch;
  `NodeQueue without IO.NetConnect grant rejected` passes on both and also
  asserts the rejection does not blame `Socket`. 32/32 in `cap_ceiling`.
- `test/dune`: the `cert_authz` rule drops `--no-cap-strict`; its golden
  matches (`dune build --root . test/cert_authz.out`, diffed against
  `test/session/cert_authz.expected`).
