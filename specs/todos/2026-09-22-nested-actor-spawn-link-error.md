# `[P2]` `spawn(Inner.Actor)` from the parent module typechecks, then fails to link

Found 2026-09-22 while writing `bench/actor_ping.march`.

```march
mod Outer do
  needs IO.Console
  needs IO.Spawn
  mod Inner do
    actor Box do
      state { n : Int }
      init  { n: 0 }
      on Put(k : Int) do
        { n: k }
      end
    end
  end
  fn main(_c : Cap(IO.Console), _s : Cap(IO.Spawn)) do
    let _p = spawn(Inner.Box)
    println("spawned")
  end
end
```

`march --check` exits 0. `march --compile` fails at link time:

```
Undefined symbols for architecture arm64:
  "_Inner.Box_spawn", referenced from:
      _march_main in nested_spawn-d50796.o
```

The spawn function for a nested actor is not emitted under the qualified name the
call site uses. Spawning from inside `Inner` (`fn new_box() do spawn(Box) end`) works,
which is what `bench/actor_ping.march` does. Related: a nested actor's message
constructors are not visible from the parent either (`Inner.Put(1)` is "I don't know a
constructor called `Inner.Put`"), so a parent cannot send to it without a helper in
`Inner`; that may be intended scoping, the link error is not.

**Acceptance.** The program above compiles, runs and prints `spawned`; a native golden
test covers it.
