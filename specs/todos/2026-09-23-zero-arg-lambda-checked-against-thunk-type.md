# `[P3]` A zero-parameter lambda checked against `() -> T` is typed `T`

Found while writing `stdlib/topology.march` (build step 3). Minimal repro:

```march
mod Z do
  type R = { name : String, go : () -> Int }
  fn mk(name : String) : R do
    { name: name, go: fn () -> 3 }      -- error: expected `() -> Int` but got `Int`
  end
  fn mk2(name : String) : R do
    let g = fn () -> 4                  -- same error, reported at this `let`
    { name: name, go: g }
  end
end
```

`go : Unit -> Int` fails the same way. Passing `fn () -> 3` as an ARGUMENT to a
parameter declared `() -> Int` works (`Signal.watch`, `Topology.hook`), so the
checking-mode path for a record field / let-bound zero-parameter lambda is the
suspect. Workaround in use: `Topology.Role.open` is `Int -> ...` called with a
dummy argument.

**Acceptance:** the repro typechecks and `(r.go)()` returns 3 on both backends; then
`Topology.Role.open` can drop its dummy argument.
