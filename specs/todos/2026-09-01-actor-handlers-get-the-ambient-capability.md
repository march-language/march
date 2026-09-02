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

## Two ways to get the capability there

The capability must reach the dispatch function from somewhere the scheduler
does not mediate. The natural source is the SPAWN SITE: `spawn(Logger)` runs in
a scope that does have the threaded capability (in the reproducer it is inside
`with_cap`). Capture it there, and have `Logger_dispatch` read it instead of
passing `root_cap`.

The question is where "there" is.

### Rejected: a hidden field on the actor record

The obvious shape — the actor record already carries synthetic fields
(`$d_dispatch`, `$e_alive`) alongside the user's state — and the wrong one.

`lib/tir/lower_actor.ml` is explicit that this layout is load-bearing beyond
the compiler: field names are `$`-prefixed so that alphabetical sort
(`$d < $e < $f < letters`) "matches the alloc/reuse arg order and the C
runtime's **hardcoded word indices** (a[2]=dispatch, a[3]=alive)". A capability
field would also have to sort after `$f_state` to avoid displacing them, and a
per-capability count makes the field list variable.

Worse, the actor STATE RECORD is what `migrate_state`, hot reload and `@compat`
all reason about. A hidden field there is a layout change with three
opinionated consumers plus a hardcoded C offset.

### Preferred: `march_actor_meta`

`march_actor_meta` (`runtime/march_runtime.c:1844`) already holds per-actor
runtime metadata keyed by actor pointer — green thread, pid index, hash-table
chains. It is **runtime-internal**: `migrate_state`, `@compat` and hot reload
do not see it, because none of them reason about anything but the state record.

So: carry the spawn-site capabilities there, and have the dispatch read them
back. Nothing about the actor record, its sort order, or the C runtime's
hardcoded `a[2]`/`a[3]` offsets moves.

Sketch, in the order it would land:

1. `march_actor_meta` gains one pointer — a compiler-built record whose fields
   are the capabilities the actor's handlers need, in the same sorted order the
   elaboration already uses for parameters. One pointer rather than N keeps the
   struct and the spawn ABI fixed regardless of how many capabilities an actor
   needs.
2. The `spawn` lowering builds that record from the caps in scope at the spawn
   site (which the elaboration has already threaded there) and passes it to
   `march_spawn`.
3. The dispatch lowering reads it back and projects the field it needs, in
   place of today's `ambient_atom`.

Still real work — a runtime struct change plus a spawn ABI change plus dispatch
lowering — but it touches none of the three consumers that make the
record-field approach expensive.

## Scope note

Only `--test` builds are affected, since that is the only place the elaboration
runs. In a release build an actor handler behaves exactly as it always has.
