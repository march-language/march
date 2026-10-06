# `[P1]` A module that declares its own `Value` crashes, compiled, when it matches on a `Msgpack.Value`

Found 2026-10-05 while writing `test/native/colliding_type_drop.march` (the shallow-drop
fix for colliding short type names). Independent of that fix: it reproduces with and
without it.

```march
mod Main do
  needs IO.Console
  type Value = Leaf(String) | Node(List(Value))
  pfn tag(v : Msgpack.Value) : Int do
    match v do
      Msgpack.Bin(_) -> 1
      _ -> 0
    end
  end
  fn main(_c : Cap(IO.Console)) : () do
    println(int_to_string(tag(Msgpack.bin([1, 2, 3]))))
  end
end
```

- Interpreted: prints `1`.
- Compiled (`--compile`, any opt level): `fatal SIGSEGV si_code=2 addr=0xb`, rc 139.
- Without the local `type Value`, the compiled program prints `1`.

`Value` is now declared by four modules (Msgpack, Config, DataFrame, Main), so it is in
the collision set; every use site carries the bare short name (`Value.Bin`), and the
stdlib values are built by Msgpack's code. Likely a constructor or layout resolved
against the entry module's own `Value` (cf. the "ambiguous ctor, current-module
preference" history) rather than Msgpack's, at the case or at the call into
`Msgpack.bin`. Start from `--emit-llvm` of the repro: compare the tag the case switches
on with the tag `Msgpack.bin` allocates.

Why P1: a user picking a common name (`Value`, `State`, `Event`, `Error`, `Level`, `Mode`
all collide with stdlib types) gets a segfault, compiled only, far from the cause.
