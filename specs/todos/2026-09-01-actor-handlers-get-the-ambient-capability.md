# Capability mocking does not reach an actor handler

Filed 2026-09-01, out of the capability-passing work (#389). The doc table in
`specs/lang/capabilities.md` lists this as a known hole; this is the precise
mechanism, because the hole is much narrower than "actors cannot be threaded"
and the fix is correspondingly smaller.

## Reproducer

```march
mod A do
  needs IO.Console
  actor Logger do
    state { n : Int }
    init  { n: 0 }
    on Say(s : String) do
      print_line("ACTOR:" ++ s)
      { state with n: state.n + 1 }
    end
  end
  pfn direct() : () do print_line("DIRECT:hi") end
  fn main(c : Cap(IO.Console)) do
    let mock = cap_impl(c, { cap_ops_empty(c) with
      print_line: Some(fn s -> print("MOCK[" ++ s ++ "]\n")) })
    with_cap(mock, fn _ -> do
      direct()
      let p = spawn(Logger)
      send(p, Say("hi"))
      run_until_idle()
    end)
  end
end
```

`march --compile --test` prints:

```
MOCK[DIRECT:hi]
ACTOR:hi          <- should be MOCK[ACTOR:hi]
```

## What is actually happening

Everything except the last step already works. From `--dump-tir --test`:

```
fn Logger_dispatch(linear $actor : Logger_Actor, $msg : Logger_Msg) : Unit =
  case $msg of
  Say($Say_s) -> ...
    __march_dispatch_print_line(root_cap, $t30216_i13602);
```

- The handler IS credited with the capability — `MARCH_DUMP_CAP_PASSING=1`
  shows `Logger_Say  IO.Console`.
- The operation IS rewritten to route through the dictionary wrapper.
- The handler body is inlined into `Logger_dispatch`.
- **`Logger_dispatch` is excluded from threading**: the actor record holds it
  as `$actor.$d_dispatch`, so it is referenced other than as a call head and
  the `unsafe` rule freezes its arity — correctly, since the scheduler calls it
  through that field.

So the wrapper is called with `root_cap`, the ambient sentinel, and reads back
`None`. Nothing is broken; the dispatch function simply has no capability to
supply.

## The fix, and why it is not a one-liner

The capability must reach the dispatch function from somewhere the scheduler
does not mediate. The natural source is the SPAWN SITE: `spawn(Logger)` runs in
a scope that does have the threaded capability (in the reproducer it is inside
`with_cap`). Capture it there into the actor record and have `Logger_dispatch`
read `$actor.$cap_IO_Console` instead of passing `root_cap`.

There is precedent for the shape — the actor record already carries synthetic
fields (`$d_dispatch`, `$e_alive`) alongside the user's declared state.

What makes it more than a table entry: the actor STATE RECORD is reasoned about
by `migrate_state`, hot reload and `@compat`, so adding a hidden field per
capability is a layout change with three consumers that all have opinions about
layout. That is the work, and it wants its own design pass rather than a
bolt-on.

## Scope note

Only `--test` builds are affected, since that is the only place the elaboration
runs. In a release build an actor handler behaves exactly as it always has.
