`[P3]` `Seq.each` only accepts an Atom-returning callback, and `Flow.run` cannot typecheck (2026-11-11)

`Seq.each` calls `folder(:ok, fn (ig, x) -> f(x))`, so the result of `f` is unified with the `:ok`
accumulator and `f` must return an Atom. A `println` callback or any other side-effecting function is
rejected. `Flow.run` passes `fn _ -> ()` to `Seq.each`, so every call of `Flow.run` is a type error: the
public function is unusable. Both doc strings now describe the restriction instead of fixing it.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  Seq.each(Seq.from_list(["a", "b"]), fn s -> println(s))
  Flow.run(Flow.range(1, 5))
end
end
```

Expected: prints `a` and `b`; `Flow.run` returns `:ok`.

Actual (interpreted / compiled): type errors at compile time, so the same on both backends: ``expected `Atom` but got `Result((), CapError)` `` for `Seq.each`, and ``expected `Stage(Atom -> (Atom -> Int -> ()) -> Atom)` but got `Stage(Atom -> (Atom -> Int -> Atom) -> Atom)` `` for `Flow.run`.

Source: `each` in `stdlib/seq.march`, `run` in `stdlib/flow.march`. One fix direction: have `each` discard `f(x)` and return the accumulator.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
